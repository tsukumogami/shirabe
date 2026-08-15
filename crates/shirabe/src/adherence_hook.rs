//! The `shirabe adherence-hook` subcommand: a Claude Code **PreToolUse**
//! adapter registered on the edit-shaped tools (`Edit`, `Write`, `MultiEdit`,
//! `NotebookEdit`) by shirabe's own plugin `hooks/hooks.json`.
//!
//! This is the walking-skeleton half of DESIGN-skill-adherence-enforcement:
//! the hook registers, runs on every edit-shaped call, **always allows**, and
//! writes the per-session witness the determination later reads as its
//! liveness input. Arming (deciding whether a session is performing plan-scale
//! execution) and refusal are separate, later increments; the ladder they hang
//! off is marked below.
//!
//! Behavior:
//!
//! - Reads the hook JSON on stdin, capped, and **always exits 0**. A non-zero
//!   exit from a `PreToolUse` handler blocks the tool call, so aborting is
//!   never an option here: the shipped precedent in this workspace is an
//!   outdated binary that did not recognize a new subcommand and bricked every
//!   write in every session on the machine.
//! - Emits nothing on stdout. An allow is the absence of a decision; the deny
//!   path does not exist yet.
//! - Performs one cheap existence check (`docs/plans` under the session's
//!   working directory) before touching disk any further, so a session in a
//!   repository that cannot host plan-scale execution leaves no witness and
//!   pays only the process floor.
//! - Creates the per-session witness with an exclusive-create operation, so
//!   two hook processes racing on the same event cannot both create it. Hooks
//!   for a single event run in parallel, so a check-then-write would be
//!   separable by another process.
//!
//! Fail-open is a property of the whole adapter, not of the parser: a
//! malformed stdin, an unresolvable working directory, a permission error, a
//! store that cannot be created, and an unexpected I/O failure all allow the
//! write and simply leave the witness unwritten.
//!
//! Env seam: `SHIRABE_ADHERENCE_DISABLE=1` is the operator switch. It does
//! **not** suppress the witness — a disabled run still writes one, marked
//! disabled, so the determination can report "somebody turned this off"
//! instead of folding it into the same `indeterminate` it reports for a run
//! that predates the feature. `SHIRABE_ADHERENCE_STORE_DIR` relocates the
//! store (tests).

use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

/// The witness's contract version. The determination reads this to know which
/// fields it may rely on; bump it when the shape changes in a way a reader
/// must notice.
const WITNESS_CONTRACT_VERSION: u32 = 1;

/// The directory whose presence means "this repository can host plan-scale
/// execution". Checked relative to the session's working directory.
const PLANS_DIR: &str = "docs/plans";

/// Cap on the hook JSON read from stdin. A tool input carries the file content
/// being written, so this is not a formality.
const MAX_STDIN_BYTES: u64 = 4 * 1024 * 1024;

/// Cap on a session id used as a filename component.
const MAX_SESSION_ID_LEN: usize = 128;

#[derive(clap::Args)]
pub struct AdherenceHookArgs {
    /// The plugin root, passed by `hooks/hooks.json` as
    /// `${CLAUDE_PLUGIN_ROOT}`. The write-target declaration ships alongside
    /// the plugin and is resolved from here by the arming increment; the
    /// registration passes it now so the shipped hook command line does not
    /// have to change when that lands.
    #[allow(dead_code)]
    #[arg(long)]
    contract: Option<PathBuf>,
}

/// Entry point for `shirabe adherence-hook`. Always returns
/// `ExitCode::SUCCESS`.
pub fn run(args: &AdherenceHookArgs) -> ExitCode {
    let _ = args;
    let input = read_stdin();
    observe(&input, resolve_store().as_deref());
    ExitCode::SUCCESS
}

/// The kill switch: `SHIRABE_ADHERENCE_DISABLE=1` (any non-empty value other
/// than `0`/`false`).
fn disabled() -> bool {
    is_truthy(std::env::var("SHIRABE_ADHERENCE_DISABLE").ok().as_deref())
}

/// Split from [`disabled`] so the predicate is testable without mutating
/// process-global environment that the other tests read concurrently.
fn is_truthy(v: Option<&str>) -> bool {
    matches!(v, Some(v) if !v.is_empty() && v != "0" && v != "false")
}

fn read_stdin() -> String {
    let mut s = String::new();
    let _ = std::io::stdin()
        .take(MAX_STDIN_BYTES)
        .read_to_string(&mut s);
    s
}

/// Core logic, split out so the store directory is a parameter rather than a
/// process-global env read: given the raw PreToolUse hook JSON, record the
/// per-session witness when this session is one the determination could ever
/// be asked about.
///
/// Returns the witness path when this call created it, `None` otherwise —
/// including when it already existed, which is the common case after the first
/// edit-shaped call of a session. Nothing about the return value reaches the
/// harness; it exists for the tests.
///
/// Every failure path returns `None` and allows.
fn observe(input: &str, store: Option<&Path>) -> Option<PathBuf> {
    let v: serde_json::Value = serde_json::from_str(input).ok()?;
    let session_id = v
        .get("session_id")
        .and_then(|s| s.as_str())
        .and_then(sanitize_session_id)?;
    let cwd = resolve_cwd(&v)?;

    // The cheap check. One stat, and the overwhelming majority of sessions on
    // a machine stop here having written nothing.
    if !hosts_plans(&cwd) {
        return None;
    }

    // The witness is written here deliberately: after the existence check, so
    // it is not created in every repository on the machine, and before the
    // arming ladder, so it records evaluations that did *not* arm. The common
    // case by volume is a hook that evaluates and allows, and a witness that
    // only armed sessions left behind would be absent exactly where the
    // determination needs it.
    let body = witness_body(&v, &session_id, &cwd, disabled());
    let created = write_witness_once(store?, &session_id, &body);

    // The arming ladder and the write-target comparison land here. Until they
    // do, every call allows.

    created
}

/// Build the witness JSON. Serialized with `serde_json`, so a crafted session
/// id, agent type, or working directory is always a JSON string value.
fn witness_body(v: &serde_json::Value, session_id: &str, cwd: &Path, disabled: bool) -> String {
    let value = serde_json::json!({
        "contract_version": WITNESS_CONTRACT_VERSION,
        "session_id": session_id,
        // Present only when the evaluated call came from a Task subagent. The
        // parent's invocation carries neither, so absence means "not a Task
        // subagent of this process" and NOT "orchestrator".
        "agent_id": v.get("agent_id").and_then(|s| s.as_str()),
        "agent_type": v.get("agent_type").and_then(|s| s.as_str()),
        "first_seen_unix": now_unix(),
        "cwd": cwd.to_string_lossy(),
        "disabled": disabled,
    });
    // The object is built from owned scalars, so serialization cannot fail;
    // the fallback keeps the function total rather than panicking in a hook.
    serde_json::to_string(&value).unwrap_or_default()
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// A session id becomes a filename component, so it is admitted only as
/// ASCII alphanumerics, `-`, and `_`. That excludes `/`, `..`, and a leading
/// `.` without needing a separate traversal check.
fn sanitize_session_id(s: &str) -> Option<String> {
    if s.is_empty() || s.len() > MAX_SESSION_ID_LEN {
        return None;
    }
    if !s
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return None;
    }
    Some(s.to_string())
}

/// The session's working directory: the hook input's `cwd` when it is an
/// absolute path, else the process's own. A relative `cwd` is refused rather
/// than joined, since the two would disagree about what it is relative to.
fn resolve_cwd(v: &serde_json::Value) -> Option<PathBuf> {
    match v.get("cwd").and_then(|c| c.as_str()) {
        Some(c) if Path::new(c).is_absolute() => Some(PathBuf::from(c)),
        Some(_) => None,
        None => std::env::current_dir().ok(),
    }
}

/// The cheap existence check. Follows symlinks: this only gates whether we
/// record a witness, and nothing under the directory is read.
fn hosts_plans(cwd: &Path) -> bool {
    std::fs::metadata(cwd.join(PLANS_DIR))
        .map(|m| m.is_dir())
        .unwrap_or(false)
}

// --- storage ---------------------------------------------------------------

/// Resolve (and create) the witness store. Lives under the state directory
/// rather than the runtime directory: the witness must outlive the session and
/// survive a reboot, and it is co-located with the conflict store under
/// `shirabe/`. Refuses a symlinked store directory. Returns `None` on any
/// failure (fail-open).
fn resolve_store() -> Option<PathBuf> {
    let dir = if let Some(d) = nonempty_env("SHIRABE_ADHERENCE_STORE_DIR") {
        PathBuf::from(d)
    } else {
        let base = nonempty_env("XDG_STATE_HOME").unwrap_or_else(|| {
            format!("{}/.local/state", std::env::var("HOME").unwrap_or_default())
        });
        PathBuf::from(base).join("shirabe").join("adherence")
    };
    prepare_store(dir)
}

/// Split from [`resolve_store`] so the symlink refusal is testable without
/// mutating process-global environment.
fn prepare_store(dir: PathBuf) -> Option<PathBuf> {
    if let Ok(meta) = std::fs::symlink_metadata(&dir) {
        if meta.file_type().is_symlink() {
            return None;
        }
    }
    std::fs::create_dir_all(&dir).ok()?;
    let _ = std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700));
    Some(dir)
}

fn nonempty_env(k: &str) -> Option<String> {
    std::env::var(k).ok().filter(|v| !v.is_empty())
}

/// Create the per-session witness exactly once.
///
/// Two hook processes can run concurrently for the same event, so existence is
/// never checked and then acted on: the content is written to a uniquely named
/// temporary file first and the witness is published by **hard-linking** it
/// into place. `link(2)` fails with `EEXIST` if the destination exists, which
/// makes publication both exclusive (only one racer wins) and atomic (the
/// witness is fully written at the instant it becomes visible, so a reader can
/// never observe a torn file). The existence check above it is a cost
/// optimization for the second and later calls of a session, not the
/// exclusivity mechanism.
///
/// Returns true when this call created the witness.
fn write_witness_once(store: &Path, session_id: &str, body: &str) -> Option<PathBuf> {
    let path = store.join(format!("{session_id}.json"));
    // Fast path: already recorded (or something non-regular is sitting there,
    // which we refuse to write through). `symlink_metadata` does not follow.
    if std::fs::symlink_metadata(&path).is_ok() {
        return None;
    }
    let tmp = store.join(format!(
        ".{session_id}.{}.{}.tmp",
        std::process::id(),
        unique_suffix()
    ));
    let wrote = write_new(&tmp, body);
    let published = wrote && std::fs::hard_link(&tmp, &path).is_ok();
    let _ = std::fs::remove_file(&tmp);
    published.then_some(path)
}

/// Write `body` to a path that must not already exist, mode 0600.
fn write_new(path: &Path, body: &str) -> bool {
    let mut f = match std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
    {
        Ok(f) => f,
        Err(_) => return false,
    };
    f.write_all(body.as_bytes()).is_ok()
}

/// A per-attempt suffix, so two hook processes in the same session (and, after
/// a pid wrap, across sessions) cannot collide on the temporary file.
fn unique_suffix() -> String {
    let mut buf = [0u8; 8];
    if getrandom::getrandom(&mut buf).is_ok() {
        return buf.iter().map(|b| format!("{b:02x}")).collect();
    }
    // getrandom is not expected to fail; the clock keeps the function total.
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// An isolated store plus a repository root, so no test touches the real
    /// state directory.
    struct Fx {
        dir: PathBuf,
    }

    impl Fx {
        fn new() -> Fx {
            static N: AtomicUsize = AtomicUsize::new(0);
            let n = N.fetch_add(1, Ordering::SeqCst);
            let dir = std::env::temp_dir().join(format!(
                "shirabe-adherence-{}-{}",
                std::process::id(),
                n
            ));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(dir.join("store")).unwrap();
            std::fs::create_dir_all(dir.join("repo")).unwrap();
            Fx { dir }
        }

        fn store(&self) -> PathBuf {
            self.dir.join("store")
        }

        fn repo(&self) -> PathBuf {
            self.dir.join("repo")
        }

        /// Give the repository a plans directory, so it can host plan-scale
        /// execution.
        fn with_plans(&self) -> &Fx {
            std::fs::create_dir_all(self.repo().join(PLANS_DIR)).unwrap();
            self
        }
    }

    impl Drop for Fx {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    /// A PreToolUse hook JSON for an edit-shaped call.
    fn hook(session: &str, cwd: &Path) -> String {
        serde_json::json!({
            "session_id": session,
            "hook_event_name": "PreToolUse",
            "tool_name": "Edit",
            "tool_input": { "file_path": "/tmp/x.rs", "old_string": "a", "new_string": "b" },
            "cwd": cwd.to_string_lossy(),
            "permission_mode": "default",
        })
        .to_string()
    }

    fn read_witness(store: &Path, session: &str) -> serde_json::Value {
        let raw = std::fs::read_to_string(store.join(format!("{session}.json"))).unwrap();
        serde_json::from_str(&raw).unwrap()
    }

    #[test]
    fn witness_is_written_once_per_session() {
        let fx = Fx::new();
        fx.with_plans();
        let input = hook("sess-one", &fx.repo());
        let first = observe(&input, Some(&fx.store()));
        assert!(first.is_some(), "first call creates the witness");
        let second = observe(&input, Some(&fx.store()));
        assert!(second.is_none(), "second call does not recreate it");
        let entries: Vec<_> = std::fs::read_dir(fx.store())
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(
            entries.len(),
            1,
            "exactly one file in the store: {entries:?}"
        );
    }

    #[test]
    fn witness_carries_the_contract_fields() {
        let fx = Fx::new();
        fx.with_plans();
        observe(&hook("sess-fields", &fx.repo()), Some(&fx.store())).unwrap();
        let w = read_witness(&fx.store(), "sess-fields");
        assert_eq!(w["contract_version"], WITNESS_CONTRACT_VERSION);
        assert_eq!(w["session_id"], "sess-fields");
        assert_eq!(w["cwd"], fx.repo().to_string_lossy().to_string());
        assert!(w["first_seen_unix"].as_u64().unwrap() > 0);
        assert_eq!(w["disabled"], false);
        // Not a subagent invocation: both identity fields are present as null
        // rather than absent, so a reader can tell "no agent" from "old
        // witness".
        assert!(w.get("agent_id").unwrap().is_null());
        assert!(w.get("agent_type").unwrap().is_null());
    }

    #[test]
    fn subagent_identity_is_recorded_when_present() {
        let fx = Fx::new();
        fx.with_plans();
        let mut v: serde_json::Value =
            serde_json::from_str(&hook("sess-agent", &fx.repo())).unwrap();
        v["agent_id"] = serde_json::json!("agent-42");
        v["agent_type"] = serde_json::json!("general-purpose");
        observe(&v.to_string(), Some(&fx.store())).unwrap();
        let w = read_witness(&fx.store(), "sess-agent");
        assert_eq!(w["agent_id"], "agent-42");
        assert_eq!(w["agent_type"], "general-purpose");
    }

    #[test]
    fn no_plans_directory_writes_no_witness() {
        let fx = Fx::new();
        // Deliberately no `with_plans()`.
        assert!(observe(&hook("sess-noplans", &fx.repo()), Some(&fx.store())).is_none());
        assert_eq!(std::fs::read_dir(fx.store()).unwrap().count(), 0);
    }

    #[test]
    fn a_plans_file_is_not_a_plans_directory() {
        let fx = Fx::new();
        std::fs::create_dir_all(fx.repo().join("docs")).unwrap();
        std::fs::write(fx.repo().join(PLANS_DIR), "not a directory").unwrap();
        assert!(observe(&hook("sess-plansfile", &fx.repo()), Some(&fx.store())).is_none());
        assert_eq!(std::fs::read_dir(fx.store()).unwrap().count(), 0);
    }

    #[test]
    fn publication_is_exclusive_create() {
        let fx = Fx::new();
        // Simulate the racer that got there first: the witness already exists
        // with content this call must not clobber.
        let path = fx.store().join("sess-race.json");
        std::fs::write(&path, "{\"winner\":true}").unwrap();
        fx.with_plans();
        assert!(observe(&hook("sess-race", &fx.repo()), Some(&fx.store())).is_none());
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            "{\"winner\":true}",
            "the loser must not overwrite the winner's witness"
        );
    }

    #[test]
    fn concurrent_hooks_produce_exactly_one_witness() {
        // Hooks for a single event run in parallel. Racing the exclusive
        // create must leave exactly one witness and exactly one winner, with
        // no torn file: `link(2)` publishes fully-written content or fails.
        let fx = Fx::new();
        fx.with_plans();
        let store = fx.store();
        let input = hook("sess-parallel", &fx.repo());
        let winners: usize = std::thread::scope(|s| {
            let handles: Vec<_> = (0..8)
                .map(|_| {
                    let store = store.clone();
                    let input = input.clone();
                    s.spawn(move || observe(&input, Some(&store)).is_some() as usize)
                })
                .collect();
            handles.into_iter().map(|h| h.join().unwrap()).sum()
        });
        assert_eq!(winners, 1, "exactly one process may create the witness");
        let w = read_witness(&store, "sess-parallel");
        assert_eq!(w["session_id"], "sess-parallel");
        assert_eq!(std::fs::read_dir(&store).unwrap().count(), 1);
    }

    #[test]
    fn publication_leaves_no_temporary_behind() {
        let fx = Fx::new();
        fx.with_plans();
        observe(&hook("sess-tmp", &fx.repo()), Some(&fx.store())).unwrap();
        let leftovers: Vec<_> = std::fs::read_dir(fx.store())
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "temporaries left: {leftovers:?}");
    }

    #[test]
    fn a_symlinked_witness_path_is_refused() {
        let fx = Fx::new();
        fx.with_plans();
        let target = fx.dir.join("outside.json");
        std::os::unix::fs::symlink(&target, fx.store().join("sess-link.json")).unwrap();
        assert!(observe(&hook("sess-link", &fx.repo()), Some(&fx.store())).is_none());
        assert!(!target.exists(), "must not write through the symlink");
    }

    #[test]
    fn traversal_shaped_session_ids_are_refused() {
        let fx = Fx::new();
        fx.with_plans();
        for sid in ["../escape", "a/b", ".hidden", "", "with space", "sess;rm"] {
            let v = serde_json::json!({
                "session_id": sid,
                "tool_name": "Write",
                "cwd": fx.repo().to_string_lossy(),
            });
            assert!(
                observe(&v.to_string(), Some(&fx.store())).is_none(),
                "session id {sid:?} must be refused"
            );
        }
        assert_eq!(std::fs::read_dir(fx.store()).unwrap().count(), 0);
    }

    #[test]
    fn overlong_session_id_is_refused() {
        let long = "a".repeat(MAX_SESSION_ID_LEN + 1);
        assert!(sanitize_session_id(&long).is_none());
        assert!(sanitize_session_id(&"a".repeat(MAX_SESSION_ID_LEN)).is_some());
    }

    #[test]
    fn malformed_and_partial_input_is_allowed() {
        let fx = Fx::new();
        fx.with_plans();
        for input in ["", "not json", "{}", "[]", "{\"session_id\": 7}", "null"] {
            assert!(
                observe(input, Some(&fx.store())).is_none(),
                "input {input:?} must be tolerated"
            );
        }
        assert_eq!(std::fs::read_dir(fx.store()).unwrap().count(), 0);
    }

    #[test]
    fn a_relative_cwd_is_refused_rather_than_joined() {
        let fx = Fx::new();
        fx.with_plans();
        let v = serde_json::json!({
            "session_id": "sess-rel",
            "tool_name": "Edit",
            "cwd": "relative/path",
        });
        assert!(observe(&v.to_string(), Some(&fx.store())).is_none());
    }

    #[test]
    fn an_unusable_store_is_allowed() {
        let fx = Fx::new();
        fx.with_plans();
        // The store could not be resolved at all.
        assert!(observe(&hook("sess-nostore", &fx.repo()), None).is_none());
        // The store path is not a directory.
        let notdir = fx.dir.join("notadir");
        std::fs::write(&notdir, "x").unwrap();
        assert!(observe(&hook("sess-nostore", &fx.repo()), Some(&notdir)).is_none());
    }

    #[test]
    fn a_symlinked_store_directory_is_refused() {
        let fx = Fx::new();
        let link = fx.dir.join("store-link");
        std::os::unix::fs::symlink(fx.store(), &link).unwrap();
        assert!(prepare_store(link).is_none());
        assert!(prepare_store(fx.dir.join("fresh")).is_some());
    }

    #[test]
    fn the_kill_switch_predicate() {
        assert!(is_truthy(Some("1")));
        assert!(is_truthy(Some("yes")));
        assert!(!is_truthy(Some("0")));
        assert!(!is_truthy(Some("false")));
        assert!(!is_truthy(Some("")));
        assert!(!is_truthy(None));
    }

    #[test]
    fn a_disabled_run_is_marked_rather_than_silent() {
        // Suppressing the witness would make a deliberately disabled run
        // indistinguishable from a run that predates the feature.
        let body = witness_body(&serde_json::json!({}), "s", Path::new("/repo"), true);
        let w: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(w["disabled"], true);
        assert_eq!(w["session_id"], "s");
    }

    #[test]
    fn the_witness_body_is_json_safe() {
        // A crafted working directory must stay inside the JSON string value.
        let cwd = PathBuf::from("/tmp/evil\" }] \u{1b}[31m/repo");
        let v = serde_json::json!({ "session_id": "s" });
        let body = witness_body(&v, "s", &cwd, false);
        let back: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(back["cwd"], cwd.to_string_lossy().to_string());
    }
}
