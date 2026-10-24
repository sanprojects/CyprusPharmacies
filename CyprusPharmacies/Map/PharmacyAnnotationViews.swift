//
//  PharmacyAnnotationViews.swift
//  CyprusPharmacies
//

import MapKit
import SwiftUI
import UIKit

final class PharmacyAnnotation: NSObject, MKAnnotation {
    private(set) var pharmacy: Pharmacy
    /// Observable, so that setting it inside a `UIView` animation block moves the marker smoothly.
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String? { pharmacy.name }

    init(_ pharmacy: Pharmacy) {
        self.pharmacy = pharmacy
        self.coordinate = pharmacy.coordinate
    }

    /// The same marker now stands for another pharmacy (it flies there when the day changes); the coordinate is set apart.
    func retarget(to pharmacy: Pharmacy) { self.pharmacy = pharmacy }
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
    /// A pin: `tipOffset` is where the coordinate (the dot) sits below the image center. With glass, `head` is where the green
    /// round goes, and `drop` is the clear glass around it, with the pointed tip.
    struct Pin {
        let image: UIImage
        let tipOffset: CGFloat
        let head: CGRect
        let rim: CGRect
        /// The outline of the clear glass: the drop with the pointed tip, and the ring of the dot under it.
        let drop: UIBezierPath
        /// The green round in the dot.
        let dot: CGRect
    }

    /// Rim width for a marker `side` wide.
    static func rim(side: CGFloat) -> CGFloat { side * 0.08 }

    /// With `glass` nothing is drawn: the drop, its head and the dot on the coordinate are glass.
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

        let spot = UIBezierPath(ovalIn: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius,
                                               width: 2 * dotRadius, height: 2 * dotRadius))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            if !glass {
                drawBody(drop, rim: rim, in: cg, scale: scale)
                drawFill(drop, rim: rim, head: head, colors: colors, in: cg)
                drawCross(at: center, radius: radius - rim)
                drawBody(spot, rim: 0, in: cg, scale: scale * 0.6)
                colors[1].setFill()
                UIBezierPath(ovalIn: spot.bounds.insetBy(dx: scale, dy: scale)).fill()
            }
        }
        // The glass is one outline, the dot a ring apart from the drop.
        let outline = UIBezierPath(cgPath: drop.cgPath)
        outline.append(spot)
        return Pin(image: image, tipOffset: dot.y - size.height / 2, head: head.insetBy(dx: rim, dy: rim),
                   rim: head, drop: outline, dot: spot.bounds.insetBy(dx: scale, dy: scale))
    }

    /// A round badge `side` wide in a white rim, with room for its shadow; the count is drawn by the caller in `badge`.
    /// With `glass` nothing is drawn: the glass is the whole badge, and the image only gives it its frame.
    static func badge(side: CGFloat, highContrast: Bool, glass: Bool, draw content: (CGRect) -> Void = { _ in }) -> UIImage {
        let pad = padding(side: side)
        let size = CGSize(width: side + 2 * pad, height: side + 2 * pad)
        if glass { return clear(size: size) }
        let circle = UIBezierPath(ovalIn: CGRect(x: pad, y: pad, width: side, height: side))
        let rim = rim(side: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            drawBody(circle, rim: rim, in: context.cgContext, scale: side / 30)
            drawFill(circle, rim: rim, head: circle.bounds, colors: MapStyle.markerColors(highContrast: highContrast),
                     in: context.cgContext)
            content(circle.bounds)
        }
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

    /// A transparent image: it gives a glass marker its frame, as the drawn one would.
    static func clear(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in }
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

/// What is on the green head of a glass marker.
enum MarkerSymbol {
    case none
    case cross
    case count(String, UIFont)
}

/// The whole glass marker in one SwiftUI tree: the clear glass (UIKit glass can only be a rounded rectangle, SwiftUI glass can
/// be any shape), the green rounds of glass on it, and what is written on the head. One tree is rendered and moved as one, so
/// the layers never part while MapKit zooms, clusters and splits the markers.
@available(iOS 26, *)
private struct GlassMarkerArt: View {
    let drop: Path
    let head: CGRect
    let dot: CGRect?
    let tint: Color
    let symbol: MarkerSymbol

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.glassEffect(.regular, in: PathShape(outline: drop))
            green(head)
            if let dot { green(dot) }
            switch symbol {
            case .none:
                EmptyView()
            case .cross:
                let side = head.width * 0.44
                Image(systemName: "cross.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .position(x: head.midX, y: head.midY)
            case let .count(text, font):
                Text(text)
                    .font(Font(font))
                    .foregroundStyle(.white)
                    .position(x: head.midX, y: head.midY)
            }
        }
    }

    private func green(_ rect: CGRect) -> some View {
        Color.clear
            .frame(width: rect.width, height: rect.height)
            .glassEffect(.regular.tint(tint), in: Circle())
            .offset(x: rect.minX, y: rect.minY)
    }

    private struct PathShape: Shape {
        let outline: Path
        func path(in rect: CGRect) -> Path { outline }
    }
}

/// A Liquid Glass marker in the shape of the drawn one: a drop with a pointed tip (a round for a badge) of clear glass, and
/// on it, inside the rim, a round of glass tinted light green. The layers are apart, so the green does not spread to the rim.
@available(iOS 26, *)
final class GlassMarkerView: UIView {
    private let host = UIHostingController(rootView: GlassMarkerArt(drop: Path(), head: .zero, dot: nil, tint: .clear, symbol: .cross))

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.safeAreaRegions = []
        addSubview(host.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `drop` is the outline of the clear glass; nil is a round, `rim`.
    func show(head: CGRect, rim: CGRect, drop: UIBezierPath?, dot: CGRect? = nil, symbol: MarkerSymbol, highContrast: Bool,
              color: UIColor? = nil) {
        let tint = color ?? (highContrast
            ? MapStyle.markerColors(highContrast: true)[1].withAlphaComponent(0.85)
            : MapStyle.lightGreen.withAlphaComponent(0.7))
        host.view.frame = bounds
        host.rootView = GlassMarkerArt(drop: Path((drop ?? UIBezierPath(ovalIn: rim)).cgPath), head: head, dot: dot,
                                       tint: Color(tint), symbol: symbol)
    }
}

final class PharmacyAnnotationView: MKAnnotationView {
    fileprivate static let diameter: CGFloat = 44
    private static let selectedScale: CGFloat = 1.5
    private static let hasGlass = if #available(iOS 26, *) { true } else { false }
    /// Pins by Increase Contrast, then unselected and selected; the selected one is drawn at its size, so it stays sharp
    /// instead of a stretched bitmap. With glass they are only the dot, and where the glass goes.
    private static let pins = [false, true].map { highContrast in
        [1, selectedScale].map { MarkerArt.pin(diameter: diameter * $0, highContrast: highContrast, glass: hasGlass) }
    }
    /// The image MapKit sees: clear, of the resting pin's size. It gives the annotation view its frame and its
    /// collision footprint, which the selection does not change, so a selected pin never pulls a neighbour into a cluster.
    private static let frameImage = MarkerArt.clear(size: pins[0][0].image.size)

    /// Everything that is seen: the drawn art and, on iOS 26+, the glass. The selection resizes and sways this view, not the
    /// annotation view: its frame, alpha and transform stay MapKit's, which animates them itself as clusters form and split.
    private let content = UIView()
    private let art = UIImageView()
    private var glass: UIView?
    private var isShownSelected = false
    /// How far under the center of `content` the coordinate is.
    private var tip: CGFloat = 0

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = MapStyle.clusteringIdentifier
        collisionMode = .circle
        // Clustering alone thins the pins out: a pin MapKit hid for colliding with a cluster badge would stay hidden.
        displayPriority = .required
        image = Self.frameImage
        centerOffset = CGPoint(x: 0, y: -Self.pins[0][0].tipOffset)
        addSubview(content)
        content.addSubview(art)
        if #available(iOS 26, *) {
            let marker = GlassMarkerView()
            content.addSubview(marker)
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

    /// The grown part of a selected pin is outside the frame: a tap on it is still a tap on the pin.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || content.frame.contains(point)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        land()
        show(selected: false)
    }

    /// A pin new to the day grows from its tip, a moment after the others have started to move.
    func appear() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        content.layer.removeAllAnimations()
        content.alpha = 0
        content.transform = pivot(scale: 0.3)
        UIView.animate(withDuration: 0.4, delay: 0.25, options: [.allowUserInteraction, .curveEaseOut]) {
            self.content.alpha = 1
            self.content.transform = .identity
        }
    }

    /// A pin that flies in the day's change: its drawing starts `offset` away from where the coordinate is, and comes there.
    func fly(from offset: CGPoint, duration: TimeInterval) {
        guard hypot(offset.x, offset.y) > 0.5 else { return }
        content.layer.removeAllAnimations()
        content.alpha = 1
        content.transform = CGAffineTransform(translationX: offset.x, y: offset.y)
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.content.transform = .identity
        }
    }

    /// A flight cut short: the pin is where its coordinate is.
    func land() {
        content.layer.removeAllAnimations()
        content.transform = .identity
        content.alpha = 1
    }

    func refreshLabel() { accessibilityLabel = annotation?.title ?? "Pharmacy" }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = MapStyle.clusteringIdentifier
        accessibilityLabel = annotation?.title ?? "Pharmacy"
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard selected != isShownSelected else { return }
        show(selected: selected)
        content.layer.removeAllAnimations()
        guard animated else { content.transform = .identity; return }
        // The new size is laid out at once, then it grows or shrinks from the old size, the tip staying on the coordinate.
        // The head, the tail, the dot and the cross are in one view, so they move as one.
        content.transform = pivot(scale: selected ? 1 / Self.selectedScale : Self.selectedScale)
        let options: UIView.AnimationOptions = [.allowUserInteraction, .beginFromCurrentState]
        guard selected && !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(withDuration: 0.15, delay: 0, options: options) { self.content.transform = .identity }
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
                    self.content.transform = self.pivot(scale: step.scale, degrees: step.degrees)
                }
                begin += step.time
            }
        }
    }

    /// Scale and turn about the tip, so it stays on the coordinate.
    private func pivot(scale: CGFloat, degrees: CGFloat = 0) -> CGAffineTransform {
        CGAffineTransform(translationX: 0, y: -tip)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
            .concatenating(CGAffineTransform(translationX: 0, y: tip))
    }

    private func show(selected: Bool) {
        isShownSelected = selected
        let highContrast = traitCollection.accessibilityContrast == .high
        let pair = Self.pins[highContrast ? 1 : 0]
        let rest = pair[0], shown = selected ? pair[1] : pair[0]
        tip = shown.tipOffset
        content.bounds = CGRect(origin: .zero, size: shown.image.size)
        // The coordinate stays under the dot of the resting pin, whatever size is shown.
        content.center = CGPoint(x: bounds.midX, y: bounds.midY + rest.tipOffset - shown.tipOffset)
        art.frame = content.bounds
        art.image = shown.image
        if #available(iOS 26, *), let marker = glass as? GlassMarkerView {
            marker.frame = content.bounds
            marker.show(head: shown.head, rim: shown.rim, drop: shown.drop, dot: shown.dot, symbol: .cross,
                        highContrast: highContrast)
        }
    }
}

final class ClusterAnnotationView: MKAnnotationView {
    /// The glass badge on iOS 26+, as the head of a pin.
    private var glass: UIView?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        if #available(iOS 26, *) {
            let marker = GlassMarkerView()
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
            let inset = MarkerArt.padding(side: side)
            marker.frame = bounds
            let rim = bounds.insetBy(dx: inset, dy: inset)
            marker.show(head: rim.insetBy(dx: MarkerArt.rim(side: side), dy: MarkerArt.rim(side: side)), rim: rim, drop: nil,
                        symbol: .count("\(count)", font), highContrast: highContrast)
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

    /// As wide as the head of a pin.
    private static func side(count: Int, font: UIFont) -> CGFloat {
        PharmacyAnnotationView.diameter * font.pointSize / 15
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

/// The user's location on iOS 26+, as the system dot but in the style of the markers: a round of clear glass with a round of
/// glass tinted system blue on it, and a soft halo pulsing around it. Earlier systems keep the system dot.
@available(iOS 26, *)
final class UserLocationView: MKAnnotationView {
    /// The size of the system dot, rim included.
    private static let diameter: CGFloat = 22
    private static let rim: CGFloat = 3.5
    private static let pad: CGFloat = 4

    private let halo = UIView()
    private let marker = GlassMarkerView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let side = Self.diameter + 2 * Self.pad
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        isEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "My location"
        displayPriority = .required
        collisionMode = .none
        zPriority = .max

        halo.frame = CGRect(x: Self.pad, y: Self.pad, width: Self.diameter, height: Self.diameter)
        halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
        halo.layer.cornerRadius = Self.diameter / 2
        halo.isUserInteractionEnabled = false
        addSubview(halo)

        marker.frame = bounds
        addSubview(marker)
        let outer = CGRect(x: Self.pad, y: Self.pad, width: Self.diameter, height: Self.diameter)
        marker.show(head: outer.insetBy(dx: Self.rim, dy: Self.rim), rim: outer, drop: nil, symbol: .none, highContrast: false,
                    color: UIColor.systemBlue.withAlphaComponent(0.85))

        NotificationCenter.default.addObserver(self, selector: #selector(pulse), name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { pulse() }
    }

    /// The halo grows and fades out, again and again; with Reduce Motion it stays still and faint.
    @objc private func pulse() {
        halo.layer.removeAllAnimations()
        guard !UIAccessibility.isReduceMotionEnabled else { halo.alpha = 0.2; return }
        halo.alpha = 1
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 2
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        halo.layer.add(group, forKey: "pulse")
    }
}
