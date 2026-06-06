//! Golden-parity tests for the `shirabe transition` subcommand.
//!
//! This is the cutover gate (PLAN Issue 4): it pins the subcommand's behavior
//! against the seven per-skill `transition-status.sh` scripts (the parity
//! oracle) before Issue 5 deletes them. It mirrors the `validate` golden-parity
//! harness (`parity.rs`): a frozen corpus, captured baselines, and one
//! `#[test]` per case so a failure names the exact diverging case.
//!
//! ## The oracle and the baselines
//!
//! `tests/fixtures/transition-golden/cases.tsv` lists every case. For each,
//! `capture_script_baseline.sh` ran the matching script in a fresh temp git
//! repo and recorded, under `expected/<case_id>/`:
//!
//!   - `result.json`   the script's JSON result, normalized through `jq -S .`
//!                     (sorted keys) -- stdout on success, stderr (json_error)
//!                     on a 1/2/3 failure.
//!   - `exit`          the script's exact exit code.
//!   - `final_path`    the resulting document's repo-relative path (the moved
//!                     `new_path` for the three moving types, else the input).
//!   - `final_content` the resulting document's full contents.
//!
//! ## What this test asserts
//!
//! Each case rebuilds the same fresh temp git repo from `corpus/<case_id>/`,
//! runs `shirabe transition` from the repo root with the repo-relative path
//! (translating the manifest's 3rd-arg into the named `--superseded-by` /
//! `--reason` flag), and asserts against the baseline:
//!
//!   - the exact exit code;
//!   - structural JSON equality of the result (same keys + values), via the
//!     same `jq -S .` normalization the capture used;
//!   - the resulting document's path and byte-exact contents.
//!
//! ## Two documented error-message divergences (NOT parity breaks)
//!
//! The error *message string* is human-readable prose; real callers
//! (`run-cascade.sh`) parse `success` / `code` / `new_path`, never `error`.
//! The DESIGN reproduces graph-rejection / precondition / invalid-status
//! messages byte-for-byte (asserted here) but legitimately changes two
//! extra-input messages with the CLI surface:
//!
//!   - design Superseded with no pointer: the script says "...as third
//!     argument" (positional); the subcommand says "...(--superseded-by)" (the
//!     flag that replaced the positional).
//!   - strategy Sunset with an unsafe reason: the script's bash source emits a
//!     literal double backslash (`\\`) in the forbidden-character list; the
//!     subcommand emits the single backslash the message means.
//!
//! For these two cases the test asserts exit code + `success: false` + the
//! `code` value (the machine contract), but not the `error` prose. Every other
//! error case asserts the full structural JSON, message included -- so a
//! message regression anywhere else still fails the harness.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Absolute path to `tests/fixtures/transition-golden`.
fn golden_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/transition-golden")
}

/// One parsed manifest row.
struct Case {
    id: String,
    doc_relpath: String,
    target: String,
    flag: String,
    arg3: String,
}

/// Parse `cases.tsv`, skipping comments and blank lines.
fn read_cases() -> Vec<Case> {
    let manifest = golden_dir().join("cases.tsv");
    let text = std::fs::read_to_string(&manifest).expect("read cases.tsv");
    let mut cases = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        assert_eq!(
            cols.len(),
            6,
            "manifest row must have 6 tab-separated columns: {line:?}"
        );
        cases.push(Case {
            id: cols[0].to_string(),
            doc_relpath: cols[2].to_string(),
            target: cols[3].to_string(),
            flag: cols[4].to_string(),
            arg3: cols[5].to_string(),
        });
    }
    cases
}

/// Look up a case by id, panicking if the manifest lost it (keeps each
/// `#[test]` self-describing while sharing one manifest).
fn case(id: &str) -> Case {
    read_cases()
        .into_iter()
        .find(|c| c.id == id)
        .unwrap_or_else(|| panic!("case {id} missing from cases.tsv"))
}

/// The two cases whose error *message* legitimately diverges from the script
/// (CLI-surface change); see the module docs. Their machine contract (exit
/// code + `code` + `success: false`) is still asserted.
fn error_message_exempt(id: &str) -> bool {
    matches!(
        id,
        "design-idempotent-superseded-no-pointer" | "strategy-idempotent-sunset-unsafe-reason"
    )
}

/// Normalize a JSON document the way the capture did: pipe it through
/// `jq -S .` (sorted keys, canonical formatting) so structural equality is a
/// byte comparison of the normalized forms. Using the same tool the baseline
/// was captured with keeps the two sides directly comparable without a JSON
/// dependency in the test crate.
fn jq_sorted(input: &str) -> String {
    use std::io::Write;
    let mut child = Command::new("jq")
        .arg("-S")
        .arg(".")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .expect("spawn jq (required for the transition parity harness)");
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .expect("write to jq stdin");
    let out = child.wait_with_output().expect("wait for jq");
    assert!(
        out.status.success(),
        "jq failed to normalize JSON:\n--- input ---\n{input}\n--- stderr ---\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).expect("jq output is UTF-8")
}

/// Extract the `code` integer from a normalized error JSON object via jq, so
/// the machine contract can be asserted even for the message-exempt cases.
fn jq_code(input: &str) -> String {
    use std::io::Write;
    let mut child = Command::new("jq")
        .arg("-r")
        .arg("\"\\(.success) \\(.code)\"")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .expect("spawn jq");
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .expect("write to jq stdin");
    let out = child.wait_with_output().expect("wait for jq");
    String::from_utf8(out.stdout).expect("jq output is UTF-8")
}

/// Read one captured baseline file for a case.
fn read_baseline(case_id: &str, name: &str) -> String {
    let path = golden_dir().join("expected").join(case_id).join(name);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read baseline {case_id}/{name}: {e}"))
}

/// Set up a fresh temp git repo seeded with the case's corpus tree, committed,
/// matching exactly what `capture_script_baseline.sh` does for the oracle.
/// Returns the repo root.
fn setup_repo(case_id: &str) -> tempdir::TempDir {
    let dir = tempdir::TempDir::new(case_id);
    let corpus = golden_dir().join("corpus").join(case_id);
    copy_tree(&corpus, dir.path());
    git(dir.path(), &["init", "-q"]);
    git(dir.path(), &["add", "-A"]);
    git(
        dir.path(),
        &[
            "-c",
            "user.email=parity@example.invalid",
            "-c",
            "user.name=parity",
            "commit",
            "-q",
            "-m",
            "corpus",
        ],
    );
    dir
}

/// Recursively copy a directory tree.
fn copy_tree(src: &Path, dst: &Path) {
    for entry in std::fs::read_dir(src).expect("read_dir corpus") {
        let entry = entry.expect("dir entry");
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() {
            std::fs::create_dir_all(&to).expect("mkdir");
            copy_tree(&from, &to);
        } else {
            if let Some(parent) = to.parent() {
                std::fs::create_dir_all(parent).expect("mkdir parent");
            }
            std::fs::copy(&from, &to).expect("copy file");
        }
    }
}

/// Run `git -C <root> <args>` and assert success.
fn git(root: &Path, args: &[&str]) {
    let status = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .expect("run git");
    assert!(status.success(), "git {args:?} failed in {root:?}");
}

/// The single per-case assertion: run the subcommand in a fresh repo and check
/// the result against the captured script baseline.
fn assert_parity(case_id: &str) {
    let c = case(case_id);
    let repo = setup_repo(case_id);
    let root = repo.path();

    let bin = env!("CARGO_BIN_EXE_shirabe");
    let mut cmd = Command::new(bin);
    cmd.current_dir(root)
        .arg("transition")
        .arg(&c.doc_relpath)
        .arg(&c.target);
    if c.flag == "superseded_by" && c.arg3 != "-" {
        cmd.arg("--superseded-by").arg(&c.arg3);
    } else if c.flag == "reason" && c.arg3 != "-" {
        cmd.arg("--reason").arg(&c.arg3);
    }

    let output = cmd.output().expect("run shirabe transition");
    let actual_exit = output.status.code().unwrap_or(-1);
    let actual_stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let actual_stderr = String::from_utf8_lossy(&output.stderr).into_owned();

    let expected_exit: i32 = read_baseline(case_id, "exit")
        .trim()
        .parse()
        .expect("baseline exit is an integer");
    let expected_json = read_baseline(case_id, "result.json");
    let expected_final_path = read_baseline(case_id, "final_path").trim().to_string();
    let expected_final_content = read_baseline(case_id, "final_content");

    // Exact exit code.
    assert_eq!(
        actual_exit, expected_exit,
        "EXIT divergence for {case_id}: script baseline {expected_exit}, subcommand {actual_exit}\n\
         --- subcommand stdout ---\n{actual_stdout}\n--- subcommand stderr ---\n{actual_stderr}"
    );

    // The result JSON is on stdout for success, stderr for a json_error.
    let actual_json_raw = if expected_exit == 0 {
        &actual_stdout
    } else {
        &actual_stderr
    };

    if expected_exit == 0 || !error_message_exempt(case_id) {
        // Full structural equality (same keys + values), normalized the same
        // way the baseline was.
        let actual_norm = jq_sorted(actual_json_raw);
        assert_eq!(
            actual_norm, expected_json,
            "JSON divergence for {case_id}\n--- expected (script) ---\n{expected_json}\n--- actual (subcommand) ---\n{actual_norm}"
        );
    } else {
        // Message-exempt error case: assert the machine contract (success flag
        // + code) but not the human-readable prose; see the module docs.
        let actual_contract = jq_code(&jq_sorted(actual_json_raw));
        let expected_contract = jq_code(&expected_json);
        assert_eq!(
            actual_contract, expected_contract,
            "error contract (success/code) divergence for {case_id}: \
             script {expected_contract:?}, subcommand {actual_contract:?}"
        );
    }

    // Resulting document path + byte-exact contents.
    let actual_final = root.join(&expected_final_path);
    assert!(
        actual_final.is_file(),
        "expected resulting doc at {expected_final_path} for {case_id}, not found"
    );
    let actual_content = std::fs::read_to_string(&actual_final).expect("read resulting doc");
    assert_eq!(
        actual_content, expected_final_content,
        "resulting content divergence for {case_id} at {expected_final_path}\n\
         --- expected (script) ---\n{expected_final_content}\n--- actual (subcommand) ---\n{actual_content}"
    );
}

/// A minimal self-contained temp-dir helper (no external crate): a uniquely
/// named directory under the system temp dir, removed on drop.
mod tempdir {
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    pub struct TempDir {
        path: PathBuf,
    }

    impl TempDir {
        pub fn new(label: &str) -> Self {
            let n = COUNTER.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "shirabe-transition-parity-{}-{}-{}",
                std::process::id(),
                n,
                label
            ));
            std::fs::create_dir_all(&path).expect("create temp dir");
            TempDir { path }
        }

        pub fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }
}

macro_rules! parity_tests {
    ($($name:ident => $case_id:literal,)*) => {
        $(
            #[test]
            fn $name() {
                assert_parity($case_id);
            }
        )*
    };
}

parity_tests! {
    // prd (membership-only): into and out of "In Progress", invalid status,
    // idempotent terminal re-run.
    prd_into_in_progress        => "prd-into-in-progress",
    prd_out_of_in_progress      => "prd-out-of-in-progress",
    prd_invalid_status          => "prd-invalid-status",
    prd_idempotent_done         => "prd-idempotent-done",

    // roadmap (graph, no move): legal move with >=2 features, rejected skip,
    // precondition block, idempotent terminal re-run.
    roadmap_legal_move          => "roadmap-legal-move",
    roadmap_rejected_skip       => "roadmap-rejected-skip",
    roadmap_precondition_feats  => "roadmap-precondition-features",
    roadmap_idempotent_done     => "roadmap-idempotent-done",

    // brief (graph, no move): legal move, rejected skip, idempotent terminal.
    brief_legal_move            => "brief-legal-move",
    brief_rejected_skip         => "brief-rejected-skip",
    brief_idempotent_done       => "brief-idempotent-done",

    // vision (graph + move + optional pointer): legal move, rejected skip,
    // Open-Questions precondition, sunset with/without pointer, idempotent
    // terminal at Sunset.
    vision_legal_move           => "vision-legal-move",
    vision_rejected_skip        => "vision-rejected-skip",
    vision_precondition_oq      => "vision-precondition-oq",
    vision_sunset_with_pointer  => "vision-sunset-with-pointer",
    vision_sunset_bare          => "vision-sunset-bare",
    vision_idempotent_sunset    => "vision-idempotent-sunset",

    // strategy (graph + move + required sanitized reason): legal move, rejected
    // skip, Open-Questions precondition, sunset with reason, and two idempotent
    // re-runs that still fail the extra-input gate (no reason / unsafe reason).
    strategy_legal_move         => "strategy-legal-move",
    strategy_rejected_skip      => "strategy-rejected-skip",
    strategy_precondition_oq    => "strategy-precondition-oq",
    strategy_sunset_with_reason => "strategy-sunset-with-reason",
    strategy_idem_sunset_no_reason     => "strategy-idempotent-sunset-no-reason",
    strategy_idem_sunset_unsafe_reason => "strategy-idempotent-sunset-unsafe-reason",

    // design (membership + move + required pointer): legal move, invalid
    // status, move to Current (no extra field), supersede into archive with a
    // pointer, and an idempotent re-run at Superseded that still fails the
    // missing-pointer gate (exit 1).
    design_legal_move           => "design-legal-move",
    design_invalid_status       => "design-invalid-status",
    design_to_current           => "design-to-current",
    design_supersede            => "design-supersede",
    design_idem_superseded_no_pointer => "design-idempotent-superseded-no-pointer",

    // comp (graph, no move; brief-shaped plus the Draft -> Done shortcut, and a
    // bare `moved: false` result field): legal move, the Draft -> Done shortcut,
    // a rejected regression (Accepted -> Draft, exit 2), idempotent terminal.
    comp_legal_move             => "comp-legal-move",
    comp_draft_to_done_shortcut => "comp-draft-to-done-shortcut",
    comp_rejected_regress       => "comp-rejected-regress",
    comp_idempotent_done        => "comp-idempotent-done",
}
