import Foundation

extension Date {
    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? self
    }

    var monthTitle: String {
        formatted(.dateTime.month(.wide).year())
    }

    var sessionTitle: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

enum SessionDurationFormatter {
    static func string(from minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Not set" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainingMinutes)m"
    }
}
