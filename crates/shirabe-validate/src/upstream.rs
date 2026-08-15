//! The single path from a parsed `upstream:` field to the entries its
//! readers walk.
//!
//! Three readers consume `upstream:`: the R6 resolution check
//! (`checks::check_upstream_resolves`), the lifecycle chain walk
//! (`lifecycle::extract_upstreams`), and the finalization walk
//! (`finalize::walk_chain_mode`). Each used to normalize the field itself,
//! and they disagreed on every question a normalizer has to answer. Reader
//! agreement is now a property of there being one reader rather than
//! something to check three ways.
//!
//! The four semantics are chosen, not merely centralized:
//!
//! 1. **A placeholder-shaped entry is skipped**, rather than reaching path
//!    resolution. This is the chain walk's long-standing behavior, and it
//!    converts what was a tool error on the finalization path (an unwritten
//!    `upstream: <PRD path>` failing path validation) into a clean
//!    termination.
//! 2. **A cross-repo `owner/repo:path` reference is marked, not removed.**
//!    The distinction is load-bearing on the mutation path: the finalization
//!    walk stops at a cross-repo upstream and reports a node saying so, and
//!    it can only stop at an entry it can see. The validator skips them; the
//!    walk stops at them; both need the entry present to do so.
//! 3. **Entries are trimmed and blank entries dropped**, following the chain
//!    walk.
//! 4. **Entries come back as written, not resolved against a root.**
//!    Resolution stays with each caller because the two callers that resolve
//!    today anchor against different bases -- the chain walk joins a
//!    canonical repo root, the R6 check tests the value against the process
//!    working directory -- and unifying that is a behavior change this
//!    module does not make.

use crate::doc::{Doc, FieldEntries, FieldValue};

/// One `upstream:` entry, normalized but not resolved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpstreamEntry {
    /// The entry's text as the author wrote it, trimmed. Never joined onto
    /// a root: see this module's semantic 4.
    pub value: String,
    /// Whether the entry is a cross-repo `owner/repo:path` reference, which
    /// names a file in another repository and so does not resolve as a
    /// local path. A marked entry stays in the list (semantic 2); what a
    /// reader does with it is the reader's decision.
    pub cross_repo: bool,
}

/// What one written entry turned out to be.
///
/// The walking readers only want the paths, and [`field_entries`] hands
/// them exactly that. The R6 check needs the three cases apart, because it
/// says something different about each: a blank entry is a finding, a
/// placeholder is a silent skip, a path gets resolved. Both go through
/// [`classify`], so there is still one answer to "what did the author
/// write here" rather than two.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Entry {
    /// Empty after trimming: `- ` on its own, or `""`.
    Blank,
    /// An unfilled template placeholder (semantic 1).
    Placeholder,
    /// Something a reader can try to resolve.
    Path(UpstreamEntry),
}

/// The entries of a doc's `upstream:` field, in written order. An absent
/// field yields none, and so does a field whose value is neither a scalar
/// nor a sequence.
pub fn upstream_entries(doc: &Doc) -> Vec<UpstreamEntry> {
    match doc.fields.get("upstream") {
        Some(field) => field_entries(field),
        None => Vec::new(),
    }
}

/// The entries of an already-looked-up field, for a caller that needs the
/// field itself (its line number, or whether it was present at all).
///
/// A scalar contributes exactly one entry holding its whole text -- a
/// scalar is never split, so a multi-line value stays one entry rather than
/// becoming several paths. A sequence contributes one entry per item.
pub fn field_entries(field: &FieldValue) -> Vec<UpstreamEntry> {
    let texts: Vec<&str> = match &field.entries {
        FieldEntries::Scalar(text) => vec![text.as_str()],
        FieldEntries::Sequence(items) => items.iter().map(String::as_str).collect(),
        // A mapping, a tagged node, or an alias names no upstream. Issue 3
        // gives this shape its own finding; here it simply has no entries.
        FieldEntries::Other => Vec::new(),
    };
    texts.into_iter().filter_map(normalize).collect()
}

/// Normalize one entry's source text, or drop it.
fn normalize(text: &str) -> Option<UpstreamEntry> {
    match classify(text) {
        Entry::Path(entry) => Some(entry),
        Entry::Blank | Entry::Placeholder => None,
    }
}

/// Classify one entry's source text: trim it, then decide whether it names
/// anything a reader could resolve.
pub fn classify(text: &str) -> Entry {
    let value = text.trim();
    if value.is_empty() {
        return Entry::Blank;
    }
    if is_placeholder(value) {
        return Entry::Placeholder;
    }
    Entry::Path(UpstreamEntry {
        value: value.to_string(),
        cross_repo: is_cross_repo_reference(value),
    })
}

/// Whether an entry is an unfilled template placeholder (`<PRD path>`,
/// `docs/prds/PRD-<slug>.md`) rather than something a reader should try to
/// resolve. The angle brackets are the marker every doc template uses.
fn is_placeholder(value: &str) -> bool {
    value.contains('<') || value.contains('>')
}

/// Reports whether an `upstream` value is a cross-repo reference in the
/// `owner/repo:path` convention (see `references/cross-repo-references.md`)
/// rather than a repo-relative path.
///
/// The discriminator is a `:` whose preceding text is an `owner/repo`
/// selector -- it contains a `/` and no space. `owner/repo:docs/prds/PRD-x.md`
/// qualifies; `docs/prds/PRD-x.md` has no colon, and `weird:name.md` has no
/// `/` before it. The check is deliberately narrow so a malformed local path
/// still reports rather than silently passing as "cross-repo".
pub fn is_cross_repo_reference(value: &str) -> bool {
    match value.find(':') {
        Some(idx) => {
            let selector = &value[..idx];
            selector.contains('/') && !selector.contains(' ')
        }
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field(entries: FieldEntries) -> FieldValue {
        FieldValue {
            value: String::new(),
            line: 1,
            entries,
        }
    }

    fn values(field: &FieldValue) -> Vec<String> {
        field_entries(field).into_iter().map(|e| e.value).collect()
    }

    #[test]
    fn scalar_is_one_entry_holding_its_whole_text() {
        let f = field(FieldEntries::Scalar("docs/prds/PRD-x.md".to_string()));
        assert_eq!(values(&f), vec!["docs/prds/PRD-x.md"]);
    }

    #[test]
    fn a_multi_line_scalar_is_never_split_into_paths() {
        let f = field(FieldEntries::Scalar("first line\nsecond line".to_string()));
        assert_eq!(values(&f), vec!["first line\nsecond line"]);
    }

    #[test]
    fn sequence_entries_keep_written_order() {
        let f = field(FieldEntries::Sequence(vec![
            "docs/a.md".to_string(),
            "docs/b.md".to_string(),
        ]));
        assert_eq!(values(&f), vec!["docs/a.md", "docs/b.md"]);
    }

    #[test]
    fn entries_are_trimmed_and_blanks_dropped() {
        let f = field(FieldEntries::Sequence(vec![
            "  docs/a.md  ".to_string(),
            "   ".to_string(),
            String::new(),
        ]));
        assert_eq!(values(&f), vec!["docs/a.md"]);
    }

    #[test]
    fn placeholder_entries_are_skipped() {
        let f = field(FieldEntries::Sequence(vec![
            "docs/prds/PRD-<slug>.md".to_string(),
            "docs/a.md".to_string(),
            "<PRD path>".to_string(),
        ]));
        assert_eq!(values(&f), vec!["docs/a.md"]);
    }

    #[test]
    fn cross_repo_entries_are_marked_not_removed() {
        let f = field(FieldEntries::Sequence(vec![
            "owner/repo:docs/prds/PRD-x.md".to_string(),
            "docs/a.md".to_string(),
        ]));
        let entries = field_entries(&f);
        assert_eq!(entries.len(), 2, "the cross-repo entry stays in the list");
        assert!(entries[0].cross_repo);
        assert!(!entries[1].cross_repo);
    }

    #[test]
    fn a_non_scalar_non_sequence_value_has_no_entries() {
        assert!(field_entries(&field(FieldEntries::Other)).is_empty());
    }

    #[test]
    fn an_empty_sequence_has_no_entries() {
        assert!(field_entries(&field(FieldEntries::Sequence(Vec::new()))).is_empty());
    }

    #[test]
    fn absent_field_yields_no_entries() {
        let doc = Doc {
            path: "docs/plans/PLAN-x.md".to_string(),
            schema: "plan/v1".to_string(),
            status: "Active".to_string(),
            fields: std::collections::HashMap::new(),
            sections: Vec::new(),
            body: Vec::new(),
            body_start_line: 1,
        };
        assert!(upstream_entries(&doc).is_empty());
    }

    #[test]
    fn classify_keeps_blank_and_placeholder_apart() {
        // `field_entries` drops both, but R6 says something different
        // about each, so the classification has to distinguish them.
        assert_eq!(classify("  "), Entry::Blank);
        assert_eq!(classify("<PRD path>"), Entry::Placeholder);
        assert_eq!(
            classify(" docs/a.md "),
            Entry::Path(UpstreamEntry {
                value: "docs/a.md".to_string(),
                cross_repo: false,
            })
        );
    }

    #[test]
    fn cross_repo_discriminator() {
        assert!(is_cross_repo_reference("owner/repo:docs/prds/PRD-x.md"));
        assert!(!is_cross_repo_reference("docs/prds/PRD-x.md"));
        assert!(!is_cross_repo_reference("weird:name.md"));
        // A space before the colon is not an `owner/repo` selector.
        assert!(!is_cross_repo_reference("see also/other:docs/x.md"));
    }
}
