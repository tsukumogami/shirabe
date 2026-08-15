//! Where a written reference points, and what survives at the other end.
//!
//! [`crate::prose::reference_spans`] decides *where in a file* a path
//! counts. This module decides *which of those paths is a defect*, and it
//! does so entirely from the state of the target: a path that names no file
//! is a defect when a file of the same basename survives somewhere in the
//! artifact directories, and is silent otherwise.
//!
//! That discriminator is measured rather than argued. Over this
//! repository's tracked markdown, 421 artifact-shaped paths appear and 140
//! of them do not resolve, but only a couple of dozen are references a
//! relocation broke. The rest are template placeholders, one-off fixture
//! names, and paths to working artifacts the cascade deleted on purpose,
//! and none of those leaves a file of the same name behind. Scoping by
//! directory or by `## References` section was tried against the same
//! corpus and both miss real defects while admitting placeholders; see
//! `docs/designs/current/DESIGN-prose-reference-staleness.md` Decision 1.
//!
//! Two callers share this: the `FC18` check, which reports, and
//! `transition`'s repoint, which rewrites. The repoint needs only
//! [`resolve`] -- it is handed both paths by the transition and infers
//! nothing -- while the check needs the whole chain.

use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use crate::formats::detect_format;
use crate::upstream::is_cross_repo_reference;

/// The artifact directories a surviving file can be found in.
///
/// This is `lifecycle::build_doc_index`'s six directories plus six the
/// format set defines. Three of the additions are destinations of moving
/// transitions -- `docs/designs/archive`, `docs/visions/sunset`, and
/// `docs/strategies/sunset` -- and omitting any one makes the corresponding
/// move undetectable: a superseded design, a sunset vision, and a sunset
/// strategy would each be indistinguishable from a deleted document. An
/// earlier revision of the design listed `docs/visions` and
/// `docs/strategies` without their `sunset/` subdirectories, which covers
/// the documents that never move and misses the ones that do.
///
/// A directory that does not exist contributes nothing and costs nothing.
pub const ARTIFACT_DIRS: &[&str] = &[
    "docs/briefs",
    "docs/competitive",
    "docs/designs",
    "docs/designs/archive",
    "docs/designs/current",
    "docs/plans",
    "docs/prds",
    "docs/roadmaps",
    "docs/strategies",
    "docs/strategies/sunset",
    "docs/visions",
    "docs/visions/sunset",
];

/// Basename -> the repo-relative paths carrying it, in path order.
pub type TargetIndex = BTreeMap<String, Vec<String>>;

/// The work-tree root for `file`: the first ancestor directory containing a
/// `.git` entry, walking up from the file's own directory.
///
/// Per file, not per run. One `validate` invocation can span two
/// repositories -- the reusable workflow hands a caller repo's changed-file
/// set to a validator living in another checkout -- and resolving a
/// `docs/…` path against the wrong tree is how a finding gets manufactured
/// out of an unrelated corpus. `visibility::resolve_claude_md_header` walks
/// exactly this way for the same reason.
///
/// `.git` is tested with `exists` rather than `is_dir` because a linked
/// worktree carries it as a file.
///
/// `None` when there is no `.git` ancestor. The check needs a repository to
/// know what an artifact directory is, and the validator is expected to run
/// against loose files, so that is a silent no-findings rather than an
/// error.
pub fn repo_root(file: &Path) -> Option<PathBuf> {
    let canonical = std::fs::canonicalize(file).unwrap_or_else(|_| file.to_path_buf());
    let mut dir = canonical.parent();
    while let Some(d) = dir {
        if d.join(".git").exists() {
            return Some(d.to_path_buf());
        }
        dir = d.parent();
    }
    None
}

/// Whether a written path is a reference this module can resolve at all.
///
/// Three classes are dropped because resolving them would answer a question
/// nobody asked:
///
/// - **URLs.** `https://example.com/docs/designs/DESIGN-a.md` names a
///   document on another host.
/// - **Cross-repo `owner/repo:path` references**, which name a file in
///   another repository. `check_upstream_resolves` skips them for the same
///   reason.
/// - **Absolute paths.** Not a form this corpus uses, and resolving one
///   would let a finding depend on the host filesystem.
///
/// What survives has to be artifact-shaped: a final component starting with
/// a known artifact prefix and ending in `.md`. The prefix set comes from
/// `formats()` through `detect_format`, so a new artifact type is covered
/// by adding it to the formats map rather than to a list here.
///
/// ## The base a path is written against
///
/// A reference is only checkable when the check knows what the path is
/// relative to, and there are exactly two forms where it does: a `./` or
/// `../` path, which is relative to the referring file, and a path whose
/// directory is one of [`ARTIFACT_DIRS`], which is relative to the work
/// tree because that is the only place that directory exists.
///
/// Everything else is written against a base the check cannot see, and
/// resolving it against the work-tree root manufactures findings. Measured
/// on this repository, dropping that third form removes six false
/// positives and no true ones: `real/PRD-roadmap-skill.md` and
/// `corpus/real/DESIGN-gha-doc-validation.md` name golden-corpus fixtures
/// relative to the corpus directory, and they collide with real documents
/// that share their basenames. Nothing moved; the reference is fine; the
/// finding would be noise of exactly the kind that gets a check disabled.
///
/// This is not the directory scope the design rejected. That one asked
/// where the *referring file* lives, which does not correlate with anything
/// -- both instruction files under `skills/` carry genuine references, and
/// they survive here because they write a `docs/…` path like everyone else.
/// This one asks what the *written path* claims, which is the claim being
/// checked.
pub fn is_candidate(text: &str) -> bool {
    if text.contains("://") || is_cross_repo_reference(text) || text.starts_with('/') {
        return false;
    }
    let Some((dir, basename)) = text.rsplit_once('/') else {
        return false;
    };
    if detect_format(basename).is_none() {
        return false;
    }
    text.starts_with("./") || text.starts_with("../") || ARTIFACT_DIRS.contains(&dir)
}

/// Resolve a written reference to an absolute path inside `root`.
///
/// `./` and `../` forms resolve against the referring file's own directory;
/// everything else against the work-tree root. Handling the relative forms
/// separately is what makes them mean what a reader means: a `../prds/…`
/// written from `docs/designs/` resolves and one written from
/// `docs/designs/current/` does not, and anchoring both at the root would
/// get the first wrong and the second right for the wrong reason.
///
/// Normalization is lexical because the target may not exist, which is the
/// interesting case: `canonicalize` fails on a path that names no file.
/// Containment is then enforced against `root`, so a `../../../etc/passwd`
/// candidate resolves to nothing rather than to a filesystem read outside
/// the repository.
pub fn resolve(candidate: &str, referring_file: &Path, root: &Path) -> Option<PathBuf> {
    let base = if candidate.starts_with("./") || candidate.starts_with("../") {
        let canonical =
            std::fs::canonicalize(referring_file).unwrap_or_else(|_| referring_file.to_path_buf());
        canonical.parent()?.to_path_buf()
    } else {
        root.to_path_buf()
    };

    let joined = normalize_lexically(&base.join(candidate));
    if joined.starts_with(root) {
        Some(joined)
    } else {
        None
    }
}

/// Collapse `.` and `..` components without touching the filesystem.
///
/// A `..` that would climb above the path's root is dropped rather than
/// wrapped around, so the result never escapes upward by more segments than
/// the input had.
fn normalize_lexically(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// The target index for `root`, scanned once per root per process.
///
/// A multi-file invocation spanning two repositories gets one index per
/// repository, which is the per-file-repo discipline `check_writing_style`
/// already follows for prose vocabulary.
pub fn target_index(root: &Path) -> Arc<TargetIndex> {
    static CACHE: OnceLock<Mutex<BTreeMap<PathBuf, Arc<TargetIndex>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(BTreeMap::new()));

    // A poisoned lock means another thread panicked mid-scan. The cache
    // holds no invariant a panic can break (entries are inserted whole), so
    // recovering the guard is safe and strictly better than propagating.
    let mut guard = cache.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(index) = guard.get(root) {
        return Arc::clone(index);
    }
    let index = Arc::new(scan_artifact_dirs(root));
    guard.insert(root.to_path_buf(), Arc::clone(&index));
    index
}

/// Read every artifact directory under `root` and map basename to the
/// repo-relative paths carrying it.
///
/// Entries are canonicalized and any escaping `root` are dropped, matching
/// `build_doc_index`'s containment handling: a symlink under
/// `docs/designs/current/` pointing outside the tree would otherwise put an
/// out-of-tree path into a finding message.
fn scan_artifact_dirs(root: &Path) -> TargetIndex {
    let canon_root = std::fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
    let mut index = TargetIndex::new();

    for sub in ARTIFACT_DIRS {
        let dir = canon_root.join(sub);
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|s| s.to_str()) else {
                continue;
            };
            if !name.ends_with(".md") {
                continue;
            }
            let Ok(canon) = std::fs::canonicalize(&path) else {
                continue;
            };
            if !canon.starts_with(&canon_root) {
                continue;
            }
            index
                .entry(name.to_string())
                .or_default()
                .push(format!("{sub}/{name}"));
        }
    }

    // Path order, so a basename at more than one path always reports its
    // matches the same way and two runs over unchanged input agree.
    for paths in index.values_mut() {
        paths.sort();
    }
    index
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_url_is_not_a_candidate() {
        assert!(!is_candidate(
            "https://example.com/docs/designs/DESIGN-a.md"
        ));
    }

    #[test]
    fn a_cross_repo_reference_is_not_a_candidate() {
        assert!(!is_candidate("owner/repo:docs/designs/DESIGN-a.md"));
    }

    #[test]
    fn an_absolute_path_is_not_a_candidate() {
        assert!(!is_candidate("/docs/designs/DESIGN-a.md"));
    }

    #[test]
    fn a_non_artifact_basename_is_not_a_candidate() {
        assert!(!is_candidate("docs/designs/getting-started.md"));
        assert!(!is_candidate("README.md"));
    }

    #[test]
    fn every_artifact_prefix_is_a_candidate() {
        for prefix in [
            "BRIEF", "PRD", "DESIGN", "PLAN", "ROADMAP", "VISION", "STRATEGY", "COMP",
        ] {
            let path = format!("docs/designs/{prefix}-a.md");
            assert!(is_candidate(&path), "{path} must be a candidate");
        }
    }

    #[test]
    fn a_path_written_against_an_unknown_base_is_not_a_candidate() {
        // Golden-corpus fixture names, written relative to the corpus
        // directory. Their basenames collide with real documents, so
        // resolving them against the work-tree root invents a finding.
        assert!(!is_candidate("real/PRD-roadmap-skill.md"));
        assert!(!is_candidate("corpus/real/DESIGN-gha-doc-validation.md"));
    }

    #[test]
    fn a_relative_form_is_a_candidate_whatever_its_directory() {
        // The referring file is the base, so the check knows what the path
        // is written against even when the directory names nothing.
        assert!(is_candidate("../prds/PRD-a.md"));
        assert!(is_candidate("./DESIGN-a.md"));
    }

    #[test]
    fn every_artifact_directory_is_a_recognized_base() {
        for dir in ARTIFACT_DIRS {
            let path = format!("{dir}/DESIGN-a.md");
            assert!(is_candidate(&path), "{path} must be a candidate");
        }
    }

    #[test]
    fn a_rooted_path_resolves_against_the_work_tree() {
        let root = Path::new("/repo");
        let file = Path::new("/repo/docs/designs/current/DESIGN-a.md");
        assert_eq!(
            resolve("docs/prds/PRD-b.md", file, root),
            Some(PathBuf::from("/repo/docs/prds/PRD-b.md"))
        );
    }

    #[test]
    fn a_relative_path_resolves_against_the_referring_file() {
        let root = Path::new("/repo");
        let file = Path::new("/repo/docs/designs/DESIGN-a.md");
        assert_eq!(
            resolve("../prds/PRD-b.md", file, root),
            Some(PathBuf::from("/repo/docs/prds/PRD-b.md"))
        );
        assert_eq!(
            resolve("./DESIGN-c.md", file, root),
            Some(PathBuf::from("/repo/docs/designs/DESIGN-c.md"))
        );
    }

    /// The case that makes the relative form worth resolving at all: the
    /// same written text means a different file once the referring document
    /// moves a directory deeper, which is how `docs/designs/current/` ends
    /// up with links into a `docs/designs/prds/` that does not exist.
    #[test]
    fn a_relative_path_moves_when_its_referring_file_does() {
        let root = Path::new("/repo");
        assert_eq!(
            resolve(
                "../prds/PRD-b.md",
                Path::new("/repo/docs/designs/current/DESIGN-a.md"),
                root
            ),
            Some(PathBuf::from("/repo/docs/designs/prds/PRD-b.md"))
        );
    }

    #[test]
    fn a_path_escaping_the_root_resolves_to_nothing() {
        let root = Path::new("/repo");
        let file = Path::new("/repo/docs/designs/DESIGN-a.md");
        assert_eq!(resolve("../../../etc/PRD-passwd.md", file, root), None);
    }

    #[test]
    fn the_target_index_is_scanned_once_per_root() {
        let root = std::env::temp_dir().join(format!("shirabe-index-once-{}", std::process::id()));
        std::fs::create_dir_all(root.join("docs/designs/current")).expect("create dirs");
        std::fs::write(root.join("docs/designs/current/DESIGN-a.md"), "x").expect("write");

        let first = target_index(&root);
        // A file written after the first call must not appear: the second
        // call has to be the memoized scan, not a fresh one.
        std::fs::write(root.join("docs/designs/current/DESIGN-b.md"), "x").expect("write");
        let second = target_index(&root);

        assert!(Arc::ptr_eq(&first, &second), "one scan per root per run");
        assert!(!second.contains_key("DESIGN-b.md"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn the_target_index_maps_basenames_to_repo_relative_paths() {
        let root = std::env::temp_dir().join(format!("shirabe-index-map-{}", std::process::id()));
        std::fs::create_dir_all(root.join("docs/visions/sunset")).expect("create dirs");
        std::fs::write(root.join("docs/visions/sunset/VISION-a.md"), "x").expect("write");
        std::fs::create_dir_all(root.join("docs/strategies/sunset")).expect("create dirs");
        std::fs::write(root.join("docs/strategies/sunset/STRATEGY-a.md"), "x").expect("write");

        let index = target_index(&root);
        assert_eq!(
            index.get("VISION-a.md").map(Vec::as_slice),
            Some(["docs/visions/sunset/VISION-a.md".to_string()].as_slice())
        );
        assert_eq!(
            index.get("STRATEGY-a.md").map(Vec::as_slice),
            Some(["docs/strategies/sunset/STRATEGY-a.md".to_string()].as_slice())
        );
        let _ = std::fs::remove_dir_all(&root);
    }

    /// Every destination a moving transition can write to has to be in the
    /// index. Omitting one makes that move undetectable -- the relocated
    /// document becomes indistinguishable from a deleted one.
    #[test]
    fn every_moving_transition_destination_is_indexed() {
        for spec in crate::transition::transition_table() {
            for (_, dir) in &spec.moves.entries {
                assert!(
                    ARTIFACT_DIRS.contains(&dir.as_str()),
                    "{dir} is a transition destination and must be indexed"
                );
            }
        }
    }

    #[test]
    fn normalization_is_lexical_and_does_not_climb_past_the_root() {
        assert_eq!(
            normalize_lexically(Path::new("/a/b/../c/./d")),
            PathBuf::from("/a/c/d")
        );
    }
}
