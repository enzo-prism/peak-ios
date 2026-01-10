import SwiftUI
import SwiftData

struct HistoryFilterSheetView: View {
    @Binding var filters: HistoryFilters
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \Buddy.name) private var buddies: [Buddy]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    Section {
                        FilterRow(title: "All spots", isSelected: filters.spot == nil) {
                            filters.spot = nil
                        }
                        ForEach(spots) { spot in
                            FilterRow(title: spot.name, isSelected: filters.spot?.persistentModelID == spot.persistentModelID) {
                                filters.spot = spot
                            }
                        }
                    } header: {
                        headerLabel("Spot")
                    }

                    Section {
                        FilterRow(title: "All gear", isSelected: filters.gear == nil) {
                            filters.gear = nil
                        }
                        ForEach(gear) { item in
                            FilterRow(title: "\(item.name) (\(item.kind.label))", isSelected: filters.gear?.persistentModelID == item.persistentModelID) {
                                filters.gear = item
                            }
                        }
                    } header: {
                        headerLabel("Gear")
                    }

                    Section {
                        FilterRow(title: "Everyone", isSelected: filters.buddy == nil) {
                            filters.buddy = nil
                        }
                        ForEach(buddies) { buddy in
                            FilterRow(title: buddy.name, isSelected: filters.buddy?.persistentModelID == buddy.persistentModelID) {
                                filters.buddy = buddy
                            }
                        }
                    } header: {
                        headerLabel("Buddies")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        filters.clear()
                    }
                    .disabled(!filters.isActive)
                }
            }
        }
    }

    @ViewBuilder
    private func headerLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
            .foregroundStyle(Theme.textMuted)
    }
}

private struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.custom("Avenir Next", size: 15, relativeTo: .body))
                    .foregroundStyle(isSelected ? Theme.textInverse : Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.textInverse)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .glassCard(cornerRadius: 16, tint: isSelected ? Theme.glassStrongTint : Theme.glassDimTint, isInteractive: true)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
