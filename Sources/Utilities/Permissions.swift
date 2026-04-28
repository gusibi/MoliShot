import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

enum Permissions {
    /// Whether Core Graphics believes screen capture is allowed for this process.
    /// Note: this can lag behind ScreenCaptureKit in some Debug / unsigned builds;
    /// do **not** use it to drive repeated `CGRequestScreenCaptureAccess()` calls.
    static var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Whether the system is currently in Secure Input mode (e.g. a password field is focused).
    /// In this state, the screen content under the secure input area is blacked out by the system.
    static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Opens **Privacy & Security → Screen Recording** so the user can toggle MoliShot.
    static func openScreenRecordingPrivacySettings() {
        // `Privacy_ScreenCapture` is the stable anchor for the Screen Recording list
        // (labeled "Screen & System Audio Recording" on newer macOS).
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Only call from an explicit user tap (e.g. a "Request access" button in Preferences).
    /// Never call this automatically on launch — if `CGPreflightScreenCaptureAccess()` is
    /// still false (common when running unsigned from Xcode), macOS will show the system
    /// permission sheet **every time**, even after the user already enabled the app.
    @discardableResult
    static func requestScreenCaptureAccessUserInitiated() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilityPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    static func requestAccessibilityAccessUserInitiated() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
