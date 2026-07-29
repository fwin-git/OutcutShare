import XCTest
@testable import OutcutShare

final class ScreenshotComposerTests: XCTestCase {
    func testTargetSizeUnlimitedKeepsSource() {
        XCTAssertEqual(ScreenshotComposer.targetSize(source: CGSize(width: 900, height: 600),
                                                     maxEdge: 0),
                       CGSize(width: 900, height: 600))
    }

    func testTargetSizeNeverUpscales() {
        XCTAssertEqual(ScreenshotComposer.targetSize(source: CGSize(width: 900, height: 600),
                                                     maxEdge: 4096),
                       CGSize(width: 900, height: 600))
    }

    func testTargetSizeScalesLongestEdgeDown() {
        XCTAssertEqual(ScreenshotComposer.targetSize(source: CGSize(width: 4000, height: 1000),
                                                     maxEdge: 2000),
                       CGSize(width: 2000, height: 500))
        XCTAssertEqual(ScreenshotComposer.targetSize(source: CGSize(width: 1000, height: 4000),
                                                     maxEdge: 1000),
                       CGSize(width: 250, height: 1000))
    }

    func testTargetSizeRoundsAndStaysPositive() {
        XCTAssertEqual(ScreenshotComposer.targetSize(source: CGSize(width: 3001, height: 5),
                                                     maxEdge: 1000),
                       CGSize(width: 1000, height: 2))
        XCTAssertEqual(ScreenshotComposer.targetSize(source: CGSize(width: 3000, height: 1),
                                                     maxEdge: 1000),
                       CGSize(width: 1000, height: 1))
    }

    func testCanvasWithoutShadowEqualsImage() {
        let layout = ScreenshotComposer.canvasLayout(for: CGSize(width: 800, height: 500),
                                                     shadow: false)
        XCTAssertEqual(layout.canvas, CGSize(width: 800, height: 500))
        XCTAssertEqual(layout.imageOrigin, .zero)
    }

    func testCanvasWithShadowAddsUniformMargin() {
        let layout = ScreenshotComposer.canvasLayout(for: CGSize(width: 800, height: 500),
                                                     shadow: true)
        let margin = ScreenshotComposer.shadowMargin
        XCTAssertEqual(layout.canvas, CGSize(width: 800 + 2 * margin,
                                             height: 500 + 2 * margin))
        XCTAssertEqual(layout.imageOrigin, CGPoint(x: margin, y: margin))
    }

    func testRenderProducesDecodableImageAtRequestedSize() throws {
        let source = try XCTUnwrap(Self.solidImage(width: 400, height: 200))
        let data = try XCTUnwrap(ScreenshotComposer.render(
            image: source, maxEdge: 100, shadow: false, quality: 1.0))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(decoded.pixelsWide, 100)
        XCTAssertEqual(decoded.pixelsHigh, 50)
    }

    func testRenderJpegQualityShrinksData() throws {
        let source = try XCTUnwrap(Self.noiseImage(width: 300, height: 300))
        let higher = try XCTUnwrap(ScreenshotComposer.render(
            image: source, maxEdge: 0, shadow: false, quality: 0.95))
        let lower = try XCTUnwrap(ScreenshotComposer.render(
            image: source, maxEdge: 0, shadow: false, quality: 0.4))
        XCTAssertLessThan(lower.count, higher.count)
    }

    func testRenderWithShadowGrowsCanvas() throws {
        let source = try XCTUnwrap(Self.solidImage(width: 200, height: 100))
        let data = try XCTUnwrap(ScreenshotComposer.render(
            image: source, maxEdge: 0, shadow: true, quality: 1.0))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        let margin = Int(ScreenshotComposer.shadowMargin)
        XCTAssertEqual(decoded.pixelsWide, 200 + 2 * margin)
        XCTAssertEqual(decoded.pixelsHigh, 100 + 2 * margin)
    }

    func testRenderRoundsCornersWhenRadiusSet() throws {
        let source = try XCTUnwrap(Self.solidImage(width: 200, height: 100))
        let data = try XCTUnwrap(ScreenshotComposer.render(
            image: source, maxEdge: 0, shadow: false, quality: 1.0, cornerRadius: 30))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        let corner = try XCTUnwrap(decoded.colorAt(x: 1, y: 1))
        let center = try XCTUnwrap(decoded.colorAt(x: 100, y: 50))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.02)
        XCTAssertEqual(center.alphaComponent, 1, accuracy: 0.02)
    }

    func testRenderCornerRadiusSurvivesDownscale() throws {
        let source = try XCTUnwrap(Self.solidImage(width: 400, height: 200))
        let data = try XCTUnwrap(ScreenshotComposer.render(
            image: source, maxEdge: 200, shadow: false, quality: 1.0, cornerRadius: 60))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(decoded.pixelsWide, 200)
        let corner = try XCTUnwrap(decoded.colorAt(x: 1, y: 1))
        XCTAssertEqual(corner.alphaComponent, 0, accuracy: 0.02)
    }

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    private static func noiseImage(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        var generator = SystemRandomNumberGenerator()
        for x in stride(from: 0, to: width, by: 10) {
            for y in stride(from: 0, to: height, by: 10) {
                context?.setFillColor(CGColor(red: .random(in: 0...1, using: &generator),
                                              green: .random(in: 0...1, using: &generator),
                                              blue: .random(in: 0...1, using: &generator),
                                              alpha: 1))
                context?.fill(CGRect(x: x, y: y, width: 10, height: 10))
            }
        }
        return context?.makeImage()
    }
}
