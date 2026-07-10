import Foundation
import Testing
@testable import Antrum

@Suite("Markdown output")
struct TranscriptMarkdownBuilderTests {
    @Test
    func buildsMarkdownWithSpeakerListTranscriptAndMergeNotes() {
        let speakers = [
            SpeakerDraft(id: "S1", defaultLabel: "Speaker 1", customName: "Mina"),
            SpeakerDraft(id: "S2", defaultLabel: "Speaker 2", customName: "Jordan", mergeTargetID: "S1")
        ]
        let blocks = [
            TranscriptBlock(speakerID: "S1", start: 0, end: 12, text: "Hello everyone,"),
            TranscriptBlock(speakerID: "S2", start: 12, end: 25, text: "welcome to the meeting.")
        ]

        let markdown = TranscriptMarkdownBuilder.markdown(
            title: "Meeting Transcript: Design Review",
            sourceFileName: "design-review.m4a",
            processedAt: Date(timeIntervalSince1970: 1_700_000_000),
            speakers: speakers,
            blocks: blocks
        )

        #expect(markdown.contains("# Meeting Transcript: Design Review"))
        #expect(markdown.contains("**Source file:** design-review.m4a"))
        #expect(markdown.contains("**Processed:** "))
        #expect(markdown.contains("## Speakers"))
        #expect(markdown.contains("- Speaker 1 — Mina"))
        #expect(markdown.contains("- Speaker 2 — Jordan (merged into Mina)"))
        #expect(markdown.contains("## Transcript"))
        #expect(markdown.contains("### Mina [0:00 – 0:25]"))
        #expect(markdown.contains("Hello everyone, welcome to the meeting."))
        #expect(markdown.hasSuffix("\n"))
    }

    @Test
    func recordingMarkdownPlacesOptInCalendarContextBeforeTranscriptMetadata() {
        let context = MeetingCalendarContext(
            title: "Design Review",
            calendarName: "Work",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            location: "Studio A"
        )

        let markdown = TranscriptMarkdownBuilder.markdown(
            title: "Meeting Transcript: Design Review",
            sourceFileName: "recording.caf",
            processedAt: Date(timeIntervalSince1970: 1_700_000_100),
            speakers: [],
            blocks: [],
            calendarContext: context
        )

        let calendarRange = try! #require(markdown.range(of: "## Calendar"))
        let sourceRange = try! #require(markdown.range(of: "**Source file:**"))
        #expect(calendarRange.lowerBound < sourceRange.lowerBound)
        #expect(markdown.contains("**Event:** Design Review"))
        #expect(markdown.contains("**Calendar:** Work"))
        #expect(markdown.contains("**Location:** Studio A"))
    }
}
