import AppKit

final class OCRWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: (OCRWindowController) -> Void

    init(text: String, onClose: @escaping (OCRWindowController) -> Void) {
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.ocrResult)
        window.center()

        super.init(window: window)

        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        textView.string = text.isEmpty ? L10n.text(.noTextDetected) : text
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isEditable = true
        textView.autoresizingMask = [.width, .height]

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        window.contentView = scrollView
        window.delegate = self

        if !text.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
