//! Intermediate representation types for parsed shirabe doc files.

use std::collections::HashMap;

/// Optional overrides for the validation run.
///
/// Shared by `checks.rs` (the individual checks) and `validate.rs` (the
/// `validate_file` driver). The crate root re-exports this as
/// `validate::Config` to match the design's public surface.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Config {
    /// Format schema version -> replacement status enum. When present for
    /// a schema version, the custom list replaces (does not extend) the
    /// format's canonical valid statuses.
    pub custom_statuses: HashMap<String, Vec<String>>,
    /// `"public"` | `"private"` | `""`. Visibility-gated checks (R7/R8)
    /// are bypassed only when this is exactly `"private"`.
    pub visibility: String,
    /// When `true`, the chain-aware L06 outline-AC completeness check
    /// is suppressed (returns no findings). Default `false`. The
    /// `--allow-untracked-acs` CLI flag sets this; the cascade script
    /// forwards `WORK_ON_ALLOW_UNTRACKED_ACS=1` by passing the flag.
    /// L01-L05 are unaffected — only L06 honors this setting.
    pub allow_untracked_acs: bool,
}

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
    /// 1-indexed file line on which `body[0]` sits.
    ///
    /// Body-relative indices are what a check naturally has; the line an
    /// author sees is what a finding must carry. Without this offset a
    /// finding on `body[i]` reports `i + 1`, which is short by the length
    /// of the frontmatter — on a 24-line frontmatter, line 38 for an
    /// occurrence at 62. A document with no frontmatter has `1` here, so
    /// the arithmetic is uniform rather than conditional.
    pub body_start_line: usize,
}

/// A frontmatter field's string value and its 1-indexed line number.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldValue {
    /// The field's scalar text: the source text for a scalar, the empty
    /// string for every other YAML shape (sequence, mapping, alias).
    ///
    /// This is what the FC02/FC03 annotation bytes are built from, and the
    /// cross-implementation parity gate compares those bytes against a
    /// frozen baseline. It stays the empty string for a sequence. Readers
    /// that want a sequence's items read [`FieldValue::entries`].
    pub value: String,
    pub line: usize,
    /// The field's value decomposed into entries, preserving written order.
    pub entries: FieldEntries,
}

/// A frontmatter field's value by YAML shape, carrying each entry's
/// original source text.
///
/// The three shapes stay distinct rather than collapsing into one list,
/// because a value that is neither a scalar nor a sequence is a distinct
/// authoring mistake from an empty sequence and is reported as such.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldEntries {
    /// A scalar. Exactly one entry holding the whole text, never split on
    /// newlines: a `problem: |` block scalar is one value, not many.
    Scalar(String),
    /// A sequence, one entry per item in written order, for both block
    /// (`- a`) and flow (`[a, b]`) syntax. Empty for `[]`. An item that is
    /// itself a sequence or mapping contributes an empty entry, so entry
    /// count and position still match what the author wrote.
    Sequence(Vec<String>),
    /// Neither a scalar nor a sequence: a mapping, a tagged node, or an
    /// alias.
    Other,
}

impl FieldValue {
    /// Build a scalar field value, keeping `value` and the single entry in
    /// agreement.
    pub fn scalar(value: impl Into<String>, line: usize) -> Self {
        let value = value.into();
        Self {
            entries: FieldEntries::Scalar(value.clone()),
            value,
            line,
        }
    }
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
    /// One of "FC01", "FC02", "FC03", "FC04", "FC05", "FC06", "R6", "R7",
    /// "R8", "SCHEMA".
    pub code: String,
    pub message: String,
}
