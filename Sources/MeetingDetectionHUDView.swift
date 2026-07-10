import SwiftUI

struct MeetingDetectionHUDView: View {
    @ObservedObject var controller: MeetingDetectionController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: AppTheme.Space.md) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.ink)
                .frame(width: AppTheme.Dictation.hudIconWidth, height: AppTheme.Dictation.hudIconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.promptTitle)
                    .font(AppTheme.Typography.microBold)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("Record locally?")
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                controller.recordFromPrompt()
            } label: {
                Text("Record")
                    .font(AppTheme.Typography.microBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(minWidth: AppTheme.MeetingDetection.recordButtonWidth)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Ask Antrum to start local meeting recording.")

            Button {
                controller.dismissPrompt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.ink.opacity(AppTheme.Dictation.hudDetailOpacity))
                    .frame(width: AppTheme.Dictation.hudDetailWidth, height: AppTheme.Dictation.hudDetailWidth)
            }
            .buttonStyle(.plain)
            .help("Dismiss until microphone use stops.")
            .accessibilityLabel("Dismiss meeting prompt")
        }
        .padding(.vertical, AppTheme.Dictation.hudVerticalPadding)
        .padding(.leading, AppTheme.Dictation.hudLeadingPadding)
        .padding(.trailing, AppTheme.Dictation.hudTrailingPadding)
        .frame(width: AppTheme.MeetingDetection.hudWidth, height: AppTheme.MeetingDetection.hudHeight)
        .meetingDetectionGlassSurface(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.promptTitle). Record locally?")
    }

    private var snapshot: MeetingDetectionSnapshot {
        controller.promptState.snapshot ?? MeetingDetectionSnapshot(appLabels: [])
    }
}

private struct MeetingDetectionGlassSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: AppTheme.Space.md) {
                content
                    .glassEffect(.regular.tint(AppTheme.Dictation.hudGlassTint), in: .capsule)
            }
        } else {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(AppTheme.Dictation.hudGlassLeading)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppTheme.Dictation.hudGlassStroke, lineWidth: AppTheme.Stroke.hairline)
                )
        }
    }
}

private extension View {
    func meetingDetectionGlassSurface(reduceTransparency: Bool) -> some View {
        modifier(MeetingDetectionGlassSurface(reduceTransparency: reduceTransparency))
    }
}
