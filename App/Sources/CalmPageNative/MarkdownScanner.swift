import Foundation

struct MarkdownScanner {
    private let extensions = Set(["md", "markdown", "mdx"])

    func scan(root: URL) throws -> [MarkdownFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [MarkdownFile] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }

            let rootPath = root.resolvingSymlinksInPath().path
            let filePath = url.resolvingSymlinksInPath().path
            let relativePath = filePath.replacingOccurrences(of: rootPath + "/", with: "")
            files.append(
                MarkdownFile(
                    id: url.path,
                    url: url,
                    relativePath: relativePath,
                    title: Self.title(from: url),
                    sizeBytes: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }

        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    static func title(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let cleaned = stem.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
