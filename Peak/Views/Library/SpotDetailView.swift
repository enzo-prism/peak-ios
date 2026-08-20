import MapKit
import SwiftUI
import SwiftData
import AppIntents

struct SpotDetailView: View {
    let spot: Spot

    var body: some View {
        // Recreate the `@Query` when the unique key changes (rename in the
        // editor), because the fetch predicate is captured at init.
        SpotDetailLoadedView(spot: spot, spotKey: spot.key)
            .id(spot.key)
    }
}

private struct SpotDetailLoadedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [SurfSession]

    let spot: Spot
    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var deleteBlockedMessage = ""
    @State private var showDeleteBlocked = false
    @State private var didDelete = false

    init(spot: Spot, spotKey: String) {
        self.spot = spot
        _sessions = Query(
            SurfSession.sortedByDateDescending(
                matchingSpotKey: spotKey,
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

                        locationSection()

                        if metrics.count > 0 {
                            UsageChartCard(
                                title: "Sessions over time",
                                data: metrics.monthlyCounts,
                                valueLabel: "Sessions"
                            )
                        }

                        LibrarySessionListSection(title: "Sessions", sessions: sessions)

                        LibraryDestructiveButton(title: "Delete Spot") {
                            deleteTapped(count: metrics.count)
                        }
                    }
                    .padding()
                    .readableContentWidth()
                }
            }
        }
        .navigationTitle("Spot")
        .navigationBarTitleDisplayMode(.inline)
        .libraryNavigationSubtitle(spot.locationName?.trimmedNonEmpty ?? "Surf break")
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
                    .accessibilityIdentifier("library.detail.edit")
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
                didDelete = true
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
        .sensoryFeedback(.success, trigger: didDelete)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spot.name)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(spot.locationName?.trimmedNonEmpty ?? "No location saved")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func summarySection(metrics: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Summary")

            DetailMetricGrid {
                MetricCardView(title: "Times Surfed", value: "\(metrics.count)")
                MetricCardView(title: "Last Surfed", value: lastUsedLabel(metrics.lastUsed))
                MetricCardView(title: "Avg Rating", value: averageRatingLabel(metrics.averageRating))
            }
        }
    }

    private func locationSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Location")

            if let coordinate = spot.coordinate {
                mapPreview(coordinate: coordinate)

                Button {
                    openInMaps(coordinate: coordinate)
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .glassButtonStyle(prominent: false)
                .accessibilityLabel("Open \(spot.name) in Maps")
                .accessibilityIdentifier("spot.detail.openInMaps")
            } else {
                Text("Drop a pin in Edit to save the surf break location.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .accessibilityHidden(true)
    }

    private func openInMaps(coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = spot.name
        item.openInMaps()
    }
}

#Preview {
    NavigationStack {
        SpotDetailView(spot: Spot(name: "Trestles"))
            .modelContainer(PreviewData.container)
    }
}
