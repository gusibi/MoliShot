import AppKit
import CoreGraphics

extension NSImage {
    var cgImageRef: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        // 添加高分辨率提示，确保获取最佳质量的CGImage
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        let hints: [NSImageRep.HintKey: Any] = [
            .ctm: transform,
            .interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)
        ]
        return cgImage(forProposedRect: &rect, context: nil, hints: hints)
    }

    var pixelSize: NSSize? {
        guard let cg = cgImageRef else { return nil }
        return NSSize(width: cg.width, height: cg.height)
    }

    convenience init(cgImage: CGImage) {
        // 自动检测屏幕缩放因子，创建正确尺寸的NSImage
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        self.init(cgImage: cgImage, size: size)
    }

    func pngData() -> Data? {
        guard let cg = cgImageRef else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        // 设置正确的尺寸，保持Retina分辨率
        rep.size = size
        // 使用最高质量的PNG压缩，0.0 = 无压缩（质量最高）
        return rep.representation(using: .png, properties: [.compressionFactor: 0.0])
    }

    func cropped(to rect: NSRect) -> NSImage? {
        guard let cg = cgImageRef else { return nil }
        let scale = CGFloat(cg.width) / size.width
        let scaled = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
        guard let cropped = cg.cropping(to: scaled) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}

extension NSPasteboard {
    func writeImage(_ image: NSImage) {
        clearContents()
        if let tiffData = image.tiffRepresentation {
            setData(tiffData, forType: .tiff)
        }
        if let pngData = image.pngData() {
            setData(pngData, forType: .png)
        }
        writeObjects([image])
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "RGB 0, 0, 0" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return "RGB \(r), \(g), \(b)"
    }
}

extension CGRect {
    func flipped(in container: CGRect) -> CGRect {
        CGRect(x: origin.x, y: container.height - origin.y - height, width: width, height: height)
    }
}

extension Collection where Element == NSScreen {
    var desktopBounds: CGRect {
        reduce(into: CGRect.null) { partialResult, screen in
            partialResult = partialResult.union(screen.frame)
        }
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("AppLanguageDidChangeNotification")
}

enum AppLanguage: String, CaseIterable {
    case system
    case english
    case simplifiedChinese

    var displayName: String {
        switch self {
        case .system: return L10n.text(.languageSystem)
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

enum L10nKey {
    case languageSystem
    case captureArea
    case captureFullScreen
    case scrollingScreenshot
    case colorPicker
    case ruler
    case screenColorPicker
    case onScreenRuler
    case history
    case preferences
    case about
    case quit
    case editor
    case select
    case arrow
    case rectangle
    case ellipse
    case line
    case pen
    case text
    case number
    case blur
    case pixelate
    case highlight
    case crop
    case undo
    case clear
    case fit
    case ocr
    case pin
    case copy
    case save
    case upload
    case copiedToClipboard
    case saved
    case saveFailed
    case uploaded
    case uploadFailed
    case annotations
    case hotkeys
    case screenRecordingPermission
    case accessibilityPermission
    case accessibilityPermissionHint
    case openAccessibilitySettings
    case requestAccessibilityPermission
    case hotkeyRegistrationMode
    case hotkeyRegistrationModeEventTap
    case hotkeyRegistrationModeFallback
    case accessibilityCaptureNoticeTitle
    case accessibilityCaptureNoticeMessage
    case continueWithoutAccessibility
    case granted
    case notGranted
    case openScreenRecordingSettings
    case showInFinder
    case saveDirectory
    case choose
    case open
    case resetToDesktop
    case general
    case storage
    case autoStart
    case language
    case launchAtLogin
    case launchAtLoginFailed
    case historyRetention
    case keepRecentScreenshots
    case pressShortcut
    case recordShortcut
    case noScreenshotsYet
    case delete
    case ocrResult
    case noTextDetected
    case ocrInProgress
    case ocrFailed
    case ocrCopiedToClipboard
    case ocrImageUnavailable
    case uploadInProgress
    case cropApplied
    case editingCancelled
    case selectionCancelled
    case undoApplied
    case nothingToUndo
    case clearedAnnotations
    case pinCreated
    case scrollInstruction
    case scrollCaptureFailedTitle
    case scrollCaptureStartFailed
    case scrollCaptureNoScrollDetected
    case scrollCaptureUnstableOverlap
    case scrollCaptureFailedMessage
    case scrollCaptureFrameUnavailable
    case done
    case cancel
    case close
    case capturedScrollProgress
    case rulerHint
}

enum L10n {
    private static let languageKey = "app.language"

    static var selectedLanguage: AppLanguage {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: languageKey),
                let language = AppLanguage(rawValue: raw)
            else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    static var isChinese: Bool {
        switch selectedLanguage {
        case .simplifiedChinese:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
    }

    static func text(_ key: L10nKey) -> String {
        isChinese ? zh(key) : en(key)
    }

    static func text(_ key: L10nKey, _ value: String) -> String {
        switch key {
        case .saved:
            return isChinese ? "已保存：\(value)" : "Saved: \(value)"
        case .saveFailed:
            return isChinese ? "保存失败：\(value)" : "Save failed: \(value)"
        case .uploaded:
            return isChinese ? "已上传：\(value)" : "Uploaded: \(value)"
        case .uploadFailed:
            return isChinese ? "上传失败：\(value)" : "Upload failed: \(value)"
        case .capturedScrollProgress:
            return isChinese ? "已捕获 \(value) px。滚动后点完成。" : "Captured \(value) px. Scroll + Done."
        case .scrollCaptureFailedMessage:
            return isChinese ? "滚动截图已停止：\(value)" : "Scrolling capture stopped: \(value)"
        default:
            return text(key)
        }
    }

    private static func en(_ key: L10nKey) -> String {
        switch key {
        case .languageSystem: return "System"
        case .captureArea: return "Capture Area"
        case .captureFullScreen: return "Capture Current Display"
        case .scrollingScreenshot: return "Scrolling Screenshot"
        case .colorPicker: return "Color Picker"
        case .ruler: return "Ruler"
        case .screenColorPicker: return "Screen Color Picker"
        case .onScreenRuler: return "On-screen Ruler"
        case .history: return "History"
        case .preferences: return "Preferences"
        case .about: return "About MoliShot"
        case .quit: return "Quit"
        case .editor: return "Editor"
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .pen: return "Pen"
        case .text: return "Text"
        case .number: return "Number"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .highlight: return "Highlight"
        case .crop: return "Crop"
        case .undo: return "Undo"
        case .clear: return "Clear"
        case .fit: return "Fit"
        case .ocr: return "OCR"
        case .pin: return "Pin"
        case .copy: return "Copy"
        case .save: return "Save..."
        case .upload: return "Upload"
        case .copiedToClipboard: return "Copied to clipboard"
        case .saved: return "Saved"
        case .saveFailed: return "Save failed"
        case .uploaded: return "Uploaded"
        case .uploadFailed: return "Upload failed"
        case .annotations: return "annotations"
        case .hotkeys: return "Hotkeys"
        case .screenRecordingPermission: return "Screen Recording Permission"
        case .accessibilityPermission: return "Accessibility Permission"
        case .accessibilityPermissionHint: return "Needed to keep menus and popovers open while starting a capture."
        case .openAccessibilitySettings: return "Open Accessibility Settings"
        case .requestAccessibilityPermission: return "Request Access"
        case .hotkeyRegistrationMode: return "Hotkey Capture Mode"
        case .hotkeyRegistrationModeEventTap: return "Keep-open mode active"
        case .hotkeyRegistrationModeFallback: return "Fallback mode"
        case .accessibilityCaptureNoticeTitle: return "Accessibility Access Improves Capture Start"
        case .accessibilityCaptureNoticeMessage: return "Grant Accessibility access if you want screenshot hotkeys to open the overlay without closing menus or popovers first. You can continue without it, but that behavior becomes best effort only."
        case .continueWithoutAccessibility: return "Continue Without Access"
        case .granted: return "Granted"
        case .notGranted: return "Not granted"
        case .openScreenRecordingSettings: return "Open Screen Recording Settings"
        case .showInFinder: return "Show in Finder"
        case .saveDirectory: return "Save Directory"
        case .choose: return "Choose..."
        case .open: return "Open"
        case .resetToDesktop: return "Reset to Desktop"
        case .general: return "General"
        case .storage: return "Storage"
        case .autoStart: return "Autostart"
        case .language: return "Language"
        case .launchAtLogin: return "Launch at Login"
        case .launchAtLoginFailed: return "Could not update Launch at Login"
        case .historyRetention: return "History Retention"
        case .keepRecentScreenshots: return "Keep recent screenshots"
        case .pressShortcut: return "Press shortcut"
        case .recordShortcut: return "Record shortcut"
        case .noScreenshotsYet: return "No screenshots yet."
        case .delete: return "Delete"
        case .ocrResult: return "OCR Result"
        case .noTextDetected: return "(no text detected)"
        case .ocrInProgress: return "Recognizing text..."
        case .ocrFailed: return "OCR failed"
        case .ocrCopiedToClipboard: return "Recognized text copied to clipboard"
        case .ocrImageUnavailable: return "Could not read the captured image."
        case .uploadInProgress: return "Uploading image..."
        case .cropApplied: return "Crop applied"
        case .editingCancelled: return "Text editing cancelled"
        case .selectionCancelled: return "Selection cancelled"
        case .undoApplied: return "Undo applied"
        case .nothingToUndo: return "Nothing to undo"
        case .clearedAnnotations: return "Annotations cleared"
        case .pinCreated: return "Pinned image created"
        case .scrollInstruction: return "Scroll the content manually, then click Done."
        case .scrollCaptureFailedTitle: return "Scrolling Capture Failed"
        case .scrollCaptureStartFailed: return "Could not capture the initial frame for scrolling capture."
        case .scrollCaptureNoScrollDetected: return "No usable scroll movement was detected. Scroll the content, then click Done."
        case .scrollCaptureUnstableOverlap: return "Frames did not overlap reliably enough to stitch. Try slower, steadier scrolling."
        case .scrollCaptureFailedMessage: return "Scrolling capture stopped."
        case .scrollCaptureFrameUnavailable: return "A captured frame could not be read."
        case .done: return "Done"
        case .cancel: return "Cancel"
        case .close: return "Close"
        case .capturedScrollProgress: return "Captured"
        case .rulerHint: return "Drag to measure. Click again to restart. ESC exits."
        }
    }

    private static func zh(_ key: L10nKey) -> String {
        switch key {
        case .languageSystem: return "跟随系统"
        case .captureArea: return "区域截图"
        case .captureFullScreen: return "当前显示器截图"
        case .scrollingScreenshot: return "滚动截图"
        case .colorPicker: return "取色器"
        case .ruler: return "标尺"
        case .screenColorPicker: return "屏幕取色器"
        case .onScreenRuler: return "屏幕标尺"
        case .history: return "历史记录"
        case .preferences: return "偏好设置"
        case .about: return "关于 MoliShot"
        case .quit: return "退出"
        case .editor: return "编辑器"
        case .select: return "选择"
        case .arrow: return "箭头"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .line: return "直线"
        case .pen: return "画笔"
        case .text: return "文字"
        case .number: return "序号"
        case .blur: return "模糊"
        case .pixelate: return "马赛克"
        case .highlight: return "高亮"
        case .crop: return "裁剪"
        case .undo: return "撤销"
        case .clear: return "清空"
        case .fit: return "适合窗口"
        case .ocr: return "识别文字"
        case .pin: return "贴图"
        case .copy: return "复制"
        case .save: return "保存..."
        case .upload: return "上传"
        case .copiedToClipboard: return "已复制到剪贴板"
        case .saved: return "已保存"
        case .saveFailed: return "保存失败"
        case .uploaded: return "已上传"
        case .uploadFailed: return "上传失败"
        case .annotations: return "个标注"
        case .hotkeys: return "快捷键"
        case .screenRecordingPermission: return "屏幕录制权限"
        case .accessibilityPermission: return "辅助功能权限"
        case .accessibilityPermissionHint: return "用于在截图热键触发时尽量保持菜单和弹窗不被提前关闭。"
        case .openAccessibilitySettings: return "打开辅助功能设置"
        case .requestAccessibilityPermission: return "请求授权"
        case .hotkeyRegistrationMode: return "快捷键捕获模式"
        case .hotkeyRegistrationModeEventTap: return "保持菜单模式已启用"
        case .hotkeyRegistrationModeFallback: return "回退模式"
        case .accessibilityCaptureNoticeTitle: return "辅助功能权限可改善截图启动"
        case .accessibilityCaptureNoticeMessage: return "如果你希望截图热键弹出 Overlay 时尽量不关闭菜单或 Popover，请授予辅助功能权限。没有该权限时仍可截图，但这项行为只能尽力而为。"
        case .continueWithoutAccessibility: return "继续但不授权"
        case .granted: return "已授权"
        case .notGranted: return "未授权"
        case .openScreenRecordingSettings: return "打开屏幕录制设置"
        case .showInFinder: return "在访达中显示"
        case .saveDirectory: return "保存目录"
        case .choose: return "选择..."
        case .open: return "打开"
        case .resetToDesktop: return "重置到桌面"
        case .general: return "通用"
        case .storage: return "存储"
        case .autoStart: return "自动启动"
        case .language: return "语言"
        case .launchAtLogin: return "跟随系统启动"
        case .launchAtLoginFailed: return "无法更新开机启动设置"
        case .historyRetention: return "历史保留数量"
        case .keepRecentScreenshots: return "保留最近截图"
        case .pressShortcut: return "按下快捷键"
        case .recordShortcut: return "录制快捷键"
        case .noScreenshotsYet: return "还没有截图。"
        case .delete: return "删除"
        case .ocrResult: return "文字识别结果"
        case .noTextDetected: return "（未识别到文字）"
        case .ocrInProgress: return "正在识别文字..."
        case .ocrFailed: return "文字识别失败"
        case .ocrCopiedToClipboard: return "识别结果已复制到剪贴板"
        case .ocrImageUnavailable: return "无法读取当前截图。"
        case .uploadInProgress: return "正在上传图片..."
        case .cropApplied: return "已应用裁剪"
        case .editingCancelled: return "已取消文字编辑"
        case .selectionCancelled: return "已取消当前操作"
        case .undoApplied: return "已撤销"
        case .nothingToUndo: return "没有可撤销的内容"
        case .clearedAnnotations: return "已清空标注"
        case .pinCreated: return "已创建贴图窗口"
        case .scrollInstruction: return "手动滚动内容，然后点击完成。"
        case .scrollCaptureFailedTitle: return "滚动截图失败"
        case .scrollCaptureStartFailed: return "无法获取滚动截图的初始画面。"
        case .scrollCaptureNoScrollDetected: return "没有检测到可用的滚动位移。请滚动内容后再点击完成。"
        case .scrollCaptureUnstableOverlap: return "连续帧重叠不稳定，无法可靠拼接。请尝试更慢、更平稳地滚动。"
        case .scrollCaptureFailedMessage: return "滚动截图已停止。"
        case .scrollCaptureFrameUnavailable: return "某一帧截图无法读取。"
        case .done: return "完成"
        case .cancel: return "取消"
        case .close: return "关闭"
        case .capturedScrollProgress: return "已捕获"
        case .rulerHint: return "拖动以测量。再次点击可重新开始。按 ESC 退出。"
        }
    }
}
