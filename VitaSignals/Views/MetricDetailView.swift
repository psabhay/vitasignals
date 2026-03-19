import SwiftUI
import Charts

struct MetricDetailView: View {
    let metricType: String
    @EnvironmentObject var dataStore: HealthDataStore
    @State private var timeRange: ChartTimeRange = .month
    @State private var selectedRecord: HealthRecord?

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: metricType)
    }

    private var records: [HealthRecord] {
        dataStore.records(for: metricType)
    }

    private var filteredRecords: [HealthRecord] {
        guard let days = timeRange.days else { return records }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return records.filter { $0.timestamp >= cutoff }
    }

    private var sortedForChart: [HealthRecord] {
        filteredRecords.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(ChartTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: definition?.icon ?? "chart.xyaxis.line",
                        description: Text("No \(definition?.name ?? "") data in this time range")
                    )
                    .padding(.top, 40)
                } else {
                    summaryCard
                    chartCard
                    recentRecordsList
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(definition?.name ?? "Metric")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRecord) { record in
            RecordDetailView(record: record)
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        let values = filteredRecords.map(\.primaryValue)
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
                Text("\(filteredRecords.count) records")
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

    private func statColumn(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart Card

    @ViewBuilder
    private var chartCard: some View {
        if let def = definition, sortedForChart.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trend").font(.headline)

                if let refMin = def.referenceMin, let refMax = def.referenceMax {
                    Text("Normal: \(def.formatValue(refMin))–\(def.formatValue(refMax)) \(def.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Chart {
                    ForEach(sortedForChart) { record in
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
                            .symbol(.circle)
                            .interpolationMethod(.catmullRom)
                        }
                    }

                    if let refMin = def.referenceMin {
                        RuleMark(y: .value("Min", refMin))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(.green.opacity(0.5))
                    }
                    if let refMax = def.referenceMax {
                        RuleMark(y: .value("Max", refMax))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .foregroundStyle(.green.opacity(0.5))
                    }
                }
                .frame(height: 220)
                .chartYAxis { AxisMarks(position: .leading) }

                let values = sortedForChart.map(\.primaryValue)
                let avg = values.reduce(0, +) / Double(max(values.count, 1))
                HStack {
                    Text("Avg: \(def.formatValue(avg)) \(def.unit)")
                    Spacer()
                    if let latest = filteredRecords.first {
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

    // MARK: - Recent Records

    private var recentRecordsList: some View {
        let recent = Array(filteredRecords.prefix(20))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Records").font(.headline)
                Spacer()
                Text("\(filteredRecords.count) total").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(recent) { record in
                Button {
                    selectedRecord = record
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.formattedPrimaryValue)
                                .font(.subheadline.bold().monospacedDigit())
                            if let def = definition {
                                Text(def.unit).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(record.formattedDateOnly).font(.caption).foregroundStyle(.secondary)
                            Text(record.formattedTimeOnly).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .tint(.primary)
                if record.id != recent.last?.id {
                    Divider()
                }
            }

            if filteredRecords.count > 20 {
                Text("Showing 20 of \(filteredRecords.count) records")
                    .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
