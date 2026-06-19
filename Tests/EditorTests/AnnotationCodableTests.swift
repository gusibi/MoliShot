import XCTest
import AppKit
@testable import MoliShot

/// Verifies each annotation type round-trips through Codable with id, style
/// and geometry preserved. This is the foundation for clipboard copy/paste
/// (#17) and any future editable-save format.
final class AnnotationCodableTests: XCTestCase {

    private let style = AnnotationStyle(
        color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8),
        strokeWidth: 5,
        fontSize: 24
    )

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testRectAnnotationRoundTrip() throws {
        let original = RectAnnotation(start: .zero, end: NSPoint(x: 30, y: 40), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testEllipseAnnotationRoundTrip() throws {
        let original = EllipseAnnotation(start: NSPoint(x: 1, y: 2), end: NSPoint(x: 3, y: 4), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testLineAnnotationRoundTrip() throws {
        let original = LineAnnotation(start: .zero, end: NSPoint(x: 50, y: 0), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testArrowAnnotationRoundTrip() throws {
        let original = ArrowAnnotation(start: .zero, end: NSPoint(x: 7, y: 8), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testHighlightAnnotationRoundTrip() throws {
        let original = HighlightAnnotation(start: .zero, end: NSPoint(x: 100, y: 100), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testBlurAnnotationRoundTrip() throws {
        let original = BlurAnnotation(start: .zero, end: NSPoint(x: 9, y: 10), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testPixelateAnnotationRoundTrip() throws {
        let original = PixelateAnnotation(start: .zero, end: NSPoint(x: 11, y: 12), style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
    }

    func testPenAnnotationRoundTrip() throws {
        let original = PenAnnotation(points: [.zero, NSPoint(x: 1, y: 1), NSPoint(x: 2, y: 2)], style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.points, original.points)
    }

    func testTextAnnotationRoundTrip() throws {
        let original = TextAnnotation(origin: NSPoint(x: 5, y: 6), text: "hello", style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.origin, original.origin)
        XCTAssertEqual(decoded.text, original.text)
    }

    func testNumberAnnotationRoundTrip() throws {
        let original = NumberAnnotation(center: NSPoint(x: 15, y: 15), number: 7, style: style)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.center, original.center)
        XCTAssertEqual(decoded.number, original.number)
        XCTAssertEqual(decoded.radius, original.radius)
    }

    func testStyleColorRoundTripsAcrossSRGB() throws {
        // Colours constructed in sRGB must survive encode/decode equal.
        let original = AnnotationStyle(color: NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.5),
                                       strokeWidth: 2, fontSize: 18)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }
}
