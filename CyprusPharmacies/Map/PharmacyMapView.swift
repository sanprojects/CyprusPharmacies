//
//  PharmacyMapView.swift
//  CyprusPharmacies
//

import MapKit
import SwiftUI

/// `MKMapView` in SwiftUI: SwiftUI `Map` on iOS 17 has no annotation clustering.
struct PharmacyMapView: UIViewRepresentable {
    static let cyprus = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.13, longitude: 33.43),
        span: MKCoordinateSpan(latitudeDelta: 1.25, longitudeDelta: 2.45)
    )

    let pharmacies: [Pharmacy]
    let selected: Pharmacy?
    let command: MapCommand?
    let showsUserLocation: Bool
    /// Height covered by the overlay at the top (date bar), so focusing keeps pins out from under it.
    let topInset: CGFloat
    let onSelect: (Pharmacy?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.register(PharmacyAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(ClusterAnnotationView.self,
                         forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        mapView.setRegion(Self.cyprus, animated: false)
        mapView.accessibilityIdentifier = "pharmacyMap"
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        mapView.showsUserLocation = showsUserLocation
        coordinator.sync(pharmacies, on: mapView)
        coordinator.syncSelection(selected, on: mapView)
        if let command, command.id != coordinator.appliedCommand {
            coordinator.appliedCommand = command.id
            // Wait for the first layout so bounds are known.
            DispatchQueue.main.async { coordinator.apply(command.kind, on: mapView) }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PharmacyMapView?
        var appliedCommand: UUID?
        private var shownIDs: [String] = []
        private var annotations: [String: PharmacyAnnotation] = [:]

        func sync(_ pharmacies: [Pharmacy], on mapView: MKMapView) {
            let ids = pharmacies.map(\.id)
            guard ids != shownIDs else { return }
            shownIDs = ids
            mapView.removeAnnotations(Array(annotations.values))
            annotations = Dictionary(pharmacies.map { ($0.id, PharmacyAnnotation($0)) }, uniquingKeysWith: { first, _ in first })
            mapView.addAnnotations(Array(annotations.values))
        }

        func syncSelection(_ selected: Pharmacy?, on mapView: MKMapView) {
            let current = mapView.selectedAnnotations.compactMap { $0 as? PharmacyAnnotation }.first
            guard current?.pharmacy.id != selected?.id else { return }
            if let selected, let annotation = annotations[selected.id] {
                mapView.selectAnnotation(annotation, animated: true)
            } else if let current {
                mapView.deselectAnnotation(current, animated: true)
            }
        }

        func apply(_ kind: MapCommand.Kind, on mapView: MKMapView) {
            let topInset = parent?.topInset ?? 0
            switch kind {
            case .showIsland:
                mapView.setRegion(PharmacyMapView.cyprus, animated: true)

            case let .focus(coordinate, bottomInset):
                let height = mapView.bounds.height
                guard height > 0 else { return }
                let span = mapView.region.span
                // Put the pin in the middle of the strip between the top bar and the sheet.
                let targetY = (topInset + (height - bottomInset)) / 2
                let degreesPerPoint = span.latitudeDelta / height
                let center = CLLocationCoordinate2D(
                    latitude: coordinate.latitude - (height / 2 - targetY) * degreesPerPoint,
                    longitude: coordinate.longitude
                )
                mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)

            case let .showUser(user, nearest):
                guard let nearest else {
                    mapView.setRegion(MKCoordinateRegion(center: user, latitudinalMeters: 4000, longitudinalMeters: 4000),
                                      animated: true)
                    return
                }
                let points = [MKMapPoint(user), MKMapPoint(nearest)]
                let rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0))) }
                let minSide = MKMapPointsPerMeterAtLatitude(user.latitude) * 1500
                let padded = rect.insetBy(dx: -max(0, (minSide - rect.width) / 2), dy: -max(0, (minSide - rect.height) / 2))
                mapView.setVisibleMapRect(padded,
                                          edgePadding: UIEdgeInsets(top: topInset + 60, left: 60, bottom: 140, right: 60),
                                          animated: true)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                return nil
            case is MKClusterAnnotation:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation)
            default:
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                zoom(into: cluster, on: mapView)
            } else if let annotation = view.annotation as? PharmacyAnnotation {
                parent?.onSelect(annotation.pharmacy)
            } else if let annotation = view.annotation {
                mapView.deselectAnnotation(annotation, animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PharmacyAnnotation,
                  parent?.selected?.id == annotation.pharmacy.id else { return }
            parent?.onSelect(nil)
        }

        private func zoom(into cluster: MKClusterAnnotation, on mapView: MKMapView) {
            let rect = cluster.memberAnnotations.reduce(MKMapRect.null) {
                $0.union(MKMapRect(origin: MKMapPoint($1.coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            let minSide = MKMapPointsPerMeterAtLatitude(cluster.coordinate.latitude) * 300
            if rect.width < minSide && rect.height < minSide {
                // Members share (almost) one spot: zoom right in instead of looping on the same cluster.
                let region = MKCoordinateRegion(center: cluster.coordinate, latitudinalMeters: 250, longitudinalMeters: 250)
                mapView.setRegion(region, animated: true)
            } else {
                let topInset = parent?.topInset ?? 0
                mapView.setVisibleMapRect(rect,
                                          edgePadding: UIEdgeInsets(top: topInset + 50, left: 50, bottom: 80, right: 50),
                                          animated: true)
            }
        }
    }
}
