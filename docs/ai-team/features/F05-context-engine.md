# F05 — Context Engine

| | |
|---|---|
| **Phase** | 2 |
| **Owner** | AI Engineer B ("Brain") |
| **Tiers** | T0 (pure Swift) |
| **Depends on** | Repositories (C1), event bus (C2), F06 retrieval, F08 budget state |
| **Consumed by** | F02 (meal-time inference), F04 (portion hints), F07, F08 explanations, F09 |

## 1. Problem
"Context-aware" means the AI answers *for this user, right now*. But on-device models have small context windows (a few thousand tokens), and sending everything is slow, wasteful and a privacy risk. We need the *right* few hundred tokens of context per request.

## 2. Outcome
`ContextEngine.packet(for: intent, budget:, destination:)` returns a compact, privacy-filtered, token-budgeted **ContextPacket** in < 50 ms.

## 3. Context providers
Each provider is small, independently testable and declares its cost and relevance:

```swift
protocol ContextProvider: Sendable {
    var id: ContextSliceID { get }
    var privacy: PrivacyClass { get }
    func relevance(for intent: AIIntent) -> Double          // 0…1 static prior
    func slice(for intent: AIIntent, now: Date) async throws -> ContextSlice
}
struct ContextSlice: Sendable { let id: ContextSliceID; let text: String; let estimatedTokens: Int; let freshness: Date }
```

| Provider | Example rendered text | Privacy |
|---|---|---|
| `ProfileSlice` | `goal=lose weight; diet=vegetarian; units=metric; age 31; sex m` | health |
| `TodaySlice` | `today: eaten 1,240/2,180 kcal (P 62g/C 160g/F 38g); water 5/8; workout: strength 48 min 310 kcal (Watch); steps 6,120; sleep 6.4h` | health |
| `TrendSlice` | `7d avg intake 2,050 kcal; weight −0.4 kg/wk; protein below target 5/7 days` | health |
| `MealWindowSlice` | `usual lunch 13:30–14:30; dinner 21:00–22:00` | personal |
| `PresetSlice` | top 5 presets for current window with kcal | personal |
| `MemorySlice` | top-k retrieved memories (F06) | personal/health |
| `ScheduleSlice` | `todos today: 3 open (gym 18:00)` | personal |
| `TimeSlice` | `now Fri 19:40 IST; weekday; locale en-IN` | public |
| `ConversationSlice` | rolling summary of the current assistant session (F07) | personal |

## 4. Intent → provider plan
A cheap deterministic map (with optional T1 classifier for free-form chat):

| Intent | Providers (in priority order) |
|---|---|
| `logFood` | Time, MealWindow, Preset, Memory(food prefs) |
| `photoMeal` | Memory(portion & dish facts), Profile(diet) |
| `askProgress` | Today, Trend, Profile, Memory |
| `whatShouldIEat` | Today, Profile(diet, goal), Preset, Memory(dislikes/allergies), Time |
| `explainBudget` | Today, F08 budget breakdown, Profile |
| `nudge` | Today, Schedule, Time, Memory(notification prefs) |
| `generalChat` | Time, Profile(minimal), Conversation, Memory |

## 5. Token budgeting
- Budget per destination: on-device default **600 tokens** of context (leaves room for instructions + output); PCC **3,000**; T3 **2,000** (and redacted).
- Greedy knapsack by `relevance × freshness` per token; required slices (Time, and Today for health intents) always included.
- Measure tokens with the model's token-count API where available; otherwise estimate (chars/3.5) with a 15% safety margin.
- Render as terse `key=value` lines — not JSON, not prose — to save tokens.

## 6. Privacy filter per destination
| Destination | Rule |
|---|---|
| T1 on-device | Everything allowed |
| T2 Apple PCC | Everything allowed (Apple PCC privacy guarantees); still minimise |
| T3 third-party | Only if consent; drop `ProfileSlice` age/sex, round numbers, no names/emails, memories filtered to `.public` + food prefs only; never raw HealthKit samples |

## 7. Caching & freshness
- Slices cached in memory, invalidated by `DomainEvent`s (e.g. `foodLogged` invalidates Today and Trend).
- Trend slice recomputed at most every 15 min or on `dayRolledOver`.

## 8. API

```swift
actor ContextEngine: ContextReading {
    func packet(for intent: AIIntent, budget: TokenBudget, destination: ProviderID) async -> ContextPacket
}
struct ContextPacket: Sendable {
    let rendered: String             // what goes into the prompt
    let slices: [ContextSliceID]     // for diagnostics/evals
    let tokenEstimate: Int
    let hash: String                 // for gateway cache keys
}
```

## 9. Acceptance criteria
- [ ] p95 packet build < 50 ms with 1 year of synthetic data.
- [ ] Never exceeds budget (property-based test over random data).
- [ ] T3 packets contain no fields on the deny-list (unit test).
- [ ] Assistant answer quality on the context-dependent eval set improves ≥ 20 pts vs. no-context baseline (F11).

## 10. Tickets
`AI-201` Provider protocol + 9 providers · `AI-202` Intent plan table + optional T1 intent classifier · `AI-203` Token budgeter · `AI-204` Privacy filter · `AI-205` Event-driven cache · `AI-206` Diagnostics view (debug) · `AI-207` Evals.
