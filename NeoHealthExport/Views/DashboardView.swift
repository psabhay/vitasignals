import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @ObservedObject var syncManager: HealthSyncManager
    @State private var activeSheet: DashboardSheet?
    @State private var addMetricType: String = MetricType.bloodPressure
    @State private var cachedCardData: [CardData] = []
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

    private var bpRecords: [HealthRecord] {
        dataStore.records(for: MetricType.bloodPressure)
    }

    private var latestBP: HealthRecord? {
        bpRecords.first
    }

    private var todayBPReadings: [HealthRecord] {
        bpRecords.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var last7DaysBP: [HealthRecord] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return bpRecords.filter { $0.timestamp >= sevenDaysAgo }
    }

    private var averageSystolic: Int? {
        guard !last7DaysBP.isEmpty else { return nil }
        return last7DaysBP.map(\.systolic).reduce(0, +) / last7DaysBP.count
    }

    private var averageDiastolic: Int? {
        guard !last7DaysBP.isEmpty else { return nil }
        return last7DaysBP.map(\.diastolic).reduce(0, +) / last7DaysBP.count
    }

    private var averagePulse: Int? {
        guard !last7DaysBP.isEmpty else { return nil }
        return last7DaysBP.map(\.pulse).reduce(0, +) / last7DaysBP.count
    }

    private var nonBPMetricTypes: [String] {
        let types = dataStore.availableMetricTypes
        return MetricRegistry.all.map(\.type).filter { types.contains($0) && $0 != MetricType.bloodPressure }
    }

    struct CardData: Identifiable {
        let id: String
        let latestValue: String
        let unit: String
        let sparkline: [(Date, Double)]
    }

    private func recomputeCardData() {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        cachedCardData = nonBPMetricTypes.map { type in
            let records = dataStore.records(for: type)
            let def = MetricRegistry.definition(for: type)
            let latest = records.first
            let recent = records.lazy.filter { $0.timestamp >= sevenDaysAgo }
                .sorted { $0.timestamp < $1.timestamp }
                .prefix(30)
                .map { ($0.timestamp, $0.primaryValue) }
            return CardData(
                id: type,
                latestValue: latest?.formattedPrimaryValue ?? "–",
                unit: def?.unit ?? "",
                sparkline: Array(recent)
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if syncManager.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text(syncManager.syncProgress)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if syncManager.permissionDenied {
                        VStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .font(.title2).foregroundStyle(.orange)
                            Text("Health Data Access Required")
                                .font(.subheadline.bold())
                            Text("This app needs access to your Apple Health data to display metrics and generate reports. Please enable access in Settings.")
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

                    if let latest = latestBP {
                        latestBPCard(latest)
                    }

                    if !cachedCardData.isEmpty {
                        metricCardsGrid
                    }

                    if !last7DaysBP.isEmpty {
                        weekAverageCard
                        miniChartCard
                    }

                    todayBPSection

                    if dataStore.recordCount == 0 {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Health Dashboard")
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
                    AddHealthRecordView(metricType: type)
                }
            }
            .navigationDestination(for: String.self) { metricType in
                MetricDetailView(metricType: metricType)
            }
            .onReceive(dataStore.$recordCount) { _ in
                recomputeCardData()
            }
            .onAppear {
                recomputeCardData()
            }
        }
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
            recomputeCardData()
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

    // MARK: - Latest BP Card

    private func latestBPCard(_ record: HealthRecord) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Latest Blood Pressure").font(.subheadline.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(record.formattedDate).font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(record.systolic)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("/").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                Text("\(record.diastolic)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("mmHg").font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
            }

            HStack(spacing: 16) {
                Label("\(record.pulse) bpm", systemImage: "heart.fill")
                    .font(.subheadline).foregroundStyle(.pink)
                if let ctx = record.bpActivityContext {
                    Label(ctx.rawValue, systemImage: ctx.icon)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            CategoryBadge(category: record.bpCategory)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest blood pressure: \(record.systolic) over \(record.diastolic) mmHg, pulse \(record.pulse) bpm, \(record.bpCategory.rawValue)")
    }

    // MARK: - Metric Cards Grid

    private var metricCardsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Overview").font(.subheadline.bold()).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(cachedCardData) { card in
                    NavigationLink(value: card.id) {
                        MetricCardView(
                            metricType: card.id,
                            latestValue: card.latestValue,
                            unit: card.unit,
                            sparklineData: card.sparkline
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Week Average

    private var weekAverageCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("7-Day Average").font(.subheadline.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(last7DaysBP.count) readings").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                if let sys = averageSystolic, let dia = averageDiastolic {
                    VStack {
                        Text("\(sys)/\(dia)").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("mmHg").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let pulse = averagePulse {
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill").foregroundStyle(.pink)
                            Text("\(pulse)").font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        Text("bpm").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Mini Chart

    private var miniChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days").font(.subheadline.bold()).foregroundStyle(.secondary)

            Chart {
                ForEach(last7DaysBP.reversed()) { record in
                    LineMark(x: .value("Time", record.timestamp), y: .value("Systolic", record.systolic))
                        .foregroundStyle(.red).symbol(.circle)
                    LineMark(x: .value("Time", record.timestamp), y: .value("Diastolic", record.diastolic))
                        .foregroundStyle(.blue).symbol(.diamond)
                }
                RuleMark(y: .value("Normal Systolic", 120))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3])).foregroundStyle(.green.opacity(0.5))
                RuleMark(y: .value("Normal Diastolic", 80))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3])).foregroundStyle(.green.opacity(0.3))
            }
            .frame(height: 180)
            .chartYAxis { AxisMarks(position: .leading) }

            HStack(spacing: 16) {
                Label("Systolic", systemImage: "circle.fill").font(.caption2).foregroundStyle(.red)
                Label("Diastolic", systemImage: "diamond.fill").font(.caption2).foregroundStyle(.blue)
                Label("Normal", systemImage: "line.diagonal").font(.caption2).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last 7 days blood pressure trend chart")
    }

    // MARK: - Today Section

    private var todayBPSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").font(.subheadline.bold()).foregroundStyle(.secondary)
            if todayBPReadings.isEmpty {
                Text("No readings today").font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity).padding()
            } else {
                ForEach(todayBPReadings) { record in
                    BPReadingRow(record: record)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
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
                    Label("\(record.pulse)", systemImage: "heart.fill").font(.caption).foregroundStyle(.pink)
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
