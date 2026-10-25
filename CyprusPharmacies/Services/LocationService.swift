//
//  LocationService.swift
//  CyprusPharmacies
//

import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject {
    enum Access {
        case notDetermined
        case denied
        case authorized
    }

    private(set) var access: Access = .notDetermined
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pending: [CheckedContinuation<CLLocation?, Never>] = []
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Access, Never>] = []
    /// Called with every new fix, one-shot or from `setTracking`.
    @ObservationIgnored var onUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        access = Self.access(manager.authorizationStatus)
    }

    /// Asks for When In Use access if needed and returns the resulting access.
    func requestAccess() async -> Access {
        guard manager.authorizationStatus == .notDetermined else {
            access = Self.access(manager.authorizationStatus)
            return access
        }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One location fix, or nil when it cannot be obtained.
    func currentLocation() async -> CLLocation? {
        guard access == .authorized else { return nil }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            if pending.count == 1 { manager.requestLocation() }
        }
    }

    /// Follows the user while the app is in front; a fix arrives after moving 25 m.
    func setTracking(_ on: Bool) {
        if on && access == .authorized {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    private func finish(_ location: CLLocation?) {
        if let location {
            self.location = location
            onUpdate?(location)
        }
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: location ?? self.location) }
    }

    private static func access(_ status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        default: return .denied
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.access = Self.access(status)
            guard status != .notDetermined else { return }
            let waiters = self.authorizationWaiters
            self.authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: self.access) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
