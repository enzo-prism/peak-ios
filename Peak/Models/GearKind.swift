import Foundation

enum GearKind: String, Codable, CaseIterable, Identifiable {
    case board
    case wetsuit
    case fins
    case leash
    case other

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .board:
            return "Board"
        case .wetsuit:
            return "Wetsuit"
        case .fins:
            return "Fins"
        case .leash:
            return "Leash"
        case .other:
            return "Other"
        }
    }

    nonisolated var pluralLabel: String {
        switch self {
        case .board:
            return "Boards"
        case .wetsuit:
            return "Wetsuits"
        case .fins:
            return "Fins"
        case .leash:
            return "Leash"
        case .other:
            return "Other"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .board:
            return "rectangle.portrait"
        case .wetsuit:
            return "tshirt"
        case .fins:
            return "triangle"
        case .leash:
            return "link"
        case .other:
            return "gearshape"
        }
    }
}
