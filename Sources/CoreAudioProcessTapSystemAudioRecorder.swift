@preconcurrency import AVFoundation
import CoreAudio
import Foundation

protocol SystemAudioCaptureSession: AnyObject {
    func stop()
    var writeFailure: String? { get }
}

@available(macOS 14.2, *)
final class CoreAudioProcessTapSystemAudioRecorder: SystemAudioCaptureSession {
    private let queue: DispatchQueue
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: QueuedAudioFileWriter?
    private let failureState = AudioCaptureFailureState()

    var writeFailure: String? {
        failureState.firstFailure
    }

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start(to url: URL, pauseState: AudioCapturePauseState) throws {
        stop()
        failureState.clear()

        do {
            let tapDescription = try makeTapDescription()
            try createTap(from: tapDescription)
            try createAggregateDevice(for: tapDescription)
            let tapFormat = try Self.makeAudioFormat(for: aggregateDeviceID)
            let fileFormat = try Self.makeFileFormat(from: tapFormat)
            let file = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
            let writer = QueuedAudioFileWriter(
                file: file,
                queue: queue,
                pauseState: pauseState,
                failureMessage: "System audio write failed",
                failureState: failureState
            )

            self.writer = writer
            try createIOProc(on: aggregateDeviceID, tapFormat: tapFormat, fileFormat: fileFormat, writer: writer)
            try startIO(on: aggregateDeviceID)
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProcID {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        writer?.flush()
        writer = nil

        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        stop()
    }

    private func makeTapDescription() throws -> CATapDescription {
        let currentProcessObjectID = try Self.currentProcessObjectID()
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [currentProcessObjectID])
        tapDescription.name = "Antrum Meeting Audio"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = CATapMuteBehavior.unmuted
        return tapDescription
    }

    private func createTap(from tapDescription: CATapDescription) throws {
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(
            AudioHardwareCreateProcessTap(tapDescription, &newTapID),
            operation: "Create CoreAudio process tap"
        )
        tapID = newTapID
    }

    private func createAggregateDevice(for tapDescription: CATapDescription) throws {
        let aggregateUID = "com.coreyoneal.Antrum.meeting-audio.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceNameKey: "Antrum Meeting Audio",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapDescription.uuid.uuidString]
            ]
        ]

        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try Self.check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateDeviceID),
            operation: "Create private CoreAudio aggregate device"
        )
        aggregateDeviceID = newAggregateDeviceID
    }

    private func createIOProc(
        on deviceID: AudioObjectID,
        tapFormat: AVAudioFormat,
        fileFormat: AVAudioFormat,
        writer: QueuedAudioFileWriter
    ) throws {
        var newIOProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, deviceID, queue) { _, inputData, _, _, _ in
            guard let buffer = AudioCaptureBufferCopy.nonInterleavedFloatBuffer(
                from: inputData,
                sourceFormat: tapFormat,
                targetFormat: fileFormat
            ) else {
                return
            }
            writer.write(buffer)
        }

        try Self.check(status, operation: "Create CoreAudio IO proc")
        ioProcID = newIOProcID
    }

    private func startIO(on deviceID: AudioObjectID) throws {
        guard let ioProcID else {
            throw CoreAudioProcessTapError.missingIOProc
        }
        try Self.check(AudioDeviceStart(deviceID, ioProcID), operation: "Start CoreAudio process tap")
    }

    private static func makeAudioFormat(for deviceID: AudioObjectID) throws -> AVAudioFormat {
        var streamDescription = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        try check(
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &streamDescription),
            operation: "Read CoreAudio tap format"
        )

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CoreAudioProcessTapError.unsupportedFormat
        }
        return format
    }

    private static func makeFileFormat(from tapFormat: AVAudioFormat) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: tapFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw CoreAudioProcessTapError.unsupportedFormat
        }
        return format
    }

    private static func currentProcessObjectID() throws -> AudioObjectID {
        var pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }

        try check(status, operation: "Find current CoreAudio process")
        guard processObjectID != kAudioObjectUnknown else {
            throw CoreAudioProcessTapError.currentProcessUnavailable
        }
        return processObjectID
    }

    private static func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CoreAudioProcessTapError.operationFailed(operation: operation, status: status)
        }
    }
}

enum CoreAudioProcessTapError: AppCodedError {
    case currentProcessUnavailable
    case missingIOProc
    case unsupportedFormat
    case operationFailed(operation: String, status: OSStatus)

    var code: AppErrorCode {
        switch self {
        case .currentProcessUnavailable:
            return .coreAudioCurrentProcessUnavailable
        case .missingIOProc:
            return .coreAudioMissingIOProc
        case .unsupportedFormat:
            return .coreAudioUnsupportedFormat
        case .operationFailed:
            return .coreAudioOperationFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .currentProcessUnavailable:
            return "Could not exclude Antrum from system audio."
        case .missingIOProc:
            return "CoreAudio tap was not ready."
        case .unsupportedFormat:
            return "CoreAudio tap format is not supported."
        case .operationFailed(let operation, let status):
            return "\(operation) failed (\(status))."
        }
    }
}
