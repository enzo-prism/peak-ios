import Foundation
import SwiftData

@Model
final class Gear {
    @Attribute(.unique) var key: String
    var name: String
    var kind: GearKind
    var createdAt: Date

    init(name: String, kind: GearKind, createdAt: Date = Date()) {
        let cleaned = name.trimmedNonEmpty ?? "Unknown"
        self.name = cleaned
        self.kind = kind
        self.key = Gear.makeKey(name: cleaned, kind: kind)
        self.createdAt = createdAt
    }

    static func makeKey(name: String, kind: GearKind) -> String {
        "\(kind.rawValue)|\(name.normalizedKey)"
    }
}
