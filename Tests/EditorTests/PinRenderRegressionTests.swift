import XCTest
import AppKit
@testable import MoliShot

/// Regression guard for #20: the pin / export / copy paths all flow through
/// EditorView.renderFinalImage → AnnotationRenderer, which must preserve real
/// pixels (the da56742 Retina fix). If a future change resamples the base
/// image at logical size, the pin window would show a blurry 1× image.
final class PinRenderRegressionTests: XCTestCase {

    /// Render a 2× Retina base (logical 50×50, pixel 100×100), render it, and
    /// confirm the output carries the real 100×100 pixels — exactly what the
    /// pin window needs to display sharply on a Retina screen.
    func testRenderFinalImagePreservesRealPixelsForPin() {
        let base = Self.retinaImage(logical: 50, pixelsPerSide: 100, color: .red)
        let renderer = TestableEditorView(baseImage: base)

        let out = renderer.renderFinalImage()

        XCTAssertEqual(out.size, NSSize(width: 50, height: 50), "logical size must match base")
        XCTAssertEqual(out.pixelSize, NSSize(width: 100, height: 100),
                       "pin/export path must receive real pixels, not 1× logical")
    }

    func testRenderWithAnnotationsKeepsRealPixels() {
        let base = Self.retinaImage(logical: 40, pixelsPerSide: 80, color: .white)
        let renderer = TestableEditorView(baseImage: base)
        let rect = RectAnnotation(start: .zero, end: NSPoint(x: 40, y: 40),
                                  style: AnnotationStyle(color: .blue, strokeWidth: 2))
        renderer.testAnnotations = [rect]

        let out = renderer.renderFinalImage()
        XCTAssertEqual(out.pixelSize, NSSize(width: 80, height: 80))
    }

    /// The pin flow copies the same image again (PinView.onCopy). Confirm that
    /// a second encode through pngData still reports real pixels.
    func testPngDataFromRenderedIsRealPixels() {
        let base = Self.retinaImage(logical: 30, pixelsPerSide: 60, color: .green)
        let renderer = TestableEditorView(baseImage: base)
        let out = renderer.renderFinalImage()
        guard let png = out.pngData() else { return XCTFail("png encode failed") }
        guard let rep = NSBitmapImageRep(data: png) else { return XCTFail("png decode failed") }
        XCTAssertEqual(rep.pixelsWide, 60)
        XCTAssertEqual(rep.pixelsHigh, 60)
    }

    // MARK: - Helpers

    private static func retinaImage(logical: Int, pixelsPerSide: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsPerSide, pixelsHigh: pixelsPerSide,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: logical, height: logical)
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        color.setFill()
        NSRect(x: 0, y: 0, width: pixelsPerSide, height: pixelsPerSide).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: logical, height: logical))
        img.addRepresentation(rep)
        return img
    }
}

/// Minimal EditorView harness exposing renderFinalImage with injectable
/// annotations, without instantiating the full NSView/scroll-view stack.
private final class TestableEditorView {
    private let baseImage: NSImage
    var testAnnotations: [Annotation] = []
    init(baseImage: NSImage) { self.baseImage = baseImage }
    func renderFinalImage() -> NSImage {
        AnnotationRenderer.render(annotations: testAnnotations, cropRect: nil, baseImage: baseImage)
    }
}
