import AppKit

/// Pure hit-testing of annotations.
///
/// Returns the id of the topmost annotation (later in the array = drawn on
/// top) whose `hitTest(_:)` accepts `point`, or nil if none match. Behaviour
/// mirrors the previous inline `annotations.reversed().first { $0.hitTest(p) }`.
///
/// The per-type hit rules still live on each `Annotation` (currently coarse
/// bounding-box with insets); issue #9 upgrades line/arrow/pen to
/// distance-to-segment nearest matching.
enum AnnotationHitTester {

    static func hitTest(point: CGPoint, annotations: [Annotation], toleranceScale: CGFloat = 1) -> UUID? {
        for ann in annotations.reversed() where ann.hitTest(point, toleranceScale: toleranceScale) {
            return ann.id
        }
        return nil
    }
}
