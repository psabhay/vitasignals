import SwiftUI
import SwiftData

struct DataBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HealthRecord.timestamp, order: .reverse) private var allRecords: [HealthRecord]
    @State private var selectedCategory: MetricCategory?
    @State private var selectedMetricType: String?
    @State private var selectedRecord: HealthRecord?
    @State private var activeSheet: DataSheet?
    @State private var addMetricType: String = MetricType.bloodPressure

    private enum DataSheet: Identifiable {
        case metricPicker
        case addForm(String)
        case recordDetail(HealthRecord)
        var id: String {
            switch self {
            case .metricPicker: return "picker"
            case .addForm(let type): return "add-\(type)"
            case .recordDetail(let r): return "detail-\(r.id)"
            }
        }
    }

    private var filteredRecords: [HealthRecord] {
        var records = allRecords
        if let metricType = selectedMetricType {
            records = records.filter { $0.metricType == metricType }
        } else if let category = selectedCategory {
            let types = MetricRegistry.definitions(for: category).map(\.type)
            records = records.filter { types.contains($0.metricType) }
        }
        return records
    }

    private var groupedRecords: [(String, [HealthRecord])] {
        let grouped = Dictionary(grouping: filteredRecords) { $0.formattedDateOnly }
        return grouped.sorted { lhs, rhs in
            guard let lDate = lhs.value.first?.timestamp,
                  let rDate = rhs.value.first?.timestamp else { return false }
            return lDate > rDate
        }
    }

    private var availableMetricTypes: [String] {
        Array(Set(allRecords.map(\.metricType))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilterBar
                Group {
                    if filteredRecords.isEmpty {
                        ContentUnavailableView(
                            "No Records",
                            systemImage: "list.bullet.clipboard",
                            description: Text(selectedMetricType != nil || selectedCategory != nil
                                ? "No records match this filter"
                                : "Your health records will appear here")
                        )
                    } else {
                        List {
                            ForEach(groupedRecords, id: \.0) { date, dayRecords in
                                Section(date) {
                                    ForEach(dayRecords) { record in
                                        Button {
                                            activeSheet = .recordDetail(record)
                                        } label: {
                                            RecordRowView(record: record)
                                        }
                                        .tint(.primary)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                deleteRecord(record)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                activeSheet = .recordDetail(record)
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .withProfileButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .metricPicker
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .metricPicker:
                    AddRecordPickerSheet { selectedType in
                        activeSheet = nil
                        addMetricType = selectedType
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activeSheet = .addForm(selectedType)
                        }
                    }
                case .addForm(let type):
                    AddHealthRecordView(metricType: type)
                case .recordDetail(let record):
                    RecordDetailView(record: record)
                }
            }
        }
    }

    // MARK: - Category Filter Bar

    @ViewBuilder
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedCategory == nil && selectedMetricType == nil) {
                    selectedCategory = nil
                    selectedMetricType = nil
                }

                ForEach(MetricCategory.allCases) { category in
                    let hasData = !MetricRegistry.definitions(for: category)
                        .filter { def in allRecords.contains { $0.metricType == def.type } }
                        .isEmpty

                    if hasData {
                        FilterChip(
                            title: category.rawValue,
                            icon: category.icon,
                            color: category.color,
                            isSelected: selectedCategory == category
                        ) {
                            if selectedCategory == category {
                                selectedCategory = nil
                            } else {
                                selectedCategory = category
                                selectedMetricType = nil
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)

        // Metric type filter (when a category is selected)
        if let category = selectedCategory {
            let metricDefs = MetricRegistry.definitions(for: category)
                .filter { def in allRecords.contains { $0.metricType == def.type } }

            if metricDefs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All \(category.rawValue)", isSelected: selectedMetricType == nil) {
                            selectedMetricType = nil
                        }
                        ForEach(metricDefs, id: \.type) { def in
                            FilterChip(
                                title: def.name,
                                icon: def.icon,
                                color: def.color,
                                isSelected: selectedMetricType == def.type
                            ) {
                                selectedMetricType = selectedMetricType == def.type ? nil : def.type
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func deleteRecord(_ record: HealthRecord) {
        if let hkID = record.healthKitUUID {
            modelContext.insert(DismissedHealthKitRecord(metricType: record.metricType, healthKitUUID: hkID))
        }
        modelContext.delete(record)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    var color: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isSelected ? color : .primary)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? color : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Record Row

struct RecordRowView: View {
    let record: HealthRecord

    private var definition: MetricDefinition? {
        MetricRegistry.definition(for: record.metricType)
    }

    var body: some View {
        HStack {
            if let def = definition {
                Image(systemName: def.icon)
                    .foregroundStyle(def.color)
                    .font(.caption)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.formattedPrimaryValue)
                        .font(.headline.monospacedDigit())
                    if let def = definition {
                        Text(def.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if record.isFromHealthKit {
                        Image(systemName: "heart.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                }

                HStack(spacing: 8) {
                    if record.metricType == MetricType.bloodPressure, let ctx = record.bpActivityContext {
                        Label(ctx.rawValue, systemImage: ctx.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let def = definition {
                        Text(def.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.formattedTimeOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if record.metricType == MetricType.bloodPressure {
                    CategoryBadge(category: record.bpCategory)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
