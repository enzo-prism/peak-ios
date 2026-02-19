import SwiftData
import XCTest

@testable import Peak

final class ExportImportTests: XCTestCase {
    func testExportImportMergeRoundTrip() throws {
        let calendar = Calendar(identifier: .gregorian)
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 6))!

        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)

        let spot = Spot(
            name: "Trestles",
            locationName: "San Clemente, CA",
            latitude: 33.384,
            longitude: -117.593,
            createdAt: createdAt
        )
        let gear = Gear(
            name: "6'2\" Fish",
            kind: .board,
            brand: "Channel Islands",
            model: "Fishbeard",
            size: "6'2\"",
            volumeLiters: 31.5,
            notes: "Daily driver",
            photoData: Data([0x01, 0x02, 0x03]),
            isArchived: false,
            createdAt: createdAt
        )
        let buddy = Buddy(name: "Kai", createdAt: createdAt)
        let session = SurfSession(
            date: createdAt,
            spot: spot,
            gear: [gear],
            buddies: [buddy],
            rating: 5,
            durationMinutes: 90,
            windCondition: .breezy,
            waveHeight: .shoulderHigh,
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
        let targetContext = ModelContext(targetContainer)
        let existingSpot = Spot(name: "Ocean Beach", createdAt: createdAt)
        targetContext.insert(existingSpot)

        try PeakExportManager.applyImport(decoded, mode: .merge, context: targetContext)

        let spots = try targetContext.fetch(FetchDescriptor<Spot>())
        let sessions = try targetContext.fetch(FetchDescriptor<SurfSession>())

        XCTAssertEqual(spots.count, 2)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.spot?.name, "Trestles")
        XCTAssertEqual(sessions.first?.durationMinutes, 90)
        XCTAssertEqual(sessions.first?.windCondition, .breezy)
        XCTAssertEqual(sessions.first?.waveHeight, .shoulderHigh)
        let importedSpot = spots.first { $0.name == "Trestles" }
        XCTAssertEqual(importedSpot?.locationName, "San Clemente, CA")
        XCTAssertEqual(importedSpot?.latitude ?? 0, 33.384, accuracy: 0.0001)
        XCTAssertEqual(importedSpot?.longitude ?? 0, -117.593, accuracy: 0.0001)
        let importedGear = try targetContext.fetch(FetchDescriptor<Gear>()).first { $0.name == "6'2\" Fish" }
        XCTAssertEqual(importedGear?.brand, "Channel Islands")
        XCTAssertEqual(importedGear?.model, "Fishbeard")
        XCTAssertEqual(importedGear?.size, "6'2\"")
        XCTAssertEqual(importedGear?.volumeLiters ?? 0, 31.5, accuracy: 0.01)
        XCTAssertEqual(importedGear?.notes, "Daily driver")
        XCTAssertEqual(importedGear?.photoData, Data([0x01, 0x02, 0x03]))
    }

    func testExportImportReplaceClearsExisting() throws {
        let calendar = Calendar(identifier: .gregorian)
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!

        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)

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
        let targetContext = ModelContext(targetContainer)
        let existingSpot = Spot(name: "Ocean Beach", createdAt: createdAt)
        targetContext.insert(existingSpot)

        try PeakExportManager.applyImport(decoded, mode: .replace, context: targetContext)

        let spots = try targetContext.fetch(FetchDescriptor<Spot>())
        let sessions = try targetContext.fetch(FetchDescriptor<SurfSession>())

        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots.first?.name, "Trestles")
        XCTAssertEqual(sessions.count, 1)
    }

    func testSessionsCSVEscapesSpecialCharacters() {
        let notes = "Line1, \"Line2\"\nLine3"
        let session = SurfSession(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 1),
            spot: nil,
            notes: notes
        )

        let csv = PeakExportManager.sessionsCSV(sessions: [session])

        XCTAssertTrue(csv.contains("\"Line1, \"\"Line2\"\"\nLine3\""))
    }

    func testApplyImportRejectsUnsupportedSchema() throws {
        let export = PeakExport(
            schemaVersion: "unsupported",
            exportedAt: ExportDateFormatter.string(from: TestCalendar.makeDate(year: 2026, month: 2, day: 1)),
            sessions: [],
            spots: [],
            gear: [],
            buddies: []
        )

        let container = try makeContainer()
        let context = ModelContext(container)
        XCTAssertThrowsError(try PeakExportManager.applyImport(export, mode: .merge, context: context)) { error in
            guard case ExportError.unsupportedSchema = error else {
                XCTFail("Expected unsupportedSchema but got \(error)")
                return
            }
        }
    }

    func testApplyImportCreatesSpotFromNameWhenMissing() throws {
        let createdAt = TestCalendar.makeDate(year: 2026, month: 2, day: 1, hour: 6)
        let createdString = ExportDateFormatter.string(from: createdAt)

        let sessionExport = SessionExport(
            id: createdString,
            date: createdString,
            spotId: nil,
            spotName: "New Spot",
            rating: 4,
            durationMinutes: 60,
            windCondition: nil,
            waveHeight: nil,
            windSpeedKph: nil,
            windDirectionDegrees: nil,
            waveHeightMeters: nil,
            swellWaveHeightMeters: nil,
            swellWavePeriodSeconds: nil,
            swellWaveDirectionDegrees: nil,
            windWaveHeightMeters: nil,
            windWavePeriodSeconds: nil,
            windWaveDirectionDegrees: nil,
            seaSurfaceTemperatureC: nil,
            conditionsSource: nil,
            conditionsFetchedAt: nil,
            conditionsLatitude: nil,
            conditionsLongitude: nil,
            notes: "",
            buddyIds: [],
            gearIds: ["missing-gear"],
            createdAt: createdString,
            updatedAt: createdString
        )

        let export = PeakExport(
            schemaVersion: PeakExportManager.schemaVersion,
            exportedAt: createdString,
            sessions: [sessionExport],
            spots: [],
            gear: [],
            buddies: []
        )

        let container = try makeContainer()
        let context = ModelContext(container)
        try PeakExportManager.applyImport(export, mode: .merge, context: context)

        let spots = try context.fetch(FetchDescriptor<Spot>())
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots.first?.name, "New Spot")

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions.first?.gear.isEmpty ?? false)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
