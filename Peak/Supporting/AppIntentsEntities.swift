import AppIntents
import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

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
        // returns nothing if it fails. Must open at the HEAD schema — asking for
        // a frozen snapshot against a store the app has already migrated past it
        // throws, and every intent then reads an empty logbook.
        fallback = try? ModelContainer(
            for: Schema(versionedSchema: PeakDataStore.headSchema),
            migrationPlan: PeakMigrationPlan.self,
            configurations: [ModelConfiguration(schema: Schema(versionedSchema: PeakDataStore.headSchema))]
        )
        return fallback
    }

    static func sessions() -> [SurfSession] {
        fetch(FetchDescriptor<SurfSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
    }

    static func spots() -> [Spot] {
        fetch(FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.name)]))
    }

    static func gear() -> [Gear] {
        fetch(FetchDescriptor<Gear>(sortBy: [SortDescriptor(\.name)]))
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

@available(iOS 18.0, *)
extension SurfSessionEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        attributes.title = spotName ?? "Surf session"
        attributes.contentDescription = Self.subtitle(date: date, rating: rating, durationMinutes: durationMinutes)
        attributes.startDate = date
        attributes.namedLocation = spotName
        attributes.keywords = ["surf", "session", spotName].compactMap { $0 }
        return attributes
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

@available(iOS 18.0, *)
extension SpotEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        attributes.title = name
        attributes.namedLocation = locationName ?? name
        attributes.keywords = ["surf", "spot", name, locationName].compactMap { $0 }
        attributes.supportsNavigation = true
        return attributes
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

// MARK: - Gear

/// A quiver item. Backed by `Gear.key` (`kind|normalized-name`), which is unique.
struct GearEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Gear",
        numericFormat: "\(placeholder: .int) pieces of gear"
    )
    static let defaultQuery = GearEntityQuery()

    let id: String
    let name: String
    let kindLabel: String

    init(gear: Gear) {
        self.id = SessionIntentQueries.identifier(for: gear)
        self.name = gear.name
        self.kindLabel = gear.kind.label
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kindLabel)",
            image: .init(systemName: "surfboard")
        )
    }
}

@available(iOS 18.0, *)
extension GearEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        attributes.title = name
        attributes.contentDescription = kindLabel
        attributes.keywords = ["surf", "gear", name, kindLabel]
        return attributes
    }
}

struct GearEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GearEntity] {
        await MainActor.run {
            SessionIntentQueries
                .gearItems(withIdentifiers: identifiers, in: PeakIntentStore.gear())
                .map(GearEntity.init(gear:))
        }
    }

    func entities(matching string: String) async throws -> [GearEntity] {
        await MainActor.run {
            SessionIntentQueries
                .gearItems(matching: string, in: PeakIntentStore.gear())
                .map(GearEntity.init(gear:))
        }
    }

    func suggestedEntities() async throws -> [GearEntity] {
        await MainActor.run {
            SessionIntentQueries
                .frequentGear(from: PeakIntentStore.gear(), sessions: PeakIntentStore.sessions())
                .map(GearEntity.init(gear:))
        }
    }
}

// MARK: - Open from Spotlight / Siri

@available(iOS 18.0, *)
struct OpenSessionIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Surf Session"
    static let description = IntentDescription("Opens a logged surf session in Peak.")
    static let openAppWhenRun = true

    @Parameter(title: "Session")
    var target: SurfSessionEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        PeakNavigationCoordinator.shared.handle(.session(id: target.id))
        return .result()
    }
}

@available(iOS 18.0, *)
struct OpenSpotIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Surf Spot"
    static let description = IntentDescription("Opens a saved surf break in Peak.")
    static let openAppWhenRun = true

    @Parameter(title: "Spot")
    var target: SpotEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        PeakNavigationCoordinator.shared.handle(.spot(id: target.id))
        return .result()
    }
}

@available(iOS 18.0, *)
struct OpenGearIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Gear"
    static let description = IntentDescription("Opens a quiver item in Peak.")
    static let openAppWhenRun = true

    @Parameter(title: "Gear")
    var target: GearEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        PeakNavigationCoordinator.shared.handle(.gear(id: target.id))
        return .result()
    }
}

struct SearchPeakIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Peak"
    static let description = IntentDescription("Searches logged sessions in Peak.")
    static let openAppWhenRun = true

    @Parameter(title: "Search")
    var criteria: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PeakNavigationCoordinator.shared.handle(.search(query: criteria))
        return .result()
    }
}
