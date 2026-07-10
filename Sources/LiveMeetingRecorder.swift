@preconcurrency import AVFoundation
import Foundation

final class LiveMeetingRecorder: NSObject {
    private let microphoneQueue = DispatchQueue(label: "com.coreyoneal.Antrum.microphone-audio")
    private let systemAudioQueue = DispatchQueue(label: "com.coreyoneal.Antrum.system-audio")
    private let pauseState = AudioCapturePauseState()
    private let audioWriteFailureState = AudioCaptureFailureState()
    private var audioEngine: AVAudioEngine?
    private var microphoneFile: AVAudioFile?
    private var sessionInfo: RecordingSessionInfo?
    private var coreAudioSystemRecorder: SystemAudioCaptureSession?

    @MainActor
    func start() async throws -> RecordingSessionInfo {
        guard sessionInfo == nil else {
            throw RecordingError.alreadyRecording
        }

        guard await Self.requestMicrophoneAccess() else {
            throw RecordingError.microphonePermissionDenied
        }

        let info = try Self.makeSessionInfo()
        try FileManager.default.createDirectory(at: info.folderURL, withIntermediateDirectories: true)
        sessionInfo = info
        audioWriteFailureState.clear()

        do {
            try startMicrophoneCapture(to: info.microphoneURL)
            try await startSystemAudioCapture(to: info.systemAudioURL)
        } catch {
            await cancel()
            throw error
        }

        return info
    }

    @MainActor
    func pause() {
        setPaused(true)
    }

    @MainActor
    func resume() {
        setPaused(false)
    }

    @MainActor
    func cancel() async {
        _ = stopSystemCapture()

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()

        microphoneQueue.sync {
            microphoneFile = nil
        }

        setPaused(false)
        audioEngine = nil
        sessionInfo = nil
    }

    @MainActor
    func stop() async throws -> MeetingRecordingArtifacts {
        guard let info = sessionInfo else {
            throw RecordingError.notRecording
        }

        let systemAudioFailure = stopSystemCapture()

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()

        microphoneQueue.sync {
            microphoneFile = nil
        }

        setPaused(false)

        let writeFailure = AudioCaptureFailurePolicy.firstFailure(
            microphone: audioWriteFailureState.firstFailure,
            systemAudio: systemAudioFailure
        )

        audioEngine = nil
        sessionInfo = nil

        if let writeFailure {
            throw RecordingError.audioWriteFailed(writeFailure)
        }

        try Self.ensureAudioFileExists(at: info.microphoneURL, sampleRate: 44_100, channelCount: 1)
        try Self.ensureAudioFileExists(
            at: info.systemAudioURL,
            sampleRate: Double(SystemAudioCapturePlan.meetingAudio.sampleRate),
            channelCount: AVAudioChannelCount(SystemAudioCapturePlan.meetingAudio.channelCount)
        )

        return MeetingRecordingArtifacts(
            displayName: info.displayName,
            folderURL: info.folderURL,
            microphoneURL: info.microphoneURL,
            systemAudioURL: info.systemAudioURL,
            startedAt: info.startedAt,
            stoppedAt: Date()
        )
    }

    @MainActor
    private func startMicrophoneCapture(to url: URL) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        // Voice processing provides local echo cancellation when speakers are used.
        // Some audio devices do not support it, which must not prevent recording.
        try? inputNode.setVoiceProcessingEnabled(true)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let fileFormat = try Self.makeMonoRecordingFormat(sampleRate: inputFormat.sampleRate)
        let file = try AVAudioFile(forWriting: url, settings: fileFormat.settings)

        microphoneFile = file
        let writer = QueuedAudioFileWriter(
            file: file,
            queue: microphoneQueue,
            pauseState: pauseState,
            failureMessage: "Microphone write failed",
            failureState: audioWriteFailureState
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4_096,
            format: inputFormat,
            block: Self.makeMicrophoneTapHandler(fileFormat: fileFormat, writer: writer)
        )

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    @MainActor
    private func startSystemAudioCapture(to url: URL) async throws {
        try Task.checkCancellation()
        let settings = MeetingAudioCaptureSettings.current()
        let backends = settings.enabledBackends(coreAudioTapSupported: Self.isCoreAudioProcessTapSupported)

        guard backends.contains(.coreAudioProcessTap) else {
            throw RecordingError.coreAudioProcessTapUnavailable
        }

        do {
            try startCoreAudioProcessTap(to: url)
        } catch {
            coreAudioSystemRecorder?.stop()
            coreAudioSystemRecorder = nil
            if case RecordingError.coreAudioProcessTapUnavailable = error {
                throw error
            }
            throw RecordingError.coreAudioSystemAudioStartFailed(error.localizedDescription)
        }
    }

    @MainActor
    private func startCoreAudioProcessTap(to url: URL) throws {
        guard Self.isCoreAudioProcessTapSupported else {
            throw RecordingError.coreAudioProcessTapUnavailable
        }

        if #available(macOS 14.2, *) {
            let recorder = CoreAudioProcessTapSystemAudioRecorder(queue: systemAudioQueue)
            try recorder.start(to: url, pauseState: pauseState)
            coreAudioSystemRecorder = recorder
        } else {
            throw RecordingError.coreAudioProcessTapUnavailable
        }
    }

    @MainActor
    private func stopSystemCapture() -> String? {
        let recorder = coreAudioSystemRecorder
        recorder?.stop()
        coreAudioSystemRecorder = nil
        return recorder?.writeFailure
    }

    private static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func makeSessionInfo() throws -> RecordingSessionInfo {
        let startedAt = Date()
        let displayName = recordingNameFormatter.string(from: startedAt)
        let rootURL = RecordingStoragePolicy.defaultRecordingsDirectory()
        let folderURL = rootURL.appendingPathComponent(displayName, isDirectory: true)
        let filePrefix = displayName.replacingOccurrences(of: " ", with: "_")

        return RecordingSessionInfo(
            displayName: displayName,
            folderURL: folderURL,
            microphoneURL: folderURL.appendingPathComponent("\(filePrefix)_microphone.caf"),
            systemAudioURL: folderURL.appendingPathComponent("\(filePrefix)_system-audio.caf"),
            startedAt: startedAt
        )
    }

    private static func ensureAudioFileExists(at url: URL, sampleRate: Double, channelCount: AVAudioChannelCount) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate / 2)) else {
            throw RecordingError.cannotCreateFallbackAudio
        }

        buffer.frameLength = buffer.frameCapacity
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static func makeMonoRecordingFormat(sampleRate: Double) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RecordingError.cannotCreateFallbackAudio
        }
        return format
    }

    private var isCapturePaused: Bool {
        pauseState.isPaused
    }

    private func setPaused(_ paused: Bool) {
        pauseState.setPaused(paused)
    }

    private static let recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss Meeting"
        return formatter
    }()

    private static var isCoreAudioProcessTapSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }
}

extension LiveMeetingRecorder: @unchecked Sendable {}

private extension LiveMeetingRecorder {
    static func makeMicrophoneTapHandler(
        fileFormat: AVAudioFormat,
        writer: QueuedAudioFileWriter
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let bufferCopy = AudioCaptureBufferCopy.monoFloatBuffer(
                from: buffer,
                targetFormat: fileFormat
            ) else { return }
            writer.write(bufferCopy)
        }
    }
}

private enum RecordingError: AppCodedError {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case coreAudioProcessTapUnavailable
    case coreAudioSystemAudioStartFailed(String?)
    case cannotCreateFallbackAudio
    case audioWriteFailed(String)

    var code: AppErrorCode {
        switch self {
        case .alreadyRecording:
            return .recordingAlreadyActive
        case .notRecording:
            return .recordingNotActive
        case .microphonePermissionDenied:
            return .recordingMicrophonePermissionDenied
        case .coreAudioProcessTapUnavailable:
            return .recordingCoreAudioProcessTapUnavailable
        case .coreAudioSystemAudioStartFailed:
            return .recordingCoreAudioSystemAudioStartFailed
        case .cannotCreateFallbackAudio:
            return .recordingFallbackAudioCreationFailed
        case .audioWriteFailed:
            return .recordingAudioWriteFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A meeting recording is already active."
        case .notRecording:
            return "No meeting recording is active."
        case .microphonePermissionDenied:
            return "Microphone permission is required to record your voice."
        case .coreAudioProcessTapUnavailable:
            return "System audio capture requires macOS 14.2 or later."
        case .coreAudioSystemAudioStartFailed(let reason):
            if let reason, !reason.isEmpty {
                return "System audio capture failed: \(reason)"
            }
            return "System audio capture failed."
        case .cannotCreateFallbackAudio:
            return "Could not create an empty audio track."
        case .audioWriteFailed(let reason):
            return "Recording audio could not be saved: \(reason)"
        }
    }
}
