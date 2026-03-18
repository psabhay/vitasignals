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

> **All P1 and P2 items below have been fixed.** The descriptions are kept for reference.

### P1 — High Impact ✅ Fixed

#### 1. HealthDataStore.refresh() loads ALL records into memory ✅
- **Fix applied:** Removed stored `allRecords` @Published property — now a lazy computed property from `recordsByType`. Added `fetchLimit: 5000` to the main query. Added `fetchRecords(from:to:metricTypes:)` for targeted report queries.

#### 2. DashboardView.cardDataList recomputes on every render ✅
- **Fix applied:** Replaced computed `cardDataList` with `@State cachedCardData` + `recomputeCardData()` triggered only by `onReceive(dataStore.objectWillChange)` and `onAppear`.

#### 3. DataBrowserView computes filteredRecords 3× per render ✅
- **Fix applied:** Consolidated 4 computed properties into single `FilteredResult` struct computed once per render.

#### 4. MetricDetailView uses @Query — inconsistent with rest of app ✅
- **Fix applied:** Migrated from `@Query` to `HealthDataStore.records(for:)`. Removed SwiftData import.

#### 5. PDF generation runs at default priority ✅
- **Fix applied:** `Task.detached(priority: .background)`.

#### 6. DateFormatter created on every PDF export ✅
- **Fix applied:** Cached as `static let` in PDFGenerator.

#### 7. Force unwraps in PDFGenerator (7 instances) ✅
- **Fix applied:** All 7 force unwraps replaced with safe nil-coalescing alternatives.

### P2 — Medium Impact ✅ Fixed

#### 8. SyncWorker creates a new ModelContext per metric ✅
- **Fix applied:** Single shared `ModelContext` created in `syncAll()` and passed to all sync methods. Single `context.save()` at the end.

#### 9. ChartsContainerView sorts records in body ✅
- **Fix applied:** Added `sortedForChart` computed property — sorted once, used by both `bpCharts` and `genericChart`.

#### 10. DispatchQueue.main.asyncAfter for sheet transitions ✅
- **Fix applied:** Removed fragile asyncAfter(0.35) pattern. Sheet item identity change handles transitions directly.

#### 11. fatalError in app entry point ✅
- **Fix applied:** Replaced `fatalError` with optional `ModelContainer?` and a graceful `DatabaseErrorView` explaining the issue to users.

---

## Summary

The app is **ready for App Store submission** from a compliance standpoint. The only remaining item is hosting a privacy policy URL (done in App Store Connect, not in code).

All 11 performance optimizations (P1 and P2) have been implemented and verified.
