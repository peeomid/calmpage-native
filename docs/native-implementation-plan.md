# CalmPage Native Implementation Plan

## Summary

- Build CalmPage Native as a new macOS app.
- Keep the current CalmPage features, but remove the browser/WebView layer.
- Use `readmd` as the shared Rust Markdown engine.
- Keep memory low with a disk-first design.

## Terms/context

- Native app
  - app uses macOS UI directly
  - no embedded browser for the main reader
- Rust core
  - shared Rust code for Markdown, scanning, cache, and index work
- Disk-first
  - store large data on disk
  - keep only small active data in memory
- Attributed text
  - macOS rich text object
  - can show headings, bold text, links, and code-like styling without a browser DOM

## Target Stack

- App shell
  - SwiftUI
  - window layout
  - settings
  - simple panels
- Native controls
  - AppKit where SwiftUI is too heavy or too limited
  - file tree
  - reader view
  - command palette if needed
- Core engine
  - Rust
  - `readmd` / future `readmd-core`
  - SQLite metadata index
- Storage
  - SQLite for metadata
  - JSON/TOML for small settings if simpler
  - temp/cache folder for rendered note files

## Main Architecture

- UI layer
  - shows folders, files, tabs, reader, TOC, palette, settings
  - never owns all Markdown bodies
  - only owns active note display state
- App model layer
  - active workspace
  - open tabs as metadata
  - selected file
  - current note title/path/scroll
- Rust service layer
  - scan folders
  - detect Markdown files
  - build metadata index
  - render active note
  - extract headings
  - write/read render cache
- Storage layer
  - `files` table for title/path/root/mtime/size
  - `folders` table for roots
  - `tabs` restore state
  - `pins` table or JSON list
  - no full Markdown body index by default

## Memory Rules

- Keep in memory
  - visible file rows
  - active tab content
  - active TOC
  - small settings
  - recent search results
- Keep on disk
  - rendered HTML or native cache output
  - metadata index
  - tab restore state
  - workspace state
  - pinned files
- Do not keep by default
  - every Markdown body
  - every rendered note
  - full-text body index
  - inactive tab content

## Phase 0: Repo Foundation

- Create repo skeleton
  - README
  - docs
  - prototype folders
  - measurement notes
- Move planning docs from Tauri repo
  - feature inventory
  - architecture options
  - spike plan
- Add baseline memory target doc
  - cold start target
  - folder loaded target
  - note open target
  - close-tab release target

## Phase 1: Spike

- AppKit/SwiftUI prototype
  - open folder
  - list Markdown files
  - open one note
  - call `readmd` CLI first
  - show rendered note in native reader
  - show TOC
  - open two tabs
  - close tab and release note content
- Slint prototype
  - same feature slice
  - use Rust code directly
  - compare reader complexity
- Measure both
  - cold start
  - folder loaded
  - normal note
  - huge note
  - two tabs
  - after close all tabs

## Phase 2: Pick Final Stack

- Pick AppKit/SwiftUI if
  - memory is clearly lowest
  - reader quality is good
  - implementation feels direct
- Pick Slint if
  - memory is close to AppKit
  - Rust-only development is faster
  - custom reader is not too much work
- Stay on Tauri if
  - native savings are too small
  - rewrite cost is too high

## Phase 3: Rust Core

- Create or refine `readmd-core`
  - render Markdown to safe HTML
  - extract title
  - extract frontmatter
  - extract headings
  - expose stable options for theme/style
- Add native-friendly output later
  - heading blocks
  - paragraph blocks
  - code blocks
  - table blocks
  - link spans
- Keep CLI thin
  - `readmd` calls `readmd-core`
  - CalmPage Native also calls `readmd-core`

## Phase 4: App Shell

- Window layout
  - sidebar
  - tab bar
  - reader pane
  - optional TOC pane
- Folder workflow
  - open folder
  - add folder
  - remove folder
  - restore folders on launch
- File tree
  - nested folders
  - virtualized rows if needed
  - collapsed/expanded state
  - file actions

## Phase 5: Reader

- First reader
  - render Markdown with `readmd`
  - convert HTML to native rich text if acceptable
  - display active note only
- Better reader
  - use native block model
  - render headings, paragraphs, code, lists, tables with native views
  - better memory control than HTML import
- Reader features
  - scroll restore
  - links
  - code blocks
  - tables
  - frontmatter block
  - find in note
  - TOC jump

## Phase 6: Tabs And State

- Tabs
  - open note
  - activate tab
  - close tab
  - close all tabs
  - restore tabs on launch
- Low-memory behavior
  - inactive tabs keep path/title/scroll only
  - active note content loads on demand
  - close tab releases reader content

## Phase 7: Search And Palette

- Metadata search
  - title search
  - path search
  - root filter
- Command palette
  - actions
  - files
  - tabs
  - headings
  - settings
  - workspaces
  - pinned files
- Content search later
  - optional
  - on-demand file reads
  - no always-on full body index until designed carefully

## Phase 8: Workspaces, Pins, Settings

- Workspaces
  - create
  - rename
  - duplicate
  - delete
  - assign folders
- Pins
  - pin/unpin file
  - show pinned group
  - palette search
- Settings
  - theme
  - reader style
  - font size
  - line height
  - content width
  - preserve whitespace

## Phase 9: Validation

- Correctness checks
  - folder add/remove works
  - large vault opens
  - tabs restore
  - search stays metadata-only
  - rendered output matches `readmd`
- Memory checks
  - `ps -o pid,rss,vsz,etime,command -p <pid>`
  - `vmmap -summary <pid>`
  - compare against current Tauri app
- Performance checks
  - folder scan time
  - search response time
  - note open time
  - tab switch time

## Open Questions

- Should first prototype call `readmd` CLI or link Rust directly?
- Is HTML-to-attributed-text good enough for CalmPage's reading style?
- Do we need cross-platform support later, or macOS-only is fine?
- What is the real target memory for normal use: `200 MB`, `300 MB`, or lower?

## First Next Step

- Build the AppKit/SwiftUI spike first.
- Keep it small.
- Measure memory before building the full app.
