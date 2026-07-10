import SwiftUI

struct PixelGlyphView: View {
    var size: CGFloat = 55

    private let rows: [[Bool]] = [
        [false, false, true,  true,  false, false, false],
        [false, true,  true,  true,  true,  false, false],
        [true,  true,  false, true,  true,  true,  false],
        [true,  false, true,  true,  false, true,  false],
        [true,  false, false, true,  false, true,  true ],
        [true,  true,  true,  true,  true,  false, true ],
        [false, true,  false, false, true,  true,  false],
        [false, false, true,  true,  false, false, false]
    ]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                pixelRow(row)
            }
        }
        .frame(width: size, height: size)
        .padding(size * (7.0 / 55.0))
        .squircleSurface(
            fill: AppTheme.panel,
            radius: max(3, size * (AppTheme.Radius.control / 55.0))
        )
        .accessibilityHidden(true)
    }

    private func pixelRow(_ row: [Bool]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, filled in
                pixelCell(isFilled: filled)
            }
        }
    }

    private func pixelCell(isFilled: Bool) -> some View {
        Rectangle()
            .fill(isFilled ? AppTheme.ink : Color.clear)
    }
}
