//
//  DutyHours.swift
//  CyprusPharmacies
//

import Foundation

/// Duty window of one pharmacy, read from its `description`: open 8:00–23:00 on its day,
/// then the pharmacist is on call by phone until the time the feed gives ("Works until 8:00 AM 2026-10-27").
struct DutyHours: Equatable {
    enum Status: Equatable {
        case opensLater
        case open
        case onCall
        case ended
    }

    let opensAt: Date
    let closesAt: Date
    let endsAt: Date
    /// The rest of the description, e.g. "Call before you go!".
    let note: String
    let timeZone: TimeZone

    /// Nil when the description is not in the known format; the raw text is shown then.
    init?(description: String, dutyDay: String, timeZone: TimeZone = DutyCalendar().timeZone) {
        let lines = description.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first,
              let match = first.wholeMatch(of: #/Works until (\d{1,2}:\d{2}) ?([AP]M) (\d{4}-\d{2}-\d{2})/#),
              let endsAt = Self.parser(timeZone, "h:mm a yyyy-MM-dd").date(from: "\(match.1) \(match.2) \(match.3)")
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // The day the pharmacy is open: the feed's `date`, or the day before the end.
        let day = Self.parser(timeZone, "yyyy-MM-dd").date(from: dutyDay)
            ?? calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: endsAt))
        guard let day,
              let opensAt = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
              let closesAt = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day),
              endsAt > closesAt
        else { return nil }

        self.opensAt = opensAt
        self.closesAt = closesAt
        self.endsAt = endsAt
        self.note = lines.dropFirst().joined(separator: " ")
        self.timeZone = timeZone
    }

    func status(at now: Date) -> Status {
        if now < opensAt { return .opensLater }
        if now < closesAt { return .open }
        if now < endsAt { return .onCall }
        return .ended
    }

    /// First line: where the duty stands right now.
    func headline(at now: Date) -> String {
        switch status(at: now) {
        case .opensLater:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar.isDate(opensAt, inSameDayAs: now)
                ? "Opens at \(time(opensAt))"
                : "Open \(time(opensAt)) – \(time(closesAt))"
        case .open: return "Open now, until \(time(closesAt))"
        case .onCall: return "Pharmacist on call, until \(time(endsAt))"
        case .ended: return "Duty ended at \(time(endsAt))"
        }
    }

    /// Secondary lines under the headline.
    func details(at now: Date) -> [String] {
        var lines: [String] = []
        switch status(at: now) {
        case .opensLater, .open:
            lines.append("On call by phone \(time(closesAt)) – \(time(endsAt))")
        case .onCall, .ended:
            break
        }
        if !note.isEmpty { lines.append(note) }
        return lines
    }

    private func time(_ date: Date) -> String {
        Self.parser(timeZone, "h:mm a").string(from: date)
    }

    private static func parser(_ timeZone: TimeZone, _ format: String, locale: String = "en_US_POSIX") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: locale)
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        formatter.dateFormat = format
        return formatter
    }
}
