@preconcurrency import AVFoundation
import Foundation

final class QueuedAudioFileWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let queue: DispatchQueue
    private let pauseState: AudioCapturePauseState
    private let failureMessage: String
    private let failureState: AudioCaptureFailureState?

    init(
        file: AVAudioFile,
        queue: DispatchQueue,
        pauseState: AudioCapturePauseState,
        failureMessage: String,
        failureState: AudioCaptureFailureState? = nil
    ) {
        self.file = file
        self.queue = queue
        self.pauseState = pauseState
        self.failureMessage = failureMessage
        self.failureState = failureState
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        // The callback timestamp defines whether the buffer belongs in the
        // recording. Checking pause state inside the queued closure can write
        // paused audio after a resume or discard audio captured before a pause.
        guard pauseState.shouldEnqueueBuffer() else { return }
        let sendableBuffer = SendableAudioBuffer(buffer)
        queue.async { [file, failureMessage, failureState] in
            autoreleasepool {
                do {
                    try file.write(from: sendableBuffer.buffer)
                } catch {
                    failureState?.record("\(failureMessage): \(error.localizedDescription)")
                }
            }
        }
    }

    func flush() {
        queue.sync {}
    }
}

enum AudioCaptureBufferCopy {
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }

        copy.frameLength = buffer.frameLength
        copyAudioBuffers(
            from: UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList),
            to: UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        )
        return copy
    }

    static func pcmBuffer(from audioBufferList: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        guard let firstBuffer = sourceBuffers.first, firstBuffer.mDataByteSize > 0 else {
            return nil
        }

        let streamDescription = format.streamDescription.pointee
        let bytesPerFrame = max(1, Int(streamDescription.mBytesPerFrame))
        let frameCount = AVAudioFrameCount(Int(firstBuffer.mDataByteSize) / bytesPerFrame)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        pcmBuffer.frameLength = frameCount
        copyAudioBuffers(
            from: sourceBuffers,
            to: UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        )
        return pcmBuffer
    }

    static func nonInterleavedFloatBuffer(
        from audioBufferList: UnsafePointer<AudioBufferList>,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard sourceFormat.commonFormat == .pcmFormatFloat32,
              targetFormat.commonFormat == .pcmFormatFloat32,
              !targetFormat.isInterleaved else {
            return nil
        }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        guard let firstBuffer = sourceBuffers.first, firstBuffer.mDataByteSize > 0 else {
            return nil
        }

        let channelCount = Int(targetFormat.channelCount)
        let sourceDescription = sourceFormat.streamDescription.pointee
        let sourceBytesPerFrame = max(1, Int(sourceDescription.mBytesPerFrame))
        let frameCount = Int(firstBuffer.mDataByteSize) / sourceBytesPerFrame
        guard frameCount > 0,
              let targetBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            return nil
        }

        targetBuffer.frameLength = AVAudioFrameCount(frameCount)
        let targetBuffers = UnsafeMutableAudioBufferListPointer(targetBuffer.mutableAudioBufferList)
        guard targetBuffers.count == channelCount else { return nil }

        if channelCount == 1, Int(sourceFormat.channelCount) > 1 {
            return downmixedMonoFloatBuffer(
                from: sourceBuffers,
                sourceFormat: sourceFormat,
                frameCount: frameCount,
                targetBuffer: targetBuffer,
                targetBuffers: targetBuffers
            )
        }

        if sourceFormat.isInterleaved {
            guard sourceBuffers.count == 1,
                  sourceFormat.channelCount == targetFormat.channelCount,
                  let sourceData = sourceBuffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return nil
            }

            for channelIndex in 0..<channelCount {
                guard let targetData = targetBuffers[channelIndex].mData?.assumingMemoryBound(to: Float.self) else {
                    return nil
                }

                for frameIndex in 0..<frameCount {
                    targetData[frameIndex] = sourceData[(frameIndex * channelCount) + channelIndex]
                }
                targetBuffers[channelIndex].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
            }
            return targetBuffer
        }

        copyAudioBuffers(from: sourceBuffers, to: targetBuffers)
        return targetBuffer
    }

    static func monoFloatBuffer(from buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        nonInterleavedFloatBuffer(
            from: UnsafePointer(buffer.audioBufferList),
            sourceFormat: buffer.format,
            targetFormat: targetFormat
        )
    }

    private static func downmixedMonoFloatBuffer(
        from sourceBuffers: UnsafeMutableAudioBufferListPointer,
        sourceFormat: AVAudioFormat,
        frameCount: Int,
        targetBuffer: AVAudioPCMBuffer,
        targetBuffers: UnsafeMutableAudioBufferListPointer
    ) -> AVAudioPCMBuffer? {
        let sourceChannelCount = Int(sourceFormat.channelCount)
        guard sourceChannelCount > 0,
              let targetData = targetBuffers[0].mData?.assumingMemoryBound(to: Float.self) else {
            return nil
        }

        if sourceFormat.isInterleaved {
            guard sourceBuffers.count == 1,
                  let sourceData = sourceBuffers[0].mData?.assumingMemoryBound(to: Float.self) else {
                return nil
            }

            for frameIndex in 0..<frameCount {
                var sum: Float = 0
                for channelIndex in 0..<sourceChannelCount {
                    sum += sourceData[(frameIndex * sourceChannelCount) + channelIndex]
                }
                targetData[frameIndex] = sum / Float(sourceChannelCount)
            }
        } else {
            guard sourceBuffers.count >= sourceChannelCount else { return nil }
            for frameIndex in 0..<frameCount {
                var sum: Float = 0
                for channelIndex in 0..<sourceChannelCount {
                    guard let sourceData = sourceBuffers[channelIndex].mData?.assumingMemoryBound(to: Float.self) else {
                        return nil
                    }
                    sum += sourceData[frameIndex]
                }
                targetData[frameIndex] = sum / Float(sourceChannelCount)
            }
        }

        targetBuffers[0].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
        return targetBuffer
    }

    private static func copyAudioBuffers(
        from sourceBuffers: UnsafeMutableAudioBufferListPointer,
        to destinationBuffers: UnsafeMutableAudioBufferListPointer
    ) {
        for index in sourceBuffers.indices {
            guard index < destinationBuffers.count,
                  let source = sourceBuffers[index].mData,
                  let destination = destinationBuffers[index].mData else {
                continue
            }

            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destination, source, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }
    }
}

private final class SendableAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

final class AudioCapturePauseState: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    func shouldEnqueueBuffer() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !paused
    }

    func setPaused(_ isPaused: Bool) {
        lock.lock()
        paused = isPaused
        lock.unlock()
    }
}

enum AudioCaptureFailurePolicy {
    static func firstFailure(microphone: String?, systemAudio: String?) -> String? {
        microphone ?? systemAudio
    }
}

final class AudioCaptureFailureState: @unchecked Sendable {
    private let lock = NSLock()
    private var firstFailureMessage: String?

    var firstFailure: String? {
        lock.lock()
        defer { lock.unlock() }
        return firstFailureMessage
    }

    func record(_ message: String) {
        lock.lock()
        if firstFailureMessage == nil {
            firstFailureMessage = message
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        firstFailureMessage = nil
        lock.unlock()
    }
}
