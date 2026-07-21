import SwiftData
import SwiftUI

/// "Best window today" for one of the surfer's favourite spots, justified entirely
/// by their own rated history there.
///
/// Three rules shape this whole view:
///
/// 1. **No passive networking.** The card sits idle until the surfer taps "Check
///    conditions". A Settings toggle opts into fetching on appear, and it ships
///    off. Peak is offline-first and a card that quietly phones a weather service
///    on every Log-tab visit would not be. The backfill action is the same rule
///    taken seriously: it is the largest request the app makes and it only ever
///    happens on a tap.
/// 2. **Confidence gates the recommendation, not the card.** A thin or uniform
///    logbook produces zero confidence by construction, and the honest answer
///    there is to say so — never to dress up the prior as a forecast. But the
///    forecast itself is still true, so a card that cannot recommend anything
///    reports the day's actual conditions instead of apologising.
/// 3. **Never render nothing.** Every state the surfer can reach — no
///    coordinates, no history, a failed fetch — has copy that says what happened
///    and, where possible, a control that fixes it.
struct BestWindowTodayCard: View {
    /// The whole logbook: the scorer needs every session at the chosen spot, not
    /// the recents window the rest of the Log tab shows.
    let sessions: [SurfSession]

    @Environment(\.modelContext) private var modelContext
    @AppStorage(TodayWindowService.autoRefreshKey) private var autoRefresh = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedSpotID: PersistentIdentifier?
    @State private var state: LoadState = .idle
    @State private var backfill: BackfillState = .idle
    /// The in-flight fetch, held so a spot change can cancel it. Its presence is
    /// also the real concurrency guard: `state` is reset to `.idle` when the spot
    /// changes, so a guard on `state != .loading` could not prevent a second
    /// fetch and the two would race to write the answer.
    @State private var refreshTask: Task<Void, Never>?
    @State private var backfillTask: Task<Void, Never>?
    /// Guards the on-appear fetch against firing again every time the tab is
    /// revisited.
    @State private var hasAutoRefreshed = false
    @State private var editingSpot: Spot?

    private enum LoadState: Equatable {
        case idle
        case loading
        /// A completed fetch. `outlook.recommendation` is nil when nothing cleared
        /// the confidence gate, which is a real answer and not an error.
        case loaded(TodayWindowService.Outlook)
        case failed(String)
    }

    private enum BackfillState: Equatable {
        case idle
        case running(completed: Int, total: Int)
        case finished(String)
    }

    private var spots: [Spot] {
        TodayWindowService.favouriteSpots(sessions: sessions)
    }

    private var selectedSpot: Spot? {
        guard let selectedSpotID else { return spots.first }
        return spots.first { $0.persistentModelID == selectedSpotID } ?? spots.first
    }

    var body: some View {
        // The card appears for any spot the surfer actually surfs, located or not.
        // Requiring coordinates here is what used to make it invisible for every
        // imported or typed-by-name break.
        if let spot = selectedSpot {
            GlassContainer(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    spotPicker
                    if spot.coordinate == nil {
                        needsLocation(spot: spot)
                    } else {
                        content(spot: spot)
                        backfillRow(spot: spot)
                        refreshButton(spot: spot)
                    }
                }
                .padding(Theme.Spacing.l)
                .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassDimTint, isInteractive: false)
                .padding(.horizontal)
            }
            .onAppear {
                // Pure local lookup against the bundled catalog — no network, so it
                // does not touch the no-passive-fetching rule. Repairs imported
                // spots permanently, which also makes session auto-fill start
                // working for them.
                if SpotCoordinateResolver.resolveMissingCoordinates(for: spots) > 0 {
                    try? modelContext.save()
                }
                guard autoRefresh, !hasAutoRefreshed, case .idle = state else { return }
                hasAutoRefreshed = true
                refresh(spot: spot)
            }
            .sheet(item: $editingSpot) { spot in
                SpotEditorView(mode: .edit(spot))
            }
        }
    }

    // MARK: Pieces

    /// The heading names the day it is actually talking about. A window found for
    /// tomorrow must never sit under the word "today".
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(headingText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var headingText: String {
        guard case .loaded(let outlook) = state else { return "Best window today" }
        switch outlook.dayOffset {
        case 0: return "Best window today"
        case 1: return "Best window tomorrow"
        default: return "Best window ahead"
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
                            select(spot)
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

    /// Switching spots invalidates everything on screen *and* everything in
    /// flight. Without the cancel, a slow fetch for the old spot would land after
    /// the switch and render the old break's recommendation — and the old break's
    /// cited session — under the new break's name.
    private func select(_ spot: Spot) {
        guard spot.persistentModelID != selectedSpot?.persistentModelID else { return }
        refreshTask?.cancel()
        refreshTask = nil
        backfillTask?.cancel()
        backfillTask = nil
        selectedSpotID = spot.persistentModelID
        state = .idle
        backfill = .idle
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

        case .loaded(let outlook):
            if let recommendation = outlook.recommendation {
                recommendationView(recommendation)
            } else {
                lowConfidenceView(spot: spot, outlook: outlook)
            }

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

    /// The honest state, and the common one. Nothing cleared the confidence gate,
    /// so no window is claimed — but the forecast is still true, so the day's
    /// conditions are shown, explicitly labelled as conditions.
    private func lowConfidenceView(spot: Spot, outlook: TodayWindowService.Outlook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let conditions = outlook.conditions {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conditionsHeading(for: conditions, dayOffset: outlook.dayOffset, spot: spot))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                        .textCase(.uppercase)
                    Text(conditions.summary())
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("window.card.conditions")
                    Text("Forecast conditions, not a recommendation.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            message(lowConfidenceCopy(spot: spot), identifier: "window.card.lowConfidence")
        }
    }

    /// Names the hour the readout actually describes. For a future day that has to
    /// be the timestamp, not a vague "tomorrow": the reading is one hour of the
    /// forecast, and calling midnight's numbers "tomorrow" would overstate them.
    private func conditionsHeading(
        for conditions: TodayWindowService.Conditions,
        dayOffset: Int,
        spot: Spot
    ) -> String {
        guard dayOffset != 0 else { return "Conditions at \(spot.name) now" }
        let when = conditions.date.formatted(.dateTime.weekday(.abbreviated).hour())
        return "\(spot.name), \(when)"
    }

    /// What the surfer actually has to do, which is not what this used to say.
    ///
    /// The old copy — "log a few more rated sessions and Peak will learn what
    /// works here" — was false twice over: plain sessions were discarded outright,
    /// so following it changed nothing, and even a full logbook of identically
    /// rated sessions carries no signal. The two real requirements are conditions
    /// attached to sessions and ratings that differ, so those are what it asks
    /// for, and it points at the control that supplies the first one.
    private func lowConfidenceCopy(spot: Spot) -> String {
        let rated = sessions.filter { $0.spot?.persistentModelID == spot.persistentModelID && $0.rating > 0 }
        let ratings = Set(rated.map(\.rating))
        if rated.count >= 8 && ratings.count <= 1 {
            return "Your sessions at \(spot.name) are all rated the same, so there is nothing yet to tell a good day from an average one. Rate them apart and Peak can start picking windows."
        }
        if hasFillableHistory(spot: spot) {
            return "Peak needs the conditions you surfed in before it can pick a window at \(spot.name). Fill in past conditions above, then keep rating sessions."
        }
        return "Peak needs more rated sessions at \(spot.name), with the conditions attached, before it can honestly call a window."
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

    // MARK: Unlocated spots

    /// A break with no coordinate cannot be forecast — but that is a fixable
    /// problem, not a reason to render an empty view. Spots created by import or
    /// typed by name arrive here, and the catalog lookup on appear has already had
    /// its chance, so what is left genuinely needs the surfer.
    private func needsLocation(spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            message(
                "Peak needs to know where \(spot.name) is before it can check the surf there.",
                identifier: "window.card.needsLocation"
            )
            Button {
                editingSpot = spot
            } label: {
                Label("Add location", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassButtonStyle()
            .accessibilityIdentifier("window.card.addLocation")
        }
    }

    // MARK: Backfill

    /// Only offered when it would do something: a located spot with sessions
    /// inside the provider's ~92-day archive that have no conditions stored.
    private func hasFillableHistory(spot: Spot) -> Bool {
        guard spot.coordinate != nil else { return false }
        return !ConditionsBackfill.eligibleSessions(from: sessions, at: spot).isEmpty
    }

    @ViewBuilder
    private func backfillRow(spot: Spot) -> some View {
        switch backfill {
        case .running(let completed, let total):
            HStack(spacing: 8) {
                ProgressView()
                Text("Filling in past conditions... \(completed) of \(total)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("window.card.backfillProgress")

        case .finished(let summary):
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("window.card.backfillSummary")

        case .idle:
            if hasFillableHistory(spot: spot), state != .loading {
                Button {
                    runBackfill(spot: spot)
                } label: {
                    Label("Fill in past conditions", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .glassButtonStyle()
                .accessibilityIdentifier("window.card.backfill")
            }
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
        .disabled(state == .loading || isBackfilling)
    }

    private var isBackfilling: Bool {
        if case .running = backfill { return true }
        return false
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
        // `refreshTask`, not `state`, is the guard: switching spots resets `state`
        // to `.idle` while a fetch is still running, so a state-based guard would
        // let a second fetch start and the two would race.
        guard refreshTask == nil,
              let latitude = spot.latitude,
              let longitude = spot.longitude else { return }

        let requestedSpotID = spot.persistentModelID
        let history = TodayWindowService.ratedHistory(sessions: sessions, at: spot)
        state = .loading

        refreshTask = Task {
            let result: LoadState
            do {
                // Both the fetch and the ranking happen off the main actor; only
                // the resulting value comes back here.
                let outlook = try await TodayWindowService.outlook(
                    history: history,
                    spotID: requestedSpotID,
                    latitude: latitude,
                    longitude: longitude
                )
                // The result carries the spot it was computed for, so staleness is
                // a property of the answer rather than of whatever the view
                // happened to remember.
                guard TodayWindowService.accepts(outlook, for: selectedSpot) else { return }
                result = .loaded(outlook)
            } catch {
                result = .failed(errorMessage(for: error))
            }

            // A failure is stale in exactly the same way a success is. Dropped
            // *before* clearing `refreshTask`, which by now may belong to a newer
            // fetch.
            guard !Task.isCancelled, selectedSpot?.persistentModelID == requestedSpotID else { return }
            refreshTask = nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                state = result
            }
        }
    }

    /// Fetches and stores the conditions for past sessions that never got any.
    ///
    /// Sequential on purpose: this is a courtesy request against a free public
    /// API on the surfer's behalf, and firing forty of them at once is how an app
    /// gets rate-limited. Progress is reported per session, and the run gives up
    /// after `ConditionsBackfill.consecutiveFailureLimit` failures in a row rather
    /// than grinding through a dead network.
    private func runBackfill(spot: Spot) {
        guard backfillTask == nil,
              let latitude = spot.latitude,
              let longitude = spot.longitude else { return }

        let requestedSpotID = spot.persistentModelID
        let candidates = ConditionsBackfill.eligibleSessions(from: sessions, at: spot)
        guard !candidates.isEmpty else { return }

        backfill = .running(completed: 0, total: candidates.count)

        backfillTask = Task {
            var summary = ConditionsBackfill.Summary(
                filled: 0, attempted: 0, eligible: candidates.count, stoppedEarly: false
            )
            var consecutiveFailures = 0

            for session in candidates {
                if Task.isCancelled { break }
                summary.attempted += 1
                do {
                    let snapshot = try await SurfConditionsService.fetch(
                        start: session.date,
                        durationMinutes: session.durationMinutes ?? ConditionsBackfill.assumedDurationMinutes,
                        latitude: latitude,
                        longitude: longitude
                    )
                    ConditionsBackfill.apply(snapshot, to: session)
                    summary.filled += 1
                    consecutiveFailures = 0
                } catch {
                    consecutiveFailures += 1
                    if consecutiveFailures >= ConditionsBackfill.consecutiveFailureLimit {
                        summary.stoppedEarly = true
                        break
                    }
                }
                guard selectedSpot?.persistentModelID == requestedSpotID else { return }
                backfill = .running(completed: summary.attempted, total: candidates.count)
            }

            // Saved before the staleness check, not after: the conditions were
            // genuinely written to those sessions, and whether the surfer has since
            // switched spots has no bearing on whether that work should survive.
            if summary.filled > 0 {
                try? modelContext.save()
            }

            guard !Task.isCancelled, selectedSpot?.persistentModelID == requestedSpotID else { return }
            backfillTask = nil
            backfill = .finished(summary.message)
            // The history just changed, so any answer on screen was computed from
            // the old one. Better to ask again than to show a stale verdict.
            state = .idle
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
