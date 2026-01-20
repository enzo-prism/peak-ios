import Foundation

enum WaveHeight: String, Codable, CaseIterable, Identifiable {
    case kneeHigh
    case waistHigh
    case shoulderHigh
    case overhead
    case wayOverhead

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .kneeHigh:
            return "Knee high"
        case .waistHigh:
            return "Waist high"
        case .shoulderHigh:
            return "Shoulder high"
        case .overhead:
            return "Overhead"
        case .wayOverhead:
            return "Way overhead"
        }
    }
}
