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
    private static let accent    = UIColor(red: 0.15, green: 0.30, blue: 0.55, alpha: 1)      // navy
    private static let red       = UIColor(red: 0.80, green: 0.15, blue: 0.15, alpha: 1)
    private static let blue      = UIColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 1)
    private static let pink      = UIColor(red: 0.75, green: 0.25, blue: 0.40, alpha: 1)
    private static let green     = UIColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 1)
    private static let orange    = UIColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 1)
    private static let purple    = UIColor(red: 0.50, green: 0.20, blue: 0.60, alpha: 1)
    private static let yellow    = UIColor(red: 0.65, green: 0.58, blue: 0.05, alpha: 1)

    private static func catColor(_ c: BPCategory) -> UIColor {
        switch c { case .normal: return green; case .elevated: return yellow; case .highStage1: return orange; case .highStage2: return red; case .crisis: return purple }
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

    // MARK: - Profile Data (plain struct, safe to pass across threads)
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

    // MARK: - Generate
    static func generate(readings: [BPReading], periodLabel: String = "", profile: ProfileData? = nil, healthContext: HealthContext? = nil, options: ReportOptions = ReportOptions()) -> URL? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BP_Report_\(dateStamp()).pdf")
        UIGraphicsBeginPDFContextToFile(url.path, CGRect(x: 0, y: 0, width: pw, height: ph), [
            kCGPDFContextTitle as String: "Blood Pressure Report",
            kCGPDFContextCreator as String: "BP Logger"
        ])
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let s = State(ctx)

        // ── PAGE 1: Summary ──
        newPage(s)
        drawHeader(s, sorted: sorted, periodLabel: periodLabel, profile: profile)
        if let profile, !profile.name.isEmpty {
            drawPatientInfo(s, profile: profile)
        }
        if options.bpSummary {
            drawSummaryTable(s, sorted: sorted)
            drawClassificationTable(s, sorted: sorted)
            drawContextTable(s, sorted: sorted)
        }
        footer(s)

        // ── PAGE 2: Charts ──
        if options.bpCharts {
            newPage(s)
            section(s, "BLOOD PRESSURE TREND")
            drawBPChart(s, readings: sorted)
            s.y += 16
            section(s, "HEART RATE TREND")
            drawPulseChart(s, readings: sorted)
            s.y += 16

            let cal = Calendar.current
            let weeks = Dictionary(grouping: sorted) { r in cal.dateInterval(of: .weekOfYear, for: r.timestamp)?.start ?? r.timestamp }
                .sorted { $0.key < $1.key }

            if options.bpWeeklyAverages && weeks.count >= 2 {
                pageBreak(s, 180)
                section(s, "WEEKLY AVERAGES")
                drawWeeklyChart(s, weeks: weeks)
                s.y += 16
            }

            if options.bpTimeOfDay {
                let am = sorted.filter { let h = cal.component(.hour, from: $0.timestamp); return h >= 5 && h < 12 }
                let pm = sorted.filter { let h = cal.component(.hour, from: $0.timestamp); return h >= 12 && h < 17 }
                let ev = sorted.filter { let h = cal.component(.hour, from: $0.timestamp); return h >= 17 || h < 5 }
                let periods = [("Morning  5 am – 12 pm", am), ("Afternoon  12 – 5 pm", pm), ("Evening  5 pm – 5 am", ev)].filter { !$0.1.isEmpty }
                if periods.count >= 2 {
                    pageBreak(s, 90)
                    section(s, "TIME-OF-DAY COMPARISON")
                    drawTimePeriods(s, periods: periods)
                }
            }
            footer(s)
        }

        // ── PAGE: Cardiovascular Fitness ──
        if options.cardioFitness, let hc = healthContext, hc.hasCardioFitnessData {
            drawCardioFitnessPage(s, healthContext: hc)
        }

        // ── PAGE: Lifestyle Factors ──
        if options.lifestyleFactors, let hc = healthContext, hc.hasLifestyleData {
            drawLifestyleFactorsPage(s, healthContext: hc)
        }

        // ── PAGE: Sleep & Recovery ──
        if options.sleepRecovery, let hc = healthContext, hc.hasSleepData {
            drawSleepRecoveryPage(s, healthContext: hc)
        }

        // ── PAGE: Correlation Analysis ──
        if options.correlationAnalysis, let hc = healthContext {
            drawCorrelationPage(s, readings: sorted, healthContext: hc)
        }

        // ── Data table ──
        if options.bpDetailedTable {
            newPage(s)
            section(s, "DETAILED READINGS  (\(sorted.count))")
            drawReadingsTable(s, sorted: sorted)
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
        ("BP Logger  |  Blood Pressure Report" as NSString).draw(at: CGPoint(x: m, y: fy), withAttributes: la)
        let rt = "Page \(s.page)"
        let rs = (rt as NSString).size(withAttributes: la)
        (rt as NSString).draw(at: CGPoint(x: pw - m - rs.width, y: fy), withAttributes: la)
    }

    // MARK: - Header

    private static func drawHeader(_ s: State, sorted: [BPReading], periodLabel: String, profile: ProfileData? = nil) {
        // Thin accent line at top
        s.ctx.setFillColor(accent.cgColor)
        s.ctx.fill(CGRect(x: 0, y: 0, width: pw, height: 3))
        s.y = m

        text(s, "BLOOD PRESSURE REPORT", font: f24b, color: accent)
        s.y += 4
        hline(s, color: accent, width: 1.5)
        s.y += 6

        let genDate = Date.now.formatted(date: .long, time: .shortened)
        text(s, "Report generated: \(genDate)", font: f10, color: mid)
        s.y += 2
        let period = periodLabel.isEmpty
            ? (sorted.first.map { "\($0.formattedDateOnly) – \(sorted.last!.formattedDateOnly)" } ?? "")
            : periodLabel
        text(s, "Data period: \(period)  (\(sorted.count) readings)", font: f10, color: mid)
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

    // MARK: - Summary Table

    private static func drawSummaryTable(_ s: State, sorted: [BPReading]) {
        section(s, "SUMMARY")

        let avgSys = sorted.map(\.systolic).reduce(0, +) / sorted.count
        let avgDia = sorted.map(\.diastolic).reduce(0, +) / sorted.count
        let avgPulse = sorted.map(\.pulse).reduce(0, +) / sorted.count
        let cat = BPReading.classify(systolic: avgSys, diastolic: avgDia)
        let mapVal = Int(Double(avgDia) + Double(avgSys - avgDia) / 3.0)
        let pp = avgSys - avgDia
        let minS = sorted.map(\.systolic).min()!
        let maxS = sorted.map(\.systolic).max()!
        let minD = sorted.map(\.diastolic).min()!
        let maxD = sorted.map(\.diastolic).max()!
        let normalPct = Int(Double(sorted.filter { $0.category == .normal }.count) / Double(sorted.count) * 100)

        let rows: [(String, String)] = [
            ("Average Blood Pressure",   "\(avgSys)/\(avgDia) mmHg"),
            ("Classification",           cat.rawValue),
            ("Average Heart Rate",       "\(avgPulse) bpm"),
            ("Systolic Range",           "\(minS) – \(maxS) mmHg"),
            ("Diastolic Range",          "\(minD) – \(maxD) mmHg"),
            ("Mean Arterial Pressure",   "\(mapVal) mmHg"),
            ("Pulse Pressure",           "\(pp) mmHg"),
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

    private static func drawClassificationTable(_ s: State, sorted: [BPReading]) {
        section(s, "CLASSIFICATION BREAKDOWN")

        let groups = Dictionary(grouping: sorted) { $0.category }
        let cats: [BPCategory] = [.normal, .elevated, .highStage1, .highStage2, .crisis]

        // Header row
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
            let pct = Int(Double(count) / Double(sorted.count) * 100)
            let avg = groups[cat]!
            let avgS = avg.map(\.systolic).reduce(0, +) / count
            let avgD = avg.map(\.diastolic).reduce(0, +) / count

            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: stripe) }

            // Color dot
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

    // MARK: - Context Table

    private static func drawContextTable(_ s: State, sorted: [BPReading]) {
        section(s, "READINGS BY ACTIVITY CONTEXT")

        let groups = Dictionary(grouping: sorted) { $0.activityContext }
        let ctxSorted = groups.sorted { $0.value.count > $1.value.count }

        let colX: [CGFloat] = [m + 6, m + 160, m + 210, m + 300, m + 380]
        let ha: [NSAttributedString.Key: Any] = [.font: f8b, .foregroundColor: mid]
        for (t, x) in zip(["Context", "Count", "Avg BP", "Avg Pulse", "Avg MAP"], colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        hline(s, color: border, width: 0.5)
        s.y += 3

        for (i, (ctx, rds)) in ctxSorted.enumerated() {
            pageBreak(s, 16)
            let n = rds.count
            let aS = rds.map(\.systolic).reduce(0, +) / n
            let aD = rds.map(\.diastolic).reduce(0, +) / n
            let aP = rds.map(\.pulse).reduce(0, +) / n
            let aM = Int(Double(aD) + Double(aS - aD) / 3.0)

            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: stripe) }
            let la: [NSAttributedString.Key: Any] = [.font: f10, .foregroundColor: black]
            let va: [NSAttributedString.Key: Any] = [.font: f9, .foregroundColor: black]
            (ctx.rawValue as NSString).draw(at: CGPoint(x: colX[0], y: s.y + 1), withAttributes: la)
            ("\(n)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
            ("\(aS)/\(aD)" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
            ("\(aP) bpm" as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: va)
            ("\(aM)" as NSString).draw(at: CGPoint(x: colX[4], y: s.y + 1), withAttributes: va)
            s.y += 15
        }
        s.y += 8
    }

    // MARK: - Readings Table

    private static func drawReadingsTable(_ s: State, sorted: [BPReading]) {
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

        for (i, r) in sorted.reversed().enumerated() {
            if s.y + 16 > ph - m - 28 { footer(s); newPage(s); tableHeader() }
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 14, color: stripe) }

            let mapV = Int(Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0)
            let vals: [(String, UIColor)] = [
                (r.formattedDate, black),
                ("\(r.systolic)", red),
                ("\(r.diastolic)", blue),
                ("\(r.pulse)", pink),
                ("\(mapV)", purple),
                (r.activityContext.rawValue, dark),
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

    // MARK: - Charts

    private static func drawBPChart(_ s: State, readings: [BPReading]) {
        guard readings.count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 150, cy = s.y
        let vals = readings.flatMap { [$0.systolic, $0.diastolic] }
        let lo = max((vals.min() ?? 60) - 10, 40), hi = min((vals.max() ?? 180) + 10, 220)
        let r = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(readings.count - 1) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }

        // Grid
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 20)

        // Normal zone
        s.ctx.setFillColor(green.withAlphaComponent(0.06).cgColor)
        s.ctx.fill(CGRect(x: cx, y: yp(120), width: cw2, height: yp(80) - yp(120)))

        // Target lines
        dashedLine(s, from: CGPoint(x: cx, y: yp(120)), to: CGPoint(x: cx + cw2, y: yp(120)), color: green.withAlphaComponent(0.4))
        dashedLine(s, from: CGPoint(x: cx, y: yp(80)), to: CGPoint(x: cx + cw2, y: yp(80)), color: green.withAlphaComponent(0.4))

        // Lines & dots
        drawLine(s, readings: readings, getValue: { $0.systolic }, xp: xp, yp: yp, color: red)
        drawLine(s, readings: readings, getValue: { $0.diastolic }, xp: xp, yp: yp, color: blue)

        // X dates
        xLabels(s, readings: readings, xp: xp, baseY: cy + ch)

        // Legend
        let ly = cy + ch + 16
        legend(s, x: cx, y: ly, items: [("Systolic", red), ("Diastolic", blue), ("Normal range 80–120", green)])
        s.y = ly + 12
    }

    private static func drawPulseChart(_ s: State, readings: [BPReading]) {
        guard readings.count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 100, cy = s.y
        let pv = readings.map(\.pulse)
        let lo = max((pv.min() ?? 50) - 5, 30), hi = (pv.max() ?? 120) + 5
        let r = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(readings.count - 1) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }

        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 10)

        // Area
        s.ctx.saveGState()
        let ap = CGMutablePath()
        ap.move(to: CGPoint(x: xp(0), y: cy + ch))
        for i in 0..<readings.count { ap.addLine(to: CGPoint(x: xp(i), y: yp(readings[i].pulse))) }
        ap.addLine(to: CGPoint(x: xp(readings.count - 1), y: cy + ch))
        ap.closeSubpath()
        s.ctx.addPath(ap)
        s.ctx.setFillColor(pink.withAlphaComponent(0.08).cgColor)
        s.ctx.fillPath()
        s.ctx.restoreGState()

        drawLine(s, readings: readings, getValue: { $0.pulse }, xp: xp, yp: yp, color: pink)
        xLabels(s, readings: readings, xp: xp, baseY: cy + ch)
        s.y = cy + ch + 16
    }

    private static func drawWeeklyChart(_ s: State, weeks: [(key: Date, value: [BPReading])]) {
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 120, cy = s.y
        let avgs = weeks.map { w -> (String, Double, Double) in
            let aS = Double(w.value.map(\.systolic).reduce(0, +)) / Double(w.value.count)
            let aD = Double(w.value.map(\.diastolic).reduce(0, +)) / Double(w.value.count)
            return (w.key.formatted(.dateTime.month(.abbreviated).day()), aS, aD)
        }
        let allV = avgs.flatMap { [$0.1, $0.2] }
        let lo = max(Int(allV.min() ?? 60) - 10, 40), hi = min(Int(allV.max() ?? 180) + 10, 220)
        let r = CGFloat(hi - lo)

        func yp(_ v: Double) -> CGFloat { cy + ch - CGFloat(v - Double(lo)) / r * ch }

        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 20)
        dashedLine(s, from: CGPoint(x: cx, y: yp(120)), to: CGPoint(x: cx + cw2, y: yp(120)), color: green.withAlphaComponent(0.4))

        let gw = cw2 / CGFloat(avgs.count)
        let bw = min(gw * 0.55, 28)
        let va: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: black]
        let da: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]

        for (i, w) in avgs.enumerated() {
            let centerX = cx + gw * CGFloat(i) + gw / 2
            let sY = yp(w.1), dY = yp(w.2)

            // Stacked bar
            s.ctx.saveGState()
            let barR = CGRect(x: centerX - bw/2, y: sY, width: bw, height: dY - sY)
            UIBezierPath(roundedRect: barR, cornerRadius: 2).addClip()
            let cols = [red.withAlphaComponent(0.65).cgColor, blue.withAlphaComponent(0.65).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: [0, 1]) {
                s.ctx.drawLinearGradient(g, start: CGPoint(x: centerX, y: sY), end: CGPoint(x: centerX, y: dY), options: [])
            }
            s.ctx.restoreGState()

            // Value label
            let st = "\(Int(w.1))"
            let ss = (st as NSString).size(withAttributes: va)
            (st as NSString).draw(at: CGPoint(x: centerX - ss.width/2, y: sY - 11), withAttributes: va)

            // Date label
            let ds = (w.0 as NSString).size(withAttributes: da)
            (w.0 as NSString).draw(at: CGPoint(x: centerX - ds.width/2, y: cy + ch + 3), withAttributes: da)
        }
        legend(s, x: cx, y: cy + ch + 16, items: [("Avg Systolic", red), ("Avg Diastolic", blue)])
        s.y = cy + ch + 28
    }

    private static func drawTimePeriods(_ s: State, periods: [(String, [BPReading])]) {
        let bw = (cw - CGFloat(periods.count - 1) * 8) / CGFloat(periods.count)
        let bh: CGFloat = 56

        for (i, p) in periods.enumerated() {
            let x = m + CGFloat(i) * (bw + 8)
            let n = p.1.count
            let aS = p.1.map(\.systolic).reduce(0, +) / n
            let aD = p.1.map(\.diastolic).reduce(0, +) / n
            let aP = p.1.map(\.pulse).reduce(0, +) / n

            // Box
            s.ctx.setFillColor(stripe.cgColor)
            UIBezierPath(roundedRect: CGRect(x: x, y: s.y, width: bw, height: bh), cornerRadius: 4).fill()
            s.ctx.setStrokeColor(border.cgColor)
            s.ctx.setLineWidth(0.5)
            UIBezierPath(roundedRect: CGRect(x: x, y: s.y, width: bw, height: bh), cornerRadius: 4).stroke()

            let ta: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: mid]
            (p.0 as NSString).draw(at: CGPoint(x: x + 8, y: s.y + 5), withAttributes: ta)

            let ba: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold), .foregroundColor: black]
            ("\(aS)/\(aD)" as NSString).draw(at: CGPoint(x: x + 8, y: s.y + 18), withAttributes: ba)

            let pa: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: dark]
            ("HR \(aP) bpm  |  \(n) readings" as NSString).draw(at: CGPoint(x: x + 8, y: s.y + bh - 14), withAttributes: pa)
        }
        s.y += bh + 8
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

    private static func drawLine(_ s: State, readings: [BPReading], getValue: (BPReading) -> Int, xp: (Int) -> CGFloat, yp: (Int) -> CGFloat, color: UIColor) {
        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(1.2)
        s.ctx.move(to: CGPoint(x: xp(0), y: yp(getValue(readings[0]))))
        for i in 1..<readings.count { s.ctx.addLine(to: CGPoint(x: xp(i), y: yp(getValue(readings[i])))) }
        s.ctx.strokePath()

        s.ctx.setFillColor(color.cgColor)
        let dr: CGFloat = readings.count > 40 ? 1.2 : 2.0
        for i in 0..<readings.count {
            s.ctx.fillEllipse(in: CGRect(x: xp(i) - dr, y: yp(getValue(readings[i])) - dr, width: dr * 2, height: dr * 2))
        }
    }

    private static func xLabels(_ s: State, readings: [BPReading], xp: (Int) -> CGFloat, baseY: CGFloat) {
        let a: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
        let step = max(readings.count / 5, 1)
        for i in stride(from: 0, to: readings.count, by: step) {
            let l = readings[i].timestamp.formatted(.dateTime.month(.abbreviated).day())
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

    // MARK: - Health Chart Helpers

    private static func drawDailyChart(_ s: State, values: [HealthContext.DailyValue], color: UIColor, unit: String, refLines: [(Double, String, UIColor)] = [], zoneRange: (Double, Double, UIColor)? = nil) {
        guard values.count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 120, cy = s.y

        let rawVals = values.map(\.value)
        var loD = (rawVals.min() ?? 0)
        var hiD = (rawVals.max() ?? 100)

        // Include reference lines and zone in range calculation
        for rl in refLines {
            loD = min(loD, rl.0)
            hiD = max(hiD, rl.0)
        }
        if let zone = zoneRange {
            loD = min(loD, zone.0)
            hiD = max(hiD, zone.1)
        }

        let padding = max((hiD - loD) * 0.1, 1.0)
        loD -= padding
        hiD += padding
        let lo = Int(floor(loD))
        let hi = Int(ceil(hiD))
        let range = CGFloat(hi - lo)

        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(values.count - 1) * cw2 }
        func yp(_ v: Double) -> CGFloat { cy + ch - CGFloat(v - Double(lo)) / range * ch }

        // Grid
        let gridStep = max(Int(range) / 5, 1)
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: gridStep)

        // Zone shading
        if let zone = zoneRange {
            let zoneTop = yp(zone.1)
            let zoneBot = yp(zone.0)
            s.ctx.setFillColor(zone.2.withAlphaComponent(0.08).cgColor)
            s.ctx.fill(CGRect(x: cx, y: zoneTop, width: cw2, height: zoneBot - zoneTop))
        }

        // Reference lines
        for rl in refLines {
            let ry = yp(rl.0)
            dashedLine(s, from: CGPoint(x: cx, y: ry), to: CGPoint(x: cx + cw2, y: ry), color: rl.2.withAlphaComponent(0.5))
            let la: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: rl.2]
            (rl.1 as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: ry - 4), withAttributes: la)
        }

        // Line
        s.ctx.setStrokeColor(color.cgColor)
        s.ctx.setLineWidth(1.2)
        s.ctx.move(to: CGPoint(x: xp(0), y: yp(values[0].value)))
        for i in 1..<values.count {
            s.ctx.addLine(to: CGPoint(x: xp(i), y: yp(values[i].value)))
        }
        s.ctx.strokePath()

        // Dots
        s.ctx.setFillColor(color.cgColor)
        let dr: CGFloat = values.count > 40 ? 1.2 : 2.0
        for i in 0..<values.count {
            s.ctx.fillEllipse(in: CGRect(x: xp(i) - dr, y: yp(values[i].value) - dr, width: dr * 2, height: dr * 2))
        }

        // X-axis date labels
        let da: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
        let step = max(values.count / 5, 1)
        for i in stride(from: 0, to: values.count, by: step) {
            let l = values[i].dateLabel
            (l as NSString).draw(at: CGPoint(x: xp(i) - 12, y: cy + ch + 3), withAttributes: da)
        }

        // Unit label
        let ua: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: mid]
        (unit as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: cy - 2), withAttributes: ua)

        s.y = cy + ch + 18
    }

    private static func drawDailyBarChart(_ s: State, values: [HealthContext.DailyValue], color: UIColor, unit: String, targetLine: Double? = nil, targetLabel: String = "") {
        guard !values.isEmpty else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 120, cy = s.y

        let rawVals = values.map(\.value)
        var hiD = (rawVals.max() ?? 100)
        if let target = targetLine { hiD = max(hiD, target) }
        let padding = max(hiD * 0.1, 1.0)
        hiD += padding
        let hi = Int(ceil(hiD))
        let lo = 0
        let range = CGFloat(hi - lo)

        func yp(_ v: Double) -> CGFloat { cy + ch - CGFloat(v - Double(lo)) / range * ch }

        // Grid
        let gridStep = max(hi / 5, 1)
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: gridStep)

        // Target line
        if let target = targetLine {
            let ty = yp(target)
            dashedLine(s, from: CGPoint(x: cx, y: ty), to: CGPoint(x: cx + cw2, y: ty), color: green.withAlphaComponent(0.6))
            if !targetLabel.isEmpty {
                let tla: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: green]
                (targetLabel as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: ty - 4), withAttributes: tla)
            }
        }

        // Bars
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

        // X-axis date labels
        let da: [NSAttributedString.Key: Any] = [.font: f7, .foregroundColor: mid]
        let labelStep = max(values.count / 6, 1)
        for i in stride(from: 0, to: values.count, by: labelStep) {
            let centerX = cx + gw * CGFloat(i) + gw / 2
            let l = values[i].dateLabel
            let ls = (l as NSString).size(withAttributes: da)
            (l as NSString).draw(at: CGPoint(x: centerX - ls.width / 2, y: cy + ch + 3), withAttributes: da)
        }

        // Unit label
        let ua: [NSAttributedString.Key: Any] = [.font: f8, .foregroundColor: mid]
        (unit as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: cy - 2), withAttributes: ua)

        s.y = cy + ch + 18
    }

    // MARK: - Cardiovascular Fitness Page

    private static func drawCardioFitnessPage(_ s: State, healthContext hc: HealthContext) {
        newPage(s)
        text(s, "CARDIOVASCULAR FITNESS", font: f14b, color: accent)
        s.y += 4
        hline(s, color: accent, width: 1.5)
        s.y += 12

        if !hc.restingHeartRates.isEmpty {
            section(s, "RESTING HEART RATE")
            drawDailyChart(s, values: hc.restingHeartRates, color: pink, unit: "bpm",
                           zoneRange: (60, 100, green))
            let avg = hc.restingHeartRates.map(\.value).reduce(0, +) / Double(hc.restingHeartRates.count)
            text(s, String(format: "Average resting HR: %.0f bpm  |  %d data points", avg, hc.restingHeartRates.count), font: f9, color: dark)
            s.y += 16
        }

        if !hc.hrvValues.isEmpty {
            pageBreak(s, 180)
            section(s, "HEART RATE VARIABILITY")
            drawDailyChart(s, values: hc.hrvValues, color: purple, unit: "ms",
                           refLines: [(50, "<50ms low", orange)],
                           zoneRange: nil)
            let avg = hc.hrvValues.map(\.value).reduce(0, +) / Double(hc.hrvValues.count)
            text(s, String(format: "Average HRV (SDNN): %.0f ms  |  %d data points", avg, hc.hrvValues.count), font: f9, color: dark)
            s.y += 16
        }

        if !hc.vo2MaxValues.isEmpty {
            pageBreak(s, 200)
            section(s, "VO2 MAX (CARDIO FITNESS)")
            drawDailyChart(s, values: hc.vo2MaxValues, color: blue, unit: "mL/kg/min",
                           refLines: [
                               (20, "Poor <20", red),
                               (35, "Fair 20-35", orange),
                               (45, "Good 35-45", green),
                           ],
                           zoneRange: (35, 45, green))
            let avg = hc.vo2MaxValues.map(\.value).reduce(0, +) / Double(hc.vo2MaxValues.count)
            let fitnessLabel: String
            if avg < 20 { fitnessLabel = "Poor" }
            else if avg < 35 { fitnessLabel = "Fair" }
            else if avg < 45 { fitnessLabel = "Good" }
            else { fitnessLabel = "Excellent" }
            text(s, String(format: "Average VO2 Max: %.1f mL/kg/min (%@)  |  %d data points", avg, fitnessLabel, hc.vo2MaxValues.count), font: f9, color: dark)
            s.y += 16
        }

        footer(s)
    }

    // MARK: - Lifestyle Factors Page

    private static func drawLifestyleFactorsPage(_ s: State, healthContext hc: HealthContext) {
        newPage(s)
        text(s, "LIFESTYLE FACTORS", font: f14b, color: accent)
        s.y += 4
        hline(s, color: accent, width: 1.5)
        s.y += 12

        if !hc.stepCounts.isEmpty {
            section(s, "DAILY STEP COUNT")
            drawDailyBarChart(s, values: hc.stepCounts, color: blue, unit: "steps",
                              targetLine: 7000, targetLabel: "7,000 steps")
            let avg = hc.stepCounts.map(\.value).reduce(0, +) / Double(hc.stepCounts.count)
            let daysAbove = hc.stepCounts.filter { $0.value >= 7000 }.count
            text(s, String(format: "Average: %.0f steps/day  |  %d of %d days above 7,000", avg, daysAbove, hc.stepCounts.count), font: f9, color: dark)
            s.y += 16
        }

        if !hc.exerciseMinutes.isEmpty {
            pageBreak(s, 200)
            section(s, "WEEKLY EXERCISE MINUTES")

            // Aggregate exercise minutes by week
            let cal = Calendar.current
            let weekGroups = Dictionary(grouping: hc.exerciseMinutes) { entry in
                cal.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date
            }
            let weeklyTotals = weekGroups.sorted { $0.key < $1.key }.map { (weekStart, entries) in
                HealthContext.DailyValue(date: weekStart, value: entries.map(\.value).reduce(0, +))
            }

            drawDailyBarChart(s, values: weeklyTotals, color: green, unit: "min/wk",
                              targetLine: 150, targetLabel: "150 min target")
            let avgWeekly = weeklyTotals.map(\.value).reduce(0, +) / Double(max(weeklyTotals.count, 1))
            let weeksAbove = weeklyTotals.filter { $0.value >= 150 }.count
            text(s, String(format: "Average: %.0f min/week  |  %d of %d weeks met 150-min target", avgWeekly, weeksAbove, weeklyTotals.count), font: f9, color: dark)
            s.y += 16
        }

        if !hc.bodyMassValues.isEmpty {
            pageBreak(s, 180)
            section(s, "BODY WEIGHT TREND")
            drawDailyChart(s, values: hc.bodyMassValues, color: orange, unit: "kg")
            let first = hc.bodyMassValues.first!.value
            let last = hc.bodyMassValues.last!.value
            let change = last - first
            let changeStr = change >= 0 ? String(format: "+%.1f", change) : String(format: "%.1f", change)
            text(s, String(format: "Current: %.1f kg  |  Change: %@ kg over period", last, changeStr), font: f9, color: dark)
            s.y += 16
        }

        footer(s)
    }

    // MARK: - Sleep & Recovery Page

    private static func drawSleepRecoveryPage(_ s: State, healthContext hc: HealthContext) {
        newPage(s)
        text(s, "SLEEP & RECOVERY", font: f14b, color: accent)
        s.y += 4
        hline(s, color: accent, width: 1.5)
        s.y += 12

        if !hc.sleepEntries.isEmpty {
            section(s, "SLEEP DURATION")
            let sleepValues = hc.sleepEntries.map {
                HealthContext.DailyValue(date: $0.date, value: $0.hours)
            }
            drawDailyBarChart(s, values: sleepValues, color: purple, unit: "hours",
                              targetLine: 7.0, targetLabel: "7h target")
            let avg = sleepValues.map(\.value).reduce(0, +) / Double(sleepValues.count)
            let daysAbove = sleepValues.filter { $0.value >= 7.0 }.count
            text(s, String(format: "Average: %.1f hours/night  |  %d of %d nights above 7h", avg, daysAbove, sleepValues.count), font: f9, color: dark)
            s.y += 16
        }

        if !hc.respiratoryRates.isEmpty {
            pageBreak(s, 180)
            section(s, "RESPIRATORY RATE")
            drawDailyChart(s, values: hc.respiratoryRates, color: blue, unit: "br/min",
                           zoneRange: (12, 20, green))
            let avg = hc.respiratoryRates.map(\.value).reduce(0, +) / Double(hc.respiratoryRates.count)
            text(s, String(format: "Average: %.1f breaths/min  |  Normal range: 12–20 br/min", avg), font: f9, color: dark)
            s.y += 16
        }

        if !hc.oxygenSaturation.isEmpty {
            pageBreak(s, 180)
            section(s, "BLOOD OXYGEN (SpO2)")
            drawDailyChart(s, values: hc.oxygenSaturation, color: red, unit: "%",
                           refLines: [(90, "Danger <90%", red)],
                           zoneRange: (95, 100, green))
            let avg = hc.oxygenSaturation.map(\.value).reduce(0, +) / Double(hc.oxygenSaturation.count)
            let belowDanger = hc.oxygenSaturation.filter { $0.value < 90 }.count
            text(s, String(format: "Average: %.1f%%  |  Readings below 90%%: %d", avg, belowDanger), font: f9, color: dark)
            s.y += 16
        }

        footer(s)
    }

    // MARK: - Correlation Analysis Page

    private static func drawCorrelationPage(_ s: State, readings: [BPReading], healthContext hc: HealthContext) {
        let cal = Calendar.current

        // We need at least 2 weeks of BP data and some health data (steps or sleep)
        let bpWeeks = Dictionary(grouping: readings) { r in cal.dateInterval(of: .weekOfYear, for: r.timestamp)?.start ?? r.timestamp }
        guard bpWeeks.count >= 2, (!hc.stepCounts.isEmpty || !hc.sleepEntries.isEmpty) else { return }

        newPage(s)
        text(s, "CORRELATION ANALYSIS", font: f14b, color: accent)
        s.y += 4
        hline(s, color: accent, width: 1.5)
        s.y += 12

        section(s, "WEEKLY HEALTH METRICS SUMMARY")

        // Build weekly data
        let allWeekStarts = bpWeeks.keys.sorted()

        struct WeekRow {
            let label: String
            var avgBP: String = "–"
            var avgHR: String = "–"
            var avgSteps: String = "–"
            var avgSleep: String = "–"
            var avgHRV: String = "–"
        }

        var rows: [WeekRow] = []

        let stepsByWeek = Dictionary(grouping: hc.stepCounts) { v in cal.dateInterval(of: .weekOfYear, for: v.date)?.start ?? v.date }
        let sleepByWeek = Dictionary(grouping: hc.sleepEntries) { e in cal.dateInterval(of: .weekOfYear, for: e.date)?.start ?? e.date }
        let hrvByWeek = Dictionary(grouping: hc.hrvValues) { v in cal.dateInterval(of: .weekOfYear, for: v.date)?.start ?? v.date }
        let hrByWeek = Dictionary(grouping: hc.restingHeartRates) { v in cal.dateInterval(of: .weekOfYear, for: v.date)?.start ?? v.date }

        for weekStart in allWeekStarts {
            let weekLabel = weekStart.formatted(.dateTime.month(.abbreviated).day())
            var row = WeekRow(label: weekLabel)

            // BP average
            if let bpReadings = bpWeeks[weekStart], !bpReadings.isEmpty {
                let avgS = bpReadings.map(\.systolic).reduce(0, +) / bpReadings.count
                let avgD = bpReadings.map(\.diastolic).reduce(0, +) / bpReadings.count
                row.avgBP = "\(avgS)/\(avgD)"
            }

            // HR average
            if let hrVals = hrByWeek[weekStart], !hrVals.isEmpty {
                let avg = hrVals.map(\.value).reduce(0, +) / Double(hrVals.count)
                row.avgHR = String(format: "%.0f", avg)
            }

            // Steps average
            if let stepsVals = stepsByWeek[weekStart], !stepsVals.isEmpty {
                let avg = stepsVals.map(\.value).reduce(0, +) / Double(stepsVals.count)
                row.avgSteps = String(format: "%.0f", avg)
            }

            // Sleep average
            if let sleepVals = sleepByWeek[weekStart], !sleepVals.isEmpty {
                let avg = sleepVals.map(\.hours).reduce(0, +) / Double(sleepVals.count)
                row.avgSleep = String(format: "%.1fh", avg)
            }

            // HRV average
            if let hrvVals = hrvByWeek[weekStart], !hrvVals.isEmpty {
                let avg = hrvVals.map(\.value).reduce(0, +) / Double(hrvVals.count)
                row.avgHRV = String(format: "%.0f", avg)
            }

            rows.append(row)
        }

        // Draw table
        let colX: [CGFloat] = [m + 6, m + 80, m + 150, m + 220, m + 300, m + 380]
        let colHeaders = ["Week", "Avg BP", "Avg HR", "Avg Steps", "Avg Sleep", "Avg HRV"]

        // Header
        fillRect(s, x: m, w: cw, h: 16, color: accent)
        let ha: [NSAttributedString.Key: Any] = [.font: f8b, .foregroundColor: UIColor.white]
        for (t, x) in zip(colHeaders, colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y + 2), withAttributes: ha)
        }
        s.y += 17

        let la: [NSAttributedString.Key: Any] = [.font: f9, .foregroundColor: black]
        for (i, row) in rows.enumerated() {
            pageBreak(s, 16)
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 15, color: stripe) }
            let vals = [row.label, row.avgBP, row.avgHR, row.avgSteps, row.avgSleep, row.avgHRV]
            for (j, v) in vals.enumerated() {
                (v as NSString).draw(at: CGPoint(x: colX[j], y: s.y + 1), withAttributes: la)
            }
            s.y += 15
        }

        s.y += 12
        text(s, "This table shows weekly averages across blood pressure, heart rate, activity, sleep, and heart rate variability to help identify correlations between lifestyle factors and cardiovascular metrics.", font: f8, color: mid, w: cw)

        footer(s)
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
