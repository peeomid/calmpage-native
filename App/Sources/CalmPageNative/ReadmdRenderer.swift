import Foundation

struct ReadmdRenderer {
    var cache: RenderCacheStore? = .live
    var useReadmdHTML = true

    func render(file: MarkdownFile, theme: String = "White", style: String = "Editorial", fontSize: Double = 18, contentWidth: Double = 760, readmdPath: String? = nil) async -> ReaderState {
        do {
            let options = ReadmdRenderOptions(theme: theme, style: style, fontSize: fontSize, contentWidth: contentWidth)
            if let cached = try cache?.load(file: file, options: options) {
                return .loaded(cached)
            }
            let markdown = try await Task.detached(priority: .userInitiated) {
                try String(contentsOf: file.url, encoding: .utf8)
            }.value
            let plainText = Self.markdownPlainText(markdown)
            let headings = Self.extractHeadings(markdown)
            let blocks = Self.markdownBlocks(markdown)
            let title = headings.first(where: { $0.level == 1 })?.title ?? file.title
            let html = useReadmdHTML ? ((try? await renderHTML(url: file.url, options: options, readmdPath: readmdPath)) ?? "") : ""
            let note = RenderedNote(title: title, html: html, plainText: plainText, headings: headings, blocks: blocks)
            try cache?.save(note, file: file, options: options)
            return .loaded(note)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func renderHTML(url: URL, options: ReadmdRenderOptions = .default, readmdPath: String? = nil) async throws -> String {
        guard let readmdPath, !readmdPath.isEmpty else { throw RendererError.readmd("readmd path is not configured") }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: readmdPath)
                process.arguments = [url.path, "--stdout", "--theme", options.readmdTheme, "--style", options.readmdStyle, "--no-generated-by-readmd"]

                let output = Pipe()
                let error = Pipe()
                process.standardOutput = output
                process.standardError = error

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    if process.terminationStatus == 0, let html = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: Self.injectCSS(options.cssOverride, into: html))
                    } else {
                        let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "readmd failed"
                        continuation.resume(throwing: RendererError.readmd(message))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func injectCSS(_ css: String, into html: String) -> String {
        if let range = html.range(of: "</head>", options: [.caseInsensitive]) {
            var updated = html
            updated.insert(contentsOf: css, at: range.lowerBound)
            return updated
        }
        return css + html
    }

    static func extractHeadings(_ markdown: String) -> [HeadingItem] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("#") else { return nil }
            let level = text.prefix { $0 == "#" }.count
            guard (1...3).contains(level), text.dropFirst(level).first == " " else { return nil }
            let title = text.dropFirst(level).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return HeadingItem(id: "heading-\(index)", level: level, title: title)
        }
    }

    static func markdownPlainText(_ markdown: String) -> String {
        let withoutFrontmatter = markdown
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: #"^---[\s\S]*?---\s*"#, with: "", options: .regularExpression)

        return withoutFrontmatter
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(line).replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
    }

    static func markdownBlocks(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdownPlainText(markdown).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        func flushCode() {
            let text = code.joined(separator: "\n")
            if !text.isEmpty { blocks.append(.code(text)) }
            code.removeAll()
        }

        for (index, rawLine) in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode { flushCode() }
                else { flushParagraph() }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(rawLine)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                if (1...3).contains(level), trimmed.dropFirst(level).first == " " {
                    flushParagraph()
                    let title = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(id: "heading-\(index)", level: level, text: title))
                    continue
                }
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            paragraph.append(lines.indices.contains(index) ? lines[index] : trimmed)
        }
        flushParagraph()
        flushCode()
        return blocks
    }
}

struct ReadmdRenderOptions: Hashable {
    let theme: String
    let style: String
    let fontSize: Double
    let contentWidth: Double

    static let `default` = ReadmdRenderOptions(theme: "White", style: "Editorial", fontSize: 18, contentWidth: 760)

    var readmdTheme: String {
        switch theme {
        case "White": return "white"
        case "Graphite": return "graphite"
        case "Polar": return "polar"
        case "Sepia": return "sepia"
        case "Midnight": return "midnight"
        default: return "paper"
        }
    }

    var readmdStyle: String {
        switch style {
        case "Notebook": return "notebook"
        case "Technical": return "technical"
        case "Large": return "large"
        default: return "editorial"
        }
    }

    var cssOverride: String {
        let roundedFontSize = Int(fontSize.rounded())
        let roundedWidth = Int(contentWidth.rounded())
        return """
        <style id="calmpage-reader-settings">
        :root { --calmpage-font-size: \(roundedFontSize)px; --calmpage-content-width: \(roundedWidth)px; }
        body { font-size: var(--calmpage-font-size) !important; padding-left: max(32px, env(safe-area-inset-left)) !important; padding-right: max(32px, env(safe-area-inset-right)) !important; }
        .page { padding-left: max(48px, 4vw) !important; padding-right: max(48px, 4vw) !important; }
        .reader, main, article, .container, .content, .document, .markdown-body { max-width: min(var(--calmpage-content-width), calc(100vw - 112px)) !important; margin-left: auto !important; margin-right: auto !important; }
        p, li, blockquote { font-size: var(--calmpage-font-size) !important; }
        </style>
        """
    }
}

struct RenderCacheStore {
    let directory: URL

    static var live: RenderCacheStore {
        AppPaths.migrateLegacyDataIfNeeded()
        return RenderCacheStore(directory: AppPaths.renderCacheDirectory)
    }

    func load(file: MarkdownFile, options: ReadmdRenderOptions = .default) throws -> RenderedNote? {
        let url = cacheURL(for: file, options: options)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(RenderedNote.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func save(_ note: RenderedNote, file: MarkdownFile, options: ReadmdRenderOptions = .default) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(note)
        try data.write(to: cacheURL(for: file, options: options), options: [.atomic])
    }

    func cacheURL(for file: MarkdownFile, options: ReadmdRenderOptions = .default) -> URL {
        directory.appendingPathComponent(Self.stableHash(cacheKey(for: file, options: options))).appendingPathExtension("json")
    }

    private func cacheKey(for file: MarkdownFile, options: ReadmdRenderOptions) -> String {
        ["render-v6-readmd-html", options.readmdTheme, options.readmdStyle, String(Int(options.fontSize.rounded())), String(Int(options.contentWidth.rounded())), file.url.path, String(file.sizeBytes), String(file.modifiedAt.timeIntervalSince1970)].joined(separator: "|")
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum RendererError: LocalizedError {
    case readmd(String)

    var errorDescription: String? {
        switch self {
        case .readmd(let message): "readmd failed: \(message)"
        }
    }
}
