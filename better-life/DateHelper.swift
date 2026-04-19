import Foundation

enum DateHelper {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func todayString() -> String {
        formatter.string(from: Date())
    }

    static func dateFromString(_ s: String) -> Date? {
        formatter.date(from: s)
    }

    static func stringFromDate(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func daysInMonth(year: Int, month: Int) -> [String] {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }
        return range.map { day in
            String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    /// Returns 0-based weekday index of the 1st of the month (0 = Sunday)
    static func weekdayOffset(year: Int, month: Int) -> Int {
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return 0
        }
        // calendar.component(.weekday) returns 1 = Sunday, 2 = Monday, ...
        return calendar.component(.weekday, from: date) - 1
    }

    static func displayDate(_ dateString: String) -> String {
        guard let date = dateFromString(dateString) else { return dateString }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return "\(month)月\(day)日 \(weekdayNames[weekday])"
    }
}
