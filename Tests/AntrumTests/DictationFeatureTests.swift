import AppKit
import AVFoundation
import Carbon
import FluidAudio
import Foundation
import Testing
@testable import Antrum

@Suite("Dictation feature")
struct DictationFeatureTests {
    @Test
    func featureFlagDefaultsOnAndHonorsDefaultsOverride() {
        let suiteName = "DictationFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(FeatureFlags.dictation(defaults: defaults, environment: [:]))

        defaults.set(false, forKey: FeatureFlags.dictationKey)
        #expect(!FeatureFlags.dictation(defaults: defaults, environment: [:]))
        defaults.set(true, forKey: FeatureFlags.dictationKey)
        #expect(FeatureFlags.dictation(defaults: defaults, environment: [:]))
    }

    @Test
    func featureFlagHonorsEnvironmentOverride() {
        let defaults = UserDefaults(suiteName: "DictationFeatureTests.\(UUID().uuidString)")!

        #expect(FeatureFlags.dictation(defaults: defaults, environment: ["ANTRUM_FEATURE_DICTATION": "true"]))
        #expect(!FeatureFlags.dictation(defaults: defaults, environment: ["ANTRUM_FEATURE_DICTATION": "false"]))
    }

    @Test
    func defaultShortcutUsesHyperOne() {
        let shortcut = DictationShortcut.defaultShortcut

        #expect(shortcut.keyCode == UInt32(kVK_ANSI_1))
        #expect(shortcut.carbonModifiers & UInt32(controlKey) != 0)
        #expect(shortcut.carbonModifiers & UInt32(optionKey) != 0)
        #expect(shortcut.carbonModifiers & UInt32(cmdKey) != 0)
        #expect(shortcut.displayName == "⌃⌥⌘1")
        #expect(shortcut.menuKeyEquivalent == "1")
        #expect(shortcut.menuModifierFlags == [.control, .option, .command])
    }

    @Test
    func shortcutRecordingKeepsOptionCommandNine() {
        let shortcut = DictationShortcut.from(
            keyCode: UInt32(kVK_ANSI_9),
            modifierFlags: [.option, .command]
        )

        #expect(shortcut?.displayName == "⌥⌘9")
        #expect(shortcut?.menuKeyEquivalent == "9")
        #expect(shortcut?.menuModifierFlags == [.option, .command])
    }

    @Test
    func shortcutRecordingNormalizesRawModifierBits() {
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | UInt(optionKey))
        let shortcut = DictationShortcut.from(keyCode: UInt32(kVK_ANSI_9), modifierFlags: flags)

        #expect(shortcut?.displayName == "⌥⌘9")
    }

    @Test
    func topCenterHUDPlacementCentersInsideGivenScreen() {
        let screenFrame = NSRect(x: 1_440, y: 0, width: 1_280, height: 800)
        let hudSize = NSSize(width: AppTheme.Dictation.hudWidth, height: AppTheme.Dictation.hudHeight)

        let origin = DictationHUDPlacement.origin(
            for: .topCenter,
            screenFrame: screenFrame,
            hudSize: hudSize,
            mouseLocation: NSPoint(x: 2_000, y: 400)
        )

        #expect(origin.x == screenFrame.midX - hudSize.width / 2)
        #expect(origin.y == screenFrame.maxY - hudSize.height - AppTheme.Dictation.hudTopInset)
    }

    @Test
    func cursorAdjacentHUDPlacementStaysInsideScreen() {
        let screenFrame = NSRect(x: 0, y: 0, width: 500, height: 260)
        let hudSize = NSSize(width: AppTheme.Dictation.hudWidth, height: AppTheme.Dictation.hudHeight)

        let origin = DictationHUDPlacement.origin(
            for: .cursorAdjacent,
            screenFrame: screenFrame,
            hudSize: hudSize,
            mouseLocation: NSPoint(x: 495, y: 12)
        )

        #expect(origin.x == screenFrame.maxX - hudSize.width)
        #expect(origin.y == screenFrame.minY)
    }

    @Test
    func settingsRoundTripShortcutAndActivationMode() throws {
        let suiteName = "DictationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = DictationSettings(
            activationMode: .holdToTalk,
            hudPosition: .cursorAdjacent,
            shortcut: .commandOptionD,
            streamingPreviewEnabled: true
        )
        settings.save(defaults: defaults)

        let loaded = DictationSettings.load(defaults: defaults)
        #expect(loaded.activationMode == settings.activationMode)
        #expect(loaded.hudPosition == settings.hudPosition)
        #expect(loaded.shortcut == settings.shortcut)
        #expect(!loaded.streamingPreviewEnabled)
    }

    @Test
    func settingsFallsBackToDefaultShortcutWhenPersistedShortcutIsInvalid() throws {
        let suiteName = "DictationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let invalidShortcut = DictationShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            carbonModifiers: UInt32(shiftKey)
        )
        defaults.set(try JSONEncoder().encode(invalidShortcut), forKey: DictationSettings.Keys.shortcut)

        #expect(DictationSettings.load(defaults: defaults).shortcut == .defaultShortcut)
    }

    @Test
    func settingsOnlyRequireHotKeyRegistrationWhenShortcutChanges() {
        let baseline = DictationSettings.defaults
        var behaviorOnlyChange = baseline
        behaviorOnlyChange.activationMode = .holdToTalk
        behaviorOnlyChange.hudPosition = .cursorAdjacent

        var shortcutChange = baseline
        shortcutChange.shortcut = .commandOptionD

        #expect(!behaviorOnlyChange.requiresHotKeyRegistration(comparedTo: baseline))
        #expect(shortcutChange.requiresHotKeyRegistration(comparedTo: baseline))
    }

    @MainActor
    @Test
    func disabledFeatureDoesNotCheckDictationModelFilesOnControllerInit() {
        var installCheckCount = 0
        _ = DictationController(isFeatureEnabled: false) {
            installCheckCount += 1
            return true
        }

        #expect(installCheckCount == 0)
    }

    @Test
    func shortcutValidationRequiresNonShiftModifierAndRealKey() {
        #expect(DictationShortcut.defaultShortcut.isValidGlobalShortcut)
        #expect(DictationShortcut.commandOptionD.isValidGlobalShortcut)
        #expect(!DictationShortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(shiftKey)).isValidGlobalShortcut)
        #expect(!DictationShortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0).isValidGlobalShortcut)
        #expect(!DictationShortcut(keyCode: UInt32(kVK_Shift), carbonModifiers: UInt32(cmdKey)).isValidGlobalShortcut)
    }

    @Test
    func modelDownloadProgressMenuTitleIsClamped() {
        #expect(DictationModelStatus.downloading(-0.2).menuTitle == "Model 0%")
        #expect(DictationModelStatus.downloading(0.42).menuTitle == "Model 42%")
        #expect(DictationModelStatus.downloading(1.4).menuTitle == "Model 100%")
    }

    @Test
    func modelDownloadCanOnlyStartFromRecoverableStates() {
        #expect(DictationModelStatus.missing.canStartDownload)
        #expect(DictationModelStatus.failed("Network unavailable").canStartDownload)
        #expect(!DictationModelStatus.downloading(0.2).canStartDownload)
        #expect(!DictationModelStatus.ready.canStartDownload)
    }

    @Test
    func dictationPerformanceThrottlesHighFrequencyAudioLevelUpdates() {
        let start = Date(timeIntervalSince1970: 100)

        #expect(DictationPerformance.shouldPublishTimedUpdate(lastUpdate: nil, now: start))
        #expect(!DictationPerformance.shouldPublishTimedUpdate(
            lastUpdate: start,
            now: start.addingTimeInterval(DictationPerformance.audioLevelMinimumInterval / 2)
        ))
        #expect(DictationPerformance.shouldPublishTimedUpdate(
            lastUpdate: start,
            now: start.addingTimeInterval(DictationPerformance.audioLevelMinimumInterval)
        ))
    }

    @Test
    func dictationPerformanceCoalescesModelDownloadProgressUpdates() {
        #expect(DictationPerformance.shouldPublishProgress(previous: nil, next: 0))
        #expect(!DictationPerformance.shouldPublishProgress(previous: 0, next: 0))
        #expect(!DictationPerformance.shouldPublishProgress(previous: 0.30, next: 0.304))
        #expect(DictationPerformance.shouldPublishProgress(previous: 0.30, next: 0.31))
        #expect(DictationPerformance.shouldPublishProgress(previous: 0.99, next: 1))
    }

    @Test
    func dictationPerformanceFiltersUnrelatedKeyUpEventsBeforeMainActorDispatch() throws {
        let matchingEvent = try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [.control, .option, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "1",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_1)
        ))
        let unrelatedEvent = try #require(NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "x",
            charactersIgnoringModifiers: "x",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_X)
        ))

        #expect(DictationPerformance.shouldDispatchShortcutRelease(event: matchingEvent, shortcut: .defaultShortcut))
        #expect(!DictationPerformance.shouldDispatchShortcutRelease(event: unrelatedEvent, shortcut: .defaultShortcut))
    }

    @MainActor
    @Test
    func cancelWhenIdleDoesNotPublishCanceledState() {
        let controller = DictationController(isFeatureEnabled: false) {
            Issue.record("Disabled dictation should not check model files.")
            return false
        }

        controller.cancel()

        #expect(controller.state == .idle)
    }

    @Test
    func modelStatusSettingsDetailGivesTheNextStep() {
        #expect(DictationModelStatus.missing.settingsDetail.contains("Download once"))
        #expect(DictationModelStatus.downloading(1.4).settingsDetail.contains("100%"))
        #expect(DictationModelStatus.ready.settingsDetail.contains("Local only"))
        #expect(DictationModelStatus.failed("Network unavailable").settingsDetail == "Network unavailable")
        #expect(DictationModelStatus.failed("").settingsDetail == "Download failed. Retry.")
    }

    @Test
    func dictationModelDisclosureNamesSizeSourceAndUploadBoundary() {
        #expect(DictationModelDisclosure.estimatedSizeText.contains("Approx."))
        #expect(DictationModelDisclosure.estimatedSizeText.contains("MB"))
        #expect(DictationModelDisclosure.sourceText.contains("FluidAudio/Hugging Face"))
        #expect(DictationModelDisclosure.sourceText.contains("not uploaded"))
    }

    @Test
    func dictationPreparationRejectsSilentAudioBeforeASR() {
        do {
            _ = try DictationModelManager.prepareSamplesForTranscription(Array(repeating: 0, count: 16_000))
            Issue.record("Expected silent dictation audio to be rejected before ASR.")
        } catch DictationModelError.noSpeechDetected {
            #expect(DictationModelError.noSpeechDetected.errorDescription == "No speech found.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func dictationPreparationKeepsQuietSpeechUsableForASR() throws {
        let sampleRate = 16_000
        let samples = (0..<(sampleRate * 2)).map { index in
            Float(sin(2 * Double.pi * 220 * Double(index) / Double(sampleRate)) * 0.012)
        }

        let prepared = try DictationModelManager.prepareSamplesForTranscription(samples)

        #expect(prepared.count == samples.count)
        #expect((prepared.map(abs).max() ?? 0) > 0.012)
    }

    @Test
    func dictationRecorderUsesMonoFloatFileFormatForASR() throws {
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        )!

        let recordingFormat = try DictationAudioRecorder.recordingFormat(for: inputFormat)

        #expect(recordingFormat.commonFormat == .pcmFormatFloat32)
        #expect(recordingFormat.sampleRate == inputFormat.sampleRate)
        #expect(recordingFormat.channelCount == 1)
        #expect(!recordingFormat.isInterleaved)
    }

    @MainActor
    @Test
    func insertionServiceRestoresPasteboardAfterPaste() async throws {
        let pasteboard = MockPasteboardStore(
            current: PasteboardSnapshot(items: [
                PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
            ])
        )
        let keyboard = MockKeyboardPaster()
        let service = DictationInsertionService(
            pasteboard: pasteboard,
            keyboard: keyboard,
            restoreDelay: 0,
            accessibilityTrusted: { true },
            requestAccessibility: {}
        )

        try await service.insert("new text")

        #expect(keyboard.pasteCount == 1)
        #expect(pasteboard.current == PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
        ]))
    }

    @MainActor
    @Test
    func insertionServiceReportsNoTextForEmptyTranscript() async throws {
        let original = PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
        ])
        let pasteboard = MockPasteboardStore(current: original)
        let keyboard = MockKeyboardPaster()
        let service = DictationInsertionService(
            pasteboard: pasteboard,
            keyboard: keyboard,
            restoreDelay: 0,
            accessibilityTrusted: { true },
            requestAccessibility: {}
        )

        do {
            try await service.insert("   ")
            Issue.record("Expected insertion to reject an empty transcript.")
        } catch DictationInsertionError.emptyTranscript {
            #expect(DictationInsertionError.emptyTranscript.errorDescription == "No text detected.")
            #expect(keyboard.pasteCount == 0)
            #expect(pasteboard.current == original)
        }
    }

    @MainActor
    @Test
    func insertionServiceRestoresPasteboardAndThrowsWhenCanceledDuringPasteDelay() async throws {
        let original = PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
        ])
        let pasteboard = MockPasteboardStore(current: original)
        let keyboard = MockKeyboardPaster()
        let service = DictationInsertionService(
            pasteboard: pasteboard,
            keyboard: keyboard,
            restoreDelay: 5_000_000_000,
            accessibilityTrusted: { true },
            requestAccessibility: {}
        )

        let task = Task {
            try await service.insert("new text")
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected insertion to throw CancellationError.")
        } catch is CancellationError {
            #expect(keyboard.pasteCount == 1)
            #expect(pasteboard.current == original)
        }
    }

    @MainActor
    @Test
    func insertionServicePreservesClipboardChangesMadeDuringPasteDelay() async throws {
        let original = PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
        ])
        let pasteboard = MockPasteboardStore(current: original)
        let keyboard = MockKeyboardPaster()
        let service = DictationInsertionService(
            pasteboard: pasteboard,
            keyboard: keyboard,
            restoreDelay: 50_000_000,
            accessibilityTrusted: { true },
            requestAccessibility: {}
        )

        let insertion = Task {
            try await service.insert("dictated")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        pasteboard.copyExternally("new clipboard value")

        try await insertion.value

        #expect(keyboard.pasteCount == 1)
        #expect(pasteboard.current == PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("new clipboard value".utf8))])
        ]))
    }

    @MainActor
    @Test
    func insertionServiceDoesNotChangePasteboardWhenAccessibilityIsMissing() async throws {
        let original = PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
        ])
        let pasteboard = MockPasteboardStore(current: original)
        let keyboard = MockKeyboardPaster()
        var requestedPermission = false
        let service = DictationInsertionService(
            pasteboard: pasteboard,
            keyboard: keyboard,
            restoreDelay: 0,
            accessibilityTrusted: { false },
            requestAccessibility: { requestedPermission = true }
        )

        do {
            try await service.insert("new text")
            Issue.record("Expected insertion to require Accessibility permission.")
        } catch DictationInsertionError.accessibilityPermissionRequired {
            #expect(requestedPermission)
            #expect(keyboard.pasteCount == 0)
            #expect(pasteboard.current == original)
        }
    }

    @MainActor
    @Test
    func insertionServiceRestoresPasteboardWhenKeyboardPasteFails() async throws {
        let original = PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data("old".utf8))])
        ])
        let pasteboard = MockPasteboardStore(current: original)
        let keyboard = MockKeyboardPaster(error: DictationInsertionError.pasteFailed)
        let service = DictationInsertionService(
            pasteboard: pasteboard,
            keyboard: keyboard,
            restoreDelay: 0,
            accessibilityTrusted: { true },
            requestAccessibility: {}
        )

        do {
            try await service.insert("new text")
            Issue.record("Expected insertion to restore pasteboard and throw paste failure.")
        } catch DictationInsertionError.pasteFailed {
            #expect(keyboard.pasteCount == 1)
            #expect(pasteboard.current == original)
        }
    }

    @Test
    func dictationStateContractMatchesMenuAndActivityRules() {
        #expect(!DictationState.idle.isActive)
        #expect(DictationState.idle.menuTitle == "Start Dictation")
        #expect(DictationState.idle.hudDetail == "Ready")
        #expect(DictationState.listening(startedAt: Date()).isActive)
        #expect(DictationState.listening(startedAt: Date()).menuTitle == "Stop Dictation")
        #expect(DictationState.listening(startedAt: Date()).hudDetail == "Esc")
        #expect(DictationState.processing.isActive)
        #expect(DictationState.processing.menuTitle == "Processing")
        #expect(DictationState.processing.hudDetail == "Offline")
        #expect(!DictationState.canceled.isActive)
        #expect(DictationState.canceled.statusTitle == "Canceled")
        #expect(!DictationState.failed("x").isActive)
        #expect(DictationState.failed("x").statusTitle == "Check Settings")
        #expect(DictationState.failed("A very long dictation failure message that would otherwise crowd the HUD").hudDetail.count <= 32)
    }

    @Test
    func dictationModelStatusRequiresUnifiedOfflineAssets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntrumDictationModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(!DictationModelManager.isInstalled(modelsRoot: root))

        for fileName in ModelNames.ParakeetUnified.requiredModels(variant: "offline") {
            let url = root.appendingPathComponent(fileName)
            if fileName.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data("test".utf8).write(to: url)
            }
        }

        #expect(DictationModelManager.isInstalled(modelsRoot: root))
    }

    @Test
    func dictationModelDefaultRootUsesAntrumOwnedModelStorage() {
        let path = DictationModelManager.defaultModelRoot.path

        #expect(path.contains("/Application Support/Antrum/Models/"))
        #expect(!path.contains("/Application Support/FluidAudio/"))
    }
}

private final class MockPasteboardStore: PasteboardStoring {
    var current: PasteboardSnapshot
    private var changeCount = 0

    init(current: PasteboardSnapshot) {
        self.current = current
    }

    func snapshot() -> PasteboardSnapshot {
        current
    }

    func replaceWithString(_ string: String) -> Int {
        current = PasteboardSnapshot(items: [
            PasteboardSnapshot.Item(values: [(.string, Data(string.utf8))])
        ])
        changeCount += 1
        return changeCount
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountMatches expectedChangeCount: Int) {
        guard changeCount == expectedChangeCount else { return }
        current = snapshot
        changeCount += 1
    }

    func copyExternally(_ string: String) {
        _ = replaceWithString(string)
    }
}

private final class MockKeyboardPaster: KeyboardPasting {
    var pasteCount = 0
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func paste() throws {
        pasteCount += 1
        if let error {
            throw error
        }
    }
}
