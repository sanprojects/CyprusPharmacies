//
//  Navigator.swift
//  CyprusPharmacies
//

import CoreLocation
import UIKit

/// Navigation apps offered by "Get directions". Every route starts at the user's current location.
enum Navigator: String, CaseIterable, Identifiable {
    case appleMaps = "Apple Maps"
    case googleMaps = "Google Maps"
    case waze = "Waze"

    var id: String { rawValue }

    /// Native app URL. Apple Maps always exists on iOS, so it has only the universal link.
    func appURL(to destination: CLLocationCoordinate2D) -> URL? {
        let ll = Self.format(destination)
        switch self {
        case .appleMaps:
            return nil
        case .googleMaps:
            return URL(string: "comgooglemaps://?daddr=\(ll)&directionsmode=driving")
        case .waze:
            return URL(string: "waze://?ll=\(ll)&navigate=yes")
        }
    }

    /// Universal / web link used when the app is not installed.
    func webURL(to destination: CLLocationCoordinate2D) -> URL? {
        let ll = Self.format(destination)
        switch self {
        case .appleMaps:
            return URL(string: "https://maps.apple.com/?daddr=\(ll)&dirflg=d")
        case .googleMaps:
            return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(ll)&travelmode=driving")
        case .waze:
            return URL(string: "https://waze.com/ul?ll=\(ll)&navigate=yes")
        }
    }

    @MainActor
    func open(to destination: CLLocationCoordinate2D) {
        let application = UIApplication.shared
        if let app = appURL(to: destination), application.canOpenURL(app) {
            application.open(app)
        } else if let web = webURL(to: destination) {
            application.open(web)
        }
    }

    private static func format(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.7f,%.7f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
    }
}
