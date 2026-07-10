import Foundation
import FluidAudio

enum RecordingStoragePolicy {
    static let appSupportFolderName = "Antrum"

    static func appSupportDirectory(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    static func recordingsDirectory(in applicationSupportDirectory: URL) -> URL {
        appSupportDirectory(in: applicationSupportDirectory)
            .appendingPathComponent("Meetings Audio Recordings", isDirectory: true)
    }

    static func defaultAppSupportDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        return appSupportDirectory(in: applicationSupport)
    }

    static func defaultRecordingsDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        return recordingsDirectory(in: applicationSupport)
    }
}

enum LocalModelStoragePolicy {
    static let modelsFolderName = "Models"
    static let legacyVendorFolderName = "FluidAudio"

    static let ownedModelRepos: [Repo] = [
        .parakeetV3,
        .parakeetUnified,
        .sortformer,
        .diarizer,
        .vad
    ]

    static func modelsDirectory(in applicationSupportDirectory: URL) -> URL {
        RecordingStoragePolicy.appSupportDirectory(in: applicationSupportDirectory)
            .appendingPathComponent(modelsFolderName, isDirectory: true)
    }

    static func defaultModelsDirectory(fileManager: FileManager = .default) -> URL {
        RecordingStoragePolicy.defaultAppSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(modelsFolderName, isDirectory: true)
    }

    static func modelDirectory(for repo: Repo, in applicationSupportDirectory: URL) -> URL {
        modelsDirectory(in: applicationSupportDirectory)
            .appendingPathComponent(repo.folderName, isDirectory: true)
    }

    static func defaultModelDirectory(for repo: Repo, fileManager: FileManager = .default) -> URL {
        defaultModelsDirectory(fileManager: fileManager)
            .appendingPathComponent(repo.folderName, isDirectory: true)
    }

    static func legacyModelsDirectory(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(legacyVendorFolderName, isDirectory: true)
            .appendingPathComponent(modelsFolderName, isDirectory: true)
    }

    static func legacyModelDirectory(for repo: Repo, in applicationSupportDirectory: URL) -> URL {
        legacyModelsDirectory(in: applicationSupportDirectory)
            .appendingPathComponent(repo.folderName, isDirectory: true)
    }

    @discardableResult
    static func migrateLegacyModelDirectories(
        applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let applicationSupport = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        var migrated: [URL] = []

        for repo in ownedModelRepos {
            let legacy = legacyModelDirectory(for: repo, in: applicationSupport)
            guard fileManager.fileExists(atPath: legacy.path) else { continue }

            let destination = modelDirectory(for: repo, in: applicationSupport)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: legacy)
            } else {
                try fileManager.moveItem(at: legacy, to: destination)
            }
            migrated.append(destination)
        }

        return migrated
    }
}

enum AppUninstallPolicy {
    static let bundleIdentifier = "com.coreyoneal.Antrum"

    static func supportDirectory(in applicationSupportDirectory: URL) -> URL {
        RecordingStoragePolicy.appSupportDirectory(in: applicationSupportDirectory)
    }

    static func preferencesFile(in libraryDirectory: URL) -> URL {
        libraryDirectory
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).plist")
    }

    static func cleanupTargets(libraryDirectory: URL) -> [URL] {
        let applicationSupport = libraryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        return [
            supportDirectory(in: applicationSupport),
            preferencesFile(in: libraryDirectory)
        ] + LocalModelStoragePolicy.ownedModelRepos.map {
            LocalModelStoragePolicy.legacyModelDirectory(for: $0, in: applicationSupport)
        }
    }
}

enum AppStoreExternalResources {
    static let privacyPolicyURL = URL(string: "https://github.com/coreyone/Antrum/blob/main/PRIVACY.md")!
    static let supportURL = URL(string: "https://github.com/coreyone/Antrum/issues/new/choose")!
    static let modelNoticesURL = URL(string: "https://github.com/coreyone/Antrum/blob/main/THIRD_PARTY_AND_MODEL_NOTICES.md")!
}

enum LocalDataDeletionPolicy {
    static func deletionTargets(in applicationSupportDirectory: URL) -> [URL] {
        [RecordingStoragePolicy.appSupportDirectory(in: applicationSupportDirectory)]
            + LocalModelStoragePolicy.ownedModelRepos.map {
                LocalModelStoragePolicy.legacyModelDirectory(for: $0, in: applicationSupportDirectory)
            }
    }

    static func deleteAll(
        in applicationSupportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let applicationSupport = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )

        for target in deletionTargets(in: applicationSupport)
        where fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }
}

enum RecordingConsentPolicy {
    static let title = "Record This Meeting Locally?"
    static let confirmationAction = "Record Meeting"
    static let message = "Only record locally when you have permission from everyone involved. Antrum captures your microphone and meeting audio. REC remains visible in the menu bar and Dock while capture is active."
}
