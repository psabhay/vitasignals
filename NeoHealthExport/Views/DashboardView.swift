import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @ObservedObject var syncManager: HealthSyncManager
    @Query private var profiles: [UserProfile]
    @State private var activeSheet: DashboardSheet?
    @State private var addMetricType: String = MetricType.bloodPressure
    @State private var cachedSummaries: [MetricSummary] = []
    @State private var cachedHighlights: [Highlight] = []
    #if DEBUG
    @State private var isGeneratingData = false
    #endif

    private enum DashboardSheet: Identifiable {
        case metricPicker
        case addForm(String)
        var id: String {
            switch self {
            case .metricPicker: return "picker"
            case .addForm(let type): return "add-\(type)"
            }
        }
    }

    // MARK: - Data Models

    struct MetricSummary: Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let latestValue: String
        let unit: String
        let trendPercent: Double?
        let sparkline: [(Date, Double)]
        let recordCount7d: Int
    }

    struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let color: Color
    }

    // MARK: - Computed Properties

    private var userName: String? {
        guard let p = profiles.first, !p.name.isEmpty else { return nil }
        let first = p.name.split(separator: " ").first.map(String.init)
        return first
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "Good morning" }
        else if hour < 17 { return "Good afternoon" }
        else { return "Good evening" }
    }

    private var allMetricTypes: [String] {
        let types = dataStore.availableMetricTypes
        var ordered: [String] = []
        var seen = Set<String>()
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category) where types.contains(def.type) {
                if seen.insert(def.type).inserted {
                    ordered.append(def.type)
                }
            }
        }
        for type in types.sorted() where !seen.contains(type) {
            ordered.append(type)
        }
        return ordered
    }

    private var bpRecords: [HealthRecord] {
        dataStore.records(for: MetricType.bloodPressure)
    }

    private var latestBP: HealthRecord? {
        bpRecords.first
    }

    private var last7DaysBP: [HealthRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return bpRecords.filter { $0.timestamp >= cutoff }
    }

    private var recentRecords: [HealthRecord] {
        Array(dataStore.allRecords.prefix(15))
    }

    // MARK: - Recompute Cached Data

    private func recompute() {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now

        cachedSummaries = allMetricTypes.compactMap { type in
            let def = MetricRegistry.definition(for: type)
            let records = dataStore.records(for: type)
            guard !records.isEmpty else { return nil }

            let latest = records.first
            let recent7d = records.filter { $0.timestamp >= sevenDaysAgo }
            let prev7d = records.filter { $0.timestamp >= fourteenDaysAgo && $0.timestamp < sevenDaysAgo }

            // Trend: compare 7d avg to previous 7d avg
            let trend: Double? = {
                guard recent7d.count >= 2, prev7d.count >= 2 else { return nil }
                let recentAvg: Double
                let prevAvg: Double
                if type == MetricType.bloodPressure {
                    recentAvg = Double(recent7d.map(\.systolic).reduce(0, +)) / Double(recent7d.count)
                    prevAvg = Double(prev7d.map(\.systolic).reduce(0, +)) / Double(prev7d.count)
                } else {
                    recentAvg = recent7d.map(\.primaryValue).reduce(0, +) / Double(recent7d.count)
                    prevAvg = prev7d.map(\.primaryValue).reduce(0, +) / Double(prev7d.count)
                }
                guard prevAvg != 0 else { return nil }
                return ((recentAvg - prevAvg) / abs(prevAvg)) * 100
            }()

            let sparkline = records.lazy.filter { $0.timestamp >= sevenDaysAgo }
                .sorted { $0.timestamp < $1.timestamp }
                .prefix(30)
                .map { ($0.timestamp, type == MetricType.bloodPressure ? Double($0.systolic) : $0.primaryValue) }

            let latestFormatted: String
            if type == MetricType.bloodPressure {
                latestFormatted = latest.map { "\($0.systolic)/\($0.diastolic)" } ?? "–"
            } else {
                latestFormatted = latest?.formattedPrimaryValue ?? "–"
            }

            return MetricSummary(
                id: type,
                name: def?.name ?? type,
                icon: def?.icon ?? "chart.xyaxis.line",
                color: def?.color ?? .gray,
                latestValue: latestFormatted,
                unit: def?.unit ?? "",
                trendPercent: trend,
                sparkline: Array(sparkline),
                recordCount7d: recent7d.count
            )
        }

        // Compute highlights
        var highlights: [Highlight] = []

        // Total readings today
        let todayCount = dataStore.allRecords.filter { Calendar.current.isDateInToday($0.timestamp) }.count
        if todayCount > 0 {
            highlights.append(Highlight(
                icon: "checkmark.circle.fill",
                text: "\(todayCount) reading\(todayCount == 1 ? "" : "s") recorded today",
                color: .green
            ))
        }

        // Top trends (biggest movers)
        let trending = cachedSummaries
            .compactMap { s -> (MetricSummary, Double)? in
                guard let t = s.trendPercent, abs(t) >= 3 else { return nil }
                return (s, t)
            }
            .sorted { abs($0.1) > abs($1.1) }
            .prefix(2)

        for (summary, pct) in trending {
            let direction = pct > 0 ? "up" : "down"
            let arrow = pct > 0 ? "arrow.up.right" : "arrow.down.right"
            // For BP, down is good. For steps/exercise, up is good.
            let isGood: Bool
            if summary.id == MetricType.bloodPressure {
                isGood = pct < 0
            } else if summary.id == MetricType.stepCount || summary.id == MetricType.exerciseMinutes || summary.id == MetricType.vo2Max {
                isGood = pct > 0
            } else {
                isGood = true // neutral
            }
            highlights.append(Highlight(
                icon: arrow,
                text: "\(summary.name) \(direction) \(Int(abs(pct)))% this week",
                color: isGood ? .green : .orange
            ))
        }

        // Streak — consecutive days with any reading
        let streak = computeStreak()
        if streak >= 3 {
            highlights.append(Highlight(
                icon: "flame.fill",
                text: "\(streak)-day logging streak",
                color: .orange
            ))
        }

        cachedHighlights = highlights
    }

    private func computeStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var daysWithData = Set<Date>()
        for record in dataStore.allRecords {
            daysWithData.insert(calendar.startOfDay(for: record.timestamp))
        }
        var streak = 0
        var day = today
        while daysWithData.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    greetingHeader

                    if syncManager.permissionDenied {
                        permissionWarning
                    }

                    if !cachedHighlights.isEmpty {
                        highlightsCard
                    }

                    if !cachedSummaries.isEmpty {
                        metricStrip
                    }

                    if last7DaysBP.count >= 2 {
                        bpTrendCard
                    }

                    if !recentRecords.isEmpty {
                        recentActivityCard
                    }

                    if dataStore.recordCount == 0 {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .withProfileButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .metricPicker
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Add Record")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .metricPicker:
                    AddRecordPickerSheet { selectedType in
                        addMetricType = selectedType
                        activeSheet = .addForm(selectedType)
                    }
                case .addForm(let type):
                    HealthRecordFormView(metricType: type)
                }
            }
            .navigationDestination(for: String.self) { metricType in
                MetricDetailView(metricType: metricType)
            }
            .onReceive(dataStore.$recordCount) { _ in
                recompute()
            }
            .onAppear {
                recompute()
            }
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = userName {
                Text("\(greeting), \(name)")
                    .font(.title2.bold())
            } else {
                Text(greeting)
                    .font(.title2.bold())
            }

            if syncManager.isSyncing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text(syncManager.syncProgress)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let lastSync = syncManager.lastSyncDate {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                    Text("Synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Permission Warning

    private var permissionWarning: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.title2).foregroundStyle(.orange)
            Text("Health Data Access Required")
                .font(.subheadline.bold())
            Text("Enable access in Settings to display metrics and generate reports.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.bold())
            .padding(.top, 4)

            #if DEBUG
            Divider().padding(.vertical, 4)
            debugGenerateButton
            #endif
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Highlights Card

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(cachedHighlights) { highlight in
                HStack(spacing: 10) {
                    Image(systemName: highlight.icon)
                        .font(.subheadline)
                        .foregroundStyle(highlight.color)
                        .frame(width: 24)
                    Text(highlight.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metric Summary Strip

    private var metricStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Overview")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cachedSummaries) { summary in
                        NavigationLink(value: summary.id) {
                            metricSummaryCard(summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func metricSummaryCard(_ summary: MetricSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: summary.icon)
                    .foregroundStyle(summary.color)
                    .font(.caption)
                Text(summary.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(summary.latestValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(summary.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let trend = summary.trendPercent {
                    trendBadge(percent: trend, metricType: summary.id)
                }
            }

            if summary.sparkline.count >= 2 {
                Chart {
                    ForEach(summary.sparkline, id: \.0) { point in
                        LineMark(
                            x: .value("Date", point.0),
                            y: .value("Value", point.1)
                        )
                        .foregroundStyle(summary.color.opacity(0.6))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.0),
                            y: .value("Value", point.1)
                        )
                        .foregroundStyle(summary.color.opacity(0.08))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 36)
            } else {
                Spacer().frame(height: 36)
            }
        }
        .frame(width: 155)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func trendBadge(percent: Double, metricType: String) -> some View {
        let isUp = percent > 0
        let arrow = isUp ? "arrow.up.right" : "arrow.down.right"
        let isGood: Bool
        if metricType == MetricType.bloodPressure {
            isGood = !isUp
        } else if metricType == MetricType.stepCount || metricType == MetricType.exerciseMinutes || metricType == MetricType.vo2Max {
            isGood = isUp
        } else {
            isGood = true
        }
        let color: Color = isGood ? .green : .orange

        return HStack(spacing: 2) {
            Image(systemName: arrow)
                .font(.system(size: 9, weight: .bold))
            Text("\(Int(abs(percent)))%")
                .font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(color)
    }

    // MARK: - BP Trend Card

    private var bpTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Blood Pressure Trend")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let latest = latestBP {
                    CategoryBadge(category: latest.bpCategory)
                }
            }

            // Latest reading hero
            if let latest = latestBP {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(latest.systolic)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("/").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                    Text("\(latest.diastolic)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("mmHg").font(.caption).foregroundStyle(.secondary).padding(.leading, 2)
                    Spacer()
                    if let pulse = latest.pulseOptional {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                                Text("\(pulse)").font(.title3.bold().monospacedDigit())
                            }
                            Text("bpm").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Mini chart
            Chart {
                ForEach(last7DaysBP.reversed()) { record in
                    LineMark(x: .value("Time", record.timestamp), y: .value("Sys", record.systolic))
                        .foregroundStyle(.red).interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", record.timestamp), y: .value("Dia", record.diastolic))
                        .foregroundStyle(.blue).interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("Ref", 120))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3])).foregroundStyle(.green.opacity(0.4))
                RuleMark(y: .value("Ref", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3])).foregroundStyle(.green.opacity(0.3))
            }
            .frame(height: 140)
            .chartYAxis { AxisMarks(position: .leading) }

            HStack(spacing: 16) {
                Label("Systolic", systemImage: "circle.fill").font(.caption2).foregroundStyle(.red)
                Label("Diastolic", systemImage: "circle.fill").font(.caption2).foregroundStyle(.blue)
            }

            // 7-day averages
            if !last7DaysBP.isEmpty {
                let avgSys = last7DaysBP.map(\.systolic).reduce(0, +) / last7DaysBP.count
                let avgDia = last7DaysBP.map(\.diastolic).reduce(0, +) / last7DaysBP.count
                HStack {
                    Text("7-day avg: \(avgSys)/\(avgDia) mmHg")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(last7DaysBP.count) readings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Activity

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(Array(recentRecords.prefix(8))) { record in
                recentActivityRow(record)
                if record.id != recentRecords.prefix(8).last?.id {
                    Divider()
                }
            }

            if recentRecords.count > 8 {
                Text("\(recentRecords.count - 8) more records")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func recentActivityRow(_ record: HealthRecord) -> some View {
        let def = MetricRegistry.definition(for: record.metricType)
        return HStack(spacing: 12) {
            Image(systemName: def?.icon ?? "chart.xyaxis.line")
                .foregroundStyle(def?.color ?? .gray)
                .font(.subheadline)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.formattedPrimaryValue)
                    .font(.subheadline.bold().monospacedDigit())
                Text(def?.name ?? record.metricType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if Calendar.current.isDateInToday(record.timestamp) {
                    Text(record.formattedTimeOnly)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(record.formattedDateOnly)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.formattedTimeOnly)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if record.metricType == MetricType.bloodPressure {
                CategoryBadge(category: record.bpCategory)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60)).foregroundStyle(.secondary)
            Text("No Health Data Yet").font(.title2.bold())
            Text("Tap + to log data or sync from Apple Health")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            #if DEBUG
            debugGenerateButton
                .padding(.top, 8)
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    #if DEBUG
    private var debugGenerateButton: some View {
        Button {
            isGeneratingData = true
            _ = SyntheticDataGenerator.generate(into: modelContext, days: 90)
            dataStore.refresh()
            recompute()
            isGeneratingData = false
            syncManager.permissionDenied = false
        } label: {
            Label(isGeneratingData ? "Generating..." : "Load Sample Data (Debug)", systemImage: "wand.and.stars")
                .font(.subheadline.bold())
                .foregroundStyle(.purple)
        }
        .disabled(isGeneratingData || dataStore.recordCount > 0)
    }
    #endif
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: BPCategory
    var badgeColor: Color {
        switch category {
        case .normal: return .green
        case .elevated: return .yellow
        case .highStage1: return .orange
        case .highStage2: return .red
        case .crisis: return .purple
        }
    }
    var body: some View {
        Text(category.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor)
            .accessibilityLabel("Blood pressure category: \(category.rawValue)")
    }
}

// MARK: - BP Reading Row

struct BPReadingRow: View {
    let record: HealthRecord
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.formattedPrimaryValue).font(.headline.monospacedDigit())
                    if record.isFromHealthKit {
                        Image(systemName: "heart.circle.fill").font(.caption).foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 8) {
                    Label(record.pulseOptional.map { "\($0)" } ?? "–", systemImage: "heart.fill").font(.caption).foregroundStyle(.pink)
                    if let ctx = record.bpActivityContext {
                        Label(ctx.rawValue, systemImage: ctx.icon).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(record.formattedTimeOnly).font(.caption).foregroundStyle(.secondary)
                CategoryBadge(category: record.bpCategory)
            }
        }
        .padding(.vertical, 4)
    }
}
