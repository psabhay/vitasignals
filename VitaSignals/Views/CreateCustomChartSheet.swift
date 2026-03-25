import SwiftUI
import SwiftData

struct CreateCustomChartSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore
    @Query(sort: \CustomMetric.createdAt) private var customMetrics: [CustomMetric]
    @Query(sort: \DashboardCard.sortIndex) private var dashboardCards: [DashboardCard]

    var editingChart: CustomChart? = nil

    @State private var name: String = ""
    @State private var leftMetric: String = ""
    @State private var rightMetric: String = ""

    private var isEditMode: Bool { editingChart != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !leftMetric.isEmpty
            && !rightMetric.isEmpty
            && leftMetric != rightMetric
    }

    /// All metrics that have data or are custom (even without data).
    private var availableMetrics: [(type: String, def: MetricDefinition)] {
        var result: [(String, MetricDefinition)] = []
        for category in MetricCategory.allCases {
            for def in MetricRegistry.definitions(for: category)
                where dataStore.availableMetricTypes.contains(def.type) {
                result.append((def.type, def))
            }
        }
        // Custom metrics without data
        let existingTypes = Set(result.map(\.0))
        for cm in customMetrics where !existingTypes.contains(cm.metricType) {
            if let def = MetricRegistry.definition(for: cm.metricType) {
                result.append((cm.metricType, def))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart Name") {
                    TextField("e.g. Morning Vitals", text: $name)
                }

                Section {
                    Picker("Left Axis", selection: $leftMetric) {
                        Text("Select metric...").tag("")
                        ForEach(availableMetrics.filter { $0.type != rightMetric }, id: \.type) { item in
                            Label(item.def.name, systemImage: item.def.icon)
                                .tag(item.type)
                        }
                    }
                } header: {
                    Text("Left Axis")
                } footer: {
                    if let def = MetricRegistry.definition(for: leftMetric) {
                        Text("Unit: \(def.unit)")
                    }
                }

                Section {
                    Picker("Right Axis", selection: $rightMetric) {
                        Text("Select metric...").tag("")
                        ForEach(availableMetrics.filter { $0.type != leftMetric }, id: \.type) { item in
                            Label(item.def.name, systemImage: item.def.icon)
                                .tag(item.type)
                        }
                    }
                } header: {
                    Text("Right Axis")
                } footer: {
                    if let def = MetricRegistry.definition(for: rightMetric) {
                        Text("Unit: \(def.unit)")
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Chart" : "New Custom Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let chart = editingChart {
                    name = chart.name
                    leftMetric = chart.leftMetricType
                    rightMetric = chart.rightMetricType
                }
            }
        }
    }

    private func save() {
        if let chart = editingChart {
            chart.name = name.trimmingCharacters(in: .whitespaces)
            chart.leftMetricType = leftMetric
            chart.rightMetricType = rightMetric
        } else {
            let chart = CustomChart(
                name: name.trimmingCharacters(in: .whitespaces),
                leftMetricType: leftMetric,
                rightMetricType: rightMetric
            )
            modelContext.insert(chart)

            // Create a DashboardCard for this custom chart
            let maxSort = dashboardCards.map(\.sortIndex).max() ?? -1
            let card = DashboardCard(
                sortIndex: maxSort + 1,
                kind: "custom_chart",
                customChartID: chart.id
            )
            modelContext.insert(card)
        }
        try? modelContext.save()
        dismiss()
    }
}
