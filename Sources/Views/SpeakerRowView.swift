import SwiftUI

struct SpeakerRowView: View {
    let speaker: SpeakerDraft
    let summary: SpeakerSummary
    let allSpeakers: [SpeakerDraft]
    let mergeOptions: [SpeakerDraft]
    let onNameChange: (String) -> Void
    let onMergeChange: (String?) -> Void

    @State private var isShowingInfoPopover = false

    var body: some View {
        let speakerName = speaker.customName
        let validationMessage = SpeakerNamePolicy.validationMessage(for: speakerName)

        HStack(alignment: .center, spacing: AppTheme.Space.sm) {
            // 1. Speaker badge
            Text(summary.defaultLabel)
                .font(AppTheme.Typography.microBold)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 70, height: 18, alignment: .center)
                .foregroundStyle(AppTheme.ink)
                .appGlassStatusSurface(isProminent: true)

            // 2. Name input TextField container
            HStack(spacing: AppTheme.Space.xxs) {
                TextField(
                    "",
                    text: Binding(
                        get: { speaker.customName },
                        set: { newName in
                            let truncated = String(newName.prefix(SpeakerNamePolicy.maxLength))
                            onNameChange(truncated)
                        }
                    ),
                    prompt: Text(summary.isMerged ? "Merged" : "Name...")
                        .foregroundStyle(AppTheme.softInk)
                )
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(summary.isMerged ? AppTheme.disabledInk : AppTheme.ink)
                .tint(AppTheme.ink)
                .disabled(summary.isMerged)
                .accessibilityLabel("Rename \(summary.defaultLabel)")
                .frame(maxWidth: .infinity)

                if let validationMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .help(validationMessage)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .appGlassStatusSurface(isProminent: !summary.isMerged)

            // 3. Merge picker dropdown (Menu)
            Menu {
                Button("No merge") {
                    onMergeChange(nil)
                }
                ForEach(mergeOptions, id: \.id) { target in
                    let targetName = target.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target.defaultLabel : target.customName
                    Button(targetName) {
                        onMergeChange(target.id)
                    }
                }
            } label: {
                let currentName = speaker.mergeTargetID.flatMap { targetID in
                    allSpeakers.first { $0.id == targetID }.map { target in
                        target.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target.defaultLabel : target.customName
                    }
                } ?? "No merge"
                Text(currentName)
                    .font(AppTheme.Typography.microStrong)
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .frame(width: 105)
            .accessibilityLabel("Merge \(summary.defaultLabel)")

            // 4. Info Popover for additional metadata
            Button {
                isShowingInfoPopover.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isShowingInfoPopover ? AppTheme.ink : AppTheme.softInk)
                    .frame(width: 18, height: 18)
            }
            .appGlassButton(isPrimary: isShowingInfoPopover)
            .onHover { hovering in
                isShowingInfoPopover = hovering
            }
            .popover(isPresented: $isShowingInfoPopover, arrowEdge: .trailing) {
                SpeakerInfoPopoverView(summary: summary, defaultLabel: summary.defaultLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.badge)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}

private struct SpeakerInfoPopoverView: View {
    let summary: SpeakerSummary
    let defaultLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.sm) {
            Text(defaultLabel)
                .font(AppTheme.Typography.bodyStrong)
                .foregroundStyle(AppTheme.ink)

            Divider()

            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                HStack(spacing: AppTheme.Space.xs) {
                    Text("Total Blocks:")
                        .font(AppTheme.Typography.microStrong)
                        .foregroundStyle(AppTheme.softInk)
                    Text("\(summary.blockCount)")
                        .font(AppTheme.Typography.micro)
                        .foregroundStyle(AppTheme.ink)
                }

                HStack(spacing: AppTheme.Space.xs) {
                    Text("Total Duration:")
                        .font(AppTheme.Typography.microStrong)
                        .foregroundStyle(AppTheme.softInk)
                    Text(formatDuration(summary.duration))
                        .font(AppTheme.Typography.micro)
                        .foregroundStyle(AppTheme.ink)
                }
            }

            if !summary.sampleText.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sample Snippet:")
                        .font(AppTheme.Typography.microStrong)
                        .foregroundStyle(AppTheme.softInk)
                    Text("\"\(summary.sampleText)\"")
                        .font(AppTheme.Typography.micro)
                        .italic()
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppTheme.Space.md)
        .frame(width: 240)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.panel)
        .preferredColorScheme(.dark)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
