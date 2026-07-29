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
    /// white; PNG keeps the shadow's transparency. cornerRadius is in
    /// source pixels (the region outline's radius at capture scale) and
    /// scales along with the image.
    static func render(image: CGImage, maxEdge: Int, shadow: Bool,
                       quality: Double, cornerRadius: CGFloat = 0) -> Data? {
        let source = CGSize(width: image.width, height: image.height)
        let scaled = targetSize(source: source, maxEdge: maxEdge)
        let layout = canvasLayout(for: scaled, shadow: shadow)
        let losslessPNG = quality >= 0.999
        // Pass 1: scale (and round) the image alone — the shadow in pass 2
        // follows this image's alpha, so rounded corners get a rounded
        // shadow for free.
        guard let styleContext = CGContext(
            data: nil, width: Int(scaled.width), height: Int(scaled.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let radius = min(cornerRadius * (scaled.width / source.width),
                         min(scaled.width, scaled.height) / 2)
        if radius > 0 {
            styleContext.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: scaled),
                                        cornerWidth: radius, cornerHeight: radius,
                                        transform: nil))
            styleContext.clip()
        }
        styleContext.interpolationQuality = .high
        styleContext.draw(image, in: CGRect(origin: .zero, size: scaled))
        guard let styled = styleContext.makeImage() else { return nil }
        // Pass 2: place onto the canvas with background and shadow.
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
        context.draw(styled, in: CGRect(origin: layout.imageOrigin, size: scaled))
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
