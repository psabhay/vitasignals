import SwiftUI

struct AddRecordPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(MetricCategory.allCases) { category in
                        let defs = MetricRegistry.definitions(for: category)
                        if !defs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(category.rawValue, systemImage: category.icon)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(category.color)
                                    .padding(.horizontal)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(defs, id: \.type) { def in
                                        Button {
                                            onSelect(def.type)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: def.icon)
                                                    .font(.title3)
                                                    .foregroundStyle(def.color)
                                                    .frame(width: 32, height: 32)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(def.name)
                                                        .font(.subheadline.bold())
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)
                                                    Text(def.unit)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()
                                            }
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(def.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .strokeBorder(def.color.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Add Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
