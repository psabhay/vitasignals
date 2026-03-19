import SwiftUI
import SwiftData

struct RecordDetailView: View {
    let record: HealthRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: record.metricType)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                detailsSection

                if record.metricType == MetricType.bloodPressure {
                    bpContextSection
                }

                if !record.notes.isEmpty {
                    Section("Notes") {
                        Text(record.notes)
                    }
                }

                sourceSection
                actionSection
            }
            .navigationTitle(definition?.name ?? "Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                HealthRecordFormView(metricType: record.metricType, record: record)
            }
            .confirmationDialog("Delete this record?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let hkID = record.healthKitUUID {
                        modelContext.insert(DismissedHealthKitRecord(metricType: record.metricType, healthKitUUID: hkID))
                    }
                    modelContext.delete(record)
                    try? modelContext.save()
                    dataStore.refresh()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(record.formattedPrimaryValue) on \(record.formattedDate)")
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                if let def = definition {
                    Image(systemName: def.icon)
                        .font(.title)
                        .foregroundStyle(def.color)
                }
                Text(record.formattedPrimaryValue)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                if let def = definition {
                    Text(def.unit)
                        .foregroundStyle(.secondary)
                }
                if record.metricType == MetricType.bloodPressure {
                    CategoryBadge(category: record.bpCategory)
                }
                if record.isFromHealthKit {
                    Label("Imported from Apple Health", systemImage: "heart.circle")
                        .font(.caption)
                        .foregroundStyle(.pink)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .padding(.vertical)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Date") {
                Text(record.formattedDate)
            }

            if record.metricType == MetricType.bloodPressure {
                LabeledContent("Systolic") {
                    Text("\(record.systolic) mmHg")
                        .foregroundStyle(.red)
                }
                LabeledContent("Diastolic") {
                    Text("\(record.diastolic) mmHg")
                        .foregroundStyle(.blue)
                }
                LabeledContent("Pulse") {
                    if let p = record.pulseOptional {
                        Text("\(p) bpm")
                            .foregroundStyle(.pink)
                    } else {
                        Text("N/A")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if record.metricType == MetricType.sleepDuration {
                LabeledContent("Duration") {
                    let hours = (record.durationSeconds ?? record.primaryValue * 3600) / 3600
                    Text(String(format: "%.1f hours", hours))
                }
            } else if let def = definition {
                LabeledContent("Value") {
                    Text("\(def.formatValue(record.primaryValue)) \(def.unit)")
                        .foregroundStyle(def.color)
                }
            }
        }
    }

    // MARK: - BP Context

    @ViewBuilder
    private var bpContextSection: some View {
        Section("Context") {
            if let ctx = record.bpActivityContext {
                LabeledContent("Activity") {
                    Label(ctx.rawValue, systemImage: ctx.icon)
                }
            }
        }
    }

    // MARK: - Source

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            LabeledContent("Source") {
                Text(record.source)
            }
            LabeledContent("Type") {
                Text(record.isManualEntry ? "Manual Entry" : "Synced from Health")
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionSection: some View {
        Section {
            Button {
                showEditSheet = true
            } label: {
                Label("Edit Record", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Record", systemImage: "trash")
            }
        }
    }
}
