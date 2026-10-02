# Phase 4 — Automation & Ambient AI (Weeks 19–22) → Release Candidate

**Goal:** LifeOS works when the app is closed — well-timed nudges, opt-in autopilot, and logging through Siri, widgets and the Watch.

## Scope
| In | Out |
|---|---|
| F09 triggers, ranking, copy, scheduling, notification actions, Autopilot settings + Activity log | New trigger types beyond the v1 catalogue |
| F03 remind/auto-log policies switched on (opt-in) | |
| F10 App Intents, App Shortcuts, widgets/controls, Watch quick-log + offline queue | |

## Entry criteria
- Phase 3 exit met.
- C4 Watch message types and C5 App Intents/widget plumbing delivered.
- Design: notification copy guidelines, widget and complication specs, Autopilot settings.

## Sprint plan
| Sprint | Weeks | Engineer A | Engineer B | QA |
|---|---|---|---|---|
| 9 | 19–20 | App Intents + entities + phrases; widgets & controls | Trigger engine + catalogue; scheduler; notification categories | Nudge simulation harness (90 days × 50 profiles) |
| 10 | 21–22 | Watch quick-log, presets digest, offline queue (with Watch team) | Ranker + fatigue model; copy prompt + templates; Autopilot + Activity log; preset remind/auto-log | Siri phrase scripts; Watch E2E; RC regression |

## Exit criteria
- [ ] Daily notification cap and quiet hours hold in 100% of simulations.
- [ ] Siri preset logging ≤ 3 s; Watch dictation result ≤ 5 s with phone reachable.
- [ ] Every automation is opt-in where specified, logged in Activity, and undoable.
- [ ] **Release Candidate** build.
