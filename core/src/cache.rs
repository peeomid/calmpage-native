use std::{
    fs,
    hash::{Hash, Hasher},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::{RenderedNote, Result};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CacheKey {
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderCache {
    directory: PathBuf,
}

impl RenderCache {
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        Self {
            directory: directory.into(),
        }
    }

    pub fn read(&self, key: &CacheKey) -> Result<Option<RenderedNote>> {
        let path = self.path_for(key);
        if !path.exists() {
            return Ok(None);
        }
        let data = fs::read_to_string(path).map_err(|source| crate::CoreError::ReadFile {
            path: self.path_for(key),
            source,
        })?;
        let note = serde_json::from_str(&data)?;
        Ok(Some(note))
    }

    pub fn write(&self, key: &CacheKey, note: &RenderedNote) -> Result<()> {
        fs::create_dir_all(&self.directory).map_err(|source| crate::CoreError::ReadDir {
            path: self.directory.clone(),
            source,
        })?;
        let data = serde_json::to_string(note)?;
        fs::write(self.path_for(key), data).map_err(|source| crate::CoreError::WriteFile {
            path: self.path_for(key),
            source,
        })?;
        Ok(())
    }

    pub fn path_for(&self, key: &CacheKey) -> PathBuf {
        self.directory.join(format!("{}.json", key.value))
    }
}

pub fn cache_key_for_file(
    path: &Path,
    modified_at: u64,
    size_bytes: u64,
    readmd_version: &str,
    style_fingerprint: &str,
) -> CacheKey {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    path.to_string_lossy().hash(&mut hasher);
    modified_at.hash(&mut hasher);
    size_bytes.hash(&mut hasher);
    readmd_version.hash(&mut hasher);
    style_fingerprint.hash(&mut hasher);

    CacheKey {
        value: format!("{:016x}", hasher.finish()),
    }
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;

    #[test]
    fn cache_key_changes_when_file_metadata_changes() {
        let first = cache_key_for_file(Path::new("note.md"), 1, 10, "0.1.0", "paper");
        let second = cache_key_for_file(Path::new("note.md"), 2, 10, "0.1.0", "paper");

        assert_ne!(first, second);
    }

    #[test]
    fn render_cache_round_trips_rendered_note() {
        let temp = tempfile::tempdir().unwrap();
        let cache = RenderCache::new(temp.path());
        let key = cache_key_for_file(Path::new("note.md"), 1, 10, "0.1.0", "paper");
        let note = crate::render_note_from_markdown("# Cached", "note.md");

        assert!(cache.read(&key).unwrap().is_none());
        cache.write(&key, &note).unwrap();
        assert_eq!(cache.read(&key).unwrap(), Some(note));
    }
}
