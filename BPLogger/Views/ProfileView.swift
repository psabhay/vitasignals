import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: \BPReading.timestamp, order: .reverse) private var readings: [BPReading]
    @FocusState private var focusedField: Field?

    @State private var name = ""
    @State private var age = ""
    @State private var gender = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var weightKg = ""
    @State private var doctorName = ""
    @State private var medicalNotes = ""
    @State private var showDeleteAllConfirmation = false
    @State private var showResetDismissedConfirmation = false
    @State private var showSaved = false
    @State private var isEditing = false

    private enum Field: Hashable {
        case name, age, heightFt, heightIn, weight, doctor, notes
    }

    private var profile: UserProfile? { profiles.first }
    private var hasProfile: Bool { profile != nil && !(profile?.name.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            List {
                if !isEditing && hasProfile {
                    displayView
                } else {
                    editView
                }

                dataManagementSection
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                if hasProfile && !isEditing {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") {
                            loadProfile()
                            isEditing = true
                        }
                    }
                }
            }
            .alert("Profile Saved", isPresented: $showSaved) {
                Button("OK") {}
            }
            .confirmationDialog(
                "Delete All Readings?",
                isPresented: $showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All \(readings.count) Readings", role: .destructive) {
                    deleteAllReadings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all \(readings.count) readings. Previously imported Health data will not reappear on future imports.")
            }
            .confirmationDialog(
                "Reset Import History?",
                isPresented: $showResetDismissedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    resetDismissedIDs()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the list of dismissed HealthKit records. All records including previously deleted ones will appear on next import.")
            }
            .onAppear {
                loadProfile()
                if !hasProfile { isEditing = true }
            }
        }
    }

    // MARK: - Display View (Read-only)

    @ViewBuilder
    private var displayView: some View {
        if let p = profile {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor.opacity(0.7))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name)
                            .font(.title2.bold())

                        HStack(spacing: 12) {
                            if p.age > 0 {
                                Label("\(p.age) yrs", systemImage: "calendar")
                            }
                            if !p.gender.isEmpty {
                                Label(p.gender, systemImage: "person")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if p.heightCm > 0 || p.weightKg > 0 {
                Section("Body") {
                    if p.heightCm > 0 {
                        LabeledContent("Height", value: p.heightFormatted)
                    }
                    if p.weightKg > 0 {
                        LabeledContent("Weight", value: p.weightFormatted)
                    }
                    if let bmi = p.bmi {
                        LabeledContent("BMI") {
                            Text(String(format: "%.1f", bmi))
                                .bold()
                            + Text("  \(p.bmiCategory)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if !p.doctorName.isEmpty || !p.medicalNotes.isEmpty {
                Section("Medical") {
                    if !p.doctorName.isEmpty {
                        LabeledContent("Physician", value: p.doctorName)
                    }
                    if !p.medicalNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(p.medicalNotes)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Edit View

    @ViewBuilder
    private var editView: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Abhay Singh", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Age")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. 35", text: $age)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .age)
            }
            .padding(.vertical, 2)

            Picker("Gender", selection: $gender) {
                Text("Not specified").tag("")
                Text("Male").tag("Male")
                Text("Female").tag("Female")
                Text("Other").tag("Other")
            }
        } header: {
            Text("Personal Information")
        }

        Section("Height & Weight") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Height")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField("5", text: $heightFeet)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .heightFt)
                            .frame(minWidth: 40)
                        Text("ft")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        TextField("8", text: $heightInches)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .heightIn)
                            .frame(minWidth: 40)
                        Text("in")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Weight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("70", text: $weightKg)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            if let bmi = computedBMI {
                HStack {
                    Text("BMI")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", bmi))
                        .bold()
                    Text("(\(bmiCategory(bmi)))")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Medical") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doctor / Physician")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Dr. Sharma", text: $doctorName)
                    .focused($focusedField, equals: .doctor)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Medical Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Medications, conditions...", text: $medicalNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .notes)
            }
            .padding(.vertical, 2)
        }

        Section {
            Button {
                focusedField = nil
                saveProfile()
                showSaved = true
                isEditing = false
            } label: {
                HStack {
                    Spacer()
                    Label("Save Profile", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    Spacer()
                }
            }

            if hasProfile {
                Button("Cancel", role: .cancel) {
                    focusedField = nil
                    loadProfile()
                    isEditing = false
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label("Delete All Readings (\(readings.count))", systemImage: "trash")
            }
            .disabled(readings.isEmpty)

            Button(role: .destructive) {
                showResetDismissedConfirmation = true
            } label: {
                Label("Reset Import History", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("\"Delete All Readings\" removes all data but remembers dismissed Health records. \"Reset Import History\" clears that memory so all Health records can be reimported.")
        }
    }

    // MARK: - Computed

    private var heightCm: Double {
        let ft = Double(heightFeet) ?? 0
        let inches = Double(heightInches) ?? 0
        return (ft * 12 + inches) * 2.54
    }

    private var computedBMI: Double? {
        let h = heightCm
        let w = Double(weightKg) ?? 0
        guard h > 0, w > 0 else { return nil }
        return w / ((h / 100) * (h / 100))
    }

    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }

    // MARK: - Actions

    private func loadProfile() {
        guard let p = profile else { return }
        name = p.name
        age = p.age > 0 ? "\(p.age)" : ""
        gender = p.gender
        if p.heightCm > 0 {
            let totalInches = p.heightCm / 2.54
            heightFeet = "\(Int(totalInches) / 12)"
            heightInches = "\(Int(totalInches) % 12)"
        }
        weightKg = p.weightKg > 0 ? String(format: "%.1f", p.weightKg) : ""
        doctorName = p.doctorName
        medicalNotes = p.medicalNotes
    }

    private func saveProfile() {
        let p = profile ?? UserProfile()
        if profile == nil { modelContext.insert(p) }

        p.name = name.trimmingCharacters(in: .whitespaces)
        p.age = Int(age) ?? 0
        p.gender = gender
        p.heightCm = heightCm
        p.weightKg = Double(weightKg) ?? 0
        p.doctorName = doctorName.trimmingCharacters(in: .whitespaces)
        p.medicalNotes = medicalNotes.trimmingCharacters(in: .whitespaces)
    }

    private func deleteAllReadings() {
        for reading in readings {
            if let hkID = reading.healthKitID {
                modelContext.insert(DismissedHealthKitID(healthKitID: hkID))
            }
            modelContext.delete(reading)
        }
    }

    private func resetDismissedIDs() {
        do {
            let dismissed = try modelContext.fetch(FetchDescriptor<DismissedHealthKitID>())
            for d in dismissed { modelContext.delete(d) }
        } catch {}
    }
}
