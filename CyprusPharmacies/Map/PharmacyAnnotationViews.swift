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
    static let lightGreen = UIColor(red: 0.46, green: 0.83, blue: 0.51, alpha: 1)
}

final class PharmacyAnnotationView: MKAnnotationView {
    private static let selectedScale: CGFloat = 1.5
    private static let pin = UIImage(named: "pin")
    /// Drawn from the vector at the selected size, so the selected pin stays sharp instead of a stretched bitmap.
    private static let selectedPin = pin.map { pin in
        let size = CGSize(width: pin.size.width * selectedScale, height: pin.size.height * selectedScale)
        return UIGraphicsImageRenderer(size: size).image { _ in pin.draw(in: CGRect(origin: .zero, size: size)) }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = MapStyle.clusteringIdentifier
        collisionMode = .circle
        image = Self.pin
        displayPriority = .defaultHigh
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
        image = Self.pin
        transform = .identity
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = MapStyle.clusteringIdentifier
        accessibilityLabel = annotation?.title ?? "Pharmacy"
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let wasSelected = image === Self.selectedPin
        guard selected != wasSelected else { return }
        image = selected ? Self.selectedPin : Self.pin
        guard animated else { transform = .identity; return }
        // Swap the image at once, then grow or shrink from the old size.
        let scale = selected ? 1 / Self.selectedScale : Self.selectedScale
        transform = CGAffineTransform(scaleX: scale, y: scale)
        UIView.animate(withDuration: 0.2) { self.transform = .identity }
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
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: bounds).fill()
            MapStyle.lightGreen.setFill()
            UIBezierPath(ovalIn: bounds.insetBy(dx: 2.5, dy: 2.5)).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: font,
            ]
            let text = "\(count)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attributes)
        }
    }
}
