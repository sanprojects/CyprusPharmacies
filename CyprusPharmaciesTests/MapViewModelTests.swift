//
//  MapViewModelTests.swift
//  CyprusPharmaciesTests
//

import CoreLocation
import XCTest
@testable import NightPharmacies

@MainActor
final class MapViewModelTests: XCTestCase {
    private var api: FakeAPI!
    private var cache: MemoryCache!
    private var network: FakeNetwork!
    private var reporter: SpyReporter!
    private var location: FakeLocation!
    private let calendar = DutyCalendar(now: { Date(timeIntervalSince1970: 1_792_746_000) }) // 2026-10-23 12:00 Nicosia

    override func setUp() async throws {
        api = FakeAPI()
        cache = MemoryCache()
        network = FakeNetwork()
        reporter = SpyReporter()
        location = FakeLocation()
    }

    private func makeModel() -> MapViewModel {
        MapViewModel(api: api, cache: cache, network: network, reporter: reporter,
                     location: location, calendar: calendar)
    }

    private func pharmacy(_ name: String, day: String = "2026-10-23", lat: Double = 35, lng: Double = 33) -> Pharmacy {
        Pharmacy(date: day, name: name, lat: lat, lng: lng)
    }

    /// Lets the load task run to completion.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testSuccessShowsAndCachesDay() async {
        api.results[0] = .success([pharmacy("A")])
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertEqual(model.pharmacies.map(\.name), ["A"])
        XCTAssertNil(model.blocking)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(cache.days["2026-10-23"]?.pharmacies.map(\.name), ["A"])
        XCTAssertEqual(model.dateTitle, "Fri 23 Oct 2026")
    }

    func testOfflineWithoutCacheShowsNoInternetAndSkipsRequestAndReport() async {
        network.connected = false
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertEqual(model.blocking, .noInternet)
        XCTAssertTrue(api.requested.isEmpty, "no request while offline")
        XCTAssertTrue(reporter.reports.isEmpty)
    }

    func testOfflineWithCacheShowsCache() async {
        network.connected = false
        cache.days["2026-10-23"] = CachedDay(dayKey: "2026-10-23", savedAt: .distantPast, pharmacies: [pharmacy("Cached")])
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertNil(model.blocking)
        XCTAssertEqual(model.pharmacies.map(\.name), ["Cached"])
    }

    func testConnectionLostMidRequestIsNotReported() async {
        api.results[0] = .failure(PharmacyAPIError.offline)
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertEqual(model.blocking, .noInternet)
        XCTAssertTrue(reporter.reports.isEmpty)
    }

    func testHTTPErrorShowsFailureAndReports() async {
        api.results[0] = .failure(PharmacyAPIError.http(status: 500))
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertEqual(model.blocking, .failure)
        XCTAssertEqual(reporter.reports.count, 1)
        XCTAssertEqual(reporter.reports.first?.0, .http(status: 500))
        XCTAssertEqual(reporter.reports.first?.1, 0)
    }

    func testRefreshFailureKeepsStaleCacheOnScreenButReports() async {
        cache.days["2026-10-23"] = CachedDay(dayKey: "2026-10-23", savedAt: .distantPast, pharmacies: [pharmacy("Cached")])
        api.results[0] = .failure(PharmacyAPIError.decoding("bad"))
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertNil(model.blocking)
        XCTAssertEqual(model.pharmacies.map(\.name), ["Cached"])
        XCTAssertEqual(reporter.reports.count, 1)
    }

    func testFreshCacheSkipsRequest() async {
        cache.days["2026-10-23"] = CachedDay(dayKey: "2026-10-23", savedAt: Date(), pharmacies: [pharmacy("Cached")])
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertTrue(api.requested.isEmpty)
        XCTAssertEqual(model.pharmacies.map(\.name), ["Cached"])
    }

    func testEmptyListIsAnEmptyMapNotAnError() async {
        api.results[0] = .success([])
        let model = makeModel()
        model.start()
        await settle()

        XCTAssertNil(model.blocking)
        XCTAssertTrue(model.pharmacies.isEmpty)
        XCTAssertTrue(model.isDayLoaded, "an empty day is a loaded day")
        XCTAssertTrue(reporter.reports.isEmpty)
        XCTAssertEqual(model.dateTitle, "Fri 23 Oct 2026", "date comes from the offset")
    }

    func testDayBounds() async {
        for offset in 0...10 { api.results[offset] = .success([]) }
        let model = makeModel()
        model.start()
        XCTAssertFalse(model.canGoToPreviousDay)
        model.previousDay()
        XCTAssertEqual(model.offset, 0)

        for _ in 0..<15 { model.nextDay() }
        XCTAssertEqual(model.offset, 10)
        XCTAssertFalse(model.canGoToNextDay)
        XCTAssertEqual(model.dayKey, "2026-11-02")
        await settle()
        XCTAssertFalse(api.requested.contains { $0 > 10 })
    }

    func testStaleResultOfPreviousDayIsIgnored() async {
        api.delays[0] = 0.2
        api.results[0] = .success([pharmacy("Today")])
        api.results[1] = .success([pharmacy("Tomorrow", day: "2026-10-24")])
        let model = makeModel()
        model.start()
        await Task.yield()
        model.nextDay()
        try? await Task.sleep(nanoseconds: 400_000_000)
        await settle()

        XCTAssertEqual(model.offset, 1)
        XCTAssertEqual(model.pharmacies.map(\.name), ["Tomorrow"])
        XCTAssertNil(cache.days["2026-10-23"], "cancelled day is not saved")
    }

    func testDismissFailureReturnsToLastShownDay() async {
        api.results[0] = .success([pharmacy("Today")])
        api.results[1] = .failure(PharmacyAPIError.http(status: 404))
        let model = makeModel()
        model.start()
        await settle()
        model.nextDay()
        await settle()
        XCTAssertEqual(model.blocking, .failure)

        cache.days["2026-10-23"] = CachedDay(dayKey: "2026-10-23", savedAt: Date(), pharmacies: [pharmacy("Today")])
        model.dismissFailure()
        await settle()

        XCTAssertNil(model.blocking)
        XCTAssertEqual(model.offset, 0)
        XCTAssertEqual(model.pharmacies.map(\.name), ["Today"])
    }

    func testDismissFailureWithoutShownDayIsNotAnEmptyDay() async {
        api.results[0] = .failure(PharmacyAPIError.http(status: 404))
        let model = makeModel()
        model.start()
        await settle()
        model.dismissFailure()

        XCTAssertNil(model.blocking)
        XCTAssertEqual(model.offset, 0)
        XCTAssertFalse(model.isDayLoaded, "no \"No duty pharmacies\" hint for a day that failed to load")
    }

    func testChangingDayClearsSelection() async {
        api.results[0] = .success([pharmacy("A")])
        api.results[1] = .success([])
        let model = makeModel()
        model.start()
        await settle()
        model.select(model.pharmacies.first)
        XCTAssertNotNil(model.selected)

        model.nextDay()
        XCTAssertNil(model.selected)
    }

    func testStartRemovesPastDays() {
        cache.days["2026-10-22"] = CachedDay(dayKey: "2026-10-22", savedAt: Date(), pharmacies: [])
        makeModel().start()
        XCTAssertEqual(cache.removedBefore, ["2026-10-23"])
    }

    func testNetworkReturnRetriesNoInternetDay() async {
        network.connected = false
        api.results[0] = .success([pharmacy("A")])
        let model = makeModel()
        model.start()
        await settle()
        XCTAssertEqual(model.blocking, .noInternet)

        network.connected = true
        network.onChange?(true)
        await settle()
        XCTAssertNil(model.blocking)
        XCTAssertEqual(model.pharmacies.map(\.name), ["A"])
    }

    func testLocateUserFocusesNearestPharmacy() async {
        api.results[0] = .success([pharmacy("Far", lat: 34.7, lng: 33.0), pharmacy("Near", lat: 35.17, lng: 33.36)])
        location.accessResult = .authorized
        location.location = CLLocation(latitude: 35.16, longitude: 33.35)
        let model = makeModel()
        model.start()
        await settle()

        await model.locateUser()
        XCTAssertTrue(model.showsUserLocation)
        guard case let .showUser(_, nearest)? = model.mapCommand?.kind else { return XCTFail("no command") }
        XCTAssertEqual(nearest, CLLocationCoordinate2D(latitude: 35.17, longitude: 33.36))
    }

    func testLocateUserDeniedShowsAlert() async {
        location.accessResult = .denied
        let model = makeModel()
        await model.locateUser()
        XCTAssertTrue(model.isLocationDeniedAlertShown)
        XCTAssertFalse(model.showsUserLocation)
    }
}

// MARK: - Fakes

private final class FakeAPI: PharmacyFetching {
    var results: [Int: Result<[Pharmacy], Error>] = [:]
    var delays: [Int: TimeInterval] = [:]
    private(set) var requested: [Int] = []

    func url(offset: Int) -> URL { URL(string: "https://example.test/today.php?offset=\(offset)")! }

    func pharmacies(offset: Int) async throws -> [Pharmacy] {
        requested.append(offset)
        if let delay = delays[offset] {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try (results[offset] ?? .failure(PharmacyAPIError.http(status: 404))).get()
    }
}

private final class MemoryCache: PharmacyCaching {
    var days: [String: CachedDay] = [:]
    private(set) var removedBefore: [String] = []

    func load(dayKey: String) -> CachedDay? { days[dayKey] }
    func save(_ pharmacies: [Pharmacy], dayKey: String) {
        days[dayKey] = CachedDay(dayKey: dayKey, savedAt: Date(), pharmacies: pharmacies)
    }
    func removeDays(before todayKey: String) {
        removedBefore.append(todayKey)
        days = days.filter { $0.key >= todayKey }
    }
}

private final class FakeNetwork: NetworkStatusProviding {
    var connected = true
    var onChange: ((Bool) -> Void)?
    func isConnected() async -> Bool { connected }
}

private final class SpyReporter: LoadErrorReporting {
    private(set) var reports: [(PharmacyAPIError, Int, URL)] = []
    func report(loadError: PharmacyAPIError, offset: Int, url: URL) {
        reports.append((loadError, offset, url))
    }
}

@MainActor
private final class FakeLocation: LocationProviding {
    var access: LocationService.Access = .notDetermined
    var accessResult: LocationService.Access = .notDetermined
    var location: CLLocation?

    func requestAccess() async -> LocationService.Access {
        access = accessResult
        return accessResult
    }

    func currentLocation() async -> CLLocation? { location }
}
