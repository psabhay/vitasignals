import SwiftUI
import Charts

// MARK: - Downsample Helper

/// Thin an array of records to at most `maxPoints` evenly spaced entries.
/// Keeps first and last for accurate range display.
func downsample(_ records: [HealthRecord], maxPoints: Int = 60) -> [HealthRecord] {
    guard records.count > maxPoints else { return records }
    let step = Double(records.count - 1) / Double(maxPoints - 1)
    var result: [HealthRecord] = []
    for i in 0..<maxPoints {
        let index = Int((Double(i) * step).rounded())
        result.append(records[index])
    }
    return result
}

// MARK: - Comparison Metric Chart

struct ComparisonMetricChart: View {
    let records: [HealthRecord]
    let definition: MetricDefinition
    let xDomain: ClosedRange<Date>
    var onTap: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    @State private var showInfo = false

    private var yMin: Double {
        let dataMin = records.map(\.primaryValue).min() ?? 0
        let refMin = definition.referenceMin ?? dataMin
        return min(dataMin, refMin)
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: definition.icon)
                    .foregroundStyle(definition.color)
                    .font(.subheadline)
                Text(definition.name)
                    .font(.subheadline.bold())
                if definition.description != nil {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfo) {
                        Text(definition.description ?? "")
                            .font(.subheadline)
                            .padding()
                            .frame(idealWidth: 260)
                            .presentationCompactAdaptation(.popover)
                    }
                }
                Spacer()
                if let latest = records.last {
                    Text("\(definition.formatValue(latest.primaryValue)) \(definition.unit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let onHide {
                    Button {
                        onHide()
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide \(definition.name) chart")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
            }

            if records.count >= 2 {
                let chartData = downsample(records)
                Chart {
                    ForEach(chartData) { record in
                        if definition.chartStyle == .bar {
                            BarMark(
                                x: .value("Date", record.timestamp, unit: .day),
                                y: .value(definition.unit, record.primaryValue)
                            )
                            .foregroundStyle(definition.color.opacity(0.7))
                        } else {
                            LineMark(
                                x: .value("Date", record.timestamp),
                                y: .value(definition.unit, record.primaryValue)
                            )
                            .foregroundStyle(definition.color)
                            .interpolationMethod(.monotone)
                        }
                    }

                    if let refMin = definition.referenceMin {
                        RuleMark(y: .value("Min", refMin))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.green.opacity(0.4))
                            .annotation(position: .topLeading, alignment: .leading) {
                                Text("Normal min: \(definition.formatValue(refMin)) \(definition.unit)")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                    }
                    if let refMax = definition.referenceMax {
                        RuleMark(y: .value("Max", refMax))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.green.opacity(0.4))
                            .annotation(position: .bottomLeading, alignment: .leading) {
                                Text("Normal max: \(definition.formatValue(refMax)) \(definition.unit)")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                    }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
                .clipped()
            } else if records.count == 1 {
                HStack {
                    Text(definition.formatValue(records[0].primaryValue))
                        .font(.title2.bold().monospacedDigit())
                    Text(definition.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("1 data point")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            } else {
                Text("No data in this range")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            // Summary footer
            if records.count >= 2 {
                let values = records.map(\.primaryValue)
                let avg = values.reduce(0, +) / Double(values.count)
                HStack {
                    Text("Avg: \(definition.formatValue(avg)) \(definition.unit)")
                    Spacer()
                    Text("\(records.count) readings")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var label = "\(definition.name) chart."
            if let latest = records.last {
                label += " Latest: \(definition.formatValue(latest.primaryValue)) \(definition.unit)."
            }
            if records.count >= 2 {
                let avg = records.map(\.primaryValue).reduce(0, +) / Double(records.count)
                label += " Average: \(definition.formatValue(avg)) \(definition.unit). \(records.count) readings."
            }
            return label
        }())
        .accessibilityHint(onTap != nil ? "Tap to view details" : "")
    }
}

// MARK: - Comparison BP Chart

struct ComparisonBPChart: View {
    let records: [HealthRecord]
    let xDomain: ClosedRange<Date>
    var onTap: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                Text("Blood Pressure")
                    .font(.subheadline.bold())
                Spacer()
                if let latest = records.last {
                    Text("\(latest.systolic)/\(latest.diastolic) mmHg")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let onHide {
                    Button {
                        onHide()
                    } label: {
                        Image(systemName: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide Blood Pressure chart")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
            }

            if records.count >= 2 {
                let chartData = downsample(records)
                Chart {
                    ForEach(chartData) { record in
                        LineMark(
                            x: .value("Date", record.timestamp),
                            y: .value("mmHg", record.systolic),
                            series: .value("Type", "Systolic")
                        )
                        .foregroundStyle(.red)
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", record.timestamp),
                            y: .value("mmHg", record.diastolic),
                            series: .value("Type", "Diastolic")
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                    }

                    RuleMark(y: .value("Ref", 120))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.red.opacity(0.3))
                        .annotation(position: .bottomLeading, alignment: .leading) {
                            Text("Systolic normal: <120 mmHg")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    RuleMark(y: .value("Ref", 80))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.blue.opacity(0.3))
                        .annotation(position: .bottomLeading, alignment: .leading) {
                            Text("Diastolic normal: <80 mmHg")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
                .chartXScale(domain: xDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(position: .bottom)
                .frame(height: 180)
                .clipped()
            } else if records.count == 1 {
                HStack {
                    Text("\(records[0].systolic)/\(records[0].diastolic)")
                        .font(.title2.bold().monospacedDigit())
                    Text("mmHg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("1 data point")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            } else {
                Text("No data in this range")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }

            // Summary footer
            if records.count >= 2 {
                let avgSys = records.map(\.systolic).reduce(0, +) / records.count
                let avgDia = records.map(\.diastolic).reduce(0, +) / records.count
                HStack {
                    Text("Avg: \(avgSys)/\(avgDia) mmHg")
                    Spacer()
                    Text("\(records.count) readings")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var label = "Blood Pressure chart."
            if let latest = records.last {
                label += " Latest: \(latest.systolic)/\(latest.diastolic) mmHg."
            }
            if records.count >= 2 {
                let avgSys = records.map(\.systolic).reduce(0, +) / records.count
                let avgDia = records.map(\.diastolic).reduce(0, +) / records.count
                label += " Average: \(avgSys)/\(avgDia) mmHg. \(records.count) readings."
            }
            return label
        }())
        .accessibilityHint(onTap != nil ? "Tap to view details" : "")
    }
}
