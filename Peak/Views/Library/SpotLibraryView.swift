import SwiftUI
import SwiftData

enum SpotSortOption: String, CaseIterable, Identifiable {
    case mostSurf = "Most Surfed"
    case recently = "Recently Surfed"
    case az = "A-Z"

    var id: String { rawValue }
}

struct SpotLibraryView: View {
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @State private var sortOption: SpotSortOption = .mostSurf
    @State private var showEditor = false
    @State private var showLimitAlert = false

    private var snapshots: [String: UsageSnapshot] {
        UsageMetricsCalculator.spotSnapshots(sessions: sessions)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SpotSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(14)
                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)

                    Text("\(spots.count) of \(Spot.maxCount) surf breaks saved")
                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                        .foregroundStyle(Theme.textMuted)

                    if spots.isEmpty {
                        EmptyStateView(
                            title: "No spots yet",
                            message: "Add your favorite breaks to see your surf history by spot.",
                            systemImage: "mappin.and.ellipse"
                        )
                    } else {
                        ForEach(sortedSpots) { spot in
                            NavigationLink {
                                SpotDetailView(spot: spot)
                            } label: {
                                SpotRowView(spot: spot, snapshot: snapshots[spot.key])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Spots")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if isLimitReached {
                        showLimitAlert = true
                    } else {
                        showEditor = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("spot.library.add")
            }
        }
        .sheet(isPresented: $showEditor) {
            SpotEditorView(mode: .new)
        }
        .alert("Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can save up to \(Spot.maxCount) surf breaks.")
        }
    }

    private var sortedSpots: [Spot] {
        switch sortOption {
        case .mostSurf:
            return spots.sorted { lhs, rhs in
                let lhsCount = snapshots[lhs.key]?.count ?? 0
                let rhsCount = snapshots[rhs.key]?.count ?? 0
                if lhsCount == rhsCount {
                    return lhs.name < rhs.name
                }
                return lhsCount > rhsCount
            }
        case .recently:
            return spots.sorted { lhs, rhs in
                let lhsDate = snapshots[lhs.key]?.lastUsed ?? .distantPast
                let rhsDate = snapshots[rhs.key]?.lastUsed ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.name < rhs.name
                }
                return lhsDate > rhsDate
            }
        case .az:
            return spots.sorted { $0.name < $1.name }
        }
    }

    private var isLimitReached: Bool {
        spots.count >= Spot.maxCount
    }
}

private struct SpotRowView: View {
    let spot: Spot
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spot.name)
                .font(.custom("Avenir Next", size: 16, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(spot.locationName?.trimmedNonEmpty ?? "No location saved")
                .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                .foregroundStyle(Theme.textMuted)

            HStack(spacing: 12) {
                Text("Times Surfed: \(snapshot?.count ?? 0)")
                Text("Avg Rating: \(averageRatingLabel)")
                Spacer()
                Text(lastUsedLabel)
            }
            .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .glassCard(cornerRadius: 20, tint: Theme.glassDimTint, isInteractive: true)
    }

    private var lastUsedLabel: String {
        guard let lastUsed = snapshot?.lastUsed else { return "Last: -" }
        return "Last: \(lastUsed.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var averageRatingLabel: String {
        let value = snapshot?.averageRating ?? 0
        if value == 0 { return "-" }
        return String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        SpotLibraryView()
            .modelContainer(PreviewData.container)
    }
}
