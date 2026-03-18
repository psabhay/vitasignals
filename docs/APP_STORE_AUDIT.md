# Neo Health Export — App Store Audit & Optimization Report

**Date:** March 18, 2026
**App Version:** 1.0.0
**Bundle ID:** com.abhaysingh.neohealthexport
**Deployment Target:** iOS 17.0

---

## App Overview

Neo Health Export is a health data tracking app that syncs with Apple HealthKit, allows manual entry of health metrics (blood pressure, heart rate, sleep, weight, and 50+ more), displays interactive charts/trends, and generates professional PDF reports for healthcare providers.

---

## App Store Compliance Status

### ✅ Passing

| Guideline | Status | Details |
|-----------|--------|---------|
| 4.2 — Minimum Functionality | ✅ | Dashboard, data browser, charts, PDF reports, HealthKit sync, onboarding, profile |
| 5.1.1 — Data Collection | ✅ | Fully offline. No network calls, no analytics, no tracking |
| 5.1.2 — Privacy Manifest | ✅ | `PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1) and HealthKit data usage |
| 27.1 — HealthKit Entitlement | ✅ | `com.apple.developer.healthkit: true` in entitlements |
| 27.2 — HealthKit Usage Desc | ✅ | `NSHealthShareUsageDescription` present in Info.plist |
| 27.3 — HealthKit Read-Only | ✅ | Only requests read access (`toShare: []`) |
| 27.4 — No Medical Diagnosis | ✅ | Health disclaimer in onboarding and profile. PDF includes disclaimer |
| 4.8 — Sign in with Apple | ✅ N/A | No login system |
| 3.1.1 — In-App Purchase | ✅ N/A | No monetization code |
| 2.3 — App Icon | ✅ | 1024×1024 PNG present |
| 2.5.1 — No Private APIs | ✅ | Only Apple public frameworks used |
| Launch Screen | ✅ | `UILaunchScreen` key present |
| No Unused Capabilities | ✅ | `UIBackgroundModes` removed (was unused) |
| Naming Consistency | ✅ | All user-facing strings say "Neo Health Export" |

### ⚠️ Remaining Action (Non-Code)

| # | Action | Where |
|---|--------|-------|
| 1 | **Host a Privacy Policy URL** | Required in App Store Connect before submission (Guideline 5.1.1). Even though the app collects no data and is fully offline, Apple requires all apps to provide one. |

---

## Performance & Optimization Recommendations

### P1 — High Impact (Recommended Before Launch)

#### 1. HealthDataStore.refresh() loads ALL records into memory
- **File:** `NeoHealthExport/Helpers/HealthDataStore.swift`
- **Problem:** `refresh()` fetches every HealthRecord from the database with no limit. For active users syncing from Apple Health, this could be 10,000+ records held in `allRecords`.
- **Impact:** High memory usage, slow refresh on large datasets.
- **Fix:** Add fetch limits for display purposes; use lazy pagination for the data browser. Keep only recent records (e.g., 90 days) in memory and fetch older data on demand.

#### 2. DashboardView.cardDataList recomputes on every render
- **File:** `NeoHealthExport/Views/DashboardView.swift` (lines 68–85)
- **Problem:** `cardDataList` is a computed property on the view body. It iterates all non-BP metric types, fetches records, filters last 7 days, sorts, and maps — all recomputed on every SwiftUI invalidation.
- **Impact:** Sluggish dashboard with many metrics.
- **Fix:** Cache in `@State` and recompute only when `dataStore.objectWillChange` fires.

#### 3. DataBrowserView computes filteredRecords 3× per render
- **File:** `NeoHealthExport/Views/DataBrowserView.swift` (lines 28–55)
- **Problem:** `filteredRecords`, `displayRecords`, `hasMoreRecords`, and `groupedRecords` all independently re-derive from the same data on every body evaluation.
- **Impact:** O(n) work multiplied 3–4× per render.
- **Fix:** Compute once and pass the result through a single struct.

#### 4. MetricDetailView uses @Query — inconsistent with rest of app
- **File:** `NeoHealthExport/Views/MetricDetailView.swift` (line 7)
- **Problem:** This is the only view still using `@Query` for HealthRecord instead of the shared `HealthDataStore`. Creates a parallel fetch pipeline.
- **Impact:** Extra memory for duplicate query results; inconsistent data timing after sync.
- **Fix:** Migrate to `HealthDataStore.records(for:)` for consistency.

#### 5. PDF generation runs at default priority
- **File:** `NeoHealthExport/Views/ReportBuilderView.swift` (line 316)
- **Problem:** `Task.detached { }` without specifying `.priority(.background)` — competes with UI thread.
- **Fix:** Use `Task.detached(priority: .background) { }`.

#### 6. DateFormatter created on every PDF export
- **File:** `NeoHealthExport/Helpers/PDFGenerator.swift` (lines 917–921)
- **Problem:** `dateStamp()` creates a new `DateFormatter` each call. DateFormatter is notoriously expensive to instantiate.
- **Fix:** Use a `static let` cached formatter.

#### 7. Force unwraps in PDFGenerator (7 instances)
- **File:** `NeoHealthExport/Helpers/PDFGenerator.swift` (lines 296, 337–340, 428–429)
- **Problem:** `.min()!`, `.max()!`, `.last!` will crash if arrays are unexpectedly empty. Guards exist upstream but defense-in-depth is safer.
- **Fix:** Replace with nil-coalescing (`?? 0`) or `guard let`.

### P2 — Medium Impact (Nice to Have)

#### 8. SyncWorker creates a new ModelContext per metric
- **File:** `NeoHealthExport/Helpers/HealthSyncManager.swift` (line 163)
- **Problem:** Each `syncMetric()` call creates its own `ModelContext(container)`. During a full sync with 10+ metrics, this means 10+ contexts.
- **Fix:** Create one shared background context and pass it through all sync operations.

#### 9. ChartsContainerView sorts records in body
- **File:** `NeoHealthExport/Views/ChartsContainerView.swift` (lines 108, 122)
- **Problem:** `.sorted { $0.timestamp < $1.timestamp }` called every time `bpCharts` or `genericChart` is evaluated.
- **Fix:** Sort once in a cached computed property or in `onChange`.

#### 10. DispatchQueue.main.asyncAfter for sheet transitions
- **Files:** `DashboardView.swift:139`, `DataBrowserView.swift:134`
- **Problem:** Fragile 0.35-second delays to dismiss one sheet then present another. Can fail on slow devices or feel laggy on fast ones.
- **Fix:** Use `onChange(of: activeSheet)` or a two-phase state machine for sheet presentation.

#### 11. fatalError in app entry point
- **File:** `NeoHealthExport/App/NeoHealthExportApp.swift` (line 24)
- **Problem:** If SwiftData store creation fails twice (after deleting the corrupted store), the app crashes with `fatalError`. This gives users no recovery path.
- **Fix:** Show a graceful error screen with a "Reset Data" button instead of crashing.

---

## Summary

The app is **ready for App Store submission** from a compliance standpoint. The only remaining item is hosting a privacy policy URL (done in App Store Connect, not in code).

For performance, the P1 items (especially #1, #2, #3) will make the biggest difference for users with large datasets. The force-unwrap fixes (#7) are low-effort high-safety improvements worth doing before launch.
