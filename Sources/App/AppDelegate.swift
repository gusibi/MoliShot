import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.registerDefaults()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hotkeyManager?.refreshRegistrationMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
