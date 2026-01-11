import SwiftUI
import SwiftData

enum BuddySortOption: String, CaseIterable, Identifiable {
    case mostSurf = "Most Sessions"
    case recently = "Recently Surfed"
    case az = "A-Z"

    var id: String { rawValue }
}

struct BuddyLibraryView: View {
    @Query(sort: \Buddy.name) private var buddies: [Buddy]
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @State private var sortOption: BuddySortOption = .mostSurf
    @State private var showEditor = false

    private var snapshots: [String: UsageSnapshot] {
        UsageMetricsCalculator.buddySnapshots(sessions: sessions)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(BuddySortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(14)
                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: true)

                    if buddies.isEmpty {
                        EmptyStateView(
                            title: "No buddies yet",
                            message: "Add your surf crew to see your shared sessions.",
                            systemImage: "person.2"
                        )
                    } else {
                        ForEach(sortedBuddies) { buddy in
                            NavigationLink {
                                BuddyDetailView(buddy: buddy)
                            } label: {
                                BuddyRowView(buddy: buddy, snapshot: snapshots[buddy.key])
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("buddy.row")
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Buddies")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("buddy.library.add")
            }
        }
        .sheet(isPresented: $showEditor) {
            BuddyEditorView(mode: .new)
        }
    }

    private var sortedBuddies: [Buddy] {
        switch sortOption {
        case .mostSurf:
            return buddies.sorted { lhs, rhs in
                let lhsCount = snapshots[lhs.key]?.count ?? 0
                let rhsCount = snapshots[rhs.key]?.count ?? 0
                if lhsCount == rhsCount {
                    return lhs.name < rhs.name
                }
                return lhsCount > rhsCount
            }
        case .recently:
            return buddies.sorted { lhs, rhs in
                let lhsDate = snapshots[lhs.key]?.lastUsed ?? .distantPast
                let rhsDate = snapshots[rhs.key]?.lastUsed ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.name < rhs.name
                }
                return lhsDate > rhsDate
            }
        case .az:
            return buddies.sorted { $0.name < $1.name }
        }
    }
}

private struct BuddyRowView: View {
    let buddy: Buddy
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(buddy.name)
                .font(.custom("Avenir Next", size: 16, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                Text("Sessions: \(snapshot?.count ?? 0)")
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
        .accessibilityIdentifier("buddy.row")
    }

    private var lastUsedLabel: String {
        guard let lastUsed = snapshot?.lastUsed else { return "Last: -" }
        return "Last: \(lastUsed.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

#Preview {
    NavigationStack {
        BuddyLibraryView()
            .modelContainer(PreviewData.container)
    }
}
