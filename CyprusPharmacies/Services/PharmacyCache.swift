//
//  PharmacyCache.swift
//  CyprusPharmacies
//

import Foundation

struct CachedDay: Codable, Equatable {
    let dayKey: String
    let savedAt: Date
    let pharmacies: [Pharmacy]
}

/// The roster the cached days came from: its ETag, and when the server last sent or confirmed it.
struct RosterStamp: Codable, Equatable {
    let etag: String?
    let checkedAt: Date
}

protocol PharmacyCaching {
    func load(dayKey: String) -> CachedDay?
    func save(_ pharmacies: [Pharmacy], dayKey: String)
    /// Deletes every day strictly before `todayKey`.
    func removeDays(before todayKey: String)
    func loadRosterStamp() -> RosterStamp?
    func saveRosterStamp(_ stamp: RosterStamp)
}

/// One JSON file per calendar day in Application Support, so the cache survives restarts and is not purged like Caches.
/// Sendable: the state is constant and every file access goes through the serial queue.
final class PharmacyCache: PharmacyCaching, @unchecked Sendable {
    private let directory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let queue = DispatchQueue(label: "PharmacyCache")

    init(directory: URL? = nil, fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.fileManager = fileManager
        self.now = now
        self.directory = directory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PharmacyCache", isDirectory: true)
    }

    func load(dayKey: String) -> CachedDay? {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL(dayKey)) else { return nil }
            return try? JSONDecoder().decode(CachedDay.self, from: data)
        }
    }

    /// Written in the background: a later `load` on the same queue still sees it.
    func save(_ pharmacies: [Pharmacy], dayKey: String) {
        let day = CachedDay(dayKey: dayKey, savedAt: now(), pharmacies: pharmacies)
        write(day, to: fileURL(dayKey))
    }

    func loadRosterStamp() -> RosterStamp? {
        queue.sync {
            guard let data = try? Data(contentsOf: stampURL) else { return nil }
            return try? JSONDecoder().decode(RosterStamp.self, from: data)
        }
    }

    func saveRosterStamp(_ stamp: RosterStamp) {
        write(stamp, to: stampURL)
    }

    private func write(_ value: some Encodable & Sendable, to url: URL) {
        queue.async { [self] in
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(value).write(to: url, options: .atomic)
            } catch {
                ErrorReporter.shared.report(cacheError: error)
            }
        }
    }

    /// In the background, like the writes: nothing waits for old days to go.
    func removeDays(before todayKey: String) {
        queue.async { [self] in
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                // ISO dates compare correctly as strings.
                if file.deletingPathExtension().lastPathComponent < todayKey {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }

    func removeAll() {
        queue.sync { _ = try? fileManager.removeItem(at: directory) }
    }

    /// Not a `.json` file, so `removeDays` leaves it alone.
    private var stampURL: URL { directory.appendingPathComponent("roster.stamp") }

    private func fileURL(_ dayKey: String) -> URL {
        directory.appendingPathComponent("\(dayKey).json")
    }
}
