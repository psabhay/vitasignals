import SwiftUI
import SwiftData
import Charts

struct MetricDetailView: View {
    let metricType: String
    @EnvironmentObject var dataStore: HealthDataStore
    @Environment(\.modelContext) private var modelContext
    @State private var timeRange: ChartTimeRange = .month
    @State private var cachedFiltered: [HealthRecord] = []
    @State private var cachedChartData: [HealthRecord] = []
    @State private var showAddForm = false
    @State private var editingRecord: HealthRecord?
    @State private var showAllRecords = false

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
                    recordsList
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(definition?.name ?? "Metric")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddForm = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Add \(definition?.name ?? "record")")
            }
        }
        .sheet(isPresented: $showAddForm) {
            HealthRecordFormView(metricType: metricType)
        }
        .onAppear { recomputeFiltered() }
        .onChange(of: timeRange) { _, _ in
            showAllRecords = false
            recomputeFiltered()
        }
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

    // MARK: - Records List

    @ViewBuilder
    private var recordsList: some View {
        if !cachedFiltered.isEmpty {
            let displayRecords = showAllRecords ? cachedFiltered : Array(cachedFiltered.prefix(10))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Readings")
                        .font(.headline)
                    Spacer()
                    Text("\(cachedFiltered.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(displayRecords) { record in
                    Button {
                        editingRecord = record
                    } label: {
                        recordRow(record)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteRecord(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if record.id != displayRecords.last?.id {
                        Divider()
                    }
                }

                if cachedFiltered.count > 10 && !showAllRecords {
                    Button {
                        withAnimation { showAllRecords = true }
                    } label: {
                        Text("Show all \(cachedFiltered.count) readings")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .sheet(item: $editingRecord) { record in
                HealthRecordFormView(metricType: record.metricType, record: record)
            }
        }
    }

    @ViewBuilder
    private func recordRow(_ record: HealthRecord) -> some View {
        if let def = definition {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if metricType == MetricType.bloodPressure {
                        Text(record.formattedPrimaryValue)
                            .font(.subheadline.bold().monospacedDigit())
                    } else {
                        Text("\(def.formatValue(record.primaryValue)) \(def.unit)")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                    if !record.notes.isEmpty {
                        Text(record.notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.timestamp.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }

    private func deleteRecord(_ record: HealthRecord) {
        if let hkID = record.healthKitUUID {
            modelContext.insert(DismissedHealthKitRecord(metricType: record.metricType, healthKitUUID: hkID))
        }
        modelContext.delete(record)
        try? modelContext.save()
        dataStore.refresh()
        recomputeFiltered()
    }

}
