// Cloudflare Worker — backend for "AVR Controller" 's problem-report feature.
//
// Routes:
//   POST /report  → create a public GitHub issue from a diagnostic report
//                   (server-side token; the app never holds one). Returns URL.
//
//                   Two shapes of request:
//                   - category bug/feature/other: client sends title+body,
//                     Worker just maps category → label.
//                   - category "compatibility": client sends a structured
//                     `compat` object (device/report data) instead of a
//                     title; the Worker validates it strictly against fixed
//                     allowlists (never trusts client strings) and builds
//                     the title/body itself, embedding a machine-readable
//                     `<!-- avr-compat {...} -->` JSON block at the end for
//                     scripts/aggregate-compat.mjs to parse later. See
//                     docs/compatibility-reports-design.md section 4.
//
// Abuse protection: per-IP + global hourly rate limits (KV) + real-byte body
// size cap + a small fixed set of labels chosen by the client (bug/enhancement/
// question/compatibility — bug/enhancement/question exist by default on a new
// GitHub repo; `compatibility` and the `brand:*` labels must be created once,
// see server/README.md). No App Attest — this is a personal-scale app, not
// worth the complexity yet (see docs/playbook-alignment.md).
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
  compatibility: "compatibility",
};

// Added when the app says the sender has tipped (tip jar) and chose to send as a
// supporter. The endpoint is public, so this is a triage hint, not proof of
// purchase — never gate anything important on it. Never added to compatibility
// reports (those aren't a priority signal, see design doc 3.2).
const SUPPORTER_LABEL = "supporter";

// Size caps. GitHub's issue-body limit is ~65,536 chars; leave margin.
const MAX_TITLE_CHARS = 200;
const MAX_BODY_CHARS = 60000;
const MAX_REQUEST_BYTES = 128 * 1024; // reject obviously oversized payloads early

// --- Compatibility report ("動作報告") validation & rendering ---------------
// All allowlists below are fixed server-side; the client only ever chooses
// from these values indirectly (via app UI) — nothing here trusts a raw
// client string beyond stripping/length-capping it.

const COMPAT_SCHEMA_VERSION = 1;
const COMPAT_BRANDS = ["denon", "marantz", "yamaha"];
const COMPAT_OVERALL_VALUES = ["works", "partial", "fails"];
const COMPAT_FEATURE_KEYS = [
  "discovery", "power", "volume", "mute", "input", "sound_mode",
  "zone2", "zone3", "tuner", "remote", "reconnect",
];
const COMPAT_FEATURE_VALUES = ["ok", "ng"];

// Model: must start with an alphanumeric, then up to 39 more of
// alphanumeric/space/./-/// or +. Trimmed before testing. This also
// guarantees "-->" (the HTML-comment terminator used below) can never
// appear in a model string, since ">" isn't in the allowed charset.
const COMPAT_MODEL_RE = /^[A-Za-z0-9][A-Za-z0-9 .\-\/+]{0,39}$/;

// Optional free-text fields: length cap per field, and characters outside
// this allowlist are stripped (not rejected). ">" is intentionally excluded
// from the allowed charset for the same "-->" reason as the model regex.
const COMPAT_STRING_FIELD_CAPS = {
  region: 8,
  firmware: 60,
  apiVersion: 60,
  app: 60,
  platform: 60,
};
const COMPAT_STRING_FIELD_ALLOWED = /[^A-Za-z0-9 .()\/_+\-:,]/g;

// The optional free-text user comment (payload.body for this category) gets
// its own, much smaller cap than a normal bug/feature report body.
const COMPAT_COMMENT_MAX_CHARS = 4000;

const COMPAT_BRAND_NAMES = { denon: "Denon", marantz: "Marantz", yamaha: "Yamaha" };
const COMPAT_OVERALL_LABELS_JA = { works: "問題なく使える", partial: "一部使えない", fails: "使えない" };
const COMPAT_FEATURE_LABELS_JA = {
  discovery: "自動検出",
  power: "電源",
  volume: "音量",
  mute: "ミュート",
  input: "入力切替",
  sound_mode: "サウンドモード",
  zone2: "ゾーン 2",
  zone3: "ゾーン 3",
  tuner: "チューナー",
  remote: "リモコン画面",
  reconnect: "IP が変わった後の再接続",
};

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
  const category = payload && payload.category;
  let title, body;
  const labels = [];

  if (category === "compatibility") {
    const compat = validateCompat(payload && payload.compat);
    if (!compat) {
      return json({ error: "invalid_compat" }, 400);
    }
    const comment = sanitizeBody(payload && payload.body, COMPAT_COMMENT_MAX_CHARS);
    ({ title, body } = buildCompatIssue(compat, comment));
    // Fixed labels only — never derived from anything the client sent
    // besides the (already-validated) brand.
    labels.push(CATEGORY_LABELS.compatibility, `brand:${compat.brand}`);
    // Intentionally no SUPPORTER_LABEL here even if payload.supporter===true.
  } else {
    title = sanitizeTitle(payload && payload.title);
    body = sanitizeBody(payload && payload.body);
    if (!title || !body) {
      return json({ error: "title_and_body_required" }, 400);
    }
    labels.push(CATEGORY_LABELS[category] || CATEGORY_LABELS.other);
    if (payload && payload.supporter === true) labels.push(SUPPORTER_LABEL);
  }

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
    body: JSON.stringify({ title, body, labels }),
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

function sanitizeBody(value, maxChars = MAX_BODY_CHARS) {
  if (typeof value !== "string") return "";
  const b = value.trim();
  if (!b) return "";
  if (b.length <= maxChars) return b;
  return b.slice(0, maxChars) + "\n\n…(truncated)";
}

/// Strips a free-text compat field down to the allowed charset, trims, and
/// caps its length. Returns undefined for anything that isn't a non-empty
/// string afterward, so callers can omit the key entirely (optional fields).
function sanitizeCompatString(value, maxLen) {
  if (typeof value !== "string") return undefined;
  const stripped = value.replace(COMPAT_STRING_FIELD_ALLOWED, "").trim();
  if (!stripped) return undefined;
  return stripped.slice(0, maxLen);
}

/// Validates payload.compat against fixed allowlists (see the constants
/// above). Returns a clean, ordered compat object on success or null on any
/// validation failure — the caller turns null into a 400 invalid_compat.
/// Order of keys matters: it's preserved into the embedded JSON block, and
/// matches docs/compatibility-reports-design.md section 4.2.
function validateCompat(compat) {
  if (!compat || typeof compat !== "object" || Array.isArray(compat)) return null;
  if (compat.schema !== COMPAT_SCHEMA_VERSION) return null;
  if (!COMPAT_BRANDS.includes(compat.brand)) return null;

  const model = typeof compat.model === "string" ? compat.model.trim() : "";
  if (!COMPAT_MODEL_RE.test(model)) return null;

  if (!COMPAT_OVERALL_VALUES.includes(compat.overall)) return null;

  if (compat.features === null || typeof compat.features !== "object" || Array.isArray(compat.features)) {
    return null;
  }
  const features = {};
  for (const [key, value] of Object.entries(compat.features)) {
    if (!COMPAT_FEATURE_KEYS.includes(key)) continue; // unknown key → drop silently
    if (!COMPAT_FEATURE_VALUES.includes(value)) return null; // known key, bad value → reject whole request
    features[key] = value;
  }

  const result = { schema: COMPAT_SCHEMA_VERSION, brand: compat.brand, model };
  for (const field of Object.keys(COMPAT_STRING_FIELD_CAPS)) {
    const v = sanitizeCompatString(compat[field], COMPAT_STRING_FIELD_CAPS[field]);
    if (v !== undefined) result[field] = v;
  }
  result.overall = compat.overall;
  result.features = features;
  return result;
}

/// JSON-stringifies a validated compat object for embedding inside the
/// `<!-- avr-compat ... -->` HTML comment. Field values are already
/// restricted to charsets that exclude ">" (see COMPAT_MODEL_RE /
/// COMPAT_STRING_FIELD_ALLOWED), so "-->" cannot appear here today — this is
/// a defense-in-depth guard in case that ever changes, so a crafted value
/// could never prematurely close the comment and inject content into the
/// rendered issue body.
function embedCompatJSON(compat) {
  const s = JSON.stringify(compat);
  return s.replace(/-{2,}/g, (run) => "‐".repeat(run.length));
}

/// Builds the title and body for a compatibility-report issue. The Worker
/// owns this entirely — payload.title from the client is never used for
/// this category (see design doc 4.1).
function buildCompatIssue(compat, comment) {
  const brandName = COMPAT_BRAND_NAMES[compat.brand];
  const overallLabel = COMPAT_OVERALL_LABELS_JA[compat.overall];
  const title = sanitizeTitle(`[動作報告] ${brandName} ${compat.model} — ${overallLabel}`);

  const envRows = [
    ["機種 (Model)", `${brandName} ${compat.model}`],
    ["地域 (Region)", compat.region],
    ["ファームウェア (Firmware)", compat.firmware],
    ["API バージョン (API version)", compat.apiVersion],
    ["アプリ (App)", compat.app],
    ["プラットフォーム (Platform)", compat.platform],
  ].filter(([, value]) => !!value);

  let body = "### 環境 (Environment)\n\n| | |\n|---|---|\n";
  for (const [label, value] of envRows) {
    body += `| ${label} | ${value} |\n`;
  }

  const featureEntries = Object.entries(compat.features);
  if (featureEntries.length > 0) {
    body += "\n### 機能ごとの結果 (Feature results)\n\n| 機能 (Feature) | 結果 (Result) |\n|---|---|\n";
    for (const [key, value] of featureEntries) {
      const label = COMPAT_FEATURE_LABELS_JA[key] || key;
      body += `| ${label} | ${value === "ok" ? "✅ 動いた" : "❌ 動かない"} |\n`;
    }
  }

  if (comment) {
    body += `\n### コメント (Comment)\n\n${comment}\n`;
  }

  body += `\n<!-- avr-compat\n${embedCompatJSON(compat)}\n-->`;

  return { title, body };
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
