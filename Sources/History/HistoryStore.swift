import AppKit

struct HistoryEntry: Codable {
    let id: UUID
    let filename: String
    let timestamp: Date

    func url(in directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }
}

final class HistoryStore {
    static let shared = HistoryStore()

    private let indexURL: URL
    let directory: URL
    private(set) var entries: [HistoryEntry] = []

    var onChange: (() -> Void)?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("MoliShot/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        self.indexURL = dir.appendingPathComponent("index.json")
        load()
        pruneIfNeeded(saveAfterPrune: true)
    }

    func store(image: NSImage) {
        guard let data = image.pngData() else { return }
        let id = UUID()
        let filename = "\(id.uuidString).png"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            let entry = HistoryEntry(id: id, filename: filename, timestamp: Date())
            entries.insert(entry, at: 0)
            pruneIfNeeded(saveAfterPrune: false)
            save()
            onChange?()
        } catch {
            NSLog("History store failed: \(error)")
        }
    }

    func delete(_ entry: HistoryEntry) {
        try? FileManager.default.removeItem(at: entry.url(in: directory))
        entries.removeAll { $0.id == entry.id }
        save()
        onChange?()
    }

    func image(for entry: HistoryEntry) -> NSImage? {
        NSImage(contentsOf: entry.url(in: directory))
    }

    func applyRetentionLimit() {
        pruneIfNeeded(saveAfterPrune: true)
        onChange?()
    }

    private func pruneIfNeeded(saveAfterPrune: Bool) {
        let max = AppSettings.historyLimit
        var didPrune = false
        while entries.count > max, let last = entries.last {
            try? FileManager.default.removeItem(at: last.url(in: directory))
            entries.removeLast()
            didPrune = true
        }
        if didPrune, saveAfterPrune {
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded.filter { FileManager.default.fileExists(atPath: $0.url(in: directory).path) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexURL)
        }
    }
}
