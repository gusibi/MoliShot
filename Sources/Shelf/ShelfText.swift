import Foundation

/// Kept with the feature so its copy follows the app's selected language.
enum ShelfText {
    static func text(_ zh: String, _ en: String) -> String { L10n.isChinese ? zh : en }
    static var title: String { text("截图暂存栏", "Screenshot Shelf") }
    static var add: String { text("加入暂存", "Add to Shelf") }
    static var capture: String { text("继续截图", "Capture Next") }
    static var copy: String { text("复制全部", "Copy All") }
    static var copyFiles: String { text("复制图片文件", "Copy Image Files") }
    static var copyImages: String { text("复制为多张图片", "Copy as Separate Images") }
    static var clear: String { text("清空暂存", "Clear Shelf") }
    static var merge: String { text("合成长图后复制", "Copy as One Image") }
    static var drag: String { text("拖出全部", "Drag All") }
    static var hint: String { text("拖动排序 · 空格预览", "Drag to reorder · Space to preview") }
    static var ready: String { text("继续收集，准备好后一次分享。", "Collect a few. Share them together.") }
    static var empty: String { text("下一组想法，从一张截图开始。", "Your next idea starts with a screenshot.") }
    static var emptyHint: String { text("截图并标注后，点击「加入暂存」。", "Capture, annotate, then choose Add to Shelf.") }
    static var remove: String { text("移出暂存", "Remove from Shelf") }
    static var earlier: String { text("向前移动", "Move Earlier") }
    static var later: String { text("向后移动", "Move Later") }
    static var collapse: String { text("收起", "Collapse") }
    static var expand: String { text("展开", "Expand") }
    static var preview: String { text("快速查看", "Quick Look") }
    static var failure: String { text("操作未完成，图片仍保留在暂存栏。", "Couldn’t finish. Your screenshots are still on the shelf.") }
    static func count(_ count: Int) -> String {
        L10n.isChinese ? "\(count) 张截图" : "\(count) screenshot\(count == 1 ? "" : "s")"
    }
    static func copied(_ count: Int, format: ShelfExport) -> String {
        switch format {
        case .files:
            return text("已复制 \(count) 个图片文件", "Copied \(count) image files")
        case .images:
            return text("已写入 \(count) 张图片 · 接收应用可能只读取一张", "Wrote \(count) images · Some apps paste only one")
        case .merged:
            return text("已将 \(count) 张截图合成为一张长图", "Combined \(count) screenshots into one image")
        }
    }
}
