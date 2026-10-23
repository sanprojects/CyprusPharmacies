//
//  Pharmacy.swift
//  CyprusPharmacies
//

import Foundation
import CoreLocation

/// One duty pharmacy as returned by `today.php?offset=N`.
struct Pharmacy: Codable, Hashable, Identifiable {
    let date: String
    let originalname: String
    let name: String
    let address: String
    let originalAddress: String
    let pharmacyPhone: String
    let homePhone: String
    let lat: Double
    let lng: Double
    let gesyId: String
    let description: String

    var id: String { "\(date)|\(name)|\(lat)|\(lng)" }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Greek name shown under the title; nil when the feed has none or it repeats `name`.
    var greekName: String? {
        let greek = originalname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !greek.isEmpty,
              greek.compare(name.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) != .orderedSame
        else { return nil }
        return greek
    }

    /// Apple Maps link to the pharmacy, for sharing; opens in a browser where Maps is missing.
    var appleMapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), lat, lng)),
            URLQueryItem(name: "q", value: name.isEmpty ? "Pharmacy" : name),
        ]
        return components?.url
    }

    /// Numbers offered by the Call button, in the order the spec lists them. Empty numbers are skipped.
    var phoneOptions: [PhoneOption] {
        [PhoneOption(kind: .pharmacy, number: pharmacyPhone),
         PhoneOption(kind: .mobile, number: homePhone)]
            .filter { $0.dialURL != nil }
    }

    init(date: String, originalname: String = "", name: String, address: String = "",
         originalAddress: String = "", pharmacyPhone: String = "", homePhone: String = "",
         lat: Double, lng: Double, gesyId: String = "", description: String = "") {
        self.date = date
        self.originalname = originalname
        self.name = name
        self.address = address
        self.originalAddress = originalAddress
        self.pharmacyPhone = pharmacyPhone
        self.homePhone = homePhone
        self.lat = lat
        self.lng = lng
        self.gesyId = gesyId
        self.description = description
    }

    // Text fields may be missing or null in the feed; treat them as empty instead of failing the whole day.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: key) ?? "" }
        date = try text(.date)
        originalname = try text(.originalname)
        name = try text(.name)
        address = try text(.address)
        originalAddress = try text(.originalAddress)
        pharmacyPhone = try text(.pharmacyPhone)
        homePhone = try text(.homePhone)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        gesyId = try text(.gesyId)
        description = try text(.description)
    }
}

struct PhoneOption: Hashable {
    enum Kind {
        case pharmacy
        case mobile

        var title: String {
            switch self {
            case .pharmacy: return "Pharmacy phone"
            case .mobile: return "Mobile phone"
            }
        }
    }

    let kind: Kind
    let number: String

    /// `tel:` URL that keeps the leading `+` and drops spaces, dashes and brackets.
    var dialURL: URL? {
        let dialable = number.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        guard dialable.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(dialable)")
    }
}
