import AppKit
import ApplicationServices
import Carbon

protocol PasteboardStoring {
    func snapshot() -> PasteboardSnapshot
    func replaceWithString(_ string: String) -> Int
    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountMatches expectedChangeCount: Int)
}

protocol KeyboardPasting {
    func paste() throws
}

struct PasteboardSnapshot: Equatable {
    struct Item: Equatable {
        let values: [(NSPasteboard.PasteboardType, Data)]

        static func == (lhs: Item, rhs: Item) -> Bool {
            guard lhs.values.count == rhs.values.count else { return false }
            return zip(lhs.values, rhs.values).allSatisfy { lhsValue, rhsValue in
                lhsValue.0 == rhsValue.0 && lhsValue.1 == rhsValue.1
            }
        }
    }

    let items: [Item]
}

final class SystemPasteboardStore: PasteboardStoring {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            PasteboardSnapshot.Item(
                values: item.types.compactMap { type in
                    guard let data = item.data(forType: type) else { return nil }
                    return (type, data)
                }
            )
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    func replaceWithString(_ string: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCountMatches expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        pasteboard.clearContents()
        let items = snapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()
            for value in snapshotItem.values {
                item.setData(value.1, forType: value.0)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

final class SystemKeyboardPaster: KeyboardPasting {
    func paste() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw DictationInsertionError.pasteFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

enum DictationInsertionError: AppCodedError {
    case accessibilityPermissionRequired
    case emptyTranscript
    case pasteFailed

    var code: AppErrorCode {
        switch self {
        case .accessibilityPermissionRequired:
            return .dictationAccessibilityPermissionRequired
        case .emptyTranscript:
            return .dictationEmptyTranscript
        case .pasteFailed:
            return .dictationPasteFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Allow Accessibility to paste."
        case .emptyTranscript:
            return "No text detected."
        case .pasteFailed:
            return "Paste failed."
        }
    }
}

@MainActor
struct DictationInsertionService {
    var pasteboard: PasteboardStoring = SystemPasteboardStore()
    var keyboard: KeyboardPasting = SystemKeyboardPaster()
    var restoreDelay: UInt64 = 350_000_000
    var accessibilityTrusted: () -> Bool = { Self.isAccessibilityTrusted }
    var requestAccessibility: () -> Void = { Self.requestAccessibilityPermission() }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func insert(_ transcript: String) async throws {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DictationInsertionError.emptyTranscript }
        guard accessibilityTrusted() else {
            requestAccessibility()
            throw DictationInsertionError.accessibilityPermissionRequired
        }

        let snapshot = pasteboard.snapshot()
        let dictationChangeCount = pasteboard.replaceWithString(text)
        do {
            try keyboard.paste()
            try await Task.sleep(nanoseconds: restoreDelay)
        } catch {
            pasteboard.restore(snapshot, ifChangeCountMatches: dictationChangeCount)
            throw error
        }
        pasteboard.restore(snapshot, ifChangeCountMatches: dictationChangeCount)
        try Task.checkCancellation()
    }
}
