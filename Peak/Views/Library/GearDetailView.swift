import SwiftUI
import SwiftData
import AppIntents

struct GearDetailView: View {
    let gear: Gear

    var body: some View {
        GearDetailLoadedView(gear: gear, gearKey: gear.key)
            .id(gear.key)
    }
}

private struct GearDetailLoadedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [SurfSession]

    let gear: Gear
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false
    @State private var cachedSummary = GearUsageSummary(
        totalUses: 0,
        firstUsed: nil,
        lastUsed: nil,
        averageRating: 0,
        topSpots: [],
        monthlyCounts: []
    )
    @State private var cachedPolicy = GearUsagePolicy(canDelete: false, canArchive: false)
    @State private var cachedRelatedSessions: [SurfSession] = []
    @State private var cachedReport: GearReport?
    @State private var didDelete = false

    init(gear: Gear, gearKey: String) {
        self.gear = gear
        _sessions = Query(
            SurfSession.sortedByDateDescending(
                matchingGearKey: gearKey,
                prefetch: [\.spot, \.gear, \.buddies]
            )
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                GlassContainer(spacing: 16) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        headerCard

                        usageSummarySection(summary: cachedSummary)

                        if let cachedReport {
                            BoardReportCard(report: cachedReport)
                        }

                        if cachedSummary.totalUses > 0 {
                            UsageChartCard(
                                title: "Usage over time",
                                data: cachedSummary.monthlyCounts,
                                valueLabel: "Sessions"
                            )
                        }

                        topSpotsSection(spots: cachedSummary.topSpots)

                        notesSection

                        LibrarySessionListSection(
                            title: "Recent Sessions",
                            sessions: cachedRelatedSessions
                        )

                        actionSection(policy: cachedPolicy)
                    }
                    .padding()
                    .readableContentWidth()
                }
            }
        }
        .navigationTitle("Gear")
        .navigationBarTitleDisplayMode(.inline)
        .libraryNavigationSubtitle(gear.kind.label)
        .userActivity("com.designprism.peak.viewingGear") { activity in
            activity.title = gear.name
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.isEligibleForHandoff = false
            if #available(iOS 18.0, *) {
                activity.appEntityIdentifier = EntityIdentifier(for: GearEntity(gear: gear))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEditor = true
                }
                .accessibilityIdentifier("library.detail.edit")
            }
        }
        .sheet(isPresented: $showEditor) {
            GearEditorView(mode: .edit(gear))
        }
        .confirmationDialog(
            gear.isArchived ? "Unarchive gear?" : "Archive gear?",
            isPresented: $showArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button(gear.isArchived ? "Unarchive" : "Archive") {
                gear.isArchived.toggle()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(gear.isArchived ? "This will make the gear available again." : "Archived gear stays in history but is hidden from pickers.")
        }
        .confirmationDialog(
            "Delete gear?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(gear)
                didDelete = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the gear from your library. Sessions will remain unchanged.")
        }
        .onChange(of: usageStamp, initial: true) { _, _ in
            refreshUsage()
        }
        .sensoryFeedback(.success, trigger: didDelete)
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            gearImage

            VStack(alignment: .leading, spacing: 6) {
                Text(gear.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                Text(gear.kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)

                if let summary = gear.profileSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if gear.isArchived {
                    Text("Archived")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var gearImage: some View {
        ZStack {
            if let data = gear.photoData {
                SessionMediaThumbnailView(imageData: data, isVideo: false)
            } else {
                Image(systemName: gear.kind.systemImage)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassTint, isInteractive: false)
    }

    private func usageSummarySection(summary: GearUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Usage Summary")

            DetailMetricGrid {
                MetricCardView(title: "Total Uses", value: "\(summary.totalUses)")
                MetricCardView(title: "First Used", value: dateLabel(summary.firstUsed))
                MetricCardView(title: "Last Used", value: dateLabel(summary.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(summary.averageRating))
            }
        }
    }

    private func topSpotsSection(spots: [GearTopSpot]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Top Spots")

            if spots.isEmpty {
                Text("No spot data yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
            } else {
                VStack(spacing: 8) {
                    ForEach(spots) { spot in
                        DetailInfoRow(title: spot.name, value: "\(spot.count)")
                        .padding(12)
                        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        Group {
            if let notes = gear.notes?.trimmedNonEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notes")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
                }
            }
        }
    }

    private func actionSection(policy: GearUsagePolicy) -> some View {
        VStack(spacing: 12) {
            if gear.isArchived || policy.canArchive {
                Button {
                    showArchiveConfirm = true
                } label: {
                    Label(gear.isArchived ? "Unarchive Gear" : "Archive Gear", systemImage: "archivebox")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .glassButtonStyle(prominent: false)
            }

            if policy.canDelete {
                LibraryDestructiveButton(title: "Delete Gear") {
                    showDeleteConfirm = true
                }
            }
        }
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "-" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func averageRatingLabel(_ value: Double) -> String {
        if value == 0 {
            return "-"
        }
        return String(format: "%.1f", value)
    }

    private var usageStamp: Int {
        SessionQueryStamp.make(sessions)
    }

    private func refreshUsage() {
        // `@Query` already isolated this gear's sessions; calculators still
        // filter by key so a two-board row is counted once for this board.
        cachedRelatedSessions = sessions
        cachedSummary = GearUsageCalculator.summary(for: gear, sessions: sessions)
        cachedPolicy = GearUsageCalculator.policy(for: gear, sessions: sessions)
        // Conditions-bucketed ratings only make sense for the thing you choose
        // per swell; a leash doesn't have a favourite period.
        cachedReport = gear.kind == .board
            ? GearInsightsCalculator.report(for: gear, sessions: sessions)
            : nil
    }
}

#Preview {
    NavigationStack {
        GearDetailView(gear: Gear(name: "6'2\" Fish", kind: .board))
            .modelContainer(PreviewData.container)
    }
}
