# LifeOS AI proxy

A Cloudflare Worker that gives the app AI and food lookups without a user-supplied
key (doc 07, `docs/engineering-roadmap/07-ai-backend-free-tier.md`). It proves each
install with App Attest, enforces per-install quotas, picks the model and holds the
provider key. It stores no request bodies and no user data.

**Status:** built and tested locally, not deployed. The app's client is off by
default (`LifeOSProxy.makeClient()` returns `nil`) and BYOK keeps working.

## Layout

| File | What |
|---|---|
| `src/app.ts` | Routes, auth, quotas, error shape. Pure: every dependency is injected. |
| `src/worker.ts` | Cloudflare bindings: Durable Objects, KV config, edge cache, Analytics Engine. |
| `src/attest.ts` | App Attest attestation and assertion checks, challenges. |
| `src/devicecheck.ts` | DeviceCheck fallback (for devices without App Attest). |
| `src/jwt.ts` | 24 h install tokens (HS256). |
| `src/limits.ts` | Token bucket, daily quota (UTC day), provider circuit breaker. |
| `src/router.ts` | Request sanitising, model fallback, retries. |
| `src/food.ts` | Open Food Facts and USDA lookups, normalised, cached at the edge. |
| `src/config.ts` | Default remote config and the KV override merge. |
| `src/metrics.ts` | Counters without bodies or raw install ids. |

## API

All errors are `{ "error": <reason>, "message": …, "retryAfter": <s>? }`, with
`Retry-After` where relevant.

| Route | Auth | Notes |
|---|---|---|
| `GET /v1/config` | none | Flags, kill switches, quotas, model lists. Cache 1 h. |
| `POST /v1/attest/challenge` | none | Stateless HMAC challenge, valid 5 min. |
| `POST /v1/attest/register` | none | `{keyId, attestation, challenge}` → install token. |
| `POST /v1/attest/refresh` | assertion | `{keyId}` → new token. |
| `POST /v1/attest/devicecheck` | none | `{deviceToken, installUUID}` → token (lower quota share). |
| `POST /v1/attest/debug` | `X-LifeOS-Debug` | Dev only, for the simulator and CI. |
| `POST /v1/vision/meal` | token + assertion | OpenAI-compatible body, inline JPEG data URLs, ≤ 2.6 MB. |
| `POST /v1/parse/meal` | token + assertion | Answer must be JSON with an `items` array (`ParsedMeal`). |
| `POST /v1/chat` | token + assertion | Streams SSE when `"stream": true`. Tools pass through. |
| `GET /v1/food/barcode/:code` | token | 404 when nobody has it. ODbL attribution included. |
| `GET /v1/food/search?q=` | token | OFF and USDA, interleaved. |

POSTs from App Attest installs carry `X-LifeOS-Assertion` over
`METHOD\npath\ntimestamp\nsha256hex(body)` and `X-LifeOS-Timestamp` (ms, ±5 min).
The counter must increase, so the iOS client sends signed requests one at a time.

### Departures from doc 07

- **Prompt-agnostic.** The routes take OpenAI-compatible chat bodies, not raw JPEG
  plus hints. The app's `PromptRegistry` stays the one source of prompts, and
  prompt changes ship without a proxy deploy. The proxy still owns the model,
  key, token caps, size limits and fallback, and drops any `model` the app sends.
- **Quota day is UTC**, not the user's local day: the proxy knows nothing about
  the user.

## Run it

```bash
npm ci                 # wrangler needs workerd's postinstall: don't use --ignore-scripts
npm test               # vitest, fake PKI for App Attest
npm run typecheck
npx wrangler deploy --dry-run --env dev   # bundles without deploying
```

`npm run dev` serves on localhost. Put dev secrets in `.dev.vars` (git-ignored).

## Deploy (BE-09, not done yet)

1. `npx wrangler kv namespace create CONFIG` for dev and prod, and replace
   `REPLACE_WITH_DEV_KV_ID` / `REPLACE_WITH_PROD_KV_ID` in `wrangler.toml`.
2. Set secrets per environment (`wrangler secret put <NAME> --env dev|production`):
   - `JWT_SECRET` (≥ 32 random bytes)
   - `GROQ_API_KEY`
   - `METRICS_SALT`
   - `DEBUG_TOKEN` (dev only)
   - Optional: `DEVICECHECK_TEAM_ID`, `DEVICECHECK_KEY_ID`, `DEVICECHECK_PRIVATE_KEY`, `USDA_API_KEY`
3. GitHub secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
   `.github/workflows/proxy.yml` deploys dev on a push to `main` and production on
   a `proxy-v*` tag.
4. Production domain: undecided (doc 07 §8). Uncomment `routes` once it is.
5. In the app, set `lx.proxy.enabled` and `lx.proxy.baseURL`, and have the AI
   team register `ProxyAIProvider` in the router.

Remote config overrides live in KV under the key `config` (JSON, merged over
`DEFAULT_CONFIG`). Kill a route with `{"killSwitches": {"chat": true}}`.

## Data

The proxy logs one JSON line per request: route, status, model, latency and a
salted install hash. No bodies, prompts, images or IPs. Cloudflare's own
invocation logs are off in `wrangler.toml`, because they would record request
URLs, and food search terms travel in the query string. Groq is the only
provider allowed personal data (`personalDataAllowedProviders`). See
`docs/providers.md`.
