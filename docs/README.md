# LifeOS docs

All planning and status documents, grouped by workstream. Each workstream has:
- a **plan** (the owner's input),
- a **status** or report (what was built and verified),
- a code area (see the repository map in the [root README](../README.md)).

## UI/UX: `uiux-plan/`

| Doc | What it is |
|---|---|
| [00_UIUX_Master_Plan.md](uiux-plan/00_UIUX_Master_Plan.md) | Direction, principles, information architecture, design-system rules, 26-week timeline |
| [01](uiux-plan/01_Phase1_Discovery_and_Direction.md) … [05](uiux-plan/05_Phase5_Ecosystem_Polish_Launch.md) | Phase plans: direction, design system and 3D, core experience, intelligence, ecosystem and launch |
| [phase1/](uiux-plan/phase1/README.md) | **Phase 1 delivered**: audit board (A1–A32), three directions with rendered boards, Life Orb spike report, rubric and decision record (gate D1 awaits the owner) |
| [phase2/](uiux-plan/phase2/README.md) | **Phase 2 status**: 30 components, snapshot tests, gallery, what still needs 3D assets |

## AI: `ai-team/`

| Doc | What it is |
|---|---|
| [00-AI-MASTER-PLAN.md](ai-team/00-AI-MASTER-PLAN.md) | AI vision, architecture and phases |
| [01-current-state-audit.md](ai-team/01-current-state-audit.md), [02-cross-team-contracts.md](ai-team/02-cross-team-contracts.md) | Starting point and interfaces with the other teams |
| [03-ai-module-guide.md](ai-team/03-ai-module-guide.md) | How `LifeOS/AI` works and how to extend it |
| [features/](ai-team/features) | Feature specs F01–F11 |
| [phases/](ai-team/phases) | Phase plans 0–5 |
| [phase-0/PHASE-0-REPORT.md](ai-team/phase-0/PHASE-0-REPORT.md) | **Phase 0 delivered**: gateway, providers, evals (with eval reports) |

## Engineering: `engineering-roadmap/` and `adr/`

| Doc | What it is |
|---|---|
| [00-MASTER-PLAN.md](engineering-roadmap/00-MASTER-PLAN.md) | Engineering master plan |
| `01`–`10` | Squad plans: platform, watch, calorie engine, food logging, assistant, automation, AI backend, premium UI, security, quality and CI |
| [P0-STATUS.md](engineering-roadmap/P0-STATUS.md) | **Phase 0 status**: LifeOSKit, data migration, watch contract |
| [adr/0001-persistence.md](adr/0001-persistence.md), [adr/0002-module-structure.md](adr/0002-module-structure.md) | Architecture decisions |

## Who owns which code

| Area | Owner workstream |
|---|---|
| `Packages/LifeOSKit/`, `LifeOS/Data/`, `LifeOS/App/`, managers, `LaunchGate`, CI, lint | Engineering (platform) |
| `LifeOS/AI/`, root `Package.swift`, `Evals/`, `Tests/`, `Tools/ai-eval/` | AI |
| `LifeOS/DesignSystem/`, `design/`, `Packages/LifeOSDesign/` | UI/UX |

Feature screens in `LifeOS/Views/` are shared. They migrate to the design system screen by screen in UI/UX Phase 3.
