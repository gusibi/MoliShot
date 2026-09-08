import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        menuBarController = MenuBarController()
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.registerDefaults()
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil)
    }

    @objc private func languageDidChange() {
        buildMainMenu()
    }

    // MARK: - Main menu

    /// Agent apps get no menu for free; without one there is no Edit/Undo,
    /// no Window management, no Help search — the fastest tell that an app
    /// "isn't really a Mac app". Actions with nil target travel the responder
    /// chain, so the key editor window answers canvas operations while an
    /// editing text field keeps its native behaviour.
    private func buildMainMenu() {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        main.addItem(helpMenu())
        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private func appMenu() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(menuItem("About MoliShot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("\(L10n.text(.preferences))…", action: #selector(openPreferences), key: ",", target: self))
        menu.addItem(.separator())
        menu.addItem(menuItem("Hide MoliShot", action: #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(menuItem("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        menu.addItem(menuItem("Show All", action: #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit MoliShot", action: #selector(NSApplication.terminate(_:)), key: "q"))
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private func fileMenu() -> NSMenuItem {
        let menu = NSMenu(title: L10n.text(.fileMenu))
        // ⌘N: the global hotkeys are ⇧⌘-based, so no double-fire here.
        menu.addItem(menuItem(L10n.text(.newAreaScreenshot), action: #selector(captureArea), key: "n", target: self))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text(.save), action: #selector(EditorWindowController.saveDocument(_:)), key: "s"))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text(.close), action: #selector(NSWindow.performClose(_:)), key: "w"))
        let item = NSMenuItem(title: L10n.text(.fileMenu), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: L10n.text(.editMenu))
        menu.addItem(menuItem("\(L10n.text(.undo))", action: #selector(EditorWindowController.undo(_:)), key: "z"))
        menu.addItem(menuItem("\(L10n.text(.redo))", action: #selector(EditorWindowController.redo(_:)), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text(.cut), action: #selector(EditorWindowController.cut(_:)), key: "x"))
        menu.addItem(menuItem(L10n.text(.copy), action: #selector(EditorWindowController.copy(_:)), key: "c"))
        menu.addItem(menuItem(L10n.text(.paste), action: #selector(EditorWindowController.paste(_:)), key: "v"))
        menu.addItem(menuItem(L10n.text(.delete), action: #selector(EditorWindowController.delete(_:)), key: String(UnicodeScalar(NSDeleteCharacter)!)))
        let item = NSMenuItem(title: L10n.text(.editMenu), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func viewMenu() -> NSMenuItem {
        let menu = NSMenu(title: L10n.text(.viewMenu))
        menu.addItem(menuItem(L10n.text(.zoomIn), action: #selector(EditorWindowController.menuZoomIn(_:)), key: "+", modifiers: .command))
        menu.addItem(menuItem(L10n.text(.zoomOut), action: #selector(EditorWindowController.menuZoomOut(_:)), key: "-"))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text(.actualSize), action: #selector(EditorWindowController.menuActualSize(_:)), key: "1"))
        menu.addItem(menuItem(L10n.text(.fit), action: #selector(EditorWindowController.menuFitToWindow(_:)), key: "0"))
        let item = NSMenuItem(title: L10n.text(.viewMenu), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: L10n.text(.windowMenu))
        menu.addItem(menuItem(L10n.text(.minimize), action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(menuItem(L10n.text(.zoomWindow), action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.text(.bringAllToFront), action: #selector(NSApplication.arrangeInFront(_:))))
        let item = NSMenuItem(title: L10n.text(.windowMenu), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func helpMenu() -> NSMenuItem {
        let menu = NSMenu(title: L10n.text(.helpMenu))
        menu.addItem(menuItem(L10n.text(.molishotHelp), action: #selector(openHelp), key: "", target: self))
        let item = NSMenuItem(title: L10n.text(.helpMenu), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func captureArea() { AppCoordinator.shared.captureArea() }
    @objc private func openPreferences() { AppCoordinator.shared.openPreferences() }
    @objc private func openHelp() {
        if let url = URL(string: "https://github.com/gusibi/MoliShot") {
            NSWorkspace.shared.open(url)
        }
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

