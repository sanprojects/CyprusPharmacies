//
//  ModelTests.swift
//  CyprusPharmaciesTests
//

import CoreLocation
import XCTest
@testable import NightPharmacies

final class PharmacyDecodingTests: XCTestCase {
    func testDecodesFixtureWithEmptyAndNullFields() throws {
        let list = try PharmacyAPI.decode(Fixture.data("today"))

        XCTAssertEqual(list.count, 3)
        let first = list[0]
        XCTAssertEqual(first.name, "Solomoy Oyrania")
        XCTAssertEqual(first.originalname, "Σολωμού Ουρανία")
        XCTAssertEqual(first.lat, 35.1416276, accuracy: 1e-9)
        XCTAssertEqual(first.description, "Works until 8:00 AM 2026-10-27\nCall before you go!")
        XCTAssertEqual(first.gesyId, "")

        XCTAssertEqual(list[1].originalAddress, "", "null becomes empty")
        XCTAssertEqual(list[1].gesyId, "", "missing becomes empty")
        XCTAssertEqual(list[2].originalname, "")
    }

    func testEmptyArrayIsValid() throws {
        XCTAssertEqual(try PharmacyAPI.decode(Data("[]".utf8)), [])
    }

    func testMissingCoordinateIsDecodingError() {
        let json = Data(#"[{"date":"2026-10-26","name":"X","lat":35.1}]"#.utf8)
        XCTAssertThrowsError(try PharmacyAPI.decode(json)) { error in
            guard case .decoding = error as? PharmacyAPIError else { return XCTFail("\(error)") }
        }
    }

    func testHTMLBodyIsDecodingError() {
        XCTAssertThrowsError(try PharmacyAPI.decode(Data("<html>429 Too Many Requests</html>".utf8)))
    }
}

final class PhoneOptionTests: XCTestCase {
    func testBothNumbersInSpecOrder() throws {
        let pharmacy = try PharmacyAPI.decode(Fixture.data("today"))[0]
        XCTAssertEqual(pharmacy.phoneOptions.map(\.kind), [.pharmacy, .mobile])
        XCTAssertEqual(pharmacy.phoneOptions.map(\.dialURL?.absoluteString), ["tel:+35722313123", "tel:+35722283622"])
    }

    func testEmptyNumberIsSkippedAndFormattingDropped() throws {
        let pharmacy = try PharmacyAPI.decode(Fixture.data("today"))[1]
        XCTAssertEqual(pharmacy.phoneOptions.map(\.kind), [.mobile])
        XCTAssertEqual(pharmacy.phoneOptions.first?.dialURL?.absoluteString, "tel:99123456")
    }

    func testNoNumbersMeansNoCallOptions() throws {
        let pharmacy = try PharmacyAPI.decode(Fixture.data("today"))[2]
        XCTAssertTrue(pharmacy.phoneOptions.isEmpty)
    }

    func testAppleMapsURLForSharing() {
        let pharmacy = Pharmacy(date: "", name: "Polis & Co", lat: 35.0361, lng: 32.4251)
        XCTAssertEqual(pharmacy.appleMapsURL?.absoluteString, "https://maps.apple.com/?ll=35.036100,32.425100&q=Polis%20%26%20Co")
    }

    func testGreekNameOnlyWhenItDiffers() {
        XCTAssertEqual(Pharmacy(date: "", originalname: " ΠΑΠΑΔΟΠΟΥΛΟΣ ", name: "PAPADOPOULOS", lat: 0, lng: 0).greekName, "ΠΑΠΑΔΟΠΟΥΛΟΣ")
        XCTAssertNil(Pharmacy(date: "", originalname: "Papadopoulos", name: "PAPADOPOULOS", lat: 0, lng: 0).greekName)
        XCTAssertNil(Pharmacy(date: "", originalname: "  ", name: "PAPADOPOULOS", lat: 0, lng: 0).greekName)
    }
}

final class DutyCalendarTests: XCTestCase {
    /// 2026-10-23 22:30 UTC is already 2026-10-24 01:30 in Nicosia, still in the duty of the 23rd.
    private let lateEvening = Date(timeIntervalSince1970: 1_792_794_600)
    /// 2026-10-23 05:30 UTC: 08:30 in Nicosia, the duty of the 23rd has begun; in UTC it would not have.
    private let morning = Date(timeIntervalSince1970: 1_792_733_400)

    func testDayKeyUsesCyprusTimeZone() {
        let calendar = DutyCalendar(now: { self.morning })
        XCTAssertEqual(calendar.todayKey, "2026-10-23")
        XCTAssertEqual(calendar.dayKey(offset: 10), "2026-11-02")
    }

    func testDutyDayStartsAt8() {
        let before = DutyCalendar(now: { Date(timeIntervalSince1970: 1_792_731_540) }) // 07:59 Nicosia
        let at = DutyCalendar(now: { Date(timeIntervalSince1970: 1_792_731_600) })     // 08:00 Nicosia
        XCTAssertEqual(before.todayKey, "2026-10-22")
        XCTAssertEqual(at.todayKey, "2026-10-23")
        XCTAssertEqual(DutyCalendar(now: { self.lateEvening }).todayKey, "2026-10-23", "after midnight, before 08:00")
        XCTAssertEqual(before.nextDayStart, Date(timeIntervalSince1970: 1_792_731_600))
        XCTAssertEqual(at.nextDayStart, Date(timeIntervalSince1970: 1_792_731_600 + 24 * 60 * 60))
    }

    func testTitles() {
        let calendar = DutyCalendar(now: { self.lateEvening })
        XCTAssertEqual(calendar.displayTitle(forDayKey: "2026-10-26"), "Mon 26 Oct 2026")
        XCTAssertEqual(calendar.displayTitle(forDayKey: "garbage"), "garbage")
        XCTAssertEqual(calendar.relativeTitle(offset: 0), "Today")
        XCTAssertEqual(calendar.relativeTitle(offset: 1), "Tomorrow")
        XCTAssertEqual(calendar.relativeTitle(offset: 7), "In 7 days")
    }

    func testOffsetRange() {
        XCTAssertEqual(DutyCalendar.offsets, 0...30)
    }

    func testMonthsCoverTheFeedDaysOnly() {
        // Fri 23 Oct 2026 + 30 days = Sun 22 Nov 2026: two months, only the weeks that hold a feed day.
        let months = DutyCalendar(now: { self.morning }).months()
        XCTAssertEqual(months.map(\.title), ["October 2026", "November 2026"])

        let october = months[0].cells
        XCTAssertEqual(october.count % 7, 0)
        XCTAssertEqual(october.first??.day, 19, "the week of the 23rd starts on Mon 19")
        XCTAssertEqual(october.compactMap { $0 }.last?.day, 31)
        XCTAssertEqual(october.compactMap { $0 }.filter { $0.offset != nil }.map(\.day), Array(23...31))
        XCTAssertEqual(october.compactMap { $0 }.first { $0.day == 22 }?.offset, nil, "yesterday is not in the feed")

        let november = months[1].cells
        XCTAssertEqual(november.count, 28, "Nov 1 is a Sunday: six blanks, then four weeks; the week of the 23rd holds no feed day")
        XCTAssertEqual(november.prefix(6).compactMap { $0 }.count, 0)
        XCTAssertEqual(november.compactMap { $0 }.compactMap(\.offset), Array(9...30))
    }
}

final class NavigatorTests: XCTestCase {
    private let target = CLLocationCoordinate2D(latitude: 35.1416276, longitude: 33.3409912)

    func testAppURLs() {
        XCTAssertNil(Navigator.appleMaps.appURL(to: target))
        XCTAssertEqual(Navigator.googleMaps.appURL(to: target)?.absoluteString,
                       "comgooglemaps://?daddr=35.1416276,33.3409912&directionsmode=driving")
        XCTAssertEqual(Navigator.waze.appURL(to: target)?.absoluteString,
                       "waze://?ll=35.1416276,33.3409912&navigate=yes")
    }

    func testWebFallbacks() {
        XCTAssertEqual(Navigator.appleMaps.webURL(to: target)?.absoluteString,
                       "https://maps.apple.com/?daddr=35.1416276,33.3409912&dirflg=d")
        XCTAssertEqual(Navigator.googleMaps.webURL(to: target)?.absoluteString,
                       "https://www.google.com/maps/dir/?api=1&destination=35.1416276,33.3409912&travelmode=driving")
        XCTAssertEqual(Navigator.waze.webURL(to: target)?.absoluteString,
                       "https://waze.com/ul?ll=35.1416276,33.3409912&navigate=yes")
    }

    func testOrderMatchesSpec() {
        XCTAssertEqual(Navigator.allCases.map(\.rawValue), ["Apple Maps", "Google Maps", "Waze"])
    }
}

final class APITests: XCTestCase {
    func testURLCarriesOffset() {
        XCTAssertEqual(PharmacyAPI().url(offset: 3).absoluteString,
                       "https://sanstv.ru/pharmacies/data/today.php?offset=3")
    }

    func testRosterAndCityURLsSitNextToToday() {
        XCTAssertEqual(PharmacyAPI().rosterURL.absoluteString, "https://sanstv.ru/pharmacies/data/days.php")
        XCTAssertEqual(PharmacyAPI().ipCityURL.absoluteString, "https://sanstv.ru/pharmacies/data/geo.php")
    }

    func testRosterDecodes() throws {
        let json = Data(#"{"today":"2026-10-23","days":{"2026-10-23":[{"date":"2026-10-23","name":"A","lat":35,"lng":33}]}}"#.utf8)
        let roster = try PharmacyAPI.decode(Roster.self, from: json)
        XCTAssertEqual(roster.today, "2026-10-23")
        XCTAssertEqual(roster.days["2026-10-23"]?.map(\.name), ["A"])
    }

    func testURLErrorMapping() {
        XCTAssertEqual(PharmacyAPI.map(URLError(.notConnectedToInternet)) as? PharmacyAPIError, .offline)
        XCTAssertEqual(PharmacyAPI.map(URLError(.timedOut)) as? PharmacyAPIError, .transport(.timedOut))
        XCTAssertTrue(PharmacyAPI.map(URLError(.cancelled)) is CancellationError)
    }

    func testLoadErrorKinds() {
        XCTAssertEqual(PharmacyAPIError.transport(.timedOut).kindTag, "timeout")
        XCTAssertEqual(PharmacyLoadError(underlying: .http(status: 503), offset: 2,
                                         url: PharmacyAPI().url(offset: 2)).errorCode, 503)
    }
}

final class PharmacyCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveLoadSurvivesNewInstance() throws {
        let list = try PharmacyAPI.decode(Fixture.data("today"))
        let writer = PharmacyCache(directory: directory)
        writer.save(list, dayKey: "2026-10-26")
        writer.saveRosterStamp(RosterStamp(etag: "\"v1\"", checkedAt: Date(timeIntervalSince1970: 0)))
        // A load waits for the background writes before it.
        XCTAssertNotNil(writer.load(dayKey: "2026-10-26"))

        let loaded = PharmacyCache(directory: directory).load(dayKey: "2026-10-26")
        XCTAssertEqual(loaded?.pharmacies, list)
        XCTAssertNil(PharmacyCache(directory: directory).load(dayKey: "2026-10-27"))
        XCTAssertEqual(PharmacyCache(directory: directory).loadRosterStamp(),
                       RosterStamp(etag: "\"v1\"", checkedAt: Date(timeIntervalSince1970: 0)))
    }

    func testRemovesOnlyDaysBeforeToday() {
        let cache = PharmacyCache(directory: directory)
        for day in ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-30"] {
            cache.save([], dayKey: day)
        }
        cache.removeDays(before: "2026-10-23")

        XCTAssertNil(cache.load(dayKey: "2026-10-21"))
        XCTAssertNil(cache.load(dayKey: "2026-10-22"))
        XCTAssertNotNil(cache.load(dayKey: "2026-10-23"))
        XCTAssertNotNil(cache.load(dayKey: "2026-10-30"))
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private final class BundleToken {}
}

final class BearingTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 35, longitude: 33)

    private func bearing(toLat lat: Double, lng: Double) -> Double {
        origin.bearing(to: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    func testCardinalDirections() {
        XCTAssertEqual(bearing(toLat: 36, lng: 33), 0, accuracy: 0.01)
        XCTAssertEqual(bearing(toLat: 35, lng: 34), 90, accuracy: 0.5)
        XCTAssertEqual(bearing(toLat: 34, lng: 33), 180, accuracy: 0.01)
        XCTAssertEqual(bearing(toLat: 35, lng: 32), 270, accuracy: 0.5)
    }
}
