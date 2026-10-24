//
//  MarkerFlight.swift
//  CyprusPharmacies
//

import MapKit
import UIKit

private struct AnnotationKey: Hashable {
    let id: ObjectIdentifier
    var members = 0
}

/// The markers as the user sees them on the map: each pin and each cluster badge with where it is drawn.
@MainActor
private struct Seen {
    var pins: [(view: PharmacyAnnotationView, point: CGPoint)] = []
    var clusters: [(view: ClusterAnnotationView, point: CGPoint)] = []
    /// Which pins and badges there are, and how many pins each badge holds; the same while MapKit has done regrouping.
    var signature = Set<AnnotationKey>()

    init(_ mapView: MKMapView) {
        // The members of a badge are on the map too, and MapKit may still hold a view for them; it is not on the screen.
        let clustered = Set(mapView.annotations.compactMap { ($0 as? MKClusterAnnotation)?.memberAnnotations }.joined().map(ObjectIdentifier.init))
        for annotation in mapView.annotations where !clustered.contains(ObjectIdentifier(annotation)) {
            if let view = mapView.view(for: annotation) as? PharmacyAnnotationView, view.isOnMap {
                pins.append((view, Self.point(of: view, in: mapView)))
                signature.insert(AnnotationKey(id: ObjectIdentifier(annotation)))
            } else if let view = mapView.view(for: annotation) as? ClusterAnnotationView, view.isOnMap {
                clusters.append((view, Self.point(of: view, in: mapView)))
                signature.insert(AnnotationKey(id: ObjectIdentifier(annotation), members: (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0))
            }
        }
    }

    private static func point(of view: UIView, in mapView: MKMapView) -> CGPoint {
        (view.superview ?? mapView).convert(view.center, to: mapView)
    }
}

/// A day's change of markers as one flight between two pictures: what the map showed and what MapKit makes of the new pins.
/// Pins fly to pins and badges to badges, each old one to the nearest new one; a new marker with no old one left to take
/// its place is simply there, and an old one with no new one left is simply gone. The pins take their new coordinates at once
/// and MapKit regroups them; the flight is only a picture laid over that, and when it is over nothing differs from the map.
@MainActor
final class MarkerFlight {
    private static let duration: TimeInterval = 0.7
    /// MapKit regroups within a turn or two of the run loop; this is the time given to it before the pictures are read.
    private static let settle: TimeInterval = 0.12
    /// The regrouping is over when the pins and badges have stayed the same this long (MapKit settles in about half a second),
    /// but it is not waited for longer than the cap.
    private static let quiet: TimeInterval = 0.6
    private static let cap: TimeInterval = 1.5
    private static var nudgeSign = 1.0

    private weak var mapView: MKMapView?
    private let overlay = UIView()
    private var pinGhosts: [(view: UIView, point: CGPoint)] = []
    private var clusterGhosts: [(view: UIView, point: CGPoint)] = []
    private var hasStarted = false
    private var isFinished = false
    /// When this flight moved the map itself; the map's region change that follows is not the user's.
    private(set) var nudgedAt: CFTimeInterval = 0
    var onEnd: (() -> Void)?

    /// Takes the picture of the markers now, before the pins change, and puts it over them.
    init(on mapView: MKMapView) {
        self.mapView = mapView
        let before = Seen(mapView)
        overlay.frame = mapView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        mapView.addSubview(overlay)
        for (view, point) in before.pins {
            pinGhosts.append((addGhost(of: view, at: point), point))
            view.isHeld = true
        }
        for (view, point) in before.clusters {
            clusterGhosts.append((addGhost(of: view, at: point), point))
            view.isHeld = true
        }
    }

    private func addGhost(of view: UIView, at point: CGPoint) -> UIView {
        // A copy of the view, not a snapshot of it: a snapshot of the glass markers never ends.
        let ghost: UIView
        if let cluster = view as? ClusterAnnotationView {
            let copy = ClusterAnnotationView(annotation: cluster.annotation, reuseIdentifier: nil)
            copy.prepareForDisplay()
            ghost = copy
        } else {
            ghost = PharmacyAnnotationView(annotation: nil, reuseIdentifier: nil)
        }
        ghost.bounds = view.bounds
        ghost.center = point
        overlay.addSubview(ghost)
        return ghost
    }

    /// Called once the pins have their new coordinates and the new ones are added to the map.
    func fly() {
        DispatchQueue.main.async { [self] in
            guard !isFinished, let mapView else { return }
            // MapKit regroups the pins only when the map's region changes, not when a pin's coordinate does.
            nudgedAt = CACurrentMediaTime()
            Self.nudgeSign = -Self.nudgeSign
            let center = mapView.centerCoordinate
            mapView.setCenter(CLLocationCoordinate2D(latitude: center.latitude + Self.nudgeSign * 1e-6, longitude: center.longitude),
                              animated: false)
            waitForRegroup(since: CACurrentMediaTime(), changedAt: CACurrentMediaTime(), last: Seen(mapView).signature)
        }
    }

    /// Looks at the map every few milliseconds until MapKit is done regrouping; what it makes on the way is not the new picture.
    private func waitForRegroup(since began: CFTimeInterval, changedAt: CFTimeInterval, last: Set<AnnotationKey>) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [self] in
            guard !isFinished, let mapView else { return }
            let now = CACurrentMediaTime()
            let current = Seen(mapView).signature
            let changed = current == last ? changedAt : now
            if (now - began >= Self.settle && now - changed >= Self.quiet) || now - began >= Self.cap {
                start()
            } else {
                waitForRegroup(since: began, changedAt: changed, last: current)
            }
        }
    }

    /// What MapKit makes while the flight is on stays out of sight until it has its turn.
    func didAdd(_ views: [MKAnnotationView]) {
        guard !isFinished, !hasStarted else { return }
        for case let view as MarkerView in views { view.isHeld = true }
    }

    private func start() {
        guard !isFinished, let mapView else { return }
        hasStarted = true
        let after = Seen(mapView)
        let duration = Self.duration

        for (old, new) in Self.match(pinGhosts.map(\.point), after.pins.map(\.point)) {
            after.pins[new].view.fly(from: Self.offset(from: pinGhosts[old].point, to: after.pins[new].point), duration: duration)
        }
        for (old, new) in Self.match(clusterGhosts.map(\.point), after.clusters.map(\.point)) {
            after.clusters[new].view.fly(from: Self.offset(from: clusterGhosts[old].point, to: after.clusters[new].point), duration: duration)
        }
        // The pictures are gone, the real markers take their place; the ones that have a pair start from the old place.
        pinGhosts.forEach { $0.view.removeFromSuperview() }
        clusterGhosts.forEach { $0.view.removeFromSuperview() }
        pinGhosts.removeAll()
        clusterGhosts.removeAll()
        after.pins.forEach { $0.view.isHeld = false }
        after.clusters.forEach { $0.view.isHeld = false }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [self] in finish(cancelled: false) }
    }

    private static func offset(from old: CGPoint, to new: CGPoint) -> CGPoint {
        CGPoint(x: old.x - new.x, y: old.y - new.y)
    }

    /// Pairs of the old and the new points, the nearest first; the rest of the longer side is left without a pair.
    private static func match(_ old: [CGPoint], _ new: [CGPoint]) -> [(old: Int, new: Int)] {
        var candidates: [(distance: CGFloat, old: Int, new: Int)] = []
        candidates.reserveCapacity(old.count * new.count)
        for (i, from) in old.enumerated() {
            for (j, to) in new.enumerated() { candidates.append((hypot(from.x - to.x, from.y - to.y), i, j)) }
        }
        candidates.sort { $0.distance < $1.distance }
        var usedOld = Set<Int>(), usedNew = Set<Int>()
        var pairs: [(old: Int, new: Int)] = []
        for candidate in candidates where !usedOld.contains(candidate.old) && !usedNew.contains(candidate.new) {
            usedOld.insert(candidate.old)
            usedNew.insert(candidate.new)
            pairs.append((candidate.old, candidate.new))
            if pairs.count == min(old.count, new.count) { break }
        }
        return pairs
    }

    /// Ends the flight, at once if it is cut short: the markers are as MapKit has them.
    func finish(cancelled: Bool) {
        guard !isFinished else { return }
        isFinished = true
        overlay.removeFromSuperview()
        if let mapView {
            for view in Self.markers(in: mapView) {
                (view as? MarkerView)?.isHeld = false
                if cancelled {
                    view.layer.removeAllAnimations()
                    view.alpha = 1
                    (view as? PharmacyAnnotationView)?.land()
                    (view as? ClusterAnnotationView)?.land()
                }
            }
        }
        onEnd?()
    }

    private static func markers(in view: UIView) -> [UIView] {
        view.subviews.flatMap { subview -> [UIView] in
            (subview is PharmacyAnnotationView || subview is ClusterAnnotationView) ? [subview] : markers(in: subview)
        }
    }
}
