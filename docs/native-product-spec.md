# CalmPage Native Product Spec

## Summary

- Build a real macOS reading app, not a prototype.
- Use `readmd` for Markdown rendering.
- Keep memory low by loading only the active note body.
- Make reading feel calm, fast, and typographically strong.

## Terms/context

- RSS
  - real memory used by the app process.
- Native UI
  - macOS views, not a browser view.
- Disk-first
  - save large data on disk, keep small active state in memory.
- Metadata
  - small file info: path, title, size, modified time.
- Render cache
  - rendered note output saved on disk so repeat opens are fast.

## Target user

- Reads local Markdown folders.
- Uses AI notes, docs, writing drafts, and vault-style folders.
- Wants quick open, low memory, readable text, and keyboard navigation.

## Must-have scope

- macOS app named `CalmPage Native` during development.
- Open one or many folders.
- Keep folder access after relaunch with macOS security-scoped bookmarks.
- Persist folder list and restore on launch.
- Scan `.md`, `.markdown`, and `.mdx` files.
- Show virtual folder tree.
- Search files by title and path.
- Open notes in tabs.
- Keep inactive tabs unloaded.
- Restore open tabs and scroll positions.
- Render Markdown with `readmd`.
- Show headings, lists, task lists, blockquotes, code, tables, links, footnotes, strikethrough, and frontmatter details.
- Show TOC for `h1`, `h2`, and `h3` headings in the active note.
- Provide find-in-note.
- Provide command palette for actions, files, tabs, headings, settings, workspaces, and pinned files.
- Pin and unpin files.
- Support workspaces with folder assignment.
- Support reader settings: theme, style, font size, line height, content width, heading scale, paragraph spacing, code scale, preserve whitespace.
- Watch folders and refresh changed open notes.
- Support basic accessibility: keyboard-only use, VoiceOver labels for main controls, and system text size where practical.

## Out of scope for first full build

- Editing Markdown.
- Always-on full-text search across all note bodies.
- Browser WebView reader.
- Mermaid, KaTeX, and Shiki unless added after base reader is stable.
- Sync, cloud storage, or account system.

## Reading experience requirements

- Text must be readable for long sessions.
- Default line length target: `66` to `78` characters.
- Default body font size target: `16` to `18` pt.
- Default line height target: `1.55` to `1.7`.
- Content width must be adjustable.
- Paragraph spacing must be clear, not cramped.
- Code blocks must use a monospace font and horizontal scrolling.
- Tables must be readable and scroll horizontally when too wide.
- Links must be visually clear and clickable.
- Light and dark themes must both pass basic contrast checks by visual review.
- Reader must not jump scroll position after late render/cache updates.
- Reader must preserve normal Markdown semantics from `readmd`: heading order, list nesting, link destinations, footnote backlinks, and code text.

## Performance requirements

- Cold start RSS: under `150 MB`.
- One folder loaded RSS: under `200 MB`.
- One normal note open RSS: under `250 MB`.
- One very large note open RSS: under `350 MB`.
- Close all tabs should return near folder-only memory.
- App should remain interactive while scanning large folders.
- Opening a cached normal note target: under `150 ms` after file selection.
- Opening an uncached normal note target: under `500 ms` after file selection.
- File search target: visible results update under `100 ms` for indexed metadata.
- Folder scan target: first visible results under `1 s` for large folders, with full scan continuing in background.
- UI target: no main-thread task over `50 ms` during scanning or rendering.

## Memory rules

- Keep in memory:
  - visible file rows
  - active note render model
  - active note TOC
  - active note find matches
  - tabs as path/title/scroll metadata
  - small settings and workspace state
- Keep on disk:
  - SQLite metadata index
  - rendered output cache
  - workspace state
  - folder list
  - pins
  - restored tabs
- Do not keep by default:
  - all Markdown bodies
  - all rendered notes
  - inactive tab render output
  - full-text body index

## Main app flows

- First launch
  - show empty library state with open-folder action.
  - no marketing page.
- Open folder
  - user picks folder.
  - app scans metadata in background.
  - file tree updates as results arrive.
- Open note
  - app loads file body from disk.
  - app renders with `readmd`.
  - app shows reader and TOC.
  - app writes or refreshes render cache.
- Switch tab
  - app saves current scroll.
  - app unloads previous note body/render model when inactive memory limit requires it.
  - app loads selected note on demand.
- Close tab
  - app drops active render model if tab is closed.
  - app keeps only restore metadata for remaining tabs.
- Search file
  - app searches SQLite metadata.
  - app never scans all bodies for normal file search.
- Find in note
  - app searches active rendered text only.

## Acceptance checks

- App opens a test vault with at least `10,000` Markdown files without freezing.
- App opens a huge Markdown file at least `5 MB` without crashing.
- Inactive tabs do not keep note body strings in app state.
- Folder watcher updates changed files within `2` seconds after save.
- Rendered output matches `readmd` for supported Markdown features.
- Memory table is recorded for each release candidate.
- App relaunch restores folders, tabs, pins, reader settings, and scroll positions.
- App can reopen previously approved folders without asking again unless macOS permission is revoked.
- Keyboard path covers open folder, search files, switch tabs, find in note, TOC jump, and settings.

## Test fixtures

- `small-vault`: nested folders, links, frontmatter, task lists, table, code, footnotes.
- `large-vault`: generated `10,000` Markdown files with mixed paths and titles.
- `huge-note`: one Markdown file at least `5 MB` with many headings and wide tables.
- `unsafe-note`: raw HTML/script/link cases used to verify `readmd` sanitization still applies.
