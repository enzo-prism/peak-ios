import Foundation

enum TestCalendar {
    static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        gmt.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
