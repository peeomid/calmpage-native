pub mod cache;
pub mod index;
pub mod render;
pub mod scanner;
pub mod workspace;

pub use cache::{CacheKey, cache_key_for_file};
pub use index::{FileRecord, InMemoryIndex};
pub use render::{RenderedNote, render_note_from_markdown};
pub use scanner::{MarkdownFile, scan_markdown_files};
pub use workspace::{RootFolder, Workspace};

pub type Result<T> = std::result::Result<T, CoreError>;

#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("failed to read directory {path}: {source}")]
    ReadDir {
        path: std::path::PathBuf,
        source: std::io::Error,
    },
    #[error("failed to read file metadata {path}: {source}")]
    Metadata {
        path: std::path::PathBuf,
        source: std::io::Error,
    },
    #[error("failed to read file {path}: {source}")]
    ReadFile {
        path: std::path::PathBuf,
        source: std::io::Error,
    },
    #[error("failed to write file {path}: {source}")]
    WriteFile {
        path: std::path::PathBuf,
        source: std::io::Error,
    },
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
}
