import XCTest
@testable import MoliShot

/// HistoryStack is a generic snapshot-based undo/redo stack.
/// `EditorState` (the concrete T used at runtime) is defined when the
/// value-type `Annotation` lands in a later issue; here we test the
/// generic behaviour with a simple value type.
private struct Step: Equatable { let n: Int }

final class HistoryStackTests: XCTestCase {

    // MARK: - Empty stack

    func testEmptyStackCannotUndoOrRedo() {
        let stack = HistoryStack<Step>()
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func testUndoOnEmptyReturnsNil() {
        let stack = HistoryStack<Step>()
        XCTAssertNil(stack.undo())
    }

    func testRedoOnEmptyReturnsNil() {
        let stack = HistoryStack<Step>()
        XCTAssertNil(stack.redo())
    }

    // MARK: - Single push (baseline)

    func testSinglePushCannotUndo() {
        // Pushing only the baseline leaves nothing to undo.
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    // MARK: - Undo / redo round trip

    func testUndoReturnsPreviousStateAndEnablesRedo() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))

        XCTAssertTrue(stack.canUndo)
        XCTAssertEqual(stack.undo(), Step(n: 0))
        XCTAssertTrue(stack.canRedo)
        XCTAssertFalse(stack.canUndo)
    }

    func testRedoRestoresState() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))
        _ = stack.undo()

        XCTAssertEqual(stack.redo(), Step(n: 1))
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func testMultipleUndoRedoRoundTrip() {
        let stack = HistoryStack<Step>()
        (0...3).forEach { stack.push(Step(n: $0)) }

        XCTAssertEqual(stack.undo(), Step(n: 2))
        XCTAssertEqual(stack.undo(), Step(n: 1))
        XCTAssertEqual(stack.undo(), Step(n: 0))
        XCTAssertFalse(stack.canUndo)

        XCTAssertEqual(stack.redo(), Step(n: 1))
        XCTAssertEqual(stack.redo(), Step(n: 2))
        XCTAssertEqual(stack.redo(), Step(n: 3))
        XCTAssertFalse(stack.canRedo)
    }

    // MARK: - Redo cleared on new push

    func testNewPushClearsRedoStack() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))
        _ = stack.undo()
        XCTAssertTrue(stack.canRedo)

        // New operation after undo must discard the redo branch.
        stack.push(Step(n: 2))
        XCTAssertFalse(stack.canRedo)
        XCTAssertTrue(stack.canUndo)
        XCTAssertEqual(stack.undo(), Step(n: 0))
    }

    // MARK: - Capacity

    func testCapacityDropsOldestUndoEntries() {
        let stack = HistoryStack<Step>(capacity: 3)
        // Push 5 states; undo stack capacity is 3 so the 2 oldest are dropped.
        (0...4).forEach { stack.push(Step(n: $0)) }

        // We can undo at most `capacity` steps back.
        XCTAssertEqual(stack.undo(), Step(n: 3))
        XCTAssertEqual(stack.undo(), Step(n: 2))
        XCTAssertEqual(stack.undo(), Step(n: 1))
        // n:0 was dropped, so one more undo returns nil.
        XCTAssertNil(stack.undo())
    }

    // MARK: - Clear

    func testClearResetsStack() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))
        _ = stack.undo()

        stack.clear()
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        XCTAssertNil(stack.undo())
        XCTAssertNil(stack.redo())
    }

    func testClearAllowsFreshHistory() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))
        stack.clear()

        stack.push(Step(n: 9))
        XCTAssertFalse(stack.canUndo)
        stack.push(Step(n: 10))
        XCTAssertEqual(stack.undo(), Step(n: 9))
    }

    // MARK: - replaceCurrent (coalescing)

    func testReplaceCurrentCoalescesWithoutNewUndoEntry() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))  // undoStack=[0], current=1

        // Simulate a continuous drag: subsequent ticks replace current.
        stack.replaceCurrent(Step(n: 2))
        stack.replaceCurrent(Step(n: 3))

        // One undo step back to the pre-drag state, not three.
        XCTAssertEqual(stack.undo(), Step(n: 0))
        XCTAssertNil(stack.undo(), "coalesced changes must not create extra undo entries")
    }

    func testReplaceCurrentClearsRedo() {
        let stack = HistoryStack<Step>()
        stack.push(Step(n: 0))
        stack.push(Step(n: 1))
        _ = stack.undo()
        XCTAssertTrue(stack.canRedo)

        stack.replaceCurrent(Step(n: 9))
        XCTAssertFalse(stack.canRedo, "replaceCurrent must discard the redo branch")
    }
}
