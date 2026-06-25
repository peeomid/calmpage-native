import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var roots: [RootFolder] = []
    @Published var query = ""
    @Published var tabs: [ReaderTab] = []
    @Published var activeTabID: String?
    @Published var readerState: ReaderState = .empty
    @Published var sidebarMode: SidebarMode = .library
    @Published var sidebarWidth: CGFloat = 268
    @Published var sidebarCollapsed = false
    @Published var inspectorVisible = false
    @Published var focusMode = false
    @Published var paletteOpen = false
    @Published var paletteQuery = ""
    @Published var helpOpen = false
    @Published var indexingMessage = ""
    @Published var indexingProgress = 0.0
    @Published var isIndexing = false
    @Published var pinnedFileIDs: Set<String> = []
    @Published var workspacePinnedFileIDs: [UUID: Set<String>] = [:]
    @Published var fontSize: Double = 18
    @Published var lineSpacing: Double = 8
    @Published var contentWidth: Double = 760
    @Published var selectedTheme = "White"
    @Published var selectedReadmdStyle = "Editorial"
    @Published var readmdSettings = ReadmdSettings()
    @Published var settingsSection: SettingsSection = .reading
    @Published private(set) var fileCount = 0
    @Published private(set) var visibleFilesSnapshot: [MarkdownFile] = []
    @Published private(set) var pinnedFilesSnapshot: [MarkdownFile] = []
    @Published private(set) var rootLibraryChildrenSnapshot: LibraryChildren = .empty
    @Published private(set) var paletteItemsSnapshot: [PaletteItem] = []
    @Published var paletteStatusMessage = ""
    @Published private(set) var palettePathMatch: MarkdownFile?
    @Published var workspaceRefreshMessage = ""
    @Published var settingsOpen = false
    @Published var contentsOpen = false
    @Published var contentsSearchQuery = ""
    @Published var contentsSearchRequestID = UUID()
    @Published var activeHeadingID: String?
    @Published var headingScrollTargetID: String?
    @Published var readerScrollCommand: ReaderScrollCommand?
    @Published var documentFindOpen = false
    @Published var documentFindQuery = ""
    @Published var documentFindRequest: DocumentFindRequest?
    @Published var documentFindStatus = DocumentFindStatus()
    @Published var libraryFilterFocusRequestID = UUID()
    @Published var workspaces: [WorkspaceItem] = [WorkspaceItem(name: "Default Workspace")]
    @Published var activeWorkspaceID: UUID?

    private let stateStore: AppStateStore
    private let libraryStore: LibraryStore
    private let scanner = MarkdownScanner()
    private let renderer: ReadmdRenderer
    private var indexTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var paletteTask: Task<Void, Never>?
    private var pathLookupTask: Task<Void, Never>?
    private var workspaceMessageTask: Task<Void, Never>?

    init(stateStore: AppStateStore = .live, libraryStore: LibraryStore? = nil, renderer: ReadmdRenderer = ReadmdRenderer(), restoreSavedState: Bool = true) {
        self.stateStore = stateStore
        AppPaths.migrateLegacyDataIfNeeded()
        self.libraryStore = libraryStore ?? (try! LibraryStore(url: AppPaths.libraryURL))
        self.renderer = renderer
        if restoreSavedState {
            restoreState()
        } else {
            refreshFileCount()
        }
        Task { await resolveReadmdPath() }
    }

    var activeTab: ReaderTab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    var activeNote: RenderedNote? {
        if case .loaded(let note) = readerState { return note }
        return nil
    }

    var visibleFiles: [MarkdownFile] {
        (try? libraryStore.searchFiles(query: query.trimmingCharacters(in: .whitespacesAndNewlines), rootIDs: activeRootIDs, limit: 500)) ?? []
    }

    var pinnedFiles: [MarkdownFile] {
        (try? libraryStore.filesByIDs(activePinnedFileIDs)) ?? []
    }

    var activeRoots: [RootFolder] {
        let ids = activeRootIDs
        return roots.filter { ids.contains($0.id) }
    }

    var rootLibraryChildren: LibraryChildren {
        libraryChildren(parentPath: nil)
    }

    var debugCounters: AppDebugCounters {
        AppDebugCounters(
            rootsCount: roots.count,
            indexedFileCount: fileCount,
            openTabCount: tabs.count,
            loadedNoteCount: activeNote == nil ? 0 : 1,
            visibleRowCount: visibleFiles.count
        )
    }

    func libraryChildren(parentPath: String?, limit: Int = 200) -> LibraryChildren {
        (try? libraryStore.children(parentPath: parentPath, rootIDs: activeRootIDs, limit: limit)) ?? .empty
    }

    func loadLibraryChildren(parentPath: String?, limit: Int = 200) async -> LibraryChildren {
        let rootIDs = activeRootIDs
        return await Task.detached(priority: .utility) { [libraryStore] in
            (try? libraryStore.children(parentPath: parentPath, rootIDs: rootIDs, limit: limit)) ?? .empty
        }.value
    }

    func loadLibraryChildren(parentPath: String?, rootID: String, limit: Int = 200) async -> LibraryChildren {
        await Task.detached(priority: .utility) { [libraryStore] in
            (try? libraryStore.children(parentPath: parentPath, rootIDs: [rootID], limit: limit)) ?? .empty
        }.value
    }

    var paletteItems: [PaletteItem] {
        paletteItems(query: paletteQuery)
    }

    func paletteItems(query rawQuery: String) -> [PaletteItem] {
        let parsed = PaletteQuery(rawQuery)
        let text = parsed.text.lowercased()
        let fileResults = (parsed.mode == .smart || parsed.mode == .files) ? ((try? libraryStore.searchFiles(query: text, rootIDs: activeRootIDs, limit: 80)) ?? []) : []
        let pinnedResults = (parsed.mode == .smart || parsed.mode == .pinned) ? ((try? libraryStore.filesByIDs(activePinnedFileIDs)) ?? []) : []
        return buildPaletteItems(rawQuery: rawQuery, fileResults: fileResults, pinnedResults: pinnedResults, tabs: tabs, activeNote: activeNote)
    }

    var activeWorkspace: WorkspaceItem? {
        guard let activeWorkspaceID else { return nil }
        return workspaces.first { $0.id == activeWorkspaceID }
    }

    private var activeRootIDs: Set<String> {
        if let activeWorkspace {
            return activeWorkspace.rootIDs.intersection(Set(roots.map(\.id)))
        }
        return Set(roots.map(\.id))
    }

    private var allRootIDs: Set<String> { Set(roots.map(\.id)) }

    private var activePinnedFileIDs: Set<String> {
        guard let activeWorkspaceID else { return pinnedFileIDs }
        return workspacePinnedFileIDs[activeWorkspaceID] ?? []
    }

    private func buildPaletteItems(rawQuery: String, fileResults: [MarkdownFile], pinnedResults: [MarkdownFile], tabs: [ReaderTab], activeNote: RenderedNote?) -> [PaletteItem] {
        let query = PaletteQuery(rawQuery)
        let mode = query.mode
        let text = query.text.lowercased()
        var items: [PaletteItem] = []

        if text.isEmpty && mode == .smart {
            items += Self.paletteHelpItems.map {
                PaletteItem(id: "help:\($0.prefix)", title: "\($0.prefix) \($0.title)", subtitle: "Filter command palette", symbol: "keyboard", kind: .help($0))
            }
        }

        if mode == .smart || mode == .actions {
            let actions = [
                ("Open Folder", "Add a Markdown folder", "folder.badge.plus"),
                ("Refresh Workspace", "Scan active workspace folders", "arrow.clockwise"),
                ("Toggle Sidebar", "Show or hide library", "sidebar.left"),
                ("Toggle Contents", "Show or hide table of contents", "list.bullet.indent"),
                ("Toggle Focus Mode", "Reader-only layout", "text.book.closed"),
                ("Find in Document", "Search inside current reader", "text.magnifyingglass"),
                ("Filter Library", "Focus the library search field", "line.3.horizontal.decrease.circle"),
                (activePinnedFileIDs.contains(activeTab?.file.id ?? "") ? "Unpin Active File" : "Pin Active File", "Pin or unpin current tab", "pin"),
                ("Close All Tabs", "Release open note state", "xmark.rectangle.stack")
            ]
            items += actions.filter { matches($0.0, text) || matches($0.1, text) }.map {
                PaletteItem(id: "action:\($0.0)", title: $0.0, subtitle: $0.1, symbol: $0.2, kind: .action($0.0))
            }
        }

        if mode == .smart || mode == .tabs {
            items += tabs.filter { matches($0.file.title, text) || matches($0.file.relativePath, text) }.map {
                PaletteItem(id: "tab:\($0.id)", title: $0.file.title, subtitle: $0.file.relativePath, symbol: "macwindow", kind: .tab($0))
            }
        }

        if mode == .smart || mode == .pinned {
            items += pinnedResults.filter { matches($0.title, text) || matches($0.relativePath, text) }.map {
                PaletteItem(id: "pin:\($0.id)", title: $0.title, subtitle: $0.relativePath, symbol: "pin.fill", kind: .pinned($0))
            }
        }

        if mode == .smart || mode == .files {
            items += fileResults.map {
                PaletteItem(id: "file:\($0.id)", title: $0.title, subtitle: $0.relativePath, symbol: "doc.text", kind: .file($0))
            }
        }

        if (mode == .smart || mode == .files), !text.isEmpty, fileResults.isEmpty {
            items.append(PaletteItem(id: "status:path-search", title: "Searching pasted path...", subtitle: "Trying to repair and locate the file", symbol: "magnifyingglass", kind: .status))
        }

        if mode == .smart || mode == .headings, let activeNote {
            items += activeNote.headings.filter { matches($0.title, text) }.map {
                PaletteItem(id: "heading:\($0.id)", title: $0.title, subtitle: "Heading level \($0.level)", symbol: "number", kind: .heading($0))
            }
        }

        if mode == .smart || mode == .settings {
            let settings = ["Appearance", "Reading Width", "Font Size", "Line Height", "Theme"]
            items += settings.filter { matches($0, text) }.map {
                PaletteItem(id: "setting:\($0)", title: $0, subtitle: "Open reader settings", symbol: "gearshape", kind: .setting($0))
            }
        }

        if mode == .smart || mode == .workspaces {
            items += workspaces.filter { matches($0.name, text) }.map {
                PaletteItem(id: "workspace:\($0.id)", title: $0.name, subtitle: "Switch workspace", symbol: "square.grid.2x2", kind: .workspace($0.name))
            }
        }

        return Array(items.prefix(120))
    }

    static let paletteHelpItems: [PaletteHelpItem] = [
        PaletteHelpItem(id: "actions", prefix: ">", title: "Actions"),
        PaletteHelpItem(id: "files", prefix: "/", title: "Files"),
        PaletteHelpItem(id: "tabs", prefix: "@", title: "Tabs"),
        PaletteHelpItem(id: "headings", prefix: "#", title: "Headings"),
        PaletteHelpItem(id: "settings", prefix: "?", title: "Settings"),
        PaletteHelpItem(id: "workspaces", prefix: ":", title: "Workspaces"),
        PaletteHelpItem(id: "pins", prefix: "!", title: "Pinned")
    ]

    func openFolderPicker(additive: Bool = true) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = additive ? "Add" : "Open"
        if panel.runModal() == .OK {
            openFolders(panel.urls, replace: !additive)
        }
    }

    func openFolders(_ urls: [URL], replace: Bool) {
        if replace {
            roots = []
            fileCount = 0
            tabs = []
            activeTabID = nil
            readerState = .empty
        }

        let newRoots = urls.map { RootFolder(id: $0.resolvingSymlinksInPath().path, url: $0, name: $0.lastPathComponent) }
        let oldRootIDs = Set(roots.map(\.id))
        let mergedRoots = Array((roots + newRoots).reduce(into: [String: RootFolder]()) { $0[$1.id] = $1 }.values)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let rootsToIndex = mergedRoots.filter { !oldRootIDs.contains($0.id) }
        roots = mergedRoots
        ensureDefaultWorkspace()
        if let activeWorkspaceID,
           let index = workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) {
            workspaces[index].rootIDs.formUnion(newRoots.map(\.id))
        } else if let firstID = workspaces.first?.id,
                  let index = workspaces.firstIndex(where: { $0.id == firstID }) {
            workspaces[index].rootIDs = Set(mergedRoots.map(\.id))
            activeWorkspaceID = firstID
        }
        for root in mergedRoots {
            try? libraryStore.upsertRoot(root)
        }
        try? libraryStore.removeRootsNotIn(allRootIDs)
        saveState()
        refreshLibrarySnapshots()
        startIndexing(roots: rootsToIndex.isEmpty ? mergedRoots : rootsToIndex)
    }

    func removeRoot(_ root: RootFolder) {
        roots.removeAll { $0.id == root.id }
        for index in workspaces.indices {
            workspaces[index].rootIDs.remove(root.id)
        }
        try? libraryStore.removeRootsNotIn(allRootIDs)
        tabs.removeAll { tab in
            !roots.contains { root in
                tab.file.url.path == root.url.path || tab.file.url.path.hasPrefix(root.url.path + "/")
            }
        }
        if let activeTabID, !tabs.contains(where: { $0.id == activeTabID }) {
            self.activeTabID = tabs.last?.id
            loadActiveTab()
        }
        if tabs.isEmpty { readerState = .empty }
        refreshLibrarySnapshots()
        saveState()
    }

    func switchWorkspace(_ workspace: WorkspaceItem) {
        activeWorkspaceID = workspace.id
        sidebarMode = .workspaces
        query = ""
        if activeTab.map({ !fileIsInActiveWorkspace($0.file) }) == true {
            activeTabID = tabs.first(where: { fileIsInActiveWorkspace($0.file) })?.id
            loadActiveTab()
        }
        refreshLibrarySnapshots()
        saveState()
    }

    func toggleRoot(_ root: RootFolder, in workspace: WorkspaceItem) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        if workspaces[index].rootIDs.contains(root.id) {
            workspaces[index].rootIDs.remove(root.id)
        } else {
            workspaces[index].rootIDs.insert(root.id)
        }
        if activeWorkspaceID == workspace.id { refreshLibrarySnapshots() }
        saveState()
    }

    func cancelIndexing() {
        indexTask?.cancel()
        indexTask = nil
        isIndexing = false
        indexingMessage = "Indexing cancelled"
        setWorkspaceRefreshMessage("Indexing cancelled")
    }

    func startIndexing(roots: [RootFolder]) {
        indexTask?.cancel()
        isIndexing = true
        indexingProgress = 0
        indexingMessage = "Preparing folders..."

        indexTask = Task { [scanner, libraryStore] in
            var indexedCount = 0
            for (index, root) in roots.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.indexingMessage = "Indexing \(root.name)..."
                    self.indexingProgress = roots.isEmpty ? 0 : Double(index) / Double(roots.count)
                }

                do {
                    let scanned = try await Task.detached(priority: .utility) {
                        try scanner.scan(root: root.url)
                    }.value
                    if Task.isCancelled { return }
                    try await Task.detached(priority: .utility) {
                        try libraryStore.upsertRoot(root)
                        try libraryStore.upsertFiles(scanned, rootID: root.id)
                    }.value
                    indexedCount += scanned.count
                    let count = (try? libraryStore.countFiles()) ?? indexedCount
                    await MainActor.run {
                        self.fileCount = count
                        self.indexingMessage = "Indexed \(count) files"
                        self.refreshLibrarySnapshots()
                    }
                } catch {
                    await MainActor.run {
                        self.indexingMessage = "Could not index \(root.name): \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                self.refreshFileCount()
                self.refreshLibrarySnapshots()
                self.indexingProgress = 1
                self.isIndexing = false
                self.indexingMessage = "Indexed \(self.fileCount) Markdown files"
                self.setWorkspaceRefreshMessage("Workspace refreshed")
            }
        }
    }

    func indexFilesForTesting(_ files: [MarkdownFile], root: RootFolder) throws {
        if !roots.contains(root) { roots.append(root) }
        try libraryStore.upsertRoot(root)
        try libraryStore.upsertFiles(files, rootID: root.id)
        refreshFileCount()
        refreshLibrarySnapshots()
    }

    func openFile(_ file: MarkdownFile) {
        let tabID = file.id
        if tabs.contains(where: { $0.id == tabID }) {
            activateTab(tabID)
            return
        }
        let tab = ReaderTab(id: tabID, file: file)
        tabs.append(tab)
        activeTabID = tab.id
        saveState()
        loadActiveTab()
    }

    func activateTab(_ tabID: String) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        activeTabID = tabID
        saveState()
        loadActiveTab()
    }

    func activateNextTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs.isEmpty else { return }
        let nextIndex = tabs.index(after: index) == tabs.endIndex ? tabs.startIndex : tabs.index(after: index)
        activateTab(tabs[nextIndex].id)
    }

    func activatePreviousTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs.isEmpty else { return }
        let previousIndex = index == tabs.startIndex ? tabs.index(before: tabs.endIndex) : tabs.index(before: index)
        activateTab(tabs[previousIndex].id)
    }

    func activateTab(atShortcutIndex shortcutIndex: Int) {
        guard shortcutIndex >= 0, tabs.indices.contains(shortcutIndex) else { return }
        activateTab(tabs[shortcutIndex].id)
    }

    func closeTab(_ tab: ReaderTab) {
        tabs.removeAll { $0.id == tab.id }
        if activeTabID == tab.id {
            activeTabID = tabs.last?.id
            loadActiveTab()
        }
        if tabs.isEmpty { readerState = .empty }
        saveState()
    }

    func closeAllTabs() {
        tabs = []
        activeTabID = nil
        readerState = .empty
        saveState()
    }

    func closeActiveTab() {
        guard let activeTab else { return }
        closeTab(activeTab)
    }

    func loadActiveTab() {
        guard let activeTab else {
            readerState = .empty
            return
        }
        readerState = .loading(activeTab.file.title)
        Task {
            let result = await renderer.render(file: activeTab.file, theme: selectedTheme, style: selectedReadmdStyle, fontSize: fontSize, contentWidth: contentWidth, readmdPath: readmdSettings.resolvedPath)
            if self.activeTabID == activeTab.id {
                self.readerState = result
                if case .loaded(let note) = result {
                    self.activeHeadingID = note.headings.first?.id
                    self.refreshPaletteItems()
                }
            }
        }
    }

    func togglePin(_ file: MarkdownFile) {
        if let activeWorkspaceID {
            var pins = workspacePinnedFileIDs[activeWorkspaceID] ?? []
            if pins.contains(file.id) { pins.remove(file.id) } else { pins.insert(file.id) }
            workspacePinnedFileIDs[activeWorkspaceID] = pins
        } else if pinnedFileIDs.contains(file.id) {
            pinnedFileIDs.remove(file.id)
        } else {
            pinnedFileIDs.insert(file.id)
        }
        saveState()
        refreshPaletteItems()
        refreshPinnedFiles()
    }

    func isPinned(_ file: MarkdownFile) -> Bool {
        activePinnedFileIDs.contains(file.id)
    }

    func updateReaderSettings(fontSize: Double? = nil, lineSpacing: Double? = nil, contentWidth: Double? = nil, selectedTheme: String? = nil, selectedReadmdStyle: String? = nil) {
        let shouldReload = selectedTheme != nil || selectedReadmdStyle != nil || fontSize != nil || contentWidth != nil
        if let fontSize { self.fontSize = fontSize }
        if let lineSpacing { self.lineSpacing = lineSpacing }
        if let contentWidth { self.contentWidth = contentWidth }
        if let selectedTheme { self.selectedTheme = selectedTheme }
        if let selectedReadmdStyle { self.selectedReadmdStyle = selectedReadmdStyle }
        saveState()
        if shouldReload { loadActiveTab() }
    }

    func resetReaderSize() {
        updateReaderSettings(fontSize: 18, lineSpacing: 8, contentWidth: 760)
    }

    func openSettings(section: SettingsSection = .reading) {
        settingsSection = section
        settingsOpen = true
    }

    func resolveReadmdPath() async {
        let resolved = await ReadmdLocator.resolve(settings: readmdSettings)
        readmdSettings = resolved
        saveState()
        if resolved.status == .ready { loadActiveTab() }
    }

    func autoDetectReadmd() {
        readmdSettings.pathMode = .automatic
        readmdSettings.message = "Searching for readmd..."
        saveState()
        Task { await resolveReadmdPath() }
    }

    func chooseReadmdPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose readmd"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            setCustomReadmdPath(url.path)
        }
    }

    func setCustomReadmdPath(_ path: String) {
        readmdSettings.pathMode = .custom
        readmdSettings.customPath = path
        readmdSettings.message = "Checking readmd..."
        saveState()
        Task { await resolveReadmdPath() }
    }

    func runPaletteItem(_ item: PaletteItem) {
        switch item.kind {
        case .action(let action): runAction(action)
        case .file(let file), .pinned(let file), .pathMatch(let file): openFile(file)
        case .tab(let tab): activateTab(tab.id)
        case .heading(let heading): jumpToHeading(heading)
        case .setting: settingsOpen = true
        case .workspace: sidebarMode = .workspaces
        case .status: return
        case .help(let help):
            updatePaletteQuery(help.prefix + " ")
            paletteOpen = true
            return
        }
        paletteOpen = false
    }

    func runAction(_ action: String) {
        switch action {
        case "Open Folder": openFolderPicker(additive: true)
        case "Refresh Workspace": refreshActiveWorkspace()
        case "Toggle Sidebar": sidebarCollapsed.toggle()
        case "Toggle Contents": contentsOpen.toggle()
        case "Toggle Focus Mode": focusMode.toggle()
        case "Find in Document": openDocumentFind()
        case "Filter Library": focusLibraryFilter()
        case "Pin Active File", "Unpin Active File": if let file = activeTab?.file { togglePin(file) }
        case "Close All Tabs": closeAllTabs()
        default: break
        }
    }

    func openDocumentFind() {
        documentFindOpen = true
    }

    func closeDocumentFind() {
        documentFindOpen = false
        documentFindQuery = ""
        documentFindStatus = DocumentFindStatus()
    }

    func findInDocument(backwards: Bool = false) {
        let text = documentFindQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        documentFindRequest = DocumentFindRequest(query: text, backwards: backwards)
    }

    func updateDocumentFindStatus(current: Int, total: Int) {
        documentFindStatus = DocumentFindStatus(current: current, total: total)
    }

    func focusLibraryFilter() {
        focusMode = false
        sidebarCollapsed = false
        sidebarMode = .library
        libraryFilterFocusRequestID = UUID()
    }

    func addWorkspace(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let workspace = WorkspaceItem(name: name, rootIDs: [])
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        sidebarMode = .workspaces
        refreshLibrarySnapshots()
        saveState()
        refreshPaletteItems()
    }

    func renameWorkspace(_ workspace: WorkspaceItem, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index].name = name
        saveState()
        refreshPaletteItems()
    }

    func removeWorkspace(_ workspace: WorkspaceItem) {
        guard workspaces.count > 1 else { return }
        workspaces.removeAll { $0.id == workspace.id }
        workspacePinnedFileIDs.removeValue(forKey: workspace.id)
        if activeWorkspaceID == workspace.id { activeWorkspaceID = workspaces.first?.id }
        saveState()
        refreshLibrarySnapshots()
        refreshPaletteItems()
    }

    func createWorkspaceFromCurrentLibrary() {
        let baseName = "Workspace \(workspaces.count + 1)"
        var name = baseName
        var suffix = 2
        while workspaces.contains(where: { $0.name == name }) {
            name = "\(baseName) \(suffix)"
            suffix += 1
        }
        let workspace = WorkspaceItem(name: name, rootIDs: Set(roots.map(\.id)))
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        saveState()
        refreshPaletteItems()
    }

    func openPalette(prefix: String = "") {
        paletteQuery = prefix
        paletteOpen = true
        helpOpen = false
        refreshPaletteItems()
    }

    func openHelp() {
        helpOpen = true
        paletteOpen = false
    }

    func updateLibraryQuery(_ query: String) {
        self.query = query
        refreshVisibleFilesDebounced()
    }

    func updatePaletteQuery(_ query: String) {
        paletteQuery = query
        refreshPaletteItemsDebounced()
        resolvePastedPathDebounced(query)
    }

    func refreshActiveWorkspace() {
        let rootsToRefresh = activeRoots
        guard !rootsToRefresh.isEmpty else {
            setWorkspaceRefreshMessage("No folders in workspace")
            return
        }
        setWorkspaceRefreshMessage("Refreshing workspace...", autoClear: false)
        startIndexing(roots: rootsToRefresh)
    }

    func setWorkspaceRefreshMessage(_ message: String, autoClear: Bool = true) {
        workspaceMessageTask?.cancel()
        workspaceRefreshMessage = message
        guard autoClear else { return }
        workspaceMessageTask = Task { [message] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                if self.workspaceRefreshMessage == message { self.workspaceRefreshMessage = "" }
            }
        }
    }

    func openTOCSearch() {
        contentsOpen = true
        contentsSearchQuery = ""
        contentsSearchRequestID = UUID()
    }

    func handleReaderVimAction(_ action: ReaderVimAction) {
        switch action {
        case .down: readerScrollCommand = ReaderScrollCommand(deltaY: 96)
        case .up: readerScrollCommand = ReaderScrollCommand(deltaY: -96)
        case .searchTOC: openTOCSearch()
        }
    }

    func jumpToHeading(_ heading: HeadingItem) {
        activeHeadingID = heading.id
        headingScrollTargetID = heading.id
    }

    func updateActiveHeading(id: String) {
        guard activeHeadingID != id else { return }
        activeHeadingID = id
    }

    private func matches(_ text: String, _ query: String) -> Bool {
        query.isEmpty || text.lowercased().contains(query)
    }

    private func restoreState() {
        let state = stateStore.load()
        roots = state.rootPaths.map { path in
            let url = URL(fileURLWithPath: path)
            return RootFolder(id: url.resolvingSymlinksInPath().path, url: url, name: url.lastPathComponent)
        }
        tabs = state.tabs.compactMap { saved in
            let url = URL(fileURLWithPath: saved.filePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let file = MarkdownFile(
                id: saved.id,
                url: url,
                relativePath: saved.relativePath,
                title: saved.title,
                sizeBytes: saved.sizeBytes,
                modifiedAt: saved.modifiedAt
            )
            return ReaderTab(id: saved.id, file: file)
        }
        activeTabID = state.activeTabID.flatMap { activeID in tabs.contains { $0.id == activeID } ? activeID : nil } ?? tabs.first?.id
        pinnedFileIDs = Set(state.pinnedFileIDs)
        workspaces = state.workspaces.isEmpty ? [WorkspaceItem(name: "Default Workspace")] : state.workspaces
        ensureDefaultWorkspace()
        inferEmptyWorkspaceFoldersFromNames()
        activeWorkspaceID = state.activeWorkspaceID.flatMap { id in workspaces.contains { $0.id == id } ? id : nil } ?? workspaces.first?.id
        workspacePinnedFileIDs = Dictionary(uniqueKeysWithValues: state.workspacePinnedFileIDs.compactMap { key, value in
            guard let id = UUID(uuidString: key) else { return nil }
            return (id, Set(value))
        })
        migrateGlobalPinsToDefaultWorkspaceIfNeeded()
        fontSize = state.readerSettings.fontSize
        lineSpacing = state.readerSettings.lineSpacing
        contentWidth = state.readerSettings.contentWidth
        selectedTheme = state.readerSettings.selectedTheme
        selectedReadmdStyle = state.readerSettings.selectedReadmdStyle
        readmdSettings = state.readmdSettings

        if !roots.isEmpty {
            for root in roots {
                try? libraryStore.upsertRoot(root)
            }
            try? libraryStore.removeRootsNotIn(allRootIDs)
            refreshFileCount()
            refreshLibrarySnapshots()
            Task { startIndexing(roots: roots) }
        } else {
            try? libraryStore.removeRootsNotIn([])
            refreshFileCount()
            refreshLibrarySnapshots()
        }
        if activeTabID != nil {
            loadActiveTab()
        }
    }

    func savedStateSnapshot() -> SavedAppState {
        SavedAppState(
            rootPaths: roots.map(\.url.path),
            tabs: tabs.map { tab in
                SavedTab(
                    id: tab.id,
                    filePath: tab.file.url.path,
                    relativePath: tab.file.relativePath,
                    title: tab.file.title,
                    sizeBytes: tab.file.sizeBytes,
                    modifiedAt: tab.file.modifiedAt,
                    scrollY: 0
                )
            },
            activeTabID: activeTabID,
            pinnedFileIDs: Array(pinnedFileIDs).sorted(),
            workspacePinnedFileIDs: Dictionary(uniqueKeysWithValues: workspacePinnedFileIDs.map { key, value in
                (key.uuidString, Array(value).sorted())
            }),
            workspaces: workspaces,
            activeWorkspaceID: activeWorkspaceID,
            readerSettings: SavedReaderSettings(
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                contentWidth: contentWidth,
                selectedTheme: selectedTheme,
                selectedReadmdStyle: selectedReadmdStyle
            ),
            readmdSettings: readmdSettings
        )
    }

    private func saveState() {
        try? stateStore.save(savedStateSnapshot())
    }

    private func ensureDefaultWorkspace() {
        if workspaces.isEmpty { workspaces = [WorkspaceItem(name: "Default Workspace")] }
        let allRootIDs = Set(roots.map(\.id))
        if let index = workspaces.firstIndex(where: { $0.name == "Default Workspace" }), workspaces[index].rootIDs.isEmpty {
            workspaces[index].rootIDs = allRootIDs
        } else if !workspaces.contains(where: { $0.name == "Default Workspace" }) {
            workspaces.insert(WorkspaceItem(name: "Default Workspace", rootIDs: allRootIDs), at: 0)
        }
    }

    private func migrateGlobalPinsToDefaultWorkspaceIfNeeded() {
        guard !pinnedFileIDs.isEmpty,
              workspacePinnedFileIDs.isEmpty,
              let defaultID = workspaces.first(where: { $0.name == "Default Workspace" })?.id else { return }
        workspacePinnedFileIDs[defaultID] = pinnedFileIDs
    }

    private func inferEmptyWorkspaceFoldersFromNames() {
        for index in workspaces.indices where workspaces[index].rootIDs.isEmpty && workspaces[index].name != "Default Workspace" {
            let normalized = workspaces[index].name.lowercased()
            let matchingRoots = roots.filter { $0.name.lowercased() == normalized }
            if !matchingRoots.isEmpty {
                workspaces[index].rootIDs = Set(matchingRoots.map(\.id))
            }
        }
    }

    private func fileIsInActiveWorkspace(_ file: MarkdownFile) -> Bool {
        activeRoots.contains { root in
            file.url.path == root.url.path || file.url.path.hasPrefix(root.url.path + "/")
        }
    }

    private func refreshFileCount() {
        fileCount = (try? libraryStore.countFiles()) ?? 0
    }

    private func refreshLibrarySnapshots() {
        refreshVisibleFiles()
        refreshPinnedFiles()
        refreshRootChildren()
        refreshPaletteItems()
    }

    private func refreshVisibleFilesDebounced() {
        queryTask?.cancel()
        queryTask = Task { [query] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self.refreshVisibleFiles(queryOverride: query) }
        }
    }

    private func refreshPaletteItemsDebounced() {
        paletteTask?.cancel()
        paletteTask = Task { [paletteQuery] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self.refreshPaletteItems(queryOverride: paletteQuery) }
        }
    }

    private func resolvePastedPathDebounced(_ rawQuery: String) {
        pathLookupTask?.cancel()
        let parsed = PaletteQuery(rawQuery)
        let candidates = Self.normalizedPastedPathCandidates(parsed.text, roots: activeRoots)
        guard parsed.mode == .smart || parsed.mode == .files, !candidates.isEmpty else {
            paletteStatusMessage = ""
            palettePathMatch = nil
            return
        }
        paletteStatusMessage = "Searching pasted path..."
        palettePathMatch = nil
        let rootIDs = activeRootIDs
        let roots = activeRoots
        pathLookupTask = Task { [libraryStore] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            let found = await Task.detached(priority: .utility) { () -> MarkdownFile? in
                for candidate in candidates {
                    if let indexed = try? libraryStore.findFileByNormalizedPath(candidate, rootIDs: rootIDs) {
                        return indexed
                    }
                }
                for candidate in candidates {
                    if let indexed = try? libraryStore.findFileContainingNormalizedPath(candidate, rootIDs: rootIDs) {
                        return indexed
                    }
                }
                for root in roots {
                    for candidate in candidates {
                        let url = root.url.appendingPathComponent(candidate)
                        if let file = Self.markdownFileIfExists(url: url, root: root) {
                            try? libraryStore.upsertFile(file, rootID: root.id)
                            return file
                        }
                    }
                }
                return nil
            }.value
            await MainActor.run {
                if Task.isCancelled { return }
                if let found {
                    self.paletteStatusMessage = "Found pasted path"
                    self.palettePathMatch = found
                    self.refreshPaletteItems()
                } else {
                    self.paletteStatusMessage = "No matching path found"
                    self.palettePathMatch = nil
                    self.refreshPaletteItems()
                }
            }
        }
    }

    nonisolated static func normalizedPastedPath(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            .lowercased()
    }

    nonisolated static func normalizedPastedPathCandidates(_ rawValue: String, roots: [RootFolder]) -> [String] {
        let normalized = normalizedPastedPath(rawValue)
        guard normalized.contains("/"), normalized.hasSuffix(".md") || normalized.hasSuffix(".markdown") || normalized.hasSuffix(".mdx") else { return [] }
        var candidates = [normalized]
        for root in roots {
            let prefix = root.name.lowercased() + "/"
            if normalized.hasPrefix(prefix) {
                candidates.append(String(normalized.dropFirst(prefix.count)))
            }
        }
        return Array(Set(candidates))
            .sorted { $0.count < $1.count }
    }

    nonisolated static func markdownFileIfExists(url: URL, root: RootFolder) -> MarkdownFile? {
        let fileURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard ["md", "markdown", "mdx"].contains(fileURL.pathExtension.lowercased()) else { return nil }
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let rootPath = root.url.resolvingSymlinksInPath().path
        let filePath = fileURL.resolvingSymlinksInPath().path
        let relativePath = filePath.replacingOccurrences(of: rootPath + "/", with: "")
        return MarkdownFile(
            id: fileURL.path,
            url: fileURL,
            relativePath: relativePath,
            title: MarkdownScanner.title(from: fileURL),
            sizeBytes: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? .distantPast
        )
    }

    private func refreshVisibleFiles(queryOverride: String? = nil) {
        let text = (queryOverride ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        let rootIDs = activeRootIDs
        Task.detached(priority: .utility) { [libraryStore] in
            (try? libraryStore.searchFiles(query: text, rootIDs: rootIDs, limit: 500)) ?? []
        }.storeResult { [weak self] files in self?.visibleFilesSnapshot = files }
    }

    private func refreshPinnedFiles() {
        let ids = activePinnedFileIDs
        let tabFiles = tabs.map(\.file)
        Task.detached(priority: .utility) { [libraryStore] in
            let indexed = (try? libraryStore.filesByIDs(ids)) ?? []
            let indexedIDs = Set(indexed.map(\.id))
            let tabPinned = tabFiles.filter { ids.contains($0.id) && !indexedIDs.contains($0.id) }
            return (indexed + tabPinned).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }.storeResult { [weak self] files in self?.pinnedFilesSnapshot = files }
    }

    private func refreshRootChildren() {
        let rootIDs = activeRootIDs
        Task.detached(priority: .utility) { [libraryStore] in
            (try? libraryStore.children(parentPath: nil, rootIDs: rootIDs, limit: 200)) ?? .empty
        }.storeResult { [weak self] children in self?.rootLibraryChildrenSnapshot = children }
    }

    private func refreshPaletteItems(queryOverride: String? = nil) {
        let rawQuery = queryOverride ?? paletteQuery
        let parsed = PaletteQuery(rawQuery)
        let text = parsed.text.lowercased()
        let rootIDs = activeRootIDs
        let pinnedIDs = activePinnedFileIDs
        let tabs = tabs
        let activeNote = activeNote
        Task.detached(priority: .utility) { [libraryStore] in
            let fileResults = (parsed.mode == .smart || parsed.mode == .files) ? ((try? libraryStore.searchFiles(query: text, rootIDs: rootIDs, limit: 80)) ?? []) : []
            let pinnedResults = (parsed.mode == .smart || parsed.mode == .pinned) ? ((try? libraryStore.filesByIDs(pinnedIDs)) ?? []) : []
            return (fileResults, pinnedResults)
        }.storeResult { [weak self] result in
            guard let self else { return }
            var items = self.buildPaletteItems(rawQuery: rawQuery, fileResults: result.0, pinnedResults: result.1, tabs: tabs, activeNote: activeNote)
            if let match = self.palettePathMatch {
                items.insert(PaletteItem(id: "path-match:\(match.id)", title: match.title, subtitle: "Matched pasted path · \(match.relativePath)", symbol: "doc.text.magnifyingglass", kind: .pathMatch(match)), at: 0)
            }
            if !self.paletteStatusMessage.isEmpty {
                items.insert(PaletteItem(id: "status:path", title: self.paletteStatusMessage, subtitle: "Pasted path lookup", symbol: "magnifyingglass", kind: .status), at: 0)
            }
            self.paletteItemsSnapshot = items
        }
    }
}

private extension Task where Failure == Never {
    func storeResult(_ apply: @MainActor @escaping (Success) -> Void) {
        Task<Void, Never> { await apply(self.value) }
    }
}
