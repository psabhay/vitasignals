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
    @Query(sort: \BPReading.timestamp, order: .reverse) private var allReadings: [BPReading]
    @State private var timeRange: ChartTimeRange = .week
    @State private var showExport = false

    private var readings: [BPReading] {
        guard let days = timeRange.days else { return allReadings }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return allReadings.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(ChartTimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if readings.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text("Add readings to see charts")
                        )
                        .padding(.top, 60)
                    } else {
                        BPTrendChart(readings: readings)
                        PulseChart(readings: readings)
                        CategoryDistributionChart(readings: readings)
                        ContextComparisonChart(readings: readings)
                        TimeOfDayChart(readings: readings)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Charts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(readings.isEmpty)
                }
            }
            .sheet(isPresented: $showExport) {
                ExportView(readings: readings, timeRange: timeRange)
            }
        }
    }
}

// MARK: - BP Trend Line Chart
struct BPTrendChart: View {
    let readings: [BPReading]

    private var sortedReadings: [BPReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blood Pressure Trend")
                .font(.headline)

            Chart {
                ForEach(sortedReadings) { reading in
                    LineMark(
                        x: .value("Date", reading.timestamp),
                        y: .value("mmHg", reading.systolic),
                        series: .value("Type", "Systolic")
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", reading.timestamp),
                        y: .value("mmHg", reading.diastolic),
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
            .chartYAxis {
                AxisMarks(position: .leading)
            }
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
    let readings: [BPReading]

    private var sortedReadings: [BPReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pulse Trend")
                .font(.headline)

            Chart {
                ForEach(sortedReadings) { reading in
                    AreaMark(
                        x: .value("Date", reading.timestamp),
                        y: .value("BPM", reading.pulse)
                    )
                    .foregroundStyle(.pink.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", reading.timestamp),
                        y: .value("BPM", reading.pulse)
                    )
                    .foregroundStyle(.pink)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)
                }
            }
            .frame(height: 160)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Category Distribution
struct CategoryDistributionChart: View {
    let readings: [BPReading]

    private var distribution: [(BPCategory, Int)] {
        let grouped = Dictionary(grouping: readings) { $0.category }
        return [.normal, .elevated, .highStage1, .highStage2, .crisis]
            .compactMap { cat in
                guard let count = grouped[cat]?.count, count > 0 else { return nil }
                return (cat, count)
            }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Distribution")
                .font(.headline)

            Chart {
                ForEach(distribution, id: \.0) { category, count in
                    SectorMark(
                        angle: .value("Count", count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(categoryColor(category))
                    .annotation(position: .overlay) {
                        Text("\(count)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 200)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(distribution, id: \.0) { category, count in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(categoryColor(category))
                            .frame(width: 8, height: 8)
                        Text("\(category.rawValue) (\(count))")
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Context Comparison
struct ContextComparisonChart: View {
    let readings: [BPReading]

    private var contextAverages: [(ActivityContext, Double, Double)] {
        let grouped = Dictionary(grouping: readings) { $0.activityContext }
        return grouped.compactMap { context, contextReadings in
            guard contextReadings.count >= 2 else { return nil }
            let avgSys = Double(contextReadings.map(\.systolic).reduce(0, +)) / Double(contextReadings.count)
            let avgDia = Double(contextReadings.map(\.diastolic).reduce(0, +)) / Double(contextReadings.count)
            return (context, avgSys, avgDia)
        }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        if !contextAverages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Average by Context")
                    .font(.headline)
                Text("Contexts with 2+ readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(contextAverages, id: \.0) { context, avgSys, avgDia in
                        BarMark(
                            x: .value("Systolic", avgSys),
                            y: .value("Context", context.rawValue)
                        )
                        .foregroundStyle(.red.opacity(0.7))

                        BarMark(
                            x: .value("Diastolic", avgDia),
                            y: .value("Context", context.rawValue)
                        )
                        .foregroundStyle(.blue.opacity(0.7))
                    }

                    RuleMark(x: .value("Normal Sys", 120))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                }
                .frame(height: CGFloat(contextAverages.count) * 50 + 20)
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }

                HStack(spacing: 16) {
                    Label("Avg Systolic", systemImage: "square.fill")
                        .font(.caption2).foregroundStyle(.red)
                    Label("Avg Diastolic", systemImage: "square.fill")
                        .font(.caption2).foregroundStyle(.blue)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - Time of Day Chart
struct TimeOfDayChart: View {
    let readings: [BPReading]

    private struct HourAverage: Identifiable {
        let id = UUID()
        let hour: Int
        let avgSystolic: Double
        let avgDiastolic: Double
        let count: Int

        var hourLabel: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            var components = DateComponents()
            components.hour = hour
            let date = Calendar.current.date(from: components)!
            return formatter.string(from: date)
        }
    }

    private var hourlyAverages: [HourAverage] {
        let grouped = Dictionary(grouping: readings) { reading in
            Calendar.current.component(.hour, from: reading.timestamp)
        }
        return grouped.map { hour, hourReadings in
            HourAverage(
                hour: hour,
                avgSystolic: Double(hourReadings.map(\.systolic).reduce(0, +)) / Double(hourReadings.count),
                avgDiastolic: Double(hourReadings.map(\.diastolic).reduce(0, +)) / Double(hourReadings.count),
                count: hourReadings.count
            )
        }.sorted { $0.hour < $1.hour }
    }

    var body: some View {
        if hourlyAverages.count >= 3 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Time of Day Pattern")
                    .font(.headline)

                Chart {
                    ForEach(hourlyAverages) { avg in
                        LineMark(
                            x: .value("Hour", avg.hourLabel),
                            y: .value("Systolic", avg.avgSystolic),
                            series: .value("Type", "Systolic")
                        )
                        .foregroundStyle(.red)
                        .symbol(.circle)

                        LineMark(
                            x: .value("Hour", avg.hourLabel),
                            y: .value("Diastolic", avg.avgDiastolic),
                            series: .value("Type", "Diastolic")
                        )
                        .foregroundStyle(.blue)
                        .symbol(.diamond)
                    }
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}
