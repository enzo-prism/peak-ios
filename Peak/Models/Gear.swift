import Foundation
import SwiftData

@Model
final class Gear {
    @Attribute(.unique) var key: String
    var name: String
    var kind: GearKind
    var brand: String?
    var model: String?
    var size: String?
    var volumeLiters: Double?
    var notes: String?
    @Attribute(.externalStorage) var photoData: Data?
    var isArchived: Bool = false
    var createdAt: Date

    init(
        name: String,
        kind: GearKind,
        brand: String? = nil,
        model: String? = nil,
        size: String? = nil,
        volumeLiters: Double? = nil,
        notes: String? = nil,
        photoData: Data? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        let cleaned = name.trimmedNonEmpty ?? "Unknown"
        self.name = cleaned
        self.kind = kind
        self.key = Gear.makeKey(name: cleaned, kind: kind)
        self.brand = brand?.trimmedNonEmpty
        self.model = model?.trimmedNonEmpty
        self.size = size?.trimmedNonEmpty
        self.volumeLiters = volumeLiters
        self.notes = notes?.trimmedNonEmpty
        self.photoData = photoData
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    static func makeKey(name: String, kind: GearKind) -> String {
        "\(kind.rawValue)|\(name.normalizedKey)"
    }

    var profileSummary: String? {
        var parts: [String] = []
        if let brand = brand?.trimmedNonEmpty {
            parts.append(brand)
        }
        if let model = model?.trimmedNonEmpty {
            parts.append(model)
        }
        if let size = size?.trimmedNonEmpty {
            parts.append(size)
        }
        if let volumeLiters {
            parts.append(String(format: "%.1fL", volumeLiters))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
}
