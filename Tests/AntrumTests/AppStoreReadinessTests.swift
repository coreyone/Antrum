import Foundation
import FluidAudio
import Testing
@testable import Antrum

@Suite("App Store readiness")
struct AppStoreReadinessTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func recordingStorageUsesAntrumApplicationSupportInsteadOfDocuments() {
        let applicationSupport = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)

        let recordingsURL = RecordingStoragePolicy.recordingsDirectory(in: applicationSupport)

        #expect(recordingsURL.path == "/Library/Application Support/Antrum/Meetings Audio Recordings")
    }

    @Test
    func localModelStorageUsesAntrumApplicationSupportForUninstallCleanup() {
        let applicationSupport = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)

        let modelsURL = LocalModelStoragePolicy.modelsDirectory(in: applicationSupport)
        let dictationURL = LocalModelStoragePolicy.modelDirectory(for: .parakeetUnified, in: applicationSupport)

        #expect(modelsURL.path == "/Library/Application Support/Antrum/Models")
        #expect(dictationURL.path.hasPrefix("/Library/Application Support/Antrum/Models/"))
        #expect(!modelsURL.path.contains("/FluidAudio/"))
    }

    @Test
    func uninstallCleanupTargetsCoverSupportDataModelsRecordingsAndPreferences() {
        let library = URL(fileURLWithPath: "/Users/test/Library", isDirectory: true)

        let targets = AppUninstallPolicy.cleanupTargets(libraryDirectory: library).map(\.path)

        #expect(targets.contains("/Users/test/Library/Application Support/Antrum"))
        #expect(targets.contains("/Users/test/Library/Preferences/com.coreyoneal.Antrum.plist"))
        #expect(targets.contains {
            $0.hasPrefix("/Users/test/Library/Application Support/FluidAudio/Models/")
        })
    }

    @Test
    func legacyFluidAudioModelFoldersMigrateIntoAntrumSupport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntrumLegacyModelMigrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = LocalModelStoragePolicy.legacyModelDirectory(for: .parakeetUnified, in: root)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: legacy.appendingPathComponent("marker.bin"))

        let migrated = try LocalModelStoragePolicy.migrateLegacyModelDirectories(applicationSupportDirectory: root)
        let destination = LocalModelStoragePolicy.modelDirectory(for: .parakeetUnified, in: root)

        #expect(migrated == [destination])
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("marker.bin").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test
    func recordingConsentExplainsTheCaptureAndParticipantPermission() {
        #expect(RecordingConsentPolicy.message.contains("permission"))
        #expect(RecordingConsentPolicy.message.contains("microphone"))
        #expect(RecordingConsentPolicy.message.contains("meeting audio"))
        #expect(RecordingConsentPolicy.message.contains("locally"))
    }

    @Test
    func meetingDetectionCopyExplainsLocalPromptAndNoBot() {
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("microphone use"))
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("local recording"))
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("never joins calls"))
        #expect(!MeetingDetectionPolicy.localPrivacySummary.contains("automatically"))
    }

    @Test
    func appSandboxEntitlementsCoverAppStoreCapabilities() throws {
        let entitlementsURL = repositoryRoot.appendingPathComponent("Sources/Antrum.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        let requiredKeys = [
            "com.apple.security.app-sandbox",
            "com.apple.security.device.audio-input",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.network.client",
            "com.apple.security.personal-information.calendars"
        ]
        for key in requiredKeys {
            #expect(plist[key] as? Bool == true)
        }
    }

    @Test
    func infoPlistDoesNotRequestScreenCapturePurposeString() throws {
        let infoURL = repositoryRoot.appendingPathComponent("Sources/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        #expect(plist["NSScreenCaptureUsageDescription"] == nil)
        #expect((plist["NSMicrophoneUsageDescription"] as? String)?.contains("offline dictation") == true)
    }

    @Test
    func projectMetadataUsesProductivityCategoryAndSandboxEntitlements() throws {
        let projectYAML = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        #expect(projectYAML.contains("INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.productivity"))
        #expect(projectYAML.contains("com.apple.security.app-sandbox: true"))
        #expect(projectYAML.contains("com.apple.security.device.audio-input: true"))
        #expect(projectYAML.contains("com.apple.security.network.client: true"))
        #expect(!projectYAML.contains("NSScreenCaptureUsageDescription"))
    }

    @Test
    func publicDocsDiscloseLocalPromptDictationModelsAndNoScreenRecording() throws {
        let privacy = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PRIVACY.md"),
            encoding: .utf8
        )
        let notices = try String(
            contentsOf: repositoryRoot.appendingPathComponent("THIRD_PARTY_AND_MODEL_NOTICES.md"),
            encoding: .utf8
        )
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let combined = [privacy, notices, readme].joined(separator: "\n")

        #expect(combined.contains("FluidAudio/Hugging Face"))
        #expect(combined.contains("Dictation"))
        #expect(combined.contains("not uploaded"))
        #expect(combined.contains("does not join calls"))
        #expect(combined.contains("does not keep history"))
        #expect(!combined.contains("Screen Recording"))
        #expect(!combined.contains("record screen video"))
    }
}
