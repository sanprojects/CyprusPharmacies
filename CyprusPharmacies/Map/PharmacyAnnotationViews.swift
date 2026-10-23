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
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = MapStyle.clusteringIdentifier
        collisionMode = .circle
        image = UIImage(named: "pin")
        displayPriority = .defaultHigh
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = MapStyle.clusteringIdentifier
        accessibilityLabel = annotation?.title ?? "Pharmacy"
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let change = { self.transform = selected ? CGAffineTransform(scaleX: 1.5, y: 1.5) : .identity }
        animated ? UIView.animate(withDuration: 0.2, animations: change) : change()
    }
}

final class ClusterAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        displayPriority = .required
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        image = Self.badge(count: count)
        accessibilityLabel = "\(count) pharmacies, zoom in"
    }

    private static func badge(count: Int) -> UIImage {
        let side: CGFloat = count < 10 ? 32 : 38
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: bounds).fill()
            MapStyle.lightGreen.setFill()
            UIBezierPath(ovalIn: bounds.insetBy(dx: 2.5, dy: 2.5)).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 15),
            ]
            let text = "\(count)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attributes)
        }
    }
}
