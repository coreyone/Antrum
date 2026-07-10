import Foundation

enum AudioTrack: Sendable {
    case microphone
    case systemAudio
}

struct PreparedAudio: Sendable {
    let samples: [Float]
    let containsSpeech: Bool
}

enum AudioPreparation {
    static let sampleRate = 16_000

    /// Applies only timing-safe, per-sample processing. It intentionally keeps the
    /// original sample count so ASR and diarization retain the recording timebase.
    static func prepare(_ samples: [Float], track: AudioTrack) -> PreparedAudio {
        guard !samples.isEmpty else {
            return PreparedAudio(samples: [], containsSpeech: false)
        }

        var prepared = samples
        if track == .microphone {
            highPassMicrophone(&prepared)
        }
        lightlyNormalize(&prepared)

        return PreparedAudio(
            samples: prepared,
            containsSpeech: VoiceActivityDetector.containsSpeech(
                in: prepared,
                sampleRate: sampleRate
            )
        )
    }

    private static func highPassMicrophone(_ samples: inout [Float]) {
        // A gentle one-pole high-pass at 80 Hz removes handling and HVAC rumble.
        let cutoff: Float = 80
        let sampleRate = Float(Self.sampleRate)
        let coefficient = sampleRate / (sampleRate + 2 * .pi * cutoff)
        var previousInput: Float = 0
        var previousOutput: Float = 0

        for index in samples.indices {
            let input = samples[index]
            let output = coefficient * (previousOutput + input - previousInput)
            samples[index] = output
            previousInput = input
            previousOutput = output
        }
    }

    private static func lightlyNormalize(_ samples: inout [Float]) {
        var sumOfSquares: Float = 0
        var peak: Float = 0

        for sample in samples {
            sumOfSquares += sample * sample
            peak = max(peak, abs(sample))
        }

        let rms = sqrt(sumOfSquares / Float(samples.count))
        guard rms >= 0.002, peak > 0 else { return }

        let requestedGain = Float(0.08) / rms
        let lightGain = min(max(requestedGain, 0.67), 1.5)
        let clipSafeGain = Float(0.98) / peak
        let gain = min(lightGain, clipSafeGain)
        guard gain != 1 else { return }

        for index in samples.indices {
            samples[index] *= gain
        }
    }
}
