import SwiftUI
import Charts

// MARK: - Comparison Metric Chart

struct ComparisonMetricChart: View {
    let records: [HealthRecord]
    let definition: MetricDefinition
    let xDomain: ClosedRange<Date>
    var onTap: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    @State private var showInfo = false
    @State private var cachedChartData: [HealthRecord] = []
    @State private var cachedAvg: Double = 0

    private func recompute() {
        cachedChartData = downsample(records)
        cachedAvg = records.map(\.primaryValue).reduce(0, +) / Double(max(records.count, 1))
    }

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
                Chart {
                    ForEach(cachedChartData) { record in
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

                    ReferenceRangeMarks(definition)
                }
                .chartXScale(domain: xDomain)
                .chartXAxis { chartDateXAxisContent() }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: ChartHeight.card)
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
                HStack {
                    Text("Avg: \(definition.formatValue(cachedAvg)) \(definition.unit)")
                    Spacer()
                    Text("\(records.count) readings")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .chartCardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var label = "\(definition.name) chart."
            if let latest = records.last {
                label += " Latest: \(definition.formatValue(latest.primaryValue)) \(definition.unit)."
            }
            if records.count >= 2 {
                label += " Average: \(definition.formatValue(cachedAvg)) \(definition.unit). \(records.count) readings."
            }
            return label
        }())
        .accessibilityHint(onTap != nil ? "Tap to view details" : "")
        .onAppear { recompute() }
        .onChange(of: records) { _, _ in recompute() }
    }
}

// MARK: - Comparison BP Chart

struct ComparisonBPChart: View {
    let records: [HealthRecord]
    let xDomain: ClosedRange<Date>
    var onTap: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    @State private var cachedChartData: [HealthRecord] = []
    @State private var cachedAvgSys: Int = 0
    @State private var cachedAvgDia: Int = 0

    private func recompute() {
        cachedChartData = downsample(records)
        cachedAvgSys = records.isEmpty ? 0 : records.map(\.systolic).reduce(0, +) / records.count
        cachedAvgDia = records.isEmpty ? 0 : records.map(\.diastolic).reduce(0, +) / records.count
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
                Chart {
                    ForEach(cachedChartData) { record in
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

                    BPReferenceMarks()
                }
                .chartXScale(domain: xDomain)
                .chartXAxis { chartDateXAxisContent() }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartLegend(position: .bottom)
                .frame(height: ChartHeight.card)
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
                HStack {
                    Text("Avg: \(cachedAvgSys)/\(cachedAvgDia) mmHg")
                    Spacer()
                    Text("\(records.count) readings")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
        .chartCardStyle()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var label = "Blood Pressure chart."
            if let latest = records.last {
                label += " Latest: \(latest.systolic)/\(latest.diastolic) mmHg."
            }
            if records.count >= 2 {
                label += " Average: \(cachedAvgSys)/\(cachedAvgDia) mmHg. \(records.count) readings."
            }
            return label
        }())
        .accessibilityHint(onTap != nil ? "Tap to view details" : "")
        .onAppear { recompute() }
        .onChange(of: records) { _, _ in recompute() }
    }
}
