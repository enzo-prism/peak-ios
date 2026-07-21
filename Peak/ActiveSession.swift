import ActivityKit
import Foundation

/// A surf session that is happening right now: which spot the surfer paddled
/// out at, and when.
///
/// Deliberately **not** a SwiftData model. It lives in App-Group `UserDefaults`
/// so the widget extension can read and write it without touching the store,
/// and so "session in progress" costs no schema version. The real
/// `SurfSession` is only created when the surfer ends the session and saves the
/// prefilled editor.
///
/// This file is compiled into both the app and the widget extension, so
/// everything in it is explicitly `nonisolated` — the two targets do not share
/// a default actor isolation setting.
nonisolated struct ActiveSessionState: Codable, Equatable {
    /// `Spot.key` of the spot, when one was known at start time. The spot is
    /// resolved back out of SwiftData when the editor opens.
    var spotKey: String?
    /// Cached display name so the Live Activity can render a spot without the store.
    var spotName: String?
    var startDate: Date

    init(spotKey: String? = nil, spotName: String? = nil, startDate: Date = Date()) {
        self.spotKey = spotKey
        self.spotName = spotName
        self.startDate = startDate
    }
}

/// A session the surfer just ended but hasn't logged yet. Whichever surface
/// ended it (the in-app button or the Live Activity's End action) writes this;
/// the app drains it the next time it is frontmost and opens the prefilled
/// editor.
nonisolated struct EndedSessionRecord: Codable, Equatable {
    var state: ActiveSessionState
    var endedAt: Date
}

/// Shared read/write for the in-progress session, backed by App-Group
/// `UserDefaults`. Every accessor takes the defaults it should use so tests can
/// hand in a scratch suite instead of the shared one.
nonisolated enum ActiveSessionStore {
    static let appGroupIdentifier = PeakWidgetStore.appGroupIdentifier

    private static let activeKey = "peak.activeSession"
    private static let pendingKey = "peak.pendingSessionLog"

    /// The App-Group suite when the entitlement is live, the app's own defaults
    /// otherwise. `UserDefaults(suiteName:)` still hands back a usable store on
    /// simulator builds where the group isn't registered yet, but the fallback
    /// keeps this honest if it ever returns nil.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    // MARK: - In-progress session

    static func loadActive(from defaults: UserDefaults = sharedDefaults) -> ActiveSessionState? {
        decode(ActiveSessionState.self, forKey: activeKey, from: defaults)
    }

    static func saveActive(_ state: ActiveSessionState, to defaults: UserDefaults = sharedDefaults) {
        encode(state, forKey: activeKey, to: defaults)
    }

    static func clearActive(in defaults: UserDefaults = sharedDefaults) {
        defaults.removeObject(forKey: activeKey)
    }

    // MARK: - Ended-but-unlogged session

    static func loadPendingLog(from defaults: UserDefaults = sharedDefaults) -> EndedSessionRecord? {
        decode(EndedSessionRecord.self, forKey: pendingKey, from: defaults)
    }

    static func savePendingLog(_ record: EndedSessionRecord, to defaults: UserDefaults = sharedDefaults) {
        encode(record, forKey: pendingKey, to: defaults)
    }

    static func clearPendingLog(in defaults: UserDefaults = sharedDefaults) {
        defaults.removeObject(forKey: pendingKey)
    }

    /// Reads the pending log and removes it in one step, so a session is never
    /// handed to the editor twice.
    static func takePendingLog(from defaults: UserDefaults = sharedDefaults) -> EndedSessionRecord? {
        guard let record = loadPendingLog(from: defaults) else { return nil }
        clearPendingLog(in: defaults)
        return record
    }

    /// Ends the in-progress session: clears it and parks it as a pending log.
    /// Returns the record so the caller can present the editor immediately.
    @discardableResult
    static func endActive(
        at endDate: Date = Date(),
        in defaults: UserDefaults = sharedDefaults
    ) -> EndedSessionRecord? {
        guard let state = loadActive(from: defaults) else { return nil }
        let record = EndedSessionRecord(state: state, endedAt: endDate)
        clearActive(in: defaults)
        savePendingLog(record, to: defaults)
        return record
    }

    /// Wipes both slots. Used by UI-test launches so a run never inherits an
    /// in-progress session from an earlier one.
    static func reset(in defaults: UserDefaults = sharedDefaults) {
        clearActive(in: defaults)
        clearPendingLog(in: defaults)
    }

    // MARK: - Coding

    private static func decode<T: Decodable>(
        _ type: T.Type,
        forKey key: String,
        from defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, forKey key: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Live Activity payload for an in-progress session. The elapsed time is
/// rendered with `Text(timerInterval:)` off `startDate`, so the activity ticks
/// on its own and Peak never needs push updates (or a push token, or a server).
nonisolated struct PeakSessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the surfer paddled out. The system counts up from here.
        var startDate: Date
    }

    /// Spot name captured at start, or nil when the session started without one.
    var spotName: String?
}
