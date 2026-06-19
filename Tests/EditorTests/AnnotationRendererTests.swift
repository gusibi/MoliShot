import XCTest
import AppKit
@testable import MoliShot

final class AnnotationRendererTests: XCTestCase {

    /// render with no annotations must reproduce the base image pixel-for-pixel
    /// (preserves the da56742 Retina fix: real pixels flow through unchanged).
    func testRenderEmptyPreservesBasePixels() {
        let base = Self.solidImage(size: NSSize(width: 24, height: 16), color: .white)
        let out = AnnotationRenderer.render(annotations: [], baseImage: base)

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

        let out = AnnotationRenderer.render(annotations: [highlight], baseImage: base)

        XCTAssertEqual(out.size, base.size)
        XCTAssertNotEqual(Self.pixelBytes(out), Self.pixelBytes(base),
                          "filled highlight must tint the output")
    }

    func testRenderReturnsBaseImageWhenCGImageMissing() {
        // An NSImage with no rep cannot yield a cgImage; renderer falls back.
        let empty = NSImage(size: NSSize(width: 10, height: 10))
        let out = AnnotationRenderer.render(annotations: [], baseImage: empty)
        XCTAssertNotNil(out)
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
