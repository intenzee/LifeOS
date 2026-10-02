# Phase 1 · Rubric and decision record (gate D1)

**Status: recommendation made; awaiting the owner's decision at gate D1.**
Until then the app keeps **Aurora Glass**, today's look, as the default. Any direction can be switched on live in Settings → Direction Lab.

## 1. Rubric (Phase 1 §6)

Scores are 1–7.
- ✅ **Measured:** the score comes from automated checks or the spike.
- ⏳ **Provisional:** the team's estimate. The owner replaces it after a day with each direction on the phone.

| Criterion | Weight | Obsidian | Porcelain | Aurora | Basis |
|---|---|---|---|---|---|
| Feels premium to you | 25% | 6 ⏳ | 5 ⏳ | 4 ⏳ | Team critique (03-directions §3). **Owner to rate** |
| Clarity of the main number | 20% | 6 ⏳ | 7 ⏳ | 6 ⏳ | Same layout in all three; Porcelain has the highest contrast in daylight. **Owner 5-second test** |
| Distinctiveness | 15% | 6 ⏳ | 6 ⏳ | 3 ⏳ | The plan itself rates Aurora least distinctive. **Owner to confirm** |
| Data readability | 15% | 6 ✅ | 6 ✅ | 6 ✅ | Shared data palette: all ≥ 4.5:1 and pass colour-blindness ΔE. **Owner: find protein in < 3 s** |
| Feasibility and performance | 15% | 6 ✅ | 6 ✅ | 7 ✅ | Same code path. Aurora needs no new type face and is nearest the current UI. Orb p95 2.3 ms (Mac proxy) for all |
| Accessibility | 10% | 6 ✅ | 5 ✅ | 5 ✅ | All pass the contrast rules. Porcelain's secondary text sits at the 4.9:1 floor. Aurora leans hardest on glass (Reduce Transparency fallback) |
| **Weighted** | | **6.00** | **5.85** | **5.10** | |

**Weighted arithmetic:**
- Obsidian: 6·.25 + 6·.2 + 6·.15 + 6·.15 + 6·.15 + 6·.1 = 6.00
- Porcelain: 5·.25 + 7·.2 + 6·.15 + 6·.15 + 6·.15 + 5·.1 = 5.85
- Aurora: 4·.25 + 6·.2 + 3·.15 + 6·.15 + 7·.15 + 5·.1 = 5.10

## 2. Recommendation: Obsidian & Champagne, with a Porcelain-grade light mode

What comes from where, as Phase 1 §6 asks for any hybrid:

| Part | From | Why |
|---|---|---|
| Dark palette, champagne accent, hairline cards | Obsidian | The strongest "private members' club" read; accent stays rare |
| New York serif for display and numbers | Obsidian / Porcelain | Both serif directions out-score rounded on premium and distinctiveness |
| Light-mode treatment: ivory paper cards, soft shadows, calm gradient | Porcelain | Obsidian's own light mode is already ivory and brass; Phase 2 should push it to Porcelain's editorial quality, since light mode matters outdoors |
| Liquid Glass limited to controls | Obsidian | Least Reduce Transparency risk; follows Apple's "glass for the control layer" |
| Orb liquid: gold in dark, brass in light | Obsidian | Ties the hero to the accent |
| Motion: no bounce, weighty springs | Obsidian | Matches "slow, weighty, precise"; `celebrate` keeps a small bounce for rare moments |

**Risk to manage** (from the plan): champagne must stay under 5% of any screen. Concretely:
- Phase 2 adds a lint check.
- The accent stays off energy and data UI, where it would be confused with `data.energy` amber.

**What would change the recommendation:** if, after a day with each direction, the owner rates Porcelain or Aurora ≥ 1 point higher on "feels premium", the weighted totals flip. The owner's rating overrides the team's.

## 3. Owner sign-off

| | |
|---|---|
| Direction chosen | ________________________ |
| Parts taken from other directions | ________________________ |
| Rejected, and why | ________________________ |
| Date (gate D1, planned Mon 26 Oct 2026) | ________________________ |

After sign-off, the follow-up steps are:
1. Set the default in `LXDirectionPreference` / `LXDirectionKey`.
2. Delete the losing direction files from `design/tokens/directions/`, or keep them as archived references.
3. Regenerate the tokens.

The Phase 2 colour and type values come from the winning file.

## 4. Gate D1 checklist

- [ ] One direction chosen and signed above
- [ ] Moodboard (the boards here), hero screen and Life Orb concept approved by the owner
- [ ] The Life Orb runs at the display frame rate on the owner's iPhone (04-spike-report §4)
- [ ] Usage-diary synthesis done (02-research-kit §3)
