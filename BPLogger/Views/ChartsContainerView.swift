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
    @State private var filterContext: ActivityContext?
    @State private var showExport = false

    private var readings: [BPReading] {
        var result = allReadings

        if let days = timeRange.days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
            result = result.filter { $0.timestamp >= cutoff }
        }

        if let context = filterContext {
            result = result.filter { $0.activityContext == context }
        }

        return result
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

                    if let context = filterContext {
                        HStack {
                            Label(context.rawValue, systemImage: context.icon)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear Filter") {
                                filterContext = nil
                            }
                            .font(.subheadline)
                        }
                        .padding(.horizontal)
                    }

                    if readings.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.xyaxis.line",
                            description: Text(filterContext != nil
                                ? "No readings for \"\(filterContext!.rawValue)\" in this time range"
                                : "Add readings to see charts")
                        )
                        .padding(.top, 60)
                    } else {
                        BPTrendChart(readings: readings)
                        PulseChart(readings: readings)
                        BPSummaryCard(readings: readings)
                        WeeklyAveragesChart(readings: readings)
                        MorningVsEveningChart(readings: readings)
                        MAPTrendChart(readings: readings)
                        HealthDataChartsSection(timeRange: timeRange)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Charts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            filterContext = nil
                        } label: {
                            Label("All Readings", systemImage: "chart.xyaxis.line")
                        }

                        Divider()

                        ForEach(ActivityContext.allCases) { context in
                            Button {
                                filterContext = context
                            } label: {
                                Label(context.rawValue, systemImage: context.icon)
                            }
                        }
                    } label: {
                        Image(systemName: filterContext != nil
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }

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
                ExportView()
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

// MARK: - Clinical Summary Card
struct BPSummaryCard: View {
    let readings: [BPReading]

    private var avgSystolic: Int {
        guard !readings.isEmpty else { return 0 }
        return readings.map(\.systolic).reduce(0, +) / readings.count
    }
    private var avgDiastolic: Int {
        guard !readings.isEmpty else { return 0 }
        return readings.map(\.diastolic).reduce(0, +) / readings.count
    }
    private var avgPulse: Int {
        guard !readings.isEmpty else { return 0 }
        return readings.map(\.pulse).reduce(0, +) / readings.count
    }
    private var avgCategory: BPCategory {
        BPReading.classify(systolic: avgSystolic, diastolic: avgDiastolic)
    }
    private var minSystolic: Int { readings.map(\.systolic).min() ?? 0 }
    private var maxSystolic: Int { readings.map(\.systolic).max() ?? 0 }
    private var minDiastolic: Int { readings.map(\.diastolic).min() ?? 0 }
    private var maxDiastolic: Int { readings.map(\.diastolic).max() ?? 0 }

    private var percentNormal: Int {
        guard !readings.isEmpty else { return 0 }
        let normal = readings.filter { $0.category == .normal }.count
        return Int(Double(normal) / Double(readings.count) * 100)
    }

    private var percentElevatedOrHigher: Int {
        guard !readings.isEmpty else { return 0 }
        let elevated = readings.filter { $0.category != .normal }.count
        return Int(Double(elevated) / Double(readings.count) * 100)
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
                Text("\(readings.count) readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                // Average BP
                VStack(spacing: 4) {
                    Text("Average BP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(avgSystolic)/\(avgDiastolic)")
                        .font(.title2.bold().monospacedDigit())
                    Text(avgCategory.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(categoryColor(avgCategory))
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                // Average Pulse
                VStack(spacing: 4) {
                    Text("Avg Pulse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .font(.caption)
                        Text("\(avgPulse)")
                            .font(.title2.bold().monospacedDigit())
                    }
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 50)

                // % in range
                VStack(spacing: 4) {
                    Text("In Range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(percentNormal)%")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(percentNormal >= 50 ? .green : .orange)
                    Text("normal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Range rows
            HStack {
                Text("Systolic range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(minSystolic) – \(maxSystolic) mmHg")
                    .font(.caption.monospacedDigit())
            }
            HStack {
                Text("Diastolic range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(minDiastolic) – \(maxDiastolic) mmHg")
                    .font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Weekly Averages Chart
struct WeeklyAveragesChart: View {
    let readings: [BPReading]

    private struct WeekData: Identifiable {
        let id = UUID()
        let weekStart: Date
        let avgSystolic: Double
        let avgDiastolic: Double
        let count: Int

        var label: String {
            weekStart.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private var weeklyData: [WeekData] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: readings) { reading in
            calendar.dateInterval(of: .weekOfYear, for: reading.timestamp)?.start ?? reading.timestamp
        }
        return grouped.map { weekStart, weekReadings in
            WeekData(
                weekStart: weekStart,
                avgSystolic: Double(weekReadings.map(\.systolic).reduce(0, +)) / Double(weekReadings.count),
                avgDiastolic: Double(weekReadings.map(\.diastolic).reduce(0, +)) / Double(weekReadings.count),
                count: weekReadings.count
            )
        }
        .sorted { $0.weekStart < $1.weekStart }
    }

    var body: some View {
        if weeklyData.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly Averages")
                    .font(.headline)
                Text("Track progress over weeks")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(weeklyData) { week in
                        BarMark(
                            x: .value("Week", week.label),
                            yStart: .value("Diastolic", week.avgDiastolic),
                            yEnd: .value("Systolic", week.avgSystolic)
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.blue.opacity(0.7), .red.opacity(0.7)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .annotation(position: .top, spacing: 2) {
                            Text("\(Int(week.avgSystolic))")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.red)
                        }
                        .annotation(position: .bottom, spacing: 2) {
                            Text("\(Int(week.avgDiastolic))")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                    }

                    RuleMark(y: .value("Target Sys", 120))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))

                    RuleMark(y: .value("Target Dia", 80))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.3))
                }
                .frame(height: 220)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }

                HStack(spacing: 16) {
                    Label("Systolic avg", systemImage: "square.fill")
                        .font(.caption2).foregroundStyle(.red)
                    Label("Diastolic avg", systemImage: "square.fill")
                        .font(.caption2).foregroundStyle(.blue)
                    Label("Target", systemImage: "line.diagonal")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
}

// MARK: - Morning vs Evening
struct MorningVsEveningChart: View {
    let readings: [BPReading]

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
        let morning = readings.filter {
            let h = calendar.component(.hour, from: $0.timestamp)
            return h >= 5 && h < 12
        }
        let afternoon = readings.filter {
            let h = calendar.component(.hour, from: $0.timestamp)
            return h >= 12 && h < 17
        }
        let evening = readings.filter {
            let h = calendar.component(.hour, from: $0.timestamp)
            return h >= 17 || h < 5
        }

        var result: [PeriodStats] = []
        for (name, icon, group) in [
            ("Morning\n5am–12pm", "sunrise", morning),
            ("Afternoon\n12pm–5pm", "sun.max", afternoon),
            ("Evening\n5pm–5am", "moon.stars", evening)
        ] {
            if !group.isEmpty {
                result.append(PeriodStats(
                    name: name,
                    icon: icon,
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
                Text("Time of Day Comparison")
                    .font(.headline)
                Text("Average BP by time period")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(periodData) { period in
                        VStack(spacing: 8) {
                            Image(systemName: period.icon)
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Text("\(Int(period.avgSystolic))/\(Int(period.avgDiastolic))")
                                .font(.headline.monospacedDigit())

                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.pink)
                                Text("\(Int(period.avgPulse))")
                                    .font(.caption.monospacedDigit())
                            }

                            Text(period.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text("\(period.count) readings")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
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

// MARK: - MAP (Mean Arterial Pressure) Trend
struct MAPTrendChart: View {
    let readings: [BPReading]

    private var sortedReadings: [BPReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    /// MAP = Diastolic + 1/3 * (Systolic - Diastolic)
    private func mapValue(_ r: BPReading) -> Double {
        Double(r.diastolic) + Double(r.systolic - r.diastolic) / 3.0
    }

    /// Pulse Pressure = Systolic - Diastolic
    private func pulsePressure(_ r: BPReading) -> Int {
        r.systolic - r.diastolic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mean Arterial Pressure")
                .font(.headline)
            Text("MAP = diastolic + \u{2153}(systolic \u{2212} diastolic). Normal: 70\u{2013}100 mmHg")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(sortedReadings) { reading in
                    LineMark(
                        x: .value("Date", reading.timestamp),
                        y: .value("MAP", mapValue(reading))
                    )
                    .foregroundStyle(.purple)
                    .symbol(.circle)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", reading.timestamp),
                        y: .value("PP", pulsePressure(reading)),
                        series: .value("Type", "Pulse Pressure")
                    )
                    .foregroundStyle(.orange)
                    .symbol(.diamond)
                    .interpolationMethod(.catmullRom)
                }

                // Normal MAP range
                RuleMark(y: .value("MAP High", 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.4))
                RuleMark(y: .value("MAP Low", 70))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.4))
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }

            HStack(spacing: 16) {
                Label("MAP", systemImage: "circle.fill")
                    .font(.caption2).foregroundStyle(.purple)
                Label("Pulse Pressure", systemImage: "diamond.fill")
                    .font(.caption2).foregroundStyle(.orange)
                Label("Normal range", systemImage: "line.diagonal")
                    .font(.caption2).foregroundStyle(.green)
            }

            if !readings.isEmpty {
                let avgMAP = sortedReadings.map { mapValue($0) }.reduce(0, +) / Double(sortedReadings.count)
                let avgPP = sortedReadings.map { pulsePressure($0) }.reduce(0, +) / sortedReadings.count
                HStack {
                    Text("Avg MAP: \(Int(avgMAP)) mmHg")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.purple)
                    Spacer()
                    Text("Avg Pulse Pressure: \(avgPP) mmHg")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Health Data Charts (fetched on-demand from HealthKit)
struct HealthDataChartsSection: View {
    let timeRange: ChartTimeRange
    @StateObject private var hkManager = HealthKitManager()
    @State private var healthContext: HealthContext?
    @State private var isLoading = false
    @State private var hasFetched = false

    private var since: Date {
        guard let days = timeRange.days else {
            return Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: .now)!
    }

    var body: some View {
        Group {
            if let ctx = healthContext, ctx.hasAnyData {
                if !ctx.restingHeartRates.isEmpty {
                    HealthDailyChart(
                        title: "Resting Heart Rate",
                        subtitle: "From Apple Watch. Normal: 60–100 bpm",
                        values: ctx.restingHeartRates,
                        unit: "bpm",
                        color: .red,
                        refLine: nil
                    )
                }

                if !ctx.hrvValues.isEmpty {
                    HealthDailyChart(
                        title: "Heart Rate Variability",
                        subtitle: "SDNN from Apple Watch. Higher is better",
                        values: ctx.hrvValues,
                        unit: "ms",
                        color: .purple,
                        refLine: (50, "Low threshold")
                    )
                }

                if !ctx.stepCounts.isEmpty {
                    HealthDailyChart(
                        title: "Daily Steps",
                        subtitle: "Recommended: 7,000+ steps/day",
                        values: ctx.stepCounts,
                        unit: "steps",
                        color: .green,
                        refLine: (7000, "Target")
                    )
                }

                if !ctx.sleepEntries.isEmpty {
                    HealthDailyChart(
                        title: "Sleep Duration",
                        subtitle: "Recommended: 7+ hours/night",
                        values: ctx.sleepEntries.map {
                            HealthContext.DailyValue(date: $0.date, value: $0.hours)
                        },
                        unit: "hours",
                        color: .indigo,
                        refLine: (7, "Target")
                    )
                }

                if !ctx.vo2MaxValues.isEmpty {
                    HealthDailyChart(
                        title: "VO2 Max (Cardio Fitness)",
                        subtitle: "From Apple Watch. Higher = better fitness",
                        values: ctx.vo2MaxValues,
                        unit: "mL/kg/min",
                        color: .orange,
                        refLine: nil
                    )
                }

                if !ctx.oxygenSaturation.isEmpty {
                    HealthDailyChart(
                        title: "Blood Oxygen (SpO2)",
                        subtitle: "From Apple Watch. Normal: 95–100%",
                        values: ctx.oxygenSaturation,
                        unit: "%",
                        color: .cyan,
                        refLine: (95, "Normal")
                    )
                }

                if !ctx.respiratoryRates.isEmpty {
                    HealthDailyChart(
                        title: "Respiratory Rate",
                        subtitle: "During sleep. Normal: 12–20 breaths/min",
                        values: ctx.respiratoryRates,
                        unit: "br/min",
                        color: .teal,
                        refLine: nil
                    )
                }

                if !ctx.exerciseMinutes.isEmpty {
                    HealthDailyChart(
                        title: "Exercise Minutes",
                        subtitle: "Target: 150 min/week (≈21 min/day)",
                        values: ctx.exerciseMinutes,
                        unit: "min",
                        color: .mint,
                        refLine: (21, "Daily avg target")
                    )
                }

                if !ctx.bodyMassValues.isEmpty {
                    HealthDailyChart(
                        title: "Body Weight",
                        subtitle: "Weight trend over time",
                        values: ctx.bodyMassValues,
                        unit: "kg",
                        color: .brown,
                        refLine: nil
                    )
                }
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Apple Health data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .onAppear {
            if !hasFetched { fetchHealthData() }
        }
        .onChange(of: timeRange) {
            fetchHealthData()
        }
    }

    private func fetchHealthData() {
        isLoading = true
        Task {
            await hkManager.requestExpandedAuthorization()
            let ctx = await hkManager.fetchHealthContext(from: since, to: .now)
            await MainActor.run {
                healthContext = ctx
                isLoading = false
                hasFetched = true
            }
        }
    }
}

// MARK: - Generic Health Daily Chart Card
struct HealthDailyChart: View {
    let title: String
    let subtitle: String
    let values: [HealthContext.DailyValue]
    let unit: String
    let color: Color
    let refLine: (Double, String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(values) { v in
                    LineMark(
                        x: .value("Date", v.date),
                        y: .value(unit, v.value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", v.date),
                        y: .value(unit, v.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(values.count > 30 ? 10 : 20)
                }

                if let ref = refLine {
                    RuleMark(y: .value("Ref", ref.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .foregroundStyle(.green.opacity(0.5))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(ref.1).font(.caption2).foregroundStyle(.green)
                        }
                }
            }
            .frame(height: 160)
            .chartYAxis {
                AxisMarks(position: .leading)
            }

            if !values.isEmpty {
                let avg = values.map(\.value).reduce(0, +) / Double(values.count)
                let minV = values.map(\.value).min() ?? 0
                let maxV = values.map(\.value).max() ?? 0
                HStack {
                    Text("Avg: \(formatValue(avg)) \(unit)")
                    Spacer()
                    Text("Range: \(formatValue(minV)) – \(formatValue(maxV))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func formatValue(_ v: Double) -> String {
        v >= 100 ? "\(Int(v))" : String(format: "%.1f", v)
    }
}
