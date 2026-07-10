import Foundation
import FluidAudio

actor LocalMeetingPipeline {
    static let defaultSortformerConfigs: [SortformerConfig] = [
        .fastV2_1,
        .balancedV2_1,
        .fastV2
    ]

    private var asrManager: AsrManager?
    private var vadManager: VadManager?
    private var sortformerModelsByVariant: [String: SortformerModels] = [:]
    private let sortformerConfigs: [SortformerConfig]

    init(sortformerConfigs: [SortformerConfig] = LocalMeetingPipeline.defaultSortformerConfigs) {
        self.sortformerConfigs = sortformerConfigs
        // Explicit setup is the only path permitted to enable model downloads.
        DownloadUtils.enforceOffline = true
    }

    func process(
        fileURL: URL,
        diarizationBackend: DiarizationBackend = .defaultBackend,
        progress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> MeetingSession {
        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .preparing))

        let converter = AudioConverter()
        let normalizedSamples = try converter.resampleAudioFile(fileURL)
        let preparedAudio = await prepareForSpeechProcessing(normalizedSamples, track: .systemAudio)
        let samples = preparedAudio.samples
        let mediaDuration = TimeInterval(samples.count) / TimeInterval(Self.normalizedSampleRate)
        await progress(PipelineProgress(stage: .preparing, mediaDuration: mediaDuration))

        guard preparedAudio.containsSpeech else {
            return emptySession(
                sourceURL: fileURL,
                processedAt: Date(),
                diarizationBackend: diarizationBackend
            )
        }

        let asrManager = try await cachedASRManager()
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)

        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .transcribing, mediaDuration: mediaDuration))
        let asrResult = try await asrManager.transcribe(
            samples,
            decoderState: &decoderState,
            language: nil
        )

        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .findingSpeakers, mediaDuration: mediaDuration))
        let diarization = try await diarize(
            samples: samples,
            backend: diarizationBackend,
            mediaDuration: mediaDuration,
            progress: progress
        )

        let blocks = TranscriptAligner.align(transcript: asrResult.text, windows: diarization.windows)
        let speakerIDs = Self.orderedUniqueSpeakerIDs(from: diarization.windows)
        let speakers = speakerIDs.enumerated().map { index, speakerID in
            SpeakerDraft(id: speakerID, defaultLabel: "Speaker \(index + 1)")
        }

        return MeetingSession(
            sourceURL: fileURL,
            processedAt: Date(),
            diarizationBackend: diarization.backend,
            diarizationFallbackReason: diarization.fallbackReason,
            speakers: speakers,
            blocks: blocks
        )
    }

    func process(
        recording: MeetingRecordingArtifacts,
        diarizationBackend: DiarizationBackend = .defaultBackend,
        calendarContext: MeetingCalendarContext? = nil,
        progress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> MeetingSession {
        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .preparing))

        let converter = AudioConverter()
        let normalizedMicrophoneSamples = try converter.resampleAudioFile(recording.microphoneURL)
        let normalizedSystemSamples = try converter.resampleAudioFile(recording.systemAudioURL)
        let preparedMicrophone = await prepareForSpeechProcessing(normalizedMicrophoneSamples, track: .microphone)
        let preparedSystem = await prepareForSpeechProcessing(normalizedSystemSamples, track: .systemAudio)
        let microphoneSamples = preparedMicrophone.samples
        let systemSamples = preparedSystem.samples
        let microphoneDuration = TimeInterval(microphoneSamples.count) / TimeInterval(Self.normalizedSampleRate)
        let systemDuration = TimeInterval(systemSamples.count) / TimeInterval(Self.normalizedSampleRate)
        let mediaDuration = max(microphoneDuration, systemDuration)
        await progress(PipelineProgress(stage: .preparing, mediaDuration: mediaDuration))

        guard preparedMicrophone.containsSpeech || preparedSystem.containsSpeech else {
            return MeetingSession(
                sourceURL: recording.folderURL,
                processedAt: recording.stoppedAt,
                diarizationBackend: diarizationBackend,
                diarizationFallbackReason: nil,
                speakers: RecordingTranscriptMerger.speakers(remoteSpeakerIDs: []),
                blocks: [],
                calendarContext: calendarContext
            )
        }

        let asrManager = try await cachedASRManager()

        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .transcribing, mediaDuration: mediaDuration, stageFraction: 0.05))
        let userTranscript = preparedMicrophone.containsSpeech
            ? try await transcribe(samples: microphoneSamples, asrManager: asrManager)
            : ""

        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .transcribing, mediaDuration: mediaDuration, stageFraction: 0.55))
        let remoteTranscript = preparedSystem.containsSpeech
            ? try await transcribe(samples: systemSamples, asrManager: asrManager)
            : ""
        await progress(PipelineProgress(stage: .transcribing, mediaDuration: mediaDuration, stageFraction: 1))

        try Task.checkCancellation()
        await progress(PipelineProgress(stage: .findingSpeakers, mediaDuration: mediaDuration))
        let diarization = preparedSystem.containsSpeech
            ? try await diarize(
                samples: systemSamples,
                backend: diarizationBackend,
                mediaDuration: mediaDuration,
                progress: progress
            )
            : DiarizationRun(windows: [], backend: diarizationBackend, fallbackReason: nil)

        let userWindows = preparedMicrophone.containsSpeech
            ? VoiceActivityDetector.windows(
                from: microphoneSamples,
                sampleRate: Self.normalizedSampleRate,
                fallbackDuration: microphoneDuration
            )
            : []
        let userBlocks = TranscriptAligner.align(transcript: userTranscript, windows: userWindows)
        let remoteBlocks = TranscriptAligner.align(transcript: remoteTranscript, windows: diarization.windows)
        let remoteSpeakerIDs = Self.orderedUniqueSpeakerIDs(from: diarization.windows)

        return MeetingSession(
            sourceURL: recording.folderURL,
            processedAt: recording.stoppedAt,
            diarizationBackend: diarization.backend,
            diarizationFallbackReason: diarization.fallbackReason,
            speakers: RecordingTranscriptMerger.speakers(remoteSpeakerIDs: remoteSpeakerIDs),
            blocks: RecordingTranscriptMerger.mergedBlocks(userBlocks: userBlocks, remoteBlocks: remoteBlocks),
            calendarContext: calendarContext
        )
    }

    private func cachedASRManager() async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }

        let models = try await AsrModels.downloadAndLoad(
            to: LocalModelStoragePolicy.defaultModelDirectory(for: .parakeetV3),
            version: .v3
        )
        let manager = AsrManager()
        try await manager.loadModels(models)
        asrManager = manager
        return manager
    }

    private func prepareForSpeechProcessing(_ samples: [Float], track: AudioTrack) async -> PreparedAudio {
        var prepared = AudioPreparation.prepare(samples, track: track)
        guard !prepared.samples.isEmpty else { return prepared }

        do {
            if let manager = try await cachedVADManager() {
                let results = try await manager.process(prepared.samples)
                prepared = PreparedAudio(
                    samples: prepared.samples,
                    containsSpeech: prepared.containsSpeech || results.contains(where: \.isVoiceActive)
                )
            }
        } catch {
            // VAD is an accelerator. Keep fully local processing usable if its model
            // has not been cached yet or Core ML cannot load it on this Mac.
        }

        return prepared
    }

    private func cachedVADManager() async throws -> VadManager? {
        if let vadManager {
            return vadManager
        }

        guard LocalModelCatalog.isVADInstalled() else {
            return nil
        }

        let manager = try await VadManager(modelDirectory: RecordingStoragePolicy.defaultAppSupportDirectory())
        vadManager = manager
        return manager
    }

    private func emptySession(
        sourceURL: URL,
        processedAt: Date,
        diarizationBackend: DiarizationBackend
    ) -> MeetingSession {
        MeetingSession(
            sourceURL: sourceURL,
            processedAt: processedAt,
            diarizationBackend: diarizationBackend,
            diarizationFallbackReason: nil,
            speakers: [],
            blocks: []
        )
    }

    private func transcribe(samples: [Float], asrManager: AsrManager) async throws -> String {
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            samples,
            decoderState: &decoderState,
            language: nil
        )
        return result.text
    }

    private func diarize(
        samples: [Float],
        backend: DiarizationBackend,
        mediaDuration: TimeInterval,
        progress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> DiarizationRun {
        switch backend {
        case .nvidiaSortformerV21:
            do {
                return DiarizationRun(
                    windows: try await sortformerWindows(
                        from: samples,
                        mediaDuration: mediaDuration,
                        progress: progress
                    ),
                    backend: .nvidiaSortformerV21,
                    fallbackReason: nil
                )
            } catch {
                guard DiarizationFallbackPolicy.shouldFallbackToPyannote(after: error),
                      LocalModelCatalog.isInstalled(.pyannote) else {
                    throw error
                }
                try Task.checkCancellation()
                await progress(PipelineProgress(stage: .findingSpeakers, mediaDuration: mediaDuration))
                return DiarizationRun(
                    windows: try await pyannoteWindows(from: samples),
                    backend: .pyannoteCoreML,
                    fallbackReason: error.localizedDescription
                )
            }
        case .pyannoteCoreML:
            return DiarizationRun(
                windows: try await pyannoteWindows(from: samples),
                backend: .pyannoteCoreML,
                fallbackReason: nil
            )
        }
    }

    private func sortformerWindows(
        from samples: [Float],
        mediaDuration: TimeInterval,
        progress: @escaping @Sendable (PipelineProgress) async -> Void
    ) async throws -> [SpeakerWindow] {
        var lastError: Error?

        for config in sortformerConfigs {
            try Task.checkCancellation()

            do {
                let models = try await cachedSortformerModels(config: config)
                try Task.checkCancellation()

                let diarizer = SortformerDiarizer(config: config, timelineConfig: .sortformerDefault)
                diarizer.initialize(models: models)
                var lastReportedFraction = 0.0
                var lastReportTime = Date.distantPast
                let timeline = try diarizer.processComplete(samples, sourceSampleRate: nil) { processedSamples, totalSamples, _ in
                    guard totalSamples > 0 else { return }

                    let fraction = max(0, min(1, Double(processedSamples) / Double(totalSamples)))
                    let now = Date()
                    guard fraction >= 1
                        || fraction - lastReportedFraction >= 0.01
                        || now.timeIntervalSince(lastReportTime) >= 0.5 else {
                        return
                    }

                    lastReportedFraction = fraction
                    lastReportTime = now
                    Task {
                        await progress(
                            PipelineProgress(
                                stage: .findingSpeakers,
                                mediaDuration: mediaDuration,
                                stageFraction: fraction
                            )
                        )
                    }
                }
                try Task.checkCancellation()
                await progress(
                    PipelineProgress(
                        stage: .findingSpeakers,
                        mediaDuration: mediaDuration,
                        stageFraction: 1
                    )
                )

                return timeline.speakers.values
                    .flatMap(\.finalizedSegments)
                    .sorted { ($0.startTime, $0.endTime, $0.speakerIndex) < ($1.startTime, $1.endTime, $1.speakerIndex) }
                    .map { segment in
                        SpeakerWindow(
                            speakerID: "S\(segment.speakerIndex + 1)",
                            start: TimeInterval(segment.startTime),
                            end: TimeInterval(segment.endTime)
                        )
                    }
            } catch {
                guard DiarizationFallbackPolicy.shouldFallbackToPyannote(after: error) else {
                    throw error
                }
                lastError = error
                sortformerModelsByVariant[Self.sortformerVariantKey(for: config)] = nil
            }
        }

        throw lastError ?? PipelineError.sortformerUnavailable
    }

    private func cachedSortformerModels(config: SortformerConfig) async throws -> SortformerModels {
        let key = Self.sortformerVariantKey(for: config)
        if let sortformerModels = sortformerModelsByVariant[key] {
            return sortformerModels
        }

        let models = try await SortformerModels.loadFromHuggingFace(
            config: config,
            cacheDirectory: LocalModelStoragePolicy.defaultModelsDirectory()
        )
        sortformerModelsByVariant[key] = models
        return models
    }

    private func pyannoteWindows(from samples: [Float]) async throws -> [SpeakerWindow] {
        let diarizerManager = OfflineDiarizerManager()
        try await diarizerManager.prepareModels(directory: LocalModelStoragePolicy.defaultModelsDirectory())
        let diarizationResult = try await diarizerManager.process(audio: samples)

        return diarizationResult.segments.map { segment in
            SpeakerWindow(
                speakerID: segment.speakerId,
                start: TimeInterval(segment.startTimeSeconds),
                end: TimeInterval(segment.endTimeSeconds)
            )
        }
    }

    private static func orderedUniqueSpeakerIDs(from windows: [SpeakerWindow]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for window in windows {
            let speakerID = window.speakerID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !speakerID.isEmpty, seen.insert(speakerID).inserted else { continue }
            ordered.append(speakerID)
        }

        return ordered
    }

    static var defaultSortformerVariantNames: [String] {
        defaultSortformerConfigs.map(Self.sortformerVariantKey(for:))
    }

    static func sortformerVariantKey(for config: SortformerConfig) -> String {
        if let variantName = config.modelVariant?.name {
            return variantName
        }

        return [
            "custom",
            "chunkLen=\(config.chunkLen)",
            "left=\(config.chunkLeftContext)",
            "right=\(config.chunkRightContext)",
            "fifo=\(config.fifoLen)",
            "spkcache=\(config.spkcacheLen)",
            "update=\(config.spkcacheUpdatePeriod)"
        ].joined(separator: ":")
    }

    private static let normalizedSampleRate = 16_000
}

private struct DiarizationRun {
    let windows: [SpeakerWindow]
    let backend: DiarizationBackend
    let fallbackReason: String?
}

private enum PipelineError: AppCodedError {
    case sortformerUnavailable

    var code: AppErrorCode {
        .pipelineSortformerUnavailable
    }

    var errorDescription: String? {
        switch self {
        case .sortformerUnavailable:
            return "Sortformer unavailable."
        }
    }
}
