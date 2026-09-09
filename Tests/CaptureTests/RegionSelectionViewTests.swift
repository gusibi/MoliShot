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
}
