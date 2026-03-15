import SwiftUI
import SwiftData

struct HealthImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingReadings: [BPReading]
    @Query private var dismissedIDs: [DismissedHealthKitID]

    @StateObject private var hkManager = HealthKitManager()
    @State private var importSince: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
    @State private var selectedIDs: Set<String> = []
    @State private var contextForAll: ActivityContext = .atRest
    @State private var importedCount = 0
    @State private var showImportDone = false

    private var excludedHealthKitIDs: Set<String> {
        var ids = Set(existingReadings.compactMap(\.healthKitID))
        for d in dismissedIDs { ids.insert(d.healthKitID) }
        return ids
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hkManager.isAuthorized {
                    authorizationView
                } else if hkManager.isLoading {
                    loadingView
                } else if hkManager.fetchedReadings.isEmpty && hkManager.errorMessage == nil {
                    emptyOrFetchView
                } else {
                    reviewList
                }
            }
            .navigationTitle("Import from Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Imported \(importedCount) Readings", isPresented: $showImportDone) {
                Button("OK") { dismiss() }
            } message: {
                Text("The readings have been added to your BP Logger history. You can edit the context for each reading from the History tab.")
            }
        }
    }

    private var authorizationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60))
                .foregroundStyle(.pink)

            Text("Connect Apple Health")
                .font(.title2.bold())

            Text("BP Logger can import blood pressure readings from Apple Health, including readings synced by ViHealth from your Wellue device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = hkManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                Task { await hkManager.requestAuthorization() }
            } label: {
                Label("Allow Health Access", systemImage: "heart.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.pink, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Fetching readings from Apple Health...")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyOrFetchView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.heart")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Fetch BP Readings")
                .font(.title3.bold())

            Text("Choose how far back to look for readings. Already-imported readings will be skipped.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            DatePicker("Import since", selection: $importSince, displayedComponents: .date)
                .padding(.horizontal, 40)

            if let error = hkManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    await hkManager.fetchReadings(since: importSince, excludedHealthKitIDs: excludedHealthKitIDs)
                    selectedIDs = Set(hkManager.fetchedReadings.map(\.id))
                }
            } label: {
                Label("Fetch Readings", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)

            if hkManager.fetchedReadings.isEmpty && hkManager.errorMessage == nil {
                Text("No new readings found for this period")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private var reviewList: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack {
                        Text("Found \(hkManager.fetchedReadings.count) new readings")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(selectedIDs.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        if selectedIDs.count == hkManager.fetchedReadings.count {
                            Button("Deselect All") { selectedIDs.removeAll() }
                        } else {
                            Button("Select All") { selectedIDs = Set(hkManager.fetchedReadings.map(\.id)) }
                        }
                    }
                    .font(.subheadline)
                }

                Section("Default Context for Imported Readings") {
                    Picker("Context", selection: $contextForAll) {
                        ForEach(ActivityContext.allCases) { context in
                            Label(context.rawValue, systemImage: context.icon).tag(context)
                        }
                    }
                }

                Section("Readings") {
                    ForEach(hkManager.fetchedReadings) { reading in
                        Button {
                            toggleSelection(reading.id)
                        } label: {
                            HStack {
                                Image(systemName: selectedIDs.contains(reading.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(reading.id) ? Color.accentColor : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(reading.formattedReading)
                                            .font(.headline.monospacedDigit())
                                        if let pulse = reading.pulse {
                                            Label("\(pulse)", systemImage: "heart.fill")
                                                .font(.caption)
                                                .foregroundStyle(.pink)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        Text(reading.formattedDate)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("via \(reading.source)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()
                                CategoryBadge(category: reading.category)
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section {
                    Text("Tip: Deselect readings that belong to family members who used the same device. You can also delete or edit any reading later from the History tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                importSelected()
            } label: {
                Text("Import \(selectedIDs.count) Readings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedIDs.isEmpty ? .gray : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .disabled(selectedIDs.isEmpty)
            .padding()
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func importSelected() {
        var count = 0
        for reading in hkManager.fetchedReadings where selectedIDs.contains(reading.id) {
            let bpReading = BPReading(
                systolic: reading.systolic,
                diastolic: reading.diastolic,
                pulse: reading.pulse ?? 0,
                timestamp: reading.timestamp,
                activityContext: contextForAll,
                notes: "Imported from Apple Health (via \(reading.source))",
                healthKitID: reading.id
            )
            modelContext.insert(bpReading)
            count += 1
        }
        importedCount = count
        showImportDone = true
    }
}
