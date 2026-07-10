import SwiftUI

struct DictationHUDView: View {
    @ObservedObject var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppTheme.Space.sm) {
            Image(systemName: controller.state.hudSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(controller.state.hudSymbolColor)
                .frame(width: AppTheme.Dictation.hudIconWidth, height: AppTheme.Dictation.hudIconWidth)
                .accessibilityHidden(true)

            AudioLevelBar(level: controller.audioLevel, isActive: isListening, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity)

            if isListening {
                if isHovering {
                    Text(controller.settings.shortcut.displayName)
                        .font(AppTheme.Typography.microStrong)
                        .foregroundStyle(AppTheme.ink.opacity(AppTheme.Dictation.hudDetailOpacity))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: AppTheme.Dictation.hudShortcutWidth, alignment: .trailing)
                } else {
                    Button {
                        controller.cancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.ink.opacity(AppTheme.Dictation.hudDetailOpacity))
                            .frame(width: AppTheme.Dictation.hudDetailWidth, height: AppTheme.Dictation.hudDetailWidth)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel dictation")
                }
            } else {
                Image(systemName: controller.state.hudDetailSymbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.ink.opacity(AppTheme.Dictation.hudDetailOpacity))
                    .frame(width: AppTheme.Dictation.hudDetailWidth, height: AppTheme.Dictation.hudDetailWidth)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, AppTheme.Dictation.hudVerticalPadding)
        .padding(.leading, AppTheme.Dictation.hudLeadingPadding)
        .padding(.trailing, AppTheme.Dictation.hudTrailingPadding)
        .frame(width: AppTheme.Dictation.hudWidth, height: AppTheme.Dictation.hudHeight)
        .dictationGlassSurface()
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Antrum dictation \(controller.state.statusTitle)")
    }

    private var isListening: Bool {
        if case .listening = controller.state { return true }
        return false
    }
}

private extension DictationState {
    var hudSymbolName: String {
        switch self {
        case .idle:
            return "mic"
        case .listening:
            return "mic.fill"
        case .processing:
            return "arrow.triangle.2.circlepath"
        case .inserted:
            return "checkmark"
        case .canceled:
            return "xmark"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var hudDetailSymbolName: String {
        switch self {
        case .idle:
            return "circle"
        case .listening:
            return "xmark"
        case .processing:
            return "waveform"
        case .inserted:
            return "checkmark.circle.fill"
        case .canceled:
            return "xmark.circle"
        case .failed:
            return "exclamationmark.circle"
        }
    }

    var hudSymbolColor: Color {
        switch self {
        case .failed:
            return AppTheme.Dictation.waveformColors[0].opacity(0.95)
        case .inserted:
            return AppTheme.Dictation.waveformColors[3].opacity(0.95)
        case .canceled:
            return AppTheme.textMuted
        case .idle:
            return AppTheme.textMuted
        case .listening, .processing:
            return AppTheme.ink
        }
    }
}

private struct AudioLevelBar: View {
    let level: Double
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let barCount = AppTheme.Dictation.hudBarCount
            let spacing = AppTheme.Dictation.hudBarSpacing
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let barWidth = max(2, (proxy.size.width - totalSpacing) / CGFloat(barCount))

            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: AppTheme.Dictation.hudBarCornerRadius, style: .continuous)
                        .fill(barGradient)
                        .frame(width: barWidth, height: height(for: index))
                        .opacity(isActive ? AppTheme.Dictation.hudPrimaryOpacity : AppTheme.Dictation.hudInactiveOpacity)
                        .animation(reduceMotion ? nil : .easeOut(duration: AppTheme.Motion.quickFeedback), value: level)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(height: AppTheme.Dictation.hudWaveformHeight)
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: AppTheme.Dictation.waveformColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func height(for index: Int) -> CGFloat {
        let midpoint = (Double(AppTheme.Dictation.hudBarCount) - 1) / 2
        let phase = abs(Double(index) - midpoint) / midpoint
        let shaped = max(
            AppTheme.Dictation.hudMinimumWaveformLevel,
            level * (AppTheme.Dictation.hudWaveformResponseScale - phase * AppTheme.Dictation.hudWaveformEdgeFalloff)
        )
        return AppTheme.Dictation.hudWaveformBaseHeight + CGFloat(shaped) * AppTheme.Dictation.hudWaveformPeakHeight
    }
}

private struct DictationGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
    func dictationGlassSurface() -> some View {
        modifier(DictationGlassSurface())
    }
}
