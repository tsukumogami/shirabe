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
