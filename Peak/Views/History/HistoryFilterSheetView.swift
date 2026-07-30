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
                        FilterRow(title: "All spots", isSelected: filters.spots.isEmpty) {
                            filters.spots.removeAll()
                        }
                        ForEach(spots) { spot in
                            FilterRow(title: spot.name, isSelected: filters.spots.contains(spot)) {
                                filters.toggleSpot(spot)
                            }
                        }
                    } header: {
                        headerLabel("Spots")
                    }

                    Section {
                        FilterRow(title: "All gear", isSelected: filters.gear.isEmpty) {
                            filters.gear.removeAll()
                        }
                        ForEach(gear) { item in
                            FilterRow(title: "\(item.name) (\(item.kind.label))", isSelected: filters.gear.contains(item)) {
                                filters.toggleGear(item)
                            }
                        }
                    } header: {
                        headerLabel("Gear")
                    }

                    Section {
                        FilterRow(title: "Everyone", isSelected: filters.buddies.isEmpty) {
                            filters.buddies.removeAll()
                        }
                        ForEach(buddies) { buddy in
                            FilterRow(title: buddy.name, isSelected: filters.buddies.contains(buddy)) {
                                filters.toggleBuddy(buddy)
                            }
                        }
                    } header: {
                        headerLabel("Buddies")
                    }

                    Section {
                        minimumRatingRow
                    } header: {
                        headerLabel("Minimum rating")
                    }

                    Section {
                        ForEach(HistoryFilters.DateRange.allCases) { range in
                            FilterRow(title: range.label, isSelected: filters.dateRange == range) {
                                filters.dateRange = range
                            }
                        }
                    } header: {
                        headerLabel("Date range")
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
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear") {
                        filters.clear()
                    }
                    .disabled(!filters.isActive)
                    .accessibilityIdentifier("history.filters.clear")
                }
            }
        }
        .tint(Theme.textPrimary)
    }

    private var minimumRatingRow: some View {
        HStack {
            RatingPickerView(rating: $filters.minimumRating)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Shows sessions rated at least this many stars.")
        .accessibilityIdentifier("history.filters.minimumRating")
    }

    @ViewBuilder
    private func headerLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
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
                    .font(.body)
                    .foregroundStyle(isSelected ? Theme.textInverse : Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.textInverse)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .glassCard(cornerRadius: Theme.Radius.input, tint: isSelected ? Theme.glassStrongTint : Theme.glassDimTint, isInteractive: true)
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
