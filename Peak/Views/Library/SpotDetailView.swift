import MapKit
import SwiftUI
import SwiftData
import AppIntents

struct SpotDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SurfSession.date, order: .reverse) private var sessions: [SurfSession]

    let spot: Spot
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var deleteBlockedMessage = ""
    @State private var showDeleteBlocked = false

    var body: some View {
        let relatedSessions = sessions.filter { session in
            session.spot?.persistentModelID == spot.persistentModelID
        }
        let metrics = UsageMetricsCalculator.metrics(for: relatedSessions)

        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    headerCard(metrics: metrics)

                    summarySection(metrics: metrics)

                    locationSection()

                    UsageChartCard(
                        title: "Sessions over time",
                        data: metrics.monthlyCounts,
                        valueLabel: "Sessions"
                    )

                    sessionSection(sessions: relatedSessions)

                    Button(role: .destructive) {
                        deleteTapped(count: metrics.count)
                    } label: {
                        Label("Delete Spot", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .glassButtonStyle(prominent: false)
                }
                .padding()
                .readableContentWidth()
            }
        }
        .navigationTitle("Spot")
        .navigationBarTitleDisplayMode(.inline)
        .userActivity("com.designprism.peak.viewingSpot") { activity in
            activity.title = spot.name
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.isEligibleForHandoff = false
            if #available(iOS 18.0, *) {
                activity.appEntityIdentifier = EntityIdentifier(for: SpotEntity(spot: spot))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            SpotEditorView(mode: .edit(spot))
        }
        .confirmationDialog(
            "Delete spot?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(spot)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the spot from your library. Sessions will remain unchanged.")
        }
        .alert("Cannot Delete", isPresented: $showDeleteBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteBlockedMessage)
        }
    }

    private func headerCard(metrics: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spot.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(spot.locationName?.trimmedNonEmpty ?? "No location saved")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(metrics.count) session\(metrics.count == 1 ? "" : "s")")
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
                MetricCardView(title: "Times Surfed", value: "\(metrics.count)")
                MetricCardView(title: "Last Surfed", value: lastUsedLabel(metrics.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(metrics.averageRating))
            }
        }
    }

    private func locationSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if let location = spot.locationName?.trimmedNonEmpty {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("No location saved yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }

            if let coordinate = spot.coordinate {
                mapPreview(coordinate: coordinate)
            } else {
                Text("Drop a pin in Edit to save the surf break location.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
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

    private func mapPreview(coordinate: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )

        return Map(position: .constant(.region(region)), interactionModes: []) {
            Marker(spot.name, coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityLabel("Map showing \(spot.name)")
    }
}

#Preview {
    NavigationStack {
        SpotDetailView(spot: Spot(name: "Trestles"))
            .modelContainer(PreviewData.container)
    }
}
