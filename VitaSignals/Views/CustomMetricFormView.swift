import SwiftUI
import SwiftData

struct CustomMetricFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataStore: HealthDataStore

    let existingMetric: CustomMetric?

    @State private var name: String
    @State private var unit: String
    @State private var selectedIcon: String
    @State private var selectedColorIndex: Int
    @State private var isCumulative: Bool
    @State private var inputMin: Double
    @State private var inputMax: Double
    @State private var inputStep: Double

    private var isEditMode: Bool { existingMetric != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !unit.trimmingCharacters(in: .whitespaces).isEmpty
            && inputMin < inputMax
            && inputStep > 0
    }

    private var selectedColor: Color {
        CustomMetric.palette[selectedColorIndex % CustomMetric.palette.count]
    }

    init(metric: CustomMetric? = nil) {
        self.existingMetric = metric
        if let metric {
            _name = State(initialValue: metric.name)
            _unit = State(initialValue: metric.unit)
            _selectedIcon = State(initialValue: metric.icon)
            _selectedColorIndex = State(initialValue: metric.colorIndex)
            _isCumulative = State(initialValue: metric.isCumulative)
            _inputMin = State(initialValue: metric.inputMin)
            _inputMax = State(initialValue: metric.inputMax)
            _inputStep = State(initialValue: metric.inputStep)
        } else {
            _name = State(initialValue: "")
            _unit = State(initialValue: "")
            _selectedIcon = State(initialValue: "star.fill")
            _selectedColorIndex = State(initialValue: 0)
            _isCumulative = State(initialValue: true)
            _inputMin = State(initialValue: 0)
            _inputMax = State(initialValue: 100)
            _inputStep = State(initialValue: 1)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                detailsSection
                trackingStyleSection
                iconSection
                colorSection
                inputRangeSection
            }
            .navigationTitle(isEditMode ? "Edit Metric" : "New Custom Metric")
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
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(selectedColor)
                    .frame(width: 44, height: 44)
                    .background(selectedColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Metric Name" : name)
                        .font(.headline)
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                    Text(unit.isEmpty ? "unit" : unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isCumulative ? "chart.bar.fill" : "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.tertiary)
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name (e.g. Coffee)", text: $name)
            TextField("Unit (e.g. cups)", text: $unit)
                .textInputAutocapitalization(.never)
        }
    }

    // MARK: - Tracking Style

    private var trackingStyleSection: some View {
        Section {
            Picker("Tracking", selection: $isCumulative) {
                Label("Tally — sum per day", systemImage: "chart.bar.fill").tag(true)
                Label("Readings — each entry", systemImage: "chart.line.uptrend.xyaxis").tag(false)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Tracking Style")
        } footer: {
            Text(isCumulative
                ? "Values are summed per day. Best for things you count (cups, pills, cigarettes)."
                : "Each entry is recorded individually. Best for measurements (mood, pain level).")
        }
    }

    // MARK: - Icon Picker

    private var iconSection: some View {
        Section("Icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(CustomMetric.availableIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(
                                selectedIcon == icon
                                    ? selectedColor.opacity(0.15)
                                    : Color(.systemGray6),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(selectedIcon == icon ? selectedColor : .secondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selectedIcon == icon ? selectedColor : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Color Picker

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(Array(CustomMetric.palette.enumerated()), id: \.offset) { index, color in
                    Button {
                        selectedColorIndex = index
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: selectedColorIndex == index ? 3 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(color.opacity(0.8), lineWidth: selectedColorIndex == index ? 2 : 0)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Input Range

    private var inputRangeSection: some View {
        Section {
            HStack {
                Text("Minimum")
                Spacer()
                TextField("0", value: $inputMin, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text("Maximum")
                Spacer()
                TextField("100", value: $inputMax, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text("Step")
                Spacer()
                TextField("1", value: $inputStep, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        } header: {
            Text("Input Range")
        } footer: {
            Text("Controls the stepper when logging values.")
        }
    }

    // MARK: - Save

    private func save() {
        if let metric = existingMetric {
            metric.name = name.trimmingCharacters(in: .whitespaces)
            metric.unit = unit.trimmingCharacters(in: .whitespaces)
            metric.icon = selectedIcon
            metric.colorIndex = selectedColorIndex
            metric.isCumulative = isCumulative
            metric.inputMin = inputMin
            metric.inputMax = inputMax
            metric.inputStep = inputStep
            // Re-register updated definition
            MetricRegistry.registerCustomMetric(metric.toMetricDefinition())
        } else {
            let metric = CustomMetric(
                name: name.trimmingCharacters(in: .whitespaces),
                unit: unit.trimmingCharacters(in: .whitespaces),
                icon: selectedIcon,
                colorIndex: selectedColorIndex,
                isCumulative: isCumulative,
                inputMin: inputMin,
                inputMax: inputMax,
                inputStep: inputStep
            )
            modelContext.insert(metric)
            MetricRegistry.registerCustomMetric(metric.toMetricDefinition())
        }
        try? modelContext.save()
        dataStore.refresh()
        dismiss()
    }
}
