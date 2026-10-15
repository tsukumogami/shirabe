//! Byte-identity of roadmap/v1 and roadmap/v2 output across the roadmap/v3
//! change.
//!
//! roadmap/v3 was added to the validator and to `roadmap populate` with a
//! promise that every v1 and v2 roadmap reads exactly as before. For each
//! roadmap under `tests/fixtures/roadmap-identity/corpus/`, this runs
//! `shirabe validate --format json` (in the corpus directory) and
//! `shirabe roadmap populate --no-issues` (on a scratch copy) and compares
//! stdout, stderr, the exit code and the populated document with what a
//! shirabe built before v3 printed, which
//! `tests/fixtures/capture_roadmap_identity.sh` recorded under `expected/`.
//! The corpus is a frozen copy of every roadmap in shirabe's test, golden
//! and eval fixtures, plus a v2 roadmap that carries a `### Milestone 2:`
//! heading and a `## Milestones` section; `SOURCES.tsv` lists where each
//! came from.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn identity_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/roadmap-identity")
}

/// Every `ROADMAP-*.md` under `dir`, corpus-relative, sorted.
fn corpus_files(dir: &Path, base: &Path, out: &mut Vec<String>) {
    for entry in fs::read_dir(dir).expect("read corpus dir") {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            corpus_files(&path, base, out);
        } else if path
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.starts_with("ROADMAP-") && n.ends_with(".md"))
        {
            let rel = path.strip_prefix(base).expect("under the corpus");
            out.push(rel.to_string_lossy().into_owned());
        }
    }
}

/// The binary, with FC09's environment cleared as the capture clears it.
fn shirabe(cwd: &Path) -> Command {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_shirabe"));
    cmd.current_dir(cwd)
        .env_remove("SHIRABE_PR_NUMBER")
        .env_remove("GITHUB_REF")
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("GITHUB_TOKEN");
    cmd
}

/// Compare one captured output with what the binary produced; push a
/// description of any difference onto `diffs`.
fn compare(diffs: &mut Vec<String>, expected: &Path, actual: &[u8]) {
    let want = fs::read(expected)
        .unwrap_or_else(|e| panic!("read {}: {e} (rerun the capture)", expected.display()));
    if want != actual {
        diffs.push(format!(
            "{} differs\n--- expected\n{}\n--- actual\n{}",
            expected.display(),
            String::from_utf8_lossy(&want),
            String::from_utf8_lossy(actual)
        ));
    }
}

fn compare_output(diffs: &mut Vec<String>, base: &Path, kind: &str, out: &Output) {
    let path = |ext: &str| PathBuf::from(format!("{}.{kind}.{ext}", base.display()));
    compare(diffs, &path("stdout"), &out.stdout);
    compare(diffs, &path("stderr"), &out.stderr);
    let code = format!("{}\n", out.status.code().unwrap_or(-1));
    compare(diffs, &path("exit"), code.as_bytes());
}

#[test]
fn v1_and_v2_roadmaps_read_as_they_did_before_v3() {
    let dir = identity_dir();
    let corpus = dir.join("corpus");
    let expected = dir.join("expected");
    let mut files = Vec::new();
    corpus_files(&corpus, &corpus, &mut files);
    files.sort();
    assert!(files.len() >= 12, "the corpus lost roadmaps: {files:?}");

    let scratch = std::env::temp_dir().join(format!("shirabe-identity-{}", std::process::id()));
    let mut diffs = Vec::new();
    for rel in &files {
        let base = expected.join(rel);

        let out = shirabe(&corpus)
            .args(["validate", "--format", "json", rel])
            .output()
            .expect("run shirabe validate");
        compare_output(&mut diffs, &base, "validate", &out);

        let _ = fs::remove_dir_all(&scratch);
        let copy = scratch.join(rel);
        fs::create_dir_all(copy.parent().unwrap()).expect("mkdir scratch");
        fs::copy(corpus.join(rel), &copy).expect("copy roadmap");
        let out = shirabe(&scratch)
            .args(["roadmap", "populate", "--no-issues", rel])
            .output()
            .expect("run shirabe roadmap populate");
        compare_output(&mut diffs, &base, "populate", &out);
        let doc = fs::read(&copy).expect("read populated roadmap");
        compare(
            &mut diffs,
            &PathBuf::from(format!("{}.populate.doc", base.display())),
            &doc,
        );
    }
    let _ = fs::remove_dir_all(&scratch);
    assert!(diffs.is_empty(), "{}", diffs.join("\n\n"));
}
