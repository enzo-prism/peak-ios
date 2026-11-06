import SwiftUI
import WatchKit

@main
struct PeakWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchRecoveryDelegate.self) private var delegate
    @StateObject private var controller = WatchWorkoutController.shared

    var body: some Scene {
        WindowGroup {
            WatchSessionView()
                .environmentObject(controller)
                .task {
                    // Recover an interrupted workout without prompting for new access.
                    await controller.recoverIfNeeded()
                }
        }
    }
}

/// watchOS may relaunch recovery work without displaying the workout scene.
@MainActor
final class WatchRecoveryDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { await WatchWorkoutController.shared.recoverIfNeeded(force: true) }
    }
}
