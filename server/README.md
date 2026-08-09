# Backend (Cloudflare Worker)

Backend for AVR Controller's "問題を報告" feature: turns a bug report or
feature request into a public GitHub issue.

The GitHub write token lives **only** as a Worker secret — it is never shipped
in the app. The app calls this proxy; the proxy calls GitHub. If the proxy is
unreachable or not yet deployed, the app falls back to opening a prefilled
"new issue" page in the browser (see `ProblemReporter.prefilledIssueURL`), so
the feature works even before this backend exists.

## API

### `POST /report`

```json
{ "title": "string (≤200 chars)", "body": "string (≤60000 chars)", "category": "bug | feature | other" }
```

`category` maps to a GitHub label server-side (`bug`→`bug`, `feature`→`enhancement`,
anything else→`question`) — all three exist by default on a new GitHub repo,
so no label needs to be created ahead of time.

| Status | Body | Meaning |
|--------|------|---------|
| 201 | `{ "url": "...", "number": 123 }` | Issue created |
| 400 | `{ "error": "invalid_json" \| "title_and_body_required" }` | Bad request |
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
