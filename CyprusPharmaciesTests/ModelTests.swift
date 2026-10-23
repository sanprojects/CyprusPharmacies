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
    /// 2026-10-23 22:30 UTC is already 2026-10-24 01:30 in Nicosia.
    private let lateEvening = Date(timeIntervalSince1970: 1_792_794_600)

    func testDayKeyUsesCyprusTimeZone() {
        let calendar = DutyCalendar(now: { self.lateEvening })
        XCTAssertEqual(calendar.todayKey, "2026-10-24")
        XCTAssertEqual(calendar.dayKey(offset: 10), "2026-11-03")
    }

    func testTitles() {
        let calendar = DutyCalendar(now: { self.lateEvening })
        XCTAssertEqual(calendar.displayTitle(forDayKey: "2026-10-26"), "Mon 26 Oct 2026")
        XCTAssertEqual(calendar.displayTitle(forDayKey: "garbage"), "garbage")
        XCTAssertEqual(calendar.relativeTitle(offset: 0), "Today")
        XCTAssertEqual(calendar.relativeTitle(offset: 1), "Tomorrow")
        XCTAssertEqual(calendar.relativeTitle(offset: 7), "In 7 days")
        XCTAssertEqual(calendar.menuTitle(offset: 0), "Today, Sat 24 Oct", "01:30 in Nicosia is already the 24th")
        XCTAssertEqual(calendar.menuTitle(offset: 1), "Tomorrow, Sun 25 Oct")
        XCTAssertEqual(calendar.menuTitle(offset: 10), "Tue 3 Nov")
    }

    func testOffsetRange() {
        XCTAssertEqual(DutyCalendar.offsets, 0...10)
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
        PharmacyCache(directory: directory).save(list, dayKey: "2026-10-26")

        let loaded = PharmacyCache(directory: directory).load(dayKey: "2026-10-26")
        XCTAssertEqual(loaded?.pharmacies, list)
        XCTAssertNil(PharmacyCache(directory: directory).load(dayKey: "2026-10-27"))
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
