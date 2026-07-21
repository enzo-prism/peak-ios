import CoreGraphics
import Foundation
import SwiftData

struct SessionDraft {
    var date: Date = Date()
    var spotName: String = ""
    var selectedSpot: Spot?
    var selectedGear: [Gear] = []
    var selectedBuddies: [Buddy] = []
    var rating: Int = 0
    var durationMinutes: Int = 0
    var windCondition: WindCondition?
    var waveHeight: WaveHeight?
    var windSpeedKph: Double?
    var windDirectionDegrees: Double?
    var waveHeightMeters: Double?
    var swellWaveHeightMeters: Double?
    var swellWavePeriodSeconds: Double?
    var swellWaveDirectionDegrees: Double?
    var windWaveHeightMeters: Double?
    var windWavePeriodSeconds: Double?
    var windWaveDirectionDegrees: Double?
    var seaSurfaceTemperatureC: Double?
    var seaLevelHeightM: Double?
    var tideTrend: TideTrend?
    var conditionsSource: String?
    var conditionsFetchedAt: Date?
    var conditionsLatitude: Double?
    var conditionsLongitude: Double?
    var notes: String = ""
    var mediaItems: [SessionMediaDraftItem] = []

    init() {}

    init(session: SurfSession) {
        date = session.date
        selectedSpot = session.spot
        spotName = session.spot?.name ?? ""
        selectedGear = session.gear
        selectedBuddies = session.buddies
        rating = session.rating
        durationMinutes = session.durationMinutes ?? 0
        windCondition = session.windCondition
        waveHeight = session.waveHeight
        windSpeedKph = session.windSpeedKph
        windDirectionDegrees = session.windDirectionDegrees
        waveHeightMeters = session.waveHeightMeters
        swellWaveHeightMeters = session.swellWaveHeightMeters
        swellWavePeriodSeconds = session.swellWavePeriodSeconds
        swellWaveDirectionDegrees = session.swellWaveDirectionDegrees
        windWaveHeightMeters = session.windWaveHeightMeters
        windWavePeriodSeconds = session.windWavePeriodSeconds
        windWaveDirectionDegrees = session.windWaveDirectionDegrees
        seaSurfaceTemperatureC = session.seaSurfaceTemperatureC
        seaLevelHeightM = session.seaLevelHeightM
        tideTrend = session.tide
        conditionsSource = session.conditionsSource
        conditionsFetchedAt = session.conditionsFetchedAt
        conditionsLatitude = session.conditionsLatitude
        conditionsLongitude = session.conditionsLongitude
        notes = session.notes
        mediaItems = session.media
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
            .map { SessionMediaDraftItem(existing: $0) }
    }

    var isReadyToSave: Bool {
        selectedSpot != nil
    }

    mutating func selectSpot(_ spot: Spot) {
        selectedSpot = spot
        spotName = spot.name
    }

    mutating func toggleGear(_ gear: Gear) {
        if let index = selectedGear.firstIndex(where: { $0.persistentModelID == gear.persistentModelID }) {
            selectedGear.remove(at: index)
        } else {
            selectedGear.append(gear)
        }
    }

    mutating func toggleBuddy(_ buddy: Buddy) {
        if let index = selectedBuddies.firstIndex(where: { $0.persistentModelID == buddy.persistentModelID }) {
            selectedBuddies.remove(at: index)
        } else {
            selectedBuddies.append(buddy)
        }
    }

    mutating func removeMediaItem(_ item: SessionMediaDraftItem) {
        mediaItems.removeAll { $0.id == item.id }
    }

    mutating func setCrop(_ rect: CGRect, for id: UUID) {
        guard let index = mediaItems.firstIndex(where: { $0.id == id }) else { return }
        mediaItems[index].cropRect = rect
    }

    var hasSurfConditions: Bool {
        windCondition != nil ||
        waveHeight != nil ||
        windSpeedKph != nil ||
        windDirectionDegrees != nil ||
        waveHeightMeters != nil ||
        swellWaveHeightMeters != nil ||
        swellWavePeriodSeconds != nil ||
        swellWaveDirectionDegrees != nil ||
        windWaveHeightMeters != nil ||
        windWavePeriodSeconds != nil ||
        windWaveDirectionDegrees != nil ||
        seaSurfaceTemperatureC != nil ||
        seaLevelHeightM != nil ||
        tideTrend != nil ||
        conditionsSource != nil ||
        conditionsFetchedAt != nil
    }

    mutating func applySurfConditions(_ snapshot: SurfConditionsSnapshot) {
        windCondition = snapshot.windCondition
        waveHeight = snapshot.waveHeightCategory
        windSpeedKph = snapshot.windSpeedKph
        windDirectionDegrees = snapshot.windDirectionDegrees
        waveHeightMeters = snapshot.waveHeightMeters
        swellWaveHeightMeters = snapshot.swellWaveHeightMeters
        swellWavePeriodSeconds = snapshot.swellWavePeriodSeconds
        swellWaveDirectionDegrees = snapshot.swellWaveDirectionDegrees
        windWaveHeightMeters = snapshot.windWaveHeightMeters
        windWavePeriodSeconds = snapshot.windWavePeriodSeconds
        windWaveDirectionDegrees = snapshot.windWaveDirectionDegrees
        seaSurfaceTemperatureC = snapshot.seaSurfaceTemperatureC
        seaLevelHeightM = snapshot.seaLevelHeightMeters
        tideTrend = snapshot.tideTrend
        conditionsSource = snapshot.source
        conditionsFetchedAt = snapshot.fetchedAt
        conditionsLatitude = snapshot.latitude
        conditionsLongitude = snapshot.longitude
    }
}

struct SessionMediaDraftItem: Identifiable {
    enum Source {
        case existing(SessionMedia)
        case newPhoto(photoData: Data, thumbnailData: Data?)
        case newVideo(temporaryURL: URL, thumbnailData: Data?)
    }

    let id: UUID
    let kind: SessionMediaKind
    let createdAt: Date
    let source: Source
    /// Staged normalized preview crop; committed to SessionMedia on Save.
    var cropRect: CGRect

    init(existing media: SessionMedia) {
        self.init(
            id: UUID(),
            kind: media.kind,
            createdAt: media.createdAt,
            source: .existing(media),
            cropRect: media.cropRect
        )
    }

    static func newPhoto(photoData: Data, thumbnailData: Data?) -> SessionMediaDraftItem {
        SessionMediaDraftItem(
            id: UUID(),
            kind: .photo,
            createdAt: Date(),
            source: .newPhoto(photoData: photoData, thumbnailData: thumbnailData),
            cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
    }

    static func newVideo(temporaryURL: URL, thumbnailData: Data?) -> SessionMediaDraftItem {
        SessionMediaDraftItem(
            id: UUID(),
            kind: .video,
            createdAt: Date(),
            source: .newVideo(temporaryURL: temporaryURL, thumbnailData: thumbnailData),
            cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
    }

    private init(id: UUID, kind: SessionMediaKind, createdAt: Date, source: Source, cropRect: CGRect) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.source = source
        self.cropRect = cropRect
    }

    var existingMedia: SessionMedia? {
        if case .existing(let media) = source {
            return media
        }
        return nil
    }

    var photoData: Data? {
        switch source {
        case .existing(let media):
            return media.photoData
        case .newPhoto(let photoData, _):
            return photoData
        case .newVideo:
            return nil
        }
    }

    var thumbnailData: Data? {
        switch source {
        case .existing(let media):
            return media.thumbnailData
        case .newPhoto(_, let thumbnailData):
            return thumbnailData
        case .newVideo(_, let thumbnailData):
            return thumbnailData
        }
    }

    var temporaryVideoURL: URL? {
        if case .newVideo(let url, _) = source {
            return url
        }
        return nil
    }
}
