import Foundation

enum GearKind: String, Codable, CaseIterable, Identifiable {
    case board
    case wetsuit
    case fins
    case leash
    case other

    var id: String { rawValue }

    var label: String {
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

    var systemImage: String {
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
