//
//  DutyCalendar.swift
//  CyprusPharmacies
//

import Foundation

/// Maps an API `offset` to a calendar day in Cyprus, whatever time zone the device is in.
struct DutyCalendar {
    static let maxOffset = 10
    static let offsets = 0...maxOffset

    var timeZone: TimeZone = TimeZone(identifier: "Asia/Nicosia") ?? .current
    var now: () -> Date = Date.init

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `YYYY-MM-DD` of today + `offset`, the same format as the `date` field of the feed.
    func dayKey(offset: Int) -> String {
        let day = calendar.date(byAdding: .day, value: offset, to: now()) ?? now()
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
        let day = calendar.date(byAdding: .day, value: offset, to: now()) ?? now()
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
