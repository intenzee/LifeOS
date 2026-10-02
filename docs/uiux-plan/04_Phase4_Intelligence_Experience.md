# Phase 4: Intelligence Experience

**Weeks:** 10–16
**Owners:** product designer (lead), motion/3D designer (assistant orb, weekly review), iOS UI engineer
**Depends on:** Phase 2 components (AI proposal card, confidence indicator, source badge), and the engineering AI core (on-device model, router, memory store, automation engine).

This phase designs how LifeOS's intelligence appears to the user: an assistant that knows their context, a memory they can see and control, insights worth reading, and automations that run in the background without becoming noise. Every AI moment must feel like a discreet personal concierge: brief, specific, and always under the user's control.

---

## 1. Outcomes and success measures

| Outcome | Measure (two weeks of your own daily use) |
| --- | --- |
| You trust the assistant's answers | For any answer you can tell, in one look, where its numbers came from |
| Memory feels safe | You can find and delete a specific memory in under 30 s |
| Insights are worth reading | You open the weekly review both Sundays; you find at least one insight per week useful |
| Automations help, not nag | After two weeks you have not turned any automation off out of annoyance |

---

## 2. Trust patterns (apply to every AI surface)

1. **Show the source.** Every AI answer carries a badge: "On device", "Groq" or "Gemini" (the free key you added), plus a "Based on" line ("your last 14 days of meals").
2. **Propose, then act.** AI never writes data silently. It shows a proposal card (Phase 2, component 24) with Log, Edit, Cancel. The only exception is an automation the user explicitly set to auto-log, and even then a notification offers Undo.
3. **Say how sure it is.** Confidence appears in words ("Check the rice portion"), not percentages.
4. **Make memory visible.** When an answer used stored memories, show "Used 2 things I know about you", expandable.
5. **Easy to correct.** Every AI output has an edit path within one tap.
6. **Stay in its lane.** No diagnoses, no medication advice, no budgets below safe floors. When asked, the assistant says so kindly and suggests a professional.

---

## 4.1 Assistant

### Entry points

| Entry | Behaviour |
| --- | --- |
| Long-press the Capture button | Opens the assistant listening (voice) |
| "Ask" chip on Today and other headers | Opens with the current screen as context ("Looking at: Today, 3 Oct") |
| Capture sheet → Ask | Switches mode in place |
| Siri ("Ask LifeOS…") | Answers in Siri's UI; "Open in LifeOS" for detail (Phase 5) |

### Layout

- A `.large` sheet over the current screen, so the user keeps their place.
- Top: context chip (removable), conversation history button, close.
- Middle: conversation. Assistant messages are left-aligned without bubbles, in `font.body`; user messages are right-aligned in a subtle surface.
- Bottom: Liquid Glass input bar with a microphone, text field and send; above it, 2–3 suggestion chips that change with context ("How's my protein this week?", "Plan dinner under 600 kcal", "Why is my budget higher today?").

### Response types

| Type | Example | Design |
| --- | --- | --- |
| Short answer | "You've averaged 96 g protein this week, 24 g under target." | Answer first, one sentence; "Based on" line; source badge |
| Data card | Protein over 14 days | Mini Swift Charts card, tap to open full view |
| List card | "Your three most frequent dinners" | List rows with Log buttons |
| Action proposal | "Log 2 eggs and toast as breakfast?" | Proposal card with Log / Edit |
| Automation proposal | "Remind me to drink water every 2 hours" | Rule preview card (4.4) with Turn on / Edit |
| Memory confirmation | "Got it, you're vegetarian." | Inline chip "Remembered · Undo" |
| Safety redirect | User asks for an 800 kcal/day plan | Kind refusal, safe-floor explanation, suggests a professional |

### States

- **Listening:** the assistant orb ripples with voice level; live transcript.
- **Thinking:** orb breathes; after 1.5 s show the step in words ("Checking your workouts…", "Looking at last week's meals…").
- **Streaming:** text appears in phrases, not letter by letter. VoiceOver announces the full answer when complete.
- **Needs confirmation:** proposal card pinned above the input bar until answered.
- **Error / offline / daily cloud quota reached:** plain message, and the assistant continues with on-device ability where possible ("I'm offline, so this uses on-device analysis only.").

### The assistant orb

- A 32 pt (input bar) and 120 pt (empty conversation) version of the Life Orb material, tinted with `color.accent.primary`.
- Built as a 2D shader (`MeshGradient` + Metal `layerEffect`) for performance, matching the 3D orb's look.
- Inputs: `audioLevel` (listening), `phase` (idle / thinking / speaking).
- Reduce Motion: static orb with a small activity indicator.

### Voice and tone

| Do | Don't |
| --- | --- |
| "You're 640 under. A 450 kcal dinner keeps you on track." | "Great question! Let me help you with that!" |
| "Saturdays run about 600 kcal higher than weekdays." | "You always overeat on weekends." |
| "I can't advise on medication. Your doctor is the right person for that." | Long legal disclaimers on every answer |

---

## 4.2 Memory: "What LifeOS knows"

Located in You → "What LifeOS knows". It replaces and absorbs today's "Learned Corrections" screen (`LearnedCorrectionsView.swift`) as one category.

### Structure

| Category | Examples | Source label |
| --- | --- | --- |
| About you | "Vegetarian", "Trains at 7 am on weekdays" | "You said" |
| Food habits | "Usual breakfast is 2 eggs and toast" | "From your logs" |
| Preferences | "Prefers short answers", "No notifications after 9 pm" | "You said" |
| Routines | "Gym Mon, Wed, Fri" | "From your logs" |
| Insights | "Weekend intake ~600 kcal higher" | "Learned from 6 weeks of data" |
| Photo corrections | Thumbnail + corrected meal (existing feature) | "Your correction" |

### Memory row

- Text in plain language, source label, date learned, a quiet confidence word for inferred items ("likely").
- Swipe actions: Edit, Forget. Long-press: Pin ("Always remember").
- Tap: detail sheet with "Used in 4 answers" and links to them.

### Controls

- Toggle at top: "Learn from my activity". Off = only things the user explicitly says are remembered.
- "Forget everything": two-step confirmation and a summary of what will be removed.
- Privacy line: "Memories stay on this iPhone. Cloud AI only sees what a specific answer needs." Memories are included in the backup file (Phase 5), so a reinstall never loses them.

### Moments where memory appears

- In conversation: "Remembered · Undo" chip.
- In answers: "Used 2 things I know about you" (expandable list).
- In Capture: preset suggestions show why ("You usually log this at 8 am").

---

## 4.3 Insights and briefs

### Morning brief (Today → Next up card)

One line + one action, generated overnight. Examples: "Big training day: budget +300 after your 7 am session. Log 'Pre-workout'?" Hidden on days with nothing useful to say.

### Evening recap (notification + card)

At the user's chosen time: "Today: 1,840 of 1,920 kcal, 118 g protein, 9 glasses. Perfect day kept." Tapping opens a short summary card.

### Weekly review (Sunday)

A full-screen story of 4–6 pages, swiped horizontally:

1. **The week in one line**, with the Life Orb shown at the week's average fill.
2. **Numbers:** average intake vs budget, protein, workouts, active energy, sleep. One chart per page, max.
3. **Best day** and why.
4. **One pattern found** (an insight card) with its evidence chart.
5. **Next week's focus:** one suggestion with "Set as goal" or "Create reminder".

Motion: orb transitions between pages (`motion.spring.gentle`). Reduce Motion: cross-fades.

### Insight card anatomy

- Claim (one sentence, `font.headline`).
- Evidence (mini chart or 2–3 numbers) with the time range.
- One action (button) and "Not useful" (feeds back to the AI team).
- Source badge and "Learned from N weeks of data".

---

## 4.4 Automations

### Automations home (You → Automations)

- **Active:** cards with name, a one-sentence summary ("Every weekday at 8:00 · suggest Usual breakfast"), on/off toggle, "Ran 4 times this week".
- **Suggested by LifeOS:** templates based on the user's habits, each with a "Turn on" button.
- **Gallery:** all templates by category: Food, Training, Water, Sleep, Weight, Focus.

### Starter templates

| Template | Sentence shown |
| --- | --- |
| Morning brief | Every day at 7:30, show my morning brief |
| Usual breakfast | On weekdays at 8:00, suggest my usual breakfast |
| Water nudge | If I've had under 4 glasses by 2 pm, remind me |
| After a workout | When an Apple Watch workout ends, show what it added to my budget |
| Protein check | At 7 pm, if protein is under 80% of target, suggest a high-protein dinner |
| Weigh-in | Every Monday at 7:00, remind me to weigh in |
| Evening recap | Every day at 9:30 pm, summarise my day |
| Weekly review | Every Sunday at 6 pm, prepare my weekly review |

### Builder

A sentence builder with three slots, each a tappable token:

> **When** [an Apple Watch workout ends] **if** [protein is under 100 g] **then** [suggest my "Protein shake" preset].

- **When:** time, day, workout ended, meal logged, weight logged, water below target by a time, arrived at a place (optional, needs location permission).
- **If (optional):** conditions on calories, protein, water, workouts, streak.
- **Then:** notify, suggest a preset, log a preset (with Undo), create a todo, start rest timer, show summary.
- Preview before saving: "Here's how this would have run last week: 3 times."

You can also describe a rule to the assistant; it returns a rule preview card using the same sentence format.

### Notifications

- Actionable: "Log it", "Not now", "Edit". Logging from the notification shows the item and kcal.
- Limits: at most 4 LifeOS notifications per day by default; quiet hours default 10 pm–7 am; both editable.
- Each notification links to "Why am I seeing this?" → the automation that fired, with a toggle to turn it off.

---

## 4.5 AI and privacy settings

Located in You → Settings → AI and privacy.

| Section | Content |
| --- | --- |
| Where AI runs | On device (always on if your iPhone supports Apple Intelligence; otherwise shows "Not available on this iPhone"), Groq (toggle), Gemini (toggle) |
| Free keys | Paste a free Groq or Gemini key, stored in the Keychain (as `AIKeyStore` already does); "Get a free key" help card with steps; Test key button |
| Today's free usage | Simple meter per service ("Groq: 112 of 1,000 requests today"); when a limit is reached, LifeOS switches to on-device estimates until tomorrow |
| What is shared | Per feature: "Photo estimates send the photo only; no name or health history" |
| Gemini note | "Google may use content sent on the free tier to improve its products. Health questions are only sent to Gemini if you turn this on." Separate toggle |
| Memory | Link to "What LifeOS knows" |

Every statement on this screen must be checked against the actual build, so it stays true.

---

## 5. Weekly plan

| Week | Product designer | Motion/3D designer | iOS UI engineer |
| --- | --- | --- | --- |
| 10 | Assistant flows, response types | Assistant orb shader concepts | Assistant sheet shell |
| 11 | Assistant states, tone guide | Orb listening/thinking states | Streaming, data cards |
| 12 | Memory screens | Memory "remembered" micro-interaction | Proposal and memory chips |
| 13 | Insights cards, morning brief, evening recap | Weekly review transitions | Memory screen |
| 14 | Weekly review pages | Weekly review polish | Insight cards, weekly review |
| 15 | Automations home, gallery, builder | Builder token animations | Automations UI |
| 16 | Notifications, AI and privacy settings; start two weeks of daily use | Polish | Notification categories; install from Xcode for daily use |

## 6. Deliverables checklist

- [ ] Assistant: all entry points, response types, states, tone guide
- [ ] Assistant orb: shader spec and states, Reduce Motion version
- [ ] Memory screens, row and detail, controls, in-conversation moments
- [ ] Morning brief, evening recap, weekly review (all pages), insight card
- [ ] Automations home, gallery, builder, rule preview card, notifications
- [ ] AI and privacy settings with engineering-verified copy
- [ ] Daily-use notes with fixes
