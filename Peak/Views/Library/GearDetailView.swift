import SwiftUI
import SwiftData
import UIKit

struct GearDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]

    let gear: Gear
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false

    var body: some View {
        let relatedSessions = sessions.filter { session in
            session.gear.contains(where: { $0.key == gear.key })
        }
        let summary = GearUsageCalculator.summary(for: gear, sessions: sessions)
        let policy = GearUsageCalculator.policy(for: gear, sessions: sessions)

        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    usageSummarySection(summary: summary)

                    UsageChartCard(
                        title: "Usage over time",
                        data: summary.monthlyCounts,
                        valueLabel: "Sessions"
                    )

                    topSpotsSection(spots: summary.topSpots)

                    notesSection

                    sessionSection(sessions: relatedSessions)

                    actionSection(policy: policy)
                }
                .padding()
            }
        }
        .navigationTitle(gear.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showEditor = true
                }
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
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the gear from your library. Sessions will remain unchanged.")
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            gearImage

            VStack(alignment: .leading, spacing: 6) {
                Text(gear.name)
                    .font(.custom("Avenir Next", size: 20, relativeTo: .headline).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(gear.kind.label)
                    .font(.custom("Avenir Next", size: 13, relativeTo: .caption).weight(.semibold))
                    .foregroundStyle(Theme.textMuted)

                if let summary = gear.profileSummary {
                    Text(summary)
                        .font(.custom("Avenir Next", size: 13, relativeTo: .caption))
                        .foregroundStyle(Theme.textSecondary)
                }

                if gear.isArchived {
                    Text("Archived")
                        .font(.custom("Avenir Next", size: 12, relativeTo: .caption).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassCapsule(tint: Theme.glassDimTint, isInteractive: false)
                }
            }

            Spacer()
        }
        .padding(16)
        .glassCard(cornerRadius: 22, tint: Theme.glassDimTint, isInteractive: true)
    }

    private var gearImage: some View {
        ZStack {
            if let data = gear.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: gear.kind.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassCard(cornerRadius: 18, tint: Theme.glassTint, isInteractive: false)
    }

    private func usageSummarySection(summary: GearUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage Summary")
                .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                MetricCardView(title: "Total Uses", value: "\(summary.totalUses)")
                MetricCardView(title: "First Used", value: dateLabel(summary.firstUsed))
            }

            HStack(spacing: 12) {
                MetricCardView(title: "Last Used", value: dateLabel(summary.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(summary.averageRating))
            }
        }
    }

    private func topSpotsSection(spots: [GearTopSpot]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Spots")
                .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if spots.isEmpty {
                Text("No spot data yet.")
                    .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
            } else {
                VStack(spacing: 8) {
                    ForEach(spots) { spot in
                        HStack {
                            Text(spot.name)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(spot.count)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                        .padding(12)
                        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
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
                        .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(notes)
                        .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
                }
            }
        }
    }

    private func sessionSection(sessions: [SurfSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if sessions.isEmpty {
                Text("No sessions yet.")
                    .font(.custom("Avenir Next", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRowView(session: session)
                    }
                    .buttonStyle(.plain)
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
                }
                .glassButtonStyle(prominent: false)
            }

            if policy.canDelete {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Gear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(prominent: false)
            }
        }
    }

    private func dateLabel(_ date: Date?) -> String {
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
        GearDetailView(gear: Gear(name: "6'2\" Fish", kind: .board))
            .modelContainer(PreviewData.container)
    }
}
