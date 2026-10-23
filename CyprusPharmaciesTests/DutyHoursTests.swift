//
//  DutyHoursTests.swift
//  CyprusPharmaciesTests
//

import XCTest
@testable import NightPharmacies

final class DutyHoursTests: XCTestCase {
    private let nicosia = TimeZone(identifier: "Asia/Nicosia")!
    private let feedText = "Works until 8:00 AM 2026-10-24\nCall before you go!"

    private func at(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = nicosia
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func hours(_ text: String? = nil, day: String = "2026-10-23") -> DutyHours? {
        DutyHours(description: text ?? feedText, dutyDay: day, timeZone: nicosia)
    }

    func testParsesFeedFormat() throws {
        let hours = try XCTUnwrap(hours())
        XCTAssertEqual(hours.opensAt, at("2026-10-23 08:00"))
        XCTAssertEqual(hours.closesAt, at("2026-10-23 23:00"))
        XCTAssertEqual(hours.endsAt, at("2026-10-24 08:00"))
        XCTAssertEqual(hours.note, "Call before you go!")
    }

    func testStatusFollowsTheDutyWindow() throws {
        let hours = try XCTUnwrap(hours())
        XCTAssertEqual(hours.status(at: at("2026-10-23 07:59")), .opensLater)
        XCTAssertEqual(hours.status(at: at("2026-10-23 12:00")), .open)
        XCTAssertEqual(hours.status(at: at("2026-10-24 02:00")), .onCall)
        XCTAssertEqual(hours.status(at: at("2026-10-24 08:00")), .ended)
    }

    func testTexts() throws {
        let hours = try XCTUnwrap(hours())
        XCTAssertEqual(hours.headline(at: at("2026-10-23 07:00")), "Opens at 8:00 AM")
        XCTAssertEqual(hours.headline(at: at("2026-10-23 12:00")), "Open now, until 11:00 PM")
        XCTAssertEqual(hours.details(at: at("2026-10-23 12:00")),
                       ["On call by phone 11:00 PM – 8:00 AM", "Call before you go!"])
        XCTAssertEqual(hours.headline(at: at("2026-10-24 02:00")), "Pharmacist on call, until 8:00 AM")
        XCTAssertEqual(hours.details(at: at("2026-10-24 02:00")), ["Call before you go!"])
        XCTAssertEqual(hours.headline(at: at("2026-10-24 09:00")), "Duty ended at 8:00 AM")
    }

    func testFutureDayIsNeverOpenNow() throws {
        let hours = try XCTUnwrap(hours("Works until 8:00 AM 2026-10-28", day: "2026-10-27"))
        let now = at("2026-10-23 12:00")
        XCTAssertEqual(hours.status(at: now), .opensLater)
        XCTAssertEqual(hours.headline(at: now), "Open 8:00 AM – 11:00 PM")
    }

    func testMissingDutyDayIsTheDayBeforeTheEnd() throws {
        let hours = try XCTUnwrap(hours(day: ""))
        XCTAssertEqual(hours.opensAt, at("2026-10-23 08:00"))
    }

    func testUnknownTextFallsBackToRawDescription() {
        XCTAssertNil(hours("Open 24 hours"))
        XCTAssertNil(hours(""))
        XCTAssertNil(hours("Works until 8:00 AM tomorrow"))
        XCTAssertNil(hours("Works until 8:00 AM 2026-10-23"), "an end before closing time is not a duty window")
    }
}
