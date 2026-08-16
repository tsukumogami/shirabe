//! The `shirabe adherence-check` subcommand: the read-only adherence
//! determination.
//!
//! Four inputs, one verdict. **Did the session register a koto orchestration
//! session**, read from the workflow record koto writes under the Claude Code
//! project directory; **did it delegate every issue**, counted from koto's
//! terminal index against the issue count the PLAN declares; **was anything
//! watching**, read from the per-session liveness witness
//! [`crate::adherence_hook`] writes; and **did it declare its departures**,
//! read from the conflict store [`crate::conflict_record`] writes. The verdict
//! is one of six values ([`Outcome`]).
//!
//! # The outcome domain, in resolution order
//!
//! First match wins, and the order is itself a claim about what may be
//! concluded from what:
//!
//! 1. [`Outcome::Coordinated`] — the PLAN's execution mode is `coordinated`. A
//!    coordinated plan has no single koto orchestration session to register and
//!    no per-issue delegation to count, so the delegation question does not
//!    apply. This is a carve-out, not a pass.
//! 2. [`Outcome::Disabled`] — the witness says the operator switch was off. The
//!    hook still wrote a witness (deliberately: see the hook's module docs), so
//!    "somebody turned this off" stays distinguishable from "nothing was
//!    watching".
//! 3. [`Outcome::Indeterminate`] — no witness, an unreadable witness, a PLAN
//!    declaring no issues, or an unreadable terminal index. Evidence that
//!    cannot be read is never reported as a violation.
//! 4. [`Outcome::NonConforming`] — past the witness gate, no workflow record
//!    means the session genuinely registered nothing. See "Absence is not
//!    failure" below for why that inference needs the witness.
//! 5. [`Outcome::Conforming`] — registered, and every issue the PLAN declares
//!    is a corroborated delegated child. **Nothing else reaches this value**;
//!    in particular the conflict store is not consulted before it is decided.
//! 6. [`Outcome::Departed`] / [`Outcome::NonConforming`] — a shortfall, split by
//!    whether the conflict store covers it.
//!
//! # A covered shortfall is `departed`, and never `conforming`
//!
//! An earlier draft of the design reported a shortfall covered by a conflict
//! record as conforming. That is wrong twice over. It contradicts the
//! requirement reserving `conforming` for a registered, fully delegated run,
//! and it makes the verified verdict **purchasable**: a session that wants to
//! implement inline runs the conflict recorder once, states a plausible
//! conflict, does the work itself, and reads back `conforming`. The record's
//! content is free text that nothing validates. So the covered case gets its
//! own value, `conforming` is decided before the store is read at all, and
//! `recording_a_conflict_does_not_buy_conforming` is the regression test.
//!
//! # Matching a record to a shortfall, not merely counting records
//!
//! A conflict record carries the workflow step it conflicts with, and that is
//! what ties it to a missing delegation. Two rules follow, both adversarial:
//!
//! - A record naming a step that is not the delegation step covers nothing. A
//!   conflict about assembling a pull request body does not excuse an
//!   undelegated issue.
//! - Records are counted by **distinct** step identity, and an identity that
//!   names an issue number the PLAN does not have counts for nothing. Without
//!   distinctness one recorded conflict would launder an arbitrary number of
//!   silent drops, which is exactly the failure the design names.
//!
//! See [`step_identity`]. What the join can prove is that a departure was
//! declared once per missing delegation; it cannot prove the declared issue is
//! the dropped one, because the terminal index carries no issue identity.
//!
//! # The join walks children
//!
//! Conflict records are keyed by the session that wrote them, and a
//! koto-delegated child runs under its own session identity, so reading the
//! orchestrator's store alone misses every conflict a child raised. The child
//! set is resolved first (from the terminal index, on the delimited boundary
//! below) and the store is read for the orchestrator's Claude Code session, for
//! the parent orchestration session, and for every boundary child — corroborated
//! or not, since a child that raised a conflict may still lack a workflow
//! record.
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
//! [`crate::adherence_hook`] writes, and [`determine`] consults the witness
//! before it is willing to read `NoRecord` as non-registration: a witness
//! exists only in a session running the shipped hook, and koto's record
//! defaulted on months before that hook did.
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
///
/// It says `determination` rather than `evidence` because the envelope now
/// carries an [`Outcome`] alongside the readings it was derived from; a
/// consumer keying on the tag learns which it is getting.
pub const SCHEMA: &str = "shirabe-adherence-determination/v1";

/// Exit codes, following the scheme `plan outlines` already uses: 0 read, 1
/// the input is not a readable PLAN, 3 I/O. There is deliberately no 2: a
/// determination is a reading, not a gate, and every outcome — including
/// `non-conforming` — is a successful read. Refusal is the hook's job.
const EXIT_TOOL_ERROR: u8 = 1;
const EXIT_IO: u8 = 3;

/// The highest witness contract version this reader knows how to interpret. A
/// witness declaring a higher one is treated as unreadable rather than read
/// field-by-field on the assumption nothing moved.
const WITNESS_CONTRACT_MAX: u64 = 1;

/// Cap on a witness read. The file is a small fixed-shape JSON object; the cap
/// exists so a reader cannot be made to slurp whatever ends up at that path.
const MAX_WITNESS_BYTES: u64 = 64 * 1024;

/// The PLAN execution mode that carves the run out of the delegation question
/// entirely: a coordinated plan spans repositories, has no single orchestration
/// session to register, and delegates nothing per-issue here.
const COORDINATED_MODE: &str = "coordinated";

/// Stems that identify a conflict record's step as the **delegation** step.
/// `delegat` covers delegate/delegation/delegated; `spawn` covers the koto
/// state name (`spawn_and_await`) an author is most likely to paste in.
///
/// Deliberately short. A wider list would let a record about some other part of
/// the workflow cover a missing delegation, which is the laundering the join
/// exists to prevent.
const DELEGATION_STEP_STEMS: &[&str] = &["delegat", "spawn"];

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

    /// Override the liveness witness store
    /// (`$XDG_STATE_HOME/shirabe/adherence`).
    #[arg(long)]
    pub witness_dir: Option<PathBuf>,

    /// Override the conflict store (`$XDG_STATE_HOME/shirabe/conflicts`).
    #[arg(long)]
    pub conflict_dir: Option<PathBuf>,
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

    let roots = Roots::resolve(args);
    let scope = RepoScope::of(&cwd);
    let evidence = gather(&roots, &scope, &args.session, args.parent.as_deref(), &plan);

    println!("{}", render(&args.plan, &scope, &args.session, &evidence));
    ExitCode::SUCCESS
}

// --- roots -----------------------------------------------------------------

/// The four machine-local surfaces this reading consumes. Injected rather than
/// resolved inline so tests never touch the real home directory, and resolved
/// without creating anything — unlike both writers, which must create.
pub struct Roots {
    /// `~/.claude/projects`, whose children are encoded project directories.
    pub projects: PathBuf,
    /// `~/.koto/_terminal_index.jsonl`, machine-global.
    pub terminal_index: PathBuf,
    /// The liveness witness store [`crate::adherence_hook`] writes, one
    /// `<session>.json` per session.
    pub witness: PathBuf,
    /// The conflict store [`crate::conflict_record`] writes, one
    /// `<session>.jsonl` per session.
    pub conflicts: PathBuf,
}

impl Roots {
    fn resolve(args: &AdherenceCheckArgs) -> Roots {
        let home = std::env::var("HOME").unwrap_or_default();
        let home_dir = PathBuf::from(&home);
        Roots {
            projects: args
                .projects_dir
                .clone()
                .unwrap_or_else(|| home_dir.join(".claude").join("projects")),
            terminal_index: args
                .terminal_index
                .clone()
                .unwrap_or_else(|| home_dir.join(".koto").join("_terminal_index.jsonl")),
            witness: args.witness_dir.clone().unwrap_or_else(witness_dir),
            // Resolved through the conflict recorder's own function rather than
            // re-derived here, so the reader and the writer cannot drift.
            conflicts: args.conflict_dir.clone().unwrap_or_else(|| {
                crate::conflict_record::store_dir_from(
                    nonempty_env("SHIRABE_CONFLICT_DIR").as_deref(),
                    nonempty_env("XDG_STATE_HOME").as_deref(),
                    Some(home.as_str()),
                )
            }),
        }
    }
}

/// Where the hook's witness store lives, resolved the same way the hook
/// resolves it. This mirrors rather than calls, because the hook's resolver
/// creates the directory and this path must not.
fn witness_dir() -> PathBuf {
    if let Some(d) = nonempty_env("SHIRABE_ADHERENCE_STORE_DIR") {
        return PathBuf::from(d);
    }
    let base = nonempty_env("XDG_STATE_HOME")
        .unwrap_or_else(|| format!("{}/.local/state", std::env::var("HOME").unwrap_or_default()));
    PathBuf::from(base).join("shirabe").join("adherence")
}

fn nonempty_env(k: &str) -> Option<String> {
    std::env::var(k).ok().filter(|v| !v.is_empty())
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

// --- the liveness witness --------------------------------------------------

/// What the hook's per-session witness says.
///
/// The witness answers one question the other readings cannot: **was anything
/// watching**. Its absence is the difference between a run that dropped its
/// delegations and a run that predates the machinery, so it is never folded
/// into a negative finding.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WitnessReading {
    /// The hook evaluated at least one edit-shaped call in this session with
    /// enforcement on.
    Live {
        contract_version: u64,
        first_seen_unix: u64,
        cwd: Option<String>,
    },
    /// The hook evaluated, and the operator switch was off. The hook writes the
    /// witness anyway precisely so this stays distinct from [`Self::Absent`].
    Disabled { contract_version: u64 },
    /// No witness for this session.
    Absent,
    /// A witness exists and cannot be relied on: not a regular file,
    /// unparseable, or declaring a contract version this reader does not know.
    Unreadable(String),
}

/// Read the witness for one Claude Code session id.
pub fn read_witness(dir: &Path, claude_session: &str) -> WitnessReading {
    let Some(sid) = sanitize_component(claude_session) else {
        return WitnessReading::Absent;
    };
    let path = dir.join(format!("{sid}.json"));
    // `symlink_metadata` does not follow: a symlink at the witness path is a
    // redirected read, not a witness.
    let Ok(meta) = std::fs::symlink_metadata(&path) else {
        return WitnessReading::Absent;
    };
    if !meta.file_type().is_file() {
        return WitnessReading::Unreadable("witness path is not a regular file".to_string());
    }
    let Ok(file) = std::fs::File::open(&path) else {
        return WitnessReading::Unreadable("witness cannot be opened".to_string());
    };
    let mut raw = String::new();
    if file
        .take(MAX_WITNESS_BYTES)
        .read_to_string(&mut raw)
        .is_err()
    {
        return WitnessReading::Unreadable("witness cannot be read".to_string());
    }
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) else {
        return WitnessReading::Unreadable("witness is not JSON".to_string());
    };
    let Some(contract_version) = v.get("contract_version").and_then(|c| c.as_u64()) else {
        return WitnessReading::Unreadable("witness declares no contract version".to_string());
    };
    if contract_version > WITNESS_CONTRACT_MAX {
        return WitnessReading::Unreadable(format!(
            "witness contract version {contract_version} is newer than this reader ({WITNESS_CONTRACT_MAX})"
        ));
    }
    if v.get("disabled").and_then(|d| d.as_bool()).unwrap_or(false) {
        return WitnessReading::Disabled { contract_version };
    }
    WitnessReading::Live {
        contract_version,
        first_seen_unix: v
            .get("first_seen_unix")
            .and_then(|t| t.as_u64())
            .unwrap_or(0),
        cwd: v
            .get("cwd")
            .and_then(|c| c.as_str())
            .map(str::to_string)
            .filter(|c| !c.is_empty()),
    }
}

// --- the conflict join -----------------------------------------------------

/// One conflict record as the determination sees it. The verbatim instruction
/// is deliberately not carried: the join needs the step, and the instruction is
/// machine-local free text this reading has no use for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JoinedConflict {
    /// The session identity the record was filed under — the orchestrator's,
    /// the orchestration session's, or a child's.
    pub session: String,
    pub step: String,
    pub recorded_at: String,
    pub node_id: String,
}

/// The conflict store read across every identity the run could have recorded
/// under.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ConflictJoin {
    /// Every identity queried, in order. Rendered so a reader can confirm the
    /// children were walked rather than take it on trust.
    pub sessions_queried: Vec<String>,
    /// Identities that yielded at least one record.
    pub sessions_with_records: Vec<String>,
    pub records: Vec<JoinedConflict>,
}

/// Read the conflict store for the orchestrator's Claude Code session, for the
/// orchestration session, and for every boundary child.
///
/// Three identity spaces, because the store is keyed by whatever the recorder
/// was told its session was: a Claude Code session id for a session recording
/// under the harness identity, and a koto session name for a delegated child
/// recording under its own. Reading only the first misses every conflict a
/// child raised, which is the mistake the design calls out by name.
pub fn join_conflicts(roots: &Roots, claude_session: &str, d: &DelegationCount) -> ConflictJoin {
    let mut out = ConflictJoin::default();
    let mut seen = BTreeSet::new();

    let children = d
        .corroborated
        .iter()
        .chain(d.uncorroborated.iter())
        .map(|c| c.session_id.clone());
    // Uncorroborated children are included deliberately: a child that raised a
    // conflict is not thereby also guaranteed a workflow record, and dropping
    // it here would lose exactly the declaration being looked for.
    for sid in [claude_session.to_string(), d.parent.clone()]
        .into_iter()
        .chain(children)
    {
        if sid.is_empty() || !seen.insert(sid.clone()) {
            continue;
        }
        // The store is addressed by filename, so an identity that is not
        // filename-safe is not queried at all rather than sanitized into some
        // neighbouring session's records.
        if !is_store_session_id(&sid) {
            continue;
        }
        out.sessions_queried.push(sid.clone());
        let found = crate::conflict_record::read_records(&roots.conflicts, &sid);
        if found.is_empty() {
            continue;
        }
        out.sessions_with_records.push(sid.clone());
        for r in found {
            out.records.push(JoinedConflict {
                session: sid.clone(),
                step: r.step,
                recorded_at: r.recorded_at,
                node_id: r.node_id,
            });
        }
    }
    out
}

/// The conflict store's own filename charset, mirrored here so a name taken
/// from the machine-global terminal index cannot become a path. Matches the
/// recorder's `SID_RE`: an alphanumeric first character, then alphanumerics,
/// `.`, `_`, and `-`. The leading-character rule is what excludes `.`, `..`,
/// and any leading-dash name.
fn is_store_session_id(s: &str) -> bool {
    if s.is_empty() || s.len() > 128 {
        return false;
    }
    let mut chars = s.chars();
    let first = chars.next().unwrap_or('\0');
    first.is_ascii_alphanumeric()
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == '-')
}

/// What a conflict record's step names, once it has been matched against a
/// plan. `None` from [`step_identity`] means "covers no delegation shortfall".
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum StepIdentity {
    /// The delegation of a specific issue this PLAN declares.
    Issue(usize),
    /// The delegation step, named without an issue. Its normalized text is the
    /// identity, so two records saying the same thing cover one shortfall and
    /// not two.
    Step(String),
}

impl StepIdentity {
    fn render(&self) -> String {
        match self {
            Self::Issue(n) => format!("issue {n}"),
            Self::Step(s) => s.clone(),
        }
    }
}

/// Decide what shortfall, if any, a record's step can cover.
///
/// Returns `None` — covers nothing — when the step does not name the
/// delegation step at all, or when it names an issue number outside the range
/// the PLAN declares. Both are cases where a record exists and proves nothing
/// about a missing delegation.
pub fn step_identity(step: &str, expected_issues: usize) -> Option<StepIdentity> {
    let tokens = normalize_step(step);
    if !tokens
        .iter()
        .any(|t| DELEGATION_STEP_STEMS.iter().any(|s| t.starts_with(s)))
    {
        return None;
    }
    for pair in tokens.windows(2) {
        if pair[0] == "issue" {
            if let Ok(n) = pair[1].parse::<usize>() {
                return (n >= 1 && n <= expected_issues).then_some(StepIdentity::Issue(n));
            }
        }
    }
    Some(StepIdentity::Step(tokens.join(" ")))
}

/// Lowercase, and collapse every non-alphanumeric run to a token boundary, so
/// `spawn_and_await`, `Spawn And Await`, and `spawn-and-await` are one step and
/// not three.
fn normalize_step(step: &str) -> Vec<String> {
    step.to_ascii_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .map(str::to_string)
        .collect()
}

/// How much of a shortfall the joined records cover.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Coverage {
    /// Distinct step identities that can cover a missing delegation, rendered.
    pub covering: Vec<String>,
    /// Joined records that covered nothing: a step that is not the delegation
    /// step, an issue number the PLAN does not have, or a duplicate of an
    /// identity already counted.
    pub non_covering: usize,
}

impl Coverage {
    /// The number of missing delegations these records can account for — one
    /// per distinct identity, never more.
    pub fn count(&self) -> usize {
        self.covering.len()
    }
}

/// Reduce the joined records to a coverage count against a PLAN's issue range.
pub fn coverage(join: &ConflictJoin, expected_issues: usize) -> Coverage {
    let mut distinct = BTreeSet::new();
    let mut non_covering = 0usize;
    for r in &join.records {
        // `insert` returning false is a second record for an identity already
        // counted, which covers nothing further.
        let covered = step_identity(&r.step, expected_issues).is_some_and(|id| distinct.insert(id));
        if !covered {
            non_covering += 1;
        }
    }
    Coverage {
        covering: distinct.iter().map(StepIdentity::render).collect(),
        non_covering,
    }
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
    /// The `execution_mode` frontmatter field. `coordinated` is the carve-out:
    /// such a plan spans repositories and has no single orchestration session
    /// whose delegation could be counted.
    pub execution_mode: Option<String>,
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
        execution_mode: doc
            .fields
            .get("execution_mode")
            .map(|f| f.value.trim().to_ascii_lowercase())
            .filter(|m| !m.is_empty()),
    })
}

// --- the gathered evidence -------------------------------------------------

/// Every reading the outcome is derived from. Holds no verdict itself;
/// [`determine`] is the only place the four readings become one value, so the
/// resolution order is stated once and testable in isolation.
pub struct Evidence {
    pub registration: RegistrationReading,
    pub delegation: DelegationCount,
    pub plan: PlanExpectation,
    pub project_dirs: Vec<String>,
    pub witness: WitnessReading,
    pub conflicts: ConflictJoin,
}

impl Evidence {
    /// Missing delegations: the issues the PLAN declares, minus the children
    /// corroborated as belonging to this repository.
    pub fn shortfall(&self) -> usize {
        self.plan
            .expected_issues
            .saturating_sub(self.delegation.delegated())
    }
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

    // The child set is resolved before the store is read, because the store is
    // keyed by session and the children are sessions.
    let conflicts = join_conflicts(roots, claude_session, &delegation);

    Evidence {
        registration,
        delegation,
        plan: plan.clone(),
        project_dirs: records.project_dirs,
        witness: read_witness(&roots.witness, claude_session),
        conflicts,
    }
}

// --- the outcome -----------------------------------------------------------

/// The determination's six-value outcome domain.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// Registered, and every issue the PLAN declares was delegated. Reserved
    /// for exactly that; a conflict record cannot produce it.
    Conforming,
    /// The run departed from the workflow without declaring it.
    NonConforming,
    /// The PLAN's execution mode carves the run out of the question.
    Coordinated,
    /// The run fell short and declared each shortfall in the conflict store
    /// beforehand. A justified departure is still a departure.
    Departed,
    /// The operator switched enforcement off for this run.
    Disabled,
    /// The evidence does not support a verdict. Never a violation.
    Indeterminate,
}

impl Outcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Conforming => "conforming",
            Self::NonConforming => "non-conforming",
            Self::Coordinated => "coordinated",
            Self::Departed => "departed",
            Self::Disabled => "disabled",
            Self::Indeterminate => "indeterminate",
        }
    }
}

/// The verdict, with the arithmetic that produced it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Determination {
    pub outcome: Outcome,
    /// One line naming why this outcome and not its neighbour.
    pub reason: String,
    pub shortfall: usize,
    pub coverage: Coverage,
}

/// Resolve the evidence to one outcome. First match wins; the order is the one
/// documented at the top of this module and each arm states what it rules out.
pub fn determine(e: &Evidence) -> Determination {
    let shortfall = e.shortfall();
    // Coverage is computed for the envelope in every arm, so a reader can see
    // what was recorded even where it did not decide anything. It is only
    // *consulted* in the shortfall arm.
    let coverage = coverage(&e.conflicts, e.plan.expected_issues);
    let verdict = |outcome: Outcome, reason: String| Determination {
        outcome,
        reason,
        shortfall,
        coverage: coverage.clone(),
    };

    // 1. The carve-out. A coordinated plan spans repositories: there is no one
    //    orchestration session to register and no per-issue delegation here to
    //    count, so neither conforming nor non-conforming is available.
    if e.plan.execution_mode.as_deref() == Some(COORDINATED_MODE) {
        return verdict(
            Outcome::Coordinated,
            format!("the PLAN declares execution_mode: {COORDINATED_MODE}"),
        );
    }

    // 2. Enforcement off. Checked before the witness-absence arm, and the two
    //    are disjoint: a disabled run still leaves a witness, marked.
    if let WitnessReading::Disabled { .. } = e.witness {
        return verdict(
            Outcome::Disabled,
            "the witness records that enforcement was switched off for this session".to_string(),
        );
    }

    // 3. Unreadable evidence, in every form. Each of these is a reason the
    //    reading cannot conclude, and none of them is a reason to report a
    //    violation.
    match &e.witness {
        WitnessReading::Absent => {
            return verdict(
                Outcome::Indeterminate,
                "no liveness witness for this session: nothing was watching, which is not \
                 evidence of a departure"
                    .to_string(),
            )
        }
        WitnessReading::Unreadable(why) => {
            return verdict(
                Outcome::Indeterminate,
                format!("the liveness witness cannot be relied on: {why}"),
            )
        }
        WitnessReading::Live { .. } | WitnessReading::Disabled { .. } => {}
    }
    if e.plan.expected_issues == 0 {
        return verdict(
            Outcome::Indeterminate,
            "the PLAN declares no issue outlines, so there is no delegation to expect".to_string(),
        );
    }

    // 4. Registration. Past the witness gate this inference is sound: a witness
    //    exists only in a session running the shipped hook, and koto's workflow
    //    record defaulted on months before that hook shipped, so absence here is
    //    the session's own doing rather than the era it ran in.
    if e.registration == RegistrationReading::NoRecord {
        return verdict(
            Outcome::NonConforming,
            "the session was watched and registered no koto orchestration session".to_string(),
        );
    }

    // 3 (continued). Delegation evidence that cannot be counted.
    if !e.delegation.index_read {
        return verdict(
            Outcome::Indeterminate,
            "koto's terminal index could not be read, so delegation cannot be counted".to_string(),
        );
    }

    // 5. The only path to conforming, and it never consults the conflict store.
    if shortfall == 0 {
        return verdict(
            Outcome::Conforming,
            format!(
                "registered, and all {} issues were delegated",
                e.plan.expected_issues
            ),
        );
    }

    // A shortfall alongside boundary-children the record universe cannot place
    // in this repository means the count is provably incomplete: those children
    // ran. Reporting a violation off an undercount is the historical
    // false-positive this whole reading is built to avoid.
    if !e.delegation.uncorroborated.is_empty() {
        return verdict(
            Outcome::Indeterminate,
            format!(
                "{} delegated of {} expected, with {} boundary children carrying no workflow \
                 record: the count is incomplete rather than short",
                e.delegation.delegated(),
                e.plan.expected_issues,
                e.delegation.uncorroborated.len()
            ),
        );
    }

    // 6. A shortfall, split by whether it was declared beforehand.
    if coverage.count() >= shortfall {
        return verdict(
            Outcome::Departed,
            format!(
                "{shortfall} of {} issues undelegated, each covered by a conflict record naming \
                 the delegation step ({} covering, {} covering nothing)",
                e.plan.expected_issues,
                coverage.count(),
                coverage.non_covering
            ),
        );
    }
    verdict(
        Outcome::NonConforming,
        format!(
            "{shortfall} of {} issues undelegated, {} covered by a conflict record naming the \
             delegation step",
            e.plan.expected_issues,
            coverage.count()
        ),
    )
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

    let witness = match &e.witness {
        WitnessReading::Live {
            contract_version,
            first_seen_unix,
            cwd,
        } => serde_json::json!({
            "reading": "live",
            "contract_version": contract_version,
            "first_seen_unix": first_seen_unix,
            "cwd": cwd,
        }),
        WitnessReading::Disabled { contract_version } => serde_json::json!({
            "reading": "disabled",
            "contract_version": contract_version,
        }),
        WitnessReading::Absent => serde_json::json!({
            "reading": "absent",
            "note": "absence of a witness is not evidence of a departure",
        }),
        WitnessReading::Unreadable(why) => serde_json::json!({
            "reading": "unreadable",
            "why": why,
        }),
    };

    let d = determine(e);

    let value = serde_json::json!({
        "schema": SCHEMA,
        "plan": plan_path,
        "session": session,
        "repo_scope": scope.encoded_repo,
        "project_directories": e.project_dirs,
        "expected_issues": e.plan.expected_issues,
        "declared_issue_count": e.plan.declared_issue_count,
        "execution_mode": e.plan.execution_mode,
        "outcome": d.outcome.as_str(),
        "reason": d.reason,
        "shortfall": d.shortfall,
        "witness": witness,
        "conflicts": {
            // Rendered so a reader can confirm the children were walked rather
            // than take it on trust.
            "sessions_queried": e.conflicts.sessions_queried,
            "sessions_with_records": e.conflicts.sessions_with_records,
            "records": conflicts_json(&e.conflicts.records),
            "covering_steps": d.coverage.covering,
            "non_covering_records": d.coverage.non_covering,
        },
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

/// The joined records, minus the verbatim instruction: the determination has
/// no use for it and it is machine-local free text.
fn conflicts_json(records: &[JoinedConflict]) -> serde_json::Value {
    serde_json::Value::Array(
        records
            .iter()
            .map(|r| {
                serde_json::json!({
                    "session": r.session,
                    "step": r.step,
                    "recorded_at": r.recorded_at,
                    "node_id": r.node_id,
                })
            })
            .collect(),
    )
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
                witness: self.dir.join("witness"),
                conflicts: self.dir.join("conflicts"),
            }
        }

        /// Write the liveness witness the hook would have written for
        /// `session`, in the shape [`crate::adherence_hook`] writes it.
        fn witness(&self, session: &str, disabled: bool) {
            let dir = self.dir.join("witness");
            std::fs::create_dir_all(&dir).unwrap();
            let body = serde_json::json!({
                "contract_version": 1,
                "session_id": session,
                "agent_id": serde_json::Value::Null,
                "agent_type": serde_json::Value::Null,
                "first_seen_unix": 1_770_000_000u64,
                "cwd": REPO,
                "disabled": disabled,
            });
            std::fs::write(dir.join(format!("{session}.json")), body.to_string()).unwrap();
        }

        /// Write a raw witness body, for the versions and shapes the writer
        /// would never produce but a reader must survive.
        fn raw_witness(&self, session: &str, body: &str) {
            let dir = self.dir.join("witness");
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join(format!("{session}.json")), body).unwrap();
        }

        /// Append a conflict record under `session`, in the shape
        /// [`crate::conflict_record`] writes it.
        fn conflict(&self, session: &str, step: &str) {
            let dir = self.dir.join("conflicts");
            std::fs::create_dir_all(&dir).unwrap();
            let line = serde_json::json!({
                "schema": crate::conflict_record::CONFLICT_SCHEMA,
                "recorded_at": "2026-08-15T00:00:00Z",
                "session": session,
                "instruction": "implement this yourself, do not delegate",
                "step": step,
                "course": "implemented in the orchestrator role",
                "node_id": format!("cf-{}", step.len()),
                "instruction_digest": "0000",
            });
            let path = dir.join(format!("{session}.jsonl"));
            let mut body = std::fs::read_to_string(&path).unwrap_or_default();
            body.push_str(&line.to_string());
            body.push('\n');
            std::fs::write(&path, body).unwrap();
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
        plan_body_mode(issues, declared, "single-pr")
    }

    fn plan_body_mode(issues: usize, declared: usize, mode: &str) -> String {
        let mut s = format!(
            "---\nschema: plan/v1\nstatus: Active\nexecution_mode: {mode}\nissue_count: {declared}\n---\n\n# PLAN: Fixture\n\n## Issue Outlines\n\n"
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
            witness: fx.dir.join("no-such-witness"),
            conflicts: fx.dir.join("no-such-conflicts"),
        };
        let _ = gather(&absent, &scope, "sess-a", None, &plan);
        assert!(!fx.dir.join("no-such-projects").exists());
        assert!(!fx.dir.join("no-such-index").exists());
        // Both stores have writers that create; this reader has none.
        assert!(!fx.dir.join("no-such-witness").exists());
        assert!(!fx.dir.join("no-such-conflicts").exists());
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

    // --- the outcome domain ---

    /// The orchestration session a full run registers, and the shape its
    /// children are named in: `<parent>.o-<task-slug>`.
    const PARENT: &str = "execute-skill-adherence-enforcement";

    fn child(n: usize) -> String {
        format!("{PARENT}.o-issue-{n}")
    }

    /// Lay down a run: a registered parent, `delegated` corroborated children,
    /// the terminal index, and a PLAN of `expected` issues. The witness is left
    /// to the caller, since which witness exists is the point of several tests.
    fn run(fx: &Fx, expected: usize, delegated: usize, mode: &str) -> PlanExpectation {
        fx.record(REPO_ENC, "sess-a", PARENT);
        let children: Vec<String> = (1..=delegated).map(child).collect();
        for c in &children {
            fx.record(REPO_ENC, "sess-child", c);
        }
        fx.index(&children.iter().map(String::as_str).collect::<Vec<_>>());
        read_plan(&fx.plan(&plan_body_mode(expected, expected, mode)))
            .ok()
            .expect("a plan/v1 document")
    }

    fn outcome_of(fx: &Fx, plan: &PlanExpectation) -> Determination {
        let scope = RepoScope::of(Path::new(REPO));
        determine(&gather(&fx.roots(), &scope, "sess-a", None, plan))
    }

    #[test]
    fn the_outcome_domain_is_six_values() {
        let all = [
            Outcome::Conforming,
            Outcome::NonConforming,
            Outcome::Coordinated,
            Outcome::Departed,
            Outcome::Disabled,
            Outcome::Indeterminate,
        ];
        let names: BTreeSet<&str> = all.iter().map(|o| o.as_str()).collect();
        assert_eq!(names.len(), 6, "every outcome renders distinctly");
        assert!(names.contains("non-conforming"));
        assert!(names.contains("indeterminate"));
    }

    #[test]
    fn a_registered_and_fully_delegated_run_is_conforming() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 9, "single-pr");
        fx.witness("sess-a", false);
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Conforming, "{}", d.reason);
        assert_eq!(d.shortfall, 0);
    }

    #[test]
    fn an_orchestrator_that_implemented_inline_is_non_conforming() {
        // The shape the acceptance criterion names: the skill was invoked and
        // its scripts ran, but no orchestration session was registered and
        // nothing was delegated. The witness is what makes the absence
        // readable as a fact rather than as an era.
        let fx = Fx::new();
        let plan = read_plan(&fx.plan(&plan_body(9, 9))).ok().unwrap();
        fx.witness("sess-a", false);
        fx.index(REAL_INDEX_IDS);
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::NonConforming, "{}", d.reason);
        assert!(d
            .reason
            .contains("registered no koto orchestration session"));
    }

    #[test]
    fn a_registered_run_that_delegated_nothing_is_also_non_conforming() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 0, "single-pr");
        fx.witness("sess-a", false);
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::NonConforming, "{}", d.reason);
        assert_eq!(d.shortfall, 9);
    }

    #[test]
    fn an_uncovered_shortfall_of_one_is_non_conforming() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 8, "single-pr");
        fx.witness("sess-a", false);
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::NonConforming, "{}", d.reason);
        assert_eq!(d.shortfall, 1);
        assert_eq!(d.coverage.count(), 0);
    }

    #[test]
    fn a_covered_shortfall_is_departed() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 8, "single-pr");
        fx.witness("sess-a", false);
        fx.conflict("sess-a", "delegate issue 9");
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Departed, "{}", d.reason);
        assert_ne!(
            d.outcome,
            Outcome::Conforming,
            "a declared departure is still a departure"
        );
        assert_eq!(d.shortfall, 1);
        assert_eq!(d.coverage.covering, vec!["issue 9".to_string()]);
    }

    #[test]
    fn recording_a_conflict_does_not_buy_conforming() {
        // The adversarial case the security review named. A session that wants
        // to implement inline records its conflicts, does all nine issues
        // itself, and reads back the verdict. Declaring the departure must
        // never produce the value reserved for a delegated run — otherwise the
        // verified reading is purchasable for the price of one free-text
        // record.
        let fx = Fx::new();
        let plan = run(&fx, 9, 0, "single-pr");
        fx.witness("sess-a", false);
        for n in 1..=9 {
            fx.conflict("sess-a", &format!("delegate issue {n}"));
        }
        let d = outcome_of(&fx, &plan);
        assert_ne!(
            d.outcome,
            Outcome::Conforming,
            "nine conflict records must not buy conforming: {}",
            d.reason
        );
        assert_eq!(d.outcome, Outcome::Departed, "{}", d.reason);
        assert_eq!(d.shortfall, 9);
        assert_eq!(d.coverage.count(), 9);
    }

    #[test]
    fn one_conflict_record_cannot_launder_two_silent_drops() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 7, "single-pr");
        fx.witness("sess-a", false);
        // One record, two missing delegations. Recording it twice changes
        // nothing: coverage is counted by distinct step identity.
        fx.conflict("sess-a", "delegate issue 8");
        fx.conflict("sess-a", "delegate issue 8");
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::NonConforming, "{}", d.reason);
        assert_eq!(d.coverage.count(), 1);
        assert_eq!(d.coverage.non_covering, 1, "the duplicate covers nothing");

        // The second drop, declared, closes it.
        fx.conflict("sess-a", "delegate issue 9");
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Departed, "{}", d.reason);
        assert_eq!(d.coverage.count(), 2);
    }

    #[test]
    fn a_conflict_naming_a_different_step_does_not_cover_the_shortfall() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 8, "single-pr");
        fx.witness("sess-a", false);
        // A real conflict, about a step that is not the delegation step.
        fx.conflict("sess-a", "assemble the home pull request body");
        // And one naming an issue this PLAN does not have.
        fx.conflict("sess-a", "delegate issue 42");
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::NonConforming, "{}", d.reason);
        assert_eq!(d.coverage.count(), 0);
        assert_eq!(d.coverage.non_covering, 2);
    }

    #[test]
    fn the_conflict_join_reads_the_store_for_each_child() {
        // A child records under its own session identity, so a join that looks
        // up only the orchestrator's session misses the declaration entirely
        // and reports a silent drop where a declared one happened.
        let fx = Fx::new();
        let plan = run(&fx, 9, 8, "single-pr");
        fx.witness("sess-a", false);
        fx.conflict(&child(3), "delegate issue 9");

        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        assert!(
            e.conflicts.sessions_queried.contains(&child(3)),
            "queried: {:?}",
            e.conflicts.sessions_queried
        );
        assert!(e.conflicts.sessions_queried.contains(&"sess-a".to_string()));
        assert!(e.conflicts.sessions_queried.contains(&PARENT.to_string()));
        assert_eq!(e.conflicts.sessions_with_records, vec![child(3)]);
        assert_eq!(determine(&e).outcome, Outcome::Departed);
    }

    #[test]
    fn a_child_with_no_workflow_record_is_still_asked_for_conflicts() {
        // The uncorroborated list is not noise here: a child that raised a
        // conflict is not thereby guaranteed a workflow record.
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", PARENT);
        fx.index(&[&child(1)]);
        let plan = read_plan(&fx.plan(&plan_body(9, 9))).ok().unwrap();
        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        assert_eq!(e.delegation.delegated(), 0);
        assert_eq!(e.delegation.uncorroborated.len(), 1);
        assert!(e.conflicts.sessions_queried.contains(&child(1)));
    }

    #[test]
    fn a_session_identity_that_is_not_filename_safe_is_never_queried() {
        assert!(!is_store_session_id("../../etc/passwd"));
        assert!(!is_store_session_id("-leading-dash"));
        assert!(!is_store_session_id(".hidden"));
        assert!(!is_store_session_id(""));
        assert!(is_store_session_id(&child(1)));

        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", PARENT);
        let hostile = format!("{PARENT}./../../etc/passwd");
        fx.index(&[&hostile]);
        let plan = read_plan(&fx.plan(&plan_body(9, 9))).ok().unwrap();
        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        assert!(
            !e.conflicts.sessions_queried.contains(&hostile),
            "queried: {:?}",
            e.conflicts.sessions_queried
        );
    }

    #[test]
    fn a_coordinated_run_is_neither_conforming_nor_non_conforming() {
        let fx = Fx::new();
        // Nothing registered, nothing delegated, no witness: a coordinated plan
        // has no single orchestration session, so none of that is a finding.
        let plan = read_plan(&fx.plan(&plan_body_mode(9, 9, "coordinated")))
            .ok()
            .unwrap();
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Coordinated, "{}", d.reason);
        assert_ne!(d.outcome, Outcome::Conforming);
        assert_ne!(d.outcome, Outcome::NonConforming);
    }

    #[test]
    fn a_missing_witness_is_indeterminate_and_never_non_conforming() {
        // The historical run: no witness, nothing delegated in this
        // repository's record universe. Reporting non-conforming here is the
        // false positive the whole reading is built to avoid.
        let fx = Fx::new();
        let plan = run(&fx, 9, 0, "single-pr");
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Indeterminate, "{}", d.reason);
        assert_ne!(d.outcome, Outcome::NonConforming);
    }

    #[test]
    fn a_disabled_run_is_disabled_and_not_indeterminate() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 0, "single-pr");
        fx.witness("sess-a", true);
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Disabled, "{}", d.reason);
        assert_ne!(
            d.outcome,
            Outcome::Indeterminate,
            "switched off must not read as nothing was watching"
        );

        // And the same run with no witness at all reads differently, which is
        // the whole reason the hook writes one for a disabled session.
        let fx2 = Fx::new();
        let plan2 = run(&fx2, 9, 0, "single-pr");
        assert_eq!(outcome_of(&fx2, &plan2).outcome, Outcome::Indeterminate);
    }

    #[test]
    fn an_unreliable_witness_is_indeterminate() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 0, "single-pr");
        // A witness from a future contract: its fields may have moved, so it is
        // not read field-by-field on the assumption they did not.
        fx.raw_witness("sess-a", "{\"contract_version\":99,\"disabled\":true}");
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Indeterminate, "{}", d.reason);
        assert!(d.reason.contains("newer than this reader"), "{}", d.reason);

        fx.raw_witness("sess-a", "not json");
        assert_eq!(outcome_of(&fx, &plan).outcome, Outcome::Indeterminate);
        fx.raw_witness("sess-a", "{\"session_id\":\"sess-a\"}");
        assert_eq!(outcome_of(&fx, &plan).outcome, Outcome::Indeterminate);
    }

    #[test]
    fn an_unreadable_terminal_index_is_indeterminate() {
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", PARENT);
        fx.witness("sess-a", false);
        // Registered, and no index to count against.
        let plan = read_plan(&fx.plan(&plan_body(9, 9))).ok().unwrap();
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Indeterminate, "{}", d.reason);
        assert!(d.reason.contains("terminal index"), "{}", d.reason);
    }

    #[test]
    fn an_incomplete_count_is_indeterminate_rather_than_short() {
        // Children ran and this repository has no workflow record for them.
        // The count undercounts by construction, so the shortfall it produces
        // is not evidence of anything.
        let fx = Fx::new();
        fx.record(REPO_ENC, "sess-a", PARENT);
        fx.witness("sess-a", false);
        let children: Vec<String> = (1..=9).map(child).collect();
        fx.index(&children.iter().map(String::as_str).collect::<Vec<_>>());
        let plan = read_plan(&fx.plan(&plan_body(9, 9))).ok().unwrap();
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Indeterminate, "{}", d.reason);
        assert!(d.reason.contains("incomplete"), "{}", d.reason);
    }

    #[test]
    fn a_plan_with_no_outlines_supports_no_verdict() {
        let fx = Fx::new();
        let plan = run(&fx, 0, 0, "single-pr");
        fx.witness("sess-a", false);
        let d = outcome_of(&fx, &plan);
        assert_eq!(d.outcome, Outcome::Indeterminate, "{}", d.reason);
    }

    // --- matching a record to a shortfall ---

    #[test]
    fn only_the_delegation_step_covers_a_missing_delegation() {
        for step in [
            "delegate issue 4",
            "delegation of the issue",
            "delegated the work",
            "spawn_and_await",
            "Spawn And Await",
        ] {
            assert!(
                step_identity(step, 9).is_some(),
                "{step} names the delegation step"
            );
        }
        for step in [
            "assemble the pull request body",
            "cleanup",
            "monitor CI",
            "",
            "phase 4",
        ] {
            assert!(
                step_identity(step, 9).is_none(),
                "{step} does not name the delegation step"
            );
        }
    }

    #[test]
    fn a_step_naming_an_issue_outside_the_plan_covers_nothing() {
        assert_eq!(
            step_identity("delegate issue 9", 9),
            Some(StepIdentity::Issue(9))
        );
        assert_eq!(
            step_identity("delegate issue-9", 9),
            Some(StepIdentity::Issue(9))
        );
        assert_eq!(step_identity("delegate issue 10", 9), None);
        assert_eq!(step_identity("delegate issue 0", 9), None);
    }

    #[test]
    fn a_step_is_one_identity_however_it_is_punctuated() {
        assert_eq!(
            step_identity("spawn_and_await", 9),
            step_identity("Spawn-And-Await", 9)
        );
        assert_eq!(
            step_identity("delegate issue 3", 9),
            step_identity("DELEGATE ISSUE 3", 9)
        );
    }

    // --- the envelope ---

    #[test]
    fn the_envelope_carries_the_outcome_and_what_produced_it() {
        let fx = Fx::new();
        let plan = run(&fx, 9, 8, "single-pr");
        fx.witness("sess-a", false);
        fx.conflict(&child(2), "delegate issue 9");

        let scope = RepoScope::of(Path::new(REPO));
        let e = gather(&fx.roots(), &scope, "sess-a", None, &plan);
        let v: serde_json::Value =
            serde_json::from_str(&render("PLAN-fixture.md", &scope, "sess-a", &e)).unwrap();

        assert_eq!(v["schema"], SCHEMA);
        assert_eq!(v["outcome"], "departed");
        assert_eq!(v["shortfall"], 1);
        assert_eq!(v["execution_mode"], "single-pr");
        assert_eq!(v["witness"]["reading"], "live");
        assert_eq!(v["conflicts"]["covering_steps"][0], "issue 9");
        assert_eq!(v["conflicts"]["records"][0]["session"], child(2));
        assert_eq!(v["conflicts"]["records"][0]["step"], "delegate issue 9");
        // The verbatim instruction is machine-local and has no business here.
        assert!(v["conflicts"]["records"][0].get("instruction").is_none());
        assert!(v["conflicts"]["sessions_queried"]
            .as_array()
            .unwrap()
            .iter()
            .any(|s| s == &serde_json::json!(child(2))));
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
