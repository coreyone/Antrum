import FluidAudio
import Foundation

/// Serializes the only periods when FluidAudio is allowed to reach the network.
///
/// FluidAudio documents `ModelHub.offlineMode` as a process-global,
/// startup-only setting. Antrum needs a short, explicit exception for a
/// user-approved model download, so all exceptions go through this gate.
actor FluidAudioDownloadGate {
    static let shared = FluidAudioDownloadGate()

    private let setOffline: @Sendable (Bool) -> Void
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(setOffline: @escaping @Sendable (Bool) -> Void = { ModelHub.offlineMode = $0 }) {
        self.setOffline = setOffline
    }

    func withNetworkAccess<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()

        do {
            try Task.checkCancellation()
        } catch {
            release()
            throw error
        }

        setOffline(false)
        defer {
            setOffline(true)
            release()
        }
        return try await operation()
    }

    private func acquire() async {
        guard isOccupied else {
            isOccupied = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard let next = waiters.first else {
            isOccupied = false
            return
        }

        waiters.removeFirst()
        next.resume()
    }
}
