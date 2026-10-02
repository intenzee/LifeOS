# F10 — Siri, Shortcuts, Widgets & Watch Voice

| | |
|---|---|
| **Phase** | 4 |
| **Owner** | AI Engineer A with iOS Core (plumbing C5) and Health/Watch (C4) |
| **Tiers** | T1/T2 via phone; watchOS 27 PCC where available |
| **Depends on** | F02, F03, F07, App Group store access |

## 1. Outcome
Logging and asking happen anywhere: *"Hey Siri, log my usual breakfast in LifeOS"*, a tap on a widget, the Action button, a Watch complication, or dictation on the wrist.

## 2. App Intents (iOS 17+)

| Intent | Parameters | Result |
|---|---|---|
| `LogFoodIntent` | `text: String` | Parses via F02; if all items high-confidence → logs and returns snippet with Undo; else returns snippet asking to confirm (`requestConfirmation`) |
| `LogPresetIntent` | `preset: PresetEntity` (with `EntityQuery` + string search) | Logs, returns kcal snippet |
| `LogWaterIntent` | `glasses: Int = 1` | Logs |
| `LogWeightIntent` | `weight: Measurement<UnitMass>` | Logs + HealthKit |
| `CaloriesLeftIntent` | — | "You have 640 kcal left; protein 38 g to go" |
| `AskLifeOSIntent` | `question: String` | Runs F07 with read-only tools; returns short answer |
| `StartWorkoutIntent` | `exercise: ExerciseEntity` | Opens Watch tracker (if paired) |

- `AppShortcutsProvider` with phrases incl. `\(.applicationName)` (e.g. "Log my usual in LifeOS", "How many calories left in LifeOS").
- `PresetEntity` and `FoodEntity` conform to `AppEntity`; on iOS 26+/27 also expose them to Apple Intelligence / Spotlight per the shipping SDK's semantic-index APIs (verify), so Siri can resolve "my gym shake".
- Intents run in-process when possible; all read/write via repositories in the App Group container.

## 3. Widgets & controls
- Interactive widget (small/medium): calories left ring + 3 time-relevant presets (`Button(intent: LogPresetIntent)`).
- Lock Screen widget: calories left / water.
- Control Center control + Action button: "Voice log food" → opens the voice sheet directly.

## 4. Apple Watch
| Capability | Implementation |
|---|---|
| One-tap presets | `presetsDigest` application context (C4); tap → `aiQuickLog` with preset ID |
| Dictate a meal | Watch text input (dictation) → `aiQuickLog` → phone parses (F02) → `aiQuickLogResult` → Watch shows summary + Undo |
| Direct on Watch (watchOS 27+) | If PCC on watchOS is available and phone unreachable, parse on Watch via PCC and queue the write for sync |
| Complication | Calories left + tap to voice log |
| Smart Stack widget | Shows the relevant preset at meal windows |
| Offline | Queue `aiQuickLog` with `transferUserInfo`; show "Will log when your iPhone is nearby" |

## 5. Acceptance criteria
- [ ] All App Shortcuts phrases recognised in en-IN and en-US manual test scripts.
- [ ] Siri "log my usual breakfast" → logged in ≤ 3 s with phone locked (where intent allows).
- [ ] Watch dictation → result on Watch ≤ 5 s with phone reachable.
- [ ] Widget buttons log without opening the app and update the widget timeline.

## 6. Tickets
`AI-420` Intent bodies (7 intents) · `AI-421` Entities + queries · `AI-422` App Shortcuts phrases · `AI-423` Widget providers · `AI-424` Watch quick-log flows (with Watch team) · `AI-425` Offline queue · `AI-426` Tests.
