//! Repo-visibility resolution for the file-level `validate` pass.
//!
//! Mirrors the idiom every shirabe skill uses to decide whether a doc's
//! owning repo is Public or Private (see `skills/strategy` Phase 0.4):
//!
//!   1. Read the owning repo's `CLAUDE.md` (or `CLAUDE.local.md`) and look
//!      for a `## Repo Visibility: (Public|Private)` header.
//!   2. If absent, infer from the path: a `private` path component implies
//!      Private, a `public` component implies Public.
//!   3. If still unknown, default to Private — restricting is easier to undo
//!      than oversharing.
//!
//! The visibility-gated checks (R7/R8/R9) bypass only on exactly `"private"`;
//! every other value (including `"public"`) runs the check. This module returns
//! the lowercase string that both the `--visibility` flag and
//! [`crate::doc::Config::visibility`] carry, so the CLI's auto-detection and the
//! skills' hand-detection resolve visibility the same way and cannot drift.

use std::path::{Component, Path};

/// The visibility string that bypasses the public-repo checks.
pub const PRIVATE: &str = "private";
/// The visibility string that runs the public-repo checks.
pub const PUBLIC: &str = "public";

/// Parse a `## Repo Visibility: (Public|Private)` header out of a `CLAUDE.md`
/// body. Case-insensitive on both the header key and the value; returns the
/// lowercase `"public"` / `"private"` string, or `None` when no well-formed
/// header is present. A header with an unrecognized value is skipped, not an
/// error — a later well-formed header (if any) still wins.
pub fn parse_visibility_header(contents: &str) -> Option<String> {
    const KEY: &str = "## repo visibility:";
    for line in contents.lines() {
        let lower = line.trim().to_ascii_lowercase();
        if let Some(value) = lower.strip_prefix(KEY) {
            let value = value.trim();
            if value.starts_with(PRIVATE) {
                return Some(PRIVATE.to_string());
            }
            if value.starts_with(PUBLIC) {
                return Some(PUBLIC.to_string());
            }
        }
    }
    None
}

/// Infer visibility from the path's components. A `private` component implies
/// Private; a `public` component implies Public. Components are walked from the
/// leaf upward, so the component nearest the doc wins when both appear.
pub fn infer_visibility_from_path(path: &Path) -> Option<String> {
    for comp in path.components().rev() {
        if let Component::Normal(os) = comp {
            let s = os.to_string_lossy();
            if s.eq_ignore_ascii_case(PRIVATE) {
                return Some(PRIVATE.to_string());
            }
            if s.eq_ignore_ascii_case(PUBLIC) {
                return Some(PUBLIC.to_string());
            }
        }
    }
    None
}

/// Walk up from `path`'s directory, returning the first CLAUDE.md header
/// value that `extract` accepts.
///
/// `CLAUDE.local.md` is preferred over `CLAUDE.md` at each level, and a file
/// carrying no matching header does not stop the walk: a nested workspace
/// keeps per-repo headers below workspace-level files that lack them.
///
/// The walk stops at the first directory containing `.git`. Without that
/// bound a declaration placed *above* a repository root reaches inside it,
/// which for a vocabulary header means a file outside the repo suppressing
/// findings within it. `resolve_doc_visibility` predates the bound and
/// keeps its unbounded behavior, since narrowing it would change how
/// existing repos resolve visibility; new headers get the bounded walk.
pub fn resolve_claude_md_header<T>(
    path: &Path,
    extract: impl Fn(&str) -> Option<T>,
    stop_at_repo_root: bool,
) -> Option<T> {
    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let mut dir = canonical.parent();
    while let Some(d) = dir {
        for name in ["CLAUDE.local.md", "CLAUDE.md"] {
            if let Ok(contents) = std::fs::read_to_string(d.join(name)) {
                if let Some(v) = extract(&contents) {
                    return Some(v);
                }
            }
        }
        if stop_at_repo_root && d.join(".git").exists() {
            return None;
        }
        dir = d.parent();
    }
    None
}

/// Resolve the visibility (`"public"` or `"private"`) for the doc at `path`,
/// applying the skills' idiom end to end. Filesystem-touching but never
/// errors: an unresolvable path defaults to `"private"` (fail safe toward
/// restriction).
pub fn resolve_doc_visibility(path: &Path) -> String {
    // Canonicalize so the ancestor walk is absolute and stable regardless of
    // the process CWD. Fall back to the raw path if canonicalization fails
    // (e.g. a relative path whose file was already consumed) — the walk still
    // works on whatever path we have, and path inference below is CWD-relative
    // either way.
    let canonical = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());

    // 1. Walk up from the doc's directory; the first CLAUDE.local.md / CLAUDE.md
    //    that carries a `## Repo Visibility:` header wins. A CLAUDE.md without
    //    the header does not stop the walk (a nested workspace layout keeps the
    //    per-repo header below workspace-level CLAUDE.md files that lack it).
    let mut dir = canonical.parent();
    while let Some(d) = dir {
        for name in ["CLAUDE.local.md", "CLAUDE.md"] {
            if let Ok(contents) = std::fs::read_to_string(d.join(name)) {
                if let Some(v) = parse_visibility_header(&contents) {
                    return v;
                }
            }
        }
        dir = d.parent();
    }

    // 2. Infer from the path components.
    if let Some(v) = infer_visibility_from_path(&canonical) {
        return v;
    }

    // 3. Default: restricting is easier to undo than oversharing.
    PRIVATE.to_string()
}

/// Parse a `## Prose Vocabulary: a, b, c` header out of a CLAUDE.md body.
///
/// Comma-delimited rather than whitespace-delimited because the rule list
/// carries multi-word terms (`align with`). Values are trimmed, lowercased,
/// and empties dropped. An empty declaration and an absent one both mean
/// "suppress nothing", which is the documented default.
///
/// The value is capped, following the precedent set for the other
/// adopter-supplied list input. Terms are used only as literal match
/// strings and are never compiled as patterns: compiling adopter input as
/// a regex would be a denial-of-service surface.
pub fn parse_prose_vocabulary_header(contents: &str) -> Option<Vec<String>> {
    const KEY: &str = "## prose vocabulary:";
    const MAX_VALUE_BYTES: usize = 64 * 1024;

    for line in contents.lines() {
        let trimmed = line.trim();
        let lower = trimmed.to_ascii_lowercase();
        if let Some(rest) = lower.strip_prefix(KEY) {
            let rest = if rest.len() > MAX_VALUE_BYTES {
                &rest[..MAX_VALUE_BYTES]
            } else {
                rest
            };
            let terms: Vec<String> = rest
                .split(',')
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty())
                .collect();
            return Some(terms);
        }
    }
    None
}

/// Resolve a repository's declared prose vocabulary for the doc at `path`.
///
/// Returns the empty vector when no header is found: nothing is suppressed
/// by default, and no allowance is made for a repository that has not
/// declared itself. Unlike visibility there is nothing to fail safe toward,
/// so there is no path inference and no non-empty default.
///
/// Resolution is per file rather than per run, which is what keeps a term
/// declared in one repository from suppressing it in another during a
/// single invocation spanning both.
pub fn resolve_prose_vocabulary(path: &Path) -> Vec<String> {
    resolve_claude_md_header(path, |c| parse_prose_vocabulary_header(c), true).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn unique_dir(tag: &str) -> PathBuf {
        // Derive a per-test directory name without Date/Random (unavailable in
        // this crate's test sandbox is not a concern here, but a stable name
        // keeps parallel test runs isolated by tag).
        let base = std::env::temp_dir();
        let dir = base.join(format!("shirabe-visibility-test-{tag}"));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn parse_header_public_and_private() {
        assert_eq!(
            parse_visibility_header("# repo\n\n## Repo Visibility: Public\n"),
            Some("public".to_string())
        );
        assert_eq!(
            parse_visibility_header("## Repo Visibility: Private\n"),
            Some("private".to_string())
        );
    }

    #[test]
    fn parse_header_is_case_insensitive() {
        assert_eq!(
            parse_visibility_header("## repo visibility: PRIVATE"),
            Some("private".to_string())
        );
    }

    #[test]
    fn parse_header_absent_or_malformed_is_none() {
        assert_eq!(parse_visibility_header("# repo\n\nno header here"), None);
        assert_eq!(
            parse_visibility_header("## Repo Visibility: internal"),
            None
        );
        // A prose mention that is not a header line must not match.
        assert_eq!(
            parse_visibility_header("See the ## Repo Visibility: Public note above"),
            None
        );
    }

    #[test]
    fn infer_from_path_prefers_nearest_component() {
        assert_eq!(
            infer_visibility_from_path(Path::new("private/vision/docs/x.md")),
            Some("private".to_string())
        );
        assert_eq!(
            infer_visibility_from_path(Path::new("public/shirabe/docs/x.md")),
            Some("public".to_string())
        );
        // Deepest component wins when both appear.
        assert_eq!(
            infer_visibility_from_path(Path::new("public/x/private/y/z.md")),
            Some("private".to_string())
        );
        assert_eq!(infer_visibility_from_path(Path::new("docs/x.md")), None);
    }

    #[test]
    fn resolve_reads_owning_repo_header() {
        let dir = unique_dir("header");
        let repo = dir.join("myrepo");
        let docs = repo.join("docs/strategies");
        fs::create_dir_all(&docs).unwrap();
        fs::write(
            repo.join("CLAUDE.md"),
            "# myrepo\n\n## Repo Visibility: Private\n",
        )
        .unwrap();
        let doc = docs.join("STRATEGY-x.md");
        fs::write(&doc, "body").unwrap();
        assert_eq!(resolve_doc_visibility(&doc), "private");
    }

    #[test]
    fn resolve_claude_local_overrides_claude_md() {
        let dir = unique_dir("local");
        let repo = dir.join("myrepo");
        fs::create_dir_all(&repo).unwrap();
        fs::write(repo.join("CLAUDE.md"), "## Repo Visibility: Public\n").unwrap();
        fs::write(
            repo.join("CLAUDE.local.md"),
            "## Repo Visibility: Private\n",
        )
        .unwrap();
        let doc = repo.join("DESIGN-x.md");
        fs::write(&doc, "body").unwrap();
        // CLAUDE.local.md is consulted first in each directory.
        assert_eq!(resolve_doc_visibility(&doc), "private");
    }

    #[test]
    fn resolve_falls_back_to_path_when_no_header() {
        let dir = unique_dir("pathinfer");
        let repo = dir.join("public").join("somerepo");
        fs::create_dir_all(&repo).unwrap();
        // A header-less CLAUDE.md must not stop the walk or force a default.
        fs::write(
            repo.join("CLAUDE.md"),
            "# somerepo\n\nno visibility header\n",
        )
        .unwrap();
        let doc = repo.join("STRATEGY-x.md");
        fs::write(&doc, "body").unwrap();
        assert_eq!(resolve_doc_visibility(&doc), "public");
    }

    #[test]
    fn resolve_defaults_private_when_unknown() {
        let dir = unique_dir("default");
        let repo = dir.join("neutralrepo");
        fs::create_dir_all(&repo).unwrap();
        let doc = repo.join("STRATEGY-x.md");
        fs::write(&doc, "body").unwrap();
        // No header anywhere up the tree, no public/private path component:
        // the safe default is Private.
        assert_eq!(resolve_doc_visibility(&doc), "private");
    }
}
