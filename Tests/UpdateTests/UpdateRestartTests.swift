import AppKit
import XCTest
@testable import MoliShot

final class UpdateRestartTests: XCTestCase {
    func testUpdateWaitsForEditorToClose() {
        _ = NSApplication.shared
        let coordinator = AppCoordinator.shared
        XCTAssertFalse(coordinator.hasWorkToFinishBeforeUpdate)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        let editor = coordinator.openEditor(with: image)
        XCTAssertTrue(coordinator.hasWorkToFinishBeforeUpdate)
        editor.close()
        XCTAssertFalse(coordinator.hasWorkToFinishBeforeUpdate)
    }
}
