import AppIntents
import Foundation
import SwiftData

/// Gives App Intents a way into the SwiftData store. Intents can run while the
/// app is already up (Action button, Control Center, in-app shortcut) or cold
/// (Siri, Spotlight), so `PeakApp` registers its live container at launch and
/// anything running before that falls back to opening the store itself.
@MainActor
enum PeakIntentStore {
    private static var registered: ModelContainer?
    private static var fallback: ModelContainer?

    /// Called by `PeakApp` so intents share the app's container — and, under UI
    /// tests, its seeded in-memory store — instead of opening a second one.
    static func register(_ container: ModelContainer) {
        registered = container
    }

    static var container: ModelContainer? {
        if let registered { return registered }
        if let fallback { return fallback }
        // Never let a Siri query archive a "corrupt" store out from under the
        // app: read-only intent access uses the plain load path and simply
        // returns nothing if it fails.
        fallback = try? ModelContainer(
            for: Schema(versionedSchema: PeakSchemaV8.self),
            migrationPlan: PeakMigrationPlan.self,
            configurations: [ModelConfiguration(schema: Schema(versionedSchema: PeakSchemaV8.self))]
        )
        return fallback
    }

    static func sessions() -> [SurfSession] {
        fetch(FetchDescriptor<SurfSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
    }

    static func spots() -> [Spot] {
        fetch(FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.name)]))
    }

    private static func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        guard let container else { return [] }
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Surf session

/// A logged session, exposed to Siri, Shortcuts and the Spotlight semantic
/// index. Values are copied out of the model rather than referenced so the
/// entity stays valid after the store closes.
struct SurfSessionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Surf Session",
        numericFormat: "\(placeholder: .int) surf sessions"
    )
    static let defaultQuery = SurfSessionEntityQuery()

    let id: String
    let spotName: String?
    let date: Date
    let rating: Int
    let durationMinutes: Int?

    init(session: SurfSession) {
        self.id = SessionIntentQueries.identifier(for: session)
        self.spotName = session.spot?.name.trimmedNonEmpty
        self.date = session.date
        self.rating = session.rating
        self.durationMinutes = session.durationMinutes
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(spotName ?? "Surf session")",
            subtitle: "\(Self.subtitle(date: date, rating: rating, durationMinutes: durationMinutes))",
            image: .init(systemName: "figure.surfing")
        )
    }

    /// "12 Mar · 1 h 30 m · ★★★★" — date first because that's how a surfer
    /// picks a session out of a list.
    static func subtitle(date: Date, rating: Int, durationMinutes: Int?) -> String {
        var parts = [date.formatted(date: .abbreviated, time: .omitted)]
        if let durationMinutes, durationMinutes > 0 {
            parts.append(SessionDurationFormatter.string(from: durationMinutes))
        }
        if rating > 0 {
            parts.append(String(repeating: "★", count: min(rating, 5)))
        }
        return parts.joined(separator: " · ")
    }
}

struct SurfSessionEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SurfSessionEntity] {
        await MainActor.run {
            SessionIntentQueries
                .sessions(withIdentifiers: identifiers, in: PeakIntentStore.sessions())
                .map(SurfSessionEntity.init(session:))
        }
    }

    func suggestedEntities() async throws -> [SurfSessionEntity] {
        await MainActor.run {
            SessionIntentQueries
                .recentSessions(from: PeakIntentStore.sessions())
                .map(SurfSessionEntity.init(session:))
        }
    }
}

// MARK: - Spot

/// A saved surf break. Backed by `Spot.key`, which is already unique and
/// normalized, so identity survives renames of everything except the name itself.
struct SpotEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Surf Spot",
        numericFormat: "\(placeholder: .int) surf spots"
    )
    static let defaultQuery = SpotEntityQuery()

    let id: String
    let name: String
    let locationName: String?

    init(spot: Spot) {
        self.id = SessionIntentQueries.identifier(for: spot)
        self.name = spot.name
        self.locationName = spot.locationName?.trimmedNonEmpty
    }

    var displayRepresentation: DisplayRepresentation {
        if let locationName {
            return DisplayRepresentation(
                title: "\(name)",
                subtitle: "\(locationName)",
                image: .init(systemName: "mappin.and.ellipse")
            )
        }
        return DisplayRepresentation(title: "\(name)", image: .init(systemName: "mappin.and.ellipse"))
    }
}

/// `EntityStringQuery` so phrasing like "…at Ocean Beach" resolves by name and
/// not just by a picker selection.
struct SpotEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SpotEntity] {
        await MainActor.run {
            SessionIntentQueries
                .spots(withIdentifiers: identifiers, in: PeakIntentStore.spots())
                .map(SpotEntity.init(spot:))
        }
    }

    func entities(matching string: String) async throws -> [SpotEntity] {
        await MainActor.run {
            SessionIntentQueries
                .spots(matching: string, in: PeakIntentStore.spots())
                .map(SpotEntity.init(spot:))
        }
    }

    func suggestedEntities() async throws -> [SpotEntity] {
        await MainActor.run {
            SessionIntentQueries
                .frequentSpots(from: PeakIntentStore.spots(), sessions: PeakIntentStore.sessions())
                .map(SpotEntity.init(spot:))
        }
    }
}
