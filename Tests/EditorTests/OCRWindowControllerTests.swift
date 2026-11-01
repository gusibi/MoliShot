import AppKit
import XCTest
@testable import MoliShot

@MainActor
final class OCRWindowControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    func testLoadingThenEmptyResultDisablesCopyAndEditing() throws {
        let controller = OCRWindowController { _ in }
        defer { controller.close() }
        let views = descendants(of: try XCTUnwrap(controller.window?.contentView))
        let copy = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.toolTip == L10n.text(.copy) })
        let text = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first)
        let progress = try XCTUnwrap(views.compactMap { $0 as? NSProgressIndicator }.first)
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(progress.isHiddenOrHasHiddenAncestor)
        controller.completeRecognition(.success(""))
        XCTAssertTrue(progress.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(text.isEditable)
        XCTAssertEqual(text.string, L10n.text(.noTextDetected))
    }

    func testFailureStopsLoadingAndDuplicateCompletionIsIgnored() throws {
        let controller = OCRWindowController { _ in }
        defer { controller.close() }
        controller.completeRecognition(.failure(.unreadableImage))
        controller.completeRecognition(.success(""))
        let views = descendants(of: try XCTUnwrap(controller.window?.contentView))
        let text = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(text.string, L10n.text(.ocrImageUnavailable))
        XCTAssertFalse(text.isEditable)
        XCTAssertTrue(try XCTUnwrap(views.compactMap { $0 as? NSProgressIndicator }.first).isHiddenOrHasHiddenAncestor)
    }

    func testAutomaticAndManualCopyUseCurrentTextAndShowFeedback() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = OCRWindowController(pasteboard: pasteboard) { _ in }
        defer { controller.close() }
        controller.completeRecognition(.success("Recognized text"))
        let views = descendants(of: try XCTUnwrap(controller.window?.contentView))
        let copy = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.toolTip == L10n.text(.copy) })
        let text = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first)
        let labels = views.compactMap { $0 as? NSTextField }
        XCTAssertEqual(pasteboard.string(forType: .string), "Recognized text")
        XCTAssertTrue(labels.contains { $0.stringValue == L10n.text(.ocrAutomaticallyCopied) })
        XCTAssertEqual(copy.title, L10n.text(.copy))
        text.string = "Edited text"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
        copy.performClick(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "Edited text")
        XCTAssertTrue(labels.contains { $0.stringValue == L10n.text(.ocrCopied) })
        XCTAssertEqual(copy.title, L10n.text(.ocrCopied))
        text.string = ""
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(labels.contains { $0.stringValue == L10n.text(.ocrCopied) })
    }

    func testCardResolvesBackgroundUsingItsOwnAppearance() throws {
        let card = MoliCardView()
        for name in [NSAppearance.Name.darkAqua, .aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            card.appearance = appearance
            card.applyStyle()
            var expected: CGColor!
            appearance.performAsCurrentDrawingAppearance {
                expected = MoliDesign.card.cgColor
            }
            XCTAssertEqual(card.layer?.backgroundColor, expected)
        }
    }

    func testEditorColorsFollowWindowAppearanceChanges() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = OCRWindowController(pasteboard: pasteboard) { _ in }
        defer { controller.close() }
        controller.completeRecognition(.success("Readable text"))
        let window = try XCTUnwrap(controller.window)
        let text = try XCTUnwrap(descendants(of: try XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextView }.first)
        for name in [NSAppearance.Name.darkAqua, .aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            window.appearance = appearance
            window.contentView?.layoutSubtreeIfNeeded()
            let foreground = try XCTUnwrap(text.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            var difference: CGFloat = 0
            appearance.performAsCurrentDrawingAppearance {
                let ink = foreground.usingColorSpace(.deviceRGB)!.redComponent
                let paper = text.backgroundColor.usingColorSpace(.deviceRGB)!.redComponent
                difference = abs(ink - paper)
            }
            XCTAssertGreaterThan(difference, 0.7, "Text must stay readable after switching appearance")
            XCTAssertTrue(text.drawsBackground)
        }
    }

    func testNativeUndoRedoFindAndFontControls() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = OCRWindowController(pasteboard: pasteboard) { _ in }
        defer { controller.close() }
        controller.completeRecognition(.success("Original"))
        let views = descendants(of: try XCTUnwrap(controller.window?.contentView))
        let text = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first)
        let buttons = views.compactMap { $0 as? NSButton }
        text.insertText("Revised", replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        text.breakUndoCoalescing()
        XCTAssertTrue(try XCTUnwrap(buttons.first { $0.toolTip == L10n.text(.undo) }).isEnabled)
        controller.undo(nil)
        XCTAssertEqual(text.string, "Original")
        XCTAssertTrue(try XCTUnwrap(buttons.first { $0.toolTip == L10n.text(.redo) }).isEnabled)
        controller.redo(nil)
        XCTAssertEqual(text.string, "Revised")
        let size = try XCTUnwrap(text.font).pointSize
        try XCTUnwrap(buttons.first { $0.toolTip == L10n.text(.ocrLargerText) }).performClick(nil)
        XCTAssertEqual(text.font?.pointSize, size + 1)
        XCTAssertEqual(text.string, "Revised")
        try XCTUnwrap(buttons.first { $0.toolTip == L10n.text(.ocrFind) }).performClick(nil)
        XCTAssertTrue(try XCTUnwrap(text.enclosingScrollView).isFindBarVisible)
    }

    func testLongResultScrollsInMinimumWindow() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = OCRWindowController(pasteboard: pasteboard) { _ in }
        defer { controller.close() }
        controller.completeRecognition(.success(Array(repeating: "Long text · 长文本", count: 100).joined(separator: "\n")))
        let window = try XCTUnwrap(controller.window)
        window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: true)
        let content = try XCTUnwrap(window.contentView)
        content.layoutSubtreeIfNeeded()
        let text = try XCTUnwrap(descendants(of: content).compactMap { $0 as? NSTextView }.first)
        text.layoutManager?.ensureLayout(for: try XCTUnwrap(text.textContainer))
        let scroll = try XCTUnwrap(text.enclosingScrollView)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertGreaterThan(scroll.frame.height, 100)
        XCTAssertGreaterThan(text.frame.height, scroll.contentSize.height)
    }

    func testClosedWindowIgnoresRecognitionResult() throws {
        let controller = OCRWindowController { _ in }
        let window = try XCTUnwrap(controller.window)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        controller.completeRecognition(.failure(.unreadableImage))
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let text = try XCTUnwrap(views.compactMap { $0 as? NSTextView }.first)
        XCTAssertNotEqual(text.string, L10n.text(.ocrImageUnavailable))
    }
}
