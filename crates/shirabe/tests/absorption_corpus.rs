//! Corpus-wide regression guard for the contribution-section checks.
//!
//! The contribution mechanism's central regression claim is that it is
//! *silent* on every document that declares no absorption. That claim is what
//! lets the change ship without touching a 500-document corpus, and it is not
//! something the unit tests can establish: they prove the checks behave
//! correctly on documents built for them, not that no document already on disk
//! trips them.
//!
//! So this walks every markdown document under `docs/` and asserts that none of
//! the codes this feature adds fires on a document with no `absorbed:` key.
//!
//! **It deliberately does not assert exit 0.** The corpus carries pre-existing
//! findings from other checks — dangling `upstream:` refs, requirement citations
//! that resolve nowhere — which are a defect of the process this feature fixes
//! and whose cleanup is sequenced follow-on work. Asserting a clean exit would
//! either fail on breakage this change did not cause, or pressure someone into
//! editing unrelated documents to make it pass. The narrow assertion is the
//! honest one: *this change* is silent where it claims to be.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Check codes this feature introduces.
const ADDED_CODES: [&str; 2] = ["FC17", "FC18"];

fn worktree_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

/// Every `.md` file under `docs/`, as repo-relative paths.
///
/// Relative rather than absolute because the validator resolves `upstream:`
/// against the process working directory, and the committed documents write
/// that field in `docs/...` form.
fn all_docs(root: &Path) -> Vec<PathBuf> {
    fn walk(dir: &Path, root: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, root, out);
            } else if path.extension().and_then(|e| e.to_str()) == Some("md") {
                out.push(path.strip_prefix(root).unwrap_or(&path).to_path_buf());
            }
        }
    }
    let mut out = Vec::new();
    walk(&root.join("docs"), root, &mut out);
    out.sort();
    out
}

/// Whether a document declares an absorption. Read textually rather than
/// through the parser so the guard does not depend on the code it is guarding.
fn declares_absorption(root: &Path, rel: &Path) -> bool {
    let Ok(text) = std::fs::read_to_string(root.join(rel)) else {
        return false;
    };
    let Some(rest) = text.strip_prefix("---\n") else {
        return false;
    };
    let Some(end) = rest.find("\n---") else {
        return false;
    };
    rest[..end]
        .lines()
        .any(|line| line.starts_with("absorbed:") || line.starts_with("absorbed :"))
}

#[test]
fn added_checks_are_silent_on_documents_declaring_no_absorption() {
    let root = worktree_root();
    if !root.join("docs").exists() {
        eprintln!("skipping: no docs/ in this build");
        return;
    }

    let docs = all_docs(&root);
    assert!(
        docs.len() > 20,
        "expected a real corpus under docs/, found {}",
        docs.len()
    );

    let non_absorbing: Vec<&PathBuf> = docs
        .iter()
        .filter(|rel| !declares_absorption(&root, rel))
        .collect();
    assert!(
        !non_absorbing.is_empty(),
        "every document declares an absorption, which cannot be right"
    );

    let bin = env!("CARGO_BIN_EXE_shirabe");
    let mut cmd = Command::new(bin);
    cmd.current_dir(&root);
    cmd.arg("validate").arg("--visibility=public");
    for rel in &non_absorbing {
        cmd.arg(rel);
    }
    let output = cmd.output().expect("failed to run shirabe");
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    for code in ADDED_CODES {
        let marker = format!("[{code}]");
        let offenders: Vec<&str> = combined
            .lines()
            .filter(|line| line.contains(&marker))
            .collect();
        assert!(
            offenders.is_empty(),
            "{code} fired on {} document(s) that declare no absorption. This change \
             is supposed to be invisible to them; a hit here means the gate is not \
             actually keyed on the declaration.\n{}",
            offenders.len(),
            offenders.join("\n")
        );
    }
}

/// No *existing* document was edited to make the guard above pass.
///
/// Pairs with the assertion rather than duplicating it: silence is cheap to
/// obtain by changing the documents, and that would defeat the point.
///
/// Modifications and deletions of tracked files are what this forbids. A new
/// untracked document is not — adding one cannot make a pre-existing document
/// stop tripping a check, which is the thing being guarded against, and
/// forbidding additions would make the suite red for any author drafting a doc.
#[test]
fn no_existing_document_was_edited() {
    let root = worktree_root();
    if !root.join(".git").exists() && !root.join(".git").is_file() {
        eprintln!("skipping: not a git worktree");
        return;
    }
    let output = Command::new("git")
        .current_dir(&root)
        .args(["status", "--porcelain", "--", "docs/"])
        .output()
        .expect("failed to run git");
    let status = String::from_utf8_lossy(&output.stdout);

    // Porcelain v1: XY <path>. `??` is untracked; anything else touches a
    // file git already knows about.
    let edited: Vec<&str> = status
        .lines()
        .filter(|line| !line.starts_with("??"))
        .collect();

    assert!(
        edited.is_empty(),
        "tracked documents under docs/ were modified while the corpus guard \
         ran. The guard's silence is only meaningful if the corpus it measured \
         is the committed one.\n{}",
        edited.join("\n")
    );
}
