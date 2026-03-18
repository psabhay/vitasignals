import SwiftUI
import SwiftData
import Charts

struct MetricCardView: View {
    let metricType: String
    let latestValue: String
    let unit: String
    let sparklineData: [(Date, Double)]

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: metricType)
    }

    var body: some View {
        guard let def = definition else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: def.icon)
                        .foregroundStyle(def.color)
                        .font(.caption)
                    Text(def.name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(latestValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if sparklineData.count >= 2 {
                    Chart {
                        ForEach(sparklineData, id: \.0) { point in
                            LineMark(
                                x: .value("Date", point.0),
                                y: .value("Value", point.1)
                            )
                            .foregroundStyle(def.color.opacity(0.6))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 30)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }
}
