import AppKit

final class AppCoordinator {
    static let shared = AppCoordinator()

    private var regionController: RegionSelectionController?
    private var scrollingController: ScrollingCaptureController?
    private var colorPickerController: ColorPickerController?
    private var historyController: HistoryWindowController?
    private var preferencesController: PreferencesWindowController?
    private var editors: [EditorWindowController] = []
    private var pins: [PinWindowController] = []
    private var ocrWindows: [OCRWindowController] = []
    private var hasShownAccessibilityCaptureNotice = false

    private init() {}

    func captureArea() {
        ensureAccessibilityAwareCaptureStart()
        guard regionController == nil else { return }
        regionController = RegionSelectionController { [weak self] result in
            self?.regionController = nil
            guard let result else { return }
            let image: NSImage
            switch result {
            case .area(let area):
                image = area.image
            case .window(let captured, _):
                image = captured
            }
            self?.handleCapturedImage(image)
        }
        regionController?.begin(mode: .area)
    }

    func captureFullScreen() {
        ensureAccessibilityAwareCaptureStart()
        Task { @MainActor in
            do {
                let image = try await ScreenCaptureService.shared.captureDisplayUnderMouse()
                handleCapturedImage(image)
            } catch {
                NSLog("Capture full screen failed: \(error)")
                presentAlert(title: L10n.text(.captureFullScreen), message: error.localizedDescription)
            }
        }
    }

    func captureScrolling() {
        ensureAccessibilityAwareCaptureStart()
        guard scrollingController == nil else { return }
        scrollingController = ScrollingCaptureController { [weak self] image in
            self?.scrollingController = nil
            guard let image = image else { return }
            self?.handleCapturedImage(image)
        }
        scrollingController?.begin()
    }

    func handleCapturedImage(_ image: NSImage) {
        HistoryStore.shared.store(image: image)
        openEditor(with: image)
    }

    func openEditor(with image: NSImage) {
        let controller = EditorWindowController(image: image) { [weak self] editor in
            self?.editors.removeAll { $0 === editor }
        }
        editors.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    func pinImage(_ image: NSImage, at origin: NSPoint? = nil) {
        let pin = PinWindowController(image: image, origin: origin) { [weak self] p in
            self?.pins.removeAll { $0 === p }
        }
        pins.append(pin)
        pin.showWindow(nil)
    }

    func openColorPicker() {
        guard colorPickerController == nil else { return }
        colorPickerController = ColorPickerController { [weak self] in
            self?.colorPickerController = nil
        }
        colorPickerController?.begin()
    }

    func runScreenOCR() {
        ensureAccessibilityAwareCaptureStart()
        guard regionController == nil else { return }
        regionController = RegionSelectionController { [weak self] result in
            self?.regionController = nil
            guard let result else { return }

            let image: NSImage
            switch result {
            case .area(let area):
                image = area.image
            case .window(let captured, _):
                image = captured
            }

            OCRService.shared.recognize(in: image) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        self?.showOCRResult(text)
                    case .failure(let error):
                        self?.presentAlert(title: L10n.text(.ocr), message: error.localizedDescription)
                    }
                }
            }
        }
        regionController?.begin(mode: .area)
    }

    func openHistory() {
        if historyController == nil {
            historyController = HistoryWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        historyController?.showWindow(nil)
    }

    func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesController?.showWindow(nil)
    }

    func showOCRResult(_ text: String) {
        let controller = OCRWindowController(text: text) { [weak self] window in
            self?.ocrWindows.removeAll { $0 === window }
        }
        ocrWindows.append(controller)
        controller.showWindow(nil)
    }

    func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func ensureAccessibilityAwareCaptureStart() {
        guard !Permissions.hasAccessibilityPermission, !hasShownAccessibilityCaptureNotice else { return }
        hasShownAccessibilityCaptureNotice = true

        let alert = NSAlert()
        alert.messageText = L10n.text(.accessibilityCaptureNoticeTitle)
        alert.informativeText = L10n.text(.accessibilityCaptureNoticeMessage)
        alert.addButton(withTitle: L10n.text(.openAccessibilitySettings))
        alert.addButton(withTitle: L10n.text(.continueWithoutAccessibility))

        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openAccessibilityPrivacySettings()
        }
    }
}
