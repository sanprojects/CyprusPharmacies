//
//  DutyCalendar.swift
//  CyprusPharmacies
//

import Foundation

/// Maps an API `offset` to a duty day in Cyprus, whatever time zone the device is in.
/// A duty runs from 08:00 to 08:00 the next morning, so until 08:00 "today" is yesterday's duty, as on the server.
struct DutyCalendar {
    static let maxOffset = 30
    static let offsets = 0...maxOffset
    static let dayStartHour = 8

    var timeZone: TimeZone = TimeZone(identifier: "Asia/Nicosia") ?? .current
    var now: () -> Date = Date.init

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func formatter(_ format: String, locale: String = "en_GB") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = format
        return formatter
    }

    /// Today's duty day + `offset`, at the current time of day.
    private func dutyDate(offset: Int) -> Date {
        let now = now()
        let started = calendar.component(.hour, from: now) >= Self.dayStartHour
        return calendar.date(byAdding: .day, value: offset - (started ? 0 : 1), to: now) ?? now
    }

    /// When the next duty day starts.
    var nextDayStart: Date {
        calendar.nextDate(after: now(), matching: DateComponents(hour: Self.dayStartHour, minute: 0, second: 0),
                          matchingPolicy: .nextTime) ?? now().addingTimeInterval(24 * 60 * 60)
    }

    /// `YYYY-MM-DD` of today + `offset`, the same format as the `date` field of the feed.
    func dayKey(offset: Int) -> String {
        let day = dutyDate(offset: offset)
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var todayKey: String { dayKey(offset: 0) }

    /// "Fri 23 Oct 2026" for a `YYYY-MM-DD` key; the key itself when it does not parse.
    func displayTitle(forDayKey key: String) -> String {
        guard let date = formatter("yyyy-MM-dd", locale: "en_US_POSIX").date(from: key) else { return key }
        return formatter("EEE d MMM yyyy").string(from: date)
    }

    func relativeTitle(offset: Int) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(offset) days"
        }
    }

    // MARK: - Month grids

    /// A month of the grid: Monday-first weeks of `cells`, `nil` for the blanks around the month; weeks without a day of the feed are left out.
    struct Month: Equatable {
        let title: String
        let cells: [Cell?]
    }

    struct Cell: Equatable {
        let day: Int
        /// API offset of the day; nil when the feed does not cover it.
        let offset: Int?
    }

    /// Weekday headings of the grid, Monday first.
    static let weekdayTitles = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// The months that hold today's duty day and the days after it up to `maxOffset`.
    func months() -> [Month] {
        let calendar = calendar
        let first = calendar.startOfDay(for: dutyDate(offset: 0))
        let last = calendar.startOfDay(for: dutyDate(offset: Self.maxOffset))
        let monthTitle = formatter("LLLL yyyy")

        var months: [Month] = []
        var cursor = calendar.dateInterval(of: .month, for: first)?.start ?? first
        while cursor <= last {
            let days = calendar.range(of: .day, in: .month, for: cursor)?.count ?? 30
            // Sunday is 1 in Gregorian weekdays; Monday-first puts it last.
            let lead = (calendar.component(.weekday, from: cursor) + 5) % 7
            var cells: [Cell?] = Array(repeating: nil, count: lead)
            for index in 0..<days {
                let date = calendar.date(byAdding: .day, value: index, to: cursor) ?? cursor
                let distance = calendar.dateComponents([.day], from: first, to: date).day ?? -1
                cells.append(Cell(day: index + 1, offset: Self.offsets.contains(distance) ? distance : nil))
            }
            // Only the weeks that hold a day of the feed; the rest of a month adds nothing.
            cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
            let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
            let shown = weeks.filter { $0.contains { $0?.offset != nil } }.flatMap { $0 }
            months.append(Month(title: monthTitle.string(from: cursor), cells: shown))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }
}
