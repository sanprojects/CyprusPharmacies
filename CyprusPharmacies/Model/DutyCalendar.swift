//
//  DutyCalendar.swift
//  CyprusPharmacies
//

import Foundation

/// Maps an API `offset` to a duty day in Cyprus, whatever time zone the device is in.
/// A duty runs from 08:00 to 08:00 the next morning, so until 08:00 "today" is yesterday's duty, as on the server.
struct DutyCalendar {
    static let maxOffset = 10
    static let offsets = 0...maxOffset
    static let dayStartHour = 8

    var timeZone: TimeZone = TimeZone(identifier: "Asia/Nicosia") ?? .current
    var now: () -> Date = Date.init

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
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
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE d MMM yyyy"
        return formatter.string(from: date)
    }

    /// Item of the day menu: "Today, Fri 23 Oct", "Tomorrow, Sat 24 Oct", then "Sun 25 Oct".
    func menuTitle(offset: Int) -> String {
        let day = dutyDate(offset: offset)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE d MMM"
        let date = formatter.string(from: day)
        return offset < 2 ? "\(relativeTitle(offset: offset)), \(date)" : date
    }

    func relativeTitle(offset: Int) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(offset) days"
        }
    }
}
