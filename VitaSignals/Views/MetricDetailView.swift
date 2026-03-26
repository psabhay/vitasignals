import SwiftUI
import Charts

struct MetricDetailView: View {
    let metricType: String
    @EnvironmentObject var dataStore: HealthDataStore
    @State private var timeRange: ChartTimeRange = .month
    @State private var cachedFiltered: [HealthRecord] = []
    @State private var cachedChartData: [HealthRecord] = []

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: metricType)
    }

    private func recomputeFiltered() {
        let records = dataStore.records(for: metricType)
        if let days = timeRange.days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
            cachedFiltered = records.filter { $0.timestamp >= cutoff }
        } else {
            cachedFiltered = records
        }
        let sortedForChart = Array(cachedFiltered.reversed())
        cachedChartData = downsample(sortedForChart, maxPoints: ChartResolution.detail)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(ChartTimeRange.detailCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if cachedFiltered.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: definition?.icon ?? "chart.xyaxis.line",
                        description: Text("No \(definition?.name ?? "") data in this time range")
                    )
                    .padding(.top, 40)
                } else {
                    summaryCard
                    chartCard
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(definition?.name ?? "Metric")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { recomputeFiltered() }
        .onChange(of: timeRange) { _, _ in recomputeFiltered() }
        .onChange(of: dataStore.recordCount) { _, _ in recomputeFiltered() }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        let values = cachedFiltered.map(\.primaryValue)
        let count = Double(max(values.count, 1))
        let avg = values.reduce(0, +) / count
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0

        return VStack(spacing: 14) {
            HStack {
                if let def = definition {
                    Image(systemName: def.icon)
                        .foregroundStyle(def.color)
                }
                Text("Summary")
                    .font(.headline)
                Spacer()
                Text("\(cachedFiltered.count) records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                statColumn(title: "Average", value: definition?.formatValue(avg) ?? "", unit: definition?.unit ?? "")
                Divider().frame(height: 50)
                statColumn(title: "Minimum", value: definition?.formatValue(minV) ?? "", unit: definition?.unit ?? "")
                Divider().frame(height: 50)
                statColumn(title: "Maximum", value: definition?.formatValue(maxV) ?? "", unit: definition?.unit ?? "")
            }

            if let def = definition, let refMin = def.referenceMin, let refMax = def.referenceMax {
                let inRange = values.filter { $0 >= refMin && $0 <= refMax }.count
                let pct = values.isEmpty ? 0 : Int(Double(inRange) / count * 100)
                HStack {
                    Text("In normal range (\(def.formatValue(refMin))–\(def.formatValue(refMax)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct)%")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(pct >= 70 ? .green : .orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Chart Card

    @ViewBuilder
    private var chartCard: some View {
        if let def = definition, cachedChartData.count >= 2 {
            let chartData = cachedChartData
            VStack(alignment: .leading, spacing: 12) {
                Text("Trend").font(.headline)

                if let refMin = def.referenceMin, let refMax = def.referenceMax {
                    Text("Normal: \(def.formatValue(refMin))–\(def.formatValue(refMax)) \(def.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Chart {
                    ForEach(chartData) { record in
                        if def.chartStyle == .bar {
                            BarMark(
                                x: .value("Date", record.timestamp, unit: .day),
                                y: .value(def.unit, record.primaryValue)
                            )
                            .foregroundStyle(def.color.opacity(0.7))
                        } else {
                            LineMark(
                                x: .value("Date", record.timestamp),
                                y: .value(def.unit, record.primaryValue)
                            )
                            .foregroundStyle(def.color)
                            .interpolationMethod(.monotone)
                        }
                    }

                    if let refMin = def.referenceMin {
                        RuleMark(y: .value("Min", refMin))
                            .lineStyle(ChartRefLine.stroke)
                            .foregroundStyle(ChartRefLine.normalColor)
                            .annotation(position: .topLeading, alignment: .leading) {
                                Text("Normal min: \(def.formatValue(refMin)) \(def.unit)")
                                    .font(.caption2)
                                    .foregroundStyle(ChartRefLine.annotationColor)
                            }
                    }
                    if let refMax = def.referenceMax {
                        RuleMark(y: .value("Max", refMax))
                            .lineStyle(ChartRefLine.stroke)
                            .foregroundStyle(ChartRefLine.normalColor)
                            .annotation(position: .bottomLeading, alignment: .leading) {
                                Text("Normal max: \(def.formatValue(refMax)) \(def.unit)")
                                    .font(.caption2)
                                    .foregroundStyle(ChartRefLine.annotationColor)
                            }
                    }
                }
                .frame(height: ChartHeight.detail)
                .chartYAxis { AxisMarks(position: .leading) }
                .clipped()

                let values = cachedFiltered.map(\.primaryValue)
                let avg = values.reduce(0, +) / Double(max(values.count, 1))
                HStack {
                    Text("Avg: \(def.formatValue(avg)) \(def.unit)")
                    Spacer()
                    if let latest = cachedFiltered.first {
                        Text("Latest: \(def.formatValue(latest.primaryValue)) \(def.unit)")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

}
