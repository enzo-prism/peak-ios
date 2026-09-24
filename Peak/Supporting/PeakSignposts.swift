import os

/// Points-of-interest signposts, so a Time Profiler / Points of Interest trace
/// in Instruments shows where Peak spends its time (library rebuilds, Stats
/// refreshes, Health queries, Spotlight donations, backups). Signposts cost
/// next to nothing when nothing is recording, and carry no user data.
nonisolated enum PeakSignposts {
    static let signposter = OSSignposter(subsystem: "com.designprism.peak", category: .pointsOfInterest)

    /// An open interval, for code where a closure would not fit (e.g. around a
    /// whole async function body): `let s = begin("X"); defer { end(s) }`.
    struct Interval {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
    }

    static func begin(_ name: StaticString) -> Interval {
        Interval(name: name, state: signposter.beginInterval(name))
    }

    static func end(_ interval: Interval) {
        signposter.endInterval(interval.name, interval.state)
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    static func interval<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }
}
