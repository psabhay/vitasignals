import SwiftUI
import Charts

// MARK: - Chart Heights

enum ChartHeight {
    static let sparkline: CGFloat = 30
    static let compact: CGFloat = 160
    static let card: CGFloat = 180
    static let dual: CGFloat = 200
    static let detail: CGFloat = 220
}

// MARK: - Chart Resolution (Downsample Targets)

enum ChartResolution {
    static let card = 60
    static let detail = 120
}

// MARK: - Reference Line Styling

enum ChartRefLine {
    static let stroke = StrokeStyle(lineWidth: 1, dash: [5, 3])
    static let normalColor = Color.green.opacity(0.5)
    static let annotationColor = Color.green
}

// MARK: - BP Reference Values

enum BPReference {
    static let systolicNormal: Double = 120
    static let diastolicNormal: Double = 80
    static let mapHigh: Double = 100
    static let mapLow: Double = 70
}

// MARK: - Chart Card Chrome

/// Standard card background modifier for chart cards.
struct ChartCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
    }
}

extension View {
    func chartCardStyle() -> some View {
        modifier(ChartCardBackground())
    }

    /// Apply `.chartXScale(domain:)` only when the domain is non-nil.
    @ViewBuilder
    func conditionalXScale(domain: ClosedRange<Date>?) -> some View {
        if let domain {
            self.chartXScale(domain: domain)
        } else {
            self
        }
    }
}

// MARK: - Reference Range Marks

/// Builds RuleMark overlays for a metric's reference range.
struct ReferenceRangeMarks: ChartContent {
    let definition: MetricDefinition
    let showAnnotations: Bool

    init(_ definition: MetricDefinition, showAnnotations: Bool = true) {
        self.definition = definition
        self.showAnnotations = showAnnotations
    }

    var body: some ChartContent {
        if let refMin = definition.referenceMin {
            RuleMark(y: .value("Ref Min", refMin))
                .lineStyle(ChartRefLine.stroke)
                .foregroundStyle(ChartRefLine.normalColor)
                .annotation(position: .topLeading, alignment: .leading) {
                    if showAnnotations {
                        Text("Normal min: \(definition.formatValue(refMin)) \(definition.unit)")
                            .font(.caption2)
                            .foregroundStyle(ChartRefLine.annotationColor)
                    }
                }
        }
        if let refMax = definition.referenceMax {
            RuleMark(y: .value("Ref Max", refMax))
                .lineStyle(ChartRefLine.stroke)
                .foregroundStyle(ChartRefLine.normalColor)
                .annotation(position: .bottomLeading, alignment: .leading) {
                    if showAnnotations {
                        Text("Normal max: \(definition.formatValue(refMax)) \(definition.unit)")
                            .font(.caption2)
                            .foregroundStyle(ChartRefLine.annotationColor)
                    }
                }
        }
    }
}

/// Builds RuleMark overlays for blood pressure systolic/diastolic reference lines.
struct BPReferenceMarks: ChartContent {
    let showAnnotations: Bool

    init(showAnnotations: Bool = true) {
        self.showAnnotations = showAnnotations
    }

    var body: some ChartContent {
        RuleMark(y: .value("Target Sys", BPReference.systolicNormal))
            .lineStyle(ChartRefLine.stroke)
            .foregroundStyle(ChartRefLine.normalColor)
            .annotation(position: .trailing, alignment: .leading) {
                if showAnnotations {
                    Text("\(Int(BPReference.systolicNormal))").font(.caption2).foregroundStyle(ChartRefLine.annotationColor)
                }
            }
        RuleMark(y: .value("Target Dia", BPReference.diastolicNormal))
            .lineStyle(ChartRefLine.stroke)
            .foregroundStyle(ChartRefLine.normalColor.opacity(0.6))
            .annotation(position: .trailing, alignment: .leading) {
                if showAnnotations {
                    Text("\(Int(BPReference.diastolicNormal))").font(.caption2).foregroundStyle(ChartRefLine.annotationColor)
                }
            }
    }
}

// MARK: - Standard Chart Axes

/// Standard X axis with abbreviated date labels.
@AxisContentBuilder
func chartDateXAxisContent() -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
        AxisGridLine()
        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
    }
}

// MARK: - Chart Time Range

enum ChartTimeRange: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case twoWeeks = "14 Days"
    case month = "30 Days"
    case threeMonths = "90 Days"
    case all = "All Time"
    case custom = "Custom"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .threeMonths: return 90
        case .all, .custom: return nil
        }
    }

    /// Cases suitable for MetricDetailView (no custom date picker there).
    static var detailCases: [ChartTimeRange] {
        [.week, .twoWeeks, .month, .threeMonths, .all]
    }
}
