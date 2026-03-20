import Foundation

// MARK: - Report Block

/// Each discrete content section of a PDF report.
/// Templates compose these blocks to control structure and order.
enum ReportBlock: Sendable, Hashable, Identifiable {
    case header
    case patientInfo
    case bpSummary
    case classificationBreakdown
    case metricsSummary
    case bpChart
    case pulseChart
    case timeOfDayAnalysis
    case metricCharts(categories: Set<MetricCategory>?)
    case disclaimer
    case bpReadingsTable

    var id: String {
        switch self {
        case .header: return "header"
        case .patientInfo: return "patientInfo"
        case .bpSummary: return "bpSummary"
        case .classificationBreakdown: return "classificationBreakdown"
        case .metricsSummary: return "metricsSummary"
        case .bpChart: return "bpChart"
        case .pulseChart: return "pulseChart"
        case .timeOfDayAnalysis: return "timeOfDayAnalysis"
        case .metricCharts: return "metricCharts"
        case .disclaimer: return "disclaimer"
        case .bpReadingsTable: return "bpReadingsTable"
        }
    }
}

// MARK: - Report Template

/// A named list of content blocks that defines the structure of a PDF report.
/// Templates are orthogonal to styles — any template works with any style.
struct ReportTemplate: Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let blocks: [ReportBlock]

    static func == (lhs: ReportTemplate, rhs: ReportTemplate) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Predefined Templates

    /// Everything — all charts, tables, annexure.
    static let comprehensive = ReportTemplate(
        id: "comprehensive",
        name: "Comprehensive",
        icon: "doc.text.fill",
        description: "All charts, tables, and detailed annexure",
        blocks: [
            .header, .patientInfo, .bpSummary, .classificationBreakdown,
            .metricsSummary, .bpChart, .pulseChart, .timeOfDayAnalysis,
            .metricCharts(categories: nil), .disclaimer
        ]
    )

    /// Tables and statistics only, no charts.
    static let summary = ReportTemplate(
        id: "summary",
        name: "Summary",
        icon: "list.bullet.rectangle",
        description: "Tables and statistics only, no charts",
        blocks: [
            .header, .patientInfo, .bpSummary, .classificationBreakdown,
            .metricsSummary, .disclaimer
        ]
    )

    /// BP and heart rate deep dive.
    static let cardioFocus = ReportTemplate(
        id: "cardioFocus",
        name: "Cardio Focus",
        icon: "heart.text.square",
        description: "Blood pressure and heart rate deep dive",
        blocks: [
            .header, .patientInfo, .bpSummary, .classificationBreakdown,
            .bpChart, .pulseChart, .timeOfDayAnalysis,
            .metricCharts(categories: [.cardioFitness]), .disclaimer
        ]
    )

    /// What a doctor wants — summaries + BP charts + raw data.
    static let providerReport = ReportTemplate(
        id: "providerReport",
        name: "Provider Report",
        icon: "stethoscope",
        description: "Summaries, BP charts, and raw data for clinicians",
        blocks: [
            .header, .patientInfo, .bpSummary, .classificationBreakdown,
            .metricsSummary, .bpChart, .pulseChart, .timeOfDayAnalysis,
            .disclaimer
        ]
    )

    static let allTemplates: [ReportTemplate] = [.comprehensive, .summary, .cardioFocus, .providerReport]
}
