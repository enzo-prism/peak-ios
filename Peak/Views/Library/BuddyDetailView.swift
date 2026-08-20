import SwiftUI
import SwiftData

struct BuddyDetailView: View {
    let buddy: Buddy

    var body: some View {
        BuddyDetailLoadedView(buddy: buddy, buddyKey: buddy.key)
            .id(buddy.key)
    }
}

private struct BuddyDetailLoadedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [SurfSession]

    let buddy: Buddy
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var deleteBlockedMessage = ""
    @State private var showDeleteBlocked = false
    @State private var didDelete = false

    init(buddy: Buddy, buddyKey: String) {
        self.buddy = buddy
        _sessions = Query(
            SurfSession.sortedByDateDescending(
                matchingBuddyKey: buddyKey,
                prefetch: [\.spot, \.gear, \.buddies]
            )
        )
    }

    var body: some View {
        let metrics = UsageMetricsCalculator.metrics(for: sessions)

        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                GlassContainer(spacing: 16) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        headerCard

                        summarySection(metrics: metrics)

                        if metrics.count > 0 {
                            UsageChartCard(
                                title: "Sessions over time",
                                data: metrics.monthlyCounts,
                                valueLabel: "Sessions"
                            )
                        }

                        LibrarySessionListSection(title: "Sessions", sessions: sessions)

                        LibraryDestructiveButton(title: "Delete Buddy") {
                            deleteTapped(count: metrics.count)
                        }
                    }
                    .padding()
                    .readableContentWidth()
                }
            }
        }
        .navigationTitle("Buddy")
        .navigationBarTitleDisplayMode(.inline)
        .libraryNavigationSubtitle("Surf buddy")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
                    .accessibilityIdentifier("library.detail.edit")
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
                didDelete = true
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
        .sensoryFeedback(.success, trigger: didDelete)
    }

    private var headerCard: some View {
        Text(buddy.name)
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
            .accessibilityAddTraits(.isHeader)
    }

    private func summarySection(metrics: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Summary")

            DetailMetricGrid {
                MetricCardView(title: "Sessions", value: "\(metrics.count)")
                MetricCardView(title: "Last Surfed", value: lastUsedLabel(metrics.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(metrics.averageRating))
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
        return date.formatted(date: .abbreviated, time: .omitted)
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
