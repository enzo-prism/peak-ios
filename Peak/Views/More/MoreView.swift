import SwiftUI
import SwiftData

struct MoreView: View {
    @Bindable private var navigation = PeakNavigationCoordinator.shared
    @Query(sort: \Spot.name) private var spots: [Spot]
    private var openedSpot: PeakEntityRef? {
        get { navigation.moreSpotSelection }
        nonmutating set { navigation.moreSpotSelection = newValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    GlassContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            NavigationLink { SurfMemoriesView() } label: {
                                Label("Surf Memories", systemImage: "photo.on.rectangle")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint)
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .accessibilityIdentifier("more.memories")
                            NavigationLink { AskPeakView() } label: {
                                Label("Ask Peak", systemImage: "magnifyingglass")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint)
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .accessibilityIdentifier("more.askPeak")
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .accessibilityLabel("Settings")
                            .accessibilityHint("Opens app settings")
                            .accessibilityIdentifier("more.settings")

                            NavigationLink {
                                YearInReviewView()
                            } label: {
                                Label("Year in Review", systemImage: "sparkles")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .accessibilityLabel("Year in Review")
                            .accessibilityHint("Opens your yearly surf summary")
                            .accessibilityIdentifier("more.yearInReview")

                            NavigationLink {
                                SpotLibraryView()
                            } label: {
                                Label("Spots", systemImage: "mappin.and.ellipse")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .accessibilityLabel("Spots")
                            .accessibilityHint("Opens your surf spot library")
                            .accessibilityIdentifier("more.spots")

                            NavigationLink {
                                BuddyLibraryView()
                            } label: {
                                Label("Buddies", systemImage: "person.2")
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .glassCard(cornerRadius: Theme.Radius.card, tint: Theme.glassDimTint, isInteractive: true)
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressFeedbackButtonStyle())
                            .accessibilityLabel("Buddies")
                            .accessibilityHint("Opens your surf buddy library")
                            .accessibilityIdentifier("more.buddies")
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("More")
            .navigationDestination(item: $navigation.moreSpotSelection) { ref in
                if let spot = spots.first(where: { SessionIntentQueries.identifier(for: $0) == ref.id }) {
                    SpotDetailView(spot: spot)
                }
            }
        }
        .tint(Theme.textPrimary)
        .onAppear {
            consumePendingSpotIfNeeded()
        }
        .onChange(of: navigation.pendingSpotID) { _, _ in
            consumePendingSpotIfNeeded()
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            consumePendingSpotIfNeeded()
        }
    }

    private func consumePendingSpotIfNeeded() {
        guard navigation.selectedTab == .more else { return }
        guard let id = navigation.pendingSpotID else { return }
        _ = navigation.consumePendingSpot()
        openedSpot = PeakEntityRef(id: id)
    }
}

#Preview {
    MoreView()
        .modelContainer(PreviewData.container)
}
