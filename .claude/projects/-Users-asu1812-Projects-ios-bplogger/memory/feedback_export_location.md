---
name: Export only in Profile
description: Reports/export feature should only be in Profile, never per-metric or per-screen
type: feedback
---

Export/report generation belongs exclusively in the Profile screen. No per-metric export buttons. The current report builder flow (choose metrics, date range, template, style, generate PDF) is exactly right — it just needs to live in Profile.

**Why:** Single-metric export is not useful. Users only need full multi-metric reports (e.g., for doctor visits). Putting export everywhere clutters the UI.

**How to apply:** When restructuring navigation, move ReportBuilderView into Profile. Do not add export buttons to MetricDetailView or individual chart cards.
