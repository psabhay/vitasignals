import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @ObservedObject var syncManager: HealthSyncManager
    @Query private var profiles: [UserProfile]
    @Query(sort: \DashboardCard.sortIndex) private var dashboardCards: [DashboardCard]
    @Query(sort: \CustomMetric.createdAt) private var customMetrics: [CustomMetric]
    @Query private var goals: [MetricGoal]
    @StateObject private var engine = DashboardEngine()
    @State private var activeSheet: DashboardSheet?
    @State private var addMetricType: String = MetricType.bloodPressure
    @State private var dashboardNavMetric: String?
    #if DEBUG
    @State private var isGeneratingData = false
    #endif

    private enum DashboardSheet: Identifiable {
        case metricPicker
        case addForm(String)
        case setGoal
        var id: String {
            switch self {
            case .metricPicker: return "picker"
            case .addForm(let type): return "add-\(type)"
            case .setGoal: return "setGoal"
            }
        }
    }

    private var userName: String? {
        guard let p = profiles.first, !p.name.isEmpty else { return nil }
        return p.name.split(separator: " ").first.map(String.init)
    }

    private func recompute() {
        engine.recompute(
            dataStore: dataStore,
            userName: userName,
            goals: goals,
            customMetrics: customMetrics,
            cards: dashboardCards,
            chartRangeDays: 7,
            modelContext: modelContext
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Smart Summary (replaces greeting)
                    SmartSummaryView(data: engine.smartSummary, syncManager: syncManager)

                    // 2. Permission warning
                    if syncManager.permissionDenied && dataStore.recordCount == 0 {
                        permissionWarning
                    }

                    // 3. Nudge cards
                    ForEach(engine.nudgeItems) { nudge in
                        NudgeCardView(item: nudge) {
                            activeSheet = .addForm(nudge.id)
                        } onDismiss: {
                            let key = "nudge_dismissed_\(nudge.id)"
                            UserDefaults.standard.set(Date.now.formatted(.dateTime.year().month().day()), forKey: key)
                            recompute()
                        }
                    }

                    // 4. Hero Card
                    if let hero = engine.heroCard {
                        HeroCardView(data: hero) {
                            dashboardNavMetric = hero.metricType
                        }
                    }

                    // 5. Highlights
                    if !engine.highlights.isEmpty {
                        highlightsCard
                    }

                    // 6. Quick Log
                    if !engine.quickLogMetrics.isEmpty {
                        QuickLogRowView(metrics: engine.quickLogMetrics) { type in
                            activeSheet = .addForm(type)
                        }
                    }

                    // 7. Goal Progress
                    if !engine.goalProgress.isEmpty {
                        goalSection
                    }

                    // 8. Recent Activity
                    if !dataStore.allRecords.isEmpty {
                        recentActivitySection
                    }

                    // 9. Weekly Recap
                    if let recap = engine.weeklyRecap {
                        WeeklyRecapCardView(data: recap)
                    }

                    // 10. Add Goal entry point
                    if dataStore.recordCount > 0 && goals.filter(\.isActive).count < 3 {
                        Button {
                            activeSheet = .setGoal
                        } label: {
                            Label("Set a Health Goal", systemImage: "target")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    // 11. Empty state
                    if dataStore.recordCount == 0 {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("Home")
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
                case .setGoal:
                    SetGoalSheet()
                }
            }
            .navigationDestination(item: $dashboardNavMetric) { metricType in
                MetricDetailView(metricType: metricType)
            }
            .onChange(of: dataStore.recordCount) { _, _ in recompute() }
            .onChange(of: goals.count) { _, _ in recompute() }
            .onAppear { recompute() }
        }
    }

    // MARK: - Highlights Card

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(engine.highlights) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.subheadline)
                        .foregroundStyle(item.color)
                        .frame(width: 24)
                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Goal Section

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goals")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            ForEach(engine.goalProgress) { goal in
                GoalProgressCardView(data: goal)
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Activity")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            let recent = Array(dataStore.allRecords.prefix(5))
            ForEach(recent) { record in
                let def = MetricRegistry.definition(for: record.metricType)
                HStack(spacing: 12) {
                    Image(systemName: def?.icon ?? "chart.xyaxis.line")
                        .font(.subheadline)
                        .foregroundStyle(def?.color ?? .gray)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(def?.name ?? record.metricType)
                            .font(.subheadline)
                        Text(record.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(record.formattedPrimaryValue)
                        .font(.subheadline.bold().monospacedDigit())
                    Text(def?.unit ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if record.id != recent.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
        case .elevated: return .orange
        case .highStage1: return .orange
        case .highStage2: return .red
        case .crisis: return .purple
        }
    }
    var badgeBackgroundColor: Color {
        switch category {
        case .elevated: return .yellow
        default: return badgeColor
        }
    }
    var body: some View {
        Button {
            showClassification = true
        } label: {
            Text(category.rawValue)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(badgeBackgroundColor.opacity(0.15), in: Capsule())
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
