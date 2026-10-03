# Phase 2 — Food logging 2.0 + AI backend: status

> Started 3 Oct 2026. Tickets are defined in `04-food-logging-presets-voice-photo.md` (FOOD) and `07-ai-backend-free-tier.md` (BE). Most of the food work shipped with the AI team's Phase 1 and UI/UX's Phase 5; this file tracks all of it and what engineering built.

**Goal:** logging a meal takes seconds (presets, a sentence, a photo, a barcode), and AI works without the user's own key.

## Verify

```bash
./scripts/test-packages.sh                         # 187 tests
./scripts/check-single-budget.sh
cd backend/ai-proxy && npm test && npm run typecheck   # 41 tests
npx wrangler deploy --dry-run --env dev            # bundles, ~97 KiB gzipped
```

The app builds for a device with no warnings. Not yet installed on the iPhone.

## Tickets

✅ done · 🟡 done, check or deploy pending · ⏳ not started · ⛔ blocked

### Food (doc 04)

| ID | Owner | Status | Notes |
|---|---|---|---|
| FOOD-01 `FoodEntry` v2 | Eng | ✅ | Optional `fiberG`, `sugarG`, `sodiumMg`, `presetID`, `photoAssetID`, plus `nutritionSourceRef` and `grams` (AI contract C1). Older shards decode them as `nil`; no shard schema bump. The AI team fills them from Smart Log and photo v2. |
| FOOD-02 Presets | AI + UI/UX | ✅ | AI Phase 1 (`FoodPreset`, `PresetsView`); App Intents by UI/UX. |
| FOOD-03 Preset proposals | AI | ✅ | AI Phase 1. |
| FOOD-04 Local food DB | AI | 🟡 | Partly covered by the AI team's curated catalog. A bundled SQLite DB is not planned yet. |
| FOOD-05 `NutritionResolver` | AI | ✅ | AI Phase 1. |
| FOOD-06…10 Text, voice, photo v2 | AI | ✅ | AI Phase 1 (Smart Log, speech capture, photo v2). |
| FOOD-11 Remove BYOK | — | ⛔ | Needs the proxy deployed and a product decision. BYOK stays until then. |
| FOOD-12 | AI | — | Tracked as AI-140. |
| FOOD-13 Label OCR | AI | ✅ | AI Phase 1. |
| FOOD-14 Port `CorrectionStore` | Eng | ✅ | Corrections move from `meal_corrections.json` to the LifeOSData store (`documents/mealCorrections.json`). The one-time migration keeps every id: the AI memory index keys photo corrections as `correction.<uuid>`. The old file is renamed `meal_corrections.migrated.json`, not deleted. An unreadable file is left alone and nothing overwrites it. `MealCorrection`, `ImageSignature` (data only) and the upsert and pruning rules live in LifeOSCore. `MealLearningEngine` and `LearnedCorrectionsView` are unchanged. **Open:** check on the device with a real corrections file. |
| FOOD-15 Barcode cache | AI | ✅ | AI Phase 1. |
| FOOD-16 Meal-slot prediction | AI | ⏳ | AI Phase 2 (`MealWindowLearner`). |

### AI backend (doc 07)

Built and tested locally. **Not deployed**, and off in the app by default.

| ID | Status | Notes |
|---|---|---|
| BE-01 Worker, environments, CI | 🟡 | `backend/ai-proxy` (Cloudflare Workers, TypeScript). `dev` and `production` environments. `.github/workflows/proxy.yml`: tests on PRs, deploys dev on `main` and production on a `proxy-v*` tag. **Open:** KV ids, secrets, Cloudflare token, domain. |
| BE-02 App Attest + tokens | 🟡 | Attestation (Apple root, nonce, rpId, aaguid, counter), assertions over method, path, timestamp and body hash, DeviceCheck fallback, 24 h HS256 install tokens. Tested against a fake PKI. **Open:** check a real attestation from the iPhone on the dev proxy. |
| BE-03 `/v1/vision/meal` | 🟡 | Model fallback, JSON check, ≤ 2.6 MB. **Open:** latency overhead (p50 < 150 ms) needs a deploy. |
| BE-04 Provider router | ✅ | Config-driven model lists, retired-model skip, retries with backoff, a model that answers in prose moves on. Only Groq may receive personal data. |
| BE-05 `/v1/chat` + SSE | 🟡 | Streams through; tools pass through. **Open:** end-to-end with the app. |
| BE-06 `/v1/parse/meal` | ✅ | An answer without an `items` array (`ParsedMeal`) is rejected and the next model tried. |
| BE-07 Food proxy | ✅ | Open Food Facts and USDA, normalised per 100 g, edge-cached 30 days (misses 1 day), ODbL attribution kept. |
| BE-08 `/v1/config` | ✅ | Defaults in code, overrides from KV, kill switches per route. The client caches it for 1 h. |
| BE-09 Quotas, limits, breaker | 🟡 | Per-install burst bucket and daily quotas (UTC day) in Durable Objects; DeviceCheck installs get half. Provider breaker: repeated 429s open it for 60 s. **Open:** the 50 rps load test needs a deploy. |
| BE-10 Observability | 🟡 | Analytics Engine data points and a JSON log line per request: no bodies, prompts or IPs, salted install hash. Cloudflare invocation logs are off (they'd record food search terms). **Open:** dashboard. |
| BE-11 iOS client | ✅ | `LifeOSAPI` (LifeOSKit): attest bootstrap, token refresh, serialised assertion signing, retry and re-auth, typed errors, SSE, food lookups, config cache. 13 tests. In the app, `ProxyAIProvider` adapts it to the AI gateway; `LifeOSProxy.makeClient()` returns `nil` unless `lx.proxy.enabled` and an https `lx.proxy.baseURL` are set. |

## Decisions taken

| # | Decision | Record |
|---|---|---|
| P2-D1 | **The proxy is prompt-agnostic.** It takes OpenAI-compatible bodies, so the AI gateway's `PromptRegistry` stays the only source of prompts. The proxy owns the model, key, limits and fallback. | Departs from doc 07 §3 (raw JPEG + hints). Agreed with the AI team. |
| P2-D2 | **BE-11 maps to `AIError`, not `MealScanError`.** The gateway replaced direct Groq calls after doc 07 was written, so the proxy is a gateway provider. | Doc 07 BE-11 text predates the gateway. |
| P2-D3 | **The proxy is a third-party (T3) provider.** It forwards to Groq, so consent, `ContextPacket.forThirdParty` and redaction apply as for BYOK. Health-class tasks need their own consent grant for it. | AI team, 3 Oct. |
| P2-D4 | Quota days are UTC. | The proxy knows nothing about the user's time zone. |

## Open items

| Item | Owner |
|---|---|
| Add `ProviderID.lifeosProxy` (T3), register `ProxyAIProvider` ahead of `groqBYOK` when the client exists | AI team, after their Phases 2–3 land |
| A consent row for the proxy on the AI & privacy screen | UI/UX |
| Deploy (KV, secrets, token, domain), then check a real attestation, latency and load | Eng, after the decisions below |
| Production domain (doc 07 §8 Q1) | Product |
| When to remove BYOK (FOOD-11) | Product |

Provider data terms: `docs/providers.md`.
