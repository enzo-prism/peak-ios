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
        notes = session.notes
        mediaItems = session.media.sorted { $0.createdAt < $1.createdAt }.map { SessionMediaDraftItem(existing: $0) }
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

    init(existing media: SessionMedia) {
        self.init(
            id: UUID(),
            kind: media.kind,
            createdAt: media.createdAt,
            source: .existing(media)
        )
    }

    static func newPhoto(photoData: Data, thumbnailData: Data?) -> SessionMediaDraftItem {
        SessionMediaDraftItem(
            id: UUID(),
            kind: .photo,
            createdAt: Date(),
            source: .newPhoto(photoData: photoData, thumbnailData: thumbnailData)
        )
    }

    static func newVideo(temporaryURL: URL, thumbnailData: Data?) -> SessionMediaDraftItem {
        SessionMediaDraftItem(
            id: UUID(),
            kind: .video,
            createdAt: Date(),
            source: .newVideo(temporaryURL: temporaryURL, thumbnailData: thumbnailData)
        )
    }

    private init(id: UUID, kind: SessionMediaKind, createdAt: Date, source: Source) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.source = source
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
