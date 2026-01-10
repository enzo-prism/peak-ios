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
