import AppKit
import XCTest
@testable import MoliShot

@MainActor
final class EditorChromeTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func makeEditor() -> EditorWindowController {
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 1000, height: 600))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 600).fill()
        image.unlockFocus()
        let editor = EditorWindowController(image: image, title: "Editor UI test", onAddToShelf: { _ in }, onClose: { _ in })
        editor.showWindow(nil)
        editor.window?.contentView?.layoutSubtreeIfNeeded()
        return editor
    }

    func testNativeToolbarRetainsAllToolsAndTracksSelection() throws {
        let editor = makeEditor()
        defer { editor.close() }
        let toolbar = try XCTUnwrap(editor.window?.toolbar)
        let root = try XCTUnwrap(editor.window?.contentView)
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? EditorView }.first)
        for tool in AnnotationTool.allCases {
            let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == tool.rawValue })
            XCTAssertEqual(item.label, tool.title)
            XCTAssertNotNil(item.image)
        }
        let arrow = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "arrow" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrow.action), to: arrow.target, from: arrow))
        XCTAssertEqual(canvas.currentTool, .arrow)
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "arrow")
        let crop = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "crop" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(crop.action), to: crop.target, from: crop))
        XCTAssertTrue(canvas.cropMode)
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, "crop")
        canvas.cancelCropMode()
        XCTAssertFalse(canvas.cropMode)
        XCTAssertEqual(toolbar.selectedItemIdentifier?.rawValue, canvas.currentTool.rawValue)
    }

    func testNativeUndoRedoValidationFollowsAnActualAnnotation() throws {
        let editor = makeEditor()
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let toolbar = try XCTUnwrap(window.toolbar)
        let canvas = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? EditorView }.first)
        let undo = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "editor.undo" })
        let redo = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "editor.redo" })
        XCTAssertFalse(editor.validateToolbarItem(undo))
        XCTAssertFalse(editor.validateToolbarItem(redo))
        canvas.currentTool = .rectangle
        func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, NSPoint(x: 80, y: 80)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 250, y: 200)))
        canvas.mouseUp(with: try event(.leftMouseUp, NSPoint(x: 250, y: 200)))
        XCTAssertEqual(canvas.annotations.count, 1)
        XCTAssertTrue(editor.validateToolbarItem(undo))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(undo.action), to: undo.target, from: undo))
        XCTAssertEqual(canvas.annotations.count, 0)
        XCTAssertTrue(editor.validateToolbarItem(redo))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(redo.action), to: redo.target, from: redo))
        XCTAssertEqual(canvas.annotations.count, 1)
    }

    func testControlBarFitsNarrowAndWideWindowsInBothLanguagesAndAppearances() throws {
        let previous = L10n.selectedLanguage
        defer { L10n.selectedLanguage = previous }
        let editor = makeEditor()
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let root = try XCTUnwrap(window.contentView)
        let actions: Set<String> = ["addToShelf:", "clearTap", "runOCR", "zoomIn", "zoomOut", "actualSize", "fitToWindow", "showOverflowPopover:"]
        for language in [AppLanguage.english, .simplifiedChinese] {
            L10n.selectedLanguage = language
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                for width: CGFloat in [700, 1100] {
                    window.setContentSize(NSSize(width: width, height: 600))
                    root.layoutSubtreeIfNeeded()
                    for button in descendants(root).compactMap({ $0 as? NSButton }) where !button.isHiddenOrHasHiddenAncestor {
                        guard actions.contains(button.action.map(NSStringFromSelector) ?? "") else { continue }
                        XCTAssertTrue(root.bounds.contains(root.convert(button.bounds, from: button)), "Clipped action: \(button.accessibilityLabel() ?? "") at \(width)")
                        XCTAssertTrue(button.title.isEmpty)
                        XCTAssertFalse(button.accessibilityLabel()?.isEmpty ?? true)
                        if #available(macOS 26, *) { XCTAssertEqual(button.bezelStyle, .glass) }
                    }
                    XCTAssertNotNil(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "editor.copy" })
                    XCTAssertNotNil(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "editor.save" })
                }
            }
        }
    }

    func testCropConfirmationUsesNativeControlsAndDispatchesActions() throws {
        var applied = 0
        var cancelled = 0
        let bar = CropConfirmBar(applyAction: { applied += 1 }, cancelAction: { cancelled += 1 })
        let buttons = descendants(bar).compactMap { $0 as? NSButton }
        let apply = try XCTUnwrap(buttons.first { $0.action == NSSelectorFromString("applyTapped") })
        let cancel = try XCTUnwrap(buttons.first { $0.action == NSSelectorFromString("cancelTapped") })
        if #available(macOS 26, *) {
            XCTAssertEqual(apply.bezelStyle, .glass)
            XCTAssertEqual(apply.borderShape, .capsule)
            XCTAssertEqual(apply.tintProminence, .primary)
            XCTAssertEqual(cancel.bezelStyle, .glass)
        }
        apply.performClick(nil)
        cancel.performClick(nil)
        XCTAssertEqual(applied, 1)
        XCTAssertEqual(cancelled, 1)
    }
}
