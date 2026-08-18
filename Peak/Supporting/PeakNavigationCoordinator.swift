import Foundation
import Observation
import SwiftUI

/// Top-level destinations in Peak's tab / sidebar shell.
///
/// The five `phoneTabs` are the iPhone tab bar. `search`, `spots`, and `buddies`
/// exist so iOS 18's sidebar-adaptable tab view can surface library destinations
/// (and a dedicated search tab) without crowding the compact tab bar.
enum PeakTab: String, Hashable, CaseIterable {
    case log
    case history
    case stats
    case quiver
    case more
    case search
    case spots
    case buddies

    /// Compact tab bar — five items, matching the HIG default.
    static let phoneTabs: [PeakTab] = [.log, .history, .stats, .quiver, .more]

    var title: String {
        switch self {
        case .log: return "Log"
        case .history: return "History"
        case .stats: return "Stats"
        case .quiver: return "Quiver"
        case .more: return "More"
        case .search: return "Search"
        case .spots: return "Spots"
        case .buddies: return "Buddies"
        }
    }

    var systemImage: String {
        switch self {
        case .log: return "square.and.pencil"
        case .history: return "clock.arrow.circlepath"
        case .stats: return "chart.bar.xaxis"
        case .quiver: return "surfboard"
        case .more: return "ellipsis.circle"
        case .search: return "magnifyingglass"
        case .spots: return "mappin.and.ellipse"
        case .buddies: return "person.2"
        }
    }
}

/// Stable, store-free identifier wrapper so SwiftUI `navigationDestination(item:)`
/// can push a session/spot/gear from a deep link or OpenIntent without requiring
/// the `@Model` class itself to travel across the navigation path.
struct PeakEntityRef: Identifiable, Hashable {
    let id: String
}

/// Routes system-initiated opens (widgets, Spotlight, Siri, Control Center)
/// into the tab shell. `QuickLogCoordinator` still owns the *new session* sheet;
/// this coordinator owns "show me this existing thing".
@MainActor
@Observable
final class PeakNavigationCoordinator {
    static let shared = PeakNavigationCoordinator()

    var selectedTab: PeakTab = .log
    var pendingSessionID: String?
    var pendingSpotID: String?
    var pendingGearID: String?
    var pendingSearchQuery: String?

    private init() {}

    func handle(_ destination: PeakDeepLink.Destination) {
        switch destination {
        case .newSession:
            QuickLogCoordinator.shared.requestNewSession()
        case .session(let id):
            selectedTab = .history
            pendingSessionID = id
        case .spot(let id):
            pendingSpotID = id
            selectedTab = sidebarLibraryTabAvailable ? .spots : .more
        case .gear(let id):
            selectedTab = .quiver
            pendingGearID = id
        case .search(let query):
            pendingSearchQuery = query
            selectedTab = sidebarLibraryTabAvailable ? .search : .history
        }
    }

    func consumePendingSession() -> String? {
        let value = pendingSessionID
        pendingSessionID = nil
        return value
    }

    func consumePendingSpot() -> String? {
        let value = pendingSpotID
        pendingSpotID = nil
        return value
    }

    func consumePendingGear() -> String? {
        let value = pendingGearID
        pendingGearID = nil
        return value
    }

    func consumePendingSearch() -> String? {
        let value = pendingSearchQuery
        pendingSearchQuery = nil
        return value
    }

    /// iOS 18+ tab view can host Spots / Search as real tabs. Below that, those
    /// destinations live under History / More and the selected-tab binding must
    /// point at a tab that actually exists.
    private var sidebarLibraryTabAvailable: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}
