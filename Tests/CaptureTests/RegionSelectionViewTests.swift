import XCTest
import AppKit
@testable import MoliShot

@MainActor
final class RegionSelectionViewTests: XCTestCase {
    func testWindowListRefreshPreservesSelectionCursor() throws {
        let view = RegionSelectionView(
            frame: NSRect(x: 0, y: 0, width: 1000, height: 1000),
            desktopBounds: NSRect(x: 0, y: 0, width: 1000, height: 1000),
            mode: .area,
            allowsWindowSelectionInAreaMode: false,
            windowRects: []
        )
        // Deliberately differ from the system cursor without moving the user's mouse.
        let systemPosition = NSEvent.mouseLocation
        let movedPosition = NSPoint(x: systemPosition.x + 200, y: systemPosition.y + 100)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: movedPosition, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            clickCount: 0, pressure: 0
        ))
        view.mouseMoved(with: event)
        defer { view.viewDidMoveToWindow() }

        view.updateWindowRects([])

        let cursorPosition = try XCTUnwrap(Mirror(reflecting: view).children
            .first(where: { $0.label == "mouseLocation" })?.value as? NSPoint)
        XCTAssertEqual(cursorPosition, movedPosition,
                       "Loading window candidates must not reset the selection cursor to the system cursor")
    }

    func testEndingSelectionRestoresSystemCursorAtSelectionEndpoint() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let originalPosition = try XCTUnwrap(CGEvent(source: nil)).location
        let view = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            desktopBounds: screen.frame,
            mode: .area,
            allowsWindowSelectionInAreaMode: false,
            windowRects: []
        )
        view.beginPointerPreservationSession()
        defer {
            view.endPointerPreservationSession()
            view.viewDidMoveToWindow()
            CGWarpMouseCursorPosition(originalPosition)
        }
        let active = Mirror(reflecting: view).children
            .first(where: { $0.label == "isPointerPreservationActive" })?.value as? Bool
        try XCTSkipUnless(active == true, "Cursor disassociation is unavailable")

        // Start from a deterministic virtual position, then complete a real drag
        // through the same intercepted-event handlers used by capture sessions.
        view.handleInterceptedEvent(.init(type: .leftMouseDown, location: originalPosition,
                                         modifiers: [], deltaX: 100, deltaY: -100))
        view.handleInterceptedEvent(.init(type: .leftMouseDragged, location: originalPosition,
                                         modifiers: [], deltaX: 150, deltaY: -120))
        var selection: NSRect?
        view.onResult = { result in
            if case .area(let rect) = result { selection = rect }
        }
        view.handleInterceptedEvent(.init(type: .leftMouseUp, location: originalPosition,
                                         modifiers: [], deltaX: 0, deltaY: 0))
        let rect = try XCTUnwrap(selection)
        let expected = CGPoint(x: rect.maxX, y: screen.frame.maxY - rect.maxY)

        view.endPointerPreservationSession()

        let actual = try XCTUnwrap(CGEvent(source: nil)).location
        XCTAssertEqual(actual.x, expected.x, accuracy: 1)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1)
        // Repeated cleanup must not move the cursor again.
        view.endPointerPreservationSession()
        XCTAssertEqual(try XCTUnwrap(CGEvent(source: nil)).location, actual)
    }

}
