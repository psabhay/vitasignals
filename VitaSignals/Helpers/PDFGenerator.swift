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

    // MARK: - Generate

    static func generate(
        records: [HealthRecord],
        selectedMetrics: Set<String>? = nil,
        periodLabel: String = "",
        profile: ProfileData? = nil,
        style: ReportStyle = .classic,
        template: ReportTemplate = .comprehensive
    ) -> URL? {
        guard !records.isEmpty else { return nil }
        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Health_Report_\(dateStamp()).pdf")
        UIGraphicsBeginPDFContextToFile(url.path, CGRect(x: 0, y: 0, width: pw, height: ph), [
            kCGPDFContextTitle as String: "Health Report",
            kCGPDFContextCreator as String: "VitaSignals"
        ])
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let s = State(ctx, style: style)

        let metrics = selectedMetrics ?? Set(sorted.map(\.metricType))
        let bpRecords = sorted.filter { $0.metricType == MetricType.bloodPressure }
        let nonBPMetrics = metrics.filter { $0 != MetricType.bloodPressure }
        let hasBP = metrics.contains(MetricType.bloodPressure) && !bpRecords.isEmpty

        newPage(s)

        for block in template.blocks {
            drawBlock(block, s: s, sorted: sorted, bpRecords: bpRecords,
                      metrics: metrics, nonBPMetrics: nonBPMetrics, hasBP: hasBP,
                      periodLabel: periodLabel, profile: profile)
        }

        footer(s)
        UIGraphicsEndPDFContext()
        return url
    }

    // MARK: - Block Dispatch

    private static func drawBlock(
        _ block: ReportBlock, s: State, sorted: [HealthRecord], bpRecords: [HealthRecord],
        metrics: Set<String>, nonBPMetrics: Set<String>, hasBP: Bool,
        periodLabel: String, profile: ProfileData?
    ) {
        switch block {
        case .header:
            drawHeader(s, records: sorted, periodLabel: periodLabel, profile: profile)
        case .patientInfo:
            guard let profile, !profile.name.isEmpty else { return }
            drawPatientInfo(s, profile: profile)
        case .bpSummary:
            guard hasBP else { return }
            drawBPSummaryTable(s, records: bpRecords)
        case .classificationBreakdown:
            guard hasBP else { return }
            drawClassificationTable(s, records: bpRecords)
        case .metricsSummary:
            guard !nonBPMetrics.isEmpty else { return }
            drawMetricsSummary(s, records: sorted, metricTypes: nonBPMetrics)
        case .bpChart:
            guard hasBP, bpRecords.count >= 2 else { return }
            let contentH: CGFloat = 181
            pageBreak(s, chartContainerH(s, contentH) + 56)
            drawSectionHeader(s, title: "Blood Pressure", subtitle: "Trends & Heart Rate")
            let startY = beginChartContainer(s, contentH: contentH)
            section(s, "Blood Pressure Trend")
            drawBPChart(s, records: bpRecords)
            endChartContainer(s, startY: startY, contentH: contentH)
        case .pulseChart:
            guard hasBP, bpRecords.filter({ $0.tertiaryValue != nil }).count >= 2 else { return }
            pageBreak(s, chartContainerH(s, 124))
            let startY = beginChartContainer(s, contentH: 124)
            section(s, "Heart Rate Trend")
            drawPulseChart(s, records: bpRecords)
            endChartContainer(s, startY: startY, contentH: 124)
        case .timeOfDayAnalysis:
            guard hasBP, bpRecords.count >= 3 else { return }
            drawTimeOfDaySection(s, records: bpRecords)
        case .metricCharts(let categoryFilter):
            drawMetricChartsBlock(s, sorted: sorted, nonBPMetrics: nonBPMetrics, categoryFilter: categoryFilter)
        case .disclaimer:
            drawDisclaimer(s)
        case .bpReadingsTable:
            guard hasBP else { return }
            newPage(s)
            drawSectionHeader(s, title: "Blood Pressure", subtitle: "Annexure — Detailed Readings")
            section(s, "Detailed Readings  (\(bpRecords.count))")
            drawBPReadingsTable(s, records: bpRecords)
        }
    }

    // MARK: - Metric Charts Block

    private static func drawMetricChartsBlock(
        _ s: State, sorted: [HealthRecord], nonBPMetrics: Set<String>, categoryFilter: Set<MetricCategory>?
    ) {
        let drawableMetrics = nonBPMetrics.sorted().compactMap { type -> (MetricDefinition, [HealthRecord])? in
            let recs = sorted.filter { $0.metricType == type }
            guard recs.count >= 2, let def = MetricRegistry.definition(for: type) else { return nil }
            if let filter = categoryFilter, !filter.contains(def.category) { return nil }
            return (def, recs)
        }
        guard !drawableMetrics.isEmpty else { return }

        let byCategory = Dictionary(grouping: drawableMetrics) { $0.0.category }
        let orderedCategories = MetricCategory.allCases.filter { byCategory[$0] != nil }

        for category in orderedCategories {
            guard let categoryMetrics = byCategory[category] else { continue }
            pageBreak(s, 240)
            if s.y > m + 10 { s.y += 16 }
            drawSectionHeader(s, title: category.rawValue, subtitle: "\(categoryMetrics.count) metric\(categoryMetrics.count == 1 ? "" : "s") with trend data")

            for (def, metricRecords) in categoryMetrics {
                let hasDesc = def.description != nil
                let contentH: CGFloat = hasDesc ? 166 : 154
                pageBreak(s, chartContainerH(s, contentH) + 10)

                let startY = beginChartContainer(s, contentH: contentH)
                section(s, "\(def.name)")

                if let desc = def.description {
                    text(s, desc, font: s.style.captionFont, color: s.style.mutedTextColor, w: cw - 8)
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
                    drawDailyBarChart(s, values: values, color: metricColor(def.type), unit: def.unit,
                                      targetLine: def.referenceMin, targetLabel: def.referenceMin != nil ? "Target" : "")
                } else {
                    drawDailyChart(s, values: values, color: metricColor(def.type), unit: def.unit,
                                   refLines: refLines, zoneRange: zoneRange)
                }

                let avg = values.map(\.value).reduce(0, +) / Double(values.count)
                text(s, String(format: "Average: %@ %@  |  %d data points", def.formatValue(avg), def.unit, values.count), font: s.style.monoFont, color: s.style.secondaryTextColor)
                endChartContainer(s, startY: startY, contentH: contentH)
            }
        }
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
        let fy = ph - 28
        if s.style.layoutVariant == .document {
            s.ctx.setStrokeColor(s.style.borderColor.cgColor)
            s.ctx.setLineWidth(0.3)
        } else {
            s.ctx.setStrokeColor(s.style.accentColor.withAlphaComponent(0.3).cgColor)
            s.ctx.setLineWidth(0.5)
        }
        s.ctx.move(to: CGPoint(x: m, y: fy - 6))
        s.ctx.addLine(to: CGPoint(x: pw - m, y: fy - 6))
        s.ctx.strokePath()
        let la: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
        (s.style.footerText as NSString).draw(at: CGPoint(x: m, y: fy), withAttributes: la)
        let rt = "Page \(s.page)"
        let rs = (rt as NSString).size(withAttributes: la)
        (rt as NSString).draw(at: CGPoint(x: pw - m - rs.width, y: fy), withAttributes: la)
    }

    // MARK: - Chart Container Helpers

    private static func chartContainerH(_ s: State, _ contentH: CGFloat) -> CGFloat {
        switch s.style.layoutVariant {
        case .dashboard: return contentH + 28
        case .editorial: return contentH + 34
        case .document:  return contentH + 16
        }
    }

    private static func beginChartContainer(_ s: State, contentH: CGFloat) -> CGFloat {
        let startY = s.y
        let h = chartContainerH(s, contentH)
        switch s.style.layoutVariant {
        case .dashboard:
            drawCard(s, x: m - 14, y: startY, w: cw + 28, h: h)
            s.y = startY + 14
        case .editorial:
            let rect = CGRect(x: m - 10, y: startY, width: cw + 20, height: h)
            drawRoundedRect(s, rect: rect, radius: s.style.cardCornerRadius, fill: s.style.cardBackground)
            s.y = startY + 16
        case .document:
            let rect = CGRect(x: m, y: startY, width: cw, height: h)
            drawRoundedRect(s, rect: rect, radius: 0, stroke: s.style.borderColor, lineWidth: 0.3)
            s.y = startY + 6
        }
        return startY
    }

    private static func endChartContainer(_ s: State, startY: CGFloat, contentH: CGFloat) {
        let h = chartContainerH(s, contentH)
        switch s.style.layoutVariant {
        case .dashboard: s.y = startY + h + 10
        case .editorial: s.y = startY + h + 14
        case .document:  s.y = startY + h + 6
        }
    }

    // MARK: - Drawing Primitives (Dashboard)

    private static func drawRoundedRect(_ s: State, rect: CGRect, radius: CGFloat, fill: UIColor? = nil, stroke: UIColor? = nil, lineWidth: CGFloat = 0.5) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        if let fill {
            s.ctx.setFillColor(fill.cgColor)
            s.ctx.addPath(path.cgPath)
            s.ctx.fillPath()
        }
        if let stroke {
            s.ctx.setStrokeColor(stroke.cgColor)
            s.ctx.setLineWidth(lineWidth)
            s.ctx.addPath(path.cgPath)
            s.ctx.strokePath()
        }
    }

    private static func drawCard(_ s: State, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, accent: UIColor? = nil) {
        let r = s.style.cardCornerRadius
        let rect = CGRect(x: x, y: y, width: w, height: h)
        drawRoundedRect(s, rect: rect, radius: r, fill: s.style.cardBackground, stroke: s.style.borderColor)
        if let accent {
            let barW: CGFloat = 3.0
            let barRect = CGRect(x: x, y: y, width: barW, height: h)
            let barPath = UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .bottomLeft],
                                       cornerRadii: CGSize(width: r, height: r))
            s.ctx.setFillColor(accent.cgColor)
            s.ctx.addPath(barPath.cgPath)
            s.ctx.fillPath()
        }
    }

    private static func drawStatCard(_ s: State, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                                      value: String, unit: String, label: String, color: UIColor, topAccent: Bool = false) {
        if topAccent {
            // Editorial: colored top bar
            let r = s.style.cardCornerRadius
            let rect = CGRect(x: x, y: y, width: w, height: h)
            drawRoundedRect(s, rect: rect, radius: r, fill: s.style.cardBackground, stroke: s.style.borderColor)
            let barH: CGFloat = 3.5
            let barRect = CGRect(x: x, y: y, width: w, height: barH)
            let barPath = UIBezierPath(roundedRect: barRect, byRoundingCorners: [.topLeft, .topRight],
                                       cornerRadii: CGSize(width: r, height: r))
            s.ctx.setFillColor(color.cgColor)
            s.ctx.addPath(barPath.cgPath)
            s.ctx.fillPath()
        } else {
            // Dashboard: colored left bar
            drawCard(s, x: x, y: y, w: w, h: h, accent: color)
        }
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: topAccent ? 18 : 16, weight: .bold)
        let pad: CGFloat = topAccent ? 16 : 14
        let va: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: s.style.primaryTextColor]
        (value as NSString).draw(at: CGPoint(x: x + pad, y: y + (topAccent ? 12 : 8)), withAttributes: va)
        if !unit.isEmpty {
            let unitA: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
            let valueSize = (value as NSString).size(withAttributes: va)
            (unit as NSString).draw(at: CGPoint(x: x + pad + 2 + valueSize.width, y: y + (topAccent ? 18 : 14)), withAttributes: unitA)
        }
        let la: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.secondaryTextColor]
        (label as NSString).draw(at: CGPoint(x: x + pad, y: y + h - 18), withAttributes: la)
    }

    @discardableResult
    private static func drawPill(_ s: State, x: CGFloat, y: CGFloat, text pillText: String, bg: UIColor, fg: UIColor) -> CGFloat {
        let font = s.style.captionBoldFont
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let size = (pillText as NSString).size(withAttributes: a)
        let pillW = size.width + 12
        let pillH = size.height + 5
        let rect = CGRect(x: x, y: y, width: pillW, height: pillH)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: pillH / 2)
        s.ctx.setFillColor(bg.cgColor)
        s.ctx.addPath(path.cgPath)
        s.ctx.fillPath()
        (pillText as NSString).draw(at: CGPoint(x: x + 6, y: y + 2.5), withAttributes: a)
        return pillW
    }

    private static func drawProgressBar(_ s: State, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, fraction: CGFloat, color: UIColor) {
        let r = h / 2
        let trackRect = CGRect(x: x, y: y, width: w, height: h)
        drawRoundedRect(s, rect: trackRect, radius: r, fill: s.style.stripeColor)
        let fillW = max(w * min(fraction, 1.0), h)
        let fillRect = CGRect(x: x, y: y, width: fillW, height: h)
        drawRoundedRect(s, rect: fillRect, radius: r, fill: color.withAlphaComponent(0.65))
    }

    // MARK: - Section Headers (variant-aware)

    private static func drawSectionHeader(_ s: State, title: String, subtitle: String) {
        switch s.style.layoutVariant {
        case .dashboard:
            s.y += 20
            let titleA: [NSAttributedString.Key: Any] = [.font: s.style.sectionHeaderFont, .foregroundColor: s.style.primaryTextColor]
            (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: titleA)
            s.y += 20
            s.ctx.setStrokeColor(s.style.accentColor.cgColor)
            s.ctx.setLineWidth(2.0)
            s.ctx.move(to: CGPoint(x: m, y: s.y))
            s.ctx.addLine(to: CGPoint(x: m + cw * 0.25, y: s.y))
            s.ctx.strokePath()
            s.y += 8
            let subA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: s.style.mutedTextColor]
            (subtitle as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: subA)
            s.y += 18

        case .editorial:
            s.y += 26
            let titleA: [NSAttributedString.Key: Any] = [.font: s.style.sectionHeaderFont, .foregroundColor: s.style.primaryTextColor]
            (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: titleA)
            s.y += 22
            s.ctx.setStrokeColor(s.style.accentColor.withAlphaComponent(0.4).cgColor)
            s.ctx.setLineWidth(1.0)
            s.ctx.move(to: CGPoint(x: m, y: s.y))
            s.ctx.addLine(to: CGPoint(x: m + cw, y: s.y))
            s.ctx.strokePath()
            s.y += 10
            let subA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: s.style.mutedTextColor]
            (subtitle as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: subA)
            s.y += 22

        case .document:
            s.y += 16
            let titleA: [NSAttributedString.Key: Any] = [.font: s.style.sectionHeaderFont, .foregroundColor: s.style.primaryTextColor]
            (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: titleA)
            s.y += 18
            hline(s, color: s.style.borderColor, width: 0.3)
            s.y += 5
            let subA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: s.style.mutedTextColor]
            (subtitle as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: subA)
            s.y += 16
        }
    }

    // MARK: - Header (3 variants)

    private static func drawHeader(_ s: State, records: [HealthRecord], periodLabel: String, profile: ProfileData? = nil) {
        let period = periodLabel.isEmpty
            ? (records.first.map { "\($0.formattedDateOnly) – \(records.last?.formattedDateOnly ?? $0.formattedDateOnly)" } ?? "")
            : periodLabel
        let metricCount = Set(records.map(\.metricType)).count

        switch s.style.layoutVariant {
        case .dashboard:
            let bannerH: CGFloat = 66
            let bannerRect = CGRect(x: 0, y: 0, width: pw, height: bannerH)
            let bannerPath = UIBezierPath(roundedRect: bannerRect, byRoundingCorners: [.bottomLeft, .bottomRight],
                                           cornerRadii: CGSize(width: 10, height: 10))
            s.ctx.setFillColor(s.style.headerBackground.cgColor)
            s.ctx.addPath(bannerPath.cgPath)
            s.ctx.fillPath()
            let white = UIColor.white
            let appA: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5, weight: .semibold),
                                                        .foregroundColor: white.withAlphaComponent(0.65), .kern: 1.2 as NSNumber]
            ("VITASIGNALS" as NSString).draw(at: CGPoint(x: m, y: 14), withAttributes: appA)
            let titleA: [NSAttributedString.Key: Any] = [.font: s.style.titleFont, .foregroundColor: white]
            ("Health Summary" as NSString).draw(at: CGPoint(x: m, y: 32), withAttributes: titleA)
            if let profile, !profile.name.isEmpty {
                let nameA: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: white.withAlphaComponent(0.9)]
                let nameSize = (profile.name as NSString).size(withAttributes: nameA)
                (profile.name as NSString).draw(at: CGPoint(x: pw - m - nameSize.width, y: 36), withAttributes: nameA)
            }
            s.y = bannerH + 14
            var pillX = m
            pillX += drawPill(s, x: pillX, y: s.y, text: period, bg: s.style.accentColor.withAlphaComponent(0.1), fg: s.style.accentColor) + 8
            pillX += drawPill(s, x: pillX, y: s.y, text: "\(records.count) records", bg: s.style.stripeColor, fg: s.style.secondaryTextColor) + 8
            drawPill(s, x: pillX, y: s.y, text: "\(metricCount) metrics", bg: s.style.stripeColor, fg: s.style.secondaryTextColor)
            s.y += 28

        case .editorial:
            let bannerH: CGFloat = 86
            let bannerRect = CGRect(x: 0, y: 0, width: pw, height: bannerH)
            let bannerPath = UIBezierPath(roundedRect: bannerRect, byRoundingCorners: [.bottomLeft, .bottomRight],
                                           cornerRadii: CGSize(width: 14, height: 14))
            s.ctx.setFillColor(s.style.headerBackground.cgColor)
            s.ctx.addPath(bannerPath.cgPath)
            s.ctx.fillPath()
            // Subtle lighter strip at bottom
            s.ctx.setFillColor(UIColor.white.withAlphaComponent(0.07).cgColor)
            s.ctx.fill(CGRect(x: 0, y: bannerH - 20, width: pw, height: 20))
            let white = UIColor.white
            let appA: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5, weight: .semibold),
                                                        .foregroundColor: white.withAlphaComponent(0.5), .kern: 1.5 as NSNumber]
            ("VITASIGNALS" as NSString).draw(at: CGPoint(x: m, y: 16), withAttributes: appA)
            let titleA: [NSAttributedString.Key: Any] = [.font: s.style.titleFont, .foregroundColor: white]
            ("Health Summary" as NSString).draw(at: CGPoint(x: m, y: 38), withAttributes: titleA)
            let infoA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: white.withAlphaComponent(0.7)]
            ("\(period)  ·  \(records.count) records  ·  \(metricCount) metrics" as NSString).draw(at: CGPoint(x: m, y: bannerH - 16), withAttributes: infoA)
            if let profile, !profile.name.isEmpty {
                let nameA: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: white]
                let nameSize = (profile.name as NSString).size(withAttributes: nameA)
                (profile.name as NSString).draw(at: CGPoint(x: pw - m - nameSize.width, y: 42), withAttributes: nameA)
            }
            s.y = bannerH + 20

        case .document:
            s.y = m
            let appA: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8, weight: .medium), .foregroundColor: s.style.mutedTextColor]
            ("VitaSignals" as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: appA)
            if let profile, !profile.name.isEmpty {
                let nameA: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.primaryTextColor]
                let nameSize = (profile.name as NSString).size(withAttributes: nameA)
                (profile.name as NSString).draw(at: CGPoint(x: pw - m - nameSize.width, y: s.y), withAttributes: nameA)
            }
            s.y += 18
            s.ctx.setStrokeColor(s.style.primaryTextColor.cgColor)
            s.ctx.setLineWidth(1.5)
            s.ctx.move(to: CGPoint(x: m, y: s.y))
            s.ctx.addLine(to: CGPoint(x: pw - m, y: s.y))
            s.ctx.strokePath()
            s.y += 12
            text(s, "Health Summary", font: s.style.titleFont, color: s.style.primaryTextColor)
            s.y += 6
            text(s, "\(period)  ·  \(records.count) records  ·  \(metricCount) metrics", font: s.style.sectionSubtitleFont, color: s.style.mutedTextColor)
            s.y += 20
        }
    }

    // MARK: - Patient Info (variant-aware)

    private static func drawPatientInfo(_ s: State, profile: ProfileData) {
        var rows: [(String, String)] = []
        if !profile.name.isEmpty { rows.append(("Patient Name", profile.name)) }
        if profile.age > 0 { rows.append(("Age", "\(profile.age) years")) }
        if !profile.gender.isEmpty { rows.append(("Gender", profile.gender)) }
        if profile.heightCm > 0 { rows.append(("Height", profile.heightFormatted)) }
        if profile.weightKg > 0 { rows.append(("Weight", profile.weightFormatted)) }
        if let bmi = profile.bmi { rows.append(("BMI", String(format: "%.1f (%@)", bmi, profile.bmiCategory))) }
        if !profile.doctorName.isEmpty { rows.append(("Physician", profile.doctorName)) }
        if !profile.medicalNotes.isEmpty { rows.append(("Notes", profile.medicalNotes)) }

        let rowH: CGFloat = s.style.layoutVariant == .document ? 16 : 18
        let cardH = 10 + CGFloat(rows.count) * rowH + 10
        pageBreak(s, cardH + 28)
        section(s, "Patient Information")

        let labelW: CGFloat = 160
        let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.secondaryTextColor]
        let va: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]

        switch s.style.layoutVariant {
        case .dashboard, .editorial:
            let cardY = s.y
            drawCard(s, x: m, y: cardY, w: cw, h: cardH)
            s.y = cardY + 10
            for (i, row) in rows.enumerated() {
                if i > 0 {
                    s.ctx.setStrokeColor(s.style.borderColor.cgColor)
                    s.ctx.setLineWidth(0.3)
                    s.ctx.move(to: CGPoint(x: m + 10, y: s.y))
                    s.ctx.addLine(to: CGPoint(x: m + cw - 10, y: s.y))
                    s.ctx.strokePath()
                }
                (row.0 as NSString).draw(at: CGPoint(x: m + 12, y: s.y + 2), withAttributes: la)
                (row.1 as NSString).draw(at: CGPoint(x: m + labelW, y: s.y + 2), withAttributes: va)
                s.y += rowH
            }
            s.y = cardY + cardH + 10

        case .document:
            for (i, row) in rows.enumerated() {
                if i % 2 == 0 { fillRect(s, x: m, w: cw, h: rowH, color: s.style.stripeColor) }
                (row.0 as NSString).draw(at: CGPoint(x: m + 6, y: s.y + 1), withAttributes: la)
                (row.1 as NSString).draw(at: CGPoint(x: m + labelW, y: s.y + 1), withAttributes: va)
                s.y += rowH
            }
            s.y += 8
        }
    }

    // MARK: - BP Summary (3 variants)

    private static func drawBPSummaryTable(_ s: State, records: [HealthRecord]) {
        let avgSys = records.map(\.systolic).reduce(0, +) / records.count
        let avgDia = records.map(\.diastolic).reduce(0, +) / records.count
        let avgPulse = records.map(\.pulse).reduce(0, +) / records.count
        let cat = BPCategory.classify(systolic: avgSys, diastolic: avgDia)
        let mapVal = Int(Double(avgDia) + Double(avgSys - avgDia) / 3.0)
        let pp = avgSys - avgDia
        let minS = records.map(\.systolic).min() ?? 0
        let maxS = records.map(\.systolic).max() ?? 0
        let minD = records.map(\.diastolic).min() ?? 0
        let maxD = records.map(\.diastolic).max() ?? 0
        let normalPct = Int(Double(records.filter { $0.bpCategory == .normal }.count) / Double(records.count) * 100)

        switch s.style.layoutVariant {
        case .dashboard:
            pageBreak(s, 170)
            section(s, "Blood Pressure Overview")
            let gap: CGFloat = 10
            let cardW = (cw - gap * 2) / 3
            let row1Y = s.y
            drawStatCard(s, x: m, y: row1Y, w: cardW, h: 54, value: "\(avgSys)/\(avgDia)", unit: "mmHg", label: "Average Blood Pressure", color: red)
            drawStatCard(s, x: m + cardW + gap, y: row1Y, w: cardW, h: 54, value: cat.rawValue, unit: "", label: "Classification", color: catColor(cat))
            drawStatCard(s, x: m + (cardW + gap) * 2, y: row1Y, w: cardW, h: 54, value: "\(avgPulse)", unit: "bpm", label: "Average Heart Rate", color: pink)
            let row2Y = row1Y + 62
            drawStatCard(s, x: m, y: row2Y, w: cardW, h: 54, value: "\(minS)–\(maxS)", unit: "mmHg", label: "Systolic Range", color: orange)
            drawStatCard(s, x: m + cardW + gap, y: row2Y, w: cardW, h: 54, value: "\(minD)–\(maxD)", unit: "mmHg", label: "Diastolic Range", color: blue)
            drawStatCard(s, x: m + (cardW + gap) * 2, y: row2Y, w: cardW, h: 54, value: "\(normalPct)%", unit: "", label: "Normal Range", color: green)
            s.y = row2Y + 62
            let detailA: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
            ("MAP: \(mapVal) mmHg  ·  Pulse Pressure: \(pp) mmHg  ·  \(records.count) readings" as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: detailA)
            s.y += 18

        case .editorial:
            pageBreak(s, 200)
            section(s, "Blood Pressure Overview")
            let gap: CGFloat = 12
            let cardW = (cw - gap * 2) / 3
            let cardH: CGFloat = 66
            let row1Y = s.y
            drawStatCard(s, x: m, y: row1Y, w: cardW, h: cardH, value: "\(avgSys)/\(avgDia)", unit: "mmHg", label: "Average Blood Pressure", color: red, topAccent: true)
            drawStatCard(s, x: m + cardW + gap, y: row1Y, w: cardW, h: cardH, value: cat.rawValue, unit: "", label: "Classification", color: catColor(cat), topAccent: true)
            drawStatCard(s, x: m + (cardW + gap) * 2, y: row1Y, w: cardW, h: cardH, value: "\(avgPulse)", unit: "bpm", label: "Average Heart Rate", color: pink, topAccent: true)
            let row2Y = row1Y + cardH + 10
            drawStatCard(s, x: m, y: row2Y, w: cardW, h: cardH, value: "\(minS)–\(maxS)", unit: "mmHg", label: "Systolic Range", color: orange, topAccent: true)
            drawStatCard(s, x: m + cardW + gap, y: row2Y, w: cardW, h: cardH, value: "\(minD)–\(maxD)", unit: "mmHg", label: "Diastolic Range", color: blue, topAccent: true)
            drawStatCard(s, x: m + (cardW + gap) * 2, y: row2Y, w: cardW, h: cardH, value: "\(normalPct)%", unit: "", label: "Normal Range", color: green, topAccent: true)
            s.y = row2Y + cardH + 10
            let detailA: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
            ("MAP: \(mapVal) mmHg  ·  Pulse Pressure: \(pp) mmHg  ·  \(records.count) readings" as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: detailA)
            s.y += 20

        case .document:
            pageBreak(s, 160)
            section(s, "Blood Pressure Summary")
            let tableRows: [(String, String, UIColor)] = [
                ("Average Blood Pressure", "\(avgSys)/\(avgDia) mmHg", s.style.primaryTextColor),
                ("Classification", cat.rawValue, catColor(cat)),
                ("Average Heart Rate", "\(avgPulse) bpm", s.style.primaryTextColor),
                ("Systolic Range", "\(minS) – \(maxS) mmHg", s.style.primaryTextColor),
                ("Diastolic Range", "\(minD) – \(maxD) mmHg", s.style.primaryTextColor),
                ("Mean Arterial Pressure", "\(mapVal) mmHg", s.style.primaryTextColor),
                ("Pulse Pressure", "\(pp) mmHg", s.style.primaryTextColor),
                ("Readings in Normal Range", "\(normalPct)%", s.style.primaryTextColor),
            ]
            let labelW: CGFloat = 200
            for (i, row) in tableRows.enumerated() {
                if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 16, color: s.style.stripeColor) }
                let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.secondaryTextColor]
                (row.0 as NSString).draw(at: CGPoint(x: m + 6, y: s.y + 1), withAttributes: la)
                let va: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: row.2]
                (row.1 as NSString).draw(at: CGPoint(x: m + labelW, y: s.y + 2), withAttributes: va)
                s.y += 16
            }
            s.y += 8
        }
    }

    // MARK: - Classification (3 variants)

    private static func drawClassificationTable(_ s: State, records: [HealthRecord]) {
        let groups = Dictionary(grouping: records) { $0.bpCategory }
        let cats: [BPCategory] = [.normal, .elevated, .highStage1, .highStage2, .crisis]
        let populated = cats.filter { (groups[$0]?.count ?? 0) > 0 }

        switch s.style.layoutVariant {
        case .dashboard, .editorial:
            let rowH: CGFloat = s.style.layoutVariant == .editorial ? 28 : 24
            let cardH = 10 + CGFloat(populated.count) * rowH + 10
            pageBreak(s, cardH + 28)
            section(s, "Classification Breakdown")
            let cardY = s.y
            if s.style.layoutVariant == .dashboard {
                drawCard(s, x: m, y: cardY, w: cw, h: cardH)
            } else {
                let rect = CGRect(x: m, y: cardY, width: cw, height: cardH)
                drawRoundedRect(s, rect: rect, radius: s.style.cardCornerRadius, fill: s.style.cardBackground)
            }
            s.y = cardY + 10
            let barX: CGFloat = m + 140
            let barW: CGFloat = s.style.layoutVariant == .editorial ? 240 : 220
            for (i, cat) in populated.enumerated() {
                let count = groups[cat]!.count
                let pct = Double(count) / Double(records.count)
                let color = catColor(cat)
                let avg = groups[cat]!
                let avgS = avg.map(\.systolic).reduce(0, +) / count
                let avgD = avg.map(\.diastolic).reduce(0, +) / count
                if i > 0 {
                    s.ctx.setStrokeColor(s.style.borderColor.cgColor)
                    s.ctx.setLineWidth(0.2)
                    s.ctx.move(to: CGPoint(x: m + 10, y: s.y))
                    s.ctx.addLine(to: CGPoint(x: m + cw - 10, y: s.y))
                    s.ctx.strokePath()
                }
                s.ctx.setFillColor(color.cgColor)
                s.ctx.fillEllipse(in: CGRect(x: m + 12, y: s.y + 7, width: 8, height: 8))
                let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
                (cat.rawValue as NSString).draw(at: CGPoint(x: m + 26, y: s.y + 4), withAttributes: la)
                drawProgressBar(s, x: barX, y: s.y + 6, w: barW, h: s.style.layoutVariant == .editorial ? 12 : 10, fraction: CGFloat(pct), color: color)
                let pctA: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: s.style.primaryTextColor]
                ("\(Int(pct * 100))%" as NSString).draw(at: CGPoint(x: barX + barW + 8, y: s.y + 4), withAttributes: pctA)
                let detA: [NSAttributedString.Key: Any] = [.font: s.style.monoFont, .foregroundColor: s.style.secondaryTextColor]
                ("\(count) · \(avgS)/\(avgD)" as NSString).draw(at: CGPoint(x: barX + barW + 44, y: s.y + 4), withAttributes: detA)
                s.y += rowH
            }
            s.y = cardY + cardH + 10

        case .document:
            let rowH: CGFloat = 15
            pageBreak(s, CGFloat(populated.count) * rowH + 40)
            section(s, "Classification Breakdown")
            let colX: [CGFloat] = [m + 6, m + 130, m + 190, m + 260]
            let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
            for (t, x) in zip(["Classification", "Count", "Percentage", "Avg BP"], colX) {
                (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
            }
            s.y += 14
            hline(s, color: s.style.borderColor, width: 0.3)
            s.y += 3
            for (i, cat) in cats.enumerated() {
                let count = groups[cat]?.count ?? 0
                guard count > 0 else { continue }
                let pct = Int(Double(count) / Double(records.count) * 100)
                let avg = groups[cat]!
                let avgS = avg.map(\.systolic).reduce(0, +) / count
                let avgD = avg.map(\.diastolic).reduce(0, +) / count
                if i % 2 == 0 { fillRect(s, x: m, w: cw, h: rowH, color: s.style.stripeColor) }
                s.ctx.setFillColor(catColor(cat).cgColor)
                s.ctx.fillEllipse(in: CGRect(x: m + 6, y: s.y + 3, width: 7, height: 7))
                let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
                let va: [NSAttributedString.Key: Any] = [.font: s.style.monoFont, .foregroundColor: s.style.primaryTextColor]
                (cat.rawValue as NSString).draw(at: CGPoint(x: m + 18, y: s.y + 1), withAttributes: la)
                ("\(count)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
                ("\(pct)%" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
                ("\(avgS)/\(avgD)" as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: va)
                s.y += rowH
            }
            s.y += 8
        }
    }

    // MARK: - Metrics Summary (variant-aware)

    private static func drawMetricsSummary(_ s: State, records: [HealthRecord], metricTypes: Set<String>) {
        let metricDefs = metricTypes.sorted().compactMap { type -> (MetricDefinition, [HealthRecord])? in
            let recs = records.filter { $0.metricType == type }
            guard !recs.isEmpty, let def = MetricRegistry.definition(for: type) else { return nil }
            return (def, recs)
        }
        guard !metricDefs.isEmpty else { return }

        let rowH: CGFloat = s.style.layoutVariant == .document ? 15 : 17
        let cardH = 10 + 16 + CGFloat(metricDefs.count) * rowH + 10
        pageBreak(s, cardH + 28)
        section(s, "Health Metrics Summary")

        let colX: [CGFloat] = [m + 12, m + 165, m + 265, m + 385]

        if s.style.layoutVariant != .document {
            let cardY = s.y
            if s.style.layoutVariant == .dashboard {
                drawCard(s, x: m, y: cardY, w: cw, h: cardH)
            } else {
                let rect = CGRect(x: m, y: cardY, width: cw, height: cardH)
                drawRoundedRect(s, rect: rect, radius: s.style.cardCornerRadius, fill: s.style.cardBackground)
            }
            s.y = cardY + 10
            let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
            for (t, x) in zip(["Metric", "Average", "Range", "Points"], colX) {
                (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
            }
            s.y += 14
            s.ctx.setStrokeColor(s.style.borderColor.cgColor)
            s.ctx.setLineWidth(0.3)
            s.ctx.move(to: CGPoint(x: m + 10, y: s.y))
            s.ctx.addLine(to: CGPoint(x: m + cw - 10, y: s.y))
            s.ctx.strokePath()
            s.y += 3
            for (def, metricRecords) in metricDefs {
                let values = metricRecords.map(\.primaryValue)
                let avg = values.reduce(0, +) / Double(values.count)
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 0
                let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
                let va: [NSAttributedString.Key: Any] = [.font: s.style.monoFont, .foregroundColor: s.style.primaryTextColor]
                (def.name as NSString).draw(at: CGPoint(x: colX[0], y: s.y + 1), withAttributes: la)
                ("\(def.formatValue(avg)) \(def.unit)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
                ("\(def.formatValue(minV)) – \(def.formatValue(maxV))" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
                ("\(metricRecords.count)" as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: va)
                s.y += rowH
            }
            s.y = cardY + cardH + 10
        } else {
            let docColX: [CGFloat] = [m + 6, m + 160, m + 260, m + 380]
            let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
            for (t, x) in zip(["Metric", "Average", "Range", "Data Points"], docColX) {
                (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
            }
            s.y += 14
            hline(s, color: s.style.borderColor, width: 0.3)
            s.y += 3
            for (i, (def, metricRecords)) in metricDefs.enumerated() {
                if i % 2 == 0 { fillRect(s, x: m, w: cw, h: rowH, color: s.style.stripeColor) }
                let values = metricRecords.map(\.primaryValue)
                let avg = values.reduce(0, +) / Double(values.count)
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 0
                let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyFont, .foregroundColor: s.style.primaryTextColor]
                let va: [NSAttributedString.Key: Any] = [.font: s.style.monoFont, .foregroundColor: s.style.primaryTextColor]
                (def.name as NSString).draw(at: CGPoint(x: docColX[0], y: s.y + 1), withAttributes: la)
                ("\(def.formatValue(avg)) \(def.unit)" as NSString).draw(at: CGPoint(x: docColX[1], y: s.y + 1), withAttributes: va)
                ("\(def.formatValue(minV)) – \(def.formatValue(maxV))" as NSString).draw(at: CGPoint(x: docColX[2], y: s.y + 1), withAttributes: va)
                ("\(metricRecords.count)" as NSString).draw(at: CGPoint(x: docColX[3], y: s.y + 1), withAttributes: va)
                s.y += rowH
            }
            s.y += 8
        }
    }

    // MARK: - Disclaimer

    private static func drawDisclaimer(_ s: State) {
        pageBreak(s, 70)
        s.y += 12
        let disclaimerText = "Disclaimer: This report is generated from self-recorded data and data imported from Apple Health. It is intended as a supplementary reference for healthcare providers and should not be used for self-diagnosis or treatment decisions."
        let font = s.style.captionFont
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: s.style.mutedTextColor]
        if s.style.layoutVariant == .document {
            hline(s, color: s.style.borderColor)
            s.y += 8
            text(s, disclaimerText, font: font, color: s.style.mutedTextColor, w: cw)
        } else {
            let textW = cw - 24
            let textRect = CGRect(x: 0, y: 0, width: textW, height: 200)
            let textH = (disclaimerText as NSString).boundingRect(with: textRect.size, options: .usesLineFragmentOrigin, attributes: a, context: nil).height
            let cardH = textH + 18
            drawCard(s, x: m, y: s.y, w: cw, h: cardH)
            (disclaimerText as NSString).draw(in: CGRect(x: m + 12, y: s.y + 9, width: textW, height: textH), withAttributes: a)
            s.y += cardH + 8
        }
    }

    // MARK: - BP Readings Table

    private static func drawBPReadingsTable(_ s: State, records: [HealthRecord]) {
        let colW: [CGFloat] = [148, 50, 50, 40, 44, 152]
        let headers = ["Date / Time", "SYS", "DIA", "HR", "MAP", "Context"]

        func tableHeader() {
            if s.style.layoutVariant != .document {
                let headerRect = CGRect(x: m, y: s.y, width: cw, height: 16)
                drawRoundedRect(s, rect: headerRect, radius: 4, fill: s.style.tableHeaderBackground)
            } else {
                fillRect(s, x: m, w: cw, h: 15, color: s.style.tableHeaderBackground)
            }
            var hx = m + 6
            let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.tableHeaderForeground]
            for (j, h) in headers.enumerated() {
                (h as NSString).draw(at: CGPoint(x: hx, y: s.y + 2), withAttributes: ha)
                hx += colW[j]
            }
            s.y += s.style.layoutVariant != .document ? 18 : 16
        }

        tableHeader()

        for (i, r) in records.reversed().enumerated() {
            if s.y + 16 > ph - m - 28 { footer(s); newPage(s); tableHeader() }
            if i % 2 == 0 { fillRect(s, x: m, w: cw, h: 14, color: s.style.stripeColor) }
            let mapV = Int(Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0)
            let ctxLabel = r.bpActivityContext?.rawValue ?? ""
            let vals: [(String, UIColor)] = [
                (r.formattedDate, s.style.primaryTextColor),
                ("\(r.systolic)", red), ("\(r.diastolic)", blue),
                ("\(r.pulse)", pink), ("\(mapV)", purple),
                (ctxLabel, s.style.secondaryTextColor),
            ]
            var cx = m + 6
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
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 135, cy = s.y
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
        guard records.filter({ $0.tertiaryValue != nil }).count >= 2 else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 90, cy = s.y
        let pv = records.compactMap(\.tertiaryValue).map { Int($0) }
        let lo = max((pv.min() ?? 50) - 5, 30), hi = (pv.max() ?? 120) + 5
        let r = CGFloat(hi - lo)
        // Use full records array for X positioning to match BP chart's date range
        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(records.count - 1) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 10)

        // Collect indices that have pulse data
        let pulseIndices = records.indices.filter { records[$0].tertiaryValue != nil }

        // Area fill — only between points with pulse data
        s.ctx.saveGState()
        let ap = CGMutablePath()
        ap.move(to: CGPoint(x: xp(pulseIndices[0]), y: cy + ch))
        for i in pulseIndices { ap.addLine(to: CGPoint(x: xp(i), y: yp(records[i].pulse))) }
        ap.addLine(to: CGPoint(x: xp(pulseIndices.last!), y: cy + ch))
        ap.closeSubpath()
        s.ctx.addPath(ap)
        s.ctx.setFillColor(pink.withAlphaComponent(s.style.chartFillOpacity).cgColor)
        s.ctx.fillPath()
        s.ctx.restoreGState()

        // Line — only connect points with pulse data
        let pulseRecords = pulseIndices.map { records[$0] }
        func pxp(_ i: Int) -> CGFloat { xp(pulseIndices[i]) }
        drawIntLine(s, records: pulseRecords, getValue: { $0.pulse }, xp: pxp, yp: yp, color: pink)

        xLabelsFromRecords(s, records: records, xp: xp, baseY: cy + ch)
        s.y = cy + ch + 16
    }

    // MARK: - Time-of-Day BP Analysis

    private enum TimePeriod: String, CaseIterable {
        case morning = "Morning (5 AM – 12 PM)"
        case afternoon = "Afternoon (12 PM – 5 PM)"
        case evening = "Evening / Night (5 PM – 5 AM)"
        var shortName: String {
            switch self { case .morning: return "Morning"; case .afternoon: return "Afternoon"; case .evening: return "Evening" }
        }
        var hourRange: String {
            switch self { case .morning: return "5:00 – 11:59"; case .afternoon: return "12:00 – 16:59"; case .evening: return "17:00 – 4:59" }
        }
        static func from(hour: Int) -> TimePeriod {
            if hour >= 5 && hour < 12 { return .morning }
            if hour >= 12 && hour < 17 { return .afternoon }
            return .evening
        }
    }

    private static func drawTimeOfDaySection(_ s: State, records: [HealthRecord]) {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { TimePeriod.from(hour: calendar.component(.hour, from: $0.timestamp)) }
        let populatedPeriods = TimePeriod.allCases.filter { (grouped[$0]?.count ?? 0) > 0 }
        guard populatedPeriods.count >= 2 else { return }

        pageBreak(s, 180)
        s.y += 12
        drawSectionHeader(s, title: "Time-of-Day Analysis", subtitle: "Blood pressure patterns by time of day")
        drawTimePeriodSummary(s, grouped: grouped, periods: populatedPeriods, totalCount: records.count)
        s.y += 10

        for period in populatedPeriods {
            guard let periodRecords = grouped[period], periodRecords.count >= 2 else { continue }
            let sorted = periodRecords.sorted { $0.timestamp < $1.timestamp }
            let contentH: CGFloat = 110
            pageBreak(s, chartContainerH(s, contentH))
            let startY = beginChartContainer(s, contentH: contentH)
            drawTimePeriodChart(s, records: sorted, period: period)
            endChartContainer(s, startY: startY, contentH: contentH)
        }
    }

    private static func drawTimePeriodSummary(_ s: State, grouped: [TimePeriod: [HealthRecord]], periods: [TimePeriod], totalCount: Int) {
        let hasMorningEvening = !(grouped[.morning] ?? []).isEmpty && !(grouped[.evening] ?? []).isEmpty
        let noteH: CGFloat = hasMorningEvening ? 18 : 0
        let rowH: CGFloat = 18
        let cardH: CGFloat = 10 + 16 + CGFloat(periods.count) * rowH + noteH + 10
        let colX: [CGFloat] = [m + 12, m + 110, m + 190, m + 268, m + 346, m + 410]

        if s.style.layoutVariant != .document {
            let cardY = s.y
            if s.style.layoutVariant == .dashboard {
                drawCard(s, x: m, y: cardY, w: cw, h: cardH)
            } else {
                let rect = CGRect(x: m, y: cardY, width: cw, height: cardH)
                drawRoundedRect(s, rect: rect, radius: s.style.cardCornerRadius, fill: s.style.cardBackground)
            }
            s.y = cardY + 10
        }

        let ha: [NSAttributedString.Key: Any] = [.font: s.style.captionBoldFont, .foregroundColor: s.style.mutedTextColor]
        for (t, x) in zip(["Time Period", "Avg BP", "Avg HR", "Classification", "Readings", "% Total"], colX) {
            (t as NSString).draw(at: CGPoint(x: x, y: s.y), withAttributes: ha)
        }
        s.y += 14
        if s.style.layoutVariant != .document {
            s.ctx.setStrokeColor(s.style.borderColor.cgColor)
            s.ctx.setLineWidth(0.3)
            s.ctx.move(to: CGPoint(x: m + 10, y: s.y))
            s.ctx.addLine(to: CGPoint(x: m + cw - 10, y: s.y))
            s.ctx.strokePath()
        } else {
            hline(s, color: s.style.borderColor, width: 0.3)
        }
        s.y += 3

        for (i, period) in periods.enumerated() {
            guard let recs = grouped[period], !recs.isEmpty else { continue }
            let avgSys = recs.map(\.systolic).reduce(0, +) / recs.count
            let avgDia = recs.map(\.diastolic).reduce(0, +) / recs.count
            let avgPulse = recs.map(\.pulse).reduce(0, +) / recs.count
            let cat = BPCategory.classify(systolic: avgSys, diastolic: avgDia)
            let pct = Int(Double(recs.count) / Double(totalCount) * 100)
            if s.style.layoutVariant == .document && i % 2 == 0 {
                fillRect(s, x: m, w: cw, h: rowH, color: s.style.stripeColor)
            }
            let la: [NSAttributedString.Key: Any] = [.font: s.style.bodyMediumFont, .foregroundColor: s.style.secondaryTextColor]
            let va: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: s.style.primaryTextColor]
            let ca: [NSAttributedString.Key: Any] = [.font: s.style.monoBoldFont, .foregroundColor: catColor(cat)]
            (period.shortName as NSString).draw(at: CGPoint(x: colX[0], y: s.y + 1), withAttributes: la)
            ("\(avgSys)/\(avgDia)" as NSString).draw(at: CGPoint(x: colX[1], y: s.y + 1), withAttributes: va)
            ("\(avgPulse) bpm" as NSString).draw(at: CGPoint(x: colX[2], y: s.y + 1), withAttributes: va)
            (cat.rawValue as NSString).draw(at: CGPoint(x: colX[3], y: s.y + 1), withAttributes: ca)
            ("\(recs.count)" as NSString).draw(at: CGPoint(x: colX[4], y: s.y + 1), withAttributes: va)
            ("\(pct)%" as NSString).draw(at: CGPoint(x: colX[5], y: s.y + 1), withAttributes: va)
            s.y += rowH
        }

        if hasMorningEvening {
            s.y += 4
            let morningRecs = grouped[.morning]!
            let eveningRecs = grouped[.evening]!
            let mornAvgSys = morningRecs.map(\.systolic).reduce(0, +) / morningRecs.count
            let eveAvgSys = eveningRecs.map(\.systolic).reduce(0, +) / eveningRecs.count
            let diff = mornAvgSys - eveAvgSys
            let note: String
            let noteColor: UIColor
            if diff > 10 {
                note = "⚠ Morning systolic +\(diff) mmHg vs evening — possible morning surge"
                noteColor = orange
            } else if diff < -10 {
                note = "Evening systolic +\(abs(diff)) mmHg vs morning — reduced nocturnal dipping"
                noteColor = s.style.secondaryTextColor
            } else {
                note = "BP relatively stable across time periods"
                noteColor = s.style.mutedTextColor
            }
            let noteA: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: noteColor]
            (note as NSString).draw(at: CGPoint(x: colX[0], y: s.y), withAttributes: noteA)
        }

        if s.style.layoutVariant != .document {
            s.y = (s.y - (hasMorningEvening ? 4 : 0)) // approximate cardY reconstruction
            // Just advance past the card
            let approxCardBottom = s.y + (hasMorningEvening ? 22 : 0) + 10
            s.y = approxCardBottom
        } else {
            s.y += 8
        }
    }

    private static func drawTimePeriodChart(_ s: State, records: [HealthRecord], period: TimePeriod) {
        let titleA: [NSAttributedString.Key: Any] = [.font: s.style.sectionSubtitleFont, .foregroundColor: s.style.accentColor]
        ("\(period.rawValue)  —  \(records.count) readings" as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: titleA)
        s.y += 14
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 80, cy = s.y
        let vals = records.flatMap { [$0.systolic, $0.diastolic] }
        let lo = max((vals.min() ?? 60) - 10, 40), hi = min((vals.max() ?? 180) + 10, 220)
        let r = CGFloat(hi - lo)
        func xp(_ i: Int) -> CGFloat { cx + CGFloat(i) / CGFloat(max(records.count - 1, 1)) * cw2 }
        func yp(_ v: Int) -> CGFloat { cy + ch - CGFloat(v - lo) / r * ch }
        grid(s, cx: cx, cy: cy, cw: cw2, ch: ch, lo: lo, hi: hi, step: 20)
        s.ctx.setFillColor(green.withAlphaComponent(0.06).cgColor)
        s.ctx.fill(CGRect(x: cx, y: yp(120), width: cw2, height: yp(80) - yp(120)))
        dashedLine(s, from: CGPoint(x: cx, y: yp(120)), to: CGPoint(x: cx + cw2, y: yp(120)), color: green.withAlphaComponent(0.4))
        dashedLine(s, from: CGPoint(x: cx, y: yp(80)), to: CGPoint(x: cx + cw2, y: yp(80)), color: green.withAlphaComponent(0.4))
        drawIntLine(s, records: records, getValue: { $0.systolic }, xp: xp, yp: yp, color: red)
        drawIntLine(s, records: records, getValue: { $0.diastolic }, xp: xp, yp: yp, color: blue)
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
        switch s.style.layoutVariant {
        case .dashboard: s.y += 6
        case .editorial: s.y += 8
        case .document:  s.y += 4
        }
        let color: UIColor = s.style.layoutVariant == .document ? s.style.primaryTextColor : s.style.accentColor
        let a: [NSAttributedString.Key: Any] = [.font: s.style.sectionFont, .foregroundColor: color]
        (title as NSString).draw(at: CGPoint(x: m, y: s.y), withAttributes: a)
        s.y += 16
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
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 110, cy = s.y
        let rawVals = values.map(\.value)
        var loD = (rawVals.min() ?? 0), hiD = (rawVals.max() ?? 100)
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
            (values[i].dateLabel as NSString).draw(at: CGPoint(x: xp(i) - 12, y: cy + ch + 3), withAttributes: da)
        }
        let ua: [NSAttributedString.Key: Any] = [.font: s.style.captionFont, .foregroundColor: s.style.mutedTextColor]
        (unit as NSString).draw(at: CGPoint(x: cx + cw2 + 3, y: cy - 2), withAttributes: ua)
        s.y = cy + ch + 16
    }

    private static func drawDailyBarChart(_ s: State, values: [DailyValue], color: UIColor, unit: String, targetLine: Double? = nil, targetLabel: String = "") {
        guard !values.isEmpty else { return }
        let cx = m + 28, cw2 = cw - 36, ch: CGFloat = 110, cy = s.y
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
        s.y = cy + ch + 16
    }

    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateStamp() -> String {
        dateStampFormatter.string(from: .now)
    }
}
