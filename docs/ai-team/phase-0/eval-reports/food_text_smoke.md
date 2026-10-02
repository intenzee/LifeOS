## Food-text smoke eval (`food_text_smoke.jsonl`, prompt 2026.10.1)

| Tier | Status | Item F1 | Precision | Recall | Meal type | Non-food | Preset | p50 | p95 | Errors | Bar |
|---|---|---|---|---|---|---|---|---|---|---|---|
| deterministic | ran | **100.0%** | 100.0% | 100.0% | 81.8% | 100.0% | 100.0% | 2 ms | 3 ms | 0 | ✅ 80.0% |
| appleOnDevice | ran | **57.4%** | 100.0% | 40.2% | 36.4% | 0.0% | 0.0% | 14968 ms | 31395 ms | 30 | ❌ 92.0% |
| applePCC | ran | **0.0%** | 100.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0 ms | 0 ms | 50 | ❌ 92.0% |
| geminiBYOK | skipped: consentRequired | — | — | — | — | — | — | — | — | — | 92.0% |
| groqBYOK | skipped: consentRequired | — | — | — | — | — | — | — | — | — | 92.0% |

<details><summary>appleOnDevice: 31 imperfect case(s)</summary>

| Case | Category | Predicted | Missed | Extra | Error |
|---|---|---|---|---|---|
| ft-003 | indian |  | masala dosa; filter coffee |  | appleOnDevice:timeout |
| ft-004 | indian |  | poha |  | appleOnDevice:timeout |
| ft-005 | indian | 2 piece paratha; 1 glass lassi | 1 butter |  |  |
| ft-019 | indian |  | egg curry; roti |  | appleOnDevice:timeout |
| ft-023 | indian |  | kheer |  | appleOnDevice:timeout |
| ft-025 | indian |  | fish curry; rice |  | appleOnDevice:timeout |
| ft-026 | hinglish |  | roti; dal |  | appleOnDevice:timeout |
| ft-027 | hinglish |  | idli; chutney |  | appleOnDevice:timeout |
| ft-028 | hinglish |  | maggi; chai |  | appleOnDevice:circuitOpen |
| ft-029 | hinglish |  | rajma chawal; salad |  | appleOnDevice:circuitOpen |
| ft-030 | hinglish |  | anda bhurji; toast |  | appleOnDevice:circuitOpen |
| ft-031 | hinglish |  | doodh |  | appleOnDevice:circuitOpen |
| ft-032 | hinglish |  | khichdi |  | appleOnDevice:circuitOpen |
| ft-033 | hinglish |  | biscuit; chai |  | appleOnDevice:circuitOpen |
| ft-034 | hinglish |  | banana; almond |  | appleOnDevice:circuitOpen |
| ft-035 | hinglish |  | paneer paratha; dahi |  | appleOnDevice:circuitOpen |
| ft-036 | western |  | scrambled egg; toast; black coffee |  | appleOnDevice:circuitOpen |
| ft-037 | western |  | chicken caesar salad |  | appleOnDevice:circuitOpen |
| ft-038 | western |  | latte; blueberry muffin |  | appleOnDevice:circuitOpen |
| ft-039 | western |  | pepperoni pizza |  | appleOnDevice:circuitOpen |
| ft-040 | western |  | oatmeal; banana; peanut butter |  | appleOnDevice:circuitOpen |
| ft-041 | western |  | grilled chicken breast; steamed broccoli |  | appleOnDevice:circuitOpen |
| ft-042 | western |  | whey protein; milk |  | appleOnDevice:circuitOpen |
| ft-043 | branded |  | coke zero |  | appleOnDevice:circuitOpen |
| ft-044 | branded |  | mcaloo tikki burger; fries |  | appleOnDevice:circuitOpen |
| ft-045 | branded |  | parle-g biscuit; tea |  | appleOnDevice:circuitOpen |
| ft-046 | branded |  | amul cheese slice; sandwich |  | appleOnDevice:circuitOpen |
| ft-047 | branded |  | caramel frappuccino |  | appleOnDevice:circuitOpen |
| ft-048 | edge |  |  |  | appleOnDevice:circuitOpen |
| ft-049 | edge |  |  |  | appleOnDevice:circuitOpen |
| ft-050 | edge |  |  |  | appleOnDevice:circuitOpen |

</details>

<details><summary>applePCC: 50 imperfect case(s)</summary>

| Case | Category | Predicted | Missed | Extra | Error |
|---|---|---|---|---|---|
| ft-001 | indian |  | roti; dal; curd |  | applePCC:server.-1 |
| ft-002 | indian |  | idli; sambar |  | applePCC:server.-1 |
| ft-003 | indian |  | masala dosa; filter coffee |  | applePCC:server.-1 |
| ft-004 | indian |  | poha |  | applePCC:circuitOpen |
| ft-005 | indian |  | aloo paratha; butter; lassi |  | applePCC:circuitOpen |
| ft-006 | indian |  | rajma chawal |  | applePCC:circuitOpen |
| ft-007 | indian |  | samosa; masala chai |  | applePCC:circuitOpen |
| ft-008 | indian |  | chole; bhatura |  | applePCC:circuitOpen |
| ft-009 | indian |  | palak paneer; jeera rice; cucumber raita |  | applePCC:circuitOpen |
| ft-010 | indian |  | chicken tikka |  | applePCC:circuitOpen |
| ft-011 | indian |  | paneer bhurji |  | applePCC:circuitOpen |
| ft-012 | indian |  | gulab jamun |  | applePCC:circuitOpen |
| ft-013 | indian |  | khichdi; papad |  | applePCC:circuitOpen |
| ft-014 | indian |  | upma; coconut chutney |  | applePCC:circuitOpen |
| ft-015 | indian |  | methi thepla |  | applePCC:circuitOpen |
| ft-016 | indian |  | chicken biryani |  | applePCC:circuitOpen |
| ft-017 | indian |  | pav bhaji |  | applePCC:circuitOpen |
| ft-018 | indian |  | veg pulao |  | applePCC:circuitOpen |
| ft-019 | indian |  | egg curry; roti |  | applePCC:circuitOpen |
| ft-020 | indian |  | nimbu pani |  | applePCC:circuitOpen |
| ft-021 | indian |  | medu vada; sambar |  | applePCC:circuitOpen |
| ft-022 | indian |  | sprouts salad |  | applePCC:circuitOpen |
| ft-023 | indian |  | kheer |  | applePCC:circuitOpen |
| ft-024 | indian |  | dhokla; green chutney |  | applePCC:circuitOpen |
| ft-025 | indian |  | fish curry; rice |  | applePCC:circuitOpen |
| ft-026 | hinglish |  | roti; dal |  | applePCC:circuitOpen |
| ft-027 | hinglish |  | idli; chutney |  | applePCC:circuitOpen |
| ft-028 | hinglish |  | maggi; chai |  | applePCC:circuitOpen |
| ft-029 | hinglish |  | rajma chawal; salad |  | applePCC:circuitOpen |
| ft-030 | hinglish |  | anda bhurji; toast |  | applePCC:circuitOpen |
| ft-031 | hinglish |  | doodh |  | applePCC:circuitOpen |
| ft-032 | hinglish |  | khichdi |  | applePCC:circuitOpen |
| ft-033 | hinglish |  | biscuit; chai |  | applePCC:circuitOpen |
| ft-034 | hinglish |  | banana; almond |  | applePCC:circuitOpen |
| ft-035 | hinglish |  | paneer paratha; dahi |  | applePCC:circuitOpen |
| ft-036 | western |  | scrambled egg; toast; black coffee |  | applePCC:circuitOpen |
| ft-037 | western |  | chicken caesar salad |  | applePCC:circuitOpen |
| ft-038 | western |  | latte; blueberry muffin |  | applePCC:circuitOpen |
| ft-039 | western |  | pepperoni pizza |  | applePCC:circuitOpen |
| ft-040 | western |  | oatmeal; banana; peanut butter |  | applePCC:circuitOpen |
| ft-041 | western |  | grilled chicken breast; steamed broccoli |  | applePCC:circuitOpen |
| ft-042 | western |  | whey protein; milk |  | applePCC:circuitOpen |
| ft-043 | branded |  | coke zero |  | applePCC:circuitOpen |
| ft-044 | branded |  | mcaloo tikki burger; fries |  | applePCC:circuitOpen |
| ft-045 | branded |  | parle-g biscuit; tea |  | applePCC:circuitOpen |
| ft-046 | branded |  | amul cheese slice; sandwich |  | applePCC:circuitOpen |
| ft-047 | branded |  | caramel frappuccino |  | applePCC:circuitOpen |
| ft-048 | edge |  |  |  | applePCC:circuitOpen |
| ft-049 | edge |  |  |  | applePCC:circuitOpen |
| ft-050 | edge |  |  |  | applePCC:circuitOpen |

</details>

F1 by category (deterministic): branded 100.0% · edge 100.0% · hinglish 100.0% · indian 100.0% · western 100.0%
