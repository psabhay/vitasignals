import SwiftUI
import SwiftData
import Charts

// MARK: - Resolved Dashboard Card

struct ResolvedDashboardCard: Identifiable {
    let id: UUID
    let metricType: String
    let records: [HealthRecord]
    let definition: MetricDefinition?
    let xDomain: ClosedRange<Date>
}

// MARK: - Resolver

@MainActor
enum DashboardCardResolver {

    static func resolve(
        cards: [DashboardCard],
        dataStore: HealthDataStore
    ) -> [ResolvedDashboardCard] {
        let now = Date.now
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let domain = sevenDaysAgo...now

        return cards
            .filter { !$0.isHidden }
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { card -> ResolvedDashboardCard? in
                guard let metricType = card.metricType,
                      dataStore.availableMetricTypes.contains(metricType) else { return nil }
                let def = MetricRegistry.definition(for: metricType)
                let allRecords = dataStore.records(for: metricType)
                let filtered = allRecords.filter { $0.timestamp >= domain.lowerBound && $0.timestamp <= domain.upperBound }
                guard !filtered.isEmpty else { return nil }

                return ResolvedDashboardCard(
                    id: card.id,
                    metricType: metricType,
                    records: filtered.reversed(),
                    definition: def,
                    xDomain: domain
                )
            }
    }

    /// Ensure dashboard cards exist for all available metrics.
    /// First 5 metrics with data are enabled; the rest are hidden.
    static func syncCards(
        existingCards: [DashboardCard],
        availableMetrics: Set<String>,
        context: ModelContext
    ) {
        let existingTypes = Set(existingCards.compactMap(\.metricType))
        let newTypes = availableMetrics.subtracting(existingTypes)
        guard !newTypes.isEmpty else { return }

        // Order new types by registry order
        var ordered: [String] = []
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category) where newTypes.contains(def.type) {
                ordered.append(def.type)
            }
        }
        for t in newTypes.sorted() where !ordered.contains(t) {
            ordered.append(t)
        }

        let maxSort = existingCards.map(\.sortIndex).max() ?? -1
        let enabledCount = existingCards.filter { !$0.isHidden }.count

        for (i, metricType) in ordered.enumerated() {
            let card = DashboardCard(
                sortIndex: maxSort + 1 + i,
                kind: "default",
                metricType: metricType
            )
            // Auto-enable first 5 total, hide the rest
            card.isHidden = (enabledCount + i) >= 5
            context.insert(card)
        }
        try? context.save()
    }
}

// MARK: - Manage Dashboard Sheet

struct ManageDashboardSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore
    @Query(sort: \DashboardCard.sortIndex) private var allCards: [DashboardCard]

    private static let maxEnabled = 10

    private var sortedCards: [DashboardCard] {
        allCards.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var enabledCount: Int {
        allCards.filter { !$0.isHidden }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedCards, id: \.id) { card in
                        cardRow(card)
                    }
                    .onMove { from, to in
                        reorder(from: from, to: to)
                    }
                } header: {
                    HStack {
                        Text("Dashboard Charts")
                        Spacer()
                        Text("\(enabledCount) of \(Self.maxEnabled)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Enable up to \(Self.maxEnabled) metrics. Drag to reorder.")
                }
            }
            .navigationTitle("Manage Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .presentationDetents([.medium, .large])
    }

    private func cardRow(_ card: DashboardCard) -> some View {
        let def = MetricRegistry.definition(for: card.metricType ?? "")
        let hasData = dataStore.availableMetricTypes.contains(card.metricType ?? "")
        let isEnabled = !card.isHidden
        let atLimit = enabledCount >= Self.maxEnabled

        return HStack(spacing: 12) {
            Image(systemName: def?.icon ?? "chart.xyaxis.line")
                .foregroundStyle(def?.color ?? .gray)
                .font(.subheadline)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(def?.name ?? card.metricType ?? "Unknown")
                    .font(.subheadline)
                if !hasData {
                    Text("No data yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { on in
                    card.isHidden = !on
                    try? modelContext.save()
                }
            ))
            .labelsHidden()
            .disabled(!isEnabled && atLimit)
        }
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        var ordered = sortedCards
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, card) in ordered.enumerated() {
            card.sortIndex = i
        }
        try? modelContext.save()
    }
}
