import Foundation

/// Snapshot-based undo/redo stack.
///
/// `push(_:)` checkpoints a state after each atomic operation; `undo()`/`redo()`
/// move between checkpoints. A new `push` discards the redo branch (forward
/// history is abandoned once the user makes a fresh change). The stack caps
/// memory by dropping the oldest undo entries past `capacity`.
///
/// The concrete element type used at runtime is `EditorState` (annotations +
/// cropRect + selection), introduced when the value-type `Annotation` lands.
/// `HistoryStack` itself is intentionally generic and free of editor coupling.
final class HistoryStack<T> {

    private var undoStack: [T] = []
    private var redoStack: [T] = []
    private var current: T?
    private let capacity: Int

    init(capacity: Int = 100) {
        precondition(capacity > 0, "HistoryStack capacity must be positive")
        self.capacity = capacity
    }

    /// Checkpoint a new state. Clears the redo branch. Call after each atomic
    /// operation (e.g. after a drag completes, after a style change commits).
    func push(_ state: T) {
        if let cur = current {
            undoStack.append(cur)
            trim()
        }
        current = state
        redoStack.removeAll(keepingCapacity: false)
    }

    /// Move one step back. Returns the previous state, or nil if at baseline.
    func undo() -> T? {
        guard let prev = undoStack.popLast() else { return nil }
        if let cur = current { redoStack.append(cur) }
        current = prev
        return prev
    }

    /// Move one step forward. Returns the next state, or nil if none.
    func redo() -> T? {
        guard let next = redoStack.popLast() else { return nil }
        if let cur = current { undoStack.append(cur) }
        current = next
        return next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Reset to empty (e.g. when loading a new document).
    func clear() {
        undoStack.removeAll(keepingCapacity: false)
        redoStack.removeAll(keepingCapacity: false)
        current = nil
    }

    private func trim() {
        while undoStack.count > capacity {
            undoStack.removeFirst()
        }
    }
}
