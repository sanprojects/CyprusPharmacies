//
//  PharmacyAPI.swift
//  CyprusPharmacies
//

import CoreLocation
import Foundation

enum PharmacyAPIError: Error, Equatable {
    /// The device lost connectivity mid-request. Shown as "No internet", never reported as a server error.
    case offline
    case http(status: Int)
    case decoding(String)
    case transport(URLError.Code)
    case invalidResponse

    var httpStatus: Int? {
        if case .http(let status) = self { return status }
        return nil
    }
}

/// Every day the server has from today on, from `days.php`: the roster is written weekly, so one request covers the week.
struct Roster: Decodable, Equatable {
    /// The server's duty day, `YYYY-MM-DD`.
    let today: String
    let days: [String: [Pharmacy]]
}

enum RosterResponse: Equatable {
    /// The roster is the one of the ETag sent.
    case notModified
    case roster(Roster, etag: String?)
}

protocol PharmacyFetching {
    func url(offset: Int) -> URL
    /// Throws `PharmacyAPIError` or `CancellationError`.
    func pharmacies(offset: Int) async throws -> [Pharmacy]
    /// Throws like `pharmacies(offset:)`; `.http(status: 404)` from a server without `days.php`.
    func roster(etag: String?) async throws -> RosterResponse
    /// Center of the city of the device's IP address when it is in Cyprus; nil elsewhere and on any failure.
    func ipCity() async -> CLLocationCoordinate2D?
}

struct PharmacyAPI: PharmacyFetching {
    static let defaultBaseURL = URL(string: "https://sanstv.ru/pharmacies/data/today.php")!

    var baseURL: URL = PharmacyAPI.defaultBaseURL
    var session: URLSession = .shared
    var timeout: TimeInterval = 20

    func url(offset: Int) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "offset", value: String(offset))]
        return components?.url ?? baseURL
    }

    /// `days.php` and `geo.php` sit next to `today.php`.
    var rosterURL: URL { baseURL.deletingLastPathComponent().appendingPathComponent("days.php") }
    var ipCityURL: URL { baseURL.deletingLastPathComponent().appendingPathComponent("geo.php") }

    func pharmacies(offset: Int) async throws -> [Pharmacy] {
        let (data, _) = try await get(url(offset: offset))
        return try Self.decode(data)
    }

    func roster(etag: String?) async throws -> RosterResponse {
        var request = makeRequest(rosterURL)
        // The app keeps the roster itself and revalidates it here, so URLCache must not answer for the server.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, http) = try await send(request, accepting: 304)
        if http.statusCode == 304 { return .notModified }
        return .roster(try Self.decode(Roster.self, from: data), etag: http.value(forHTTPHeaderField: "ETag"))
    }

    func ipCity() async -> CLLocationCoordinate2D? {
        var request = makeRequest(ipCityURL)
        request.timeoutInterval = 5
        // "null" outside Cyprus.
        guard let response = try? await send(request),
              let place = try? JSONDecoder().decode(IPCity?.self, from: response.0) else { return nil }
        return CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
    }

    private struct IPCity: Decodable {
        let lat: Double
        let lng: Double
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        try await send(makeRequest(url))
    }

    /// A 2xx response, or one with `status`; throws `PharmacyAPIError` or `CancellationError` otherwise.
    private func send(_ request: URLRequest, accepting status: Int? = nil) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.map(error)
        } catch is CancellationError {
            throw CancellationError()
        }

        guard let http = response as? HTTPURLResponse else { throw PharmacyAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) || http.statusCode == status else {
            throw PharmacyAPIError.http(status: http.statusCode)
        }
        return (data, http)
    }

    static func decode(_ data: Data) throws -> [Pharmacy] {
        try decode([Pharmacy].self, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PharmacyAPIError.decoding(String(describing: error))
        }
    }

    static func map(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return PharmacyAPIError.offline
        default:
            return PharmacyAPIError.transport(error.code)
        }
    }
}
