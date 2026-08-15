//! The `shirabe adherence-check` subcommand: the evidence half of the
//! read-only adherence determination.
//!
//! This increment establishes two of the determination's inputs and nothing
//! else. **Did the session register a koto orchestration session**, read from
//! the workflow record koto writes under the Claude Code project directory;
//! and **did it delegate every issue**, counted from koto's terminal index
//! against the issue count the PLAN declares. The six-value outcome domain,
//! the conflict-store join, and the coordinated carve-out are the next
//! increment; everything here is shaped to be its input.
//!
//! # Read-only means read-only
//!
//! Nothing in this module creates, opens for write, links, or removes a path.
//! It resolves its roots without `create_dir_all` — deliberately unlike the
//! hook's store resolution, which must create — and every parse failure
//! degrades to "unreadable" rather than repairing anything on disk. The only
//! bytes it emits go to stdout.
//!
//! # Absence is not failure
//!
//! The single most important property of this reading is what it does *not*
//! conclude. A completed nine-child run on the machine this was written
//! against (`execute-feature-23-google-cli-access`) carries **no workflow
//! record at all**: koto defaulted that recording on in a commit dated
//! 2026-07-18, and the record only began appearing in that workspace on
//! 2026-08-04. Every one of its nine children is in the terminal index and
//! none of them is in the record universe. A reading that treated absence as
//! non-registration would report a fully delegated run as non-conforming, and
//! a count that hard-required record corroboration would report that same run
//! as nought-of-nine delegated.
//!
//! So [`RegistrationReading::NoRecord`] is its own value, distinct from a
//! record that says the session registered nothing, and the delegation count
//! reports corroborated and uncorroborated children as two separate lists
//! rather than silently dropping the second. What separates "did not
//! register" from "nothing was watching" is the liveness witness
//! [`crate::adherence_hook`] writes, which the next increment joins in.
//!
//! # Two independent scopings, and why both are needed
//!
//! koto's terminal index is a **single machine-global file**. Its records
//! carry a session id, a timestamp, and a terminal state — no repository and
//! no path. On the machine this was written against it holds 138 distinct
//! session ids spanning months and unrelated repositories.
//!
//! Counting a parent's children by bare string prefix over that file is
//! therefore cross-session contamination waiting to happen, and not
//! hypothetically: a parent named `task` bare-prefix-matches eighteen
//! strangers (`task_i1_seam_generalization`, `task_i2_flow_definition`, …),
//! `commuter-booked` matches `commuter-booked-live-run`, and `issue_246`
//! matches `issue_2462`. So identities are matched on a delimited boundary
//! (see [`is_child_of`]) and the count is additionally scoped by the same
//! encoded project directory registration uses (see [`RepoScope`]).

use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

use shirabe_validate::{parse_doc, parse_issue_outlines, ParseError};

/// The envelope's schema identifier. A consumer that does not recognize this
/// value must refuse rather than read fields positionally.
pub const SCHEMA: &str = "shirabe-adherence-evidence/v1";

/// Exit codes, following the scheme `plan outlines` already uses: 0 read, 1
/// the input is not a readable PLAN, 3 I/O. There is deliberately no 2 — this
/// increment reports evidence and renders no verdict on it.
const EXIT_TOOL_ERROR: u8 = 1;
const EXIT_IO: u8 = 3;

/// Cap on the terminal index read. It is an append-only machine-global log
/// with no compaction, so its size is not bounded by anything this process
/// controls.
const MAX_INDEX_BYTES: u64 = 64 * 1024 * 1024;

/// The encoded form of `/.claude/worktrees/`: the path segment that turns a
/// repository's project directory into one of its worktrees'. Truncating an
/// encoded path here recovers the repository the worktree belongs to.
const WORKTREE_MARKER: &str = "--claude-worktrees-";

/// The character koto puts between a parent orchestration session's name and
/// a delegated child's. A child is named `<parent>.o-<task-slug>`.
///
/// This is the *only* character admitted as a boundary, and the narrowness is
/// the point. `-` and `_` both occur inside session names that are unrelated
/// siblings rather than children — `commuter-booked` beside
/// `commuter-booked-live-run`, `task` beside `task_i1_seam_generalization` —
/// so admitting either as a boundary reintroduces exactly the contamination
/// the boundary rule exists to prevent.
const CHILD_BOUNDARY: u8 = b'.';

/// The schema value a PLAN document declares.
const PLAN_SCHEMA: &str = "plan/v1";

#[derive(clap::Args)]
pub struct AdherenceCheckArgs {
    /// Path to the PLAN document the run was executing. The expected issue
    /// count is read from its `## Issue Outlines` section.
    #[arg(long)]
    pub plan: String,

    /// The Claude Code session id of the orchestrator, which is the key koto's
    /// workflow record is filed under.
    #[arg(long)]
    pub session: String,

    /// The koto orchestration session name whose children to count. Defaults
    /// to the workflow named by the freshest in-scope record for `--session`.
    #[arg(long)]
    pub parent: Option<String>,

    /// The working tree the run happened in. Defaults to the process's own
    /// working directory. Only its path is used, to derive the repository
    /// scope; nothing under it is read except the PLAN.
    #[arg(long)]
    pub cwd: Option<PathBuf>,

    /// Override the Claude Code projects directory (`~/.claude/projects`).
    #[arg(long)]
    pub projects_dir: Option<PathBuf>,

    /// Override koto's terminal index (`~/.koto/_terminal_index.jsonl`).
    #[arg(long)]
    pub terminal_index: Option<PathBuf>,
}

/// Entry point for `shirabe adherence-check`.
pub fn run(args: &AdherenceCheckArgs) -> ExitCode {
    let plan = match read_plan(Path::new(&args.plan)) {
        Ok(p) => p,
        Err(PlanError::Io(e)) => {
            eprintln!("[adherence check] cannot read {}: {}", args.plan, e);
            return ExitCode::from(EXIT_IO);
        }
        Err(PlanError::NotAPlan(what)) => {
            eprintln!(
                "[adherence check] {} is not a PLAN document ({what})",
                args.plan
            );
            return ExitCode::from(EXIT_TOOL_ERROR);
        }
    };

    let cwd = match args.cwd.clone().or_else(|| std::env::current_dir().ok()) {
        Some(c) => c,
        None => {
            eprintln!("[adherence check] cannot resolve a working directory");
            return ExitCode::from(EXIT_IO);
        }
    };

    let roots = Roots::resolve(args.projects_dir.clone(), args.terminal_index.clone());
    let scope = RepoScope::of(&cwd);
    let evidence = gather(&roots, &scope, &args.session, args.parent.as_deref(), &plan);

    println!("{}", render(&args.plan, &scope, &args.session, &evidence));
    ExitCode::SUCCESS
}

// --- roots -----------------------------------------------------------------

/// The two machine-local surfaces this reading consumes. Injected rather than
/// resolved inline so tests never touch the real home directory, and resolved
/// without creating anything.
pub struct Roots {
    /// `~/.claude/projects`, whose children are encoded project directories.
    pub projects: PathBuf,
    /// `~/.koto/_terminal_index.jsonl`, machine-global.
    pub terminal_index: PathBuf,
}

impl Roots {
    fn resolve(projects: Option<PathBuf>, terminal_index: Option<PathBuf>) -> Roots {
        let home = PathBuf::from(std::env::var("HOME").unwrap_or_default());
        Roots {
            projects: projects.unwrap_or_else(|| home.join(".claude").join("projects")),
            terminal_index: terminal_index
                .unwrap_or_else(|| home.join(".koto").join("_terminal_index.jsonl")),
        }
    }
}

// --- repository scope ------------------------------------------------------

/// The repository this reading is scoped to, expressed the only way the state
/// on disk expresses it: as the encoded project directory name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepoScope {
    /// The encoding of the repository root — the working tree's own encoding
    /// with any worktree suffix removed.
    pub encoded_repo: String,
}

impl RepoScope {
    /// Derive the scope from a working tree.
    pub fn of(cwd: &Path) -> RepoScope {
        let encoded = encode_project_dir(cwd);
        // The first occurrence, so a worktree nested inside a worktree still
        // resolves to the outermost repository.
        let encoded_repo = match encoded.find(WORKTREE_MARKER) {
            Some(i) => encoded[..i].to_string(),
            None => encoded,
        };
        RepoScope { encoded_repo }
    }

    /// Whether an encoded project directory belongs to this repository.
    ///
    /// The repository's own directory, and anything one path segment or more
    /// below it — which is what a worktree under `.claude/worktrees/` and a
    /// session started in a subdirectory both look like once encoded.
    ///
    /// The encoding is lossy and not invertible: every non-alphanumeric
    /// character collapses to `-`, so a *sibling* directory whose name extends
    /// the repository's (`shirabe-extra` beside `shirabe`) is admitted here
    /// too, and no amount of string work can tell it from a subdirectory named
    /// `extra`. That residual is benign because this is not the only scoping
    /// in force: a session from a sibling repository would still have to be
    /// named `<parent>.<something>` for this exact parent to be counted as one
    /// of its children, and the boundary rule is what actually carries the
    /// no-contamination guarantee.
    pub fn admits(&self, project_dir: &str) -> bool {
        if self.encoded_repo.is_empty() {
            return false;
        }
        if project_dir == self.encoded_repo {
            return true;
        }
        project_dir
            .strip_prefix(&self.encoded_repo)
            .is_some_and(|rest| rest.starts_with('-'))
    }
}

/// Encode an absolute path the way Claude Code names its project directories:
/// every character that is not an ASCII alphanumeric becomes `-`.
///
/// The leading `/` becomes the leading `-`, and `/.claude/worktrees/x` becomes
/// `--claude-worktrees-x`, which is why a worktree's encoding prefix-matches
/// its repository's.
pub fn encode_project_dir(path: &Path) -> String {
    path.to_string_lossy()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

// --- registration ----------------------------------------------------------

/// One koto workflow record, as written under
/// `<projects>/<encoded-cwd>/<claude-session-id>/workflows/koto-<uuid>.json`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkflowRecord {
    /// `koto.workflow`: the koto orchestration session's name. This is the
    /// identity the terminal index is keyed by.
    pub workflow: String,
    /// The template half of `name`, which koto shapes as
    /// `"<template> · <state>"`.
    pub template: Option<String>,
    /// `koto.currentState`.
    pub current_state: Option<String>,
    /// The record's top-level `status`.
    pub status: Option<String>,
    /// The encoded project directory the record was found under.
    pub project_dir: String,
    pub path: PathBuf,
    pub modified: SystemTime,
}

/// What the workflow records say about registration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RegistrationReading {
    /// A record exists for this session under this repository. The freshest by
    /// modification time, which is how a session that appears under more than
    /// one project directory is resolved.
    Registered(Box<WorkflowRecord>),
    /// No record under any in-scope project directory.
    ///
    /// **Not evidence of non-registration.** See the module docs: koto began
    /// writing these records long after it began delegating, so a fully
    /// conforming historical run reaches this arm. The caller must resolve it
    /// against the liveness witness, not against the absence itself.
    NoRecord,
}

/// Everything one walk of the in-scope project directories yields.
#[derive(Debug, Default)]
pub struct ScopedRecords {
    /// Every koto session name carrying a workflow record under an in-scope
    /// project directory — the repository's record universe, used to
    /// corroborate terminal-index entries that carry no repository of their
    /// own.
    pub known_sessions: BTreeSet<String>,
    /// Records filed under the queried Claude Code session id, freshest first.
    pub for_session: Vec<WorkflowRecord>,
    /// The in-scope project directories that were walked.
    pub project_dirs: Vec<String>,
}

impl ScopedRecords {
    /// The registration reading: the freshest in-scope record for the session.
    pub fn registration(&self) -> RegistrationReading {
        match self.for_session.first() {
            Some(r) => RegistrationReading::Registered(Box::new(r.clone())),
            None => RegistrationReading::NoRecord,
        }
    }
}

/// Walk the in-scope project directories once, collecting both the repository's
/// record universe and the records filed under `claude_session`.
///
/// Every I/O failure is skipped rather than propagated: a project directory
/// that cannot be listed contributes nothing, which reads through as absence,
/// which the caller already must not treat as failure.
pub fn scan_records(roots: &Roots, scope: &RepoScope, claude_session: &str) -> ScopedRecords {
    let mut out = ScopedRecords::default();
    let session = sanitize_component(claude_session);

    let Ok(entries) = std::fs::read_dir(&roots.projects) else {
        return out;
    };

    for entry in entries.flatten() {
        let dir_name = entry.file_name().to_string_lossy().to_string();
        if !scope.admits(&dir_name) {
            continue;
        }
        out.project_dirs.push(dir_name.clone());

        let Ok(sessions) = std::fs::read_dir(entry.path()) else {
            continue;
        };
        for s in sessions.flatten() {
            let s_name = s.file_name().to_string_lossy().to_string();
            let mine = session.as_deref() == Some(s_name.as_str());
            for record in read_workflow_dir(&s.path().join("workflows"), &dir_name) {
                out.known_sessions.insert(record.workflow.clone());
                if mine {
                    out.for_session.push(record);
                }
            }
        }
    }

    out.project_dirs.sort();
    // Freshest first. `mtime` is the tiebreaker the acceptance criterion
    // names; the path keeps the order total so the reading is deterministic
    // when two records share a timestamp.
    out.for_session
        .sort_by(|a, b| b.modified.cmp(&a.modified).then(a.path.cmp(&b.path)));
    out
}

/// Read every `koto-*.json` in one `workflows/` directory.
fn read_workflow_dir(dir: &Path, project_dir: &str) -> Vec<WorkflowRecord> {
    let Ok(files) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for f in files.flatten() {
        let name = f.file_name().to_string_lossy().to_string();
        if !name.starts_with("koto-") || !name.ends_with(".json") {
            continue;
        }
        let Ok(meta) = f.metadata() else { continue };
        if !meta.is_file() {
            continue;
        }
        let modified = meta.modified().unwrap_or(UNIX_EPOCH);
        if let Some(r) = parse_workflow_record(&f.path(), project_dir, modified) {
            out.push(r);
        }
    }
    out
}

/// Parse one workflow record. A record naming no koto workflow identifies no
/// orchestration session and is dropped.
fn parse_workflow_record(
    path: &Path,
    project_dir: &str,
    modified: SystemTime,
) -> Option<WorkflowRecord> {
    let raw = std::fs::read_to_string(path).ok()?;
    let v: serde_json::Value = serde_json::from_str(&raw).ok()?;
    let koto = v.get("koto")?;
    let workflow = koto.get("workflow").and_then(|w| w.as_str())?.to_string();
    if workflow.is_empty() {
        return None;
    }
    // koto shapes `name` as "<template> · <state>". The state half is
    // redundant with `koto.currentState`; the template half is not recorded
    // anywhere else.
    let template = v
        .get("name")
        .and_then(|n| n.as_str())
        .map(|n| n.split_once(" · ").map_or(n, |(t, _)| t).trim().to_string())
        .filter(|t| !t.is_empty());

    Some(WorkflowRecord {
        workflow,
        template,
        current_state: koto
            .get("currentState")
            .and_then(|s| s.as_str())
            .map(str::to_string),
        status: v.get("status").and_then(|s| s.as_str()).map(str::to_string),
        project_dir: project_dir.to_string(),
        path: path.to_path_buf(),
        modified,
    })
}

/// A Claude Code session id is used as a path component, so it is admitted
/// only as ASCII alphanumerics, `-`, and `_`. That excludes `/`, `..`, and a
/// leading `.` without needing a separate traversal check.
fn sanitize_component(s: &str) -> Option<String> {
    if s.is_empty() || s.len() > 128 {
        return None;
    }
    s.chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        .then(|| s.to_string())
}

// --- delegation ------------------------------------------------------------

/// One terminal-index entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TerminalChild {
    pub session_id: String,
    pub terminal_state: Option<String>,
    pub has_result: bool,
}

/// Whether `candidate` is a delegated child of `parent`.
///
/// The rule is a delimited boundary, never a bare prefix: `candidate` must
/// begin with `parent`, the next byte must be [`CHILD_BOUNDARY`], and
/// something must follow it. Measured against the 138 session ids on the
/// machine this was written against, the boundary drops 22 bare-prefix false
/// positives and loses no true child.
pub fn is_child_of(parent: &str, candidate: &str) -> bool {
    if parent.is_empty() {
        return false;
    }
    match candidate.strip_prefix(parent) {
        Some(rest) => rest.as_bytes().first() == Some(&CHILD_BOUNDARY) && rest.len() > 1,
        None => false,
    }
}

/// The delegation reading for one parent orchestration session.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DelegationCount {
    pub parent: String,
    /// Whether the parent itself carries a workflow record under this
    /// repository.
    pub parent_corroborated: bool,
    /// Boundary-children of `parent` that reached a terminal state *and* carry
    /// a workflow record under an in-scope project directory. This is the
    /// delegated count.
    pub corroborated: Vec<TerminalChild>,
    /// Boundary-children present in the terminal index that carry no such
    /// record.
    ///
    /// This list is not noise and must not be folded into either the count or
    /// zero. The terminal index carries no repository, so the record universe
    /// is the only thing that can place a session in this repository — and
    /// koto began writing those records long after it began delegating. A
    /// historical run reaches here with every child uncorroborated, and the
    /// caller distinguishes "no children ran" from "children ran and this
    /// repository has no record of them" by which list is empty.
    pub uncorroborated: Vec<TerminalChild>,
    /// False when the terminal index could not be read at all, which is
    /// unreadable evidence rather than zero delegation.
    pub index_read: bool,
}

impl DelegationCount {
    /// The delegated count: children corroborated as belonging to this
    /// repository.
    pub fn delegated(&self) -> usize {
        self.corroborated.len()
    }
}

/// Count `parent`'s delegated children from the terminal index, scoped by the
/// repository's record universe and matched on the delimited boundary.
pub fn count_delegation(roots: &Roots, known: &BTreeSet<String>, parent: &str) -> DelegationCount {
    let mut out = DelegationCount {
        parent: parent.to_string(),
        parent_corroborated: known.contains(parent),
        ..Default::default()
    };
    let Some(entries) = read_terminal_index(&roots.terminal_index) else {
        return out;
    };
    out.index_read = true;

    for (session_id, child) in entries {
        if !is_child_of(parent, &session_id) {
            continue;
        }
        if known.contains(&session_id) {
            out.corroborated.push(child);
        } else {
            out.uncorroborated.push(child);
        }
    }
    out
}

/// Read the terminal index, deduplicated by session id with the last entry
/// winning — it is append-only, so a session that reaches a terminal state
/// more than once appears more than once and the last line is its current
/// state.
///
/// Returns `None` when the file cannot be read at all; unparsable individual
/// lines are skipped, since one torn append must not blind the whole count.
fn read_terminal_index(path: &Path) -> Option<BTreeMap<String, TerminalChild>> {
    let file = std::fs::File::open(path).ok()?;
    let mut raw = String::new();
    file.take(MAX_INDEX_BYTES).read_to_string(&mut raw).ok()?;

    let mut out = BTreeMap::new();
    for line in raw.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let Some(session_id) = v.get("session_id").and_then(|s| s.as_str()) else {
            continue;
        };
        if session_id.is_empty() {
            continue;
        }
        out.insert(
            session_id.to_string(),
            TerminalChild {
                session_id: session_id.to_string(),
                terminal_state: v
                    .get("terminal_state")
                    .and_then(|s| s.as_str())
                    .map(str::to_string),
                has_result: v
                    .get("has_result")
                    .and_then(|b| b.as_bool())
                    .unwrap_or(false),
            },
        );
    }
    Some(out)
}

// --- the plan --------------------------------------------------------------

/// What the PLAN document contributes: how many issues the run was supposed to
/// delegate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanExpectation {
    /// The number of `### Issue <N>:` outline blocks — the structural count,
    /// and the one the delegation count is compared against.
    pub expected_issues: usize,
    /// The `issue_count` frontmatter field, when declared. Reported alongside
    /// rather than used: a disagreement with `expected_issues` means the
    /// document contradicts itself, which a reader should see rather than have
    /// silently resolved here.
    pub declared_issue_count: Option<usize>,
}

pub enum PlanError {
    Io(String),
    NotAPlan(String),
}

/// Read the PLAN. Refuses anything that is not a `plan/v1` document, so a
/// mistyped path cannot silently contribute an expectation of zero.
pub fn read_plan(path: &Path) -> Result<PlanExpectation, PlanError> {
    let doc = match parse_doc(path) {
        Ok(d) => d,
        Err(ParseError::Io(e)) => return Err(PlanError::Io(e.to_string())),
        Err(e) => return Err(PlanError::NotAPlan(e.to_string())),
    };

    let schema = doc.fields.get("schema").map(|f| f.value.trim().to_string());
    if schema.as_deref() != Some(PLAN_SCHEMA) {
        return Err(PlanError::NotAPlan(format!(
            "expected 'schema: {PLAN_SCHEMA}', found {}",
            schema
                .as_deref()
                .map(|s| format!("'{s}'"))
                .unwrap_or_else(|| "no schema field".to_string())
        )));
    }

    Ok(PlanExpectation {
        expected_issues: parse_issue_outlines(&doc).blocks.len(),
        declared_issue_count: doc
            .fields
            .get("issue_count")
            .and_then(|f| f.value.trim().parse().ok()),
    })
}

// --- the gathered evidence -------------------------------------------------

/// Everything this increment establishes, in the shape the outcome domain
/// consumes. Deliberately holds no verdict: choosing among conforming,
/// non-conforming, coordinated, departed, disabled, and indeterminate needs
/// the liveness witness and the conflict store, neither of which is joined
/// here.
pub struct Evidence {
    pub registration: RegistrationReading,
    pub delegation: DelegationCount,
    pub plan: PlanExpectation,
    pub project_dirs: Vec<String>,
}

/// Gather the registration and delegation readings.
///
/// `parent` names the orchestration session whose children to count; when it
/// is `None` the workflow named by the freshest in-scope record is used, and
/// with no record there is nothing to count children of.
pub fn gather(
    roots: &Roots,
    scope: &RepoScope,
    claude_session: &str,
    parent: Option<&str>,
    plan: &PlanExpectation,
) -> Evidence {
    let records = scan_records(roots, scope, claude_session);
    let registration = records.registration();

    let parent = parent.map(str::to_string).or_else(|| match &registration {
        RegistrationReading::Registered(r) => Some(r.workflow.clone()),
        RegistrationReading::NoRecord => None,
    });

    let delegation = match parent {
        Some(p) => count_delegation(roots, &records.known_sessions, &p),
        None => DelegationCount::default(),
    };

    Evidence {
        registration,
        delegation,
        plan: plan.clone(),
        project_dirs: records.project_dirs,
    }
}

// --- rendering -------------------------------------------------------------

fn render(plan_path: &str, scope: &RepoScope, session: &str, e: &Evidence) -> String {
    let registration = match &e.registration {
        RegistrationReading::Registered(r) => serde_json::json!({
            "reading": "registered",
            "workflow": r.workflow,
            "template": r.template,
            "current_state": r.current_state,
            "status": r.status,
            "project_dir": r.project_dir,
            "record": r.path.to_string_lossy(),
            "modified_unix": unix_secs(r.modified),
        }),
        // Named so a consumer cannot mistake it for a negative finding.
        RegistrationReading::NoRecord => serde_json::json!({
            "reading": "no_record",
            "note": "absence of a workflow record is not evidence of non-registration",
        }),
    };

    let value = serde_json::json!({
        "schema": SCHEMA,
        "plan": plan_path,
        "session": session,
        "repo_scope": scope.encoded_repo,
        "project_directories": e.project_dirs,
        "expected_issues": e.plan.expected_issues,
        "declared_issue_count": e.plan.declared_issue_count,
        "registration": registration,
        "delegation": {
            "parent": e.delegation.parent,
            "parent_corroborated": e.delegation.parent_corroborated,
            "index_read": e.delegation.index_read,
            "delegated": e.delegation.delegated(),
            "corroborated": children_json(&e.delegation.corroborated),
            "uncorroborated": children_json(&e.delegation.uncorroborated),
        },
    });
    serde_json::to_string_pretty(&value).unwrap_or_default()
}

fn children_json(children: &[TerminalChild]) -> serde_json::Value {
    serde_json::Value::Array(
        children
            .iter()
            .map(|c| {
                serde_json::json!({
                    "session_id": c.session_id,
                    "terminal_state": c.terminal_state,
                    "has_result": c.has_result,
                })
            })
            .collect(),
    )
}

fn unix_secs(t: SystemTime) -> u64 {
    t.duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// A throwaway tree standing in for `~/.claude/projects` and
    /// `~/.koto/_terminal_index.jsonl`.
    struct Fx {
        dir: PathBuf,
    }

    impl Fx {
        fn new() -> Fx {
            static N: AtomicUsize = AtomicUsize::new(0);
            let n = N.fetch_add(1, Ordering::SeqCst);
            let dir = std::env::temp_dir().join(format!(
                "shirabe-adherence-check-{}-{}",
                std::process::id(),
                n
            ));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(dir.join("projects")).unwrap();
            Fx { dir }
        }

        fn roots(&self) -> Roots {
            Roots {
                projects: self.dir.join("projects"),
                terminal_index: self.dir.join("index.jsonl"),
            }
        }

        /// Write a workflow record for `session` under encoded project
        /// directory `project_dir`, naming koto session `workflow`.
        fn record(&self, project_dir: &str, session: &str, workflow: &str) -> PathBuf {
            let dir = self
                .dir
                .join("projects")
                .join(project_dir)
                .join(session)
                .join("workflows");
            std::fs::create_dir_all(&dir).unwrap();
            let path = dir.join(format!("koto-{workflow}.json"));
            let body = serde_json::json!({
                "id": format!("koto-{workflow}"),
                "name": "execute · spawn_and_await",
                "status": "running",
                "koto": {
                    "sessionId": "0000-1111",
                    "workflow": workflow,
                    "currentState": "spawn_and_await",
                    "contractVersion": 2,
                },
            });
            std::fs::write(&path, body.to_string()).unwrap();
            path
        }

        fn index(&self, session_ids: &[&str]) {
            let body: String = session_ids
                .iter()
                .map(|s| {
                    format!(
                        "{{\"session_id\":\"{s}\",\"terminal_at\":\"2026-08-01T00:00:00Z\",\
                         \"terminal_state\":\"completed\",\"has_result\":true}}\n"
                    )
                })
                .collect();
            std::fs::write(self.dir.join("index.jsonl"), body).unwrap();
        }

        fn plan(&self, body: &str) -> PathBuf {
            let path = self.dir.join("PLAN-fixture.md");
            std::fs::write(&path, body).unwrap();
            path
        }

        /// Every path under the fixture, for the writes-nothing assertion.
        fn snapshot(&self) -> Vec<String> {
            fn walk(dir: &Path, out: &mut Vec<String>) {
                let Ok(entries) = std::fs::read_dir(dir) else {
                    return;
                };
                for e in entries.flatten() {
                    out.push(e.path().to_string_lossy().to_string());
                    if e.path().is_dir() {
                        walk(&e.path(), out);
                    }
                }
            }
            let mut out = Vec::new();
            walk(&self.dir, &mut out);
            out.sort();
            out
        }
    }

    impl Drop for Fx {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    const REPO: &str =
        "/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/public/shirabe";
    const REPO_ENC: &str =
        "-home-dgazineu-dev-niwaw-tsuku-tsuku-execute-and-work-on-trigger-d36b0bbf-public-shirabe";

    /// Real session ids read off the machine this was written against. The
    /// boundary rule is measured against these, not against invented names.
    const REAL_INDEX_IDS: &[&str] = &[
        "task",
        "task_i1_seam_generalization",
        "task_i2_flow_definition",
        "task_charter_always_roadmap",
        "task_execute-skeleton",
        "commuter-booked",
        "commuter-booked-live-run",
        "commuter-booked-validate",
        "issue_246",
        "issue_2462",
        "issue_2463",
        "execute-feature-23-google-cli-access",
        "execute-feature-23-google-cli-access.o-docs-guides-add-the-gmail-cloud-console-setup-guide",
        "execute-feature-23-google-cli-access.o-feat-scripts-add-the-gmail-oauth-credential",
        "execute-feature-23-google-cli-access.o-test-security-add-the-secret-hygiene-scan",
    ];

    fn plan_body(issues: usize, declared: usize) -> String {
        let mut s = format!(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: single-pr\nissue_count: {declared}\n---\n\n# PLAN: Fixture\n\n## Issue Outlines\n\n"
        );
        for n in 1..=issues {
            s.push_str(&format!(
                "### Issue {n}: Step {n}\n\n**Goal**: Do step {n}.\n\n**Acceptance Criteria**:\n- [ ] It is done.\n\n**Dependencies**: None\n\n**Type**: code\n**Files**: `src/a.rs`\n\n---\n\n"
            ));
        }
        s
    }

    // --- encoding and scope ---

    #[test]
    fn encoding_matches_claude_codes_project_directory_names() {
        // Verified against the real directory names under ~/.claude/projects.
        assert_eq!(encode_project_dir(Path::new(REPO)), REPO_ENC);
        assert_eq!(
            encode_project_dir(Path::new("/home/dgazineu/.claude/jobs/0726b22a/tmp/x")),
            "-home-dgazineu--claude-jobs-0726b22a-tmp-x"
        );
    }

    #[test]
    fn a_worktree_encoding_prefix_matches_its_repository() {
        let wt = PathBuf::from(REPO).join(".claude/worktrees/skill-adherence-enforcement");
        let encoded = encode_project_dir(&wt);
        assert_eq!(
            encoded,
            format!("{REPO_ENC}--claude-worktrees-skill-adherence-enforcement")
        );
        // A session run inside the worktree scopes to the repository, and both
        // directories are admitted.
        let scope = RepoScope::of(&wt);
        assert_eq!(scope.encoded_repo, REPO_ENC);
        assert!(scope.admits(REPO_ENC));
        assert!(scope.admits(&encoded));
    }

    #[test]
    fn scope_rejects_unrelated_repositories() {
        let scope = RepoScope::of(Path::new(REPO));
        assert!(
            !scope.admits("-home-dgazineu-dev-niwaw-tsuku-tsuku-install-reinstall-flag-80b388aa")
        );
        assert!(!scope.admits("-home-dgazineu--claude-jobs-0726b22a-tmp-indep1-d-projset-215-repo"));
        // A shorter path that the repository extends is not a parent scope.
        assert!(!scope.admits("-home-dgazineu-dev-niwaw-tsuku"));
    }

    #[test]
    fn an_empty_scope_admits_nothing() {
        let scope = RepoScope {
            encoded_repo: String::new(),
        };
        assert!(!scope.admits("-anything"));
        assert!(!scope.admits(""));
    }

    // --- the boundary rule ---

    #[test]
    fn a_parent_name_that_prefixes_strangers_does_not_adopt_them() {
        // The regression test for the cross-session contamination the security
        // review found. Every one of these is a real session id from the
        // machine's terminal index, and every one bare-prefix-matches.
        for stranger in [
            "task_i1_seam_generalization",
            "task_i2_flow_definition",
            "task_charter_always_roadmap",
            "task_execute-skeleton",
        ] {
            assert!(
                stranger.starts_with("task"),
                "{stranger} must be a bare-prefix match for the test to mean anything"
            );
            assert!(
                !is_child_of("task", stranger),
                "{stranger} is not a child of task"
            );
        }
        assert!(!is_child_of("commuter-booked", "commuter-booked-live-run"));
        assert!(!is_child_of("commuter-booked", "commuter-booked-validate"));
        assert!(!is_child_of("issue_246", "issue_2462"));
        assert!(!is_child_of("issue_246", "issue_2463"));
    }

    #[test]
    fn a_delegated_child_is_matched() {
        let parent = "execute-feature-23-google-cli-access";
        assert!(is_child_of(
            parent,
            "execute-feature-23-google-cli-access.o-feat-scripts-add-the-gmail-oauth-credential"
        ));
        // The parent is not its own child, and neither is a bare trailing dot.
        assert!(!is_child_of(parent, parent));
        assert!(!is_child_of(parent, &format!("{parent}.")));
        // An empty parent would match the whole index.
        assert!(!is_child_of("", "anything.o-x"));
    }

    // --- registration ---

    #[test]
    fn registration_is_read_from_the_in_scope_record() {
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", "execute-topic");
        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        match records.registration() {
            RegistrationReading::Registered(r) => {
                assert_eq!(r.workflow, "execute-topic");
                assert_eq!(r.template.as_deref(), Some("execute"));
                assert_eq!(r.current_state.as_deref(), Some("spawn_and_await"));
                assert_eq!(r.project_dir, REPO_ENC);
            }
            RegistrationReading::NoRecord => panic!("expected a record"),
        }
    }

    #[test]
    fn a_record_under_another_repository_is_not_this_repositorys() {
        let fx = Fx::new();
        fx.record(
            "-home-dgazineu-dev-niwaw-tsuku-tsuku-something-else",
            "sess-a",
            "execute-topic",
        );
        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        assert_eq!(records.registration(), RegistrationReading::NoRecord);
        assert!(records.known_sessions.is_empty());
    }

    #[test]
    fn the_freshest_record_wins_across_project_directories() {
        let fx = Fx::new();
        let wt = format!("{REPO_ENC}--claude-worktrees-w1");
        let older = fx.record(REPO_ENC, "sess-a", "execute-older");
        let newer = fx.record(&wt, "sess-a", "execute-newer");
        // Make the ordering unambiguous rather than trusting write order.
        set_mtime(&older, 1_000_000);
        set_mtime(&newer, 2_000_000);

        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        assert_eq!(
            records.for_session.len(),
            2,
            "both directories are in scope"
        );
        match records.registration() {
            RegistrationReading::Registered(r) => assert_eq!(r.workflow, "execute-newer"),
            RegistrationReading::NoRecord => panic!("expected a record"),
        }
    }

    #[test]
    fn absence_of_a_record_is_its_own_reading() {
        let fx = Fx::new();
        // A record exists for the repository, but not for this session.
        fx.record(REPO_ENC, "sess-other", "execute-topic");
        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        assert_eq!(records.registration(), RegistrationReading::NoRecord);
        // The repository's record universe still sees the other session.
        assert!(records.known_sessions.contains("execute-topic"));
    }

    #[test]
    fn a_traversal_shaped_session_id_matches_nothing() {
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", "execute-topic");
        let scope = RepoScope::of(Path::new(REPO));
        for sid in ["../sess-a", "a/b", ".hidden", ""] {
            let records = scan_records(&fx.roots(), &scope, sid);
            assert_eq!(
                records.registration(),
                RegistrationReading::NoRecord,
                "session id {sid:?} must match no record"
            );
        }
    }

    #[test]
    fn a_record_naming_no_workflow_is_dropped() {
        let fx = Fx::new();
        let dir = fx
            .dir
            .join("projects")
            .join(REPO_ENC)
            .join("sess-a")
            .join("workflows");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("koto-x.json"), "{\"name\":\"execute · x\"}").unwrap();
        std::fs::write(dir.join("koto-y.json"), "not json").unwrap();
        std::fs::write(dir.join("other.json"), "{\"koto\":{\"workflow\":\"w\"}}").unwrap();
        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        assert_eq!(records.registration(), RegistrationReading::NoRecord);
        assert!(records.known_sessions.is_empty());
    }

    // --- delegation ---

    #[test]
    fn delegation_counts_only_corroborated_boundary_children() {
        let fx = Fx::new();
        let parent = "execute-feature-23-google-cli-access";
        fx.record(REPO_ENC, "sess-a", parent);
        for child in REAL_INDEX_IDS.iter().filter(|s| is_child_of(parent, s)) {
            fx.record(REPO_ENC, "sess-child", child);
        }
        fx.index(REAL_INDEX_IDS);

        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        let d = count_delegation(&fx.roots(), &records.known_sessions, parent);

        assert!(d.index_read);
        assert!(d.parent_corroborated);
        assert_eq!(
            d.delegated(),
            3,
            "the three `.o-` children and nothing else"
        );
        assert!(d.uncorroborated.is_empty());
        for c in &d.corroborated {
            assert!(is_child_of(parent, &c.session_id));
            assert_eq!(c.terminal_state.as_deref(), Some("completed"));
            assert!(c.has_result);
        }
    }

    #[test]
    fn a_prefix_colliding_parent_counts_none_of_the_strangers() {
        // The same regression, driven end to end through the counter: `task`
        // is corroborated and its bare-prefix matches are too, so only the
        // boundary rule stands between the count and eighteen strangers.
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", "task");
        for id in REAL_INDEX_IDS {
            fx.record(REPO_ENC, "sess-strangers", id);
        }
        fx.index(REAL_INDEX_IDS);

        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        let d = count_delegation(&fx.roots(), &records.known_sessions, "task");
        assert_eq!(d.delegated(), 0, "counted: {:?}", d.corroborated);
        assert!(d.uncorroborated.is_empty());
    }

    #[test]
    fn children_without_a_record_are_reported_uncorroborated_not_dropped() {
        // The historical shape: a fully delegated run whose children are all in
        // the terminal index and none of which has a workflow record. Zero
        // delegated must be distinguishable from zero children.
        let fx = Fx::new();
        let parent = "execute-feature-23-google-cli-access";
        fx.record(REPO_ENC, "sess-a", parent);
        fx.index(REAL_INDEX_IDS);

        let scope = RepoScope::of(Path::new(REPO));
        let records = scan_records(&fx.roots(), &scope, "sess-a");
        let d = count_delegation(&fx.roots(), &records.known_sessions, parent);
        assert_eq!(d.delegated(), 0);
        assert_eq!(d.uncorroborated.len(), 3);
    }

    #[test]
    fn an_unreadable_index_is_not_zero_delegation() {
        let fx = Fx::new();
        // No index file written at all.
        let d = count_delegation(&fx.roots(), &BTreeSet::new(), "execute-topic");
        assert!(!d.index_read, "the caller must see unreadable, not zero");
        assert_eq!(d.delegated(), 0);
    }

    #[test]
    fn the_index_is_deduplicated_last_entry_winning() {
        let fx = Fx::new();
        std::fs::write(
            fx.dir.join("index.jsonl"),
            concat!(
                "{\"session_id\":\"p.o-a\",\"terminal_state\":\"failed\",\"has_result\":false}\n",
                "\n",
                "not json at all\n",
                "{\"terminal_state\":\"completed\"}\n",
                "{\"session_id\":\"p.o-a\",\"terminal_state\":\"completed\",\"has_result\":true}\n",
            ),
        )
        .unwrap();
        let known: BTreeSet<String> = ["p.o-a".to_string()].into_iter().collect();
        let d = count_delegation(&fx.roots(), &known, "p");
        assert_eq!(d.delegated(), 1);
        assert_eq!(
            d.corroborated[0].terminal_state.as_deref(),
            Some("completed")
        );
        assert!(d.corroborated[0].has_result);
    }

    // --- the plan ---

    #[test]
    fn the_expected_count_comes_from_the_plan() {
        let fx = Fx::new();
        let path = fx.plan(&plan_body(9, 9));
        let p = read_plan(&path).ok().expect("a plan/v1 document");
        assert_eq!(p.expected_issues, 9);
        assert_eq!(p.declared_issue_count, Some(9));
    }

    #[test]
    fn a_self_contradicting_plan_reports_both_counts() {
        let fx = Fx::new();
        let path = fx.plan(&plan_body(3, 9));
        let p = read_plan(&path).ok().expect("a plan/v1 document");
        assert_eq!(
            p.expected_issues, 3,
            "the outlines are the structural truth"
        );
        assert_eq!(p.declared_issue_count, Some(9));
    }

    #[test]
    fn a_document_that_is_not_a_plan_is_refused() {
        let fx = Fx::new();
        let path = fx.plan("---\nschema: design/v1\nstatus: Current\n---\n\n# DESIGN\n");
        assert!(matches!(read_plan(&path), Err(PlanError::NotAPlan(_))));
        assert!(matches!(
            read_plan(&fx.dir.join("absent.md")),
            Err(PlanError::Io(_))
        ));
    }

    // --- the whole reading ---

    #[test]
    fn the_parent_defaults_to_the_registered_workflow() {
        let fx = Fx::new();
        let parent = "execute-feature-23-google-cli-access";
        fx.record(REPO_ENC, "sess-a", parent);
        for child in REAL_INDEX_IDS.iter().filter(|s| is_child_of(parent, s)) {
            fx.record(REPO_ENC, "sess-child", child);
        }
        fx.index(REAL_INDEX_IDS);
        let plan = read_plan(&fx.plan(&plan_body(3, 3))).ok().unwrap();

        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        assert_eq!(e.delegation.parent, parent);
        assert_eq!(e.delegation.delegated(), 3);
        assert_eq!(e.plan.expected_issues, 3);
    }

    #[test]
    fn with_no_record_and_no_parent_there_is_nothing_to_count() {
        let fx = Fx::new();
        fx.index(REAL_INDEX_IDS);
        let plan = read_plan(&fx.plan(&plan_body(2, 2))).ok().unwrap();
        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        assert_eq!(e.registration, RegistrationReading::NoRecord);
        assert_eq!(e.delegation.parent, "");
        assert!(!e.delegation.index_read, "the index was never consulted");
    }

    #[test]
    fn the_determination_writes_nothing() {
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", "execute-topic");
        fx.index(REAL_INDEX_IDS);
        let plan_path = fx.plan(&plan_body(2, 2));
        let before = fx.snapshot();

        let plan = read_plan(&plan_path).ok().unwrap();
        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        let _ = render("PLAN-fixture.md", &scope, "sess-a", &e);

        assert_eq!(before, fx.snapshot(), "the reading must not touch the tree");
        // And a missing projects root is read, not created.
        let absent = Roots {
            projects: fx.dir.join("no-such-projects"),
            terminal_index: fx.dir.join("no-such-index"),
        };
        let _ = gather(&absent, &scope, "sess-a", None, &plan);
        assert!(!fx.dir.join("no-such-projects").exists());
        assert!(!fx.dir.join("no-such-index").exists());
    }

    #[test]
    fn the_envelope_names_absence_rather_than_implying_failure() {
        let fx = Fx::new();
        let plan = read_plan(&fx.plan(&plan_body(2, 2))).ok().unwrap();
        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        let out = render("PLAN-fixture.md", &scope, "sess-a", &e);
        let v: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["schema"], SCHEMA);
        assert_eq!(v["registration"]["reading"], "no_record");
        assert_eq!(v["repo_scope"], REPO_ENC);
        assert_eq!(v["expected_issues"], 2);
    }

    /// Set a file's mtime, so freshness ordering is asserted rather than
    /// inferred from write order.
    fn set_mtime(path: &Path, secs: i64) {
        let ts = rustix::fs::Timestamps {
            last_access: rustix::fs::Timespec {
                tv_sec: secs,
                tv_nsec: 0,
            },
            last_modification: rustix::fs::Timespec {
                tv_sec: secs,
                tv_nsec: 0,
            },
        };
        rustix::fs::utimensat(rustix::fs::CWD, path, &ts, rustix::fs::AtFlags::empty()).unwrap();
    }
}
