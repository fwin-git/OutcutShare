import CoreGraphics

/// Pure geometry helpers shared by selection, capture and virtual display sizing.
enum Geometry {
    static let minRegionSide: CGFloat = 64

    /// Rectangle spanned by two drag points, regardless of drag direction.
    static func selectionRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func meetsMinimumSize(_ r: CGRect) -> Bool {
        r.width >= minRegionSide && r.height >= minRegionSide
    }

    /// Converts an AppKit global rect (bottom-left origin) into the display-local,
    /// top-left-origin coordinates that SCStreamConfiguration.sourceRect expects.
    static func displayLocalTopLeftRect(appKitGlobal r: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: r.minX - screenFrame.minX,
               y: screenFrame.maxY - r.maxY,
               width: r.width, height: r.height)
    }

    /// Keeps a moved region fully inside its screen (AppKit coordinates).
    static func clampedRegionOrigin(_ proposed: CGPoint, regionSize: CGSize,
                                    screenFrame: CGRect) -> CGPoint {
        CGPoint(x: min(max(proposed.x, screenFrame.minX), screenFrame.maxX - regionSize.width),
                y: min(max(proposed.y, screenFrame.minY), screenFrame.maxY - regionSize.height))
    }

    /// Region resulting from a corner-resize drag. `anchor` is the fixed
    /// opposite corner, `dragged` the current mouse point. With an `aspect`
    /// (width/height) the dominant drag axis wins and the other follows.
    /// Enforces the minimum region size and stays inside the screen.
    static func resizedRegion(anchor: CGPoint, dragged: CGPoint, aspect: CGFloat?,
                              screenFrame: CGRect) -> CGRect {
        let signX: CGFloat = dragged.x >= anchor.x ? 1 : -1
        let signY: CGFloat = dragged.y >= anchor.y ? 1 : -1
        var w = abs(dragged.x - anchor.x)
        var h = abs(dragged.y - anchor.y)
        let availW = signX > 0 ? screenFrame.maxX - anchor.x : anchor.x - screenFrame.minX
        let availH = signY > 0 ? screenFrame.maxY - anchor.y : anchor.y - screenFrame.minY
        if let aspect {
            w = max(w, h * aspect, minRegionSide, minRegionSide * aspect)
            w = min(w, availW, availH * aspect)
            h = w / aspect
        } else {
            w = min(max(w, minRegionSide), availW)
            h = min(max(h, minRegionSide), availH)
        }
        return CGRect(x: signX > 0 ? anchor.x : anchor.x - w,
                      y: signY > 0 ? anchor.y : anchor.y - h,
                      width: w, height: h)
    }

    /// Placement for the hidden mirror window: pinned at the bottom-right
    /// corner of the screen so exactly 1×1 pt stays on screen. macOS keeps
    /// rendering (and sharing apps keep capturing) a window only while some
    /// part of it is on a display; a fully offscreen window turns black.
    static func hiddenWindowFrame(regionSize: CGSize, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.maxX - 1,
               y: screenFrame.minY - regionSize.height + 1,
               width: regionSize.width, height: regionSize.height)
    }

    /// Inverse of displayLocalTopLeftRect for global CG window frames:
    /// CG top-left origin → AppKit bottom-left origin.
    static func appKitRect(fromCGTopLeft r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Viewer-friendly preset rects anchored at the drag origin, extending in
    /// the drag direction. nil where the size doesn't fit inside bounds.
    static func presetCandidates(anchor: CGPoint, toward: CGPoint,
                                 sizes: [CGSize], bounds: CGRect) -> [CGRect?] {
        let signX: CGFloat = toward.x >= anchor.x ? 1 : -1
        let signY: CGFloat = toward.y >= anchor.y ? 1 : -1
        return sizes.map { size in
            let rect = CGRect(x: signX > 0 ? anchor.x : anchor.x - size.width,
                              y: signY > 0 ? anchor.y : anchor.y - size.height,
                              width: size.width, height: size.height)
            return bounds.contains(rect) ? rect : nil
        }
    }

    /// Candidate whose extent best matches the drag distance from the anchor.
    static func snappedPresetIndex(dragged: CGPoint, candidates: [CGRect],
                                   anchor: CGPoint) -> Int? {
        let dragDistance = hypot(dragged.x - anchor.x, dragged.y - anchor.y)
        return candidates.enumerated().min { a, b in
            let da = abs(hypot(a.element.width, a.element.height) - dragDistance)
            let db = abs(hypot(b.element.width, b.element.height) - dragDistance)
            return da < db
        }?.offset
    }

    /// Windows are listed front-to-back; first hit wins.
    static func frontmostWindowFrame(at point: CGPoint, windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }

    /// Capture size in pixels: region points × display scale, floored to even
    /// values so the video pipeline never sees odd dimensions.
    static func capturePixelSize(region: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (Int(region.width * scale) & ~1, Int(region.height * scale) & ~1)
    }
}
