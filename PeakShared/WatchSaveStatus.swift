import Foundation

nonisolated enum WatchSaveStatus: Equatable, Sendable {
    case idle, saving, saved, savedWithoutRoute, failed
}
