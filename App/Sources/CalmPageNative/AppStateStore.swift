import Foundation

struct SavedAppState: Codable, Equatable {
    var rootPaths: [String] = []
    var tabs: [SavedTab] = []
    var activeTabID: String?
    var pinnedFileIDs: [String] = []
    var workspacePinnedFileIDs: [String: [String]] = [:]
    var workspaces: [WorkspaceItem] = [WorkspaceItem(name: "Default Workspace")]
    var activeWorkspaceID: UUID?
    var readerSettings = SavedReaderSettings()
    var readmdSettings = ReadmdSettings()

    enum CodingKeys: String, CodingKey {
        case rootPaths
        case tabs
        case activeTabID
        case pinnedFileIDs
        case workspacePinnedFileIDs
        case workspaces
        case activeWorkspaceID
        case readerSettings
        case readmdSettings
    }

    init() {}

    init(rootPaths: [String], tabs: [SavedTab], activeTabID: String?, pinnedFileIDs: [String], workspacePinnedFileIDs: [String: [String]] = [:], workspaces: [WorkspaceItem] = [WorkspaceItem(name: "Default Workspace")], activeWorkspaceID: UUID? = nil, readerSettings: SavedReaderSettings, readmdSettings: ReadmdSettings = ReadmdSettings()) {
        self.rootPaths = rootPaths
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.pinnedFileIDs = pinnedFileIDs
        self.workspacePinnedFileIDs = workspacePinnedFileIDs
        self.workspaces = workspaces.isEmpty ? [WorkspaceItem(name: "Default Workspace")] : workspaces
        self.activeWorkspaceID = activeWorkspaceID
        self.readerSettings = readerSettings
        self.readmdSettings = readmdSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootPaths = try container.decodeIfPresent([String].self, forKey: .rootPaths) ?? []
        tabs = try container.decodeIfPresent([SavedTab].self, forKey: .tabs) ?? []
        activeTabID = try container.decodeIfPresent(String.self, forKey: .activeTabID)
        pinnedFileIDs = try container.decodeIfPresent([String].self, forKey: .pinnedFileIDs) ?? []
        workspacePinnedFileIDs = try container.decodeIfPresent([String: [String]].self, forKey: .workspacePinnedFileIDs) ?? [:]
        let decodedWorkspaces = try container.decodeIfPresent([WorkspaceItem].self, forKey: .workspaces) ?? []
        workspaces = decodedWorkspaces.isEmpty ? [WorkspaceItem(name: "Default Workspace")] : decodedWorkspaces
        activeWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .activeWorkspaceID)
        readerSettings = try container.decodeIfPresent(SavedReaderSettings.self, forKey: .readerSettings) ?? SavedReaderSettings()
        readmdSettings = try container.decodeIfPresent(ReadmdSettings.self, forKey: .readmdSettings) ?? ReadmdSettings()
    }
}

struct SavedTab: Codable, Equatable {
    var id: String
    var filePath: String
    var relativePath: String
    var title: String
    var sizeBytes: Int64
    var modifiedAt: Date
    var scrollY: Double
}

struct SavedReaderSettings: Codable, Equatable {
    var fontSize: Double = 18
    var lineSpacing: Double = 8
    var contentWidth: Double = 760
    var selectedTheme: String = "White"
    var selectedReadmdStyle: String = "Editorial"
}

struct AppStateStore {
    let url: URL

    static var live: AppStateStore {
        AppPaths.migrateLegacyDataIfNeeded()
        return AppStateStore(url: AppPaths.stateURL)
    }

    func load() -> SavedAppState {
        guard let data = try? Data(contentsOf: url) else { return SavedAppState() }
        return (try? JSONDecoder().decode(SavedAppState.self, from: data)) ?? SavedAppState()
    }

    func save(_ state: SavedAppState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }
}
