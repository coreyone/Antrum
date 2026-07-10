import Foundation
import Testing
@testable import Antrum

@Suite("Audio preparation")
struct AudioPreparationTests {
    @Test
    func preparationPreservesSampleCountAndLimitsGain() {
        let samples = Array(repeating: Float(0.01), count: 16_000)

        let prepared = AudioPreparation.prepare(samples, track: .systemAudio)

        #expect(prepared.samples.count == samples.count)
        #expect(prepared.samples.max() ?? 0 <= 0.015)
    }

    @Test
    func microphoneHighPassRemovesSteadyLowFrequencyOffset() {
        let samples = Array(repeating: Float(0.08), count: 16_000)

        let prepared = AudioPreparation.prepare(samples, track: .microphone)

        let trailingEnergy = prepared.samples.suffix(4_000).reduce(Float(0)) { $0 + abs($1) }
        #expect(trailingEnergy < 0.01)
    }

    @Test
    func preparationDoesNotCreateSpeechFromSilence() {
        let samples = Array(repeating: Float(0), count: 16_000)

        let prepared = AudioPreparation.prepare(samples, track: .microphone)

        #expect(prepared.samples == samples)
    }
}
