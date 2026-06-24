# Lightweight CalmPage Architecture Options

## Goal

- Keep all current CalmPage features.
- Make memory much lower than the current Tauri/WebKit app.
- Reuse `readmd` as the Markdown rendering core when possible.
- Keep the app maintainable for one developer.

## Current Problem

- Tauri app bundle is small.
- Runtime memory is still high because macOS Tauri uses WebKit through `WKWebView`.
- WebKit can allocate a large separate `WebContent` process for `tauri://localhost`.
- Even after fixes, the WebView remains the biggest fixed cost.

Source: Tauri docs say macOS uses WebKit through `WKWebView` and the OS-provided webview runtime.
<https://v2.tauri.app/reference/webview-versions/>

## Current Asset To Reuse

- `readmd`
  - path: `/Users/luannguyenthanh/Development/Osimify/readmd`
  - already exposes Rust modules through `src/lib.rs`
  - pure Rust CLI
  - Markdown to standalone HTML
  - themes: `paper`, `white`, `graphite`, `polar`, `sepia`, `midnight`
  - styles: `editorial`, `notebook`, `technical`, `large`
  - uses `pulldown-cmark`, `ammonia`, `serde_yaml`

## Important Terms

- WebView
  - a small browser inside the app
  - Tauri uses this to show the Svelte UI
- WebKit
  - Apple's browser engine used by Safari and `WKWebView`
  - this is where `tauri://localhost` memory mostly comes from
- Native UI
  - UI drawn by macOS or a non-browser GUI toolkit
  - avoids browser DOM and JavaScript memory
- DOM
  - browser's in-memory tree for HTML elements
  - big Markdown pages can make this tree large

## Option A: Native macOS AppKit + SwiftUI Shell

### Shape

- App shell in SwiftUI/AppKit.
- Sidebar, tabs, settings, command palette in native macOS UI.
- Markdown rendering from Rust via `readmd` library/CLI.
- Display rendered content with native text/layout, not a WebView.

### Reader Rendering Choices

- Best memory path
  - convert Markdown to an attributed document model
  - display using `NSTextView` or custom AppKit view
  - avoid full browser DOM
- Faster migration path
  - generate HTML with `readmd`
  - convert HTML to `NSAttributedString`
  - display in `NSTextView`

### Best CalmPage Shape

- SwiftUI
  - window shell
  - sidebar structure
  - settings sheets
  - command palette shell
- AppKit
  - virtual file tree if SwiftUI list is too heavy
  - tab strip if custom behavior is needed
  - `NSTextView` or custom block reader for document view
- Rust/readmd
  - parse Markdown
  - sanitize content
  - extract title/frontmatter/headings
  - optionally output native block model instead of HTML later
- SQLite
  - metadata index only by default
  - optional on-demand content search later

### Fit

- Best for lowest macOS memory.
- Best platform feel.
- Best chance to keep idle memory very low.

### Risk

- More macOS-specific code.
- Markdown-to-native-rich-text may take work.
- Tables/code blocks/frontmatter need careful native rendering.

### Sources

- Apple `NSTextView` is the front-end class for AppKit text rendering.
  <https://developer.apple.com/documentation/appkit/nstextview>
- Apple shows using SwiftUI with AppKit for top-tier macOS apps.
  <https://developer.apple.com/la/videos/play/wwdc2022/10075/>

### Verdict

- Best long-term option for “very very lightweight” on macOS.
- Recommended if macOS-only is acceptable.

### Expected Memory Shape

- Lowest fixed cost.
- No browser process.
- Main risk is large attributed text documents, not app shell.
- Best chance to idle below Tauri by a large amount.

## Option B: Rust Native UI With Slint

### Shape

- Rewrite UI in Rust + Slint.
- Keep `readmd` as a Rust library for Markdown parsing/rendering.
- Store app state in Rust structs and SQLite.
- Build custom reader widgets for headings, paragraphs, code, tables.

### Fit

- Very low runtime overhead.
- Rust end to end.
- Good if we want no Swift/AppKit dependency.

### Risk

- Rich text reading UI may be harder than native AppKit.
- Some macOS polish must be built manually.
- Need custom command palette, sidebar tree, tabs, settings UI.

### Sources

- Slint supports Rust and compiles UI to machine code.
- Slint says its runtime fits in less than `300KiB` RAM.
  <https://slint.dev/>

### Verdict

- Strong Rust-native option.
- Best if you want a Rust app and can accept custom UI work.

### Expected Memory Shape

- Much lower fixed cost than WebKit.
- Runtime is marketed as tiny, but real desktop app memory still needs measurement.
- Rich reader widgets are the main unknown.

## Option C: Rust Native UI With Iced

### Shape

- Rewrite UI in Rust + Iced.
- Keep `readmd` as Rust rendering core.
- Build virtual file tree, tabs, command palette, settings in Iced.

### Fit

- Native Rust GUI, no browser engine.
- Good layout/widgets for app UI.
- Async support helps scanning/indexing.

### Risk

- Immediate-mode UI means the view code runs often.
- Rich document rendering is not a browser; tables/code/links need custom work.
- Iced docs describe it as experimental.

### Sources

- Iced is a cross-platform Rust GUI library.
- It has a native runtime and renderers using `wgpu` and `tiny-skia`.
  <https://github.com/iced-rs/iced>

### Verdict

- Good for a Rust-native prototype.
- Less ideal than AppKit for polished long-form text on macOS.

### Expected Memory Shape

- Can be small, especially with software rendering.
- GPU renderer may use more memory but can scroll smoother.
- Needs measurement with large Markdown documents.

## Option D: Rust Native UI With egui

### Shape

- Rewrite UI in Rust + egui/eframe.
- Keep `readmd` for Markdown parse/render logic.
- Build the reader from custom egui widgets.

### Fit

- Very fast to prototype.
- Pure Rust.
- Good for tools and dense controls.

### Risk

- Immediate-mode UI repaints frequently.
- Text-heavy reader app may need a lot of custom work.
- Default font support may need custom fonts for broad language support.

### Sources

- egui is a pure Rust immediate-mode GUI.
- In immediate mode, UI code runs every frame and produces shapes.
  <https://docs.rs/egui/latest/egui/>

### Verdict

- Best for prototype/spike.
- Not my first choice for the final polished reader.

## Option E: Keep Tauri, But Use It As A Thin Shell

### Shape

- Keep current app.
- Continue reducing WebView memory.
- Move more work to Rust/disk.
- Keep only visible UI and one active note in JS.

### Fit

- Lowest rewrite cost.
- Keeps current Svelte UI.
- All current features stay intact.

### Risk

- Cannot remove WebKit base cost.
- Memory can still spike inside `WebContent`.
- DOM remains expensive for large rendered notes.

### Verdict

- Best short-term path.
- Not enough for “very very lightweight.”

### Remaining Tauri Optimizations

- Keep only active note HTML in Svelte memory.
- Use Rust/readmd for render output and shared tests.
- Store rendered HTML on disk, not in tab state.
- Store folder/file metadata in SQLite, not localStorage.
- Use metadata-only search by default.
- Add optional content search that opens files only during search.
- Add hard limits for localStorage and WebKit cache reset.
- Avoid loading every heading for every file.
- Avoid body FTS index unless it is compressed and optional.

## Option F: Flutter Desktop

### Shape

- Rewrite UI in Flutter/Dart.
- Call Rust `readmd` through FFI or shell process.

### Fit

- Cross-platform desktop UI.
- Strong UI toolkit.

### Risk

- Bundles/uses Flutter engine.
- Not as low-level/light as AppKit or Rust-native UI.
- More language/runtime split: Dart + Rust.

### Sources

- Flutter officially supports macOS, Windows, and Linux desktop apps.
  <https://docs.flutter.dev/platform-integration/desktop>

### Verdict

- Good cross-platform product option.
- Not best for minimum memory.

## Option G: Qt Widgets

### Shape

- App in C++/Rust bindings/Python bindings around Qt Widgets.
- Reader uses `QTextBrowser` / `QTextDocument` for rich text.
- Rust/readmd can provide HTML or a document model.

### Fit

- Mature desktop toolkit.
- Rich text browser already exists.
- Cross-platform if needed later.

### Risk

- Bigger dependency stack than AppKit or Slint.
- Licensing and packaging need care.
- macOS feel may be less native than AppKit.

### Sources

- Qt `QTextBrowser` provides rich text display with links.
  <https://doc.qt.io/qt-6/qtextbrowser.html>

### Verdict

- Practical fallback if AppKit text rendering is too hard.
- Not the first choice for minimum macOS memory.

## Option H: Electron

### Shape

- Rewrite to Electron.
- Use Chromium instead of WebKit.

### Fit

- Web app development is easy.
- Current Svelte UI could move over.

### Risk

- Usually worse for memory and disk than Tauri.
- Does not solve the main problem.

### Sources

- Electron docs emphasize profiling and reducing memory/CPU/disk use.
  <https://www.electronjs.org/docs/latest/tutorial/performance>

### Verdict

- Not recommended.

## Best Candidate Paths

### Path 1: Lowest Risk Now

- Keep Tauri.
- Finish memory hardening.
- Reuse `readmd` as renderer.
- Add reset-state and localStorage guard.
- Keep SQLite index metadata-only.
- Avoid body index until there is a compact external index design.

### Path 2: Best Lightweight macOS App

- Build new native macOS app.
- Use SwiftUI for shell.
- Use AppKit for file tree, tabs, and advanced text view where needed.
- Use Rust/readmd for Markdown parsing and style model.
- Render to native attributed text or native blocks.

### Path 3: Best Rust-Only App

- Prototype Slint version.
- Keep all data/index/render logic in Rust.
- Build custom reader components.
- Compare memory and implementation pain against AppKit.

## Recommended Next Step

- Do a spike, not a full rewrite.
- Build the same small feature slice in two prototypes:
  - AppKit/SwiftUI prototype
  - Slint prototype
- Feature slice:
  - open folder
  - list Markdown files
  - open one note
  - render using `readmd`
  - switch between two tabs
  - show TOC
  - measure memory after cold start and after opening a large note

## Measurement Plan

- Same vault.
- Same note.
- Same app actions.
- Measure:
  - cold start RSS
  - physical footprint
  - after folder scan
  - after opening one small note
  - after opening one huge note
  - after switching tabs 20 times
  - after closing all tabs

## Likely Winner

- If macOS-only is fine:
  - AppKit + SwiftUI + Rust/readmd core.
- If Rust-only matters more:
  - Slint + Rust/readmd core.
- If fastest delivery matters:
  - keep Tauri and keep reducing memory.

## Next Spec

- Native rewrite spike:
  - `docs/native-rewrite-spike-plan.md`

## Decision Rule

- Choose AppKit/SwiftUI if:
  - macOS-only is acceptable
  - cold start memory is clearly lowest
  - rendered note quality is good enough
- Choose Slint if:
  - Rust-only is important
  - memory is close to AppKit
  - custom reader work feels manageable
- Stay on Tauri if:
  - prototype savings are not large enough
  - rewrite cost is too high
  - current app can stay below the memory target after hardening
