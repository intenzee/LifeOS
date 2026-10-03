# Phase 3 — Assistant & Coaching (Weeks 14–18) → Beta 3

> **Status (3 Oct 2026):** assistant engine (safety, 17 tools, grounding, memory, context) implemented under UI/UX's Phase 4 assistant screens; see [`../phase-2-3/PHASE-2-3-REPORT.md`](../phase-2-3/PHASE-2-3-REPORT.md).

**Goal:** a private concierge the user can talk to, which acts through tools, answers from their own data and coaches without preaching.

## Scope
| In | Out |
|---|---|
| F07 assistant: session manager, 13 tools, persona, streaming, summarise/escalate, deterministic fallback, safety flows | Siri/Watch voice (Phase 4) |
| Daily briefing, post-workout card, weekly review | Proactive notifications (Phase 4) |
| `AssistantVisualState` for Design's 3D/motion assistant (C9) | |
| Adaptive TDEE suggestions enabled for beta users | |

## Entry criteria
- Phase 2 exit met.
- Design: assistant surface, tool-action cards, orb motion spec (C6/C9).
- Safety policy reviewed by AI Lead + product (and, ideally, a qualified nutrition advisor) — F11 §5.

## Sprint plan
| Sprint | Weeks | Engineer A | Engineer B | QA |
|---|---|---|---|---|
| 6 | 14–15 | Food tools (`logFood`, `logPreset`, presets), `explainBudget`, `queryStats` | Session manager, instructions, streaming + visual state, summarise/escalate | Tool-call set (400 turns) |
| 7 | 16–17 | Daily briefing, post-workout card, weekly review (deterministic stats → model prose) | Remaining tools (water, weight, todos, reminders, memory); deterministic fallback router | Grounding Q&A set; red-team v1 |
| 8 | 18 | Polish, latency tuning, prewarm | Safety flows, guardrail handling, conversation retention settings | Full eval + beta feedback triage |

## Exit criteria
- [ ] Tool accuracy ≥ 93% (1.0 bar 95%); zero hallucinated numbers on grounding set.
- [ ] All red-team critical cases pass.
- [ ] First-token p50 ≤ 1.2 s on T1.
- [ ] TestFlight **Beta 3**.

## Demo script
"How did I do this week?" → "What should I have for dinner with 600 left?" → "Log the second one" → "Remind me to drink water every two hours until 6" → "Why is my target higher today?" → show orb states throughout.
