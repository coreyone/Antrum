import AppKit
import Carbon
import Foundation

enum DictationState: Equatable {
    case idle
    case listening(startedAt: Date)
    case processing
    case inserted
    case canceled
    case failed(String)

    var isActive: Bool {
        switch self {
        case .listening, .processing:
            return true
        case .idle, .inserted, .canceled, .failed:
            return false
        }
    }

    var menuTitle: String {
        switch self {
        case .idle, .inserted, .canceled, .failed:
            return "Start Dictation"
        case .listening:
            return "Stop Dictation"
        case .processing:
            return "Processing"
        }
    }

    var statusTitle: String {
        switch self {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .inserted:
            return "Inserted"
        case .canceled:
            return "Canceled"
        case .failed:
            return "Check Settings"
        }
    }

    var hudDetail: String {
        switch self {
        case .idle:
            return "Ready"
        case .listening:
            return "Esc"
        case .processing:
            return "Offline"
        case .inserted:
            return "Pasted"
        case .canceled:
            return "Canceled"
        case .failed(let message):
            return message.isEmpty ? "Check settings" : Self.compactHUDMessage(message)
        }
    }

    private static func compactHUDMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 32 else { return trimmed }
        return String(trimmed.prefix(29)) + "..."
    }
}

enum DictationModelStatus: Equatable {
    case missing
    case downloading(Double)
    case ready
    case failed(String)

    var canStartDownload: Bool {
        switch self {
        case .missing, .failed:
            return true
        case .downloading, .ready:
            return false
        }
    }

    var menuTitle: String {
        switch self {
        case .missing:
            return "Model missing"
        case .downloading(let progress):
            let clampedProgress = max(0, min(1, progress))
            return "Model \(Int(clampedProgress * 100))%"
        case .ready:
            return "Model ready"
        case .failed:
            return "Model failed"
        }
    }

    var settingsDetail: String {
        switch self {
        case .missing:
            return "Download once. Runs offline."
        case .downloading(let progress):
            let clampedProgress = max(0, min(1, progress))
            return "Downloading \(Int(clampedProgress * 100))%. Keep open."
        case .ready:
            return "Ready. Local only."
        case .failed(let message):
            return message.isEmpty ? "Download failed. Retry." : message
        }
    }
}

enum DictationModelDisclosure {
    static let estimatedSizeText = "Approx. 650 MB"
    static let sourceText = "Downloads from FluidAudio/Hugging Face. Dictation audio and text are not uploaded."
}

enum DictationActivationMode: String, CaseIterable, Identifiable {
    case toggle
    case holdToTalk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggle:
            return "Toggle"
        case .holdToTalk:
            return "Hold"
        }
    }
}

enum DictationHUDPosition: String, CaseIterable, Identifiable {
    case topCenter
    case cursorAdjacent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topCenter:
            return "Top"
        case .cursorAdjacent:
            return "Cursor"
        }
    }
}

enum DictationHUDPlacement {
    static func origin(
        for position: DictationHUDPosition,
        screenFrame: NSRect,
        hudSize: NSSize,
        mouseLocation: NSPoint
    ) -> NSPoint {
        let proposed: NSPoint
        switch position {
        case .topCenter:
            proposed = NSPoint(
                x: screenFrame.midX - hudSize.width / 2,
                y: screenFrame.maxY - hudSize.height - AppTheme.Dictation.hudTopInset
            )
        case .cursorAdjacent:
            proposed = NSPoint(
                x: mouseLocation.x + AppTheme.Dictation.hudCursorGap,
                y: mouseLocation.y - hudSize.height - AppTheme.Dictation.hudCursorGap
            )
        }

        return clamped(origin: proposed, hudSize: hudSize, screenFrame: screenFrame)
    }

    static func clamped(origin: NSPoint, hudSize: NSSize, screenFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, screenFrame.minX), screenFrame.maxX - hudSize.width),
            y: min(max(origin.y, screenFrame.minY), screenFrame.maxY - hudSize.height)
        )
    }
}

struct DictationShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let defaultShortcut = DictationShortcut(
        keyCode: UInt32(kVK_ANSI_1),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    static let commandOptionD = DictationShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(optionKey | cmdKey)
    )

    var displayName: String {
        modifierDisplayName + keyDisplayName
    }

    var modifierDisplayName: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined()
    }

    var keyDisplayName: String {
        Self.keyNames[keyCode] ?? "Key \(keyCode)"
    }

    var menuKeyEquivalent: String {
        switch keyCode {
        case UInt32(kVK_Space):
            return " "
        default:
            return keyDisplayName.count == 1 ? keyDisplayName.lowercased() : ""
        }
    }

    var menuModifierFlags: NSEvent.ModifierFlags {
        Self.eventModifiers(fromCarbon: carbonModifiers)
    }

    var isValidGlobalShortcut: Bool {
        guard !Self.modifierKeyCodes.contains(keyCode) else { return false }
        let modifiers = Self.eventModifiers(fromCarbon: carbonModifiers)
        return modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
    }

    func matches(event: NSEvent) -> Bool {
        guard UInt32(event.keyCode) == keyCode else { return false }
        let expected = Self.eventModifiers(fromCarbon: carbonModifiers)
        return Self.normalizedModifiers(from: event.modifierFlags) == expected
    }

    static func from(event: NSEvent) -> DictationShortcut? {
        from(keyCode: UInt32(event.keyCode), modifierFlags: event.modifierFlags)
    }

    static func from(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> DictationShortcut? {
        let modifiers = normalizedModifiers(from: modifierFlags)
        guard !modifiers.isEmpty else { return nil }
        let shortcut = DictationShortcut(
            keyCode: keyCode,
            carbonModifiers: carbonModifiers(from: modifiers)
        )
        return shortcut.isValidGlobalShortcut ? shortcut : nil
    }

    static func normalizedModifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        let rawValue = flags.rawValue
        if flags.contains(.control) || rawValue & NSEvent.ModifierFlags.control.rawValue != 0 || rawValue & UInt(controlKey) != 0 {
            modifiers.insert(.control)
        }
        if flags.contains(.option) || rawValue & NSEvent.ModifierFlags.option.rawValue != 0 || rawValue & UInt(optionKey) != 0 {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) || rawValue & NSEvent.ModifierFlags.shift.rawValue != 0 || rawValue & UInt(shiftKey) != 0 {
            modifiers.insert(.shift)
        }
        if flags.contains(.command) || rawValue & NSEvent.ModifierFlags.command.rawValue != 0 || rawValue & UInt(cmdKey) != 0 {
            modifiers.insert(.command)
        }
        return modifiers
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static func eventModifiers(fromCarbon modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    private static let relevantNSEventModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    private static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Shift),
        UInt32(kVK_RightShift),
        UInt32(kVK_Control),
        UInt32(kVK_RightControl),
        UInt32(kVK_Option),
        UInt32(kVK_RightOption),
        UInt32(kVK_Command)
    ]

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_Space): "Space"
    ]
}

struct DictationSettings: Equatable {
    var activationMode: DictationActivationMode
    var hudPosition: DictationHUDPosition
    var shortcut: DictationShortcut
    var streamingPreviewEnabled: Bool

    static let defaults = DictationSettings(
        activationMode: .toggle,
        hudPosition: .topCenter,
        shortcut: .defaultShortcut,
        streamingPreviewEnabled: false
    )

    static func load(defaults: UserDefaults = .standard) -> DictationSettings {
        let activationMode = defaults.string(forKey: Keys.activationMode)
            .flatMap(DictationActivationMode.init(rawValue:)) ?? Self.defaults.activationMode
        let hudPosition = defaults.string(forKey: Keys.hudPosition)
            .flatMap(DictationHUDPosition.init(rawValue:)) ?? Self.defaults.hudPosition
        let shortcut: DictationShortcut
        if let data = defaults.data(forKey: Keys.shortcut),
           let decoded = try? JSONDecoder().decode(DictationShortcut.self, from: data),
           decoded.isValidGlobalShortcut {
            shortcut = decoded
        } else {
            shortcut = Self.defaults.shortcut
        }
        return DictationSettings(
            activationMode: activationMode,
            hudPosition: hudPosition,
            shortcut: shortcut,
            streamingPreviewEnabled: false
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(activationMode.rawValue, forKey: Keys.activationMode)
        defaults.set(hudPosition.rawValue, forKey: Keys.hudPosition)
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: Keys.shortcut)
        defaults.set(false, forKey: Keys.streamingPreviewEnabled)
    }

    func requiresHotKeyRegistration(comparedTo previous: DictationSettings) -> Bool {
        shortcut != previous.shortcut
    }

    enum Keys {
        static let activationMode = "Dictation.ActivationMode"
        static let hudPosition = "Dictation.HUDPosition"
        static let shortcut = "Dictation.Shortcut"
        static let streamingPreviewEnabled = "Dictation.StreamingPreviewEnabled"
    }
}

enum DictationPerformance {
    static let audioLevelMinimumInterval: TimeInterval = 1.0 / 30.0
    static let modelDownloadProgressMinimumStep = 0.01

    static func shouldDispatchShortcutRelease(event: NSEvent, shortcut: DictationShortcut) -> Bool {
        event.type == .keyUp && shortcut.matches(event: event)
    }

    static func shouldPublishTimedUpdate(
        lastUpdate: Date?,
        now: Date,
        minimumInterval: TimeInterval = audioLevelMinimumInterval
    ) -> Bool {
        guard let lastUpdate else { return true }
        return now.timeIntervalSince(lastUpdate) + 0.000_001 >= minimumInterval
    }

    static func shouldPublishProgress(
        previous: Double?,
        next: Double,
        minimumStep: Double = modelDownloadProgressMinimumStep
    ) -> Bool {
        let clampedNext = max(0, min(1, next))
        guard let previous else { return true }
        if clampedNext == 0 || clampedNext == 1 { return clampedNext != previous }
        return abs(clampedNext - previous) >= minimumStep
    }
}
