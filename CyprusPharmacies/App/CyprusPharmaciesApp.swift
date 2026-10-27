//
//  CyprusPharmaciesApp.swift
//  CyprusPharmacies
//

import CoreLocation
import SwiftUI

@main
struct CyprusPharmaciesApp: App {
    @State private var model: MapViewModel

    init() {
        ErrorReporter.shared.start()

        var api = PharmacyAPI()
        var fetcher: PharmacyFetching = api
        var forcedOffline = false
        var cache = PharmacyCache()
        var regionStore: MapRegionStoring? = UserDefaultsMapRegionStore()
        #if DEBUG
        // Launch arguments for manual checks, e.g. `-simulateOffline YES`, `-apiBaseURL https://…/missing.php`, `-resetCache YES`.
        let defaults = UserDefaults.standard
        if let override = defaults.string(forKey: "apiBaseURL"), let url = URL(string: override) {
            api.baseURL = url
            fetcher = api
        }
        // UI tests pass the feed in the environment, and keep their days out of the real cache.
        if let fixture = ProcessInfo.processInfo.environment["PHARMACIES_FIXTURE"] {
            fetcher = FixturePharmacies(json: Data(fixture.utf8))
            cache = PharmacyCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("UITestCache"))
            regionStore = nil
        }
        forcedOffline = defaults.bool(forKey: "simulateOffline")
        if defaults.bool(forKey: "resetCache") {
            cache.removeAll()
            defaults.removeObject(forKey: UserDefaultsMapRegionStore.key)
        }
        #endif

        _model = State(initialValue: MapViewModel(
            api: fetcher,
            cache: cache,
            network: NetworkMonitor(forcedOffline: forcedOffline),
            reporter: ErrorReporter.shared,
            location: LocationService(),
            regionStore: regionStore
        ))
    }

    var body: some Scene {
        WindowGroup {
            MapScreen(model: model)
        }
    }
}

#if DEBUG
/// The same pharmacies for every day.
private struct FixturePharmacies: PharmacyFetching {
    let json: Data

    func url(offset: Int) -> URL {
        URL(fileURLWithPath: "/fixture/\(offset)")
    }

    func pharmacies(offset: Int) async throws -> [Pharmacy] {
        try PharmacyAPI.decode(json)
    }

    /// A server without the roster, so every day comes from `pharmacies(offset:)`.
    func roster(etag: String?) async throws -> RosterResponse {
        throw PharmacyAPIError.http(status: 404)
    }

    func ipCity() async -> CLLocationCoordinate2D? { nil }
}
#endif
