import AppKit
import AVFoundation
import Foundation
import SwiftUI

private enum PendingModelProcessing {
    case file(URL)
    case recording(MeetingRecordingArtifacts, MeetingCalendarContext?)
}

@MainActor
final class MeetingTranscriptionViewModel: ObservableObject {
    enum ViewMode: Equatable {
        case idle
        case recording
        case processing(stage: ProcessingStage, fileName: String)
        case review
        case failed(message: String)
    }

    @Published private(set) var mode: ViewMode = .idle
    @Published var sourceFileName: String = "Drop a file to begin"
    @Published var processedAt: Date = .now
    @Published var speakers: [SpeakerDraft] = []
    @Published var blocks: [TranscriptBlock] = []
    @Published var markdown: String = ""
    @Published private(set) var speakerRows: [SpeakerReviewRow] = []
    @Published private(set) var renderedTranscriptBlocks: [RenderedTranscriptBlock] = []
    @Published private(set) var visibleRenderedTranscriptBlocks: [RenderedTranscriptBlock] = []
    @Published private(set) var transcriptFilterOptions: [TranscriptFilterOption] = []
    @Published private(set) var selectedTranscriptSpeakerIDs: Set<String> = []
    @Published private(set) var reviewMetrics: ReviewMetrics = .empty
    @Published private(set) var processedAtDisplay: String = ""
    @Published private(set) var processingProgress: ProcessingProgressSnapshot?
    @Published private(set) var recordingProgress: RecordingProgressSnapshot?
    @Published private(set) var liveRecordingState: LiveRecordingState = .idle
    @Published var errorMessage: String?
    @Published var userMessage: UserMessage?
    @Published var newFileConfirmationRequest: UUID?
    @Published var recordingConsentRequest: UUID?
    @Published private(set) var modelSetupRequest: ModelSetupRequest?
    @Published private(set) var modelDownloadStates: [LocalModelPackageID: ModelDownloadState] = [:]
    @Published private(set) var calendarAccessState: CalendarAccessState = .notDetermined
    @Published private(set) var calendarAccessRequestInFlight = false
    @Published private(set) var includesCurrentSessionCalendarContext = false
    @Published var includesCalendarContext = false {
        didSet {
            UserDefaults.standard.set(includesCalendarContext, forKey: CalendarContextPolicy.preferenceKey)
        }
    }
    @Published var diarizationBackend: DiarizationBackend {
        didSet {
            UserDefaults.standard.set(diarizationBackend.rawValue, forKey: Self.diarizationBackendDefaultsKey)
        }
    }

    private let pipeline = LocalMeetingPipeline()
    private let recorder = LiveMeetingRecorder()
    private var currentSession: MeetingSession?
    private var processingTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var recordingStartupWatchdogTask: Task<Void, Never>?
    private var modelDownloadTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var processingRunID = UUID()
    private var activeRecordingInfo: RecordingSessionInfo?
    private var activeRecordingIncludesCalendarContext = false
    private var pendingModelProcessing: PendingModelProcessing?
    private let modelDownloads = LocalModelDownloadManager()
    private let calendarContextStore = CalendarContextStore()

    var canExport: Bool {
        guard !blocks.isEmpty else { return false }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !speakers.contains(where: { $0.customName.count > SpeakerNamePolicy.maxLength })
    }

    var exportStatusMessage: String {
        if blocks.isEmpty {
            return "No transcript to export."
        }
        if speakers.contains(where: { $0.customName.count > SpeakerNamePolicy.maxLength }) {
            return "Fix speaker name length before export."
        }
        return canExport ? "Markdown ready." : "Review before export."
    }

    var canStartNewFile: Bool {
        mode != .idle && !liveRecordingState.isActive
    }

    var progressStage: ProcessingStage? {
        if case let .processing(stage, _) = mode {
            return stage
        }
        return nil
    }

    var reviewTitle: String {
        currentSessionTitle
    }

    var currentSessionCalendarContext: MeetingCalendarContext? {
        currentSession?.calendarContext
    }

    init() {
        let storedBackend = UserDefaults.standard.string(forKey: Self.diarizationBackendDefaultsKey)
            .flatMap(DiarizationBackend.init(rawValue:))
        diarizationBackend = storedBackend ?? .defaultBackend
        calendarAccessState = calendarContextStore.authorizationState()
        includesCalendarContext = UserDefaults.standard.bool(forKey: CalendarContextPolicy.preferenceKey)
            && calendarAccessState.canReadEvents
    }

    func loadMockSession() {
        let mockURL = URL(fileURLWithPath: "/Users/coreyoneal/Documents/Antrum/test.wav")
        let mockSpeakers = [
            SpeakerDraft(id: "S1", defaultLabel: "Speaker 1", customName: "Mina"),
            SpeakerDraft(id: "S2", defaultLabel: "Speaker 2", customName: "Jordan", mergeTargetID: "S1"),
            SpeakerDraft(id: "S3", defaultLabel: "Speaker 3", customName: "Alex")
        ]
        let mockBlocks = [
            TranscriptBlock(speakerID: "S1", start: 0, end: 12, text: "Hello everyone, welcome to the Antrum design review pass."),
            TranscriptBlock(speakerID: "S2", start: 12, end: 25, text: "Thanks Mina. We should look closely at the corner radii of the panels and ensure the contrast ratios are legible."),
            TranscriptBlock(speakerID: "S3", start: 25, end: 40, text: "Yes, and make sure that we disable inputs for merged speakers to avoid confusion during the transcription review.")
        ]
        let session = MeetingSession(
            sourceURL: mockURL,
            processedAt: Date(),
            diarizationBackend: .nvidiaSortformerV21,
            diarizationFallbackReason: nil,
            speakers: mockSpeakers,
            blocks: mockBlocks
        )
        self.apply(session)
    }


    func acceptDroppedFile(url: URL) {
        guard modelSetupRequest == nil else {
            showUserMessage(title: "Model setup active", detail: "Finish setup before importing another file.", kind: .status)
            return
        }

        guard !liveRecordingState.isActive else {
            showUserMessage(title: "Recording active", detail: "Stop before importing.", kind: .status)
            return
        }

        guard SupportedMeetingFile.isSupported(url) else {
            errorMessage = "Unsupported file. Use .mp3, .wav, .m4a, .mp4, or .mov."
            mode = .failed(message: errorMessage ?? "Unsupported file.")
            return
        }

        guard !requestModelSetupIfNeeded(for: .file(url), diarizationBackend: diarizationBackend) else {
            return
        }

        processFile(url)
    }

    private func processFile(_ url: URL) {

        processingTask?.cancel()
        durationTask?.cancel()
        let runID = UUID()
        processingRunID = runID
        errorMessage = nil
        showUserMessage(title: "File accepted", detail: url.lastPathComponent, kind: .status)
        markdown = ""
        blocks = []
        speakers = []
        clearReviewDerivedState()
        processedAt = .now
        sourceFileName = url.lastPathComponent
        setProcessing(stage: .preparing, fileName: url.lastPathComponent)
        let backend = diarizationBackend

        durationTask = Task { [weak self] in
            guard let duration = await Self.loadMediaDuration(from: url) else { return }
            await MainActor.run {
                guard self?.processingRunID == runID else { return }
                self?.setProcessingMediaDuration(duration, fileName: url.lastPathComponent)
            }
        }

        processingTask = Task { [pipeline] in
            do {
                let session = try await pipeline.process(fileURL: url, diarizationBackend: backend) { [weak self] progress in
                    await MainActor.run {
                        guard let self else { return }
                        guard self.processingRunID == runID else { return }
                        self.setProcessing(
                            stage: progress.stage,
                            fileName: url.lastPathComponent,
                            mediaDuration: progress.mediaDuration,
                            stageFraction: progress.stageFraction
                        )
                    }
                }

                await MainActor.run {
                    guard self.processingRunID == runID else { return }
                    self.apply(session)
                    if session.diarizationFallbackReason == nil {
                        self.showUserMessage(title: "Transcript ready", detail: "Name speakers.", kind: .success)
                    } else {
                        self.showUserMessage(title: "Used Pyannote fallback", detail: "Sortformer unavailable.", kind: .status)
                    }
                }
            } catch is CancellationError {
                // A newer file was dropped.
            } catch {
                await MainActor.run {
                    guard self.processingRunID == runID else { return }
                    self.errorMessage = error.localizedDescription
                    self.showUserMessage(title: "Processing failed", detail: "Drop another file.", kind: .failure)
                    self.processingProgress = nil
                    self.mode = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    func requestLiveRecording() {
        guard modelSetupRequest == nil else {
            showUserMessage(title: "Model setup active", detail: "Finish setup before recording.", kind: .status)
            return
        }
        guard !liveRecordingState.isActive else { return }
        recordingConsentRequest = UUID()
    }

    func confirmLiveRecording() {
        recordingConsentRequest = nil
        startLiveRecording()
    }

    func cancelLiveRecordingRequest() {
        recordingConsentRequest = nil
    }

    func refreshCalendarAccess() {
        calendarAccessState = calendarContextStore.authorizationState()
        if !calendarAccessState.canReadEvents {
            includesCalendarContext = false
        }
    }

    func requestCalendarAccess() {
        guard calendarAccessState == .notDetermined, !calendarAccessRequestInFlight else { return }

        calendarAccessRequestInFlight = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let granted = try await self.calendarContextStore.requestFullAccess()
                self.refreshCalendarAccess()
                if granted && self.calendarAccessState.canReadEvents {
                    self.includesCalendarContext = true
                    self.showUserMessage(title: "Calendar connected", detail: "Recorded meetings can include the matching event.", kind: .success)
                } else {
                    self.showUserMessage(title: "Calendar access not granted", detail: "Recording and Markdown stay unchanged.", kind: .status)
                }
            } catch {
                self.refreshCalendarAccess()
                self.showUserMessage(title: "Calendar access failed", detail: error.localizedDescription, kind: .failure)
            }
            self.calendarAccessRequestInFlight = false
        }
    }

    func openCalendarPrivacySettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func setCurrentSessionCalendarContextIncluded(_ included: Bool) {
        guard currentSession?.calendarContext != nil else { return }
        includesCurrentSessionCalendarContext = included
        rebuildMarkdown()
        showUserMessage(
            title: included ? "Calendar context included" : "Calendar context excluded",
            detail: included ? "It will appear in this meeting's Markdown." : "It will stay out of this meeting's Markdown.",
            kind: .status
        )
    }

    func downloadModel(_ packageID: LocalModelPackageID) {
        guard let setupRequestID = modelSetupRequest?.id,
              modelDownloadTask == nil else {
            return
        }

        modelDownloadStates[packageID] = .downloading(0)
        let downloads = modelDownloads
        modelDownloadTask = Task { [weak self] in
            do {
                try await downloads.download(packageID) { [weak self] progress in
                    Task { @MainActor in
                        guard self?.modelSetupRequest?.id == setupRequestID else { return }
                        self?.modelDownloadStates[packageID] = .downloading(progress)
                    }
                }

                guard !Task.isCancelled else { return }
                guard self?.modelSetupRequest?.id == setupRequestID else { return }
                self?.modelDownloadStates[packageID] = .downloaded
                self?.showUserMessage(title: "Model ready", detail: "\(packageID.rawValue.capitalized) is ready locally.", kind: .success)
            } catch is CancellationError {
                // The user dismissed setup before the download completed.
            } catch {
                guard self?.modelSetupRequest?.id == setupRequestID else { return }
                self?.modelDownloadStates[packageID] = .failed(error.localizedDescription)
                self?.showUserMessage(title: "Model download failed", detail: error.localizedDescription, kind: .failure)
            }
            guard self?.modelSetupRequest?.id == setupRequestID else { return }
            self?.modelDownloadTask = nil
        }
    }

    func continueAfterModelSetup() {
        guard let request = modelSetupRequest,
              request.requiredPackageIDs.allSatisfy({ modelDownloadStates[$0] == .downloaded }),
              let pendingModelProcessing else {
            return
        }

        diarizationBackend = request.diarizationBackend
        modelSetupRequest = nil
        modelDownloadStates = [:]
        self.pendingModelProcessing = nil
        switch pendingModelProcessing {
        case .file(let url):
            processFile(url)
        case .recording(let artifacts, let calendarContext):
            processRecordingArtifacts(artifacts, calendarContext: calendarContext)
        }
    }

    func cancelModelSetup() {
        guard modelDownloadTask == nil else { return }
        modelSetupRequest = nil
        modelDownloadStates = [:]
        pendingModelProcessing = nil
    }

    private func startLiveRecording() {
        guard !liveRecordingState.isActive else { return }
        guard modelSetupRequest == nil else {
            showUserMessage(title: "Model setup active", detail: "Finish setup before recording.", kind: .status)
            return
        }

        refreshCalendarAccess()

        processingTask?.cancel()
        durationTask?.cancel()
        recordingTask?.cancel()
        recordingStartupWatchdogTask?.cancel()
        modelDownloadTask?.cancel()
        processingRunID = UUID()
        errorMessage = nil
        markdown = ""
        blocks = []
        speakers = []
        clearReviewDerivedState()
        processedAt = .now
        sourceFileName = "Live meeting"
        processingProgress = nil
        activeRecordingInfo = nil
        activeRecordingIncludesCalendarContext = includesCalendarContext && calendarAccessState.canReadEvents
        setRecordingState(.starting, info: nil)
        mode = .recording
        showUserMessage(title: "Starting recording", detail: "Requesting local capture.", kind: .status)
        startRecordingStartupWatchdog()

        recordingTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let info = try await self.recorder.start()
                try Task.checkCancellation()
                self.recordingStartupWatchdogTask?.cancel()
                self.recordingStartupWatchdogTask = nil
                self.activeRecordingInfo = info
                self.sourceFileName = info.displayName
                self.setRecordingState(
                    .recording(startedAt: info.startedAt, pausedAt: nil, accumulatedPausedDuration: 0),
                    info: info
                )
                self.mode = .recording
                self.showUserMessage(title: "Recording", detail: "Mic and meeting audio are separate.", kind: .success)
            } catch is CancellationError {
                // Stop/cancel took over cleanup.
            } catch {
                guard let self else { return }
                self.recordingStartupWatchdogTask?.cancel()
                self.recordingStartupWatchdogTask = nil
                self.activeRecordingInfo = nil
                self.activeRecordingIncludesCalendarContext = false
                self.setRecordingState(.idle, info: nil)
                self.errorMessage = error.localizedDescription
                self.mode = .failed(message: error.localizedDescription)
                self.showUserMessage(title: "Recording failed", detail: error.localizedDescription, kind: .failure)
            }
        }
    }

    func pauseLiveRecording() {
        guard case let .recording(startedAt, pausedAt, pausedDuration) = liveRecordingState,
              pausedAt == nil else {
            return
        }

        recorder.pause()
        setRecordingState(
            .recording(startedAt: startedAt, pausedAt: Date(), accumulatedPausedDuration: pausedDuration),
            info: activeRecordingInfo
        )
        showUserMessage(title: "Paused", detail: "Capture is paused.", kind: .status)
    }

    func resumeLiveRecording() {
        guard case let .recording(startedAt, pausedAt, pausedDuration) = liveRecordingState,
              let pausedAt else {
            return
        }

        recorder.resume()
        let accumulated = pausedDuration + Date().timeIntervalSince(pausedAt)
        setRecordingState(
            .recording(startedAt: startedAt, pausedAt: nil, accumulatedPausedDuration: accumulated),
            info: activeRecordingInfo
        )
        showUserMessage(title: "Recording", detail: "Capture resumed.", kind: .status)
    }

    func stopLiveRecording() {
        guard liveRecordingState.canStop else { return }

        if liveRecordingState == .starting {
            cancelStartingRecording(
                title: "Recording stopped",
                detail: "Startup canceled.",
                kind: .status
            )
            return
        }

        recordingStartupWatchdogTask?.cancel()
        recordingStartupWatchdogTask = nil
        setRecordingState(.stopping, info: activeRecordingInfo)
        mode = .recording
        showUserMessage(title: "Stopping", detail: "Saving separate tracks.", kind: .status)

        recordingTask?.cancel()
        recordingTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }
                let artifacts = try await self.recorder.stop()
                let calendarContext = self.activeRecordingIncludesCalendarContext
                    ? self.calendarContextStore.context(for: artifacts)
                    : nil
                self.activeRecordingInfo = nil
                self.activeRecordingIncludesCalendarContext = false
                self.setRecordingState(.idle, info: nil)
                self.processRecordingArtifacts(artifacts, calendarContext: calendarContext)
            } catch {
                guard let self else { return }
                self.activeRecordingInfo = nil
                self.activeRecordingIncludesCalendarContext = false
                self.setRecordingState(.idle, info: nil)
                self.errorMessage = error.localizedDescription
                self.mode = .failed(message: error.localizedDescription)
                self.showUserMessage(title: "Stop failed", detail: error.localizedDescription, kind: .failure)
            }
        }
    }

    func stopCaptureForTermination() async {
        guard liveRecordingState.isActive else { return }

        recordingStartupWatchdogTask?.cancel()
        recordingStartupWatchdogTask = nil
        recordingTask?.cancel()
        await recorder.cancel()
        activeRecordingInfo = nil
        activeRecordingIncludesCalendarContext = false
        setRecordingState(.idle, info: nil)
    }

    func updateSpeakerName(id: String, name: String) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[index].customName = name
        rebuildMarkdown()
        refreshReviewDerivedState()
    }

    func updateMergeTarget(id: String, targetID: String?) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[index].mergeTargetID = targetID
        rebuildMarkdown()
        normalizeSelectedTranscriptFilters()
        refreshReviewDerivedState()
        if let targetID {
            let targetName = SpeakerResolver.displayName(for: targetID, speakers: speakers)
            showUserMessage(title: "Speakers merged", detail: "Into \(targetName).", kind: .success)
        }
    }

    func copyMarkdownToClipboard() {
        guard canExport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        showUserMessage(title: "Copied", detail: "Markdown on clipboard.", kind: .success)
    }

    func saveMarkdownToFile() {
        guard canExport else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = exportFileName
        panel.title = "Save Markdown"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                showUserMessage(title: "Saved", detail: url.lastPathComponent, kind: .success)
            } catch {
                showUserMessage(title: "Save failed", detail: error.localizedDescription, kind: .failure)
            }
        }
    }

    func toggleTranscriptFilter(speakerID: String) {
        if selectedTranscriptSpeakerIDs.contains(speakerID) {
            selectedTranscriptSpeakerIDs.remove(speakerID)
        } else {
            selectedTranscriptSpeakerIDs.insert(speakerID)
        }
        refreshVisibleTranscriptBlocks()
    }

    func clearTranscriptFilters() {
        selectedTranscriptSpeakerIDs.removeAll()
        refreshVisibleTranscriptBlocks()
    }

    func requestNewFile() {
        guard modelSetupRequest == nil else {
            showUserMessage(title: "Model setup active", detail: "Finish setup before clearing.", kind: .status)
            return
        }
        guard canStartNewFile else { return }
        newFileConfirmationRequest = UUID()
    }

    func startNewFile() {
        guard !liveRecordingState.isActive else {
            showUserMessage(title: "Recording active", detail: "Stop before clearing.", kind: .status)
            return
        }
        guard modelDownloadTask == nil else {
            showUserMessage(title: "Model download active", detail: "Wait for the current download before clearing.", kind: .status)
            return
        }

        processingTask?.cancel()
        durationTask?.cancel()
        recordingTask?.cancel()
        recordingStartupWatchdogTask?.cancel()
        processingRunID = UUID()
        processingTask = nil
        durationTask = nil
        recordingTask = nil
        recordingStartupWatchdogTask = nil
        modelDownloadTask = nil
        modelSetupRequest = nil
        modelDownloadStates = [:]
        pendingModelProcessing = nil
        currentSession = nil
        newFileConfirmationRequest = nil
        errorMessage = nil
        markdown = ""
        blocks = []
        speakers = []
        clearReviewDerivedState()
        processedAt = .now
        sourceFileName = "Drop a file to begin"
        processingProgress = nil
        recordingProgress = nil
        mode = .idle
        showUserMessage(title: "Ready", detail: "Drop the next file.", kind: .status)
    }

    func cancelNewFileRequest() {
        newFileConfirmationRequest = nil
    }

    func clearError() {
        errorMessage = nil
        if case .failed = mode {
            processingProgress = nil
            mode = .idle
        }
    }

    func clearUserMessage() {
        messageTask?.cancel()
        userMessage = nil
    }

    func setDiarizationBackend(_ backend: DiarizationBackend) {
        guard modelSetupRequest == nil else {
            showUserMessage(title: "Model setup active", detail: "Finish setup before changing the speaker engine.", kind: .status)
            return
        }
        diarizationBackend = backend
        showUserMessage(title: "Speaker engine", detail: backend.displayName, kind: .status)
    }

    private func apply(_ session: MeetingSession) {
        durationTask?.cancel()
        durationTask = nil
        currentSession = session
        includesCurrentSessionCalendarContext = session.calendarContext != nil
        speakers = session.speakers
        blocks = session.blocks
        selectedTranscriptSpeakerIDs.removeAll()
        processedAt = session.processedAt
        sourceFileName = session.sourceURL.lastPathComponent
        processingProgress = nil
        mode = .review
        rebuildMarkdown()
        refreshReviewDerivedState()
    }

    private func processRecordingArtifacts(
        _ artifacts: MeetingRecordingArtifacts,
        calendarContext: MeetingCalendarContext?
    ) {
        guard !requestModelSetupIfNeeded(for: .recording(artifacts, calendarContext), diarizationBackend: diarizationBackend) else {
            mode = .idle
            return
        }

        startProcessingRecordingArtifacts(artifacts, calendarContext: calendarContext)
    }

    private func startProcessingRecordingArtifacts(
        _ artifacts: MeetingRecordingArtifacts,
        calendarContext: MeetingCalendarContext?
    ) {
        processingTask?.cancel()
        durationTask?.cancel()
        let runID = UUID()
        processingRunID = runID
        errorMessage = nil
        markdown = ""
        blocks = []
        speakers = []
        clearReviewDerivedState()
        processedAt = artifacts.stoppedAt
        sourceFileName = artifacts.displayName
        setProcessing(stage: .preparing, fileName: artifacts.displayName)
        showUserMessage(title: "Tracks saved", detail: artifacts.folderURL.lastPathComponent, kind: .success)
        let backend = diarizationBackend

        processingTask = Task { [pipeline] in
            do {
                let session = try await pipeline.process(
                    recording: artifacts,
                    diarizationBackend: backend,
                    calendarContext: calendarContext
                ) { [weak self] progress in
                    await MainActor.run {
                        guard let self else { return }
                        guard self.processingRunID == runID else { return }
                        self.setProcessing(
                            stage: progress.stage,
                            fileName: artifacts.displayName,
                            mediaDuration: progress.mediaDuration,
                            stageFraction: progress.stageFraction
                        )
                    }
                }

                await MainActor.run {
                    guard self.processingRunID == runID else { return }
                    self.apply(session)
                    if session.diarizationFallbackReason == nil {
                        self.showUserMessage(title: "Transcript ready", detail: "Name speakers.", kind: .success)
                    } else {
                        self.showUserMessage(title: "Used Pyannote fallback", detail: "Sortformer unavailable.", kind: .status)
                    }
                }
            } catch is CancellationError {
                // A newer file or recording superseded this processing run.
            } catch {
                await MainActor.run {
                    guard self.processingRunID == runID else { return }
                    self.errorMessage = error.localizedDescription
                    self.showUserMessage(title: "Processing failed", detail: "Record again or drop a file.", kind: .failure)
                    self.processingProgress = nil
                    self.mode = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    private func requestModelSetupIfNeeded(
        for pending: PendingModelProcessing,
        diarizationBackend: DiarizationBackend
    ) -> Bool {
        let requiredPackageIDs = LocalModelCatalog.requiredPackageIDs(for: diarizationBackend)
        let missingRequiredModel = requiredPackageIDs.contains { !LocalModelCatalog.isInstalled($0) }
        guard missingRequiredModel else { return false }

        pendingModelProcessing = pending
        modelSetupRequest = ModelSetupRequest(
            diarizationBackend: diarizationBackend,
            requiredPackageIDs: requiredPackageIDs
        )
        modelDownloadStates = Dictionary(
            uniqueKeysWithValues: LocalModelCatalog.packages.map { package in
                (package.id, LocalModelCatalog.isInstalled(package.id) ? .downloaded : .notDownloaded)
            }
        )
        showUserMessage(title: "Local models needed", detail: "Choose what to download before processing.", kind: .status)
        return true
    }

    private func showUserMessage(title: String, detail: String, kind: UserMessage.Kind) {
        messageTask?.cancel()
        userMessage = UserMessage(title: title, detail: detail, kind: kind)
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run {
                self?.userMessage = nil
            }
        }
    }

    private func startRecordingStartupWatchdog() {
        recordingStartupWatchdogTask?.cancel()
        recordingStartupWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: RecordingStartupPolicy.timeout)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.liveRecordingState == .starting else { return }
                self.cancelStartingRecording(
                    title: "Recording stalled",
                    detail: "Startup stopped safely. Try Record Meeting again.",
                    kind: .failure
                )
            }
        }
    }

    private func cancelStartingRecording(title: String, detail: String, kind: UserMessage.Kind) {
        guard liveRecordingState == .starting else { return }

        recordingStartupWatchdogTask?.cancel()
        recordingStartupWatchdogTask = nil
        setRecordingState(.stopping, info: activeRecordingInfo)
        mode = .recording
        showUserMessage(title: "Stopping", detail: "Canceling startup.", kind: .status)

        recordingTask?.cancel()
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.recorder.cancel()
            self.activeRecordingInfo = nil
            self.activeRecordingIncludesCalendarContext = false
            self.setRecordingState(.idle, info: nil)
            self.mode = .idle
            self.showUserMessage(title: title, detail: detail, kind: kind)
        }
    }

    func rebuildMarkdown() {
        guard let currentSession else {
            markdown = ""
            return
        }

        markdown = TranscriptMarkdownBuilder.markdown(
            title: currentSessionTitle,
            sourceFileName: currentSession.sourceURL.lastPathComponent,
            processedAt: processedAt,
            speakers: speakers,
            blocks: blocks,
            calendarContext: includesCurrentSessionCalendarContext ? currentSession.calendarContext : nil
        )
    }

    private var currentSessionTitle: String {
        let stem = currentSession?.sourceURL.deletingPathExtension().lastPathComponent ?? sourceFileName
        let normalized = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let capitalized = normalized.isEmpty ? "Meeting Transcript" : normalized
        return "Meeting Transcript: \(capitalized)"
    }

    private var exportFileName: String {
        let stem = currentSession?.sourceURL.deletingPathExtension().lastPathComponent ?? "meeting-transcript"
        return stem + ".md"
    }

    private func refreshReviewDerivedState() {
        speakerRows = speakers.map { speaker in
            SpeakerReviewRow(
                speaker: speaker,
                summary: TranscriptAligner.summary(for: speaker.id, speakers: speakers, blocks: blocks),
                mergeOptions: speakers.filter { $0.id != speaker.id }
            )
        }
        renderedTranscriptBlocks = TranscriptRenderer.render(blocks: blocks, speakers: speakers)
        normalizeSelectedTranscriptFilters()
        transcriptFilterOptions = Self.filterOptions(from: renderedTranscriptBlocks)
        refreshVisibleTranscriptBlocks()
        reviewMetrics = ReviewMetrics(
            speakerCount: "\(speakers.count)",
            blockCount: "\(blocks.count)",
            duration: Self.formatDuration(blocks.reduce(0) { $0 + max(0, $1.end - $1.start) })
        )
        processedAtDisplay = Self.processedAtFormatter.string(from: processedAt)
    }

    private func clearReviewDerivedState() {
        speakerRows = []
        renderedTranscriptBlocks = []
        visibleRenderedTranscriptBlocks = []
        transcriptFilterOptions = []
        selectedTranscriptSpeakerIDs = []
        reviewMetrics = .empty
        processedAtDisplay = ""
    }

    private func setProcessing(
        stage: ProcessingStage,
        fileName: String,
        mediaDuration: TimeInterval? = nil,
        stageFraction: Double? = nil
    ) {
        let previous = processingProgress
        let duration = mediaDuration ?? previous?.mediaDuration
        let startedAt = previous?.stage == stage ? previous?.startedAt ?? .now : Date()
        let fraction = stageFraction ?? (previous?.stage == stage ? previous?.stageFraction : nil)

        processingProgress = ProcessingProgressSnapshot(
            stage: stage,
            fileName: fileName,
            startedAt: startedAt,
            mediaDuration: duration,
            stageFraction: fraction.map { max(0, min(1, $0)) }
        )
        mode = .processing(stage: stage, fileName: fileName)
    }

    private func setRecordingState(_ state: LiveRecordingState, info: RecordingSessionInfo?) {
        liveRecordingState = state
        if state.isActive {
            recordingProgress = RecordingProgressSnapshot(
                state: state,
                displayName: info?.displayName ?? "Live meeting",
                folderURL: info?.folderURL
            )
        } else {
            recordingProgress = nil
        }
    }

    private func setProcessingMediaDuration(_ duration: TimeInterval, fileName: String) {
        guard case let .processing(stage, activeFileName) = mode,
              activeFileName == fileName else {
            return
        }

        setProcessing(stage: stage, fileName: fileName, mediaDuration: duration)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }

    private static func loadMediaDuration(from url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds > 0 ? seconds : nil
        } catch {
            return nil
        }
    }

    private func refreshVisibleTranscriptBlocks() {
        if selectedTranscriptSpeakerIDs.isEmpty {
            visibleRenderedTranscriptBlocks = renderedTranscriptBlocks
        } else {
            visibleRenderedTranscriptBlocks = renderedTranscriptBlocks.filter {
                selectedTranscriptSpeakerIDs.contains($0.speakerID)
            }
        }
    }

    private func normalizeSelectedTranscriptFilters() {
        selectedTranscriptSpeakerIDs = Set(selectedTranscriptSpeakerIDs.map {
            SpeakerResolver.canonicalSpeakerID(for: $0, speakers: speakers)
        })
    }

    private static func filterOptions(from blocks: [RenderedTranscriptBlock]) -> [TranscriptFilterOption] {
        var order: [String] = []
        var labelsByID: [String: String] = [:]
        var countsByID: [String: Int] = [:]

        for block in blocks {
            if labelsByID[block.speakerID] == nil {
                order.append(block.speakerID)
                labelsByID[block.speakerID] = block.label
            }
            countsByID[block.speakerID, default: 0] += 1
        }

        return order.map {
            TranscriptFilterOption(
                id: $0,
                label: labelsByID[$0] ?? SpeakerResolver.fallbackLabel(for: $0),
                blockCount: countsByID[$0] ?? 0
            )
        }
    }

    private static let processedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let diarizationBackendDefaultsKey = "diarizationBackend"
}

extension MeetingTranscriptionViewModel: @unchecked Sendable {}
