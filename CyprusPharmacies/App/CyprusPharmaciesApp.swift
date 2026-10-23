//
//  CyprusPharmaciesApp.swift
//  CyprusPharmacies
//

import SwiftUI

@main
struct CyprusPharmaciesApp: App {
    @State private var model: MapViewModel

    init() {
        ErrorReporter.shared.start()

        var api = PharmacyAPI()
        var forcedOffline = false
        let cache = PharmacyCache()
        #if DEBUG
        // Launch arguments for manual checks, e.g. `-simulateOffline YES`, `-apiBaseURL https://…/missing.php`, `-resetCache YES`.
        let defaults = UserDefaults.standard
        if let override = defaults.string(forKey: "apiBaseURL"), let url = URL(string: override) {
            api.baseURL = url
        }
        forcedOffline = defaults.bool(forKey: "simulateOffline")
        if defaults.bool(forKey: "resetCache") { cache.removeAll() }
        #endif

        _model = State(initialValue: MapViewModel(
            api: api,
            cache: cache,
            network: NetworkMonitor(forcedOffline: forcedOffline),
            reporter: ErrorReporter.shared,
            location: LocationService()
        ))
    }

    var body: some Scene {
        WindowGroup {
            MapScreen(model: model)
        }
    }
}
