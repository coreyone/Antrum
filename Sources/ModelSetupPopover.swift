import SwiftUI

struct ModelSetupPopover: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let request: ModelSetupRequest
    let states: [LocalModelPackageID: ModelDownloadState]
    let download: (LocalModelPackageID) -> Void
    let continueProcessing: () -> Void
    let cancel: () -> Void

    var body: some View {
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                GlassEffectContainer(spacing: AppTheme.Space.md) {
                    popoverContent
                }
                .frame(width: 560)
                .overlay(alignment: .top) {
                    AppSpectralRule(opacity: 0.58)
                        .padding(.horizontal, AppTheme.Radius.panel)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous))
                }
                .glassEffect(.regular.tint(AppTheme.glassInkQuiet), in: RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous))
            } else {
                popoverContent
                    .frame(width: 560)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous)
                            .fill(AppTheme.glassPanelLeading)
                    )
                    .overlay(alignment: .top) {
                        AppSpectralRule(opacity: 0.48)
                            .padding(.horizontal, AppTheme.Radius.panel)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.panel, style: .continuous)
                            .stroke(AppTheme.quietBorder, lineWidth: AppTheme.Stroke.hairline)
                    )
            }
        }
        .shadow(color: AppTheme.shadow, radius: 24, y: 12)
        .preferredColorScheme(.dark)
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xxl) {
            VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
                Text(LocalModelSetupPolicy.title)
                    .font(AppTheme.Typography.section)
                    .foregroundStyle(AppTheme.ink)
                Text(LocalModelSetupPolicy.summary)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppTheme.Space.sm) {
                ForEach(LocalModelCatalog.packages) { package in
                    modelRow(package)
                }
            }

            HStack {
                Button("Not Now") {
                    cancel()
                }
                .appGlassButton()
                .disabled(isDownloading)

                Spacer()

                Button("Continue") {
                    continueProcessing()
                }
                .appGlassButton(isPrimary: true)
                .disabled(!canContinue)
            }
            .appGlassGroup(spacing: AppTheme.Space.lg)
        }
        .padding(AppTheme.Space.xxl)
    }

    private func modelRow(_ package: LocalModelPackage) -> some View {
        let state = states[package.id] ?? .notDownloaded
        let isRequired = request.requiredPackageIDs.contains(package.id)

        return HStack(spacing: AppTheme.Space.md) {
            Image(systemName: package.symbolName)
                .frame(width: 20)
                .foregroundStyle(AppTheme.ink)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppTheme.Space.xs) {
                    Text(package.title)
                        .font(AppTheme.Typography.bodyStrong)
                        .foregroundStyle(AppTheme.ink)
                    if isRequired {
                        Text("Required")
                            .font(AppTheme.Typography.label)
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .appGlassStatusSurface(isProminent: true)
                    }
                }
                Text(package.detail)
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk)
                Text("\(package.estimatedSizeText) · \(package.sourceText)")
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.Space.sm)

            modelAction(for: package.id, state: state)
        }
        .padding(AppTheme.Space.md)
        .appGlassControlSurface(cornerRadius: AppTheme.Radius.control)
    }

    @ViewBuilder
    private func modelAction(for packageID: LocalModelPackageID, state: ModelDownloadState) -> some View {
        switch state {
        case .downloaded:
            Label("Ready", systemImage: "checkmark")
                .font(AppTheme.Typography.microBold)
                .foregroundStyle(AppTheme.softInk)
        case .downloading(let progress):
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: progress)
                    .frame(width: 86)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(AppTheme.Typography.micro)
                    .foregroundStyle(AppTheme.softInk)
            }
        case .failed:
            Button("Retry") {
                download(packageID)
            }
            .appGlassButton()
            .disabled(isDownloading)
        case .notDownloaded:
            Button("Download") {
                download(packageID)
            }
            .appGlassButton(isPrimary: request.requiredPackageIDs.contains(packageID))
            .disabled(isDownloading)
        }
    }

    private var canContinue: Bool {
        request.requiredPackageIDs.allSatisfy { states[$0] == .downloaded }
    }

    private var isDownloading: Bool {
        states.values.contains {
            if case .downloading = $0 {
                return true
            }
            return false
        }
    }
}
