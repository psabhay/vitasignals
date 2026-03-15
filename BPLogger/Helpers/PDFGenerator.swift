import UIKit

struct PDFGenerator {
    // MARK: - Layout
    private static let pw: CGFloat = 612
    private static let ph: CGFloat = 792
    private static let m: CGFloat = 48
    private static let cw: CGFloat = 612 - 96

    // MARK: - Fixed Colors (no dynamic/system colors)
    private static let black     = UIColor(white: 0.10, alpha: 1)
    private static let dark      = UIColor(white: 0.25, alpha: 1)
    private static let mid       = UIColor(white: 0.50, alpha: 1)
    private static let border    = UIColor(white: 0.78, alpha: 1)
    private static let stripe    = UIColor(white: 0.95, alpha: 1)
    private static let accent    = UIColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1)
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

    // MARK: - Fonts
    private static let f24b  = UIFont.systemFont(ofSize: 24, weight: .bold)
    private static let f14b  = UIFont.systemFont(ofSize: 14, weight: .bold)
    private static let f12b  = UIFont.systemFont(ofSize: 12, weight: .bold)
    private static let f11m  = UIFont.systemFont(ofSize: 11, weight: .medium)
    private static let f11   = UIFont.systemFont(ofSize: 11)
    private static let f10m  = UIFont.systemFont(ofSize: 10, weight: .medium)
    private static let f10   = UIFont.systemFont(ofSize: 10)
    private static let f9b   = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let f9    = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private static let f8b   = UIFont.systemFont(ofSize: 8, weight: .bold)
    private static let f8    = UIFont.systemFont(ofSize: 8)
    private static let f7    = UIFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)

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
        init(_ ctx: CGContext) { self.ctx = ctx }
    }

    // MARK: - Generate (new universal API)

    static func generate(
        records: [HealthRecord],
        selectedMetrics: Set<String>? = nil,
        periodLabel: String = "",
        profile: ProfileData? = nil
    ) -> URL? {
        guard !records.isEmpty else { return nil }
        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Health_Report_\(dateStamp()).pdf")
        UIGraphicsBeginPDFContextToFile(url.path, CGRect(x: 0, y: 0, width: pw, height: ph), [
            kCGPDFContextTitle as String: "Health Report",
            kCGPDFContextCreator as String: "Health Logger"
        ])
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let s = State(ctx)

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

        // ── BP Charts Page ──
        if metrics.contains(MetricType.bloodPressure) && bpRecords.count >= 2 {
            newPage(s)
            section(s, "BLOOD PRESSURE TREND")
            drawBPChart(s, records: bpRecords)
            s.y += 16
            section(s, "HEART RATE TREND")
            drawPulseChart(s, records: bpRecords)
            footer(s)
        }

        // ── Metric-specific chart pages ──
        for metricType in nonBPMetrics.sorted() {
            let metricRecords = sorted.filter { $0.metricType == metricType }
            guard metricRecords.count >= 2, let def = MetricRegistry.definition(for: metricType) else { continue }

            newPage(s)
            let color = metricColor(metricType)
            text(s, def.name.uppercased(), font: f14b, color: accent)
            s.y += 4
            hline(s, color: accent, width: 1.5)
            s.y += 12

            section(s, "\(def.name.uppercased()) TREND")

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

            // Stats
            let avg = values.map(\.value).reduce(0, +) / Double(values.count)
            text(s, String(format: "Average: %@ %@  |  %d data points", def.formatValue(avg), def.unit, values.count), font: f9, color: dark)
            s.y += 16

            footer(s)
        }

        // ── BP Data Table ──
        if metrics.contains(MetricType.bloodPressure) && !bpRecords.isEmpty {
            newPage(s)
            section(s, "DETAILED BP READINGS  (\(bpRecords.count))")
            drawBPReadingsTable(s, records: bpRecords)
        }

        // Disclaimer
        s.y += 12
        pageBreak(s, 32)
        hline(s, color: border)
        s.y += 6
        text(s, "Disclaimer: This report is generated from self-recorded data and data imported from Apple Health. It is intended as a supplementary reference for healthcare providers and should not be used for self-diagnosis or treatment decisions.", font: f8, color: mid, w: cw)
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
        hline(s, y: fy - 6, color: border)
        let la: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: mid]
        ("Health Logger  |  Health Report" as NSString).draw(at: CGPoint(x: m, y: fy), withAttributes: la)
        let rt = "Page \(s.page)"
        let rs = (rt as NSString).size(withAttributes: la)
        (rt as NSString).draw(at: CGPoint(x: pw - m - rs.width, y: fy), withAttributes: la)
    }

    // MARK: - Header

    private static func drawHeader(_ s: State, records: [HealthRecord], periodLabel: String, profile: ProfileData? = nil) {
        s.ctx.setFillColor(accent.cgColor)
        s.ctx.fill(CGRect(x: 0, y: 0, width: pw, height: 3))
        s.y = m

        text(s, "HEALTH REPORT", font: f24b, color: accent)
        s.y += 4
        hline(s, color: accent, width: 1.5)
        s.y += 6

        let genDate = Date.now.formatted(date: .long, time: .shortened)
        text(s, "Report generated: \(genDate)", font: f10, color: mid)
        s.y += 2
        let period = periodLabel.isEmpty
            ? (records.first.map { "\($0.formattedDateOnly) – \(records.last!.formattedDateOnly)" } ?? "")
            : periodLabel
        let metricCount = Set(records.map(\.metricType)).count
        text(s, "Data period: \(period)  (\(records.count) records, \(metricCount) metric types)", font: f10, color: mid)
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

        let la: [NSAttributedString.Key: Any] = [.font: f10m, .foregroundColor: dark]
        let va: [NSAttributedString.Key: Any] = [.font: f10, .foregroundColor: black]
        for (i, row) in rows.enumerated() {
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 16, color: stripe) }
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
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 16, color: stripe) }
            let la: [NSAttributedString.Key: Any] = [.font: f10m, .foregroundColor: dark]
            (row.0 as NSString).draw(at: CGPoint(x: m + 6, y: s.y + 1), withAttributes: la)
            let va: [NSAttributedString.Key: Any] = [.font: f9b, .foregroundColor: row.0 == "Classification" ? catColor(cat) : black]
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
        let ha: [NSAttributedString.Key: Any] = [.font: f8b, .foregroundColor: mid]
        for (t, x) in zip(["Classification", "Count", "Percentage", "Avg BP"], colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        hline(s, color: border, width: 0.5)
        s.y += 3

        for (i, cat) in cats.enumerated() {
            let count = groups[cat]?.count ?? 0
            guard count > 0 else { continue }
            let pct = Int(Double(count) / Double(records.count) * 100)
            let avg = groups[cat]!
            let avgS = avg.map(\.systolic).reduce(0, +) / count
            let avgD = avg.map(\.diastolic).reduce(0, +) / count

            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: stripe) }
            s.ctx.setFillColor(catColor(cat).cgColor)
            s.ctx.fillEllipse(in: CGRect(x: m + 6, y: s.y + 3, width: 7, height: 7))

            let la: [NSAttributedString.Key: Any] = [.font: f10, .foregroundColor: black]
            let va: [NSAttributedString.Key: Any] = [.font: f9, .foregroundColor: black]
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
        let ha: [NSAttributedString.Key: Any] = [.font: f8b, .foregroundColor: mid]
        for (t, x) in zip(["Metric", "Average", "Range", "Data Points"], colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        hline(s, color: border, width: 0.5)
        s.y += 3

        for (i, metricType) in metricTypes.sorted().enumerated() {
            let metricRecords = records.filter { $0.metricType == metricType }
            guard !metricRecords.isEmpty, let def = MetricRegistry.definition(for: metricType) else { continue }

            pageBreak(s, 16)
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: stripe) }

            let values = metricRecords.map(\.primaryValue)
            let avg = values.reduce(0, +) / Double(values.count)
            let minV = values.min()!
            let maxV = values.max()!

            let la: [NSAttributedString.Key: Any] = [.font: f10, .foregroundColor: black]
            let va: [NSAttributedString.Key: Any] = [.font: f9, .foregroundColor: black]

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
            fillRect(s, x: m, w: cw, h: 15, color: accent)
            var hx = m + 4
            let ha: [NSAttributedString.Key: Any] = [.font: f8b, .foregroundColor: UIColor.white]
            for (j, h) in headers.enumerated() {
                (h as NSString).draw(at: CGPoint(x: hx, y: s.y + 2), withAttributes: ha)
                hx += colW[j]
            }
            s.y += 16
        }

        tableHeader()

        for (i, r) in records.reversed().enumerated() {
            if s.y + 16 > ph - m - 28 { footer(s); newPage(s); tableHeader() }
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 14, color: stripe) }

            let mapV = Int(Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0)
            let ctxLabel = r.bpActivityContext?.rawValue ?? ""
            let vals: [(String, UIColor)] = [
                (r.formattedDate, black),
                ("\(r.systolic)", red),
                ("\(r.diastolic)", blue),
                ("\(r.pulse)", pink),
                ("\(mapV)", purple),
                (ctxLabel, dark),
            ]

            var cx = m + 4
            for (j, v) in vals.enumerated() {
                let f = (j == 1 || j == 2) ? f9b : f9
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
        s.ctx.setFillColor(pink.withAlphaComponent(0.08).cgColor)
        s.ctx.fillPath()
        s.ctx.restoreGState()

        drawIntLine(s, records: records, getValue: { $0.pulse }, xp: xp, yp: yp, color: pink)
        xLabelsFromRecords(s, records: records, xp: xp, baseY: cy + ch)
        s.y = cy + ch + 16
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
        let a: [NSAttributedString.Key: Any] = [.font: f12b, .foregroundColor: accent]
        (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: a)
        s.y += 16
        hline(s, color: accent, width: 1)
        s.y += 6
    }

    private static func hline(_ s: State, y: CGFloat? = nil, color: UIColor = border, width: CGFloat = 0.5) {
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
        let ga: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
        s.ctx.setStrokeColor(UIColor(white: 0.90, alpha: 1).cgColor)
        s.ctx.setLineWidth(0.4)
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
        s.ctx.setLineWidth(1.2)
        s.ctx.move(to: CGPoint(x: xp(0), y: yp(getValue(records[0]))))
        for i in 1..<records.count { s.ctx.addLine(to: CGPoint(x: xp(i), y: yp(getValue(records[i])))) }
        s.ctx.strokePath()

        s.ctx.setFillColor(color.cgColor)
        let dr: CGFloat = records.count > 40 ? 1.2 : 2.0
        for i in 0..<records.count {
            s.ctx.fillEllipse(in: CGRect(x: xp(i) - dr, y: yp(getValue(records[i])) - dr, width: dr * 2, height: dr * 2))
        }
    }

    private static func xLabelsFromRecords(_ s: State, records: [HealthRecord], xp: (Int) -> CGFloat, baseY: CGFloat) {
        let a: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
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
            let a: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: dark]
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
            s.ctx.setFillColor(zone.2.withAlphaComponent(0.08).cgColor)
            s.ctx.fill(CGRect(x: cx, y: yp(zone.1), width: cw2, height: yp(zone.0) - yp(zone.1)))
        }

        for rl in refLines {
            let ry = yp(rl.0)
            dashedLine(s, from: CGPoint(x: cx, y: ry), to: CGPoint(x: cx + cw2, y: ry), color: rl.2.withAlphaComponent(0.5))
            let la: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: rl.2]
            (rl.1 as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: ry - 4), withAttributes: la)
        }

        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(1.2)
        s.ctx.move(to: CGPoint(x: xp(0), y: yp(values[0].value)))
        for i in 1..<values.count { s.ctx.addLine(to: CGPoint(x: xp(i), y: yp(values[i].value))) }
        s.ctx.strokePath()

        s.ctx.setFillColor(color.cgColor)
        let dr: CGFloat = values.count > 40 ? 1.2 : 2.0
        for i in 0..<values.count {
            s.ctx.fillEllipse(in: CGRect(x: xp(i) - dr, y: yp(values[i].value) - dr, width: dr * 2, height: dr * 2))
        }

        let da: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
        let step = max(values.count / 5, 1)
        for i in stride(from: 0, to: values.count, by: step) {
            let l = values[i].dateLabel
            (l as NSString).draw(at: CGPoint(x: xp(i) - 12, y: cy + ch + 3), withAttributes: da)
        }

        let ua: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: mid]
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
                let tla: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: green]
                (targetLabel as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: ty - 4), withAttributes: tla)
            }
        }

        let gw = cw2 / CGFloat(values.count)
        let bw = min(max(gw * 0.6, 2), 16)

        for (i, v) in values.enumerated() {
            let barX = cx + gw * CGFloat(i) + (gw - bw) / 2
            let barY = yp(v.value)
            let barH = yp(0) - barY
            s.ctx.setFillColor(color.withAlphaComponent(0.7).cgColor)
            let barRect = CGRect(x: barX, y: barY, width: bw, height: barH)
            UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 1.5, height: 1.5)).fill()
        }

        let da: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
        let labelStep = max(values.count / 6, 1)
        for i in stride(from: 0, to: values.count, by: labelStep) {
            let centerX = cx + gw * CGFloat(i) + gw / 2
            let l = values[i].dateLabel
            let ls = (l as NSString).size(withAttributes: da)
            (l as NSString).draw(at: CGPoint(x: centerX - ls.width / 2, y: cy + ch + 3), withAttributes: da)
        }

        let ua: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: mid]
        (unit as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: cy - 2), withAttributes: ua)
        s.y = cy + ch + 18
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
