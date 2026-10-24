//
//  MarkerFlight.swift
//  CyprusPharmacies
//

import MapKit
import UIKit

/// The markers as the user sees them on the map: where each pharmacy is drawn (its own pin, or the cluster badge it is in).
@MainActor
private struct Seen {
    var points: [ObjectIdentifier: CGPoint] = [:]
    var pins: [ObjectIdentifier: PharmacyAnnotationView] = [:]
    var annotations: [ObjectIdentifier: PharmacyAnnotation] = [:]
    var clusters: [(view: ClusterAnnotationView, members: Set<ObjectIdentifier>, point: CGPoint)] = []

    init(_ mapView: MKMapView) {
        for annotation in mapView.annotations {
            if let cluster = annotation as? MKClusterAnnotation {
                guard let view = mapView.view(for: cluster) as? ClusterAnnotationView else { continue }
                let point = Self.point(of: view, in: mapView)
                let members = Set(cluster.memberAnnotations.map { ObjectIdentifier($0) })
                clusters.append((view, members, point))
                members.forEach { points[$0] = point }
                for case let member as PharmacyAnnotation in cluster.memberAnnotations {
                    annotations[ObjectIdentifier(member)] = member
                }
            } else if let pharmacy = annotation as? PharmacyAnnotation {
                let id = ObjectIdentifier(pharmacy)
                annotations[id] = pharmacy
                if let view = mapView.view(for: pharmacy) as? PharmacyAnnotationView {
                    pins[id] = view
                    points[id] = Self.point(of: view, in: mapView)
                }
            }
        }
    }

    private static func point(of view: UIView, in mapView: MKMapView) -> CGPoint {
        (view.superview ?? mapView).convert(view.center, to: mapView)
    }
}

/// A day's change of pins as one flight that ends in what MapKit really draws. The pins take their new coordinates at once
/// and MapKit regroups them; the flight is only a picture laid over that: a pin that ends as a pin flies there (from its old
/// pin or from the cluster it was in), a pin that ends in a cluster flies into the badge, which shows up as the pin lands,
/// and a cluster that falls apart lets its pins fly out. When it is over, nothing is left to differ from the map.
@MainActor
final class MarkerFlight {
    private static let duration: TimeInterval = 0.7
    /// MapKit regroups within a turn or two of the run loop; this is the time given to it before the pictures are read.
    private static let settle: TimeInterval = 0.12
    private static var nudgeSign = 1.0

    private weak var mapView: MKMapView?
    private let before: Seen
    private let overlay = UIView()
    private var pinGhosts: [ObjectIdentifier: UIView] = [:]
    private var clusterGhosts: [(view: UIView, members: Set<ObjectIdentifier>)] = []
    private var arriving: Set<ObjectIdentifier> = []
    private var hasStarted = false
    private var showsClusters = false
    private var isFinished = false
    /// When this flight moved the map itself; the map's region change that follows is not the user's.
    private(set) var nudgedAt: CFTimeInterval = 0
    var onEnd: (() -> Void)?

    /// Takes the picture of the markers now, before the pins change, and puts it over them.
    init(on mapView: MKMapView) {
        self.mapView = mapView
        before = Seen(mapView)
        overlay.frame = mapView.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        mapView.addSubview(overlay)
        for (id, view) in before.pins {
            guard let point = before.points[id], let ghost = addGhost(of: view, at: point) else { continue }
            pinGhosts[id] = ghost
            view.isHidden = true
        }
        for cluster in before.clusters {
            guard let ghost = addGhost(of: cluster.view, at: cluster.point) else { continue }
            clusterGhosts.append((ghost, cluster.members))
            cluster.view.isHidden = true
        }
    }

    private func addGhost(of view: UIView, at point: CGPoint) -> UIView? {
        // A copy of the view, not a snapshot of it: a snapshot of the glass markers never ends.
        let ghost: UIView
        if view is PharmacyAnnotationView {
            ghost = PharmacyAnnotationView(annotation: nil, reuseIdentifier: nil)
        } else if let cluster = view as? ClusterAnnotationView {
            let copy = ClusterAnnotationView(annotation: cluster.annotation, reuseIdentifier: nil)
            copy.prepareForDisplay()
            ghost = copy
        } else {
            return nil
        }
        ghost.bounds = view.bounds
        ghost.center = point
        overlay.addSubview(ghost)
        return ghost
    }

    /// A pin the next day has no place for shrinks into its tip where it was.
    func shrink(_ annotation: PharmacyAnnotation) {
        guard let ghost = pinGhosts.removeValue(forKey: ObjectIdentifier(annotation)) else { return }
        let scale: CGFloat = 0.3
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            ghost.alpha = 0
            ghost.transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: ghost.bounds.height * (1 - scale) / 2)
        } completion: { _ in ghost.removeFromSuperview() }
    }

    /// Called once the pins have their new coordinates and the new ones are added to the map.
    func fly(arriving: Set<ObjectIdentifier>) {
        self.arriving = arriving
        DispatchQueue.main.async { [self] in
            guard !isFinished, let mapView else { return }
            // MapKit regroups the pins only when the map's region changes, not when a pin's coordinate does.
            nudgedAt = CACurrentMediaTime()
            Self.nudgeSign = -Self.nudgeSign
            let center = mapView.centerCoordinate
            mapView.setCenter(CLLocationCoordinate2D(latitude: center.latitude + Self.nudgeSign * 1e-6, longitude: center.longitude),
                              animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [self] in start() }
        }
    }

    /// What MapKit makes while the flight is on stays out of sight until it has its turn.
    func didAdd(_ views: [MKAnnotationView]) {
        guard !isFinished else { return }
        for view in views {
            if view is ClusterAnnotationView {
                if !showsClusters { view.isHidden = true }
            } else if view is PharmacyAnnotationView, !hasStarted {
                view.isHidden = true
            }
        }
    }

    private func start() {
        guard !isFinished, let mapView else { return }
        hasStarted = true
        let after = Seen(mapView)
        let duration = Self.duration

        for (id, view) in after.pins {
            view.isHidden = false
            let new = after.points[id] ?? .zero
            pinGhosts.removeValue(forKey: id)?.removeFromSuperview()
            if let old = before.points[id] {
                // Either it was a pin before, or inside a cluster that has fallen apart.
                view.fly(from: CGPoint(x: old.x - new.x, y: old.y - new.y), duration: duration)
            } else if arriving.contains(id) {
                view.appear()
            }
        }
        for cluster in after.clusters { cluster.view.isHidden = true }

        // The pins that end up inside a badge fly into it and fade as it comes.
        for (id, ghost) in pinGhosts {
            let target = after.points[id] ?? after.annotations[id].map { mapView.convert($0.coordinate, toPointTo: mapView) }
                ?? before.annotations[id].map { mapView.convert($0.coordinate, toPointTo: mapView) }
            glide(ghost, to: target)
        }
        pinGhosts.removeAll()

        // An old badge follows the new one that has most of its pins, or is gone.
        for (ghost, members) in clusterGhosts {
            let heir = after.clusters.max { $0.members.intersection(members).count < $1.members.intersection(members).count }
            if let heir, !heir.members.isDisjoint(with: members) {
                glide(ghost, to: heir.point)
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) { ghost.alpha = 0 }
            }
        }
        clusterGhosts.removeAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.75) { [self] in revealClusters() }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [self] in finish(cancelled: false) }
    }

    private func glide(_ ghost: UIView, to target: CGPoint?) {
        let duration = Self.duration
        if let target {
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut]) { ghost.center = target }
        }
        UIView.animate(withDuration: duration * 0.2, delay: duration * 0.8, options: .curveLinear) { ghost.alpha = 0 }
    }

    private func revealClusters() {
        guard !isFinished, let mapView else { return }
        showsClusters = true
        for case let view as ClusterAnnotationView in Self.markers(in: mapView) where view.isHidden {
            view.alpha = 0
            view.isHidden = false
            UIView.animate(withDuration: Self.duration * 0.25, delay: 0, options: .curveEaseOut) { view.alpha = 1 }
        }
    }

    /// Ends the flight, at once if it is cut short: the markers are as MapKit has them.
    func finish(cancelled: Bool) {
        guard !isFinished else { return }
        isFinished = true
        overlay.removeFromSuperview()
        if let mapView {
            for view in Self.markers(in: mapView) {
                view.isHidden = false
                if cancelled {
                    view.layer.removeAllAnimations()
                    view.alpha = 1
                    (view as? PharmacyAnnotationView)?.land()
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
