import Foundation

protocol AppCodedError: LocalizedError {
    var code: AppErrorCode { get }
}

enum AppErrorCode: String, CaseIterable, Sendable {
    case recordingAlreadyActive = "recording.already_active"
    case recordingNotActive = "recording.not_active"
    case recordingMicrophonePermissionDenied = "recording.microphone_permission_denied"
    case recordingCoreAudioProcessTapUnavailable = "recording.core_audio_process_tap_unavailable"
    case recordingCoreAudioSystemAudioStartFailed = "recording.core_audio_system_audio_start_failed"
    case recordingFallbackAudioCreationFailed = "recording.fallback_audio_creation_failed"
    case recordingAudioWriteFailed = "recording.audio_write_failed"

    case coreAudioCurrentProcessUnavailable = "core_audio.current_process_unavailable"
    case coreAudioMissingIOProc = "core_audio.missing_io_proc"
    case coreAudioUnsupportedFormat = "core_audio.unsupported_format"
    case coreAudioOperationFailed = "core_audio.operation_failed"

    case modelMissing = "model.missing"
    case modelNoAudioCaptured = "model.no_audio_captured"
    case modelNoSpeechDetected = "model.no_speech_detected"
    case modelDownloadFailed = "model.download_failed"

    case dictationAccessibilityPermissionRequired = "dictation.accessibility_permission_required"
    case dictationEmptyTranscript = "dictation.empty_transcript"
    case dictationPasteFailed = "dictation.paste_failed"
    case dictationAlreadyRecording = "dictation.already_recording"
    case dictationNotRecording = "dictation.not_recording"
    case dictationMicrophonePermissionDenied = "dictation.microphone_permission_denied"
    case dictationUnsupportedAudioFormat = "dictation.unsupported_audio_format"
    case dictationWriteFailed = "dictation.write_failed"
    case dictationInvalidShortcut = "dictation.invalid_shortcut"
    case dictationShortcutRegistrationFailed = "dictation.shortcut_registration_failed"

    case pipelineSortformerUnavailable = "pipeline.sortformer_unavailable"
}
