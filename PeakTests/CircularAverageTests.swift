import XCTest

@testable import Peak

/// Regression coverage for the compass-bearing (circular) mean used when
/// averaging wind/swell directions across a session window. A plain arithmetic
/// mean is wrong across the 0°/360° wrap, so these guard the vector mean.
final class CircularAverageTests: XCTestCase {
    func testWrapsAroundNorth() {
        // 350° and 10° straddle due north; the mean must read ~0°, not 180°.
        let avg = try? XCTUnwrap(SurfConditionsService.circularAverage(values: [350, 10]))
        XCTAssertEqual(shortestAngle(avg ?? -1, 0), 0, accuracy: 0.001)
    }

    func testClusterNearNorthAveragesToNorth() {
        let avg = SurfConditionsService.circularAverage(values: [350, 355, 5, 10])
        XCTAssertNotNil(avg)
        XCTAssertEqual(shortestAngle(avg ?? -1, 0), 0, accuracy: 0.001)
    }

    func testAgreesWithLinearMeanWithinAnArc() {
        // Samples that don't cross the wrap match the arithmetic mean.
        let avg = SurfConditionsService.circularAverage(values: [80, 100])
        XCTAssertEqual(avg ?? -1, 90, accuracy: 0.001)
    }

    func testOpposingSamplesFallBackToLinearMean() {
        // 0° and 180° cancel out; fall back to the linear mean rather than an
        // arbitrary bearing.
        let avg = SurfConditionsService.circularAverage(values: [0, 180])
        XCTAssertEqual(avg ?? -1, 90, accuracy: 0.001)
    }

    func testResultIsNormalizedTo0To360() {
        let avg = SurfConditionsService.circularAverage(values: [270, 350])
        XCTAssertNotNil(avg)
        XCTAssertGreaterThanOrEqual(avg ?? -1, 0)
        XCTAssertLessThan(avg ?? 999, 360)
    }

    func testNilWhenNoSamples() {
        XCTAssertNil(SurfConditionsService.circularAverage(values: []))
        XCTAssertNil(SurfConditionsService.circularAverage(values: [nil, nil]))
    }

    /// Shortest absolute angular distance between two bearings, in [0, 180].
    private func shortestAngle(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }
}
