import Testing
@testable import Antrum

@Suite("Operational maturity")
struct OperationalMaturityTests {
    @Test
    func stableErrorCodesAreUniqueAndNamespaced() {
        let rawValues = AppErrorCode.allCases.map(\.rawValue)

        #expect(Set(rawValues).count == rawValues.count)
        #expect(rawValues.allSatisfy { $0.contains(".") })
    }

    @Test
    func runbookErrorCodesExistInCode() {
        #expect(AppErrorCode.recordingMicrophonePermissionDenied.rawValue == "recording.microphone_permission_denied")
        #expect(AppErrorCode.recordingCoreAudioProcessTapUnavailable.rawValue == "recording.core_audio_process_tap_unavailable")
        #expect(AppErrorCode.dictationAccessibilityPermissionRequired.rawValue == "dictation.accessibility_permission_required")
        #expect(AppErrorCode.dictationMicrophonePermissionDenied.rawValue == "dictation.microphone_permission_denied")
    }

    @Test
    func representativeErrorsExposeStableCodes() {
        #expect(DictationInsertionError.accessibilityPermissionRequired.code == .dictationAccessibilityPermissionRequired)
        #expect(DictationRecordingError.microphonePermissionDenied.code == .dictationMicrophonePermissionDenied)
        #expect(DictationModelError.noSpeechDetected.code == .modelNoSpeechDetected)
        #expect(CoreAudioProcessTapError.unsupportedFormat.code == .coreAudioUnsupportedFormat)
    }
}
