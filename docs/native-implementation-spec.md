# CalmPage Native Implementation Spec

## Summary

- Build in vertical slices.
- Each slice must include tests.
- Each slice must be reviewed before the next slice starts.

## Terms/context

- Vertical slice
  - one small feature that works end to end.
- Gate
  - checks that must pass before moving on.
- Fixture
  - small test folder or file used by tests.

## Work rules

- Do one subtask at a time.
- Keep each change small enough to review.
- Do not add WebView.
- Do not store all note bodies in memory.
- Add tests with implementation.
- Add or update fixtures when behavior depends on Markdown shape, folder size, or permissions.
- Record memory numbers after runnable app exists.
- Update trove session after meaningful progress.
- Add trove build log when a buildable app or release artifact is produced.
- Do not move to next subtask until review gate and listed tests pass, or the failure is documented with a clear blocker.

## Subtask 1: Repo and core skeleton

- Create `core/` Rust crate.
- Add scanner, index, render, cache, workspace module placeholders.
- Add dependency on local `readmd` crate.
- Add test fixtures.
- Add fixture generator for large-vault and huge-note tests.
- Tests:
  - `cargo fmt --all -- --check`
  - `cargo test`
- Review gate:
  - crate builds.
  - no unused placeholder API that hides missing work.
  - fixture generation is deterministic.

## Subtask 2: Rust scanner and metadata index

- Implement folder scan for `.md`, `.markdown`, `.mdx`.
- Store metadata in SQLite.
- Support add/change/delete refresh.
- Implement title extraction through `readmd::note_title`.
- Add schema migrations and required indexes.
- Tests:
  - nested fixture scan.
  - ignore non-Markdown.
  - update changed file.
  - delete removed file.
- Review gate:
  - scanner does not read full bodies except when title extraction requires it.
  - large body is not kept after metadata write.
  - scan streams results or batches writes; no unbounded file list kept in memory.

## Subtask 3: Rust render service and cache

- Implement render active note.
- Use `readmd::render_markdown` first.
- Extract headings from rendered article HTML or shared parser.
- Implement cache key and cache read/write.
- Add cache size cap and idle cleanup entry point.
- Add compatibility layer for current `readmd` API and future `render_note` API.
- Tests:
  - render frontmatter.
  - render tables/task lists/code.
  - unsafe HTML sanitized by readmd.
  - cache hit and stale cache invalidation.
- Review gate:
  - cache does not skip security/sanitization.
  - cache invalidates on file change.
  - rendered headings use anchors that match rendered article HTML.

## Subtask 4: Swift app shell

- Create macOS app target.
- Add main window layout.
- Add sidebar, tab bar, reader pane, optional TOC pane.
- Add empty state and open-folder action.
- Add keyboard commands for open folder, command palette, close tab, and find.
- Tests:
  - app target builds.
  - basic Swift unit tests run.
- Review gate:
  - UI shell uses native views only.
  - main window has stable layout at narrow and wide sizes.

## Subtask 5: Swift/Rust bridge

- Expose Rust functions through C ABI.
- Add Swift bridge wrapper.
- Run scanning and rendering off main thread.
- Add status/version function and bounded-result APIs.
- Tests:
  - bridge returns version/status.
  - bridge scans fixture path.
  - bridge renders fixture note.
- Review gate:
  - Rust-owned strings are freed.
  - UI is not blocked by core calls.
  - bridge errors become typed Swift errors, not raw strings in the UI layer.

## Subtask 6: Library UI and folder workflow

- Open folder picker.
- Persist root folders.
- Persist and restore security-scoped bookmarks.
- Display virtual folder tree from SQLite metadata.
- Add file search by title/path.
- Add folder watcher.
- Tests:
  - open fixture folder in UI test.
  - restore approved fixture folder after relaunch.
  - search indexed file.
  - changed file refreshes.
- Review gate:
  - large folders do not render all rows at once.
  - removed or stale folder permission has a recoverable UI state.

## Subtask 7: Reader MVP

- Render active note through Rust service.
- Convert HTML to native attributed text.
- Display with `NSTextView`.
- Add link handling.
- Add code/table readable styling.
- Add reader settings application without re-reading every file.
- Tests:
  - open note UI test.
  - verify body text appears.
  - verify link click handler path.
  - verify table, code, task list, footnote, and frontmatter fixtures render.
- Review gate:
  - inactive tabs do not hold rendered text.
  - scroll position does not jump after render/cache refresh.

## Subtask 8: Tabs and state restore

- Open, activate, close, close all tabs.
- Save scroll position.
- Restore tabs on launch.
- Keep inactive tabs as metadata only.
- Handle missing moved files without deleting user tabs silently.
- Tests:
  - tab model tests.
  - close tab releases reader model.
  - restore active tab.
- Review gate:
  - memory rule is enforced in code.
  - restore state is versioned and migration-safe.

## Subtask 9: TOC and find-in-note

- Show active note headings.
- Jump to heading.
- Search headings in palette.
- Add find in active note.
- Tests:
  - heading extraction.
  - TOC jump.
  - find next/previous.
- Review gate:
  - TOC only stores active note headings.

## Subtask 10: Command palette, pins, workspaces, settings

- Add palette prefixes.
- Add pin/unpin and pinned search.
- Add workspace create/rename/delete/switch.
- Add reader settings UI.
- Add keyboard-only path for all palette actions.
- Tests:
  - palette action search.
  - pinned files persist.
  - workspace folder filter.
  - settings persist.
- Review gate:
  - settings changes do not reload whole vault.
  - workspace switching unloads inactive workspace reader state.

## Subtask 11: Performance and memory pass

- Add measurement fixtures.
- Record memory table.
- Fix obvious memory retention.
- Add release candidate checklist.
- Record first-visible scan latency, note-open latency, and search latency.
- Tests:
  - all unit tests.
  - UI smoke tests.
  - manual memory commands recorded.
- Review gate:
  - numbers meet target or have clear notes.

## Subagent workflow

- Main agent assigns one subtask.
- Subagent implements only that subtask.
- Main agent reviews diff and runs tests.
- Main agent asks for fixes or moves to next subtask.
- No two subagents edit the same files at once.

## Review checklist

- Correctness
  - feature works from user flow.
  - edge cases handled.
- Performance
  - no full body loading except active note or explicit render.
  - no unbounded in-memory arrays for large vaults.
- Memory
  - inactive tabs store metadata only.
  - close path releases active content.
- Tests
  - tests cover new behavior.
  - tests are not only happy path.
- UX
  - keyboard path works.
  - typography stays readable.
  - no visible debug UI.
