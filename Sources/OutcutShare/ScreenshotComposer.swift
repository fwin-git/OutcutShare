import AppKit

/// Turns a captured frame into the file the screenshot settings describe:
/// scaled to a maximum edge, optionally on a soft drop-shadow canvas,
/// encoded as PNG (quality 1.0) or JPEG.
enum ScreenshotComposer {
    /// Canvas padding around the image when the shadow is on — generous
    /// enough that the blur fades out fully.
    static let shadowMargin: CGFloat = 48

    /// Downscales so the longest edge fits maxEdge (0 = unlimited).
    /// Never upscales; rounds to whole pixels, at least 1.
    static func targetSize(source: CGSize, maxEdge: Int) -> CGSize {
        let longest = max(source.width, source.height)
        guard maxEdge > 0, longest > CGFloat(maxEdge) else { return source }
        let scale = CGFloat(maxEdge) / longest
        return CGSize(width: max(1, (source.width * scale).rounded()),
                      height: max(1, (source.height * scale).rounded()))
    }

    static func canvasLayout(for image: CGSize,
                             shadow: Bool) -> (canvas: CGSize, imageOrigin: CGPoint) {
        guard shadow else { return (image, .zero) }
        return (CGSize(width: image.width + 2 * shadowMargin,
                       height: image.height + 2 * shadowMargin),
                CGPoint(x: shadowMargin, y: shadowMargin))
    }

    /// Renders and encodes; returns nil only if a bitmap context can't be
    /// created. JPEG has no alpha, so with the shadow on it composites onto
    /// white; PNG keeps the shadow's transparency.
    static func render(image: CGImage, maxEdge: Int, shadow: Bool,
                       quality: Double) -> Data? {
        let scaled = targetSize(source: CGSize(width: image.width, height: image.height),
                                maxEdge: maxEdge)
        let layout = canvasLayout(for: scaled, shadow: shadow)
        let losslessPNG = quality >= 0.999
        guard let context = CGContext(
            data: nil, width: Int(layout.canvas.width), height: Int(layout.canvas.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if !losslessPNG {
            context.setFillColor(CGColor.white)
            context.fill(CGRect(origin: .zero, size: layout.canvas))
        }
        if shadow {
            context.setShadow(offset: CGSize(width: 0, height: -shadowMargin / 4),
                              blur: shadowMargin / 2,
                              color: CGColor(gray: 0, alpha: 0.45))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: layout.imageOrigin, size: scaled))
        guard let composed = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: composed)
        return losslessPNG
            ? rep.representation(using: .png, properties: [:])
            : rep.representation(using: .jpeg,
                                 properties: [.compressionFactor: quality])
    }

    static func fileExtension(quality: Double) -> String {
        quality >= 0.999 ? "png" : "jpg"
    }
}
