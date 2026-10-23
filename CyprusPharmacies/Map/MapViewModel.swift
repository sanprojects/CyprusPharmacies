//
//  MapViewModel.swift
//  CyprusPharmacies
//

import CoreLocation
import Foundation
import Observation

/// Instructions for the map view; a new `id` makes the map apply the command once.
struct MapCommand: Equatable {
    enum Kind: Equatable {
        case showIsland
        /// Center on a pharmacy so it stays visible above a sheet of `bottomInset` points;
        /// `zoomIn` brings it out of a cluster when it was picked in the list.
        case focus(CLLocationCoordinate2D, bottomInset: CGFloat, zoomIn: Bool)
        /// Fit the user and, when known, the nearest pharmacy.
        case showUser(CLLocationCoordinate2D, nearest: CLLocationCoordinate2D?)
    }

    let id = UUID()
    let kind: Kind
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

@MainActor
protocol LocationProviding: AnyObject {
    var access: LocationService.Access { get }
    func requestAccess() async -> LocationService.Access
    func currentLocation() async -> CLLocation?
}

extension LocationService: LocationProviding {}

@MainActor
@Observable
final class MapViewModel {
    enum Blocking: Equatable {
        case noInternet
        case failure
    }

    private(set) var offset = 0
    private(set) var dayKey: String
    /// Pharmacies of `dayKey`, never of another day.
    private(set) var pharmacies: [Pharmacy] = []
    /// `pharmacies` came from the server or the cache; false while the day is unknown, e.g. after a failed load.
    private(set) var isDayLoaded = false
    private(set) var isLoading = false
    private(set) var blocking: Blocking?
    private(set) var mapCommand: MapCommand? = MapCommand(kind: .showIsland)
    private(set) var showsUserLocation = false
    /// Last known position; set only once location access is granted.
    private(set) var userLocation: CLLocation?
    var selected: Pharmacy?
    var isLocationDeniedAlertShown = false

    @ObservationIgnored private let api: PharmacyFetching
    @ObservationIgnored private let cache: PharmacyCaching
    @ObservationIgnored private let network: NetworkStatusProviding
    @ObservationIgnored private let reporter: LoadErrorReporting
    @ObservationIgnored private let location: LocationProviding
    @ObservationIgnored let calendar: DutyCalendar
    /// A cached day younger than this is shown without asking the server again.
    @ObservationIgnored private let refreshInterval: TimeInterval
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastShownOffset: Int?
    /// The selection came from the list, where its pin may be hidden in a cluster.
    @ObservationIgnored private var zoomsToSelection = false

    init(api: PharmacyFetching,
         cache: PharmacyCaching,
         network: NetworkStatusProviding,
         reporter: LoadErrorReporting,
         location: LocationProviding,
         calendar: DutyCalendar = DutyCalendar(),
         refreshInterval: TimeInterval = 15 * 60) {
        self.api = api
        self.cache = cache
        self.network = network
        self.reporter = reporter
        self.location = location
        self.calendar = calendar
        self.refreshInterval = refreshInterval
        self.dayKey = calendar.todayKey
        self.showsUserLocation = location.access == .authorized
        network.onChange = { [weak self] connected in
            MainActor.assumeIsolated { self?.networkChanged(connected: connected) }
        }
    }

    // MARK: - Day navigation

    var canGoToPreviousDay: Bool { offset > 0 }
    var canGoToNextDay: Bool { offset < DutyCalendar.maxOffset }

    /// Date of the shown day: the feed's `date` when there is data, otherwise the date computed from `offset`.
    var dateTitle: String { calendar.displayTitle(forDayKey: pharmacies.first?.date ?? dayKey) }
    var relativeDayTitle: String { calendar.relativeTitle(offset: offset) }

    func start() {
        cache.removeDays(before: calendar.todayKey)
        load()
        Task { await refreshUserLocation() }
    }

    func previousDay() { show(offset: offset - 1) }
    func nextDay() { show(offset: offset + 1) }

    func show(offset newOffset: Int) {
        guard DutyCalendar.offsets.contains(newOffset), newOffset != offset || blocking != nil else { return }
        offset = newOffset
        selected = nil
        load()
    }

    /// App came to the foreground or the calendar day changed.
    func refreshIfNeeded() {
        cache.removeDays(before: calendar.todayKey)
        if blocking == nil || dayKey != calendar.dayKey(offset: offset) {
            load()
        }
    }

    func retry() { load() }

    /// OK on "Something went wrong": back to the last day that was shown successfully.
    func dismissFailure() {
        blocking = nil
        if let lastShownOffset, lastShownOffset != offset {
            offset = lastShownOffset
            load()
        }
    }

    // MARK: - Loading

    /// Shows the cached day at once, then asks the server unless the cache is fresh.
    func load() {
        loadTask?.cancel()
        generation += 1
        let token = generation
        let requestedOffset = offset
        let key = calendar.dayKey(offset: requestedOffset)
        let cached = cache.load(dayKey: key)

        if dayKey != key { selected = nil }
        dayKey = key
        if let cached {
            apply(cached.pharmacies, offset: requestedOffset)
        } else {
            pharmacies = []
            isDayLoaded = false
            selected = nil
        }

        if let cached, Date().timeIntervalSince(cached.savedAt) < refreshInterval {
            isLoading = false
            return
        }

        isLoading = true
        loadTask = Task { [weak self] in
            await self?.fetch(offset: requestedOffset, dayKey: key, hasCache: cached != nil, token: token)
        }
    }

    private func fetch(offset requestedOffset: Int, dayKey key: String, hasCache: Bool, token: Int) async {
        defer { if token == generation { isLoading = false } }

        guard await network.isConnected() else {
            guard token == generation else { return }
            if !hasCache { blocking = .noInternet }
            return
        }
        guard token == generation, !Task.isCancelled else { return }

        do {
            let list = try await api.pharmacies(offset: requestedOffset)
            guard token == generation, !Task.isCancelled else { return }
            cache.save(list, dayKey: key)
            apply(list, offset: requestedOffset)
        } catch let error as PharmacyAPIError {
            guard token == generation, !Task.isCancelled else { return }
            if error == .offline {
                if !hasCache { blocking = .noInternet }
                return
            }
            reporter.report(loadError: error, offset: requestedOffset, url: api.url(offset: requestedOffset))
            // A cached day stays on screen; the refresh failure is only reported.
            if !hasCache { blocking = .failure }
        } catch {
            // CancellationError: the user moved to another day.
        }
    }

    private func apply(_ list: [Pharmacy], offset shownOffset: Int) {
        blocking = nil
        lastShownOffset = shownOffset
        isDayLoaded = true
        if list != pharmacies {
            if let selected, !list.contains(selected) { self.selected = nil }
            pharmacies = list
        }
    }

    private func networkChanged(connected: Bool) {
        if connected && blocking == .noInternet { load() }
    }

    // MARK: - Map

    func select(_ pharmacy: Pharmacy?, zoomIn: Bool = false) {
        selected = pharmacy
        zoomsToSelection = zoomIn && pharmacy != nil
    }

    func focus(on pharmacy: Pharmacy, bottomInset: CGFloat) {
        mapCommand = MapCommand(kind: .focus(pharmacy.coordinate, bottomInset: bottomInset, zoomIn: zoomsToSelection))
    }

    func nearestPharmacy(to location: CLLocation) -> Pharmacy? {
        pharmacies.min {
            location.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))
                < location.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lng))
        }
    }

    /// Straight-line distance from the user, when their position is known.
    func distance(to pharmacy: Pharmacy) -> CLLocationDistance? {
        userLocation?.distance(from: CLLocation(latitude: pharmacy.lat, longitude: pharmacy.lng))
    }

    /// The day's pharmacies for the list: nearest first when the user's position is known, otherwise by name.
    var sortedPharmacies: [Pharmacy] {
        if userLocation != nil {
            return pharmacies.sorted { (distance(to: $0) ?? 0) < (distance(to: $1) ?? 0) }
        }
        return pharmacies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Updates `userLocation` without moving the map and without asking for access.
    func refreshUserLocation() async {
        guard location.access == .authorized else { return }
        showsUserLocation = true
        if let here = await location.currentLocation() { userLocation = here }
    }

    func locateUser() async {
        switch await location.requestAccess() {
        case .denied:
            showsUserLocation = false
            isLocationDeniedAlertShown = true
            return
        case .notDetermined:
            return
        case .authorized:
            showsUserLocation = true
        }
        guard let here = await location.currentLocation() else { return }
        userLocation = here
        mapCommand = MapCommand(kind: .showUser(here.coordinate, nearest: nearestPharmacy(to: here)?.coordinate))
    }
}
