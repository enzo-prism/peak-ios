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
            waveCount: nil,
            topSpeedKph: nil,
            longestRideSeconds: nil,
            longestRideMeters: nil,
            paddleDistanceMeters: nil,
            waveStatsSource: nil,
            linkedWorkoutID: nil,
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

    func testMergeImportDoesNotDuplicateSessionOnReimportIntoSameLibrary() throws {
        // A real session's createdAt (from Date()) carries sub-millisecond
        // precision; the export id is truncated to milliseconds. Re-importing an
        // export back into the library that still holds the original must match on
        // the millisecond key, not exact Date equality, or the whole library
        // duplicates on a merge restore.
        let createdAt = Date(timeIntervalSince1970: 1_770_000_000.123456)

        let container = try makeContainer()
        let context = ModelContext(container)
        let spot = Spot(name: "Trestles", createdAt: createdAt)
        let session = SurfSession(date: createdAt, spot: spot, rating: 4, createdAt: createdAt, updatedAt: createdAt)
        context.insert(spot)
        context.insert(session)

        let export = PeakExportManager.makeExport(
            sessions: [session],
            spots: [spot],
            gear: [],
            buddies: [],
            now: createdAt
        )
        let decoded = try PeakExportManager.decodeJSON(try PeakExportManager.jsonData(from: export))

        try PeakExportManager.applyImport(decoded, mode: .merge, context: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1, "Re-importing an export must not duplicate the existing session")
    }

    func testMergeRestoreDoesNotDuplicateMediaOnExistingSession() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_770_000_000.123456)

        let container = try makeContainer()
        let context = ModelContext(container)
        let spot = Spot(name: "Uluwatu", createdAt: createdAt)
        let photo = SessionMedia(kind: .photo, photoData: Data([0x01, 0x02]), sortIndex: 0, createdAt: createdAt)
        let session = SurfSession(date: createdAt, spot: spot, media: [photo], rating: 4, createdAt: createdAt, updatedAt: createdAt)
        context.insert(spot)
        context.insert(session)

        let backupURL = try await BackupManager.makeBackupFile(
            sessions: [session],
            spots: [spot],
            gear: [],
            buddies: [],
            now: createdAt
        )
        defer { try? FileManager.default.removeItem(at: backupURL) }

        // Restore the same backup into the library that still holds the original.
        try await BackupManager.restore(from: backupURL, mode: .merge, context: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.media.count, 1, "Merge restore must not duplicate media on an existing session")
    }

    /// A manifest video entry whose base64 payload is corrupt must be dropped,
    /// not inserted as a `SessionMedia(videoFileName: nil)` row — that tile
    /// would be permanently broken and invisible to file cleanup.
    func testRestoreDropsVideoEntryWithCorruptBase64() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_770_000_000)
        let createdString = ExportDateFormatter.string(from: createdAt)

        let sessionExport = PeakExportManager.makeExport(
            sessions: [SurfSession(date: createdAt, spot: nil, rating: 3, createdAt: createdAt, updatedAt: createdAt)],
            spots: [], gear: [], buddies: [],
            now: createdAt
        )
        let corruptVideo = SessionMediaBackupEntry(
            id: "corrupt",
            sessionId: createdString,
            kind: "video",
            sortIndex: 0,
            cropOriginX: 0, cropOriginY: 0, cropWidth: 1, cropHeight: 1,
            createdAt: createdString,
            photoBase64: nil,
            thumbnailBase64: nil,
            videoBase64: "!!!not-base64!!!"
        )
        let file = PeakBackupFile(
            export: sessionExport,
            manifest: PeakBackupManifest(
                backupVersion: BackupManager.backupVersion,
                exportedAt: createdString,
                media: [corruptVideo]
            )
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-video-test.peakbackup")
        try BackupManager.encodeBackupFile(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let container = try makeContainer()
        let context = ModelContext(container)
        try await BackupManager.restore(from: url, mode: .merge, context: context)

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.media.count, 0, "Corrupt video payloads must be skipped, not restored as broken rows")
    }

    func testImportClampsOutOfRangeRating() throws {
        let createdString = ExportDateFormatter.string(from: TestCalendar.makeDate(year: 2026, month: 2, day: 1, hour: 6))
        let sessionExport = SessionExport(
            id: createdString,
            date: createdString,
            spotId: nil,
            spotName: nil,
            rating: 99,
            durationMinutes: nil,
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
            waveCount: nil,
            topSpeedKph: nil,
            longestRideSeconds: nil,
            longestRideMeters: nil,
            paddleDistanceMeters: nil,
            waveStatsSource: nil,
            linkedWorkoutID: nil,
            notes: "",
            buddyIds: [],
            gearIds: [],
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

        let sessions = try context.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.first?.rating, 5, "Out-of-range imported rating must clamp to the 0...5 scale")
    }

    func testSessionsCSVNeutralizesFormulaInjectionButKeepsNegativeNumbers() {
        let session = SurfSession(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 1),
            spot: Spot(name: "=SUM(A1:A9)"),
            conditionsLongitude: -117.593,
            notes: "@cmd"
        )

        let csv = PeakExportManager.sessionsCSV(sessions: [session])

        XCTAssertTrue(csv.contains("'=SUM(A1:A9)"), "Formula-leading text must be quote-prefixed")
        XCTAssertTrue(csv.contains("'@cmd"), "@-leading text must be quote-prefixed")
        XCTAssertTrue(csv.contains("-117.593"), "Negative numbers must survive")
        XCTAssertFalse(csv.contains("'-117.593"), "Legitimate negative numbers must not be mangled into text")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SurfSession.self, Spot.self, Gear.self, Buddy.self, SessionMedia.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Wave stats (3.0)

    /// Wave stats must survive backup and restore.
    ///
    /// This is the failure mode that would matter most in practice: a user who
    /// hand-corrects a season of wave counts, restores from backup, and silently
    /// loses every one of them. The `.edited` marker is asserted too — without
    /// it a restored session would look freshly derivable and a later workout
    /// import could overwrite the corrections.
    func testWaveStatsRoundTripThroughExportAndImport() throws {
        let createdAt = TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 6)
        let sourceContext = ModelContext(try makeContainer())

        let spot = Spot(name: "Trestles", createdAt: createdAt)
        let session = SurfSession(
            date: createdAt,
            spot: spot,
            rating: 5,
            durationMinutes: 90,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        session.waveCount = 13
        session.topSpeedKph = 27.5
        session.longestRideSeconds = 19.5
        session.longestRideMeters = 88.25
        session.paddleDistanceMeters = 1_430.5
        session.waveStats = .edited
        session.linkedWorkoutID = "8B2A1C4D-0000-4000-8000-000000000000"
        sourceContext.insert(spot)
        sourceContext.insert(session)

        let export = PeakExportManager.makeExport(
            sessions: [session], spots: [spot], gear: [], buddies: [], now: createdAt
        )
        let decoded = try PeakExportManager.decodeJSON(PeakExportManager.jsonData(from: export))

        let targetContext = ModelContext(try makeContainer())
        try PeakExportManager.applyImport(decoded, mode: .merge, context: targetContext)

        let sessions = try targetContext.fetch(FetchDescriptor<SurfSession>())
        XCTAssertEqual(sessions.count, 1)
        let round = try XCTUnwrap(sessions.first)
        XCTAssertEqual(round.waveCount, 13)
        XCTAssertEqual(round.topSpeedKph ?? 0, 27.5, accuracy: 0.0001)
        XCTAssertEqual(round.longestRideSeconds ?? 0, 19.5, accuracy: 0.0001)
        XCTAssertEqual(round.longestRideMeters ?? 0, 88.25, accuracy: 0.0001)
        XCTAssertEqual(round.paddleDistanceMeters ?? 0, 1_430.5, accuracy: 0.0001)
        XCTAssertEqual(round.waveStats, .edited, "the human-owned marker must survive a restore")
        XCTAssertEqual(round.linkedWorkoutID, "8B2A1C4D-0000-4000-8000-000000000000")
    }

    /// Sessions with no wave stats round-trip as nil, not as zero — a restore must
    /// not invent "0 waves" for every session a user ever logged by hand.
    func testSessionsWithoutWaveStatsRoundTripAsNil() throws {
        let createdAt = TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 6)
        let sourceContext = ModelContext(try makeContainer())
        let spot = Spot(name: "Trestles", createdAt: createdAt)
        let session = SurfSession(date: createdAt, spot: spot, createdAt: createdAt, updatedAt: createdAt)
        sourceContext.insert(spot)
        sourceContext.insert(session)

        let export = PeakExportManager.makeExport(
            sessions: [session], spots: [spot], gear: [], buddies: [], now: createdAt
        )
        let decoded = try PeakExportManager.decodeJSON(PeakExportManager.jsonData(from: export))
        let targetContext = ModelContext(try makeContainer())
        try PeakExportManager.applyImport(decoded, mode: .merge, context: targetContext)

        let round = try XCTUnwrap(try targetContext.fetch(FetchDescriptor<SurfSession>()).first)
        XCTAssertNil(round.waveCount)
        XCTAssertNil(round.waveStatsSource)
        XCTAssertNil(round.linkedWorkoutID)
        XCTAssertFalse(round.hasWaveStats)
    }

    /// A backup written before 3.0 has no wave-stat keys at all and must still
    /// import, leaving the new columns nil rather than failing the whole restore.
    func testPreWaveStatsBackupStillImports() throws {
        let createdAt = TestCalendar.makeDate(year: 2026, month: 2, day: 1, hour: 6)
        let createdString = ExportDateFormatter.string(from: createdAt)
        let json = """
        {
          "schema_version": "\(PeakExportManager.schemaVersion)",
          "exported_at": "\(createdString)",
          "sessions": [{
            "id": "\(createdString)",
            "date": "\(createdString)",
            "spot_name": "Legacy Point",
            "rating": 3,
            "notes": "",
            "buddy_ids": [],
            "gear_ids": [],
            "created_at": "\(createdString)",
            "updated_at": "\(createdString)"
          }],
          "spots": [], "gear": [], "buddies": []
        }
        """

        let decoded = try PeakExportManager.decodeJSON(Data(json.utf8))
        let context = ModelContext(try makeContainer())
        try PeakExportManager.applyImport(decoded, mode: .merge, context: context)

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<SurfSession>()).first)
        XCTAssertEqual(session.rating, 3)
        XCTAssertNil(session.waveCount)
        XCTAssertNil(session.waveStatsSource)
        XCTAssertFalse(session.hasWaveStats)
    }

    /// The CSV header and every row must stay the same width, or a spreadsheet
    /// silently misaligns every column after the new ones.
    func testCSVIncludesWaveStatColumnsAndStaysRectangular() throws {
        let createdAt = TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 6)
        let context = ModelContext(try makeContainer())
        let spot = Spot(name: "Trestles", createdAt: createdAt)
        let withStats = SurfSession(date: createdAt, spot: spot, rating: 5, createdAt: createdAt, updatedAt: createdAt)
        withStats.waveCount = 7
        withStats.topSpeedKph = 24
        withStats.waveStats = .auto
        let without = SurfSession(date: createdAt, spot: spot, rating: 2, createdAt: createdAt, updatedAt: createdAt)
        context.insert(spot)
        context.insert(withStats)
        context.insert(without)

        let csv = PeakExportManager.sessionsCSV(sessions: [withStats, without])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("waveCount"))
        XCTAssertTrue(lines[0].contains("waveStatsSource"))

        let width = lines[0].split(separator: ",", omittingEmptySubsequences: false).count
        for line in lines.dropFirst() {
            XCTAssertEqual(
                line.split(separator: ",", omittingEmptySubsequences: false).count,
                width,
                "row width diverged from the header: \(line)"
            )
        }
    }
}
