# CalmPage Apple Native UI Design Spec

## Summary

- Design the native app before rebuilding features.
- Keep the old CalmPage workflow, but make it feel like a real macOS app.
- Main goal: reading first, fast folder handling, no UI hang.
- Visual direction: quiet Apple-native reader, dense where needed, beautiful typography in the article.

## Terms/context

- Sidebar
  - left panel for folders, workspaces, pinned files, and file tree.
- Inspector
  - right panel for table of contents and note details.
- Command palette
  - fast search box for actions, files, tabs, headings, settings.
- Indexing
  - app scans folders and stores file metadata in SQLite.
- Metadata
  - small file info: path, title, size, modified time. Not full note body.
- Virtual list
  - list renders only visible rows, so large vaults stay fast.

## Design principles

- Native first
  - use `NavigationSplitView`, `Table/List`, `NSTextView`, `NSOutlineView`, `Inspector`, `Toolbar`, `Menu`, `Sheet`, `Popover`.
  - avoid web-style cards and heavy decoration.
- Reading first
  - article gets the most visual care.
  - controls stay quiet until needed.
- Fast by design
  - adding a folder must never block the main window.
  - scanner runs in background.
  - first results appear quickly.
  - full count and title enrichment can finish later.
- Memory light
  - inactive tabs keep path/title/scroll only.
  - active note only has rendered content.
  - no all-body in-memory list.
- Keyboard strong
  - command palette is the main power-user path.
  - every major action has menu + shortcut.

## App layout

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Toolbar: Sidebar | Workspace | Search/Palette | Reader Controls       │
├───────────────┬────────────────────────────────────────────┬─────────┤
│ Left Sidebar  │ Main Reader                                │ Inspector│
│               │                                            │         │
│ Rail          │ Tab bar                                    │ TOC     │
│ Library       │ Article                                    │ Details │
│ Workspaces    │                                            │ Find    │
│ Pins          │                                            │         │
└───────────────┴────────────────────────────────────────────┴─────────┘
```

## Window regions

- Toolbar
  - sidebar toggle
  - active workspace menu
  - quick open field button
  - add folder progress pill
  - reader style popover
  - inspector toggle
- Left sidebar
  - narrow rail for modes: Library, Workspaces, Pins.
  - content area changes by selected rail mode.
  - resizable width: `240` to `420` pt.
- Main reader
  - tab strip above article.
  - article scroll area.
  - empty state when no note is open.
- Right inspector
  - table of contents.
  - note info.
  - find results.
  - hidden by default when screen is narrow.

## Toolbar design

- Left side
  - sidebar icon button.
  - workspace picker as native menu button.
- Center
  - command palette trigger styled like Spotlight field.
  - text: `Search files, commands, headings`.
- Right side
  - typography popover button.
  - theme popover button.
  - inspector toggle.
- Status
  - folder indexing appears as a small progress pill.
  - example: `Indexing 1,240 files...` with cancel button.
  - status must not block reader.

## Left sidebar: Library mode

- Top
  - search field.
  - small folder count and file count.
- Body
  - native outline tree.
  - root folders first.
  - nested folders.
  - Markdown files.
  - pinned files can show as a small section above tree.
- Row design
  - folder row: disclosure chevron, folder icon, name, count.
  - file row: doc icon, title, muted relative path.
  - active file row uses Apple selection highlight.
- Context menu
  - Open.
  - Reveal in Finder.
  - Copy Relative Path.
  - Copy Full Path.
  - Pin/Unpin.
  - Remove Folder for root rows.

## Left sidebar: Workspaces mode

- Shows workspace list.
- Each workspace row:
  - name.
  - folder count.
  - file count.
- Actions:
  - create workspace.
  - rename.
  - duplicate.
  - delete.
  - assign folders.
- Switching workspace filters the library instantly using indexed metadata.

## Left sidebar: Pins mode

- Shows pinned files grouped by workspace/root.
- Row actions:
  - open.
  - unpin.
  - reveal in library.

## Add folder flow

- User action
  - `File > Add Folder...`
  - toolbar `+ Folder`.
  - sidebar footer button.
- Immediate UI response
  - folder appears in sidebar as `Indexing...`.
  - progress pill appears in toolbar.
  - app remains usable.
- Background work phases
  - Phase 1: collect paths and file metadata.
  - Phase 2: write metadata to SQLite in batches.
  - Phase 3: update visible tree in chunks.
  - Phase 4: enrich titles for small files only.
  - Phase 5: watch folder for future changes.
- Cancel behavior
  - user can cancel indexing.
  - already indexed files remain usable.
- Error behavior
  - permission error shown on folder row.
  - app does not freeze.

## Main reader

- Empty state
  - simple native empty view.
  - primary action: Open Folder.
  - secondary action: Open Markdown File.
- Tab bar
  - horizontal native-style tabs.
  - close button appears on hover/active.
  - pinned marker if file is pinned.
  - inactive tabs have no rendered body in memory.
- Article
  - `NSTextView` or custom native block renderer.
  - no WebView.
  - default content width: `680` to `760` pt.
  - body font: `New York` or `Iowan Old Style` fallback.
  - code font: `SF Mono`.
  - default body size: `17` pt.
  - default line height: around `1.6`.
- Reading controls
  - typography popover, not always visible sliders.
  - presets: Editorial, Notebook, Technical, Large.
  - width, font size, line height, paragraph spacing.

## Right inspector

- Default tab: Contents.
- Contents tab
  - `h1`, `h2`, `h3` headings.
  - current heading highlight.
  - search field when heading count is high.
- Info tab
  - file name.
  - relative path.
  - size.
  - modified time.
  - root folder.
- Find tab
  - current note search.
  - match count.
  - next/previous.

## Command palette

- Opens with `Cmd+P`.
- Native floating panel centered near top.
- Prefix modes from old app stay:
  - `>` actions.
  - `/` files.
  - `@` tabs.
  - `#` headings.
  - `?` settings.
  - `:` workspaces.
  - `!` pinned files.
- Results grouped:
  - Open Tabs.
  - Pinned Files.
  - Files.
  - Headings.
  - Actions.
  - Settings.
  - Workspaces.
- Performance rule
  - palette reads SQLite metadata.
  - no folder scan while typing.
  - missing file lookup is explicit and cancellable.

## Focus mode

- Shortcut: `Cmd+.`.
- Hides sidebar, tab bar, and inspector.
- Keeps a tiny floating control strip:
  - exit focus.
  - contents search.
  - typography.
- Keyboard reading:
  - `J` / `K` scroll.
  - `/` heading search.
  - `G` bottom, `g` top.

## Settings design

- Use native Settings window.
- Tabs:
  - General.
  - Files.
  - Appearance.
  - Reading.
  - Shortcuts.
  - Advanced.
- Avoid giant custom settings modal.
- Preview typography changes in a small native preview pane.

## Visual style

- Overall
  - refined Apple utility app.
  - quiet chrome.
  - article is warm and book-like.
- Color presets
  - Paper.
  - Graphite.
  - Polar.
  - Sepia.
  - Midnight.
- Native mapping
  - use system materials for sidebars/toolbars.
  - use custom article background only inside reader.
  - use Apple selection colors for lists.
- Avoid
  - nested cards.
  - heavy gradients.
  - marketing page feel.
  - sliders always visible in toolbar.

## Key shortcuts

- `Cmd+O`: open folder.
- `Cmd+Shift+O`: add folder.
- `Cmd+P`: command palette.
- `Cmd+B`: toggle sidebar.
- `Cmd+J`: toggle inspector/TOC.
- `Cmd+W`: close current tab.
- `Cmd+Shift+W`: close all tabs.
- `Cmd+F`: find in note.
- `Cmd+,`: settings.
- `Cmd+.`: focus mode.

## Native component map

- App shell
  - `NavigationSplitView` or AppKit `NSSplitViewController`.
- File tree
  - AppKit `NSOutlineView` for large vaults.
- File list search
  - `NSSearchField`.
- Reader
  - Milestone 1: `NSTextView` with attributed text.
  - Milestone 2: custom native block view if needed.
- Tabs
  - custom SwiftUI/AppKit tab strip.
- Command palette
  - borderless `NSPanel`.
- Inspector
  - SwiftUI inspector pane or split child pane.
- Settings
  - native `Settings` scene.

## Required user flows

- First run
  - window opens instantly.
  - no folder scanning.
  - user can open folder or open single Markdown file.
- Add folder
  - no hang.
  - progress appears.
  - partial file list appears quickly.
- Open note
  - note renders without blocking file tree.
  - old active note content is released when tab closes.
- Switch tab
  - save scroll.
  - load selected note on demand.
- Search file
  - uses SQLite metadata.
  - instant for indexed files.
- Change file on disk
  - watcher updates metadata.
  - active open note refreshes only if that file changed.

## Implementation order after UI design

- Step 1: Build static native shell with fake data.
- Step 2: Validate layout and interactions with screenshots.
- Step 3: Add background folder indexing with progress.
- Step 4: Add SQLite-backed library tree.
- Step 5: Add native reader rendering.
- Step 6: Add tabs and scroll restore.
- Step 7: Add command palette.
- Step 8: Add workspaces, pins, settings.
- Step 9: Performance pass with large vault.

## UI acceptance checks

- App window appears instantly.
- Adding a folder never blocks clicking, scrolling, or closing window.
- Sidebar can show `10,000` files with smooth scroll.
- Reader typography looks good before settings are touched.
- Command palette opens under `100 ms`.
- Focus mode leaves only reading controls.
- All old CalmPage workflows have a native location.
