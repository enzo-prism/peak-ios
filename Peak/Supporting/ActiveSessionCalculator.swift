import Foundation

/// Turns an ended in-progress session into the values the log editor opens
/// with. Stateless and pure so the rounding/clamping rules are unit-testable
/// without a store, a clock, or a Live Activity.
enum ActiveSessionCalculator {
    /// Shortest session worth logging — a mis-tap that lasts 40 seconds still
    /// opens the editor at one step rather than 0 (which reads as "unset").
    /// The step and ceiling come from `SurfSession` so the prefill can never
    /// drift from the editor's own slider.
    static var minimumDurationMinutes: Int { SurfSession.durationStepMinutes }
    static var durationStepMinutes: Int { SurfSession.durationStepMinutes }
    static var maximumDurationMinutes: Int { SurfSession.maxDurationMinutes }

    /// Elapsed time rounded to the nearest 5-minute step and clamped to
    /// 5...480. Negative or zero elapsed time (clock changes, a stale record)
    /// collapses to the minimum rather than producing nonsense.
    static func durationMinutes(from startDate: Date, to endDate: Date) -> Int {
        let elapsedMinutes = endDate.timeIntervalSince(startDate) / 60
        guard elapsedMinutes > 0 else { return minimumDurationMinutes }

        let step = Double(durationStepMinutes)
        let rounded = Int((elapsedMinutes / step).rounded() * step)
        return min(max(rounded, minimumDurationMinutes), maximumDurationMinutes)
    }

    /// Builds the editor's starting draft from an ended session. `spots` is the
    /// current spot library; the session's `spotKey` is matched against it so
    /// the spot arrives preselected (and the draft stays save-ready).
    static func makeDraft(from record: EndedSessionRecord, spots: [Spot]) -> SessionDraft {
        var draft = SessionDraft()
        draft.date = record.state.startDate
        draft.durationMinutes = durationMinutes(from: record.state.startDate, to: record.endedAt)

        if let spot = matchingSpot(for: record.state, in: spots) {
            draft.selectSpot(spot)
        } else if let name = record.state.spotName?.trimmedNonEmpty {
            // The spot was deleted (or never saved) while the session ran —
            // keep the typed name so the editor can recreate it on save.
            draft.spotName = name
        }

        return draft
    }

    /// Resolves the stored spot key against the library, falling back to a
    /// normalized name match so a renamed-then-rekeyed spot still lands.
    static func matchingSpot(for state: ActiveSessionState, in spots: [Spot]) -> Spot? {
        if let key = state.spotKey?.trimmedNonEmpty,
           let match = spots.first(where: { $0.key == key }) {
            return match
        }
        guard let name = state.spotName?.trimmedNonEmpty else { return nil }
        let key = Spot.makeKey(from: name)
        return spots.first { $0.key == key }
    }
}
