# AI providers and their data terms

Which cloud providers may see user data, and why. The proxy enforces this in
`backend/ai-proxy/src/config.ts` (`personalDataAllowedProviders`), and the
app's gateway does the same for BYOK through consent and redaction
(`PrivacyGate`, `ContextPacket.forThirdParty`). Re-check the terms before each
release that changes providers; they change.

Last checked: 3 Oct 2026.

| Provider | Used for | Personal data? | Why |
|---|---|---|---|
| Groq (API, via the proxy) | Photo, text parse, chat | **Allowed** | Groq's terms bar training on API inputs and outputs. Requests aren't retained by default, except logs kept up to 30 days for troubleshooting and abuse. Zero Data Retention can be turned on in the console's Data Controls: **turn it on for the proxy's account before launch.** |
| Groq (BYOK) | Same | The user's own account and terms | The key is the user's; consent screens say so. |
| Gemini API, free tier | Not used by the proxy | **Not allowed** | Google may use free-tier prompts and responses to improve its products, and human reviewers may read them. Google's own terms say not to send personal information to the unpaid tier. |
| Gemini API, paid tier (BYOK) | Optional BYOK | The user's own account and terms | Google says paid-tier prompts aren't used to improve its products. |
| Open Food Facts, USDA FoodData Central | Barcode and food search (proxy) | No | Only a barcode or a search term is sent, never an install id or anything about the user. OFF data is ODbL: show the attribution. |

## Sources

- [Groq: Your data](https://console.groq.com/docs/your-data)
- [Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms)
