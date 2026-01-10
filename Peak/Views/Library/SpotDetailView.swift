import MapKit
import SwiftUI
import SwiftData

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
                VStack(alignment: .leading, spacing: 16) {
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
            }
        }
        .navigationTitle(spot.name)
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

    private func summarySection(metrics: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                MetricCardView(title: "Times Surfed", value: "\(metrics.count)")
                MetricCardView(title: "Last Surfed", value: lastUsedLabel(metrics.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(metrics.averageRating))
            }
        }
    }

    private func locationSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.custom("Avenir Next", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if let location = spot.locationName?.trimmedNonEmpty {
                Text(location)
                    .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("No location saved yet.")
                    .font(.custom("Avenir Next", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textMuted)
            }

            if let coordinate = spot.coordinate {
                mapPreview(coordinate: coordinate)
            } else {
                Text("Drop a pin in Edit to save the surf break location.")
                    .font(.custom("Avenir Next", size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
            }
        }
    }

    private func sessionSection(sessions: [SurfSession]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sessions")
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
        .glassCard(cornerRadius: 18, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityLabel("Map showing \(spot.name)")
    }
}

#Preview {
    NavigationStack {
        SpotDetailView(spot: Spot(name: "Trestles"))
            .modelContainer(PreviewData.container)
    }
}
