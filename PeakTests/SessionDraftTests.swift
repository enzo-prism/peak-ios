import XCTest

@testable import Peak

final class SessionDraftTests: XCTestCase {
    func testSelectSpotUpdatesNameAndSelection() {
        var draft = SessionDraft()
        let spot = TestFixture.spot(name: "Ocean Beach")

        draft.selectSpot(spot)

        XCTAssertEqual(draft.selectedSpot?.name, "Ocean Beach")
        XCTAssertEqual(draft.spotName, "Ocean Beach")
    }

    func testToggleGearAddsAndRemoves() {
        var draft = SessionDraft()
        let gear = TestFixture.gear(name: "Twin Pin")

        draft.toggleGear(gear)
        XCTAssertEqual(draft.selectedGear.count, 1)

        draft.toggleGear(gear)
        XCTAssertTrue(draft.selectedGear.isEmpty)
    }

    func testToggleBuddyAddsAndRemoves() {
        var draft = SessionDraft()
        let buddy = TestFixture.buddy(name: "Sam")

        draft.toggleBuddy(buddy)
        XCTAssertEqual(draft.selectedBuddies.count, 1)

        draft.toggleBuddy(buddy)
        XCTAssertTrue(draft.selectedBuddies.isEmpty)
    }

    func testApplySurfConditionsPopulatesFields() {
        var draft = SessionDraft()
        let snapshot = SurfConditionsSnapshot(
            source: "Open-Meteo",
            fetchedAt: TestCalendar.makeDate(year: 2026, month: 2, day: 5, hour: 8),
            latitude: 33.3,
            longitude: -117.6,
            windSpeedKph: 12,
            windDirectionDegrees: 280,
            waveHeightMeters: 1.4,
            swellWaveHeightMeters: 1.2,
            swellWavePeriodSeconds: 12,
            swellWaveDirectionDegrees: 265,
            windWaveHeightMeters: 0.6,
            windWavePeriodSeconds: 6,
            windWaveDirectionDegrees: 300,
            seaSurfaceTemperatureC: 17.5
        )

        draft.applySurfConditions(snapshot)

        XCTAssertEqual(draft.windSpeedKph, 12)
        XCTAssertEqual(draft.waveHeightMeters, 1.4)
        XCTAssertEqual(draft.conditionsSource, "Open-Meteo")
        XCTAssertEqual(draft.conditionsLatitude, 33.3)
        XCTAssertEqual(draft.conditionsLongitude, -117.6)
        XCTAssertTrue(draft.hasSurfConditions)
    }
}
