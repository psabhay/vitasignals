import SwiftUI
import SwiftData
import Charts

enum ChartTimeRange: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case twoWeeks = "14 Days"
    case month = "30 Days"
    case threeMonths = "90 Days"
    case all = "All Time"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .threeMonths: return 90
        case .all: return nil
        }
    }
}

struct ChartsContainerView: View {
    @EnvironmentObject var dataStore: HealthDataStore
    @State private var timeRange: ChartTimeRange = .week
    @State private var selectedMetricType: String = MetricType.bloodPressure

    private var filteredRecords: [HealthRecord] {
        var result = dataStore.records(for: selectedMetricType)
        if let days = timeRange.days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
            result = result.filter { $0.timestamp >= cutoff }
        }
        return result
    }

    // Sort once for chart consumption — records from dataStore are reverse-chronological
    private var sortedForChart: [HealthRecord] {
        filteredRecords.reversed()
    }

    private var availableMetricTypes: [String] {
        let types = dataStore.availableMetricTypes
        return MetricRegistry.all.map(\.type).filter { types.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Time range picker
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(ChartTimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Metric type picker
                    if availableMetricTypes.count > 1 {
                        metricPicker
                    }

                    if filteredRecords.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("No \(MetricRegistry.definition(for: selectedMetricType)?.name ?? "records") in this time range")
                        )
                        .padding(.top, 60)
                    } else if selectedMetricType == MetricType.bloodPressure {
                        bpCharts
                    } else {
                        genericChart
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Charts")
            .withProfileButton()
        }
    }

    // MARK: - Metric Picker

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableMetricTypes, id: \.self) { type in
                    if let def = MetricRegistry.definition(for: type) {
                        FilterChip(
                            title: def.name,
                            icon: def.icon,
                            color: def.color,
                            isSelected: selectedMetricType == type
                        ) {
                            selectedMetricType = type
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - BP Charts

    @ViewBuilder
    private var bpCharts: some View {
        let sorted = sortedForChart

        BPTrendChart(records: sorted)
        PulseChart(records: sorted)
        BPSummaryCard(records: sorted)
        WeeklyAveragesChart(records: sorted)
        MorningVsEveningChart(records: sorted)
        MAPTrendChart(records: sorted)
    }

    // MARK: - Generic Metric Chart

    @ViewBuilder
    private var genericChart: some View {
        if let def = MetricRegistry.definition(for: selectedMetricType) {
            GenericMetricChart(records: sortedForChart, definition: def)
        }
    }
}

// MARK: - Generic Metric Chart Card

struct GenericMetricChart: View {
    let records: [HealthRecord]
    let definition: MetricDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(definition.name)
                .font(.headline)
            if let refMin = definition.referenceMin, let refMax = definition.referenceMax {
                Text("Normal: \(definition.formatValue(refMin))–\(definition.formatValue(refMax)) \(definition.unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(records) { record in
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
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", record.timestamp),
                            y: .value(definition.unit, record.primaryValue)
                        )
                        .foregroundStyle(definition.color)
                        .symbolSize(records.count > 30 ? 10 : 20)
                    }
                }

                if let refMin = definition.referenceMin {
                    RuleMark(y: .value("Ref Min", refMin))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                }
                if let refMax = definition.referenceMax {
                    RuleMark(y: .value("Ref Max", refMax))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                }
            }
            .frame(height: 220)
            .chartYAxis { AxisMarks(position: .leading) }

            if !records.isEmpty {
                let avg = records.map(\.primaryValue).reduce(0, +) / Double(records.count)
                let minV = records.map(\.primaryValue).min() ?? 0
                let maxV = records.map(\.primaryValue).max() ?? 0
                HStack {
                    Text("Avg: \(definition.formatValue(avg)) \(definition.unit)")
                    Spacer()
                    Text("Range: \(definition.formatValue(minV)) – \(definition.formatValue(maxV))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - BP Trend Line Chart

struct BPTrendChart: View {
    let records: [HealthRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blood Pressure Trend")
                .font(.headline)

            Chart {
                ForEach(records) { record in
                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("mmHg", record.systolic),
                        series: .value("Type", "Systolic")
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("mmHg", record.diastolic),
                        series: .value("Type", "Diastolic")
                    )
                    .foregroundStyle(.blue)
                    .symbol(.diamond)
                    .interpolationMethod(.catmullRom)
                }

                RuleMark(y: .value("Target Sys", 120))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.5))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("120").font(.caption2).foregroundStyle(.green)
                    }
                RuleMark(y: .value("Target Dia", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.3))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("80").font(.caption2).foregroundStyle(.green)
                    }
            }
            .frame(height: 220)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartLegend(position: .bottom)

            HStack(spacing: 16) {
                Label("Systolic", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(.red)
                Label("Diastolic", systemImage: "diamond.fill")
                    .font(.caption2).foregroundStyle(.blue)
                Label("Normal", systemImage: "line.diagonal")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Pulse Chart

struct PulseChart: View {
    let records: [HealthRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pulse Trend")
                .font(.headline)

            Chart {
                ForEach(records) { record in
                    AreaMark(
                        x: .value("Date", record.timestamp),
                        y: .value("BPM", record.pulse)
                    )
                    .foregroundStyle(.pink.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("BPM", record.pulse)
                    )
                    .foregroundStyle(.pink)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 160)
            .chartYAxis { AxisMarks(position: .leading) }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Clinical Summary Card

struct BPSummaryCard: View {
    let records: [HealthRecord]

    private var avgSystolic: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.systolic).reduce(0, +) / records.count
    }
    private var avgDiastolic: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.diastolic).reduce(0, +) / records.count
    }
    private var avgPulse: Int {
        guard !records.isEmpty else { return 0 }
        return records.map(\.pulse).reduce(0, +) / records.count
    }
    private var avgCategory: BPCategory {
        BPCategory.classify(systolic: avgSystolic, diastolic: avgDiastolic)
    }
    private var percentNormal: Int {
        guard !records.isEmpty else { return 0 }
        let normal = records.filter { $0.bpCategory == .normal }.count
        return Int(Double(normal) / Double(records.count) * 100)
    }

    private func categoryColor(_ cat: BPCategory) -> Color {
        switch cat {
        case .normal: return .green
        case .elevated: return .yellow
        case .highStage1: return .orange
        case .highStage2: return .red
        case .crisis: return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Summary")
                    .font(.headline)
                Spacer()
                Text("\(records.count) readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Average BP").font(.caption).foregroundStyle(.secondary)
                    Text("\(avgSystolic)/\(avgDiastolic)")
                        .font(.title2.bold().monospacedDigit())
                    Text(avgCategory.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(categoryColor(avgCategory))
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                VStack(spacing: 4) {
                    Text("Avg Pulse").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                        Text("\(avgPulse)").font(.title2.bold().monospacedDigit())
                    }
                    Text("bpm").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                VStack(spacing: 4) {
                    Text("In Range").font(.caption).foregroundStyle(.secondary)
                    Text("\(percentNormal)%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(percentNormal >= 50 ? .green : .orange)
                    Text("normal").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            let minS = records.map(\.systolic).min() ?? 0
            let maxS = records.map(\.systolic).max() ?? 0
            let minD = records.map(\.diastolic).min() ?? 0
            let maxD = records.map(\.diastolic).max() ?? 0

            HStack {
                Text("Systolic range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(minS) – \(maxS) mmHg").font(.caption.monospacedDigit())
            }
            HStack {
                Text("Diastolic range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(minD) – \(maxD) mmHg").font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Weekly Averages Chart

struct WeeklyAveragesChart: View {
    let records: [HealthRecord]

    private struct WeekData: Identifiable {
        let id = UUID()
        let weekStart: Date
        let avgSystolic: Double
        let avgDiastolic: Double
        let count: Int
        var label: String { weekStart.formatted(.dateTime.month(.abbreviated).day()) }
    }

    private var weeklyData: [WeekData] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { record in
            calendar.dateInterval(of: .weekOfYear, for: record.timestamp)?.start ?? record.timestamp
        }
        return grouped.map { weekStart, weekRecords in
            WeekData(
                weekStart: weekStart,
                avgSystolic: Double(weekRecords.map(\.systolic).reduce(0, +)) / Double(weekRecords.count),
                avgDiastolic: Double(weekRecords.map(\.diastolic).reduce(0, +)) / Double(weekRecords.count),
                count: weekRecords.count
            )
        }.sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        if weeklyData.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Averages").font(.headline)

                Chart {
                    ForEach(weeklyData) { week in
                        BarMark(
                            x: .value("Week", week.label),
                            yStart: .value("Diastolic", week.avgDiastolic),
                            yEnd: .value("Systolic", week.avgSystolic)
                        )
                        .foregroundStyle(
                            .linearGradient(colors: [.blue.opacity(0.7), .red.opacity(0.7)], startPoint: .bottom, endPoint: .top)
                        )
                    }
                    RuleMark(y: .value("Target Sys", 120))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                    RuleMark(y: .value("Target Dia", 80))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.3))
                }
                .frame(height: 220)
                .chartYAxis { AxisMarks(position: .leading) }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - Morning vs Evening

struct MorningVsEveningChart: View {
    let records: [HealthRecord]

    private struct PeriodStats: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let avgSystolic: Double
        let avgDiastolic: Double
        let avgPulse: Double
        let count: Int
    }

    private var periodData: [PeriodStats] {
        let calendar = Calendar.current
        let morning = records.filter { let h = calendar.component(.hour, from: $0.timestamp); return h >= 5 && h < 12 }
        let afternoon = records.filter { let h = calendar.component(.hour, from: $0.timestamp); return h >= 12 && h < 17 }
        let evening = records.filter { let h = calendar.component(.hour, from: $0.timestamp); return h >= 17 || h < 5 }

        var result: [PeriodStats] = []
        for (name, icon, group) in [
            ("Morning\n5am–12pm", "sunrise", morning),
            ("Afternoon\n12pm–5pm", "sun.max", afternoon),
            ("Evening\n5pm–5am", "moon.stars", evening)
        ] {
            if !group.isEmpty {
                result.append(PeriodStats(
                    name: name, icon: icon,
                    avgSystolic: Double(group.map(\.systolic).reduce(0, +)) / Double(group.count),
                    avgDiastolic: Double(group.map(\.diastolic).reduce(0, +)) / Double(group.count),
                    avgPulse: Double(group.map(\.pulse).reduce(0, +)) / Double(group.count),
                    count: group.count
                ))
            }
        }
        return result
    }

    var body: some View {
        if periodData.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Time of Day Comparison").font(.headline)

                HStack(spacing: 12) {
                    ForEach(periodData) { period in
                        VStack(spacing: 8) {
                            Image(systemName: period.icon).font(.title3).foregroundStyle(.secondary)
                            Text("\(Int(period.avgSystolic))/\(Int(period.avgDiastolic))")
                                .font(.headline.monospacedDigit())
                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(.pink)
                                Text("\(Int(period.avgPulse))").font(.caption.monospacedDigit())
                            }
                            Text(period.name).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Text("\(period.count) readings").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - MAP Trend

struct MAPTrendChart: View {
    let records: [HealthRecord]

    private func mapValue(_ r: HealthRecord) -> Double {
        Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0
    }
    private func pulsePressure(_ r: HealthRecord) -> Int {
        r.systolic - r.diastolic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mean Arterial Pressure").font(.headline)
            Text("MAP = diastolic + \u{2153}(systolic \u{2212} diastolic). Normal: 70\u{2013}100 mmHg")
                .font(.caption).foregroundStyle(.secondary)

            Chart {
                ForEach(records) { record in
                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("MAP", mapValue(record))
                    )
                    .foregroundStyle(.purple)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", record.timestamp),
                        y: .value("PP", pulsePressure(record)),
                        series: .value("Type", "Pulse Pressure")
                    )
                    .foregroundStyle(.orange)
                    .symbol(.diamond)
                    .interpolationMethod(.catmullRom)
                }

                RuleMark(y: .value("MAP High", 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.4))
                RuleMark(y: .value("MAP Low", 70))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.4))
            }
            .frame(height: 200)
            .chartYAxis { AxisMarks(position: .leading) }

            HStack(spacing: 16) {
                Label("MAP", systemImage: "circle.fill").font(.caption2).foregroundStyle(.purple)
                Label("Pulse Pressure", systemImage: "diamond.fill").font(.caption2).foregroundStyle(.orange)
                Label("Normal range", systemImage: "line.diagonal").font(.caption2).foregroundStyle(.green)
            }

            if !records.isEmpty {
                let avgMAP = records.map { mapValue($0) }.reduce(0, +) / Double(records.count)
                let avgPP = records.map { pulsePressure($0) }.reduce(0, +) / records.count
                HStack {
                    Text("Avg MAP: \(Int(avgMAP)) mmHg").font(.caption.monospacedDigit()).foregroundStyle(.purple)
                    Spacer()
                    Text("Avg Pulse Pressure: \(avgPP) mmHg").font(.caption.monospacedDigit()).foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
