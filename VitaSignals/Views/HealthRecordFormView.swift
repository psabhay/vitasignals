import SwiftUI
import SwiftData

struct HealthRecordFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore

    let metricType: String
    let existingRecord: HealthRecord?

    private var isEditMode: Bool { existingRecord != nil }
    private var isHealthKitRecord: Bool { existingRecord?.isFromHealthKit ?? false }

    @State private var timestamp: Date
    @State private var notes: String

    // BP fields
    @State private var systolic: Int
    @State private var diastolic: Int
    @State private var pulse: Int
    @State private var selectedContext: ActivityContext

    // Generic numeric field
    @State private var primaryValue: Double

    // Sleep field
    @State private var sleepHours: Double

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: metricType)
    }

    init(metricType: String, record: HealthRecord? = nil) {
        self.metricType = metricType
        self.existingRecord = record

        if let record {
            _timestamp = State(initialValue: record.timestamp)
            _notes = State(initialValue: record.notes)
            _systolic = State(initialValue: record.systolic)
            _diastolic = State(initialValue: record.diastolic)
            _pulse = State(initialValue: record.pulse)
            _selectedContext = State(initialValue: record.bpActivityContext ?? .atRest)
            _primaryValue = State(initialValue: record.primaryValue)
            _sleepHours = State(initialValue: metricType == MetricType.sleepDuration
                ? (record.durationSeconds ?? record.primaryValue * 3600) / 3600
                : record.primaryValue)
        } else {
            _timestamp = State(initialValue: .now)
            _notes = State(initialValue: "")
            _systolic = State(initialValue: 120)
            _diastolic = State(initialValue: 80)
            _pulse = State(initialValue: 72)
            _selectedContext = State(initialValue: .atRest)
            let def = MetricRegistry.definition(for: metricType)
            _primaryValue = State(initialValue: def.map { ($0.inputMin + $0.inputMax) / 2 } ?? 0)
            _sleepHours = State(initialValue: 7.5)
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

                if isHealthKitRecord {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Imported from Apple Health")
                                    .font(.subheadline.bold())
                                Text("Values are read-only. You can edit the timestamp and notes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "heart.circle")
                                .foregroundStyle(.pink)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextField("Any additional details...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("\(isEditMode ? "Edit" : "Add") \(definition?.name ?? "Record")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
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

        if isHealthKitRecord {
            Section("Blood Pressure") {
                LabeledContent("Systolic") {
                    Text("\(systolic) mmHg").font(.headline.monospacedDigit()).foregroundStyle(.red)
                }
                LabeledContent("Diastolic") {
                    Text("\(diastolic) mmHg").font(.headline.monospacedDigit()).foregroundStyle(.blue)
                }
                LabeledContent("Pulse") {
                    Text("\(pulse) bpm").font(.headline.monospacedDigit()).foregroundStyle(.pink)
                }
            }
            if let ctx = existingRecord?.bpActivityContext {
                Section("Context") {
                    LabeledContent("Activity") {
                        Label(ctx.rawValue, systemImage: ctx.icon)
                    }
                }
            }
        } else {
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

        if !isHealthKitRecord {
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
    }

    // Generic text field binding for large-range metrics
    @State private var primaryValueText: String = ""
    @State private var hasInitializedText = false

    private var isLargeRange: Bool {
        guard let def = definition else { return false }
        return (def.inputMax - def.inputMin) > 200
    }

    // MARK: - Generic Form

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

            if let desc = def.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isHealthKitRecord {
                Section(def.name) {
                    if isLargeRange {
                        HStack {
                            Text("Value")
                            Spacer()
                            TextField("Value", text: $primaryValueText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(def.color)
                                .frame(maxWidth: 120)
                                .onChange(of: primaryValueText) { _, newValue in
                                    if let parsed = Double(newValue) {
                                        primaryValue = min(max(parsed, def.inputMin), def.inputMax)
                                    }
                                }
                                .onAppear {
                                    if !hasInitializedText {
                                        primaryValueText = def.formatValue(primaryValue)
                                        hasInitializedText = true
                                    }
                                }
                            Text(def.unit)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
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
        }
    }

    // MARK: - Save

    private func save() {
        if let record = existingRecord {
            // Edit mode
            record.timestamp = timestamp
            record.notes = notes

            if !isHealthKitRecord {
                if metricType == MetricType.bloodPressure {
                    record.primaryValue = Double(systolic)
                    record.secondaryValue = Double(diastolic)
                    record.tertiaryValue = Double(pulse)
                    record.activityContext = selectedContext.rawValue
                } else if metricType == MetricType.sleepDuration {
                    record.primaryValue = sleepHours
                    record.durationSeconds = sleepHours * 3600
                } else {
                    record.primaryValue = primaryValue
                }
            }
        } else {
            // Add mode
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
        }
        try? modelContext.save()
        dataStore.refresh()
        dismiss()
    }
}
