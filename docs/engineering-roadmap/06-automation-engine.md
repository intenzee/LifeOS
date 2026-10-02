# 06 — Automation Engine

> **Squad:** Platform (engine) + Health & Watch (triggers) · **Phase:** P3 (foundations of BG scheduling start in P1) · **Depends on:** 01, 02, 03, 04, 05 · **Feeds:** notifications, widgets, Live Activities, assistant insight cards

---

## 1. Goal

LifeOS does the right thing at the right moment without being asked: it nudges, logs routines, summarises and adapts. The user stays in control and every automation can be seen, paused and undone.

---

## 2. Current state
- `NotificationService` schedules local notifications for todos, fixed-interval water reminders (9:00–21:00 every 2 h) and default meal reminders. They are calendar triggers only and carry no context (e.g. a water reminder fires even when the goal is already met).
- No background tasks, widgets, Live Activities, App Intents or Shortcuts.

---

## 3. Concepts

```swift
@Model final class AutomationRule {
    @Attribute(.unique) var id: UUID
    var templateID: String          // "meal.preset.suggest", "water.pacing", ...
    var params: Data                // Codable params per template
    var isEnabled: Bool
    var createdBy: RuleOrigin       // builtIn, user, assistant
    var lastFiredAt: Date?
    var fireCountToday: Int
    var quietHours: DateInterval?   // inherits global quiet hours if nil
}
```
- **Trigger:** time, HealthKit event (workout ended, weight logged), app event (meal logged, goal hit), day boundary, or location (deferred to v2).
- **Condition:** a pure function over the `AutomationContext` snapshot (today's data, profile, memory flags).
- **Action:** notify (with actions), create insight card, log preset (with undo), create task, update widget/Live Activity, or run a summariser.

v1 ships **template-based rules** (built-in templates with user-tunable params), not a free-form rule builder. Users who want arbitrary automations get **Shortcuts** support through App Intents (§5). That gives them full power for no extra engineering cost.

### Engine flow
```mermaid
flowchart LR
    T1[BGAppRefreshTask] --> EV
    T2[HK observer wake] --> EV
    T3[App foreground] --> EV
    T4[Data change events] --> EV
    T5[Notification action] --> EV
    EV[AutomationEngine.evaluate(trigger)] --> CTX[Build AutomationContext]
    CTX --> R{For each enabled rule<br/>matching trigger}
    R -->|condition true & budget OK| ACT[Execute action]
    R -->|false| SKIP[skip]
    ACT --> LOG[(AutomationLog)]
    ACT --> OUT[Notification · Card · Widget reload · Live Activity · Data write]
```

**Notification budget:** max 4 automation notifications per day by default (user-configurable). Priority ordering decides what fires. Global quiet hours are respected, and nothing fires during an active workout (except workout-related ones).

---

## 4. Built-in automation templates (v1)

| ID | Name | Trigger | Condition | Action | Default |
|---|---|---|---|---|---|
| `morning.brief` | Morning brief | First unlock after wake / 07:30 BG | Not sent today | Notification + Home card: sleep, today's budget, planned workout, top task | On |
| `meal.preset.suggest` | Usual meal nudge | Learned typical time of a preset (doc 04) − 10 min | Slot not yet logged today | Actionable notification **"Log usual breakfast?" [Log] [Something else]** | On (once a preset is used ≥ 5×) |
| `meal.preset.autolog` | Auto-log routine | Same | User set `autoLogPolicy = .autoWithUndo` | Logs, then notifies "Logged usual breakfast · Undo" | Off (opt-in per preset) |
| `water.pacing` | Smart water | Every 2 h in the waking window | Behind the linear pace to goal by ≥ 2 glasses | Notification with [+1 glass] [+2] actions | On |
| `workout.synced` | Workout recap | HK workout ingested (doc 02) | Workout ≥ 10 min | Notification: "Run 5.2 km · +205 kcal to budget" | On |
| `protein.postworkout` | Protein nudge | 45 min after a strength workout | Protein < 50% of target | Card / notification with 2 quick-add suggestions | On |
| `budget.evening` | Evening check-in | 19:00 | Budget left > 300 or over by > 200 | Card with dinner ideas (assistant `suggestMeals`) or a gentle note | On |
| `streak.protect` | Streak save | 20:30 | Perfect-day streak ≥ 3 and 1 item missing | Notification naming the missing item | On |
| `day.wrap` | End-of-day summary | 23:30 BG / next morning | — | Writes the episodic memory (doc 05 AI-11). Freezes the day (doc 03). | On (silent) |
| `week.review` | Weekly review | Sunday 18:00 | ≥ 4 days of data | Insight card + optional notification: trends, wins, one suggestion | On |
| `weight.reminder` | Weigh-in | User's chosen days, morning | No weight today | Notification [Log weight] (opens the picker) | Off |
| `health.access` | Health check | Weekly | Likely denied (doc 02 §3.6) | Card to fix permissions | On |

All copy is templated in code with exact numbers. The LLM is optional ("polish" for `week.review` only).

---

## 5. System integrations

| Integration | What | Tickets |
|---|---|---|
| **BGTaskScheduler** | `app.lifeos.refresh` (BGAppRefresh, ~hourly best-effort) and `app.lifeos.maintenance` (BGProcessing: day freeze, embeddings, summaries, allowance job from doc 03) | AUTO-02 |
| **Actionable notifications** | Categories with actions that run **without opening the app** (log water, log preset, undo, snooze) via `UNNotificationCategory` | AUTO-03 |
| **App Intents + Shortcuts** | Intents for every core action (log water, log preset, log weight, start workout, get remaining calories, ask LifeOS). Exposed with `AppShortcutsProvider`, so users can build personal automations in Shortcuts (time of day, arriving at the gym, etc.). | AUTO-05 |
| **WidgetKit (iOS)** | Home/Lock Screen: budget ring, macros, water with an interactive +1 button (iOS 17+ `Button(intent:)`), streak, next task | AUTO-06 |
| **Controls (iOS 18+)** | Control Center / Lock Screen controls: +1 water, log usual breakfast, start workout | AUTO-07 |
| **Live Activities** | During a workout: elapsed time, sets, kcal. During an eating window (optional). Dynamic Island. | AUTO-09 |
| **Watch** | Complications and Smart Stack (doc 02 WCH-15) reload on the same events | — |
| **Focus filters (later)** | Silence non-critical automations in Work/Sleep focus | v2 |

---

## 6. Tickets

| ID | Title | Size | Phase | Acceptance criteria |
|---|---|---|---|---|
| AUTO-01 | `AutomationEngine` core | L | P3 | Rule model, context builder, evaluation loop, notification budget, quiet hours, `AutomationLog`. Pure evaluation is unit-tested with a fake clock. |
| AUTO-02 | Background tasks | M | P1 | Both BG identifiers registered in Info.plist. Handlers are idempotent and finish < 25 s. Expiration handlers save state. |
| AUTO-03 | Actionable notification categories | M | P3 | Actions execute in the background through App Intents/handlers. Every write action has a follow-up "Undo" path. |
| AUTO-04 | Built-in templates (12) | L | P3 | §4 table implemented with params UI. Each has unit tests for trigger/condition and copy snapshots. |
| AUTO-05 | App Intents catalogue + Shortcuts | M | P2→P3 | ≥ 8 intents. Appear in Shortcuts and Spotlight. Parameterised phrases. Work from the watch via Siri. |
| AUTO-06 | Widgets (iOS) | L | P3 | 4 widget kinds, small/medium/large and Lock Screen. Interactive water button. Timeline reloads on data change. Shares the `EnergyDay` source. |
| AUTO-07 | Controls (iOS 18+) | S | P3 | 3 controls, gated by `#available` |
| AUTO-08 | Day-wrap maintenance job | S | P3 | Freezes the day, writes the episodic memory, recomputes the allowance. Runs even when the app wasn't opened that day (best effort; catches up on next launch). |
| AUTO-09 | Workout Live Activity | M | P3 | Starts from a phone or watch workout. Updates ≤ every 10 s. Ends automatically. |
| AUTO-10 | Automation settings screen | M | P3 | List of rules, toggles, params, history log ("what fired and why"), global quiet hours, daily cap |
| AUTO-11 | Replace `NotificationService` water/meal schedules | S | P3 | Old fixed schedules removed during migration, with the user's prior on/off choices preserved |
| AUTO-12 | Assistant-created automations | S | P3 | `createAutomation` tool (doc 05) maps NL → template + params, confirmed by the user |

---

## 7. Principles
1. **Earn the interruption.** Each notification must contain a number or action specific to that user's day. Generic "Don't forget to log!" isn't allowed.
2. **Silence when goals are met.** Conditions always check current state first.
3. **Automation writes are labelled** `source = .automation` and are undoable for 24 h from the log/history screen.
4. **Best-effort background, guaranteed foreground.** iOS decides when BG tasks run, so every job also runs on next foreground if it's overdue.

---

## 8. Open questions
1. Default daily notification cap: 4? Should the premium audience get "concierge mode" (more proactive) as an opt-in?
2. Location-based triggers (arrive at gym → start workout) in v1 via Shortcuts only, or native geofencing in v2?
