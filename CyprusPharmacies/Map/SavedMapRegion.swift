//
//  SavedMapRegion.swift
//  CyprusPharmacies
//

import CoreLocation
import MapKit

/// The part of the map the user last looked at, kept between launches.
struct SavedMapRegion: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double

    init(_ region: MKCoordinateRegion) {
        latitude = region.center.latitude
        longitude = region.center.longitude
        latitudeDelta = region.span.latitudeDelta
        longitudeDelta = region.span.longitudeDelta
    }

    /// Nil for a region that cannot be shown, e.g. one read from damaged storage.
    var region: MKCoordinateRegion? {
        let values = [latitude, longitude, latitudeDelta, longitudeDelta]
        guard values.allSatisfy(\.isFinite),
              abs(latitude) <= 90, abs(longitude) <= 180,
              latitudeDelta > 0, latitudeDelta <= 180, longitudeDelta > 0, longitudeDelta <= 360 else { return nil }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                  span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

extension MKCoordinateRegion {
    /// Room left around a pin that the zoom-out brings in, as a share of the span.
    private static let widenMargin = 1.25

    /// The same center with the smallest zoom-out that brings the nearest of `points` in, or nil when one is in already.
    /// `topInset` is the share of the height the date bar covers: a pin under it does not count as in view.
    func widened(toInclude points: [CLLocationCoordinate2D], topInset: Double = 0) -> MKCoordinateRegion? {
        guard span.latitudeDelta > 0, span.longitudeDelta > 0 else { return nil }
        /// How many times the span must grow for `point` to lie within `room` of the center, as a share of the span.
        func growth(for point: CLLocationCoordinate2D, room: Double) -> Double {
            let north = (point.latitude - center.latitude) / span.latitudeDelta
            let east = abs(point.longitude - center.longitude) / span.longitudeDelta
            return max(north > 0 ? north / (0.5 - topInset) : -north / 0.5, east / 0.5) / room
        }
        guard let needed = points.map({ growth(for: $0, room: 1 / Self.widenMargin) }).min(),
              points.map({ growth(for: $0, room: 1) }).min()! > 1 else { return nil }
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: min(180, span.latitudeDelta * needed),
                                                         longitudeDelta: min(360, span.longitudeDelta * needed)))
    }
}

protocol MapRegionStoring {
    func load() -> SavedMapRegion?
    func save(_ region: SavedMapRegion)
}

struct UserDefaultsMapRegionStore: MapRegionStoring {
    static let key = "savedMapRegion"
    var defaults: UserDefaults = .standard

    func load() -> SavedMapRegion? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(SavedMapRegion.self, from: data)
    }

    func save(_ region: SavedMapRegion) {
        defaults.set(try? JSONEncoder().encode(region), forKey: Self.key)
    }
}
