import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("com.osimify.calmpage-native", isDirectory: true)
    }

    static var legacySpacedSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CalmPage Native", isDirectory: true)
    }

    static var legacyCompactSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CalmPageNative", isDirectory: true)
    }

    static var stateURL: URL { supportDirectory.appendingPathComponent("state.json") }
    static var libraryURL: URL { supportDirectory.appendingPathComponent("library.sqlite") }
    static var renderCacheDirectory: URL { supportDirectory.appendingPathComponent("render-cache", isDirectory: true) }

    static func migrateLegacyDataIfNeeded() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        copyIfNeeded(from: legacySpacedSupportDirectory.appendingPathComponent("state.json"), to: stateURL)
        copyIfNeeded(from: legacyCompactSupportDirectory.appendingPathComponent("library.sqlite"), to: libraryURL)
        copyDirectoryContentsIfNeeded(from: legacyCompactSupportDirectory.appendingPathComponent("render-cache", isDirectory: true), to: renderCacheDirectory)
    }

    private static func copyIfNeeded(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: destination.path) else { return }
        try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.copyItem(at: source, to: destination)
    }

    private static func copyDirectoryContentsIfNeeded(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let items = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try? fileManager.copyItem(at: item, to: target)
        }
    }
}
