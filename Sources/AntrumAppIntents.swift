import AppIntents
import Foundation
import FluidAudio

struct TranscribeAudioIntent: AppIntent {
    static let title: LocalizedStringResource = "Transcribe Audio File"

    static let description = IntentDescription("Transcribes a local audio or video file using local AI models and returns the speaker-labeled Markdown transcript.")

    @Parameter(title: "Audio/Video File")
    var file: IntentFile

    @Parameter(title: "Diarization Backend", default: .nvidiaSortformerV21)
    var diarizationBackend: DiarizationBackendAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe \(\.$file) using \(\.$diarizationBackend)")
    }
    func perform() async throws -> some ReturnsValue<String> {
        let tempDir = FileManager.default.temporaryDirectory
        let rawFilename = file.filename
        let cleanFilename = URL(fileURLWithPath: rawFilename).lastPathComponent
        let safeFilename = cleanFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "temp_audio_file" : cleanFilename
        let fileURL = tempDir.appendingPathComponent(safeFilename)

        // Write the data to a temporary file
        try file.data.write(to: fileURL)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let pipeline = LocalMeetingPipeline()
        let session = try await pipeline.process(
            fileURL: fileURL,
            diarizationBackend: diarizationBackend.toDomain()
        ) { _ in }

        let markdown = TranscriptMarkdownBuilder.markdown(
            title: session.sourceURL.deletingPathExtension().lastPathComponent,
            sourceFileName: session.sourceURL.lastPathComponent,
            processedAt: session.processedAt,
            speakers: session.speakers,
            blocks: session.blocks
        )

        return .result(value: markdown)
    }
}

enum DiarizationBackendAppEnum: String, AppEnum {
    case nvidiaSortformerV21 = "nvidiaSortformerV21"
    case pyannoteCoreML = "pyannoteCoreML"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Diarization Backend"

    static let caseDisplayRepresentations: [DiarizationBackendAppEnum: DisplayRepresentation] = [
        .nvidiaSortformerV21: "NVIDIA Sortformer v2.1",
        .pyannoteCoreML: "Pyannote CoreML"
    ]

    func toDomain() -> DiarizationBackend {
        switch self {
        case .nvidiaSortformerV21:
            return .nvidiaSortformerV21
        case .pyannoteCoreML:
            return .pyannoteCoreML
        }
    }
}

struct AntrumShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranscribeAudioIntent(),
            phrases: [
                "Transcribe audio with \(.applicationName)",
                "Transcribe audio file in \(.applicationName)",
                "Get transcript from \(.applicationName)"
            ],
            shortTitle: "Transcribe Audio File",
            systemImageName: "waveform.and.mic"
        )
    }
}