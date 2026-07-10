import Foundation
import Testing
@testable import Antrum

@Suite("Local model setup")
struct ModelSetupTests {

    @Test
    func downloadGateSerializesNetworkAccessAndRestoresOfflineMode() async throws {
        let state = DownloadGateOfflineState()
        let gate = FluidAudioDownloadGate(setOffline: state.setOffline)
        let probe = DownloadGateProbe()

        async let first: Void = gate.withNetworkAccess {
            await probe.begin()
            try await Task.sleep(for: .milliseconds(20))
            await probe.finish()
        }
        async let second: Void = gate.withNetworkAccess {
            await probe.begin()
            try await Task.sleep(for: .milliseconds(20))
            await probe.finish()
        }
        _ = try await (first, second)

        #expect(await probe.maximumConcurrentOperations == 1)
        #expect(state.transitions == [false, true, false, true])
        #expect(state.isOffline)
    }

    @Test
    func sortformerRequiresTranscriptionAndItsSelectedSpeakerEngine() {
        let required = LocalModelCatalog.requiredPackageIDs(for: .nvidiaSortformerV21)

        #expect(required == [.transcription, .sortformer])
    }

    @Test
    func pyannoteRequiresTranscriptionAndItsSelectedSpeakerEngine() {
        let required = LocalModelCatalog.requiredPackageIDs(for: .pyannoteCoreML)

        #expect(required == [.transcription, .pyannote])
    }

    @Test
    func setupExplainsThatModelDownloadsStaySeparateFromMeetingData() {
        #expect(LocalModelSetupPolicy.summary.contains("not uploaded"))
        #expect(LocalModelSetupPolicy.summary.contains("local"))
        #expect(LocalModelSetupPolicy.summary.contains("FluidAudio/Hugging Face"))
    }

    @Test
    func allModelPackagesDiscloseApproximateSizeSourceAndUploadBoundary() {
        for package in LocalModelCatalog.packages {
            #expect(package.estimatedSizeText.contains("Approx."))
            #expect(package.estimatedSizeText.contains("MB"))
            #expect(package.sourceText.contains("FluidAudio/Hugging Face"))
            #expect(package.sourceText.contains("not uploaded"))
        }
    }

    @Test
    func modelInstallChecksUseAntrumOwnedStorage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntrumModelStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let modelRoot = LocalModelStoragePolicy.modelDirectory(for: .parakeetV3, in: root)

        #expect(modelRoot.path.hasPrefix(root.appendingPathComponent("Antrum/Models").path))
        #expect(!modelRoot.path.contains("/FluidAudio/"))
    }
}

private actor DownloadGateProbe {
    private var activeOperations = 0
    private(set) var maximumConcurrentOperations = 0

    func begin() {
        activeOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperations)
    }

    func finish() {
        activeOperations -= 1
    }
}

private final class DownloadGateOfflineState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var transitions: [Bool] = []
    private(set) var isOffline = true

    var setOffline: @Sendable (Bool) -> Void {
        { [weak self] isOffline in
            self?.lock.lock()
            self?.isOffline = isOffline
            self?.transitions.append(isOffline)
            self?.lock.unlock()
        }
    }
}
