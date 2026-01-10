import SwiftData
import XCTest

@testable import Peak

final class ModelMigrationTests: XCTestCase {
    func testContainerInitializesWithMigrationPlan() {
        let schema = Schema(versionedSchema: PeakSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        XCTAssertNoThrow(try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self, configurations: [configuration]))
    }
}
