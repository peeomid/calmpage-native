# CalmPage Native Optimization Implementation Spec

## Summary

- Fix persistence, indexing slowness, memory growth, and large-library UI.
- Re-apply the previous CalmPage optimizations in the native app.
- Implement one task at a time with subagent implementation, review, and tests.

## Terms/context

- Main thread
  - UI thread. Heavy work here makes app feel frozen.
- Metadata-only index
  - database stores path/title/size/date, not note body.
- Paged library
  - UI asks for small visible/search result sets, not all files.
- Lazy tabs
  - inactive tabs keep only path/title/scroll.
- Render cache
  - rendered note output saved on disk.

## Previous CalmPage optimizations to carry over

- Persist folders, tabs, active tab, scroll, pins, reader settings.
- Restore active tab first, hydrate other tabs later.
- Keep inactive tab note content unloaded.
- Use metadata-only index by default.
- Never build full body FTS index by default.
- Do targeted missing-file lookup, not full refresh while typing in palette.
- Put indexing and render cache work in backend/background workers.
- Keep large file lists out of UI memory.

## Current native app problems

- Folders and tabs are not restored on relaunch.
- Indexing publishes large `[MarkdownFile]` arrays into SwiftUI state.
- Folder tree is recomputed from all files in `AppModel`.
- Palette filters in-memory arrays.
- SwiftUI recursive tree can get slow on large vaults.
- Reader no longer stores HTML duplicate, but render cache/direct readmd bridge is not complete.

## Target architecture

- SwiftUI shell
  - toolbar, reader, tabs, inspector, settings.
- AppKit components
  - `NSOutlineView` for large folder tree.
  - `NSPanel` for command palette.
- Library service
  - actor-owned SQLite database.
  - scans folders off main thread.
  - writes metadata in batches.
  - exposes small query APIs.
- App model
  - owns only UI selection and small state.
  - does not own full file library array.

## Storage design

- Database path
  - `Application Support/CalmPage Native/state.sqlite`
- Tables
  - `roots(id, path, name, bookmark, created_at)`
  - `files(id, root_id, path, relative_path, title, extension, size_bytes, modified_at, indexed_at)`
  - `tabs(id, file_id, title, scroll_y, is_active, opened_at)`
  - `pins(file_id, pinned_at)`
  - `settings(key, value, updated_at)`
  - `folders(id, root_id, path, name, parent_path)` if needed for outline queries
- UserDefaults
  - only acceptable for tiny UI flags during transition.

## Task 1: Persistent app state

- Add `AppStateStore` in Swift.
- Persist:
  - root folder paths.
  - open tabs metadata.
  - active tab id.
  - pins.
  - reader settings.
- Load saved state on app startup.
- Re-index saved roots after window appears.
- Restore tabs as metadata only.
- Render active tab first when file exists.
- Tests:
  - encode/decode saved roots.
  - encode/decode tabs.
  - settings round-trip.
  - inactive restored tabs do not create `RenderedNote`.
- Acceptance:
  - relaunch keeps folders and tabs.
  - no note bodies are persisted.

## Task 2: SQLite library service

- Add native-side `LibraryStore` or wire existing Rust SQLite core.
- Store roots and files in SQLite.
- Scan folders off main thread.
- Write files in batches.
- AppModel no longer owns full library as source of truth.
- Query APIs:
  - `searchFiles(query, limit)`.
  - `children(parentPath, limit)`.
  - `pinnedFiles()`.
  - `fileByID(id)`.
- Tests:
  - insert/update/delete file metadata.
  - search title/path.
  - root persistence.
  - batch scan does not read file bodies.
- Acceptance:
  - app can restart and show indexed metadata before fresh scan completes.

## Task 3: Library UI performance

- Replace recursive SwiftUI disclosure tree with large-list-safe implementation.
- Preferred: `NSOutlineView` wrapper.
- Fallback: paged SwiftUI visible row list.
- Tree rows load children from `LibraryStore`.
- Collapsed folders do not build child rows.
- Tests:
  - tree row model for nested files.
  - collapsed folder does not request descendants.
  - search returns limited rows.
- Acceptance:
  - adding/scanning folder does not block clicking reader or palette.
  - large vault does not create thousands of SwiftUI row views at once.

## Task 4: Command palette performance

- Replace sheet/list palette with keyboard-first native flow.
- Query SQLite with limits.
- Prefixes:
  - `>` actions.
  - `/` files.
  - `@` tabs.
  - `#` headings.
  - `?` settings.
  - `:` workspaces.
  - `!` pins.
- Arrow keys, Enter, Escape must work.
- No full folder scan while typing.
- Tests:
  - prefix detection.
  - arrow selection bounds.
  - Enter runs selected item.
  - file query limit is enforced.
- Acceptance:
  - palette opens under `100 ms` with large library.

## Task 5: Reader and tab memory

- Keep only active note render model.
- Inactive tabs store path/title/scroll only.
- Add disk render cache.
- Restore active tab first on launch.
- Use `readmd` core/bridge instead of spawning CLI per note when practical.
- Tests:
  - close tab releases active note.
  - switch tab unloads previous note.
  - render cache key invalidates on file change.
  - active tab restore runs before full re-index.
- Acceptance:
  - open/close tab memory returns near previous state.

## Task 6: Measurement and regression gates

- Add measurement doc per run in `measurements/`.
- Add debug counters:
  - roots count.
  - indexed file count.
  - visible row count.
  - open tab count.
  - loaded note count.
- Record:
  - cold launch RSS.
  - after restored roots.
  - during indexing.
  - after indexing.
  - normal note open.
  - huge note open.
  - close all tabs.
- Acceptance:
  - no regression without note explaining why.

## Review workflow

- For each task:
  - spawn implementation subagent.
  - review spec compliance.
  - review code quality.
  - run tests locally in root agent.
  - only then move to next task.
- Do not run two implementation subagents touching app files at same time.

## Execution spec for this pass

- Parent tracker
  - `minimal-markdown-reader:37`.
- Order
  - Task 1, then Task 2, then Task 3, then Task 4, then Task 5, then Task 6.
- Review gate after every task
  - inspect changed files with `git diff`.
  - verify scope stayed inside the task.
  - run focused tests plus full app tests when practical.
  - record remaining limits in this document or `measurements/`.
- Main rule
  - SwiftUI state must not become the database. Large roots, file lists, and folder trees belong in the store/service layer.
- Done means
  - code builds.
  - tests pass.
  - app can launch.
  - no known UI freeze path is left hidden behind a placeholder.

## Task handoff specs

### Task 1 handoff: persistent app state

- Scope
  - `AppStateStore`, `AppModel` restore/save integration, and tests only.
- Persist
  - roots, tabs metadata, active tab id, pins, reader settings.
- Do not persist
  - Markdown body text, rendered HTML, heading body content, or full file arrays.
- Startup behavior
  - window can appear with saved tabs before indexing completes.
  - active tab attempts render from saved file metadata.
  - saved roots trigger indexing after restore.
- Test names should clearly prove
  - roots round-trip.
  - tabs round-trip.
  - settings round-trip.
  - inactive restored tabs do not create `RenderedNote`.

### Task 2 handoff: SQLite library store

- Scope
  - Add `LibraryStore` using system SQLite3 from Swift, or thin wrapper around existing Rust core if faster and clean.
  - No UI wiring yet unless needed for compile.
- Store
  - roots and file metadata only.
- APIs
  - `upsertRoot`.
  - `upsertFiles` batch write.
  - `searchFiles(query, limit)`.
  - `children(parentPath, limit)`.
  - `fileByID(id)`.
  - `count`.
- Tests
  - insert/update file metadata.
  - title/path search.
  - root persistence.
  - metadata storage does not read file bodies.

### Task 3 handoff: native library tree performance

- Scope
  - Replace recursive SwiftUI tree with `NSOutlineView` wrapper or a proven paged fallback.
- Required behavior
  - direct children loaded on expand.
  - collapsed folders do not build descendants.
  - search capped by limit.
  - clicking reader remains responsive during indexing.
- Tests
  - tree row model asks only for direct children.
  - search result limit enforced.

### Task 4 handoff: command palette performance

- Scope
  - Native keyboard-first palette flow backed by limited queries.
- Required behavior
  - `Cmd+P` opens fast.
  - arrows move selection.
  - Enter runs selected item.
  - Escape closes.
  - prefixes do not scan/filter full file arrays.
- Tests
  - prefix detection.
  - selection bounds.
  - file query limit.

### Task 5 handoff: reader and tab memory

- Scope
  - active-note-only render model, render cache, tab unloading.
- Required behavior
  - inactive tabs keep metadata only.
  - switching tabs releases previous note state.
  - close tab clears active render when needed.
  - render cache invalidates on modified time or size change.
- Tests
  - close tab release.
  - switch tab unload.
  - cache invalidation.

### Task 6 handoff: measurement gates

- Scope
  - measurement docs and debug counters.
- Required measurements
  - cold launch RSS.
  - after restore.
  - during indexing.
  - after indexing.
  - open note.
  - close all tabs.
- Output
  - one dated markdown file under `measurements/`.

## Execution guardrails

- Keep each task shippable by itself.
- Do not hide slow paths behind placeholders.
- Prefer measured behavior over visual-only changes.
- Keep all heavy work away from SwiftUI view bodies.
- Keep full Markdown note bodies out of persisted state and inactive tabs.
- Use small query limits for search and palette results.
- Add tests at the same layer as the change:
  - pure model/store logic in unit tests.
  - scanner/index behavior with temporary folders.
  - UI wrappers with small deterministic row models where direct UI tests are hard.
- After each task, record:
  - what changed.
  - tests run.
  - remaining limitation.

## Detailed acceptance checklist

### Task 1 checklist

- Relaunch restores added folder paths.
- Relaunch restores open tab list and active tab id.
- Relaunch restores pins and reader settings.
- Inactive restored tabs do not hold rendered note text or HTML.
- Active tab renders after startup if the file still exists.
- Missing active file gives a readable failed state, not a crash.
- Saved roots re-index after the first window render.

### Task 2 checklist

- Files are stored as metadata only: path, relative path, title, size, modified time.
- Scanner does not read Markdown bodies for indexing.
- Writes are batched.
- UI can query file rows with `LIMIT`.
- Existing indexed rows show before a fresh scan completes.

### Task 3 checklist

- Collapsed folders do not build descendant row views.
- Folder expand loads direct children only.
- Search result count is capped.
- Reader remains clickable while indexing runs.

### Task 4 checklist

- Palette opens quickly even with a large indexed vault.
- Arrow keys, Enter, and Escape work from the search field.
- Prefix modes do not scan or filter the full library in SwiftUI.
- Result count is capped.

### Task 5 checklist

- Only the active tab has a loaded `RenderedNote`.
- Switching tabs unloads previous active note state.
- Close tab releases active render state.
- Render cache invalidates when file modified time or size changes.

### Task 6 checklist

- Measurement files include date, git status summary, command used, and RSS numbers.
- Debug counters expose loaded note count and visible row count.
- Regression notes are explicit when memory or latency gets worse.
