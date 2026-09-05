import Foundation

nonisolated enum TestingDefaults {
    static var isUITest: Bool {
        ProcessInfo.processInfo.environment["UITESTS"] == "1"
    }

    /// Explicit compatibility lane for older tests that exercise compact flows.
    /// UI tests otherwise use the same adaptive navigation as the shipped app.
    static var usesClassicNavigation: Bool {
        isUITest && ProcessInfo.processInfo.environment["UITESTS_CLASSIC_NAVIGATION"] == "1"
    }

    static var isAdCapture: Bool {
        ProcessInfo.processInfo.environment["PEAK_AD_CAPTURE"] == "1"
    }

    /// Marketing screenshot capture. When set, the seed renders real sample
    /// imagery (instead of the cheap blank fallback) so media-rich screens look
    /// good in App Store screenshots.
    static var isScreenshotCapture: Bool {
        ProcessInfo.processInfo.environment["PEAK_SCREENSHOTS"] == "1"
    }

    /// Forces the first-run welcome even under `UITESTS`, which otherwise skips
    /// it so every pre-2.9 UI-test baseline still launches straight into the Log
    /// tab. Only the dedicated welcome test sets this.
    static var forcesWelcome: Bool {
        ProcessInfo.processInfo.environment["UITESTS_SHOW_WELCOME"] == "1"
    }

    /// A deep link handed to the app at launch. The UI suite can't ask the
    /// system to deliver a real widget tap, so it injects the same URL here and
    /// the app routes it through the identical `onOpenURL` handler.
    static var launchDeepLinkURL: URL? {
        guard let value = ProcessInfo.processInfo.environment["UITESTS_OPEN_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return URL(string: value)
    }

    static var surfConditionsScenario: String? {
        guard let value = ProcessInfo.processInfo.environment["UITESTS_SURF_CONDITIONS_SCENARIO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Drives the Best Window Today card under UI test: it both fakes the forecast
    /// provider and (via `PreviewData`) decides how much rated history the seeded
    /// spot gets, so the card's confident and low-confidence states are both
    /// reachable without a network call.
    static var windowScenario: String? {
        guard let value = ProcessInfo.processInfo.environment["UITESTS_WINDOW_SCENARIO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Drives the on-device insights surfaces under UI test. The simulator has
    /// no Apple Intelligence, so the AI layout would otherwise be unreachable
    /// from the UI suite. `stub` substitutes a canned, model-free draft; unset
    /// (the default) leaves the real availability gate in charge, which on the
    /// simulator means the plain-stats fallback.
    static var insightsScenario: String? {
        guard let value = ProcessInfo.processInfo.environment["UITESTS_INSIGHTS_SCENARIO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    static var isRunningTests: Bool {
        if isUITest {
            return true
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }

    static var fixedSeedDate: Date? {
        guard let value = ProcessInfo.processInfo.environment["UITESTS_FIXED_DATE"],
              !value.isEmpty else {
            return nil
        }

        if let date = iso8601Fractional.date(from: value) {
            return date
        }
        if let date = iso8601.date(from: value) {
            return date
        }
        for formatter in fallbackFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    static var sessionMarker: String? {
        guard let value = ProcessInfo.processInfo.environment["UITESTS_SESSION_MARKER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    private static var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static var iso8601Fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static var fallbackFormatters: [DateFormatter] {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }
}
