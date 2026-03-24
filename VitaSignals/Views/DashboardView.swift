import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @ObservedObject var syncManager: HealthSyncManager
    @Query private var profiles: [UserProfile]
    @Query(sort: \DashboardCard.sortIndex) private var dashboardCards: [DashboardCard]
    @State private var activeSheet: DashboardSheet?
    @State private var addMetricType: String = MetricType.bloodPressure
    @State private var cachedHighlights: [Highlight] = []
    @State private var cachedDashboardCards: [ResolvedDashboardCard] = []
    @State private var showManageDashboard = false
    @State private var dashboardNavMetric: String?
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


    // MARK: - Recompute Cached Data

    private func recompute() {
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

        // Sync dashboard cards with available metrics, then resolve
        DashboardCardResolver.syncCards(
            existingCards: dashboardCards,
            availableMetrics: dataStore.availableMetricTypes,
            context: modelContext
        )
        cachedDashboardCards = DashboardCardResolver.resolve(
            cards: dashboardCards,
            dataStore: dataStore
        )
    }

    private func computeStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Records are sorted newest-first; walk until we find a gap
        var daysWithData = Set<Date>()
        for record in dataStore.allRecords {
            let day = calendar.startOfDay(for: record.timestamp)
            daysWithData.insert(day)
            // No need to look beyond 365 days for a streak starting from today
            if today.timeIntervalSince(day) > 366 * 86400 { break }
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

                    if syncManager.permissionDenied && dataStore.recordCount == 0 {
                        permissionWarning
                    }

                    if !cachedHighlights.isEmpty {
                        highlightsCard
                    }

                    if dataStore.recordCount > 0 {
                        dashboardChartsHeader

                        ForEach(cachedDashboardCards) { card in
                            dashboardChartView(for: card)
                        }
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
            .navigationDestination(item: $dashboardNavMetric) { metricType in
                MetricDetailView(metricType: metricType)
            }
            .sheet(isPresented: $showManageDashboard) {
                ManageDashboardSheet()
                    .onDisappear { recompute() }
            }
            .onChange(of: dataStore.recordCount) { _, _ in
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
            } else if syncManager.permissionDenied {
                Button {
                    Task {
                        await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.circle")
                            .foregroundStyle(.pink)
                        Text("Connect Apple Health for more insights")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
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
            Text("Trends compare your last 7 days to the previous 7 days.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Dashboard Charts

    private var dashboardChartsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("My Charts")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text("Tap to view details")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                showManageDashboard = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                    Text("Manage")
                        .font(.caption)
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func dashboardChartView(for card: ResolvedDashboardCard) -> some View {
        if card.metricType == MetricType.bloodPressure {
            ComparisonBPChart(
                records: card.records,
                xDomain: card.xDomain,
                onTap: { dashboardNavMetric = card.metricType }
            )
        } else if let def = card.definition {
            ComparisonMetricChart(
                records: card.records,
                definition: def,
                xDomain: card.xDomain,
                onTap: { dashboardNavMetric = card.metricType }
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60)).foregroundStyle(.secondary)
            Text("No Health Data Yet").font(.title2.bold())
            Text("Log data manually or connect Apple Health to get started.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    activeSheet = .metricPicker
                } label: {
                    Label("Add Record", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                }

                Button {
                    Task {
                        await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
                    }
                } label: {
                    Label("Connect Health", systemImage: "heart.circle")
                        .font(.subheadline.bold())
                }
            }
            .padding(.top, 8)

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
    @State private var showClassification = false

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
        Button {
            showClassification = true
        } label: {
            Text(category.rawValue)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blood pressure category: \(category.rawValue). Tap for classification details.")
        .popover(isPresented: $showClassification) {
            VStack(alignment: .leading, spacing: 10) {
                Text("AHA BP Classification")
                    .font(.subheadline.bold())
                ClassificationRow(label: "Normal", systolic: "< 120", diastolic: "< 80", color: .green)
                ClassificationRow(label: "Elevated", systolic: "120-129", diastolic: "< 80", color: .yellow)
                ClassificationRow(label: "High Stage 1", systolic: "130-139", diastolic: "80-89", color: .orange)
                ClassificationRow(label: "High Stage 2", systolic: "\u{2265} 140", diastolic: "\u{2265} 90", color: .red)
                ClassificationRow(label: "Crisis", systolic: "> 180", diastolic: "> 120", color: .purple)
            }
            .padding()
            .frame(idealWidth: 300)
            .presentationCompactAdaptation(.popover)
        }
    }
}

private struct ClassificationRow: View {
    let label: String
    let systolic: String
    let diastolic: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.bold())
                .frame(width: 90, alignment: .leading)
            Text(systolic)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("and")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(diastolic)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
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
