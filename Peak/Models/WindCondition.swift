import Foundation

enum WindCondition: String, Codable, CaseIterable, Identifiable {
    case calm
    case breezy
    case windy
    case strong

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .calm:
            return "No wind"
        case .breezy:
            return "A little breezy"
        case .windy:
            return "Pretty windy"
        case .strong:
            return "Super windy"
        }
    }
}
