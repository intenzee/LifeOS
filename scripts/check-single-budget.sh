#!/usr/bin/env bash
# CAL-03: the daily calorie budget has one source, the calorie engine
# (LifeOSCore CalorieEngine → LifeOSData BudgetService → EnergyDay.budgetKcal,
# read in the app through HealthSync.budget(on:)). This fails if app code
# rebuilds the old "limit + burned × eat-back %" formula on its own.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The legacy eat-back key may only be read where it is migrated into EnergySettings.
allowed='^(LifeOS/Managers/CalorieSettings\.swift|LifeOS/App/HealthSync\.swift):'
hits=$(grep -rn --include='*.swift' 'loadPercentage()' LifeOS "LifeOS Watch App" | grep -Ev "$allowed" || true)
# Adding to the stored limit is the duplicated formula (HomeViewModel / makeSnapshot before P1).
hits+=$(grep -rnE --include='*.swift' 'loadLimit\(\) *\+' LifeOS "LifeOS Watch App" || true)

if [[ -n "$hits" ]]; then
  echo "::error::Budget maths outside the calorie engine (CAL-03). Read HealthSync.budget(on:) instead:"
  echo "$hits"
  exit 1
fi
echo "Single budget source: OK"
