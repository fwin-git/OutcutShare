import AppKit

enum AppVersion {
    /// "1.1 (84.5b4d644)" for the stamped bundle, "dev build" otherwise.
    static var display: String {
        guard Bundle.main.bundlePath.hasSuffix(".app"),
              let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return L10n.string(.appVersionDevBuild)
        }
        return L10n.string(.appVersionBuild, arguments: [version, build])
    }
}

extension NSColor {
    /// "#RRGGBBAA" in sRGB; used to persist colors in UserDefaults.
    convenience init?(hexRGBA: String) {
        guard hexRGBA.hasPrefix("#"), hexRGBA.count == 9,
              let value = UInt32(hexRGBA.dropFirst(), radix: 16) else {
            return nil
        }
        self.init(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                  green: CGFloat((value >> 16) & 0xFF) / 255,
                  blue: CGFloat((value >> 8) & 0xFF) / 255,
                  alpha: CGFloat(value & 0xFF) / 255)
    }

    var hexRGBA: String {
        let c = usingColorSpace(.sRGB) ?? self
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        let value = byte(c.redComponent) << 24 | byte(c.greenComponent) << 16
                  | byte(c.blueComponent) << 8 | byte(c.alphaComponent)
        return String(format: "#%08X", value)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }
}
