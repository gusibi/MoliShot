import XCTest
import AppKit
@testable import MoliShot

/// Tests the pure resize/handle logic on annotation structs (the GUI drag
/// plumbing in EditorView is verified manually). Covers #10 acceptance.
final class ResizeTests: XCTestCase {

    // MARK: - resized(to:)

    func testRectResizedMapsCorners() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10))
        let out = r.resized(to: CGRect(x: 20, y: 20, width: 40, height: 40)) as? RectAnnotation
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.start, NSPoint(x: 20, y: 20))
        XCTAssertEqual(out?.end, NSPoint(x: 60, y: 60))
    }

    func testRectResizedPreservesIdAndStyle() {
        let style = AnnotationStyle(color: .blue, strokeWidth: 5, fontSize: 12)
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10), style: style)
        let out = r.resized(to: CGRect(x: 0, y: 0, width: 50, height: 50)) as? RectAnnotation
        XCTAssertEqual(out?.id, r.id)
        XCTAssertEqual(out?.style, style)
    }

    func testLineResizedScalesProportionally() {
        let line = LineAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        let out = line.resized(to: CGRect(x: 0, y: 0, width: 50, height: 50)) as? LineAnnotation
        XCTAssertEqual(out?.start, .zero)
        XCTAssertEqual(out?.end, NSPoint(x: 50, y: 50))
    }

    func testPenResizedMapsAllPoints() {
        let pen = PenAnnotation(points: [.zero, NSPoint(x: 50, y: 0), NSPoint(x: 50, y: 50)])
        let out = pen.resized(to: CGRect(x: 0, y: 0, width: 100, height: 100)) as? PenAnnotation
        XCTAssertEqual(out?.points, [.zero, NSPoint(x: 100, y: 0), NSPoint(x: 100, y: 100)])
    }

    func testNumberResizedRecentersAndScalesRadius() {
        let n = NumberAnnotation(center: .zero, number: 1)
        let out = n.resized(to: CGRect(x: 0, y: 0, width: 40, height: 40)) as? NumberAnnotation
        XCTAssertEqual(out?.center, CGPoint(x: 20, y: 20))
        XCTAssertEqual(out?.radius, 20)
    }

    func testNumberResizedClampsRadiusToMinimum() {
        let n = NumberAnnotation(center: .zero, number: 1)
        let out = n.resized(to: CGRect(x: 0, y: 0, width: 4, height: 4)) as? NumberAnnotation
        XCTAssertEqual(out?.radius, 6, "radius must not shrink below 6")
    }

    func testTextResizedScalesFontSizeByHeight() {
        let t = TextAnnotation(origin: .zero, text: "Hi",
                               style: AnnotationStyle(color: .black, strokeWidth: 3, fontSize: 20))
        let oldHeight = t.bounds.height
        XCTAssertGreaterThan(oldHeight, 0)

        // Shrink to 10% height → font ~2pt → clamped to 8.
        let small = t.resized(to: CGRect(x: 5, y: 5, width: 100, height: oldHeight * 0.1)) as? TextAnnotation
        XCTAssertEqual(small?.style.fontSize ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(small?.origin, NSPoint(x: 5, y: 5))

        // Grow to 20x height → font ~400pt → clamped to 200.
        let big = t.resized(to: CGRect(x: 0, y: 0, width: 100, height: oldHeight * 20)) as? TextAnnotation
        XCTAssertEqual(big?.style.fontSize ?? 0, 200, accuracy: 0.001)
    }

    // MARK: - handle(at:)

    func testRectHandleAtBottomLeftCorner() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertEqual(r.handle(at: CGPoint(x: 0, y: 0)), .bottomLeft)
    }

    func testRectHandleAtTopRightCorner() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertEqual(r.handle(at: CGPoint(x: 100, y: 100)), .topRight)
    }

    func testRectHandleNilFarFromBounds() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertNil(r.handle(at: CGPoint(x: 50, y: 50)), "centre of the rect is not a handle")
    }

    func testRectHandleWithinTolerance() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        // 5pt off the top-right corner — within the 8pt handle radius.
        XCTAssertEqual(r.handle(at: CGPoint(x: 105, y: 105)), .topRight)
    }

    func testLineExposesEndpointHandlesOnly() {
        let line = LineAnnotation(start: .zero, end: NSPoint(x: 100, y: 0))
        XCTAssertEqual(line.handle(at: CGPoint(x: 0, y: 0)), .startEndpoint)
        XCTAssertEqual(line.handle(at: CGPoint(x: 100, y: 0)), .endEndpoint)
        // A point on the stroke midpoint is NOT a handle for a line.
        XCTAssertNil(line.handle(at: CGPoint(x: 50, y: 0)))
    }

    func testLineHandlePointsAreStartAndEnd() {
        let line = LineAnnotation(start: NSPoint(x: 1, y: 2), end: NSPoint(x: 3, y: 4))
        let pts = line.handlePoints.map { $0.0 }
        XCTAssertEqual(pts, [.startEndpoint, .endEndpoint])
    }

    func testRectHasEightHandlePoints() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertEqual(r.handlePoints.count, 8)
    }
}
