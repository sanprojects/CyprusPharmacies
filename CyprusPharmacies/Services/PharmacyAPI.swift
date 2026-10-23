//
//  PharmacyAPI.swift
//  CyprusPharmacies
//

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

protocol PharmacyFetching {
    func url(offset: Int) -> URL
    /// Throws `PharmacyAPIError` or `CancellationError`.
    func pharmacies(offset: Int) async throws -> [Pharmacy]
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

    func pharmacies(offset: Int) async throws -> [Pharmacy] {
        var request = URLRequest(url: url(offset: offset), timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

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
        guard (200...299).contains(http.statusCode) else { throw PharmacyAPIError.http(status: http.statusCode) }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [Pharmacy] {
        do {
            return try JSONDecoder().decode([Pharmacy].self, from: data)
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
