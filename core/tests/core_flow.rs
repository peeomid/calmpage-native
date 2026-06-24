use std::{fs, path::PathBuf};

use calmpage_core::{InMemoryIndex, render_note_from_markdown, scan_markdown_files};

#[test]
fn scan_index_and_render_fixture_vault() {
    let root = fixture_root();
    let files = scan_markdown_files(&root).unwrap();
    assert_eq!(files.len(), 3);

    let mut index = InMemoryIndex::default();
    for file in &files {
        index.upsert_scanned_file(file);
    }

    assert_eq!(index.len(), 3);
    assert_eq!(index.search("readme").len(), 1);

    let markdown = fs::read_to_string(root.join("README.md")).unwrap();
    let rendered = render_note_from_markdown(&markdown, "README.md");
    assert_eq!(rendered.title, "Fixture Home");
    assert!(rendered.article_html.contains("Welcome to the test vault"));
}

fn fixture_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")
}
