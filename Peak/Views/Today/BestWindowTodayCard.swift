import SwiftData
import SwiftUI

/// "Best window today" for one of the surfer's favourite spots, justified entirely
/// by their own rated history there.
///
/// Two rules shape this whole view:
///
/// 1. **No passive networking.** The card sits idle until the surfer taps "Check
///    conditions". A Settings toggle opts into fetching on appear, and it ships
///    off. Peak is offline-first and a card that quietly phones a weather service
///    on every Log-tab visit would not be.
/// 2. **Confidence gates the recommendation, not the star rating.** A thin or
///    uniform logbook produces zero confidence by construction, and the honest
///    answer there is to say so — never to dress up the prior as a forecast.
struct BestWindowTodayCard: View {
    /// The whole logbook: the scorer needs every session at the chosen spot, not
    /// the recents window the rest of the Log tab shows.
    let sessions: [SurfSession]

    @AppStorage(TodayWindowService.autoRefreshKey) private var autoRefresh = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedSpotID: PersistentIdentifier?
    @State private var state: LoadState = .idle
    /// Guards against a second fetch while one is in flight, and against the
    /// on-appear fetch firing again every time the tab is revisited.
    @State private var hasAutoRefreshed = false

    private enum LoadState: Equatable {
        case idle
        case loading
        case recommendation(TodayWindowService.Recommendation)
        /// Ranked, but nothing cleared the confidence gate.
        case notEnoughHistory
        case failed(String)
    }

    private var spots: [Spot] {
        TodayWindowService.favouriteSpots(sessions: sessions)
    }

    private var selectedSpot: Spot? {
        guard let selectedSpotID else { return spots.first }
        return spots.first { $0.persistentModelID == selectedSpotID } ?? spots.first
    }

    var body: some View {
        // With no located spot there is nothing to forecast, and an empty card
        // explaining that would be noise on the app's busiest screen.
        if let spot = selectedSpot {
            GlassContainer(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    header(spot: spot)
                    spotPicker
                    content(spot: spot)
                    refreshButton(spot: spot)
                }
                .padding(Theme.Spacing.l)
                .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint, isInteractive: false)
                .padding(.horizontal)
            }
            .onAppear {
                guard autoRefresh, !hasAutoRefreshed, case .idle = state else { return }
                hasAutoRefreshed = true
                refresh(spot: spot)
            }
        }
    }

    // MARK: Pieces

    private func header(spot: Spot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text("Best window today")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    /// Only shown when there is a genuine choice. One favourite spot needs no picker.
    @ViewBuilder
    private var spotPicker: some View {
        if spots.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(spots, id: \.persistentModelID) { spot in
                        SelectableChip(
                            label: spot.name,
                            systemImage: "mappin",
                            isSelected: spot.persistentModelID == selectedSpot?.persistentModelID
                        ) {
                            guard spot.persistentModelID != selectedSpot?.persistentModelID else { return }
                            selectedSpotID = spot.persistentModelID
                            // The old answer belongs to the old spot; keeping it on
                            // screen under a new name would be a lie.
                            state = .idle
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            // The identifier goes on the ScrollView, never on the chips inside it:
            // content inside a ScrollView is not reliably queryable.
            .accessibilityIdentifier("window.card.spots")
        }
    }

    @ViewBuilder
    private func content(spot: Spot) -> some View {
        switch state {
        case .idle:
            message(
                "Check today's conditions at \(spot.name) against everything you've logged here.",
                identifier: "window.card.idle"
            )

        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking conditions...")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityIdentifier("window.card.loading")

        case .recommendation(let recommendation):
            recommendationView(recommendation)

        case .notEnoughHistory:
            // The honest empty state. Never a fabricated window.
            message(
                "Log a few more rated sessions at \(spot.name) and Peak will learn what works here.",
                identifier: "window.card.lowConfidence"
            )

        case .failed(let reason):
            message(reason, identifier: "window.card.error")
        }
    }

    private func recommendationView(_ recommendation: TodayWindowService.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.timeRangeLabel())
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("window.card.time")

            if !recommendation.factorSummary.isEmpty {
                Text(recommendation.factorSummary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("window.card.factors")
            }

            matchLink(recommendation)

            // Says out loud that this is a pattern from the surfer's own log, not
            // a forecast service's verdict.
            Text("Based on your own sessions at this spot.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The cited session, tappable through to its detail — the claim has to be
    /// checkable, or it is just a number.
    @ViewBuilder
    private func matchLink(_ recommendation: TodayWindowService.Recommendation) -> some View {
        if let matchSession = matchedSession(for: recommendation) {
            NavigationLink {
                SessionDetailView(session: matchSession)
            } label: {
                HStack(spacing: 6) {
                    Text(matchLabel(for: recommendation))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFeedbackButtonStyle())
            .accessibilityIdentifier("window.card.match")
        } else if let label = matchLabelIfAvailable(recommendation) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("window.card.match")
        }
    }

    private func refreshButton(spot: Spot) -> some View {
        Button {
            refresh(spot: spot)
        } label: {
            Label(state == .loading ? "Checking..." : "Check conditions", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .glassButtonStyle()
        .disabled(state == .loading)
    }

    private func message(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }

    // MARK: Copy

    private func matchLabel(for recommendation: TodayWindowService.Recommendation) -> String {
        matchLabelIfAvailable(recommendation) ?? "Similar to a past session here"
    }

    private func matchLabelIfAvailable(_ recommendation: TodayWindowService.Recommendation) -> String? {
        guard let date = recommendation.matchDate else { return nil }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        guard let rating = recommendation.matchRating, rating > 0 else {
            return "Similar to your session on \(day)"
        }
        return "Similar to your \(rating)\u{2605} session on \(day)"
    }

    private func matchedSession(for recommendation: TodayWindowService.Recommendation) -> SurfSession? {
        guard let id = recommendation.matchSessionID else { return nil }
        return sessions.first { $0.persistentModelID == id }
    }

    // MARK: Loading

    private func refresh(spot: Spot) {
        guard state != .loading,
              let latitude = spot.latitude,
              let longitude = spot.longitude else { return }

        let history = TodayWindowService.ratedHistory(sessions: sessions, at: spot)
        state = .loading

        Task {
            do {
                // Both the fetch and the ranking happen off the main actor; only
                // the resulting value comes back here.
                let recommendation = try await TodayWindowService.bestWindow(
                    history: history,
                    latitude: latitude,
                    longitude: longitude
                )
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    state = recommendation.map(LoadState.recommendation) ?? .notEnoughHistory
                }
            } catch {
                state = .failed(errorMessage(for: error))
            }
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let error = error as? SurfConditionsError, let description = error.errorDescription {
            return description
        }
        return "Could not check conditions right now."
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            BestWindowTodayCard(sessions: [])
        }
        .background(Theme.background)
    }
}
