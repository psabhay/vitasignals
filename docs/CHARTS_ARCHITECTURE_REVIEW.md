# Charts Architecture Review & Implementation Plan

**Date:** 2026-03-26
**Scope:** Complete audit of all chart-related code in VitaSignals
**Context:** Charts are the core product — the entire app exists to make health metric viewing easy and feature-rich. The chart system must be architecturally excellent.

---

## Table of Contents

1. [Current Architecture Map](#1-current-architecture-map)
2. [Data Pipeline](#2-data-pipeline)
3. [Verified Issues — Critical](#3-verified-issues--critical)
4. [Verified Issues — High](#4-verified-issues--high)
5. [Verified Issues — Medium](#5-verified-issues--medium)
6. [What Apple Says — Swift Charts Best Practices](#6-what-apple-says--swift-charts-best-practices)
7. [Missing Abstractions](#7-missing-abstractions)
8. [Implementation Plan](#8-implementation-plan)

---

## 1. Current Architecture Map

### Chart Rendering Contexts

The app renders charts in 5 distinct contexts, each with its own implementation:

| Context | Entry Point | Chart Components Used | Has Zoom/Pan |
|---------|------------|----------------------|--------------|
| **Charts tab — overview cards** | `ChartsContainerView` | `ComparisonMetricChart`, `ComparisonBPChart`, `DualAxisChartView` | Yes (inherited) |
| **Charts tab — expanded detail** | `ChartsContainerView.expandedContent` | `GenericMetricChart`, `BPTrendChart`, `PulseChart`, `BPSummaryCard`, `WeeklyAveragesChart`, `MorningVsEveningChart`, `MAPTrendChart` | **No** |
| **Dashboard mini-charts** | `DashboardView` | `ComparisonMetricChart`, `ComparisonBPChart`, `DualAxisChartView` | Yes (inherited from Dashboard) |
| **Metric Detail** (from Dashboard tap) | `MetricDetailView` | Inline chart (own implementation) | **No** |
| **Sparkline** | `MetricCardView` | Inline mini LineMark | No (by design) |

### File Map

| File | Lines | Types Defined | Role |
|------|-------|---------------|------|
| `ChartsContainerView.swift` | **1,782** | 12 types | Charts tab, zoom/pan, 6 expanded chart structs, filter sheet, saved views |
| `ComparisonChartView.swift` | ~355 | 3 types + `downsample()` | `ComparisonMetricChart`, `ComparisonBPChart`, free `downsample` function |
| `DualAxisChartView.swift` | ~230 | 1 type | Custom dual-axis overlay chart |
| `MetricDetailView.swift` | ~200 | 1 type | Standalone metric detail (separate from Charts tab) |
| `DashboardChartCard.swift` | ~180 | 3 types | `DashboardCardResolver`, card model, manage sheet |
| `DashboardView.swift` | ~350 | 1 type | Dashboard tab, dispatches to chart components |
| `MetricCardView.swift` | ~80 | 1 type | Sparkline mini-chart |

---

## 2. Data Pipeline

### Storage to Pixel — Full Trace

```
SwiftData (HealthRecord @Model)
    │
    ▼
HealthDataStore.refresh()          ← fetchLimit = 500 per metric type
    │                                 (HealthDataStore.swift:81,89)
    │                                 sorted descending by timestamp
    ▼
recordsByType: [String: [HealthRecord]]   ← in-memory cache
    │
    ├──► ChartsContainerView.recomputeVisible()
    │        │  calls filteredRecords(for:) → date range filter
    │        │  stores result in cachedRecords: [String: [HealthRecord]]
    │        ▼
    │    chartCard(for:) in body
    │        │  reads cachedRecords[metricType]
    │        │  passes to ComparisonMetricChart / ComparisonBPChart
    │        ▼
    │    downsample() called INSIDE body  ← re-runs every render
    │        │  uniform stride, 60 pts (cards) or 120 pts (detail)
    │        ▼
    │    Chart { LineMark / BarMark }
    │        .chartXScale(domain: xDomain)  ← zoom/pan applied here
    │
    ├──► customChartCard() in body
    │        │  calls filteredRecords(for:) DIRECTLY  ← bypasses cache
    │        ▼
    │    DualAxisChartView
    │        .onAppear { recomputeCache() }  ← no .onChange
    │
    ├──► MetricDetailView.recomputeFiltered()
    │        │  own date filtering, independent of Charts tab
    │        ▼
    │    downsample() inside body, 120 pts
    │        ▼
    │    Chart { LineMark / BarMark }  ← no .chartXScale, no zoom
    │
    └──► DashboardView → DashboardCardResolver.resolve()
             │  uses @AppStorage("dashboardChartDays") — separate from ChartTimeRange
             ▼
         ComparisonMetricChart / ComparisonBPChart / DualAxisChartView
```

### Key Data Pipeline Problems

1. **500-record cap silently truncates "All Time"** — A user with 800+ BP readings loses the oldest ~300 with no indication. `cachedEarliestDate` reflects the cap boundary, not the true earliest date. (`HealthDataStore.swift:81`)

2. **Downsampling is zoom-unaware** — 60 points are sampled uniformly across the full date range *before* the zoom domain is applied. Zooming into a 3-day window within 90 days may show only 2-3 visible points, even if raw data has 30+ records in that range. This defeats the purpose of zoom.

3. **Three independent date filtering implementations** — `ChartsContainerView.filteredRecords()`, `MetricDetailView.recomputeFiltered()`, and `DashboardCardResolver.resolve()` each filter dates differently. Dashboard uses `@AppStorage("dashboardChartDays")` (plain Int), completely disconnected from `ChartTimeRange`.

---

## 3. Verified Issues — Critical

> Every claim below has been verified against the source code with exact line references.

### C1. `DualAxisChartView` Cache Never Invalidates on Data Change

**File:** `DualAxisChartView.swift:90`
**Evidence:** `.onAppear { recomputeCache() }` — this is the ONLY call to `recomputeCache()`. No `.onChange(of: leftRecords)` or `.onChange(of: rightRecords)` exists anywhere in the file.
**Impact:** When the parent changes time range or new data syncs from HealthKit, SwiftUI may reuse the view instance. `onAppear` won't re-fire, so the chart renders stale data from the previous time range.

### C2. Downsampling is Zoom-Unaware

**Files:** `ComparisonChartView.swift:8-17` (downsample definition), called at `ComparisonChartView.swift:98` (60pts), `ChartsContainerView.swift:1281` (120pts), etc.
**Evidence:** `downsample()` runs on the full filtered record set before `chartXScale(domain: xDomain)` clips the visible window. The 60/120-point budget is spread across the entire date range regardless of zoom level.
**Impact:** At 10x zoom on a 90-day range, the visible 9-day window contains ~6 of the 60 sampled points. The user zooms in expecting more detail but sees less.

### C3. Expanded/Detail Charts Lose Zoom Context

**Files:** `ChartsContainerView.swift` — `GenericMetricChart` (line 1247), `BPTrendChart` (line 1347), `PulseChart` (line 1414), `WeeklyAveragesChart` (line 1569), `MAPTrendChart` (line 1715)
**Evidence:** None of these 5 structs accept an `xDomain` parameter. None apply `.chartXScale(domain:)`. Verified by reading every parameter declaration and every modifier chain.
**Impact:** Tapping to expand a metric while zoomed to a specific week shows ALL data instead of the zoomed window. The zoom context is lost on drill-down.

### C4. BP Reference Lines Hardcoded Instead of Using MetricDefinition

**Evidence — Hardcoded values:**
- `ComparisonChartView.swift:274` → `RuleMark(y: .value("Ref", 120))`
- `ComparisonChartView.swift:282` → `RuleMark(y: .value("Ref", 80))`
- `ChartsContainerView.swift:1377` → `RuleMark(y: .value("Target Sys", 120))`
- `ChartsContainerView.swift:1383` → `RuleMark(y: .value("Target Dia", 80))`
- `ChartsContainerView.swift:1612` → `RuleMark(y: .value("Target Sys", 120))`
- `ChartsContainerView.swift:1615` → `RuleMark(y: .value("Target Dia", 80))`
- `ChartsContainerView.swift:1750` → `RuleMark(y: .value("MAP High", 100))`
- `ChartsContainerView.swift:1753` → `RuleMark(y: .value("MAP Low", 70))`

**Evidence — MetricRegistry:** `MetricRegistry.swift:107-125` defines `referenceMin: 90, referenceMax: 120` for BP as a single metric. The systolic/diastolic split (120/80) is not modeled in the definition.
**Impact:** If reference values need to change (e.g., user-customizable targets), every hardcoded site must be found and updated manually. The model-view contract is broken.

### C5. "All Time" Silently Truncates Data

**File:** `HealthDataStore.swift:81,89`
**Evidence:** `let perMetricLimit = 500` and `descriptor.fetchLimit = perMetricLimit`
**Impact:** For `ChartTimeRange.all`, the chart domain starts at `cachedEarliestDate` (the 500th-oldest record), not the true earliest date. Users with long histories see a misleading "All Time" view.

---

## 4. Verified Issues — High

### H1. Core Chart Rendering Duplicated 5+ Times

The same chart body — `Chart { ForEach { if .bar { BarMark } else { LineMark } } + RuleMark for ref range }` with axis configuration — is copy-pasted with minor variations:

| Location | File:Line | Height | Downsample | Has Annotations |
|----------|-----------|--------|------------|-----------------|
| `ComparisonMetricChart.body` | `ComparisonChartView.swift:97-180` | 180 | 60 | Yes |
| `GenericMetricChart.body` | `ChartsContainerView.swift:1280-1342` | 220 | 120 | Yes |
| `MetricDetailView.chartCard` | `MetricDetailView.swift:118-178` | 220 | 120 | **No** |
| `BPTrendChart.body` | `ChartsContainerView.swift:1347-1410` | 220 | 120 | Yes |
| `ComparisonBPChart.body` | `ComparisonChartView.swift:204-355` | 180 | 60 | Yes (different style) |

Any improvement (e.g., adding selection, improving accessibility) must be applied 5 times.

### H2. `MetricDetailView` is a Disconnected Parallel Universe

**File:** `MetricDetailView.swift`
**Evidence:** Has its own `recomputeFiltered()` (line 14), own chart rendering (line 118), own summary stats (line 58), own `statColumn` helper (line 106). Zero shared code with `ChartsContainerView`.
**Impact:** The same metric shows different UI depending on navigation path (Dashboard → MetricDetail vs Charts tab → expanded). No zoom/pan support. The `.custom` time range option is shown in the picker (line 28 — `ForEach(ChartTimeRange.allCases)`) but falls through to showing all records with no custom date picker (line 20 — `else { cachedFiltered = records }`).

### H3. Downsampling Runs Inside `body` on Every Render

**Verified call sites inside `body` (no caching):**
1. `ComparisonMetricChart` — `ComparisonChartView.swift:98`: `let chartData = downsample(records)`
2. `GenericMetricChart` — `ChartsContainerView.swift:1281`: `let chartData = downsample(records, maxPoints: 120)`
3. `BPTrendChart` — `ChartsContainerView.swift:1351`: `let chartData = downsample(records, maxPoints: 120)`
4. `PulseChart` — `ChartsContainerView.swift:1423`: `let chartData = downsample(recordsWithPulse, maxPoints: 120)`
5. `MAPTrendChart` — `ChartsContainerView.swift:1731`: `let chartData = downsample(records, maxPoints: 120)`

**Only `DualAxisChartView`** correctly caches via `@State private var cachedLeftPoints` with `recomputeCache()` on `.onAppear`.

**Apple says:** "The most common SwiftUI performance issue involves expensive computations in view bodies" — [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance). Also from Apple Developer Forums: developers report 50-150ms hangs with 500-2000 data points in Swift Charts.

### H4. `ChartsContainerView.swift` is a 1,782-Line God File

**Contains 12 distinct types:**
1. `enum ChartTimeRange` (line 5)
2. `struct ChartExportRequest` (line 27)
3. `struct ChartsContainerView` (line 33) — ~800 lines
4. `struct SavedViewsSheet` (line 892)
5. `struct ChartFilterSheet` (line 1078)
6. `struct GenericMetricChart` (line 1247)
7. `struct BPTrendChart` (line 1347)
8. `struct PulseChart` (line 1414)
9. `struct BPSummaryCard` (line 1459)
10. `struct WeeklyAveragesChart` (line 1569)
11. `struct MorningVsEveningChart` (line 1632)
12. `struct MAPTrendChart` (line 1715)

### H5. Pan Gesture Only Works on Zoom Indicator Bar

**File:** `ChartsContainerView.swift:537`
**Evidence:** `.gesture(panGesture)` is attached inside `zoomIndicator` — a small banner view. The charts themselves and the scroll area do not have the pan gesture.
**Impact:** Users intuitively drag on charts to pan. Instead, this scrolls the `ScrollView`. The pan target is a small, non-obvious UI element.

### H6. Custom Chart Cards Bypass the Record Cache

**File:** `ChartsContainerView.swift:676-677`
**Evidence:**
```swift
let leftRecords = filteredRecords(for: chart.leftMetricType)
let rightRecords = filteredRecords(for: chart.rightMetricType)
```
This calls `filteredRecords(for:)` directly in `body` instead of reading from `cachedRecords`. Single-metric charts at line 656 correctly use `cachedRecords[metricType]`.

---

## 5. Verified Issues — Medium

### M1. Reference Line Styles Vary Across 6 Locations

| Location | Dash Pattern | Color/Opacity | Annotations |
|----------|-------------|---------------|-------------|
| `ComparisonMetricChart` (line 119) | `[4, 3]` | `.green.opacity(0.4)` | Yes |
| `ComparisonBPChart` (line 274) | `[4, 3]` | `.red.opacity(0.3)` / `.blue.opacity(0.3)` | Yes |
| `MetricDetailView` (line 150) | `[5, 3]` | `.green.opacity(0.5)` | **No** |
| `GenericMetricChart` (line 1302) | `[5, 3]` | `.green.opacity(0.5)` | Yes |
| `BPTrendChart` (line 1379) | `[5, 3]` | `.green.opacity(0.5)` / `.green.opacity(0.3)` | Yes |
| `MAPTrendChart` (line 1751) | `[5, 3]` | `.green.opacity(0.4)` | Yes |

### M2. Six Different Chart Heights, No Design Tokens

| Chart | Height | File:Line |
|-------|--------|-----------|
| `MetricCardView` sparkline | 30 | `MetricCardView.swift:54` |
| `PulseChart` | 160 | `ChartsContainerView.swift:1446` |
| `ComparisonMetricChart` | 180 | `ComparisonChartView.swift:146` |
| `ComparisonBPChart` | 180 | `ComparisonChartView.swift:300` |
| `DualAxisChartView` | 200 | `DualAxisChartView.swift:179` |
| `MAPTrendChart` | 200 | `ChartsContainerView.swift:1757` |
| `GenericMetricChart` | 220 | `ChartsContainerView.swift:1321` |
| `BPTrendChart` | 220 | `ChartsContainerView.swift:1390` |
| `WeeklyAveragesChart` | 220 | `ChartsContainerView.swift:1619` |
| `MetricDetailView` | 220 | `MetricDetailView.swift:159` |

### M3. `ChartStyle.bpDual` is Architecturally Orphaned

**File:** `MetricRegistry.swift:57` — `enum ChartStyle { case line, bar, bpDual }`
**But dispatch uses string comparison:**
```swift
// ChartsContainerView.swift:657
if metricType == MetricType.bloodPressure {
    ComparisonBPChart(...)
} else if let def = MetricRegistry.definition(for: metricType) {
    ComparisonMetricChart(...)
}
```
Same pattern in `DashboardView.swift:283`. The `chartStyle` property is never checked for routing.

### M4. `statColumn` Helper Duplicated Identically

**MetricDetailView.swift:106-113** and **ChartsContainerView.swift:844-851** — byte-for-byte identical.

### M5. `allMetricsWithData` Duplicated and Uncached

**ChartsContainerView.swift:91-108** and **ChartFilterSheet.swift:1087-1102** — identical computed property. Both are `private var` running O(categories x metrics) on every `body` evaluation.

### M6. `downsample()` Lives in a View File

**File:** `ComparisonChartView.swift:8-17` — a free function in a View file. Called from 5+ other files via implicit module-level visibility. If `ComparisonChartView.swift` is reorganized, call sites break silently.

### M7. Naive Downsampling Algorithm

Current: uniform stride selection — picks evenly spaced indices. This can miss important peaks/valleys (e.g., a hypertensive crisis that falls between stride steps).

Better: **LTTB (Largest Triangle Three Buckets)** — preserves visual shape by selecting points that maximize triangle area. Swift implementation available: [GuillaumeBeal/LTTB](https://github.com/GuillaumeBeal/LTTB). Recommended in Apple Developer Forums for chart downsampling.

### M8. `aggregation` and `isCumulative` Fields Are Dead Code for Charts

`MetricDefinition.aggregation` specifies `.sum` for step count, exercise minutes, active energy. But every chart plots raw `primaryValue` per record regardless — the aggregation type is never consulted during rendering.

---

## 6. What Apple Says — Swift Charts Best Practices

### From WWDC22/23 Sessions and Apple Documentation

**Scrolling (iOS 17+):**
Apple provides native chart scrolling via `.chartScrollableAxes(.horizontal)` combined with `.chartXVisibleDomain(length:)` to set the visible window, and `.chartScrollPosition(x:)` as a binding to track/control position. `.chartScrollTargetBehavior(.valueAligned(...))` allows snapping to date boundaries. The current app does NOT use any of these — it implements custom zoom/pan with `MagnifyGesture` + `DragGesture` + manual `xDomain` calculation.

*Sources:*
- [chartScrollableAxes documentation](https://developer.apple.com/documentation/swiftui/view/chartscrollableaxes(_:))
- [WWDC23: Explore pie charts and interactivity](https://developer.apple.com/videos/play/wwdc2023/10037/)

**Selection (iOS 17+):**
The `chartXSelection(value:)` modifier handles all gesture recognition and stores the selected value to a binding. Supports single-value selection (tap), range selection (two-finger tap on iOS), and custom gestures via `ChartProxy`. The app does NOT use `chartXSelection` — there is no data point selection/inspection on any chart.

*Sources:*
- [WWDC23: Explore pie charts and interactivity](https://developer.apple.com/videos/play/wwdc2023/10037/)

**Performance:**
Apple Developer Forums report 50-150ms hangs with 500-2000 data points in Swift Charts. Developers recommend LTTB downsampling off the main thread. Apple's own guidance: "The most common SwiftUI performance issue involves expensive computations in view bodies."

*Sources:*
- [Swift Charts performance discussion](https://developer.apple.com/forums/thread/740314)
- [Poor performance with many data points](https://developer.apple.com/forums/thread/735687)
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)
- [WWDC25: Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)

**Accessibility (HIG + WWDC21):**
- Use symbols in addition to color to differentiate data series
- Support `Differentiate Without Color` accessibility setting
- Support `Increase Contrast` setting with higher-contrast color alternatives
- Expose chart data to VoiceOver via `AXChart` protocol and `accessibilityChartDescriptor`
- Avoid red+green together (most common color blindness)

*Sources:*
- [HIG: Charts](https://developer.apple.com/design/human-interface-guidelines/components/content/charts/)
- [WWDC21: Bring accessibility to charts](https://developer.apple.com/videos/play/wwdc2021/10122/)

**Design Principles (HIG):**
- Include axis lines and labels so values can be estimated
- Use interactivity for accessing precise values
- Charts should communicate one clear message

*Sources:*
- [HIG: Charts](https://developer.apple.com/design/human-interface-guidelines/components/content/charts/)
- [WWDC22: Design an effective chart](https://developer.apple.com/videos/play/wwdc2022/110340/)

---

## 7. Missing Abstractions

### What Should Exist

| Abstraction | Purpose | Replaces |
|-------------|---------|----------|
| **`MetricChartView`** | Single reusable chart component that renders any metric type | 5 duplicate chart rendering blocks |
| **`BPChartView`** | BP-specific chart (systolic + diastolic dual series) | `ComparisonBPChart` inline chart + `BPTrendChart` |
| **`ChartConstants`** | Named constants for heights, downsample limits, reference line styles | Magic numbers in 10+ locations |
| **`ReferenceRangeOverlay`** | Shared `RuleMark` component with consistent styling | 6 inconsistent reference line implementations |
| **`ChartCardChrome`** | Shared card wrapper (header, footer, padding, background, rounded corners) | Repeated card shell in every chart view |
| **`ChartDataProvider`** | Centralized date filtering + downsampling + caching, computed once | Per-view ad-hoc filtering and in-body downsampling |
| **`Helpers/ChartUtilities.swift`** | Home for `downsample()`, future LTTB, stat helpers | Free function buried in ComparisonChartView.swift |
| **`BPDetailCharts/`** folder | Group for `BPTrendChart`, `PulseChart`, `BPSummaryCard`, `WeeklyAveragesChart`, `MorningVsEveningChart`, `MAPTrendChart` | 6 structs inside ChartsContainerView.swift |

---

## 8. Implementation Plan

### Phase 0: Foundation — Extract Shared Utilities (No Visual Changes)

**Goal:** Move shared code to proper homes. Zero visual changes, zero behavior changes. Pure refactor.

**Step 0.1 — Create `Helpers/ChartUtilities.swift`**
- Move `downsample()` from `ComparisonChartView.swift:8-17` to new file
- Move `statColumn()` from both `MetricDetailView.swift:106` and `ChartsContainerView.swift:844` to new file as a static function or View extension
- Move `allMetricsWithData` logic to a shared computed property on `HealthDataStore` or a free function

**Step 0.2 — Create `Models/ChartConstants.swift`**
```swift
enum ChartHeight {
    static let sparkline: CGFloat = 30
    static let compact: CGFloat = 160
    static let card: CGFloat = 180
    static let dual: CGFloat = 200
    static let detail: CGFloat = 220
}

enum ChartResolution {
    static let card = 60
    static let detail = 120
}

enum ChartRefLineStyle {
    static let stroke = StrokeStyle(lineWidth: 1, dash: [5, 3])
    static let normalColor = Color.green.opacity(0.5)
}
```
- Replace all magic numbers across every chart file

**Step 0.3 — Model BP reference values properly**
- Add `systolicRef` and `diastolicRef` to `MetricDefinition` (or a dedicated `BPReferenceRange` struct)
- Replace all hardcoded 120/80/100/70 values with reads from the definition

---

### Phase 1: Fix Critical Bugs (Minimal Code, Maximum Impact)

**Step 1.1 — Fix `DualAxisChartView` stale cache**
- Add `.onChange(of: leftRecords)` and `.onChange(of: rightRecords)` handlers that call `recomputeCache()`
- ~5 lines of code

**Step 1.2 — Fix custom chart cache bypass**
- In `ChartsContainerView.customChartCard()`, read from `cachedRecords` instead of calling `filteredRecords(for:)` directly
- Ensure `recomputeVisible()` also caches records for custom chart metric types

**Step 1.3 — Pass `xDomain` to expanded charts**
- Add `xDomain: ClosedRange<Date>` parameter to `GenericMetricChart`, `BPTrendChart`, `PulseChart`, `WeeklyAveragesChart`, `MAPTrendChart`
- Apply `.chartXScale(domain: xDomain)` in each
- Pass the current `xDomain` from `ChartsContainerView.expandedContent()`

**Step 1.4 — Remove `.custom` from MetricDetailView picker**
- Filter `ChartTimeRange.allCases` to exclude `.custom` in `MetricDetailView` since there's no custom date picker UI there

---

### Phase 2: Performance — Cache Downsampled Data Outside `body`

**Step 2.1 — Move downsampling to `@State` cache in every chart view**
Apply the pattern already used in `DualAxisChartView`:
```swift
@State private var cachedChartData: [HealthRecord] = []

.onAppear { recompute() }
.onChange(of: records) { recompute() }

private func recompute() {
    cachedChartData = downsample(records, maxPoints: N)
}
```

Apply to: `ComparisonMetricChart`, `ComparisonBPChart`, `GenericMetricChart`, `BPTrendChart`, `PulseChart`, `MAPTrendChart`

**Step 2.2 — Move summary stats computation out of `body`**
Same `@State` + `.onChange` pattern for all avg/min/max/count calculations in:
- `ComparisonMetricChart` (lines 171-172)
- `ComparisonBPChart` (lines 325-326)
- `BPSummaryCard.stats` (line 1470)
- `WeeklyAveragesChart.weeklyData` (line 1581)
- `MorningVsEveningChart.periodData` (line 1645)
- `MAPTrendChart` avg computations (line 1768)

**Step 2.3 — Make downsampling zoom-aware**
When `effectiveZoom > 1.0`:
- Resample from the full (undownsampled) records within the visible `xDomain` window
- Use the detail resolution (120 points) for the visible window instead of the card resolution (60 points) spread across the full range
- This ensures zooming in reveals more detail, not less

---

### Phase 3: Consolidate — Build Reusable Chart Components

**Step 3.1 — Create `MetricChartView`**
A single reusable view that replaces the duplicated chart body:
```swift
struct MetricChartView: View {
    let records: [HealthRecord]
    let definition: MetricDefinition
    let xDomain: ClosedRange<Date>?
    let height: CGFloat
    let maxPoints: Int
    let showAnnotations: Bool

    // Handles: BarMark/LineMark branching, RuleMarks for reference range,
    // axis configuration, downsampling (cached), consistent styling
}
```
Adopt in: `ComparisonMetricChart`, `GenericMetricChart`, `MetricDetailView.chartCard`

**Step 3.2 — Create `BPChartView`**
Same concept for BP dual-series charts:
```swift
struct BPChartView: View {
    let records: [HealthRecord]
    let xDomain: ClosedRange<Date>?
    let height: CGFloat
    let maxPoints: Int
    // Handles: systolic + diastolic LineMark, reference lines from definition,
    // legend, consistent styling
}
```
Adopt in: `ComparisonBPChart`, `BPTrendChart`

**Step 3.3 — Create `ChartCardChrome`**
Extract the card shell (header with icon/name/value, hide/expand buttons, footer stats, padding/background/corner radius) into a container view:
```swift
struct ChartCardChrome<Content: View>: View {
    let definition: MetricDefinition
    let latestValue: String
    let onExpand: () -> Void
    let onHide: () -> Void
    @ViewBuilder let chart: () -> Content
}
```
Adopt in: `ComparisonMetricChart`, `ComparisonBPChart`

**Step 3.4 — Create `ReferenceRangeOverlay`**
```swift
struct ReferenceRangeOverlay: ChartContent {
    let definition: MetricDefinition
    let showAnnotations: Bool
    // Emits 0-2 RuleMarks with consistent dash, color, annotation style
}
```

**Step 3.5 — Dispatch on `ChartStyle` instead of string comparison**
Replace `if metricType == MetricType.bloodPressure` with `switch definition.chartStyle`:
```swift
switch definition.chartStyle {
case .bpDual: BPChartView(...)
case .line, .bar: MetricChartView(...)
}
```

---

### Phase 4: Break Up the God File

**Step 4.1 — Extract `ChartTimeRange` to `Models/ChartTimeRange.swift`**
It's a model enum, not a view concern.

**Step 4.2 — Extract BP detail charts to `Views/BPDetailCharts.swift`**
Move `BPTrendChart`, `PulseChart`, `BPSummaryCard`, `WeeklyAveragesChart`, `MorningVsEveningChart`, `MAPTrendChart` — all only used in `ChartsContainerView.bpExpandedCharts()`.

**Step 4.3 — Extract `SavedViewsSheet` to `Views/SavedViewsSheet.swift`**

**Step 4.4 — Extract `ChartFilterSheet` to `Views/ChartFilterSheet.swift`**

After this, `ChartsContainerView.swift` should be ~500-600 lines: just the container, zoom/pan logic, and layout orchestration.

---

### Phase 5: Unify MetricDetailView with Charts Tab

**Step 5.1 — Replace MetricDetailView's inline chart with `MetricChartView`**
Use the same component the Charts tab uses. Pass the same height, downsample count, and styling.

**Step 5.2 — Add zoom/pan support to MetricDetailView**
Extract the zoom/pan gesture logic from `ChartsContainerView` into a reusable `ChartZoomState` ObservableObject or a ViewModifier, then apply it to MetricDetailView.

**Step 5.3 — Share summary stats computation**
Both MetricDetailView and the Charts tab expanded views compute avg/min/max/count. Use a shared `MetricStats` struct:
```swift
struct MetricStats {
    let average: Double
    let min: Double
    let max: Double
    let count: Int
    let inRangePercent: Double?

    init(records: [HealthRecord], definition: MetricDefinition) { ... }
}
```

---

### Phase 6: Adopt Apple's Native Chart Interactivity

**Step 6.1 — Add `chartXSelection` for data point inspection**
Use Apple's built-in `.chartXSelection(value: $selectedDate)` modifier (iOS 17+) to show a tooltip/annotation when the user taps on a chart. This is the #1 missing interaction for a charts-heavy app.

**Step 6.2 — Evaluate `chartScrollableAxes` as a replacement for custom zoom/pan**
The current MagnifyGesture + DragGesture + manual xDomain calculation works but fights with ScrollView gestures and limits pan to the zoom indicator bar. Apple's native `.chartScrollableAxes(.horizontal)` + `.chartXVisibleDomain()` + `.chartScrollPosition()` may provide a better UX with less code. Evaluate whether it meets the app's needs:
- Pro: native gesture handling, no ScrollView conflicts, chartScrollTargetBehavior for snapping
- Con: may not support pinch-to-zoom natively (only scrolling), less control over zoom levels
- Decision: If pinch-zoom is essential, keep the custom implementation but fix the pan gesture target. If scroll + visible domain is sufficient, migrate to native.

**Step 6.3 — Improve accessibility**
- Add `accessibilityChartDescriptor` to chart views
- Add symbol differentiation for `Differentiate Without Color` setting
- Ensure chart data points are navigable via VoiceOver
- Use higher-contrast colors when `Increase Contrast` is active

---

### Phase 7: Data Layer Improvements

**Step 7.1 — Remove or increase the 500-record cap**
Options:
- Remove `fetchLimit` entirely (may impact memory for power users)
- Increase to 2000+ with lazy loading
- Implement progressive loading: load 500 for default view, fetch more when user selects "All Time" or zooms beyond the cached range

**Step 7.2 — Upgrade downsampling to LTTB**
Replace the naive stride algorithm with LTTB (Largest Triangle Three Buckets) which preserves visual shape — peaks, valleys, and trends are retained even at aggressive downsampling ratios. Swift implementation: [GuillaumeBeal/LTTB](https://github.com/GuillaumeBeal/LTTB) or implement the ~30-line algorithm directly.

**Step 7.3 — Unify date range management**
Create a single `ChartDateRange` model that replaces:
- `ChartTimeRange` enum in `ChartsContainerView`
- `@AppStorage("dashboardChartDays")` in `DashboardView`
- Manual date arithmetic in `MetricDetailView`

---

### Execution Order & Dependencies

```
Phase 0 (Foundation)     ← No dependencies, safe refactor, do first
    │
Phase 1 (Critical Bugs) ← Depends on Phase 0 for constants/utilities
    │
Phase 2 (Performance)   ← Depends on Phase 0 for ChartUtilities
    │
Phase 3 (Consolidate)   ← Depends on Phase 0, 1, 2 for clean base
    │
Phase 4 (Break up file) ← Depends on Phase 3 (new components reduce file size)
    │
Phase 5 (Unify Detail)  ← Depends on Phase 3 (uses MetricChartView)
    │
Phase 6 (Native APIs)   ← Depends on Phase 3, 5 (single component to modify)
    │
Phase 7 (Data Layer)    ← Independent of Phases 3-6, can run in parallel after Phase 2
```

---

### Risk Notes

- **Phase 3 is the highest-risk phase** — it touches every chart view. Test each chart type (line, bar, bpDual, dual-axis) across all contexts (dashboard, charts tab, expanded, detail) after each step.
- **Phase 6.2 (native scrolling)** requires prototyping — don't commit to replacing the custom zoom system until the native approach is proven to meet needs.
- **Phase 7.1 (record cap)** — profile memory usage before removing limits. 5000+ HealthRecords in memory could impact low-RAM devices.
- **Throughout:** Run the app after every step. Chart code has many subtle visual and interaction behaviors that are hard to catch in code review alone.
