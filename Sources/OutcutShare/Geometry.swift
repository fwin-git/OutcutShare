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

    /// Rect covering `target`, honoring an optional aspect (width/height),
    /// centered on the target and kept inside the screen. Used by follow mode.
    static func aspectFittedRect(around target: CGRect, aspect: CGFloat?,
                                 screenFrame: CGRect) -> CGRect {
        var w = max(target.width, minRegionSide)
        var h = max(target.height, minRegionSide)
        if let aspect {
            w = max(w, h * aspect)
            h = w / aspect
            if w > screenFrame.width {
                w = screenFrame.width
                h = w / aspect
            }
            if h > screenFrame.height {
                h = screenFrame.height
                w = h * aspect
            }
        } else {
            w = min(w, screenFrame.width)
            h = min(h, screenFrame.height)
        }
        let proposed = CGPoint(x: target.midX - w / 2, y: target.midY - h / 2)
        let origin = clampedRegionOrigin(proposed, regionSize: CGSize(width: w, height: h),
                                         screenFrame: screenFrame)
        return CGRect(origin: origin, size: CGSize(width: w, height: h))
    }

    /// How far the region must move so `point` re-enters its inner margin
    /// (camera-follow dead zone). Zero while the point is comfortably inside.
    static func deadZoneShift(region: CGRect, point: CGPoint, margin: CGFloat) -> CGSize {
        let dx = min(margin, region.width / 3)
        let dy = min(margin, region.height / 3)
        let inner = region.insetBy(dx: dx, dy: dy)
        var shift = CGSize.zero
        if point.x < inner.minX { shift.width = point.x - inner.minX }
        if point.x > inner.maxX { shift.width = point.x - inner.maxX }
        if point.y < inner.minY { shift.height = point.y - inner.minY }
        if point.y > inner.maxY { shift.height = point.y - inner.maxY }
        return shift
    }

    enum RegionEdge {
        case left, right, top, bottom
    }

    /// Resize by dragging one edge: that side follows the mouse, the opposite
    /// side stays fixed. With a locked aspect the cross-axis grows/shrinks
    /// around its center. Enforces the minimum size and the screen bounds.
    static func edgeResizedRegion(_ region: CGRect, edge: RegionEdge, draggedTo point: CGPoint,
                                  lockedAspect: CGFloat?, screenFrame: CGRect) -> CGRect {
        var r = region
        switch edge {
        case .right:
            r.size.width = min(max(point.x - r.minX, minRegionSide), screenFrame.maxX - r.minX)
        case .left:
            let newMinX = min(max(point.x, screenFrame.minX), r.maxX - minRegionSide)
            r.size.width = r.maxX - newMinX
            r.origin.x = newMinX
        case .top:
            r.size.height = min(max(point.y - r.minY, minRegionSide), screenFrame.maxY - r.minY)
        case .bottom:
            let newMinY = min(max(point.y, screenFrame.minY), r.maxY - minRegionSide)
            r.size.height = r.maxY - newMinY
            r.origin.y = newMinY
        }
        if let aspect = lockedAspect {
            switch edge {
            case .left, .right:
                let newHeight = min(r.width / aspect, screenFrame.height)
                r.origin.y = region.midY - newHeight / 2
                r.size.height = newHeight
                r.size.width = newHeight * aspect
                if edge == .left { r.origin.x = region.maxX - r.width }
            case .top, .bottom:
                let newWidth = min(r.height * aspect, screenFrame.width)
                r.origin.x = region.midX - newWidth / 2
                r.size.width = newWidth
                r.size.height = newWidth / aspect
                if edge == .bottom { r.origin.y = region.maxY - r.height }
            }
            r.origin = clampedRegionOrigin(r.origin, regionSize: r.size, screenFrame: screenFrame)
        }
        return r
    }

    /// Auto-placement for the floating hotbar next to the region border.
    /// Preference: below → right → left → top → inside-bottom fallback.
    static func hotbarOrigin(barSize: CGSize, region: CGRect,
                             screenFrame: CGRect, gap: CGFloat) -> CGPoint {
        let clampedX = min(max(region.midX - barSize.width / 2, screenFrame.minX),
                           screenFrame.maxX - barSize.width)
        let clampedY = min(max(region.midY - barSize.height / 2, screenFrame.minY),
                           screenFrame.maxY - barSize.height)
        if region.minY - gap - barSize.height >= screenFrame.minY {
            return CGPoint(x: clampedX, y: region.minY - gap - barSize.height)
        }
        if region.maxX + gap + barSize.width <= screenFrame.maxX {
            return CGPoint(x: region.maxX + gap, y: clampedY)
        }
        if region.minX - gap - barSize.width >= screenFrame.minX {
            return CGPoint(x: region.minX - gap - barSize.width, y: clampedY)
        }
        if region.maxY + gap + barSize.height <= screenFrame.maxY {
            return CGPoint(x: clampedX, y: region.maxY + gap)
        }
        return CGPoint(x: clampedX, y: region.minY + gap)
    }

    /// Default placement for the shared-output preview panel: bottom-right
    /// corner of the screen, sized by `width` with the region's aspect
    /// (width/height); shrinks when the screen is too small.
    static func previewPanelFrame(aspect: CGFloat, screenFrame: CGRect,
                                  width: CGFloat = 320, margin: CGFloat = 16) -> CGRect {
        var w = min(width, screenFrame.width - 2 * margin)
        var h = w / aspect
        let maxH = screenFrame.height - 2 * margin
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        return CGRect(x: screenFrame.maxX - margin - w,
                      y: screenFrame.minY + margin, width: w, height: h)
    }

    /// Large, centered placement for the virtual-monitor preview — the
    /// primary way to see the otherwise invisible screen. 55% of the screen
    /// width, height-clamped to 75% with the aspect kept.
    static func prominentPreviewFrame(aspect: CGFloat, screenFrame: CGRect) -> CGRect {
        var w = screenFrame.width * 0.55
        var h = w / aspect
        let maxH = screenFrame.height * 0.75
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        return CGRect(x: screenFrame.midX - w / 2, y: screenFrame.midY - h / 2,
                      width: w, height: h)
    }

    /// Docking spot for the preview panel next to the shared region: the
    /// first fully-on-screen position outside the region, so the panel never
    /// covers what's being shared. Preference: right of the region (bottom-
    /// aligned) → left → below (right-aligned, clear of the centered hotbar)
    /// → above → bottom-right screen corner as the last resort.
    static func previewDockedFrame(size: CGSize, region: CGRect, screenFrame: CGRect,
                                   gap: CGFloat = 12, margin: CGFloat = 16) -> CGRect {
        let candidates = [
            CGRect(x: region.maxX + gap, y: region.minY,
                   width: size.width, height: size.height),
            CGRect(x: region.minX - gap - size.width, y: region.minY,
                   width: size.width, height: size.height),
            CGRect(x: region.maxX - size.width, y: region.minY - gap - size.height,
                   width: size.width, height: size.height),
            CGRect(x: region.maxX - size.width, y: region.maxY + gap,
                   width: size.width, height: size.height),
        ]
        if let fit = candidates.first(where: { screenFrame.contains($0) }) {
            return fit
        }
        return CGRect(x: screenFrame.maxX - margin - size.width,
                      y: screenFrame.minY + margin,
                      width: size.width, height: size.height)
    }

    /// Refits an existing preview panel frame to a new aspect (the shared
    /// region was resized): the width and the top-left corner stay, the
    /// height follows, and the result is clamped inside the screen.
    static func aspectRefittedPanelFrame(current: CGRect, aspect: CGFloat,
                                         screenFrame: CGRect,
                                         minWidth: CGFloat = 160) -> CGRect {
        var w = max(current.width, minWidth)
        var h = w / aspect
        if h > screenFrame.height {
            h = screenFrame.height
            w = h * aspect
        }
        if w > screenFrame.width {
            w = screenFrame.width
            h = w / aspect
        }
        let origin = clampedRegionOrigin(CGPoint(x: current.minX, y: current.maxY - h),
                                         regionSize: CGSize(width: w, height: h),
                                         screenFrame: screenFrame)
        return CGRect(origin: origin, size: CGSize(width: w, height: h))
    }

    /// Windows are listed front-to-back; first hit wins.
    static func frontmostWindowFrame(at point: CGPoint, windows: [CGRect]) -> CGRect? {
        windows.first { $0.contains(point) }
    }

    /// Linear map of a point inside the preview panel onto the virtual
    /// display it mirrors (both AppKit global coordinates).
    static func previewPointToDisplayPoint(_ p: CGPoint, panel: CGRect,
                                           display: CGRect) -> CGPoint {
        guard panel.width > 0, panel.height > 0 else { return display.origin }
        return CGPoint(x: display.minX + (p.x - panel.minX) / panel.width * display.width,
                       y: display.minY + (p.y - panel.minY) / panel.height * display.height)
    }

    /// Origin (AppKit) centering a window of `size` at `center`, clamped
    /// fully inside `bounds`.
    static func centeredClampedWindowOrigin(size: CGSize, center: CGPoint,
                                            bounds: CGRect) -> CGPoint {
        clampedRegionOrigin(CGPoint(x: center.x - size.width / 2,
                                    y: center.y - size.height / 2),
                            regionSize: size, screenFrame: bounds)
    }

    /// AX window position (CG global, top-left origin) for an AppKit rect.
    static func cgTopLeftPoint(forAppKit rect: CGRect, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryHeight - rect.maxY)
    }

    /// A completed global drag counts as "window dropped onto the preview"
    /// only when it ends inside the panel, travelled a real distance, and
    /// the candidate window actually moved along (filters plain clicks and
    /// in-window drags like text selection).
    static func isWindowDropOnPanel(start: CGPoint, end: CGPoint, panel: CGRect,
                                    windowFrameAtStart: CGRect,
                                    windowFrameAtEnd: CGRect) -> Bool {
        guard panel.contains(end) else { return false }
        guard hypot(end.x - start.x, end.y - start.y) > 30 else { return false }
        let moved = hypot(windowFrameAtEnd.minX - windowFrameAtStart.minX,
                          windowFrameAtEnd.minY - windowFrameAtStart.minY)
        return moved > 20
    }

    /// Capture size in pixels: region points × display scale, floored to even
    /// values so the video pipeline never sees odd dimensions.
    static func capturePixelSize(region: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (Int(region.width * scale) & ~1, Int(region.height * scale) & ~1)
    }
}
