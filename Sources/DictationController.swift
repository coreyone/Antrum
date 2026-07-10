import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class DictationController: NSObject, ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var modelStatus: DictationModelStatus
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var shortcutError: String?
    @Published var settings: DictationSettings {
        didSet {
            settings.save()
            if settings.requiresHotKeyRegistration(comparedTo: oldValue) {
                registerHotKey()
            }
        }
    }

    let isFeatureEnabled: Bool

    private let recorder = DictationAudioRecorder()
    private let modelManager = DictationModelManager()
    private let hotKeyManager = DictationHotKeyManager()
    private var insertionService = DictationInsertionService()
    private var recordingStartTask: Task<Void, Never>?
    private var recordingStartTaskID: UUID?
    private var processingTask: Task<Void, Never>?
    private var processingTaskID: UUID?
    private var modelDownloadTask: Task<Void, Never>?
    private var modelDownloadTaskID: UUID?
    private var hideHUDTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var hudWindow: NSPanel?
    private var shortcutRecorderMonitor: Any?
    private var shortcutRecorderModifierFlags: NSEvent.ModifierFlags = []
    private var terminationObserver: NSObjectProtocol?
    private var activeTemporaryAudioURL: URL?
    private var lastAudioLevelUpdate: Date?
    private var lastModelDownloadProgress: Double?

    var canStart: Bool {
        isFeatureEnabled && !state.isActive
    }

    var permissionStatusTitle: String {
        DictationInsertionService.isAccessibilityTrusted ? "Accessibility OK" : "Accessibility needed"
    }

    var microphonePermissionStatusTitle: String {
        DictationAudioRecorder.microphonePermissionTitle
    }

    var microphonePermissionActionTitle: String {
        DictationAudioRecorder.microphonePermissionActionTitle
    }

    var permissionSummaryTitle: String {
        let microphone = DictationAudioRecorder.isMicrophonePermissionReady ? "Mic OK" : "Mic needed"
        let accessibility = DictationInsertionService.isAccessibilityTrusted ? "Access OK" : "Access needed"
        return "\(microphone) · \(accessibility)"
    }

    var hasAllDictationPermissions: Bool {
        DictationAudioRecorder.isMicrophonePermissionReady
            && DictationInsertionService.isAccessibilityTrusted
    }

    init(
        isFeatureEnabled: Bool = FeatureFlags.dictation(),
        isModelInstalled: () -> Bool = { DictationModelManager.isInstalled() }
    ) {
        self.isFeatureEnabled = isFeatureEnabled
        self.settings = DictationSettings.load()
        self.modelStatus = isFeatureEnabled && isModelInstalled() ? .ready : .missing
        super.init()

        hotKeyManager.onActivate = { [weak self] in
            self?.handleShortcutActivation()
        }
        hotKeyManager.onShortcutReleased = { [weak self] in
            self?.handleShortcutReleased()
        }
        hotKeyManager.onCancel = { [weak self] in
            self?.cancel()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancel()
            }
        }

        if isFeatureEnabled {
            registerHotKey()
        }
    }

    deinit {
        recordingStartTask?.cancel()
        processingTask?.cancel()
        modelDownloadTask?.cancel()
        hideHUDTask?.cancel()
        recordingStartTaskID = nil
        processingTaskID = nil
        modelDownloadTaskID = nil
        MainActor.assumeIsolated {
            recorder.cancel()
            hotKeyManager.unregister()
            if let terminationObserver {
                NotificationCenter.default.removeObserver(terminationObserver)
            }
        }
    }

    func toggleFromMenu() {
        handleShortcutActivation()
    }

    func handleShortcutActivation() {
        guard isFeatureEnabled else { return }
        switch state {
        case .idle, .inserted, .canceled, .failed:
            start()
        case .listening:
            if settings.activationMode == .toggle {
                stopAndInsert()
            }
        case .processing:
            break
        }
    }

    func handleShortcutReleased() {
        guard settings.activationMode == .holdToTalk else { return }
        if case .listening = state {
            stopAndInsert()
        }
    }

    func start() {
        guard canStart else { return }
        guard DictationModelManager.isInstalled() else {
            modelStatus = .missing
            showSettings()
            state = .failed("Download model first.")
            showHUD()
            hideHUDSoon()
            return
        }

        recordingStartTask?.cancel()
        processingTask?.cancel()
        let recordingStartTaskID = UUID()
        self.recordingStartTaskID = recordingStartTaskID
        hideHUDTask?.cancel()
        hideHUDTask = nil
        state = .listening(startedAt: Date())
        audioLevel = 0
        lastAudioLevelUpdate = nil
        showHUD()
        hotKeyManager.startCancelMonitoring()
        NSSound(named: "Tink")?.play()

        recordingStartTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.recordingStartTaskID == recordingStartTaskID {
                    self.recordingStartTask = nil
                    self.recordingStartTaskID = nil
                }
            }
            do {
                try await self.recorder.start { [weak self] level in
                    Task { @MainActor in
                        self?.publishAudioLevel(level)
                    }
                }
                if Task.isCancelled || !self.state.isActive {
                    self.recorder.cancel()
                }
            } catch is CancellationError {
                self.recorder.cancel()
            } catch {
                self.recorder.cancel()
                self.state = .failed(error.localizedDescription)
                self.audioLevel = 0
                self.lastAudioLevelUpdate = nil
                self.hotKeyManager.stopCancelMonitoring()
                self.hideHUDSoon()
            }
        }
    }

    func stopAndInsert() {
        guard case .listening = state else { return }
        guard recorder.isRecording else {
            cancel()
            return
        }
        hotKeyManager.stopCancelMonitoring()
        state = .processing
        audioLevel = 0
        lastAudioLevelUpdate = nil

        let fileURL: URL
        do {
            fileURL = try recorder.stop()
            activeTemporaryAudioURL = fileURL
        } catch {
            state = .failed(error.localizedDescription)
            hideHUDSoon()
            return
        }

        let processingTaskID = UUID()
        self.processingTaskID = processingTaskID
        processingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: fileURL)
                self.activeTemporaryAudioURL = nil
                if self.processingTaskID == processingTaskID {
                    self.processingTask = nil
                    self.processingTaskID = nil
                }
            }
            do {
                let transcript = try await self.modelManager.transcribe(fileURL: fileURL)
                try await self.insertionService.insert(transcript)
                self.state = .inserted
                NSSound(named: "Tink")?.play()
            } catch is CancellationError {
                self.state = .canceled
            } catch {
                self.state = .failed(error.localizedDescription)
            }
            self.hideHUDSoon()
        }
    }

    func cancel() {
        let hasActiveWork = recordingStartTask != nil
            || processingTask != nil
            || recorder.isRecording
            || activeTemporaryAudioURL != nil
            || state.isActive
        guard hasActiveWork else { return }

        recordingStartTask?.cancel()
        recordingStartTask = nil
        recordingStartTaskID = nil
        processingTask?.cancel()
        processingTask = nil
        processingTaskID = nil
        recorder.cancel()
        if let activeTemporaryAudioURL {
            try? FileManager.default.removeItem(at: activeTemporaryAudioURL)
            self.activeTemporaryAudioURL = nil
        }
        hotKeyManager.stopCancelMonitoring()
        state = .canceled
        audioLevel = 0
        lastAudioLevelUpdate = nil
        hideHUDSoon()
    }

    func startModelDownload() {
        guard isFeatureEnabled else { return }
        guard modelStatus.canStartDownload else { return }
        modelStatus = .downloading(0)
        lastModelDownloadProgress = 0
        let modelDownloadTaskID = UUID()
        self.modelDownloadTaskID = modelDownloadTaskID
        modelDownloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.modelDownloadTaskID == modelDownloadTaskID {
                    self.modelDownloadTask = nil
                    self.modelDownloadTaskID = nil
                }
            }
            do {
                try await self.modelManager.download { [weak self] progress in
                    Task { @MainActor in
                        self?.publishModelDownloadProgress(progress)
                    }
                }
                try Task.checkCancellation()
                self.modelStatus = .ready
                self.lastModelDownloadProgress = nil
            } catch is CancellationError {
                self.modelStatus = .missing
                self.lastModelDownloadProgress = nil
            } catch {
                self.modelStatus = .failed(error.localizedDescription)
                self.lastModelDownloadProgress = nil
            }
        }
    }

    func requestAccessibilityPermission() {
        if DictationInsertionService.isAccessibilityTrusted {
            return
        }
        DictationInsertionService.requestAccessibilityPermission()
        DictationInsertionService.openAccessibilitySettings()
        objectWillChange.send()
    }

    func requestMicrophonePermission() {
        Task { [weak self] in
            if DictationAudioRecorder.microphonePermissionActionTitle == "Open Settings" {
                DictationAudioRecorder.openMicrophoneSettings()
            } else {
                _ = await DictationAudioRecorder.requestMicrophoneAccess()
            }
            await MainActor.run {
                self?.objectWillChange.send()
            }
        }
    }

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DictationSettingsView(controller: self)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Dictation Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: AppTheme.Dictation.settingsWidth, height: AppTheme.Dictation.settingsHeight))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func beginRecordingShortcut() {
        endRecordingShortcut()
        shortcutRecorderModifierFlags = []
        shortcutRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.shortcutRecorderModifierFlags = DictationShortcut.normalizedModifiers(from: event.modifierFlags)
                return nil
            }

            let modifierFlags = DictationShortcut.normalizedModifiers(from: event.modifierFlags)
                .union(self.shortcutRecorderModifierFlags)
            Task { @MainActor in
                if let shortcut = DictationShortcut.from(keyCode: UInt32(event.keyCode), modifierFlags: modifierFlags) {
                    self.settings.shortcut = shortcut
                    self.endRecordingShortcut()
                }
            }
            return nil
        }
    }

    func endRecordingShortcut() {
        if let shortcutRecorderMonitor {
            NSEvent.removeMonitor(shortcutRecorderMonitor)
            self.shortcutRecorderMonitor = nil
        }
        shortcutRecorderModifierFlags = []
    }

    func setShortcutPreset(_ shortcut: DictationShortcut) {
        settings.shortcut = shortcut
    }

    private func registerHotKey() {
        guard isFeatureEnabled else { return }
        do {
            try hotKeyManager.register(shortcut: settings.shortcut)
            shortcutError = nil
        } catch {
            shortcutError = error.localizedDescription
        }
    }

    private func publishAudioLevel(_ level: Double, now: Date = Date()) {
        guard case .listening = state else { return }
        guard DictationPerformance.shouldPublishTimedUpdate(lastUpdate: lastAudioLevelUpdate, now: now) else {
            return
        }
        audioLevel = max(0, min(1, level))
        lastAudioLevelUpdate = now
    }

    private func publishModelDownloadProgress(_ progress: Double) {
        let clampedProgress = max(0, min(1, progress))
        guard DictationPerformance.shouldPublishProgress(previous: lastModelDownloadProgress, next: clampedProgress) else {
            return
        }
        lastModelDownloadProgress = clampedProgress
        modelStatus = .downloading(clampedProgress)
    }

    private func showHUD() {
        hideHUDTask?.cancel()
        hideHUDTask = nil
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: AppTheme.Dictation.hudWidth,
                    height: AppTheme.Dictation.hudHeight
                ),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.contentViewController = NSHostingController(rootView: DictationHUDView(controller: self))
            hudWindow = panel
        }
        positionHUD()
        hudWindow?.orderFrontRegardless()
    }

    private func positionHUD() {
        guard let hudWindow else { return }
        let mouseLocation = NSEvent.mouseLocation
        let frame = Self.hudScreenFrame(containing: mouseLocation)
        let size = hudWindow.frame.size
        let origin = DictationHUDPlacement.origin(
            for: settings.hudPosition,
            screenFrame: frame,
            hudSize: size,
            mouseLocation: mouseLocation
        )
        hudWindow.setFrameOrigin(origin)
    }

    private static func hudScreenFrame(containing point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func hideHUDSoon() {
        hideHUDTask?.cancel()
        hideHUDTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.state.isActive else { return }
                self.hudWindow?.orderOut(nil)
                if self.state == .inserted || self.state == .canceled {
                    self.state = .idle
                }
                self.hideHUDTask = nil
            }
        }
    }
}

extension DictationController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
            endRecordingShortcut()
        }
    }
}
