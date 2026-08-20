import SwiftUI
import SwiftData

struct BuddyDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]

    let buddy: Buddy
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var deleteBlockedMessage = ""
    @State private var showDeleteBlocked = false

    var body: some View {
        let relatedSessions = sessions.filter { session in
            session.buddies.contains(where: { $0.persistentModelID == buddy.persistentModelID })
        }
        let metrics = UsageMetricsCalculator.metrics(for: relatedSessions)

        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    headerCard(metrics: metrics)

                    summarySection(metrics: metrics)

                    UsageChartCard(
                        title: "Sessions over time",
                        data: metrics.monthlyCounts,
                        valueLabel: "Sessions"
                    )

                    sessionSection(sessions: relatedSessions)

                    Button(role: .destructive) {
                        deleteTapped(count: metrics.count)
                    } label: {
                        Label("Delete Buddy", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle(prominent: false)
                }
                .padding()
                .readableContentWidth()
            }
        }
        .navigationTitle("Buddy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            BuddyEditorView(mode: .edit(buddy))
        }
        .confirmationDialog(
            "Delete buddy?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(buddy)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the buddy from your library. Sessions will remain unchanged.")
        }
        .alert("Cannot Delete", isPresented: $showDeleteBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteBlockedMessage)
        }
    }

    private func headerCard(metrics: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(buddy.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(metrics.count) shared session\(metrics.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
    }

    private func summarySection(metrics: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            DetailMetricGrid {
                MetricCardView(title: "Sessions", value: "\(metrics.count)")
                MetricCardView(title: "Last Surfed", value: lastUsedLabel(metrics.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(metrics.averageRating))
            }
        }
    }

    private func sessionSection(sessions: [SurfSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sessions")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if sessions.isEmpty {
                Text("No sessions yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRowView(session: session)
                    }
                    .buttonStyle(PressFeedbackButtonStyle())
                }
            }
        }
    }

    private func deleteTapped(count: Int) {
        if count > 0 {
            deleteBlockedMessage = "Used by \(count) sessions."
            showDeleteBlocked = true
        } else {
            showDeleteConfirm = true
        }
    }

    private func lastUsedLabel(_ date: Date?) -> String {
        guard let date else { return "-" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func averageRatingLabel(_ value: Double) -> String {
        if value == 0 {
            return "-"
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        BuddyDetailView(buddy: Buddy(name: "Kai"))
            .modelContainer(PreviewData.container)
    }
}
