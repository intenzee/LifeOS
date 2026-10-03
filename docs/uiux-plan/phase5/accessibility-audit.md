# Phase 5 accessibility audit (first pass)

This audit covers the new experience: `LifeOS/Experience/Views/**` and the design system it uses, against the [Phase 5 §7 checklist](../05_Phase5_Ecosystem_Polish_Launch.md#7-accessibility-audit-checklist). It was done by reading the code. The **On device** column lists what still needs a hands-on pass on the iPhone (VoiceOver, Accessibility Inspector, Settings → Accessibility toggles) before gate D3.

Legend: ✅ passes in code · 🔧 fixed in this pass · 📱 verify on device · ⏳ open

## Vision

| Check | Status | Notes |
|---|---|---|
| Contrast (body ≥ 4.5:1, large text/icons ≥ 3:1, light + dark) | ✅ 📱 | Token pairs are checked by `design/tools/gen_tokens.py --check` (Phase 2). 🔧 The medal earning-moment scrim went from 55% to 65% black, so white body text stays above 4.5:1 even over a white screen. |
| Largest accessibility text size, no truncated key numbers | 🔧 📱 | Tile grids reflow to one column at accessibility sizes: Today metrics, You streaks, You weight tiles, Training Health tiles, the Nutrition legend and the medal buttons (`LXTileRow`, `DynamicTypeSize.lxColumns`). Capture's 5 modes become 2 columns. The Today hero number already scales down to 60% within one line. |
| Bold Text, Increase Contrast, Reduce Transparency | ✅ 📱 | Glass surfaces and the orb follow `accessibilityReduceTransparency` and `colorSchemeContrast` in the design system. 🔧 The earning-moment scrim goes opaque with Reduce Transparency. |
| Colour is never the only signal | ✅ | Budget status has words ("over", "left"). The heat map has a legend and per-day labels. The over-budget bars in the weekly review have a dashed budget line plus the numbers on the page. |
| Colour-blind simulation for data colours | ✅ 📱 | CVD checks run in the token generator. Confirm once with Accessibility Inspector on the device. |

## VoiceOver

| Check | Status | Notes |
|---|---|---|
| Every control labelled | ✅ | Icon buttons use `LXIconButton(label:)` or `.accessibilityLabel` (Ask chip, mic, send, context chip, close review). |
| Reading order; orb reads as one element | ✅ 📱 | The Today hero is one element: "Remaining calories, 640. Budget 1,920, including 222 earned from activity." |
| Charts have a summary | ✅ 🔧 | Assistant chart, weekly review bars and heat-map days were already labelled. 🔧 Insight-card evidence charts now read "Weekdays: 1,820 kilocalories, Weekends: 2,310 kilocalories". |
| Streaming AI answers announced once complete | ✅ | `AssistantSheet` posts one announcement when the answer settles; partial text is hidden from VoiceOver until then. |
| Custom actions instead of swipe-only | ✅ 🔧 | Nutrition rows have Delete; Memory rows have Forget and Pin, and 🔧 now Edit too. The Achievements tiles are single buttons with a hint. |
| Modals announce themselves | 🔧 | The medal earning moment is `.isModal`, announces "New medal: …", and its tap-to-dismiss scrim is hidden from VoiceOver (Done is the accessible exit). |

## Motion and interaction

| Check | Status | Notes |
|---|---|---|
| Reduce Motion: no parallax, zoom or orb motion | ✅ | Every animation goes through `LXMotion`, which becomes a cross-fade. The assistant orb shows a static orb plus a spinner. The weekly review pages cross-fade. The medal drops in normally but only fades with Reduce Motion, and the 3D medal's idle spin is off. |
| Every haptic has a visible counterpart | ✅ | Logged → toast; water → count changes; medal → the earning moment. |
| Touch targets ≥ 44 × 44 pt | ✅ 📱 | Rows use `LX.Space.minTouchTarget` / 52 pt. The 28 pt step numbers in Refresh help are decorative and hidden from VoiceOver. |
| Voice features have a typed alternative | ✅ | Capture has Say and Type; the assistant has a text field; Siri intents are also Shortcuts actions. |

## Still open (📱 / ⏳)

1. A full VoiceOver walk-through on the iPhone for Today → Capture → Proposal → Log, the assistant, Memory, Automations, and Data and backup.
2. Accessibility Inspector audit and the colour-blind filters on the device.
3. ⏳ Widgets, Lock Screen, Live Activities and the Watch: audit them when they are built (Phase 5 §3, §4, §2).
4. ⏳ The classic screens (photo, barcode, search, gym sheet), which are still reused from before Phase 3: audit them when they're redesigned.
