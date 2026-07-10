import AppKit

enum AppWindowSizePolicy {
    static let minimumContentSize = NSSize(width: 860, height: 500)

    static func contentSize(
        for mode: MeetingTranscriptionViewModel.ViewMode,
        hasModelSetup: Bool = false
    ) -> NSSize {
        if hasModelSetup {
            return NSSize(width: 900, height: 620)
        }

        switch mode {
        case .idle:
            return NSSize(width: 900, height: 520)
        case .failed:
            return NSSize(width: 900, height: 560)
        case .recording:
            return NSSize(width: 860, height: 560)
        case .processing:
            return NSSize(width: 860, height: 500)
        case .review:
            return NSSize(width: 1180, height: 760)
        }
    }
}
