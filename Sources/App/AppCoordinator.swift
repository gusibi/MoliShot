import AppKit

final class AppCoordinator {
    static let shared = AppCoordinator()

    private var regionController: RegionSelectionController?
    private var scrollingController: ScrollingCaptureController?
    private var colorPickerController: ColorPickerController?
    private var historyController: HistoryWindowController?
    private var preferencesController: PreferencesWindowController?
    private var editors: [EditorWindowController] = []
    private var shelfController: ScreenshotShelfWindowController?
    private let captureVisibility = CaptureWindowVisibility()
    private var captureInProgress = false
    private var pins: [PinWindowController] = []
    private var ocrWindows: [OCRWindowController] = []
    /// Set when a capture starts without accessibility permission and the
    /// one-time notice hasn't been acknowledged yet. Surfaced as a toast in
    /// the editor AFTER capture (never as a pre-capture modal, which would
    /// activate MoliShot and dismiss the front app's open menus).
    private var pendingAccessibilityNotice = false
    private static let accessibilityNoticeKey = "accessibilityNoticeAcknowledged"

    private var hasAcknowledgedAccessibilityNotice: Bool {
        UserDefaults.standard.bool(forKey: Self.accessibilityNoticeKey)
    }

    /// Editors hold annotations in memory; never restart an update over them.
    var hasWorkToFinishBeforeUpdate: Bool {
        captureInProgress || colorPickerController != nil || !editors.isEmpty || !ocrWindows.isEmpty || !pins.isEmpty
    }

    private init() {}

    func captureArea() {
        guard beginCapture() else { return }
        ensureAccessibilityAwareCaptureStart()
        guard regionController == nil else { return }
        regionController = RegionSelectionController { [weak self] result in
            self?.regionController = nil
            self?.endCapture()
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
        guard beginCapture() else { return }
        ensureAccessibilityAwareCaptureStart()
        Task { @MainActor in
            do {
                let image = try await ScreenCaptureService.shared.captureDisplayUnderMouse()
                endCapture()
                handleCapturedImage(image)
            } catch {
                endCapture()
                NSLog("Capture full screen failed: \(error)")
                presentAlert(title: L10n.text(.captureFullScreen), message: error.localizedDescription)
            }
        }
    }

    func captureScrolling() {
        guard beginCapture() else { return }
        ensureAccessibilityAwareCaptureStart()
        guard scrollingController == nil else { return }
        scrollingController = ScrollingCaptureController { [weak self] image in
            self?.scrollingController = nil
            self?.endCapture()
            guard let image = image else { return }
            self?.handleCapturedImage(image)
        }
        scrollingController?.begin()
    }

    func handleCapturedImage(_ image: NSImage) {
        HistoryStore.shared.store(image: image)
        let editor = openEditor(with: image)
        if pendingAccessibilityNotice {
            pendingAccessibilityNotice = false
            UserDefaults.standard.set(true, forKey: Self.accessibilityNoticeKey)
            editor.showNotice(L10n.text(.accessibilityCaptureNoticeMessage))
        }
    }

    @discardableResult
    func openEditor(with image: NSImage, title: String? = nil) -> EditorWindowController {
        let controller = EditorWindowController(image: image, title: title ?? Self.screenshotTitle(), onClose: { [weak self] editor in
            self?.editors.removeAll { $0 === editor }
        })
        editors.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        return controller
    }

    /// Document-style window title ("Screenshot 9 Sep 2026 at 00:47:12").
    /// Real titles feed the Window menu, tabbing, and VoiceOver; the editor
    /// keeps them visually hidden behind the glass toolbar.
    static func screenshotTitle(for date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return "Screenshot \(df.string(from: date))"
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
        guard beginCapture() else { return }
        ensureAccessibilityAwareCaptureStart()
        guard regionController == nil else { return }
        regionController = RegionSelectionController { [weak self] result in
            self?.regionController = nil
            self?.endCapture()
            guard let result else { return }

            let image: NSImage
            switch result {
            case .area(let area):
                image = area.image
            case .window(let captured, _):
                image = captured
            }

            self?.recognizeText(in: image)
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

    func addToShelf(_ image: NSImage) throws {
        try ScreenshotShelfStore.shared.append(image: image)
        openShelf()
    }

    func openShelf() {
        guard !captureInProgress else { return }
        if shelfController == nil {
            ScreenshotShelfStore.shared.pruneUnreferencedFiles()
            shelfController = ScreenshotShelfWindowController { [weak self] in self?.captureArea() }
        }
        shelfController?.present()
    }

    private func beginCapture() -> Bool {
        guard !captureInProgress else { return false }
        captureInProgress = true
        let candidates = editors.compactMap(\.window) + [shelfController?.window, shelfController?.previewWindow].compactMap { $0 }
        captureVisibility.hide(candidates)
        return true
    }

    private func endCapture() {
        captureVisibility.restore()
        captureInProgress = false
    }

    func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesController?.showWindow(nil)
    }

    func recognizeText(in image: NSImage) {
        let controller = OCRWindowController { [weak self] window in
            self?.ocrWindows.removeAll { $0 === window }
        }
        ocrWindows.append(controller)
        controller.showWindow(nil)
        OCRService.shared.recognize(in: image) { [weak controller] result in
            DispatchQueue.main.async {
                controller?.completeRecognition(result)
            }
        }
    }

    func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func ensureAccessibilityAwareCaptureStart() {
        // Intentionally non-modal: a runModal alert here would activate
        // MoliShot, deactivate the front app, and dismiss its open menus.
        // The notice is deferred to a post-capture editor toast instead.
        guard !Permissions.hasAccessibilityPermission, !hasAcknowledgedAccessibilityNotice else { return }
        pendingAccessibilityNotice = true
    }
}
