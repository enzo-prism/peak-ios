import AppIntents
import Foundation
import SwiftData

/// A surf break exposed to Siri, Shortcuts, and Spotlight as a pickable value.
struct SpotEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Surf Break" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = SpotEntityQuery()
}

struct SpotEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SpotEntity] {
        try allSpots().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [SpotEntity] {
        try allSpots().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SpotEntity] {
        try allSpots()
    }

    @MainActor
    private func allSpots() throws -> [SpotEntity] {
        let context = PeakDataStore.shared.container.mainContext
        let descriptor = FetchDescriptor<Spot>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map { SpotEntity(id: $0.key, name: $0.name) }
    }
}

enum LogSurfSessionError: Error, CustomLocalizedStringResourceConvertible {
    case spotNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .spotNotFound:
            return "That surf break couldn't be found. Add it in Peak first."
        }
    }
}

/// Logs a surf session from Siri / Shortcuts / Spotlight without opening the app.
struct LogSurfSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Surf Session"
    static var description = IntentDescription("Quickly log a surf session at one of your saved breaks.")

    @Parameter(title: "Surf Break")
    var spot: SpotEntity

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "Duration (minutes)")
    var durationMinutes: Int?

    @Parameter(title: "Rating (0–5)")
    var rating: Int?

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log a session at \(\.$spot)") {
            \.$date
            \.$durationMinutes
            \.$rating
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let spotKey = spot.id
        let context = PeakDataStore.shared.container.mainContext
        let descriptor = FetchDescriptor<Spot>(predicate: #Predicate { $0.key == spotKey })
        guard let matchedSpot = try context.fetch(descriptor).first else {
            throw LogSurfSessionError.spotNotFound
        }

        let session = SurfSession(
            date: date ?? Date(),
            spot: matchedSpot,
            rating: min(max(rating ?? 0, 0), 5),
            durationMinutes: SurfSession.normalizedDuration(durationMinutes),
            notes: notes ?? ""
        )
        context.insert(session)
        try context.save()

        return .result(dialog: "Logged a session at \(matchedSpot.name).")
    }
}

struct PeakShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSurfSessionIntent(),
            phrases: [
                "Log a surf session in \(.applicationName)",
                "Log a \(.applicationName) session",
                "Add a surf session to \(.applicationName)"
            ],
            shortTitle: "Log Session",
            systemImageName: "figure.surfing"
        )
    }
}
