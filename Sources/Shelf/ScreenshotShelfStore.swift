import AppKit
import ImageIO

struct ShelfEntry: Codable, Equatable {
    let id: UUID
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ShelfExport {
    case images, files, merged
}

enum ShelfError: LocalizedError {
    case unreadableImage, empty, tooLarge, clipboard

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return ShelfText.text("无法读取图片。", "The image couldn’t be read.")
        case .empty: return ShelfText.emptyHint
        case .tooLarge: return ShelfText.text("图片过大，无法合成长图。请复制多张图片或图片文件。", "Too large to combine. Copy the separate images or image files instead.")
        case .clipboard: return ShelfText.text("无法写入剪贴板，请重试。", "Couldn’t write to the clipboard. Try again.")
        }
    }
}

/// The shelf owns rendered PNGs, independent of raw capture history and its retention limit.
final class ScreenshotShelfStore {
    static let shared = ScreenshotShelfStore()
    static let didChange = Notification.Name("ScreenshotShelfDidChange")
    let directory: URL
    private(set) var entries: [ShelfEntry] = []
    private let indexURL: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MoliShot/Shelf", isDirectory: true)) {
        self.directory = directory
        indexURL = directory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([ShelfEntry].self, from: data) {
            entries = saved.filter {
                $0.filename == URL(fileURLWithPath: $0.filename).lastPathComponent &&
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.filename).path)
            }
        }
    }

    func url(for entry: ShelfEntry) -> URL { directory.appendingPathComponent(entry.filename) }

    @discardableResult
    func append(image: NSImage) throws -> ShelfEntry {
        guard let cg = image.cgImageRef, let data = image.pngData() else { throw ShelfError.unreadableImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let entry = ShelfEntry(id: id, filename: "Screenshot-\(id.uuidString).png", pixelWidth: cg.width, pixelHeight: cg.height)
        try data.write(to: url(for: entry), options: .atomic)
        do {
            try commit(entries + [entry])
        } catch {
            try? FileManager.default.removeItem(at: url(for: entry))
            throw error
        }
        return entry
    }

    func remove(id: UUID) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        try beginRemovalGracePeriod(for: [entry])
        try commit(entries.filter { $0.id != id })
        // Keep the PNG: a clipboard or drag destination may still be reading it.
        // Removed files are reclaimed by pruneUnreferencedFiles after a grace period.
    }

    func removeAll() throws {
        guard !entries.isEmpty else { return }
        try beginRemovalGracePeriod(for: entries)
        try commit([])
    }

    private func beginRemovalGracePeriod(for removed: [ShelfEntry]) throws {
        let now = Date()
        for entry in removed where FileManager.default.fileExists(atPath: url(for: entry).path) {
            // Start at removal so old captures copied just now remain readable.
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url(for: entry).path)
        }
    }

    func move(id: UUID, to destination: Int) throws {
        guard let source = entries.firstIndex(where: { $0.id == id }) else { return }
        var next = entries
        let entry = next.remove(at: source)
        next.insert(entry, at: max(0, min(destination, next.count)))
        if next != entries { try commit(next) }
    }

    private func commit(_ next: [ShelfEntry]) throws {
        let data = try JSONEncoder().encode(next)
        try data.write(to: indexURL, options: .atomic)
        entries = next
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func thumbnail(for entry: ShelfEntry) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: entry) as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg)
    }

    func copy(_ format: ShelfExport, to pasteboard: NSPasteboard = .general) throws {
        guard !entries.isEmpty else { throw ShelfError.empty }
        let objects: [NSPasteboardWriting]
        switch format {
        case .files:
            guard entries.allSatisfy({ FileManager.default.fileExists(atPath: url(for: $0).path) }) else {
                throw ShelfError.unreadableImage
            }
            objects = entries.map { url(for: $0) as NSURL }
        case .images:
            objects = try entries.map { entry -> NSPasteboardItem in
                let item = NSPasteboardItem()
                let data = try Data(contentsOf: url(for: entry))
                item.setData(data, forType: .png)
                return item
            }
        case .merged:
            guard let data = try mergedImage().pngData() else { throw ShelfError.unreadableImage }
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            objects = [item]
        }
        // Prepare everything before changing the user's clipboard.
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else { throw ShelfError.clipboard }
    }

    func mergedImage() throws -> NSImage {
        guard !entries.isEmpty else { throw ShelfError.empty }
        let gap = 16
        let width = entries.map(\.pixelWidth).max() ?? 0
        let height = entries.reduce(0) { $0 + $1.pixelHeight } + gap * (entries.count - 1)
        guard width > 0, height > 0, width <= 32_768, height <= 32_768,
              width * height <= 60_000_000 else { throw ShelfError.tooLarge }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ShelfError.tooLarge }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = height
        for entry in entries {
            guard let source = CGImageSourceCreateWithURL(url(for: entry) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ShelfError.unreadableImage }
            top -= image.height
            context.draw(image, in: CGRect(x: (width - image.width) / 2, y: top, width: image.width, height: image.height))
            top -= gap
        }
        guard let image = context.makeImage() else { throw ShelfError.unreadableImage }
        return NSImage(cgImage: image)
    }

    /// Only our unreferenced PNGs, older than a week, are eligible for reclamation.
    /// Active shelf entries are never subject to the history retention setting.
    func pruneUnreferencedFiles(now: Date = Date()) {
        let active = Set(entries.map(\.filename))
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.lastPathComponent.hasPrefix("Screenshot-") && file.pathExtension == "png" && !active.contains(file.lastPathComponent) {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               now.timeIntervalSince(date) > 7 * 24 * 60 * 60 {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
