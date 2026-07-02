import MapKit
import SwiftUI
import SwiftData

/// Map of every saved spot that has a pinned coordinate, each annotated with
/// its name and a session-count badge. Spots without a pin are listed in a
/// compact "Not on the map" strip below the map. Tapping either opens the
/// spot's detail screen.
struct SpotsMapView: View {
    @Query(sort: \Spot.name) private var spots: [Spot]
    @Query(SurfSession.sortedByDateDescending(prefetch: [\.spot]))
    private var sessions: [SurfSession]

    // `.automatic` frames the annotations; replaced by the wide default on
    // appear when nothing is pinned so the camera never sits on 0,0.
    @State private var cameraPosition: MapCameraPosition = .automatic
    // Computed once on appear (not per body): counting is O(sessions).
    @State private var sessionCounts: [String: Int] = [:]
    @State private var selectedSpot: Spot?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Map(position: $cameraPosition) {
                ForEach(pinnedSpots) { spot in
                    if let coordinate = spot.coordinate {
                        Annotation(spot.name, coordinate: coordinate) {
                            annotationButton(for: spot)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .accessibilityIdentifier("spots.map")

            if pinnedSpots.isEmpty {
                EmptyStateView(
                    title: "No pins yet",
                    message: "Drop a pin on a spot in Edit to see it on the map.",
                    systemImage: "mappin.and.ellipse"
                )
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !unpinnedSpots.isEmpty {
                unpinnedStrip
            }
        }
        .navigationTitle("Spot Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedSpot) { spot in
            SpotDetailView(spot: spot)
        }
        .onAppear {
            sessionCounts = UsageMetricsCalculator.spotSnapshots(sessions: sessions)
                .mapValues(\.count)
            if pinnedSpots.isEmpty {
                cameraPosition = .region(SpotMapRegion.wideDefault)
            }
        }
    }

    private var pinnedSpots: [Spot] {
        spots.filter { $0.coordinate != nil }
    }

    private var unpinnedSpots: [Spot] {
        spots.filter { $0.coordinate == nil }
    }

    private func annotationButton(for spot: Spot) -> some View {
        let count = sessionCounts[spot.key] ?? 0
        return Button {
            selectedSpot = spot
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                Text(spot.name)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textInverse)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.glassStrongTint))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
            .frame(maxWidth: 220)
        }
        .buttonStyle(PressFeedbackButtonStyle())
        .accessibilityLabel("\(spot.name), \(count) session\(count == 1 ? "" : "s")")
        .accessibilityHint("Opens spot details")
        .accessibilityIdentifier("spots.map.annotation.\(spot.key)")
    }

    private var unpinnedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOT ON THE MAP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unpinnedSpots) { spot in
                        Button {
                            selectedSpot = spot
                        } label: {
                            Label(spot.name, systemImage: "mappin.slash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .glassCapsule(tint: Theme.glassDimTint, isInteractive: true)
                        }
                        .buttonStyle(PressFeedbackButtonStyle())
                        .accessibilityHint("Opens spot details")
                        .accessibilityIdentifier("spots.map.unpinned.\(spot.key)")
                    }
                }
                .padding(2)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: false)
        .padding(.horizontal)
        .padding(.bottom, Theme.Spacing.s)
        .accessibilityIdentifier("spots.map.unpinnedSection")
    }
}

#Preview {
    NavigationStack {
        SpotsMapView()
            .modelContainer(PreviewData.container)
    }
}
