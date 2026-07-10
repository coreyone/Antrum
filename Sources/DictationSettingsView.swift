import SwiftUI

struct DictationSettingsView: View {
    @ObservedObject var controller: DictationController
    @State private var isRecordingShortcut = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            settingsContent(columns: .double)
            ScrollView {
                settingsContent(columns: .single)
            }
        }
        .frame(minWidth: AppTheme.Dictation.settingsWidth, minHeight: AppTheme.Dictation.settingsHeight)
        .tint(AppTheme.focus)
        .background(AppBackdropView())
        .preferredColorScheme(.dark)
        .onChange(of: controller.settings.shortcut) { _, _ in
            isRecordingShortcut = false
        }
    }

    private func settingsContent(columns: SettingsColumns) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
            header

            switch columns {
            case .double:
                HStack(alignment: .top, spacing: AppTheme.Space.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
                        modelSection
                        permissionsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
                        shortcutSection
                        behaviorSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .appGlassGroup(spacing: AppTheme.Space.lg)
            case .single:
                VStack(alignment: .leading, spacing: AppTheme.Space.lg) {
                    modelSection
                    permissionsSection
                    shortcutSection
                    behaviorSection
                }
                .appGlassGroup(spacing: AppTheme.Space.lg)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, AppTheme.Space.xl)
        .padding(.horizontal, AppTheme.Space.xl)
        .padding(.bottom, AppTheme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: AppTheme.Space.sm) {
            PixelGlyphView(size: AppTheme.Dictation.settingsHeaderGlyphSize)
            VStack(alignment: .leading, spacing: AppTheme.Dictation.settingsTightTextSpacing) {
                Text("Dictation")
                    .font(AppTheme.Typography.section)
                    .foregroundStyle(AppTheme.ink)
                Text("Offline English. Local audio. Pastes to front app.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: AppTheme.Dictation.settingsHeaderTextWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelSection: some View {
        SettingsPanel(title: "Model", detail: "Parakeet 0.6B. English. int8. Offline.") {
            VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                HStack {
                    Text(controller.modelStatus.menuTitle)
                        .font(AppTheme.Typography.bodyStrong)
                        .foregroundStyle(AppTheme.ink)

                    Spacer()

                    modelAction
                }

                Text(controller.modelStatus.settingsDetail)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(DictationModelDisclosure.estimatedSizeText) · \(DictationModelDisclosure.sourceText)")
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var modelAction: some View {
        switch controller.modelStatus {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.ink)
                .frame(width: AppTheme.Control.minimumTarget, height: AppTheme.Control.minimumTarget)
                .appGlassCircleStatus(isProminent: true)
                .accessibilityLabel("Model ready")
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: AppTheme.Dictation.settingsModelProgressWidth)
                .accessibilityLabel(controller.modelStatus.menuTitle)
        case .missing:
            Button("Download") {
                controller.startModelDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: AppTheme.Control.minimumTarget)
        case .failed:
            Button("Retry") {
                controller.startModelDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: AppTheme.Control.minimumTarget)
        }
    }

    private var permissionsSection: some View {
        SettingsPanel(title: "Permissions", detail: "Mic records. Accessibility pastes.") {
            VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                PermissionRow(
                    title: "Microphone",
                    detail: controller.microphonePermissionStatusTitle,
                    isReady: DictationAudioRecorder.isMicrophonePermissionReady,
                    actionTitle: controller.microphonePermissionActionTitle
                ) {
                    controller.requestMicrophonePermission()
                }
                PermissionRow(
                    title: "Accessibility",
                    detail: controller.permissionStatusTitle,
                    isReady: DictationInsertionService.isAccessibilityTrusted,
                    actionTitle: "Open Settings"
                ) {
                    controller.requestAccessibilityPermission()
                }
            }
        }
    }

    private var shortcutSection: some View {
        SettingsPanel(title: "Shortcut", detail: "Default \(DictationShortcut.defaultShortcut.displayName)") {
            VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
                HStack {
                    Text(controller.settings.shortcut.displayName)
                        .font(AppTheme.Typography.bodyStrong)
                        .foregroundStyle(AppTheme.ink)
                        .padding(.vertical, AppTheme.Space.sm)
                        .padding(.horizontal, AppTheme.Space.md)
                        .appGlassStatusSurface()

                    Spacer()

                    Button(isRecordingShortcut ? "Listening" : "Record") {
                        isRecordingShortcut = true
                        controller.beginRecordingShortcut()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(minHeight: AppTheme.Control.minimumTarget)
                    .disabled(isRecordingShortcut)
                }

                if isRecordingShortcut {
                    HStack(spacing: AppTheme.Space.md) {
                        Text("Press modifier + key.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.softInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Button("Cancel") {
                            isRecordingShortcut = false
                            controller.endRecordingShortcut()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .frame(minHeight: AppTheme.Control.minimumTarget)
                    }
                }

                shortcutPresetButtons

                if let shortcutError = controller.shortcutError {
                    Text(shortcutError)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.ink)
                }
            }
        }
    }

    @ViewBuilder
    private var shortcutPresetButtons: some View {
        Menu("Presets") {
            Button(DictationShortcut.defaultShortcut.displayName) {
                isRecordingShortcut = false
                controller.endRecordingShortcut()
                controller.setShortcutPreset(.defaultShortcut)
            }

            Button(DictationShortcut.commandOptionD.displayName) {
                isRecordingShortcut = false
                controller.endRecordingShortcut()
                controller.setShortcutPreset(.commandOptionD)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .frame(minHeight: AppTheme.Control.minimumTarget)
    }

    private var behaviorSection: some View {
        SettingsPanel(title: "Behavior", detail: "Record. Transcribe. Paste.") {
            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                DictationSettingRow(title: "Activation") {
                    DictationSegmentedControl(
                        selection: $controller.settings.activationMode,
                        options: DictationActivationMode.allCases,
                        title: \.displayName
                    )
                }

                DictationSettingRow(title: "HUD") {
                    DictationSegmentedControl(
                        selection: $controller.settings.hudPosition,
                        options: DictationHUDPosition.allCases,
                        title: \.displayName
                    )
                }

                DictationSettingRow(title: "Streaming") {
                    Text("Later")
                        .font(AppTheme.Typography.microStrong)
                        .foregroundStyle(AppTheme.disabledInk)
                        .frame(minWidth: 92, minHeight: 30)
                        .appGlassStatusSurface(cornerRadius: AppTheme.Radius.control)
                        .help("Later. V1 records, transcribes, pastes.")
                        .accessibilityLabel("Streaming preview unavailable")
                }
            }
        }
    }
}

private enum SettingsColumns {
    case double
    case single
}

private struct DictationSettingRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Space.md) {
            Text(title)
                .font(AppTheme.Typography.captionStrong)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 82, alignment: .leading)

            content

            Spacer(minLength: 0)
        }
        .frame(minHeight: AppTheme.Control.minimumTarget)
    }
}

private struct DictationSegmentedControl<Option: Hashable & Identifiable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: KeyPath<Option, String>

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(option[keyPath: title])
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .frame(minWidth: 150, alignment: .leading)
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            VStack(alignment: .leading, spacing: AppTheme.Dictation.settingsTightTextSpacing) {
                Text(title)
                    .font(AppTheme.Typography.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
            }
            content
        }
        .padding(AppTheme.Space.lg)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.card)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isReady: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Dictation.settingsTightTextSpacing) {
                Text(title)
                    .font(AppTheme.Typography.bodyStrong)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
            }

            Spacer()

            if isReady {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: AppTheme.Control.minimumTarget, height: AppTheme.Control.minimumTarget)
                    .appGlassCircleStatus(isProminent: true)
                    .accessibilityLabel("\(title) ready")
            } else {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: AppTheme.Control.minimumTarget)
            }
        }
        .frame(minHeight: AppTheme.Control.minimumTarget)
    }
}
