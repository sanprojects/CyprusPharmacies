//
//  HeadingCone.swift
//  CyprusPharmacies
//

import CoreLocation
import SwiftUI
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

/// Compass heading of one consumer: the map's cone while it shows the user's location.
final class HeadingTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var isRunning = false
    var onChange: ((CLLocationDirection?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    /// No compass (a simulator, an old device) simply gives no heading.
    func setRunning(_ running: Bool) {
        guard running != isRunning, CLLocationManager.headingAvailable() else { return }
        isRunning = running
        if running {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
            onChange?(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the compass is not calibrated: no reliable direction.
        guard newHeading.headingAccuracy >= 0 else {
            onChange?(nil)
            return
        }
        onChange?(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
    }
}

/// One compass for all the arrows on screen: a list of cards must not run a heading manager per card.
@MainActor @Observable
final class HeadingSource {
    static let shared = HeadingSource()

    private(set) var heading: CLLocationDirection?
    private var users = 0
    private let tracker = HeadingTracker()

    private init() {
        tracker.onChange = { [weak self] in self?.heading = $0 }
    }

    /// The compass runs while at least one arrow is on screen.
    func use() {
        users += 1
        tracker.setRunning(true)
    }

    func release() {
        users -= 1
        if users == 0 { tracker.setRunning(false) }
    }
}

/// The location arrow of the map's own button, turned toward the pharmacy: with the compass it follows where the phone
/// points, without it the arrow shows the direction on a north-up map.
struct BearingIcon: View {
    /// Direction to the pharmacy, degrees clockwise from north.
    let bearing: CLLocationDirection

    /// Unwrapped, so a turn through north takes the short way round instead of spinning.
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "location.north.fill")
            .rotationEffect(.degrees(angle))
            .onAppear {
                HeadingSource.shared.use()
                angle = target
            }
            .onDisappear { HeadingSource.shared.release() }
            .onChange(of: target) { _, new in
                let delta = (new - angle + 540).truncatingRemainder(dividingBy: 360) - 180
                withAnimation(.smooth) { angle += delta }
            }
    }

    private var target: Double { bearing - (HeadingSource.shared.heading ?? 0) }
}
