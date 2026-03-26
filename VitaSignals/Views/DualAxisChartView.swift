import SwiftUI
import Charts

/// A chart card that overlays two metrics with independent Y-axis scaling.
/// Left axis shows metric A's values, right axis shows metric B's values.
/// Both are normalized to [0, 1] internally so each fills the chart height.
struct DualAxisChartView: View {
    let chartName: String
    let leftRecords: [HealthRecord]
    let rightRecords: [HealthRecord]
    let leftDefinition: MetricDefinition
    let rightDefinition: MetricDefinition
    let xDomain: ClosedRange<Date>
    var onHide: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    // MARK: - Normalization

    private struct NormalizedPoint: Identifiable {
        let id: UUID
        let date: Date
        let normalized: Double
        let series: String
    }

    private struct AxisStats {
        let min: Double
        let max: Double
        let range: Double
    }

    @State private var cachedLeftStats: AxisStats?
    @State private var cachedRightStats: AxisStats?
    @State private var cachedLeftPoints: [NormalizedPoint] = []
    @State private var cachedRightPoints: [NormalizedPoint] = []
    @State private var cachedLeftAvg: Double = 0
    @State private var cachedRightAvg: Double = 0

    private static func computeStats(for records: [HealthRecord]) -> AxisStats {
        let values = records.map(\.primaryValue)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let range = Swift.max(hi - lo, 1e-6)
        return AxisStats(min: lo, max: hi, range: range)
    }

    private static func computePoints(records: [HealthRecord], stats: AxisStats, seriesName: String) -> [NormalizedPoint] {
        downsample(records, maxPoints: ChartResolution.card).map { r in
            NormalizedPoint(
                id: r.id, date: r.timestamp,
                normalized: (r.primaryValue - stats.min) / stats.range,
                series: seriesName
            )
        }
    }

    private func recomputeCache() {
        let ls = Self.computeStats(for: leftRecords)
        let rs = Self.computeStats(for: rightRecords)
        cachedLeftStats = ls
        cachedRightStats = rs
        cachedLeftPoints = Self.computePoints(records: leftRecords, stats: ls, seriesName: leftDefinition.name)
        cachedRightPoints = Self.computePoints(records: rightRecords, stats: rs, seriesName: rightDefinition.name)
        cachedLeftAvg = leftRecords.map(\.primaryValue).reduce(0, +) / Double(max(leftRecords.count, 1))
        cachedRightAvg = rightRecords.map(\.primaryValue).reduce(0, +) / Double(max(rightRecords.count, 1))
    }

    private var hasEnoughData: Bool {
        leftRecords.count >= 2 && rightRecords.count >= 2
    }

    private var hasAnyData: Bool {
        !leftRecords.isEmpty || !rightRecords.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if hasEnoughData {
                dualChart
                legend
                summaryFooter
            } else if hasAnyData {
                sparseDataView
            } else {
                noDataView
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .onAppear { recomputeCache() }
        .onChange(of: leftRecords) { recomputeCache() }
        .onChange(of: rightRecords) { recomputeCache() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chartName) comparison chart. \(leftDefinition.name) versus \(rightDefinition.name). \(leftRecords.count) and \(rightRecords.count) readings respectively.")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.text.clipboard")
                .foregroundStyle(.purple)
                .font(.subheadline)
            Text(chartName)
                .font(.subheadline.bold())
            Spacer()
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
                .accessibilityLabel("Hide \(chartName) chart")
            }
        }
    }

    // MARK: - Dual-Axis Chart

    private var dualChart: some View {
        let lStats = cachedLeftStats ?? Self.computeStats(for: leftRecords)
        let rStats = cachedRightStats ?? Self.computeStats(for: rightRecords)
        let tickPositions: [Double] = [0, 0.25, 0.5, 0.75, 1.0]

        return Chart {
            ForEach(cachedLeftPoints) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.normalized),
                    series: .value("Metric", p.series)
                )
                .foregroundStyle(leftDefinition.color)
                .interpolationMethod(.monotone)
            }
            ForEach(cachedRightPoints) { p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value("Value", p.normalized),
                    series: .value("Metric", p.series)
                )
                .foregroundStyle(rightDefinition.color)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: -0.05...1.05)
        .chartXAxis { chartDateXAxisContent() }
        .chartYAxis {
            AxisMarks(position: .leading, values: tickPositions) { value in
                let v = value.as(Double.self) ?? 0
                let actual = lStats.min + v * lStats.range
                AxisGridLine()
                AxisValueLabel {
                    Text(leftDefinition.formatValue(actual))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(leftDefinition.color)
                }
            }
            AxisMarks(position: .trailing, values: tickPositions) { value in
                let v = value.as(Double.self) ?? 0
                let actual = rStats.min + v * rStats.range
                AxisValueLabel {
                    Text(rightDefinition.formatValue(actual))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(rightDefinition.color)
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: ChartHeight.dual)
        .clipped()
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(leftDefinition.color)
                    .frame(width: 16, height: 3)
                Text("\(leftDefinition.name) (\(leftDefinition.unit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(rightDefinition.color)
                            .frame(width: 4, height: 3)
                    }
                }
                .frame(width: 16)
                Text("\(rightDefinition.name) (\(rightDefinition.unit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Summary

    private var summaryFooter: some View {
        HStack {
            Text("\(leftDefinition.name) avg: \(leftDefinition.formatValue(cachedLeftAvg))")
                .foregroundStyle(leftDefinition.color)
            Spacer()
            Text("\(rightDefinition.name) avg: \(rightDefinition.formatValue(cachedRightAvg))")
                .foregroundStyle(rightDefinition.color)
        }
        .font(.caption2.monospacedDigit())
    }

    // MARK: - Fallback States

    private var sparseDataView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(leftDefinition.name): \(leftRecords.count) point\(leftRecords.count == 1 ? "" : "s")")
                Text("\(rightDefinition.name): \(rightRecords.count) point\(rightRecords.count == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Text("Need 2+ readings each")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private var noDataView: some View {
        Text("No data in this range")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }
}
