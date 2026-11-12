import SwiftUI

/// First-run gating. The welcome is skipped under every automation mode so the
/// UI-test and screenshot baselines keep launching straight into the Log tab;
/// `UITESTS_SHOW_WELCOME=1` forces it back on for the one test that exercises it.
enum WelcomeExperience {
    static let hasSeenWelcomeKey = "hasSeenWelcome"

    static var isSuppressedForAutomation: Bool {
        TestingDefaults.isUITest
            || TestingDefaults.isAdCapture
            || TestingDefaults.isScreenshotCapture
    }

    static func shouldPresent(hasSeenWelcome: Bool) -> Bool {
        if TestingDefaults.forcesWelcome {
            return true
        }
        return !hasSeenWelcome && !isSuppressedForAutomation
    }
}

/// One optional introduction; permissions belong to the action that needs them.
struct WelcomeView: View {
    let onLogFirstSession: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button("Skip", action: onFinish)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("welcome.skip")
                    }
                    Image(systemName: "water.waves")
                        .font(.system(size: 56))
                        .padding(28)
                        .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassTint)
                        .accessibilityHidden(true)
                    Text("Your surf logbook")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Remember the surf. Know your quiver.")
                        .font(.title3.weight(.semibold))
                    Text("Start with your last surf. A spot is all you need; add your board, time in the water and a rating when you want.")
                        .font(.body)
                    Label("On your device. No account or tracking.", systemImage: "lock.shield")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Button(action: onLogFirstSession) {
                        Label("Log my last surf", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .glassButtonStyle(prominent: true)
                    .accessibilityIdentifier("welcome.cta")
                    Text("Apple Health, photos and voice are optional. Peak asks when you use them.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
                .readableContentWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

#Preview { WelcomeView(onLogFirstSession: {}, onFinish: {}) }
