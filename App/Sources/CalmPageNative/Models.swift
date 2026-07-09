import Foundation

struct MarkdownFile: Identifiable, Hashable {
    let id: String
    let url: URL
    let relativePath: String
    let title: String
    let sizeBytes: Int64
    let modifiedAt: Date
}

struct RootFolder: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
}

struct ReaderTab: Identifiable, Hashable {
    let id: String
    let file: MarkdownFile
}

struct WorkspaceItem: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var rootIDs: Set<String>

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootIDs
    }

    init(id: UUID = UUID(), name: String, rootIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.rootIDs = rootIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Workspace"
        rootIDs = try container.decodeIfPresent(Set<String>.self, forKey: .rootIDs) ?? []
    }
}

struct HeadingItem: Identifiable, Hashable, Codable {
    let id: String
    let level: Int
    let title: String
}

enum MarkdownBlock: Equatable, Codable, Hashable {
    case heading(id: String, level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case code(String)
    case quote(String)
}

struct RenderedNote: Equatable, Codable {
    let title: String
    let html: String
    let plainText: String
    let headings: [HeadingItem]
    let blocks: [MarkdownBlock]

    init(title: String, html: String, plainText: String, headings: [HeadingItem], blocks: [MarkdownBlock]? = nil) {
        self.title = title
        self.html = html
        self.plainText = plainText
        self.headings = headings
        if let blocks {
            self.blocks = blocks
        } else if !headings.isEmpty {
            self.blocks = headings.map { .heading(id: $0.id, level: $0.level, text: $0.title) }
        } else {
            self.blocks = [.paragraph(plainText)]
        }
    }

    enum CodingKeys: String, CodingKey {
        case title
        case html
        case plainText
        case headings
        case blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decode(String.self, forKey: .title)
        let html = try container.decodeIfPresent(String.self, forKey: .html) ?? ""
        let plainText = try container.decode(String.self, forKey: .plainText)
        let headings = try container.decode([HeadingItem].self, forKey: .headings)
        let blocks = try container.decodeIfPresent([MarkdownBlock].self, forKey: .blocks)
        self.init(title: title, html: html, plainText: plainText, headings: headings, blocks: blocks ?? [.paragraph(plainText)])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(html, forKey: .html)
        try container.encode(plainText, forKey: .plainText)
        try container.encode(headings, forKey: .headings)
        try container.encode(blocks, forKey: .blocks)
    }
}

enum ReaderState: Equatable {
    case empty
    case loading(String)
    case loaded(RenderedNote)
    case failed(String)
}

enum SidebarMode: String, CaseIterable, Identifiable {
    case library
    case workspaces
    case pins

    var id: String { rawValue }
}

enum PaletteMode: String, CaseIterable, Identifiable {
    case smart
    case actions
    case files
    case tabs
    case headings
    case settings
    case workspaces
    case pinned

    var id: String { rawValue }
}

struct PaletteItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case action(String)
        case file(MarkdownFile)
        case tab(ReaderTab)
        case heading(HeadingItem)
        case pinned(MarkdownFile)
        case setting(String)
        case workspace(String)
        case status
        case pathMatch(MarkdownFile)
        case help(PaletteHelpItem)
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let kind: Kind
}

struct PaletteHelpItem: Identifiable, Hashable {
    let id: String
    let prefix: String
    let title: String
}

struct ReaderThemeOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct PaletteQuery: Equatable {
    let mode: PaletteMode
    let text: String

    init(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        let first = trimmed.first
        switch first {
        case ">": mode = .actions
        case "/": mode = .files
        case "@": mode = .tabs
        case "#": mode = .headings
        case "?": mode = .settings
        case ":": mode = .workspaces
        case "!": mode = .pinned
        default: mode = .smart
        }

        if let first, PaletteQuery.prefixes.contains(first) {
            text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else {
            text = trimmed
        }
    }

    private static let prefixes: Set<Character> = [">", "/", "@", "#", "?", ":", "!"]
}

enum PaletteSelection {
    static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    static func moveUp(from index: Int, count: Int) -> Int {
        clamped(index - 1, count: count)
    }

    static func moveDown(from index: Int, count: Int) -> Int {
        clamped(index + 1, count: count)
    }
}

struct LibraryFolder: Identifiable, Hashable {
    let id: String
    let path: String
    let name: String
}

struct LibraryChildren: Equatable {
    var folders: [LibraryFolder]
    var files: [MarkdownFile]

    static let empty = LibraryChildren(folders: [], files: [])
}

struct LibraryRevealRequest: Equatable {
    let id = UUID()
    let rootID: String
    let folderPaths: Set<String>
    let fileID: String
}

struct AppDebugCounters: Equatable {
    var rootsCount: Int
    var indexedFileCount: Int
    var openTabCount: Int
    var loadedNoteCount: Int
    var visibleRowCount: Int
}

enum ReaderVimAction {
    case down
    case up
    case searchTOC
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case reading = "Reading"
    case library = "Library"
    case renderer = "Renderer"
    case shortcuts = "Shortcuts"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .reading: return "textformat.size"
        case .library: return "folder"
        case .renderer: return "terminal"
        case .shortcuts: return "keyboard"
        }
    }
}

struct ReaderScrollCommand: Equatable {
    let id = UUID()
    let deltaY: CGFloat
}

struct DocumentFindRequest: Equatable {
    let id = UUID()
    let query: String
    let backwards: Bool
}

struct DocumentFindStatus: Equatable {
    var current: Int = 0
    var total: Int = 0
}
