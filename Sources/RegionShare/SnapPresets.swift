import AppKit

/// Viewer-friendly snap sizes shared by the selection and adjust overlays,
/// with the faded preview rendering (colored outlines + resolution labels).
@MainActor
enum SnapPresets {
    static let sizes: [CGSize] = [
        CGSize(width: 1280, height: 720),
        CGSize(width: 1600, height: 900),
        CGSize(width: 1920, height: 1080),
    ]
    static let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange]

    static func draw(candidates: [CGRect?], snapped: CGRect?, anchor: CGPoint) {
        for (index, candidate) in candidates.enumerated() {
            guard let rect = candidate else { continue }
            let color = colors[index % colors.count]
            let isSnapped = rect == snapped
            color.withAlphaComponent(isSnapped ? 0.9 : 0.45).setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = isSnapped ? 3 : 1.5
            if !isSnapped {
                path.setLineDash([6, 4], count: 2, phase: 0)
            }
            path.stroke()

            let size = sizes[index]
            let label = "\(Int(size.width)) × \(Int(size.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let textSize = label.size(withAttributes: attributes)
            // Far corner (away from the anchor), kept inside the rect.
            let x = rect.minX == anchor.x ? rect.maxX - textSize.width - 8 : rect.minX + 8
            let y = rect.minY == anchor.y ? rect.maxY - textSize.height - 6 : rect.minY + 6
            let background = CGRect(x: x - 4, y: y - 2,
                                    width: textSize.width + 8, height: textSize.height + 4)
            color.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
            label.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
        }
    }
}
