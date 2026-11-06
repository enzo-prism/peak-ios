import CoreGraphics
import Foundation

/// One interrupted NEW session. Model references are resolved against the live
/// library at resume; no model objects or GPS routes are serialized.
nonisolated struct SavedSessionDraft: Codable, Sendable {
    let savedAt: Date
    let spotKey: String?
    let gearKeys: [String]
    let buddyKeys: [String]
    let media: [Media]
    let date: Date
    let spotName: String
    let rating: Int
    let durationMinutes: Int
    let windCondition: String?
    let waveHeight: String?
    let windSpeedKph: Double?
    let windDirectionDegrees: Double?
    let waveHeightMeters: Double?
    let swellWaveHeightMeters: Double?
    let swellWavePeriodSeconds: Double?
    let swellWaveDirectionDegrees: Double?
    let windWaveHeightMeters: Double?
    let windWavePeriodSeconds: Double?
    let windWaveDirectionDegrees: Double?
    let seaSurfaceTemperatureC: Double?
    let seaLevelHeightM: Double?
    let tideTrend: String?
    let conditionsSource: String?
    let conditionsFetchedAt: Date?
    let conditionsLatitude: Double?
    let conditionsLongitude: Double?
    let waveCount: Int?
    let topSpeedKph: Double?
    let longestRideSeconds: Double?
    let longestRideMeters: Double?
    let paddleDistanceMeters: Double?
    let waveStatsSource: String?
    let linkedWorkoutID: String?
    let notes: String
    let isAnchoredToNow: Bool
    let gearIsSuggested: Bool

    struct Media: Codable, Sendable {
        let id: UUID
        let photo: Data?
        let thumbnail: Data?
        let videoName: String?
        let crop: CGRect
        let createdAt: Date
    }

    @MainActor init(_ draft: SessionDraft, at date: Date = Date()) {
        savedAt = date
        spotKey = draft.selectedSpot?.key
        gearKeys = draft.selectedGear.map(\.key)
        buddyKeys = draft.selectedBuddies.map(\.key)
        self.date = draft.date
        self.spotName = draft.spotName
        self.rating = draft.rating
        self.durationMinutes = draft.durationMinutes
        self.windCondition = draft.windCondition?.rawValue
        self.waveHeight = draft.waveHeight?.rawValue
        self.windSpeedKph = draft.windSpeedKph
        self.windDirectionDegrees = draft.windDirectionDegrees
        self.waveHeightMeters = draft.waveHeightMeters
        self.swellWaveHeightMeters = draft.swellWaveHeightMeters
        self.swellWavePeriodSeconds = draft.swellWavePeriodSeconds
        self.swellWaveDirectionDegrees = draft.swellWaveDirectionDegrees
        self.windWaveHeightMeters = draft.windWaveHeightMeters
        self.windWavePeriodSeconds = draft.windWavePeriodSeconds
        self.windWaveDirectionDegrees = draft.windWaveDirectionDegrees
        self.seaSurfaceTemperatureC = draft.seaSurfaceTemperatureC
        self.seaLevelHeightM = draft.seaLevelHeightM
        self.tideTrend = draft.tideTrend?.rawValue
        self.conditionsSource = draft.conditionsSource
        self.conditionsFetchedAt = draft.conditionsFetchedAt
        self.conditionsLatitude = draft.conditionsLatitude
        self.conditionsLongitude = draft.conditionsLongitude
        self.waveCount = draft.waveCount
        self.topSpeedKph = draft.topSpeedKph
        self.longestRideSeconds = draft.longestRideSeconds
        self.longestRideMeters = draft.longestRideMeters
        self.paddleDistanceMeters = draft.paddleDistanceMeters
        self.waveStatsSource = draft.waveStatsSource?.rawValue
        self.linkedWorkoutID = draft.linkedWorkoutID
        self.notes = draft.notes
        self.isAnchoredToNow = draft.isAnchoredToNow
        self.gearIsSuggested = draft.gearIsSuggested
        media = draft.mediaItems.map { item in
            Media(id: item.id, photo: item.photoData, thumbnail: item.thumbnailData,
                  videoName: item.temporaryVideoURL.map { _ in item.id.uuidString + ".mov" },
                  crop: item.cropRect, createdAt: item.createdAt)
        }
    }

    /// Large video copies belong off the UI executor. The durable source is
    /// never handed to editor cleanup; cancellation removes only new copies.
    @concurrent func prepareVideoCopies(in directory: URL) async throws -> [UUID: URL] {
        var copies: [UUID: URL] = [:]
        do {
            for item in media {
                try Task.checkCancellation()
                guard let name = item.videoName else { continue }
                guard name == item.id.uuidString + ".mov", copies[item.id] == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                do { try FileManager.default.copyItem(at: directory.appendingPathComponent(name), to: copy) }
                catch { try? FileManager.default.removeItem(at: copy); throw error }
                copies[item.id] = copy
            }
            try Task.checkCancellation()
            return copies
        } catch {
            for copy in copies.values { try? FileManager.default.removeItem(at: copy) }
            throw error
        }
    }

    @MainActor func restore(spots: [Spot], gear: [Gear], buddies: [Buddy], videoCopies: [UUID: URL] = [:]) throws -> SessionDraft {
        var draft = SessionDraft()
        draft.date = date
        draft.spotName = spotName
        draft.rating = rating
        draft.durationMinutes = durationMinutes
        draft.windCondition = windCondition.flatMap(WindCondition.init(rawValue:))
        draft.waveHeight = waveHeight.flatMap(WaveHeight.init(rawValue:))
        draft.windSpeedKph = windSpeedKph
        draft.windDirectionDegrees = windDirectionDegrees
        draft.waveHeightMeters = waveHeightMeters
        draft.swellWaveHeightMeters = swellWaveHeightMeters
        draft.swellWavePeriodSeconds = swellWavePeriodSeconds
        draft.swellWaveDirectionDegrees = swellWaveDirectionDegrees
        draft.windWaveHeightMeters = windWaveHeightMeters
        draft.windWavePeriodSeconds = windWavePeriodSeconds
        draft.windWaveDirectionDegrees = windWaveDirectionDegrees
        draft.seaSurfaceTemperatureC = seaSurfaceTemperatureC
        draft.seaLevelHeightM = seaLevelHeightM
        draft.tideTrend = tideTrend.flatMap(TideTrend.init(rawValue:))
        draft.conditionsSource = conditionsSource
        draft.conditionsFetchedAt = conditionsFetchedAt
        draft.conditionsLatitude = conditionsLatitude
        draft.conditionsLongitude = conditionsLongitude
        draft.waveCount = waveCount
        draft.topSpeedKph = topSpeedKph
        draft.longestRideSeconds = longestRideSeconds
        draft.longestRideMeters = longestRideMeters
        draft.paddleDistanceMeters = paddleDistanceMeters
        draft.waveStatsSource = waveStatsSource.flatMap(WaveStatsSource.init(rawValue:))
        draft.linkedWorkoutID = linkedWorkoutID
        draft.notes = notes
        draft.isAnchoredToNow = isAnchoredToNow
        draft.gearIsSuggested = gearIsSuggested
        // Resuming tomorrow must not change the times the surfer entered today.
        draft.isAnchoredToNow = false
        draft.selectedSpot = spots.first { $0.key == spotKey }
        draft.selectedGear = gear.filter { gearKeys.contains($0.key) && !$0.isArchived }
        draft.selectedBuddies = buddies.filter { buddyKeys.contains($0.key) }
        do {
            draft.mediaItems = try media.map { item in
                guard item.crop.origin.x.isFinite, item.crop.origin.y.isFinite,
                      item.crop.width.isFinite, item.crop.height.isFinite else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let source: SessionMediaDraftItem.Source
                let kind: SessionMediaKind
                if let videoName = item.videoName {
                    guard videoName == item.id.uuidString + ".mov" else { throw CocoaError(.fileReadCorruptFile) }
                    guard let copy = videoCopies[item.id] else { throw CocoaError(.fileReadNoSuchFile) }
                    source = .newVideo(temporaryURL: copy, thumbnailData: item.thumbnail)
                    kind = .video
                } else if let photo = item.photo {
                    source = .newPhoto(photoData: photo, thumbnailData: item.thumbnail)
                    kind = .photo
                } else { throw CocoaError(.fileReadCorruptFile) }
                return SessionMediaDraftItem(id: item.id, kind: kind, createdAt: item.createdAt,
                                            source: source, cropRect: item.crop)
            }
        } catch {
            SessionMediaStore.deleteTemporaryFiles(Array(videoCopies.values))
            throw error
        }
        return draft
    }
}

/// Serialized file writes plus generation ordering stop a late autosave from
/// resurrecting a draft that has already been saved or explicitly discarded.
actor SessionDraftStore {
    static let shared = SessionDraftStore()
    let directory: URL
    private var latestMutation = Date.distantPast

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionDraft", isDirectory: true)
    }

    func save(_ snapshot: SavedSessionDraft, videos: [UUID: URL]) throws {
        guard snapshot.savedAt >= latestMutation else { return }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in snapshot.media {
            guard let name = item.videoName else { continue }
            guard name == item.id.uuidString + ".mov" else { throw CocoaError(.fileReadCorruptFile) }
            let destination = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let source = videos[item.id] else { throw CocoaError(.fileReadNoSuchFile) }
                let staging = directory.appendingPathComponent(".copy-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: staging) }
                try FileManager.default.copyItem(at: source, to: staging)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staging.path)
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent("draft.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        latestMutation = snapshot.savedAt
        // Retire unreferenced recovery videos only AFTER the new index commits.
        let kept = Set(snapshot.media.compactMap(\.videoName) + ["draft.json"])
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where !kept.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
    }

    func load() throws -> SavedSessionDraft? {
        let index = directory.appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: index.path) else { return nil }
        return try JSONDecoder().decode(SavedSessionDraft.self, from: Data(contentsOf: index))
    }

    func clear(at date: Date = Date()) throws {
        guard date >= latestMutation else { return }
        latestMutation = date
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
