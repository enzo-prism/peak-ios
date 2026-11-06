import Foundation

/// Where a watch-side surf workout is in its lifecycle.
///
/// Mirrors the subset of `HKWorkoutSessionState` Peak actually acts on.
/// HealthKit also reports `.prepared` and `.stopped`, but those are transitional
/// states the UI has nothing distinct to say about, so they are folded into the
/// neighbouring states rather than given buttons of their own.
nonisolated enum SurfWorkoutState: String, Codable, Sendable {
    case idle
    case running
    case paused
    case ended
}

/// The four things a surfer can do to a session, in the order the watch UI
/// offers them.
nonisolated enum SurfWorkoutEvent: String, Codable, Sendable {
    case start
    case pause
    case resume
    case end
}

/// The state machine *and* the elapsed-time accounting for a watch surf
/// session, as one pure value type.
///
/// These two concerns are deliberately fused rather than split: elapsed time is
/// only correct if it is derived from the same transitions that drive the state
/// (a pause that updates the state but not the clock silently inflates every
/// session by the time the surfer spent sitting on the beach). Keeping them in
/// one `Equatable` struct also means the whole lifecycle is exercisable in unit
/// tests with an injected clock — no HealthKit, no watch, no ocean.
///
/// `HKWorkoutSession` remains the authority on the real session; this type is
/// the model the SwiftUI view binds to and the record the handoff payload is
/// built from.
nonisolated struct SurfWorkoutTimeline: Equatable, Sendable {
    private(set) var state: SurfWorkoutState
    /// Time already banked from completed running stretches.
    private(set) var accumulated: TimeInterval
    /// When the current running stretch began; nil unless `state == .running`.
    private(set) var runningSince: Date?
    /// When the surfer first paddled out — the workout's start date.
    private(set) var startedAt: Date?
    /// When the session ended, so `elapsed` freezes instead of ticking forever.
    private(set) var endedAt: Date?

    init() {
        state = .idle
        accumulated = 0
        runningSince = nil
        startedAt = nil
        endedAt = nil
    }

    init(recoveringStartDate start: Date, elapsed: TimeInterval, paused: Bool, at now: Date) {
        self.init()
        state = paused ? .paused : .running
        startedAt = min(start, now)
        accumulated = elapsed.isFinite ? max(0, elapsed) : 0
        runningSince = paused ? nil : now
    }

    /// Timer reference includes all running stretches before the last pause.
    var timerReferenceDate: Date? { runningSince?.addingTimeInterval(-accumulated) }

    /// Applies an event, returning false when the transition is not legal from
    /// the current state.
    ///
    /// Illegal transitions are reported rather than trapped because they are
    /// reachable in normal use, not just from programmer error: watchOS can
    /// deliver a `.paused` state change for an autopause the UI never asked
    /// for, and a double-tap on End can fire twice before the first one lands.
    /// Both should be no-ops, not crashes.
    @discardableResult
    mutating func apply(_ event: SurfWorkoutEvent, at date: Date) -> Bool {
        switch (state, event) {
        case (.idle, .start):
            state = .running
            startedAt = date
            runningSince = date
            return true

        case (.running, .pause):
            accumulated += date.timeIntervalSince(runningSince ?? date)
            runningSince = nil
            state = .paused
            return true

        case (.paused, .resume):
            runningSince = date
            state = .running
            return true

        case (.running, .end):
            accumulated += date.timeIntervalSince(runningSince ?? date)
            runningSince = nil
            state = .ended
            endedAt = date
            return true

        case (.paused, .end):
            state = .ended
            endedAt = date
            return true

        default:
            return false
        }
    }

    /// Active surf time as of `date`: banked time plus the stretch in progress.
    ///
    /// Paused time is excluded by construction, and an ended session returns a
    /// value that no longer depends on `date`.
    func elapsed(at date: Date) -> TimeInterval {
        guard let runningSince else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(runningSince))
    }

    /// True while there is a session worth showing controls for.
    var isActive: Bool {
        state == .running || state == .paused
    }
}
