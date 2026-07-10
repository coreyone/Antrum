import Foundation
import Testing
@testable import Antrum

@Suite("Transcript alignment")
struct TranscriptAlignerTests {
    @Test
    func collapsesAdjacentWindowsWithSameSpeaker() {
        let windows = [
            SpeakerWindow(speakerID: "S1", start: 0, end: 10),
            SpeakerWindow(speakerID: "S1", start: 10, end: 20),
            SpeakerWindow(speakerID: "S2", start: 20, end: 30)
        ]

        let blocks = TranscriptAligner.align(
            transcript: "Alpha bravo charlie delta echo foxtrot",
            windows: windows
        )

        #expect(blocks.count == 2)
        #expect(blocks[0].speakerID == "S1")
        #expect(blocks[0].start == 0)
        #expect(blocks[0].end == 20)
        #expect(blocks[0].text == "Alpha bravo charlie delta")
        #expect(blocks[1].speakerID == "S2")
        #expect(blocks[1].start == 20)
        #expect(blocks[1].end == 30)
        #expect(blocks[1].text == "echo foxtrot")
    }

    @Test
    func renderedTranscriptIDsStayStableAcrossSpeakerRenames() {
        let blocks = [
            TranscriptBlock(speakerID: "S1", start: 0, end: 10, text: "Hello there."),
            TranscriptBlock(speakerID: "S2", start: 10, end: 20, text: "General Kenobi.")
        ]
        let originalSpeakers = [
            SpeakerDraft(id: "S1", defaultLabel: "Speaker 1"),
            SpeakerDraft(id: "S2", defaultLabel: "Speaker 2")
        ]
        let renamedSpeakers = [
            SpeakerDraft(id: "S1", defaultLabel: "Speaker 1", customName: "Mina"),
            SpeakerDraft(id: "S2", defaultLabel: "Speaker 2", customName: "Jordan")
        ]

        let original = TranscriptRenderer.render(blocks: blocks, speakers: originalSpeakers)
        let renamed = TranscriptRenderer.render(blocks: blocks, speakers: renamedSpeakers)

        #expect(original.map(\.id) == renamed.map(\.id))
        #expect(renamed.map(\.label) == ["Mina", "Jordan"])
    }

    @Test
    func recordingMergeKeepsUserAndRemoteBlocksChronological() {
        let userBlocks = [
            TranscriptBlock(speakerID: RecordingTranscriptMerger.userSpeakerID, start: 5, end: 7, text: "I agree."),
            TranscriptBlock(speakerID: RecordingTranscriptMerger.userSpeakerID, start: 18, end: 20, text: "Next steps?")
        ]
        let remoteBlocks = [
            TranscriptBlock(speakerID: "S1", start: 0, end: 5, text: "Here is the plan."),
            TranscriptBlock(speakerID: "S2", start: 10, end: 18, text: "We should ship the smaller version.")
        ]

        let merged = RecordingTranscriptMerger.mergedBlocks(userBlocks: userBlocks, remoteBlocks: remoteBlocks)
        let speakers = RecordingTranscriptMerger.speakers(remoteSpeakerIDs: ["S1", "S2"])

        #expect(merged.map(\.speakerID) == ["S1", "USER", "S2", "USER"])
        #expect(speakers.map(\.defaultLabel) == ["You", "Speaker 1", "Speaker 2"])
        #expect(speakers[0].customName == "You")
        #expect(speakers[1].customName.isEmpty)
    }

    @Test
    func voiceActivityDetectorCreatesUserWindowsForSpeechBursts() {
        let sampleRate = 1_000
        let silence = Array(repeating: Float(0), count: 300)
        let speech = Array(repeating: Float(0.4), count: 500)
        let samples = silence + speech + silence + speech

        let windows = VoiceActivityDetector.windows(from: samples, sampleRate: sampleRate)

        #expect(windows.count >= 1)
        #expect(windows.allSatisfy { $0.speakerID == RecordingTranscriptMerger.userSpeakerID })
        #expect(windows[0].start >= 0.25)
        #expect(windows[0].end <= 1.65)
    }
}
