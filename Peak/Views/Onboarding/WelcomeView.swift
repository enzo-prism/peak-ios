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

/// What Peak is, the privacy promise, an Apple Watch opt-in (where Health
/// exists), and a CTA into the editor. Cold start used to drop straight into an
/// empty Log tab with no explanation of what the app was for.
struct WelcomeView: View {
    private enum Page {
        case logbook
        case privacy
        case watch
        case firstSession
    }

    /// Called on the final CTA — dismisses and opens the session editor.
    let onLogFirstSession: () -> Void
    /// Called on skip or after the CTA — marks the welcome seen.
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HealthKitService.healthSyncEnabledKey) private var healthSyncEnabled = false
    @State private var page = 0

    private let pages: [Page]

    init(onLogFirstSession: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onLogFirstSession = onLogFirstSession
        self.onFinish = onFinish
        // The Watch page only makes sense where Apple Health exists.
        pages = HealthKitService.isHealthDataAvailable
            ? [.logbook, .privacy, .watch, .firstSession]
            : [.logbook, .privacy, .firstSession]
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                header

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, kind in
                        pageView(kind)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)

                controls
            }
            .padding(.vertical, 24)
            .readableContentWidth()
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("Skip") {
                onFinish()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("welcome.skip")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func pageView(_ kind: Page) -> some View {
        switch kind {
        case .logbook:
            pageContent(
                icon: "water.waves",
                title: "Your surf logbook",
                body: "Log a session in seconds — spot, gear, buddies, and a rating. Peak turns that into your quiver stats, spot history, and trends."
            )
        case .privacy:
            pageContent(
                icon: "lock.shield",
                title: "Stays on your phone",
                body: "Everything is stored on-device. No account, no cloud, no tracking, no analytics. Your logbook is yours, and you can export it any time."
            )
        case .watch:
            pageContent(
                icon: "applewatch",
                title: "Surf with an Apple Watch?",
                body: "Peak can pick up surfs your Watch records — when, how long, and an estimated wave count — so logging one is a rating and Save. Sessions you log are saved to Apple Health as surfing workouts. It all stays on your devices, and you can change it any time in Settings."
            ) {
                healthConnectButton
            }
        case .firstSession:
            pageContent(
                icon: "square.and.pencil",
                title: "Log your first session",
                body: "The fastest way to see what Peak does is to put one session in it. Paddle out already happened — this takes twenty seconds."
            )
        }
    }

    /// The same opt-in as Settings → Apple Health: flips the toggle and asks for
    /// Health access. Skipping this page leaves Health off, exactly as before.
    @ViewBuilder
    private var healthConnectButton: some View {
        if healthSyncEnabled {
            Label("Apple Health connected", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("welcome.health.connected")
        } else {
            Button {
                healthSyncEnabled = true
                Task { try? await HealthKitService.shared.requestAuthorization() }
            } label: {
                Label("Connect Apple Health", systemImage: "heart.fill")
                    .font(.headline)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle(prominent: false)
            .accessibilityIdentifier("welcome.health.connect")
        }
    }

    private func pageContent(icon: String, title: String, body: String) -> some View {
        pageContent(icon: icon, title: title, body: body) { EmptyView() }
    }

    private func pageContent<Accessory: View>(
        icon: String,
        title: String,
        body: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let accessoryView = accessory()
        // ScrollView so AX text sizes can scroll; minHeight + the inner Spacers
        // keep the content vertically centered at default sizes.
        return GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)

                    Image(systemName: icon)
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(28)
                        .glassCard(cornerRadius: Theme.Radius.section, tint: Theme.glassTint, isInteractive: false)
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(body)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accessoryView

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if page == pages.count - 1 {
            Button {
                onLogFirstSession()
            } label: {
                Label("Log Your First Session", systemImage: "plus")
                    .font(.headline)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle(prominent: true)
            .padding(.horizontal)
            .accessibilityIdentifier("welcome.cta")
        } else {
            Button {
                page = min(page + 1, pages.count - 1)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle(prominent: true)
            .padding(.horizontal)
            .accessibilityIdentifier("welcome.next")
        }
    }
}

#Preview {
    WelcomeView(onLogFirstSession: {}, onFinish: {})
}
