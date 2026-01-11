import SwiftUI
import SwiftData

enum QuiverSortOption: String, CaseIterable, Identifiable {
    case mostUsed = "Most Used"
    case recentlyUsed = "Recently Used"
    case az = "A-Z"

    var id: String { rawValue }
}

struct QuiverView: View {
    @Query(sort: \Gear.name) private var gear: [Gear]
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]

    @State private var searchText = ""
    @State private var sortOption: QuiverSortOption = .mostUsed
    @State private var showArchived = false
    @State private var showEditor = false
    @State private var cachedSnapshots: [String: GearUsageSnapshot] = [:]

    private var snapshots: [String: GearUsageSnapshot] {
        cachedSnapshots
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterCard

                    if visibleGear.isEmpty {
                    EmptyStateView(
                        title: emptyStateTitle,
                        message: emptyStateMessage,
                        imageName: "surfboard"
                    )
                    } else {
                        ForEach(GearKind.allCases) { kind in
                            let items = sortedGear(for: kind)
                            if !items.isEmpty {
                                gearSection(kind: kind, items: items)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Quiver")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("quiver.add")
            }
        }
        .searchable(text: $searchText, prompt: "Search gear")
        .sheet(isPresented: $showEditor) {
            GearEditorView(mode: .new)
        }
        .onAppear {
            refreshSnapshots()
        }
        .onChange(of: sessions) { _, _ in
            refreshSnapshots()
        }
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sort", selection: $sortOption) {
                ForEach(QuiverSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show archived", isOn: $showArchived)
                .toggleStyle(SwitchToggleStyle(tint: Theme.surfGreen))
        }
        .padding(14)
        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)
    }

    private func gearSection(kind: GearKind, items: [Gear]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.pluralLabel.uppercased())
                .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                .foregroundStyle(Theme.textMuted)

            ForEach(items) { item in
                NavigationLink {
                    GearDetailView(gear: item)
                } label: {
                    QuiverGearRow(gear: item, snapshot: snapshots[item.key])
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityIdentifier("quiver.row")
            }
        }
    }

    private var visibleGear: [Gear] {
        let filtered = gear.filter { showArchived || !$0.isArchived }
        guard let query = searchText.trimmedNonEmpty else { return filtered }
        return filtered.filter { item in
            item.name.localizedCaseInsensitiveContains(query)
                || (item.brand?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.model?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func sortedGear(for kind: GearKind) -> [Gear] {
        let items = visibleGear.filter { $0.kind == kind }
        switch sortOption {
        case .mostUsed:
            return items.sorted { lhs, rhs in
                let lhsCount = snapshots[lhs.key]?.count ?? 0
                let rhsCount = snapshots[rhs.key]?.count ?? 0
                if lhsCount == rhsCount {
                    return lhs.name < rhs.name
                }
                return lhsCount > rhsCount
            }
        case .recentlyUsed:
            return items.sorted { lhs, rhs in
                let lhsDate = snapshots[lhs.key]?.lastUsed ?? .distantPast
                let rhsDate = snapshots[rhs.key]?.lastUsed ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.name < rhs.name
                }
                return lhsDate > rhsDate
            }
        case .az:
            return items.sorted { $0.name < $1.name }
        }
    }

    private var emptyStateTitle: String {
        if searchText.trimmedNonEmpty != nil {
            return "No matching gear"
        }
        return "No gear yet"
    }

    private var emptyStateMessage: String {
        if searchText.trimmedNonEmpty != nil {
            return "Try a different search or clear your filters."
        }
        return "Add boards, wetsuits, fins, and more to build your quiver."
    }

    private func refreshSnapshots() {
        cachedSnapshots = GearUsageCalculator.snapshots(sessions: sessions)
    }
}

private struct QuiverGearRow: View {
    let gear: Gear
    let snapshot: GearUsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gear.name)
                        .font(.custom("Avenir Next", size: 16, relativeTo: .headline).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(gear.profileSummary ?? gear.kind.label)
                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                        .foregroundStyle(Theme.textMuted)
                }

                Spacer()

                if gear.isArchived {
                    Text("Archived")
                        .font(.custom("Avenir Next", size: 11, relativeTo: .caption).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                }
            }

            HStack(spacing: 12) {
                Text("Times used: \(snapshot?.count ?? 0)")
                Spacer()
                Text(lastUsedLabel)
            }
            .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 20, tint: Theme.glassDimTint, isInteractive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("quiver.row")
    }

    private var lastUsedLabel: String {
        guard let lastUsed = snapshot?.lastUsed else { return "Last used: -" }
        return "Last used: \(lastUsed.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

#Preview {
    NavigationStack {
        QuiverView()
            .modelContainer(PreviewData.container)
    }
}
