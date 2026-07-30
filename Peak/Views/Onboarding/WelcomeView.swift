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

/// Three screens: what Peak is, the privacy promise, and a CTA into the editor.
/// Cold start used to drop straight into an empty Log tab with no explanation of
/// what the app was for.
struct WelcomeView: View {
    /// Called on the final CTA — dismisses and opens the session editor.
    let onLogFirstSession: () -> Void
    /// Called on skip or after the CTA — marks the welcome seen.
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private static let pageCount = 3

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                header

                TabView(selection: $page) {
                    pageContent(
                        icon: "water.waves",
                        title: "Your surf logbook",
                        body: "Log a session in seconds — spot, gear, buddies, and a rating. Peak turns that into your quiver stats, spot history, and trends."
                    )
                    .tag(0)

                    pageContent(
                        icon: "lock.shield",
                        title: "Stays on your phone",
                        body: "Everything is stored on-device. No account, no cloud, no tracking, no analytics. Your logbook is yours, and you can export it any time."
                    )
                    .tag(1)

                    pageContent(
                        icon: "square.and.pencil",
                        title: "Log your first session",
                        body: "The fastest way to see what Peak does is to put one session in it. Paddle out already happened — this takes twenty seconds."
                    )
                    .tag(2)
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

    private func pageContent(icon: String, title: String, body: String) -> some View {
        // ScrollView so AX text sizes can scroll; minHeight + the inner Spacers
        // keep the content vertically centered at default sizes.
        GeometryReader { geo in
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
        if page == Self.pageCount - 1 {
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
                page = min(page + 1, Self.pageCount - 1)
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
