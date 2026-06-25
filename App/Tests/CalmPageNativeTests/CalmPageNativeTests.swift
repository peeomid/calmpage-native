import XCTest
@testable import CalmPageNative

final class CalmPageNativeTests: XCTestCase {
    func testScannerFindsMarkdownFilesOnly() throws {
        let root = try makeTempVault()
        try "# Home".write(to: root.appendingPathComponent("home.md"), atomically: true, encoding: .utf8)
        try "No".write(to: root.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)

        let files = try MarkdownScanner().scan(root: root)

        XCTAssertEqual(files.map(\.relativePath), ["home.md"])
        XCTAssertEqual(files.first?.title, "home")
    }

    func testHeadingExtractionKeepsH1ToH3() {
        let headings = ReadmdRenderer.extractHeadings("# One\n\n## Two\n\n### Three\n\n#### Four")

        XCTAssertEqual(headings.map(\.title), ["One", "Two", "Three"])
    }

    func testMarkdownPlainTextRemovesSimpleMarkup() {
        let text = ReadmdRenderer.markdownPlainText("---\ntitle: X\n---\n# Title\n\n**Bold**")

        XCTAssertTrue(text.contains("Title"))
        XCTAssertTrue(text.contains("Bold"))
        XCTAssertFalse(text.contains("---"))
    }

    func testRenderCacheReturnsStoredNoteForSameFileMetadata() async throws {
        let root = try makeTempVault()
        let url = root.appendingPathComponent("cached.md")
        try "# First".write(to: url, atomically: true, encoding: .utf8)
        let file = MarkdownFile(id: url.path, url: url, relativePath: "cached.md", title: "Cached", sizeBytes: 7, modifiedAt: Date(timeIntervalSince1970: 10))
        let renderer = ReadmdRenderer(cache: RenderCacheStore(directory: root.appendingPathComponent("cache")), useReadmdHTML: false)

        let first = await renderer.render(file: file)
        try "# Other".write(to: url, atomically: true, encoding: .utf8)
        let second = await renderer.render(file: file)

        XCTAssertEqual(first, .loaded(RenderedNote(title: "First", html: "", plainText: "First", headings: [HeadingItem(id: "heading-0", level: 1, title: "First")])))
        XCTAssertEqual(second, first)
    }

    func testRenderCacheInvalidatesWhenFileSizeOrModifiedDateChanges() async throws {
        let root = try makeTempVault()
        let url = root.appendingPathComponent("changed.md")
        try "# First".write(to: url, atomically: true, encoding: .utf8)
        let renderer = ReadmdRenderer(cache: RenderCacheStore(directory: root.appendingPathComponent("cache")), useReadmdHTML: false)
        let original = MarkdownFile(id: url.path, url: url, relativePath: "changed.md", title: "Changed", sizeBytes: 7, modifiedAt: Date(timeIntervalSince1970: 10))
        _ = await renderer.render(file: original)

        try "# Second title".write(to: url, atomically: true, encoding: .utf8)
        let changed = MarkdownFile(id: url.path, url: url, relativePath: "changed.md", title: "Changed", sizeBytes: 14, modifiedAt: Date(timeIntervalSince1970: 11))
        let result = await renderer.render(file: changed)

        XCTAssertEqual(result, .loaded(RenderedNote(title: "Second title", html: "", plainText: "Second title", headings: [HeadingItem(id: "heading-0", level: 1, title: "Second title")])))
    }

    func testRenderCacheLoadsLegacyNoteWithoutBlocks() throws {
        let root = try makeTempVault()
        let url = root.appendingPathComponent("legacy.md")
        try "# Legacy".write(to: url, atomically: true, encoding: .utf8)
        let file = MarkdownFile(id: url.path, url: url, relativePath: "legacy.md", title: "Legacy", sizeBytes: 8, modifiedAt: Date(timeIntervalSince1970: 20))
        let cache = RenderCacheStore(directory: root.appendingPathComponent("cache"))
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let legacyJSON = """
        {"title":"Legacy","html":"","plainText":"Legacy","headings":[{"id":"heading-0","level":1,"title":"Legacy"}]}
        """
        try legacyJSON.write(to: cache.cacheURL(for: file), atomically: true, encoding: .utf8)

        let note = try cache.load(file: file)

        XCTAssertEqual(note, RenderedNote(title: "Legacy", html: "", plainText: "Legacy", headings: [HeadingItem(id: "heading-0", level: 1, title: "Legacy")], blocks: [.paragraph("Legacy")]))
    }

    @MainActor
    func testPinsPersistInModelState() {
        let model = makeModel()
        let file = MarkdownFile(
            id: "/tmp/test.md",
            url: URL(fileURLWithPath: "/tmp/test.md"),
            relativePath: "test.md",
            title: "Test",
            sizeBytes: 10,
            modifiedAt: .now
        )
        try? model.indexFilesForTesting([file], root: RootFolder(id: "/tmp", url: URL(fileURLWithPath: "/tmp"), name: "tmp"))

        model.togglePin(file)
        XCTAssertTrue(model.pinnedFileIDs.contains(file.id))
        XCTAssertEqual(model.pinnedFiles.map(\.id), [file.id])

        model.togglePin(file)
        XCTAssertFalse(model.pinnedFileIDs.contains(file.id))
    }

    @MainActor
    func testPaletteFindsActionsAndFiles() {
        let model = makeModel()
        let file = MarkdownFile(
            id: "/tmp/native-design.md",
            url: URL(fileURLWithPath: "/tmp/native-design.md"),
            relativePath: "native-design.md",
            title: "Native Design",
            sizeBytes: 10,
            modifiedAt: .now
        )
        try? model.indexFilesForTesting([file], root: RootFolder(id: "/tmp", url: URL(fileURLWithPath: "/tmp"), name: "tmp"))

        model.paletteQuery = "/ native"
        XCTAssertTrue(model.paletteItems.contains { $0.title == "Native Design" })

        model.paletteQuery = "> sidebar"
        XCTAssertTrue(model.paletteItems.contains { $0.title == "Toggle Sidebar" })
    }

    func testPaletteQueryDetectsPrefixes() {
        let cases: [(String, PaletteMode, String)] = [
            ("> sidebar", .actions, "sidebar"),
            ("/ native", .files, "native"),
            ("@ tab", .tabs, "tab"),
            ("# intro", .headings, "intro"),
            ("? theme", .settings, "theme"),
            (": default", .workspaces, "default"),
            ("! pinned", .pinned, "pinned"),
            ("plain", .smart, "plain")
        ]

        for (rawValue, mode, text) in cases {
            let query = PaletteQuery(rawValue)
            XCTAssertEqual(query.mode, mode)
            XCTAssertEqual(query.text, text)
        }
    }

    func testPaletteSelectionClampsAndMovesWithinBounds() {
        XCTAssertEqual(PaletteSelection.clamped(-4, count: 3), 0)
        XCTAssertEqual(PaletteSelection.clamped(9, count: 3), 2)
        XCTAssertEqual(PaletteSelection.clamped(2, count: 0), 0)
        XCTAssertEqual(PaletteSelection.moveUp(from: 0, count: 3), 0)
        XCTAssertEqual(PaletteSelection.moveDown(from: 0, count: 3), 1)
        XCTAssertEqual(PaletteSelection.moveDown(from: 2, count: 3), 2)
    }

    @MainActor
    func testNormalizedPastedPathRemovesTerminalLineBreaksAndSpaces() {
        let raw = "docs/lessons/w2-setup-buying-fit-mini-orchestrator-lesson-2026-\n        06-23.md"

        XCTAssertEqual(
            AppModel.normalizedPastedPath(raw),
            "docs/lessons/w2-setup-buying-fit-mini-orchestrator-lesson-2026-06-23.md"
        )
    }

    @MainActor
    func testNormalizedPastedPathCandidatesStripRootFolderName() {
        let root = RootFolder(id: "/Users/test/content", url: URL(fileURLWithPath: "/Users/test/content"), name: "content")
        let raw = "content/content-engine/runs/x/final.md"

        XCTAssertEqual(
            AppModel.normalizedPastedPathCandidates(raw, roots: [root]),
            ["content-engine/runs/x/final.md", "content/content-engine/runs/x/final.md"]
        )
    }

    @MainActor
    func testPaletteEnterRunsSelectedItem() throws {
        let model = makeModel()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        let files = [
            MarkdownFile(id: "/tmp/vault/alpha.md", url: URL(fileURLWithPath: "/tmp/vault/alpha.md"), relativePath: "alpha.md", title: "Alpha", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/beta.md", url: URL(fileURLWithPath: "/tmp/vault/beta.md"), relativePath: "beta.md", title: "Beta", sizeBytes: 1, modifiedAt: .now)
        ]
        try model.indexFilesForTesting(files, root: root)
        model.paletteOpen = true
        model.paletteQuery = "/"

        let items = model.paletteItems
        let selectedIndex = PaletteSelection.clamped(1, count: items.count)
        model.runPaletteItem(items[selectedIndex])

        XCTAssertEqual(model.activeTabID, files[1].id)
        XCTAssertFalse(model.paletteOpen)
    }

    @MainActor
    func testTabShortcutSelectionMovesBetweenTabs() {
        let model = makeModel()
        let files = [
            MarkdownFile(id: "/tmp/vault/one.md", url: URL(fileURLWithPath: "/tmp/vault/one.md"), relativePath: "one.md", title: "One", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/two.md", url: URL(fileURLWithPath: "/tmp/vault/two.md"), relativePath: "two.md", title: "Two", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/three.md", url: URL(fileURLWithPath: "/tmp/vault/three.md"), relativePath: "three.md", title: "Three", sizeBytes: 1, modifiedAt: .now)
        ]

        files.forEach { model.openFile($0) }
        model.activateTab(atShortcutIndex: 0)
        XCTAssertEqual(model.activeTabID, files[0].id)

        model.activateNextTab()
        XCTAssertEqual(model.activeTabID, files[1].id)

        model.activatePreviousTab()
        XCTAssertEqual(model.activeTabID, files[0].id)

        model.activatePreviousTab()
        XCTAssertEqual(model.activeTabID, files[2].id)
    }

    @MainActor
    func testPastedPathPaletteLookupWaitsForEnterBeforeOpening() async throws {
        let rootURL = try makeTempVault()
        let folder = rootURL.appendingPathComponent("content-engine/runs/x/final", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("note.md")
        try "# Final".write(to: fileURL, atomically: true, encoding: .utf8)

        let model = makeModel()
        let root = RootFolder(id: rootURL.path, url: rootURL, name: rootURL.lastPathComponent)
        let file = MarkdownFile(id: fileURL.path, url: fileURL, relativePath: "content-engine/runs/x/final/note.md", title: "note", sizeBytes: 7, modifiedAt: .now)
        try model.indexFilesForTesting([file], root: root)

        model.openPalette()
        model.updatePaletteQuery("\(root.name)/content-engine/runs/x/final/note.md")
        try await waitForPalettePathMatch(in: model, title: "note")

        XCTAssertNil(model.activeTabID)
        XCTAssertTrue(model.paletteOpen)
        XCTAssertTrue(model.paletteItemsSnapshot.contains { item in
            if case .pathMatch(let matched) = item.kind { return matched.id == file.id }
            return false
        })
    }

    @MainActor
    func testPaletteFileResultsUseQueryLimit() throws {
        let model = makeModel()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        let files = (0..<120).map { index in
            MarkdownFile(id: "/tmp/vault/note-\(index).md", url: URL(fileURLWithPath: "/tmp/vault/note-\(index).md"), relativePath: "note-\(index).md", title: "Note \(index)", sizeBytes: 1, modifiedAt: .now)
        }
        try model.indexFilesForTesting(files, root: root)
        model.paletteQuery = "/ note"

        XCTAssertEqual(model.paletteItems.count, 80)
        XCTAssertTrue(model.paletteItems.allSatisfy { if case .file = $0.kind { return true } else { return false } })
    }

    @MainActor
    func testPaletteFindsDefaultWorkspace() {
        let model = makeModel()
        model.paletteQuery = ": default"

        XCTAssertEqual(model.paletteItems.map(\.title), ["Default Workspace"])
    }

    func testLibraryStoreChildrenReturnsDirectChildrenOnly() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        try store.upsertRoot(root)
        try store.upsertFiles([
            MarkdownFile(id: "/tmp/vault/root.md", url: URL(fileURLWithPath: "/tmp/vault/root.md"), relativePath: "root.md", title: "Root", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/docs/page.md", url: URL(fileURLWithPath: "/tmp/vault/docs/page.md"), relativePath: "docs/page.md", title: "Page", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/docs/deep/nested.md", url: URL(fileURLWithPath: "/tmp/vault/docs/deep/nested.md"), relativePath: "docs/deep/nested.md", title: "Nested", sizeBytes: 1, modifiedAt: .now)
        ], rootID: root.id)

        let children = try store.children(parentPath: nil, limit: 10)

        XCTAssertEqual(children.folders.map(\.path), ["docs"])
        XCTAssertEqual(children.files.map(\.relativePath), ["root.md"])
        XCTAssertFalse(children.files.contains { $0.relativePath == "docs/page.md" })
    }

    func testLibraryStoreNestedDescendantsAreNotIncludedUntilRequested() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        try store.upsertRoot(root)
        try store.upsertFiles([
            MarkdownFile(id: "/tmp/vault/docs/page.md", url: URL(fileURLWithPath: "/tmp/vault/docs/page.md"), relativePath: "docs/page.md", title: "Page", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/docs/deep/nested.md", url: URL(fileURLWithPath: "/tmp/vault/docs/deep/nested.md"), relativePath: "docs/deep/nested.md", title: "Nested", sizeBytes: 1, modifiedAt: .now)
        ], rootID: root.id)

        let docsChildren = try store.children(parentPath: "docs", limit: 10)
        let deepChildren = try store.children(parentPath: "docs/deep", limit: 10)

        XCTAssertEqual(docsChildren.folders.map(\.path), ["docs/deep"])
        XCTAssertEqual(docsChildren.files.map(\.relativePath), ["docs/page.md"])
        XCTAssertFalse(docsChildren.files.contains { $0.relativePath == "docs/deep/nested.md" })
        XCTAssertEqual(deepChildren.files.map(\.relativePath), ["docs/deep/nested.md"])
    }

    func testLibraryStoreChildrenLimitIsEnforced() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        try store.upsertRoot(root)
        let files = (0..<5).map { index in
            MarkdownFile(id: "/tmp/vault/folder-\(index)/note.md", url: URL(fileURLWithPath: "/tmp/vault/folder-\(index)/note.md"), relativePath: "folder-\(index)/note.md", title: "Note \(index)", sizeBytes: 1, modifiedAt: .now)
        }
        try store.upsertFiles(files, rootID: root.id)

        let children = try store.children(parentPath: nil, limit: 2)

        XCTAssertEqual(children.folders.count + children.files.count, 2)
    }

    @MainActor
    func testAppModelLibraryChildrenUsesDirectStoreChildren() throws {
        let model = makeModel()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        try model.indexFilesForTesting([
            MarkdownFile(id: "/tmp/vault/root.md", url: URL(fileURLWithPath: "/tmp/vault/root.md"), relativePath: "root.md", title: "Root", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/docs/page.md", url: URL(fileURLWithPath: "/tmp/vault/docs/page.md"), relativePath: "docs/page.md", title: "Page", sizeBytes: 1, modifiedAt: .now),
            MarkdownFile(id: "/tmp/vault/docs/deep/nested.md", url: URL(fileURLWithPath: "/tmp/vault/docs/deep/nested.md"), relativePath: "docs/deep/nested.md", title: "Nested", sizeBytes: 1, modifiedAt: .now)
        ], root: root)

        let rootChildren = model.rootLibraryChildren
        let docsChildren = model.libraryChildren(parentPath: "docs")

        XCTAssertEqual(rootChildren.folders.map(\.path), ["docs"])
        XCTAssertEqual(rootChildren.files.map(\.relativePath), ["root.md"])
        XCTAssertEqual(docsChildren.folders.map(\.path), ["docs/deep"])
        XCTAssertEqual(docsChildren.files.map(\.relativePath), ["docs/page.md"])
    }

    @MainActor
    func testWorkspaceSwitchScopesLibraryRoots() throws {
        let model = makeModel()
        let content = RootFolder(id: "/tmp/content", url: URL(fileURLWithPath: "/tmp/content"), name: "content")
        let ideas = RootFolder(id: "/tmp/ideas", url: URL(fileURLWithPath: "/tmp/ideas"), name: "ideas")
        try model.indexFilesForTesting([
            MarkdownFile(id: "/tmp/content/a.md", url: URL(fileURLWithPath: "/tmp/content/a.md"), relativePath: "a.md", title: "A", sizeBytes: 1, modifiedAt: .now)
        ], root: content)
        try model.indexFilesForTesting([
            MarkdownFile(id: "/tmp/ideas/b.md", url: URL(fileURLWithPath: "/tmp/ideas/b.md"), relativePath: "b.md", title: "B", sizeBytes: 1, modifiedAt: .now)
        ], root: ideas)

        model.addWorkspace(named: "content")
        guard let workspace = model.activeWorkspace else { return XCTFail("Expected active workspace") }
        model.toggleRoot(content, in: workspace)

        XCTAssertEqual(model.activeRoots.map(\.name), ["content"])
        XCTAssertEqual(model.libraryChildren(parentPath: nil).files.map(\.title), ["A"])
    }

    @MainActor
    func testPinsAreScopedToActiveWorkspace() throws {
        let model = makeModel()
        let root = RootFolder(id: "/tmp/content", url: URL(fileURLWithPath: "/tmp/content"), name: "content")
        let file = MarkdownFile(id: "/tmp/content/a.md", url: URL(fileURLWithPath: "/tmp/content/a.md"), relativePath: "a.md", title: "A", sizeBytes: 1, modifiedAt: .now)
        try model.indexFilesForTesting([file], root: root)
        model.addWorkspace(named: "one")
        guard let one = model.activeWorkspace else { return XCTFail("Expected first workspace") }
        model.toggleRoot(root, in: one)
        model.togglePin(file)
        model.addWorkspace(named: "two")
        guard let two = model.activeWorkspace else { return XCTFail("Expected second workspace") }
        model.toggleRoot(root, in: two)

        XCTAssertFalse(model.isPinned(file))
        model.switchWorkspace(one)
        XCTAssertTrue(model.isPinned(file))
    }

    func testAppStateStoreRoundTripsRootsTabsPinsAndSettings() throws {
        let store = try makeTempStore()
        let state = SavedAppState(
            rootPaths: ["/tmp/vault"],
            tabs: [SavedTab(id: "/tmp/vault/a.md", filePath: "/tmp/vault/a.md", relativePath: "a.md", title: "A", sizeBytes: 12, modifiedAt: Date(timeIntervalSince1970: 10), scrollY: 42)],
            activeTabID: "/tmp/vault/a.md",
            pinnedFileIDs: ["/tmp/vault/a.md"],
            readerSettings: SavedReaderSettings(fontSize: 20, lineSpacing: 9, contentWidth: 700, selectedTheme: "Graphite", selectedReadmdStyle: "Technical"),
            readmdSettings: ReadmdSettings(pathMode: .custom, customPath: "/opt/homebrew/bin/readmd", detectedPath: "", status: .ready, version: "readmd 1.0", message: "ready")
        )

        try store.save(state)

        XCTAssertEqual(store.load(), state)
    }

    func testReadmdLocatorReportsMissingCustomPath() {
        let result = ReadmdLocator.validate(path: "/tmp/definitely-missing-readmd")

        XCTAssertEqual(result.status, .missing)
    }

    func testAppStateStoreLoadsLegacyStateWithoutWorkspaces() throws {
        let store = try makeTempStore()
        let legacyJSON = """
        {
          "rootPaths" : ["/tmp/vault"],
          "tabs" : [],
          "activeTabID" : null,
          "pinnedFileIDs" : [],
          "readerSettings" : {
            "fontSize" : 18,
            "lineSpacing" : 8,
            "contentWidth" : 760,
            "selectedTheme" : "White",
            "selectedReadmdStyle" : "Editorial"
          }
        }
        """
        try legacyJSON.write(to: store.url, atomically: true, encoding: .utf8)

        let state = store.load()

        XCTAssertEqual(state.rootPaths, ["/tmp/vault"])
        XCTAssertEqual(state.workspaces.map(\.name), ["Default Workspace"])
    }

    func testAppStateStoreLoadsLegacyWorkspacesWithoutRootIDs() throws {
        let store = try makeTempStore()
        let legacyJSON = """
        {
          "rootPaths" : ["/tmp/vault"],
          "tabs" : [],
          "activeTabID" : null,
          "pinnedFileIDs" : [],
          "workspaces" : [{"id":"AB930F32-29E5-4774-A271-706D6560B2C5","name":"Default Workspace"}],
          "readerSettings" : {
            "fontSize" : 18,
            "lineSpacing" : 8,
            "contentWidth" : 760,
            "selectedTheme" : "White",
            "selectedReadmdStyle" : "Editorial"
          }
        }
        """
        try legacyJSON.write(to: store.url, atomically: true, encoding: .utf8)

        let state = store.load()

        XCTAssertEqual(state.rootPaths, ["/tmp/vault"])
        XCTAssertEqual(state.workspaces.map(\.name), ["Default Workspace"])
        XCTAssertEqual(state.workspaces.first?.rootIDs, [])
    }

    @MainActor
    func testAppModelRestoresTabsAsMetadataOnly() throws {
        let root = try makeTempVault()
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        try "# First".write(to: first, atomically: true, encoding: .utf8)
        try "# Second".write(to: second, atomically: true, encoding: .utf8)
        let store = try makeTempStore()
        try store.save(SavedAppState(
            rootPaths: [root.path],
            tabs: [
                SavedTab(id: first.path, filePath: first.path, relativePath: "first.md", title: "First", sizeBytes: 7, modifiedAt: .now, scrollY: 0),
                SavedTab(id: second.path, filePath: second.path, relativePath: "second.md", title: "Second", sizeBytes: 8, modifiedAt: .now, scrollY: 0)
            ],
            activeTabID: first.path,
            pinnedFileIDs: [second.path],
            readerSettings: SavedReaderSettings(fontSize: 19, lineSpacing: 10, contentWidth: 720, selectedTheme: "Polar", selectedReadmdStyle: "Notebook")
        ))

        let model = AppModel(stateStore: store, restoreSavedState: true)

        XCTAssertEqual(model.roots.map(\.url.path), [root.path])
        XCTAssertEqual(model.tabs.map(\.id), [first.path, second.path])
        XCTAssertEqual(model.activeTabID, first.path)
        XCTAssertEqual(model.pinnedFileIDs, [second.path])
        XCTAssertEqual(model.selectedReadmdStyle, "Notebook")
        XCTAssertEqual(model.fontSize, 19)
        XCTAssertEqual(model.contentWidth, 720)
        XCTAssertNotEqual(model.readerState, .empty)
    }

    @MainActor
    func testAppModelSwitchingTabsUnloadsPreviousNoteAndLoadsActiveOnly() async throws {
        let root = try makeTempVault()
        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try "# First".write(to: firstURL, atomically: true, encoding: .utf8)
        try "# Second".write(to: secondURL, atomically: true, encoding: .utf8)
        let model = makeModel(cacheDirectory: root.appendingPathComponent("cache"))
        let first = MarkdownFile(id: firstURL.path, url: firstURL, relativePath: "first.md", title: "First", sizeBytes: 7, modifiedAt: .now)
        let second = MarkdownFile(id: secondURL.path, url: secondURL, relativePath: "second.md", title: "Second", sizeBytes: 8, modifiedAt: .now)

        model.openFile(first)
        try await waitForLoadedNote(in: model, title: "First")
        model.openFile(second)

        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertNil(Mirror(reflecting: model.tabs[0]).children.first { $0.value is RenderedNote })
        if case .loading("Second") = model.readerState {} else { XCTFail("Expected previous note to be released while second tab loads") }
        try await waitForLoadedNote(in: model, title: "Second")
        XCTAssertEqual(model.activeNote?.title, "Second")
    }

    @MainActor
    func testAppModelClickingActiveTabDoesNotReload() async throws {
        let root = try makeTempVault()
        let url = root.appendingPathComponent("note.md")
        try "# Note".write(to: url, atomically: true, encoding: .utf8)
        let model = makeModel(cacheDirectory: root.appendingPathComponent("cache"))
        let file = MarkdownFile(id: url.path, url: url, relativePath: "note.md", title: "Note", sizeBytes: 6, modifiedAt: .now)

        model.openFile(file)
        try await waitForLoadedNote(in: model, title: "Note")
        let loadedState = model.readerState

        model.activateTab(file.id)

        XCTAssertEqual(model.readerState, loadedState)
    }

    @MainActor
    func testAppModelReopeningActiveFileRefreshesChangedContent() async throws {
        let root = try makeTempVault()
        let url = root.appendingPathComponent("note.md")
        try "# First".write(to: url, atomically: true, encoding: .utf8)
        let model = makeModel(cacheDirectory: root.appendingPathComponent("cache"))
        let file = MarkdownFile(id: url.path, url: url, relativePath: "note.md", title: "Note", sizeBytes: 7, modifiedAt: Date(timeIntervalSince1970: 10))

        model.openFile(file)
        try await waitForLoadedNote(in: model, title: "First")
        try "# Second title".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 20)], ofItemAtPath: url.path)

        model.openFile(file)

        try await waitForLoadedNote(in: model, title: "Second title")
        XCTAssertEqual(model.tabs.first?.file.sizeBytes, 14)
    }

    @MainActor
    func testAppModelCloseAllTabsReleasesLoadedNote() async throws {
        let root = try makeTempVault()
        let url = root.appendingPathComponent("note.md")
        try "# Note".write(to: url, atomically: true, encoding: .utf8)
        let model = makeModel(cacheDirectory: root.appendingPathComponent("cache"))
        let file = MarkdownFile(id: url.path, url: url, relativePath: "note.md", title: "Note", sizeBytes: 6, modifiedAt: .now)

        model.openFile(file)
        try await waitForLoadedNote(in: model, title: "Note")
        model.closeAllTabs()

        XCTAssertNil(model.activeNote)
        XCTAssertEqual(model.readerState, .empty)
        XCTAssertTrue(model.tabs.isEmpty)
    }

    func testLibraryStorePersistsRootsAndSearchesMetadata() throws {
        let store = try LibraryStore.memory()
        let rootURL = URL(fileURLWithPath: "/tmp/vault")
        let root = RootFolder(id: rootURL.path, url: rootURL, name: "vault")
        let note = MarkdownFile(
            id: "/tmp/vault/docs/native-design.md",
            url: URL(fileURLWithPath: "/tmp/vault/docs/native-design.md"),
            relativePath: "docs/native-design.md",
            title: "Native Design",
            sizeBytes: 100,
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )

        try store.upsertRoot(root)
        try store.upsertFiles([note], rootID: root.id)

        XCTAssertEqual(try store.roots(), [root])
        XCTAssertEqual(try store.countFiles(), 1)
        XCTAssertEqual(try store.searchFiles(query: "native", limit: 10), [note])
        XCTAssertEqual(try store.searchFiles(query: "docs", limit: 10), [note])
        XCTAssertEqual(try store.fileByID(note.id), note)
    }

    func testLibraryStoreUpdatesExistingFileMetadata() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        let original = MarkdownFile(id: "/tmp/vault/a.md", url: URL(fileURLWithPath: "/tmp/vault/a.md"), relativePath: "a.md", title: "Old", sizeBytes: 1, modifiedAt: Date(timeIntervalSince1970: 1))
        let updated = MarkdownFile(id: "/tmp/vault/a.md", url: URL(fileURLWithPath: "/tmp/vault/a.md"), relativePath: "a.md", title: "New", sizeBytes: 2, modifiedAt: Date(timeIntervalSince1970: 2))

        try store.upsertRoot(root)
        try store.upsertFiles([original], rootID: root.id)
        try store.upsertFiles([updated], rootID: root.id)

        XCTAssertEqual(try store.countFiles(), 1)
        XCTAssertEqual(try store.fileByID(updated.id), updated)
    }

    func testLibraryStoreSearchLimitIsEnforced() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        try store.upsertRoot(root)
        let files = (0..<5).map { index in
            MarkdownFile(id: "/tmp/vault/note-\(index).md", url: URL(fileURLWithPath: "/tmp/vault/note-\(index).md"), relativePath: "note-\(index).md", title: "Note \(index)", sizeBytes: 1, modifiedAt: .now)
        }
        try store.upsertFiles(files, rootID: root.id)

        XCTAssertEqual(try store.searchFiles(query: "note", limit: 2).count, 2)
    }

    func testLibraryStoreSearchMatchesFilenameWithLooseSeparators() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        let file = MarkdownFile(
            id: "/tmp/vault/content-engine/runs/w2-research-notes.md",
            url: URL(fileURLWithPath: "/tmp/vault/content-engine/runs/w2-research-notes.md"),
            relativePath: "content-engine/runs/w2-research-notes.md",
            title: "w2-research-notes",
            sizeBytes: 1,
            modifiedAt: .now
        )
        try store.upsertRoot(root)
        try store.upsertFiles([file], rootID: root.id)

        XCTAssertEqual(try store.searchFiles(query: "w2 research notes", rootIDs: [root.id], limit: 10).map(\.id), [file.id])
        XCTAssertEqual(try store.searchFiles(query: "w2_research_notes.md", rootIDs: [root.id], limit: 10).map(\.id), [file.id])
    }

    func testLibraryStoreFindsPartialNormalizedPathFragment() throws {
        let store = try LibraryStore.memory()
        let root = RootFolder(id: "/tmp/content", url: URL(fileURLWithPath: "/tmp/content"), name: "content")
        let file = MarkdownFile(
            id: "/tmp/content/content-engine/runs/gearnudge/w2-full-userpain-test-20260624-01/GN-I026-gn-p026/w2-research-notes.md",
            url: URL(fileURLWithPath: "/tmp/content/content-engine/runs/gearnudge/w2-full-userpain-test-20260624-01/GN-I026-gn-p026/w2-research-notes.md"),
            relativePath: "content-engine/runs/gearnudge/w2-full-userpain-test-20260624-01/GN-I026-gn-p026/w2-research-notes.md",
            title: "w2-research-notes",
            sizeBytes: 1,
            modifiedAt: .now
        )
        try store.upsertRoot(root)
        try store.upsertFiles([file], rootID: root.id)

        let pasted = AppModel.normalizedPastedPath("engine/runs/gearnudge/w2-full-userpain-test-20260624-01/GN-I026-gn-p026/w2-research-\n    notes.md")

        XCTAssertEqual(try store.findFileContainingNormalizedPath(pasted, rootIDs: [root.id])?.id, file.id)
    }

    @MainActor
    func testAppModelSearchUsesLibraryStoreLimitAndTracksCount() throws {
        let model = makeModel()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        let files = (0..<600).map { index in
            MarkdownFile(id: "/tmp/vault/note-\(index).md", url: URL(fileURLWithPath: "/tmp/vault/note-\(index).md"), relativePath: "note-\(index).md", title: "Note \(index)", sizeBytes: 1, modifiedAt: .now)
        }

        try model.indexFilesForTesting(files, root: root)
        model.query = "note"

        XCTAssertEqual(model.fileCount, 600)
        XCTAssertEqual(model.visibleFiles.count, 500)
    }

    @MainActor
    func testAppModelDebugCountersTrackRegressionGateValues() async throws {
        let rootURL = try makeTempVault()
        let noteURL = rootURL.appendingPathComponent("note.md")
        try "# Note".write(to: noteURL, atomically: true, encoding: .utf8)
        let model = makeModel(cacheDirectory: rootURL.appendingPathComponent("cache"))
        let root = RootFolder(id: rootURL.path, url: rootURL, name: rootURL.lastPathComponent)
        let file = MarkdownFile(id: noteURL.path, url: noteURL, relativePath: "note.md", title: "Note", sizeBytes: 6, modifiedAt: .now)

        model.roots = [root]
        try model.indexFilesForTesting([file], root: root)
        model.openFile(file)
        try await waitForLoadedNote(in: model, title: "Note")

        XCTAssertEqual(model.debugCounters, AppDebugCounters(
            rootsCount: 1,
            indexedFileCount: 1,
            openTabCount: 1,
            loadedNoteCount: 1,
            visibleRowCount: 1
        ))

        model.closeAllTabs()

        XCTAssertEqual(model.debugCounters.openTabCount, 0)
        XCTAssertEqual(model.debugCounters.loadedNoteCount, 0)
    }

    @MainActor
    func testAppModelPinsResolveFromLibraryStore() throws {
        let model = makeModel()
        let root = RootFolder(id: "/tmp/vault", url: URL(fileURLWithPath: "/tmp/vault"), name: "vault")
        let file = MarkdownFile(id: "/tmp/vault/pinned.md", url: URL(fileURLWithPath: "/tmp/vault/pinned.md"), relativePath: "pinned.md", title: "Pinned", sizeBytes: 1, modifiedAt: .now)

        try model.indexFilesForTesting([file], root: root)
        model.pinnedFileIDs = [file.id]

        XCTAssertEqual(model.pinnedFiles.map(\.id), [file.id])
    }

    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempStore() throws -> AppStateStore {
        let root = try makeTempVault()
        return AppStateStore(url: root.appendingPathComponent("state.json"))
    }

    @MainActor
    private func makeModel(cacheDirectory: URL? = nil) -> AppModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        let cache = RenderCacheStore(directory: cacheDirectory ?? url.deletingLastPathComponent().appendingPathComponent("cache"))
        return AppModel(stateStore: AppStateStore(url: url), libraryStore: try! LibraryStore.memory(), renderer: ReadmdRenderer(cache: cache, useReadmdHTML: false), restoreSavedState: false)
    }

    @MainActor
    private func waitForLoadedNote(in model: AppModel, title: String) async throws {
        for _ in 0..<50 {
            if model.activeNote?.title == title { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for loaded note named \(title)")
    }

    @MainActor
    private func waitForPalettePathMatch(in model: AppModel, title: String) async throws {
        for _ in 0..<50 {
            if model.paletteItemsSnapshot.contains(where: { item in
                if case .pathMatch(let file) = item.kind { return file.title == title }
                return false
            }) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for pasted path match named \(title)")
    }
}
