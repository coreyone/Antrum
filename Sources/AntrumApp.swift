import SwiftUI
import FluidAudio

@main
struct AntrumApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = MeetingTranscriptionViewModel()
    @StateObject private var presentationManager = AppPresentationManager()
    @StateObject private var dictationController = DictationController()
    @StateObject private var meetingDetectionController = MeetingDetectionController()

    init() {
        _ = try? LocalModelStoragePolicy.migrateLegacyModelDirectories()
        // Model downloads are always initiated from the explicit setup surface.
        DownloadUtils.enforceOffline = true
    }

    var body: some Scene {
        WindowGroup("Antrum", id: Self.mainWindowID) {
            ContentView(
                presentationManager: presentationManager,
                dictationController: dictationController,
                meetingDetectionController: meetingDetectionController
            )
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: AppWindowSizePolicy.contentSize(for: .idle).width,
            height: AppWindowSizePolicy.contentSize(for: .idle).height
        )
        .commands {
            CommandMenu("Appearance") {
                Picker("App Interface Style", selection: $presentationManager.mode) {
                    ForEach(AppPresentationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
            CommandMenu("Meeting") {
                Button("Record Meeting") {
                    viewModel.requestLiveRecording()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.liveRecordingState.isActive)

                Button(viewModel.liveRecordingState.isPaused ? "Resume Recording" : "Pause Recording") {
                    if viewModel.liveRecordingState.isPaused {
                        viewModel.resumeLiveRecording()
                    } else {
                        viewModel.pauseLiveRecording()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!canToggleRecordingPause)

                Button("Stop Recording") {
                    viewModel.stopLiveRecording()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!canStopRecording)

                Divider()

                Button("New File") {
                    viewModel.requestNewFile()
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(!viewModel.canStartNewFile)
            }

            CommandMenu("Markdown") {
                Button("Copy Markdown") {
                    viewModel.copyMarkdownToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!viewModel.canExport)

                Button("Save .md File") {
                    viewModel.saveMarkdownToFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!viewModel.canExport)
            }

            CommandMenu("Speaker Engine") {
                ForEach(DiarizationBackend.allCases) { backend in
                    Button(menuTitle(for: backend)) {
                        viewModel.setDiarizationBackend(backend)
                    }
                }
            }
        }
    }

    private func menuTitle(for backend: DiarizationBackend) -> String {
        let marker = viewModel.diarizationBackend == backend ? "✓ " : ""
        return marker + "\(backend.shortDisplayName) — \(backend.shortDisplaySubtitle)"
    }

    private var canToggleRecordingPause: Bool {
        viewModel.liveRecordingState.canPauseOrResume
    }

    private var canStopRecording: Bool {
        viewModel.liveRecordingState.canStop
    }
}
