//
//  NetworkMonitor.swift
//  CyprusPharmacies
//

import Foundation
import Network

protocol NetworkStatusProviding: AnyObject {
    /// Current connectivity; waits briefly for the first path update after launch.
    func isConnected() async -> Bool
    /// Called on the main actor whenever connectivity changes.
    var onChange: ((Bool) -> Void)? { get set }
}

/// State is guarded by `lock`, so the monitor can be used from any queue.
final class NetworkMonitor: NetworkStatusProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private let lock = NSLock()
    private var status: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private let forcedOffline: Bool

    var onChange: ((Bool) -> Void)?

    init(forcedOffline: Bool = false) {
        self.forcedOffline = forcedOffline
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func isConnected() async -> Bool {
        if forcedOffline { return false }
        if let status = currentStatus() { return status }
        return await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
                return
            }
            waiters.append(continuation)
            lock.unlock()
            // NWPathMonitor reports within milliseconds; never hang a load if it does not.
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.update(nil) }
        }
    }

    private func currentStatus() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    private func update(_ newStatus: Bool?) {
        lock.lock()
        let old = status
        if let newStatus { status = newStatus }
        let resolved = status ?? true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()

        pending.forEach { $0.resume(returning: forcedOffline ? false : resolved) }
        if let newStatus, newStatus != old, !forcedOffline {
            DispatchQueue.main.async { [weak self] in self?.onChange?(newStatus) }
        }
    }
}
