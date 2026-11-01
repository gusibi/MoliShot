import AppKit
import XCTest
@testable import MoliShot

@MainActor
final class ScreenshotShelfTests: XCTestCase {
    private var directory: URL!
    private var store: ScreenshotShelfStore!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ScreenshotShelfStore(directory: directory)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func image(_ color: NSColor, width: Int = 80, height: Int = 40) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width / 2, height: height / 2))
    }

    func testPersistsFinalPixelsOrderAndRemovalWithoutBreakingCopiedFiles() throws {
        let first = try store.append(image: image(.red))
        let second = try store.append(image: image(.blue, width: 160))
        XCTAssertEqual(first.pixelWidth, 80, "Retina pixels must survive export")
        try store.move(id: second.id, to: 0)
        XCTAssertEqual(ScreenshotShelfStore(directory: directory).entries.map(\.id), [second.id, first.id])
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try store.copy(.files, to: board)
        let urls = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self]) as? [URL])
        XCTAssertEqual(urls, [store.url(for: second), store.url(for: first)])
        try store.remove(id: first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path))
        XCTAssertEqual(ScreenshotShelfStore(directory: directory).entries.map(\.id), [second.id])
    }

    func testCopiesThreeIndependentPNGsInShelfOrder() throws {
        for color in [NSColor.red, .green, .blue] { try store.append(image: image(color)) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try store.copy(.images, to: board)
        let items = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(items.count, 3)
        for (item, entry) in zip(items, store.entries) {
            XCTAssertEqual(item.data(forType: .png), try Data(contentsOf: store.url(for: entry)))
        }
    }

    func testClearPersistsEmptyShelfAndKeepsEveryCopiedFileReadable() throws {
        for color in [NSColor.red, .green, .blue] { try store.append(image: image(color)) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try store.copy(.files, to: board)
        let urls = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self]) as? [URL])
        XCTAssertEqual(urls.count, 3)
        try store.removeAll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(ScreenshotShelfStore(directory: directory).entries.isEmpty)
        store.pruneUnreferencedFiles()
        for url in urls { XCTAssertNotNil(NSImage(contentsOf: url)) }
        XCTAssertEqual(board.pasteboardItems?.count, 3)
        try store.removeAll()
    }

    func testClearFailurePreservesEntries() throws {
        try store.append(image: image(.red))
        let index = directory.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.removeAll())
        XCTAssertEqual(store.entries.count, 1)
    }

    func testVisibleRemoveButtonDeletesItsOwnItemAndClearEmptiesShelf() throws {
        for color in [NSColor.red, .green, .blue] { try store.append(image: image(color)) }
        let ids = store.entries.map(\.id)
        let controller = ScreenshotShelfWindowController(store: store, onCapture: {})
        defer { controller.close() }
        let root = try XCTUnwrap(controller.window?.contentView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let collection = try XCTUnwrap(descendants(root).compactMap { $0 as? NSCollectionView }.first)
        let item = controller.collectionView(collection, itemForRepresentedObjectAt: IndexPath(item: 0, section: 0))
        let remove = try XCTUnwrap(descendants(item.view).compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("removeItem") })
        XCTAssertFalse(remove.isHidden)
        remove.performClick(nil)
        XCTAssertEqual(store.entries.map(\.id), Array(ids.dropFirst()), "The close button must use item identity, not the current selection")
        let clear = try XCTUnwrap(descendants(root).compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("clearShelf") })
        XCTAssertTrue(clear.isEnabled)
        clear.performClick(nil)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(clear.isEnabled)
    }

    func testCopyAllButtonWritesThreeOrderedFilesAndFormatSpecificFeedback() throws {
        for color in [NSColor.red, .green, .blue] { try store.append(image: image(color)) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let controller = ScreenshotShelfWindowController(store: store, pasteboard: board, onCapture: {})
        defer { controller.close() }
        let root = try XCTUnwrap(controller.window?.contentView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let copy = try XCTUnwrap(descendants(root).compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("copyAll") })
        copy.performClick(nil)
        let urls = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self]) as? [URL])
        XCTAssertEqual(urls, store.entries.map { store.url(for: $0) })
        XCTAssertTrue(descendants(root).compactMap { $0 as? NSTextField }.contains { $0.stringValue == ShelfText.copied(3, format: .files) })
        XCTAssertNotEqual(ShelfText.copied(3, format: .files), ShelfText.copied(3, format: .merged))
    }

    func testMergePreservesPixelsAndTopToBottomOrder() throws {
        try store.append(image: image(.red, width: 80, height: 40))
        try store.append(image: image(.blue, width: 100, height: 60))
        let merged = try store.mergedImage()
        let cg = try XCTUnwrap(merged.cgImageRef)
        XCTAssertEqual(cg.width, 100)
        XCTAssertEqual(cg.height, 116)
        let rep = NSBitmapImageRep(cgImage: cg)
        let top = try XCTUnwrap(rep.colorAt(x: 50, y: 10)?.usingColorSpace(.deviceRGB))
        let bottom = try XCTUnwrap(rep.colorAt(x: 50, y: 100)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(top.redComponent, 0.9)
        XCTAssertGreaterThan(bottom.blueComponent, 0.9)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try store.copy(.merged, to: board)
        XCTAssertEqual(board.pasteboardItems?.count, 1)
    }

    func testFailureLeavesClipboardAndShelfUntouched() throws {
        let entry = try store.append(image: image(.red))
        try FileManager.default.removeItem(at: store.url(for: entry))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Keep existing content", forType: .string)
        XCTAssertThrowsError(try store.copy(.images, to: board))
        XCTAssertEqual(board.string(forType: .string), "Keep existing content")
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(ScreenshotShelfStore(directory: directory).entries.isEmpty)
    }

    func testFailedIndexWriteDoesNotLoseInMemoryEntries() throws {
        try store.append(image: image(.red))
        let index = directory.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.remove(id: store.entries[0].id))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertThrowsError(try store.append(image: image(.blue)))
        XCTAssertEqual(store.entries.count, 1)
        let pngs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
        XCTAssertEqual(pngs.count, 1, "A failed append must clean up only its own new file")
    }

    func testPrunesOnlyOldUnreferencedPNGs() throws {
        let active = try store.append(image: image(.red))
        let old = try store.append(image: image(.blue))
        try store.remove(id: old.id)
        let recent = try store.append(image: image(.green))
        try store.remove(id: recent.id)
        let oldDate = Date(timeIntervalSinceNow: -8 * 24 * 60 * 60)
        for entry in [active, old] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: store.url(for: entry).path)
        }
        store.pruneUnreferencedFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: active).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: old).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: recent).path))
    }

    func testRemovalStartsNewGracePeriodForAnOldCapture() throws {
        let entry = try store.append(image: image(.blue))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)],
                                             ofItemAtPath: store.url(for: entry).path)
        try store.remove(id: entry.id)
        store.pruneUnreferencedFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: entry).path))
    }

    func testEditorAddsAnnotatedFinalImageAndClosesOnlyOnSuccess() throws {
        let base = image(.white, width: 240, height: 160)
        var closed = false
        let controller = EditorWindowController(image: base, title: "Shelf integration", onAddToShelf: { [self] in
            try store.append(image: $0)
        }, onClose: { _ in closed = true })
        defer { controller.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let canvas = try XCTUnwrap(descendants(try XCTUnwrap(controller.window?.contentView)).compactMap { $0 as? EditorView }.first)
        canvas.currentTool = .rectangle
        canvas.strokeColor = .red
        func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: controller.window!.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, NSPoint(x: 10, y: 10)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 90, y: 60)))
        canvas.mouseUp(with: try event(.leftMouseUp, NSPoint(x: 90, y: 60)))
        XCTAssertEqual(canvas.annotations.count, 1)
        let expected = canvas.renderFinalImage().pngData()
        XCTAssertNotEqual(expected, base.pngData())
        controller.addToShelf(nil)
        XCTAssertTrue(closed)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: store.url(for: store.entries[0])), expected)
        XCTAssertEqual(store.entries[0].pixelWidth, 240)
    }

    func testMergeLimitRejectsBeforeAllocatingAndPreservesClipboard() throws {
        let entry = try store.append(image: image(.red))
        let huge = ShelfEntry(id: entry.id, filename: entry.filename, pixelWidth: 20_000, pixelHeight: 20_000)
        try JSONEncoder().encode([huge]).write(to: directory.appendingPathComponent("index.json"))
        let oversized = ScreenshotShelfStore(directory: directory)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Keep existing content", forType: .string)
        XCTAssertThrowsError(try oversized.copy(.merged, to: board))
        XCTAssertEqual(board.string(forType: .string), "Keep existing content")
    }

    func testEditorKeepsWorkingWindowWhenAddingFails() throws {
        var closed = false
        let controller = EditorWindowController(image: image(.white), title: "Failed shelf write",
            onAddToShelf: { _ in throw ShelfError.unreadableImage }, onClose: { _ in closed = true })
        defer { controller.close() }
        controller.showWindow(nil)
        controller.addToShelf(nil)
        XCTAssertFalse(closed)
        XCTAssertTrue(controller.window?.isVisible == true)
    }

    func testCaptureVisibilityRestoresOnlyVisibleWindows() throws {
        let visible = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
        let hidden = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        visible.orderFrontRegardless()
        defer { visible.orderOut(nil); hidden.orderOut(nil) }
        let visibility = CaptureWindowVisibility()
        visibility.hide([visible, hidden])
        XCTAssertFalse(visible.isVisible)
        visibility.restore()
        XCTAssertTrue(visible.isVisible)
        XCTAssertFalse(hidden.isVisible)
        visibility.restore()
        XCTAssertTrue(visible.isVisible)
    }

    func testNativeShelfEmptyFilledCollapsedAndAppearanceSnapshots() throws {
        let previous = L10n.selectedLanguage
        defer { L10n.selectedLanguage = previous }
        let controller = ScreenshotShelfWindowController(store: store, onCapture: {})
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let root = try XCTUnwrap(window.contentView)
        controller.present()
        window.makeKeyAndOrderFront(nil)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let buttons = descendants(root).compactMap { $0 as? NSButton }
        let copy = try XCTUnwrap(buttons.first { $0.action == NSSelectorFromString("copyAll") })
        XCTAssertFalse(copy.isEnabled)
        for color in [NSColor.systemBlue, .systemOrange, .systemGreen] { try store.append(image: image(color, width: 640, height: 400)) }
        XCTAssertTrue(copy.isEnabled, "The panel must observe additions without reopening")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("MoliShotShelfQA")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .simplifiedChinese] {
            L10n.selectedLanguage = language
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: name)
                root.layoutSubtreeIfNeeded()
                XCTAssertFalse(root.hasAmbiguousLayout)
                for label in descendants(root).compactMap({ $0 as? NSTextField }) where label.stringValue.contains(" × ") {
                    XCTAssertGreaterThan(label.bounds.width, 100)
                    XCTAssertGreaterThan(label.bounds.height, 10)
                }
                for button in buttons where !button.isHiddenOrHasHiddenAncestor {
                    XCTAssertTrue(root.bounds.contains(root.convert(button.bounds, from: button)), "Button outside panel: \(button.title)")
                    if ["captureNext", "copyAll", "explainDrag", "toggleCollapsed", "clearShelf", "showSharingMenu:"].contains(button.action.map(NSStringFromSelector) ?? "") {
                        XCTAssertTrue(button.title.isEmpty)
                        XCTAssertNotNil(button.image)
                        XCTAssertFalse(button.accessibilityLabel()?.isEmpty ?? true)
                        XCTAssertFalse(button.toolTip?.isEmpty ?? true)
                        if #available(macOS 26, *) {
                            XCTAssertEqual(button.bezelStyle, .glass)
                            XCTAssertEqual(button.borderShape, .circle)
                            XCTAssertGreaterThanOrEqual(button.bounds.height, 36)
                        }
                    }
                }
                let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("shelf-\(language.rawValue)-\(name.rawValue).png"))
            }
        }
        let toggle = try XCTUnwrap(buttons.first { $0.action == NSSelectorFromString("toggleCollapsed") })
        toggle.performClick(nil)
        XCTAssertLessThan(root.frame.height, 100)
        XCTAssertTrue(copy.isEnabled)
        toggle.performClick(nil)
        XCTAssertGreaterThan(root.frame.height, 200)
    }
}
