#!/usr/bin/env node
// scripts/aggregate-compat.mjs
//
// Aggregates "動作報告" (compatibility report) GitHub issues into
// help/compatibility.json and the help/compatibility.html /
// help/en/compatibility.html static pages. Run by .github/workflows/pages.yml
// on a schedule, on issue events, and on workflow_dispatch — see
// docs/compatibility-reports-design.md section 4.3 for the design.
//
// Node 20+, zero npm dependencies: only global fetch + node:fs + node:path.
//
// Env vars:
//   GITHUB_TOKEN       optional. Without it, GitHub's unauthenticated REST/
//                       Search API rate limits apply (fine for local runs;
//                       CLOSE_ISSUES is also a no-op without a token, since
//                       commenting/closing requires auth).
//   GITHUB_REPOSITORY  "owner/repo", default "Yorihito/symmetrical-carnival"
//                       (this is also the name GitHub Actions sets automatically).
//   OUT_DIR             output directory, default "help". May be relative
//                       (resolved against cwd) or absolute.
//   CLOSE_ISSUES        "1" to comment + close ingested open `compatibility`
//                       issues after aggregating. Default off.
//
// CLI:
//   node scripts/aggregate-compat.mjs             normal run (network + write)
//   node scripts/aggregate-compat.mjs --selftest   run inline fixtures through
//                                                   the parser/aggregator and
//                                                   check the resulting status
//                                                   values; no network, no
//                                                   files written. See
//                                                   runSelfTest() below.
//
// Failure policy: this script must never break the Pages deploy just because
// the GitHub API had a bad day. Network/API failures while *fetching* issues
// are logged and treated as "no new reports this run" — output is still
// written from help/data/verified.json alone. Only a genuine bug (e.g. a
// crash while building the aggregation or writing files) exits non-zero.
//
// NOTE ON DUPLICATED VALIDATION: the compat schema/enums below intentionally
// mirror server/worker.js's COMPAT_* constants and validateCompat(). They
// can't be imported directly (server/ has no package.json, and worker.js
// uses Workers-module `export` syntax that Node would try to load as
// CommonJS without one) — so this is a deliberate duplication, not an
// oversight. Keep the two in sync if the schema ever changes. This script
// re-validates every issue body from scratch rather than trusting the
// embedded JSON, because issues can be hand-edited on GitHub after the
// Worker created them, and some issues arrive via the browser "new issue"
// fallback path that never went through the Worker's validation at all.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const REPO = process.env.GITHUB_REPOSITORY || "Yorihito/symmetrical-carnival";
const OUT_DIR = process.env.OUT_DIR || "help";
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || "";
const CLOSE_ISSUES = process.env.CLOSE_ISSUES === "1";

const VERIFIED_PATH = path.join(REPO_ROOT, "help", "data", "verified.json");

const CLOSE_COMMENT =
  "集計に反映しました。ご報告ありがとうございます。\n\n" +
  "This report has been added to the compatibility list. Thank you!";

// --- Compat schema (mirrors server/worker.js — see note above) -------------

const COMPAT_SCHEMA_VERSION = 1;
const COMPAT_BRANDS = ["denon", "marantz", "yamaha"];
const COMPAT_OVERALL_VALUES = ["works", "partial", "fails"];
const COMPAT_FEATURE_KEYS = [
  "discovery", "power", "volume", "mute", "input", "sound_mode",
  "zone2", "zone3", "tuner", "remote", "reconnect",
];
const COMPAT_FEATURE_VALUES = ["ok", "ng"];
const COMPAT_MODEL_RE = /^[A-Za-z0-9][A-Za-z0-9 .\-\/+]{0,39}$/;
const COMPAT_STRING_FIELD_CAPS = { region: 8, firmware: 60, apiVersion: 60, app: 60, platform: 60 };
const COMPAT_STRING_FIELD_ALLOWED = /[^A-Za-z0-9 .()\/_+\-:,]/g;

const COMPAT_BRAND_NAMES = { denon: "Denon", marantz: "Marantz", yamaha: "Yamaha" };

const FEATURE_LABELS = {
  discovery: { ja: "自動検出", en: "Auto-discovery" },
  power: { ja: "電源", en: "Power" },
  volume: { ja: "音量", en: "Volume" },
  mute: { ja: "ミュート", en: "Mute" },
  input: { ja: "入力切替", en: "Input" },
  sound_mode: { ja: "サウンドモード", en: "Sound mode" },
  zone2: { ja: "ゾーン2", en: "Zone 2" },
  zone3: { ja: "ゾーン3", en: "Zone 3" },
  tuner: { ja: "チューナー", en: "Tuner" },
  remote: { ja: "リモコン画面", en: "Remote" },
  reconnect: { ja: "IP変更後の再接続", en: "Reconnect after IP change" },
};

// --- Validation (duplicated from server/worker.js; see note at top) --------

function sanitizeCompatString(value, maxLen) {
  if (typeof value !== "string") return undefined;
  const stripped = value.replace(COMPAT_STRING_FIELD_ALLOWED, "").trim();
  if (!stripped) return undefined;
  return stripped.slice(0, maxLen);
}

/// Strictly validates a parsed `avr-compat` block. Returns a clean object or
/// null. This never trusts the issue body beyond these allowlists, even
/// though the block *should* already be Worker-shaped — see the top-of-file
/// note on why we re-validate instead of trusting it.
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
    if (!COMPAT_FEATURE_VALUES.includes(value)) return null; // known key, bad value → reject whole block
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

/// Extracts and validates the `<!-- avr-compat ... -->` block from an issue
/// body. If more than one such block is present (e.g. a spoofed one pasted
/// into the free-text comment before the real one), the LAST match wins —
/// the Worker always appends its real block last, after any user comment,
/// so this can't be defeated by a comment injected earlier in the body.
function parseCompatBlock(body) {
  if (typeof body !== "string" || !body.includes("avr-compat")) return null;
  const re = /<!--\s*avr-compat\s*([\s\S]*?)-->/g;
  let match;
  let last = null;
  while ((match = re.exec(body)) !== null) {
    last = match[1];
  }
  if (last === null) return null;
  let parsed;
  try {
    parsed = JSON.parse(last.trim());
  } catch {
    return null;
  }
  return validateCompat(parsed);
}

// --- GitHub API --------------------------------------------------------------

function hasLabel(issue, name) {
  return Array.isArray(issue.labels) && issue.labels.some((l) => (typeof l === "string" ? l : l && l.name) === name);
}

async function githubFetch(url, token, init = {}) {
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "avr-controller-compat-aggregator",
    ...(init.body ? { "Content-Type": "application/json" } : {}),
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(init.headers || {}),
  };
  return fetch(url, { ...init, headers });
}

/// Fetches all issues (any state) carrying the `compatibility` label.
async function fetchIssuesByLabel(repo, token) {
  const issues = [];
  for (let page = 1; page <= 50; page++) {
    const url = `https://api.github.com/repos/${repo}/issues?state=all&labels=compatibility&per_page=100&page=${page}`;
    const res = await githubFetch(url, token);
    if (!res.ok) throw new Error(`issues-by-label fetch failed: HTTP ${res.status}`);
    const batch = await res.json();
    if (!Array.isArray(batch) || batch.length === 0) break;
    issues.push(...batch);
    if (batch.length < 100) break;
  }
  return issues;
}

/// Catches issues that carry no `compatibility` label — e.g. reports sent via
/// the browser "new issue" fallback (see design doc 3.3 / 4.3.1) — by full-text
/// searching for the machine-readable marker instead.
async function fetchIssuesBySearchMarker(repo, token) {
  const issues = [];
  const q = encodeURIComponent(`repo:${repo} "avr-compat" in:body is:issue`);
  for (let page = 1; page <= 10; page++) {
    const url = `https://api.github.com/search/issues?q=${q}&per_page=100&page=${page}`;
    const res = await githubFetch(url, token);
    if (!res.ok) throw new Error(`search fetch failed: HTTP ${res.status}`);
    const data = await res.json();
    const items = Array.isArray(data.items) ? data.items : [];
    if (items.length === 0) break;
    issues.push(...items);
    if (items.length < 100) break;
  }
  return issues;
}

async function fetchAllCandidateIssues(repo, token) {
  const [byLabel, bySearch] = await Promise.all([
    fetchIssuesByLabel(repo, token),
    fetchIssuesBySearchMarker(repo, token),
  ]);
  const byNumber = new Map();
  for (const issue of [...byLabel, ...bySearch]) {
    if (issue && typeof issue.number === "number") byNumber.set(issue.number, issue);
  }
  return [...byNumber.values()];
}

/// Filters candidate issues down to ones that parse as valid compat reports:
/// skips pull requests, skips issues labeled "invalid", parses+validates the
/// avr-compat block, and drops anything that doesn't parse.
function parseIngestedIssues(rawIssues) {
  const ingested = [];
  for (const issue of rawIssues) {
    if (!issue || issue.pull_request) continue; // PRs can carry labels/body too; not reports
    if (hasLabel(issue, "invalid")) continue; // manually marked as junk/spam
    const compat = parseCompatBlock(issue.body || "");
    if (!compat) continue; // unparseable/invalid → skip silently
    ingested.push({ issue, compat, createdAt: issue.created_at });
  }
  return ingested;
}

async function commentAndClose(repo, token, issueNumber) {
  const commentRes = await githubFetch(`https://api.github.com/repos/${repo}/issues/${issueNumber}/comments`, token, {
    method: "POST",
    body: JSON.stringify({ body: CLOSE_COMMENT }),
  });
  if (!commentRes.ok) throw new Error(`comment failed: HTTP ${commentRes.status}`);

  const closeRes = await githubFetch(`https://api.github.com/repos/${repo}/issues/${issueNumber}`, token, {
    method: "PATCH",
    body: JSON.stringify({ state: "closed", state_reason: "completed" }),
  });
  if (!closeRes.ok) throw new Error(`close failed: HTTP ${closeRes.status}`);
}

/// Comments + closes ingested issues that are still open and carry the
/// `compatibility` label. Never touches an issue without that label, even if
/// it was ingested via the search-marker path — those may be hand-filed
/// issues where closing on the reporter's behalf would be surprising.
async function closeIngestedIssues(ingested, repo, token) {
  for (const { issue } of ingested) {
    if (issue.state !== "open") continue;
    if (!hasLabel(issue, "compatibility")) continue;
    try {
      await commentAndClose(repo, token, issue.number);
      console.log(`[aggregate-compat] closed #${issue.number}`);
    } catch (err) {
      console.error(`[aggregate-compat] failed to close #${issue.number}: ${err.message}`);
    }
  }
}

// --- Aggregation ---------------------------------------------------------------

function normalizeModelKey(brand, model) {
  return `${brand}::${model.trim().replace(/\s+/g, " ").toLowerCase()}`;
}

function loadVerified() {
  try {
    const raw = fs.readFileSync(VERIFIED_PATH, "utf8");
    const list = JSON.parse(raw);
    if (!Array.isArray(list)) return [];
    return list.filter((v) => v && COMPAT_BRANDS.includes(v.brand) && typeof v.model === "string" && v.model.trim());
  } catch (err) {
    console.error(`[aggregate-compat] could not read ${VERIFIED_PATH}, continuing with none: ${err.message}`);
    return [];
  }
}

/*
 * status decision, applied in this order (deterministic):
 *   1. "verified" — the model is listed in help/data/verified.json. This
 *      always wins, regardless of what reports say: the developer confirmed
 *      it firsthand on real hardware.
 *   2. "failing"  — reports' `overall` field: fails > works.
 *   3. "partial"  — not failing, and at least one feature has ng >= ok
 *      (with ng > 0) — i.e. some specific feature is reported broken at
 *      least as often as it's reported working.
 *   4. "reported" — not failing/partial-by-feature, and works >= 1 and
 *      works > fails.
 *   5. "partial" (fallback) — reports exist but none of the above matched
 *      (e.g. only "partial"-overall reports with no single feature having a
 *      ng majority, or works === fails === 0). Falls back to "partial"
 *      rather than "reported" so weak/ambiguous signal never gets
 *      overstated as a clean confirmation.
 */
function computeStatus(bucket, isVerified) {
  if (isVerified) return "verified";
  const { works, fails } = bucket.overall;
  if (fails > works) return "failing";
  const featureNgMajority = Object.values(bucket.features).some((f) => f.ng > 0 && f.ng >= f.ok);
  if (featureNgMajority) return "partial";
  if (works >= 1 && works > fails) return "reported";
  return "partial";
}

/// Aggregates ingested reports (+ verified.json) into the sorted model list
/// that becomes help/compatibility.json's `models` array.
function buildModels(ingested, verified) {
  const buckets = new Map();

  function getBucket(brand, model) {
    const key = normalizeModelKey(brand, model);
    let b = buckets.get(key);
    if (!b) {
      b = {
        brand,
        model, // display casing; updated to the most recent report's casing below
        reports: 0,
        overall: { works: 0, partial: 0, fails: 0 },
        features: {},
        lastReportDate: null, // Date, internal sort key only
        lastReport: null, // "YYYY-MM-DD" for output
        lastApp: null,
      };
      buckets.set(key, b);
    }
    return b;
  }

  const sorted = [...ingested].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
  for (const { compat, createdAt } of sorted) {
    const bucket = getBucket(compat.brand, compat.model);
    bucket.reports += 1;
    bucket.overall[compat.overall] += 1;
    for (const [key, value] of Object.entries(compat.features)) {
      if (!bucket.features[key]) bucket.features[key] = { ok: 0, ng: 0 };
      bucket.features[key][value] += 1;
    }
    const d = new Date(createdAt);
    if (!bucket.lastReportDate || d >= bucket.lastReportDate) {
      bucket.lastReportDate = d;
      bucket.model = compat.model; // most recent original casing wins for display
      bucket.lastReport = typeof createdAt === "string" ? createdAt.slice(0, 10) : d.toISOString().slice(0, 10);
      bucket.lastApp = compat.app ? compat.app.split(" ")[0] : null;
    }
  }

  const verifiedKeys = new Set();
  for (const v of verified) {
    const key = normalizeModelKey(v.brand, v.model);
    verifiedKeys.add(key);
    const bucket = getBucket(v.brand, v.model);
    if (bucket.reports === 0) bucket.model = v.model; // no reports to derive display casing from
  }

  const models = [...buckets.entries()].map(([key, b]) => ({
    brand: b.brand,
    model: b.model,
    status: computeStatus(b, verifiedKeys.has(key)),
    reports: b.reports,
    overall: b.overall,
    features: b.features,
    lastReport: b.lastReport,
    lastApp: b.lastApp,
  }));

  models.sort((a, b) => {
    if (a.brand !== b.brand) return a.brand.localeCompare(b.brand);
    return a.model.localeCompare(b.model, undefined, { sensitivity: "base" });
  });

  return models;
}

// --- Output: JSON --------------------------------------------------------------

function writeJSON(outDirAbs, generatedAt, models) {
  const out = { generatedAt, models };
  fs.writeFileSync(path.join(outDirAbs, "compatibility.json"), JSON.stringify(out, null, 2) + "\n", "utf8");
}

// --- Output: HTML ----------------------------------------------------------

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

const PAGE_TEXT = {
  ja: {
    lang: "ja",
    styleHref: "style.css",
    homeHref: "index.html",
    detailsHref: "details.html",
    privacyHref: "privacy.html",
    selfHref: "compatibility.html",
    siteTitle: "AVR Controller ヘルプ",
    pageTitle: "対応機種",
    docTitle: "対応機種 - AVR Controller",
    lede: "ユーザーからの動作報告をもとに、機種ごとの動作状況をまとめています。",
    generatedNote: "自動で集計しています。動作を保証するものではありません。",
    affiliation:
      "本アプリは個人が開発した非公式アプリで、各メーカーとは提携していません。製品名は対応機種を示す目的でのみ記載しており、各社の商標は各社に帰属します。",
    howToReportHeading: "動作報告のしかた",
    howToReport:
      "アプリ内の「設定」→「この機種での動作を報告する」から、いつでも動作報告を送ることができます。報告は GitHub 上に公開されます。",
    noModels: "まだ集計できる報告がありません。",
    colModel: "機種",
    colStatus: "状態",
    colReports: "報告数",
    colFeatures: "動かない報告がある機能",
    colLastReport: "最新の報告日",
    none: "—",
    langSwitchSelf: "日本語",
    langSwitchOther: "English",
    navHome: "かんたんガイド",
    navDetails: "詳細ガイド",
    navCompat: "対応機種",
    navPrivacy: "プライバシーポリシー",
  },
  en: {
    lang: "en",
    styleHref: "../style.css",
    homeHref: "index.html",
    detailsHref: "details.html",
    privacyHref: "privacy.html",
    selfHref: "compatibility.html",
    siteTitle: "AVR Controller Help",
    pageTitle: "Supported Models",
    docTitle: "Supported Models - AVR Controller",
    lede: "A model-by-model summary built from reports sent in by users.",
    generatedNote: "Generated automatically. This is not a guarantee of compatibility.",
    affiliation:
      "This is an unofficial app made by an independent developer and is not affiliated with any manufacturer. Product names are used only to indicate compatibility; trademarks belong to their respective owners.",
    howToReportHeading: "How to send a report",
    howToReport:
      "You can send a compatibility report any time from Settings → \"Report how it works with your model\" in the app. Reports are published publicly on GitHub.",
    noModels: "No reports have been aggregated yet.",
    colModel: "Model",
    colStatus: "Status",
    colReports: "Reports",
    colFeatures: "Features with issues reported",
    colLastReport: "Last report",
    none: "—",
    langSwitchSelf: "日本語",
    langSwitchOther: "English",
    navHome: "Quick Guide",
    navDetails: "Details",
    navCompat: "Supported Models",
    navPrivacy: "Privacy Policy",
  },
};

function statusLabel(status, reports, lang) {
  if (lang === "ja") {
    switch (status) {
      case "verified": return "開発者確認済み";
      case "reported": return `ユーザー報告で動作確認済み（${reports} 件）`;
      case "partial": return "一部の機能が動かない報告あり";
      case "failing": return "動かないという報告あり";
      default: return "—";
    }
  }
  switch (status) {
    case "verified": return "Developer-verified";
    case "reported": return `Confirmed working by user reports (${reports})`;
    case "partial": return "Some features reported not working";
    case "failing": return "Reported as not working";
    default: return "—";
  }
}

function featuresWithIssues(features, lang) {
  const entries = Object.entries(features).filter(([, counts]) => counts.ng > 0);
  if (entries.length === 0) return null;
  const sep = lang === "ja" ? "、" : ", ";
  return entries
    .map(([key, counts]) => {
      const label = (FEATURE_LABELS[key] && FEATURE_LABELS[key][lang]) || key;
      return `${label} (${counts.ng})`;
    })
    .join(sep);
}

function renderBrandTable(brand, models, lang) {
  const t = PAGE_TEXT[lang];
  const brandName = COMPAT_BRAND_NAMES[brand] || brand;
  let html = `    <h3>${escapeHtml(brandName)}</h3>\n`;
  html += `    <table class="compat">\n      <thead><tr><th>${t.colModel}</th><th>${t.colStatus}</th><th>${t.colReports}</th><th>${t.colFeatures}</th><th>${t.colLastReport}</th></tr></thead>\n      <tbody>\n`;
  for (const m of models) {
    const featureText = featuresWithIssues(m.features, lang);
    html += "        <tr>";
    html += `<td>${escapeHtml(m.model)}</td>`;
    html += `<td>${escapeHtml(statusLabel(m.status, m.reports, lang))}</td>`;
    html += `<td>${escapeHtml(String(m.reports))}</td>`;
    html += `<td>${featureText ? escapeHtml(featureText) : t.none}</td>`;
    html += `<td>${m.lastReport ? escapeHtml(m.lastReport) : t.none}</td>`;
    html += "</tr>\n";
  }
  html += "      </tbody>\n    </table>\n";
  return html;
}

function renderPage(lang, models, generatedAt) {
  const t = PAGE_TEXT[lang];
  const byBrand = new Map();
  for (const m of models) {
    if (!byBrand.has(m.brand)) byBrand.set(m.brand, []);
    byBrand.get(m.brand).push(m);
  }
  // Fixed brand display order, matching COMPAT_BRANDS; only render brands
  // that actually have at least one model.
  const brandSections = COMPAT_BRANDS.filter((b) => byBrand.has(b))
    .map((b) => renderBrandTable(b, byBrand.get(b), lang))
    .join("\n");

  const body =
    brandSections.length > 0
      ? brandSections
      : `    <p>${escapeHtml(t.noModels)}</p>\n`;

  // Cross-directory links (help/compatibility.html vs help/en/compatibility.html),
  // matching the pattern used by index.html / details.html / privacy.html:
  // same-language nav links stay within the current directory; the lang-switch
  // is the only thing that crosses the help/ ↔ help/en/ boundary.
  const jaSwitchHref = lang === "ja" ? "compatibility.html" : "../compatibility.html";
  const enSwitchHref = lang === "ja" ? "en/compatibility.html" : "compatibility.html";

  return `<!DOCTYPE html>
<html lang="${t.lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${escapeHtml(t.docTitle)}</title>
<link rel="stylesheet" href="${t.styleHref}">
<style>
table.compat { width: 100%; border-collapse: collapse; margin: 12px 0 28px; font-size: 14px; }
table.compat th, table.compat td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--border-color); }
table.compat th { color: var(--secondary-text); font-weight: 600; }
.generated-note { font-size: 13px; color: var(--secondary-text); margin-top: 8px; }
</style>
</head>
<body>
<div class="wrap">
    <header class="site">
        <div class="title-row">
            <h1>${escapeHtml(t.siteTitle)}</h1>
            <div class="lang-switch">
                <a href="${jaSwitchHref}"${lang === "ja" ? ' class="current"' : ""}>${t.langSwitchSelf}</a>
                <a href="${enSwitchHref}"${lang === "en" ? ' class="current"' : ""}>${t.langSwitchOther}</a>
            </div>
        </div>
        <nav class="tabs">
            <a href="${t.homeHref}">${t.navHome}</a>
            <a href="${t.detailsHref}">${t.navDetails}</a>
            <a href="${t.selfHref}" class="current">${t.navCompat}</a>
            <a href="${t.privacyHref}">${t.navPrivacy}</a>
        </nav>
    </header>

    <h1 class="page-title">${escapeHtml(t.pageTitle)}</h1>
    <p class="lede">${escapeHtml(t.lede)}</p>
    <p>${escapeHtml(t.generatedNote)}</p>
    <p>${escapeHtml(t.affiliation)}</p>

${body}
    <h2>${escapeHtml(t.howToReportHeading)}</h2>
    <p>${escapeHtml(t.howToReport)}</p>

    <p class="generated-note">${lang === "ja" ? "最終更新" : "Last updated"}: ${escapeHtml(generatedAt)}</p>

    <footer class="site">
        <p>© 2026 Yorihito Tada</p>
    </footer>
</div>
</body>
</html>
`;
}

function writeHTML(outDirAbs, models, generatedAt) {
  fs.mkdirSync(path.join(outDirAbs, "en"), { recursive: true });
  fs.writeFileSync(path.join(outDirAbs, "compatibility.html"), renderPage("ja", models, generatedAt), "utf8");
  fs.writeFileSync(path.join(outDirAbs, "en", "compatibility.html"), renderPage("en", models, generatedAt), "utf8");
}

function writeOutputs(models, generatedAt) {
  const outDirAbs = path.resolve(process.cwd(), OUT_DIR);
  fs.mkdirSync(outDirAbs, { recursive: true });
  writeJSON(outDirAbs, generatedAt, models);
  writeHTML(outDirAbs, models, generatedAt);
  return outDirAbs;
}

// --- Self-test (no network, no files) ---------------------------------------

/// Builds a handful of fake issues (as the GitHub API would shape them),
/// runs them through the real parsing + aggregation functions, and checks
/// the resulting status values. Exercises: normal parsing, the "verified"
/// override, the "partial" (feature ng-majority) rule, the "reported" rule,
/// the "failing" rule, and the "invalid"-label exclusion. Nothing is written
/// to disk and no network calls are made.
function runSelfTest() {
  const now = Date.now();
  const iso = (daysAgo) => new Date(now - daysAgo * 86400000).toISOString();

  const fixtures = [
    { brand: "yamaha", model: "RX-V581", overall: "works", features: { power: "ok", volume: "ok", remote: "ok" }, createdAt: iso(10) },
    { brand: "yamaha", model: "RX-V581", overall: "partial", features: { power: "ok", remote: "ng" }, createdAt: iso(2) },
    { brand: "denon", model: "AVR-X3800H", overall: "fails", features: { power: "ng" }, createdAt: iso(5) },
    { brand: "marantz", model: "SR6015", overall: "works", features: { power: "ok", input: "ok" }, createdAt: iso(1) },
    { brand: "marantz", model: "SR8015", overall: "fails", features: { power: "ng" }, createdAt: iso(1) },
    { brand: "yamaha", model: "RX-V999", overall: "fails", features: {}, createdAt: iso(1), invalid: true },
  ];

  let issueNumber = 9000;
  const fixtureIssues = fixtures.map((f) => {
    const compat = { schema: 1, brand: f.brand, model: f.model, overall: f.overall, features: f.features };
    const body = `### 環境 (Environment)\n\n(fixture)\n\n<!-- avr-compat\n${JSON.stringify(compat)}\n-->`;
    const labels = [{ name: "compatibility" }];
    if (f.invalid) labels.push({ name: "invalid" });
    return { number: issueNumber++, state: "open", created_at: f.createdAt, body, labels };
  });

  let pass = true;

  const ingested = parseIngestedIssues(fixtureIssues);
  const expectedIngestedCount = fixtures.filter((f) => !f.invalid).length;
  if (ingested.length !== expectedIngestedCount) {
    pass = false;
    console.error(`[selftest] FAIL: expected ${expectedIngestedCount} ingested reports (invalid-labeled one excluded), got ${ingested.length}`);
  } else {
    console.log(`[selftest] ingested ${ingested.length}/${fixtures.length} fixtures (1 correctly excluded via "invalid" label) — OK`);
  }

  const fixtureVerified = [{ brand: "denon", model: "AVR-X3800H", note: "test", since: "test" }];
  const models = buildModels(ingested, fixtureVerified);
  const byKey = new Map(models.map((m) => [normalizeModelKey(m.brand, m.model), m]));

  const expectations = [
    [normalizeModelKey("yamaha", "RX-V581"), "partial"], // remote: ng(1) >= ok(1)
    [normalizeModelKey("denon", "AVR-X3800H"), "verified"], // in verified.json fixture, overrides fails>works
    [normalizeModelKey("marantz", "SR6015"), "reported"], // works=1, fails=0
    [normalizeModelKey("marantz", "SR8015"), "failing"], // fails=1, works=0
    [normalizeModelKey("yamaha", "RX-V999"), undefined], // excluded via "invalid" label
  ];
  for (const [key, expected] of expectations) {
    const model = byKey.get(key);
    const actual = model && model.status;
    const ok = actual === expected;
    pass = pass && ok;
    console.log(`[selftest] ${key}: expected=${expected} actual=${actual} — ${ok ? "OK" : "FAIL"}`);
  }

  console.log(pass ? "[selftest] ALL PASS" : "[selftest] FAILED");
  return pass;
}

// --- Entry point ---------------------------------------------------------------

async function main() {
  if (process.argv.includes("--selftest")) {
    const ok = runSelfTest();
    process.exitCode = ok ? 0 : 1;
    return;
  }

  const generatedAt = new Date().toISOString();
  const verified = loadVerified();

  let ingested = [];
  try {
    const raw = await fetchAllCandidateIssues(REPO, GITHUB_TOKEN);
    ingested = parseIngestedIssues(raw);
  } catch (err) {
    console.error(`[aggregate-compat] GitHub fetch failed, continuing with verified.json only: ${err.message}`);
    ingested = [];
  }

  const models = buildModels(ingested, verified);
  const outDirAbs = writeOutputs(models, generatedAt);
  console.log(`[aggregate-compat] wrote ${models.length} model(s) to ${outDirAbs} (${ingested.length} report(s) ingested from ${REPO})`);

  if (CLOSE_ISSUES && GITHUB_TOKEN) {
    try {
      await closeIngestedIssues(ingested, REPO, GITHUB_TOKEN);
    } catch (err) {
      console.error(`[aggregate-compat] closing issues failed (non-fatal): ${err.message}`);
    }
  } else if (CLOSE_ISSUES && !GITHUB_TOKEN) {
    console.log("[aggregate-compat] CLOSE_ISSUES=1 but no GITHUB_TOKEN — skipping comment/close step.");
  }
}

main().catch((err) => {
  console.error(`[aggregate-compat] fatal: ${err && err.stack ? err.stack : err}`);
  process.exitCode = 1;
});
