# CalmPage Feature Inventory

## Purpose

- Markdown reader for local folders
  - focused on reading, not editing
  - optimized for AI-generated notes, docs, and local vaults

## File Sources

- Folder library
  - open one folder
  - open many folders
  - add folder to existing library
  - remove folder
  - save folder list locally
  - restore folders on app start
- File types
  - `.md`
  - `.markdown`
  - `.mdx`
- File watching
  - watch added folders
  - update file list when Markdown changes
  - refresh open tabs when changed files are open

## Library UI

- Sidebar library
  - root folders
  - nested folders
  - Markdown file rows
  - collapsed/expanded folder state
  - virtualized visible rows for large lists
- File actions
  - open file
  - reveal file in library
  - copy relative path
  - copy full path
  - pin/unpin file
- Folder actions
  - copy root path
  - copy root name/path label
  - remove folder

## Reading

- Markdown render
  - rendered by Rust backend
  - sanitized safe HTML
  - frontmatter rendered as document details
  - tables
  - footnotes
  - strikethrough
  - task lists
  - heading attributes
  - optional preserve whitespace mode
- Reader view
  - styled article area
  - code blocks
  - inline code
  - blockquotes
  - tables
  - links
  - marks for find results
- Scroll state
  - save tab scroll position
  - restore scroll on tab switch
  - restore scroll after app restart

## Tabs

- Open tabs
  - open note in tab
  - activate tab
  - close current tab
  - close all tabs
  - move between tabs
  - horizontal tab strip
  - scroll tab strip
- Low-memory tab behavior
  - keep active note HTML only
  - unload inactive tab HTML
  - restore inactive tabs as metadata
  - render unloaded tab on click
- Tab persistence
  - save open tabs
  - save active tab
  - save scroll position

## Search And Navigation

- Library search
  - filter visible library files
  - search by title/path
- Command palette
  - search actions
  - search files
  - search tabs
  - search headings
  - search settings
  - search workspaces
  - search pinned files
  - support prefixes
    - `>` actions
    - `/` files
    - `@` tabs
    - `#` headings
    - `?` settings
    - `:` workspaces
    - `!` pinned files
- Missing file lookup
  - paste path into palette
  - direct path match
  - nearby folder scan
  - avoids full root scan for plain text
- In-note find
  - find query
  - highlight matches
  - active match
  - next/previous match

## Table Of Contents

- TOC extraction
  - parse current rendered HTML
  - collect `h1`, `h2`, `h3`
  - limit headings
- TOC UI
  - show/hide TOC
  - floating TOC panel
  - search headings
  - jump to heading
  - selected heading state

## Focus Mode

- Focus reading
  - hide sidebar noise
  - hide/collapse TOC by default
  - floating reader actions
  - focus mode toast
  - exit hint
- Keyboard reading
  - arrow navigation
  - `J` / `K` navigation
  - `/` heading search in focus mode

## Workspaces

- Workspace list
  - default workspace
  - create workspace
  - rename workspace
  - duplicate workspace
  - delete workspace
  - switch workspace
- Workspace folders
  - assign root folders to workspace
  - active workspace root filter
  - file count per workspace
  - save workspaces locally

## Pinned Files

- Pin file
  - from file menu
  - from tab menu
- Pinned UI
  - pinned files group
  - pinned tab indicator
  - pinned palette search
- Persistence
  - save pinned files locally

## Settings

- Appearance
  - light/dark mode
  - color preset
  - reader preset
  - custom theme presets
- Reader controls
  - font size
  - line height
  - content width
  - heading scale
  - paragraph spacing
  - code scale
  - preserve Markdown whitespace
- Settings panels
  - general
  - shortcuts
  - files
  - appearance
  - table of contents
  - markdown
  - advanced
- Config tools
  - copy preset config
  - apply preset config JSON

## Onboarding And Help

- Shortcut HUD
  - show shortcuts with `?`
  - restart walkthrough
- Guided tour
  - first-run onboarding
  - step highlight
  - next/previous/skip
  - saved seen state

## Backend And Storage

- Rust backend commands
  - open vaults
  - add vault
  - remove vault
  - get vault
  - refresh vault snapshot
  - search files
  - find missing files
  - render note
  - render saved note
  - open external Markdown file
  - memory debug info
- Disk cache
  - rendered HTML cache
  - cache size limit
  - stale cache cleanup
- SQLite index
  - metadata search index
  - file path/title search
  - background indexing
  - fallback to memory search

## Packaging

- macOS app
  - Tauri bundle
  - file association for Markdown
  - installed as `CalmPage.app`
- Release artifacts
  - `.app`
  - `.dmg`

