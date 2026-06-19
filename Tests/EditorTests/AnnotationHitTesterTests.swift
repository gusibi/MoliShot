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
}
