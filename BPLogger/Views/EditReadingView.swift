import SwiftUI
import SwiftData

struct EditReadingView: View {
    @Bindable var reading: BPReading
    @Environment(\.dismiss) private var dismiss

    @State private var systolic: Int
    @State private var diastolic: Int
    @State private var pulse: Int
    @State private var timestamp: Date
    @State private var selectedContext: ActivityContext
    @State private var notes: String

    init(reading: BPReading) {
        self.reading = reading
        _systolic = State(initialValue: reading.systolic)
        _diastolic = State(initialValue: reading.diastolic)
        _pulse = State(initialValue: reading.pulse)
        _timestamp = State(initialValue: reading.timestamp)
        _selectedContext = State(initialValue: reading.activityContext)
        _notes = State(initialValue: reading.notes)
    }

    private var previewCategory: BPCategory {
        BPReading.classify(systolic: systolic, diastolic: diastolic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Text("\(systolic)/\(diastolic)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                        CategoryBadge(category: previewCategory)
                        if reading.isFromHealthKit {
                            Label("Imported from Apple Health", systemImage: "heart.circle")
                                .font(.caption)
                                .foregroundStyle(.pink)
                        }
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

                Section("When") {
                    DatePicker("Date & Time", selection: $timestamp)
                }

                Section("Context") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
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
                                    selectedContext == context
                                        ? Color.accentColor
                                        : .primary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            selectedContext == context
                                                ? Color.accentColor
                                                : .clear,
                                            lineWidth: 1.5
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Notes (Optional)") {
                    TextField("Any additional details...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .bold()
                }
            }
        }
    }

    private func saveChanges() {
        reading.systolic = systolic
        reading.diastolic = diastolic
        reading.pulse = pulse
        reading.timestamp = timestamp
        reading.activityContext = selectedContext
        reading.notes = notes
        dismiss()
    }
}
