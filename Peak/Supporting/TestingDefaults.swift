import Foundation

enum TestingDefaults {
    static var isUITest: Bool {
        ProcessInfo.processInfo.environment["UITESTS"] == "1"
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
