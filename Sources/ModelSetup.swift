import FluidAudio
import Foundation

enum LocalModelPackageID: String, CaseIterable, Identifiable, Equatable, Sendable {
    case transcription
    case sortformer
    case pyannote

    var id: String { rawValue }
}

struct LocalModelPackage: Identifiable, Equatable, Sendable {
    let id: LocalModelPackageID
    let title: String
    let detail: String
    let estimatedSizeText: String
    let sourceText: String
    let symbolName: String
}

struct ModelSetupRequest: Identifiable, Equatable {
    let id = UUID()
    let diarizationBackend: DiarizationBackend
    let requiredPackageIDs: [LocalModelPackageID]
}

enum ModelDownloadState: Equatable {
    case notDownloaded
    case downloading(Double)
    case downloaded
    case failed(String)
}

enum LocalModelSetupPolicy {
    static let title = "Set Up Local Models"
    static let summary = "Models download from FluidAudio/Hugging Face only when you choose one, then run locally on this Mac. Meeting audio and transcript text are not uploaded."
}

enum LocalModelCatalog {
    static let packages: [LocalModelPackage] = [
        LocalModelPackage(
            id: .transcription,
            title: "Parakeet transcription",
            detail: "Turns meeting audio into text.",
            estimatedSizeText: "Approx. 500 MB",
            sourceText: "Downloads from FluidAudio/Hugging Face. Audio and transcripts are not uploaded.",
            symbolName: "text.quote"
        ),
        LocalModelPackage(
            id: .sortformer,
            title: "NVIDIA Sortformer",
            detail: "Labels remote speakers. Recommended.",
            estimatedSizeText: "Approx. 250 MB",
            sourceText: "Downloads from FluidAudio/Hugging Face. Audio and transcripts are not uploaded.",
            symbolName: "person.2"
        ),
        LocalModelPackage(
            id: .pyannote,
            title: "Pyannote Core ML",
            detail: "Alternative remote-speaker engine.",
            estimatedSizeText: "Approx. 25 MB",
            sourceText: "Downloads from FluidAudio/Hugging Face. Audio and transcripts are not uploaded.",
            symbolName: "person.2.badge.gearshape"
        )
    ]

    static func requiredPackageIDs(for backend: DiarizationBackend) -> [LocalModelPackageID] {
        switch backend {
        case .nvidiaSortformerV21:
            return [.transcription, .sortformer]
        case .pyannoteCoreML:
            return [.transcription, .pyannote]
        }
    }

    static func isInstalled(_ packageID: LocalModelPackageID, fileManager: FileManager = .default) -> Bool {
        switch packageID {
        case .transcription:
            return AsrModels.modelsExist(
                at: LocalModelStoragePolicy.defaultModelDirectory(for: .parakeetV3),
                version: .v3
            )
        case .sortformer:
            let modelURL = LocalModelStoragePolicy.defaultModelDirectory(for: .sortformer)
                .appendingPathComponent("Sortformer_v2.1.mlmodelc", isDirectory: true)
            return fileManager.fileExists(atPath: modelURL.path)
        case .pyannote:
            let root = LocalModelStoragePolicy.defaultModelsDirectory()
                .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
            let requiredFiles = [
                "Segmentation.mlmodelc",
                "FBank.mlmodelc",
                "Embedding.mlmodelc",
                "PldaRho.mlmodelc",
                "plda-parameters.json"
            ]
            return requiredFiles.allSatisfy {
                fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
            }
        }
    }

    static func isVADInstalled(fileManager: FileManager = .default) -> Bool {
        let modelURL = LocalModelStoragePolicy.defaultModelDirectory(for: .vad)
            .appendingPathComponent("silero-vad-unified-256ms-v6.0.0.mlmodelc", isDirectory: true)
        return fileManager.fileExists(atPath: modelURL.path)
    }
}

actor LocalModelDownloadManager {
    func download(
        _ packageID: LocalModelPackageID,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let progressHandler: ProgressHandler = { update in
            progress(max(0, min(1, update.fractionCompleted)))
        }

        try await FluidAudioDownloadGate.shared.withNetworkAccess {
            switch packageID {
            case .transcription:
                _ = try await AsrModels.download(
                    to: LocalModelStoragePolicy.defaultModelDirectory(for: .parakeetV3),
                    version: .v3,
                    progressHandler: progressHandler
                )
            case .sortformer:
                _ = try await SortformerModels.loadFromHuggingFace(
                    config: .fastV2_1,
                    cacheDirectory: LocalModelStoragePolicy.defaultModelsDirectory(),
                    progressHandler: progressHandler
                )
            case .pyannote:
                progress(0.1)
                let manager = OfflineDiarizerManager()
                try await manager.prepareModels(directory: LocalModelStoragePolicy.defaultModelsDirectory())
                progress(1)
            }
        }
    }
}
