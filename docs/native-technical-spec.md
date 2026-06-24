# CalmPage Native Technical Spec

## Summary

- Final stack: SwiftUI shell, AppKit reader/tree where needed, Rust core, SQLite metadata.
- `readmd` is the Markdown source of truth.
- The app is disk-first and active-note-only in memory.

## Terms/context

- SwiftUI
  - Apple UI framework, useful for app shell and settings.
- AppKit
  - older macOS UI framework, strong for text views and custom controls.
- Rust core
  - fast shared backend code for scanning, rendering, cache, and indexing.
- FFI
  - bridge between Swift and Rust code.
- SQLite
  - small local database file.

## Repository shape

```text
calmpage-native/
  App/
    CalmPageNative.xcodeproj
    CalmPageNative/
      AppMain.swift
      UI/
      Reader/
      Library/
      Tabs/
      Palette/
      Settings/
      Bridge/
      Tests/
  core/
    Cargo.toml
    src/
      lib.rs
      scanner.rs
      index.rs
      render.rs
      cache.rs
      workspace.rs
      ffi.rs
    tests/
  docs/
  measurements/
```

## Module boundaries

- Swift app
  - owns windows, views, keyboard commands, selection, focus, and accessibility.
  - never stores all file bodies.
- Swift app model
  - owns active workspace id, visible tree state, selected file, tab metadata, reader settings.
  - stores only active note content model.
- Rust core
  - scans folders.
  - writes metadata to SQLite.
  - searches metadata.
  - calls `readmd` APIs.
  - extracts headings.
  - writes and invalidates render cache.
- SQLite
  - stores file metadata, roots, workspaces, pins, tabs, and settings.

## `readmd` integration

- First implementation
  - use local Rust crate at `/Users/luannguyenthanh/Development/Osimify/readmd`.
  - call existing `readmd::render_markdown(markdown)` for article HTML.
  - call existing `readmd::note_title(markdown, path)` for title.
  - keep `readmd` sanitization as the only trusted Markdown-to-HTML path.
  - test against `readmd` CLI output for representative fixtures.
- Required next API in `readmd`
  - add `render_note(markdown, path, options) -> RenderedNote`.
  - return `title`, `article_html`, `headings`, and optional `frontmatter` metadata.
  - return stable heading anchors matching article HTML anchors.
  - include `readmd_version` in output for cache keys and bug reports.
  - keep CLI behavior unchanged.
- Later native reader API
  - add block model output after HTML import is measured.
  - blocks: heading, paragraph, list, code, quote, table, rule.

## Swift to Rust bridge

- Use C ABI functions from Rust for stable Swift calls.
- Return JSON for complex values at first.
- Use explicit free functions for Rust-owned strings.
- Keep calls async on Swift side so UI does not freeze.
- Add a small status/version call before feature calls so app startup can fail clearly when the Rust library is mismatched.
- Bound JSON response size for metadata search and tree calls; paginate or stream large result sets.

## Core data model

```sql
CREATE TABLE roots (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE files (
  id TEXT PRIMARY KEY,
  root_id TEXT NOT NULL,
  path TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  title TEXT NOT NULL,
  extension TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_at INTEGER NOT NULL,
  indexed_at INTEGER NOT NULL,
  UNIQUE(root_id, relative_path)
);

CREATE TABLE headings (
  file_id TEXT NOT NULL,
  level INTEGER NOT NULL,
  title TEXT NOT NULL,
  anchor TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  PRIMARY KEY(file_id, ordinal)
);

CREATE TABLE tabs (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL,
  file_id TEXT NOT NULL,
  title TEXT NOT NULL,
  scroll_y REAL NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 0,
  opened_at INTEGER NOT NULL
);

CREATE TABLE pins (
  workspace_id TEXT NOT NULL,
  file_id TEXT NOT NULL,
  pinned_at INTEGER NOT NULL,
  PRIMARY KEY(workspace_id, file_id)
);

CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
);
```

- Store security-scoped bookmark data for each root in the app database or settings store.
- Store settings with explicit version so old reader settings can migrate safely.
- Add indexes for `files(root_id, relative_path)`, `files(title)`, and `files(modified_at)` before large-vault tests.

## Indexing policy

- Fast scan
  - collect path, relative path, extension, size, and modified time without reading file bodies.
  - derive temporary title from file name.
- Title enrichment
  - read small files in a background queue to extract frontmatter title or first `h1`.
  - skip title enrichment for files above the configured large-file limit until opened.
  - never keep body text after title extraction.
- Large-file limit
  - default: `1 MB` for background title extraction.
  - active-note open can read larger files on demand.
- Search
  - search title/path metadata only by default.
  - body search is active-note-only until a compact body index is designed.

## Render cache

- Cache key
  - file path
  - file modified time
  - file size
  - readmd version
  - reader style options that affect output
- Cache file
  - app cache directory under `CalmPageNative/render-cache/`.
  - one file per cache key.
- Cache behavior
  - read cache before rendering.
  - write cache after render.
  - delete stale cache entries during idle cleanup.
  - cap cache size and remove least-recently-used entries during idle cleanup.
  - never cache a render that failed sanitization or produced a fallback view.

## Reader architecture

- Milestone 1 reader
  - convert safe `readmd` article HTML to `NSAttributedString`.
  - show with `NSTextView` inside SwiftUI.
  - measure memory with huge notes.
  - apply typography with native attributes after import so reader settings do not require re-rendering Markdown.
- Milestone 2 reader
  - custom native block renderer if `NSAttributedString` is too heavy or weak for tables/code.
  - keep blocks lazy where possible.

## macOS permissions

- Use `NSOpenPanel` for folder selection.
- Create and persist security-scoped bookmarks for selected folders.
- Resolve bookmarks on launch before scanning.
- Handle stale bookmarks by asking the user to approve the folder again.
- Stop accessing a folder when its root is removed.

## Threading rules

- Main thread
  - UI updates only.
- Background tasks
  - folder scanning.
  - SQLite writes.
  - Markdown file reading.
  - `readmd` rendering.
  - cache cleanup.
- Cancellation
  - cancel old render when user switches notes quickly.
  - cancel scan when root is removed.

## Error handling

- Missing file
  - keep tab but show missing-file state.
- Permission error
  - show folder permission problem and keep root disabled.
- Render error
  - show plain Markdown fallback for active note.
- SQLite error
  - show recoverable index reset option.
- Bookmark error
  - keep root in disabled state and show re-approve action.
- Cache error
  - ignore cache and render fresh; do not block reading.

## Test plan

- Rust unit tests
  - Markdown extension detection.
  - metadata scan ignores non-Markdown.
  - render output sanitizes unsafe HTML.
  - title extraction from frontmatter, first heading, then path.
  - cache key changes when file modified time changes.
  - migration applies once and preserves existing rows.
  - cache cap removes old entries.
- Rust integration tests
  - scan nested folder fixture.
  - update SQLite after file add/change/delete.
  - search title/path from SQLite.
- Swift unit tests
  - tab state keeps metadata only.
  - settings encode/decode.
  - reader model releases on close.
  - folder bookmark encode/decode and stale-bookmark handling.
- UI tests
  - open folder.
  - open note.
  - switch tabs.
  - command palette file search.
  - TOC jump.
- Performance tests
  - cold start RSS.
  - folder loaded RSS.
  - normal note RSS.
  - huge note RSS.
  - close all tabs RSS.
  - first visible scan result latency.
  - search result latency with `10,000` indexed files.

## Measurement method

- Use the same fixtures for every release candidate.
- Record machine, macOS version, build type, fixture size, and command output.
- Measure RSS with `ps -o pid,rss,vsz,etime,command -p <pid>`.
- Inspect retained regions with `vmmap -summary <pid>` when RSS misses target.
- Run each memory check after a short idle period so cache cleanup can run.

## Build commands

```bash
cd core
cargo fmt --all -- --check
cargo test

cd ../App
xcodebuild test -scheme CalmPageNative -destination 'platform=macOS'
```

## Release gate

- All tests pass.
- Memory table added to `measurements/`.
- No WebView dependency in app target.
- No full-body metadata index enabled by default.
- Large vault smoke test passes.
