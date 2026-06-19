import XCTest
import AppKit
@testable import MoliShot

final class AnnotationHitTesterTests: XCTestCase {

    func testEmptyAnnotationsReturnsNil() {
        XCTAssertNil(AnnotationHitTester.hitTest(point: .zero, annotations: []))
    }

    func testHitInsideAnnotationReturnsItsId() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10))
        let id = AnnotationHitTester.hitTest(point: CGPoint(x: 5, y: 5), annotations: [r])
        XCTAssertEqual(id, r.id)
    }

    func testHitOutsideAnnotationReturnsNil() {
        // RectAnnotation hitTest uses bounds insetBy(-6,-6): spans (-6,-6) to (16,16).
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10))
        let id = AnnotationHitTester.hitTest(point: CGPoint(x: 20, y: 20), annotations: [r])
        XCTAssertNil(id)
    }

    func testTopmostAnnotationWinsWhenOverlapping() {
        let bottom = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10))
        let top = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10))
        let id = AnnotationHitTester.hitTest(point: CGPoint(x: 5, y: 5),
                                             annotations: [bottom, top])
        XCTAssertEqual(id, top.id, "later annotation (drawn on top) should win")
    }

    func testReturnsIdOfOnlyMatchingAnnotation() {
        let a = RectAnnotation(start: .zero, end: NSPoint(x: 10, y: 10))
        let b = RectAnnotation(start: NSPoint(x: 100, y: 100), end: NSPoint(x: 110, y: 110))
        let id = AnnotationHitTester.hitTest(point: CGPoint(x: 5, y: 5),
                                             annotations: [a, b])
        XCTAssertEqual(id, a.id)
    }

    // MARK: - Nearest-matching for line / arrow / pen (#9)

    func testDiagonalLineHitOnStroke() {
        let line = LineAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertEqual(AnnotationHitTester.hitTest(point: CGPoint(x: 50, y: 50), annotations: [line]), line.id)
    }

    func testDiagonalLineMissInEmptyBboxCorner() {
        // Diagonal line's bbox is (0,0,100,100); the old bounds hit-test would
        // select when clicking the empty corner. Nearest-matching must reject it.
        let line = LineAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertNil(AnnotationHitTester.hitTest(point: CGPoint(x: 10, y: 90), annotations: [line]),
                     "clicking empty bbox corner of a diagonal line must not select it")
    }

    func testDiagonalLineHitWithinTolerance() {
        let line = LineAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        // Perpendicular distance ~3.5pt — within 6pt tolerance.
        XCTAssertEqual(AnnotationHitTester.hitTest(point: CGPoint(x: 55, y: 50), annotations: [line]), line.id)
    }

    func testDiagonalLineMissBeyondTolerance() {
        let line = LineAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        // Perpendicular distance ~7pt — beyond 6pt tolerance.
        XCTAssertNil(AnnotationHitTester.hitTest(point: CGPoint(x: 60, y: 50), annotations: [line]))
    }

    func testDiagonalArrowMissInEmptyBboxCorner() {
        let arrow = ArrowAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertNil(AnnotationHitTester.hitTest(point: CGPoint(x: 10, y: 90), annotations: [arrow]))
    }

    func testDiagonalArrowHitOnStroke() {
        let arrow = ArrowAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertEqual(AnnotationHitTester.hitTest(point: CGPoint(x: 50, y: 50), annotations: [arrow]), arrow.id)
    }

    func testPenHitOnStroke() {
        let pen = PenAnnotation(points: [.zero, NSPoint(x: 100, y: 100)])
        XCTAssertEqual(AnnotationHitTester.hitTest(point: CGPoint(x: 50, y: 50), annotations: [pen]), pen.id)
    }

    func testPenMissInEmptyBboxCorner() {
        let pen = PenAnnotation(points: [.zero, NSPoint(x: 100, y: 100)])
        XCTAssertNil(AnnotationHitTester.hitTest(point: CGPoint(x: 10, y: 90), annotations: [pen]),
                     "clicking empty bbox corner of a pen stroke must not select it")
    }

    func testPenMultiSegmentHitAndMiss() {
        let pen = PenAnnotation(points: [.zero, NSPoint(x: 100, y: 0), NSPoint(x: 100, y: 100)])
        // On the vertical segment.
        XCTAssertEqual(AnnotationHitTester.hitTest(point: CGPoint(x: 100, y: 50), annotations: [pen]), pen.id)
        // Empty corner of the L (inside bbox, far from both segments).
        XCTAssertNil(AnnotationHitTester.hitTest(point: CGPoint(x: 10, y: 90), annotations: [pen]))
    }

    // MARK: - Regression: outline shapes still hit inside their bounds

    func testRectStillHitsInsideBounds() {
        let r = RectAnnotation(start: .zero, end: NSPoint(x: 100, y: 100))
        XCTAssertEqual(AnnotationHitTester.hitTest(point: CGPoint(x: 50, y: 50), annotations: [r]), r.id)
    }
}
