import XCTest
@testable import MoliShot

final class PermissionStatusModelTests: XCTestCase {
    func testRefreshNeverRequestsAndTracksGrantAndRevocation() {
        var screen = false
        var accessibility = false
        var prompts = 0
        var registrations = 0
        let model = PermissionStatusModel(
            checkScreen: { screen }, checkAccessibility: { accessibility },
            requestScreen: { prompts += 1; return false },
            requestAccessibility: { prompts += 1; return false },
            accessibilityChanged: { registrations += 1 }
        )
        model.refresh()
        XCTAssertEqual(prompts, 0)
        screen = true
        accessibility = true
        model.refresh()
        XCTAssertTrue(model.screenCaptureGranted)
        XCTAssertTrue(model.accessibilityGranted)
        XCTAssertEqual(registrations, 1)
        model.refresh()
        XCTAssertEqual(registrations, 1)
        accessibility = false
        model.refresh()
        XCTAssertFalse(model.accessibilityGranted)
        XCTAssertEqual(registrations, 2)
        XCTAssertEqual(prompts, 0)
    }

    func testRequestUsesMatchingAPIAndRefreshesImmediateGrant() {
        var screen = false
        var screenRequests = 0
        var accessibilityRequests = 0
        let model = PermissionStatusModel(
            checkScreen: { screen }, checkAccessibility: { false },
            requestScreen: { screenRequests += 1; screen = true; return true },
            requestAccessibility: { accessibilityRequests += 1; return false },
            accessibilityChanged: {}
        )
        model.requestScreenAccess()
        XCTAssertTrue(model.screenCaptureGranted)
        XCTAssertEqual(screenRequests, 1)
        XCTAssertEqual(accessibilityRequests, 0)
        model.requestScreenAccess()
        XCTAssertEqual(screenRequests, 1)
        model.requestAccessibilityAccess()
        XCTAssertEqual(accessibilityRequests, 1)
        XCTAssertFalse(model.accessibilityGranted)
    }

    func testRequestReturnDoesNotOverrideLiveStateAndDelayedGrantIsObserved() {
        var accessibility = false
        let model = PermissionStatusModel(
            checkScreen: { false }, checkAccessibility: { accessibility },
            requestScreen: { true }, requestAccessibility: { true },
            accessibilityChanged: {}
        )
        model.requestScreenAccess()
        model.requestAccessibilityAccess()
        XCTAssertFalse(model.screenCaptureGranted)
        XCTAssertFalse(model.accessibilityGranted)
        accessibility = true
        model.refresh()
        XCTAssertTrue(model.accessibilityGranted)
    }
}
