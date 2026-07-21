import Foundation

nonisolated enum TestingDefaults {
    static var isUITest: Bool {
        ProcessInfo.processInfo.environment["UITESTS"] == "1"
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
