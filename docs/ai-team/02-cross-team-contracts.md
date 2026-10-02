# 02 — Cross-Team Contracts (AI ⇄ iOS Core ⇄ Health/Watch ⇄ Design)

The AI team cannot ship alone. This document lists every interface we **need** from other teams and every interface we **provide**, with the phase in which it is needed. Each row should be agreed in writing (ticket link) before the dependent phase starts.

---

## 1. Summary table

| # | Contract | Provider | Consumer | Needed by |
|---|---|---|---|---|
| C1 | SwiftData domain store + repositories | iOS Core | AI | Phase 1 (presets), **blocking** Phase 2 |
| C2 | Domain event bus | iOS Core | AI | Phase 2 |
| C3 | HealthKit workout & energy feed (incl. Apple Watch) | Health/Watch | AI (F08) | Phase 2 |
| C4 | Watch ⇄ phone AI message types | Health/Watch | AI (F10) | Phase 4 |
| C5 | App Intents / widget plumbing | iOS Core | AI (F10) | Phase 4 |
| C6 | AI UI component kit & states | Design | AI | Phase 1 (first components) |
| C7 | `AIGateway` public API | **AI** | All teams | End of Phase 0 |
| C8 | `ContextEngine` + `MemoryStore` read APIs | **AI** | Design (memory screen), iOS Core | Phase 2 |
| C9 | `AssistantVisualState` stream | **AI** | Design (3D/motion assistant orb) | Phase 3 |
| C10 | Remote config (model lists, feature flags, prompts version) | iOS Core (infra) | AI | Phase 0 |

---

## 2. What we need from iOS Core

### 2.1 C1 — SwiftData store and repositories
Replace `UserDefaults` JSON blobs with SwiftData models, date-keyed, with file protection `.complete` (or `.completeUntilFirstUserAuthentication` where background tasks need access). Minimum entities and fields the AI team relies on:

```swift
@Model final class FoodEntry {        // one logged item
    var id: UUID; var name: String
    var kcal: Double; var protein: Double; var carbs: Double; var fat: Double
    var quantity: Double; var unit: String          // e.g. 2, "roti"
    var grams: Double?                               // resolved weight if known
    var mealType: String                             // breakfast/lunch/dinner/snacks
    var loggedAt: Date
    var source: String                               // manual|barcode|photo|voice|text|preset|assistant|automation
    var aiConfidence: Double?                        // nil for manual
    var presetId: UUID?; var photoSignatureId: UUID?
    var nutritionSourceRef: String?                  // e.g. "usda:173944", "user:custom:…", "llm-estimate"
}
@Model final class FoodPreset { … }    // spec in F03
@Model final class WorkoutSession { … } // spec in C3
@Model final class DailyMetric {        // water, weight, steps, sleep, active energy per day
    var date: Date; var kind: String; var value: Double; var source: String
}
@Model final class TodoItemModel { … } // existing TodoItem fields + createdBy (user|ai)
```

Repository protocols (async, testable) — the AI team only talks to these:

```swift
protocol FoodLogRepository {
    func entries(in range: DateInterval) async throws -> [FoodEntry]
    func add(_ entries: [FoodEntryDraft], undoToken: UUID) async throws
    func undo(_ token: UUID) async throws
}
protocol PresetRepository { /* CRUD + usage stats */ }
protocol WorkoutRepository { func sessions(in: DateInterval) async throws -> [WorkoutSession] }
protocol MetricsRepository { func series(_ kind: MetricKind, in: DateInterval) async throws -> [DailyMetricValue] }
```

**Must also fix:** B2 (weekday-keyed workouts), B3 (duplicate stores), B4 (main-actor crash). Migration must import existing UserDefaults history.

### 2.2 Undo
Every write API accepts an `undoToken`. AI writes surface a snackbar "Logged 2 rotis · Undo" for at least 8 seconds and remain undoable from the day view until midnight.

### 2.3 C2 — Domain event bus
A single `AsyncStream<DomainEvent>` (or Combine publisher) replacing the many `.onChange` streak triggers:

```swift
enum DomainEvent: Sendable {
    case foodLogged([UUID], source: String)
    case foodDeleted(UUID)
    case waterChanged(Int)
    case weightLogged(Double)
    case workoutIngested(UUID, source: WorkoutSource)
    case todoChanged(UUID)
    case dayRolledOver(Date)
    case appBecameActive
}
```
Debounced (≥ 300 ms) for streak recomputation. The AI Context Engine, Memory consolidator and Trigger engine subscribe to it.

### 2.4 C5 — App Intents plumbing
iOS Core sets up the App Intents target membership, `AppShortcutsProvider`, widget extension and App Group container (so intents and widgets can read the store). AI team writes the intent bodies (F10).

### 2.5 C10 — Remote config
A tiny, free remote config (e.g. a JSON file on GitHub Pages or a CloudKit public record) read at launch and cached:

```json
{
  "ai": {
    "groqVisionModels": ["…"], "geminiModels": ["…"],
    "promptVersion": "2026.10.1",
    "flags": { "assistant": true, "autoLogPresets": false, "pccEnabled": true }
  }
}
```

---

## 3. What we need from Health/Watch

### 3.1 C3 — Workout & energy feed

**Requirements**
1. Read `HKWorkout` samples (all activity types) plus their `activeEnergyBurned` statistics, heart-rate average, duration and source (Apple Watch, iPhone, third-party apps).
2. Use `HKObserverQuery` + `enableBackgroundDelivery(for:frequency:)` on the workout type, and `HKAnchoredObjectQuery` to fetch only new/deleted samples. (Requires the HealthKit background-delivery entitlement and the paid developer programme.)
3. Persist each workout into `WorkoutSession` and emit `DomainEvent.workoutIngested`.
4. Also expose daily totals: active energy, basal energy (if authorised), steps, exercise minutes.
5. **Stop writing the synthetic "workout calories" sample** to HealthKit once real workouts are ingested (prevents feedback loops — see audit B6). Keep writing body mass.
6. Optional (stretch): run an `HKWorkoutSession` on the Watch for LifeOS-started strength sessions so `AutoSetTracker` works with the screen off and the session lands in Health as a real workout.

```swift
struct WorkoutSession: Identifiable, Sendable {
    let id: UUID
    let healthKitUUID: UUID?          // nil for manual
    let source: WorkoutSource         // .appleWatch, .iPhone, .thirdParty(bundleId), .manualLifeOS, .watchAutoSet
    let activityType: String          // HKWorkoutActivityType name
    let start: Date, end: Date
    let activeKcal: Double?           // measured
    let estimatedKcal: Double?        // LifeOS MET estimate (manual sets)
    let avgHeartRate: Double?
    let exercises: [ExerciseSummary]  // for LifeOS strength sessions (body part, name, sets, reps)
}
```

**Latency SLA:** a workout finished on the Watch should be in `WorkoutRepository` within 15 minutes while the phone is locked, and within 10 seconds when LifeOS is foregrounded.

### 3.2 C4 — Watch messages for AI
New WatchConnectivity message types (phone does the AI work unless watchOS 27 PCC is used directly):

| Message | Direction | Payload |
|---|---|---|
| `aiQuickLog` | watch → phone | `{ text: String, locale, timestamp }` (dictated text) |
| `aiQuickLogResult` | phone → watch | `{ summary, kcal, undoToken, needsConfirm: Bool }` |
| `aiConfirm` / `aiUndo` | watch → phone | `{ undoToken }` |
| `presetsDigest` | phone → watch (application context) | top 8 presets `{ id, name, kcal }` for one-tap logging |

---

## 4. What we need from Design (UI/UX) — C6

The AI team will not design visuals; we need a component kit with these **states** specified (light/dark, Dynamic Type, reduced motion):

| Component | States to design |
|---|---|
| **AI confirmation card** (food from text/voice/photo/preset) | parsing, ready (high confidence), ready (needs review — highlighted low-confidence items), editing item, logged + undo, failed → manual |
| **Source & confidence chip** | On-device · Apple Cloud · Your key (Gemini/Groq) · Learned · Estimate; confidence high/medium/low (never a fake %) |
| **Voice capture sheet** | listening (live transcript), thinking, result, error/no speech |
| **Photo capture screen** | live camera, framing hint, captured, analysing, per-item results with portion sliders |
| **Assistant surface** | idle, listening, thinking, streaming answer, tool-action card ("Logged water · Undo"), error; minimised orb on Home |
| **Memory screen** | list grouped by type, edit, delete, pause memory, "forget everything" confirm |
| **Consent sheets** | enable Apple Intelligence features; enable third-party cloud (clear data-use disclosure); HealthKit read |
| **Nudge notification + in-app card** | standard, actionable (one-tap log), snoozed |
| **Budget explainer** | "Why is my target 2,340 today?" breakdown |

### 4.1 C9 — What we provide to Design for motion/3D
A single observable state machine the premium assistant visual (orb/3D object) can bind to:

```swift
enum AssistantVisualState: Equatable {
    case idle
    case listening(level: Double)     // 0…1 mic level for reactive animation
    case thinking
    case speaking(progress: Double)   // streaming progress
    case success
    case error
}
@Observable final class AssistantPresence { var state: AssistantVisualState }
```
Design owns rendering (SwiftUI/Metal/RealityKit); we guarantee state changes are emitted on the main actor at ≤ 30 Hz.

---

## 5. What we provide — C7 / C8 (summary; detail in F01, F05, F06)

```swift
// C7
protocol AIGatewaying {
    func run<Output: Decodable & Sendable>(_ request: AIRequest<Output>) async throws -> AIResult<Output>
    func availability(for task: AITask) async -> AIAvailability   // for UI gating/badges
}
// C8
protocol ContextReading { func packet(for intent: AIIntent, budget: TokenBudget) async -> ContextPacket }
protocol MemoryBrowsing {
    func all() async -> [MemoryItem]; func update(_ item: MemoryItem) async
    func delete(_ id: UUID) async; func wipe() async; var isPaused: Bool { get set }
}
```
