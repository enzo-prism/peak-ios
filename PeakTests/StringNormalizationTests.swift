import XCTest

@testable import Peak

final class StringNormalizationTests: XCTestCase {
    func testNormalizedKeyCollapsesWhitespaceAndLowercases() {
        let input = "  San   Onofre \n State   Beach "
        XCTAssertEqual(input.normalizedKey, "san onofre state beach")
    }

    func testTrimmedNonEmptyReturnsNilWhenOnlyWhitespace() {
        XCTAssertNil("   \n\t  ".trimmedNonEmpty)
    }

    func testTrimmedNonEmptyStripsEdges() {
        XCTAssertEqual("  Ocean Beach  ".trimmedNonEmpty, "Ocean Beach")
    }
}
