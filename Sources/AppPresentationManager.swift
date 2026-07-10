import SwiftUI
import AppKit
import Combine
import ServiceManagement
import OSLog

enum AppPresentationMode: String, CaseIterable, Identifiable {
    case dockOnly = "dockOnly"
    case menuBarOnly = "menuBarOnly"
    case both = "both"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dockOnly: return "Dock Only"
        case .menuBarOnly: return "Menu Bar Only"
        case .both: return "Both"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .dockOnly: return "Dock"
        case .menuBarOnly: return "Menu Bar"
        case .both: return "Both"
        }
    }
}

@MainActor
final class AppPresentationManager: NSObject, ObservableObject {
    @Published var mode: AppPresentationMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.preferenceKey)
            applyMode()
        }
    }

    @Published var launchAtStartup: Bool {
        didSet {
            setLaunchAtStartup(launchAtStartup)
        }
    }

    var onRecordMeeting: (() -> Void)?
    var onTranscribeFile: (() -> Void)?
    var onPauseRecording: (() -> Void)?
    var onResumeRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onOpenMainWindow: (() -> Void)?

    private static let preferenceKey = "AppPresentationMode"
    private var statusItem: NSStatusItem?
    private var recordingState: LiveRecordingState = .idle
    private weak var dictationController: DictationController?
    private weak var meetingDetectionController: MeetingDetectionController?
    private weak var mainWindow: NSWindow?
    private var dictationCancellables: Set<AnyCancellable> = []
    private var meetingDetectionCancellables: Set<AnyCancellable> = []
    private var dictationMenuBarAnimationTimer: Timer?
    private var dictationMenuBarAnimationFrame = 0
    private static let statusMenuMinimumWidth: CGFloat = 220
    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("AntrumMainWindow")
    private static let logger = Logger(subsystem: "com.coreyoneal.Antrum", category: "presentation")

    override init() {
        let savedMode = UserDefaults.standard.string(forKey: Self.preferenceKey)
            .flatMap(AppPresentationMode.init(rawValue:))
        self.mode = savedMode ?? .menuBarOnly
        self.launchAtStartup = SMAppService.mainApp.status == .enabled
        super.init()
        applyMode()
    }

    func applyMode() {
        switch mode {
        case .dockOnly:
            NSApp.setActivationPolicy(.regular)
            removeStatusItem()
        case .menuBarOnly:
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem()
        case .both:
            NSApp.setActivationPolicy(.regular)
            setupStatusItem()
        }

        updateMenuCheckmarks()
    }

    func configureDictation(_ controller: DictationController) {
        guard dictationController !== controller else { return }
        dictationController = controller
        dictationCancellables.removeAll()
        controller.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateDictationIndicators()
                }
            }
            .store(in: &dictationCancellables)
        rebuildStatusMenu()
    }

    func configureMeetingDetection(_ controller: MeetingDetectionController) {
        guard meetingDetectionController !== controller else { return }
        meetingDetectionController = controller
        meetingDetectionCancellables.removeAll()
        controller.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMeetingDetectionIndicators()
                }
            }
            .store(in: &meetingDetectionCancellables)
        rebuildStatusMenu()
    }

    private func setLaunchAtStartup(_ enabled: Bool) {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                do {
                    try service.register()
                } catch {
                    Self.logger.error("Failed to register SMAppService: \(String(describing: error), privacy: .private)")
                }
            }
        } else {
            if service.status == .enabled {
                do {
                    try service.unregister()
                } catch {
                    Self.logger.error("Failed to unregister SMAppService: \(String(describing: error), privacy: .private)")
                }
            }
        }
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Antrum")
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        let menu = makeStatusMenu()
        item.menu = menu
        statusItem = item
        updateMenuCheckmarks()
        updateRecordingIndicators()
        updateDictationIndicators()
    }

    private func rebuildStatusMenu() {
        guard let item = statusItem else { return }
        item.menu = makeStatusMenu()
        updateMenuCheckmarks()
        updateRecordingIndicators()
        updateDictationIndicators()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = Self.statusMenuMinimumWidth

        let showItem = NSMenuItem(title: "Show Antrum", action: #selector(showAppWindow), keyEquivalent: "o")
        showItem.target = self
        menu.addItem(showItem)

        let transcribeFileItem = NSMenuItem(title: "Transcribe File", action: #selector(transcribeFileFromMenu), keyEquivalent: "t")
        transcribeFileItem.target = self
        menu.addItem(transcribeFileItem)

        let detectedMeetingItem = NSMenuItem(title: "Detected microphone use", action: #selector(recordDetectedMeetingFromMenu), keyEquivalent: "")
        detectedMeetingItem.target = self
        detectedMeetingItem.representedObject = MeetingDetectionMenuItemID.prompt.rawValue as NSString
        detectedMeetingItem.isHidden = true
        menu.addItem(detectedMeetingItem)

        if dictationController?.isFeatureEnabled == true {
            menu.addItem(NSMenuItem.separator())

            let dictationStatusItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
            dictationStatusItem.isEnabled = false
            dictationStatusItem.representedObject = DictationMenuItemID.status.rawValue as NSString
            menu.addItem(dictationStatusItem)

            let dictationItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictationFromMenu), keyEquivalent: "")
            dictationItem.target = self
            if let shortcut = dictationController?.settings.shortcut {
                configureDictationShortcut(shortcut, for: dictationItem)
            }
            menu.addItem(dictationItem)

            let settingsItem = NSMenuItem(title: "Dictation Settings", action: #selector(showDictationSettingsFromMenu), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)

            let modelItem = NSMenuItem(title: "Model missing", action: nil, keyEquivalent: "")
            modelItem.isEnabled = false
            modelItem.representedObject = DictationMenuItemID.model.rawValue as NSString
            menu.addItem(modelItem)

            let permissionItem = NSMenuItem(title: "Mic needed · Access needed", action: nil, keyEquivalent: "")
            permissionItem.isEnabled = false
            permissionItem.representedObject = DictationMenuItemID.permission.rawValue as NSString
            menu.addItem(permissionItem)
        }

        menu.addItem(NSMenuItem.separator())

        let recordItem = NSMenuItem(title: "Record Meeting", action: #selector(recordMeetingFromMenu), keyEquivalent: "r")
        recordItem.target = self
        recordItem.representedObject = RecordingMenuItemID.record.rawValue as NSString
        menu.addItem(recordItem)

        let pauseItem = NSMenuItem(title: "Pause", action: #selector(pauseRecordingFromMenu), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.representedObject = RecordingMenuItemID.pause.rawValue as NSString
        pauseItem.isEnabled = false
        menu.addItem(pauseItem)

        let resumeItem = NSMenuItem(title: "Resume", action: #selector(resumeRecordingFromMenu), keyEquivalent: "")
        resumeItem.target = self
        resumeItem.representedObject = RecordingMenuItemID.resume.rawValue as NSString
        resumeItem.isEnabled = false
        menu.addItem(resumeItem)

        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopRecordingFromMenu), keyEquivalent: "")
        stopItem.target = self
        stopItem.representedObject = RecordingMenuItemID.stop.rawValue as NSString
        stopItem.isEnabled = false
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let configMenuItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let configSubmenu = NSMenu()
        for option in AppPresentationMode.allCases {
            let subItem = NSMenuItem(title: option.displayName, action: #selector(changeModeFromMenu(_:)), keyEquivalent: "")
            subItem.representedObject = option.rawValue as AnyObject
            subItem.target = self
            configSubmenu.addItem(subItem)
        }
        configMenuItem.submenu = configSubmenu
        menu.addItem(configMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func removeStatusItem() {
        stopDictationMenuBarAnimation(resetIcon: false)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateMenuCheckmarks() {
        guard let item = statusItem, let menu = item.menu else { return }
        if let appearanceItem = menu.items.first(where: { $0.title == "Appearance" }),
           let submenu = appearanceItem.submenu {
            for subItem in submenu.items {
                if let rawStr = subItem.representedObject as? String,
                   let option = AppPresentationMode(rawValue: rawStr) {
                    subItem.state = (option == mode) ? .on : .off
                }
            }
        }
    }

    func updateRecordingState(_ state: LiveRecordingState) {
        recordingState = state
        updateRecordingIndicators()
    }

    func configureMainWindow(
        _ window: NSWindow,
        mode: MeetingTranscriptionViewModel.ViewMode,
        hasModelSetup: Bool
    ) {
        mainWindow = window
        window.identifier = Self.mainWindowIdentifier
        window.delegate = self
        updateMainWindowSize(for: mode, hasModelSetup: hasModelSetup, animated: false)
    }

    func updateMainWindowSize(
        for mode: MeetingTranscriptionViewModel.ViewMode,
        hasModelSetup: Bool,
        animated: Bool = true
    ) {
        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        mainWindow = window

        let minimumContentSize = AppWindowSizePolicy.minimumContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size

        let targetContentSize = AppWindowSizePolicy.contentSize(for: mode, hasModelSetup: hasModelSetup)
        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        guard abs(currentContentSize.width - targetContentSize.width) > 1
            || abs(currentContentSize.height - targetContentSize.height) > 1 else {
            return
        }

        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
        var targetFrame = window.frame
        targetFrame.origin.y = targetFrame.maxY - targetFrameSize.height
        targetFrame.size = targetFrameSize
        targetFrame = Self.clampedFrame(targetFrame, to: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        window.setFrame(targetFrame, display: true, animate: animated)
    }

    private func updateRecordingIndicators() {
        NSApp.dockTile.badgeLabel = recordingState.dockBadge
        guard let item = statusItem else { return }

        if let button = item.button {
            let presentation = recordingState.menuBarPresentation
            button.image = NSImage.menuBarRecordingIcon(for: presentation)
            button.title = presentation.title
            button.contentTintColor = presentation.tint.nsColor
        }

        guard let menu = item.menu else { return }
        menu.recordingItem(id: .record)?.isEnabled = !recordingState.isActive
        menu.recordingItem(id: .pause)?.isEnabled = recordingState.canPauseOrResume && !recordingState.isPaused
        menu.recordingItem(id: .resume)?.isEnabled = recordingState.isPaused
        menu.recordingItem(id: .stop)?.isEnabled = recordingState.canStop
        updateDictationIndicators()
    }

    private func updateDictationIndicators() {
        guard let controller = dictationController,
              controller.isFeatureEnabled,
              let item = statusItem,
              let menu = item.menu else {
            updateMeetingDetectionIndicators()
            return
        }

        if let statusItem = menu.dictationItem(id: .status) {
            statusItem.title = controller.state.statusTitle
            statusItem.isHidden = controller.state.statusTitle == "Ready"
        }
        let dictationItem = menu.items.first { $0.action == #selector(toggleDictationFromMenu) }
        dictationItem?.title = controller.state.menuTitle
        dictationItem?.isEnabled = controller.state != .processing
        if let dictationItem {
            configureDictationShortcut(controller.settings.shortcut, for: dictationItem)
        }

        if let modelItem = menu.dictationItem(id: .model) {
            modelItem.title = controller.modelStatus.menuTitle
            modelItem.isHidden = controller.modelStatus == .ready
        }

        if let permissionItem = menu.dictationItem(id: .permission) {
            permissionItem.title = controller.permissionSummaryTitle
            permissionItem.isHidden = controller.hasAllDictationPermissions
        }

        setActivityMenuBarPresentation(isDictationActive: controller.state.isActive)
    }

    private func updateMeetingDetectionIndicators() {
        guard let item = statusItem,
              let menu = item.menu else {
            return
        }

        if let promptItem = menu.meetingDetectionItem(id: .prompt) {
            if let snapshot = meetingDetectionController?.promptState.snapshot {
                promptItem.title = snapshot.menuTitle
                promptItem.isHidden = false
                promptItem.isEnabled = !recordingState.isActive
            } else {
                promptItem.title = "Detected microphone use"
                promptItem.isHidden = true
                promptItem.isEnabled = false
            }
        }

        let isDictationActive = dictationController?.state.isActive == true
        setActivityMenuBarPresentation(isDictationActive: isDictationActive)
    }

    private func setActivityMenuBarPresentation(isDictationActive: Bool) {
        guard let button = statusItem?.button, !recordingState.isActive else {
            stopDictationMenuBarAnimation(resetIcon: false)
            return
        }

        button.title = ""
        button.contentTintColor = nil

        switch MenuBarActivityPriority.current(
            recordingState: recordingState,
            isDictationActive: isDictationActive,
            isMeetingDetectionVisible: meetingDetectionController?.isPromptVisible == true
        ) {
        case .recording:
            stopDictationMenuBarAnimation(resetIcon: false)
        case .dictation:
            startDictationMenuBarAnimation()
        case .meetingDetection:
            stopDictationMenuBarAnimation(resetIcon: false)
            button.image = NSImage.rainbowWaveformIcon(
                accessibilityDescription: "Meeting-capable app using microphone"
            )
        case .idle:
            stopDictationMenuBarAnimation(resetIcon: true)
        }
    }

    private func startDictationMenuBarAnimation() {
        guard dictationMenuBarAnimationTimer == nil else { return }
        dictationMenuBarAnimationFrame = 0
        updateDictationMenuBarAnimationFrame()

        let timer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceDictationMenuBarAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dictationMenuBarAnimationTimer = timer
    }

    private func advanceDictationMenuBarAnimation() {
        dictationMenuBarAnimationFrame += 1
        updateDictationMenuBarAnimationFrame()
    }

    private func updateDictationMenuBarAnimationFrame() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.contentTintColor = nil
        button.image = NSImage.rainbowWaveformIcon(
            accessibilityDescription: "Dictation active",
            phase: dictationMenuBarAnimationFrame
        )
    }

    private func stopDictationMenuBarAnimation(resetIcon: Bool) {
        dictationMenuBarAnimationTimer?.invalidate()
        dictationMenuBarAnimationTimer = nil
        dictationMenuBarAnimationFrame = 0

        guard resetIcon, let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Antrum")
        button.title = ""
        button.contentTintColor = nil
    }

    private static func clampedFrame(_ frame: NSRect, to visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else { return frame }
        var clamped = frame

        if clamped.width > visibleFrame.width {
            clamped.size.width = visibleFrame.width
        }
        if clamped.height > visibleFrame.height {
            clamped.size.height = visibleFrame.height
        }
        if clamped.minX < visibleFrame.minX {
            clamped.origin.x = visibleFrame.minX
        }
        if clamped.maxX > visibleFrame.maxX {
            clamped.origin.x = visibleFrame.maxX - clamped.width
        }
        if clamped.minY < visibleFrame.minY {
            clamped.origin.y = visibleFrame.minY
        }
        if clamped.maxY > visibleFrame.maxY {
            clamped.origin.y = visibleFrame.maxY - clamped.height
        }

        return clamped
    }

    private func configureDictationShortcut(_ shortcut: DictationShortcut, for item: NSMenuItem) {
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.menuModifierFlags
        item.toolTip = shortcut.menuKeyEquivalent.isEmpty ? shortcut.displayName : nil
    }

    @objc private func statusItemClicked() {
        // macOS handles showing the menu automatically
    }

    @objc private func showAppWindow() {
        presentMainWindow()
    }

    func presentMainWindow() {
        let hadCandidate = !mainWindowCandidates().isEmpty
        if !hadCandidate {
            onOpenMainWindow?()
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentExistingMainWindow()
        }

        if !hadCandidate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.presentExistingMainWindow()
            }
        }
    }

    private func presentExistingMainWindow() {
        let candidates = mainWindowCandidates()
        guard !candidates.isEmpty else { return }

        NSApp.unhide(nil)
        for window in candidates {
            presentWindowToFront(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func mainWindowCandidates() -> [NSWindow] {
        var candidates: [NSWindow] = []
        var seen = Set<ObjectIdentifier>()

        func append(_ window: NSWindow?) {
            guard let window, window.canBecomeMain else { return }
            let id = ObjectIdentifier(window)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            candidates.append(window)
        }

        append(mainWindow)
        NSApp.windows
            .filter { $0.identifier == Self.mainWindowIdentifier }
            .forEach { append($0) }

        if candidates.isEmpty {
            NSApp.windows
                .filter { $0.canBecomeMain && !($0 is NSPanel) }
                .forEach { append($0) }
        }

        return candidates
    }

    private func presentWindowToFront(_ window: NSWindow) {
        let originalCollectionBehavior = window.collectionBehavior
        window.collectionBehavior.insert(.moveToActiveSpace)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        if originalCollectionBehavior != window.collectionBehavior {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak window] in
                window?.collectionBehavior = originalCollectionBehavior
            }
        }
    }

    @objc private func changeModeFromMenu(_ sender: NSMenuItem) {
        if let rawStr = sender.representedObject as? String,
           let option = AppPresentationMode(rawValue: rawStr) {
            self.mode = option
        }
    }

    @objc private func recordMeetingFromMenu() {
        showAppWindow()
        onRecordMeeting?()
    }

    @objc private func transcribeFileFromMenu() {
        showAppWindow()
        onTranscribeFile?()
    }

    @objc private func recordDetectedMeetingFromMenu() {
        showAppWindow()
        meetingDetectionController?.recordFromPrompt()
    }

    @objc private func pauseRecordingFromMenu() {
        onPauseRecording?()
    }

    @objc private func resumeRecordingFromMenu() {
        onResumeRecording?()
    }

    @objc private func stopRecordingFromMenu() {
        onStopRecording?()
    }

    @objc private func toggleDictationFromMenu() {
        dictationController?.toggleFromMenu()
    }

    @objc private func showDictationSettingsFromMenu() {
        dictationController?.showSettings()
    }

    @objc private func quitApp() {
        AppDelegate.isTerminating = true
        NSApp.terminate(nil)
    }
}

private enum DictationMenuItemID: String {
    case status
    case model
    case permission
}

private enum MeetingDetectionMenuItemID: String {
    case prompt
}

private enum RecordingMenuItemID: String {
    case record
    case pause
    case resume
    case stop
}

private extension MenuBarRecordingTint {
    var nsColor: NSColor? {
        switch self {
        case .none:
            return nil
        case .accent:
            return .controlAccentColor
        case .red:
            return .systemRed
        }
    }
}

private extension NSImage {
    static func menuBarRecordingIcon(for presentation: MenuBarRecordingPresentation) -> NSImage? {
        switch presentation.iconStyle {
        case .monochromeWaveform:
            return NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: presentation.accessibilityDescription
            )
        case .rainbowWaveform:
            return rainbowWaveformIcon(accessibilityDescription: presentation.accessibilityDescription)
        }
    }

    static func rainbowWaveformIcon(accessibilityDescription: String, phase: Int = 0) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        image.lockFocus()
        defer { image.unlockFocus() }

        let baseColors = [
            NSColor(red: 1.00, green: 0.24, blue: 0.34, alpha: 1),
            NSColor(red: 1.00, green: 0.56, blue: 0.16, alpha: 1),
            NSColor(red: 0.96, green: 0.82, blue: 0.18, alpha: 1),
            NSColor(red: 0.24, green: 0.80, blue: 0.45, alpha: 1),
            NSColor(red: 0.12, green: 0.72, blue: 0.90, alpha: 1),
            NSColor(red: 0.36, green: 0.50, blue: 1.00, alpha: 1),
            NSColor(red: 0.76, green: 0.36, blue: 1.00, alpha: 1)
        ]
        let colors = baseColors.indices.map { index in
            baseColors[(index + phase) % baseColors.count]
        }
        let barWidths = Array(repeating: CGFloat(2), count: colors.count)
        let spacing: CGFloat = 1
        let totalWidth = barWidths.reduce(0, +) + spacing * CGFloat(colors.count - 1)
        var x = (size.width - totalWidth) / 2
        let heights: [CGFloat] = [6, 10, 14, 16, 12, 9, 6]

        for index in colors.indices {
            let height = heights[index]
            let y = (size.height - height) / 2
            let rect = NSRect(x: x, y: y, width: barWidths[index], height: height)
            colors[index].setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            x += barWidths[index] + spacing
        }

        return image
    }
}

private extension NSMenu {
    func meetingDetectionItem(id: MeetingDetectionMenuItemID) -> NSMenuItem? {
        items.first { ($0.representedObject as? String) == id.rawValue }
    }

    func dictationItem(id: DictationMenuItemID) -> NSMenuItem? {
        items.first { ($0.representedObject as? String) == id.rawValue }
    }

    func recordingItem(id: RecordingMenuItemID) -> NSMenuItem? {
        items.first { ($0.representedObject as? String) == id.rawValue }
    }
}

extension AppPresentationManager: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if AppDelegate.isTerminating {
            return true
        }
        sender.orderOut(nil)
        return false
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var isTerminating = false
    static var prepareForTermination: (() async -> Void)?
    static var presentMainWindow: (() -> Void)?
    private var isPreparingForTermination = false

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.isTerminating = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingForTermination else {
            return .terminateLater
        }

        AppDelegate.isTerminating = true
        isPreparingForTermination = true
        Task { @MainActor in
            await AppDelegate.prepareForTermination?()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppDelegate.presentMainWindow?()
        }
        return true
    }
}
