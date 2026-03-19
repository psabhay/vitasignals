import SwiftUI

struct AddRecordPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore
    var onSelect: (String) -> Void
    @State private var showCreateCustomMetric = false
    @State private var customMetricRefreshID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(MetricCategory.allCases) { category in
                        if category == .custom {
                            customSection.id(customMetricRefreshID)
                        } else {
                            let defs = MetricRegistry.definitions(for: category)
                            if !defs.isEmpty {
                                metricCategorySection(category: category, definitions: defs)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Add Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateCustomMetric) {
                CustomMetricFormView()
                    .onDisappear {
                        // Force refresh the custom section after creating a metric
                        customMetricRefreshID = UUID()
                    }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Standard Category Section

    private func metricCategorySection(category: MetricCategory, definitions: [MetricDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(category.rawValue, systemImage: category.icon)
                .font(.subheadline.bold())
                .foregroundStyle(category.color)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(definitions, id: \.type) { def in
                    metricButton(def: def)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Custom Section

    private var customSection: some View {
        let defs = MetricRegistry.definitions(for: .custom)
        return VStack(alignment: .leading, spacing: 10) {
            Label(MetricCategory.custom.rawValue, systemImage: MetricCategory.custom.icon)
                .font(.subheadline.bold())
                .foregroundStyle(MetricCategory.custom.color)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(defs, id: \.type) { def in
                    metricButton(def: def)
                }

                // "Create New" button
                Button {
                    showCreateCustomMetric = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create New")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("Custom metric")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Metric Button

    private func metricButton(def: MetricDefinition) -> some View {
        Button {
            onSelect(def.type)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: def.icon)
                    .font(.title3)
                    .foregroundStyle(def.color)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(def.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(def.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(def.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
