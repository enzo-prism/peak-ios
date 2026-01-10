import SwiftUI
import SwiftData

enum GearSortOption: String, CaseIterable, Identifiable {
    case mostUsed = "Most Used"
    case recentlyUsed = "Recently Used"
    case az = "A-Z"

    var id: String { rawValue }
}

enum GearKindFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case board = "Boards"
    case wetsuit = "Wetsuits"
    case fins = "Fins"
    case leash = "Leash"
    case other = "Other"

    var id: String { rawValue }

    var kind: GearKind? {
        switch self {
        case .all: return nil
        case .board: return .board
        case .wetsuit: return .wetsuit
        case .fins: return .fins
        case .leash: return .leash
        case .other: return .other
        }
    }
}

struct GearLibraryView: View {
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @State private var sortOption: GearSortOption = .mostUsed
    @State private var filter: GearKindFilter = .all
    @State private var showEditor = false

    private var snapshots: [String: UsageSnapshot] {
        UsageMetricsCalculator.gearSnapshots(sessions: sessions)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterBar

                    if filteredGear.isEmpty {
                        EmptyStateView(
                            title: "No gear yet",
                            message: "Add boards, wetsuits, fins, and more to build your library.",
                            systemImage: "wrench.and.screwdriver"
                        )
                    } else {
                        ForEach(sortedGear) { item in
                            NavigationLink {
                                GearDetailView(gear: item)
                            } label: {
                                GearRowView(gear: item, snapshot: snapshots[item.key])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Gear")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            GearEditorView(mode: .new)
        }
    }

    private var filteredGear: [Gear] {
        let activeGear = gear.filter { !$0.isArchived }
        guard let kind = filter.kind else { return activeGear }
        return activeGear.filter { $0.kind == kind }
    }

    private var sortedGear: [Gear] {
        let filtered = filteredGear
        switch sortOption {
        case .mostUsed:
            return filtered.sorted { lhs, rhs in
                let lhsCount = snapshots[lhs.key]?.count ?? 0
                let rhsCount = snapshots[rhs.key]?.count ?? 0
                if lhsCount == rhsCount {
                    return lhs.name < rhs.name
                }
                return lhsCount > rhsCount
            }
        case .recentlyUsed:
            return filtered.sorted { lhs, rhs in
                let lhsDate = snapshots[lhs.key]?.lastUsed ?? .distantPast
                let rhsDate = snapshots[rhs.key]?.lastUsed ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.name < rhs.name
                }
                return lhsDate > rhsDate
            }
        case .az:
            return filtered.sorted { $0.name < $1.name }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sort", selection: $sortOption) {
                ForEach(GearSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Kind", selection: $filter) {
                ForEach(GearKindFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
    }
}

private struct GearRowView: View {
    let gear: Gear
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gear.name)
                        .font(.custom("Avenir Next", size: 16, relativeTo: .headline).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(gear.kind.label)
                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Text("\(snapshot?.count ?? 0)x")
                    .font(.custom("Avenir Next", size: 16, relativeTo: .headline).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            HStack(spacing: 12) {
                Label("Times Used", systemImage: "chart.bar")
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                Text("\(snapshot?.count ?? 0)")
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                Spacer()
                Text(lastUsedLabel)
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.textMuted)
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .glassCard(cornerRadius: 20, tint: Theme.glassDimTint, isInteractive: true)
    }

    private var lastUsedLabel: String {
        guard let lastUsed = snapshot?.lastUsed else { return "Last used: -"}
        return "Last used: \(lastUsed.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

#Preview {
    NavigationStack {
        GearLibraryView()
            .modelContainer(PreviewData.container)
    }
}
