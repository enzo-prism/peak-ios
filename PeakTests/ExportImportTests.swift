import SwiftData
import XCTest

@testable import Peak

final class ExportImportTests: XCTestCase {
    func testDuplicateTimestampBackupPreservesUUIDsAndOwnPhotosAcrossRepeatedMerge() async throws {
        let source = ModelContext(try makeContainer())
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let a = SurfSession(date: date, spot: nil, notes: "A", createdAt: date)
        let b = SurfSession(date: date, spot: nil, notes: "B", createdAt: date)
        source.insert(a)
        source.insert(b)
        let photoA = SessionMedia(kind: .photo, photoData: Data([1, 2, 3]))
        let photoB = SessionMedia(kind: .photo, photoData: Data([4, 5, 6]))
        source.insert(photoA)
        source.insert(photoB)
        a.media = [photoA]
        b.media = [photoB]
        try source.save()
        let url = try await BackupManager.makeBackupFile(sessions: [a, b], spots: [], gear: [], buddies: [])
        defer { try? FileManager.default.removeItem(at: url) }
        let target = ModelContext(try makeContainer())
        for _ in 0..<2 {
            try await BackupManager.restore(from: url, mode: .merge, context: target)
            let readback = ModelContext(target.container)
            let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
            XCTAssertEqual(sessions.count, 2)
            XCTAssertEqual(Set(sessions.compactMap(\.sessionID)), Set([a, b].compactMap(\.sessionID)))
            XCTAssertEqual(sessions.first { $0.notes == "A" }?.media.map(\.photoData), [Data([1, 2, 3])])
            XCTAssertEqual(sessions.first { $0.notes == "B" }?.media.map(\.photoData), [Data([4, 5, 6])])
        }
    }

    func testAmbiguousLegacyImportRejectsBeforeReplaceDeletesData() throws {
        let context = ModelContext(try makeContainer())
        let original = SurfSession(date: Date(), spot: nil, notes: "Keep me")
        context.insert(original)
        try context.save()
        let exported = PeakExportManager.makeExport(sessions: [original], spots: [], gear: [], buddies: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PeakExportManager.jsonData(from: exported)) as? [String: Any])
        var row = try XCTUnwrap((object["sessions"] as? [[String: Any]])?.first)
        row["id"] = row["created_at"]
        object["sessions"] = [row, row]
        object["schema_version"] = "peak_export_v1"
        let legacy = try PeakExportManager.decodeJSON(JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try PeakExportManager.applyImport(legacy, mode: .replace, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<SurfSession>()).map(\.notes), ["Keep me"])
    }

    func testUniqueLegacyImportMatchesExistingUUID() throws {
        let context = ModelContext(try makeContainer())
        let original = SurfSession(date: Date(), spot: nil)
        context.insert(original)
        try context.save()
        let id = original.sessionID
        let exported = PeakExportManager.makeExport(sessions: [original], spots: [], gear: [], buddies: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PeakExportManager.jsonData(from: exported)) as? [String: Any])
        var row = try XCTUnwrap((object["sessions"] as? [[String: Any]])?.first)
        row["id"] = row["created_at"]
        object["sessions"] = [row]
        object["schema_version"] = "peak_export_v1"
        let legacy = try PeakExportManager.decodeJSON(JSONSerialization.data(withJSONObject: object))
        try PeakExportManager.applyImport(legacy, mode: .merge, context: context)
        let readback = ModelContext(context.container)
        XCTAssertEqual(try readback.fetch(FetchDescriptor<SurfSession>()).compactMap(\.sessionID), [try XCTUnwrap(id)])
    }

    private enum InjectedImportSaveFailure: Error { case failed }

    private func makeDiskImportContainer() throws -> ModelContainer {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImportTransaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(versionedSchema: PeakSchemaV12.self)
        return try ModelContainer(for: schema, migrationPlan: PeakMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: root.appendingPathComponent("test.store"))])
    }

    func testRestoreSaveFailurePreservesPersistedRowsVideosAndUnrelatedEdits() async throws {
        for mode in [ImportMode.merge, .replace] {
            let container = try makeDiskImportContainer()
            let context = ModelContext(container)
            let name = "transaction-original-\(UUID().uuidString).mov"
            let originalURL = SessionMediaStore.videoURL(for: name)
            try FileManager.default.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data([0x21, 0x22, 0x23])
            try bytes.write(to: originalURL)
            defer { SessionMediaStore.deleteVideoFile(named: name) }
            let original = SurfSession(date: Date(), spot: nil, media: [SessionMedia(kind: .video, videoFileName: name)], notes: "Backup version")
            context.insert(original)
            try context.save()
            let backup = try await BackupManager.makeBackupFile(sessions: [original], spots: [], gear: [], buddies: [])
            defer { try? FileManager.default.removeItem(at: backup) }
            original.notes = "Pending local edit"
            let originalID = original.sessionID
            let beforeFiles = Set(try FileManager.default.contentsOfDirectory(atPath: originalURL.deletingLastPathComponent().path))
            do {
                try await BackupManager.restore(from: backup, mode: mode, context: context, save: { _ in
                    XCTAssertEqual(try Data(contentsOf: originalURL), bytes, "Original must survive until commit")
                    throw InjectedImportSaveFailure.failed
                })
                XCTFail("Injected commit failure must be reported")
            } catch InjectedImportSaveFailure.failed { }
            XCTAssertEqual(original.notes, "Pending local edit")
            XCTAssertEqual(original.media.first?.videoFileName, name)
            XCTAssertFalse(context.hasChanges)
            let fresh = ModelContext(container)
            let persisted = try fresh.fetch(FetchDescriptor<SurfSession>())
            XCTAssertEqual(persisted.count, 1)
            XCTAssertEqual(persisted.first?.sessionID, originalID)
            XCTAssertEqual(persisted.first?.notes, "Pending local edit", "Rollback must not discard caller edits")
            XCTAssertEqual(persisted.first?.media.first?.videoFileName, name)
            XCTAssertEqual(try Data(contentsOf: originalURL), bytes)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: originalURL.deletingLastPathComponent().path)), beforeFiles, "Failed restore must remove staged videos")
        }
    }

    func testRestoreCommitsMergeAndReplaceBeforeDeletingOriginalVideos() async throws {
        for mode in [ImportMode.merge, .replace] {
            let container = try makeDiskImportContainer()
            let context = ModelContext(container)
            let name = "transaction-success-\(UUID().uuidString).mov"
            let originalURL = SessionMediaStore.videoURL(for: name)
            try FileManager.default.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data([0x31, 0x32, 0x33])
            try bytes.write(to: originalURL)
            defer { SessionMediaStore.deleteVideoFile(named: name) }
            let original = SurfSession(date: Date(), spot: nil, media: [SessionMedia(kind: .video, videoFileName: name)], notes: "Saved backup")
            context.insert(original)
            try context.save()
            let backup = try await BackupManager.makeBackupFile(sessions: [original], spots: [], gear: [], buddies: [])
            defer { try? FileManager.default.removeItem(at: backup) }
            var committed = false
            try await BackupManager.restore(from: backup, mode: mode, context: context, save: { transaction in
                XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
                try transaction.save()
                committed = true
            })
            XCTAssertTrue(committed)
            XCTAssertFalse(context.hasChanges)
            XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
            let readback = ModelContext(container)
            let persisted = try readback.fetch(FetchDescriptor<SurfSession>())
            XCTAssertEqual(persisted.count, 1)
            let restoredName = try XCTUnwrap(persisted.first?.media.first?.videoFileName)
            defer { SessionMediaStore.deleteVideoFile(named: restoredName) }
            XCTAssertNotEqual(restoredName, name)
            XCTAssertEqual(try Data(contentsOf: SessionMediaStore.videoURL(for: restoredName)), bytes)
        }
    }

    func testJSONReplaceSaveFailureLeavesOriginalPersistedVideoIntact() throws {
        let container = try makeDiskImportContainer()
        let context = ModelContext(container)
        let name = "json-transaction-\(UUID().uuidString).mov"
        let originalURL = SessionMediaStore.videoURL(for: name)
        try FileManager.default.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data([0x41, 0x42])
        try bytes.write(to: originalURL)
        defer { SessionMediaStore.deleteVideoFile(named: name) }
        let original = SurfSession(date: Date(), spot: nil, media: [SessionMedia(kind: .video, videoFileName: name)], notes: "Keep me")
        context.insert(original)
        try context.save()
        let empty = PeakExportManager.makeExport(sessions: [], spots: [], gear: [], buddies: [])
        XCTAssertThrowsError(try PeakExportManager.applyImport(empty, mode: .replace, context: context, save: { _ in
            throw InjectedImportSaveFailure.failed
        }))
        let failureReadback = ModelContext(container)
        XCTAssertEqual(try failureReadback.fetch(FetchDescriptor<SurfSession>()).map(\.notes), ["Keep me"])
        XCTAssertEqual(original.notes, "Keep me", "Failure must leave caller models usable")
        XCTAssertEqual(try Data(contentsOf: originalURL), bytes)
        try PeakExportManager.applyImport(empty, mode: .replace, context: context)
        let successReadback = ModelContext(container)
        XCTAssertTrue(try successReadback.fetch(FetchDescriptor<SurfSession>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    func testCommittedImportRequestsFreshUIContextWithUpdatedLibrary() async throws {
        let container = try makeDiskImportContainer()
        let context = ModelContext(container)
        let previousIntentContainer = PeakIntentStore.container
        defer {
            if let previousIntentContainer { PeakIntentStore.register(previousIntentContainer) }
        }
        let original = SurfSession(date: Date(), spot: nil, notes: "Original")
        context.insert(original)
        try context.save()
        PeakIntentStore.register(container, context: context)
        XCTAssertEqual(PeakIntentStore.sessions().map(\.notes), ["Original"])
        let replacement = SurfSession(date: Date(), spot: nil, notes: "Imported")
        let payload = PeakExportManager.makeExport(sessions: [replacement], spots: [], gear: [], buddies: [])
        let refreshed = expectation(forNotification: .peakLibraryDidImport, object: container)
        try PeakExportManager.applyImport(payload, mode: .replace, context: context)
        await fulfillment(of: [refreshed], timeout: 1)
        // The UI refresh listener creates this context instead of reusing the
        // original context's cached model graph.
        let refreshedContext = ModelContext(container)
        PeakIntentStore.register(container, context: refreshedContext)
        XCTAssertEqual(PeakIntentStore.sessions().map(\.notes), ["Imported"])
        XCTAssertEqual(try refreshedContext.fetch(FetchDescriptor<SurfSession>()).map(\.notes), ["Imported"])
        XCTAssertFalse(context.hasChanges)
    }

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
        let readback = ModelContext(targetContext.container)

        let spots = try readback.fetch(FetchDescriptor<Spot>())
        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())

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
        let importedGear = try readback.fetch(FetchDescriptor<Gear>()).first { $0.name == "6'2\" Fish" }
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
        let readback = ModelContext(targetContext.container)

        let spots = try readback.fetch(FetchDescriptor<Spot>())
        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())

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
        let readback = ModelContext(context.container)

        let spots = try readback.fetch(FetchDescriptor<Spot>())
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots.first?.name, "New Spot")

        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
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
        let readback = ModelContext(targetContext.container)

        let restoredSessions = try readback.fetch(FetchDescriptor<SurfSession>())
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

    func testRecoveryVideoCopyFailureResumesBeforeOpeningFreshStore() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root, copyItem: { source, destination in
            if source.lastPathComponent == "SessionMedia" { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.copyItem(at: source, to: destination)
        }))
        try assertRecoveryBytes(in: root)
        let interrupted = try XCTUnwrap(PeakDataStore.pendingRecovery(in: root))
        XCTAssertEqual(interrupted.phase, .copying)
        XCTAssertNil(interrupted.archivedPath, "Missing videos means the copy is incomplete")
        let incomplete = root.appendingPathComponent(try XCTUnwrap(interrupted.archiveDirectory))
        let memory = try makeContainer()
        var preserved: URL?
        let result = PeakDataStore.loadPersistent(open: {
            XCTAssertNotNil(preserved, "Must complete preservation before opening disk")
            return memory
        }, fallback: {
            XCTFail("A retry after storage is freed should succeed")
            return memory
        }, recover: {
            let archive = try PeakDataStore.relocateStoreFiles(in: root)
            preserved = archive
            return archive
        }, pending: { try PeakDataStore.pendingRecovery(in: root) })
        let archive = try XCTUnwrap(preserved)
        XCTAssertEqual(result.outcome, .recoveredFresh(archivedPath: archive.path))
        try assertRecoveryBytes(in: archive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: incomplete.path), "Retry must reclaim its incomplete copy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("SessionMedia").path))
        XCTAssertNil(try PeakDataStore.pendingRecovery(in: root))
    }

    func testRecoveryLegacyCopyMarkerCanResumeWithoutRemovingOriginalsEarly() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        // Before phases existed, nil archive meant that source removal had not begun.
        try Data(#"{"details":"Copy interrupted"}"#.utf8).write(to: root.appendingPathComponent(PeakDataStore.recoveryMarkerName))
        XCTAssertEqual(try PeakDataStore.pendingRecovery(in: root)?.phase, .copying)
        let archive = try PeakDataStore.relocateStoreFiles(in: root)
        try assertRecoveryBytes(in: archive)
    }

    func testCorruptHistoricalRecoveryReceiptDoesNotBlockHealthyLibrary() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("damaged historical receipt".utf8).write(to: root.appendingPathComponent(PeakDataStore.recoveryRecordName))
        XCTAssertNil(try PeakDataStore.preservedArchive(in: root))
        let memory = try makeContainer()
        let result = PeakDataStore.loadPersistent(open: { memory }, fallback: {
            XCTFail("An advisory receipt must not disable persistence")
            return memory
        }, recover: {
            XCTFail("A healthy library must not be archived")
            return root
        }, pending: { try PeakDataStore.pendingRecovery(in: root) }, preservedArchive: {
            throw CocoaError(.fileReadCorruptFile)
        })
        XCTAssertEqual(result.outcome, .normal)
        try assertRecoveryBytes(in: root)
    }

    func testRecoveryRelativeReceiptSurvivesSandboxDirectoryMove() throws {
        let root = try makeRecoveryFixture()
        let movedRoot = root.appendingPathExtension("relocated")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: movedRoot)
        }
        let archive = try PeakDataStore.relocateStoreFiles(in: root)
        let receiptData = try Data(contentsOf: root.appendingPathComponent(PeakDataStore.recoveryRecordName))
        let stored = try JSONDecoder().decode(StoreRecoveryIssue.self, from: receiptData)
        XCTAssertNil(stored.archivedPath, "Persist relative identifiers, never sandbox absolute paths")
        XCTAssertEqual(stored.archiveDirectory, archive.lastPathComponent)
        try FileManager.default.moveItem(at: root, to: movedRoot)
        let relocated = movedRoot.appendingPathComponent(archive.lastPathComponent)
        XCTAssertEqual(try PeakDataStore.preservedArchive(in: movedRoot), relocated.path)
        try assertRecoveryBytes(in: relocated)
    }

    func testLegacyAbsoluteRecoveryReceiptRebasesToCurrentSandbox() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try PeakDataStore.relocateStoreFiles(in: root)
        let legacy = StoreRecoveryIssue(archivedPath: "/old-sandbox/Library/Application Support/\(archive.lastPathComponent)", details: "Legacy receipt")
        try JSONEncoder().encode(legacy).write(to: root.appendingPathComponent(PeakDataStore.recoveryRecordName))
        XCTAssertEqual(try PeakDataStore.preservedArchive(in: root), archive.path)
        try assertRecoveryBytes(in: archive)
    }

    func testPendingRemovalStaysBlockedAfterSandboxDirectoryMove() throws {
        let root = try makeRecoveryFixture()
        let movedRoot = root.appendingPathExtension("relocated")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: movedRoot)
        }
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root, removeItem: { _ in throw CocoaError(.fileWriteNoPermission) }))
        let original = try XCTUnwrap(PeakDataStore.pendingRecovery(in: root))
        try FileManager.default.moveItem(at: root, to: movedRoot)
        let pending = try XCTUnwrap(PeakDataStore.pendingRecovery(in: movedRoot))
        XCTAssertEqual(pending.phase, .removing)
        let relocatedArchive = movedRoot.appendingPathComponent(try XCTUnwrap(original.archiveDirectory))
        XCTAssertEqual(pending.archivedPath, relocatedArchive.path)
        XCTAssertFalse(PeakDataStore.canOpenStore(in: movedRoot))
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: movedRoot))
        try assertRecoveryBytes(in: relocatedArchive)
    }

    func testRecoveryReceiptCannotResolveOutsideApplicationSupport() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = StoreRecoveryIssue(archivedPath: nil, details: "Invalid receipt", phase: .removing, archiveDirectory: "../Archived Store outside")
        try JSONEncoder().encode(invalid).write(to: root.appendingPathComponent(PeakDataStore.recoveryRecordName))
        XCTAssertNil(try PeakDataStore.preservedArchive(in: root))
    }

    func testRecoveryReceiptKeepsExportAvailableOnNextNormalLaunch() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try PeakDataStore.relocateStoreFiles(in: root)
        XCTAssertNil(try PeakDataStore.pendingRecovery(in: root), "Completed recovery must unblock the fresh store")
        XCTAssertEqual(try PeakDataStore.preservedArchive(in: root), archive.path)
        let memory = try makeContainer()
        let result = PeakDataStore.loadPersistent(open: { memory }, fallback: {
            XCTFail("A saved receipt must not block a healthy current library")
            return memory
        }, recover: {
            XCTFail("A healthy current library must not be archived again")
            return archive
        }, pending: { try PeakDataStore.pendingRecovery(in: root) }, preservedArchive: {
            try PeakDataStore.preservedArchive(in: root)
        })
        XCTAssertEqual(result.outcome, .recoveredFresh(archivedPath: archive.path))
        try assertRecoveryBytes(in: archive)
    }

    func testIntentDiskAccessBlocksPendingAndUnreadableRecoveryMarkers() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(PeakDataStore.canOpenStore(in: root))
        let marker = root.appendingPathComponent(PeakDataStore.recoveryMarkerName)
        let issue = StoreRecoveryIssue(archivedPath: nil, details: "Incomplete preservation")
        try JSONEncoder().encode(issue).write(to: marker)
        XCTAssertFalse(PeakDataStore.canOpenStore(in: root))
        try Data("invalid marker".utf8).write(to: marker)
        XCTAssertFalse(PeakDataStore.canOpenStore(in: root), "Unreadable recovery state must fail closed for cold intents")
        let missingPhase = StoreRecoveryIssue(archivedPath: nil, details: "Damaged relative marker", archiveDirectory: "Archived Store incomplete")
        try JSONEncoder().encode(missingPhase).write(to: marker)
        XCTAssertThrowsError(try PeakDataStore.pendingRecovery(in: root))
        XCTAssertFalse(PeakDataStore.canOpenStore(in: root), "Missing phase in a new marker must not be treated as resumable")
        try assertRecoveryBytes(in: root)
    }

    func testRecoveryExportCreatesZIPWithoutChangingArchive() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = try PeakDataStore.relocateStoreFiles(in: root)
        let exported = try PeakDataStore.recoveryExport(archivedPath: archive.path)
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertEqual(exported.pathExtension, "zip")
        let zipBytes = try Data(contentsOf: exported)
        XCTAssertEqual(Array(zipBytes.prefix(2)), [0x50, 0x4b])
        XCTAssertNotNil(zipBytes.range(of: Data("SessionMedia/session-video.mov".utf8)), "ZIP must include the separately stored session video")
        try assertRecoveryBytes(in: archive)
    }

    func testStoreLoadNormalDoesNotAttemptRecovery() throws {
        let memory = try makeContainer()
        let result = PeakDataStore.loadPersistent(open: { memory }, fallback: {
            XCTFail("Normal open should not use fallback")
            return memory
        }, recover: {
            XCTFail("Normal open should not archive")
            return URL(fileURLWithPath: "/unused")
        }, pending: { nil })
        XCTAssertEqual(result.outcome, .normal)
    }

    func testStoreLoadFreshSuccessReportsActualArchive() throws {
        let memory = try makeContainer()
        var opens = 0
        let result = PeakDataStore.loadPersistent(open: {
            opens += 1
            if opens == 1 { throw CocoaError(.fileReadCorruptFile) }
            return memory
        }, fallback: {
            XCTFail("Fresh store opened successfully")
            return memory
        }, recover: { URL(fileURLWithPath: "/preserved-library") }, pending: { nil })
        XCTAssertEqual(opens, 2)
        XCTAssertEqual(result.outcome, .recoveredFresh(archivedPath: "/preserved-library"))
    }

    func testStoreLoadUnreadableRecoveryMarkerDoesNotOpenDisk() throws {
        let memory = try makeContainer()
        let result = PeakDataStore.loadPersistent(open: {
            XCTFail("An unreadable marker cannot prove disk is safe")
            return memory
        }, fallback: { memory }, recover: {
            XCTFail("Must not overwrite unknown recovery state")
            return URL(fileURLWithPath: "/unused")
        }, pending: { throw CocoaError(.fileReadCorruptFile) })
        guard case .inMemoryFallback(let issue) = result.outcome else { return XCTFail("Expected temporary store") }
        XCTAssertTrue(issue.details.contains("Could not check previous recovery"))
    }

    func testRecoveryCopyFailureLeavesEveryOriginalAndBlocksReopening() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var copied = 0
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root, copyItem: { source, destination in
            copied += 1
            if copied == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.copyItem(at: source, to: destination)
        })) { error in
            XCTAssertNil((error as? StoreRecoveryIssue)?.archivedPath, "A partial copy must never be offered as a complete archive")
        }
        XCTAssertEqual(copied, 2)
        try assertRecoveryBytes(in: root)
        let pending = try XCTUnwrap(PeakDataStore.pendingRecovery(in: root))
        XCTAssertNil(pending.archivedPath)
    }

    func testRecoveryRemovalFailureKeepsCompleteArchiveAndDurableMarker() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var removed = 0
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root, removeItem: { url in
            removed += 1
            if removed == 2 { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })) { error in
            XCTAssertNotNil((error as? StoreRecoveryIssue)?.archivedPath)
        }
        XCTAssertEqual(removed, 2)
        let pending = try XCTUnwrap(PeakDataStore.pendingRecovery(in: root))
        let archive = URL(fileURLWithPath: try XCTUnwrap(pending.archivedPath))
        try assertRecoveryBytes(in: archive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("default.store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("default.store-wal").path))
        // A second preservation attempt must not overwrite the complete copy
        // with the incomplete set of remaining source files.
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root))
        try assertRecoveryBytes(in: archive)
    }

    func testRecoveryMarkerRemovalFailureStillBlocksNextLaunch() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root, removeItem: { url in
            if url.lastPathComponent == PeakDataStore.recoveryMarkerName { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        }))
        let pending = try XCTUnwrap(PeakDataStore.pendingRecovery(in: root))
        try assertRecoveryBytes(in: URL(fileURLWithPath: XCTUnwrap(pending.archivedPath)))
    }

    func testRecoveryUsesUniqueArchiveForIdenticalTimestamps() throws {
        let root = try makeRecoveryFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try PeakDataStore.relocateStoreFiles(in: root, now: now)
        try Data("next".utf8).write(to: root.appendingPathComponent("default.store"))
        let second = try PeakDataStore.relocateStoreFiles(in: root, now: now)
        XCTAssertNotEqual(first, second)
        try assertRecoveryBytes(in: first)
        XCTAssertEqual(try Data(contentsOf: second.appendingPathComponent("default.store")), Data("next".utf8))
        XCTAssertNil(try PeakDataStore.pendingRecovery(in: root))
    }

    func testRecoveryMissingSourcesDoesNotClaimPreservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try PeakDataStore.relocateStoreFiles(in: root))
    }

    func testStoreLoadDoesNotRetryDiskWhenPreservationFails() throws {
        let memory = try makeContainer()
        var opens = 0
        let issue = StoreRecoveryIssue(archivedPath: nil, details: "Injected copy failure")
        let result = PeakDataStore.loadPersistent(open: {
            opens += 1
            throw CocoaError(.fileReadCorruptFile)
        }, fallback: { memory }, recover: { throw issue }, pending: { nil })
        XCTAssertEqual(opens, 1, "Never create a fresh store after a failed archive")
        guard case .inMemoryFallback(let recovery) = result.outcome else { return XCTFail("Expected temporary store") }
        XCTAssertNil(recovery.archivedPath)
        XCTAssertTrue(recovery.details.contains(issue.details))
    }

    func testStoreLoadInterruptedRecoveryNeverOpensDisk() throws {
        let memory = try makeContainer()
        let pending = StoreRecoveryIssue(archivedPath: "/preserved-library", details: "Interrupted removal")
        let result = PeakDataStore.loadPersistent(open: {
            XCTFail("Must not open a possibly partial store")
            return memory
        }, fallback: { memory }, recover: {
            XCTFail("Must preserve the existing recovery archive")
            return URL(fileURLWithPath: "/unused")
        }, pending: { pending })
        XCTAssertEqual(result.outcome, .inMemoryFallback(recovery: pending))
    }

    func testStoreLoadFreshFailureRetainsArchiveContext() throws {
        let memory = try makeContainer()
        var opens = 0
        let result = PeakDataStore.loadPersistent(open: {
            opens += 1
            throw CocoaError(.fileWriteOutOfSpace)
        }, fallback: { memory }, recover: { URL(fileURLWithPath: "/preserved-library") }, pending: { nil })
        XCTAssertEqual(opens, 2)
        guard case .inMemoryFallback(let recovery) = result.outcome else { return XCTFail("Expected temporary store") }
        XCTAssertEqual(recovery.archivedPath, "/preserved-library")
        XCTAssertTrue(recovery.details.contains("fresh library could not open"))
    }

    private func makeRecoveryFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PeakRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".default_SUPPORT"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("SessionMedia"), withIntermediateDirectories: true)
        for name in ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT/blob.bin", "SessionMedia/session-video.mov"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        return root
    }

    private func assertRecoveryBytes(in directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        for name in ["default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT/blob.bin", "SessionMedia/session-video.mov"] {
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), Data(name.utf8), file: file, line: line)
        }
    }

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
        let readback = ModelContext(context.container)

        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
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
        let readback = ModelContext(context.container)

        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
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
        let readback = ModelContext(context.container)

        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
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
        let readback = ModelContext(context.container)

        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
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
        let readback = ModelContext(targetContext.container)

        let sessions = try readback.fetch(FetchDescriptor<SurfSession>())
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
        let readback = ModelContext(targetContext.container)

        let round = try XCTUnwrap(try readback.fetch(FetchDescriptor<SurfSession>()).first)
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
        let readback = ModelContext(context.container)

        let session = try XCTUnwrap(try readback.fetch(FetchDescriptor<SurfSession>()).first)
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
