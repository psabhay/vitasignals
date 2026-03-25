# VitaSignals — Metrics Review

Complete audit of every synced metric: sync path, unit handling, and correctness.

## Sync Architecture

Three sync paths exist:

| Path | Method | Used For | Data Source |
|------|--------|----------|-------------|
| **A** | `syncBloodPressure` | Blood Pressure only | `HKCorrelationType(.bloodPressure)` |
| **B** | `syncSleep` | Sleep Duration only | `HKCategoryType(.sleepAnalysis)` |
| **C** | `syncMetric` | All other HealthKit metrics | `HKQuantityType` — branches to `fetchDailyStatistics` (cumulative) or `fetchQuantitySamples` (non-cumulative) |

Date predicate is the sole constraint on all queries (no hard sample limits). Non-cumulative metrics are downsampled to 50 samples/day before storage to bound high-frequency data like heart rate.

---

## Curated Metrics (MetricRegistry.all — take priority over catalog)

### Blood Pressure
| Field | Value | Status |
|-------|-------|--------|
| Sync path | A (dedicated) | OK |
| HK type | `HKCorrelationType(.bloodPressure)` | OK |
| Unit | `mmHg` (hardcoded in sync) | OK |
| Storage | primary=systolic, secondary=diastolic, tertiary=pulse | OK |
| Reference | 90–120 mmHg (systolic) | OK |
| Display | `"\(systolic)/\(diastolic)"` | OK |
| Notes | Pulse paired from HR within 5-min window. Activity context hardcoded to "At Rest". | OK |

### Resting Heart Rate
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` (non-cumulative) | OK |
| HK unit | `count/min` | OK |
| Display | `"bpm"` | OK |
| Reference | 60–100 bpm | OK |
| isCumulative | false | OK |
| Notes | Category conflict: curated says `.cardioFitness`, catalog says `.vitals`. Curated wins. Minor. | MINOR |

### Heart Rate Variability (SDNN)
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` | OK |
| HK unit | `ms` (`.secondUnit(with: .milli)`) | OK |
| Display | `"ms"` | OK |
| Reference | min 20ms, no max (higher is better) | OK |

### VO2 Max
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` | OK |
| HK unit | `"ml/kg*min"` (compound string) | OK |
| Display | `"mL/kg/min"` | OK |
| Reference | 20–60 | OK |

### Walking Heart Rate Average
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` | OK |
| HK unit | `count/min` | OK |
| Display | `"bpm"` | OK |
| Reference | none | OK |

### Steps
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchDailyStatistics` (cumulative) | OK |
| HK unit | `.count()` | OK |
| Display | `"steps"` | OK |
| isCumulative | true | OK — steps are genuinely cumulative in HK |

### Exercise Minutes
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchDailyStatistics` | OK |
| HK unit | `.minute()` | OK |
| Display | `"min"` | OK |
| isCumulative | true | OK |

### Active Energy
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchDailyStatistics` | OK |
| HK unit | `.kilocalorie()` | OK |
| Display | `"kcal"` | OK |
| isCumulative | true | OK |

### Weight (Body Mass)
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` | OK |
| HK unit | `.gramUnit(with: .kilo)` | OK |
| Display | `"kg"` | OK |
| isCumulative | false | OK |

### Sleep Duration
| Field | Value | Status |
|-------|-------|--------|
| Sync path | B (dedicated) | OK |
| HK type | `HKCategoryType(.sleepAnalysis)` | OK |
| Stages | asleepCore, asleepDeep, asleepREM, asleepUnspecified | OK |
| Aggregation | Merges overlapping intervals, sums per day | OK |
| Storage | primary=hours, durationSeconds=seconds | OK |
| Display | `durationSeconds / 3600` with fallback to `primaryValue` | OK (fixed) |
| Reference | 7–9 hours | OK |

### Workout
| Field | Value | Status |
|-------|-------|--------|
| Sync path | **NONE** — `hkQuantityType` is nil, not in `syncableMetrics` | **BUG** |
| Notes | Authorization requests `workoutType()` but no `syncWorkout` exists. Manual entry only. | **Not synced** |

### Respiratory Rate
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` | OK |
| HK unit | `count/min` | OK |
| Display | `"br/min"` | OK |
| Reference | 12–20 br/min | OK |

### Blood Oxygen (SpO2)
| Field | Value | Status |
|-------|-------|--------|
| Sync path | C → `fetchQuantitySamples` | OK |
| HK unit | `.percent()` → `×100` conversion at sync | OK |
| Display | `"%"` — stored as 95–100, displayed as 95–100% | OK |
| Reference | 95–100% | OK |
| Notes | HK stores as 0.95–1.0 fraction. The `×100` conversion produces correct display values. | OK |

---

## Catalog-Only Metrics (HealthKitCatalog.entries)

### Vitals

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| Heart Rate | `count/min` | bpm | false | samples | OK — high-frequency, capped at 50/day |
| Body Temperature | `°C` | °C | false | samples | OK |
| Basal Body Temp | `°C` | °C | false | samples | OK |
| Blood Glucose | `mg/dL` | mg/dL | false | samples | OK |
| Blood Alcohol | `.percent()` | % | false | samples | **BUG** — see below |
| Perfusion Index | `.percent()` | % | false | samples | OK — `×100` matches inputMax=20 |

### Cardio Fitness

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| HR Recovery (1 min) | `count/min` | bpm | false | samples | OK |
| AFib Burden | `.percent()` | % | false | samples | **MINOR** — refMax=1 after ×100 is technically correct but may confuse |

### Activity

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| Resting Energy | `kcal` | kcal | true | daily stats | OK |
| Walk+Run Distance | `km` | km | true | daily stats | OK |
| Cycling Distance | `km` | km | true | daily stats | OK |
| Swimming Distance | `m` | m | true | daily stats | OK |
| Flights Climbed | `count` | flights | true | daily stats | OK |
| Stand Time | `min` | min | true | daily stats | OK |
| Move Time | `min` | min | true | daily stats | OK |
| Swim Strokes | `count` | strokes | true | daily stats | OK |
| Wheelchair Pushes | `count` | pushes | true | daily stats | OK |
| Nike Fuel | `count` | NikeFuel | true | daily stats | OK |
| Running Speed | `km/h` | km/h | false | samples | OK (fixed from m/s) |
| Running Power | `W` | W | false | samples | OK |
| Cycling Speed | `km/h` | km/h | false | samples | OK (fixed from m/s) |
| Cycling Power | `W` | W | false | samples | OK |
| Cycling Cadence | `count/min` | rpm | false | samples | OK |

### Body

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| BMI | `.count()` | kg/m² | false | samples | **MINOR** — display label says "kg/m²" but HK unit is dimensionless. Values correct, label misleading. |
| Body Fat % | `.percent()` | % | false | samples | OK — `×100` converts 0.20→20%, inputMax=60 matches |
| Lean Body Mass | `kg` | kg | false | samples | OK |
| Height | `cm` | cm | false | samples | OK |
| Waist Circumference | `cm` | cm | false | samples | OK |

### Respiratory

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| FEV1 | `L` | L | false | samples | OK |
| Forced Vital Capacity | `L` | L | false | samples | OK |
| Peak Flow Rate | `L/min` | L/min | false | samples | OK |
| Inhaler Usage | `count` | puffs | true | daily stats | OK |

### Nutrition (all cumulative → daily stats)

| Metric | HK Unit | Display | Status |
|--------|---------|---------|--------|
| Calories Consumed | `kcal` | kcal | OK |
| Protein | `g` | g | OK |
| Carbohydrates | `g` | g | OK |
| Total Fat | `g` | g | OK |
| Sugar | `g` | g | OK — refMax=25g (WHO guideline) |
| Fiber | `g` | g | OK — refMin=25g |
| Sodium | `mg` | mg | OK — refMax=2300mg (FDA) |
| Water | `mL` | mL | OK — refMin=2000mL |
| Caffeine | `mg` | mg | OK — refMax=400mg (FDA) |
| Vitamin D | `mcg` | mcg | OK |
| Calcium | `mg` | mg | OK |
| Iron | `mg` | mg | OK |
| Potassium | `mg` | mg | OK |

### Mobility

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| Walking Speed | `m/s` | m/s | false | samples | OK |
| Step Length | `cm` | cm | false | samples | OK |
| Double Support % | `.percent()` | % | false | samples | OK — `×100` matches inputMax=100 |
| Walking Asymmetry % | `.percent()` | % | false | samples | OK — `×100` matches inputMax=100 |
| Stair Ascent Speed | `m/s` | m/s | false | samples | OK |
| Stair Descent Speed | `m/s` | m/s | false | samples | OK |
| 6-Min Walk Distance | `m` | m | false | samples | OK — refMin=400m |
| Walking Steadiness | `.percent()` | % | false | samples | OK — `×100` matches inputMax=100 |

### Other

| Metric | HK Unit | Display | Cumul. | Sync Path | Status |
|--------|---------|---------|--------|-----------|--------|
| Env. Sound | `dBA` | dB | false | samples | OK — refMax=80dB |
| Headphone Audio | `dBA` | dB | false | samples | OK — refMax=80dB |
| Falls | `count` | falls | true | daily stats | OK |
| Alcoholic Beverages | `count` | drinks | true | daily stats | OK |
| UV Exposure | `count` | UV index | false | samples | OK — refMax=6 |
| Electrodermal Activity | `"mcS"` | μS | false | samples | **MINOR** — uses `HKUnit(from: "mcS")` string initializer; may silently fail if HK doesn't recognize it |

---

## Bugs Found

### BUG: Blood Alcohol Content — wrong values after ×100 conversion

**File:** `HealthKitCatalog.swift` (bloodAlcoholContent entry) + `HealthSyncManager.swift:302`

HealthKit stores BAC as a fraction (e.g., 0.08 = legal limit). The `.percent()` unit triggers `value *= 100` at sync, turning 0.08 into 8.0. But:
- `referenceMax` is 0.08 — set for the raw fraction, not the ×100 value. After conversion the reference line is at 0.08 on a 0–50 scale (invisible).
- `inputMax` is 0.5 — also set for the raw fraction. After conversion the actual stored max would be 50.

**Fix needed:** BAC should NOT use `.percent()`. It should use a dimensionless unit and store the raw fraction as-is. Change unit to `{ HKUnit.count() }`, displayUnit to `"BAC"`, and remove the `×100` trigger. Or alternatively, update referenceMax to 8 and inputMax to 50 to be consistent with the post-conversion values.

### BUG: Workout metric is never synced

**File:** `MetricRegistry.swift` (workout entry has `hkQuantityType: nil`)

The Workout metric type has no HK quantity type and is not sleep, so `syncableMetrics` excludes it. `requestAuthorization` does request `HKSampleType.workoutType()` permission, but no sync method imports workouts. Workout data is manual-entry only.

**Fix needed:** Either implement a `syncWorkouts` method (reading `HKWorkoutType` samples and extracting duration/type/calories), or remove the workout authorization request to avoid confusing Apple reviewers.

---

## Minor Issues

| Issue | Location | Notes |
|-------|----------|-------|
| BMI display unit | `HealthKitCatalog.swift` | Label says "kg/m²" but HK uses dimensionless `.count()`. Values are correct. |
| AFib referenceMax=1 | `HealthKitCatalog.swift` | After ×100, this means 1%. Medically defensible but visually almost invisible on a 0–100 chart. |
| Electrodermal unit | `HealthKitCatalog.swift` | Uses `HKUnit(from: "mcS")` string init — may not be recognized by all HK versions. |
| Resting HR category | `MetricRegistry.swift` | Curated entry puts it in `.cardioFitness`, catalog says `.vitals`. Not wrong, just a choice. |

---

## Percent-Unit Metrics — Conversion Summary

All metrics using `.percent()` as HK unit get `×100` conversion at sync (line 302). Here's the full list and whether the conversion is handled correctly:

| Metric | HK stores | After ×100 | inputMax | refMax | Consistent? |
|--------|-----------|------------|----------|--------|-------------|
| Blood Oxygen (SpO2) | 0.95–1.0 | 95–100 | 100 | 100 | **YES** |
| Body Fat % | 0.10–0.50 | 10–50 | 60 | — | **YES** |
| Double Support % | 0.20–0.40 | 20–40 | 100 | — | **YES** |
| Walking Asymmetry % | 0.0–0.50 | 0–50 | 100 | — | **YES** |
| Walking Steadiness | 0.0–1.0 | 0–100 | 100 | — | **YES** |
| AFib Burden | 0.0–1.0 | 0–100 | 100 | 1 | **YES** (1% threshold) |
| Blood Alcohol | 0.0–0.50 | 0–50 | 0.5 | 0.08 | **NO — BUG** |
| Perfusion Index | 0.0–0.20 | 0–20 | 20 | — | **YES** |
