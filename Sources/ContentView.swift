import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: MeetingTranscriptionViewModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var presentationManager: AppPresentationManager
    @ObservedObject var dictationController: DictationController
    @ObservedObject var meetingDetectionController: MeetingDetectionController
    @State private var isDropTargeted = false
    @State private var isShowingNewFileConfirmation = false
    @State private var isShowingRecordingConsent = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingCalendarContextHelp = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            AppBackdropView()

            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                sidebarDrawerView
                    .padding(.top, hiddenTitleBarTopInset)
                    .padding(.horizontal, AppTheme.Space.md)
                    .padding(.bottom, AppTheme.Space.md)
                    .navigationSplitViewColumnWidth(min: 206, ideal: 216, max: 236)
            } detail: {
                stateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: stateViewVerticalAlignment)
                    .frame(maxWidth: 1040)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, AppTheme.Space.xxl)
                    .padding(.top, hiddenTitleBarTopInset)
                    .padding(.bottom, AppTheme.Space.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationSplitViewStyle(.balanced)

            if let userMessage = viewModel.userMessage {
                HStack {
                    Spacer()
                    ToastView(message: userMessage) {
                        viewModel.clearUserMessage()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 11)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }

            if let request = viewModel.modelSetupRequest {
                AppTheme.nearBlack.opacity(0.14)
                    .ignoresSafeArea()
                    .zIndex(20)

                ModelSetupPopover(
                    request: request,
                    states: viewModel.modelDownloadStates,
                    download: viewModel.downloadModel,
                    continueProcessing: viewModel.continueAfterModelSetup,
                    cancel: viewModel.cancelModelSetup
                )
                .zIndex(21)
            }
        }
        .frame(
            minWidth: AppWindowSizePolicy.minimumContentSize.width,
            maxWidth: .infinity,
            minHeight: AppWindowSizePolicy.minimumContentSize.height,
            maxHeight: .infinity
        )
        .tint(AppTheme.focus)
        .preferredColorScheme(.dark)
        .background(
            MainWindowAccessor { window in
                presentationManager.configureMainWindow(
                    window,
                    mode: viewModel.mode,
                    hasModelSetup: viewModel.modelSetupRequest != nil
                )
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Antrum local transcription")
        .animation(.easeOut(duration: 0.18), value: viewModel.userMessage?.id)
        .onChange(of: viewModel.newFileConfirmationRequest) { _, request in
            guard request != nil else { return }
            isShowingNewFileConfirmation = true
        }
        .onChange(of: viewModel.recordingConsentRequest) { _, request in
            guard request != nil else { return }
            isShowingRecordingConsent = true
        }
        .confirmationDialog(
            "Clear transcript?",
            isPresented: $isShowingNewFileConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear and Drop New File", role: .destructive) {
                viewModel.startNewFile()
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelNewFileRequest()
            }
        } message: {
            Text("Export first if you need this Markdown.")
        }
        .confirmationDialog(
            RecordingConsentPolicy.title,
            isPresented: $isShowingRecordingConsent,
            titleVisibility: .visible
        ) {
            Button(RecordingConsentPolicy.confirmationAction) {
                viewModel.confirmLiveRecording()
            }

            Button("Cancel", role: .cancel) {
                viewModel.cancelLiveRecordingRequest()
            }
        } message: {
            Text(RecordingConsentPolicy.message)
        }
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .onAppear {
            presentationManager.onRecordMeeting = { viewModel.requestLiveRecording() }
            presentationManager.onTranscribeFile = { viewModel.requestNewFile() }
            presentationManager.onPauseRecording = { viewModel.pauseLiveRecording() }
            presentationManager.onResumeRecording = { viewModel.resumeLiveRecording() }
            presentationManager.onStopRecording = { viewModel.stopLiveRecording() }
            presentationManager.onOpenMainWindow = { openWindow(id: AntrumApp.mainWindowID) }
            presentationManager.configureDictation(dictationController)
            presentationManager.configureMeetingDetection(meetingDetectionController)
            AppDelegate.presentMainWindow = { [weak presentationManager] in
                presentationManager?.presentMainWindow()
            }
            meetingDetectionController.onRecord = { viewModel.requestLiveRecording() }
            meetingDetectionController.setRecordingActive(viewModel.liveRecordingState.isActive)
            meetingDetectionController.setDictationActive(dictationController.state.isActive)
            meetingDetectionController.start()
            presentationManager.updateRecordingState(viewModel.liveRecordingState)
            AppDelegate.prepareForTermination = { await viewModel.stopCaptureForTermination() }
            viewModel.refreshCalendarAccess()
        }
        .onChange(of: viewModel.liveRecordingState) { _, state in
            meetingDetectionController.setRecordingActive(state.isActive)
            presentationManager.updateRecordingState(state)
        }
        .onChange(of: dictationController.state) { _, state in
            meetingDetectionController.setDictationActive(state.isActive)
        }
        .onChange(of: viewModel.mode) { _, mode in
            presentationManager.updateMainWindowSize(
                for: mode,
                hasModelSetup: viewModel.modelSetupRequest != nil
            )
        }
        .onChange(of: viewModel.modelSetupRequest) { _, request in
            presentationManager.updateMainWindowSize(
                for: viewModel.mode,
                hasModelSetup: request != nil
            )
        }
    }

    private var hiddenTitleBarTopInset: CGFloat {
        34
    }

    private var sidebarDrawerView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xl) {
            HStack(spacing: AppTheme.Space.sm) {
                PixelGlyphView(size: 18)

                Text("Antrum")
                    .font(AppTheme.Typography.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                SidebarStepItem(number: 1, title: "Dictate")
                SidebarStepItem(number: 2, title: "Record meetings")
                SidebarStepItem(number: 3, title: "Transcribe files")
            }

            Spacer(minLength: AppTheme.Space.page)

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                if dictationController.isFeatureEnabled {
                    Button {
                        dictationController.showSettings()
                    } label: {
                        Text("Dictation Settings")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Open dictation settings.")
                }

                Button {
                    isShowingPrivacyPolicy = true
                } label: {
                    Text("Privacy")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("View how Antrum handles meeting data.")
            }
        }
        .padding(AppTheme.Space.sm)
        .frame(width: 190, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Antrum navigation")
    }

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.mode {
        case .idle:
            landingView(errorMessage: nil)
        case .failed:
            landingView(errorMessage: viewModel.errorMessage)
        case .recording:
            recordingView
        case .processing:
            processingView
        case .review:
            reviewView
        }
    }

    private var stateViewVerticalAlignment: Alignment {
        switch viewModel.mode {
        case .idle, .failed, .recording, .processing, .review:
            return .top
        }
    }

    private func landingView(errorMessage: String?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: AppTheme.Space.lg)

            VStack(spacing: AppTheme.Space.lg) {
                creationOptionsView

                if let errorMessage {
                    ErrorBanner(message: errorMessage) {
                        viewModel.clearError()
                    }
                    .frame(width: 560)
                }

                TechFootnote(presentationManager: presentationManager)
                    .frame(maxWidth: 700)
            }

            Spacer(minLength: AppTheme.Space.md)

            localTranscriptionFooter
        }
        .frame(maxWidth: 760, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, AppTheme.Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Record or upload local audio")
    }

    private var localTranscriptionFooter: some View {
        Text("Transcribe locally.")
            .font(AppTheme.Typography.micro)
            .foregroundStyle(AppTheme.softInk)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, AppTheme.Space.xs)
            .accessibilityLabel("Transcribe locally. Local transcription uses Parakeet and FluidAudio.")
    }

    private var recordingView: some View {
        VStack(spacing: AppTheme.Space.xxxl) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: AppTheme.Space.xxl) {
                HStack(alignment: .center, spacing: AppTheme.Space.md) {
                    RecordingPulseView(isPaused: viewModel.liveRecordingState.isPaused)

                    VStack(alignment: .leading, spacing: AppTheme.Space.xxs) {
                        Text(recordingTitle)
                            .font(AppTheme.Typography.section)
                            .foregroundStyle(AppTheme.ink)

                        Text(recordingSubtitle)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.softInk)
                    }

                    Spacer(minLength: 16)

                    RecordingTimerView(state: viewModel.liveRecordingState)
                }

                VStack(alignment: .leading, spacing: AppTheme.Space.md) {
                    RecordingTrackRow(title: "Microphone", detail: "User voice", isActive: viewModel.liveRecordingState.isActive)
                    RecordingTrackRow(title: "Meeting audio", detail: "Remote speakers via system audio", isActive: viewModel.liveRecordingState.isActive)
                }

                Text("For cleaner speaker labels, use headphones.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)

                HStack {
                    Spacer()

                    Button(viewModel.liveRecordingState.isPaused ? "Resume" : "Pause") {
                        if viewModel.liveRecordingState.isPaused {
                            viewModel.resumeLiveRecording()
                        } else {
                            viewModel.pauseLiveRecording()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canUseRecordingControls)
                    .help(viewModel.liveRecordingState.isPaused ? "Resume microphone and meeting audio capture." : "Pause microphone and meeting audio capture.")

                    Button("Stop") {
                        viewModel.stopLiveRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.liveRecordingState.canStop)
                    .help("Stop recording and process the separate audio tracks.")
                }
                .appGlassGroup(spacing: AppTheme.Space.lg)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .chunkyPanel()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var processingView: some View {
        VStack(spacing: AppTheme.Space.xxxl) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: AppTheme.Space.xxl) {
                Text("Processing audio...")
                    .font(AppTheme.Typography.section)
                    .foregroundStyle(AppTheme.ink)

                if let progress = viewModel.processingProgress {
                    ProcessingStagesView(progress: progress)
                }

                ProcessingSkeletonView()

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.startNewFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Cancel active transcription and drop another file.")
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .chunkyPanel()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var reviewView: some View {
        VStack(spacing: AppTheme.Space.xxl) {
            reviewHeaderView

            HStack(alignment: .top, spacing: AppTheme.Space.xxl) {
                speakerPanel
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                transcriptPanel
                    .frame(minWidth: 400)
                    .frame(maxHeight: .infinity)
            }
            .appGlassGroup(spacing: AppTheme.Space.xxl)
            .frame(maxHeight: .infinity)

            footerView
        }
        .frame(maxHeight: .infinity)
    }

    private var reviewHeaderView: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.md) {
            PixelGlyphView(size: 18)

            Text("Antrum")
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)

            Text("•")
                .foregroundStyle(AppTheme.quietBorder)

            Text(viewModel.sourceFileName)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)

            Text(viewModel.processedAtDisplay)
                .font(AppTheme.Typography.micro)
                .foregroundStyle(AppTheme.softInk)
                .lineLimit(1)

            Spacer(minLength: 16)

            HStack(spacing: AppTheme.Space.md) {
                Text(viewModel.reviewMetrics.speakerCountLabel)
                Text("·")
                Text(viewModel.reviewMetrics.blockCountLabel)
                Text("·")
                Text(viewModel.reviewMetrics.duration)
            }
            .font(AppTheme.Typography.captionStrong)
            .foregroundStyle(AppTheme.softInk)
            .padding(.horizontal, AppTheme.Space.md)
            .padding(.vertical, 5)
            .appGlassStatusSurface()

            Button("New File") {
                viewModel.requestNewFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Clear this transcript and return to the drop target.")
        }
        .padding(.horizontal, AppTheme.Space.sm)
        .padding(.vertical, AppTheme.Space.xs)
        .thinHeaderSurface()
    }

    private var speakerPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xl) {
            SectionHeader(
                title: "Speakers",
                subtitle: "Rename or merge speakers."
            )

            ScrollView {
                if viewModel.speakerRows.isEmpty {
                    EmptyPanelState(title: "No speakers", detail: "Transcript can still export.")
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.speakerRows) { row in
                            SpeakerRowView(
                                speaker: row.speaker,
                                summary: row.summary,
                                allSpeakers: viewModel.speakers,
                                mergeOptions: row.mergeOptions,
                                onNameChange: { newName in
                                    viewModel.updateSpeakerName(id: row.speaker.id, name: newName)
                                },
                                onMergeChange: { target in
                                    viewModel.updateMergeTarget(id: row.speaker.id, targetID: target)
                                }
                            )
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .chunkyPanel()
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xl) {
            SectionHeader(
                title: "Transcript",
                subtitle: "Aligned transcript preview."
            )

            if let calendarContext = viewModel.currentSessionCalendarContext,
               viewModel.includesCurrentSessionCalendarContext {
                TranscriptCalendarContextCard(calendarContext: calendarContext) {
                    viewModel.setCurrentSessionCalendarContextIncluded(false)
                }
            }

            if viewModel.transcriptFilterOptions.count > 1 {
                TranscriptFilterBar(
                    options: viewModel.transcriptFilterOptions,
                    selectedSpeakerIDs: viewModel.selectedTranscriptSpeakerIDs,
                    visibleCount: viewModel.visibleRenderedTranscriptBlocks.count,
                    totalCount: viewModel.renderedTranscriptBlocks.count,
                    onToggle: { speakerID in
                        viewModel.toggleTranscriptFilter(speakerID: speakerID)
                    },
                    onClear: {
                        viewModel.clearTranscriptFilters()
                    }
                )
            }

            ScrollView {
                if viewModel.visibleRenderedTranscriptBlocks.isEmpty {
                    EmptyPanelState(title: "No speech found", detail: "Check mic or meeting audio.")
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.visibleRenderedTranscriptBlocks) { block in
                            TranscriptBlockView(block: block)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .chunkyPanel()
    }

    private var footerView: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.xxl) {
            Text(viewModel.exportStatusMessage)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(viewModel.canExport ? AppTheme.softInk : AppTheme.ink)

            if let calendarContext = viewModel.currentSessionCalendarContext {
                Toggle(isOn: Binding(
                    get: { viewModel.includesCurrentSessionCalendarContext },
                    set: { viewModel.setCurrentSessionCalendarContextIncluded($0) }
                )) {
                    Label(
                        "Calendar: \(calendarContext.title)",
                        systemImage: viewModel.includesCurrentSessionCalendarContext ? "calendar.badge.checkmark" : "calendar"
                    )
                    .font(AppTheme.Typography.microBold)
                    .lineLimit(1)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Include this matched calendar event in the Markdown for this meeting only.")
            }

            Spacer(minLength: 16)

            HStack(spacing: AppTheme.Space.lg) {
                Button("Copy Markdown") {
                    viewModel.copyMarkdownToClipboard()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!viewModel.canExport)
                .help("Copy the full speaker-labeled Markdown transcript.")

                Button("Save .md File") {
                    viewModel.saveMarkdownToFile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canExport)
                .help("Save the full speaker-labeled transcript as a Markdown file.")
            }
        }
        .padding(.horizontal, AppTheme.Space.sm)
    }

    private var creationOptionsView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xl) {
            HStack(alignment: .top, spacing: AppTheme.Space.xl) {
                VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                    Text("New recording")
                        .font(AppTheme.Typography.captionStrong)
                        .foregroundStyle(AppTheme.ink)

                    Button("Record Meeting") {
                        viewModel.requestLiveRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.liveRecordingState.isActive)
                    .help("Capture microphone and meeting audio as separate local tracks. Processing stays on this Mac.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(AppTheme.quietBorder)
                    .opacity(0.72)
                    .frame(width: AppTheme.Stroke.hairline, height: 92)

                VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                    Text("Upload File")
                        .font(AppTheme.Typography.captionStrong)
                        .foregroundStyle(AppTheme.ink)

                    HStack(spacing: AppTheme.Space.sm) {
                        ForEach(SupportedMeetingFile.sortedExtensions, id: \.self) { fileType in
                            Text(".\(fileType)")
                                .font(AppTheme.Typography.microStrong)
                                .foregroundStyle(AppTheme.softInk)
                                .lineLimit(1)
                                .frame(width: 38, height: 24)
                                .appGlassStatusSurface()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            calendarContextControl
        }
        .padding(AppTheme.Space.xxl)
        .frame(width: 560)
        .modifier(PrimaryCreationSurface(isActive: isDropTargeted))
        .scaleEffect(isDropTargeted ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .help("Record live audio or drop .mp3, .wav, .m4a, .mp4, or .mov. All processing stays on this Mac.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New recording and upload file")
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async {
                    viewModel.acceptDroppedFile(url: url)
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var calendarContextControl: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.md) {
            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.ink)
                .frame(width: 18)

            Button {
                isShowingCalendarContextHelp.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Calendar Details to .MD")
                        .font(AppTheme.Typography.captionStrong)
                        .foregroundStyle(AppTheme.softInk)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(CalendarContextPolicy.matchingRule)
            .popover(isPresented: $isShowingCalendarContextHelp, arrowEdge: .bottom) {
                CalendarContextHelpPopover()
            }

            Spacer(minLength: AppTheme.Space.sm)

            switch viewModel.calendarAccessState {
            case .fullAccess:
                Toggle("Add Calendar Details to .MD", isOn: Binding(
                    get: { viewModel.includesCalendarContext },
                    set: { viewModel.includesCalendarContext = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Add Calendar Details to .MD")
                .accessibilityValue(viewModel.includesCalendarContext ? "On" : "Off")
                .help(CalendarContextPolicy.matchingRule)
            case .notDetermined:
                if viewModel.calendarAccessRequestInFlight {
                    HStack(spacing: AppTheme.Space.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for macOS…")
                            .font(AppTheme.Typography.microBold)
                            .foregroundStyle(AppTheme.softInk)
                    }
                    .accessibilityLabel("Waiting for macOS Calendar permission")
                } else {
                    Button("Allow Calendar Access") {
                        viewModel.requestCalendarAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help(CalendarContextPolicy.matchingRule)
                }
            case .denied:
                Button("Open Settings") {
                    viewModel.openCalendarPrivacySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Allow Calendar access for Antrum in System Settings to enable this option.")
            case .restricted:
                Text("Access unavailable")
                    .font(AppTheme.Typography.microBold)
                    .foregroundStyle(AppTheme.softInk)
            }
        }
        .help(CalendarContextPolicy.matchingRule)
        .accessibilityElement(children: .contain)
    }

    private var canUseRecordingControls: Bool {
        viewModel.liveRecordingState.canPauseOrResume
    }

    private var recordingTitle: String {
        if viewModel.liveRecordingState == .starting {
            return "Starting recording..."
        }
        if viewModel.liveRecordingState == .stopping {
            return "Saving recording..."
        }
        return viewModel.liveRecordingState.isPaused ? "Recording paused" : "Recording meeting"
    }

    private var recordingSubtitle: String {
        "Recording locally."
    }
}

private struct ProcessingStagesView: View {
    let progress: ProcessingProgressSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let activeIndex = ProcessingStage.allCases.firstIndex(of: progress.stage) ?? 0

            VStack(alignment: .leading, spacing: AppTheme.Space.md) {
                HStack(alignment: .center, spacing: AppTheme.Space.sm) {
                    ForEach(Array(ProcessingStage.allCases.enumerated()), id: \.offset) { index, stage in
                        let state: StageState = {
                            if index < activeIndex { return .complete }
                            if index == activeIndex { return .active }
                            return .upcoming
                        }()

                        StageStep(
                            index: index + 1,
                            title: stage.rawValue,
                            state: state,
                            progress: stageProgress(for: stage, state: state, at: timeline.date)
                        )

                        if index < ProcessingStage.allCases.count - 1 {
                            Rectangle()
                                .fill(AppTheme.quietBorder)
                                .frame(width: 16, height: 1)
                                .padding(.horizontal, 2)
                        }
                    }
                }

                Text(stageDetail(for: progress.stage))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stageDetail(for stage: ProcessingStage) -> String {
        switch stage {
        case .preparing:
            return "Reading file."
        case .transcribing:
            return "Transcribing."
        case .findingSpeakers:
            return "Finding speakers."
        }
    }

    private func stageProgress(for stage: ProcessingStage, state: StageState, at date: Date) -> StageProgressValue {
        switch state {
        case .complete:
            return StageProgressValue(fraction: 1, label: "done")
        case .upcoming:
            return StageProgressValue(fraction: 0, label: estimateLabel(for: stage))
        case .active:
            if stage == progress.stage, let stageFraction = progress.stageFraction {
                let fraction = max(0.02, min(1, stageFraction))
                let elapsed = max(0, date.timeIntervalSince(progress.startedAt))

                guard fraction > 0.02, fraction < 1 else {
                    return StageProgressValue(fraction: fraction, label: fraction >= 1 ? "done" : "\(Self.timeLabel(elapsed))")
                }

                let projectedTotal = elapsed / fraction
                let remaining = max(0, projectedTotal - elapsed)
                return StageProgressValue(fraction: fraction, label: "≈\(Self.timeLabel(remaining))")
            }

            guard let estimate = estimatedDuration(for: stage) else {
                return StageProgressValue(
                    fraction: indeterminateFraction(at: date),
                    label: "\(Self.timeLabel(date.timeIntervalSince(progress.startedAt)))"
                )
            }

            let elapsed = max(0, date.timeIntervalSince(progress.startedAt))
            let fraction = min(0.94, max(0.08, elapsed / estimate))
            let remaining = max(0, estimate - elapsed)
            return StageProgressValue(fraction: fraction, label: "≈\(Self.timeLabel(remaining))")
        }
    }

    private func estimatedDuration(for stage: ProcessingStage) -> TimeInterval? {
        guard let mediaDuration = progress.mediaDuration else { return nil }

        switch stage {
        case .preparing:
            return min(18, max(3, mediaDuration * 0.02 + 2))
        case .transcribing:
            return max(8, mediaDuration * 0.20 + 4)
        case .findingSpeakers:
            return max(20, mediaDuration * 0.45 + 8)
        }
    }

    private func estimateLabel(for stage: ProcessingStage) -> String {
        guard let estimate = estimatedDuration(for: stage) else { return "wait" }
        return "≈\(Self.timeLabel(estimate))"
    }

    private func indeterminateFraction(at date: Date) -> Double {
        let step = Int(date.timeIntervalSinceReferenceDate) % 8
        return Double(step + 1) / 10
    }

    private static func timeLabel(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct RecordingTimerView: View {
    let state: LiveRecordingState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let label = elapsedLabel(at: timeline.date)
            Text(label)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
                .padding(.vertical, AppTheme.Space.sm)
                .padding(.horizontal, AppTheme.Space.md)
                .appGlassStatusSurface()
                .accessibilityLabel("Recording duration \(label)")
        }
    }

    private func elapsedLabel(at date: Date) -> String {
        guard case let .recording(startedAt, pausedAt, pausedDuration) = state else {
            return "0:00"
        }

        let activeEnd = pausedAt ?? date
        let elapsed = max(0, activeEnd.timeIntervalSince(startedAt) - pausedDuration)
        let totalSeconds = Int(elapsed.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct RecordingPulseView: View {
    let isPaused: Bool

    var body: some View {
        Group {
            if isPaused {
                pulseCircle(opacity: 0.45, fill: AppTheme.softInk)
            } else {
                TimelineView(.periodic(from: .now, by: 0.7)) { timeline in
                    let pulse = Int(timeline.date.timeIntervalSinceReferenceDate / 0.7) % 2 == 0 ? 1.0 : 0.55
                    pulseCircle(opacity: pulse, fill: AppTheme.Dictation.waveformColors[0])
                }
            }
        }
        .frame(width: 24, height: 24)
    }

    private func pulseCircle(opacity: Double, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 18, height: 18)
            .opacity(opacity)
            .overlay {
                Circle()
                    .stroke(AppTheme.ink, lineWidth: AppTheme.Stroke.hairline)
            }
            .accessibilityLabel(isPaused ? "Recording paused" : "Recording active")
    }
}

private struct RecordingTrackRow: View {
    let title: String
    let detail: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: AppTheme.Space.md) {
            Circle()
                .fill(isActive ? AppTheme.ink : AppTheme.quietBorder)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.bodyStrong)
                    .foregroundStyle(AppTheme.ink)

                Text(detail)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
            }

            Spacer(minLength: 12)
        }
        .padding(AppTheme.Space.md)
        .appGlassStatusSurface(cornerRadius: AppTheme.Radius.card)
    }
}

private struct StageStep: View {
    let index: Int
    let title: String
    let state: StageState
    let progress: StageProgressValue

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
            HStack(spacing: AppTheme.Space.sm) {
                Group {
                    if state == .active {
                        UnicodeSpinnerView(size: 12, foreground: state.foreground)
                    } else {
                        Text("\(index)")
                            .font(AppTheme.Typography.microBold)
                    }
                }
                .frame(width: 20, height: 20)
                .foregroundStyle(state.foreground)
                .appGlassCircleStatus(isProminent: state == .active)

                Text(title)
                    .font(AppTheme.Typography.captionStrong)
                    .foregroundStyle(state.foreground)
            }

            HStack(spacing: AppTheme.Space.xs) {
                Text(unicodeBar(fraction: progress.fraction, state: state))
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(state.foreground)
                    .lineLimit(1)

                Text(progress.label)
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(state.foreground.opacity(state == .upcoming ? 0.75 : 0.9))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, AppTheme.Space.sm)
        .padding(.horizontal, AppTheme.Space.md)
        .appGlassStatusSurface(isProminent: state == .active, cornerRadius: AppTheme.Radius.progressChip)
        .accessibilityLabel("\(title), \(progress.label)")
    }

    private func unicodeBar(fraction: Double, state: StageState) -> String {
        let width = 10
        let clamped = max(0, min(1, fraction))
        let filledCount = min(width, max(0, Int((clamped * Double(width)).rounded(.down))))
        let filled = String(repeating: "█", count: filledCount)
        let empty = String(repeating: state == .upcoming ? "·" : "░", count: width - filledCount)
        return filled + empty
    }
}

private struct StageProgressValue: Equatable {
    let fraction: Double
    let label: String
}

private enum StageState {
    case complete
    case active
    case upcoming

    var background: Color {
        switch self {
        case .complete, .active:
            return AppTheme.ink.opacity(0.16)
        case .upcoming:
            return AppTheme.panel
        }
    }

    var foreground: Color {
        switch self {
        case .complete, .active, .upcoming:
            return AppTheme.ink
        }
    }
}


private struct UnicodeSpinnerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let size: CGFloat
    let foreground: Color
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
            Text(frame(for: timeline.date))
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(foreground)
                .frame(width: size + 4, height: size + 4)
                .accessibilityLabel("Loading")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func frame(for date: Date) -> String {
        guard !reduceMotion else { return Self.frames[0] }
        let index = Int(date.timeIntervalSinceReferenceDate / 0.08) % Self.frames.count
        return Self.frames[index]
    }
}

private struct ProcessingSkeletonView: View {
    private let rowWidths: [CGFloat] = [520, 420, 320]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.md) {
            HStack(spacing: AppTheme.Space.sm) {
                UnicodeSpinnerView(size: 13, foreground: AppTheme.ink)

                Text("Building review")
                    .font(AppTheme.Typography.captionStrong)
                    .foregroundStyle(AppTheme.ink)
            }

            ForEach(Array(rowWidths.enumerated()), id: \.offset) { index, width in
                PixelLoadingRow(width: width, isStrong: index == 0)
            }
        }
        .padding(AppTheme.Space.lg)
        .appGlassStatusSurface(cornerRadius: AppTheme.Radius.card)
    }
}

private struct PixelLoadingRow: View {
    let width: CGFloat
    let isStrong: Bool

    var body: some View {
        Rectangle()
            .fill(isStrong ? AppTheme.border : AppTheme.quietBorder)
            .frame(width: width, height: 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct EmptyPanelState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            Text(title)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)

            Text(detail)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.softInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.xl)
        .appGlassStatusSurface(cornerRadius: AppTheme.Radius.card)
    }
}

private struct MetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.softInk)

            Text(value)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
        }
        .padding(.vertical, AppTheme.Space.sm)
        .padding(.horizontal, AppTheme.Space.md)
        .appGlassStatusSurface()
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xxs) {
            Text(title)
                .font(AppTheme.Typography.section)
                .foregroundStyle(AppTheme.ink)

            Text(subtitle)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.softInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TranscriptFilterBar: View {
    let options: [TranscriptFilterOption]
    let selectedSpeakerIDs: Set<String>
    let visibleCount: Int
    let totalCount: Int
    let onToggle: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.sm) {
                Text("Show")
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(AppTheme.softInk)

                Menu {
                    Button("All speakers") {
                        onClear()
                    }
                    .disabled(selectedSpeakerIDs.isEmpty)

                    Divider()

                    ForEach(options) { option in
                        Toggle(isOn: Binding(
                            get: { selectedSpeakerIDs.contains(option.id) },
                            set: { isOn in
                                if isOn != selectedSpeakerIDs.contains(option.id) {
                                    onToggle(option.id)
                                }
                            }
                        )) {
                            Text(option.label)
                        }
                    }
                } label: {
                    Label(filterMenuTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .font(AppTheme.Typography.microStrong)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel("Transcript speaker filter")

                Spacer(minLength: 8)

                Text("\(visibleCount)/\(totalCount) blocks")
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(AppTheme.softInk)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appGlassGroup(spacing: AppTheme.Space.xs)

            if !selectedSpeakerIDs.isEmpty {
                Text("Filtered preview only. Export keeps the full transcript.")
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk)
            }
        }
        .padding(AppTheme.Space.md)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.card)
    }

    private var filterMenuTitle: String {
        selectedSpeakerIDs.isEmpty ? "All speakers" : "\(selectedSpeakerIDs.count) selected"
    }
}

private struct TranscriptCalendarContextCard: View {
    let calendarContext: MeetingCalendarContext
    let hideFromMarkdown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.md) {
                Label("Meeting details", systemImage: "calendar")
                    .font(AppTheme.Typography.captionStrong)
                    .foregroundStyle(AppTheme.ink)

                Spacer(minLength: AppTheme.Space.md)

                Button("Hide from .MD") {
                    hideFromMarkdown()
                }
                .font(AppTheme.Typography.microStrong)
                .frame(minHeight: 30)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Remove meeting details from this Markdown.")
            }

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                calendarDetail("Event", calendarContext.title)
                calendarDetail("Scheduled", calendarContext.scheduledDisplay)
                calendarDetail("Calendar", calendarContext.calendarName)

                if let location = calendarContext.cleanLocation {
                    calendarDetail("Location", location)
                }
            }
        }
        .padding(AppTheme.Space.md)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meeting details included in Markdown")
    }

    private func calendarDetail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.sm) {
            Text(label)
                .font(AppTheme.Typography.label)
                .foregroundStyle(AppTheme.softInk)
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(AppTheme.Typography.captionStrong)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CalendarContextHelpPopover: View {
    var body: some View {
        Text(CalendarContextPolicy.matchingRule)
            .font(AppTheme.Typography.captionStrong)
            .foregroundStyle(AppTheme.ink)
            .lineSpacing(2)
            .shadow(color: AppTheme.nearBlack.opacity(0.7), radius: 1.5, x: 0, y: 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppTheme.Space.xxl)
            .padding(.vertical, AppTheme.Space.xl)
            .frame(width: 330, alignment: .leading)
            .modifier(CalendarContextHelpSurface())
            .padding(AppTheme.Space.xs)
            .accessibilityLabel(CalendarContextPolicy.matchingRule)
    }
}

private struct CalendarContextHelpSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.dropTarget, style: .continuous)

        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(.regular.tint(AppTheme.nearBlack.opacity(0.34)), in: .rect(cornerRadius: AppTheme.Radius.dropTarget))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(AppTheme.nearBlack.opacity(0.42)))
        }
    }
}

private struct PrimaryCreationSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isActive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.dropTarget, style: .continuous)

        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: AppTheme.Space.md) {
                content
                    .clipShape(shape)
                    .overlay(shape.stroke(isActive ? AppTheme.ink.opacity(0.32) : AppTheme.glassPanelStroke, lineWidth: AppTheme.Stroke.hairline))
                    .glassEffect(.regular.tint(AppTheme.glassInkQuiet).interactive(), in: .rect(cornerRadius: AppTheme.Radius.dropTarget))
            }
        } else {
            let fill = isActive ? AppTheme.glassPanelLeading.opacity(0.96) : AppTheme.glassPanelLeading

            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(fill))
                .clipShape(shape)
                .overlay(shape.stroke(isActive ? AppTheme.ink.opacity(0.34) : AppTheme.quietBorder, lineWidth: AppTheme.Stroke.hairline))
        }
    }
}

private struct SidebarStepItem: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: AppTheme.Space.xs) {
            Text("\(number)")
                .font(AppTheme.Typography.microStrong)
                .foregroundStyle(AppTheme.textSubtle)
                .monospacedDigit()
                .frame(width: 14, alignment: .trailing)

            Text(title)
                .font(AppTheme.Typography.microStrong)
                .foregroundStyle(AppTheme.softInk)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.78)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title)")
    }
}

private struct CustomSegmentedPicker: View {
    @Binding var selection: AppPresentationMode

    var body: some View {
        Picker("App Interface", selection: $selection) {
            ForEach(AppPresentationMode.allCases) { option in
                Text(option.shortDisplayName)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .frame(minWidth: 210)
        .help("Show Antrum in \(selection.displayName.lowercased()).")
    }
}

private struct CustomBackendSegmentedPicker: View {
    @Binding var selection: DiarizationBackend

    var body: some View {
        Picker("Speaker Engine", selection: $selection) {
            ForEach(DiarizationBackend.allCases) { option in
                Text(option.shortDisplayName)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .frame(minWidth: 230)
        .help("\(selection.shortDisplaySubtitle). \(selection.selectionGuidance)")
    }
}

private struct TechFootnote: View {
    @EnvironmentObject var viewModel: MeetingTranscriptionViewModel
    @ObservedObject var presentationManager: AppPresentationManager

    var body: some View {
        VStack(spacing: AppTheme.Space.sm) {
            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                HStack(spacing: AppTheme.Space.xs) {
                    Text("Speaker Engine:")
                        .font(AppTheme.Typography.micro)
                        .foregroundStyle(AppTheme.softInk)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Pick by meeting size.")

                    CustomBackendSegmentedPicker(selection: $viewModel.diarizationBackend)
                }

                HStack(spacing: AppTheme.Space.md) {
                    HStack(spacing: AppTheme.Space.xs) {
                        Text("App Interface:")
                            .font(AppTheme.Typography.micro)
                            .foregroundStyle(AppTheme.softInk)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        CustomSegmentedPicker(selection: $presentationManager.mode)
                    }

                    Toggle("Launch at startup", isOn: $presentationManager.launchAtStartup)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk)
                    .accessibilityLabel("Launch at startup")
                    .accessibilityValue(presentationManager.launchAtStartup ? "On" : "Off")
                    .help("Open Antrum automatically when you sign in.")
                }
            }
            .padding(.vertical, AppTheme.Space.xs)
            .padding(.horizontal, AppTheme.Space.sm)
            .appGlassControlSurface(cornerRadius: AppTheme.Radius.card)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local transcription settings")
    }
}

private struct ToastView: View {
    let message: UserMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Space.lg) {
            Text(marker)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 22, height: 22)
                .appGlassStatusSurface()

            VStack(alignment: .leading, spacing: AppTheme.Space.xxs) {
                Text(message.title)
                    .font(AppTheme.Typography.captionStrong)
                    .foregroundStyle(AppTheme.ink)

                Text(message.detail)
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("x") {
                onDismiss()
            }
            .font(AppTheme.Typography.captionStrong)
            .frame(width: AppTheme.Control.minimumTarget, height: AppTheme.Control.minimumTarget)
            .buttonStyle(.bordered)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.vertical, AppTheme.Space.lg)
        .padding(.horizontal, AppTheme.Space.xl)
        .frame(width: 300, alignment: .leading)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.card)
        .shadow(color: AppTheme.shadow, radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var marker: String {
        switch message.kind {
        case .success:
            return "OK"
        case .status:
            return ".."
        case .failure:
            return "!!"
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Space.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Space.xxs) {
                Text("Could not continue")
                    .font(AppTheme.Typography.captionStrong)
                    .foregroundStyle(AppTheme.ink)

                Text(message)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(AppTheme.Space.xxl)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.panel)
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        reportWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        reportWindow(for: nsView)
    }

    private func reportWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onWindowAvailable(window)
        }
    }
}
