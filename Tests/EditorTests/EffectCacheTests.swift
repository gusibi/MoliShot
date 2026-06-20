import XCTest
import AppKit
@testable import MoliShot

/// Verifies the blur/pixelate render cache (#19): repeated draws of the same
/// annotation produce identical pixels (cache hit), and changing the effect
/// parameter changes the output (param is part of the cache key).
final class EffectCacheTests: XCTestCase {

    func testRepeatedBlurRenderIsPixelIdentical() {
        let base = Self.solidImage(size: 40, color: NSColor(white: 0.5, alpha: 1))
        let blur = BlurAnnotation(start: .zero, end: NSPoint(x: 40, y: 40),
                                  style: AnnotationStyle(color: .black), radius: 10)

        let first = render([blur], base: base)
        let second = render([blur], base: base)

        XCTAssertEqual(Self.pixelBytes(first), Self.pixelBytes(second),
                       "cached blur render must be deterministic across draws")
    }

    func testDifferentBlurRadiusProducesDifferentPixels() {
        let base = Self.solidImage(size: 40, color: NSColor(white: 0.5, alpha: 1))
        let weak = BlurAnnotation(start: .zero, end: NSPoint(x: 40, y: 40),
                                  style: AnnotationStyle(color: .black), radius: 4)
        let strong = BlurAnnotation(start: .zero, end: NSPoint(x: 40, y: 40),
                                    style: AnnotationStyle(color: .black), radius: 30)

        // Same id so only the param differs — proves param is in the key.
        var strongCopy = strong
        strongCopy.id = weak.id

        let weakOut = render([weak], base: base)
        let strongOut = render([strongCopy], base: base)

        XCTAssertNotEqual(Self.pixelBytes(weakOut), Self.pixelBytes(strongOut),
                          "different radius must produce different pixels (param in cache key)")
    }

    func testPixelateRepeatedRenderIsIdentical() {
        let base = Self.solidImage(size: 40, color: NSColor(white: 0.5, alpha: 1))
        let px = PixelateAnnotation(start: .zero, end: NSPoint(x: 40, y: 40),
                                    style: AnnotationStyle(color: .black), pixelSize: 10)
        let a = render([px], base: base)
        let b = render([px], base: base)
        XCTAssertEqual(Self.pixelBytes(a), Self.pixelBytes(b))
    }

    // MARK: - Helpers

    private func render(_ anns: [Annotation], base: NSImage) -> NSImage {
        AnnotationRenderer.render(annotations: anns, cropRect: nil, baseImage: base)
    }

    private static func solidImage(size: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        // Checkerboard so blur/pixelate have edges to act on.
        let cell = size / 4
        for y in 0..<4 {
            for x in 0..<4 {
                let c = ((x + y) % 2 == 0) ? NSColor.black : NSColor.white
                c.setFill()
                NSRect(x: x * cell, y: y * cell, width: cell, height: cell).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    private static func pixelBytes(_ image: NSImage) -> [UInt8] {
        guard let cg = image.cgImageRef else { return [] }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }
}
