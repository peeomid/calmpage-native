use std::{fs, path::Path};

use pulldown_cmark::{Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use serde::{Deserialize, Serialize};

use crate::{CoreError, Result};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Heading {
    pub level: u8,
    pub title: String,
    pub anchor: String,
    pub ordinal: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderedNote {
    pub title: String,
    pub article_html: String,
    pub headings: Vec<Heading>,
}

pub fn render_note_from_markdown(markdown: &str, note_path: &str) -> RenderedNote {
    RenderedNote {
        title: readmd::renderer::note_title(markdown, note_path),
        article_html: readmd::renderer::render_markdown(markdown),
        headings: extract_headings(markdown),
    }
}

pub fn render_note_from_file(path: impl AsRef<Path>) -> Result<RenderedNote> {
    let path = path.as_ref();
    let markdown = fs::read_to_string(path).map_err(|source| CoreError::ReadFile {
        path: path.to_path_buf(),
        source,
    })?;
    Ok(render_note_from_markdown(
        &markdown,
        &path.to_string_lossy(),
    ))
}

pub fn extract_headings(markdown: &str) -> Vec<Heading> {
    let (_frontmatter, body) = readmd::renderer::split_frontmatter(markdown);
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_FOOTNOTES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    options.insert(Options::ENABLE_TASKLISTS);
    options.insert(Options::ENABLE_HEADING_ATTRIBUTES);

    let mut headings = Vec::new();
    let mut active_heading: Option<(u8, String)> = None;
    for event in Parser::new_ext(body, options) {
        match event {
            Event::Start(Tag::Heading { level, .. }) => {
                active_heading = Some((heading_level(level), String::new()));
            }
            Event::Text(text) | Event::Code(text) => {
                if let Some((_level, title)) = &mut active_heading {
                    title.push_str(&text);
                }
            }
            Event::End(TagEnd::Heading(_)) => {
                if let Some((level, title)) = active_heading.take() {
                    if level <= 3 && !title.trim().is_empty() {
                        let ordinal = headings.len();
                        headings.push(Heading {
                            level,
                            anchor: anchor_for(&title, ordinal),
                            title: title.trim().to_string(),
                            ordinal,
                        });
                    }
                }
            }
            _ => {}
        }
    }

    headings
}

fn heading_level(level: HeadingLevel) -> u8 {
    match level {
        HeadingLevel::H1 => 1,
        HeadingLevel::H2 => 2,
        HeadingLevel::H3 => 3,
        HeadingLevel::H4 => 4,
        HeadingLevel::H5 => 5,
        HeadingLevel::H6 => 6,
    }
}

fn anchor_for(title: &str, ordinal: usize) -> String {
    let slug = title
        .chars()
        .filter_map(|ch| {
            if ch.is_ascii_alphanumeric() {
                Some(ch.to_ascii_lowercase())
            } else if ch.is_whitespace() || ch == '-' || ch == '_' {
                Some('-')
            } else {
                None
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    if slug.is_empty() {
        format!("heading-{ordinal}")
    } else {
        slug
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn render_uses_readmd_title_and_sanitized_html() {
        let note = render_note_from_markdown(
            "---\ntitle: Safe title\n---\n# Heading\n\n<script>alert('x')</script>\n\n- [x] Done",
            "note.md",
        );

        assert_eq!(note.title, "Safe title");
        assert!(note.article_html.contains("Document details"));
        assert!(note.article_html.contains("type=\"checkbox\""));
        assert!(!note.article_html.contains("<script>"));
        assert_eq!(note.headings[0].title, "Heading");
    }

    #[test]
    fn heading_extraction_keeps_h1_to_h3_only() {
        let headings = extract_headings("# One\n\n## Two\n\n### Three\n\n#### Four");

        assert_eq!(headings.len(), 3);
        assert_eq!(headings[1].anchor, "two");
    }
}
