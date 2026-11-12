import SwiftUI
import TipKit

/// Surfaces the conditions auto-fill only after the surfer has saved a session
/// by hand, so the first log stays uninterrupted and the tip lands when they
/// already know what they'd be filling in.
struct AutoFillConditionsTip: Tip {
    @Parameter static var hasSavedSession: Bool = false

    var title: Text { Text("Skip the typing") }

    var message: Text? {
        Text("Auto-fill pulls wind, swell, and water temperature for this spot and time.")
    }

    var image: Image? { Image(systemName: "wand.and.stars") }

    var rules: [Rule] {
        #Rule(Self.$hasSavedSession) { $0 == true }
    }
}

/// TipKit wiring. Tips are hard-disabled under every automation mode: a popover
/// that appears mid-run would break UI tests and marketing screenshots alike.
enum PeakTips {
    static var areEnabled: Bool {
        !TestingDefaults.isUITest
            && !TestingDefaults.isAdCapture
            && !TestingDefaults.isScreenshotCapture
    }

    static func configure() {
        guard areEnabled else { return }
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    /// Unlocks contextual auto-fill guidance after the first saved session.
    /// The welcome screen already teaches logging; no competing Log popover.
    static func markSessionSaved() {
        guard areEnabled else { return }
        AutoFillConditionsTip.hasSavedSession = true
    }
}

extension View {
    /// `popoverTip`, but inert whenever tips are disabled — so a UI-test run
    /// never has to know TipKit exists.
    @ViewBuilder
    func peakTip<Content: Tip>(_ tip: Content) -> some View {
        if PeakTips.areEnabled {
            self.popoverTip(tip)
        } else {
            self
        }
    }
}
