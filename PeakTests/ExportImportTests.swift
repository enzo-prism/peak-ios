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
            seaLevelHeightM: nil,
            tideTrend: nil,
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

    // MARK: - Full-data backup (.peakbackup)

    func testBackupFileRoundTripPreservesSessionsAndMedia() async throws {
        let createdAt = TestCalendar.makeDate(year: 2026, month: 3, day: 3, hour: 7)

        let sourceContainer = try makeContainer()
        let sourceContext = ModelContext(sourceContainer)

        let spot = Spot(name: "Uluwatu", createdAt: createdAt)
        let photoBytes = Data([0x10, 0x20, 0x30, 0x40, 0x50])
        let thumbBytes = Data([0xAA, 0xBB])

        // Fake video binary on disk (the test media dir under the temp folder).
        let videoFileName = "backup-test-\(UUID().uuidString).mov"
        let videoBytes = Data((0..<64).map { UInt8($0 & 0xFF) })
        let videoURL = SessionMediaStore.videoURL(for: videoFileName)
        try videoBytes.write(to: videoURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let photoMedia = SessionMedia(
            kind: .photo,
            photoData: photoBytes,
            thumbnailData: thumbBytes,
            sortIndex: 0,
            cropOriginX: 0.1,
            cropOriginY: 0.2,
            cropWidth: 0.7,
            cropHeight: 0.6,
            createdAt: createdAt
        )
        let videoMedia = SessionMedia(
            kind: .video,
            videoFileName: videoFileName,
            sortIndex: 1,
            createdAt: createdAt
        )
        let session = SurfSession(
            date: createdAt,
            spot: spot,
            media: [photoMedia, videoMedia],
            rating: 4,
            notes: "Backup me",
            createdAt: createdAt,
            updatedAt: createdAt
        )
        sourceContext.insert(spot)
        sourceContext.insert(session)

        let backupURL = try await BackupManager.makeBackupFile(
            sessions: [session],
            spots: [spot],
            gear: [],
            buddies: [],
            now: createdAt
        )
        defer { try? FileManager.default.removeItem(at: backupURL) }
        XCTAssertEqual(backupURL.pathExtension, BackupManager.fileExtension)

        // Restore into a FRESH container.
        let targetContainer = try makeContainer()
        let targetContext = ModelContext(targetContainer)
        try await BackupManager.restore(from: backupURL, mode: .merge, context: targetContext)

        let restoredSessions = try targetContext.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(restoredSessions.count, 1)
        let restored = try XCTUnwrap(restoredSessions.first)
        XCTAssertEqual(restored.spot?.name, "Uluwatu")
        XCTAssertEqual(restored.rating, 4)
        XCTAssertEqual(restored.media.count, 2)

        let restoredPhoto = try XCTUnwrap(restored.media.first { $0.kind == .photo })
        XCTAssertEqual(restoredPhoto.photoData, photoBytes)
        XCTAssertEqual(restoredPhoto.thumbnailData, thumbBytes)
        XCTAssertEqual(restoredPhoto.sortIndex, 0)
        XCTAssertEqual(restoredPhoto.cropOriginX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(restoredPhoto.cropOriginY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(restoredPhoto.cropWidth, 0.7, accuracy: 0.0001)
        XCTAssertEqual(restoredPhoto.cropHeight, 0.6, accuracy: 0.0001)

        let restoredVideo = try XCTUnwrap(restored.media.first { $0.kind == .video })
        XCTAssertEqual(restoredVideo.sortIndex, 1)
        let restoredVideoFileName = try XCTUnwrap(restoredVideo.videoFileName)
        let restoredVideoData = try Data(contentsOf: SessionMediaStore.videoURL(for: restoredVideoFileName))
        XCTAssertEqual(restoredVideoData, videoBytes)
    }

    func testBackupFileEncodeDecodeRoundTrip() throws {
        let createdString = ExportDateFormatter.string(from: TestCalendar.makeDate(year: 2026, month: 4, day: 1))
        let export = PeakExport(
            schemaVersion: PeakExportManager.schemaVersion,
            exportedAt: createdString,
            sessions: [],
            spots: [],
            gear: [],
            buddies: []
        )
        let entry = SessionMediaBackupEntry(
            id: "entry-1",
            sessionId: createdString,
            kind: "photo",
            sortIndex: 2,
            cropOriginX: 0.1,
            cropOriginY: 0.2,
            cropWidth: 0.3,
            cropHeight: 0.4,
            createdAt: createdString,
            photoBase64: Data([0x01, 0x02]).base64EncodedString(),
            thumbnailBase64: nil,
            videoBase64: nil
        )
        let manifest = PeakBackupManifest(
            backupVersion: BackupManager.backupVersion,
            exportedAt: createdString,
            media: [entry]
        )
        let file = PeakBackupFile(export: export, manifest: manifest)

        let data = try BackupManager.encodeBackupFile(file)
        let decoded = try BackupManager.decodeBackupFile(data)

        XCTAssertEqual(decoded.manifest.backupVersion, "1")
        XCTAssertEqual(decoded.export.schemaVersion, PeakExportManager.schemaVersion)
        XCTAssertEqual(decoded.manifest.media.count, 1)
        let decodedEntry = try XCTUnwrap(decoded.manifest.media.first)
        XCTAssertEqual(decodedEntry.sessionId, createdString)
        XCTAssertEqual(decodedEntry.kind, "photo")
        XCTAssertEqual(decodedEntry.sortIndex, 2)
        XCTAssertEqual(decodedEntry.cropWidth, 0.3, accuracy: 0.0001)
        XCTAssertEqual(decodedEntry.photoBase64, Data([0x01, 0x02]).base64EncodedString())
        XCTAssertNil(decodedEntry.thumbnailBase64)
        XCTAssertNil(decodedEntry.videoBase64)
    }

    // MARK: - Crash-proof store recovery

    func testRelocateStoreFilesMovesCorruptStoreFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("PeakStoreFixture-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Fabricate a "corrupt" store: main file + sidecars + external-storage support dir.
        let storeName = "default.store"
        try Data("corrupt".utf8).write(to: root.appendingPathComponent(storeName))
        try Data("wal".utf8).write(to: root.appendingPathComponent("\(storeName)-wal"))
        try Data("shm".utf8).write(to: root.appendingPathComponent("\(storeName)-shm"))
        let supportDir = root.appendingPathComponent(".default_SUPPORT", isDirectory: true)
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data("blob".utf8).write(to: supportDir.appendingPathComponent("blob.bin"))

        let now = TestCalendar.makeDate(year: 2026, month: 5, day: 5, hour: 12)
        let archiveDir = try PeakDataStore.relocateStoreFiles(in: root, storeName: storeName, now: now)

        // Originals moved out of the live directory.
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent(storeName).path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("\(storeName)-wal").path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("\(storeName)-shm").path))
        XCTAssertFalse(fm.fileExists(atPath: supportDir.path))

        // Preserved inside the timestamped archive folder.
        XCTAssertTrue(archiveDir.lastPathComponent.hasPrefix("Archived Store"))
        XCTAssertTrue(fm.fileExists(atPath: archiveDir.appendingPathComponent(storeName).path))
        XCTAssertTrue(fm.fileExists(atPath: archiveDir.appendingPathComponent("\(storeName)-wal").path))
        XCTAssertTrue(fm.fileExists(atPath: archiveDir.appendingPathComponent(".default_SUPPORT/blob.bin").path))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
