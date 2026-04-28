import AppKit
import ServiceManagement

enum AppSettings {
    private static let saveDirectoryBookmarkKey = "saveDirectoryBookmark"
    private static let historyLimitKey = "historyLimit"

    static let minHistoryLimit = 1
    static let maxHistoryLimit = 500

    static var historyLimit: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: historyLimitKey)
            return value > 0 ? value : 50
        }
        set {
            UserDefaults.standard.set(clampedHistoryLimit(newValue), forKey: historyLimitKey)
        }
    }

    static func clampedHistoryLimit(_ value: Int) -> Int {
        min(max(value, minHistoryLimit), maxHistoryLimit)
    }

    static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setLaunchesAtLogin(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }

    // MARK: - Save Directory (Security-Scoped Bookmarks)

    /// Tracks whether the current security-scoped resource is being accessed.
    private static var isAccessingSecurityScopedResource = false
    private static var accessedURL: URL?

    static var saveDirectoryURL: URL {
        get {
            if let data = UserDefaults.standard.data(forKey: saveDirectoryBookmarkKey) {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: data,
                    options: [.withoutUI, .withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    if isStale {
                        setSaveDirectory(url)
                    }
                    return url
                }
            }

            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
    }

    static func setSaveDirectory(_ url: URL) {
        // Stop accessing the previous security-scoped resource
        stopAccessingSaveDirectory()

        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(data, forKey: saveDirectoryBookmarkKey)
    }

    static func clearSaveDirectory() {
        stopAccessingSaveDirectory()
        UserDefaults.standard.removeObject(forKey: saveDirectoryBookmarkKey)
    }

    /// Start accessing the security-scoped save directory.
    /// Must be called before reading/writing files in the directory.
    @discardableResult
    static func startAccessingSaveDirectory() -> Bool {
        guard !isAccessingSecurityScopedResource else { return true }
        let url = saveDirectoryURL
        if url.startAccessingSecurityScopedResource() {
            isAccessingSecurityScopedResource = true
            accessedURL = url
            return true
        }
        return false
    }

    /// Stop accessing the security-scoped save directory.
    static func stopAccessingSaveDirectory() {
        if isAccessingSecurityScopedResource, let url = accessedURL {
            url.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
            accessedURL = nil
        }
    }

    static func save(image: NSImage, prefix: String) throws -> URL {
        guard let data = image.pngData() else {
            throw NSError(domain: "MoliShot.Save", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }

        let directory = saveDirectoryURL
        startAccessingSaveDirectory()
        defer { stopAccessingSaveDirectory() }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "\(prefix)-\(formatter.string(from: Date()))"

        var attempt = 0
        var url = directory.appendingPathComponent("\(baseName).png")
        while FileManager.default.fileExists(atPath: url.path) {
            attempt += 1
            url = directory.appendingPathComponent("\(baseName)-\(attempt).png")
        }

        try data.write(to: url)
        return url
    }
}
