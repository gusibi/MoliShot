import AppKit
import HotKey

extension Notification.Name {
    static let hotkeysDidChange = Notification.Name("HotkeysDidChangeNotification")
    static let hotkeyRegistrationModeDidChange = Notification.Name("HotkeyRegistrationModeDidChangeNotification")
}

enum HotkeyRegistrationMode {
    case eventTap
    case fallbackHotKey
}

enum HotkeyAction: String, CaseIterable {
    case captureArea
    case captureFull
    case captureScrolling
    case colorPicker
    case ocr

    var title: String {
        switch self {
        case .captureArea: return L10n.text(.captureArea)
        case .captureFull: return L10n.text(.captureFullScreen)
        case .captureScrolling: return L10n.text(.scrollingScreenshot)
        case .colorPicker: return L10n.text(.colorPicker)
        case .ocr: return L10n.text(.ocr)
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .captureArea: return KeyCombo(key: .one, modifiers: [.command, .shift])
        case .captureFull: return KeyCombo(key: .three, modifiers: [.command, .shift])
        case .captureScrolling: return KeyCombo(key: .four, modifiers: [.command, .shift])
        case .colorPicker: return KeyCombo(key: .p, modifiers: [.command, .shift])
        case .ocr: return KeyCombo(key: .r, modifiers: [.command, .shift])
        }
    }

    func perform() {
        switch self {
        case .captureArea: AppCoordinator.shared.captureArea()
        case .captureFull: AppCoordinator.shared.captureFullScreen()
        case .captureScrolling: AppCoordinator.shared.captureScrolling()
        case .colorPicker: AppCoordinator.shared.openColorPicker()
        case .ocr: AppCoordinator.shared.runScreenOCR()
        }
    }
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [HotkeyAction: HotKey] = [:]
    private let eventTapMonitor = EventTapHotkeyMonitor()
    private let userDefaults = UserDefaults.standard
    private let storagePrefix = "hotkey."
    private(set) var registrationMode: HotkeyRegistrationMode = .fallbackHotKey

    private init() {}

    func registerDefaults() {
        registerConfiguredHotkeys()
    }

    func registerConfiguredHotkeys() {
        let combos = Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0, combo(for: $0)) })
        eventTapMonitor.stop()
        unregisterFallbackHotkeys()

        if Permissions.hasAccessibilityPermission {
            eventTapMonitor.configure(combos: combos) { action in
                action.perform()
            }
            if eventTapMonitor.start() {
                registrationMode = .eventTap
                NotificationCenter.default.post(name: .hotkeyRegistrationModeDidChange, object: nil)
                return
            }
        }

        for (action, combo) in combos {
            registerFallbackHotkey(action: action, combo: combo)
        }
        registrationMode = .fallbackHotKey
        NotificationCenter.default.post(name: .hotkeyRegistrationModeDidChange, object: nil)
    }

    func combo(for action: HotkeyAction) -> KeyCombo {
        for key in storageKeys(for: action) {
            if let dictionary = userDefaults.dictionary(forKey: key),
               let combo = KeyCombo(dictionary: dictionary) {
                return combo
            }
        }
        return action.defaultCombo
    }

    func setCombo(_ newCombo: KeyCombo?, for action: HotkeyAction) {
        let key = storageKeys(for: action).first!
        if let newCombo {
            userDefaults.set(newCombo.dictionary, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
        for legacyKey in storageKeys(for: action).dropFirst() {
            userDefaults.removeObject(forKey: legacyKey)
        }
        registerConfiguredHotkeys()
        NotificationCenter.default.post(name: .hotkeysDidChange, object: nil)
    }

    func displayString(for action: HotkeyAction) -> String {
        combo(for: action).description
    }

    func pauseAll() {
        eventTapMonitor.stop()
        for hotkey in hotkeys.values {
            hotkey.isPaused = true
        }
    }

    func resumeAll() {
        registerConfiguredHotkeys()
    }

    func unregisterAll() {
        eventTapMonitor.stop()
        unregisterFallbackHotkeys()
    }

    func refreshRegistrationMode() {
        registerConfiguredHotkeys()
    }

    private func unregisterFallbackHotkeys() {
        hotkeys.removeAll()
    }

    private func registerFallbackHotkey(action: HotkeyAction, combo: KeyCombo) {
        hotkeys.removeValue(forKey: action)
        let hotkey = HotKey(keyCombo: combo)
        hotkey.keyDownHandler = {
            action.perform()
        }
        hotkeys[action] = hotkey
    }

    private func storageKeys(for action: HotkeyAction) -> [String] {
        if action == .ocr {
            return [storagePrefix + action.rawValue, storagePrefix + "ruler"]
        }
        return [storagePrefix + action.rawValue]
    }
}
