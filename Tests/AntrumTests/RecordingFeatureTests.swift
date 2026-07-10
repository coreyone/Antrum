import AVFoundation
import Foundation
import Testing
@testable import Antrum

@Suite("Recording feature")
struct RecordingFeatureTests {
    @Test
    func recordingSpeakersStartWithEditableUserNameAndRemotePlaceholders() {
        let speakers = RecordingTranscriptMerger.speakers(remoteSpeakerIDs: ["S2", "S4"])

        #expect(speakers.map(\.id) == ["USER", "S2", "S4"])
        #expect(speakers.map(\.defaultLabel) == ["You", "Speaker 1", "Speaker 2"])
        #expect(speakers[0].customName == "You")
        #expect(speakers.dropFirst().allSatisfy { $0.customName.isEmpty })
    }

    @Test
    func recordingMergeDropsEmptyBlocksBeforeMarkdownReview() {
        let blocks = RecordingTranscriptMerger.mergedBlocks(
            userBlocks: [
                TranscriptBlock(speakerID: "USER", start: 0, end: 4, text: "   "),
                TranscriptBlock(speakerID: "USER", start: 8, end: 10, text: "I can take that.")
            ],
            remoteBlocks: [
                TranscriptBlock(speakerID: "S1", start: 4, end: 8, text: "Can someone own follow up?"),
                TranscriptBlock(speakerID: "S2", start: 10, end: 12, text: "")
            ]
        )

        #expect(blocks.map(\.speakerID) == ["S1", "USER"])
        #expect(blocks.map(\.text) == ["Can someone own follow up?", "I can take that."])
    }

    @Test
    func recordingMarkdownUsesRenamedUserSpeaker() {
        let speakers = [
            SpeakerDraft(id: "USER", defaultLabel: "You", customName: "Corey"),
            SpeakerDraft(id: "S1", defaultLabel: "Speaker 1", customName: "Mina")
        ]
        let blocks = [
            TranscriptBlock(speakerID: "USER", start: 0, end: 3, text: "I will send the notes."),
            TranscriptBlock(speakerID: "S1", start: 3, end: 6, text: "Thanks.")
        ]

        let markdown = TranscriptMarkdownBuilder.markdown(
            title: "Meeting Transcript: Live Meeting",
            sourceFileName: "2026-06-18 Meeting",
            processedAt: Date(timeIntervalSince1970: 1_800_000_000),
            speakers: speakers,
            blocks: blocks
        )

        #expect(markdown.contains("- You — Corey"))
        #expect(markdown.contains("### Corey [0:00 – 0:03]"))
        #expect(!markdown.contains("### You [0:00 – 0:03]"))
    }

    @MainActor
    @Test
    func emptyRecordingReviewDoesNotEnableMarkdownExport() {
        let viewModel = MeetingTranscriptionViewModel()
        viewModel.speakers = [
            SpeakerDraft(id: "USER", defaultLabel: "You", customName: "You")
        ]
        viewModel.blocks = []
        viewModel.markdown = "# Meeting Transcript: Empty Recording\n\n## Speakers\n\n- You"

        #expect(!viewModel.canExport)
        #expect(viewModel.exportStatusMessage == "No transcript to export.")
    }

    @Test
    func liveRecordingStateReportsMenuAndDockContract() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let pausedAt = Date(timeIntervalSince1970: 105)

        #expect(!LiveRecordingState.idle.isActive)
        #expect(!LiveRecordingState.idle.canStop)
        #expect(!LiveRecordingState.idle.canPauseOrResume)
        #expect(LiveRecordingState.idle.dockBadge == nil)
        #expect(LiveRecordingState.idle.menuBarPresentation.iconStyle == .monochromeWaveform)
        #expect(LiveRecordingState.idle.menuBarPresentation.title == "")
        #expect(LiveRecordingState.starting.isActive)
        #expect(LiveRecordingState.starting.canStop)
        #expect(!LiveRecordingState.starting.canPauseOrResume)
        #expect(LiveRecordingState.starting.dockBadge == "REC")
        #expect(LiveRecordingState.starting.menuBarPresentation.iconStyle == .rainbowWaveform)
        #expect(LiveRecordingState.starting.menuBarPresentation.title == " REC")

        let active = LiveRecordingState.recording(
            startedAt: startedAt,
            pausedAt: nil,
            accumulatedPausedDuration: 0
        )
        #expect(active.isActive)
        #expect(!active.isPaused)
        #expect(active.canStop)
        #expect(active.canPauseOrResume)
        #expect(active.dockBadge == "REC")
        #expect(active.menuBarPresentation.iconStyle == .rainbowWaveform)
        #expect(active.menuBarPresentation.title == " REC")
        #expect(active.menuBarPresentation.tint == .none)

        let paused = LiveRecordingState.recording(
            startedAt: startedAt,
            pausedAt: pausedAt,
            accumulatedPausedDuration: 0
        )
        #expect(paused.isActive)
        #expect(paused.isPaused)
        #expect(paused.canStop)
        #expect(paused.canPauseOrResume)
        #expect(paused.dockBadge == "PAUSE")
        #expect(paused.menuBarPresentation.iconStyle == .rainbowWaveform)
        #expect(paused.menuBarPresentation.title == " PAUSE")

        #expect(LiveRecordingState.stopping.isActive)
        #expect(!LiveRecordingState.stopping.canStop)
        #expect(!LiveRecordingState.stopping.canPauseOrResume)
        #expect(LiveRecordingState.stopping.dockBadge == "SAVE")
        #expect(LiveRecordingState.stopping.menuBarPresentation.iconStyle == .rainbowWaveform)
        #expect(LiveRecordingState.stopping.menuBarPresentation.title == " SAVE")
    }

    @Test
    func voiceActivityDetectorReturnsNoWindowsForSilentAudioWithoutFallback() {
        let windows = VoiceActivityDetector.windows(
            from: Array(repeating: Float(0), count: 2_000),
            sampleRate: 1_000
        )

        #expect(windows.isEmpty)
    }

    @Test
    func systemAudioCapturePlanUsesAudioOnlyOutputForPrivacy() {
        let plan = SystemAudioCapturePlan.meetingAudio

        #expect(plan.sampleRate == 16_000)
        #expect(plan.channelCount == 1)
    }

    @Test
    func meetingAudioCaptureDefaultsToCoreAudioWithoutScreenPermission() {
        let settings = MeetingAudioCaptureSettings()

        #expect(settings.enabledBackends(coreAudioTapSupported: true) == [.coreAudioProcessTap])
        #expect(settings.enabledBackends(coreAudioTapSupported: false).isEmpty)
    }

    @Test
    func systemAudioCaptureBackendsDoNotIncludeScreenCaptureFallback() {
        let backends = MeetingAudioCaptureSettings().enabledBackends(coreAudioTapSupported: true)

        #expect(backends == [.coreAudioProcessTap])
    }

    @Test
    func coreAudioInterleavedFloatBufferConvertsToNonInterleavedFileBuffer() {
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        )!
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        var interleavedSamples: [Float] = [1, 10, 2, 20, 3, 30]

        let buffer = interleavedSamples.withUnsafeMutableBytes { sampleBytes in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(sampleBytes.count),
                mData: sampleBytes.baseAddress
            )
            var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            return withUnsafePointer(to: &audioBufferList) { audioBufferListPointer in
                AudioCaptureBufferCopy.nonInterleavedFloatBuffer(
                    from: audioBufferListPointer,
                    sourceFormat: sourceFormat,
                    targetFormat: targetFormat
                )
            }
        }

        #expect(buffer?.frameLength == 3)
        #expect(buffer?.format.isInterleaved == false)

        let channelData = buffer?.floatChannelData
        #expect(channelData?[0][0] == 1)
        #expect(channelData?[0][1] == 2)
        #expect(channelData?[0][2] == 3)
        #expect(channelData?[1][0] == 10)
        #expect(channelData?[1][1] == 20)
        #expect(channelData?[1][2] == 30)
    }

    @Test
    func coreAudioInterleavedFloatBufferDownmixesToMonoFileBuffer() {
        let sourceFormat = Self.floatFormat(
            sampleRate: 48_000,
            channels: 4,
            interleaved: true
        )
        let targetFormat = Self.floatFormat(
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )
        var interleavedSamples: [Float] = [
            1, 3, 5, 7,
            2, 4, 6, 8,
            -1, -3, -5, -7
        ]

        let buffer = interleavedSamples.withUnsafeMutableBytes { sampleBytes in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 4,
                mDataByteSize: UInt32(sampleBytes.count),
                mData: sampleBytes.baseAddress
            )
            var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            return withUnsafePointer(to: &audioBufferList) { audioBufferListPointer in
                AudioCaptureBufferCopy.nonInterleavedFloatBuffer(
                    from: audioBufferListPointer,
                    sourceFormat: sourceFormat,
                    targetFormat: targetFormat
                )
            }
        }

        #expect(buffer?.frameLength == 3)
        #expect(buffer?.format.channelCount == 1)
        #expect(buffer?.format.isInterleaved == false)

        let channelData = buffer?.floatChannelData
        #expect(channelData?[0][0] == 4)
        #expect(channelData?[0][1] == 5)
        #expect(channelData?[0][2] == -4)
    }

    @Test
    func coreAudioNonInterleavedFloatBufferDownmixesToMonoFileBuffer() {
        let sourceFormat = Self.floatFormat(
            sampleRate: 48_000,
            channels: 3,
            interleaved: false
        )
        let targetFormat = Self.floatFormat(
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 2)!
        sourceBuffer.frameLength = 2
        sourceBuffer.floatChannelData?[0][0] = 1
        sourceBuffer.floatChannelData?[0][1] = 4
        sourceBuffer.floatChannelData?[1][0] = 2
        sourceBuffer.floatChannelData?[1][1] = 5
        sourceBuffer.floatChannelData?[2][0] = 3
        sourceBuffer.floatChannelData?[2][1] = 6

        let buffer = AudioCaptureBufferCopy.monoFloatBuffer(
            from: sourceBuffer,
            targetFormat: targetFormat
        )

        #expect(buffer?.frameLength == 2)
        #expect(buffer?.format.channelCount == 1)
        let channelData = buffer?.floatChannelData
        #expect(channelData?[0][0] == 2)
        #expect(channelData?[0][1] == 5)
    }

    @Test
    func audioCaptureFailureStateKeepsFirstFailureOnly() {
        let state = AudioCaptureFailureState()

        state.record("first")
        state.record("second")

        #expect(state.firstFailure == "first")
        state.clear()
        #expect(state.firstFailure == nil)
    }

    @Test
    func pausedCaptureBuffersAreRejectedBeforeQueueing() {
        let state = AudioCapturePauseState()

        #expect(state.shouldEnqueueBuffer())
        state.setPaused(true)
        #expect(!state.shouldEnqueueBuffer())
        state.setPaused(false)
        #expect(state.shouldEnqueueBuffer())
    }

    @Test
    func recordingFailsForEitherTrackWriteFailure() {
        #expect(AudioCaptureFailurePolicy.firstFailure(
            microphone: "Mic write failed",
            systemAudio: "System write failed"
        ) == "Mic write failed")
        #expect(AudioCaptureFailurePolicy.firstFailure(
            microphone: nil,
            systemAudio: "System write failed"
        ) == "System write failed")
        #expect(AudioCaptureFailurePolicy.firstFailure(microphone: nil, systemAudio: nil) == nil)
    }

    @Test
    func activeRecordingPerformanceBudgetRejectsHeavyCaptureDefaults() {
        #expect(RecordingPerformanceBudget.idleCPUPercent <= 1)
        #expect(RecordingPerformanceBudget.idleRSSMegabytes <= 150)
        #expect(RecordingPerformanceBudget.activeRecordingCPUPercent <= 15)
        #expect(RecordingPerformanceBudget.activeRecordingRSSMegabytes <= 220)
    }

    @Test
    func recordingStartupPolicyFailsFastEnoughForUserRecovery() {
        #expect(RecordingStartupPolicy.timeout == .seconds(12))
        #expect(RecordingStartupPolicy.timeoutSeconds >= 5)
        #expect(RecordingStartupPolicy.timeoutSeconds <= 15)
    }

    private static func floatFormat(
        sampleRate: Double,
        channels: UInt32,
        interleaved: Bool
    ) -> AVAudioFormat {
        let bytesPerSample = UInt32(MemoryLayout<Float>.size)
        let flags: AudioFormatFlags = kAudioFormatFlagIsFloat
            | kAudioFormatFlagIsPacked
            | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved)
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags,
            mBytesPerPacket: interleaved ? bytesPerSample * channels : bytesPerSample,
            mFramesPerPacket: 1,
            mBytesPerFrame: interleaved ? bytesPerSample * channels : bytesPerSample,
            mChannelsPerFrame: channels,
            mBitsPerChannel: bytesPerSample * 8,
            mReserved: 0
        )
        let layoutTag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder | channels)
        let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag)
        return AVAudioFormat(streamDescription: &description, channelLayout: channelLayout)!
    }
}
