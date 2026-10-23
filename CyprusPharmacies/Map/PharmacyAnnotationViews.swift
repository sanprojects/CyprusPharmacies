//
//  PharmacyAnnotationViews.swift
//  CyprusPharmacies
//

import MapKit
import UIKit

final class PharmacyAnnotation: NSObject, MKAnnotation {
    let pharmacy: Pharmacy
    let coordinate: CLLocationCoordinate2D
    var title: String? { pharmacy.name }

    init(_ pharmacy: Pharmacy) {
        self.pharmacy = pharmacy
        self.coordinate = pharmacy.coordinate
    }
}

enum MapStyle {
    static let clusteringIdentifier = "pharmacyCluster"
    static let green = UIColor(named: "greenPharm") ?? .systemGreen
    /// The light green of the app icon and of the first pins, a shade darker, which the markers are filled with.
    static let lightGreen = UIColor(red: 0.37, green: 0.75, blue: 0.43, alpha: 1)

    /// Marker gradient, top to bottom: light green, or the darker pharmacy green under Increase Contrast.
    static func markerColors(highContrast: Bool) -> [UIColor] {
        highContrast
            ? [UIColor(red: 0.10, green: 0.62, blue: 0.42, alpha: 1),
               green.resolvedColor(with: UITraitCollection(accessibilityContrast: .high))]
            : [UIColor(red: 0.50, green: 0.83, blue: 0.55, alpha: 1), lightGreen]
    }
}

/// Markers drawn in code, so they are sharp at every size, in the shape of the system marker: a round head in a white
/// rim with a short pointed tail, a small dot on the coordinate under the tip, and a soft shadow behind.
enum MarkerArt {
    /// A pin: `tipOffset` is where the coordinate (the dot) sits below the image center; `head` and `tail` (its tip)
    /// are where a glass marker goes: halfway into the rim, which is laid over the glass and hides its edges.
    struct Pin {
        let image: UIImage
        let tipOffset: CGFloat
        let head: CGRect
        let tail: CGPoint
    }

    /// Rim width for a marker `side` wide.
    static func rim(side: CGFloat) -> CGFloat { side * 0.08 }

    /// With `glass`, only the shadow, the rim and the dot are drawn, the inside left clear for the glass.
    static func pin(diameter: CGFloat, highContrast: Bool, glass: Bool) -> Pin {
        let scale = diameter / 30
        let radius = diameter / 2
        let pad = 4 * scale
        let rim = rim(side: diameter)
        let dotRadius = 2.6 * scale
        let center = CGPoint(x: radius + pad, y: pad + radius)
        let tip = CGPoint(x: center.x, y: center.y + radius * 1.42)
        let dot = CGPoint(x: center.x, y: tip.y + 2.5 * scale + dotRadius)
        let size = CGSize(width: diameter + 2 * pad, height: dot.y + dotRadius + pad)
        // The tail leaves the head where the lines from the tip touch it.
        let spread = acos(radius / (tip.y - center.y))
        let drop = UIBezierPath(arcCenter: center, radius: radius,
                                startAngle: .pi / 2 + spread, endAngle: .pi / 2 - spread, clockwise: true)
        drop.addLine(to: tip)
        drop.close()
        let head = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
        let colors = MapStyle.markerColors(highContrast: highContrast)
        let glassTip = tip.y - rim / 2.squareRoot()

        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            drawBody(drop, rim: rim, in: cg, scale: scale)
            if glass {
                clearInside(drop, rim: rim, in: cg)
                // The glass's rounded corner stops short of the sharp inner tip: the rim is a little thicker there.
                cg.saveGState()
                drop.addClip()
                UIColor.white.setFill()
                cg.fill(CGRect(x: 0, y: glassTip - 1.6 * rim, width: size.width, height: size.height))
                cg.restoreGState()
            } else {
                drawFill(drop, rim: rim, head: head, colors: colors, in: cg)
                drawCross(at: center, radius: radius - rim)
            }
            let spot = UIBezierPath(ovalIn: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius,
                                                   width: 2 * dotRadius, height: 2 * dotRadius))
            drawBody(spot, rim: 0, in: cg, scale: scale * 0.6)
            colors[1].setFill()
            UIBezierPath(ovalIn: spot.bounds.insetBy(dx: scale, dy: scale)).fill()
        }
        // Along the tail's sides, about 45° off the vertical, half the rim is rim / √2 up from the tip.
        return Pin(image: image, tipOffset: dot.y - size.height / 2, head: head.insetBy(dx: rim / 2, dy: rim / 2),
                   tail: CGPoint(x: tip.x, y: glassTip))
    }

    /// A round badge `side` wide in a white rim, with room for its shadow; the count is drawn by the caller in `badge`,
    /// and with `glass` the inside is left clear.
    static func badge(side: CGFloat, highContrast: Bool, glass: Bool, draw content: (CGRect) -> Void = { _ in }) -> UIImage {
        let pad = padding(side: side)
        let size = CGSize(width: side + 2 * pad, height: side + 2 * pad)
        let circle = UIBezierPath(ovalIn: CGRect(x: pad, y: pad, width: side, height: side))
        let rim = rim(side: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            drawBody(circle, rim: rim, in: context.cgContext, scale: side / 30)
            if glass {
                clearInside(circle, rim: rim, in: context.cgContext)
            } else {
                drawFill(circle, rim: rim, head: circle.bounds, colors: MapStyle.markerColors(highContrast: highContrast),
                         in: context.cgContext)
                content(circle.bounds)
            }
        }
    }

    /// A transparent image: it gives a glass marker its frame, as the drawn one would.
    static func clear(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in }
    }

    /// Room around a badge `side` wide for its shadow.
    static func padding(side: CGFloat) -> CGFloat { 4 * side / 30 }

    /// The white body under a soft shadow; the rim is what the fill or the glass leaves of it.
    private static func drawBody(_ shape: UIBezierPath, rim: CGFloat, in cg: CGContext, scale: CGFloat) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1.5 * scale), blur: 4 * scale,
                     color: UIColor.black.withAlphaComponent(0.3).cgColor)
        UIColor.white.setFill()
        shape.fill()
        cg.restoreGState()
    }

    /// Clips to the shape minus its rim.
    private static func clipInside(_ shape: UIBezierPath, rim: CGFloat, in cg: CGContext) {
        shape.addClip()
        let band = shape.cgPath.copy(strokingWithWidth: 2 * rim, lineCap: .round, lineJoin: .round, miterLimit: 1)
        cg.addPath(shape.cgPath)
        cg.addPath(band)
        cg.clip(using: .evenOdd)
    }

    /// Erases the inside of the rim, shadow and all, so the map shows through the glass there.
    private static func clearInside(_ shape: UIBezierPath, rim: CGFloat, in cg: CGContext) {
        cg.saveGState()
        clipInside(shape, rim: rim, in: cg)
        cg.setBlendMode(.clear)
        cg.fill(shape.bounds.insetBy(dx: -1, dy: -1))
        cg.restoreGState()
    }

    private static func drawFill(_ shape: UIBezierPath, rim: CGFloat, head: CGRect, colors: [UIColor], in cg: CGContext) {
        cg.saveGState()
        clipInside(shape, rim: rim, in: cg)
        let bounds = shape.bounds
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray,
                                     locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.minY),
                                  end: CGPoint(x: bounds.midX, y: head.maxY), options: [.drawsAfterEndLocation])
        }
        // A soft sheen on the upper half of the head.
        let sheen = UIBezierPath(ovalIn: CGRect(x: head.minX + head.width * 0.18, y: head.minY + head.height * 0.06,
                                                width: head.width * 0.64, height: head.height * 0.42))
        sheen.addClip()
        let shine = [UIColor.white.withAlphaComponent(0.4).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shine, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: head.midX, y: head.minY),
                                  end: CGPoint(x: head.midX, y: head.minY + head.height * 0.48), options: [])
        }
        cg.restoreGState()
    }

    private static func drawCross(at center: CGPoint, radius: CGFloat) {
        let arm = radius * 1.05
        let width = radius * 0.36
        UIColor.white.setFill()
        UIBezierPath(roundedRect: CGRect(x: center.x - arm / 2, y: center.y - width / 2, width: arm, height: width),
                     cornerRadius: width * 0.3).fill()
        UIBezierPath(roundedRect: CGRect(x: center.x - width / 2, y: center.y - arm / 2, width: width, height: arm),
                     cornerRadius: width * 0.3).fill()
    }
}

/// A translucent Liquid Glass marker inside the drawn rim, the map showing through it tinted light green. Glass takes
/// no free outline, so a pin is a round head and a rounded square turned on its corner below it, which the container
/// melts into one drop.
@available(iOS 26, *)
final class GlassMarkerView: UIVisualEffectView {
    /// Content goes into its `contentView`.
    let head = UIVisualEffectView()
    private let tail = UIVisualEffectView()

    init() {
        super.init(effect: UIGlassContainerEffect())
        isUserInteractionEnabled = false
        head.cornerConfiguration = .capsule()
        tail.transform = CGAffineTransform(rotationAngle: .pi / 4)
        contentView.addSubview(tail)
        contentView.addSubview(head)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A pin whose tail ends at `tip`, or a round badge when `tip` is nil.
    func show(head frame: CGRect, tip: CGPoint?, highContrast: Bool) {
        let container = UIGlassContainerEffect()
        container.spacing = frame.width * 0.2
        effect = container
        head.effect = Self.glass(highContrast: highContrast)
        head.frame = frame
        tail.isHidden = tip == nil
        guard let tip else { return }
        let side = frame.width * 0.42
        let corner = side * 0.12
        tail.effect = Self.glass(highContrast: highContrast)
        tail.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        tail.cornerConfiguration = .corners(radius: .fixed(corner))
        // Its lower corner, rounded off, ends on the tip.
        tail.center = CGPoint(x: tip.x, y: tip.y - side / 2.squareRoot() + corner * (2.squareRoot() - 1))
    }

    private static func glass(highContrast: Bool) -> UIGlassEffect {
        let effect = UIGlassEffect()
        effect.tintColor = highContrast
            ? MapStyle.markerColors(highContrast: true)[1].withAlphaComponent(0.85)
            : MapStyle.lightGreen.withAlphaComponent(0.7)
        return effect
    }
}

final class PharmacyAnnotationView: MKAnnotationView {
    private static let diameter: CGFloat = 30
    private static let selectedScale: CGFloat = 1.5
    private static let hasGlass = if #available(iOS 26, *) { true } else { false }
    /// Pins by Increase Contrast, then unselected and selected; the selected one is drawn at its size, so it stays sharp
    /// instead of a stretched bitmap. With glass they are only the rim, the dot and the shadow.
    private static let pins = [false, true].map { highContrast in
        [1, selectedScale].map { MarkerArt.pin(diameter: diameter * $0, highContrast: highContrast, glass: hasGlass) }
    }

    private static let clearPins = pins[0].map { MarkerArt.clear(size: $0.image.size) }

    /// The glass marker on iOS 26+, under the drawn rim, the dot and the shadow, over a clear image of their size.
    private var glass: UIView?
    private let rimView = UIImageView()
    private let cross = UIImageView(image: UIImage(systemName: "cross.fill"))
    private var isShownSelected = false
    private var collisionInsets = UIEdgeInsets.zero

    /// MapKit checks collisions on the frame minus these insets. The selected pin keeps its unselected footprint, so
    /// growing does not pull it into a cluster with a neighbour it stood apart from.
    override var alignmentRectInsets: UIEdgeInsets { collisionInsets }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = MapStyle.clusteringIdentifier
        collisionMode = .circle
        if #available(iOS 26, *) {
            let marker = GlassMarkerView()
            cross.tintColor = .white
            cross.contentMode = .scaleAspectFit
            marker.head.contentView.addSubview(cross)
            addSubview(marker)
            addSubview(rimView)
            glass = marker
        }
        show(selected: false)
        isAccessibilityElement = true
        accessibilityTraits = .button
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (view: Self, _) in
            view.show(selected: view.isShownSelected)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var annotation: MKAnnotation? {
        willSet { clusteringIdentifier = MapStyle.clusteringIdentifier }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        show(selected: false)
        transform = .identity
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = MapStyle.clusteringIdentifier
        accessibilityLabel = annotation?.title ?? "Pharmacy"
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard selected != isShownSelected else { return }
        show(selected: selected)
        layer.removeAllAnimations()
        guard animated else { transform = .identity; return }
        // Swap the image at once, then grow or shrink from the old size, the tip staying on the coordinate.
        let start = pivot(scale: selected ? 1 / Self.selectedScale : Self.selectedScale)
        transform = start
        let options: UIView.AnimationOptions = [.allowUserInteraction, .beginFromCurrentState]
        guard selected && !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(withDuration: 0.2, delay: 0, options: options) { self.transform = .identity }
            return
        }
        // A selected pin overshoots and sways on its tip a few times, fading out, like the system marker.
        let steps: [(time: Double, scale: CGFloat, degrees: CGFloat)] = [
            (0.28, 1.10, -9), (0.22, 0.96, 6), (0.18, 1.03, -3.5), (0.16, 0.99, 1.5), (0.16, 1, 0),
        ]
        var begin = 0.0
        UIView.animateKeyframes(withDuration: 0.7, delay: 0, options: [.calculationModeCubic, .allowUserInteraction]) {
            for step in steps {
                UIView.addKeyframe(withRelativeStartTime: begin, relativeDuration: step.time) {
                    self.transform = self.pivot(scale: step.scale, degrees: step.degrees)
                }
                begin += step.time
            }
        }
    }

    /// Scale and turn about the tip, so it stays on the coordinate.
    private func pivot(scale: CGFloat, degrees: CGFloat = 0) -> CGAffineTransform {
        let tip = -centerOffset.y
        return CGAffineTransform(translationX: 0, y: -tip)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: 0, y: tip))
    }

    private func show(selected: Bool) {
        isShownSelected = selected
        let highContrast = traitCollection.accessibilityContrast == .high
        let pin = Self.pins[highContrast ? 1 : 0][0], selectedPin = Self.pins[highContrast ? 1 : 0][1]
        let art = selected ? selectedPin : pin
        if #available(iOS 26, *), let marker = glass as? GlassMarkerView {
            image = Self.clearPins[selected ? 1 : 0]
            rimView.image = art.image
            rimView.frame = bounds
            marker.frame = bounds
            marker.show(head: art.head, tip: art.tail, highContrast: highContrast)
            cross.frame = marker.head.bounds.insetBy(dx: art.head.width * 0.24, dy: art.head.width * 0.24)
        } else {
            image = art.image
        }
        centerOffset = CGPoint(x: 0, y: -art.tipOffset)
        collisionInsets = selected ? Self.footprint(of: pin, in: selectedPin) : .zero
        displayPriority = .defaultHigh
    }

    /// Insets that cut the `outer` pin's frame down to the `inner` pin's, the tips on one spot.
    private static func footprint(of inner: MarkerArt.Pin, in outer: MarkerArt.Pin) -> UIEdgeInsets {
        let big = outer.image.size, small = inner.image.size
        let side = (big.width - small.width) / 2
        let top = (big.height / 2 + outer.tipOffset) - (small.height / 2 + inner.tipOffset)
        return UIEdgeInsets(top: top, left: side, bottom: big.height - small.height - top, right: side)
    }
}

final class ClusterAnnotationView: MKAnnotationView {
    /// The glass badge on iOS 26+, as on `PharmacyAnnotationView`.
    private var glass: UIView?
    private let countLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        if #available(iOS 26, *) {
            let marker = GlassMarkerView()
            countLabel.textColor = .white
            countLabel.textAlignment = .center
            marker.head.contentView.addSubview(countLabel)
            addSubview(marker)
            glass = marker
        }
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityTraits = .button
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitAccessibilityContrast.self]) { (view: Self, _) in
            view.updateBadge()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        updateBadge()
    }

    private func updateBadge() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        let font = Self.font(traits: traitCollection)
        let side = Self.side(count: count, font: font)
        let highContrast = traitCollection.accessibilityContrast == .high
        if #available(iOS 26, *), let marker = glass as? GlassMarkerView {
            image = MarkerArt.badge(side: side, highContrast: highContrast, glass: true)
            let inset = MarkerArt.padding(side: side) + MarkerArt.rim(side: side)
            marker.frame = bounds
            marker.show(head: bounds.insetBy(dx: inset, dy: inset), tip: nil, highContrast: highContrast)
            countLabel.text = "\(count)"
            countLabel.font = font
            countLabel.frame = marker.head.bounds
        } else {
            image = Self.badge(count: count, font: font, side: side, highContrast: highContrast)
        }
        accessibilityLabel = "\(count) pharmacies, zoom in"
    }

    /// The count follows the text size, up to a point, so large badges do not hide the map.
    private static func font(traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .boldSystemFont(ofSize: 15), maximumPointSize: 22, compatibleWith: traits)
    }

    private static func side(count: Int, font: UIFont) -> CGFloat {
        (count < 10 ? 32 : 38) * font.pointSize / 15
    }

    private static func badge(count: Int, font: UIFont, side: CGFloat, highContrast: Bool) -> UIImage {
        MarkerArt.badge(side: side, highContrast: highContrast, glass: false) { circle in
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.25)
            shadow.shadowOffset = CGSize(width: 0, height: 0.5)
            shadow.shadowBlurRadius = 1
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: font,
                .shadow: shadow,
            ]
            let text = "\(count)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
