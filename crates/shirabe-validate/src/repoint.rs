//! Rewriting inbound references when a lifecycle transition moves a
//! document.
//!
//! This is the prevention half of the stale-reference problem, and it is
//! the half that stops it recurring. `FC18` finds references broken by moves
//! that already happened; the repoint means no new one is ever created.
//!
//! It decides nothing. The transition hands it the old path and the new
//! one, both from its own resolved `Moves` entry rather than from document
//! text, so there is no inference and no basename lookup here -- the parts
//! `FC18` needs precisely because it arrives after the fact.
//!
//! Four properties are worth stating because each is a way to get this
//! wrong.
//!
//! **A rewrite is a substitution, never a re-render.** The pass replaces
//! byte ranges in the original text and writes the result back. It does not
//! parse a document and print it again, which is how a formatter-shaped
//! tool silently reflows content nobody asked it to touch. The diff of a
//! repointed file can therefore be asserted to contain only the substituted
//! substrings.
//!
//! **Substitution runs right to left.** Applying edits in ascending order
//! invalidates every later range as soon as a replacement differs in length
//! from the original, and it always does here.
//!
//! **Relative forms are matched by resolution, not by string.** A referrer
//! that wrote `../designs/DESIGN-a.md` names the same document as one that
//! wrote `docs/designs/DESIGN-a.md`. Comparing raw strings would repoint
//! the second and leave the first, which is worse than leaving both: the
//! corpus ends up with two conventions for one edge and no signal that one
//! of them is stale. A rewritten relative reference stays relative.
//!
//! **Failure is a refusal, not a rollback.** Every file is read and its
//! edits computed before any file is written, so the common failure -- an
//! unreadable file, a permission error -- lands while nothing has changed.
//! A write that fails midway reports the file that failed and the files
//! already rewritten, and the caller exits non-zero. There is deliberately
//! no automatic undo: everything is staged in git, so `git checkout` is a
//! better recovery than a bespoke rollback path that only ever runs on the
//! day it is needed.
//!
//! The finding cap the prose checks apply is **not** applied here.
//! Truncating a rewrite leaves a file half-repointed, which is worse than
//! not repointing it at all. The cap is a reporting policy, not an editing
//! one.

use std::path::{Component, Path};

use crate::references;

/// One file the pass rewrote, and how many occurrences it replaced.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileRewrite {
    /// Repo-relative path, as `git ls-files` reported it.
    pub path: String,
    pub occurrences: usize,
}

/// Why a repoint could not complete.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RepointError {
    /// A tracked file could not be read. Nothing has been written.
    Read { path: String, detail: String },
    /// A write or a stage failed partway through. `rewritten` names the
    /// files already changed on disk.
    Partial {
        path: String,
        detail: String,
        action: &'static str,
        rewritten: Vec<String>,
    },
}

impl RepointError {
    /// The operator-facing message, naming the failing file and -- for a
    /// mid-run failure -- everything already rewritten, so recovery does
    /// not start with a search.
    pub fn message(&self) -> String {
        match self {
            RepointError::Read { path, detail } => {
                format!("repoint aborted before writing anything: failed to read {path}: {detail}")
            }
            RepointError::Partial {
                path,
                detail,
                action,
                rewritten,
            } => {
                let already = if rewritten.is_empty() {
                    "none".to_string()
                } else {
                    rewritten.join(", ")
                };
                format!("repoint failed to {action} {path}: {detail}; already rewritten: {already}")
            }
        }
    }
}

/// Rewrite every reference to `old_rel` as `new_rel` across the tracked
/// markdown of the work tree at `root`, staging each rewritten file.
///
/// `old_rel` and `new_rel` are repo-relative. Returns one entry per file
/// changed, in `git ls-files` order; an empty result means nothing referred
/// to the old path, which is what a second run over the same tree reports
/// rather than failing.
pub fn repoint_references(
    root: &Path,
    old_rel: &str,
    new_rel: &str,
) -> Result<Vec<FileRewrite>, RepointError> {
    if old_rel == new_rel {
        return Ok(Vec::new());
    }

    let mut planned: Vec<(String, String, usize)> = Vec::new();

    // Phase 1: read everything and compute every edit. Nothing is written
    // until the whole plan is in hand.
    for rel in tracked_markdown(root) {
        let abs = root.join(&rel);
        let bytes = match std::fs::read(&abs) {
            Ok(b) => b,
            // A tracked path with no file on disk is a staged deletion. It
            // carries no reference to rewrite, and failing the transition
            // over one would be a refusal nobody can act on.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
            Err(e) => {
                return Err(RepointError::Read {
                    path: rel,
                    detail: e.to_string(),
                })
            }
        };
        // A `.md` that is not UTF-8 is not a document this pass can reason
        // about, and re-encoding one would corrupt it.
        let Ok(text) = String::from_utf8(bytes) else {
            continue;
        };

        let Some((updated, occurrences)) = rewrite_text(&text, &abs, root, old_rel, new_rel) else {
            continue;
        };
        planned.push((rel, updated, occurrences));
    }

    // Phase 2: write and stage. A failure here names what has already
    // changed rather than attempting an undo.
    let mut rewrites: Vec<FileRewrite> = Vec::new();
    for (rel, updated, occurrences) in planned {
        let abs = root.join(&rel);
        if let Err(e) = std::fs::write(&abs, updated) {
            return Err(RepointError::Partial {
                path: rel,
                detail: e.to_string(),
                action: "write",
                rewritten: rewrites.into_iter().map(|r| r.path).collect(),
            });
        }
        if let Err(detail) = git_add(root, &rel) {
            return Err(RepointError::Partial {
                path: rel,
                detail,
                action: "stage",
                rewritten: rewrites.into_iter().map(|r| r.path).collect(),
            });
        }
        rewrites.push(FileRewrite {
            path: rel,
            occurrences,
        });
    }

    Ok(rewrites)
}

/// The tracked markdown of the work tree at `root`.
///
/// `git ls-files` rather than a directory walk: it excludes untracked
/// scratch, honors the repository's ignore rules, and is the same index the
/// transition is already staging into. Outside a repository it reports
/// nothing, which turns the repoint into a no-op rather than an error.
fn tracked_markdown(root: &Path) -> Vec<String> {
    let output = std::process::Command::new("git")
        .arg("-C")
        .arg(root)
        .arg("ls-files")
        .arg("--")
        .arg("*.md")
        .output();
    let Ok(out) = output else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect()
}

/// `git -C <root> add -- <path>`, as an argument vector.
///
/// Never an interpolated shell string, and the `--` separator is there so a
/// filename beginning with a dash cannot become a flag. Same discipline as
/// the `git mv` this pass follows.
fn git_add(root: &Path, rel: &str) -> Result<(), String> {
    let status = std::process::Command::new("git")
        .arg("-C")
        .arg(root)
        .arg("add")
        .arg("--")
        .arg(rel)
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err("git add failed".to_string())
    }
}

/// Compute one file's rewritten text, or `None` when it names the old path
/// nowhere.
///
/// Exposed to the tests so the substitution can be exercised without a
/// repository.
pub(crate) fn rewrite_text(
    text: &str,
    file: &Path,
    root: &Path,
    old_rel: &str,
    new_rel: &str,
) -> Option<(String, usize)> {
    // A cheap reject before any parsing: a file that does not contain the
    // old path's basename cannot refer to it in any form.
    let basename = old_rel.rsplit('/').next().unwrap_or(old_rel);
    if !text.contains(basename) {
        return None;
    }

    let lines = split_keeping_terminators(text);
    let body_start_line = body_start_line_of(text);

    // Per-line edits, keyed by 0-indexed line, each a byte range within
    // that line's text and its replacement.
    let mut edits: Vec<Vec<(std::ops::Range<usize>, String)>> = vec![Vec::new(); lines.len()];

    // The prose half, over the same extractor `FC18` reads, so the two
    // halves agree about where a path counts -- including the fenced and
    // indented code blocks both leave alone.
    let body: Vec<String> = lines
        .iter()
        .skip(body_start_line.saturating_sub(1))
        .map(|l| l.text.clone())
        .collect();
    let target = references::resolve(old_rel, file, root);
    for span in crate::prose::reference_spans(&body, body_start_line) {
        let relative = span.text.starts_with("./") || span.text.starts_with("../");
        let names_old = if relative {
            target.is_some() && references::resolve(&span.text, file, root) == target
        } else {
            span.text == old_rel
        };
        if !names_old {
            continue;
        }
        let replacement = if relative {
            match relativize(file, root, new_rel) {
                Some(r) => r,
                None => continue,
            }
        } else {
            new_rel.to_string()
        };
        let idx = span.line - 1;
        if let Some(slot) = edits.get_mut(idx) {
            slot.push((span.range.clone(), replacement));
        }
    }

    // The frontmatter half. The extractor never sees it -- `FC18` reads
    // `doc.body` only, deliberately -- but the determinism argument does
    // not change at the frontmatter boundary, and leaving it out produces
    // an odd result: a command that repairs a document's References section
    // and leaves an error-level R6 dangle three lines above it in the same
    // file.
    for (idx, range) in upstream_value_ranges(&lines, body_start_line, old_rel) {
        if let Some(slot) = edits.get_mut(idx) {
            slot.push((range, new_rel.to_string()));
        }
    }

    let occurrences: usize = edits.iter().map(Vec::len).sum();
    if occurrences == 0 {
        return None;
    }

    let mut out = String::with_capacity(text.len());
    for (idx, line) in lines.iter().enumerate() {
        let mut rendered = line.text.clone();
        let mut line_edits = std::mem::take(&mut edits[idx]);
        // Right to left: an ascending pass invalidates every later range as
        // soon as a replacement differs in length from what it replaced.
        line_edits.sort_by_key(|(range, _)| std::cmp::Reverse(range.start));
        for (range, replacement) in line_edits {
            rendered.replace_range(range, &replacement);
        }
        out.push_str(&rendered);
        out.push_str(line.terminator);
    }

    Some((out, occurrences))
}

/// One source line: its text and the terminator that followed it, so a file
/// with CRLF endings or no final newline rebuilds byte for byte.
struct SourceLine<'a> {
    text: String,
    terminator: &'a str,
}

fn split_keeping_terminators(text: &str) -> Vec<SourceLine<'_>> {
    let mut lines = Vec::new();
    let mut start = 0usize;
    for (i, b) in text.bytes().enumerate() {
        if b == b'\n' {
            lines.push(SourceLine {
                text: text[start..i].to_string(),
                terminator: "\n",
            });
            start = i + 1;
        }
    }
    if start < text.len() {
        lines.push(SourceLine {
            text: text[start..].to_string(),
            terminator: "",
        });
    }
    lines
}

/// The 1-indexed line the body starts on, via the same frontmatter split
/// the validator uses. A file with no frontmatter, or one whose frontmatter
/// will not parse, starts at line 1 -- the same whole-file fallback the
/// per-file driver applies.
fn body_start_line_of(text: &str) -> usize {
    match crate::frontmatter::parse_doc_bytes("repoint", text.as_bytes()) {
        Ok(doc) => doc.body_start_line,
        Err(_) => 1,
    }
}

/// Byte ranges of `upstream:` values equal to `old_rel`, within the
/// frontmatter block.
///
/// Both YAML shapes the field takes: a scalar (`upstream: docs/…`) and a
/// sequence (`- docs/…` under the key). The field ends at the next
/// top-level key, so a path sitting in some other field is untouched.
fn upstream_value_ranges(
    lines: &[SourceLine<'_>],
    body_start_line: usize,
    old_rel: &str,
) -> Vec<(usize, std::ops::Range<usize>)> {
    let mut out = Vec::new();
    if body_start_line <= 1 {
        return out;
    }
    let mut in_upstream = false;

    for (idx, line) in lines.iter().enumerate().take(body_start_line - 1) {
        let text = &line.text;
        if let Some(rest) = text.strip_prefix("upstream:") {
            in_upstream = true;
            if let Some(range) = value_range(text, rest.len(), old_rel) {
                out.push((idx, range));
            }
            continue;
        }
        // Any other unindented `key:` closes the field.
        if !in_upstream {
            continue;
        }
        let is_top_level_key = !text.starts_with([' ', '\t', '-'])
            && text
                .find(':')
                .is_some_and(|i| !text[..i].is_empty() && !text[..i].contains(' '));
        if is_top_level_key {
            in_upstream = false;
            continue;
        }
        let trimmed = text.trim_start();
        if let Some(rest) = trimmed.strip_prefix('-') {
            if let Some(range) = value_range(text, rest.len(), old_rel) {
                out.push((idx, range));
            }
        }
    }
    out
}

/// The byte range of `old_rel` within `text`, when the last `suffix_len`
/// bytes of the line -- trimmed -- are exactly that path.
///
/// Matching the whole trimmed value rather than searching for a substring
/// is what keeps a comment or a longer path that merely contains the old
/// one from being rewritten.
fn value_range(text: &str, suffix_len: usize, old_rel: &str) -> Option<std::ops::Range<usize>> {
    let start = text.len().checked_sub(suffix_len)?;
    let tail = &text[start..];
    let trimmed = tail.trim();
    if trimmed != old_rel {
        return None;
    }
    let offset = start + (tail.len() - tail.trim_start().len());
    Some(offset..offset + old_rel.len())
}

/// `new_rel`, written relative to the directory of `file`.
///
/// A referrer that used a relative form keeps one: rewriting it as a
/// repo-rooted path would leave the corpus with two conventions for the
/// same edge. A target in the referrer's own directory comes back as
/// `./NAME`, so the result is still a path token rather than a bare
/// basename the extractor would not see.
fn relativize(file: &Path, root: &Path, new_rel: &str) -> Option<String> {
    let file_abs = std::fs::canonicalize(file).unwrap_or_else(|_| file.to_path_buf());
    let from = file_abs.parent()?;
    let from_rel = from.strip_prefix(root).ok().or_else(|| {
        let canon_root = std::fs::canonicalize(root).ok()?;
        from.strip_prefix(&canon_root).ok()
    })?;

    let from_parts: Vec<&std::ffi::OsStr> = from_rel
        .components()
        .filter_map(|c| match c {
            Component::Normal(p) => Some(p),
            _ => None,
        })
        .collect();
    let to_parts: Vec<&str> = new_rel.split('/').collect();

    let shared = from_parts
        .iter()
        .zip(to_parts.iter())
        .take_while(|(a, b)| a.to_str() == Some(**b))
        .count();

    let mut parts: Vec<String> = std::iter::repeat_n("..".to_string(), from_parts.len() - shared)
        .chain(to_parts[shared..].iter().map(|s| s.to_string()))
        .collect();
    if parts.first().is_none_or(|p| p != "..") {
        parts.insert(0, ".".to_string());
    }
    Some(parts.join("/"))
}

/// The path a repoint would leave, exposed for the `relativize` tests.
#[cfg(test)]
fn relativize_for_test(file_rel: &str, new_rel: &str) -> Option<String> {
    let root = Path::new("/repo");
    relativize(&root.join(file_rel), root, new_rel)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ROOT: &str = "/repo";

    fn rewrite(
        file_rel: &str,
        text: &str,
        old_rel: &str,
        new_rel: &str,
    ) -> Option<(String, usize)> {
        let root = Path::new(ROOT);
        rewrite_text(text, &root.join(file_rel), root, old_rel, new_rel)
    }

    #[test]
    fn a_rooted_reference_is_repointed() {
        let (out, n) = rewrite(
            "docs/prds/PRD-a.md",
            "See `docs/designs/DESIGN-a.md` for the approach.\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 1);
        assert_eq!(
            out,
            "See `docs/designs/current/DESIGN-a.md` for the approach.\n"
        );
    }

    #[test]
    fn only_the_path_substring_changes() {
        let before =
            "Trailing whitespace here:   \nSee `docs/designs/DESIGN-a.md`.   \n\n- bullet\t\n";
        let (out, _) = rewrite(
            "docs/prds/PRD-a.md",
            before,
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(
            out,
            before.replace(
                "docs/designs/DESIGN-a.md",
                "docs/designs/current/DESIGN-a.md"
            ),
            "the diff must contain only the substituted substring"
        );
    }

    #[test]
    fn a_crlf_file_keeps_its_line_endings() {
        let before = "---\r\nschema: prd/v1\r\n---\r\n\r\nSee `docs/designs/DESIGN-a.md`.\r\n";
        let (out, n) = rewrite(
            "docs/prds/PRD-a.md",
            before,
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 1);
        assert_eq!(
            out,
            before.replace(
                "docs/designs/DESIGN-a.md",
                "docs/designs/current/DESIGN-a.md"
            )
        );
        assert!(out.contains("\r\n"), "CRLF endings survive");
    }

    #[test]
    fn a_file_with_no_final_newline_keeps_none() {
        let (out, _) = rewrite(
            "docs/prds/PRD-a.md",
            "See `docs/designs/DESIGN-a.md`.",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert!(!out.ends_with('\n'));
    }

    #[test]
    fn a_fenced_or_indented_code_block_is_left_alone() {
        let text = concat!(
            "```\n",
            "upstream: docs/designs/DESIGN-a.md\n",
            "```\n",
            "\n",
            "    docs/designs/DESIGN-a.md\n",
            "\n",
            "after\n",
        );
        assert!(
            rewrite(
                "docs/prds/PRD-a.md",
                text,
                "docs/designs/DESIGN-a.md",
                "docs/designs/current/DESIGN-a.md",
            )
            .is_none(),
            "a worked example stops being the example it was chosen to be"
        );
    }

    #[test]
    fn edits_on_one_line_apply_right_to_left() {
        // Two occurrences on a line, and the replacement is longer than
        // what it replaces. An ascending pass corrupts the second.
        let (out, n) = rewrite(
            "docs/prds/PRD-a.md",
            "Both `docs/designs/DESIGN-a.md` and `docs/designs/DESIGN-a.md` moved.\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 2);
        assert_eq!(
            out,
            "Both `docs/designs/current/DESIGN-a.md` and `docs/designs/current/DESIGN-a.md` moved.\n"
        );
    }

    #[test]
    fn a_relative_referrer_is_repointed_and_stays_relative() {
        let (out, n) = rewrite(
            "docs/prds/PRD-a.md",
            "See [the design](../designs/DESIGN-a.md).\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 1);
        assert_eq!(out, "See [the design](../designs/current/DESIGN-a.md).\n");
    }

    #[test]
    fn a_frontmatter_upstream_is_repointed() {
        let (out, n) = rewrite(
            "docs/plans/PLAN-a.md",
            "---\nschema: plan/v1\nupstream: docs/designs/DESIGN-a.md\nstatus: Active\n---\n\n## Status\n\nActive\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 1);
        assert!(out.contains("upstream: docs/designs/current/DESIGN-a.md\n"));
        assert!(out.contains("status: Active\n"), "nothing else moves");
    }

    #[test]
    fn a_frontmatter_upstream_sequence_is_repointed() {
        let (out, n) = rewrite(
            "docs/plans/PLAN-a.md",
            "---\nupstream:\n  - docs/designs/DESIGN-a.md\n  - docs/prds/PRD-b.md\nstatus: Active\n---\n\nbody\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 1);
        assert!(out.contains("  - docs/designs/current/DESIGN-a.md\n"));
        assert!(out.contains("  - docs/prds/PRD-b.md\n"));
    }

    #[test]
    fn a_path_in_another_frontmatter_field_is_left_alone() {
        assert!(rewrite(
            "docs/plans/PLAN-a.md",
            "---\nupstream: docs/prds/PRD-b.md\nnote: docs/designs/DESIGN-a.md\n---\n\nbody\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .is_none());
    }

    #[test]
    fn an_unrelated_document_is_not_rewritten() {
        assert!(rewrite(
            "docs/prds/PRD-a.md",
            "See `docs/designs/DESIGN-other.md`.\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .is_none());
    }

    #[test]
    fn a_longer_path_containing_the_old_one_is_not_rewritten() {
        assert!(rewrite(
            "docs/prds/PRD-a.md",
            "See `docs/designs/DESIGN-a.md.bak` and `archive/docs/designs/DESIGN-a.md`.\n",
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .is_none());
    }

    #[test]
    fn the_prose_finding_cap_is_not_applied() {
        // A reporting policy truncates a list. Truncating a rewrite leaves
        // a file half-repointed, which is worse than not repointing it.
        let body = "See `docs/designs/DESIGN-a.md`.\n".repeat(200);
        let (out, n) = rewrite(
            "docs/prds/PRD-a.md",
            &body,
            "docs/designs/DESIGN-a.md",
            "docs/designs/current/DESIGN-a.md",
        )
        .expect("rewritten");
        assert_eq!(n, 200);
        assert!(!out.contains("`docs/designs/DESIGN-a.md`"));
    }

    #[test]
    fn relativize_walks_up_to_the_shared_prefix() {
        assert_eq!(
            relativize_for_test("docs/prds/PRD-a.md", "docs/designs/current/DESIGN-a.md"),
            Some("../designs/current/DESIGN-a.md".to_string())
        );
        assert_eq!(
            relativize_for_test(
                "docs/designs/DESIGN-b.md",
                "docs/designs/current/DESIGN-a.md"
            ),
            Some("./current/DESIGN-a.md".to_string())
        );
        assert_eq!(
            relativize_for_test(
                "docs/designs/current/DESIGN-b.md",
                "docs/designs/DESIGN-a.md"
            ),
            Some("../DESIGN-a.md".to_string())
        );
    }

    #[test]
    fn a_same_directory_target_keeps_a_leading_dot_slash() {
        // A bare `DESIGN-a.md` is not a path token, so the extractor would
        // stop seeing it and the next move would strand it.
        assert_eq!(
            relativize_for_test("docs/designs/DESIGN-b.md", "docs/designs/DESIGN-a.md"),
            Some("./DESIGN-a.md".to_string())
        );
    }

    #[test]
    fn an_error_message_names_the_files_already_rewritten() {
        let err = RepointError::Partial {
            path: "docs/prds/PRD-c.md".to_string(),
            detail: "permission denied".to_string(),
            action: "write",
            rewritten: vec!["docs/prds/PRD-a.md".to_string()],
        };
        let message = err.message();
        assert!(message.contains("docs/prds/PRD-c.md"));
        assert!(message.contains("docs/prds/PRD-a.md"));
        assert!(message.contains("permission denied"));
    }
}
