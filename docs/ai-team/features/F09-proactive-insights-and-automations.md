# F09 — Proactive Insights & Automations

| | |
|---|---|
| **Phase** | 4 |
| **Owner** | AI Engineer B |
| **Tiers** | T0 (triggers, scoring, scheduling) + T1 (copy) |
| **Depends on** | F05, F06, F08, F03 routines, `NotificationService`, BackgroundTasks |

## 1. Outcome
LifeOS acts before the user has to: the right reminder at the right moment, gentle course-corrections, and small automations — while never becoming noisy. **Default ceiling: 2 proactive notifications per day**, user-adjustable.

## 2. Trigger catalogue (v1)

| ID | Trigger (deterministic) | Action | Default |
|---|---|---|---|
| T-MEAL | Meal window started (learned, F05) and nothing logged | Actionable notif: top preset one-tap / "log by voice" | On |
| T-PRESET | Preset `remind`/`autoLog` policy (F03) | Remind or auto-log with undo | Per preset |
| T-WATER | Behind hydration pace by ≥ 2 glasses at 14:00/17:00 | Notif with +1 glass action | On |
| T-WORKOUT | `workoutIngested` | Post-workout card + optional notif | Card only |
| T-PROTEIN | 19:00 and protein < 60% of target | Suggest 2 foods from presets/history | Off (opt-in) |
| T-STREAK | Streak at risk (StreakManager) at 20:00 | Single nudge naming the missing item | On |
| T-LOGGAP | No logs for 2 days | Friendly check-in, no guilt | On |
| T-WEIGH | Weekly weigh-in day (user-chosen) morning | Reminder | Off |
| T-TODO | Todo due soon with no reminder set | Suggest reminder | In-app only |
| T-REVIEW | Sunday 19:00 | Weekly review ready (F07) | On |
| T-ANOMALY | Intake > 140% of target 3 days running, or sleep < 5 h 3 nights | Supportive insight card (not a notification); no shaming copy | In-app only |

## 3. Nudge ranking
Each candidate gets `score = urgency × usefulness × (1 − fatigue) × userAffinity`:
- `urgency`: time sensitivity (meal window closing → high).
- `usefulness`: learned from response — tapped/acted (+), dismissed/ignored (−); per trigger type, EMA.
- `fatigue`: notifications in last 24 h and same-type in last 72 h.
- `userAffinity`: memory preferences ("no notifications before 8am", "don't remind me about water").
Send only if score ≥ threshold and under the daily cap; otherwise demote to an in-app card. Quiet hours respected (default 22:30–07:30, plus Focus modes via interruption levels).

## 4. Copy generation
`nudgeCompose` on T1 with a strict schema (`title ≤ 40 chars`, `body ≤ 90 chars`, `actions`) and the context slice; template fallback for every trigger. Tone rules from F07; banned-phrase list (guilt/shame words) checked deterministically.

## 5. Scheduling mechanics
- Time-based → `UNCalendarNotificationTrigger` scheduled for the next 24 h at app open/day rollover; re-planned on relevant events.
- Event-based (workouts) → HealthKit background delivery wakes the app (C3) → evaluate triggers → local notification.
- Periodic evaluation → `BGAppRefreshTask` (best-effort; system decides timing) — design so nothing *depends* on exact background timing.
- Heavy jobs (memory consolidation, routine mining, adaptive TDEE) → `BGProcessingTask` requiring power.
- Notification actions (Log, +1 glass, Undo) handled via `UNNotificationCategory` actions without opening the app where possible.

## 6. Automations ("Autopilot" settings)
User-visible toggles, each off by default except where noted:
- Auto-log presets (per preset, F03).
- Auto-adjust targets after workouts (on — F08).
- Adaptive target (F08 §6).
- Auto-create todos from assistant plans ("plan my week" → todos) with confirmation.
- Smart reminder timing: move fixed reminders to learned best times.
Every automation run writes an **Activity log** entry ("08:55 Auto-logged 'Weekday breakfast' · Undo") visible in Settings → Autopilot.

## 7. Acceptance criteria
- [ ] Never exceeds the daily cap (simulation over 90 synthetic days × 50 user profiles).
- [ ] Respects quiet hours and Focus in 100% of simulated cases.
- [ ] Meal reminders: ≥ 25% action rate in beta (telemetry) or the trigger is retuned.
- [ ] Every automation action appears in the Activity log and is undoable.

## 8. Tickets
`AI-401` Trigger engine + catalogue · `AI-402` Nudge ranker + fatigue model · `AI-403` Copy prompt + templates + banned-phrase check · `AI-404` Scheduler (calendar triggers, BGAppRefresh, BGProcessing) · `AI-405` Notification categories/actions · `AI-406` Autopilot settings data + Activity log · `AI-407` Simulation harness.
