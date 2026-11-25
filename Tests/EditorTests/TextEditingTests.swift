import AppKit
import XCTest
@testable import MoliShot

@MainActor
final class TextEditingTests: XCTestCase {

    private func makeImage(width: CGFloat = 600, height: CGFloat = 400) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    private func makeHostedEditor(width: CGFloat = 600, height: CGFloat = 400) -> (NSWindow, EditorView) {
        _ = NSApplication.shared
        let image = makeImage(width: width, height: height)
        let editorView = EditorView(image: image)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = editorView
        window.makeKeyAndOrderFront(nil)
        return (window, editorView)
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        point: NSPoint,
        in view: EditorView,
        window: NSWindow,
        clickCount: Int = 1,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ))
    }

    private func activeTextView(in view: EditorView) -> NSTextView? {
        func find(_ v: NSView) -> NSTextView? {
            if let tv = v as? NSTextView { return tv }
            for sub in v.subviews {
                if let found = find(sub) { return found }
            }
            return nil
        }
        return find(view)
    }

    // MARK: - TextAnnotation wrapping & Codable

    func testTextAnnotationWrapsWithMaxWidth() {
        let style = AnnotationStyle(color: .systemRed, fontSize: 20)
        let longText = "This is a fairly long screenshot annotation sentence that should wrap cleanly onto multiple lines."
        let singleLine = TextAnnotation(origin: .zero, text: longText, style: style, maxWidth: nil)
        let wrapped = TextAnnotation(origin: .zero, text: longText, style: style, maxWidth: 160)

        XCTAssertGreaterThan(singleLine.bounds.width, 300)
        XCTAssertLessThanOrEqual(wrapped.bounds.width, 160)
        XCTAssertGreaterThan(wrapped.bounds.height, singleLine.bounds.height * 1.8)
    }

    func testTextAnnotationSupportsExplicitMultiline() {
        let style = AnnotationStyle(color: .systemRed, fontSize: 20)
        let oneLine = TextAnnotation(origin: .zero, text: "Hello", style: style)
        let twoLines = TextAnnotation(origin: .zero, text: "Hello\nWorld", style: style)
        XCTAssertGreaterThan(twoLines.bounds.height, oneLine.bounds.height * 1.5)
    }

    func testTextAnnotationCodablePreservesMaxWidth() throws {
        let original = TextAnnotation(
            origin: NSPoint(x: 10, y: 20),
            text: "Line 1\nLine 2",
            style: AnnotationStyle(color: .systemBlue, fontSize: 18),
            maxWidth: 220
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TextAnnotation.self, from: data)
        XCTAssertEqual(decoded.maxWidth, 220)
        XCTAssertEqual(decoded.text, "Line 1\nLine 2")
    }

    // MARK: - Re-editing existing text

    func testDoubleClickOnTextEntersEditingEvenNearHandle() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        // Create a text annotation via Text tool.
        view.currentTool = .text
        let origin = NSPoint(x: 100, y: 200)
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: origin, in: view, window: window))
        let tv = try XCTUnwrap(activeTextView(in: view))
        tv.string = "Hello"
        view.commitActiveTextEditing()

        XCTAssertEqual(view.annotations.count, 1)
        let textAnn = try XCTUnwrap(view.annotations.first as? TextAnnotation)
        XCTAssertEqual(textAnn.text, "Hello")

        // Switch to Select tool and double-click right on the text's center
        // (which is within 8pt of the top/bottom resize handles on a 24pt tall text box).
        view.currentTool = .select
        let center = NSPoint(x: textAnn.bounds.midX, y: textAnn.bounds.midY)
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: center, in: view, window: window, clickCount: 1))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: center, in: view, window: window, clickCount: 1))
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: center, in: view, window: window, clickCount: 2))

        XCTAssertTrue(view.isEditingText, "Double-clicking existing text must enter edit mode even near resize handles")
        let editTV = try XCTUnwrap(activeTextView(in: view))
        editTV.string = "Edited Text"
        view.commitActiveTextEditing()

        let updated = try XCTUnwrap(view.annotations.first as? TextAnnotation)
        XCTAssertEqual(updated.text, "Edited Text")
    }

    func testClickingExistingTextInTextToolEditsInsteadOfDuplicating() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .text
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 120, y: 200), in: view, window: window))
        let tv = try XCTUnwrap(activeTextView(in: view))
        tv.string = "Original"
        view.commitActiveTextEditing()
        XCTAssertEqual(view.annotations.count, 1)

        let existing = try XCTUnwrap(view.annotations.first as? TextAnnotation)
        view.currentTool = .text
        let center = NSPoint(x: existing.bounds.midX, y: existing.bounds.midY)
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: center, in: view, window: window))

        XCTAssertEqual(view.annotations.count, 1, "Clicking existing text in Text tool must edit it, not create a duplicate")
        XCTAssertTrue(view.isEditingText)
    }

    func testReturnOnSelectedTextStartsEditing() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .text
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 100, y: 200), in: view, window: window))
        try XCTUnwrap(activeTextView(in: view)).string = "Press Enter"
        view.commitActiveTextEditing()

        XCTAssertFalse(view.isEditingText)
        XCTAssertTrue(view.editSelectedTextIfApplicable())
        XCTAssertTrue(view.isEditingText)
    }

    func testEscapeWhileEditingExistingTextRevertsInsteadOfDeleting() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .text
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 100, y: 200), in: view, window: window))
        try XCTUnwrap(activeTextView(in: view)).string = "Keep Me"
        view.commitActiveTextEditing()

        XCTAssertTrue(view.editSelectedTextIfApplicable())
        let tv = try XCTUnwrap(activeTextView(in: view))
        tv.string = ""
        view.cancelCurrentInteraction()

        XCTAssertFalse(view.isEditingText)
        XCTAssertEqual(view.annotations.count, 1, "Cancelling edit on existing text must restore it, not delete it")
        XCTAssertEqual((view.annotations.first as? TextAnnotation)?.text, "Keep Me")
    }

    func testStyleChangeWhileEditingTextSurvivesCommit() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .text
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 100, y: 200), in: view, window: window))
        let tv = try XCTUnwrap(activeTextView(in: view))
        tv.string = "Styled"
        view.setStrokeColor(.systemGreen)
        view.setFontSize(32)
        view.commitActiveTextEditing()

        let ann = try XCTUnwrap(view.annotations.first as? TextAnnotation)
        XCTAssertEqual(ann.text, "Styled")
        XCTAssertEqual(ann.style.fontSize, 32, accuracy: 0.01)
        XCTAssertTrue(ColorSwatchButton.colorsMatch(ann.style.color, .systemGreen))
    }

    func testLongTextAutoWrapsWithinCanvasWidth() throws {
        let (window, view) = makeHostedEditor(width: 400, height: 300)
        defer { window.close() }

        view.currentTool = .text
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 180, y: 220), in: view, window: window))
        let tv = try XCTUnwrap(activeTextView(in: view))
        tv.string = "这是一段非常长的标注文字，用来测试当文字超过截图右边界时是否会自动换行并向下扩展高度，而不会被截断"
        tv.didChangeText()
        view.commitActiveTextEditing()

        let ann = try XCTUnwrap(view.annotations.first as? TextAnnotation)
        XCTAssertNotNil(ann.maxWidth, "Long text reaching canvas edge should auto-wrap with a maxWidth")
        XCTAssertLessThanOrEqual(ann.bounds.maxX, 400, "Wrapped text must remain inside canvas right edge")
        XCTAssertGreaterThan(ann.bounds.height, 40, "Wrapped text must expand vertically")
    }

    // MARK: - Straight line & arrow regression

    func testHorizontalLineIsNotDroppedOnMouseUp() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .line
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 50, y: 150), in: view, window: window))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: NSPoint(x: 250, y: 150), in: view, window: window))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: NSPoint(x: 250, y: 150), in: view, window: window))

        XCTAssertEqual(view.annotations.count, 1, "Horizontal line (height == 0) must not be silently dropped")
        XCTAssertNotNil(view.selected, "Newly drawn shape should be selected automatically")
    }

    func testVerticalArrowIsNotDroppedOnMouseUp() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .arrow
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 150, y: 50), in: view, window: window))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: NSPoint(x: 150, y: 250), in: view, window: window))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: NSPoint(x: 150, y: 250), in: view, window: window))

        XCTAssertEqual(view.annotations.count, 1, "Vertical arrow (width == 0) must not be silently dropped")
        XCTAssertNotNil(view.selected)
    }

    func testArrowKeyNudgeMovesSelectedAnnotation() throws {
        let (window, view) = makeHostedEditor()
        defer { window.close() }

        view.currentTool = .rectangle
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 100, y: 100), in: view, window: window))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: NSPoint(x: 200, y: 200), in: view, window: window))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: NSPoint(x: 200, y: 200), in: view, window: window))

        let before = try XCTUnwrap(view.selected?.bounds)
        XCTAssertTrue(view.nudgeSelection(dx: 10, dy: -5))
        let after = try XCTUnwrap(view.selected?.bounds)
        XCTAssertEqual(after.minX, before.minX + 10, accuracy: 0.01)
        XCTAssertEqual(after.minY, before.minY - 5, accuracy: 0.01)
    }
}
