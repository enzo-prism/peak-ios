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

    func testSearchFoldedRemovesDiacriticsAndCase() {
        XCTAssertEqual("São Pedro".searchFolded, "sao pedro")
        XCTAssertEqual("ULUWATU".searchFolded, "uluwatu")
    }
}

final class SurfBreakCatalogTests: XCTestCase {
    private func makeCatalog() -> SurfBreakCatalog {
        SurfBreakCatalog(breaks: [
            SurfBreak(name: "Uluwatu", region: "Bali", country: "Indonesia", latitude: -8.8151, longitude: 115.0883),
            SurfBreak(name: "Trestles", region: "San Clemente, California", country: "USA", latitude: 33.385, longitude: -117.589),
            SurfBreak(name: "São Pedro", region: "Lisbon", country: "Portugal", latitude: 38.7, longitude: -9.3),
            SurfBreak(name: "Pipeline", region: "North Shore, Oahu", country: "USA", latitude: 21.665, longitude: -158.053),
        ])
    }

    func testPrefixMatch() {
        XCTAssertEqual(makeCatalog().search("uluw").first?.name, "Uluwatu")
    }

    func testDiacriticInsensitiveMatch() {
        XCTAssertEqual(makeCatalog().search("sao").first?.name, "São Pedro")
    }

    func testShortQueryReturnsEmpty() {
        XCTAssertTrue(makeCatalog().search("u").isEmpty)
    }

    func testExcludingKeysHidesSavedBreak() {
        let savedKey = "Uluwatu".normalizedKey
        XCTAssertTrue(makeCatalog().search("uluw", excludingKeys: [savedKey]).isEmpty)
    }

    func testResultsCappedAtLimit() {
        let many = (0..<20).map {
            SurfBreak(name: "Surfspot\($0)", region: "R", country: "C", latitude: 0, longitude: 0)
        }
        XCTAssertEqual(SurfBreakCatalog(breaks: many).search("surfspot", limit: 6).count, 6)
    }

    func testLocationContainsMatch() {
        XCTAssertEqual(makeCatalog().search("clemente").first?.name, "Trestles")
    }

    // Guards the bundled JSON keys against SurfBreak's synthesized Decodable (a mismatch yields []).
    func testBundledCatalogLoadsNonEmpty() {
        XCTAssertGreaterThan(SurfBreakCatalog.shared.count, 50)
    }
}
