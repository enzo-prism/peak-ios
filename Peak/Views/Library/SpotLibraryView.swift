import SwiftUI
import SwiftData

enum SpotSortOption: String, CaseIterable, Identifiable {
    case mostSurf = "Most Surfed"
    case recently = "Recently Surfed"
    case az = "A-Z"

    var id: String { rawValue }
}

struct SpotLibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable private var navigation = PeakNavigationCoordinator.shared
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot]))
    private var sessions: [SurfSession]
    @State private var sortOption: SpotSortOption = .mostSurf
    @State private var showEditor = false
    @State private var showLimitAlert = false
    @State private var snapshots: [String: UsageSnapshot] = [:]
    @State private var openedSpot: PeakEntityRef?

    private var usesSplitNavigation: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitNavigation {
                NavigationSplitView {
                    spotsRoot
                        .navigationTitle("Spots")
                        .toolbar { spotsToolbar }
                } detail: {
                    if let ref = openedSpot, let spot = spotMatching(ref) {
                        SpotDetailView(spot: spot)
                    } else {
                        ContentUnavailableView("Select a spot", systemImage: "mappin.and.ellipse")
                    }
                }
            } else {
                spotsRoot
                    .navigationTitle("Spots")
                    .toolbar { spotsToolbar }
                    .navigationDestination(item: $openedSpot) { ref in
                        spotDetail(for: ref)
                    }
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
        .onAppear {
            snapshots = UsageMetricsCalculator.spotSnapshots(sessions: sessions)
            consumePendingSpotIfNeeded()
        }
        .onChange(of: sessions) { _, _ in
            snapshots = UsageMetricsCalculator.spotSnapshots(sessions: sessions)
        }
        .onChange(of: navigation.pendingSpotID) { _, _ in
            consumePendingSpotIfNeeded()
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            consumePendingSpotIfNeeded()
        }
    }

    private var spotsRoot: some View {
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
                    .padding(Theme.Spacing.l)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)

                    Text("\(spots.count) of \(Spot.maxCount) surf breaks saved")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)

                    if spots.isEmpty {
                        EmptyStateView(
                            title: "No spots yet",
                            message: "Add your favorite breaks to see your surf history by spot.",
                            systemImage: "mappin.and.ellipse"
                        )
                    } else {
                        ForEach(sortedSpots) { spot in
                            spotRow(spot)
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("spot.row")
                        }
                    }
                }
                .padding()
            }
        }
    }

    @ToolbarContentBuilder
    private var spotsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink {
                SpotsMapView()
            } label: {
                Image(systemName: "map")
                    .accessibilityLabel("Spot Map")
            }
            .accessibilityIdentifier("spot.library.map")
            .disabled(spots.allSatisfy { $0.coordinate == nil })
        }
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
            .accessibilityLabel("Add surf break")
            .accessibilityIdentifier("spot.library.add")
        }
    }

    @ViewBuilder
    private func spotRow(_ spot: Spot) -> some View {
        if usesSplitNavigation {
            Button {
                openedSpot = PeakEntityRef(id: SessionIntentQueries.identifier(for: spot))
            } label: {
                SpotRowView(spot: spot, snapshot: snapshots[spot.key])
            }
        } else {
            NavigationLink {
                SpotDetailView(spot: spot)
            } label: {
                SpotRowView(spot: spot, snapshot: snapshots[spot.key])
            }
        }
    }

    @ViewBuilder
    private func spotDetail(for ref: PeakEntityRef) -> some View {
        if let spot = spotMatching(ref) {
            SpotDetailView(spot: spot)
        }
    }

    private func spotMatching(_ ref: PeakEntityRef) -> Spot? {
        spots.first { SessionIntentQueries.identifier(for: $0) == ref.id }
    }

    /// iOS 18's Spots tab is always in the tab shell, so it owns the pending
    /// id. On iOS 17 the coordinator lands on More and `MoreView` pushes.
    private func consumePendingSpotIfNeeded() {
        if #available(iOS 18.0, *) {
            guard let id = navigation.pendingSpotID else { return }
            _ = navigation.consumePendingSpot()
            openedSpot = PeakEntityRef(id: id)
            return
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
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(spot.locationName?.trimmedNonEmpty ?? "No location saved")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)

            HStack(spacing: 12) {
                Text("Times Surfed: \(snapshot?.count ?? 0)")
                Text("Avg Rating: \(averageRatingLabel)")
                Spacer()
                Text(lastUsedLabel)
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.l)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("spot.row")
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
