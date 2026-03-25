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

    // Reminder
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var reminderFrequency: String
    @State private var reminderCustomDays: Int
    @State private var showPermissionDenied = false

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
            _reminderEnabled = State(initialValue: metric.reminderEnabled)
            _reminderFrequency = State(initialValue: metric.reminderFrequency)
            _reminderCustomDays = State(initialValue: metric.reminderCustomDays)
            // Build a Date from hour/minute for the time picker
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            comps.hour = metric.reminderHour
            comps.minute = metric.reminderMinute
            _reminderTime = State(initialValue: Calendar.current.date(from: comps) ?? .now)
        } else {
            _name = State(initialValue: "")
            _unit = State(initialValue: "")
            _selectedIcon = State(initialValue: "star.fill")
            _selectedColorIndex = State(initialValue: 0)
            _isCumulative = State(initialValue: true)
            _inputMin = State(initialValue: 0)
            _inputMax = State(initialValue: 100)
            _inputStep = State(initialValue: 1)
            _reminderEnabled = State(initialValue: false)
            _reminderFrequency = State(initialValue: "daily")
            _reminderCustomDays = State(initialValue: 0)
            // Default 8 PM
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            comps.hour = 20
            comps.minute = 0
            _reminderTime = State(initialValue: Calendar.current.date(from: comps) ?? .now)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                detailsSection
                trackingStyleSection
                reminderSection
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

    // MARK: - Reminder

    private static let weekdaySymbols: [(index: Int, short: String)] = {
        // index = Calendar weekday (1=Sun, 2=Mon, …, 7=Sat)
        // Display Mon–Sun order for a natural UI
        let symbols = Calendar.current.veryShortWeekdaySymbols // ["S","M","T","W","T","F","S"]
        return [2, 3, 4, 5, 6, 7, 1].map { wd in
            (index: wd, short: symbols[wd - 1])
        }
    }()

    private var reminderSection: some View {
        Section {
            Toggle(isOn: $reminderEnabled) {
                Label("Reminder", systemImage: "bell.fill")
            }
            .onChange(of: reminderEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    let granted = await NotificationManager.shared.requestPermission()
                    if !granted {
                        reminderEnabled = false
                        showPermissionDenied = true
                    }
                }
            }

            if reminderEnabled {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)

                Picker("Frequency", selection: $reminderFrequency) {
                    Text("Every Day").tag("daily")
                    Text("Weekdays").tag("weekdays")
                    Text("Custom").tag("custom")
                }

                if reminderFrequency == "custom" {
                    HStack(spacing: 8) {
                        ForEach(Self.weekdaySymbols, id: \.index) { wd in
                            let isOn = reminderCustomDays & (1 << (wd.index - 1)) != 0
                            Button {
                                reminderCustomDays ^= (1 << (wd.index - 1))
                            } label: {
                                Text(wd.short)
                                    .font(.caption.bold())
                                    .frame(width: 36, height: 36)
                                    .background(
                                        isOn ? selectedColor.opacity(0.2) : Color(.systemGray6),
                                        in: Circle()
                                    )
                                    .foregroundStyle(isOn ? selectedColor : .secondary)
                                    .overlay(
                                        Circle().strokeBorder(isOn ? selectedColor : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[wd.index - 1])
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            if reminderEnabled {
                Text("You\u{2019}ll get a notification to log this metric. Reminders expire at midnight and won\u{2019}t carry over to the next day.")
            }
        }
        .alert("Notifications Disabled", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable notifications in Settings to use reminders.")
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

    private var reminderHour: Int { Calendar.current.component(.hour, from: reminderTime) }
    private var reminderMinuteValue: Int { Calendar.current.component(.minute, from: reminderTime) }

    private func save() {
        let metric: CustomMetric
        if let existing = existingMetric {
            metric = existing
            metric.name = name.trimmingCharacters(in: .whitespaces)
            metric.unit = unit.trimmingCharacters(in: .whitespaces)
            metric.icon = selectedIcon
            metric.colorIndex = selectedColorIndex
            metric.isCumulative = isCumulative
            metric.inputMin = inputMin
            metric.inputMax = inputMax
            metric.inputStep = inputStep
        } else {
            metric = CustomMetric(
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
        }

        // Reminder fields
        metric.reminderEnabled = reminderEnabled
        metric.reminderHour = reminderHour
        metric.reminderMinute = reminderMinuteValue
        metric.reminderFrequency = reminderFrequency
        metric.reminderCustomDays = reminderCustomDays

        MetricRegistry.registerCustomMetric(metric.toMetricDefinition())
        try? modelContext.save()

        // Schedule or cancel the notification
        NotificationManager.shared.scheduleReminder(for: metric)

        dataStore.refresh()
        dismiss()
    }
}
