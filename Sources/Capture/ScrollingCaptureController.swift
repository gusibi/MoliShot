import AppKit
import ScreenCaptureKit
import Vision
import CoreGraphics

/// Simplified scrolling screenshot:
/// 1. User picks a rect on a display.
/// 2. A floating toolbar appears. User scrolls the underlying content manually.
/// 3. We capture the rect at ~6 fps and use VNTranslationalImageRegistrationRequest
///    to find the vertical offset between consecutive frames.
/// 4. Newly-revealed rows are appended to the stitched image.
/// 5. User clicks Done to finish.
final class ScrollingCaptureController {
    private enum FailureReason {
        case startFailed
        case captureFailed(String)
        case noScrollDetected
        case unstableOverlap
    }

    private let completion: (NSImage?) -> Void
    private var regionController: RegionSelectionController?
    private var toolbar: ScrollingToolbar?
    private var timer: Timer?

    private var display: SCDisplay?
    private var sourceRect: CGRect = .zero
    private var previousFrame: CGImage?
    private var stitched: CGImage?
    private var stitchedScale = CGSize(width: 1, height: 1)
    private var isCapturing = false
    private var isCaptureStepRunning = false
    private var appendedStripCount = 0
    private var consecutiveCaptureFailures = 0
    private var sawUnstableOverlap = false

    init(completion: @escaping (NSImage?) -> Void) {
        self.completion = completion
    }

    func begin() {
        // Reuse region picker — area mode only.
        regionController = RegionSelectionController(allowsWindowSelectionInAreaMode: false) { [weak self] result in
            self?.regionController = nil
            guard let result else {
                self?.completion(nil); return
            }
            guard case .area(let area) = result else {
                self?.completion(nil); return
            }
            self?.promptScrollFlow(firstCapture: area)
        }
        regionController?.begin(mode: .area)
    }

    /// After the region picker hands back a baseline image we show the floating
    /// toolbar and start capturing the same rect on a timer.
    private func promptScrollFlow(firstCapture: AreaCaptureResult) {
        guard let firstFrame = firstCapture.image.cgImageRef else {
            fail(.startFailed)
            return
        }
        display = firstCapture.display
        sourceRect = firstCapture.sourceRect
        stitched = firstFrame
        previousFrame = firstFrame
        appendedStripCount = 0
        consecutiveCaptureFailures = 0
        sawUnstableOverlap = false
        if firstCapture.image.size.width > 0, firstCapture.image.size.height > 0 {
            stitchedScale = CGSize(
                width: CGFloat(firstFrame.width) / firstCapture.image.size.width,
                height: CGFloat(firstFrame.height) / firstCapture.image.size.height
            )
        } else {
            stitchedScale = CGSize(width: 1, height: 1)
        }
        showToolbar(near: firstCapture.screenRect)
        start()
    }

    private func showToolbar(near rect: NSRect) {
        let tb = ScrollingToolbar()
        tb.onDone = { [weak self] in self?.finish() }
        tb.onCancel = { [weak self] in self?.cancel() }
        tb.show(near: rect)
        toolbar = tb
    }

    private func start() {
        guard !isCapturing else { return }
        isCapturing = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.captureStep()
        }
    }

    private func captureStep() {
        guard let display = display, !isCaptureStepRunning else { return }
        let rect = sourceRect
        isCaptureStepRunning = true
        Task { @MainActor [weak self, display, rect] in
            defer { self?.isCaptureStepRunning = false }
            do {
                let image = try await ScreenCaptureService.shared.captureRectUsingSourceRect(rect, onDisplay: display)
                guard let cg = image.cgImageRef else {
                    self?.handleCaptureFailure(message: L10n.text(.scrollCaptureFrameUnavailable))
                    return
                }
                guard let self, self.isCapturing else {
                    return
                }
                self.merge(newFrame: cg)
            } catch {
                NSLog("scrolling capture step failed: \(error)")
                self?.handleCaptureFailure(message: error.localizedDescription)
            }
        }
    }

    private func merge(newFrame: CGImage) {
        guard let stitched = stitched, let previous = previousFrame else { return }

        guard
            let previousROI = registrationROI(for: previous),
            let newROI = registrationROI(for: newFrame)
        else {
            sawUnstableOverlap = true
            previousFrame = newFrame
            return
        }

        let handler = VNImageRequestHandler(cgImage: previousROI, options: [:])
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: newROI, options: [:])
        do {
            try handler.perform([request])
        } catch {
            sawUnstableOverlap = true
            previousFrame = newFrame
            return
        }
        guard let obs = request.results?.first as? VNImageTranslationAlignmentObservation else {
            sawUnstableOverlap = true
            previousFrame = newFrame
            return
        }
        let dy = -obs.alignmentTransform.ty  // a positive dy means content scrolled up, so new rows are at the bottom
        let minimumUsableShift: CGFloat = 6
        let maxExpectedShift = CGFloat(newFrame.height) * 0.85
        guard dy >= minimumUsableShift else {
            return
        }
        guard dy < maxExpectedShift else {
            sawUnstableOverlap = true
            previousFrame = newFrame
            return
        }

        let newRowPixels = min(Int(dy.rounded()), newFrame.height)
        guard newRowPixels > 0 else { return }

        // Extract the bottom `newRowPixels` rows from newFrame.
        let bottomRect = CGRect(x: 0, y: newFrame.height - newRowPixels, width: newFrame.width, height: newRowPixels)
        guard let bottomStrip = newFrame.cropping(to: bottomRect) else {
            sawUnstableOverlap = true
            previousFrame = newFrame
            return
        }

        self.stitched = append(strip: bottomStrip, below: stitched)
        previousFrame = newFrame
        consecutiveCaptureFailures = 0
        appendedStripCount += 1
        toolbar?.updateProgress(height: self.stitched?.height ?? 0)
    }

    private func registrationROI(for image: CGImage) -> CGImage? {
        let insetRatio: CGFloat = 0.12
        let topInset = Int(CGFloat(image.height) * insetRatio)
        let bottomInset = Int(CGFloat(image.height) * insetRatio)
        let croppedHeight = image.height - topInset - bottomInset
        guard croppedHeight > max(20, image.height / 3) else {
            return image
        }
        let roi = CGRect(x: 0, y: bottomInset, width: image.width, height: croppedHeight)
        return image.cropping(to: roi)
    }

    private func append(strip: CGImage, below base: CGImage) -> CGImage? {
        let width = base.width
        let totalHeight = base.height + strip.height
        // 使用标准 sRGB 色彩空间，与系统截图保持一致
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: info) else {
            return nil
        }
        ctx.draw(base, in: CGRect(x: 0, y: strip.height, width: width, height: base.height))
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: strip.height))
        return ctx.makeImage()
    }

    private func finish() {
        guard appendedStripCount > 0 else {
            fail(sawUnstableOverlap ? .unstableOverlap : .noScrollDetected)
            return
        }
        guard let cg = stitched else {
            fail(.captureFailed(L10n.text(.scrollCaptureFrameUnavailable)))
            return
        }
        let outputScale = stitchedScale
        let size = NSSize(
            width: CGFloat(cg.width) / max(outputScale.width, 1),
            height: CGFloat(cg.height) / max(outputScale.height, 1)
        )
        cleanup()
        completion(NSImage(cgImage: cg, size: size))
    }

    private func cancel() {
        cleanup()
        completion(nil)
    }

    private func handleCaptureFailure(message: String) {
        consecutiveCaptureFailures += 1
        if consecutiveCaptureFailures >= 3 {
            fail(.captureFailed(message))
        }
    }

    private func fail(_ reason: FailureReason) {
        let title = L10n.text(.scrollCaptureFailedTitle)
        let message: String
        switch reason {
        case .startFailed:
            message = L10n.text(.scrollCaptureStartFailed)
        case .captureFailed(let detail):
            message = L10n.text(.scrollCaptureFailedMessage, detail)
        case .noScrollDetected:
            message = L10n.text(.scrollCaptureNoScrollDetected)
        case .unstableOverlap:
            message = L10n.text(.scrollCaptureUnstableOverlap)
        }
        cleanup()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completion(nil)
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        isCapturing = false
        isCaptureStepRunning = false
        display = nil
        sourceRect = .zero
        previousFrame = nil
        stitched = nil
        stitchedScale = CGSize(width: 1, height: 1)
        appendedStripCount = 0
        consecutiveCaptureFailures = 0
        sawUnstableOverlap = false
        toolbar?.close()
        toolbar = nil
    }
}

final class ScrollingToolbar {
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private var window: NSWindow?
    private let label = NSTextField(labelWithString: L10n.text(.scrollInstruction))

    func show(near rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let size = NSSize(width: 420, height: 56)
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - 80)
        let win = NSWindow(contentRect: NSRect(origin: origin, size: size),
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear

        let container = MoliCardView(
            frame: NSRect(origin: .zero, size: size),
            fillColor: MoliDesign.card,
            borderColor: MoliDesign.hairline,
            cornerRadius: 10
        )

        label.frame = NSRect(x: 12, y: 18, width: 260, height: 20)
        label.textColor = MoliDesign.primaryText
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)

        let done = NSButton(title: L10n.text(.done), target: self, action: #selector(doneTap))
        done.frame = NSRect(x: 280, y: 14, width: 60, height: 28)
        configureToolbarButton(done, emphasized: true)
        container.addSubview(done)

        let cancel = NSButton(title: L10n.text(.cancel), target: self, action: #selector(cancelTap))
        cancel.frame = NSRect(x: 346, y: 14, width: 66, height: 28)
        configureToolbarButton(cancel, emphasized: false)
        container.addSubview(cancel)

        win.contentView = container
        win.makeKeyAndOrderFront(nil)
        self.window = win

        // Retain self via window controller alternative: associated object
        objc_setAssociatedObject(win, &toolbarKey, self, .OBJC_ASSOCIATION_RETAIN)
    }

    func updateProgress(height: Int) {
        label.stringValue = L10n.text(.capturedScrollProgress, "\(height)")
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    private func configureToolbarButton(_ button: NSButton, emphasized: Bool) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = (emphasized ? MoliDesign.cardElevated : .clear).cgColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: emphasized ? MoliDesign.primaryText : MoliDesign.secondaryText,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        button.setAccessibilityLabel(button.title)
    }

    @objc private func doneTap() { onDone?() }
    @objc private func cancelTap() { onCancel?() }
}

private var toolbarKey: UInt8 = 0
