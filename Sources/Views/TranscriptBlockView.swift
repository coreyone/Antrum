import SwiftUI

struct TranscriptBlockView: View {
    let block: RenderedTranscriptBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(block.label)
                    .font(AppTheme.Typography.microBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: 60, alignment: .center)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .foregroundStyle(AppTheme.ink)
                    .appGlassStatusSurface(isProminent: true)

                if !block.timeRange.isEmpty {
                    Text(block.timeRange)
                        .font(AppTheme.Typography.label)
                        .foregroundStyle(AppTheme.softInk)
                        .monospacedDigit()
                }
            }

            Text(block.text.isEmpty ? "No transcript text." : block.text)
                .font(AppTheme.Typography.body)
                .foregroundStyle(block.text.isEmpty ? AppTheme.softInk : AppTheme.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .squircleSurface(
            fill: AppTheme.blockBackground,
            stroke: AppTheme.quietBorder,
            lineWidth: AppTheme.Stroke.hairline,
            radius: AppTheme.Radius.card
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let text = block.text.isEmpty ? "No transcript text." : block.text
        guard !block.timeRange.isEmpty else { return "\(block.label). \(text)" }
        return "\(block.label), \(block.timeRange). \(text)"
    }
}
