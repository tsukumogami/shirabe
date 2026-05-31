//! Intermediate representation types for parsed shirabe doc files.

use std::collections::HashMap;

/// Intermediate representation of a parsed shirabe doc file.
#[derive(Debug, Clone)]
pub struct Doc {
    pub path: String,
    pub schema: String,
    pub status: String,
    /// Frontmatter fields with absolute (1-indexed) line numbers.
    pub fields: HashMap<String, FieldValue>,
    /// `## ` headings with absolute (1-indexed) line numbers.
    pub sections: Vec<Section>,
    /// Raw body lines, used by FC03 and `check_vision_public`.
    pub body: Vec<String>,
}

/// A frontmatter field's string value and its 1-indexed line number.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldValue {
    pub value: String,
    pub line: usize,
}

/// A `## ` heading name and its 1-indexed line number.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Section {
    pub name: String,
    pub line: usize,
}

/// A single validation failure, mapped 1:1 to a GHA annotation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationError {
    pub file: String,
    pub line: usize,
    /// One of "FC01", "FC02", "FC03", "FC04", "R6", "R7", "SCHEMA".
    pub code: String,
    pub message: String,
}
