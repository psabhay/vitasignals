# Neo Health Export

A fully offline iOS health data app that imports data from Apple Health and lets users manually log readings, then generates professional PDF reports to share with their doctor. No accounts, no servers, no tracking — everything stays on-device.

**Bundle ID:** `com.abhaysingh.neohealthexport`
**Platform:** iOS 17.0+
**Architecture:** SwiftUI + SwiftData
**Dependencies:** Zero third-party — Apple frameworks only (HealthKit, PDFKit, Swift Charts)

---

## Features

### HealthKit Sync

- Reads **60+ health metric types** from Apple Health covering vitals, activity, sleep, nutrition, body measurements, respiratory, mobility, cardio fitness, and more
- **Incremental sync** — only fetches new data since last sync, with a 1-hour overlap window for UUID-based deduplication
- Syncs up to 6 metric types in parallel via `TaskGroup` for speed
- Blood pressure synced from `HKCorrelation` and automatically paired with the nearest heart rate reading within 5 minutes
- Sleep aggregated from Apple's staged sleep data (core, deep, REM, unspecified)
- Deleted records are "tombstoned" via `DismissedHealthKitRecord` so they won't re-import on next sync
- Per-metric fetch limit of 500 samples to avoid memory spikes

### Dashboard (Tab 1)

- Latest BP reading with large systolic/diastolic display, pulse, activity context, and AHA classification badge (Normal / Elevated / High Stage 1 / High Stage 2 / Hypertensive Crisis)
- 7-day BP average card (systolic, diastolic, pulse)
- Mini 7-day BP trend chart with dual systolic (red) and diastolic (blue) lines and dashed reference markers at 120/80 mmHg
- 2-column grid of metric cards for every non-BP metric with data — each shows metric icon, name, latest value, unit, and a 7-day sparkline
- Tapping a metric card navigates to a detailed Metric Detail View
- Today's BP readings list with time, value, pulse, context, and category badge
- Permission-denied banner with "Open Settings" link when HealthKit access is blocked
- Sync progress indicator during active sync
- Empty state when no data exists

### Data Browser (Tab 2)

- Horizontal scrollable category filter bar (only shows categories with data)
- Sub-filter row for individual metric types within a selected category
- Records grouped by calendar date, display capped at 200 with "showing N of total" indicator
- Each row shows: metric icon, value + unit, source badge (pink heart for HealthKit), time, and BP category badge
- Swipe left to delete (writes tombstone for HealthKit records)
- Swipe right to open edit view
- Tap row to open full record detail

### Charts (Tab 3)

- Segmented time range picker: 7 Days / 14 Days / 30 Days / 90 Days / All Time
- Horizontal metric picker chips for switching between any available metric type
- **Blood pressure mode** renders 6 chart cards:
  1. **BP Trend** — dual line chart (systolic + diastolic) with Catmull-Rom interpolation and reference lines at 120/80
  2. **Pulse Trend** — area + line chart
  3. **Summary Card** — average BP with classification, average pulse, % in normal range, systolic/diastolic ranges
  4. **Weekly Averages** — gradient bar chart showing diastolic-to-systolic range per week
  5. **Time of Day Comparison** — stat cards for Morning (5am–12pm), Afternoon (12pm–5pm), Evening (5pm–5am)
  6. **Mean Arterial Pressure** — dual line chart for MAP and Pulse Pressure with normal range (70–100 mmHg)
- **Generic metric mode** for any non-BP metric: line or bar chart (based on metric definition) with reference range overlays and avg/range summary

### Metric Detail View

- Accessed by tapping a metric card on the Dashboard
- Time range picker (same 5 options)
- Summary card: average, minimum, maximum, record count, "% in normal range" if reference bounds exist
- Trend chart with reference lines
- Recent records list (up to 20 entries)

### Reports (Tab 4)

- Configurable date range (From / To date pickers)
- Per-metric selection with expandable category disclosure groups and individual toggles
- Select All / Deselect All for quick toggling
- Preview summary: record count in range, metric type count, patient name
- 3 PDF report styles:
  - **Classic** — navy blue accent, system fonts, professional layout
  - **Modern** — teal/green accent, heavier fonts, softer feel
  - **Clinical** — Georgia serif fonts, near-monochrome, minimal color
- Generate button (disabled when no data in range or no metrics selected)
- After generation: in-app PDF preview (full-screen via PDFKit), Share via system share sheet, Regenerate button
- PDF generation runs on a background thread to keep the UI responsive

### PDF Report Contents

The generated report is US Letter size (612×792 pt) with 48pt margins and includes:

1. **Header** — report title, generation timestamp, period label, total record and metric count
2. **Patient Info Table** — name, age, gender, height (ft/in + cm), weight (kg/lbs), BMI + category, physician, medical notes
3. **Blood Pressure Summary** — average BP, AHA classification, average heart rate, systolic/diastolic ranges, MAP, pulse pressure, % in normal range
4. **BP Classification Breakdown** — table of each category (Normal through Crisis) with count, percentage, and average BP
5. **Health Metrics Summary** — multi-column table of all non-BP metrics with average, range, and data point count
6. **BP Charts** — trend chart (systolic + diastolic lines), pulse trend chart
7. **Time of Day Analysis** — comparison table by Morning/Afternoon/Evening with clinical note (flags morning surge if morning systolic ≥ 10 mmHg above evening)
8. **Per-Category Metric Pages** — for each category with ≥2 data points: section header, per-metric description, chart, and summary stats
9. **Medical Disclaimer** — informational purpose notice
10. **Blood Pressure Annexure** — full detailed readings table with Date/Time, SYS, DIA, HR, MAP, and Context columns

### Manual Data Entry

- Entry points: "+" button on Dashboard and Data Browser tabs
- `AddRecordPickerSheet`: category-grouped 2-column grid of all available metric types
- **Blood pressure form:** steppers for systolic (60–300), diastolic (30–200), pulse (30–220); live "SYS/DIA" preview with animated category badge; 18 activity context buttons in a 2-column grid
- **Sleep form:** 0.5-hour step slider (0–24 hours) with large hour display
- **Generic metric form:** stepper with per-metric min/max/step bounds and value display in metric color
- All forms include: date/time picker, optional notes text field
- Edit any existing record with the same form layouts, pre-populated from the record

### Activity Contexts (Blood Pressure)

18 pre-defined contexts for BP readings, each with a system image icon:

Just Woke Up, Before Breakfast, After Breakfast, Before Lunch, After Lunch, Before Dinner, After Dinner, After Coffee, After Tea, After Walking, After Running, After Exercise, After Medication, At Rest, Before Sleep, Feeling Stressed, After Alcohol, Other

### Blood Pressure Classification

Uses AHA (American Heart Association) thresholds:

| Category | Systolic | Diastolic |
|---|---|---|
| Normal | < 120 | and < 80 |
| Elevated | 120–129 | and < 80 |
| High Stage 1 | 130–139 | or 80–89 |
| High Stage 2 | ≥ 140 | or ≥ 90 |
| Hypertensive Crisis | > 180 | or > 120 |

The higher category always wins.

### Profile & Data Management

- **Onboarding** on first launch — full-screen form with name (required), age, gender, height (ft/in), weight (kg), doctor name, and medical notes
- Profile viewable and editable from any tab via the person-circle toolbar icon
- **Delete All Records** — removes all health records and writes tombstones for HealthKit-sourced records to prevent re-import
- **Reset Import History** — clears all tombstones to allow a full re-import from Apple Health on next sync

### Onboarding Flow

1. First launch detects no `UserProfile` exists
2. `OnboardingView` presented as non-dismissable full-screen cover
3. User fills in profile (only name is required)
4. On "Continue", profile is saved and HealthKit sync is triggered automatically
5. Subsequent launches skip onboarding and sync immediately

---

## Supported Health Metrics

### Curated Metrics (with hand-tuned definitions)

| Metric | HealthKit Type | Category |
|---|---|---|
| Blood Pressure | HKCorrelationType(.bloodPressure) | Vitals |
| Resting Heart Rate | .restingHeartRate | Cardio Fitness |
| Heart Rate Variability | .heartRateVariabilitySDNN | Cardio Fitness |
| VO2 Max | .vo2Max | Cardio Fitness |
| Walking Heart Rate | .walkingHeartRateAverage | Cardio Fitness |
| Steps | .stepCount | Activity |
| Exercise Minutes | .appleExerciseTime | Activity |
| Active Energy | .activeEnergyBurned | Activity |
| Weight | .bodyMass | Body |
| Sleep Duration | HKCategoryType(.sleepAnalysis) | Sleep & Recovery |
| Respiratory Rate | .respiratoryRate | Respiratory |
| Blood Oxygen (SpO2) | .oxygenSaturation | Respiratory |

### Extended Catalog (~50 additional metrics auto-generated from HealthKitCatalog)

**Vitals:** Heart Rate, Body Temperature, Basal Body Temperature, Blood Glucose, Blood Alcohol Content, Perfusion Index

**Cardio Fitness:** Heart Rate Recovery, AFib Burden

**Activity:** Resting Energy, Walking + Running Distance, Cycling Distance, Swimming Distance, Flights Climbed, Stand Time, Move Time, Swim Strokes, Wheelchair Pushes, Nike Fuel, Running Speed, Running Power, Cycling Speed, Cycling Power, Cycling Cadence

**Body:** BMI, Body Fat %, Lean Body Mass, Height, Waist Circumference

**Respiratory:** FEV1, Forced Vital Capacity, Peak Flow Rate, Inhaler Usage

**Nutrition:** Calories Consumed, Protein, Carbohydrates, Total Fat, Sugar, Fiber, Sodium, Water Intake, Caffeine, Vitamin D, Calcium, Iron, Potassium

**Mobility:** Walking Speed, Step Length, Double Support Time, Walking Asymmetry, Stair Ascent Speed, Stair Descent Speed, 6-Minute Walk Distance, Walking Steadiness

**Other:** Environmental Sound, Headphone Audio Level, Falls, Alcoholic Beverages, UV Exposure, Electrodermal Activity

---

## Data Model

### SwiftData Entities

| Entity | Purpose |
|---|---|
| `HealthRecord` | Universal container for any health measurement — stores metricType, primaryValue, secondaryValue, tertiaryValue, durationSeconds, healthKitUUID, source, isManualEntry, activityContext, notes |
| `UserProfile` | Single-row user info (name, age, gender, height, weight, doctor, medical notes) used in onboarding, profile display, and PDF reports |
| `SyncState` | Per-metric incremental sync tracking (metricType, lastSyncDate, isAvailable) |
| `DismissedHealthKitRecord` | Tombstone for HealthKit records the user deleted (metricType, healthKitUUID) to prevent re-import |

### HealthRecord Value Encoding

- **Blood pressure:** primaryValue = systolic, secondaryValue = diastolic, tertiaryValue = pulse
- **Sleep:** primaryValue = hours, durationSeconds = raw seconds
- **All other metrics:** primaryValue = the single numeric value

---

## Technical Architecture

### Data Flow

```
Apple Health (HealthKit)
        │
        ▼
HealthSyncManager → SyncWorker (background ModelContext, 6 parallel tasks)
        │
        ▼
SwiftData (on-device SQLite)
        │
        ▼
HealthDataStore (shared @Published in-memory cache)
        │
        ▼
All SwiftUI Views (via @EnvironmentObject)
```

### Performance Optimizations

- Single shared `HealthDataStore` eliminates redundant `@Query` loads across views
- `allRecords` is a lazy computed property to avoid a second full copy in memory
- Main fetch capped at 5,000 records; report fetch capped at 10,000
- Dashboard card data cached in `@State`, recomputed only when `recordCount` changes
- Data Browser uses a single `FilteredResult` struct computed once per render
- PDF generation runs on `Task.detached(priority: .background)`
- HealthKit sync uses up to 6 parallel tasks via `withTaskGroup`
- Each sync task gets its own `ModelContext` for thread safety
- Incremental sync with overlap window avoids full re-import on every launch

### Privacy & Security

- **Fully offline** — zero network calls, no analytics, no crash reporting, no third-party SDKs
- **Read-only HealthKit access** — `toShare: []`, only reads data
- **All data on-device** in SwiftData (SQLite)
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) declares HealthKit data collection (not linked, not for tracking) and UserDefaults access
- **Medical disclaimer** in onboarding, profile footer, and every generated PDF report
- Data only leaves the device when the user explicitly shares a PDF via the system share sheet

### Accessibility

- VoiceOver labels on icon-only buttons, metric cards, chart containers, filter chips, and BP category badges
- `accessibilityAddTraits(.isSelected)` on filter chips and activity context buttons
- Dark mode support via system colors throughout
- Portrait-only orientation lock

### Test Suite

| Test Class | Coverage |
|---|---|
| `HealthRecordTests` | BP classification logic, record factory methods, ActivityContext icons, BPCategory colors |
| `MetricRegistryTests` | All curated types have definitions, category filtering, syncable metrics, formatValue, catalog auto-generation, curated-overrides-catalog precedence, uniqueness |
| `PDFGeneratorTests` | Empty records, basic BP, with/without profile, multi-metric, selected-metrics filter, single reading, 100 readings, non-BP only |
| `UserProfileTests` | Default init, BMI calculation and categories, height/weight formatted strings |

---

## Project Structure

```
NeoHealthExport/
├── App/
│   └── NeoHealthExportApp.swift              — Entry point, SwiftData schema, container setup
├── Models/
│   ├── HealthRecord.swift                    — Core entity, BPCategory, ActivityContext
│   ├── HealthKitCatalog.swift                — ~55 extended HK metric entries
│   ├── MetricRegistry.swift                  — Metric definitions, categories, chart styles
│   ├── ReportStyle.swift                     — Classic/Modern/Clinical PDF themes
│   ├── UserProfile.swift                     — User profile entity with BMI
│   ├── SyncState.swift                       — Per-metric sync timestamp
│   └── DismissedHealthKitRecord.swift        — Tombstone for deleted HK records
├── Views/
│   ├── ContentView.swift                     — Tab shell, onboarding, profile sheet
│   ├── DashboardView.swift                   — Main dashboard with BP card, metric grid, charts
│   ├── DataBrowserView.swift                 — Filterable record list, FilterChip
│   ├── ChartsContainerView.swift             — All BP analysis charts + generic metric chart
│   ├── MetricDetailView.swift                — Per-metric detail with summary + chart
│   ├── MetricCardView.swift                  — Compact metric card with sparkline
│   ├── ReportBuilderView.swift               — Report config UI, PDF preview/share
│   ├── AddRecordPickerSheet.swift            — Metric type selector for adding records
│   ├── AddHealthRecordView.swift             — Add form (BP/sleep/generic)
│   ├── EditHealthRecordView.swift            — Edit form (same layouts, pre-populated)
│   └── RecordDetailView.swift                — Record inspector with edit/delete
├── Helpers/
│   ├── HealthSyncManager.swift               — HealthKit auth, discovery, incremental sync
│   ├── HealthDataStore.swift                 — Shared in-memory record cache
│   ├── PDFGenerator.swift                    — CoreGraphics PDF renderer
│   └── MigrationManager.swift                — DB migration stub
├── Resources/
│   ├── Assets.xcassets/                      — App icon, accent color
│   └── PrivacyInfo.xcprivacy                 — Privacy manifest
└── Info.plist                                — Usage descriptions, orientation, display name
```
