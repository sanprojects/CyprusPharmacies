//
//  HeadingCone.swift
//  CyprusPharmacies
//

import CoreLocation
import UIKit

/// The beam of light in front of the user's dot, as in Apple Maps: points where the phone's top edge points.
final class HeadingConeView: UIView {
    private static let radius: CGFloat = 48
    private static let spread: CGFloat = .pi / 3

    /// Where the phone points, in degrees clockwise from north; nil hides the cone.
    var heading: CLLocationDirection? { didSet { update() } }
    /// How far the map is turned from north, in degrees.
    var mapHeading: CLLocationDirection = 0 { didSet { update() } }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 2 * Self.radius, height: 2 * Self.radius))
        backgroundColor = .clear
        isUserInteractionEnabled = false
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let wedge = UIBezierPath()
        wedge.move(to: center)
        wedge.addArc(withCenter: center, radius: Self.radius,
                     startAngle: -.pi / 2 - Self.spread / 2, endAngle: -.pi / 2 + Self.spread / 2, clockwise: true)
        wedge.close()
        context.addPath(wedge.cgPath)
        context.clip()
        let colors = [tintColor.withAlphaComponent(0.55).cgColor, tintColor.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 6, endCenter: center, endRadius: Self.radius, options: [])
    }

    private func update() {
        let visible = heading != nil
        if let heading {
            transform = CGAffineTransform(rotationAngle: CGFloat((heading - mapHeading) * .pi / 180))
        }
        guard (alpha > 0) != visible else { return }
        UIView.animate(withDuration: 0.25) { self.alpha = visible ? 1 : 0 }
    }
}

/// Compass heading while the map shows the user's location.
final class HeadingTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: ((CLLocationDirection?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    /// No compass (a simulator, an old device) simply gives no heading.
    func setRunning(_ running: Bool) {
        guard CLLocationManager.headingAvailable() else { return }
        if running {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
            onChange?(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the compass is not calibrated: no reliable direction.
        guard newHeading.headingAccuracy >= 0 else { return onChange?(nil) ?? () }
        onChange?(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
    }
}
