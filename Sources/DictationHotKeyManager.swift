import AppKit
import Carbon

@MainActor
final class DictationHotKeyManager {
    var onActivate: (() -> Void)?
    var onShortcutReleased: (() -> Void)?
    var onCancel: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var cancelHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var keyUpMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?
    private var shortcut: DictationShortcut = .defaultShortcut
    private var registeredShortcut: DictationShortcut?

    func register(shortcut: DictationShortcut) throws {
        guard shortcut.isValidGlobalShortcut else {
            throw DictationHotKeyError.invalidShortcut
        }
        guard registeredShortcut != shortcut || hotKeyRef == nil || eventHandlerRef == nil else {
            return
        }
        unregister()
        self.shortcut = shortcut
        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.activationHotKeyID)
        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard hotKeyStatus == noErr else {
            throw DictationHotKeyError.registrationFailed(hotKeyStatus)
        }

        let shortcutForRelease = shortcut
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard DictationPerformance.shouldDispatchShortcutRelease(event: event, shortcut: shortcutForRelease) else {
                return
            }
            Task { @MainActor in
                self?.onShortcutReleased?()
            }
        }
        registeredShortcut = shortcut
    }

    func startCancelMonitoring() {
        stopCancelMonitoring()
        registerEscapeHotKeyIfPossible()
        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in self?.onCancel?() }
        }
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            Task { @MainActor in self?.onCancel?() }
            return nil
        }
    }

    func stopCancelMonitoring() {
        if let cancelHotKeyRef {
            UnregisterEventHotKey(cancelHotKeyRef)
            self.cancelHotKeyRef = nil
        }
        if let escapeGlobalMonitor {
            NSEvent.removeMonitor(escapeGlobalMonitor)
            self.escapeGlobalMonitor = nil
        }
        if let escapeLocalMonitor {
            NSEvent.removeMonitor(escapeLocalMonitor)
            self.escapeLocalMonitor = nil
        }
    }

    func unregister() {
        stopCancelMonitoring()
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        registeredShortcut = nil
    }

    deinit {
        MainActor.assumeIsolated {
            unregister()
        }
    }

    private static let signature: OSType = {
        let chars = Array("ANTR".utf8)
        return chars.reduce(0) { ($0 << 8) + OSType($1) }
    }()

    private static let activationHotKeyID: UInt32 = 1
    private static let cancelHotKeyID: UInt32 = 2

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr else { return noErr }

                let manager = Unmanaged<DictationHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleHotKeyEvent(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else { throw DictationHotKeyError.registrationFailed(handlerStatus) }
    }

    private func registerEscapeHotKeyIfPossible() {
        guard cancelHotKeyRef == nil else { return }
        do {
            try installEventHandlerIfNeeded()
        } catch {
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.cancelHotKeyID)
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &cancelHotKeyRef
        )
        if status != noErr {
            cancelHotKeyRef = nil
        }
    }

    private func handleHotKeyEvent(id: UInt32) {
        switch id {
        case Self.activationHotKeyID:
            onActivate?()
        case Self.cancelHotKeyID:
            onCancel?()
        default:
            break
        }
    }
}

enum DictationHotKeyError: AppCodedError {
    case invalidShortcut
    case registrationFailed(OSStatus)

    var code: AppErrorCode {
        switch self {
        case .invalidShortcut:
            return .dictationInvalidShortcut
        case .registrationFailed:
            return .dictationShortcutRegistrationFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            return "Use Command, Control, or Option plus a key."
        case .registrationFailed(let status):
            return "Shortcut failed (\(status))."
        }
    }
}
