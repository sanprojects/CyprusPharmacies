//
//  PharmacyMapView.swift
//  CyprusPharmacies
//

import MapKit
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// Watches the taps on the map without taking part: it never recognizes, so it cannot hold up or cancel any gesture of
/// MapKit (the double-tap zoom among them), and it reports a tap at lift-off, without MapKit's wait for a second tap.
final class TapObserver: UIGestureRecognizer {
    var onTouchDown: (() -> Void)?
    var onTap: ((CGPoint) -> Void)?
    private var start: (point: CGPoint, time: TimeInterval)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // A second finger is a pinch or a two-finger tap, not a tap.
        guard event.allTouches?.count == 1, let touch = touches.first else { start = nil; return }
        start = (touch.location(in: view), touch.timestamp)
        onTouchDown?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let point = touches.first?.location(in: view) else { return }
        if hypot(point.x - start.point.x, point.y - start.point.y) > 10 { self.start = nil }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        defer { start = nil; state = .failed }
        guard let start, let touch = touches.first, touch.timestamp - start.time < 0.5 else { return }
        onTap?(start.point)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        start = nil
        state = .failed
    }

    override func reset() { start = nil }
}

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
    /// The user started to pan, pinch or double-tap the map.
    let onUserMove: () -> Void

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
        // MapKit says nothing about who moved the map; these watch the user's gestures alongside its own.
        for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] {
            recognizer.addTarget(context.coordinator, action: #selector(Coordinator.userGesture(_:)))
            recognizer.delegate = context.coordinator
            recognizer.cancelsTouchesInView = false
            mapView.addGestureRecognizer(recognizer)
        }
        // MapKit acts on a tap (selects a marker, drops the selection) only once the double-tap window (about 0.3 s) has
        // passed. This sees the tap at lift-off and acts at once.
        let taps = TapObserver()
        taps.onTouchDown = { [weak mapView, weak coordinator = context.coordinator] in
            coordinator?.touchedDown(on: mapView)
        }
        taps.onTap = { [weak mapView, weak coordinator = context.coordinator] point in
            if let mapView { coordinator?.tapped(at: point, on: mapView) }
        }
        taps.cancelsTouchesInView = false
        taps.delegate = context.coordinator
        mapView.addGestureRecognizer(taps)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        mapView.showsUserLocation = showsUserLocation
        coordinator.heading.setRunning(showsUserLocation)
        coordinator.sync(pharmacies, on: mapView)
        coordinator.syncSelection(selected, on: mapView)
        if let command, command.id != coordinator.appliedCommand {
            coordinator.appliedCommand = command.id
            // Wait for the first layout so bounds are known.
            DispatchQueue.main.async { coordinator.apply(command.kind, on: mapView) }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        /// About 3 km top to bottom: close enough for single pins, not clusters.
        static let streetSpan: CLLocationDegrees = 0.03
        /// About 17 km top to bottom: a town and its suburbs.
        static let citySpan: CLLocationDegrees = 0.15

        var parent: PharmacyMapView?
        var appliedCommand: UUID?
        let heading = HeadingTracker()
        private let cone = HeadingConeView()
        private var shownIDs: [String] = []
        private var annotations: [String: PharmacyAnnotation] = [:]

        func sync(_ pharmacies: [Pharmacy], on mapView: MKMapView) {
            let ids = pharmacies.map(\.id)
            guard ids != shownIDs else { return }
            shownIDs = ids
            // Keep annotations of pharmacies still on the map: replacing all of them breaks MapKit clustering.
            let wanted = Dictionary(pharmacies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let gone = annotations.filter { wanted[$0.key] != $0.value.pharmacy }
            gone.keys.forEach { annotations[$0] = nil }
            mapView.removeAnnotations(Array(gone.values))

            let added = wanted.values.filter { annotations[$0.id] == nil }.map { pharmacy -> PharmacyAnnotation in
                let annotation = PharmacyAnnotation(pharmacy)
                annotations[pharmacy.id] = annotation
                return annotation
            }
            mapView.addAnnotations(added)
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

            case let .focus(coordinate, bottomInset, zoomIn):
                let height = mapView.bounds.height
                guard height > 0 else { return }
                var span = mapView.region.span
                if zoomIn && span.latitudeDelta > Self.streetSpan {
                    span = MKCoordinateSpan(latitudeDelta: Self.streetSpan,
                                            longitudeDelta: span.longitudeDelta * Self.streetSpan / span.latitudeDelta)
                }
                // Put the pin in the middle of the strip between the top bar and the sheet.
                let targetY = (topInset + (height - bottomInset)) / 2
                let degreesPerPoint = span.latitudeDelta / height
                let center = CLLocationCoordinate2D(
                    latitude: coordinate.latitude - (height / 2 - targetY) * degreesPerPoint,
                    longitude: coordinate.longitude
                )
                mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)

            case let .showCity(center):
                let span = MKCoordinateSpan(latitudeDelta: Self.citySpan, longitudeDelta: Self.citySpan)
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

        private var quickTapAt = Date.distantPast
        private var quickTapSelected = false
        private var lastTap: (time: Date, point: CGPoint)?
        private var regionAtTouchDown: MKCoordinateRegion?

        func touchedDown(on mapView: MKMapView?) { regionAtTouchDown = mapView?.region }

        /// A tap on a marker selects it at lift-off (MapKit's own, late selection of it is then ignored); a tap on the bare
        /// map takes the selection off at once.
        func tapped(at point: CGPoint, on mapView: MKMapView) {
            let now = Date()
            let isSecondTap = lastTap.map { now.timeIntervalSince($0.time) < 0.4 && hypot(point.x - $0.point.x, point.y - $0.point.y) < 40 } ?? false
            lastTap = isSecondTap ? nil : (now, point)

            var hit = mapView.hitTest(point, with: nil)
            while let view = hit, !(view is MKAnnotationView) { hit = view.superview }
            guard let annotationView = hit as? MKAnnotationView, let annotation = annotationView.annotation else {
                mapView.selectedAnnotations.forEach { mapView.deselectAnnotation($0, animated: true) }
                if isSecondTap { zoomInIfMapKitDidNot(at: point, on: mapView) }
                return
            }
            guard !(annotation is MKUserLocation) else { return }
            quickTapAt = now
            quickTapSelected = false
            mapView.selectAnnotation(annotation, animated: true)
        }

        /// MapKit zooms in on a double tap by itself, as the finger lifts. If the map has not moved a moment later, it does not
        /// (a gesture of ours or the system's is in the way), and the zoom is done here: half the span, the point under the
        /// finger staying under it.
        private func zoomInIfMapKitDidNot(at point: CGPoint, on mapView: MKMapView) {
            guard let before = regionAtTouchDown else { return }
            let under = mapView.convert(point, toCoordinateFrom: mapView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak mapView] in
                guard let mapView else { return }
                let now = mapView.region
                let tolerance = before.span.latitudeDelta * 0.001
                guard abs(now.span.latitudeDelta - before.span.latitudeDelta) < tolerance,
                      abs(now.center.latitude - before.center.latitude) < tolerance else { return }
                let center = CLLocationCoordinate2D(
                    latitude: under.latitude + (before.center.latitude - under.latitude) / 2,
                    longitude: under.longitude + (before.center.longitude - under.longitude) / 2)
                let span = MKCoordinateSpan(latitudeDelta: before.span.latitudeDelta / 2,
                                            longitudeDelta: before.span.longitudeDelta / 2)
                mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
            }
        }

        @objc func userGesture(_ recognizer: UIGestureRecognizer) {
            if recognizer.state == .began { parent?.onUserMove() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        override init() {
            super.init()
            heading.onChange = { [weak cone] in cone?.heading = $0 }
        }

        // MARK: MKMapViewDelegate

        /// The cone sits under the system's dot, which is why it is a subview of it, not a view of its own.
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            guard let dot = views.first(where: { $0.annotation is MKUserLocation }) else { return }
            // The system's dot is not drawn in the middle of its view.
            var isSystemDot = true
            if #available(iOS 26, *) { isSystemDot = !(dot is UserLocationView) }
            cone.center = CGPoint(x: dot.bounds.midX - (isSystemDot ? 4 : 0), y: dot.bounds.midY + (isSystemDot ? 13 : 0))
            cone.mapHeading = mapView.camera.heading
            dot.insertSubview(cone, at: 0)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            cone.mapHeading = mapView.camera.heading
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                if #available(iOS 26, *) { return UserLocationView(annotation: annotation, reuseIdentifier: nil) }
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
            if Date().timeIntervalSince(quickTapAt) < 0.7 {
                if quickTapSelected {
                    if let annotation = view.annotation as? MKClusterAnnotation { mapView.deselectAnnotation(annotation, animated: false) }
                    return
                }
                quickTapSelected = true
            }
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                UISelectionFeedbackGenerator().selectionChanged()
                zoom(into: cluster, on: mapView)
            } else if let annotation = view.annotation as? PharmacyAnnotation {
                // A selection made in `syncSelection` comes back here too: reporting it again would drop the list's zoom-in.
                guard parent?.selected?.id != annotation.pharmacy.id else { return }
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
