import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @EnvironmentObject var storeManager: StoreManager
    @Query private var profiles: [UserProfile]
    @State private var selectedTab = 0
    @State private var hasCompletedOnboarding = false
    @State private var showFirstSyncOverlay = false
    @State private var showOnboarding = false
    @State private var shouldRunFirstSyncAfterOnboarding = false
    @StateObject private var syncManager = HealthSyncManager()
    @State private var notificationMetricType: String?
    @State private var pendingNotificationMetricType: String?

    private var hasProfile: Bool {
        guard let p = profiles.first else { return false }
        return !p.name.isEmpty
    }

    var body: some View {
        Group {
            if storeManager.isLoading {
                // Show neutral loading while verifying subscription status
                // to avoid flashing PaywallView for premium users on cold launch
                ProgressView()
                    .scaleEffect(1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !storeManager.isPremium {
                PaywallView()
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            DashboardView(syncManager: syncManager)
                .tabItem { Label("Home", systemImage: "heart.text.square") }
                .tag(0)

            ChartsContainerView()
                .tabItem { Label("Metrics", systemImage: "chart.xyaxis.line") }
                .tag(1)

            ProfileView(syncManager: syncManager)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(2)
        }
        .tint(Color.accentColor)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                EmptyView()
            }
        }
        .overlay {
            if showFirstSyncOverlay {
                FirstSyncOverlayView(syncManager: syncManager)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
            guard shouldRunFirstSyncAfterOnboarding else { return }
            shouldRunFirstSyncAfterOnboarding = false
            performFirstSync()
        }) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
                selectedTab = 0
                shouldRunFirstSyncAfterOnboarding = true
            }
        }
        .task {
            if !hasProfile && !hasCompletedOnboarding {
                showOnboarding = true
            }
            guard hasProfile else { return }
            hasCompletedOnboarding = true
            // Only show overlay on first ever sync (no lastSyncDate)
            if syncManager.lastSyncDate == nil {
                performFirstSync()
            } else {
                // Silent background sync for returning users
                await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationManager.openMetricFormNotification)) { notification in
            if let metricType = notification.userInfo?["metricType"] as? String {
                // Switch to Home tab; the form will open once the tab switch settles
                selectedTab = 0
                pendingNotificationMetricType = metricType
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Open the form after the tab switch completes
            if newTab == 0, let metricType = pendingNotificationMetricType {
                pendingNotificationMetricType = nil
                notificationMetricType = metricType
            }
        }
        .onChange(of: hasProfile) { _, profileExists in
            if profileExists {
                showOnboarding = false
            }
        }
        .sheet(item: Binding(
            get: { notificationMetricType.map { MetricTypeWrapper(metricType: $0) } },
            set: { notificationMetricType = $0?.metricType }
        )) { wrapper in
            HealthRecordFormView(metricType: wrapper.metricType)
        }
    }

    private func performFirstSync() {
        guard !showFirstSyncOverlay else { return }
        showFirstSyncOverlay = true
        Task {
            await Task.yield()
            await syncManager.syncAll(container: modelContext.container, dataStore: dataStore)
            withAnimation(.easeOut(duration: 0.4)) {
                showFirstSyncOverlay = false
            }
        }
    }
}

/// Lightweight Identifiable wrapper so a metric type string can drive a `.sheet(item:)`.
private struct MetricTypeWrapper: Identifiable {
    let metricType: String
    var id: String { metricType }
}

// MARK: - First Sync Overlay

struct FirstSyncOverlayView: View {
    @ObservedObject var syncManager: HealthSyncManager

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, options: .repeating)

                Text("Setting Up Your Dashboard")
                    .font(.title2.bold())

                Text("Connecting to Apple Health and importing your data. This only takes a moment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text(syncManager.syncProgress.isEmpty ? "Getting ready..." : syncManager.syncProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut, value: syncManager.syncProgress)
                }
                .padding(.top, 8)

                Spacer()
                Spacer()
            }
        }
        .transition(.opacity)
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
                        Text("Welcome to VitaSignals")
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
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
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
    @ObservedObject var syncManager: HealthSyncManager
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataStore: HealthDataStore
    @EnvironmentObject var storeManager: StoreManager
    @Query private var profiles: [UserProfile]
    @Query(sort: \CustomMetric.createdAt) private var customMetrics: [CustomMetric]
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
    @State private var showBMIInfo = false
    @State private var editingCustomMetric: CustomMetric?
    @State private var showCreateCustomMetric = false
    @State private var showDeleteCustomMetricConfirmation = false
    @State private var customMetricToDelete: CustomMetric?
    @State private var showSaveError = false
    #if DEBUG
    @State private var showSyntheticDataConfirmation = false
    @State private var syntheticDataCount: Int?
    #endif

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

        subscriptionSection

        customMetricsSection

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
                        HStack {
                            Text("BMI")
                            Button {
                                showBMIInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showBMIInfo) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("BMI Categories")
                                        .font(.subheadline.bold())
                                    Group {
                                        Text("Underweight: < 18.5")
                                        Text("Normal: 18.5 - 24.9")
                                        Text("Overweight: 25 - 29.9")
                                        Text("Obese: \u{2265} 30")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding()
                                .presentationCompactAdaptation(.popover)
                            }
                            Spacer()
                            Text(String(format: "%.1f", bmi)).bold()
                            + Text("  \(p.bmiCategory)").foregroundStyle(.secondary)
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

    // MARK: - Subscription

    @State private var showManageSubscription = false

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Image(systemName: subscriptionIcon)
                    .foregroundStyle(subscriptionIconColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan: \(storeManager.currentPlan)")
                        .font(.subheadline)
                    if storeManager.isTrialActive {
                        Text("\(storeManager.trialDaysRemaining) days remaining in free trial")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !storeManager.purchasedProductIDs.isEmpty {
                Button {
                    showManageSubscription = true
                } label: {
                    Label("Manage or Change Plan", systemImage: "creditcard")
                }
            }

            Button {
                Task { await storeManager.restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
    }

    private var subscriptionIcon: String {
        if !storeManager.purchasedProductIDs.isEmpty { return "checkmark.seal.fill" }
        if storeManager.isTrialActive { return "clock" }
        return "xmark.circle"
    }

    private var subscriptionIconColor: Color {
        if !storeManager.purchasedProductIDs.isEmpty { return .green }
        if storeManager.isTrialActive { return .orange }
        return .red
    }

    // MARK: - Custom Metrics Management

    @ViewBuilder
    private var customMetricsSection: some View {
        Section {
            if customMetrics.isEmpty {
                Text("No custom metrics yet. Create one from the \(Image(systemName: "plus.circle.fill")) Add Record menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(customMetrics) { metric in
                    Button {
                        editingCustomMetric = metric
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: metric.icon)
                                .foregroundStyle(metric.color)
                                .font(.subheadline)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(metric.unit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: metric.isCumulative ? "chart.bar.fill" : "chart.line.uptrend.xyaxis")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            customMetricToDelete = metric
                            showDeleteCustomMetricConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Custom Metrics")
        } footer: {
            if !customMetrics.isEmpty {
                Text("Tap to edit. Swipe left to delete.")
            }
        }
        .sheet(item: $editingCustomMetric) { metric in
            CustomMetricFormView(metric: metric)
        }
        .sheet(isPresented: $showCreateCustomMetric) {
            CustomMetricFormView()
        }
        .confirmationDialog(
            "Delete \"\(customMetricToDelete?.name ?? "")\"?",
            isPresented: $showDeleteCustomMetricConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Metric & All Its Data", role: .destructive) {
                if let metric = customMetricToDelete {
                    deleteCustomMetric(metric)
                }
            }
            Button("Cancel", role: .cancel) {
                customMetricToDelete = nil
            }
        } message: {
            Text("This will permanently delete this custom metric and all recorded data for it.")
        }
    }

    private func deleteCustomMetric(_ metric: CustomMetric) {
        // Delete all HealthRecords for this metric
        let metricType = metric.metricType
        let descriptor = FetchDescriptor<HealthRecord>(
            predicate: #Predicate { $0.metricType == metricType }
        )
        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
        }

        // Cancel any scheduled notifications
        NotificationManager.shared.cancelReminder(for: metricType)

        // Unregister from MetricRegistry
        MetricRegistry.unregisterCustomMetric(metricType)

        // Delete the CustomMetric itself
        modelContext.delete(metric)
        do {
            try modelContext.save()
        } catch {
            showSaveError = true
        }
        dataStore.refresh()
        customMetricToDelete = nil
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

            #if DEBUG
            Button {
                showSyntheticDataConfirmation = true
            } label: {
                Label("Generate Synthetic Data (90 days)", systemImage: "wand.and.stars")
                    .foregroundStyle(.purple)
            }
            .disabled(dataStore.recordCount > 0)
            #endif
        } header: {
            Text("Data Management")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("\"Delete All Records\" removes all health data. \"Reset Import History\" allows all Health records to be reimported.")
                Text("VitaSignals is not a medical device and does not provide medical advice, diagnosis, or treatment. Health data classifications are for informational purposes only. Always consult a qualified healthcare provider.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog("Delete All Records?", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
            Button("Delete All \(dataStore.recordCount) Records", role: .destructive) {
                let descriptor = FetchDescriptor<HealthRecord>()
                if let records = try? modelContext.fetch(descriptor) {
                    for record in records {
                        if let hkID = record.healthKitUUID {
                            modelContext.insert(DismissedHealthKitRecord(metricType: record.metricType, healthKitUUID: hkID))
                        }
                        modelContext.delete(record)
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        showSaveError = true
                    }
                    syncManager.resetSyncState(container: modelContext.container)
                    dataStore.refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all records and mark imported Health records so they won't be re-imported. Use \"Reset Import History\" afterward if you want to re-import them.")
        }
        .confirmationDialog("Reset Import History?", isPresented: $showResetDismissedConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                if let dismissed = try? modelContext.fetch(FetchDescriptor<DismissedHealthKitRecord>()) {
                    for d in dismissed { modelContext.delete(d) }
                    do {
                        try modelContext.save()
                    } catch {
                        showSaveError = true
                    }
                }
                syncManager.resetSyncState(container: modelContext.container)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK") {}
        } message: {
            Text("Changes could not be saved. Please try again. If the problem persists, restart the app.")
        }
        #if DEBUG
        .confirmationDialog("Generate Synthetic Data?", isPresented: $showSyntheticDataConfirmation, titleVisibility: .visible) {
            Button("Generate 90 Days of Data") {
                let count = SyntheticDataGenerator.generate(into: modelContext, days: 90)
                dataStore.refresh()
                syntheticDataCount = count
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create ~1500 realistic health records across 15+ metric types spanning the last 90 days. Use this to test the app in the simulator.")
        }
        .alert("Synthetic Data Generated", isPresented: Binding(
            get: { syntheticDataCount != nil },
            set: { if !$0 { syntheticDataCount = nil } }
        )) {
            Button("OK") { syntheticDataCount = nil }
        } message: {
            Text("\(syntheticDataCount ?? 0) records created across multiple health metrics.")
        }
        #endif
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

// MARK: - Profile View (Tab)

struct ProfileView: View {
    @ObservedObject var syncManager: HealthSyncManager
    @EnvironmentObject var dataStore: HealthDataStore
    @State private var exportRequest: ChartExportRequest?

    var body: some View {
        NavigationStack {
            List {
                ProfileSection(syncManager: syncManager)

                // Reports section
                Section {
                    NavigationLink {
                        ReportBuilderView(exportRequest: $exportRequest)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Generate PDF Report")
                                    .font(.subheadline)
                                Text("Create reports for your doctor or personal records")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .disabled(dataStore.recordCount == 0)
                } header: {
                    Text("Reports")
                } footer: {
                    if dataStore.recordCount == 0 {
                        Text("Add health records to generate reports.")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
