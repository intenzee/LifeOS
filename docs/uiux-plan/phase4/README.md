# UI/UX Phase 4: Intelligence Experience (first build)

This build implements the [Phase 4 plan](../04_Phase4_Intelligence_Experience.md) on top of the Phase 3 shell. The main rule: **answer from the user's own data on the iPhone first.** A model is used only for open questions, and only when a provider is available. On an iPhone without Apple Intelligence (e.g. the iPhone 15), the assistant, memory, insights and automations still work fully. Only free-form chat needs Gemini with health consent.

## What's built

| # | Surface | Status | Where |
|---|---|---|---|
| 4.1 | Assistant | Done. Long-press Capture (opens listening), the Ask chip on Today (context chip "Looking at: Today, 3 Oct"), and "Ask LifeOS instead" in Capture. Orb with idle/listening/thinking/speaking states; the step text appears after 1.5 s; text reveals phrase by phrase. Answers show a source badge, a "Based on …" line and "Used N things I know about you". Inline cards: chart, list with Log buttons, log proposal (the same card as Capture), rule preview, remembered/forgotten. Under 1,200 kcal/day and medical questions get a safety redirect | `Views/Assistant/`, `Adapters/AssistantSession.swift`, `Core/AssistantBrain.swift` |
| 4.2 | Memory ("What LifeOS knows") | Done. Sections About you, Food habits, Preferences, Routines, Insights and Photo corrections. Each item shows its source (You said / From your logs / Learned / Correction) and confidence. Swipe Forget/Edit, Pin, search, a "Learn from my activity" switch, and a two-step "Forget everything" with a summary | `Views/Intelligence/MemoryScreen.swift`, `Core/MemoryModel.swift` |
| 4.3 | Insights + weekly review | Done. Morning brief (before noon) and evening recap (from 19:00) on Today; weekly review card on Sun/Mon and in You → Weekly review. Full-screen 4–5 page story: one line, numbers + chart, best day, one pattern, next week's focus with "Create reminder". Insight cards have claim, evidence, range, source and "Not useful" | `Views/Intelligence/WeeklyReviewView.swift`, `Core/InsightsModel.swift` |
| 4.4 | Automations | Done. 8 templates, Suggested ("Because: …"), a When/If/Then builder with a backtest ("would have run N times last week"), plain-sentence rules ("remind me to drink water every 2 hours"), quiet hours (22–7), a daily cap of 4, and "Ran N times this week". Notifications have Log it / Not now / Why am I seeing this? actions; "when I log …" rules show an in-app banner | `Views/Intelligence/AutomationsScreen.swift`, `Core/AutomationModel.swift`, `Adapters/IntelligenceStore.swift`, `Adapters/ExperienceNotifications.swift` |
| 4.5 | AI and privacy | Done. Live on-device availability, Groq/Gemini switches, free-key entry in the Keychain with **Test key**, today's free usage per provider (and the pause after errors), "What is shared" per feature, and a separate "Allow health questions to Gemini" switch | `Views/Intelligence/AIPrivacyScreen.swift` |

Entry points are in You: What LifeOS knows, Automations, AI and privacy, and Weekly review.

## How it fits together

```
LifeOS/Experience/
  Core/                         pure Swift, unit-tested (LifeOSExperienceTests)
    IntelligenceFacts.swift     DayFacts + IntelligenceSnapshot (28 days), formatting
    AssistantBrain.swift        intent → reply from data; needsModel for the rest
    MemoryModel.swift           "remember that …" phrasing, inference from logs
    InsightsModel.swift         briefs, recap, weekly review, insight cards
    AutomationModel.swift       rules, templates, parser, planner (quiet hours, cap), backtest
  Adapters/
    ExperienceStore+Intelligence.swift   builds the snapshot from the existing managers
    IntelligenceStore.swift     memories + rules (JSON in Application Support), notification planning
    ExperienceNotifications.swift  the app's single notification delegate (a router, see below)
    AssistantSession.swift      conversation state; AIGateway assistantChat stream for open questions
  Views/Assistant, Views/Intelligence
```

**Notifications.** Rules become local `UNCalendarNotificationTrigger` requests (`lx.auto.<rule>.<stamp>`), planned 7 days ahead and re-planned after every change. A conditional rule (e.g. "if under 4 glasses") is dropped for today once its condition is met. `ExperienceNotifications` is the only `UNUserNotificationCenter` delegate. Other features call `register(categoryPrefix:categories:handler:)`, and categories are merged by identifier rather than overwritten. The engineering roadmap's AUTO-03 relies on this contract.

**Privacy.** Memory inference, insights and rule planning run only on the iPhone. The assistant's open questions send a short summary (recent days + memories) with privacy class `.health`. The gateway allows that only to Apple on-device / PCC, or to Gemini when the health switch is on.

**Tests:** `cd Packages/LifeOSDesign && swift test --filter LifeOSExperienceTests` runs 32 tests, 16 of them new. They cover intent routing, the safety redirect ("plan dinner under 800 kcal" is *not* redirected), remember/forget phrasing, usual-meal / gym-day / weekend inference (today's partial day excluded), recap and weekly review, the rule parser, quiet hours, the daily cap, condition skipping and the backtest.

## Decisions and known gaps

- **No Apple Intelligence on the test iPhone.** Everything except free-form chat is rule-based and on-device by design. Free-form chat explains what it needs when no provider is available.
- **Budget** still uses the classic formula (as Home and the Watch do). Switching to `CalorieEngine` (CAL-07, now on main) is the next follow-up.
- **Event triggers** ("when I log a workout") fire in-app from snapshot changes, not in the background.
- **Not yet built:**
  - Voice replies (text-to-speech).
  - Assistant conversation history across launches.
  - Insight cards in Nutrition/Training (they exist only in the weekly review).
  - A Watch surface for automations.
