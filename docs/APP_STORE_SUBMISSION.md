# VitaSignals — App Store Submission Guide

Everything you need to fill in on App Store Connect to submit VitaSignals.

---

## App Information

| Field | Value |
|---|---|
| **App Name** | VitaSignals |
| **Subtitle** | Health Tracking & Reports |
| **Bundle ID** | `com.vitasignals.app` |
| **SKU** | `vitasignals-ios-001` |
| **Primary Language** | English (U.S.) |
| **Primary Category** | Health & Fitness |
| **Secondary Category** | Medical |
| **Content Rights** | Does not contain, show, or access third-party content |

---

## Pricing & Availability

| Field | Value |
|---|---|
| **Price** | Free (no in-app purchases) |
| **Availability** | All territories (or choose specific) |

---

## Version Information

| Field | Value |
|---|---|
| **Version Number** | 1.0.0 |
| **Build Number** | 1 |
| **Platform** | iOS |
| **Minimum iOS Version** | 17.0 |
| **Supported Devices** | iPhone only (`TARGETED_DEVICE_FAMILY: 1`) |

---

## App Store Description

### Promotional Text (170 characters max — can be updated without a new build)

```
Track 60+ health metrics from Apple Health, create custom metrics, visualize trends, and generate professional PDF reports for your doctor.
```

### Description (4000 characters max)

```
VitaSignals brings all your health data together in one place. Whether you track blood pressure, heart rate, sleep, steps, nutrition, or any custom metric — VitaSignals gives you the tools to understand your health trends and share them with your healthcare provider.

DASHBOARD
See your health at a glance. The Dashboard shows your latest readings, 7-day trends, sparkline charts, and personalized highlights like logging streaks and trending metrics. Blood pressure gets a dedicated trend card with category badges (Normal, Elevated, High Stage 1/2, Crisis).

60+ HEALTH METRICS FROM APPLE HEALTH
Automatically sync data from Apple Health, including:
• Vitals — blood pressure, heart rate, blood glucose, body temperature
• Cardio Fitness — resting heart rate, HRV, VO2 Max, walking heart rate
• Activity — steps, exercise minutes, active energy, cycling, swimming
• Body — weight, BMI, body fat, height
• Sleep — total sleep duration across all stages
• Respiratory — respiratory rate, blood oxygen (SpO2)
• Nutrition — calories, protein, carbs, fat, water, caffeine, vitamins
• Mobility — walking speed, step length, stair speed, walking steadiness

CUSTOM METRICS
Track anything Apple Health doesn't cover. Create your own metrics with custom names, units, icons, and colors. Log coffee consumption, mood, medication doses — whatever matters to you.

INTERACTIVE CHARTS
Compare multiple metrics side by side with shared date ranges. Pinch-to-zoom for detail, drag to pan. Save your favorite chart configurations as bookmarks to reload instantly.

PROFESSIONAL PDF REPORTS
Generate clinical-quality PDF health reports to share with your doctor. Choose from four templates (Comprehensive, Summary, Cardio Focus, Provider Report) and three visual styles (Classic, Modern, Clinical). Reports include trend charts, statistical summaries, and reference ranges.

DATA BROWSER
Browse, filter, and manage all your health records. Filter by category or individual metric. Add, edit, or delete entries. Records imported from Apple Health are clearly marked.

PRIVACY FIRST
All data stays on your device. VitaSignals never sends your health data to any server. No accounts, no cloud sync, no analytics, no ads.

IMPORTANT: VitaSignals is not a medical device and does not provide medical advice, diagnosis, or treatment. Health data classifications are for informational purposes only. Always consult a qualified healthcare provider for medical decisions.
```

### Keywords (100 characters max, comma-separated)

```
health,blood pressure,heart rate,health tracker,medical report,PDF,HealthKit,vitals,fitness,wellness
```

---

## What's New in This Version

```
Initial release of VitaSignals.
```

---

## App Review Information

### Contact Information

| Field | Value |
|---|---|
| **First Name** | _(your first name)_ |
| **Last Name** | _(your last name)_ |
| **Phone** | _(your phone number)_ |
| **Email** | _(your email)_ |

### Review Notes

Paste this in the "Notes" field for the reviewer:

```
VitaSignals is a personal health data aggregation and visualization tool. It reads health data from Apple Health (read-only — no writing to HealthKit) and allows users to create custom metrics.

KEY POINTS FOR REVIEW:
• The app requires HealthKit permission to import health data. If denied, the app still functions fully with manually entered data and custom metrics.
• The app does NOT diagnose, treat, or prescribe. It is a data organization and reporting tool, not a medical device. It does not make treatment recommendations.
• Blood pressure classifications (Normal, Elevated, High Stage 1, High Stage 2, Hypertensive Crisis) follow standard AHA guidelines and are labeled "for informational purposes only."
• All data is stored locally on-device via SwiftData. No server communication, no analytics, no tracking.
• PDF reports are generated locally and shared via the system share sheet.
• No sign-in required. The app uses a simple on-device profile (name, age, etc.) for report personalization.

TO TEST:
1. On first launch, complete the onboarding profile (only name is required).
2. Grant HealthKit access when prompted (or deny it to test custom-metrics-only mode).
3. If testing on a simulator without HealthKit data, use the "Load Sample Data" debug button (only visible in debug builds — not in the release build).
4. Navigate the four tabs: Dashboard, Data, Charts, Reports.
5. Try generating a PDF report from the Reports tab.

DEMO ACCOUNT: None required — no sign-in or server needed.
```

### Sign-In Required

**No** — the app does not require sign-in.

---

## Age Rating

Answer these questions on App Store Connect:

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Prolonged Graphic or Sadistic Realistic Violence | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | **Infrequent/Mild** |
| Alcohol, Tobacco, or Drug Use or References | None |
| Simulated Gambling | None |
| Sexual Content or Nudity | None |
| Unrestricted Web Access | No |
| Gambling with Real Currency | No |

**Resulting rating: 12+** (due to Medical/Treatment Information — the app shows BP classifications and health reference ranges)

---

## App Privacy (Privacy Nutrition Labels)

On App Store Connect, go to **App Privacy** and answer:

### Does your app collect any data?

**Yes**

### Data Types Collected

**Health & Fitness > Health**

| Question | Answer |
|---|---|
| Is this data linked to the user's identity? | **No** |
| Is this data used for tracking? | **No** |
| What purposes is this data collected for? | **App Functionality** |

That is the ONLY data type to declare. The app collects no other categories (no identifiers, no usage data, no diagnostics, no contact info, etc.).

### Why only "Health" data?

- The user profile (name, age, etc.) is stored only on-device and never leaves the device. It is not collected by the developer. Per Apple's guidelines, on-device-only data that is not sent off-device does not need to be declared.
- No analytics, crash reporting, or any server communication exists.

---

## Export Compliance

| Question | Answer |
|---|---|
| Does your app use encryption? | **No** |
| Does your app qualify for any exemptions? | N/A (no encryption used) |
| Does your app contain, display, or access third-party content? | **No** |

**Recommendation:** Add this key to `Info.plist` to permanently skip the annual export compliance prompt:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

---

## HealthKit Entitlement

The app uses the HealthKit entitlement. Ensure the following are in place:

1. **Entitlements file** (`VitaSignals.entitlements`): `com.apple.developer.healthkit = true`
2. **Info.plist**: `NSHealthShareUsageDescription` is set (read-only access)
3. **No** `NSHealthUpdateUsageDescription` (app does not write to HealthKit)
4. **App ID configuration**: HealthKit capability must be enabled in your Apple Developer account under Certificates, Identifiers & Profiles > Identifiers > your App ID > Capabilities.

### HealthKit Usage Description (exact string in Info.plist)

> VitaSignals reads your health and wellness data from Apple Health — including vitals, blood pressure, heart rate, respiratory metrics, activity, sleep, nutrition, body measurements, mobility, and other available metrics — to generate comprehensive health reports for your healthcare provider. All data remains on your device.

---

## Screenshots

Prepare screenshots for these device sizes (required for submission):

- **6.7" Display** (iPhone 15 Pro Max / iPhone 16 Pro Max) — required
- **6.5" Display** (iPhone 11 Pro Max) — required if supporting older devices
- **5.5" Display** (iPhone 8 Plus) — optional

### Recommended Screenshots (in order)

1. **Dashboard** — Health Overview strip with sparklines, BP trend card, highlights
2. **Charts** — Multi-metric comparison view with time range selector
3. **Charts (zoomed)** — Pinch-zoomed view showing detail on a specific date range
4. **PDF Report** — Generated report preview (Classic or Modern style)
5. **Data Browser** — Records list with category filter chips
6. **Custom Metric** — Creation form showing icon/color picker
7. **Add Record** — Metric picker grid showing all categories including Custom
8. **Onboarding** — Welcome/profile setup screen

### Screenshot Tips

- Use a device with real or realistic health data for compelling screenshots
- The app supports dark mode — consider showing 1-2 dark mode screenshots
- Do NOT include the status bar time, battery, or carrier — use Xcode's simulator screenshot feature or clean status bar tool

---

## App Store Icon

The app icon is at:
```
VitaSignals/Resources/Assets.xcassets/AppIcon.appiconset/appicon.png
```

App Store Connect requires a **1024x1024** icon (no transparency, no rounded corners — Apple applies the mask). Ensure the icon file meets this requirement.

---

## Frameworks & Capabilities Checklist

Verify these are correctly configured before submission:

- [x] HealthKit capability enabled in Apple Developer Portal
- [x] HealthKit entitlement in app
- [x] `NSHealthShareUsageDescription` in Info.plist
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) present and accurate
- [x] No third-party SDKs (no IDFA, no tracking)
- [x] `ITSAppUsesNonExemptEncryption = false` in Info.plist (add if not present)
- [x] App icon is 1024x1024

---

## Common Rejection Reasons to Avoid

1. **HealthKit rejection**: Apple is strict about HealthKit apps. Ensure the usage description clearly explains WHY you need each data type. Our description covers this comprehensively.

2. **Medical claims**: Never claim the app diagnoses or treats conditions. The app includes disclaimers in onboarding, profile section, and every PDF report.

3. **Missing purpose string**: If the HealthKit permission dialog appears without a clear usage description, the app will be rejected. Ours is set in Info.plist.

4. **Crash on permission denial**: The app must work if the user denies HealthKit access. VitaSignals handles this — the dashboard shows a gentle prompt and the user can still use custom metrics and manual entry.

5. **Minimum functionality**: Apple may reject apps that don't work without HealthKit data. VitaSignals works fully with custom metrics and manual data entry, so this is covered.

6. **Privacy label mismatch**: The App Privacy nutrition labels must match what the app actually does. We only declare "Health" data for "App Functionality" — accurate and complete.

---

## Pre-Submission Checklist

Before uploading your build:

- [ ] Archive the app with a Release configuration (not Debug)
- [ ] Verify the debug-only "Load Sample Data" button is NOT visible in the Release build
- [ ] Test on a real device with actual HealthKit data
- [ ] Test with HealthKit permission denied — verify the app still works
- [ ] Generate a PDF report and verify it renders correctly
- [ ] Verify the onboarding flow works on a fresh install
- [ ] Check the app icon renders correctly at all sizes
- [ ] Run the full test suite (`xcodebuild test`) — all 46 tests should pass
- [ ] Upload using Xcode Organizer or `xcodebuild -exportArchive`
