import Foundation
import FluidAudio
import Testing
@testable import Antrum

@Suite("Sortformer policy")
struct SortformerPolicyTests {
    @Test
    func defaultSortformerPlanAvoidsBrokenHighContextVariant() {
        #expect(LocalMeetingPipeline.defaultSortformerVariantNames == [
            "Sortformer_v2.1",
            "SortformerNvidiaLow_v2.1",
            "Sortformer_v2"
        ])
        #expect(!LocalMeetingPipeline.defaultSortformerVariantNames.contains("SortformerNvidiaHigh_v2.1"))
    }

    @Test
    func cancellationDoesNotFallBackToPyannote() {
        #expect(!DiarizationFallbackPolicy.shouldFallbackToPyannote(after: CancellationError()))
    }

    @Test
    func sortformerRuntimeFailureCanFallBackToPyannote() {
        #expect(DiarizationFallbackPolicy.shouldFallbackToPyannote(after: PipelineTestError.sortformerRuntimeFailure))
    }

    @Test
    func customSortformerConfigKeysIncludeRuntimeShape() {
        let shortContext = SortformerConfig(modelVariant: nil, chunkLen: 6, chunkLeftContext: 1, chunkRightContext: 7)
        let longContext = SortformerConfig(modelVariant: nil, chunkLen: 340, chunkLeftContext: 1, chunkRightContext: 40)

        #expect(LocalMeetingPipeline.sortformerVariantKey(for: shortContext) != LocalMeetingPipeline.sortformerVariantKey(for: longContext))
    }

    @Test
    func speakerEngineGuidanceExplainsTheSpeakerCountThresholds() {
        #expect(DiarizationBackend.nvidiaSortformerV21.shortDisplayName == "< 5 People")
        #expect(DiarizationBackend.nvidiaSortformerV21.shortDisplaySubtitle == "Sortformer v2.1")
        #expect(DiarizationBackend.nvidiaSortformerV21.selectionGuidance.contains("fewer than 5 people"))
        #expect(DiarizationBackend.pyannoteCoreML.shortDisplayName == "5 + People")
        #expect(DiarizationBackend.pyannoteCoreML.shortDisplaySubtitle == "Pyannote")
        #expect(DiarizationBackend.pyannoteCoreML.selectionGuidance.contains("5 or more people"))
    }
}

private enum PipelineTestError: Error {
    case sortformerRuntimeFailure
}
