import UIKit

struct PDFGenerator {
    // MARK: - Layout
    private static let pw: CGFloat = 612
    private static let ph: CGFloat = 792
    private static let m: CGFloat = 48
    private static let cw: CGFloat = 612 - 96

    // MARK: - Metric Colors (fixed, not theme-dependent)
    private static let red       = UIColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1)
    private static let blue      = UIColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 1)
    private static let pink      = UIColor(red: 0.75, green: 0.25, blue: 0.40, alpha: 1)
    private static let green     = UIColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 1)
    private static let orange    = UIColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 1)
    private static let purple    = UIColor(red: 0.50, green: 0.20, blue: 0.60, alpha: 1)
    private static let yellow    = UIColor(red: 0.65, green: 0.58, blue: 0.05, alpha: 1)
    private static let teal      = UIColor(red: 0.15, green: 0.55, blue: 0.55, alpha: 1)
    private static let indigo    = UIColor(red: 0.30, green: 0.20, blue: 0.60, alpha: 1)

    private static func catColor(_ c: BPCategory) -> UIColor {
        switch c { case .normal: return green; case .elevated: return yellow; case .highStage1: return orange; case .highStage2: return red; case .crisis: return purple }
    }

    private static func metricColor(_ type: String) -> UIColor {
        switch type {
        case MetricType.bloodPressure: return red
        case MetricType.restingHeartRate: return pink
        case MetricType.heartRateVariability: return purple
        case MetricType.vo2Max: return orange
        case MetricType.stepCount: return green
        case MetricType.exerciseMinutes: return teal
        case MetricType.activeEnergy: return yellow
        case MetricType.bodyMass: return orange
        case MetricType.sleepDuration: return indigo
        case MetricType.respiratoryRate: return teal
        case MetricType.oxygenSaturation: return red
        default: return blue
        }
    }

    // MARK: - Profile Data
    struct ProfileData: Sendable {
        let name: String
        let age: Int
        let gender: String
        let heightCm: Double
        let weightKg: Double
        let doctorName: String
        let medicalNotes: String

        var bmi: Double? {
            guard heightCm > 0, weightKg > 0 else { return nil }
            let hm = heightCm / 100
            return weightKg / (hm * hm)
        }
        var bmiCategory: String {
            guard let bmi else { return "" }
            switch bmi {
            case ..<18.5: return "Underweight"
            case 18.5..<25: return "Normal"
            case 25..<30: return "Overweight"
            default: return "Obese"
            }
        }
        var heightFormatted: String {
            guard heightCm > 0 else { return "" }
            let totalInches = heightCm / 2.54
            return "\(Int(totalInches) / 12)'\(Int(totalInches) % 12)\" (\(Int(heightCm)) cm)"
        }
        var weightFormatted: String {
            guard weightKg > 0 else { return "" }
            return String(format: "%.0f kg (%.0f lbs)", weightKg, weightKg * 2.20462)
        }

        init(from profile: UserProfile) {
            self.name = profile.name
            self.age = profile.age
            self.gender = profile.gender
            self.heightCm = profile.heightCm
            self.weightKg = profile.weightKg
            self.doctorName = profile.doctorName
            self.medicalNotes = profile.medicalNotes
        }
    }

    // MARK: - State
    private class State {
        var y: CGFloat = 0
        var page = 0
        let ctx: CGContext
        let style: ReportStyle
        init(_ ctx: CGContext, style: ReportStyle) { self.ctx = ctx; self.style = style }
    }

    // MARK: - Generate (new universal API)

    static func generate(
        records: [HealthRecord],
        selectedMetrics: Set<String>? = nil,
        periodLabel: String = "",
        profile: ProfileData? = nil,
        style: ReportStyle = .classic
    ) -> URL? {
        guard !records.isEmpty else { return nil }
        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Health_Report_\(dateStamp()).pdf")
        UIGraphicsBeginPDFContextToFile(url.path, CGRect(x: 0, y: 0, width: pw, height: ph), [
            kCGPDFContextTitle as String: "Health Report",
            kCGPDFContextCreator as String: "Health Logger"
        ])
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let s = State(ctx, style: style)

        let metrics = selectedMetrics ?? Set(sorted.map(\.metricType))
        let bpRecords = sorted.filter { $0.metricType == MetricType.bloodPressure }

        // ── PAGE 1: Summary ──
        newPage(s)
        drawHeader(s, records: sorted, periodLabel: periodLabel, profile: profile)
        if let profile, !profile.name.isEmpty {
            drawPatientInfo(s, profile: profile)
        }

        // BP Summary (if BP data included)
        if metrics.contains(MetricType.bloodPressure) && !bpRecords.isEmpty {
            drawBPSummaryTable(s, records: bpRecords)
            drawClassificationTable(s, records: bpRecords)
        }

        // Summary of other metrics
        let nonBPMetrics = metrics.filter { $0 != MetricType.bloodPressure }
        if !nonBPMetrics.isEmpty {
            drawMetricsSummary(s, records: sorted, metricTypes: nonBPMetrics)
        }
        footer(s)

        // ── BLOOD PRESSURE SECTION ──
        if metrics.contains(MetricType.bloodPressure) && !bpRecords.isEmpty {

            // BP Charts Page
            if bpRecords.count >= 2 {
                newPage(s)
                drawSectionHeader(s, title: "BLOOD PRESSURE", subtitle: "Trends & Heart Rate")
                section(s, "BLOOD PRESSURE TREND")
                drawBPChart(s, records: bpRecords)
                s.y += 16
                section(s, "HEART RATE TREND")
                drawPulseChart(s, records: bpRecords)
                footer(s)
            }

            // BP Time-of-Day Analysis
            if bpRecords.count >= 3 {
                drawTimeOfDayPage(s, records: bpRecords)
            }
        }

        // ── Other Health Metrics (grouped by category, flowing layout) ──
        let drawableMetrics = nonBPMetrics.sorted().compactMap { type -> (MetricDefinition, [HealthRecord])? in
            let recs = sorted.filter { $0.metricType == type }
            guard recs.count >= 2, let def = MetricRegistry.definition(for: type) else { return nil }
            return (def, recs)
        }
        if !drawableMetrics.isEmpty {
            let chartBlockHeight: CGFloat = 200
            // Group by category, preserving MetricCategory.allCases order
            let byCategory = Dictionary(grouping: drawableMetrics) { $0.0.category }
            let orderedCategories = MetricCategory.allCases.filter { byCategory[$0] != nil }

            for category in orderedCategories {
                guard let categoryMetrics = byCategory[category] else { continue }

                // Each category starts a new page with its own section header
                newPage(s)
                drawSectionHeader(s, title: category.rawValue.uppercased(), subtitle: "\(categoryMetrics.count) metric\(categoryMetrics.count == 1 ? "" : "s") with trend data")

                for (def, metricRecords) in categoryMetrics {
                    pageBreak(s, chartBlockHeight)

                    let color = metricColor(def.type)
                    section(s, "\(def.name.uppercased()) TREND")
                    if let desc = def.description {
                        text(s, desc, font: s.style.captionFont, color: s.style.mutedTextColor, w: cw)
                        s.y += 4
                    }

                    let values = metricRecords.map { DailyValue(date: $0.timestamp, value: $0.primaryValue) }
                    var refLines: [(Double, String, UIColor)] = []
                    if let refMin = def.referenceMin { refLines.append((refMin, "Min \(def.formatValue(refMin))", green)) }
                    if let refMax = def.referenceMax { refLines.append((refMax, "Max \(def.formatValue(refMax))", green)) }

                    let zoneRange: (Double, Double, UIColor)? = {
                        if let lo = def.referenceMin, let hi = def.referenceMax { return (lo, hi, green) }
                        return nil
                    }()

                    if def.chartStyle == .bar {
                        drawDailyBarChart(s, values: values, color: color, unit: def.unit,
                                          targetLine: def.referenceMin, targetLabel: def.referenceMin != nil ? "Target" : "")
                    } else {
                        drawDailyChart(s, values: values, color: color, unit: def.unit,
                                       refLines: refLines, zoneRange: zoneRange)
                    }

                    let avg = values.map(\.value).reduce(0, +) / Double(values.count)
                    text(s, String(format: "Average: %@ %@  |  %d data points", def.formatValue(avg), def.unit, values.count), font: s.style.monoFont, color: s.style.secondaryTextColor)
                    s.y += 20
                }
                footer(s)
            }
        }

        // Disclaimer
        pageBreak(s, 32)
        s.y += 12
        hline(s, color: s.style.borderColor)
        s.y += 6
        text(s, "Disclaimer: This report is generated from self-recorded data and data imported from Apple Health. It is intended as a supplementary reference for healthcare providers and should not be used for self-diagnosis or treatment decisions.", font: s.style.captionFont, color: s.style.mutedTextColor, w: cw)

        // ── ANNEXURE: BP Data Table (at the very end) ──
        if metrics.contains(MetricType.bloodPressure) && !bpRecords.isEmpty {
            newPage(s)
            drawSectionHeader(s, title: "BLOOD PRESSURE", subtitle: "Annexure — Detailed Readings")
            section(s, "DETAILED BP READINGS  (\(bpRecords.count))")
            drawBPReadingsTable(s, records: bpRecords)
        }

        footer(s)

        UIGraphicsEndPDFContext()
        return url
    }

    // MARK: - Page Helpers

    private static func newPage(_ s: State) {
        UIGraphicsBeginPDFPage()
        s.page += 1
        s.y = m
    }

    private static func pageBreak(_ s: State, _ needed: CGFloat) {
        if s.y + needed > ph - m - 28 { footer(s); newPage(s) }
    }

    private static func footer(_ s: State) {
        let fy = ph - 30
        hline(s, y: fy - 6, color: s.style.borderColor)
        let la: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
        (s.style.footerText as NSString).draw(at: CGPoint(x: m, y: fy), withAttributes: la)
        let rt = "Page \(s.page)"
        let rs = (rt as NSString).size(withAttributes: la)
        (rt as NSString).draw(at: CGPoint(x: pw - m - rs.width, y: fy), withAttributes: la)
    }

    // MARK: - Section Page Header

    private static func drawSectionHeader(_ s: State, title: String, subtitle: String) {
        // Accent bar at top
        s.ctx.setFillColor(s.style.accentColor.cgColor)
        s.ctx.fill(CGRect(x: m, y: s.y, width: cw, height: s.style.sectionBarHeight))
        s.y += 8

        // Section heading
        let titleA: [NSAttributedString.Key: Any] = [.font: s.style.sectionHeaderFont, .foregroundColor: s.style.accentColor]
        (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: titleA)
        s.y += 18

        // Subtitle
        let subA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: s.style.mutedTextColor]
        (subtitle as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: subA)
        s.y += 14

        hline(s, color: s.style.accentColor.withAlphaComponent(0.3), width: 1)
        s.y += 12
    }

    // MARK: - Header

    private static func drawHeader(_ s: State, records: [HealthRecord], periodLabel: String, profile: ProfileData? = nil) {
        s.ctx.setFillColor(s.style.accentColor.cgColor)
        s.ctx.fill(CGRect(x: 0, y: 0, width: pw, height: 3))
        s.y = m

        text(s, "HEALTH REPORT", font: s.style.titleFont, color: s.style.accentColor)
        s.y += 4
        hline(s, color: s.style.accentColor, width: s.style.headerRuleWidth)
        s.y += 6

        let genDate = Date.now.formatted(date: .long, time: .shortened)
        text(s, "Report generated: \(genDate)", font: s.style.bodyFont, color: s.style.mutedTextColor)
        s.y += 2
        let period = periodLabel.isEmpty
            ? (records.first.map { "\($0.formattedDateOnly) – \(records.last!.formattedDateOnly)" } ?? "")
            : periodLabel
        let metricCount = Set(records.map(\.metricType)).count
        text(s, "Data period: \(period)  (\(records.count) records, \(metricCount) metric types)", font: s.style.bodyFont, color: s.style.mutedTextColor)
        s.y += 14
    }

    private static func drawPatientInfo(_ s: State, profile: ProfileData) {
        section(s, "PATIENT INFORMATION")
        let labelW: CGFloat = 160
        var rows: [(String, String)] = []
        if !profile.name.isEmpty { rows.append(("Patient Name", profile.name)) }
        if profile.age > 0 { rows.append(("Age", "\(profile.age) years")) }
        if !profile.gender.isEmpty { rows.append(("Gender", profile.gender)) }
        if profile.heightCm > 0 { rows.append(("Height", profile.heightFormatted)) }
        if profile.weightKg > 0 { rows.append(("Weight", profile.weightFormatted)) }
        if let bmi = profile.bmi { rows.append(("BMI", String(format: "%.1f (%@)", bmi, profile.bmiCategory))) }
        if !profile.doctorName.isEmpty { rows.append(("Physician", profile.doctorName)) }
        if !profile.medicalNotes.isEmpty { rows.append(("Notes", profile.medicalNotes)) }

        let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.secondaryTextColor]
        let va: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
        for (i, row) in rows.enumerated() {
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 16, color: s.style.stripeColor) }
            (row.0 as NSString).draw(at: CGPoint(x: m + 6, y: s.y + 1), withAttributes: la)
            (row.1 as NSString).draw(at: CGPoint(x: m + labelW, y: s.y + 1), withAttributes: va)
            s.y += 16
        }
        s.y += 12
    }

    // MARK: - BP Summary Table

    private static func drawBPSummaryTable(_ s: State, records: [HealthRecord]) {
        section(s, "BLOOD PRESSURE SUMMARY")
        let avgSys = records.map(\.systolic).reduce(0, +) / records.count
        let avgDia = records.map(\.diastolic).reduce(0, +) / records.count
        let avgPulse = records.map(\.pulse).reduce(0, +) / records.count
        let cat = BPCategory.classify(systolic: avgSys, diastolic: avgDia)
        let mapVal = Int(Double(avgDia) + Double(avgSys - avgDia) / 3.0)
        let pp = avgSys - avgDia
        let minS = records.map(\.systolic).min()!
        let maxS = records.map(\.systolic).max()!
        let minD = records.map(\.diastolic).min()!
        let maxD = records.map(\.diastolic).max()!
        let normalPct = Int(Double(records.filter { $0.bpCategory == .normal }.count) / Double(records.count) * 100)

        let rows: [(String, String)] = [
            ("Average Blood Pressure", "\(avgSys)/\(avgDia) mmHg"),
            ("Classification", cat.rawValue),
            ("Average Heart Rate", "\(avgPulse) bpm"),
            ("Systolic Range", "\(minS) – \(maxS) mmHg"),
            ("Diastolic Range", "\(minD) – \(maxD) mmHg"),
            ("Mean Arterial Pressure", "\(mapVal) mmHg"),
            ("Pulse Pressure", "\(pp) mmHg"),
            ("Readings in Normal Range", "\(normalPct)%"),
        ]

        let labelW: CGFloat = 200
        for (i, row) in rows.enumerated() {
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 16, color: s.style.stripeColor) }
            let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.secondaryTextColor]
            (row.0 as NSString).draw(at: CGPoint(x: m + 6, y: s.y + 1), withAttributes: la)
            let va: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: row.0 == "Classification" ? catColor(cat) : s.style.primaryTextColor]
            (row.1 as NSString).draw(at: CGPoint(x: m + labelW, y: s.y + 2), withAttributes: va)
            s.y += 16
        }
        s.y += 12
    }

    // MARK: - Classification Table

    private static func drawClassificationTable(_ s: State, records: [HealthRecord]) {
        section(s, "CLASSIFICATION BREAKDOWN")
        let groups = Dictionary(grouping: records) { $0.bpCategory }
        let cats: [BPCategory] = [.normal, .elevated, .highStage1, .highStage2, .crisis]

        let colX: [CGFloat] = [m + 6, m + 130, m + 190, m + 260]
        let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
        for (t, x) in zip(["Classification", "Count", "Percentage", "Avg BP"], colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        hline(s, color: s.style.borderColor, width: 0.5)
        s.y += 3

        for (i, cat) in cats.enumerated() {
            let count = groups[cat]?.count ?? 0
            guard count > 0 else { continue }
            let pct = Int(Double(count) / Double(records.count) * 100)
            let avg = groups[cat]!
            let avgS = avg.map(\.systolic).reduce(0, +) / count
            let avgD = avg.map(\.diastolic).reduce(0, +) / count

            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: s.style.stripeColor) }
            s.ctx.setFillColor(catColor(cat).cgColor)
            s.ctx.fillEllipse(in: CGRect(x: m + 6, y: s.y + 3, width: 7, height: 7))

            let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
            let va: [NSAttributedString.Key: Any] = [.font: s.style.monoFont, .foregroundColor: s.style.primaryTextColor]
            (cat.rawValue as NSString).draw(at: CGPoint(x: m + 18, y: s.y + 1), withAttributes: la)
            ("\(count)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
            ("\(pct)%" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
            ("\(avgS)/\(avgD)" as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: va)
            s.y += 15
        }
        s.y += 12
    }

    // MARK: - Metrics Summary (non-BP)

    private static func drawMetricsSummary(_ s: State, records: [HealthRecord], metricTypes: Set<String>) {
        section(s, "HEALTH METRICS SUMMARY")

        let colX: [CGFloat] = [m + 6, m + 160, m + 260, m + 380]
        let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
        for (t, x) in zip(["Metric", "Average", "Range", "Data Points"], colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        hline(s, color: s.style.borderColor, width: 0.5)
        s.y += 3

        for (i, metricType) in metricTypes.sorted().enumerated() {
            let metricRecords = records.filter { $0.metricType == metricType }
            guard !metricRecords.isEmpty, let def = MetricRegistry.definition(for: metricType) else { continue }

            pageBreak(s, 16)
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: s.style.stripeColor) }

            let values = metricRecords.map(\.primaryValue)
            let avg = values.reduce(0, +) / Double(values.count)
            let minV = values.min()!
            let maxV = values.max()!

            let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
            let va: [NSAttributedString.Key: Any] = [.font: s.style.monoFont, .foregroundColor: s.style.primaryTextColor]

            (def.name as NSString).draw(at: CGPoint(x: colX[0], y: s.y + 1), withAttributes: la)
            ("\(def.formatValue(avg)) \(def.unit)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
            ("\(def.formatValue(minV)) – \(def.formatValue(maxV))" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
            ("\(metricRecords.count)" as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: va)
            s.y += 15
        }
        s.y += 8
    }

    // MARK: - BP Readings Table

    private static func drawBPReadingsTable(_ s: State, records: [HealthRecord]) {
        let colW: [CGFloat] = [148, 50, 50, 40, 44, 152]
        let headers = ["Date / Time", "SYS", "DIA", "HR", "MAP", "Context"]

        func tableHeader() {
            fillRect(s, x: m, w: cw, h: 15, color: s.style.tableHeaderBackground)
            var hx = m + 4
            let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.tableHeaderForeground]
            for (j, h) in headers.enumerated() {
                (h as NSString).draw(at: CGPoint(x: hx, y: s.y + 2), withAttributes: ha)
                hx += colW[j]
            }
            s.y += 16
        }

        tableHeader()

        for (i, r) in records.reversed().enumerated() {
            if s.y + 16 > ph - m - 28 { footer(s); newPage(s); tableHeader() }
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 14, color: s.style.stripeColor) }

            let mapV = Int(Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0)
            let ctxLabel = r.bpActivityContext?.rawValue ?? ""
            let vals: [(String, UIColor)] = [
                (r.formattedDate, s.style.primaryTextColor),
                ("\(r.systolic)", red),
                ("\(r.diastolic)", blue),
                ("\(r.pulse)", pink),
                ("\(mapV)", purple),
                (ctxLabel, s.style.secondaryTextColor),
            ]

            var cx = m + 4
            for (j, v) in vals.enumerated() {
                let f = (j == 1 || j == 2) ? s.style.monoBoldFont : s.style.monoFont
                let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: v.1]
                (v.0 as NSString).draw(at: CGPoint(x: cx, y: s.y + 1), withAttributes: a)
                cx += colW[j]
            }
            s.y += 14
        }
    }

    // MARK: - BP Chart

    private static func drawBPChart(_ s: State, records: [HealthRecord]) {
        guard records.count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 150, cy = s.y
        let vals = records.flatMap { [$0.systolic, $0.diastolic] }
        let lo = max((vals.min() ?? 60) - 10, 40), hi = min((vals.max() ?? 180) + 10, 220)
        let r = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(records.count - 1) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }

        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 20)

        s.ctx.setFillColor(green.withAlphaComponent(0.06).cgColor)
        s.ctx.fill(CGRect(x: cx, y: yp(120), width: cw2, height: yp(80) - yp(120)))

        dashedLine(s, from: CGPoint(x: cx, y: yp(120)), to: CGPoint(x: cx + cw2, y: yp(120)), color: green.withAlphaComponent(0.4))
        dashedLine(s, from: CGPoint(x: cx, y: yp(80)), to: CGPoint(x: cx + cw2, y: yp(80)), color: green.withAlphaComponent(0.4))

        drawIntLine(s, records: records, getValue: { $0.systolic }, xp: xp, yp: yp, color: red)
        drawIntLine(s, records: records, getValue: { $0.diastolic }, xp: xp, yp: yp, color: blue)

        xLabelsFromRecords(s, records: records, xp: xp, baseY: cy + ch)

        let ly = cy + ch + 16
        legend(s, x: cx, y: ly, items: [("Systolic", red), ("Diastolic", blue), ("Normal range 80–120", green)])
        s.y = ly + 12
    }

    private static func drawPulseChart(_ s: State, records: [HealthRecord]) {
        guard records.count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 100, cy = s.y
        let pv = records.map(\.pulse)
        let lo = max((pv.min() ?? 50) - 5, 30), hi = (pv.max() ?? 120) + 5
        let r = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(records.count - 1) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }

        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 10)

        // Area
        s.ctx.saveGState()
        let ap = CGMutablePath()
        ap.move(to: CGPoint(x: xp(0), y: cy + ch))
        for i in 0..<records.count { ap.addLine(to: CGPoint(x: xp(i), y: yp(records[i].pulse))) }
        ap.addLine(to: CGPoint(x: xp(records.count - 1), y: cy + ch))
        ap.closeSubpath()
        s.ctx.addPath(ap)
        s.ctx.setFillColor(pink.withAlphaComponent(s.style.chartFillOpacity).cgColor)
        s.ctx.fillPath()
        s.ctx.restoreGState()

        drawIntLine(s, records: records, getValue: { $0.pulse }, xp: xp, yp: yp, color: pink)
        xLabelsFromRecords(s, records: records, xp: xp, baseY: cy + ch)
        s.y = cy + ch + 16
    }

    // MARK: - Time-of-Day BP Analysis

    private enum TimePeriod: String, CaseIterable {
        case morning = "Morning (5 AM – 12 PM)"
        case afternoon = "Afternoon (12 PM – 5 PM)"
        case evening = "Evening / Night (5 PM – 5 AM)"

        var shortName: String {
            switch self {
            case .morning: return "Morning"
            case .afternoon: return "Afternoon"
            case .evening: return "Evening"
            }
        }

        var hourRange: String {
            switch self {
            case .morning: return "5:00 – 11:59"
            case .afternoon: return "12:00 – 16:59"
            case .evening: return "17:00 – 4:59"
            }
        }

        static func from(hour: Int) -> TimePeriod {
            if hour >= 5 && hour < 12 { return .morning }
            if hour >= 12 && hour < 17 { return .afternoon }
            return .evening
        }
    }

    private static func drawTimeOfDayPage(_ s: State, records: [HealthRecord]) {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { TimePeriod.from(hour: calendar.component(.hour, from: $0.timestamp)) }

        // Only draw if we have readings in at least 2 time periods
        let populatedPeriods = TimePeriod.allCases.filter { (grouped[$0]?.count ?? 0) > 0 }
        guard populatedPeriods.count >= 2 else { return }

        newPage(s)
        drawSectionHeader(s, title: "BLOOD PRESSURE", subtitle: "Time-of-Day Analysis")
        text(s, "TIME-OF-DAY ANALYSIS", font: s.style.sectionHeaderFont, color: s.style.accentColor)
        s.y += 4
        hline(s, color: s.style.accentColor, width: s.style.headerRuleWidth)
        s.y += 6
        text(s, "Blood pressure readings grouped by time of day to help identify patterns such as morning hypertension or evening dipping.", font: s.style.bodyFont, color: s.style.mutedTextColor, w: cw)
        s.y += 12

        // Comparison summary table
        drawTimePeriodSummary(s, grouped: grouped, periods: populatedPeriods, totalCount: records.count)
        s.y += 8

        // Individual mini charts per time period
        for period in populatedPeriods {
            guard let periodRecords = grouped[period], periodRecords.count >= 2 else { continue }
            let sorted = periodRecords.sorted { $0.timestamp < $1.timestamp }
            pageBreak(s, 140)
            drawTimePeriodChart(s, records: sorted, period: period)
            s.y += 8
        }

        footer(s)
    }

    private static func drawTimePeriodSummary(_ s: State, grouped: [TimePeriod: [HealthRecord]], periods: [TimePeriod], totalCount: Int) {
        section(s, "COMPARISON BY TIME OF DAY")

        // Table header
        let colX: [CGFloat] = [m + 6, m + 110, m + 190, m + 260, m + 330, m + 400]
        let headers = ["Time Period", "Avg BP", "Avg HR", "Classification", "Readings", "% of Total"]
        let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
        for (t, x) in zip(headers, colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        hline(s, color: s.style.borderColor, width: 0.5)
        s.y += 3

        for (i, period) in periods.enumerated() {
            guard let recs = grouped[period], !recs.isEmpty else { continue }

            let avgSys = recs.map(\.systolic).reduce(0, +) / recs.count
            let avgDia = recs.map(\.diastolic).reduce(0, +) / recs.count
            let avgPulse = recs.map(\.pulse).reduce(0, +) / recs.count
            let cat = BPCategory.classify(systolic: avgSys, diastolic: avgDia)
            let pct = Int(Double(recs.count) / Double(totalCount) * 100)

            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 16, color: s.style.stripeColor) }

            let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.secondaryTextColor]
            let va: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: s.style.primaryTextColor]
            let ca: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: catColor(cat)]

            (period.shortName as NSString).draw(at: CGPoint(x: colX[0], y: s.y + 1), withAttributes: la)
            ("\(avgSys)/\(avgDia)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
            ("\(avgPulse) bpm" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
            (cat.rawValue as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: ca)
            ("\(recs.count)" as NSString).draw(at: CGPoint(x: colX[4], y: s.y + 1), withAttributes: va)
            ("\(pct)%" as NSString).draw(at: CGPoint(x: colX[5], y: s.y + 1), withAttributes: va)

            s.y += 16
        }

        // Clinical note about morning hypertension
        s.y += 6
        let morningRecs = grouped[.morning] ?? []
        let eveningRecs = grouped[.evening] ?? []
        if !morningRecs.isEmpty && !eveningRecs.isEmpty {
            let mornAvgSys = morningRecs.map(\.systolic).reduce(0, +) / morningRecs.count
            let eveAvgSys = eveningRecs.map(\.systolic).reduce(0, +) / eveningRecs.count
            let diff = mornAvgSys - eveAvgSys
            if diff > 10 {
                text(s, "⚠ Morning systolic average is \(diff) mmHg higher than evening — may indicate morning hypertension surge.", font: s.style.bodyFont, color: orange, w: cw)
            } else if diff < -10 {
                text(s, "Note: Evening systolic average is \(abs(diff)) mmHg higher than morning — normal nocturnal dipping pattern may be reduced.", font: s.style.bodyFont, color: s.style.secondaryTextColor, w: cw)
            } else {
                text(s, "Blood pressure appears relatively stable across time periods.", font: s.style.bodyFont, color: s.style.secondaryTextColor, w: cw)
            }
        }
        s.y += 6
    }

    private static func drawTimePeriodChart(_ s: State, records: [HealthRecord], period: TimePeriod) {
        // Section title
        let titleA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: s.style.accentColor]
        ("\(period.rawValue)  —  \(records.count) readings" as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: titleA)
        s.y += 14

        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 90, cy = s.y
        let vals = records.flatMap { [$0.systolic, $0.diastolic] }
        let lo = max((vals.min() ?? 60) - 10, 40), hi = min((vals.max() ?? 180) + 10, 220)
        let r = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(max(records.count - 1, 1)) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }

        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 20)

        // Normal range zone
        s.ctx.setFillColor(green.withAlphaComponent(0.06).cgColor)
        s.ctx.fill(CGRect(x: cx, y: yp(120), width: cw2, height: yp(80) - yp(120)))
        dashedLine(s, from: CGPoint(x: cx, y: yp(120)), to: CGPoint(x: cx + cw2, y: yp(120)), color: green.withAlphaComponent(0.4))
        dashedLine(s, from: CGPoint(x: cx, y: yp(80)), to: CGPoint(x: cx + cw2, y: yp(80)), color: green.withAlphaComponent(0.4))

        // Draw systolic + diastolic lines
        drawIntLine(s, records: records, getValue: { $0.systolic }, xp: xp, yp: yp, color: red)
        drawIntLine(s, records: records, getValue: { $0.diastolic }, xp: xp, yp: yp, color: blue)

        // X-axis labels (dates)
        xLabelsFromRecords(s, records: records, xp: xp, baseY: cy + ch)

        // Inline stats on the right
        let avgSys = records.map(\.systolic).reduce(0, +) / records.count
        let avgDia = records.map(\.diastolic).reduce(0, +) / records.count
        let avgPulse = records.map(\.pulse).reduce(0, +) / records.count
        let statsY = cy + 4
        let statsX = cx + cw2 + 10
        let sa: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.secondaryTextColor]
        let sb: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.primaryTextColor]
        ("Avg:" as NSString).draw(at: CGPoint(x: statsX, y: statsY), withAttributes: sa)
        ("\(avgSys)/\(avgDia)" as NSString).draw(at: CGPoint(x: statsX, y: statsY + 10), withAttributes: sb)
        ("♡ \(avgPulse)" as NSString).draw(at: CGPoint(x: statsX, y: statsY + 22), withAttributes: [.font: s.style.captionFont, .foregroundColor: pink])

        s.y = cy + ch + 18
    }

    // MARK: - Drawing Primitives

    private static func text(_ s: State, _ t: String, font: UIFont, color: UIColor, w: CGFloat? = nil) {
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = w ?? cw
        let rect = CGRect(x: m, y: s.y, width: width, height: 800)
        let br = (t as NSString).boundingRect(with: rect.size, options: .usesLineFragmentOrigin, attributes: a, context: nil)
        (t as NSString).draw(in: CGRect(x: m, y: s.y, width: width, height: br.height), withAttributes: a)
        s.y += br.height
    }

    private static func section(_ s: State, _ title: String) {
        let a: [NSAttributedString.Key: Any] = [.font: s.style.sectionFont, .foregroundColor: s.style.accentColor]
        (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: a)
        s.y += 16
        hline(s, color: s.style.accentColor, width: 1)
        s.y += 6
    }

    private static func hline(_ s: State, y: CGFloat? = nil, color: UIColor, width: CGFloat = 0.5) {
        let ly = y ?? s.y
        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(width)
        s.ctx.move(to: CGPoint(x: m, y: ly))
        s.ctx.addLine(to: CGPoint(x: pw - m, y: ly))
        s.ctx.strokePath()
    }

    private static func fillRect(_ s: State, x: CGFloat, w: CGFloat, h: CGFloat, color: UIColor) {
        s.ctx.setFillColor(color.cgColor)
        s.ctx.fill(CGRect(x: x, y: s.y, width: w, height: h))
    }

    private static func dashedLine(_ s: State, from: CGPoint, to: CGPoint, color: UIColor) {
        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(0.8)
        s.ctx.setLineDash(phase: 0, lengths: [4, 3])
        s.ctx.move(to: from)
        s.ctx.addLine(to: to)
        s.ctx.strokePath()
        s.ctx.setLineDash(phase: 0, lengths: [])
    }

    private static func grid(_ s: State, cx: CGFloat, cy: CGFloat, cw: CGFloat, ch: CGFloat, lo: Int, hi: Int, step: Int) {
        let ga: [NSAttributedString.Key: Any] = [.font: s.style.tinyFont, .foregroundColor: s.style.mutedTextColor]
        s.ctx.setStrokeColor(s.style.gridColor.cgColor)
        s.ctx.setLineWidth(s.style.gridLineWidth)
        for v in stride(from: (lo / step) * step, through: hi, by: step) {
            let gy = cy + ch - CGFloat(v - lo) / CGFloat(hi - lo) * ch
            s.ctx.move(to: CGPoint(x: cx, y: gy))
            s.ctx.addLine(to: CGPoint(x: cx + cw, y: gy))
            s.ctx.strokePath()
            ("\(v)" as NSString).draw(at: CGPoint(x: m, y: gy - 4), withAttributes: ga)
        }
    }

    private static func drawIntLine(_ s: State, records: [HealthRecord], getValue: (HealthRecord) -> Int, xp: (Int) -> CGFloat, yp: (Int) -> CGFloat, color: UIColor) {
        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(s.style.chartLineWidth)
        s.ctx.move(to: CGPoint(x: xp(0), y: yp(getValue(records[0]))))
        for i in 1..<records.count { s.ctx.addLine(to: CGPoint(x: xp(i), y: yp(getValue(records[i])))) }
        s.ctx.strokePath()

        s.ctx.setFillColor(color.cgColor)
        let dr: CGFloat = records.count > 40 ? 1.2 : s.style.chartDotRadius
        for i in 0..<records.count {
            s.ctx.fillEllipse(in: CGRect(x: xp(i) - dr, y: yp(getValue(records[i])) - dr, width: dr * 2, height: dr * 2))
        }
    }

    private static func xLabelsFromRecords(_ s: State, records: [HealthRecord], xp: (Int) -> CGFloat, baseY: CGFloat) {
        let a: [NSAttributedString.Key: Any] = [.font: s.style.tinyFont, .foregroundColor: s.style.mutedTextColor]
        let step = max(records.count / 5, 1)
        for i in stride(from: 0, to: records.count, by: step) {
            let l = records[i].timestamp.formatted(.dateTime.month(.abbreviated).day())
            (l as NSString).draw(at: CGPoint(x: xp(i) - 12, y: baseY + 3), withAttributes: a)
        }
    }

    private static func legend(_ s: State, x: CGFloat, y: CGFloat, items: [(String, UIColor)]) {
        var lx = x
        for item in items {
            s.ctx.setFillColor(item.1.cgColor)
            s.ctx.fillEllipse(in: CGRect(x: lx, y: y + 2, width: 5, height: 5))
            let a: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.secondaryTextColor]
            (item.0 as NSString).draw(at: CGPoint(x: lx + 8, y: y), withAttributes: a)
            lx += (item.0 as NSString).size(withAttributes: a).width + 20
        }
    }

    // MARK: - Daily Chart Helpers

    private struct DailyValue {
        let date: Date
        let value: Double
        var dateLabel: String { date.formatted(.dateTime.month(.abbreviated).day()) }
    }

    private static func drawDailyChart(_ s: State, values: [DailyValue], color: UIColor, unit: String, refLines: [(Double, String, UIColor)] = [], zoneRange: (Double, Double, UIColor)? = nil) {
        guard values.count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 120, cy = s.y

        let rawVals = values.map(\.value)
        var loD = (rawVals.min() ?? 0)
        var hiD = (rawVals.max() ?? 100)
        for rl in refLines { loD = min(loD, rl.0); hiD = max(hiD, rl.0) }
        if let zone = zoneRange { loD = min(loD, zone.0); hiD = max(hiD, zone.1) }

        let padding = max((hiD - loD) * 0.1, 1.0)
        loD -= padding; hiD += padding
        let lo = Int(floor(loD)), hi = Int(ceil(hiD))
        let range = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(values.count - 1) * cw2 }
        func yp(_ v: Double) -> CGFloat { cy + ch - CGFloat(v - Double(lo)) / range * ch }

        let gridStep = max(Int(range) / 5, 1)
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: gridStep)

        if let zone = zoneRange {
            s.ctx.setFillColor(zone.2.withAlphaComponent(s.style.chartFillOpacity).cgColor)
            s.ctx.fill(CGRect(x: cx, y: yp(zone.1), width: cw2, height: yp(zone.0) - yp(zone.1)))
        }

        for rl in refLines {
            let ry = yp(rl.0)
            dashedLine(s, from: CGPoint(x: cx, y: ry), to: CGPoint(x: cx + cw2, y: ry), color: rl.2.withAlphaComponent(0.5))
            let la: [NSAttributedString.Key: Any] = [.font: s.style.tinyFont, .foregroundColor: rl.2]
            (rl.1 as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: ry - 4), withAttributes: la)
        }

        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(s.style.chartLineWidth)
        s.ctx.move(to: CGPoint(x: xp(0), y: yp(values[0].value)))
        for i in 1..<values.count { s.ctx.addLine(to: CGPoint(x: xp(i), y: yp(values[i].value))) }
        s.ctx.strokePath()

        s.ctx.setFillColor(color.cgColor)
        let dr: CGFloat = values.count > 40 ? 1.2 : s.style.chartDotRadius
        for i in 0..<values.count {
            s.ctx.fillEllipse(in: CGRect(x: xp(i) - dr, y: yp(values[i].value) - dr, width: dr * 2, height: dr * 2))
        }

        let da: [NSAttributedString.Key: Any] = [.font: s.style.tinyFont, .foregroundColor: s.style.mutedTextColor]
        let step = max(values.count / 5, 1)
        for i in stride(from: 0, to: values.count, by: step) {
            let l = values[i].dateLabel
            (l as NSString).draw(at: CGPoint(x: xp(i) - 12, y: cy + ch + 3), withAttributes: da)
        }

        let ua: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
        (unit as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: cy - 2), withAttributes: ua)
        s.y = cy + ch + 18
    }

    private static func drawDailyBarChart(_ s: State, values: [DailyValue], color: UIColor, unit: String, targetLine: Double? = nil, targetLabel: String = "") {
        guard !values.isEmpty else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 120, cy = s.y

        var hiD = (values.map(\.value).max() ?? 100)
        if let target = targetLine { hiD = max(hiD, target) }
        hiD += max(hiD * 0.1, 1.0)
        let hi = Int(ceil(hiD)), lo = 0
        let range = CGFloat(hi - lo)

        func yp(_ v: Double) -> CGFloat { cy + ch - CGFloat(v - Double(lo)) / range * ch }

        let gridStep = max(hi / 5, 1)
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: gridStep)

        if let target = targetLine {
            let ty = yp(target)
            dashedLine(s, from: CGPoint(x: cx, y: ty), to: CGPoint(x: cx + cw2, y: ty), color: green.withAlphaComponent(0.6))
            if !targetLabel.isEmpty {
                let tla: [NSAttributedString.Key: Any] = [.font: s.style.tinyFont, .foregroundColor: green]
                (targetLabel as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: ty - 4), withAttributes: tla)
            }
        }

        let gw = cw2 / CGFloat(values.count)
        let bw = min(max(gw * 0.6, 2), 16)

        for (i, v) in values.enumerated() {
            let barX = cx + gw * CGFloat(i) + (gw - bw) / 2
            let barY = yp(v.value)
            let barH = yp(0) - barY
            s.ctx.setFillColor(color.withAlphaComponent(s.style.barOpacity).cgColor)
            let barRect = CGRect(x: barX, y: barY, width: bw, height: barH)
            UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: s.style.barCornerRadius, height: s.style.barCornerRadius)).fill()
        }

        let da: [NSAttributedString.Key: Any] = [.font: s.style.tinyFont, .foregroundColor: s.style.mutedTextColor]
        let labelStep = max(values.count / 6, 1)
        for i in stride(from: 0, to: values.count, by: labelStep) {
            let centerX = cx + gw * CGFloat(i) + gw / 2
            let l = values[i].dateLabel
            let ls = (l as NSString).size(withAttributes: da)
            (l as NSString).draw(at: CGPoint(x: centerX - ls.width / 2, y: cy + ch + 3), withAttributes: da)
        }

        let ua: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
        (unit as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: cy - 2), withAttributes: ua)
        s.y = cy + ch + 18
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
