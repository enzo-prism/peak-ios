import Foundation
import CoreData
import SwiftData

/// Session edits/deletions are staged in an expendable context. SwiftData can
/// invalidate cascade children during rollback, so a failed stage is discarded.
enum SessionPersistence {
    static func stagingContext(from source: ModelContext) throws -> ModelContext {
        // New library selections must have permanent IDs before resolving them
        // into another context. Preserve pre-existing edits before staging.
        if source.hasChanges { try source.save() }
        let context = ModelContext(source.container)
        context.autosaveEnabled = false
        return context
    }

    /// Resolve a saved choice or create a name-only spot in the SAME staging
    /// context as the session. Cancelling or failing the session cannot leave
    /// an orphan spot in the library. Fetch errors must not become duplicates.
    static func spot(selection: Spot?, name: String, in context: ModelContext) throws -> Spot {
        if let selection { return try resolve(selection, in: context) }
        guard let name = name.trimmedNonEmpty else { throw CocoaError(.validationMissingMandatoryProperty) }
        let key = Spot.makeKey(from: name)
        var descriptor = FetchDescriptor<Spot>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { return existing }
        return try context.createSpot(name: name, locationName: nil, latitude: nil, longitude: nil)
    }

    /// Retire external videos only after the deletion transaction commits.
    static func resetLibrary(from source: ModelContext,
                             save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let transaction = try stagingContext(from: source)
        let videos = try transaction.fetch(FetchDescriptor<SessionMedia>()).compactMap(\.videoFileName)
        try transaction.resetAllData(deleteMediaFiles: false)
        try save(transaction)
        videos.forEach { SessionMediaStore.deleteVideoFile(named: $0) }
    }

    static func resolve<Model: PersistentModel>(_ model: Model, in context: ModelContext) throws -> Model {
        guard let resolved = context.model(for: model.persistentModelID) as? Model else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return resolved
    }
}
