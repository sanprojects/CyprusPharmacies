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
    /// Top of the marker gradient; white bold text on it still has 3:1.
    static let lightGreen = UIColor(red: 0.10, green: 0.62, blue: 0.42, alpha: 1)
}

/// Markers drawn in code, so they are sharp at every size: a green glass drop with a white rim, a soft top highlight
/// and a shadow; the pin has the usual tail, its tip on the coordinate.
enum MarkerArt {
    private static let shadowPadding: CGFloat = 3
    private static let rim: CGFloat = 2

    /// A pin whose head is `diameter` wide; `tipOffset` is where the tip sits below the image center.
    static func pin(diameter: CGFloat) -> (image: UIImage, tipOffset: CGFloat) {
        let radius = diameter / 2
        let height = diameter * 1.32
        let pad = shadowPadding * diameter / 30
        let size = CGSize(width: diameter + 2 * pad, height: height + 2 * pad)
        let center = CGPoint(x: size.width / 2, y: pad + radius)
        let tip = CGPoint(x: center.x, y: pad + height)
        // The tail leaves the head where the lines from the tip touch it.
        let spread = acos(radius / (tip.y - center.y))
        let drop = UIBezierPath(arcCenter: center, radius: radius,
                                startAngle: .pi / 2 + spread, endAngle: .pi / 2 - spread, clockwise: true)
        drop.addLine(to: tip)
        drop.close()

        let image = UIGraphicsImageRenderer(size: size).image { context in
            drawGlass(drop, head: CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter),
                      in: context.cgContext, scale: diameter / 30)
            drawCross(at: center, radius: radius)
        }
        return (image, tip.y - size.height / 2)
    }

    /// A round badge `side` wide with room for its shadow, the count drawn by the caller in `badge`.
    static func badge(side: CGFloat, draw content: (CGRect) -> Void) -> UIImage {
        let pad = shadowPadding
        let size = CGSize(width: side + 2 * pad, height: side + 2 * pad)
        let circle = CGRect(x: pad, y: pad, width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            drawGlass(UIBezierPath(ovalIn: circle), head: circle, in: context.cgContext, scale: 1)
            content(circle)
        }
    }

    private static func drawGlass(_ shape: UIBezierPath, head: CGRect, in cg: CGContext, scale: CGFloat) {
        // Shadow under a white body; the rim is what the green leaves of it.
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1 * scale), blur: 3 * scale,
                     color: UIColor.black.withAlphaComponent(0.35).cgColor)
        UIColor.white.setFill()
        shape.fill()
        cg.restoreGState()

        cg.saveGState()
        shape.addClip()
        // Fill everything inside the rim: the shape minus a stroke of twice the rim width.
        let body = shape.cgPath.copy(strokingWithWidth: 2 * rim * scale, lineCap: .round, lineJoin: .round, miterLimit: 1)
        cg.addPath(shape.cgPath)
        cg.addPath(body)
        cg.clip(using: .evenOdd)
        let bounds = shape.bounds
        let colors = [MapStyle.lightGreen.cgColor, MapStyle.green.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.minY),
                                  end: CGPoint(x: bounds.midX, y: head.maxY), options: [.drawsAfterEndLocation])
        }
        // A soft sheen on the upper half of the head.
        let sheen = UIBezierPath(ovalIn: CGRect(x: head.minX + head.width * 0.18, y: head.minY + head.height * 0.06,
                                                width: head.width * 0.64, height: head.height * 0.42))
        sheen.addClip()
        let shine = [UIColor.white.withAlphaComponent(0.45).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shine, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: head.midX, y: head.minY),
                                  end: CGPoint(x: head.midX, y: head.minY + head.height * 0.48), options: [])
        }
        cg.restoreGState()
    }

    private static func drawCross(at center: CGPoint, radius: CGFloat) {
        let arm = radius * 0.98
        let width = radius * 0.34
        UIColor.white.setFill()
        UIBezierPath(roundedRect: CGRect(x: center.x - arm / 2, y: center.y - width / 2, width: arm, height: width),
                     cornerRadius: width * 0.3).fill()
        UIBezierPath(roundedRect: CGRect(x: center.x - width / 2, y: center.y - arm / 2, width: width, height: arm),
                     cornerRadius: width * 0.3).fill()
    }
}

final class PharmacyAnnotationView: MKAnnotationView {
    private static let diameter: CGFloat = 30
    private static let selectedScale: CGFloat = 1.5
    private static let pin = MarkerArt.pin(diameter: diameter)
    /// Drawn at the selected size, so the selected pin stays sharp instead of a stretched bitmap.
    private static let selectedPin = MarkerArt.pin(diameter: diameter * selectedScale)

    private var isShownSelected = false
    private var collisionInsets = UIEdgeInsets.zero

    /// MapKit checks collisions on the frame minus these insets. The selected pin keeps its unselected footprint, so
    /// growing does not pull it into a cluster with a neighbour it stood apart from.
    override var alignmentRectInsets: UIEdgeInsets { collisionInsets }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = MapStyle.clusteringIdentifier
        collisionMode = .circle
        show(selected: false)
        isAccessibilityElement = true
        accessibilityTraits = .button
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
        guard animated else { transform = .identity; return }
        // Swap the image at once, then grow or shrink from the old size, the tip staying on the coordinate.
        let scale = selected ? 1 / Self.selectedScale : Self.selectedScale
        let tip = -centerOffset.y
        transform = CGAffineTransform(translationX: 0, y: (1 - scale) * tip).scaledBy(x: scale, y: scale)
        UIView.animate(withDuration: 0.2) { self.transform = .identity }
    }

    private func show(selected: Bool) {
        isShownSelected = selected
        let art = selected ? Self.selectedPin : Self.pin
        image = art.image
        centerOffset = CGPoint(x: 0, y: -art.tipOffset)
        collisionInsets = selected ? Self.footprint(of: Self.pin, in: Self.selectedPin) : .zero
        displayPriority = .defaultHigh
    }

    /// Insets that cut the `outer` pin's frame down to the `inner` pin's, the tips on one spot.
    private static func footprint(of inner: (image: UIImage, tipOffset: CGFloat),
                                  in outer: (image: UIImage, tipOffset: CGFloat)) -> UIEdgeInsets {
        let big = outer.image.size, small = inner.image.size
        let side = (big.width - small.width) / 2
        let top = (big.height / 2 + outer.tipOffset) - (small.height / 2 + inner.tipOffset)
        return UIEdgeInsets(top: top, left: side, bottom: big.height - small.height - top, right: side)
    }
}

final class ClusterAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityTraits = .button
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: Self, _) in
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
        image = Self.badge(count: count, traits: traitCollection)
        accessibilityLabel = "\(count) pharmacies, zoom in"
    }

    /// The count follows the text size, up to a point, so large badges do not hide the map.
    private static func badge(count: Int, traits: UITraitCollection) -> UIImage {
        let font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .boldSystemFont(ofSize: 15), maximumPointSize: 22, compatibleWith: traits)
        let side = (count < 10 ? 32 : 38) * font.pointSize / 15
        return MarkerArt.badge(side: side) { circle in
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
