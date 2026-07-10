import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: MeetingTranscriptionViewModel
    @State private var isShowingLocalDataDeletionConfirmation = false
    @State private var localDataDeletionStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xl) {
            HStack {
                Text("Privacy & Data Use")
                    .font(AppTheme.Typography.section)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(AppTheme.Typography.bodyStrong)
                }
                .appGlassButton(isPrimary: true)
                .help("Close Privacy & Data Use.")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
                    privacySection(
                        title: "On-device processing",
                        detail: "Antrum transcribes, diarizes, runs dictation, and generates Markdown on this Mac. Meeting audio, dictation audio, transcript text, and pasted dictation text are not uploaded by the app."
                    )
                    privacySection(
                        title: "Permissions",
                        detail: "Microphone records your voice for meetings and offline dictation. System audio records remote speakers through local Core Audio capture on macOS 14.2 or later. Accessibility is used only to paste dictation text into the front app. Calendar is optional and reads only the matching event. Get participant consent before recording."
                    )
                    privacySection(
                        title: "Meeting detection",
                        detail: "Antrum can notice local microphone use by Zoom, Teams, Arc, Chrome, or Safari and show a recording prompt. It does not join calls, inspect browser tabs, read window titles, or start recording automatically."
                    )
                    privacySection(
                        title: "Local storage",
                        detail: "During a meeting recording, separate microphone and meeting-audio files are stored in Antrum's Application Support folder for processing. Dictation uses temporary microphone audio and does not keep history. Markdown is saved only when you choose a destination. Use Delete Local Recordings and Models below to remove Antrum's local recordings, temporary artifacts, and offline models; Markdown saved elsewhere is not removed."
                    )
                    privacySection(
                        title: "Model downloads",
                        detail: "An internet connection may be used to download FluidAudio/Hugging Face AI model files when you choose Download. Those requests do not include meeting audio, dictation audio, transcript text, speaker labels, or calendar details."
                    )
                    privacySection(
                        title: "Tracking",
                        detail: "Antrum does not use advertising tracking, analytics SDKs, accounts, or in-app purchases. Revoke Microphone, Accessibility, or Calendar access in macOS Privacy & Security settings."
                    )

                    HStack(spacing: AppTheme.Space.lg) {
                        Link("Privacy Policy", destination: AppStoreExternalResources.privacyPolicyURL)
                        Link("Model Notices", destination: AppStoreExternalResources.modelNoticesURL)
                        Link("Support & Feedback", destination: AppStoreExternalResources.supportURL)
                    }
                    .font(AppTheme.Typography.caption)

                    VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                        Button("Delete Local Recordings and Models", role: .destructive) {
                            isShowingLocalDataDeletionConfirmation = true
                        }
                        .appGlassButton()
                        .disabled(!canDeleteLocalData)

                        if let localDataDeletionStatus {
                            Text(localDataDeletionStatus)
                                .font(AppTheme.Typography.micro)
                                .foregroundStyle(AppTheme.softInk)
                        } else if !canDeleteLocalData {
                            Text("Stop recording, processing, or model setup before deleting local data.")
                                .font(AppTheme.Typography.micro)
                                .foregroundStyle(AppTheme.softInk)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppTheme.Space.xxl)
        .frame(minWidth: 520, minHeight: 470)
        .background(AppBackdropView())
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.panel)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Delete Local Recordings and Models?",
            isPresented: $isShowingLocalDataDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Local Data", role: .destructive) {
                deleteLocalData()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Antrum's local recordings, temporary artifacts, and downloaded models. Markdown files saved outside Antrum are not removed.")
        }
    }

    private func privacySection(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
            Text(title)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)
            Text(detail)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.softInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppTheme.Space.sm)
    }

    private var canDeleteLocalData: Bool {
        !viewModel.liveRecordingState.isActive
            && viewModel.progressStage == nil
            && viewModel.modelSetupRequest == nil
    }

    private func deleteLocalData() {
        do {
            try LocalDataDeletionPolicy.deleteAll()
            localDataDeletionStatus = "Local recordings and models deleted."
        } catch {
            localDataDeletionStatus = "Could not delete local data: \(error.localizedDescription)"
        }
    }
}
