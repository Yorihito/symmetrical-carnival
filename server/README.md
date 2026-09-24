# Backend (Cloudflare Worker)

Backend for AVR Controller's "ご意見・ご要望を送る" (Send Feedback) feature: turns a bug report or
feature request into a public GitHub issue.

The GitHub write token lives **only** as a Worker secret — it is never shipped
in the app. The app calls this proxy; the proxy calls GitHub. If the proxy is
unreachable or not yet deployed, the app falls back to opening a prefilled
"new issue" page in the browser (see `ProblemReporter.prefilledIssueURL`), so
the feature works even before this backend exists.

## API

### `POST /report`

```json
{ "title": "string (≤200 chars)", "body": "string (≤60000 chars)", "category": "bug | feature | other", "supporter": true }
```

`category` maps to a GitHub label server-side (`bug`→`bug`, `feature`→`enhancement`,
anything else→`question`) — all three exist by default on a new GitHub repo,
so no label needs to be created ahead of time.

`supporter` (optional boolean) is sent by the app when the user has tipped via the
in-app tip jar and chose to send as a supporter; `true` adds a `supporter` label.
The endpoint is public, so treat it as a triage hint, not proof of purchase.

#### `category: "compatibility"` ("動作報告" / compatibility report)

For this category, the request shape is different: instead of `title`, send a
structured `compat` object; `body` becomes an *optional* free-text comment
(≤4000 chars, may be omitted/empty). `title` is ignored — the Worker builds
the title and the whole issue body itself, so old/new app versions can't
disagree on formatting. See `docs/compatibility-reports-design.md` (sections
3.3 and 4) for the app-side rationale.

```json
{
  "category": "compatibility",
  "body": "optional free-text comment, ≤4000 chars",
  "compat": {
    "schema": 1,
    "brand": "denon | marantz | yamaha",
    "model": "string, ≤40 chars, /^[A-Za-z0-9][A-Za-z0-9 .\\-\\/+]{0,39}$/",
    "region": "optional string, ≤8 chars",
    "firmware": "optional string, ≤60 chars",
    "apiVersion": "optional string, ≤60 chars",
    "app": "optional string, ≤60 chars",
    "platform": "optional string, ≤60 chars",
    "overall": "works | partial | fails",
    "features": {
      "<discovery|power|volume|mute|input|sound_mode|zone2|zone3|tuner|remote|reconnect>": "ok | ng"
    }
  }
}
```

Validation is strict — the Worker never trusts a client-supplied string as-is:
- `compat.schema` must be exactly `1`.
- `brand` must be one of the three listed values; this also adds a
  `brand:<brand>` label (e.g. `brand:denon`).
- `model` must match the regex above after trimming (starts with a letter or
  digit; letters, digits, space, `.`, `-`, `/`, `+` only — notably no `>`, so
  a model string can never contain `-->`).
- `region`/`firmware`/`apiVersion`/`app`/`platform` are optional; any
  character outside `[A-Za-z0-9 .()/_+\-:,]` is stripped (not rejected), then
  the result is capped to its field's length (`region` 8 chars, the rest 60).
  An empty result after stripping omits the key entirely.
- `overall` must be one of `works` / `partial` / `fails`.
- `features` must be an object (possibly empty). Unknown keys are dropped
  silently; a *known* key with a value other than `ok`/`ng` fails the whole
  request. Valid keys: `discovery`, `power`, `volume`, `mute`, `input`,
  `sound_mode`, `zone2`, `zone3`, `tuner`, `remote`, `reconnect`.
- Any failure of the above → `400 { "error": "invalid_compat" }`.
- The `supporter` label is **never** added for this category, even if
  `payload.supporter === true` — a compatibility report isn't a priority
  signal.

The Worker renders a human-readable environment/feature table, the optional
comment, and then a machine-readable block the aggregation script
(`scripts/aggregate-compat.mjs`) parses:

```
<!-- avr-compat
{"schema":1,"brand":"denon","model":"AVR-X3800H","overall":"works","features":{"power":"ok"}}
-->
```

**One-time setup:** the `compatibility` label and the three `brand:denon` /
`brand:marantz` / `brand:yamaha` labels must exist on the GitHub repo before
this category is used in production (unlike `bug`/`enhancement`/`question`,
these aren't created by GitHub automatically). Create them once via the repo's
Issues → Labels page or `gh label create`.

| Status | Body | Meaning |
|--------|------|---------|
| 201 | `{ "url": "...", "number": 123 }` | Issue created |
| 400 | `{ "error": "invalid_json" \| "title_and_body_required" \| "invalid_compat" }` | Bad request |
| 413 | `{ "error": "payload_too_large" }` | Body > 128 KB |
| 429 | `{ "error": "rate_limited", "retryAfter": 3600 }` | Too many requests from this IP |
| 500 | `{ "error": "server_misconfigured" }` | Secrets/KV not set up yet |
| 502 | `{ "error": "upstream_failed" }` | GitHub call failed |

Rate limit: 5 / hour per IP, 30 / hour total across all IPs.

Abuse protection: per-IP **and** global hourly rate limits via KV, body size
cap enforced on the bytes actually received (chunked bodies included), fixed
label allowlist, source IPs never stored (only a salted hash, short TTL, used
solely for rate limiting). No App Attest — not worth the complexity at this
app's scale. KV counters are eventually consistent / non-atomic, so the
limits are best-effort, not a hard guarantee.

## Deploy

```bash
cd server
npm i -g wrangler            # or: npx wrangler ...

# 1. Create the KV namespace and paste the printed id into wrangler.toml
npx wrangler kv namespace create RATE_LIMIT

# 2. Create a fine-grained PAT (Issues: Read and write, repo Yorihito/symmetrical-carnival only)
#    and store it as a secret:
npx wrangler secret put GITHUB_TOKEN

# 3. (REQUIRED) a salt so rate-limit IP hashes can't be brute-forced.
#    The raw IP is never stored; only a salted SHA-256 is used as a short-TTL key.
#    POST /report fails closed (500) until this is set.
npx wrangler secret put RATE_SALT

# 4. Deploy
npx wrangler deploy
```

**Redeploy required:** any change to `server/worker.js` (including the
`compatibility` category support added here) only takes effect after running
`npx wrangler deploy` from `server/` again. Existing app versions keep
working unchanged against an un-redeployed Worker — they simply don't send
`category: "compatibility"` yet.

After deploy, note the Worker URL (e.g. `https://avr-controller-report-proxy.<sub>.workers.dev`).
Set `<that URL>/report` as `AVRReportEndpoint` in both `DenonController/DenonController/Info.plist`
and `DenonControllerMobile/App/Info.plist`, then rebuild.

## Local test

```bash
npx wrangler dev
curl -s -XPOST http://localhost:8787/report \
  -H 'content-type: application/json' \
  -d '{"title":"test","body":"hello from curl","category":"bug"}'
```
