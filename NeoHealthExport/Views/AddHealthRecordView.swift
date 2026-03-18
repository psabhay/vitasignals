import SwiftUI
import SwiftData

struct AddHealthRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore

    let metricType: String

    @State private var timestamp: Date = .now
    @State private var notes: String = ""

    // BP fields
    @State private var systolic: Int = 120
    @State private var diastolic: Int = 80
    @State private var pulse: Int = 72
    @State private var selectedContext: ActivityContext = .atRest

    // Generic numeric field
    @State private var primaryValue: Double = 0

    // Sleep field
    @State private var sleepHours: Double = 7.5

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: metricType)
    }

    init(metricType: String = MetricType.bloodPressure) {
        self.metricType = metricType
        if let def = MetricRegistry.definition(for: metricType) {
            _primaryValue = State(initialValue: (def.inputMin + def.inputMax) / 2)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if metricType == MetricType.bloodPressure {
                    bpForm
                } else if metricType == MetricType.sleepDuration {
                    sleepForm
                } else {
                    genericForm
                }

                Section("When") {
                    DatePicker("Date & Time", selection: $timestamp)
                }

                Section("Notes (Optional)") {
                    TextField("Any additional details...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add \(definition?.name ?? "Record")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecord() }
                        .bold()
                }
            }
        }
    }

    // MARK: - Blood Pressure Form

    @ViewBuilder
    private var bpForm: some View {
        Section {
            VStack(spacing: 8) {
                Text("\(systolic)/\(diastolic)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                CategoryBadge(category: BPCategory.classify(systolic: systolic, diastolic: diastolic))
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
        }

        Section("Blood Pressure") {
            Stepper(value: $systolic, in: 60...300) {
                HStack {
                    Text("Systolic")
                    Spacer()
                    Text("\(systolic)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }
            Stepper(value: $diastolic, in: 30...200) {
                HStack {
                    Text("Diastolic")
                    Spacer()
                    Text("\(diastolic)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.blue)
                }
            }
            Stepper(value: $pulse, in: 30...220) {
                HStack {
                    Text("Pulse")
                    Spacer()
                    Text("\(pulse)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.pink)
                }
            }
        }

        Section("Context") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ActivityContext.allCases) { context in
                    Button {
                        selectedContext = context
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: context.icon)
                                .font(.caption)
                            Text(context.rawValue)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(
                            selectedContext == context
                                ? Color.accentColor.opacity(0.15)
                                : Color(.systemGray6)
                        )
                        .foregroundStyle(
                            selectedContext == context ? Color.accentColor : .primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    selectedContext == context ? Color.accentColor : .clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(context.rawValue)
                    .accessibilityAddTraits(selectedContext == context ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sleep Form

    @ViewBuilder
    private var sleepForm: some View {
        Section {
            VStack(spacing: 8) {
                Text(String(format: "%.1f", sleepHours))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                Text("hours")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
        }

        Section("Sleep Duration") {
            Stepper(value: $sleepHours, in: 0...24, step: 0.5) {
                HStack {
                    Text("Hours")
                    Spacer()
                    Text(String(format: "%.1f", sleepHours))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.indigo)
                }
            }
        }
    }

    // MARK: - Generic Numeric Form

    @ViewBuilder
    private var genericForm: some View {
        if let def = definition {
            Section {
                VStack(spacing: 8) {
                    Text(def.formatValue(primaryValue))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                    Text(def.unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
            }

            Section(def.name) {
                Stepper(value: $primaryValue, in: def.inputMin...def.inputMax, step: def.inputStep) {
                    HStack {
                        Text("Value")
                        Spacer()
                        Text(def.formatValue(primaryValue))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(def.color)
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func saveRecord() {
        let record: HealthRecord
        if metricType == MetricType.bloodPressure {
            record = HealthRecord.bloodPressure(
                systolic: systolic,
                diastolic: diastolic,
                pulse: pulse,
                timestamp: timestamp,
                activityContext: selectedContext,
                notes: notes
            )
        } else if metricType == MetricType.sleepDuration {
            record = HealthRecord(
                metricType: MetricType.sleepDuration,
                timestamp: timestamp,
                primaryValue: sleepHours,
                durationSeconds: sleepHours * 3600,
                notes: notes
            )
        } else {
            record = HealthRecord(
                metricType: metricType,
                timestamp: timestamp,
                primaryValue: primaryValue,
                notes: notes
            )
        }
        modelContext.insert(record)
        try? modelContext.save()
        dataStore.refresh()
        dismiss()
    }
}
