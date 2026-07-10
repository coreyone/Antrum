import SwiftUI

enum AppTheme {
    // Calibrated graphite ladder. OKLCH is the luminance source; SwiftUI renders exact sRGB.
    static let paper = Color(red: 0.110, green: 0.125, blue: 0.137) // #1c2023 oklch(24.07% 0.0083 240.2)
    static let nearBlack = Color(red: 0.141, green: 0.161, blue: 0.176) // #24292d oklch(27.76% 0.0103 242.1)
    static let surfaceRaised = Color(red: 0.173, green: 0.192, blue: 0.208) // #2c3135 oklch(30.99% 0.0100 242.0)
    static let surfaceHover = Color(red: 0.208, green: 0.231, blue: 0.251) // #353b40 oklch(34.86% 0.0119 243.2)
    static let surfaceActive = Color(red: 0.255, green: 0.282, blue: 0.306) // #41484e oklch(39.75% 0.0137 243.9)
    static let graphiteBorder = Color(red: 0.302, green: 0.333, blue: 0.361) // #4d555c oklch(44.50% 0.0154 244.5)
    static let graphiteBorderSubtle = Color(red: 0.255, green: 0.282, blue: 0.306) // #41484e oklch(39.75% 0.0137 243.9)
    static let graphiteBorderStrong = Color(red: 0.349, green: 0.384, blue: 0.412) // #596269 oklch(49.08% 0.0158 241.2)

    static let nearWhite = Color(red: 0.894, green: 0.914, blue: 0.937) // #e4e9ef
    static let text = Color(red: 0.820, green: 0.835, blue: 0.851) // #d1d5d9
    static let textMuted = Color(red: 0.659, green: 0.671, blue: 0.686) // #a8abaf
    static let textSubtle = Color(red: 0.541, green: 0.549, blue: 0.565) // #8a8c90
    static let focus = Color(red: 0.000, green: 0.361, blue: 0.608) // #005c9b oklch(46% 0.130 245), AA with near-white text
    static let selection = Color(red: 0.000, green: 0.315, blue: 0.557) // #00508e oklch(42% 0.130 245), AA with normal text

    static let canvasBackground = paper
    static let settingsAreaBackground = surfaceRaised

    static let panel = settingsAreaBackground
    static let ink = nearWhite
    static let inverseInk = paper
    static let softInk = textMuted
    static let border = graphiteBorder
    static let quietBorder = graphiteBorderSubtle
    static let blockBackground = settingsAreaBackground
    static let disabledInk = textSubtle.opacity(0.62)
    static let disabledBorder = graphiteBorderSubtle.opacity(0.74)
    static let shadow = paper.opacity(0.42)
    static let glassInk = nearBlack.opacity(0.88)
    static let glassInkQuiet = nearBlack.opacity(0.46)
    static let glassPanelLeading = settingsAreaBackground.opacity(0.86)
    static let glassPanelTrailing = surfaceActive.opacity(0.34)
    static let glassPanelStroke = graphiteBorder.opacity(0.92)
    static let glassPanelShadow = paper.opacity(0.42)

    enum Radius {
        static let badge: CGFloat = 6
        static let control: CGFloat = 7
        static let progressChip: CGFloat = 7
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
        static let dropTarget: CGFloat = 14
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let control: CGFloat = 1.5
        static let heavy: CGFloat = 2
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let xl: CGFloat = 14
        static let xxl: CGFloat = 16
        static let xxxl: CGFloat = 18
        static let page: CGFloat = 24
    }

    enum Control {
        static let minimumTarget: CGFloat = 44
    }

    enum Motion {
        static let quickFeedback: Double = 0.08
    }

    enum Dictation {
        static let settingsWidth: CGFloat = 760
        static let settingsHeight: CGFloat = 500
        static let settingsHeaderTextWidth: CGFloat = 560
        static let settingsHeaderGlyphSize: CGFloat = 28
        static let settingsTightTextSpacing: CGFloat = 2
        static let settingsModelProgressWidth: CGFloat = 120

        static let hudWidth: CGFloat = 172
        static let hudHeight: CGFloat = 54
        static let hudIconWidth: CGFloat = 20
        static let hudDetailWidth: CGFloat = 24
        static let hudShortcutWidth: CGFloat = 58
        static let hudWaveformHeight: CGFloat = 20
        static let hudWaveformBaseHeight: CGFloat = 4
        static let hudWaveformPeakHeight: CGFloat = 16
        static let hudBarSpacing: CGFloat = 3
        static let hudBarCount = 14
        static let hudBarCornerRadius: CGFloat = 2
        static let hudVerticalPadding: CGFloat = Space.md
        static let hudLeadingPadding: CGFloat = Space.lg
        static let hudTrailingPadding: CGFloat = Space.lg
        static let hudTopInset: CGFloat = Space.xl
        static let hudCursorGap: CGFloat = Space.xxxl

        static let hudPrimaryOpacity = 0.95
        static let hudInactiveOpacity = 0.38
        static let hudDetailOpacity = 0.82
        static let hudMinimumWaveformLevel = 0.12
        static let hudWaveformResponseScale = 1.1
        static let hudWaveformEdgeFalloff = 0.55
        static let hudGlassLeadingOpacity = 0.78
        static let hudGlassTrailingOpacity = 0.34
        static let hudGlassTintOpacity = 0.28
        static let hudGlassStrokeOpacity = 0.18

        static let hudGlassLeading = AppTheme.nearBlack.opacity(hudGlassLeadingOpacity)
        static let hudGlassTrailing = AppTheme.nearBlack.opacity(hudGlassTrailingOpacity)
        static let hudGlassTint = AppTheme.nearBlack.opacity(hudGlassTintOpacity)
        static let hudGlassStroke = AppTheme.nearWhite.opacity(hudGlassStrokeOpacity)

        static let waveformColors: [Color] = [
            Color(red: 1.00, green: 0.24, blue: 0.34),
            Color(red: 1.00, green: 0.56, blue: 0.16),
            Color(red: 0.96, green: 0.82, blue: 0.18),
            Color(red: 0.24, green: 0.80, blue: 0.45),
            Color(red: 0.12, green: 0.72, blue: 0.90),
            Color(red: 0.36, green: 0.50, blue: 1.00),
            Color(red: 0.76, green: 0.36, blue: 1.00)
        ]

        static let warmGlassColors: [Color] = [
            AppTheme.nearWhite,
            Color(red: 1.00, green: 0.82, blue: 0.52),
            Color(red: 1.00, green: 0.45, blue: 0.22),
            Color(red: 0.82, green: 0.20, blue: 0.24)
        ]
    }

    enum MeetingDetection {
        static let hudWidth: CGFloat = 316
        static let hudHeight: CGFloat = Dictation.hudHeight
        static let recordButtonWidth: CGFloat = 54
    }

    enum Typography {
        static let display = Font.system(size: 31, weight: .bold, design: .monospaced)
        static let title = Font.system(size: 26, weight: .bold, design: .monospaced)
        static let appTitle = Font.system(size: 20, weight: .bold, design: .monospaced)
        static let section = Font.system(size: 18, weight: .bold, design: .monospaced)
        static let body = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let bodyStrong = Font.system(size: 13, weight: .semibold, design: .monospaced)
        static let caption = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let captionStrong = Font.system(size: 12, weight: .semibold, design: .monospaced)
        static let micro = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let microStrong = Font.system(size: 11, weight: .semibold, design: .monospaced)
        static let microBold = Font.system(size: 11, weight: .bold, design: .monospaced)
        static let label = Font.system(size: 10, weight: .semibold, design: .monospaced)
    }

    static let panelRadius: CGFloat = Radius.panel
    static let controlRadius: CGFloat = Radius.control
    static let panelBorderWidth: CGFloat = 1.5
    static let controlBorderWidth: CGFloat = 1.5
    static let panelPadding: CGFloat = 16
    static let controlHorizontalPadding: CGFloat = 13
    static let controlVerticalPadding: CGFloat = 9
}

struct ChunkyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var isPrimary: Bool = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
        let tint = isPrimary ? AppTheme.surfaceActive.opacity(0.72) : AppTheme.glassInkQuiet
        let fill = isPrimary ? AppTheme.nearWhite.opacity(0.18) : AppTheme.nearWhite.opacity(0.045)
        let stroke = isPrimary ? AppTheme.nearWhite.opacity(0.62) : AppTheme.quietBorder
        let strokeWidth = isPrimary ? AppTheme.Stroke.control : AppTheme.Stroke.hairline
        let verticalPadding = isPrimary ? AppTheme.controlVerticalPadding : AppTheme.Space.sm
        let horizontalPadding = isPrimary ? AppTheme.controlHorizontalPadding : AppTheme.Space.lg

        let label = configuration.label
            .font(AppTheme.Typography.captionStrong)
            .foregroundStyle(isEnabled ? AppTheme.ink : AppTheme.disabledInk)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: isPrimary ? 36 : 32)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.48)

        if #available(macOS 26.0, *), !reduceTransparency {
            label
                .background(shape.fill(fill))
                .overlay(shape.stroke(stroke, lineWidth: strokeWidth))
                .overlay(alignment: .top) {
                    if isPrimary {
                        AppSpectralRule(opacity: 0.72)
                            .padding(.horizontal, AppTheme.Space.sm)
                            .clipShape(shape)
                    }
                }
                .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: AppTheme.controlRadius))
        } else {
            label
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(fill))
                .overlay(shape.stroke(stroke, lineWidth: strokeWidth))
                .overlay(alignment: .top) {
                    if isPrimary {
                        AppSpectralRule(opacity: 0.62)
                            .padding(.horizontal, AppTheme.Space.sm)
                            .clipShape(shape)
                    }
                }
        }
    }
}

struct AppGlassButtonModifier: ViewModifier {
    var isPrimary: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        content.buttonStyle(ChunkyButtonStyle(isPrimary: isPrimary))
    }
}

struct AppGlassGroupModifier: ViewModifier {
    var spacing: CGFloat = AppTheme.Space.xxl

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct AppGlassControlSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = AppTheme.Radius.dropTarget

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .clipShape(shape)
                .glassEffect(.regular.tint(AppTheme.glassInkQuiet), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(AppTheme.settingsAreaBackground.opacity(0.92)))
                .clipShape(shape)
                .overlay(shape.stroke(AppTheme.quietBorder, lineWidth: AppTheme.Stroke.hairline))
        }
    }
}

struct PixelPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = AppTheme.panelRadius
    var padding: CGFloat = AppTheme.panelPadding

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .padding(padding)
                .clipShape(shape)
                .overlay(shape.stroke(AppTheme.glassPanelStroke, lineWidth: AppTheme.Stroke.hairline))
                .overlay(alignment: .top) {
                    AppSpectralRule(opacity: 0.38)
                        .padding(.horizontal, cornerRadius)
                        .clipShape(shape)
                }
                .glassEffect(.regular.tint(AppTheme.glassInkQuiet), in: .rect(cornerRadius: cornerRadius))
                .shadow(color: AppTheme.glassPanelShadow, radius: 18, y: 8)
                .contentShape(shape)
        } else {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(AppTheme.glassPanelLeading))
                .clipShape(shape)
                .overlay(shape.stroke(AppTheme.quietBorder, lineWidth: AppTheme.Stroke.hairline))
                .overlay(alignment: .top) {
                    AppSpectralRule(opacity: 0.32)
                        .padding(.horizontal, cornerRadius)
                        .clipShape(shape)
                }
                .shadow(color: AppTheme.glassPanelShadow, radius: 18, y: 8)
                .contentShape(shape)
        }
    }
}

struct ThinHeaderSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)

        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: AppTheme.Space.lg) {
                content
                    .clipShape(shape)
                    .overlay(alignment: .bottom) {
                        AppSpectralRule(opacity: 0.52)
                            .padding(.horizontal, AppTheme.Radius.card)
                    }
                    .glassEffect(.regular.tint(AppTheme.glassInkQuiet), in: .rect(cornerRadius: AppTheme.Radius.card))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(AppTheme.settingsAreaBackground.opacity(0.82), in: shape)
                .clipShape(shape)
                .overlay(alignment: .bottom) {
                    AppSpectralRule(opacity: 0.42)
                        .padding(.horizontal, AppTheme.Radius.card)
                }
                .overlay(shape.stroke(AppTheme.quietBorder, lineWidth: AppTheme.Stroke.hairline))
        }
    }
}

struct AppGlassStatusSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var isProminent: Bool = false
    var cornerRadius: CGFloat = AppTheme.Radius.badge

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = isProminent ? AppTheme.ink.opacity(0.18) : AppTheme.glassInkQuiet
        let fallbackFill = isProminent ? AppTheme.ink.opacity(0.16) : AppTheme.blockBackground
        let fallbackStroke = isProminent ? AppTheme.ink.opacity(0.30) : AppTheme.quietBorder

        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .clipShape(shape)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                .overlay(shape.stroke(fallbackStroke, lineWidth: AppTheme.Stroke.hairline))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(fallbackFill))
                .clipShape(shape)
                .overlay(shape.stroke(fallbackStroke, lineWidth: AppTheme.Stroke.hairline))
        }
    }
}

struct AppGlassCircleStatusModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var isProminent: Bool = false

    func body(content: Content) -> some View {
        let tint = isProminent ? AppTheme.ink.opacity(0.18) : AppTheme.glassInkQuiet
        let fallbackFill = isProminent ? AppTheme.ink.opacity(0.16) : AppTheme.blockBackground

        if #available(macOS 26.0, *), !reduceTransparency {
            content
                .clipShape(Circle())
                .glassEffect(.regular.tint(tint), in: Circle())
                .overlay(Circle().stroke(AppTheme.ink.opacity(isProminent ? 0.30 : 0.18), lineWidth: AppTheme.Stroke.hairline))
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .background(Circle().fill(fallbackFill))
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.quietBorder, lineWidth: AppTheme.Stroke.hairline))
        }
    }
}

struct AppSpectralRule: View {
    var opacity: Double = 0.5
    var colors: [Color] = AppTheme.Dictation.warmGlassColors

    var body: some View {
        LinearGradient(
            stops: spectralStops,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: AppTheme.Stroke.hairline)
        .accessibilityHidden(true)
    }

    private var spectralStops: [Gradient.Stop] {
        let visibleColors = colors.map { $0.opacity(opacity) }
        guard !visibleColors.isEmpty else {
            return [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 1)
            ]
        }

        let innerStart = 0.12
        let innerEnd = 0.88
        let step = visibleColors.count > 1 ? (innerEnd - innerStart) / Double(visibleColors.count - 1) : 0
        let middleStops = visibleColors.enumerated().map { index, color in
            Gradient.Stop(color: color, location: innerStart + (Double(index) * step))
        }

        return [
            .init(color: .clear, location: 0),
            .init(color: visibleColors[0].opacity(0.24), location: 0.06)
        ] + middleStops + [
            .init(color: visibleColors[visibleColors.count - 1].opacity(0.24), location: 0.94),
            .init(color: .clear, location: 1)
        ]
    }
}

struct AppBackdropView: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            AppTheme.canvasBackground
                .backgroundExtensionEffect()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            AppTheme.canvasBackground
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }
}

struct SquircleSurface: ViewModifier {
    let fill: Color
    let stroke: Color
    let lineWidth: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .background(shape.fill(fill))
            .clipShape(shape)
            .overlay(shape.stroke(stroke, lineWidth: lineWidth))
            .contentShape(shape)
    }
}

struct CircleSurface: ViewModifier {
    let fill: Color
    let stroke: Color
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Circle().fill(fill))
            .clipShape(Circle())
            .overlay(Circle().stroke(stroke, lineWidth: lineWidth))
            .contentShape(Circle())
    }
}

extension View {
    func chunkyPanel() -> some View {
        modifier(PixelPanel())
    }

    func appGlassButton(isPrimary: Bool = false) -> some View {
        modifier(AppGlassButtonModifier(isPrimary: isPrimary))
    }

    func appGlassGroup(spacing: CGFloat = AppTheme.Space.xxl) -> some View {
        modifier(AppGlassGroupModifier(spacing: spacing))
    }

    func appGlassControlSurface(cornerRadius: CGFloat = AppTheme.Radius.dropTarget) -> some View {
        modifier(AppGlassControlSurfaceModifier(cornerRadius: cornerRadius))
    }

    func appGlassStatusSurface(isProminent: Bool = false, cornerRadius: CGFloat = AppTheme.Radius.badge) -> some View {
        modifier(AppGlassStatusSurfaceModifier(isProminent: isProminent, cornerRadius: cornerRadius))
    }

    func appGlassCircleStatus(isProminent: Bool = false) -> some View {
        modifier(AppGlassCircleStatusModifier(isProminent: isProminent))
    }

    func thinHeaderSurface() -> some View {
        modifier(ThinHeaderSurface())
    }

    func squircleSurface(
        fill: Color,
        stroke: Color = AppTheme.border,
        lineWidth: CGFloat = AppTheme.Stroke.control,
        radius: CGFloat = AppTheme.Radius.control
    ) -> some View {
        modifier(SquircleSurface(fill: fill, stroke: stroke, lineWidth: lineWidth, radius: radius))
    }

    func circleSurface(
        fill: Color,
        stroke: Color = AppTheme.border,
        lineWidth: CGFloat = AppTheme.Stroke.control
    ) -> some View {
        modifier(CircleSurface(fill: fill, stroke: stroke, lineWidth: lineWidth))
    }
}
