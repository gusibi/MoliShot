import AppKit
import XCTest
@testable import MoliShot

@MainActor
final class OCRWindowControllerTests: XCTestCase {
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
        text.string = "Edited text"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
        copy.performClick(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "Edited text")
        XCTAssertTrue(labels.contains { $0.stringValue == L10n.text(.ocrCopied) })
        text.string = ""
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(labels.contains { $0.stringValue == L10n.text(.ocrCopied) })
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
