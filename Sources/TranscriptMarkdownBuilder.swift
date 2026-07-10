import Foundation

enum TranscriptMarkdownBuilder {
    static func markdown(
        title: String,
        sourceFileName: String,
        processedAt: Date,
        speakers: [SpeakerDraft],
        blocks: [TranscriptBlock],
        calendarContext: MeetingCalendarContext? = nil
    ) -> String {
        let groupedBlocks = TranscriptAligner.collapseAdjacentSameSpeaker(
            blocks.map { block in
                TranscriptBlock(
                    speakerID: SpeakerResolver.canonicalSpeakerID(for: block.speakerID, speakers: speakers),
                    start: block.start,
                    end: block.end,
                    text: block.text
                )
            }
        )

        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        if let calendarContext {
            lines.append("## Calendar")
            lines.append("")
            lines.append("**Event:** \(calendarContext.title)")
            lines.append("**Scheduled:** \(calendarContext.scheduledDisplay)")
            lines.append("**Calendar:** \(calendarContext.calendarName)")
            if let location = calendarContext.cleanLocation {
                lines.append("**Location:** \(location)")
            }
            lines.append("")
        }
        lines.append("**Source file:** \(sourceFileName)")
        lines.append("**Processed:** \(processedAtFormatter.string(from: processedAt))")
        lines.append("")
        lines.append("## Speakers")
        lines.append("")

        for speaker in speakers {
            lines.append(Self.speakerLine(for: speaker, speakers: speakers))
        }

        lines.append("")
        lines.append("## Transcript")
        lines.append("")

        for block in groupedBlocks {
            let label = SpeakerResolver.displayName(for: block.speakerID, speakers: speakers)
            let timeRange = Self.formatTimeRange(start: block.start, end: block.end)
            lines.append("### \(label) \(timeRange)")
            lines.append("")
            lines.append(block.text.isEmpty ? "_" : block.text)
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func formatTimeRange(start: TimeInterval, end: TimeInterval) -> String {
        guard end > 0 || start > 0 else { return "" }
        return "[\(formatTime(start)) – \(formatTime(end))]"
    }

    private static func speakerLine(for speaker: SpeakerDraft, speakers: [SpeakerDraft]) -> String {
        let customName = speaker.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = "- \(speaker.defaultLabel)"

        if !customName.isEmpty, customName != speaker.defaultLabel {
            line += " — \(customName)"
        }

        if let targetID = speaker.mergeTargetID {
            let targetLabel = SpeakerResolver.displayName(for: targetID, speakers: speakers)
            line += " (merged into \(targetLabel))"
        }

        return line
    }

    private static func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static let processedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

}
