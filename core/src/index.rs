use std::{collections::BTreeMap, fs, path::Path};

use rusqlite::{Connection, params};

use serde::{Deserialize, Serialize};

use crate::{CoreError, Result, scanner::MarkdownFile};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileRecord {
    pub id: String,
    pub relative_path: String,
    pub title: String,
    pub size_bytes: u64,
    pub modified_at: u64,
}

pub struct MetadataIndex {
    connection: Connection,
}

impl MetadataIndex {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let connection = Connection::open(path)?;
        let index = Self { connection };
        index.init_schema()?;
        Ok(index)
    }

    pub fn open_memory() -> Result<Self> {
        let connection = Connection::open_in_memory()?;
        let index = Self { connection };
        index.init_schema()?;
        Ok(index)
    }

    pub fn init_schema(&self) -> Result<()> {
        self.connection.execute_batch(
            "CREATE TABLE IF NOT EXISTS files (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                relative_path TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                extension TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                modified_at INTEGER NOT NULL,
                indexed_at INTEGER NOT NULL
            );",
        )?;
        Ok(())
    }

    pub fn upsert_scanned_file(&self, file: &MarkdownFile) -> Result<()> {
        let relative_path = file.relative_path.to_string_lossy().to_string();
        let title = readmd::renderer::title_from_path(&relative_path);

        self.connection.execute(
            "INSERT INTO files (
                id, path, relative_path, title, extension, size_bytes, modified_at, indexed_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, strftime('%s','now'))
            ON CONFLICT(relative_path) DO UPDATE SET
                path = excluded.path,
                title = excluded.title,
                extension = excluded.extension,
                size_bytes = excluded.size_bytes,
                modified_at = excluded.modified_at,
                indexed_at = excluded.indexed_at",
            params![
                relative_path,
                file.path.to_string_lossy(),
                file.relative_path.to_string_lossy(),
                title,
                file.extension,
                file.size_bytes as i64,
                file.modified_at as i64,
            ],
        )?;
        Ok(())
    }

    pub fn refresh_from_scan(&mut self, files: &[MarkdownFile]) -> Result<()> {
        let transaction = self.connection.transaction()?;
        for file in files {
            let relative_path = file.relative_path.to_string_lossy().to_string();
            let title = readmd::renderer::title_from_path(&relative_path);
            transaction.execute(
                "INSERT INTO files (
                    id, path, relative_path, title, extension, size_bytes, modified_at, indexed_at
                ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, strftime('%s','now'))
                ON CONFLICT(relative_path) DO UPDATE SET
                    path = excluded.path,
                    title = excluded.title,
                    extension = excluded.extension,
                    size_bytes = excluded.size_bytes,
                    modified_at = excluded.modified_at,
                    indexed_at = excluded.indexed_at",
                params![
                    relative_path,
                    file.path.to_string_lossy(),
                    file.relative_path.to_string_lossy(),
                    title,
                    file.extension,
                    file.size_bytes as i64,
                    file.modified_at as i64,
                ],
            )?;
        }

        let present_paths = files
            .iter()
            .map(|file| file.relative_path.to_string_lossy().to_string())
            .collect::<Vec<_>>();
        if present_paths.is_empty() {
            transaction.execute("DELETE FROM files", [])?;
        } else {
            let placeholders = std::iter::repeat_n("?", present_paths.len())
                .collect::<Vec<_>>()
                .join(",");
            let sql = format!("DELETE FROM files WHERE relative_path NOT IN ({placeholders})");
            let params = rusqlite::params_from_iter(present_paths.iter());
            transaction.execute(&sql, params)?;
        }
        transaction.commit()?;
        Ok(())
    }

    pub fn enrich_title_from_file(&self, relative_path: &str, limit_bytes: u64) -> Result<bool> {
        let Some(record) = self.get(relative_path)? else {
            return Ok(false);
        };
        if record.size_bytes > limit_bytes {
            return Ok(false);
        }
        let path: String = self.connection.query_row(
            "SELECT path FROM files WHERE relative_path = ?1",
            params![relative_path],
            |row| row.get(0),
        )?;
        let markdown = fs::read_to_string(&path).map_err(|source| CoreError::ReadFile {
            path: path.into(),
            source,
        })?;
        let title = readmd::renderer::note_title(&markdown, relative_path);
        self.connection.execute(
            "UPDATE files SET title = ?1 WHERE relative_path = ?2",
            params![title, relative_path],
        )?;
        Ok(true)
    }

    pub fn get(&self, relative_path: &str) -> Result<Option<FileRecord>> {
        let mut statement = self.connection.prepare(
            "SELECT id, relative_path, title, size_bytes, modified_at
            FROM files WHERE relative_path = ?1",
        )?;
        let mut rows = statement.query(params![relative_path])?;
        let Some(row) = rows.next()? else {
            return Ok(None);
        };
        Ok(Some(row_to_record(row)?))
    }

    pub fn search(&self, query: &str) -> Result<Vec<FileRecord>> {
        let pattern = format!("%{}%", query.to_ascii_lowercase());
        let mut statement = self.connection.prepare(
            "SELECT id, relative_path, title, size_bytes, modified_at
            FROM files
            WHERE lower(title) LIKE ?1 OR lower(relative_path) LIKE ?1
            ORDER BY relative_path ASC",
        )?;
        let rows = statement.query_map(params![pattern], row_to_record)?;
        rows.collect::<std::result::Result<Vec<_>, _>>()
            .map_err(CoreError::from)
    }

    pub fn len(&self) -> Result<usize> {
        self.connection
            .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
            .map_err(CoreError::from)
    }
}

fn row_to_record(row: &rusqlite::Row<'_>) -> rusqlite::Result<FileRecord> {
    let size_bytes: i64 = row.get(3)?;
    let modified_at: i64 = row.get(4)?;
    Ok(FileRecord {
        id: row.get(0)?,
        relative_path: row.get(1)?,
        title: row.get(2)?,
        size_bytes: size_bytes as u64,
        modified_at: modified_at as u64,
    })
}

#[derive(Debug, Default, Clone)]
pub struct InMemoryIndex {
    files: BTreeMap<String, FileRecord>,
}

impl InMemoryIndex {
    pub fn upsert_scanned_file(&mut self, file: &MarkdownFile) {
        let relative_path = file.relative_path.to_string_lossy().to_string();
        let title = readmd::renderer::title_from_path(&relative_path);
        let record = FileRecord {
            id: relative_path.clone(),
            relative_path: relative_path.clone(),
            title,
            size_bytes: file.size_bytes,
            modified_at: file.modified_at,
        };
        self.files.insert(relative_path, record);
    }

    pub fn remove_missing(&mut self, present_paths: &[String]) {
        let present = present_paths
            .iter()
            .collect::<std::collections::BTreeSet<_>>();
        self.files.retain(|path, _| present.contains(path));
    }

    pub fn search(&self, query: &str) -> Vec<&FileRecord> {
        let query = query.to_ascii_lowercase();
        self.files
            .values()
            .filter(|file| {
                file.title.to_ascii_lowercase().contains(&query)
                    || file.relative_path.to_ascii_lowercase().contains(&query)
            })
            .collect()
    }

    pub fn len(&self) -> usize {
        self.files.len()
    }

    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use std::{fs, path::PathBuf};

    use super::*;

    #[test]
    fn index_searches_title_and_path_metadata() {
        let mut index = InMemoryIndex::default();
        index.upsert_scanned_file(&MarkdownFile {
            path: PathBuf::from("/vault/deep/ai-note.md"),
            relative_path: PathBuf::from("deep/ai-note.md"),
            extension: "md".to_string(),
            size_bytes: 12,
            modified_at: 1,
        });

        assert_eq!(index.search("ai note").len(), 1);
        assert_eq!(index.search("deep").len(), 1);
        assert_eq!(index.search("missing").len(), 0);
    }

    #[test]
    fn sqlite_index_refreshes_and_searches_metadata() {
        let root = tempfile::tempdir().unwrap();
        fs::write(root.path().join("alpha-note.md"), "# Alpha Title").unwrap();
        fs::write(root.path().join("ignore.txt"), "ignore").unwrap();
        let files = crate::scanner::scan_markdown_files(root.path()).unwrap();
        let mut index = MetadataIndex::open_memory().unwrap();

        index.refresh_from_scan(&files).unwrap();

        assert_eq!(index.len().unwrap(), 1);
        assert_eq!(index.search("alpha").unwrap().len(), 1);
        assert_eq!(index.search("ignore").unwrap().len(), 0);
    }

    #[test]
    fn sqlite_index_removes_missing_files_on_refresh() {
        let root = tempfile::tempdir().unwrap();
        let note_path = root.path().join("remove-me.md");
        fs::write(&note_path, "# Remove Me").unwrap();
        let mut index = MetadataIndex::open_memory().unwrap();

        let files = crate::scanner::scan_markdown_files(root.path()).unwrap();
        index.refresh_from_scan(&files).unwrap();
        fs::remove_file(note_path).unwrap();
        let files = crate::scanner::scan_markdown_files(root.path()).unwrap();
        index.refresh_from_scan(&files).unwrap();

        assert_eq!(index.len().unwrap(), 0);
    }

    #[test]
    fn title_enrichment_reads_small_files_only() {
        let root = tempfile::tempdir().unwrap();
        fs::write(root.path().join("plain-name.md"), "# Real Title\n\nBody").unwrap();
        let files = crate::scanner::scan_markdown_files(root.path()).unwrap();
        let mut index = MetadataIndex::open_memory().unwrap();
        index.refresh_from_scan(&files).unwrap();

        assert_eq!(
            index.get("plain-name.md").unwrap().unwrap().title,
            "plain name"
        );
        assert!(index.enrich_title_from_file("plain-name.md", 1024).unwrap());
        assert_eq!(
            index.get("plain-name.md").unwrap().unwrap().title,
            "Real Title"
        );
        assert!(!index.enrich_title_from_file("plain-name.md", 1).unwrap());
    }
}
