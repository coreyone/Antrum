import Foundation
import Testing
@testable import Antrum

@Suite("Meeting detection")
struct MeetingDetectionTests {
    @Test
    func allowlistMatchesExactAndHelperBundleIDs() {
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("us.zoom.xos"))
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("us.zoom.xos.helper"))
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("com.microsoft.teams"))
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("com.microsoft.teams2.helper"))
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("com.google.Chrome.helper"))
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("com.apple.Safari.WebContent"))
        #expect(MeetingDetectionPolicy.isAllowedMicrophoneApp("company.thebrowser.Browser.helper"))
    }

    @Test
    func allowlistRejectsUnsupportedMicrophoneAppsAndPrefixCollisions() {
        #expect(!MeetingDetectionPolicy.isAllowedMicrophoneApp("com.apple.FaceTime"))
        #expect(!MeetingDetectionPolicy.isAllowedMicrophoneApp("com.google.ChromeRemoteDesktop"))
        #expect(!MeetingDetectionPolicy.isAllowedMicrophoneApp("com.apple.WebKit.WebContent"))
    }

    @Test
    func processFilteringIgnoresInvalidOwnedAndUnsupportedProcesses() throws {
        let ownedPID: pid_t = 10
        let processes = [
            MicrophoneInputProcess(pid: 0, bundleID: "com.google.Chrome"),
            MicrophoneInputProcess(pid: 10, bundleID: "com.google.Chrome"),
            MicrophoneInputProcess(pid: 20, bundleID: ""),
            MicrophoneInputProcess(pid: 30, bundleID: "com.apple.FaceTime"),
            MicrophoneInputProcess(pid: 40, bundleID: "us.zoom.xos"),
            MicrophoneInputProcess(pid: 50, bundleID: "company.thebrowser.Browser.helper")
        ].compactMap { $0 }

        let allowed = MeetingDetectionPolicy.activeAllowedExternalProcesses(
            from: processes,
            ownedPIDs: [ownedPID]
        )

        #expect(allowed.map(\.pid) == [40, 50])
        #expect(MeetingDetectionPolicy.dedupedAppLabels(from: allowed) == ["Zoom", "Arc"])
    }

    @Test
    func stateMachineDetectsHeartbeatsAndDelayedClear() {
        var state = MeetingDetectionStateMachine()
        let snapshot = MeetingDetectionSnapshot(appLabels: ["Zoom"])

        #expect(state.update(activeExternalInput: true, snapshot: snapshot) == .detected(snapshot))
        for _ in 0..<(MeetingDetectionPolicy.heartbeatEveryActivePolls - 1) {
            #expect(state.update(activeExternalInput: true, snapshot: snapshot) == nil)
        }
        #expect(state.update(activeExternalInput: true, snapshot: snapshot) == .heartbeat(snapshot))
        #expect(state.update(activeExternalInput: false, snapshot: snapshot) == nil)
        #expect(state.update(activeExternalInput: false, snapshot: snapshot) == .cleared)
        #expect(state.update(activeExternalInput: false, snapshot: snapshot) == nil)
    }

    @Test
    func promptCopyIsHonestForBrowsersAndCalls() {
        #expect(MeetingDetectionSnapshot(appLabels: ["Chrome"]).promptTitle == "Microphone active in Chrome")
        #expect(MeetingDetectionSnapshot(appLabels: ["Arc"]).promptTitle == "Microphone active in Arc")
        #expect(MeetingDetectionSnapshot(appLabels: ["Safari"]).promptTitle == "Microphone active in Safari")
        #expect(MeetingDetectionSnapshot(appLabels: ["Zoom"]).promptTitle == "Call active in Zoom")
        #expect(MeetingDetectionSnapshot(appLabels: ["Teams"]).promptTitle == "Call active in Teams")
        #expect(MeetingDetectionSnapshot(appLabels: ["Zoom", "Chrome"]).promptTitle == "Microphone active in Zoom, Chrome")
    }

    @Test
    func localPrivacySummaryDoesNotPromiseAutomaticMeetingKnowledge() {
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("microphone use"))
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("asks before local recording starts"))
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("never joins calls"))
        #expect(MeetingDetectionPolicy.localPrivacySummary.contains("records automatically") == false)
    }

    @Test
    func menuBarPriorityPrefersRecordingThenDictationThenMeetingDetection() {
        let recording = LiveRecordingState.recording(
            startedAt: Date(timeIntervalSince1970: 100),
            pausedAt: nil,
            accumulatedPausedDuration: 0
        )

        #expect(MenuBarActivityPriority.current(
            recordingState: recording,
            isDictationActive: true,
            isMeetingDetectionVisible: true
        ) == .recording)
        #expect(MenuBarActivityPriority.current(
            recordingState: .idle,
            isDictationActive: true,
            isMeetingDetectionVisible: true
        ) == .dictation)
        #expect(MenuBarActivityPriority.current(
            recordingState: .idle,
            isDictationActive: false,
            isMeetingDetectionVisible: true
        ) == .meetingDetection)
        #expect(MenuBarActivityPriority.current(
            recordingState: .idle,
            isDictationActive: false,
            isMeetingDetectionVisible: false
        ) == .idle)
    }
}
