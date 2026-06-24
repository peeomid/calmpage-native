# CalmPage Native

Native, very lightweight version of CalmPage.

## Goal

- Keep the CalmPage reading workflow.
- Remove the WebView fixed memory cost.
- Reuse `readmd` for Markdown rendering.
- Keep file bodies and rendered output on disk whenever possible.

## Current Direction

- First target: macOS native app.
- Preferred stack: SwiftUI + AppKit + Rust/readmd core.
- Backup stack: Slint + Rust/readmd if Rust-only wins the spike.

## Docs

- [Feature inventory](docs/calm-page-feature-inventory.md)
- [Architecture options](docs/lightweight-architecture-options.md)
- [Native rewrite spike plan](docs/native-rewrite-spike-plan.md)
- [Native implementation plan](docs/native-implementation-plan.md)
- [Native product spec](docs/native-product-spec.md)
- [Apple native UI design spec](docs/apple-native-ui-design-spec.md)
- [Native technical spec](docs/native-technical-spec.md)
- [Native implementation spec](docs/native-implementation-spec.md)
