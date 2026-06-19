import AppKit
import ScreenCaptureKit
import CoreGraphics

enum ScreenCaptureError: Error {
    case noContent
    case captureFailed
    case noDisplay
    case noWindow
}

/// Thin wrapper around ScreenCaptureKit for one-shot screenshots.
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()
    private init() {}

    func captureDisplayUnderMouse() async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mouseLocation = NSEvent.mouseLocation
        let targetDisplayID = NSScreen.screens
            .first(where: { $0.frame.contains(mouseLocation) })
            .flatMap(ScreenCaptureService.displayID(for:))
            ?? CGMainDisplayID()

        guard let display = content.displays.first(where: { $0.displayID == targetDisplayID }) ?? content.displays.first else {
            throw ScreenCaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let size = screen(for: display.displayID)?.frame.size ?? NSSize(width: display.width, height: display.height)
        let pixelSize = outputPixelSize(for: display, pointSize: size)
        return try await capture(filter: filter, width: pixelSize.width, height: pixelSize.height, imageSize: size)
    }

    func captureDisplay(_ display: SCDisplay, excludingWindows: [SCWindow] = []) async throws -> NSImage {
        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
        let size = screen(for: display.displayID)?.frame.size ?? NSSize(width: display.width, height: display.height)
        let pixelSize = outputPixelSize(for: display, pointSize: size)
        return try await capture(filter: filter, width: pixelSize.width, height: pixelSize.height, imageSize: size)
    }

    func captureRect(_ rect: CGRect, onDisplay display: SCDisplay, excludingWindows: [SCWindow] = []) async throws -> NSImage {
        // 使用sourceRect方式直接截取指定区域，避免全屏裁剪带来的性能和精度损失
        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
        let cfg = SCStreamConfiguration()
        let scale = displayScale(for: display)
        cfg.width = max(1, Int((rect.width * scale.width).rounded()))
        cfg.height = max(1, Int((rect.height * scale.height).rounded()))
        cfg.sourceRect = rect
        configure(cfg)
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return NSImage(cgImage: cg, size: rect.size)
    }

    func captureRectUsingSourceRect(_ rect: CGRect, onDisplay display: SCDisplay, excludingWindows: [SCWindow] = []) async throws -> NSImage {
        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
        let cfg = SCStreamConfiguration()
        let scale = displayScale(for: display)
        cfg.width = max(1, Int((rect.width * scale.width).rounded()))
        cfg.height = max(1, Int((rect.height * scale.height).rounded()))
        cfg.sourceRect = rect
        configure(cfg)
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return NSImage(cgImage: cg, size: rect.size)
    }

    func captureWindow(_ window: SCWindow, onDisplayID displayID: CGDirectDisplayID? = nil) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        let scale: CGSize
        if let displayID, let explicitScale = currentDisplayScale(displayID: displayID) {
            scale = explicitScale
        } else {
            scale = displayScale(containingTopLeftRect: window.frame)
        }
        cfg.width = max(1, Int((window.frame.width * scale.width).rounded()))
        cfg.height = max(1, Int((window.frame.height * scale.height).rounded()))
        configure(cfg)
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return NSImage(cgImage: cg, size: NSSize(width: window.frame.width, height: window.frame.height))
    }

    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private func capture(filter: SCContentFilter, width: Int, height: Int, imageSize: NSSize) async throws -> NSImage {
        let cfg = SCStreamConfiguration()
        cfg.width = max(1, width)
        cfg.height = max(1, height)
        configure(cfg)
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        return NSImage(cgImage: cg, size: imageSize)
    }

    private func captureDisplayImage(filter: SCContentFilter, display: SCDisplay) async throws -> CGImage {
        let size = screen(for: display.displayID)?.frame.size ?? NSSize(width: display.width, height: display.height)
        let pixelSize = outputPixelSize(for: display, pointSize: size)
        let cfg = SCStreamConfiguration()
        cfg.width = pixelSize.width
        cfg.height = pixelSize.height
        configure(cfg)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    private func configure(_ cfg: SCStreamConfiguration) {
        cfg.capturesAudio = false
        cfg.showsCursor = false
        cfg.captureResolution = .best
        cfg.scalesToFit = false
        cfg.preservesAspectRatio = true
    }

    private func pixelRect(for rect: CGRect, scale: CGSize, image: CGImage) -> CGRect {
        let x = floor(rect.minX * scale.width)
        let y = floor(rect.minY * scale.height)
        let maxX = ceil(rect.maxX * scale.width)
        let maxY = ceil(rect.maxY * scale.height)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y).intersection(bounds)
    }

    private func outputPixelSize(for display: SCDisplay, pointSize: NSSize) -> (width: Int, height: Int) {
        let scale = displayScale(for: display)
        return (
            width: max(1, Int((pointSize.width * scale.width).rounded())),
            height: max(1, Int((pointSize.height * scale.height).rounded()))
        )
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ScreenCaptureService.displayID(for: $0) == displayID }
    }

    private func displayScale(for display: SCDisplay) -> CGSize {
        currentDisplayScale(displayID: display.displayID) ?? CGSize(width: 1, height: 1)
    }

    private func displayScale(containingTopLeftRect rect: CGRect) -> CGSize {
        guard
            let screen = screen(containingTopLeftRect: rect),
            let displayID = ScreenCaptureService.displayID(for: screen),
            let contentScale = currentDisplayScale(displayID: displayID)
        else {
            return CGSize(width: 1, height: 1)
        }
        return contentScale
    }

    private func currentDisplayScale(displayID: CGDirectDisplayID) -> CGSize? {
        guard let screen = screen(for: displayID) else { return nil }
        // backingScaleFactor is the correct pixels-per-point ratio for the display.
        // On modern macOS, CGDisplayPixelsWide() returns the *scaled logical* pixel
        // count (not physical pixels), so dividing it by screen.frame.width always
        // yields 1.0 — which produced 1× (blurry) captures on Retina displays.
        let s = screen.backingScaleFactor
        return CGSize(width: s, height: s)
    }

    private func screen(containingTopLeftRect rect: CGRect) -> NSScreen? {
        let desktopBounds = NSScreen.screens.desktopBounds
        let appKitRect = CGRect(
            x: rect.origin.x,
            y: desktopBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let center = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
