import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies, \.media]))
    private var sessions: [SurfSession]
    @State private var filters = HistoryFilters()
    @State private var showFilters = false
    @State private var showNewSession = false
    @State private var editingSession: SurfSession?
    @State private var sessionPendingDelete: SurfSession?
    @State private var deletionCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if sessions.isEmpty {
                    EmptyStateView(
                        title: "No sessions yet 🌊",
                        message: "Log your first surf and your timeline will show up here.",
                        systemImage: "wave.3.right"
                    )
                } else if filteredSessions.isEmpty {
                    EmptyStateView(
                        title: "No matches",
                        message: "Try adjusting your filters to see more sessions.",
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
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            sessionPendingDelete = session
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            editingSession = session
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Color(uiColor: .systemGray))
                                    }
                                    .contextMenu {
                                        Button {
                                            editingSession = session
                                        } label: {
                                            Label("Edit Session", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            sessionPendingDelete = session
                                        } label: {
                                            Label("Delete Session", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(group.key.monthTitle)
                                    .font(.caption.weight(.semibold))
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
        .sheet(item: $editingSession) { session in
            SessionEditorView(mode: .edit(session))
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: Binding(
                get: { sessionPendingDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        sessionPendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deletePendingSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the session and its media.")
        }
        .sensoryFeedback(.success, trigger: deletionCount)
    }

    private func deletePendingSession() {
        guard let session = sessionPendingDelete else { return }
        sessionPendingDelete = nil
        SessionMediaStore.deleteStoredMedia(for: session.media)
        modelContext.delete(session)
        deletionCount += 1
    }

    private var filteredSessions: [SurfSession] {
        sessions.filter { filters.matches(session: $0) }
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
