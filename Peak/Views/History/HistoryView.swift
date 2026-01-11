import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]
    @State private var filters = HistoryFilters()
    @State private var showFilters = false
    @State private var showNewSession = false

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
                                    .buttonStyle(PressFeedbackButtonStyle())
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 6)
                                }
                            } header: {
                                Text(group.key.monthTitle)
                                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
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
    }

    private var filteredSessions: [SurfSession] {
        sessions.filter { session in
            if let spot = filters.spot, session.spot?.persistentModelID != spot.persistentModelID {
                return false
            }
            if let gear = filters.gear, !session.gear.contains(where: { $0.persistentModelID == gear.persistentModelID }) {
                return false
            }
            if let buddy = filters.buddy, !session.buddies.contains(where: { $0.persistentModelID == buddy.persistentModelID }) {
                return false
            }
            return true
        }
    }

    private var groupedSessions: [(key: Date, value: [SurfSession])] {
        let grouped = Dictionary(grouping: filteredSessions) { $0.date.startOfMonth }
        return grouped.keys.sorted(by: >).map { key in
            let values = grouped[key, default: []].sorted { $0.date > $1.date }
            return (key: key, value: values)
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(PreviewData.container)
}
