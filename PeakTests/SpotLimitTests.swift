import SwiftData
import XCTest

@testable import Peak

final class SpotLimitTests: XCTestCase {
    func testSpotLimitBlocksNewSpots() throws {
        let container = try makeContainer()
        let context = container.mainContext

        for index in 0..<Spot.maxCount {
            _ = try context.createSpot(
                name: "Spot \(index)",
                locationName: "Location \(index)",
                latitude: Double(index),
                longitude: Double(index)
            )
        }

        XCTAssertThrowsError(
            try context.createSpot(
                name: "Extra",
                locationName: "Extra",
                latitude: 0,
                longitude: 0
            )
        ) { error in
            XCTAssertTrue(error is SpotLimitError)
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
