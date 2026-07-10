import AppKit
import CoreAudio
import Foundation
import SwiftUI

struct MeetingDetectionSnapshot: Equatable {
    let appLabels: [String]

    var appLine: String {
        appLabels.isEmpty ? "Microphone in use" : appLabels.joined(separator: ", ")
    }

    var promptTitle: String {
        guard !appLabels.isEmpty else { return "Microphone active" }
        if appLabels.count == 1, let label = appLabels.first {
            return MeetingDetectionPolicy.browserLabels.contains(label)
                ? "Microphone active in \(label)"
                : "Call active in \(label)"
        }
        return "Microphone active in \(appLine)"
    }

    var menuTitle: String {
        "Detected microphone use in \(appLine)"
    }
}

enum MeetingDetectionPromptState: Equatable {
    case idle
    case detected(MeetingDetectionSnapshot)
    case suppressedUntilClear

    var snapshot: MeetingDetectionSnapshot? {
        if case let .detected(snapshot) = self {
            return snapshot
        }
        return nil
    }

    var isPromptVisible: Bool {
        snapshot != nil
    }
}

enum MeetingDetectionEvent: Equatable {
    case detected(MeetingDetectionSnapshot)
    case heartbeat(MeetingDetectionSnapshot)
    case cleared
}

struct MicrophoneInputProcess: Equatable {
    let pid: pid_t
    let bundleID: String
    let appLabel: String

    init?(pid: pid_t, bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pid > 0, !bundleID.isEmpty else { return nil }
        self.pid = pid
        self.bundleID = bundleID
        self.appLabel = MeetingDetectionPolicy.appLabel(for: bundleID)
    }
}

enum MeetingDetectionPolicy {
    static let pollInterval: TimeInterval = 1
    static let clearAfterInactivePolls = 2
    static let heartbeatEveryActivePolls = 5
    static let localPrivacySummary = "Antrum only notices microphone use by meeting-capable apps and asks before local recording starts. It never joins calls or records by itself."

    static let allowedBundlePrefixes = [
        "company.thebrowser.Browser",
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "us.zoom.xos"
    ]

    static let browserLabels: Set<String> = ["Arc", "Chrome", "Safari"]

    static func appLabel(for bundleID: String) -> String {
        if bundleIDMatchesPrefix(bundleID, prefix: "company.thebrowser.Browser") {
            return "Arc"
        }
        if bundleIDMatchesPrefix(bundleID, prefix: "com.google.Chrome") {
            return "Chrome"
        }
        if bundleIDMatchesPrefix(bundleID, prefix: "com.apple.Safari") {
            return "Safari"
        }
        if bundleIDMatchesPrefix(bundleID, prefix: "com.microsoft.teams")
            || bundleIDMatchesPrefix(bundleID, prefix: "com.microsoft.teams2") {
            return "Teams"
        }
        if bundleIDMatchesPrefix(bundleID, prefix: "us.zoom.xos") {
            return "Zoom"
        }
        return bundleID
            .split(separator: ".")
            .last
            .map(String.init) ?? bundleID
    }

    static func isAllowedMicrophoneApp(_ bundleID: String) -> Bool {
        allowedBundlePrefixes.contains { bundleIDMatchesPrefix(bundleID, prefix: $0) }
    }

    static func activeAllowedExternalProcesses(
        from activeProcesses: [MicrophoneInputProcess],
        ownedPIDs: Set<pid_t>
    ) -> [MicrophoneInputProcess] {
        activeProcesses.filter { process in
            !ownedPIDs.contains(process.pid) && isAllowedMicrophoneApp(process.bundleID)
        }
    }

    static func dedupedAppLabels(from processes: [MicrophoneInputProcess]) -> [String] {
        var labels: [String] = []
        for process in processes where !labels.contains(process.appLabel) {
            labels.append(process.appLabel)
        }
        return labels
    }

    private static func bundleIDMatchesPrefix(_ bundleID: String, prefix: String) -> Bool {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bundleID == prefix || bundleID.hasPrefix(prefix + ".")
    }
}

struct MeetingDetectionStateMachine {
    private var active = false
    private var inactivePolls = 0
    private var activePollsSinceEmit = 0

    mutating func update(activeExternalInput: Bool, snapshot: MeetingDetectionSnapshot) -> MeetingDetectionEvent? {
        if activeExternalInput {
            inactivePolls = 0
            if !active {
                active = true
                activePollsSinceEmit = 0
                return .detected(snapshot)
            }

            activePollsSinceEmit += 1
            if activePollsSinceEmit >= MeetingDetectionPolicy.heartbeatEveryActivePolls {
                activePollsSinceEmit = 0
                return .heartbeat(snapshot)
            }
            return nil
        }

        activePollsSinceEmit = 0
        guard active else {
            inactivePolls = 0
            return nil
        }

        inactivePolls += 1
        guard inactivePolls >= MeetingDetectionPolicy.clearAfterInactivePolls else { return nil }
        active = false
        inactivePolls = 0
        return .cleared
    }
}

final class MeetingDetectionMonitor: @unchecked Sendable {
    typealias EventHandler = @MainActor (MeetingDetectionEvent) -> Void

    private let queue = DispatchQueue(label: "com.coreyoneal.Antrum.meeting-detection")
    private var timer: DispatchSourceTimer?
    private var stateMachine = MeetingDetectionStateMachine()
    private let activeInputProcesses: () throws -> [MicrophoneInputProcess]
    private let ownedPIDs: () -> Set<pid_t>
    private let eventHandler: EventHandler

    init(
        activeInputProcesses: @escaping () throws -> [MicrophoneInputProcess] = CoreAudioMeetingInputProbe.activeInputProcesses,
        ownedPIDs: @escaping () -> Set<pid_t> = { [ProcessInfo.processInfo.processIdentifier] },
        eventHandler: @escaping EventHandler
    ) {
        self.activeInputProcesses = activeInputProcesses
        self.ownedPIDs = ownedPIDs
        self.eventHandler = eventHandler
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + MeetingDetectionPolicy.pollInterval, repeating: MeetingDetectionPolicy.pollInterval)
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func poll() {
        let activeProcesses = (try? activeInputProcesses()) ?? []
        let allowedProcesses = MeetingDetectionPolicy.activeAllowedExternalProcesses(
            from: activeProcesses,
            ownedPIDs: ownedPIDs()
        )
        let snapshot = MeetingDetectionSnapshot(
            appLabels: MeetingDetectionPolicy.dedupedAppLabels(from: allowedProcesses)
        )
        guard let event = stateMachine.update(
            activeExternalInput: !allowedProcesses.isEmpty,
            snapshot: snapshot
        ) else {
            return
        }

        Task { @MainActor [eventHandler] in
            eventHandler(event)
        }
    }
}

enum CoreAudioMeetingInputProbe {
    static func activeInputProcesses() throws -> [MicrophoneInputProcess] {
        var processes: [MicrophoneInputProcess] = []
        for processObject in try processObjects() where processObject != AudioObjectID(kAudioObjectUnknown) {
            guard (try? readUInt32(processObject, selector: .processIsRunningInput, operation: "read process input state")) != 0 else {
                continue
            }
            guard processHasInputDevices(processObject) else { continue }
            guard let pid = try readPID(processObject),
                  let bundleID = try readBundleID(processObject),
                  let process = MicrophoneInputProcess(pid: pid, bundleID: bundleID) else {
                continue
            }
            processes.append(process)
        }

        processes.sort { $0.pid < $1.pid }
        var seenPIDs: Set<pid_t> = []
        return processes.filter { seenPIDs.insert($0.pid).inserted }
    }

    private static func processObjects() throws -> [AudioObjectID] {
        try readObjectArray(
            AudioObjectID(kAudioObjectSystemObject),
            selector: .hardwareProcessObjectList,
            scope: kAudioObjectPropertyScopeGlobal,
            sizeOperation: "read process object list size",
            dataOperation: "read process object list"
        )
    }

    private static func processHasInputDevices(_ objectID: AudioObjectID) -> Bool {
        (try? readObjectArray(
            objectID,
            selector: .processDevices,
            scope: kAudioObjectPropertyScopeInput,
            sizeOperation: "read process device list size",
            dataOperation: "read process device list"
        ).isEmpty == false) ?? false
    }

    private static func readPID(_ objectID: AudioObjectID) throws -> pid_t? {
        let value = try readInt32(objectID, selector: .processPID, operation: "read process pid")
        return value > 0 ? pid_t(value) : nil
    }

    private static func readBundleID(_ objectID: AudioObjectID) throws -> String? {
        var value: CFString?
        try readScalar(objectID, selector: .processBundleID, operation: "read process bundle id", value: &value)
        guard let value else { return nil }
        let bundleID = value as String
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readObjectArray(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        sizeOperation: String,
        dataOperation: String
    ) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize), operation: sizeOperation)
        guard dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objects = Array(repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &objects), operation: dataOperation)
        objects.removeAll { $0 == AudioObjectID(kAudioObjectUnknown) }
        return objects
    }

    private static func readInt32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws -> Int32 {
        var value: Int32 = 0
        try readScalar(objectID, selector: selector, operation: operation, value: &value)
        return value
    }

    private static func readUInt32(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws -> UInt32 {
        var value: UInt32 = 0
        try readScalar(objectID, selector: selector, operation: operation, value: &value)
        return value
    }

    private static func readScalar<T>(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String,
        value: inout T
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer), operation: operation)
        }
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw MeetingDetectionProbeError(operation: operation, status: status)
        }
    }
}

struct MeetingDetectionProbeError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed with OSStatus \(status)"
    }
}

private extension AudioObjectPropertySelector {
    static let hardwareProcessObjectList = fourCC("prs#")
    static let processPID = fourCC("ppid")
    static let processBundleID = fourCC("pbid")
    static let processDevices = fourCC("pdv#")
    static let processIsRunningInput = fourCC("piri")
}

private func fourCC(_ value: StaticString) -> AudioObjectPropertySelector {
    var result: UInt32 = 0
    for scalar in value.description.utf8.prefix(4) {
        result = (result << 8) + UInt32(scalar)
    }
    return AudioObjectPropertySelector(result)
}

@MainActor
final class MeetingDetectionController: ObservableObject {
    @Published private(set) var promptState: MeetingDetectionPromptState = .idle

    var onRecord: (() -> Void)?

    private var monitor: MeetingDetectionMonitor?
    private var hudWindow: NSPanel?
    private var recordingActive = false
    private var dictationActive = false

    var isPromptVisible: Bool {
        promptState.isPromptVisible
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = MeetingDetectionMonitor { [weak self] event in
            self?.handle(event)
        }
        self.monitor = monitor
        monitor.start()
    }

    func setRecordingActive(_ active: Bool) {
        recordingActive = active
        if active {
            suppressUntilClear()
        }
    }

    func setDictationActive(_ active: Bool) {
        dictationActive = active
        if active {
            hideHUD()
        }
    }

    func dismissPrompt() {
        suppressUntilClear()
    }

    func recordFromPrompt() {
        suppressUntilClear()
        onRecord?()
    }

    private func handle(_ event: MeetingDetectionEvent) {
        switch event {
        case .detected(let snapshot), .heartbeat(let snapshot):
            guard !recordingActive, !dictationActive else {
                hideHUD()
                return
            }
            guard case .suppressedUntilClear = promptState else {
                promptState = .detected(snapshot)
                showHUD()
                return
            }
        case .cleared:
            promptState = .idle
            hideHUD()
        }
    }

    private func suppressUntilClear() {
        promptState = .suppressedUntilClear
        hideHUD()
    }

    private func showHUD() {
        guard case .detected = promptState else { return }
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: AppTheme.MeetingDetection.hudWidth,
                    height: AppTheme.MeetingDetection.hudHeight
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
            panel.contentViewController = NSHostingController(rootView: MeetingDetectionHUDView(controller: self))
            hudWindow = panel
        }
        positionHUD()
        hudWindow?.orderFrontRegardless()
    }

    private func hideHUD() {
        hudWindow?.orderOut(nil)
    }

    private func positionHUD() {
        guard let hudWindow else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = hudWindow.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - AppTheme.Dictation.hudTopInset
        )
        hudWindow.setFrameOrigin(origin)
    }
}
