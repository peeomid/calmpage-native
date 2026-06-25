import SwiftUI
import WebKit

private enum ShellMetrics {
    static let railWidth: CGFloat = 52
    static let sidebarWidth: CGFloat = 280
    static let titlebarHeight: CGFloat = 44
}

@main
struct CalmPageNativeApp: App {
    @StateObject private var model = AppModel()

    init() {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        app.setActivationPolicy(.regular)
        DispatchQueue.main.async { app.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup {
        ContentView()
                .environmentObject(model)
                .frame(minWidth: 1220, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Folder...") { model.openFolderPicker(additive: true) }
                    .keyboardShortcut("O", modifiers: [.command, .shift])
                Button("Command Palette") { model.openPalette() }
                    .keyboardShortcut("p", modifiers: [.command])
                Button("Find in Document") { model.openDocumentFind() }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("Filter Library") { model.focusLibraryFilter() }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("Settings...") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Reader") {
                Button("Toggle Contents") { model.contentsOpen.toggle() }
                    .keyboardShortcut("j", modifiers: [.command])
                Button("Toggle Sidebar") { model.sidebarCollapsed.toggle() }
                    .keyboardShortcut("b", modifiers: [.command])
                Button("Toggle Focus Mode") { model.focusMode.toggle() }
                    .keyboardShortcut(".", modifiers: [.command])
                Button("Next Tab") { model.activateNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { model.activatePreviousTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Close Tab") { model.closeActiveTab() }
                    .keyboardShortcut("w", modifiers: [.command])
                Button("Close All Tabs") { model.closeAllTabs() }
                    .keyboardShortcut("W", modifiers: [.command, .shift])
                Divider()
                ForEach(1...9, id: \.self) { index in
                    Button("Select Tab \(index)") { model.activateTab(atShortcutIndex: index - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [.command])
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            NativeSplitShell(model: model)
                .ignoresSafeArea(.container, edges: .top)
            if !model.sidebarCollapsed && !model.focusMode {
                SidebarTitlebarOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: .top)
                    .zIndex(5)
            }
            if !model.focusMode {
                ReaderTopTabBarView()
                    .padding(.leading, model.sidebarCollapsed ? 72 : ShellMetrics.sidebarWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: .top)
                    .zIndex(6)
            }
            if !model.workspaceRefreshMessage.isEmpty || model.readmdSettings.status != .ready {
                AppStatusToast()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 18)
                    .padding(.bottom, 48)
                    .zIndex(8)
            }
            if model.paletteOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { model.paletteOpen = false }
                CommandPaletteView()
                    .environmentObject(model)
                    .zIndex(20)
            }
            if model.helpOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { model.helpOpen = false }
                HelpPanelView()
                    .environmentObject(model)
                    .zIndex(22)
            }
        }
        .background(AppTheme.windowBackground(model.selectedTheme))
        .background(WindowAppearanceSetter(theme: model.selectedTheme))
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(AppKeyHandlingView(
            closeTab: { model.closeActiveTab() },
            findDocument: { model.openDocumentFind() },
            filterLibrary: { model.focusLibraryFilter() },
            nextTab: { model.activateNextTab() },
            previousTab: { model.activatePreviousTab() },
            selectTab: { model.activateTab(atShortcutIndex: $0) }
        ))
        .tint(AppTheme.activeIcon(model.selectedTheme))
        .sheet(isPresented: $model.settingsOpen) { ReaderSettingsView() }
        .transaction { $0.animation = nil }
    }
}

struct NativeSplitShell: NSViewControllerRepresentable {
    @ObservedObject var model: AppModel

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin

        let sidebarController = NSHostingController(rootView: sidebarView)
        let readerController = NSHostingController(rootView: readerView)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 260
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = model.sidebarCollapsed || model.focusMode
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none

        let readerItem = NSSplitViewItem(viewController: readerController)
        readerItem.minimumThickness = 620
        readerItem.canCollapse = false
        readerItem.titlebarSeparatorStyle = .none

        controller.addSplitViewItem(sidebarItem)
        controller.addSplitViewItem(readerItem)
        context.coordinator.sidebarItem = sidebarItem
        context.coordinator.sidebarController = sidebarController
        context.coordinator.readerController = readerController
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.sidebarController?.rootView = sidebarView
        context.coordinator.readerController?.rootView = readerView
        context.coordinator.sidebarItem?.animator().isCollapsed = model.sidebarCollapsed || model.focusMode
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var sidebarView: AnyView {
        AnyView(LeftSidebarView().environmentObject(model))
    }

    private var readerView: AnyView {
        AnyView(ReaderColumnView().environmentObject(model))
    }

    final class Coordinator {
        var sidebarItem: NSSplitViewItem?
        var sidebarController: NSHostingController<AnyView>?
        var readerController: NSHostingController<AnyView>?
    }
}

struct WindowAppearanceSetter: NSViewRepresentable {
    let theme: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        let appearanceName: NSAppearance.Name = AppTheme.isDark(theme) ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        NSApplication.shared.appearance = appearance
        window.appearance = appearance
        window.backgroundColor = NSColor(AppTheme.windowBackground(theme))
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 1220, height: 760)
        ensureUsableWindowSize(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ensureUsableWindowSize(window) }
    }

    private func ensureUsableWindowSize(_ window: NSWindow) {
        guard window.frame.width < 900 || window.frame.height < 600 else { return }
        window.setFrame(NSRect(x: 700, y: 120, width: 1220, height: 1050), display: true)
    }
}

struct AppKeyHandlingView: NSViewRepresentable {
    let closeTab: () -> Void
    let findDocument: () -> Void
    let filterLibrary: () -> Void
    let nextTab: () -> Void
    let previousTab: () -> Void
    let selectTab: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.closeTab = closeTab
        context.coordinator.findDocument = findDocument
        context.coordinator.filterLibrary = filterLibrary
        context.coordinator.nextTab = nextTab
        context.coordinator.previousTab = previousTab
        context.coordinator.selectTab = selectTab
        context.coordinator.install()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(closeTab: closeTab, findDocument: findDocument, filterLibrary: filterLibrary, nextTab: nextTab, previousTab: previousTab, selectTab: selectTab)
    }

    final class Coordinator {
        var closeTab: () -> Void
        var findDocument: () -> Void
        var filterLibrary: () -> Void
        var nextTab: () -> Void
        var previousTab: () -> Void
        var selectTab: (Int) -> Void
        private var monitor: Any?

        init(closeTab: @escaping () -> Void, findDocument: @escaping () -> Void, filterLibrary: @escaping () -> Void, nextTab: @escaping () -> Void, previousTab: @escaping () -> Void, selectTab: @escaping (Int) -> Void) {
            self.closeTab = closeTab
            self.findDocument = findDocument
            self.filterLibrary = filterLibrary
            self.nextTab = nextTab
            self.previousTab = previousTab
            self.selectTab = selectTab
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers == [.command, .shift] {
                    switch chars {
                    case "]": self.nextTab(); return nil
                    case "[": self.previousTab(); return nil
                    default: return event
                    }
                }
                guard modifiers == .command else { return event }
                switch chars {
                case "w": self.closeTab(); return nil
                case "f": self.findDocument(); return nil
                case "l": self.filterLibrary(); return nil
                case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                    if let index = Int(chars) { self.selectTab(index - 1); return nil }
                    return event
                default: return event
                }
            }
        }
    }
}

struct LeftSidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarRailView()
            VStack(alignment: .leading, spacing: 10) {
                SidebarHeaderView()
                switch model.sidebarMode {
                case .library: LibraryPaneView()
                case .workspaces: WorkspacePaneView()
                case .pins: PinsPaneView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 54)
            .padding(.bottom, 14)
            .background(AppTheme.sidebarBackground(model.selectedTheme))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppTheme.sidebarBorder(model.selectedTheme))
                    .frame(width: 1)
            }
        }
        .background(AppTheme.sidebarBackground(model.selectedTheme))
    }
}

struct SidebarRailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 54)
            RailButton(mode: .library, icon: "folder")
            RailButton(mode: .workspaces, icon: "square.grid.2x2")
            RailButton(mode: .pins, icon: "pin")
            Spacer()
            RailIconButton(icon: "magnifyingglass", help: "Command palette (⌘P)") { model.openPalette() }
            RailIconButton(icon: "gearshape", help: "Settings (⌘,)") { model.openSettings() }
            RailIconButton(icon: "questionmark.circle", help: "Help") { model.openHelp() }
        }
        .padding(.bottom, 16)
        .frame(width: ShellMetrics.railWidth)
        .background(AppTheme.railBackground(model.selectedTheme))
    }
}

struct SidebarTitlebarOverlay: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            AppTheme.railBackground(model.selectedTheme)
                .frame(width: ShellMetrics.railWidth)
            HStack(spacing: 10) {
                Button { model.openFolderPicker(additive: true) } label: {
                    Image(systemName: "folder.badge.plus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
                .help("Add folder (⇧⌘O)")
                Spacer()
                Button { model.sidebarCollapsed.toggle() } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
                .help("Toggle sidebar (⌘B)")
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.leading, 70)
            .padding(.trailing, 12)
            .background(AppTheme.sidebarBackground(model.selectedTheme))
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppTheme.sidebarBorder(model.selectedTheme))
                    .frame(width: 1)
            }
        }
        .frame(width: ShellMetrics.sidebarWidth, height: ShellMetrics.titlebarHeight)
    }
}

struct RailIconButton: View {
    @EnvironmentObject private var model: AppModel
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
                .frame(width: 38, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

struct RailButton: View {
    @EnvironmentObject private var model: AppModel
    let mode: SidebarMode
    let icon: String

    var body: some View {
        Button { model.sidebarMode = mode } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.sidebarMode == mode ? AppTheme.activeIcon(model.selectedTheme) : AppTheme.icon(model.selectedTheme))
                .frame(width: 38, height: 38)
                .background(model.sidebarMode == mode ? AppTheme.activeControlBackground(model.selectedTheme) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

enum AppTheme {
    static func isDark(_ theme: String) -> Bool {
        theme == "Graphite" || theme == "Midnight"
    }

    static func windowBackground(_ theme: String) -> Color {
        switch theme {
        case "Graphite": return Color(red: 0.18, green: 0.17, blue: 0.15)
        case "Midnight": return Color(red: 0.12, green: 0.15, blue: 0.18)
        case "Sepia": return Color(red: 0.95, green: 0.89, blue: 0.78)
        case "Paper": return Color(red: 1.0, green: 0.975, blue: 0.91)
        default: return Color(red: 0.985, green: 0.985, blue: 0.975)
        }
    }

    static func sidebarBackground(_ theme: String) -> Color {
        switch theme {
        case "Graphite": return Color(red: 0.22, green: 0.21, blue: 0.19)
        case "Midnight": return Color(red: 0.15, green: 0.18, blue: 0.21)
        case "Sepia": return Color(red: 0.91, green: 0.84, blue: 0.72)
        case "Paper": return Color(red: 0.96, green: 0.92, blue: 0.82)
        default: return Color(red: 0.905, green: 0.918, blue: 0.902)
        }
    }

    static func railBackground(_ theme: String) -> Color {
        switch theme {
        case "Graphite": return Color(red: 0.18, green: 0.17, blue: 0.15)
        case "Midnight": return Color(red: 0.12, green: 0.15, blue: 0.18)
        case "Sepia": return Color(red: 0.86, green: 0.78, blue: 0.66)
        case "Paper": return Color(red: 0.92, green: 0.86, blue: 0.74)
        default: return Color(red: 0.845, green: 0.87, blue: 0.84)
        }
    }

    static func sidebarBorder(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color.white.opacity(0.12)
        default: return Color(red: 0.62, green: 0.66, blue: 0.61).opacity(0.55)
        }
    }

    static func primaryText(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color.white.opacity(0.88)
        default: return Color(red: 0.18, green: 0.14, blue: 0.09)
        }
    }

    static func secondaryText(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color.white.opacity(0.68)
        default: return Color(red: 0.38, green: 0.31, blue: 0.22).opacity(0.72)
        }
    }

    static func icon(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color.white.opacity(0.70)
        default: return Color(red: 0.34, green: 0.30, blue: 0.24).opacity(0.82)
        }
    }

    static func activeIcon(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color(red: 0.73, green: 0.86, blue: 1.0)
        default: return Color(red: 0.42, green: 0.34, blue: 0.24)
        }
    }

    static func activeControlBackground(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color.white.opacity(0.12)
        default: return Color(red: 0.42, green: 0.34, blue: 0.24).opacity(0.11)
        }
    }

    static func controlBackground(_ theme: String) -> Color {
        switch theme {
        case "Graphite", "Midnight": return Color.white.opacity(0.07)
        default: return Color(nsColor: .controlBackgroundColor)
        }
    }
}

struct SidebarHeaderView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.sidebarMode == .library ? "Library" : model.sidebarMode == .pins ? "Pinned" : "Workspaces")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
            Text("\(model.activeRoots.count) folders · \(model.fileCount) Markdown files")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
            if model.sidebarMode == .library {
                TextField("Filter library", text: Binding(get: { model.query }, set: { model.updateLibraryQuery($0) }))
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
                    .help("Filter library (⌘L)")
                if model.isIndexing || !model.indexingMessage.isEmpty {
                    HStack(spacing: 6) {
                        if model.isIndexing { ProgressView().controlSize(.small) }
                        Text(model.indexingMessage)
                            .lineLimit(1)
                        if model.isIndexing {
                            Button { model.cancelIndexing() } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless)
                                .help("Cancel indexing")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                }
            } else if model.sidebarMode == .workspaces, let active = model.activeWorkspace {
                Text(active.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                    .lineLimit(1)
            }
        }
        .onChange(of: model.libraryFilterFocusRequestID) { _, _ in
            DispatchQueue.main.async { filterFocused = true }
        }
    }
}

struct LibraryPaneView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            if !model.pinnedFilesSnapshot.isEmpty {
                SectionLabel("PINNED")
                ForEach(model.pinnedFilesSnapshot.prefix(5)) { file in
                    FileRowView(file: file)
                        .contextMenu { FileContextMenu(file: file) }
                }
            }
            SectionLabel(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "FOLDERS" : "MATCHING FILES")
            List {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(model.activeRoots) { root in
                        RootNodeView(root: root)
                            .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                    }
                } else {
                    ForEach(model.visibleFilesSnapshot) { file in
                        FileRowView(file: file)
                            .contextMenu { FileContextMenu(file: file) }
                            .padding(.vertical, 2)
                            .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sidebarBackground(model.selectedTheme))
            .listStyle(.plain)
        }
    }
}

struct RootNodeView: View {
    @EnvironmentObject private var model: AppModel
    let root: RootFolder
    @State private var isExpanded = false
    @State private var children: LibraryChildren = .empty
    @State private var didLoadChildren = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                ForEach(children.folders) { folder in
                    FolderNodeView(folder: folder, rootID: root.id)
                        .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                }
                ForEach(children.files) { file in
                    FileRowView(file: file)
                        .contextMenu { FileContextMenu(file: file) }
                        .padding(.vertical, 2)
                        .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                }
                if children.folders.isEmpty && children.files.isEmpty {
                    Text(model.isIndexing ? "Indexing..." : "No Markdown files")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                        .padding(.leading, 8)
                }
            }
        } label: {
            Label(root.name, systemImage: "folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
        }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root.url]) }
            Button("Copy Folder Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(root.url.path, forType: .string)
            }
            Divider()
            Button("Remove Folder from Library") { model.removeRoot(root) }
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, !didLoadChildren else { return }
            didLoadChildren = true
            Task { children = await model.loadLibraryChildren(parentPath: nil, rootID: root.id) }
        }
        .onChange(of: model.fileCount) { _, _ in
            guard isExpanded else { return }
            Task { children = await model.loadLibraryChildren(parentPath: nil, rootID: root.id) }
        }
    }
}

struct FolderNodeView: View {
    @EnvironmentObject private var model: AppModel
    let folder: LibraryFolder
    let rootID: String
    @State private var isExpanded = false
    @State private var children: LibraryChildren = .empty
    @State private var didLoadChildren = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isExpanded {
                ForEach(children.folders) { folder in
                    FolderNodeView(folder: folder, rootID: rootID)
                        .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                }
                ForEach(children.files) { file in
                    FileRowView(file: file)
                        .contextMenu { FileContextMenu(file: file) }
                        .padding(.vertical, 2)
                        .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                }
            }
        } label: {
            Label(folder.name, systemImage: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
        }
        .onChange(of: isExpanded) { _, expanded in
            guard expanded, !didLoadChildren else { return }
            didLoadChildren = true
            Task { children = await model.loadLibraryChildren(parentPath: folder.path, rootID: rootID) }
        }
    }
}

struct WorkspacePaneView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("WORKSPACES")
                Button { model.refreshActiveWorkspace() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
                    .help("Refresh workspace folders")
                Button { model.createWorkspaceFromCurrentLibrary() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
                    .help("Create workspace from current folders")
            }

            HStack(spacing: 8) {
                TextField("New workspace", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWorkspace() }
                Button("Add") { addWorkspace() }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !model.workspaceRefreshMessage.isEmpty {
                Text(model.workspaceRefreshMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
            }

            List(model.workspaces) { workspace in
                WorkspaceRowView(workspace: workspace)
                    .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sidebarBackground(model.selectedTheme))
            .listStyle(.plain)

            Spacer()
        }
    }

    private func addWorkspace() {
        model.addWorkspace(named: draftName)
        draftName = ""
    }
}

struct WorkspaceRowView: View {
    @EnvironmentObject private var model: AppModel
    let workspace: WorkspaceItem
    @State private var isEditing = false
    @State private var draftName = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(isActive ? AppTheme.activeIcon(model.selectedTheme) : AppTheme.icon(model.selectedTheme))
            if isEditing {
                TextField("Workspace name", text: $draftName)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
                    .onSubmit { saveRename() }
            } else {
                Text(workspace.name)
                    .foregroundStyle(isActive ? AppTheme.primaryText(model.selectedTheme) : AppTheme.secondaryText(model.selectedTheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            if isEditing {
                Button { saveRename() } label: { Image(systemName: "checkmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
                Button { isEditing = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
            } else {
                Button { model.switchWorkspace(workspace) } label: {
                    Text(isActive ? "Active" : "Switch")
                        .font(.caption.weight(.semibold))
                        .frame(width: 52)
                }
                .buttonStyle(.borderless)
                .disabled(isActive)
                .help("Switch workspace")
                Button { beginRename() } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
                    .help("Rename workspace")
                Button { model.removeWorkspace(workspace) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
                    .disabled(model.workspaces.count <= 1)
                    .help("Remove workspace")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isActive ? AppTheme.activeControlBackground(model.selectedTheme) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contextMenu {
            Button("Switch to Workspace") { model.switchWorkspace(workspace) }
                .disabled(isActive)
            Button("Rename Workspace") { beginRename() }
            Button("Remove Workspace") { model.removeWorkspace(workspace) }
                .disabled(model.workspaces.count <= 1)
        }

        if isActive {
            VStack(alignment: .leading, spacing: 6) {
                Text("Folders")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                ForEach(model.roots) { root in
                    Toggle(isOn: Binding(
                        get: { workspace.rootIDs.contains(root.id) },
                        set: { _ in model.toggleRoot(root, in: workspace) }
                    )) {
                        Text(root.name)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                            .lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.leading, 26)
            .padding(.bottom, 8)
        }
    }

    private var isActive: Bool { model.activeWorkspaceID == workspace.id }

    private func beginRename() {
        draftName = workspace.name
        isEditing = true
    }

    private func saveRename() {
        model.renameWorkspace(workspace, to: draftName)
        isEditing = false
    }
}

struct PinsPaneView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            if model.pinnedFilesSnapshot.isEmpty {
                Text("No pinned files in this workspace")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                    .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
            } else {
                ForEach(model.pinnedFilesSnapshot, id: \.id) { file in
                    FileRowView(file: file)
                        .contextMenu { FileContextMenu(file: file) }
                        .listRowBackground(AppTheme.sidebarBackground(model.selectedTheme))
                }
            }
        }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sidebarBackground(model.selectedTheme))
            .listStyle(.plain)
    }
}

struct FileRowView: View {
    @EnvironmentObject private var model: AppModel
    let file: MarkdownFile

    var body: some View {
        Button { model.openFile(file) } label: {
            HStack(spacing: 8) {
                Image(systemName: model.isPinned(file) ? "pin.fill" : "doc.text")
                    .foregroundStyle(model.isPinned(file) ? .orange : AppTheme.secondaryText(model.selectedTheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title).lineLimit(1).foregroundStyle(AppTheme.primaryText(model.selectedTheme))
                    Text(file.relativePath).font(.caption).foregroundStyle(AppTheme.secondaryText(model.selectedTheme)).lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FileContextMenu: View {
    @EnvironmentObject private var model: AppModel
    let file: MarkdownFile
    var body: some View {
        Button("Open") { model.openFile(file) }
        Button(model.isPinned(file) ? "Unpin File" : "Pin File") { model.togglePin(file) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        Button("Copy Relative Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.relativePath, forType: .string) }
        Button("Copy Full Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.url.path, forType: .string) }
    }
}

struct AppStatusToast: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
            Text(message)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(AppTheme.controlBackground(model.selectedTheme).opacity(AppTheme.isDark(model.selectedTheme) ? 1 : 0.90))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(AppTheme.secondaryText(model.selectedTheme).opacity(0.18), lineWidth: 1) }
        .shadow(color: Color.black.opacity(AppTheme.isDark(model.selectedTheme) ? 0.20 : 0.08), radius: 12, x: 0, y: 6)
    }

    private var message: String {
        if model.readmdSettings.status != .ready { return "readmd setup needed" }
        return model.workspaceRefreshMessage
    }

    private var icon: String {
        model.readmdSettings.status == .ready ? "checkmark.circle" : "exclamationmark.triangle"
    }
}

struct SectionLabel: View {
    @EnvironmentObject private var model: AppModel
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReaderColumnView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ReaderView()
            }
            if model.documentFindOpen {
                DocumentFindBar()
                    .padding(.top, model.focusMode ? 18 : 60)
                    .padding(.trailing, 28)
                    .zIndex(12)
            }
            if model.contentsOpen {
                FloatingContentsView()
                    .padding(.top, model.documentFindOpen ? (model.focusMode ? 68 : 110) : (model.focusMode ? 18 : 60))
                    .padding(.trailing, 28)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
            ShortcutHintBar()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 18)
                .padding(.bottom, 12)
        }
    }
}

struct ReaderTopTabBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.sidebarCollapsed {
                Button { model.sidebarCollapsed.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help("Toggle sidebar (⌘B)")
                Button { model.openPalette() } label: { Image(systemName: "magnifyingglass") }
                    .help("Command palette (⌘P)")
            }
            ToolbarTabStripView()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(AppTheme.icon(model.selectedTheme))
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppTheme.windowBackground(model.selectedTheme))
    }
}

struct DocumentFindBar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
            TextField("Find in document", text: $model.documentFindQuery)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.findInDocument() }
                .frame(width: 220)
            Text(findStatusText)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                .frame(width: 56, alignment: .trailing)
            Button { model.findInDocument(backwards: true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
                .help("Previous match")
            Button { model.findInDocument() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
                .help("Next match")
            Button { model.closeDocumentFind() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.icon(model.selectedTheme))
                .help("Close find")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.controlBackground(model.selectedTheme).opacity(AppTheme.isDark(model.selectedTheme) ? 1 : 0.92))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.secondaryText(model.selectedTheme).opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(AppTheme.isDark(model.selectedTheme) ? 0.20 : 0.08), radius: 12, x: 0, y: 6)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onExitCommand { model.closeDocumentFind() }
    }

    private var findStatusText: String {
        guard !model.documentFindQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard model.documentFindStatus.total > 0 else { return "0/0" }
        return "\(model.documentFindStatus.current)/\(model.documentFindStatus.total)"
    }
}

struct ShortcutHintBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            if model.focusMode {
                ShortcutHint(keys: "⌘.", label: "Exit focus")
            } else {
                ShortcutHint(keys: "⌘J", label: "Contents")
                ShortcutHint(keys: "⌘⇧]", label: "Next tab")
                ShortcutHint(keys: "⌘.", label: "Focus")
                ShortcutHint(keys: "/", label: "Headings")
            }
        }
        .font(.caption2)
        .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.controlBackground(model.selectedTheme).opacity(AppTheme.isDark(model.selectedTheme) ? 1 : 0.72))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(AppTheme.secondaryText(model.selectedTheme).opacity(0.22), lineWidth: 1)
        }
        .opacity(model.focusMode ? 0.76 : 0.66)
    }
}

struct ShortcutHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys).fontWeight(.semibold)
            Text(label)
        }
    }
}

struct ToolbarTabStripView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            if model.tabs.isEmpty {
                Text("CalmPage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                    .frame(maxWidth: 520)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.tabs) { tab in
                            ToolbarTabChip(tab: tab)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: 28)
            }
        }
    }
}

struct ToolbarTabChip: View {
    @EnvironmentObject private var model: AppModel
    let tab: ReaderTab

    var body: some View {
        HStack(spacing: 4) {
            Button { model.activateTab(tab.id) } label: {
                HStack(spacing: 5) {
                    if model.isPinned(tab.file) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(tab.file.title)
                        .font(.system(size: 12, weight: model.activeTabID == tab.id ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 190)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.activeTabID == tab.id ? AppTheme.primaryText(model.selectedTheme) : AppTheme.secondaryText(model.selectedTheme))

            Button { model.closeTab(tab) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.icon(model.selectedTheme).opacity(0.72))
            .help("Close tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(model.activeTabID == tab.id ? AppTheme.activeControlBackground(model.selectedTheme) : AppTheme.controlBackground(model.selectedTheme).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppTheme.secondaryText(model.selectedTheme).opacity(model.activeTabID == tab.id ? 0.22 : 0.10), lineWidth: 1)
        }
        .help(tab.file.url.path)
        .contextMenu { FileContextMenu(file: tab.file) }
    }
}

struct TabStripView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.tabs) { tab in
                    HStack(spacing: 7) {
                        Button(tab.file.title) { model.activateTab(tab.id) }
                            .buttonStyle(.plain)
                            .foregroundStyle(model.activeTabID == tab.id ? AppTheme.primaryText(model.selectedTheme) : AppTheme.secondaryText(model.selectedTheme))
                            .lineLimit(1)
                        if model.pinnedFileIDs.contains(tab.file.id) { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                        Button { model.closeTab(tab) } label: { Image(systemName: "xmark").font(.caption) }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.icon(model.selectedTheme))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(model.activeTabID == tab.id ? AppTheme.activeControlBackground(model.selectedTheme) : AppTheme.controlBackground(model.selectedTheme))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contextMenu { FileContextMenu(file: tab.file) }
                }
            }
            .padding(8)
        }
        .frame(height: 46)
        .background(AppTheme.windowBackground(model.selectedTheme))
    }
}

struct ReaderView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scrollView: NSScrollView?

    var body: some View {
        Group {
            if case .loaded(let note) = model.readerState, !note.html.isEmpty {
                ReadmdHTMLView(
                    html: note.html,
                    headings: note.headings,
                    theme: model.selectedTheme,
                    headingTargetID: model.headingScrollTargetID,
                    scrollCommand: model.readerScrollCommand,
                    findRequest: model.documentFindRequest,
                    onFindStatusChange: { model.updateDocumentFindStatus(current: $0, total: $1) },
                    onActiveHeadingChange: { model.updateActiveHeading(id: $0) }
                )
                .background(ReaderVimKeyHandlingView(handle: model.handleReaderVimAction))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            switch model.readerState {
                            case .empty: EmptyReaderView()
                            case .loading(let title): ProgressView("Loading \(title)").frame(maxWidth: .infinity, minHeight: 360)
                            case .failed(let message): Text(message).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                            case .loaded(let note): ArticleView(note: note)
                            }
                        }
                        .frame(maxWidth: model.contentWidth)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 34)
                        .frame(maxWidth: .infinity)
                        .background(ReaderScrollResolver { scrollView = $0 })
                    }
                    .background(readerBackground)
                    .background(ReaderVimKeyHandlingView(handle: model.handleReaderVimAction))
                    .onChange(of: model.headingScrollTargetID) { _, target in
                        guard let target else { return }
                        withAnimation(.easeInOut(duration: 0.18)) { proxy.scrollTo(target, anchor: .top) }
                    }
                    .onChange(of: model.readerScrollCommand) { _, command in
                        guard let command else { return }
                        scrollView?.scrollBy(deltaY: command.deltaY)
                    }
                }
            }
        }
    }

    var readerBackground: Color {
        switch model.selectedTheme {
        case "Graphite": return Color(red: 0.09, green: 0.085, blue: 0.078)
        case "Polar": return Color(red: 0.98, green: 0.99, blue: 0.99)
        case "Midnight": return Color(red: 0.06, green: 0.09, blue: 0.12)
        default: return Color(red: 1.0, green: 0.98, blue: 0.94)
        }
    }

    var nsReaderBackground: NSColor {
        switch model.selectedTheme {
        case "Graphite": return NSColor(red: 0.09, green: 0.085, blue: 0.078, alpha: 1)
        case "Polar": return NSColor(red: 0.98, green: 0.99, blue: 0.99, alpha: 1)
        case "Midnight": return NSColor(red: 0.06, green: 0.09, blue: 0.12, alpha: 1)
        default: return NSColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        }
    }

    var nsArticleTextColor: NSColor {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return NSColor(red: 0.91, green: 0.89, blue: 0.84, alpha: 1)
        default: return NSColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1)
        }
    }
}

struct ReadmdHTMLView: NSViewRepresentable {
    let html: String
    let headings: [HeadingItem]
    let theme: String
    let headingTargetID: String?
    let scrollCommand: ReaderScrollCommand?
    let findRequest: DocumentFindRequest?
    let onFindStatusChange: (Int, Int) -> Void
    let onActiveHeadingChange: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "headingObserver")
        configuration.userContentController.add(context.coordinator, name: "findStatus")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(true, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.headings = headings
        webView.setValue(true, forKey: "drawsBackground")
        webView.layer?.backgroundColor = nsReaderBackground(theme).cgColor
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
        if context.coordinator.lastScrollCommandID != scrollCommand?.id {
            context.coordinator.lastScrollCommandID = scrollCommand?.id
            if let scrollCommand { webView.evaluateJavaScript("window.scrollBy({top: \(Int(scrollCommand.deltaY)), behavior: 'smooth'});") }
        }
        if context.coordinator.lastFindRequestID != findRequest?.id {
            context.coordinator.lastFindRequestID = findRequest?.id
            if let findRequest {
                let query = Self.javascriptStringLiteral(findRequest.query)
                webView.evaluateJavaScript("window.__calmpageFind && window.__calmpageFind(\(query), \(findRequest.backwards ? "true" : "false"));")
            }
        }
        if context.coordinator.lastHeadingTargetID != headingTargetID {
            context.coordinator.lastHeadingTargetID = headingTargetID
            if let headingTargetID, let index = headings.firstIndex(where: { $0.id == headingTargetID }) {
                webView.evaluateJavaScript("document.querySelectorAll('h1,h2,h3')[\(index)]?.scrollIntoView({behavior: 'smooth', block: 'start'});")
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(headings: headings, onFindStatusChange: onFindStatusChange, onActiveHeadingChange: onActiveHeadingChange) }

    private static func javascriptStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(encoded.dropFirst().dropLast())
    }

    private func nsReaderBackground(_ theme: String) -> NSColor {
        switch theme {
        case "White": return .white
        case "Graphite": return NSColor(red: 0.09, green: 0.085, blue: 0.078, alpha: 1)
        case "Polar": return NSColor(red: 0.98, green: 0.99, blue: 0.99, alpha: 1)
        case "Sepia": return NSColor(red: 0.98, green: 0.93, blue: 0.84, alpha: 1)
        case "Midnight": return NSColor(red: 0.06, green: 0.09, blue: 0.12, alpha: 1)
        default: return NSColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedHTML: String?
        var lastHeadingTargetID: String?
        var lastScrollCommandID: UUID?
        var lastFindRequestID: UUID?
        var headings: [HeadingItem]

        private let onFindStatusChange: (Int, Int) -> Void
        private let onActiveHeadingChange: (String) -> Void

        init(headings: [HeadingItem], onFindStatusChange: @escaping (Int, Int) -> Void, onActiveHeadingChange: @escaping (String) -> Void) {
            self.headings = headings
            self.onFindStatusChange = onFindStatusChange
            self.onActiveHeadingChange = onActiveHeadingChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = #"""
            (() => {
              const headings = Array.from(document.querySelectorAll('h1,h2,h3'));
              const send = () => {
                if (!headings.length) return;
                const current = headings.reduce((best, heading, index) => {
                  const top = heading.getBoundingClientRect().top;
                  if (top <= 120) return { index, top };
                  return best;
                }, { index: 0, top: -Infinity });
                window.webkit.messageHandlers.headingObserver.postMessage(String(current.index));
              };
              window.removeEventListener('scroll', window.__calmpageHeadingObserver);
              window.__calmpageHeadingObserver = () => window.requestAnimationFrame(send);
              window.addEventListener('scroll', window.__calmpageHeadingObserver, { passive: true });
              send();

              const style = document.createElement('style');
              style.textContent = 'mark.calmpage-find{background:rgba(255,210,74,.55);color:inherit;border-radius:3px;padding:0 1px}mark.calmpage-find.current{background:rgba(82,160,255,.70)}';
              document.head.appendChild(style);
              window.__calmpageFindIndex = -1;
              window.__calmpageFindOriginalHTML = null;
              window.__calmpageFind = (query, backwards) => {
                const root = document.querySelector('.reader') || document.body;
                if (window.__calmpageFindOriginalHTML !== null) root.innerHTML = window.__calmpageFindOriginalHTML;
                window.__calmpageFindOriginalHTML = root.innerHTML;
                if (!query) {
                  window.webkit.messageHandlers.findStatus.postMessage({current:0,total:0});
                  return;
                }
                const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                const regex = new RegExp(escaped, 'gi');
                root.innerHTML = root.innerHTML.replace(regex, match => `<mark class="calmpage-find">${match}</mark>`);
                const matches = Array.from(root.querySelectorAll('mark.calmpage-find'));
                if (!matches.length) {
                  window.__calmpageFindIndex = -1;
                  window.webkit.messageHandlers.findStatus.postMessage({current:0,total:0});
                  return;
                }
                window.__calmpageFindIndex = backwards
                  ? (window.__calmpageFindIndex <= 0 ? matches.length - 1 : window.__calmpageFindIndex - 1)
                  : (window.__calmpageFindIndex + 1) % matches.length;
                matches.forEach(mark => mark.classList.remove('current'));
                const current = matches[window.__calmpageFindIndex];
                current.classList.add('current');
                current.scrollIntoView({block:'center'});
                window.webkit.messageHandlers.findStatus.postMessage({current: window.__calmpageFindIndex + 1, total: matches.length});
              };
            })();
            """#
            webView.evaluateJavaScript(script)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "findStatus",
               let body = message.body as? [String: Any],
               let current = body["current"] as? Int,
               let total = body["total"] as? Int {
                Task { @MainActor in self.onFindStatusChange(current, total) }
                return
            }

            guard message.name == "headingObserver",
                  let rawIndex = message.body as? String,
                  let index = Int(rawIndex),
                  headings.indices.contains(index) else { return }
            let headingID = headings[index].id
            Task { @MainActor in
                onActiveHeadingChange(headingID)
            }
        }
    }
}

struct ArticleView: View {
    @EnvironmentObject private var model: AppModel
    let note: RenderedNote
    var body: some View {
        VStack(alignment: .leading, spacing: model.lineSpacing + 8) {
            ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let id, let level, let text):
            Text(text)
                .id(id)
                .font(.system(size: headingSize(level), weight: level == 1 ? .medium : .regular, design: .serif))
                .foregroundStyle(articleTextColor)
                .padding(.top, level == 1 ? 10 : 18)
        case .paragraph(let text):
            Text(text)
                .font(.system(size: model.fontSize, weight: .regular, design: .serif))
                .lineSpacing(model.lineSpacing)
                .foregroundStyle(articleTextColor)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundStyle(articleMutedColor)
                Text(text).font(.system(size: model.fontSize, design: .serif)).lineSpacing(model.lineSpacing)
            }
            .foregroundStyle(articleTextColor)
        case .quote(let text):
            Text(text)
                .font(.system(size: model.fontSize, weight: .regular, design: .serif).italic())
                .foregroundStyle(articleMutedColor)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(articleMutedColor.opacity(0.35)).frame(width: 3) }
        case .code(let text):
            Text(text)
                .font(.system(size: max(13, model.fontSize - 2), design: .monospaced))
                .foregroundStyle(articleTextColor)
                .padding(12)
                .background(codeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func headingSize(_ level: Int) -> Double {
        switch level {
        case 1: model.fontSize * 1.65
        case 2: model.fontSize * 1.30
        default: model.fontSize * 1.08
        }
    }

    private var articleTextColor: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color(red: 0.91, green: 0.89, blue: 0.84)
        default: return Color(red: 0.12, green: 0.10, blue: 0.08)
        }
    }

    private var articleMutedColor: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color(red: 0.70, green: 0.68, blue: 0.62)
        default: return Color(red: 0.43, green: 0.39, blue: 0.32)
        }
    }

    private var codeBackground: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.08)
        default: return Color.black.opacity(0.055)
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Contents").font(.headline)
                Spacer()
                Button { model.openTOCSearch() } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Search headings")
            }
            .padding(.top, 16)
            if let note = model.activeNote, !note.headings.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        HeadingOutlineList(headings: note.headings, selectedHeadingID: model.activeHeadingID)
                    }
                    .frame(maxHeight: 330)
                    .onChange(of: model.activeHeadingID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            } else {
                Text("No headings").font(.caption).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 6)
            Text("Note Info").font(.headline)
            if let tab = model.activeTab {
                Text(tab.file.relativePath).font(.caption).foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: tab.file.sizeBytes, countStyle: .file)).font(.caption)
                Button(model.pinnedFileIDs.contains(tab.file.id) ? "Unpin File" : "Pin File") { model.togglePin(tab.file) }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct FloatingContentsView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var selectedIndex = 0

    private var filteredHeadings: [HeadingItem] {
        guard let note = model.activeNote else { return [] }
        let query = model.contentsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return note.headings }
        return note.headings.filter { $0.title.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Contents")
                    .font(.headline)
                    .foregroundStyle(contentsText)
                Spacer()
                Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(contentsMutedText)
                    .help("Search headings")
                Button { model.contentsOpen = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(contentsMutedText)
                    .help("Close contents")
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(contentsMutedText)
                TextField("Search headings", text: $model.contentsSearchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .foregroundStyle(contentsText)
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(searchFocused ? contentsSearchFocusedBackground : contentsSearchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(searchFocused ? contentsFocusBorder : Color.clear, lineWidth: 1)
            }

            if !filteredHeadings.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        HeadingOutlineList(headings: filteredHeadings, selectedHeadingID: selectedHeadingID)
                    }
                    .onChange(of: model.activeHeadingID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: selectedHeadingID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            } else {
                Text("No headings").font(.caption).foregroundStyle(contentsMutedText)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 330, height: 430)
        .background(contentsBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(contentsBorder, lineWidth: 1)
        }
        .shadow(color: contentsShadow, radius: 16, x: 0, y: 8)
        .onChange(of: model.contentsSearchRequestID) { _, _ in
            focusSearchSoon()
            selectedIndex = 0
        }
        .onChange(of: model.contentsSearchQuery) { _, _ in selectedIndex = 0 }
        .onChange(of: filteredHeadings.count) { _, count in selectedIndex = min(selectedIndex, max(0, count - 1)) }
        .onAppear {
            if !model.contentsSearchQuery.isEmpty || model.contentsOpen { focusSearchSoon() }
        }
        .background(ContentsKeyHandlingView(
            moveUp: { moveSelection(-1) },
            moveDown: { moveSelection(1) },
            submit: { submitSelection() },
            cancel: { cancelContents() }
        ))
    }

    private var selectedHeadingID: String? {
        guard filteredHeadings.indices.contains(selectedIndex) else { return nil }
        return filteredHeadings[selectedIndex].id
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredHeadings.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), filteredHeadings.count - 1)
    }

    private func submitSelection() {
        guard filteredHeadings.indices.contains(selectedIndex) else { return }
        model.jumpToHeading(filteredHeadings[selectedIndex])
        model.contentsOpen = false
    }

    private func cancelContents() {
        if searchFocused || !model.contentsSearchQuery.isEmpty {
            searchFocused = false
            model.contentsSearchQuery = ""
        } else {
            model.contentsOpen = false
        }
    }

    private func focusSearchSoon() {
        DispatchQueue.main.async { searchFocused = true }
    }

    private var contentsBackground: Color {
        switch model.selectedTheme {
        case "Graphite": return Color(red: 0.13, green: 0.125, blue: 0.115).opacity(0.74)
        case "Midnight": return Color(red: 0.09, green: 0.12, blue: 0.15).opacity(0.74)
        case "Polar": return Color(red: 0.985, green: 0.99, blue: 0.99).opacity(0.76)
        default: return Color(red: 1.0, green: 0.975, blue: 0.91).opacity(0.76)
        }
    }

    private var contentsSearchBackground: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.06)
        default: return Color(red: 0.45, green: 0.35, blue: 0.22).opacity(0.055)
        }
    }

    private var contentsSearchFocusedBackground: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.10)
        default: return Color(red: 0.45, green: 0.35, blue: 0.22).opacity(0.09)
        }
    }

    private var contentsFocusBorder: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.20)
        default: return Color(red: 0.45, green: 0.35, blue: 0.22).opacity(0.22)
        }
    }

    private var contentsText: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.88)
        default: return Color(red: 0.18, green: 0.14, blue: 0.09)
        }
    }

    private var contentsMutedText: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.58)
        default: return Color(red: 0.38, green: 0.31, blue: 0.22).opacity(0.72)
        }
    }

    private var contentsBorder: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.10)
        default: return Color(red: 0.50, green: 0.42, blue: 0.31).opacity(0.18)
        }
    }

    private var contentsShadow: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.black.opacity(0.20)
        default: return Color(red: 0.30, green: 0.22, blue: 0.12).opacity(0.10)
        }
    }
}

struct HeadingOutlineList: View {
    @EnvironmentObject private var model: AppModel
    let headings: [HeadingItem]
    let selectedHeadingID: String?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(headings) { heading in
                Button { model.jumpToHeading(heading) } label: {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(indicatorColor(for: heading))
                            .frame(width: 2)
                        Text(heading.title)
                            .font(.system(size: max(12, 15 - Double(heading.level)), weight: rowIsEmphasized(heading) ? .medium : .regular))
                            .foregroundStyle(rowIsEmphasized(heading) ? activeText : inactiveText)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat((heading.level - 1) * 12))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .id(heading.id)
                .buttonStyle(.plain)
                .background(rowIsEmphasized(heading) ? activeBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func rowIsEmphasized(_ heading: HeadingItem) -> Bool {
        heading.id == selectedHeadingID || heading.id == model.activeHeadingID
    }

    private func indicatorColor(for heading: HeadingItem) -> Color {
        rowIsEmphasized(heading) ? activeIndicator : Color.clear
    }

    private var activeIndicator: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.38)
        default: return Color(red: 0.45, green: 0.35, blue: 0.22).opacity(0.42)
        }
    }

    private var activeText: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.86)
        default: return Color(red: 0.18, green: 0.14, blue: 0.09).opacity(0.90)
        }
    }

    private var inactiveText: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.56)
        default: return Color(red: 0.30, green: 0.24, blue: 0.17).opacity(0.72)
        }
    }

    private var activeBackground: Color {
        switch model.selectedTheme {
        case "Graphite", "Midnight": return Color.white.opacity(0.045)
        default: return Color(red: 0.45, green: 0.35, blue: 0.22).opacity(0.045)
        }
    }
}

struct ContentsKeyHandlingView: NSViewRepresentable {
    var moveUp: () -> Void
    var moveDown: () -> Void
    var submit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> ContentsKeyHandlingNSView {
        context.coordinator.installMonitor()
        return ContentsKeyHandlingNSView()
    }

    func updateNSView(_ nsView: ContentsKeyHandlingNSView, context: Context) {
        context.coordinator.moveUp = moveUp
        context.coordinator.moveDown = moveDown
        context.coordinator.submit = submit
        context.coordinator.cancel = cancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(moveUp: moveUp, moveDown: moveDown, submit: submit, cancel: cancel)
    }

    final class Coordinator {
        var moveUp: () -> Void
        var moveDown: () -> Void
        var submit: () -> Void
        var cancel: () -> Void
        private var monitor: Any?

        init(moveUp: @escaping () -> Void, moveDown: @escaping () -> Void, submit: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.moveUp = moveUp
            self.moveDown = moveDown
            self.submit = submit
            self.cancel = cancel
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 126: self.moveUp(); return nil
                case 125: self.moveDown(); return nil
                case 36: self.submit(); return nil
                case 53: self.cancel(); return nil
                default: return event
                }
            }
        }
    }
}

final class ContentsKeyHandlingNSView: NSView {}

struct ReaderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $model.settingsSection)
                .frame(width: 170)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(model.settingsSection.rawValue)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Done") { dismiss() }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                Divider()
                ScrollView {
                    settingsDetail
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: 720, height: 500)
        .background(AppTheme.windowBackground(model.selectedTheme))
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch model.settingsSection {
        case .reading: ReadingSettingsPane()
        case .library: LibrarySettingsPane()
        case .renderer: RendererSettingsPane()
        case .shortcuts: ShortcutsSettingsPane()
        }
    }
}

struct SettingsSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button { selection = section } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selection == section ? AppTheme.activeControlBackground(model.selectedTheme) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == section ? AppTheme.primaryText(model.selectedTheme) : AppTheme.secondaryText(model.selectedTheme))
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.sidebarBackground(model.selectedTheme))
    }
}

struct ReadingSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Theme", selection: Binding(get: { model.selectedTheme }, set: { model.updateReaderSettings(selectedTheme: $0) })) {
                ForEach(["Paper", "White", "Graphite", "Polar", "Sepia", "Midnight"], id: \.self) { Text($0) }
            }
            Picker("Readmd Style", selection: Binding(get: { model.selectedReadmdStyle }, set: { model.updateReaderSettings(selectedReadmdStyle: $0) })) {
                ForEach(["Editorial", "Notebook", "Technical", "Large"], id: \.self) { Text($0) }
            }
            SliderRow(title: "Font", value: Binding(get: { model.fontSize }, set: { model.updateReaderSettings(fontSize: $0) }), range: 14...28)
            SliderRow(title: "Line", value: Binding(get: { model.lineSpacing }, set: { model.updateReaderSettings(lineSpacing: $0) }), range: 4...16)
            SliderRow(title: "Width", value: Binding(get: { model.contentWidth }, set: { model.updateReaderSettings(contentWidth: $0) }), range: 560...1040)
            Button("Reset Reading Defaults") { model.resetReaderSize() }
        }
    }
}

struct LibrarySettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsInfoRow(title: "Workspace", value: model.activeWorkspace?.name ?? "None")
            SettingsInfoRow(title: "Folders", value: "\(model.activeRoots.count)")
            SettingsInfoRow(title: "Markdown files", value: "\(model.fileCount)")
            HStack {
                Button("Refresh Workspace") { model.refreshActiveWorkspace() }
                if model.isIndexing { ProgressView(value: model.indexingProgress).frame(width: 120) }
            }
            Text(model.indexingMessage.isEmpty ? "Refresh checks folders for new or changed Markdown files." : model.indexingMessage)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
        }
    }
}

struct RendererSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(statusTitle)
                    .font(.headline)
                Spacer()
                Button("Auto-detect") { model.autoDetectReadmd() }
                Button("Choose...") { model.chooseReadmdPath() }
            }
            SettingsInfoRow(title: "Current path", value: model.readmdSettings.resolvedPath ?? "Not set")
            SettingsInfoRow(title: "Version", value: model.readmdSettings.version.isEmpty ? "Unknown" : model.readmdSettings.version)
            Text(model.readmdSettings.message)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))

            Picker("Path Mode", selection: Binding(get: { model.readmdSettings.pathMode }, set: { mode in
                model.readmdSettings.pathMode = mode
                Task { await model.resolveReadmdPath() }
            })) {
                Text("Automatic").tag(ReadmdPathMode.automatic)
                Text("Custom").tag(ReadmdPathMode.custom)
            }
            .pickerStyle(.segmented)

            HStack {
                TextField("/opt/homebrew/bin/readmd", text: Binding(get: { model.readmdSettings.customPath }, set: { model.readmdSettings.customPath = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.readmdSettings.pathMode != .custom)
                Button("Test") { Task { await model.resolveReadmdPath() } }
            }

            Divider().padding(.vertical, 4)
            Text("Install readmd")
                .font(.headline)
            Text("Install or build readmd, then use Auto-detect or Choose. If readmd is missing, CalmPage still opens but uses fallback rendering.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
            HStack {
                Button("Copy Install Hint") { copyInstallHint() }
                Button("Open Renderer Settings") { model.settingsSection = .renderer }
            }
        }
    }

    private var statusTitle: String {
        switch model.readmdSettings.status {
        case .ready: return "readmd ready"
        case .missing: return "readmd missing"
        case .invalid: return "readmd invalid"
        }
    }

    private var statusColor: Color {
        switch model.readmdSettings.status {
        case .ready: return .green
        case .missing: return .orange
        case .invalid: return .red
        }
    }

    private func copyInstallHint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("cargo install --path /path/to/readmd", forType: .string)
    }
}

struct ShortcutsSettingsPane: View {
    private let shortcuts = [
        ("⌘P", "Command palette"), ("⌘F", "Find in document"), ("⌘L", "Filter library"),
        ("⌘J", "Toggle contents"), ("/", "Search headings"), ("⌘B", "Toggle sidebar"),
        ("⌘.", "Focus mode"), ("⌘⇧]", "Next tab"), ("⌘⇧[", "Previous tab"),
        ("⌘1-⌘9", "Select tab"), ("⌘W", "Close tab")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(shortcuts, id: \.0) { key, label in
                HStack {
                    Text(key).font(.system(.body, design: .monospaced)).frame(width: 80, alignment: .leading)
                    Text(label)
                    Spacer()
                }
            }
        }
    }
}

struct SettingsInfoRow: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title).frame(width: 48, alignment: .leading)
            Slider(value: $value, in: range)
            Text("\(Int(value))").foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }
    }
}

struct ReaderStyleMenu: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Menu {
            Picker("Theme", selection: Binding(get: { model.selectedTheme }, set: { model.updateReaderSettings(selectedTheme: $0) })) {
                ForEach(["Paper", "White", "Graphite", "Polar", "Sepia", "Midnight"], id: \.self) { Text($0) }
            }
            Picker("Style", selection: Binding(get: { model.selectedReadmdStyle }, set: { model.updateReaderSettings(selectedReadmdStyle: $0) })) {
                ForEach(["Editorial", "Notebook", "Technical", "Large"], id: \.self) { Text($0) }
            }
            Slider(value: Binding(get: { model.fontSize }, set: { model.updateReaderSettings(fontSize: $0) }), in: 14...24) { Text("Font Size") }
            Slider(value: Binding(get: { model.contentWidth }, set: { model.updateReaderSettings(contentWidth: $0) }), in: 560...980) { Text("Width") }
            Button("Reset Typography") { model.resetReaderSize() }
            Divider()
            Button("More Settings...") { model.openSettings() }
        } label: {
            Image(systemName: "textformat.size")
        }
        .help("Reader style")
        .controlSize(.small)
    }
}

struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search files, commands, headings...", text: Binding(get: { model.paletteQuery }, set: { model.updatePaletteQuery($0) }))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { runSelected() }
            }
            .padding(16)
            Divider()
            PaletteHelpStrip()
            List(Array(model.paletteItemsSnapshot.enumerated()), id: \.element.id) { index, item in
                Button {
                    if case .status = item.kind { return }
                    model.runPaletteItem(item)
                    model.paletteOpen = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol).frame(width: 22)
                            .foregroundStyle(itemColor(item))
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isStatus(item))
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .frame(width: 680, height: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 16)
        .background(PaletteKeyHandlingView(
            moveUp: { moveUp() },
            moveDown: { moveDown() },
            submit: { runSelected() },
            cancel: { model.paletteOpen = false }
        ))
        .onAppear { focused = true; selectedIndex = 0 }
        .onChange(of: model.paletteQuery) { _, _ in selectedIndex = 0 }
        .onChange(of: model.paletteItemsSnapshot.count) { _, count in
            selectedIndex = PaletteSelection.clamped(selectedIndex, count: count)
            if model.paletteItemsSnapshot.indices.contains(selectedIndex), isStatus(model.paletteItemsSnapshot[selectedIndex]) {
                selectedIndex = nextActionableIndex(from: selectedIndex, direction: 1)
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .down: moveDown()
            case .up: moveUp()
            default: break
            }
        }
        .onExitCommand { model.paletteOpen = false }
    }

    private func moveUp() {
        selectedIndex = nextActionableIndex(from: selectedIndex, direction: -1)
    }

    private func moveDown() {
        selectedIndex = nextActionableIndex(from: selectedIndex, direction: 1)
    }

    private func runSelected() {
        let items = model.paletteItemsSnapshot
        let index = PaletteSelection.clamped(selectedIndex, count: items.count)
        guard items.indices.contains(index), !isStatus(items[index]) else { return }
        model.runPaletteItem(items[index])
        model.paletteOpen = false
    }

    private func nextActionableIndex(from index: Int, direction: Int) -> Int {
        let items = model.paletteItemsSnapshot
        guard !items.isEmpty else { return 0 }
        var next = PaletteSelection.clamped(index + direction, count: items.count)
        while items.indices.contains(next), isStatus(items[next]) {
            let advanced = next + direction
            guard items.indices.contains(advanced) else { break }
            next = advanced
        }
        return next
    }

    private func itemColor(_ item: PaletteItem) -> Color {
        if case .status = item.kind { return AppTheme.secondaryText(model.selectedTheme) }
        return AppTheme.icon(model.selectedTheme)
    }

    private func isStatus(_ item: PaletteItem) -> Bool {
        if case .status = item.kind { return true }
        return false
    }
}

struct HelpPanelView: View {
    @EnvironmentObject private var model: AppModel

    private let shortcuts = [
        ("⌘P", "Command palette"),
        ("⌘F", "Find in document"),
        ("⌘L", "Filter library"),
        ("⌘J", "Toggle contents"),
        ("/", "Search headings"),
        ("⌘B", "Toggle sidebar"),
        ("⌘.", "Focus mode"),
        ("⌘⇧]", "Next tab"),
        ("⌘⇧[", "Previous tab"),
        ("⌘1-⌘9", "Select tab"),
        ("⌘W", "Close tab")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Help")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
                Spacer()
                Button { model.helpOpen = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.icon(model.selectedTheme))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcuts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                ForEach(shortcuts, id: \.0) { key, label in
                    HelpRow(left: key, right: label)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Command Palette Prefixes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
                ForEach(AppModel.paletteHelpItems) { item in
                    HelpRow(left: item.prefix, right: item.title)
                }
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(AppTheme.sidebarBackground(model.selectedTheme))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.secondaryText(model.selectedTheme).opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(AppTheme.isDark(model.selectedTheme) ? 0.28 : 0.14), radius: 24, x: 0, y: 14)
        .onExitCommand { model.helpOpen = false }
    }
}

struct HelpRow: View {
    @EnvironmentObject private var model: AppModel
    let left: String
    let right: String

    var body: some View {
        HStack(spacing: 12) {
            Text(left)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText(model.selectedTheme))
                .frame(width: 48, alignment: .leading)
            Text(right)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryText(model.selectedTheme))
            Spacer()
        }
    }
}

struct PaletteHelpStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppModel.paletteHelpItems) { item in
                Text("\(item.prefix) \(item.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

struct PaletteKeyHandlingView: NSViewRepresentable {
    var moveUp: () -> Void
    var moveDown: () -> Void
    var submit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> PaletteKeyHandlingNSView {
        context.coordinator.installMonitor()
        return PaletteKeyHandlingNSView()
    }

    func updateNSView(_ nsView: PaletteKeyHandlingNSView, context: Context) {
        context.coordinator.moveUp = moveUp
        context.coordinator.moveDown = moveDown
        context.coordinator.submit = submit
        context.coordinator.cancel = cancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(moveUp: moveUp, moveDown: moveDown, submit: submit, cancel: cancel)
    }

    final class Coordinator {
        var moveUp: () -> Void
        var moveDown: () -> Void
        var submit: () -> Void
        var cancel: () -> Void
        private var monitor: Any?

        init(moveUp: @escaping () -> Void, moveDown: @escaping () -> Void, submit: @escaping () -> Void, cancel: @escaping () -> Void) {
            self.moveUp = moveUp
            self.moveDown = moveDown
            self.submit = submit
            self.cancel = cancel
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 125:
                    self.moveDown()
                    return nil
                case 126:
                    self.moveUp()
                    return nil
                case 38:
                    self.moveDown()
                    return nil
                case 40:
                    self.moveUp()
                    return nil
                case 36, 76:
                    self.submit()
                    return nil
                case 53:
                    self.cancel()
                    return nil
                default:
                    return event
                }
            }
        }
    }
}

final class PaletteKeyHandlingNSView: NSView {}

struct ReaderScrollResolver: NSViewRepresentable {
    var onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> ReaderScrollResolverView {
        let view = ReaderScrollResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: ReaderScrollResolverView, context: Context) {
        nsView.onResolve = onResolve
        DispatchQueue.main.async { nsView.resolve() }
    }
}

final class ReaderScrollResolverView: NSView {
    var onResolve: ((NSScrollView?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolve()
    }

    func resolve() {
        var parent = superview
        while let view = parent {
            if let scrollView = view as? NSScrollView {
                onResolve?(scrollView)
                return
            }
            parent = view.superview
        }
        onResolve?(nil)
    }
}

private extension NSScrollView {
    func scrollBy(deltaY: CGFloat) {
        let current = contentView.bounds.origin
        let documentHeight = documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - contentView.bounds.height)
        let nextY = min(max(current.y + deltaY, 0), maxY)
        contentView.scroll(to: CGPoint(x: current.x, y: nextY))
        reflectScrolledClipView(contentView)
    }
}

struct ReaderVimKeyHandlingView: NSViewRepresentable {
    var handle: (ReaderVimAction) -> Void

    func makeNSView(context: Context) -> ReaderVimKeyHandlingNSView {
        context.coordinator.installMonitor()
        return ReaderVimKeyHandlingNSView()
    }

    func updateNSView(_ nsView: ReaderVimKeyHandlingNSView, context: Context) {
        context.coordinator.handle = handle
    }

    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }

    final class Coordinator {
        var handle: (ReaderVimAction) -> Void
        private var monitor: Any?

        init(handle: @escaping (ReaderVimAction) -> Void) { self.handle = handle }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let chars = event.charactersIgnoringModifiers, !event.modifierFlags.contains(.command) else { return event }
                if event.window?.firstResponder is NSTextView { return event }
                switch chars {
                case "j": self.handle(.down); return nil
                case "k": self.handle(.up); return nil
                case "/": self.handle(.searchTOC); return nil
                default: return event
                }
            }
        }
    }
}

final class ReaderVimKeyHandlingNSView: NSView {}

struct EmptyReaderView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Open a folder, then choose a Markdown file.").font(.title3).foregroundStyle(.secondary)
            Button("Add Folder") { model.openFolderPicker(additive: true) }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
