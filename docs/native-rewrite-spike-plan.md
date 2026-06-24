# CalmPage Native Rewrite Spike Spec

## Goal

- Find the lightest way to keep CalmPage features.
- Avoid a full rewrite before we have memory numbers.
- Reuse `readmd` for Markdown rendering.

## Success Target

- Cold start memory: under `150 MB` RSS.
- One folder loaded: under `200 MB` RSS.
- One normal note open: under `250 MB` RSS.
- One very large note open: under `350 MB` RSS.
- After closing note: memory should drop close to folder-only state.
- No full Markdown bodies kept in memory after indexing.

## Terms

- RSS: memory the process currently has in RAM.
- WebView: embedded browser view. Current Tauri app uses this through WebKit on macOS.
- Native UI: macOS controls or Rust UI widgets, without browser DOM.
- DOM: browser page tree. Big HTML pages can make this large.
- Index: small search database for title/path/file metadata.

## Prototype A: AppKit + SwiftUI + Rust `readmd`

- Purpose
  - test lowest-memory macOS path
  - use native macOS UI instead of WebKit
- Build
  - SwiftUI app shell
  - AppKit file tree where needed
  - AppKit/native text reader
  - Rust `readmd` called through library or CLI first
- Feature slice
  - open one folder
  - list `.md`, `.markdown`, `.mdx`
  - search by title/path
  - open one note
  - render note content
  - show `h1`/`h2`/`h3` TOC
  - open two tabs
  - close tab and release note content
- Disk-first rule
  - keep file metadata in SQLite
  - keep rendered HTML/temp output on disk
  - keep only active rendered note in memory
  - keep inactive tabs as path/title/scroll only
- Risks
  - HTML to native rich text may not match current styling perfectly
  - tables/code blocks may need custom views

## Prototype B: Slint + Rust `readmd`

- Purpose
  - test Rust-only lightweight path
  - avoid Swift code if possible
- Build
  - Rust app with Slint UI
  - Rust file scanner
  - SQLite metadata index
  - `readmd` used directly as Rust crate
- Feature slice
  - same as Prototype A
- Disk-first rule
  - same as Prototype A
- Risks
  - rich document reader will need custom widgets
  - macOS polish may take more manual work

## Keep Tauri Baseline

- Purpose
  - compare against current app after memory fixes
- Measure
  - clean launch
  - folder loaded
  - one normal note
  - one huge note
  - two tabs
  - close all tabs
- Rule
  - do not add body/full-text SQLite index again
  - keep SQLite metadata-only unless a compact content index is designed

## `readmd` Integration Plan

- Current state
  - `readmd` already has `src/lib.rs`
  - modules are public: `cli`, `config`, `document`, `error`, `renderer`, `theme`
- First integration
  - call `readmd` CLI for fastest spike
  - write rendered HTML to temp/cache folder
- Better integration
  - depend on `readmd` as a local Rust crate
  - expose one stable function like `render_markdown_to_html(input, options)`
  - return rendered HTML plus headings metadata
- Best native integration
  - expose a document model from `readmd`
  - blocks: heading, paragraph, code, table, quote, list
  - render blocks with native UI

## Memory Rules For Final App

- In memory
  - folder tree metadata
  - current visible rows
  - active tab content
  - active TOC
  - small settings/state
- On disk
  - rendered HTML cache
  - SQLite metadata index
  - tab restore state
  - workspace/folder/pin settings
  - temp rendered files
- Never keep by default
  - all Markdown file bodies
  - all rendered HTML pages
  - full DOM for inactive tabs
  - full-text body index for every file

## Measurement Commands

```bash
ps -o pid,rss,vsz,etime,command -p <pid>
vmmap -summary <pid>
```

## Decision Rule

- Pick AppKit + SwiftUI if it is clearly lowest memory and feels good on macOS.
- Pick Slint if memory is close and Rust-only speed is better.
- Keep Tauri only if native prototypes do not save at least `300 MB` in normal use.

## Recommended Timeline

- Day 1
  - AppKit/SwiftUI prototype
  - same test vault
  - first memory table
- Day 2
  - Slint prototype
  - same test vault
  - second memory table
  - final choice doc

