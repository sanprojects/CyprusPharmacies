//
//  ErrorReporter.swift
//  CyprusPharmacies
//

import Foundation
import os
import Sentry

protocol LoadErrorReporting {
    /// A server-side load failure: HTTP != 2xx, timeout, decoding or transport error while online.
    func report(loadError: PharmacyAPIError, offset: Int, url: URL)
}

/// Thin wrapper over Sentry. Crash reporting is on as soon as `start()` runs with a DSN.
/// Sendable: the cache reports from any thread; Sentry itself is thread-safe.
final class ErrorReporter: LoadErrorReporting, Sendable {
    static let shared = ErrorReporter()

    private let enabled = OSAllocatedUnfairLock(initialState: false)
    var isEnabled: Bool { enabled.withLock { $0 } }

    func start(bundle: Bundle = .main) {
        let dsn = (bundle.object(forInfoDictionaryKey: "SentryDSN") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard dsn.hasPrefix("https://") else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "release"
            #endif
            options.enableCrashHandler = true
            options.attachStacktrace = true
            options.sendDefaultPii = false
        }
        enabled.withLock { $0 = true }
    }

    func report(loadError: PharmacyAPIError, offset: Int, url: URL) {
        guard isEnabled else { return }
        let error = PharmacyLoadError(underlying: loadError, offset: offset, url: url)
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: "pharmacy_load", key: "kind")
            scope.setTag(value: String(offset), key: "offset")
            scope.setTag(value: loadError.kindTag, key: "load_error")
            if let status = loadError.httpStatus {
                scope.setTag(value: String(status), key: "http_status")
            }
            scope.setContext(value: [
                "url": url.absoluteString,
                "offset": offset,
                "http_status": loadError.httpStatus as Any,
                "detail": String(describing: loadError),
                "app_version": Bundle.main.appVersion,
            ], key: "pharmacy_load")
        }
    }

    func report(cacheError: Error) {
        guard isEnabled else { return }
        SentrySDK.capture(error: cacheError) { scope in
            scope.setTag(value: "cache", key: "kind")
        }
    }
}

/// Sentry groups by type and code, so each failure kind gets its own issue.
struct PharmacyLoadError: CustomNSError, LocalizedError {
    let underlying: PharmacyAPIError
    let offset: Int
    let url: URL

    static var errorDomain: String { "CyprusPharmacies.PharmacyLoad" }

    var errorCode: Int {
        switch underlying {
        case .http(let status): return status
        case .decoding: return 1
        case .transport(let code): return code.rawValue
        case .invalidResponse: return 2
        case .offline: return 3
        }
    }

    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: errorDescription ?? ""]
    }

    var errorDescription: String? {
        "Pharmacy load failed (\(underlying.kindTag)) for offset \(offset): \(underlying)"
    }
}

extension PharmacyAPIError {
    var kindTag: String {
        switch self {
        case .offline: return "offline"
        case .http: return "http"
        case .decoding: return "decoding"
        case .transport(let code): return code == .timedOut ? "timeout" : "transport"
        case .invalidResponse: return "invalid_response"
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
