import CoreGraphics
import Foundation

/// A region remembered across launches (last shared region, presets).
struct StoredRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var displayID: UInt32

    init(rect: CGRect, displayID: UInt32) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
        self.displayID = displayID
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct RegionPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var region: StoredRegion
    /// Share mode captured when the preset was saved; restored on recall.
    var shareModeRaw: String
}

/// Whether (and where) a preset can re-point the RUNNING session instead of
/// restarting it: same display, same share mode, and in virtual-display
/// mode the same aspect ratio (that display's resolution is fixed).
enum PresetSwitch {
    static func liveTarget(presetRect: CGRect, presetDisplayID: UInt32,
                           presetMode: ShareMode?, activeMode: ShareMode,
                           currentRect: CGRect, currentScreenID: UInt32,
                           screens: [(id: UInt32, frame: CGRect)]) -> CGRect? {
        guard activeMode != .virtualMonitor, presetMode == activeMode,
              let resolved = RegionResolver.resolve(rect: presetRect,
                                                    displayID: presetDisplayID,
                                                    screens: screens),
              screens[resolved.screenIndex].id == currentScreenID else { return nil }
        if activeMode == .virtualDisplay {
            let aspect = resolved.rect.width / resolved.rect.height
            let current = currentRect.width / currentRect.height
            guard abs(aspect - current) < 0.01 else { return nil }
        }
        return resolved.rect
    }
}

/// Maps a stored region back onto today's screen layout.
enum RegionResolver {
    /// Chooses the target screen (exact display id → most overlap → first)
    /// and fits the rect into it, shrinking oversized regions.
    static func resolve(rect: CGRect, displayID: UInt32,
                        screens: [(id: UInt32, frame: CGRect)])
        -> (rect: CGRect, screenIndex: Int)? {
        guard !screens.isEmpty else { return nil }
        let index: Int
        if let exact = screens.firstIndex(where: { $0.id == displayID }) {
            index = exact
        } else {
            let overlaps = screens.map { $0.frame.intersection(rect) }
                .map { $0.isNull ? 0 : $0.width * $0.height }
            let best = overlaps.enumerated().max(by: { $0.element < $1.element })!
            index = best.element > 0 ? best.offset : 0
        }
        let frame = screens[index].frame
        let size = CGSize(width: min(rect.width, frame.width),
                          height: min(rect.height, frame.height))
        let origin = Geometry.clampedRegionOrigin(rect.origin, regionSize: size, screenFrame: frame)
        return (CGRect(origin: origin, size: size), index)
    }
}
