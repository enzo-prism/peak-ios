import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot, \.gear, \.buddies, \.media]))
    private var sessions: [SurfSession]
    @State private var filters = HistoryFilters()
    @State private var searchText = ""
    /// Search text applied to the list, trailing `searchText` by ~275ms so we
    /// don't re-filter on every keystroke.
    @State private var debouncedSearchText = ""
    /// Memoized filter + group result; recomputed only in `refreshResults()`
    /// (sessions/filters/debounced-search changes), not on every body pass.
    @State private var groupedSessions: [(key: Date, value: [SurfSession])] = []
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
                        title: "No sessions yet",
                        message: "Log your first surf and your timeline will show up here.",
                        systemImage: "wave.3.right"
                    )
                } else {
                    VStack(spacing: 0) {
                        if hasActiveCriteria {
                            activeFiltersRow
                        }

                        if groupedSessions.isEmpty && hasActiveCriteria {
                            Spacer()
                            noMatchesState
                            Spacer()
                        } else {
                            sessionList
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("Filters", systemImage: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .contentTransition(.symbolEffect(.replace))
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
            .searchable(text: $searchText, prompt: "Spots, notes, gear, buddies")
            .searchMinimizeBehavior()
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
        .task(id: searchText) {
            if searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(275))
            } catch {
                return
            }
            debouncedSearchText = searchText
        }
        .onAppear {
            refreshResults()
        }
        .onChange(of: sessionsStamp) { _, _ in
            refreshResults()
        }
        .onChange(of: filters) { _, _ in
            refreshResults()
        }
        .onChange(of: debouncedSearchText) { _, _ in
            refreshResults()
        }
    }

    // MARK: - List

    private var sessionList: some View {
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

    // MARK: - Active filter chips

    private var hasActiveCriteria: Bool {
        filters.isActive || !searchText.isEmpty
    }

    private var activeFiltersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    clearAllCriteria()
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textInverse)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassCapsule(tint: Theme.glassStrongTint, isInteractive: true)
                }
                .buttonStyle(PressFeedbackButtonStyle())
                .accessibilityLabel("Clear all filters and search")
                .accessibilityIdentifier("history.filters.clearAll")

                if !searchText.isEmpty {
                    removableChip(label: "\u{201C}\(searchText)\u{201D}", systemImage: "magnifyingglass") {
                        searchText = ""
                    }
                }
                ForEach(filters.spots.sorted { $0.name < $1.name }, id: \.persistentModelID) { spot in
                    removableChip(label: spot.name, systemImage: "mappin.and.ellipse") {
                        filters.spots.remove(spot)
                    }
                }
                ForEach(filters.gear.sorted { $0.name < $1.name }, id: \.persistentModelID) { item in
                    removableChip(label: item.name, systemImage: item.kind.systemImage) {
                        filters.gear.remove(item)
                    }
                }
                ForEach(filters.buddies.sorted { $0.name < $1.name }, id: \.persistentModelID) { buddy in
                    removableChip(label: buddy.name, systemImage: "person.2") {
                        filters.buddies.remove(buddy)
                    }
                }
                if filters.minimumRating > 0 {
                    removableChip(label: "\(filters.minimumRating)+ stars", systemImage: "star.fill") {
                        filters.minimumRating = 0
                    }
                }
                if filters.dateRange != .allTime {
                    removableChip(label: filters.dateRange.label, systemImage: "calendar") {
                        filters.dateRange = .allTime
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, Theme.Spacing.s)
        }
        .accessibilityIdentifier("history.activeFilters")
    }

    private func removableChip(label: String, systemImage: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .accessibilityLabel("Remove filter: \(label)")
    }

    // MARK: - Empty state

    private var noMatchesState: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(
                title: "No sessions match",
                message: "Try adjusting your search or filters.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
            Button {
                clearAllCriteria()
            } label: {
                Text("Clear Filters")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textInverse)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, 10)
                    .glassCapsule(tint: Theme.glassStrongTint, isInteractive: true)
            }
            .buttonStyle(PressFeedbackButtonStyle())
            .accessibilityIdentifier("history.empty.clearFilters")
        }
    }

    // MARK: - Actions & memoization

    private func clearAllCriteria() {
        filters.clear()
        searchText = ""
        debouncedSearchText = ""
    }

    private func deletePendingSession() {
        guard let session = sessionPendingDelete else { return }
        sessionPendingDelete = nil
        SessionMediaStore.deleteStoredMedia(for: session.media)
        HealthKitService.shared.deleteWorkout(for: session)
        modelContext.delete(session)
        deletionCount += 1
    }

    /// Cheap change signature for the session list: covers inserts, deletes,
    /// reorders, and edits (via `updatedAt`) without re-filtering per body pass.
    private var sessionsStamp: Int {
        var hasher = Hasher()
        for session in sessions {
            hasher.combine(session.persistentModelID)
            hasher.combine(session.updatedAt)
        }
        return hasher.finalize()
    }

    private func refreshResults() {
        let filtered = filters.apply(to: sessions, searchText: debouncedSearchText)
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfMonth }
        groupedSessions = grouped.keys.sorted(by: >).map { key in
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
