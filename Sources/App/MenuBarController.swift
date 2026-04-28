import AppKit
import HotKey

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let coordinator = AppCoordinator.shared
    private let menu = NSMenu()
    private var actionItems: [HotkeyAction: NSMenuItem] = [:]
    private var actionTitles: [HotkeyAction: String] = [:]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshShortcutDisplay), name: .hotkeysDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "MoliShot")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "MoliShot"
    }

    private func buildMenu() {
        menu.delegate = self
        menu.removeAllItems()
        actionItems.removeAll()
        actionTitles.removeAll()

        menu.addItem(makeHotkeyItem(for: .captureArea, action: #selector(captureArea)))
        menu.addItem(makeHotkeyItem(for: .captureFull, action: #selector(captureFull)))
        menu.addItem(makeHotkeyItem(for: .captureScrolling, action: #selector(captureScrolling)))
        menu.addItem(.separator())
        menu.addItem(makeHotkeyItem(for: .colorPicker, action: #selector(openPicker), title: L10n.text(.screenColorPicker)))
        menu.addItem(makeHotkeyItem(for: .ocr, action: #selector(runScreenOCR), title: L10n.text(.ocr)))
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.text(.history) + "...", action: #selector(openHistory), key: "h"))
        menu.addItem(makeItem(L10n.text(.preferences) + "...", action: #selector(openPreferences), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(L10n.text(.about), action: #selector(about), key: ""))
        menu.addItem(makeItem(L10n.text(.quit), action: #selector(quit), key: "q"))

        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags = [.command, .shift]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func makeHotkeyItem(for hotkeyAction: HotkeyAction, action: Selector, title: String? = nil) -> NSMenuItem {
        let baseTitle = title ?? hotkeyAction.title
        let item = makeItem(baseTitle, action: action, key: "")
        actionItems[hotkeyAction] = item
        actionTitles[hotkeyAction] = baseTitle
        configureShortcutDisplay(for: item, action: hotkeyAction, baseTitle: baseTitle)
        return item
    }

    @objc private func refreshShortcutDisplay() {
        for (action, item) in actionItems {
            guard let baseTitle = actionTitles[action] else { continue }
            configureShortcutDisplay(for: item, action: action, baseTitle: baseTitle)
        }
    }

    @objc private func languageDidChange() {
        buildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshShortcutDisplay()
    }

    private func configureShortcutDisplay(for item: NSMenuItem, action: HotkeyAction, baseTitle: String) {
        let combo = HotkeyManager.shared.combo(for: action)
        item.title = baseTitle
        item.keyEquivalentModifierMask = combo.modifiers

        if let keyEquivalent = keyEquivalentString(for: combo) {
            item.keyEquivalent = keyEquivalent
            item.toolTip = nil
        } else {
            item.keyEquivalent = ""
            item.title = "\(baseTitle) (\(combo.description))"
            item.toolTip = nil
        }
    }

    private func keyEquivalentString(for combo: KeyCombo) -> String? {
        guard let key = combo.key else { return nil }

        switch key {
        case .space: return " "
        case .tab: return "\t"
        case .return: return "\r"
        case .delete: return String(UnicodeScalar(NSDeleteCharacter)!)
        case .escape: return String(UnicodeScalar(0x1B)!)
        case .upArrow: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case .downArrow: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case .leftArrow: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case .rightArrow: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case .home: return String(UnicodeScalar(NSHomeFunctionKey)!)
        case .end: return String(UnicodeScalar(NSEndFunctionKey)!)
        case .pageUp: return String(UnicodeScalar(NSPageUpFunctionKey)!)
        case .pageDown: return String(UnicodeScalar(NSPageDownFunctionKey)!)
        default:
            let keyEquivalent = key.description.lowercased()
            return keyEquivalent.count == 1 ? keyEquivalent : nil
        }
    }

    @objc private func captureArea() { coordinator.captureArea() }
    @objc private func captureFull() { coordinator.captureFullScreen() }
    @objc private func captureScrolling() { coordinator.captureScrolling() }
    @objc private func openPicker() { coordinator.openColorPicker() }
    @objc private func runScreenOCR() { coordinator.runScreenOCR() }
    @objc private func openHistory() { coordinator.openHistory() }
    @objc private func openPreferences() { coordinator.openPreferences() }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}
