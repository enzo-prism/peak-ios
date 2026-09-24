import SwiftData
import XCTest

@testable import Peak

final class ModelContextHelpersTests: XCTestCase {
    func testUpsertSpotReturnsExisting() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let first = context.upsertSpot(named: "Trestles")
        let second = context.upsertSpot(named: "Trestles")

        XCTAssertEqual(first.persistentModelID, second.persistentModelID)
    }

    func testUpsertGearUnarchivesExisting() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let gear = TestFixture.gear(name: "Step-Up", kind: .board, isArchived: true)
        context.insert(gear)

        let updated = context.upsertGear(named: "Step-Up", kind: .board)

        XCTAssertEqual(updated.persistentModelID, gear.persistentModelID)
        XCTAssertFalse(updated.isArchived)
    }

    func testSpotCountMatchesInsertedSpots() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        XCTAssertEqual(try context.spotCount(), 0)

        context.insert(Spot(name: "Trestles"))
        context.insert(Spot(name: "Ocean Beach"))

        XCTAssertEqual(try context.spotCount(), 2)
    }

    func testResetAllDataClearsEntities() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

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

    func testMatchingSpotKeyFetchReturnsOnlyThatSpotNewestFirst() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let trestles = TestFixture.spot(name: "Trestles")
        let ocean = TestFixture.spot(name: "Ocean Beach")
        context.insert(trestles)
        context.insert(ocean)

        let older = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 1),
            spot: trestles
        )
        let newer = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 10),
            spot: trestles
        )
        let other = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 20),
            spot: ocean
        )
        context.insert(older)
        context.insert(newer)
        context.insert(other)
        try context.save()

        let fetched = try context.fetch(
            SurfSession.sortedByDateDescending(matchingSpotKey: trestles.key)
        )
        XCTAssertEqual(
            fetched.map(\.persistentModelID),
            [newer.persistentModelID, older.persistentModelID]
        )
    }

    func testInMemoryGearFilterIncludesATwoBoardSessionOncePerBoard() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let boardA = TestFixture.gear(name: "Fish", kind: .board)
        let boardB = TestFixture.gear(name: "Step-Up", kind: .board)
        let unused = TestFixture.gear(name: "Spare", kind: .leash)
        context.insert(boardA)
        context.insert(boardB)
        context.insert(unused)

        let both = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 10),
            gear: [boardA, boardB]
        )
        context.insert(both)
        try context.save()

        let onlyB = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 11),
            gear: [boardB]
        )
        context.insert(onlyB)
        try context.save()

        XCTAssertEqual(both.gear.map(\.key).sorted(), [boardA.key, boardB.key].sorted())
        XCTAssertEqual(onlyB.gear.map(\.key), [boardB.key])

        let sessions = try context.fetch(SurfSession.sortedByDateDescending())
        let forA = sessions.filter { session in
            session.gear.contains { $0.key == boardA.key }
        }
        XCTAssertEqual(forA.map(\.persistentModelID), [both.persistentModelID])

        let forB = sessions.filter { session in
            session.gear.contains { $0.key == boardB.key }
        }
        XCTAssertEqual(
            forB.map(\.persistentModelID),
            [onlyB.persistentModelID, both.persistentModelID]
        )

        let forUnused = sessions.filter { session in
            session.gear.contains { $0.key == unused.key }
        }
        XCTAssertTrue(forUnused.isEmpty)
    }

    func testInMemoryBuddyFilterExcludesUnrelatedSessions() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let kai = TestFixture.buddy(name: "Kai")
        let nia = TestFixture.buddy(name: "Nia")
        context.insert(kai)
        context.insert(nia)

        let withKai = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 8),
            buddies: [kai]
        )
        context.insert(withKai)
        try context.save()

        let withBoth = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 9),
            buddies: [kai, nia]
        )
        context.insert(withBoth)
        try context.save()

        let withNia = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 10),
            buddies: [nia]
        )
        context.insert(withNia)
        try context.save()

        XCTAssertEqual(withKai.buddies.map(\.key), [kai.key])
        XCTAssertEqual(withBoth.buddies.map(\.key).sorted(), [kai.key, nia.key].sorted())
        XCTAssertEqual(withNia.buddies.map(\.key), [nia.key])

        let sessions = try context.fetch(SurfSession.sortedByDateDescending())
        let forKai = sessions.filter { session in
            session.buddies.contains { $0.key == kai.key }
        }
        XCTAssertEqual(
            forKai.map(\.persistentModelID),
            [withBoth.persistentModelID, withKai.persistentModelID]
        )
        XCTAssertFalse(forKai.contains { $0.persistentModelID == withNia.persistentModelID })
    }

    func testMatchingSpotDescriptorPrefetchesRequestedRelationships() {
        let descriptor = SurfSession.sortedByDateDescending(
            matchingSpotKey: "trestles",
            prefetch: [\.spot, \.gear, \.buddies]
        )
        XCTAssertEqual(descriptor.relationshipKeyPathsForPrefetching.count, 3)
        XCTAssertNil(descriptor.fetchLimit)
    }

    func testSessionQueryStampChangesWhenUpdatedAtChanges() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let session = TestFixture.session()
        context.insert(session)
        try context.save()

        let first = SessionQueryStamp.make([session])
        session.updatedAt = session.updatedAt.addingTimeInterval(60)
        let second = SessionQueryStamp.make([session])

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second, SessionQueryStamp.make([session]))
    }

    // MARK: - What a staged save does (and does not) reach

    /// On iOS 18+ a *new* session saved by the editor no longer rebuilds the
    /// view tree. That relies on the staged insert being fetchable from the
    /// library context — the container's main context and the fresh context a
    /// delete/import swaps in alike.
    func testStagedInsertIsFetchableFromTheMainLibraryContext() throws {
        let container = try TestModelContainer.make()
        try assertStagedInsertIsFetchable(from: container.mainContext)
    }

    func testStagedInsertIsFetchableFromARefreshedLibraryContext() throws {
        let container = try TestModelContainer.make()
        let refreshed = ModelContext(container)
        refreshed.autosaveEnabled = true
        try assertStagedInsertIsFetchable(from: refreshed)
    }

    /// Why *edits* still rebuild: a model the library context already holds
    /// keeps its old values after a commit from the staging context. If this
    /// starts failing on a newer OS, edits could skip the rebuild too.
    func testStagedSaveDoesNotRefreshModelsTheLibraryAlreadyHolds() throws {
        let container = try TestModelContainer.make()
        let library = container.mainContext
        let session = TestFixture.session(rating: 2)
        library.insert(session)
        try library.save()

        let staging = try SessionPersistence.stagingContext(from: library)
        try SessionPersistence.resolve(session, in: staging).rating = 5
        try staging.save()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(session.rating, 2)
    }

    private func assertStagedInsertIsFetchable(
        from library: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let spot = TestFixture.spot(name: "Trestles")
        library.insert(spot)
        library.insert(TestFixture.session(spot: spot, rating: 2))
        try library.save()

        let staging = try SessionPersistence.stagingContext(from: library)
        staging.insert(TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 3, hour: 7),
            spot: try SessionPersistence.resolve(spot, in: staging),
            rating: 4
        ))
        try staging.save()

        let fetched = try library.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(fetched.count, 2, "the staged insert is not fetchable from the library context", file: file, line: line)
    }
}
