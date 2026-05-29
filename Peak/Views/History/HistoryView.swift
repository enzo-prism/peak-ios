import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @State private var filters = HistoryFilters()
    @State private var showFilters = false
    @State private var showNewSession = false
    @State private var searchText = ""
    @State private var deleteFeedbackTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if sessions.isEmpty {
                    EmptyStateView(
                        title: "No sessions yet",
                        message: "Log your first surf and your timeline will show up here.",
                        systemImage: "wave.3.right"
                    )
                } else if filteredSessions.isEmpty {
                    EmptyStateView(
                        title: "No matches",
                        message: "Try adjusting your search or filters to see more sessions.",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } else {
                    List {
                        ForEach(groupedSessions, id: \.key) { group in
                            Section {
                                ForEach(group.value) { session in
                                    NavigationLink {
                                        SessionDetailView(session: session)
                                    } label: {
                                        SessionRowView(session: session)
                                    }
                                    .accessibilityIdentifier(sessionRowIdentifier(for: session))
                                    .buttonStyle(PressFeedbackButtonStyle())
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 6)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            delete(session)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(group.key.monthTitle)
                                    .font(.peak(12, relativeTo: .caption).weight(.semibold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("history.list")
                }
            }
            .searchable(text: $searchText, prompt: "Search spot, gear, buddy, or notes")
            .sensoryFeedback(.success, trigger: deleteFeedbackTrigger)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewSession = true
                    } label: {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            HistoryFilterSheetView(filters: $filters)
        }
        .sheet(isPresented: $showNewSession) {
            SessionEditorView(mode: .new)
        }
    }

    private var filteredSessions: [SurfSession] {
        sessions.filter { filters.matches(session: $0) && matchesSearch($0) }
    }

    private func matchesSearch(_ session: SurfSession) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if session.spot?.name.localizedCaseInsensitiveContains(query) == true { return true }
        if session.notes.localizedCaseInsensitiveContains(query) { return true }
        if session.gear.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) { return true }
        if session.buddies.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) { return true }
        return false
    }

    private func delete(_ session: SurfSession) {
        SessionMediaStore.deleteStoredMedia(for: session.media)
        modelContext.delete(session)
        deleteFeedbackTrigger += 1
    }

    private var groupedSessions: [(key: Date, value: [SurfSession])] {
        let grouped = Dictionary(grouping: filteredSessions) { $0.date.startOfMonth }
        return grouped.keys.sorted(by: >).map { key in
            let values = grouped[key, default: []].sorted { $0.date > $1.date }
            return (key: key, value: values)
        }
    }

    private func sessionRowIdentifier(for session: SurfSession) -> String {
        guard let marker = TestingDefaults.sessionMarker,
              session.notes.contains(marker) else {
            return "history.row"
        }
        return "history.row.test-marker"
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewData.container)
}
