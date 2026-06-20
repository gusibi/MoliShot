import XCTest
import AppKit
@testable import MoliShot

/// Verifies the clipboard encode/decode path: round-trip preserves geometry
/// and style, but always mints a fresh UUID (paste/duplicate must not collide).
final class AnnotationClipboardTests: XCTestCase {

    private let style = AnnotationStyle(
        color: NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.9),
        strokeWidth: 4, fontSize: 22, opacity: 0.7
    )

    private func roundTrip(_ ann: Annotation) -> [Annotation] {
        guard let blob = AnnotationClipboard.encode([ann]) else { return [] }
        return AnnotationClipboard.decode(blob)
    }

    func testRectRoundTripPreservesGeometryStyleNewId() {
        let original = RectAnnotation(start: .zero, end: NSPoint(x: 30, y: 40), style: style)
        let out = roundTrip(original)
        XCTAssertEqual(out.count, 1)
        guard let r = out.first as? RectAnnotation else { return XCTFail("wrong type") }
        XCTAssertNotEqual(r.id, original.id, "decode must mint a fresh UUID")
        XCTAssertEqual(r.start, original.start)
        XCTAssertEqual(r.end, original.end)
        XCTAssertEqual(r.style, original.style)
    }

    func testPenRoundTripPreservesPointsNewId() {
        let original = PenAnnotation(points: [.zero, NSPoint(x: 5, y: 5), NSPoint(x: 10, y: 0)], style: style)
        let out = roundTrip(original)
        guard let p = out.first as? PenAnnotation else { return XCTFail("wrong type") }
        XCTAssertNotEqual(p.id, original.id)
        XCTAssertEqual(p.points, original.points)
    }

    func testTextRoundTripPreservesTextNewId() {
        let original = TextAnnotation(origin: NSPoint(x: 7, y: 8), text: "hello", style: style)
        let out = roundTrip(original)
        guard let t = out.first as? TextAnnotation else { return XCTFail("wrong type") }
        XCTAssertNotEqual(t.id, original.id)
        XCTAssertEqual(t.text, original.text)
        XCTAssertEqual(t.origin, original.origin)
    }

    func testBlurRoundTripPreservesRadiusNewId() {
        let original = BlurAnnotation(start: .zero, end: NSPoint(x: 50, y: 50), style: style, radius: 25)
        let out = roundTrip(original)
        guard let b = out.first as? BlurAnnotation else { return XCTFail("wrong type") }
        XCTAssertNotEqual(b.id, original.id)
        XCTAssertEqual(b.radius, 25)
    }

    func testPixelateRoundTripPreservesPixelSizeNewId() {
        let original = PixelateAnnotation(start: .zero, end: NSPoint(x: 50, y: 50), style: style, pixelSize: 20)
        let out = roundTrip(original)
        guard let p = out.first as? PixelateAnnotation else { return XCTFail("wrong type") }
        XCTAssertNotEqual(p.id, original.id)
        XCTAssertEqual(p.pixelSize, 20)
    }

    func testEncodeMultipleRoundTrips() {
        let arr: [Annotation] = [
            RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10), style: style),
            LineAnnotation(start: .zero, end: NSPoint(x: 20, y: 0), style: style),
            NumberAnnotation(center: NSPoint(x: 5, y: 5), number: 3, style: style),
        ]
        guard let blob = AnnotationClipboard.encode(arr) else { return XCTFail("encode failed") }
        let out = AnnotationClipboard.decode(blob)
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out[0] is RectAnnotation)
        XCTAssertTrue(out[1] is LineAnnotation)
        XCTAssertTrue(out[2] is NumberAnnotation)
    }

    func testDecodeGarbageReturnsEmpty() {
        let out = AnnotationClipboard.decode(Data("[not json".utf8))
        XCTAssertTrue(out.isEmpty)
    }

    // MARK: - withNewId

    func testWithNewIdMintsFreshIdKeepsGeometry() {
        let original = ArrowAnnotation(start: .zero, end: NSPoint(x: 30, y: 30), style: style)
        let copy = original.withNewId()
        guard let a = copy as? ArrowAnnotation else { return XCTFail("wrong type") }
        XCTAssertNotEqual(a.id, original.id)
        XCTAssertEqual(a.start, original.start)
        XCTAssertEqual(a.end, original.end)
        XCTAssertEqual(a.style, original.style)
    }
}
