import SwiftData
import XCTest

@testable import Peak

final class ExportImportTests: XCTestCase {
    func testExportImportMergeRoundTrip() throws {
        let calendar = Calendar(identifier: .gregorian)
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 6))!

        let sourceContainer = try makeContainer()
        let sourceContext = sourceContainer.mainContext

        let spot = Spot(
            name: "Trestles",
            locationName: "San Clemente, CA",
            latitude: 33.384,
            longitude: -117.593,
            createdAt: createdAt
        )
        let gear = Gear(name: "6'2\" Fish", kind: .board, createdAt: createdAt)
        let buddy = Buddy(name: "Kai", createdAt: createdAt)
        let session = SurfSession(
            date: createdAt,
            spot: spot,
            gear: [gear],
            buddies: [buddy],
            rating: 5,
            notes: "Clean lines",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        sourceContext.insert(spot)
        sourceContext.insert(gear)
        sourceContext.insert(buddy)
        sourceContext.insert(session)

        let export = PeakExportManager.makeExport(
            sessions: [session],
            spots: [spot],
            gear: [gear],
            buddies: [buddy],
            now: createdAt
        )
        let data = try PeakExportManager.jsonData(from: export)
        let decoded = try PeakExportManager.decodeJSON(data)

        let targetContainer = try makeContainer()
        let targetContext = targetContainer.mainContext
        let existingSpot = Spot(name: "Ocean Beach", createdAt: createdAt)
        targetContext.insert(existingSpot)

        try PeakExportManager.applyImport(decoded, mode: .merge, context: targetContext)

        let spots = try targetContext.fetch(FetchDescriptor<Spot>())
        let sessions = try targetContext.fetch(FetchDescriptor<SurfSession>())

        XCTAssertEqual(spots.count, 2)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.spot?.name, "Trestles")
        let importedSpot = spots.first { $0.name == "Trestles" }
        XCTAssertEqual(importedSpot?.locationName, "San Clemente, CA")
        XCTAssertEqual(importedSpot?.latitude ?? 0, 33.384, accuracy: 0.0001)
        XCTAssertEqual(importedSpot?.longitude ?? 0, -117.593, accuracy: 0.0001)
    }

    func testExportImportReplaceClearsExisting() throws {
        let calendar = Calendar(identifier: .gregorian)
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!

        let sourceContainer = try makeContainer()
        let sourceContext = sourceContainer.mainContext

        let spot = Spot(name: "Trestles", createdAt: createdAt)
        let session = SurfSession(date: createdAt, spot: spot, createdAt: createdAt, updatedAt: createdAt)
        sourceContext.insert(spot)
        sourceContext.insert(session)

        let export = PeakExportManager.makeExport(
            sessions: [session],
            spots: [spot],
            gear: [],
            buddies: [],
            now: createdAt
        )

        let data = try PeakExportManager.jsonData(from: export)
        let decoded = try PeakExportManager.decodeJSON(data)

        let targetContainer = try makeContainer()
        let targetContext = targetContainer.mainContext
        let existingSpot = Spot(name: "Ocean Beach", createdAt: createdAt)
        targetContext.insert(existingSpot)

        try PeakExportManager.applyImport(decoded, mode: .replace, context: targetContext)

        let spots = try targetContext.fetch(FetchDescriptor<Spot>())
        let sessions = try targetContext.fetch(FetchDescriptor<SurfSession>())

        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots.first?.name, "Trestles")
        XCTAssertEqual(sessions.count, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
