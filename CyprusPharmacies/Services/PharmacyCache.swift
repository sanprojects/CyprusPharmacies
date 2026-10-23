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

protocol PharmacyCaching {
    func load(dayKey: String) -> CachedDay?
    func save(_ pharmacies: [Pharmacy], dayKey: String)
    /// Deletes every day strictly before `todayKey`.
    func removeDays(before todayKey: String)
}

/// One JSON file per calendar day in Application Support, so the cache survives restarts and is not purged like Caches.
final class PharmacyCache: PharmacyCaching {
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

    func save(_ pharmacies: [Pharmacy], dayKey: String) {
        let day = CachedDay(dayKey: dayKey, savedAt: now(), pharmacies: pharmacies)
        queue.sync {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(day).write(to: fileURL(dayKey), options: .atomic)
            } catch {
                ErrorReporter.shared.report(cacheError: error)
            }
        }
    }

    func removeDays(before todayKey: String) {
        queue.sync {
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

    private func fileURL(_ dayKey: String) -> URL {
        directory.appendingPathComponent("\(dayKey).json")
    }
}
