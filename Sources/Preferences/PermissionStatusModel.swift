import Combine

/// Reads live system state. Request return values are not the user's eventual decision.
final class PermissionStatusModel: ObservableObject {
    @Published private(set) var screenCaptureGranted = false
    @Published private(set) var accessibilityGranted = false

    private let checkScreen: () -> Bool
    private let checkAccessibility: () -> Bool
    private let requestScreen: () -> Bool
    private let requestAccessibility: () -> Bool
    private let accessibilityChanged: () -> Void

    init(
        checkScreen: @escaping () -> Bool = { Permissions.hasScreenCapturePermission },
        checkAccessibility: @escaping () -> Bool = { Permissions.hasAccessibilityPermission },
        requestScreen: @escaping () -> Bool = { Permissions.requestScreenCaptureAccessUserInitiated() },
        requestAccessibility: @escaping () -> Bool = { Permissions.requestAccessibilityAccessUserInitiated() },
        accessibilityChanged: @escaping () -> Void = { HotkeyManager.shared.refreshRegistrationMode() }
    ) {
        self.checkScreen = checkScreen
        self.checkAccessibility = checkAccessibility
        self.requestScreen = requestScreen
        self.requestAccessibility = requestAccessibility
        self.accessibilityChanged = accessibilityChanged
        refresh()
    }

    func refresh() {
        let screen = checkScreen()
        let accessibility = checkAccessibility()
        if screenCaptureGranted != screen { screenCaptureGranted = screen }
        if accessibilityGranted != accessibility {
            accessibilityGranted = accessibility
            accessibilityChanged()
        }
    }

    func requestScreenAccess() {
        refresh()
        if !screenCaptureGranted { _ = requestScreen() }
        refresh()
    }

    func requestAccessibilityAccess() {
        refresh()
        if !accessibilityGranted { _ = requestAccessibility() }
        refresh()
    }
}
