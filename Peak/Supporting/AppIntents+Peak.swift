import AppIntents
import Foundation
import SwiftUI

/// Read-only intents that answer questions about the logbook, plus the app's
/// shortcut phrases. These run in the app process (they need SwiftData), so
/// unlike the start/end intents they aren't shared with the widget extension.
///
/// Every answer is produced by `SessionIntentQueries` so the sentence Siri
/// speaks is covered by unit tests.

/// "When did I last surf?"
struct LastSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Last Surf Session"
    static let description = IntentDescription(
        "Tells you when and where you last surfed."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<SurfSessionEntity?> & ShowsSnippetView {
        let session = SessionIntentQueries.lastSession(in: PeakIntentStore.sessions())
        let dialog = SessionIntentQueries.lastSessionDialog(for: session)
        let entity = session.map(SurfSessionEntity.init(session:))
        return .result(
            value: entity,
            dialog: IntentDialog(stringLiteral: dialog),
            view: LastSessionSnippetView(entity: entity)
        )
    }
}

/// Compact result shown with "When did I last surf?" so the surfer can tap
/// through to the session instead of only hearing a sentence.
private struct LastSessionSnippetView: View {
    let entity: SurfSessionEntity?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entity?.spotName ?? "No sessions yet")
                .font(.headline)
            if let entity {
                Text(SurfSessionEntity.subtitle(
                    date: entity.date,
                    rating: entity.rating,
                    durationMinutes: entity.durationMinutes
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text("Log a surf to see it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

/// "How many surf sessions this month?"
struct SessionsThisMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "Sessions This Month"
    static let description = IntentDescription(
        "Counts the surf sessions you've logged this month."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let sessions = SessionIntentQueries.sessionsThisMonth(in: PeakIntentStore.sessions())
        let dialog = SessionIntentQueries.sessionsThisMonthDialog(count: sessions.count)
        return .result(value: sessions.count, dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// The four intents Peak offers to Siri, Spotlight and the Action button.
/// Phrases stay natural and always name the app, which is what the App Intents
/// matcher requires.
struct PeakAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSessionIntent(),
            phrases: [
                "Log a session in \(.applicationName)",
                "Log a surf session in \(.applicationName)",
                "Log my surf in \(.applicationName)"
            ],
            shortTitle: "Log Session",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "Start a surf session in \(.applicationName)",
                "I'm paddling out with \(.applicationName)"
            ],
            shortTitle: "Start Session",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: EndSessionIntent(),
            phrases: [
                "End my session in \(.applicationName)",
                "End my surf session in \(.applicationName)",
                "I'm out of the water in \(.applicationName)"
            ],
            shortTitle: "End Session",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: LastSessionIntent(),
            phrases: [
                "When did I last surf in \(.applicationName)",
                "My last session in \(.applicationName)",
                "Last surf in \(.applicationName)"
            ],
            shortTitle: "Last Session",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: SessionsThisMonthIntent(),
            phrases: [
                "How many sessions this month in \(.applicationName)",
                "My sessions this month in \(.applicationName)",
                "Surf count in \(.applicationName)"
            ],
            shortTitle: "Sessions This Month",
            systemImageName: "chart.bar.xaxis"
        )
        AppShortcut(
            intent: SearchPeakIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find a session in \(.applicationName)",
                "Search my surfs in \(.applicationName)"
            ],
            shortTitle: "Search Peak",
            systemImageName: "magnifyingglass"
        )
    }
}
