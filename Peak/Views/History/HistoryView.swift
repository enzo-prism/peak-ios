import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @State private var filters = HistoryFilters()
    @State private var showFilters = false
    @State private var showNewSession = false
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var groups: [(key: Date, value: [SurfSession])] = []
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
                } else if groups.isEmpty && isNarrowed {
                    EmptyStateView(
                        title: "No matches",
                        message: "Try adjusting your search or filters to see more sessions.",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } else {
                    List {
                        ForEach(groups, id: \.key) { group in
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
            .onAppear { recompute() }
            .onChange(of: sessions) { _, _ in recompute() }
            .onChange(of: filters) { _, _ in recompute() }
            .task(id: searchText) {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                debouncedQuery = searchText
                recompute()
            }
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

    private var isNarrowed: Bool {
        filters.isActive || !debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Filtering + grouping over the whole history is cached here and refreshed only when its
    /// inputs change (sessions, filters, debounced search) — not on every body evaluation.
    private func recompute() {
        let query = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = sessions.filter { filters.matches(session: $0) && matchesSearch($0, query: query) }
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfMonth }
        groups = grouped.keys.sorted(by: >).map { key in
            (key: key, value: grouped[key, default: []].sorted { $0.date > $1.date })
        }
    }

    private func matchesSearch(_ session: SurfSession, query: String) -> Bool {
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
