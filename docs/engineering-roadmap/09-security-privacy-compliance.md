# 09 — Security, Privacy & Compliance

> **Squad:** Platform (owner). Every squad reviews against this doc. · **Phases:** baseline in P0, AI/cloud items in P2–P3, full review in P5
> ⚠️ This is an engineering checklist, **not legal advice**. Have a lawyer review the privacy policy, consent flows and data-processing terms before external beta. Re-check Apple's App Review Guidelines and each provider's terms at submission time, because they change.

---

## 1. Principles
1. **Local-first, minimal cloud.** Health, food, weight, sleep, memory and photos stay on the device. The cloud proxy is stateless (doc 07).
2. **Explicit consent before any personal data leaves the device**, including to AI providers.
3. **Transparency and control:** users can see, export and delete everything, including AI memory.
4. **Least privilege:** request only the HealthKit types and permissions a feature needs, in context.

---

## 2. Current state (gaps)
| Gap | Evidence |
|---|---|
| Health data in plain `UserDefaults` plists | `PersistenceManager`, managers (doc 01 C6) |
| User-supplied Groq key in Keychain (OK), but the feature requires users to handle API keys | `AIKeyStore` |
| Meal photos sent to a third-party AI with no explicit consent screen | `AIMealScanView` → Groq |
| No privacy manifest (`PrivacyInfo.xcprivacy`) | repo |
| `print` logs may include user values | throughout |
| No data export or delete-all flow | — |

---

## 3. Requirements

### 3.1 Data at rest
- The store file (SwiftData/SQLite) and photo directory use Data Protection. Use `.completeUntilFirstUserAuthentication` (not `.complete`), because HealthKit background delivery and BG tasks need to write while the phone is locked. Document this trade-off.
- Secrets (install token, App Attest key ID) live in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. That's the pattern `AIKeyStore` already uses.
- Optional **App Lock** (Face ID / passcode) on launch and on the Memory screen. Premium users expect this.
- Exclude caches (OFF cache, thumbnails) from backup. Include the user's store and photos in the encrypted device backup.

### 3.2 Data in transit
- TLS only (ATS default, no exceptions). Proxy only. No direct third-party AI calls from the client after FOOD-11.
- Certificate pinning is **optional** for our own proxy domain (weigh the operational risk of pin rotation). Don't pin third-party domains.

### 3.3 AI-specific
| Risk | Control |
|---|---|
| Personal data to third-party AI | **Consent screen** before first cloud AI use: what's sent (photo / text / selected context), to whom (provider name), retention per provider terms, and how to turn it off. Store a consent record (version, date). On-device paths need no consent. |
| Provider terms allow training/human review on free tier | Provider eligibility rule (doc 07 §5). E.g. exclude the Gemini free tier for personal data. |
| **Prompt injection via data** — OpenFoodFacts product names/ingredients are user-generated, and so are memory items and notes | Treat all tool results and retrieved text as *data*. Wrap them in delimiters and tell the model so in the system prompt. **Write tools always require confirmation** (doc 05 §5), so injected instructions can't silently act. |
| Hallucinated numbers | Numbers validator (doc 05 AI-08) |
| Unsafe diet/medical advice | Safety policy and suite (doc 05 §8, AI-16) |
| Health context sent to cloud | Off by default. `sensitivity = .health` memory items are filtered out unless the user opts in. |
| Photo metadata (GPS) | Re-encode and strip. Unit test asserts no GPS EXIF in uploaded bytes or stored files. |

### 3.4 Apple platform & App Review
| Area | Requirement (verify current wording before submission) |
|---|---|
| Privacy manifest | `PrivacyInfo.xcprivacy` for the app and each embedded SDK: required-reason APIs (e.g. `UserDefaults`, file timestamps), collected data types, tracking = false |
| App Privacy "nutrition label" | Declare health and fitness, photos (if uploaded for analysis), diagnostics and identifiers (install ID), linked/not linked, purposes |
| HealthKit (guideline 5.1.3 & HealthKit terms) | No use of HealthKit data for advertising or data mining. Don't share it with third parties without explicit consent. **Don't store personal health information in iCloud** (this is why cloud sync is deferred, decision D3). Don't write false data to HealthKit (we stop writing estimated active energy — FND-07/WCH-07). A privacy policy is required. |
| Sharing with third-party AI (guideline 5.1.2) | Clearly disclose and get explicit permission before sharing personal data with third parties, **including third-party AI** |
| Medical accuracy (guideline 1.4.1) | Present calorie and energy figures as estimates. No diagnostic claims. Disclaimer in onboarding and the assistant. |
| Permissions copy | `Info.plist` usage strings explain the specific purpose (camera = barcode **and meal photos**, microphone and speech recognition for voice logging, HealthKit read/write lists). Today's camera string mentions barcodes only, so update it. |
| Age rating & provider age limits | Some AI provider terms require 18+ users. Align the age rating and terms accordingly. |

### 3.5 Privacy law
Depending on the launch markets: India's **DPDP Act 2023** (notice, consent, purpose limitation, data-principal rights, breach duties), **GDPR/UK GDPR** if EU/UK users (health = special-category data, explicit consent), US state health-data laws (e.g. Washington's My Health My Data Act). Legal must map the markets before external beta.

### 3.6 User rights features
- **Export:** full JSON (+ CSV for food, weight, workouts) via the share sheet, including memory items and automation logs.
- **Delete all data:** wipes the store, photos, memory, Keychain items and anchors, and revokes the install token at the proxy. A confirmation step with a 2-step guard.
- **Per-item delete** for memory, corrections, presets and photos.
- **AI controls:** toggles for cloud AI, health-context-in-cloud and memory (pause), all in one Privacy screen.

### 3.7 Supply chain & licences
- Keep third-party dependencies minimal (currently none, which is excellent). Each added package needs a Tech Lead sign-off, a licence check and a privacy-manifest check.
- Dataset licences: OpenFoodFacts (ODbL: attribution and share-alike on database derivatives), USDA FDC (public domain), IFCT/regional data (check terms), 3D assets and fonts (embedding licence).
- Maintain `THIRD_PARTY_NOTICES.md` and an in-app Acknowledgements screen.

---

## 4. Tickets
| ID | Title | Size | Phase | Acceptance criteria |
|---|---|---|---|---|
| SEC-01 | Store and photo file protection | S | P0 | §3.1 protection classes applied and verified on device |
| SEC-02 | Privacy manifest | S | P0 | `PrivacyInfo.xcprivacy` added. Xcode privacy report generated and reviewed. |
| SEC-03 | Logging privacy | S | P0 | All user values `privacy: .private`. No bodies or prompts logged in release builds. |
| SEC-04 | Info.plist purpose strings update | S | P2 | Camera, mic, speech and HealthKit strings accurate for all features |
| SEC-05 | Cloud AI consent flow | M | P2 | §3.3 consent screen, versioned consent record, settings toggle, blocks cloud calls until accepted |
| SEC-06 | EXIF/GPS stripping test | S | P2 | Unit test on sample photos with GPS |
| SEC-07 | Prompt-injection hardening | M | P3 | Delimited tool data. Red-team prompts in the AI-16 suite include injected OFF product names. 0 unconfirmed writes. |
| SEC-08 | Health-context-in-cloud gating | S | P3 | Memory sensitivity filter. Snapshot redaction when the toggle is off. |
| SEC-09 | Export all data | M | P3 | JSON + CSV, includes every model. Round-trip import test (debug). |
| SEC-10 | Delete all data | M | P3 | §3.6. Verified empty store, Keychain and file system after deletion. Proxy token revoked. |
| SEC-11 | App Lock | S | P4 | Face ID / passcode, timeout options, protects the app and the Memory screen |
| SEC-12 | Third-party notices + acknowledgements | S | P5 | All datasets, fonts and assets listed with licences |
| SEC-13 | Pre-submission compliance review | M | P5 | §3.4 table checked line by line against the then-current guidelines. Sign-off recorded. |
| SEC-14 | Proxy security review | M | P5 | App Attest verification, quotas, secret rotation, no-PII logging verified. Basic penetration test of the endpoints. |
