// Cloudflare Worker — backend for "AVR Controller" 's problem-report feature.
//
// Routes:
//   POST /report  → create a public GitHub issue from a diagnostic report
//                   (server-side token; the app never holds one). Returns URL.
//
// Abuse protection: per-IP + global hourly rate limits (KV) + real-byte body
// size cap + a small fixed set of labels chosen by the client (bug/enhancement/
// question — all exist by default on a new GitHub repo, no pre-creation
// needed). No App Attest — this is a personal-scale app, not worth the
// complexity yet (see docs/playbook-alignment.md).
//
// --- Setup -------------------------------------------------------------------
//   Secret  : GITHUB_TOKEN  (fine-grained PAT, Issues:write, REPO only)
//   Secret  : RATE_SALT     (REQUIRED; POSTs fail closed without it)
//   Binding : RATE_LIMIT    (KV namespace; used only for rate limiting)
//   Optional vars (wrangler.toml [vars]): REPO
// -----------------------------------------------------------------------------

const DEFAULTS = {
  REPO: "Yorihito/symmetrical-carnival",
};

// category (from the app) → GitHub label. Fixed allowlist — never trust an
// arbitrary client-supplied label string.
const CATEGORY_LABELS = {
  bug: "bug",
  feature: "enhancement",
  other: "question",
};

// Size caps. GitHub's issue-body limit is ~65,536 chars; leave margin.
const MAX_TITLE_CHARS = 200;
const MAX_BODY_CHARS = 60000;
const MAX_REQUEST_BYTES = 128 * 1024; // reject obviously oversized payloads early

// Rate limits, per client IP, per hour.
const RATE_WINDOW_SEC = 3600;
const REPORT_RATE_MAX = 5;

// Coarse GLOBAL cap per hour (all IPs combined), bounding total damage even
// when senders are distributed across IPs. KV counters are not atomic, so
// this — like the per-IP limit — is best-effort, not a hard guarantee.
const REPORT_GLOBAL_MAX = 30;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/report") {
      return handleReportRequest(request, env);
    }
    return json({ error: "not_found" }, 404);
  },
};

async function handleReportRequest(request, env) {
  // Rate limiting is part of the abuse posture — fail CLOSED when the pieces
  // it needs are missing, instead of silently running unlimited.
  if (!env.RATE_LIMIT || !env.RATE_SALT || !env.GITHUB_TOKEN) {
    return json({ error: "server_misconfigured" }, 500);
  }

  const declaredLen = Number(request.headers.get("content-length") || "0");
  if (declaredLen > MAX_REQUEST_BYTES) {
    return json({ error: "payload_too_large" }, 413);
  }

  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const rl = await checkRateLimit(env, ip);
  if (!rl.ok) {
    return json({ error: "rate_limited", retryAfter: rl.retryAfter }, 429, {
      "retry-after": String(rl.retryAfter),
    });
  }

  // Enforce the size cap on the bytes actually received, not just the
  // declared Content-Length — chunked bodies carry none.
  const text = await readBodyCapped(request, MAX_REQUEST_BYTES);
  if (text === null) {
    return json({ error: "payload_too_large" }, 413);
  }
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  return handleReport(payload, env);
}

async function handleReport(payload, env) {
  const title = sanitizeTitle(payload && payload.title);
  const body = sanitizeBody(payload && payload.body);
  if (!title || !body) {
    return json({ error: "title_and_body_required" }, 400);
  }

  const label = CATEGORY_LABELS[payload && payload.category] || CATEGORY_LABELS.other;
  const repo = env.REPO || DEFAULTS.REPO;

  const ghResp = await fetch(`https://api.github.com/repos/${repo}/issues`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "avr-controller-report-proxy",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ title, body, labels: [label] }),
  });

  if (!ghResp.ok) {
    console.log(`github_error ${ghResp.status} ${await safeText(ghResp)}`);
    return json({ error: "upstream_failed" }, 502);
  }

  const issue = await ghResp.json();
  return json({ url: issue.html_url, number: issue.number }, 201);
}

// --- Helpers -----------------------------------------------------------------

/// Reads the request body up to `maxBytes`; returns null once the cap is
/// exceeded (aborting the read) so oversized/chunked uploads can't make us
/// buffer or parse them.
async function readBodyCapped(request, maxBytes) {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      try { await reader.cancel(); } catch {}
      return null;
    }
    chunks.push(value);
  }
  const buf = new Uint8Array(total);
  let offset = 0;
  for (const c of chunks) { buf.set(c, offset); offset += c.byteLength; }
  return new TextDecoder().decode(buf);
}

function sanitizeTitle(value) {
  if (typeof value !== "string") return "";
  const t = value.replace(/[\r\n]+/g, " ").trim();
  return t.slice(0, MAX_TITLE_CHARS);
}

function sanitizeBody(value) {
  if (typeof value !== "string") return "";
  const b = value.trim();
  if (!b) return "";
  if (b.length <= MAX_BODY_CHARS) return b;
  return b.slice(0, MAX_BODY_CHARS) + "\n\n…(truncated)";
}

async function checkRateLimit(env, ip) {
  // KV is eventually consistent and read-modify-write here is NOT atomic, so
  // these limits are best-effort abuse mitigation, not a hard guarantee. The
  // per-IP limit deters casual abuse; the global cap bounds total damage even
  // when senders are distributed across IPs.
  const globalKey = "rl:global:report";
  const globalCurrent = Number((await env.RATE_LIMIT.get(globalKey)) || "0");
  if (globalCurrent >= REPORT_GLOBAL_MAX) {
    return { ok: false, retryAfter: RATE_WINDOW_SEC };
  }

  // Don't store the raw IP. Key on a salted hash with a short TTL, used only
  // for rate limiting — so "we don't store your IP" (per the privacy policy)
  // stays accurate. RATE_SALT is required (fail closed above) so the hash
  // can't be brute-forced over the IPv4 space.
  const key = await rateLimitKey(env, ip);
  const current = Number((await env.RATE_LIMIT.get(key)) || "0");
  if (current >= REPORT_RATE_MAX) {
    return { ok: false, retryAfter: RATE_WINDOW_SEC };
  }
  await env.RATE_LIMIT.put(key, String(current + 1), { expirationTtl: RATE_WINDOW_SEC });
  await env.RATE_LIMIT.put(globalKey, String(globalCurrent + 1), { expirationTtl: RATE_WINDOW_SEC });
  return { ok: true };
}

/// Salted SHA-256 of the client IP → rate-limit key. The raw IP is never stored.
async function rateLimitKey(env, ip) {
  const data = new TextEncoder().encode(`${env.RATE_SALT}:report:${ip}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `rl:report:${hex.slice(0, 24)}`;
}

function json(obj, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...extraHeaders },
  });
}

async function safeText(resp) {
  try {
    return (await resp.text()).slice(0, 500);
  } catch {
    return "";
  }
}
