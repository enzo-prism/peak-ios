import SwiftData
import XCTest

@testable import Peak

final class ModelContextHelpersTests: XCTestCase {
    func testUpsertSpotReturnsExisting() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let first = context.upsertSpot(named: "Trestles")
        let second = context.upsertSpot(named: "Trestles")

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
    }

    func testUpsertGearUnarchivesExisting() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let gear = TestFixture.gear(name: "Step-Up", kind: .board, isArchived: true)
        context.insert(gear)

        let updated = context.upsertGear(named: "Step-Up", kind: .board)

        XCTAssertEqual(updated.persistentModelID, gear.persistentModelID)
        XCTAssertFalse(updated.isArchived)
    }

    func testResetAllDataClearsEntities() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let spot = TestFixture.spot()
        let gear = TestFixture.gear()
        let buddy = TestFixture.buddy()
        let session = TestFixture.session(spot: spot, gear: [gear], buddies: [buddy])

        context.insert(spot)
        context.insert(gear)
        context.insert(buddy)
        context.insert(session)

        try context.resetAllData()

        XCTAssertTrue(try context.fetch(FetchDescriptor<Spot>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Gear>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Buddy>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SurfSession>()).isEmpty)
    }
}
