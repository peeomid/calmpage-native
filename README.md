# CalmPage Native

CalmPage Native is a lightweight macOS version of the previous CalmPage reading app.

It keeps the same core idea: browse a folder of Markdown files and read them in a calm, focused interface. This native version is built to use less memory than the earlier WebView-based app.

## Why Native

- Native macOS UI with SwiftUI and AppKit.
- Lower fixed memory cost than a browser/WebView shell.
- File bodies and render cache stay on disk when possible.
- Markdown rendering stays shared through [`readmd`](https://github.com/peeomid/readmd).

## Status

This is an early native rewrite.

Current focus:

- Fast local Markdown library scanning.
- Multi-tab reading.
- Workspace roots.
- Lightweight render cache.
- `readmd` setup and validation.

## Requirements

- macOS 14 or newer.
- Xcode Command Line Tools.
- Swift 6 toolchain.
- Rust, only for the Rust core tests.
- Optional: `readmd` CLI for full Markdown HTML rendering in the app.

## Install readmd

Recommended Homebrew install:

```bash
brew tap peeomid/tap
brew install readmd
```

Cargo fallback from GitHub:

```bash
cargo install --git https://github.com/peeomid/readmd.git --force
```

Do not use `cargo install readmd`: that crates.io name belongs to another project.

After install, open CalmPage Native settings and use **Auto-detect** in the readmd renderer section.

## Build App

Build and package the macOS app bundle:

```bash
scripts/build-macos-app.sh
```

The app bundle is written to:

```text
build/CalmPage Native.app
```

Run Swift tests:

```bash
cd App
swift test
```

Run Rust core tests:

```bash
cd core
cargo test
```

## Repo Layout

- `App/`: SwiftUI/AppKit macOS app.
- `core/`: Rust scanning, indexing, and render helpers.
- `docs/`: product, design, and technical specs.
- `scripts/`: local build scripts.
- `measurements/`: performance and regression notes.

## Docs

- [Feature inventory](docs/calm-page-feature-inventory.md)
- [Architecture options](docs/lightweight-architecture-options.md)
- [Native rewrite spike plan](docs/native-rewrite-spike-plan.md)
- [Native implementation plan](docs/native-implementation-plan.md)
- [Native product spec](docs/native-product-spec.md)
- [Apple native UI design spec](docs/apple-native-ui-design-spec.md)
- [Native technical spec](docs/native-technical-spec.md)
- [Native implementation spec](docs/native-implementation-spec.md)
