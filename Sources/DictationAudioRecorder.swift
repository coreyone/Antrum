import AppKit
@preconcurrency import AVFoundation
import Foundation

@MainActor
final class DictationAudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioWriteQueue: DispatchQueue?
    private let writeFailureState = AudioCaptureFailureState()
    private var outputURL: URL?

    var isRecording: Bool {
        audioEngine != nil
    }

    func start(levelHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard audioEngine == nil else { throw DictationRecordingError.alreadyRecording }
        guard await Self.requestMicrophoneAccess() else {
            throw DictationRecordingError.microphonePermissionDenied
        }
        try Task.checkCancellation()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        try? inputNode.setVoiceProcessingEnabled(true)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let fileFormat = try Self.recordingFormat(for: inputFormat)
        let url = Self.makeTemporaryURL()
        let file = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
        let writeQueue = DispatchQueue(label: "com.coreyoneal.Antrum.dictation.audio-write", qos: .userInitiated)

        audioEngine = engine
        audioWriteQueue = writeQueue
        outputURL = url
        writeFailureState.clear()

        do {
            inputNode.installTap(
                onBus: 0,
                bufferSize: 2_048,
                format: inputFormat,
                block: Self.makeTapHandler(
                    file: file,
                    fileFormat: fileFormat,
                    writeQueue: writeQueue,
                    failureState: writeFailureState,
                    levelHandler: levelHandler
                )
            )

            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
    }

    func stop() throws -> URL {
        guard let outputURL else { throw DictationRecordingError.notRecording }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioWriteQueue?.sync {}
        if let failure = writeFailureState.firstFailure {
            try? FileManager.default.removeItem(at: outputURL)
            audioEngine = nil
            audioWriteQueue = nil
            self.outputURL = nil
            throw DictationRecordingError.writeFailed(failure)
        }
        audioEngine = nil
        audioWriteQueue = nil
        self.outputURL = nil
        return outputURL
    }

    func cancel() {
        let url = outputURL
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioWriteQueue?.sync {}
        audioEngine = nil
        audioWriteQueue = nil
        outputURL = nil
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static var isMicrophonePermissionReady: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var microphonePermissionTitle: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "Mic OK"
        case .notDetermined:
            return "Mic not asked"
        case .denied:
            return "Mic denied"
        case .restricted:
            return "Mic restricted"
        @unknown default:
            return "Mic unknown"
        }
    }

    static var microphonePermissionActionTitle: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return "Open Settings"
        case .authorized:
            return "Ready"
        case .notDetermined:
            return "Allow"
        @unknown default:
            return "Open Settings"
        }
    }

    static func openMicrophoneSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func openSettingsPane(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Antrum-Dictation-\(UUID().uuidString)")
            .appendingPathExtension("caf")
    }

    nonisolated static func recordingFormat(for inputFormat: AVAudioFormat) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DictationRecordingError.unsupportedAudioFormat
        }
        return format
    }

    private nonisolated static func makeTapHandler(
        file: AVAudioFile,
        fileFormat: AVAudioFormat,
        writeQueue: DispatchQueue,
        failureState: AudioCaptureFailureState,
        levelHandler: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let copy = AudioCaptureBufferCopy.monoFloatBuffer(
                from: buffer,
                targetFormat: fileFormat
            ) else {
                failureState.record("Could not prepare microphone audio.")
                return
            }
            let level = level(from: copy)
            levelHandler(level)
            let sendableBuffer = SendableDictationAudioBuffer(copy)
            writeQueue.async {
                do {
                    try file.write(from: sendableBuffer.buffer)
                } catch {
                    failureState.record("Microphone write failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private nonisolated static func level(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<frameCount {
            sum += channel[index] * channel[index]
        }
        let rms = sqrt(sum / Float(frameCount))
        return min(1, max(0, Double(rms) * 8))
    }
}

private final class SendableDictationAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

enum DictationRecordingError: AppCodedError {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case unsupportedAudioFormat
    case writeFailed(String)

    var code: AppErrorCode {
        switch self {
        case .alreadyRecording:
            return .dictationAlreadyRecording
        case .notRecording:
            return .dictationNotRecording
        case .microphonePermissionDenied:
            return .dictationMicrophonePermissionDenied
        case .unsupportedAudioFormat:
            return .dictationUnsupportedAudioFormat
        case .writeFailed:
            return .dictationWriteFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording."
        case .notRecording:
            return "Not recording."
        case .microphonePermissionDenied:
            return "Allow Microphone for dictation."
        case .unsupportedAudioFormat:
            return "Mic format unsupported."
        case .writeFailed(let message):
            return message
        }
    }
}
