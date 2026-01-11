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
    var notes: String = ""
    var photos: [SessionPhotoEntry] = []

    init() {}

    init(session: SurfSession) {
        date = session.date
        selectedSpot = session.spot
        spotName = session.spot?.name ?? ""
        selectedGear = session.gear
        selectedBuddies = session.buddies
        rating = session.rating
        durationMinutes = session.durationMinutes ?? 0
        notes = session.notes
        photos = session.photos
            .sorted(by: { $0.sortIndex < $1.sortIndex })
            .map { SessionPhotoEntry(photo: $0) }
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
}

struct SessionPhotoEntry: Identifiable, Equatable {
    let id: UUID
    var data: Data
    var existingPhoto: SessionPhoto?

    init(data: Data) {
        self.id = UUID()
        self.data = data
        self.existingPhoto = nil
    }

    init(photo: SessionPhoto) {
        self.id = UUID()
        self.data = photo.data
        self.existingPhoto = photo
    }
}
