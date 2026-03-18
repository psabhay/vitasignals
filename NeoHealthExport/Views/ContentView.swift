import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @Query private var profiles: [UserProfile]
    @State private var selectedTab = 0
    @State private var showProfile = false
    @State private var hasCompletedOnboarding = false
    @StateObject private var syncManager = HealthSyncManager()

    private var hasProfile: Bool {
        guard let p = profiles.first else { return false }
        return !p.name.isEmpty
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(syncManager: syncManager)
                .tabItem { Label("Dashboard", systemImage: "heart.text.square") }
                .tag(0)

            DataBrowserView()
                .tabItem { Label("Data", systemImage: "list.bullet.clipboard") }
                .tag(1)

            ChartsContainerView()
                .tabItem { Label("Charts", systemImage: "chart.xyaxis.line") }
                .tag(2)

            ReportsTab()
                .tabItem { Label("Reports", systemImage: "doc.text") }
                .tag(3)
        }
        .tint(Color.accentColor)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                EmptyView()
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
        }
        .fullScreenCover(isPresented: .constant(!hasProfile && !hasCompletedOnboarding)) {
            OnboardingView {
                hasCompletedOnboarding = true
                Task {
                    await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
                }
            }
        }
        .task {
            guard hasProfile else { return }
            hasCompletedOnboarding = true
            await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
        }
        .environment(\.showProfile, $showProfile)
    }
}

// MARK: - Environment key to share showProfile binding across tabs

private struct ShowProfileKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var showProfile: Binding<Bool> {
        get { self[ShowProfileKey.self] }
        set { self[ShowProfileKey.self] = newValue }
    }
}

// MARK: - Profile toolbar button modifier (used by each tab's NavigationStack)

struct ProfileToolbarModifier: ViewModifier {
    @Environment(\.showProfile) private var showProfile

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showProfile.wrappedValue = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profile")
            }
        }
    }
}

extension View {
    func withProfileButton() -> some View {
        modifier(ProfileToolbarModifier())
    }
}

// MARK: - Profile Sheet

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ProfileSection()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Onboarding View (first launch)

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?
    var onComplete: () -> Void

    @State private var name = ""
    @State private var age = ""
    @State private var gender = ""
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var weightKg = ""
    @State private var doctorName = ""
    @State private var medicalNotes = ""

    private enum Field: Hashable {
        case name, age, heightFt, heightIn, weight, doctor, notes
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor)
                        Text("Welcome to Neo Health Export")
                            .font(.title2.bold())
                        Text("Set up your profile to personalize your health reports.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("This app is not a medical device and does not provide medical advice. Always consult your healthcare provider.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 12)
                }

                Section("Personal Information") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Name *").font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. John Smith", text: $name)
                            .textContentType(.name)
                            .focused($focusedField, equals: .name)
                    }.padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Age").font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. 35", text: $age)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .age)
                    }.padding(.vertical, 2)

                    Picker("Gender", selection: $gender) {
                        Text("Not specified").tag("")
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                        Text("Other").tag("Other")
                    }
                }

                Section("Height & Weight") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Height").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                TextField("5", text: $heightFeet)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .heightFt)
                                    .frame(minWidth: 40)
                                Text("ft").foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                TextField("8", text: $heightInches)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .heightIn)
                                    .frame(minWidth: 40)
                                Text("in").foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weight").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            TextField("70", text: $weightKg)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                            Text("kg").foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 2)
                }

                Section("Medical (Optional)") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Doctor / Physician").font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. Dr. Sharma", text: $doctorName)
                            .focused($focusedField, equals: .doctor)
                    }.padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medical Notes").font(.caption).foregroundStyle(.secondary)
                        TextField("Medications, conditions...", text: $medicalNotes, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .notes)
                    }.padding(.vertical, 2)
                }

                Section {
                    Button {
                        focusedField = nil
                        saveProfile()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Continue", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func saveProfile() {
        let ft = Double(heightFeet) ?? 0
        let inches = Double(heightInches) ?? 0
        let heightCm = (ft * 12 + inches) * 2.54

        let p = UserProfile()
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.age = Int(age) ?? 0
        p.gender = gender
        p.heightCm = heightCm
        p.weightKg = Double(weightKg) ?? 0
        p.doctorName = doctorName.trimmingCharacters(in: .whitespaces)
        p.medicalNotes = medicalNotes.trimmingCharacters(in: .whitespaces)
        modelContext.insert(p)

        onComplete()
    }
}

// MARK: - Profile Section (for profile sheet and data management)

struct ProfileSection: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @Query private var profiles: [UserProfile]
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
        if !isEditing && hasProfile {
            displayView
        } else {
            editView
        }

        dataManagementSection
    }

    // MARK: - Display View

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

                Button("Edit Profile") {
                    loadProfile()
                    isEditing = true
                }
            }

            if p.heightCm > 0 || p.weightKg > 0 {
                Section("Body") {
                    if p.heightCm > 0 { LabeledContent("Height", value: p.heightFormatted) }
                    if p.weightKg > 0 { LabeledContent("Weight", value: p.weightFormatted) }
                    if let bmi = p.bmi {
                        LabeledContent("BMI") {
                            Text(String(format: "%.1f", bmi)).bold()
                            + Text("  \(p.bmiCategory)").foregroundColor(.secondary)
                        }
                    }
                }
            }

            if !p.doctorName.isEmpty || !p.medicalNotes.isEmpty {
                Section("Medical") {
                    if !p.doctorName.isEmpty { LabeledContent("Physician", value: p.doctorName) }
                    if !p.medicalNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(.caption).foregroundStyle(.secondary)
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
        Section("Personal Information") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. John Smith", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
            }.padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Age").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. 35", text: $age)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .age)
            }.padding(.vertical, 2)

            Picker("Gender", selection: $gender) {
                Text("Not specified").tag("")
                Text("Male").tag("Male")
                Text("Female").tag("Female")
                Text("Other").tag("Other")
            }
        }

        Section("Height & Weight") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Height").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField("5", text: $heightFeet)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .heightFt)
                            .frame(minWidth: 40)
                        Text("ft").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        TextField("8", text: $heightInches)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .heightIn)
                            .frame(minWidth: 40)
                        Text("in").foregroundStyle(.secondary)
                    }
                }
            }.padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Weight").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("70", text: $weightKg)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                    Text("kg").foregroundStyle(.secondary)
                }
            }.padding(.vertical, 2)
        }

        Section("Medical") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doctor / Physician").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Dr. Sharma", text: $doctorName)
                    .focused($focusedField, equals: .doctor)
            }.padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Medical Notes").font(.caption).foregroundStyle(.secondary)
                TextField("Medications, conditions...", text: $medicalNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .notes)
            }.padding(.vertical, 2)
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
                    Label("Save Profile", systemImage: "checkmark.circle.fill").font(.headline)
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
        .alert("Profile Saved", isPresented: $showSaved) {
            Button("OK") {}
        }
        .onAppear {
            loadProfile()
            if !hasProfile { isEditing = true }
        }
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllConfirmation = true
            } label: {
                Label("Delete All Records (\(dataStore.recordCount))", systemImage: "trash")
            }
            .disabled(dataStore.recordCount == 0)

            Button(role: .destructive) {
                showResetDismissedConfirmation = true
            } label: {
                Label("Reset Import History", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Data Management")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("\"Delete All Records\" removes all health data. \"Reset Import History\" allows all Health records to be reimported.")
                Text("Neo Health Export is not a medical device and does not provide medical advice, diagnosis, or treatment. Health data classifications are for informational purposes only. Always consult a qualified healthcare provider.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog("Delete All Records?", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete All \(dataStore.recordCount) Records", role: .destructive) {
                // Fetch managed objects to delete them
                let descriptor = FetchDescriptor<HealthRecord>()
                if let records = try? modelContext.fetch(descriptor) {
                    for record in records {
                        if let hkID = record.healthKitUUID {
                            modelContext.insert(DismissedHealthKitRecord(metricType: record.metricType, healthKitUUID: hkID))
                        }
                        modelContext.delete(record)
                    }
                    try? modelContext.save()
                    dataStore.refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Reset Import History?", isPresented: $showResetDismissedConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                if let dismissed = try? modelContext.fetch(FetchDescriptor<DismissedHealthKitRecord>()) {
                    for d in dismissed { modelContext.delete(d) }
                    try? modelContext.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private var heightCm: Double {
        let ft = Double(heightFeet) ?? 0
        let inches = Double(heightInches) ?? 0
        return (ft * 12 + inches) * 2.54
    }

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
}

// MARK: - Reports Tab

struct ReportsTab: View {
    var body: some View {
        NavigationStack {
            List {
                ReportBuilderView()
            }
            .navigationTitle("Reports")
            .withProfileButton()
        }
    }
}
