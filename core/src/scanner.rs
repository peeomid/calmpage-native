use std::{fs, path::PathBuf, time::UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::{CoreError, Result};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MarkdownFile {
    pub path: PathBuf,
    pub relative_path: PathBuf,
    pub extension: String,
    pub size_bytes: u64,
    pub modified_at: u64,
}

pub fn scan_markdown_files(root: impl Into<PathBuf>) -> Result<Vec<MarkdownFile>> {
    let root = root.into();
    let mut files = Vec::new();
    scan_dir(&root, &root, &mut files)?;
    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(files)
}

fn scan_dir(root: &PathBuf, dir: &PathBuf, files: &mut Vec<MarkdownFile>) -> Result<()> {
    let entries = fs::read_dir(dir).map_err(|source| CoreError::ReadDir {
        path: dir.clone(),
        source,
    })?;

    for entry in entries {
        let entry = entry.map_err(|source| CoreError::ReadDir {
            path: dir.clone(),
            source,
        })?;
        let path = entry.path();
        let metadata = entry.metadata().map_err(|source| CoreError::Metadata {
            path: path.clone(),
            source,
        })?;

        if metadata.is_dir() {
            scan_dir(root, &path, files)?;
            continue;
        }

        if !metadata.is_file() || !readmd::renderer::is_markdown(&path) {
            continue;
        }

        let extension = path
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase();
        let relative_path = path.strip_prefix(root).unwrap_or(&path).to_path_buf();
        let modified_at = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .map(|duration| duration.as_secs())
            .unwrap_or_default();

        files.push(MarkdownFile {
            path,
            relative_path,
            extension,
            size_bytes: metadata.len(),
            modified_at,
        });
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{fs, path::Path};

    use super::*;

    #[test]
    fn scanner_finds_supported_markdown_extensions() {
        let root = fixture_root();
        let files = scan_markdown_files(root).unwrap();
        let names = files
            .iter()
            .map(|file| file.relative_path.to_string_lossy().to_string())
            .collect::<Vec<_>>();

        assert_eq!(
            names,
            vec!["README.md", "draft.markdown", "subdir/page.mdx"]
        );
    }

    #[test]
    fn scanner_ignores_non_markdown_files() {
        let temp = tempfile::tempdir().unwrap();
        fs::write(temp.path().join("note.md"), "# Note").unwrap();
        fs::write(temp.path().join("image.png"), "not markdown").unwrap();

        let files = scan_markdown_files(temp.path()).unwrap();

        assert_eq!(files.len(), 1);
        assert_eq!(files[0].relative_path, Path::new("note.md"));
    }

    fn fixture_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/vault")
    }
}
