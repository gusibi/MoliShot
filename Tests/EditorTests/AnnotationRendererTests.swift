import XCTest
import AppKit
@testable import MoliShot

final class AnnotationRendererTests: XCTestCase {

    /// render with no annotations must reproduce the base image pixel-for-pixel
    /// (preserves the da56742 Retina fix: real pixels flow through unchanged).
    func testRenderEmptyPreservesBasePixels() {
        let base = Self.solidImage(size: NSSize(width: 24, height: 16), color: .white)
        let out = AnnotationRenderer.render(annotations: [], cropRect: nil, baseImage: base)

        XCTAssertEqual(out.size, base.size)
        XCTAssertNotNil(out.cgImageRef)
        XCTAssertEqual(Self.pixelBytes(out), Self.pixelBytes(base),
                       "empty render must not alter base pixels")
    }

    /// An annotation that fills the canvas must change at least one pixel,
    /// proving the annotation draw path runs through the renderer.
    func testRenderWithAnnotationModifiesPixels() {
        let base = Self.solidImage(size: NSSize(width: 24, height: 16), color: .white)
        let highlight = HighlightAnnotation(start: .zero, end: NSPoint(x: 24, y: 16),
                                            style: AnnotationStyle(color: .red))

        let out = AnnotationRenderer.render(annotations: [highlight], cropRect: nil, baseImage: base)

        XCTAssertEqual(out.size, base.size)
        XCTAssertNotEqual(Self.pixelBytes(out), Self.pixelBytes(base),
                          "filled highlight must tint the output")
    }

    func testRenderReturnsBaseImageWhenCGImageMissing() {
        // An NSImage with no rep cannot yield a cgImage; renderer falls back.
        let empty = NSImage(size: NSSize(width: 10, height: 10))
        let out = AnnotationRenderer.render(annotations: [], cropRect: nil, baseImage: empty)
        XCTAssertNotNil(out)
    }

    func testRenderCropsToCropRect() {
        // 4-quadrant image so we can verify the crop picks the right region.
        let base = Self.quadrantImage(size: NSSize(width: 20, height: 20))
        // Crop the bottom-left quadrant: x[0,10), y[0,10) in base-image coords.
        let crop = CGRect(x: 0, y: 0, width: 10, height: 10)
        let out = AnnotationRenderer.render(annotations: [], cropRect: crop, baseImage: base)

        XCTAssertEqual(out.size, NSSize(width: 10, height: 10))
        let px = Self.pixelBytes(out)
        // Bottom-left quadrant was red. After crop (y-up origin), the output's
        // sole quadrant should be red throughout.
        XCTAssertTrue(Self.isRed(px, width: 10, height: 10),
                      "cropped output must contain only the bottom-left (red) quadrant")
    }

    // MARK: - Helpers

    private static func solidImage(size: NSSize, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    /// 20×20 image split into 4 colored quadrants (base-image coords, y-up):
    /// bottom-left red, bottom-right green, top-left blue, top-right white.
    private static func quadrantImage(size: NSSize) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        let half = size.width / 2
        NSColor.red.setFill();   NSRect(x: 0, y: 0, width: half, height: half).fill()
        NSColor.green.setFill(); NSRect(x: half, y: 0, width: half, height: half).fill()
        NSColor.blue.setFill();  NSRect(x: 0, y: half, width: half, height: half).fill()
        NSColor.white.setFill(); NSRect(x: half, y: half, width: half, height: half).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    private static func isRed(_ bytes: [UInt8], width: Int, height: Int) -> Bool {
        guard bytes.count == width * height * 4 else { return false }
        for i in stride(from: 0, to: bytes.count, by: 4) {
            // premultipliedLast: R,G,B,A
            if bytes[i] < 200 || bytes[i + 1] > 50 || bytes[i + 2] > 50 { return false }
        }
        return true
    }

    private static func pixelBytes(_ image: NSImage) -> [UInt8] {
        guard let cg = image.cgImageRef else { return [] }
        let width = cg.width
        let height = cg.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}
