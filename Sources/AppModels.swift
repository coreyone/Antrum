import Foundation

enum ProcessingStage: String, CaseIterable, Identifiable, Equatable, Sendable {
    case preparing = "Preparing"
    case transcribing = "Transcribing"
    case findingSpeakers = "Finding speakers"

    var id: String { rawValue }
}

struct ProcessingProgressSnapshot: Equatable {
    let stage: ProcessingStage
    let fileName: String
    let startedAt: Date
    let mediaDuration: TimeInterval?
    let stageFraction: Double?
}

struct PipelineProgress: Sendable {
    let stage: ProcessingStage
    let mediaDuration: TimeInterval?
    let stageFraction: Double?

    init(
        stage: ProcessingStage,
        mediaDuration: TimeInterval? = nil,
        stageFraction: Double? = nil
    ) {
        self.stage = stage
        self.mediaDuration = mediaDuration
        self.stageFraction = stageFraction
    }
}

enum LiveRecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording(startedAt: Date, pausedAt: Date?, accumulatedPausedDuration: TimeInterval)
    case stopping

    var isActive: Bool {
        switch self {
        case .idle:
            return false
        case .starting, .recording, .stopping:
            return true
        }
    }

    var isPaused: Bool {
        if case let .recording(_, pausedAt, _) = self {
            return pausedAt != nil
        }
        return false
    }

    var canPauseOrResume: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var canStop: Bool {
        isActive && self != .stopping
    }

    var dockBadge: String? {
        switch self {
        case .recording(_, let pausedAt, _):
            return pausedAt == nil ? "REC" : "PAUSE"
        case .starting:
            return "REC"
        case .stopping:
            return "SAVE"
        case .idle:
            return nil
        }
    }

    var menuBarPresentation: MenuBarRecordingPresentation {
        switch self {
        case .idle:
            return MenuBarRecordingPresentation(
                iconStyle: .monochromeWaveform,
                title: "",
                tint: .none,
                accessibilityDescription: "Antrum"
            )
        case .starting:
            return MenuBarRecordingPresentation(
                iconStyle: .rainbowWaveform,
                title: " REC",
                tint: .none,
                accessibilityDescription: "Starting recording"
            )
        case .recording(_, let pausedAt, _):
            return MenuBarRecordingPresentation(
                iconStyle: .rainbowWaveform,
                title: pausedAt == nil ? " REC" : " PAUSE",
                tint: .none,
                accessibilityDescription: pausedAt == nil ? "Recording" : "Recording paused"
            )
        case .stopping:
            return MenuBarRecordingPresentation(
                iconStyle: .rainbowWaveform,
                title: " SAVE",
                tint: .none,
                accessibilityDescription: "Stopping recording"
            )
        }
    }
}

struct MenuBarRecordingPresentation: Equatable, Sendable {
    let iconStyle: MenuBarRecordingIconStyle
    let title: String
    let tint: MenuBarRecordingTint
    let accessibilityDescription: String
}

enum MenuBarRecordingIconStyle: Equatable, Sendable {
    case monochromeWaveform
    case rainbowWaveform
}

enum MenuBarRecordingTint: Equatable, Sendable {
    case none
    case accent
    case red
}

enum MenuBarActivityPriority: Equatable, Sendable {
    case recording
    case dictation
    case meetingDetection
    case idle

    static func current(
        recordingState: LiveRecordingState,
        isDictationActive: Bool,
        isMeetingDetectionVisible: Bool
    ) -> MenuBarActivityPriority {
        if recordingState.isActive {
            return .recording
        }
        if isDictationActive {
            return .dictation
        }
        if isMeetingDetectionVisible {
            return .meetingDetection
        }
        return .idle
    }
}

struct RecordingProgressSnapshot: Equatable {
    let state: LiveRecordingState
    let displayName: String
    let folderURL: URL?
}

struct RecordingSessionInfo: Equatable, Sendable {
    let displayName: String
    let folderURL: URL
    let microphoneURL: URL
    let systemAudioURL: URL
    let startedAt: Date
}

struct MeetingRecordingArtifacts: Equatable, Sendable {
    let displayName: String
    let folderURL: URL
    let microphoneURL: URL
    let systemAudioURL: URL
    let startedAt: Date
    let stoppedAt: Date
}

enum SystemAudioCaptureBackend: Equatable, Sendable {
    case coreAudioProcessTap
}

struct MeetingAudioCaptureSettings: Equatable, Sendable {
    init() {}

    static func current(defaults: UserDefaults = .standard) -> MeetingAudioCaptureSettings {
        MeetingAudioCaptureSettings()
    }

    func enabledBackends(coreAudioTapSupported: Bool) -> [SystemAudioCaptureBackend] {
        coreAudioTapSupported ? [.coreAudioProcessTap] : []
    }
}

struct SystemAudioCapturePlan: Equatable, Sendable {
    let sampleRate: Int
    let channelCount: Int

    static let meetingAudio = SystemAudioCapturePlan(
        sampleRate: 16_000,
        channelCount: 1
    )
}

enum RecordingPerformanceBudget {
    static let idleCPUPercent = 1.0
    static let idleRSSMegabytes = 150
    static let activeRecordingCPUPercent = 15.0
    static let activeRecordingRSSMegabytes = 220
}

enum RecordingStartupPolicy {
    static let timeout: Duration = .seconds(12)
    static let timeoutSeconds: TimeInterval = 12
}

enum SupportedMeetingFile {
    static let extensions: Set<String> = ["mp3", "wav", "m4a", "mp4", "mov"]
    static let sortedExtensions = extensions.sorted()

    static func isSupported(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

enum DiarizationBackend: String, CaseIterable, Identifiable, Equatable {
    case nvidiaSortformerV21
    case pyannoteCoreML

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nvidiaSortformerV21:
            return "NVIDIA Sortformer v2.1"
        case .pyannoteCoreML:
            return "Pyannote CoreML"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .nvidiaSortformerV21:
            return "< 5 People"
        case .pyannoteCoreML:
            return "5 + People"
        }
    }

    var shortDisplaySubtitle: String {
        switch self {
        case .nvidiaSortformerV21:
            return "Sortformer v2.1"
        case .pyannoteCoreML:
            return "Pyannote"
        }
    }

    var shortTechLabel: String {
        switch self {
        case .nvidiaSortformerV21:
            return "NVIDIA Sortformer v2.1 speakers"
        case .pyannoteCoreML:
            return "Pyannote CoreML speakers"
        }
    }

    var selectionGuidance: String {
        switch self {
        case .nvidiaSortformerV21:
            return "Best for fewer than 5 people."
        case .pyannoteCoreML:
            return "Best for 5 or more people."
        }
    }

    static let defaultBackend: DiarizationBackend = .nvidiaSortformerV21
}

enum DiarizationFallbackPolicy {
    static func shouldFallbackToPyannote(after error: Error) -> Bool {
        !(error is CancellationError)
    }
}

struct DroppedMeetingFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let displayName: String
    let processedAt: Date
}

struct SpeakerDraft: Identifiable, Equatable {
    let id: String
    let defaultLabel: String
    var customName: String
    var mergeTargetID: String?

    init(id: String, defaultLabel: String, customName: String = "", mergeTargetID: String? = nil) {
        self.id = id
        self.defaultLabel = defaultLabel
        self.customName = customName
        self.mergeTargetID = mergeTargetID
    }
}

enum SpeakerNamePolicy {
    static let maxLength = 32

    static func validationMessage(for name: String) -> String? {
        name.count >= maxLength ? "Maximum length reached (\(maxLength) characters)." : nil
    }
}

struct SpeakerWindow: Identifiable, Equatable, Sendable {
    let id = UUID()
    let speakerID: String
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        max(0, end - start)
    }
}

struct TranscriptBlock: Identifiable, Equatable, Sendable {
    let id = UUID()
    let speakerID: String
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct SpeakerSummary: Equatable {
    let speakerID: String
    let displayName: String
    let defaultLabel: String
    let sampleText: String
    let duration: TimeInterval
    let blockCount: Int
    let isMerged: Bool
}

struct MeetingSession: Equatable {
    let sourceURL: URL
    let processedAt: Date
    let diarizationBackend: DiarizationBackend
    let diarizationFallbackReason: String?
    let speakers: [SpeakerDraft]
    let blocks: [TranscriptBlock]
    let calendarContext: MeetingCalendarContext?

    init(
        sourceURL: URL,
        processedAt: Date,
        diarizationBackend: DiarizationBackend,
        diarizationFallbackReason: String?,
        speakers: [SpeakerDraft],
        blocks: [TranscriptBlock],
        calendarContext: MeetingCalendarContext? = nil
    ) {
        self.sourceURL = sourceURL
        self.processedAt = processedAt
        self.diarizationBackend = diarizationBackend
        self.diarizationFallbackReason = diarizationFallbackReason
        self.speakers = speakers
        self.blocks = blocks
        self.calendarContext = calendarContext
    }
}

struct UserMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case status
        case failure
    }

    let id = UUID()
    let title: String
    let detail: String
    let kind: Kind
}

enum SpeakerResolver {
    static func canonicalSpeakerID(for speakerID: String, speakers: [SpeakerDraft]) -> String {
        var seen = Set<String>()
        var current = speakerID

        while let speaker = speakers.first(where: { $0.id == current }),
              let target = speaker.mergeTargetID,
              target != current,
              !seen.contains(target) {
            seen.insert(current)
            current = target
        }

        return current
    }

    static func speaker(for speakerID: String, speakers: [SpeakerDraft]) -> SpeakerDraft? {
        speakers.first { $0.id == speakerID }
    }

    static func displayName(for speakerID: String, speakers: [SpeakerDraft]) -> String {
        let canonicalID = canonicalSpeakerID(for: speakerID, speakers: speakers)
        guard let speaker = speaker(for: canonicalID, speakers: speakers) else {
            return fallbackLabel(for: speakerID)
        }
        let trimmed = speaker.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? speaker.defaultLabel : trimmed
    }

    static func fallbackLabel(for speakerID: String) -> String {
        let digits = speakerID.compactMap { $0.wholeNumberValue }
        guard !digits.isEmpty, let parsed = Int(digits.map(String.init).joined()) else {
            return speakerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Speaker" : speakerID
        }
        return "Speaker \(parsed)"
    }
}

enum TranscriptAligner {
    static func align(transcript: String, windows: [SpeakerWindow]) -> [TranscriptBlock] {
        let cleanedWindows = windows
            .sorted { $0.start < $1.start }
            .filter { $0.duration > 0 }

        guard !cleanedWindows.isEmpty else {
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [TranscriptBlock(speakerID: "S1", start: 0, end: 0, text: trimmed)]
        }

        let words = transcript
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)

        guard !words.isEmpty else {
            return cleanedWindows.map {
                TranscriptBlock(speakerID: $0.speakerID, start: $0.start, end: $0.end, text: "")
            }
        }

        let totalDuration = cleanedWindows.reduce(0) { $0 + $1.duration }
        var remainingWords = words[...]
        var provisionalBlocks: [TranscriptBlock] = []

        for (index, window) in cleanedWindows.enumerated() {
            if remainingWords.isEmpty { break }

            let windowsLeft = cleanedWindows.count - index
            let wordsForWindow: Int
            if windowsLeft == 1 {
                wordsForWindow = remainingWords.count
            } else if totalDuration > 0 {
                let idealShare = Double(words.count) * window.duration / totalDuration
                wordsForWindow = max(1, min(remainingWords.count - (windowsLeft - 1), Int(idealShare.rounded())))
            } else {
                wordsForWindow = max(1, remainingWords.count / windowsLeft)
            }

            let assigned = remainingWords.prefix(wordsForWindow)
            remainingWords.removeFirst(min(wordsForWindow, remainingWords.count))

            provisionalBlocks.append(
                TranscriptBlock(
                    speakerID: window.speakerID,
                    start: window.start,
                    end: window.end,
                    text: assigned.joined(separator: " ")
                )
            )
        }

        if !remainingWords.isEmpty, let lastIndex = provisionalBlocks.indices.last {
            let tail = remainingWords.joined(separator: " ")
            provisionalBlocks[lastIndex] = TranscriptBlock(
                speakerID: provisionalBlocks[lastIndex].speakerID,
                start: provisionalBlocks[lastIndex].start,
                end: provisionalBlocks[lastIndex].end,
                text: provisionalBlocks[lastIndex].text.isEmpty ? tail : provisionalBlocks[lastIndex].text + " " + tail
            )
        }

        return collapseAdjacentSameSpeaker(provisionalBlocks)
    }

    static func collapseAdjacentSameSpeaker(_ blocks: [TranscriptBlock]) -> [TranscriptBlock] {
        guard let first = blocks.first else { return [] }

        var collapsed: [TranscriptBlock] = [first]

        for block in blocks.dropFirst() {
            guard let last = collapsed.last else { continue }
            if last.speakerID == block.speakerID {
                collapsed[collapsed.count - 1] = TranscriptBlock(
                    speakerID: last.speakerID,
                    start: last.start,
                    end: block.end,
                    text: [last.text, block.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                )
            } else {
                collapsed.append(block)
            }
        }

        return collapsed
    }

    static func summary(for speakerID: String, speakers: [SpeakerDraft], blocks: [TranscriptBlock]) -> SpeakerSummary {
        let canonicalID = SpeakerResolver.canonicalSpeakerID(for: speakerID, speakers: speakers)
        let originalSpeaker = SpeakerResolver.speaker(for: speakerID, speakers: speakers)
        let speaker = SpeakerResolver.speaker(for: canonicalID, speakers: speakers)
        let filteredBlocks = blocks.filter {
            SpeakerResolver.canonicalSpeakerID(for: $0.speakerID, speakers: speakers) == canonicalID
        }
        let sampleText = filteredBlocks.first?.text ?? ""
        let duration = filteredBlocks.reduce(0) { $0 + max(0, $1.end - $1.start) }
        let trimmed = speaker?.customName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return SpeakerSummary(
            speakerID: canonicalID,
            displayName: trimmed.isEmpty ? speaker?.defaultLabel ?? SpeakerResolver.fallbackLabel(for: speakerID) : trimmed,
            defaultLabel: originalSpeaker?.defaultLabel ?? SpeakerResolver.fallbackLabel(for: speakerID),
            sampleText: sampleText,
            duration: duration,
            blockCount: filteredBlocks.count,
            isMerged: originalSpeaker?.mergeTargetID != nil
        )
    }
}

enum RecordingTranscriptMerger {
    static let userSpeakerID = "USER"
    static let userDefaultLabel = "You"

    static func mergedBlocks(userBlocks: [TranscriptBlock], remoteBlocks: [TranscriptBlock]) -> [TranscriptBlock] {
        (userBlocks + remoteBlocks)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                if $0.start == $1.start {
                    return $0.end < $1.end
                }
                return $0.start < $1.start
            }
    }

    static func speakers(remoteSpeakerIDs: [String]) -> [SpeakerDraft] {
        [SpeakerDraft(id: userSpeakerID, defaultLabel: userDefaultLabel, customName: userDefaultLabel)]
            + remoteSpeakerIDs.enumerated().map { index, speakerID in
                SpeakerDraft(id: speakerID, defaultLabel: "Speaker \(index + 1)")
            }
    }
}

enum VoiceActivityDetector {
    static func containsSpeech(in samples: [Float], sampleRate: Int = 16_000) -> Bool {
        !windows(from: samples, sampleRate: sampleRate).isEmpty
    }

    static func windows(
        from samples: [Float],
        sampleRate: Int = 16_000,
        fallbackDuration: TimeInterval? = nil
    ) -> [SpeakerWindow] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }

        let frameSize = max(1, sampleRate / 20)
        var frames: [(index: Int, rms: Float)] = []
        var offset = 0

        while offset < samples.count {
            let upperBound = min(samples.count, offset + frameSize)
            let slice = samples[offset..<upperBound]
            let meanSquare = slice.reduce(Float(0)) { partial, sample in
                partial + sample * sample
            } / Float(max(1, slice.count))
            frames.append((index: offset / frameSize, rms: sqrt(meanSquare)))
            offset += frameSize
        }

        guard let maxRMS = frames.map(\.rms).max(), maxRMS > 0 else {
            return fallbackWindow(duration: fallbackDuration)
        }

        let sortedRMS = frames.map(\.rms).sorted()
        let lowerQuartile = sortedRMS[max(0, sortedRMS.count / 4)]
        let threshold = max(Float(0.012), lowerQuartile * 2.5, maxRMS * 0.12)
        let frameDuration = TimeInterval(frameSize) / TimeInterval(sampleRate)
        let maxSilenceFrames = max(1, Int((0.45 / frameDuration).rounded()))
        let minSpeechDuration: TimeInterval = 0.20

        var windows: [SpeakerWindow] = []
        var activeStartFrame: Int?
        var trailingSilence = 0

        for frame in frames {
            if frame.rms >= threshold {
                if activeStartFrame == nil {
                    activeStartFrame = frame.index
                }
                trailingSilence = 0
            } else if activeStartFrame != nil {
                trailingSilence += 1
                if trailingSilence > maxSilenceFrames {
                    let endFrame = max(frame.index - trailingSilence + 1, activeStartFrame ?? frame.index)
                    appendWindow(
                        startFrame: activeStartFrame,
                        endFrame: endFrame,
                        frameDuration: frameDuration,
                        minSpeechDuration: minSpeechDuration,
                        to: &windows
                    )
                    activeStartFrame = nil
                    trailingSilence = 0
                }
            }
        }

        if let activeStartFrame {
            appendWindow(
                startFrame: activeStartFrame,
                endFrame: frames.count,
                frameDuration: frameDuration,
                minSpeechDuration: minSpeechDuration,
                to: &windows
            )
        }

        if windows.isEmpty {
            return fallbackWindow(duration: fallbackDuration ?? TimeInterval(samples.count) / TimeInterval(sampleRate))
        }

        return windows
    }

    private static func appendWindow(
        startFrame: Int?,
        endFrame: Int,
        frameDuration: TimeInterval,
        minSpeechDuration: TimeInterval,
        to windows: inout [SpeakerWindow]
    ) {
        guard let startFrame else { return }
        let start = TimeInterval(startFrame) * frameDuration
        let end = TimeInterval(max(startFrame + 1, endFrame)) * frameDuration
        guard end - start >= minSpeechDuration else { return }
        windows.append(SpeakerWindow(speakerID: RecordingTranscriptMerger.userSpeakerID, start: start, end: end))
    }

    private static func fallbackWindow(duration: TimeInterval?) -> [SpeakerWindow] {
        guard let duration, duration > 0 else { return [] }
        return [SpeakerWindow(speakerID: RecordingTranscriptMerger.userSpeakerID, start: 0, end: duration)]
    }
}

struct ReviewMetrics: Equatable {
    let speakerCount: String
    let blockCount: String
    let duration: String

    var speakerCountLabel: String {
        "\(speakerCount) \(speakerCount == "1" ? "speaker" : "speakers")"
    }

    var blockCountLabel: String {
        "\(blockCount) \(blockCount == "1" ? "block" : "blocks")"
    }

    static let empty = ReviewMetrics(speakerCount: "0", blockCount: "0", duration: "0m 00s")
}

struct SpeakerReviewRow: Identifiable, Equatable {
    let id: String
    let speaker: SpeakerDraft
    let summary: SpeakerSummary
    let mergeOptions: [SpeakerDraft]

    init(speaker: SpeakerDraft, summary: SpeakerSummary, mergeOptions: [SpeakerDraft]) {
        id = speaker.id
        self.speaker = speaker
        self.summary = summary
        self.mergeOptions = mergeOptions
    }
}

struct RenderedTranscriptBlock: Identifiable, Equatable {
    let id: String
    let speakerID: String
    let label: String
    let timeRange: String
    let text: String
}

struct TranscriptFilterOption: Identifiable, Equatable {
    let id: String
    let label: String
    let blockCount: Int
}

enum TranscriptRenderer {
    static func render(blocks: [TranscriptBlock], speakers: [SpeakerDraft]) -> [RenderedTranscriptBlock] {
        TranscriptAligner.collapseAdjacentSameSpeaker(blocks.map { block in
            TranscriptBlock(
                speakerID: SpeakerResolver.canonicalSpeakerID(for: block.speakerID, speakers: speakers),
                start: block.start,
                end: block.end,
                text: block.text
            )
        })
        .map { block in
            RenderedTranscriptBlock(
                id: stableID(for: block),
                speakerID: block.speakerID,
                label: SpeakerResolver.displayName(for: block.speakerID, speakers: speakers),
                timeRange: timeRange(start: block.start, end: block.end),
                text: block.text
            )
        }
    }

    private static func stableID(for block: TranscriptBlock) -> String {
        "\(block.speakerID)-\(milliseconds(block.start))-\(milliseconds(block.end))"
    }

    private static func milliseconds(_ interval: TimeInterval) -> Int {
        Int((interval * 1_000).rounded())
    }

    private static func timeRange(start: TimeInterval, end: TimeInterval) -> String {
        guard end > 0 || start > 0 else { return "" }
        return "[\(formatTime(start)) – \(formatTime(end))]"
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
}
