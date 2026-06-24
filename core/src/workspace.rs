use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RootFolder {
    pub id: String,
    pub path: PathBuf,
    pub display_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub roots: Vec<RootFolder>,
}

impl Workspace {
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            roots: Vec::new(),
        }
    }

    pub fn add_root(&mut self, root: RootFolder) {
        if self.roots.iter().any(|existing| existing.path == root.path) {
            return;
        }
        self.roots.push(root);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_deduplicates_root_paths() {
        let mut workspace = Workspace::new("default", "Default");
        let root = RootFolder {
            id: "root-1".to_string(),
            path: PathBuf::from("/vault"),
            display_name: "vault".to_string(),
        };

        workspace.add_root(root.clone());
        workspace.add_root(root);

        assert_eq!(workspace.roots.len(), 1);
    }
}
