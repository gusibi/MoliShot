import AppKit

/// A capture hides only currently visible windows and restores their stacking order,
/// without activating the app or reopening a window that was already hidden.
final class CaptureWindowVisibility {
    private var windows: [NSWindow] = []

    func hide(_ candidates: [NSWindow]) {
        windows = NSApp.orderedWindows.filter { window in
            window.isVisible && candidates.contains(where: { $0 === window })
        }
        windows.forEach { $0.orderOut(nil) }
    }

    func restore() {
        windows.reversed().forEach { $0.orderFrontRegardless() }
        windows.removeAll()
    }
}
