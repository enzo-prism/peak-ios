import Foundation

/// A plan is never a recorded surf. No forecast values become logged facts.
nonisolated struct SurfPlan: Codable, Equatable, Identifiable {
    let id: UUID
    let spotKey: String
    let spotName: String
    let gearKeys: [String]
    let start: Date
    let end: Date
    let fetchedAt: Date
    let summary: String

    func isUsable(at now: Date) -> Bool {
        start < end && end > now && now.timeIntervalSince(fetchedAt) < 6 * 3600
            && fetchedAt <= now.addingTimeInterval(60)
    }
}

enum SurfPlanStore {
    static let key = "peak.surfPlan.v1"
    static func load(defaults: UserDefaults = .standard) -> SurfPlan? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SurfPlan.self, from: $0) }
    }
    static func save(_ plan: SurfPlan, defaults: UserDefaults = .standard) throws {
        guard plan.start < plan.end else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(plan), forKey: key)
        publish(plan)
    }
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        publish(nil)
    }
    private static func publish(_ plan: SurfPlan?) {
        guard !TestingDefaults.isRunningTests else { return }
        var snapshot = PeakWidgetStore.read()
        snapshot.planGlance = plan.map { PeakPlanGlance(spotKey: $0.spotKey, spotName: $0.spotName,
            gearKeys: $0.gearKeys, start: $0.start, end: $0.end, fetchedAt: $0.fetchedAt, summary: $0.summary) }
        PeakWidgetStore.write(snapshot)
        PeakWidgetRefresh.reloadTimelines()
    }

    static func draft(for plan: SurfPlan, spots: [Spot], gear: [Gear], now: Date = Date()) -> SessionDraft? {
        guard plan.isUsable(at: now), let spot = spots.first(where: { $0.key == plan.spotKey }) else { return nil }
        // Logging means "I surfed", not "I intend to surf". The plan only
        // supplies setup; start/duration/rating/conditions remain the user's.
        var draft = SessionDraft()
        draft.isAnchoredToNow = true
        draft.selectSpot(spot)
        draft.selectedGear = gear.filter { plan.gearKeys.contains($0.key) && !$0.isArchived }
        return draft
    }
}
