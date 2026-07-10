import FluidAudio
import Foundation

actor DictationModelManager {
    private var manager: UnifiedAsrManager?

    func transcribe(fileURL: URL) async throws -> String {
        guard Self.isInstalled() else {
            throw DictationModelError.modelMissing
        }

        let manager = try await loadedManager()
        let samples = try AudioConverter().resampleAudioFile(fileURL)
        let preparedSamples = try Self.prepareSamplesForTranscription(samples)
        return try await manager.transcribe(preparedSamples)
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let model = UnifiedAsrManager(encoderPrecision: .int8)
        try await FluidAudioDownloadGate.shared.withNetworkAccess {
            try await model.loadModels(
                to: Self.defaultModelsDirectory,
                progressHandler: { update in
                    progress(max(0, min(1, update.fractionCompleted)))
                }
            )
        }
        manager = model
    }

    private func loadedManager() async throws -> UnifiedAsrManager {
        if let manager { return manager }
        let model = UnifiedAsrManager(encoderPrecision: .int8)
        try await model.loadModels(from: Self.defaultModelRoot)
        manager = model
        return model
    }

    nonisolated static var defaultModelsDirectory: URL {
        LocalModelStoragePolicy.defaultModelsDirectory()
    }

    nonisolated static var defaultModelRoot: URL {
        LocalModelStoragePolicy.defaultModelDirectory(for: Repo.parakeetUnified)
    }

    nonisolated static func isInstalled(modelsRoot root: URL = defaultModelRoot, fileManager: FileManager = .default) -> Bool {
        return ModelNames.ParakeetUnified.requiredModels(variant: "offline").allSatisfy {
            fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    nonisolated static func prepareSamplesForTranscription(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else {
            throw DictationModelError.noAudioCaptured
        }

        let prepared = AudioPreparation.prepare(samples, track: .microphone)
        guard prepared.containsSpeech else {
            throw DictationModelError.noSpeechDetected
        }
        return prepared.samples
    }
}

enum DictationModelError: AppCodedError {
    case modelMissing
    case noAudioCaptured
    case noSpeechDetected

    var code: AppErrorCode {
        switch self {
        case .modelMissing:
            return .modelMissing
        case .noAudioCaptured:
            return .modelNoAudioCaptured
        case .noSpeechDetected:
            return .modelNoSpeechDetected
        }
    }

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Download the dictation model."
        case .noAudioCaptured:
            return "No mic audio captured."
        case .noSpeechDetected:
            return "No speech found."
        }
    }
}
