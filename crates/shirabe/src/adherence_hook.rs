//! The `shirabe adherence-hook` subcommand: a Claude Code **PreToolUse**
//! adapter registered on the edit-shaped tools (`Edit`, `Write`, `MultiEdit`,
//! `NotebookEdit`) by shirabe's own plugin `hooks/hooks.json`.
//!
//! The hook registers, runs on every edit-shaped call, writes the per-session
//! witness the determination later reads as its liveness input, decides
//! **arming** — whether this session is performing plan-scale execution in the
//! orchestrator role — and, when armed, compares the call's write target
//! against the closed set `/execute` declares. A target outside that set is
//! **denied** with a reason naming it and the route back in; everything else
//! allows.
//!
//! Behavior:
//!
//! - Reads the hook JSON on stdin, capped, and **always exits 0**. A non-zero
//!   exit from a `PreToolUse` handler blocks the tool call, so aborting is
//!   never an option here: the shipped precedent in this workspace is an
//!   outdated binary that did not recognize a new subcommand and bricked every
//!   write in every session on the machine.
//! - Emits nothing on stdout on an allow. An allow is the absence of a
//!   decision; a deny is a `permissionDecision` object assembled with
//!   `serde_json`, never string-interpolated, because the reason carries a path
//!   the session chose.
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
//! write and simply leave the witness unwritten. Every arming path has the same
//! obligation: a missing transcript, an unreadable one, an over-cap read, an
//! unresolvable reference, a parse failure, and an over-cap match count all
//! yield [`NotArmed`] with the reason recorded, never a refusal.
//!
//! # The scan boundary is a security control, not a detail
//!
//! Arming reads **only the instructions the session was given**, which is
//! strictly narrower than "the records the session received". Measured against
//! a real 13MB transcript, the received records break down as roughly 862
//! tool-result payloads, 256 prompts, 8 text records, and 307 attachments:
//! three quarters are output the agent *pulled in*, not instructions anyone
//! sent it.
//!
//! Scanning all of them would break the feature in two ways, one needing no
//! attacker. Any agent that reads, greps, or reviews a plan file would pull
//! that filename into a tool result and arm the refusal against itself. And an
//! outside contributor could open a pull request adding a valid plan plus any
//! readable file naming it, and the first agent to read the second file would
//! be write-denied for the rest of its session under `bypassPermissions`, with
//! no human present to appeal to. One pull request, no merge required.
//!
//! [`is_prompt_shaped`] is that boundary. It is tested directly, and
//! `a_plan_filename_in_tool_output_does_not_arm` is the regression test.
//!
//! # The scan is a tail scan, and that shape is forced
//!
//! The transcript grows all run and the predicate re-runs on every edit-shaped
//! call, so a full rescan is linear in transcript size: roughly 2ms against
//! 4.1MB, extrapolating to about 50ms at 100MB. The fix is to persist the fold
//! and re-read only what was appended, which [`CachedFold`] does. Both of the
//! simpler things one would reach for first are wrong, and the reasons are
//! recorded at [`CachedFold`] and [`fold_transcript`] rather than here: in
//! short, a cached *verdict* is wrong because the write-target comparison is a
//! property of the target and not of the session, and a *frozen* arming
//! decision is wrong because the predicate is not monotone — an author who
//! re-scopes mid-run must be able to disarm the session.
//!
//! Env seam: `SHIRABE_ADHERENCE_DISABLE=1` is the operator switch. It does
//! **not** suppress the witness — a disabled run still writes one, marked
//! disabled, so the determination can report "somebody turned this off"
//! instead of folding it into the same `indeterminate` it reports for a run
//! that predates the feature. `SHIRABE_ADHERENCE_STORE_DIR` relocates the
//! store (tests).

use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};
use std::process::ExitCode;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

use regex::Regex;

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

// --- arming caps -----------------------------------------------------------
//
// Every cap below is a fail-open threshold: exceeding it does not block, retry,
// or truncate-and-guess. It yields a [`NotArmed`] reason and the write goes
// through. Each is stated here rather than inline so the whole bound surface of
// the predicate is readable in one place.

/// Cap on the transcript file. Real transcripts in this workspace top out
/// around 13MB; 64 MiB is five times the observed ceiling, and a session that
/// somehow exceeds it allows rather than paying an unbounded disk-bound read on
/// every edit-shaped call.
const MAX_TRANSCRIPT_BYTES: u64 = 64 * 1024 * 1024;

/// Cap on one JSONL record. A prompt-shaped record is small; a record over this
/// is a tool-result payload we would discard anyway, so it is skipped without
/// being parsed. This also bounds peak memory: the scan holds one record at a
/// time, never the whole transcript.
const MAX_RECORD_BYTES: usize = 1024 * 1024;

/// Cap on the plan file. The plan is an ordinary file in the working tree, so
/// whoever can add a plan can add a very large one and make every edit-shaped
/// call an unbounded read.
const MAX_PLAN_BYTES: u64 = 1024 * 1024;

/// Cap on frontmatter lines scanned in a plan, so a file whose first megabyte
/// is one long unterminated frontmatter block costs a bounded walk.
const MAX_PLAN_FRONT_MATTER_LINES: usize = 200;

/// Cap on plan-shaped references collected across the scanned records. Each
/// reference costs a resolution and an open, so an instruction carrying
/// hundreds of them would otherwise be paid for on every call.
const MAX_PLAN_REFERENCES: usize = 32;

/// Cap on one reference. Longer than this is not a path anyone typed.
const MAX_REFERENCE_LEN: usize = 512;

/// The cached fold's contract version. A cache file that does not declare
/// exactly this is ignored and the fold re-derives from the start, so the shape
/// can change without a migration and an older binary sharing the store with a
/// newer one costs a rescan rather than a misread.
const SCAN_CACHE_CONTRACT_VERSION: u32 = 1;

/// Cap on the cache file. The state it holds is bounded by
/// [`MAX_PLAN_REFERENCES`] references of [`MAX_REFERENCE_LEN`] bytes, so this is
/// an order of magnitude above anything this code writes; a file over it is
/// ignored rather than read.
const MAX_SCAN_CACHE_BYTES: u64 = 256 * 1024;

/// The schema a PLAN document declares in its frontmatter. Anything else,
/// including a missing `schema:`, is not a plan and does not arm.
const PLAN_SCHEMA: &str = "plan/v1";

/// The execution mode that stands the refusal down: a coordinated plan spans
/// repositories and has no single shared branch, so the closed write-target set
/// does not describe it.
const COORDINATED_MODE: &str = "coordinated";

/// Markers that identify a delegated single-issue child rather than the
/// orchestrator. A child receives one in the dispatch prompt `/execute` writes
/// for it; matching is case-insensitive substring containment over the
/// prompt-shaped records only, same boundary as the plan reference itself.
///
/// The direction of a miss is safe either way: a marker seen where there is
/// none stands the refusal down (allow), and a marker missed leaves the child
/// armed, where the write-target comparison still permits writes to its own
/// issue's files.
const SINGLE_ISSUE_MARKERS: &[&str] = &[
    "single-issue child",
    "single-issue delegation",
    "/work-on single-issue",
];

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
    let eval = evaluate(&input, resolve_store().as_deref());

    // The refusal seam. When `eval.arming` is `Armed`, the next increment
    // compares the tool's write target against the declaration shipped at
    // `--contract` and denies outside it. Until then every call allows, armed
    // or not, which is what the observe-only stage needs: the false-positive
    // rate of this predicate is the input that decides whether denial is safe
    // to turn on.
    if let Some(witness) = &eval.witness {
        trace(&format!("witness created at {}", witness.display()));
    }
    match eval.arming.armed_plan() {
        Some(plan) => trace(&format!("armed plan={}", plan.display())),
        None => trace(&format!("not armed reason={}", eval.arming.reason())),
    }

    ExitCode::SUCCESS
}

/// Record an arming decision on stderr when `SHIRABE_ADHERENCE_TRACE` is set.
///
/// Stderr, not stdout: stdout carries the hook's decision and must stay empty
/// on an allow. Off by default because it runs on every edit-shaped call; on,
/// it is how the over-cap and stand-down reasons are read back during the
/// observe-only stage.
fn trace(line: &str) {
    if is_truthy(std::env::var("SHIRABE_ADHERENCE_TRACE").ok().as_deref()) {
        let _ = writeln!(std::io::stderr(), "[shirabe adherence] {line}");
    }
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

/// What one evaluation of one edit-shaped call concluded.
struct Evaluation {
    /// The witness path when this call created it, `None` otherwise —
    /// including when it already existed, which is the common case after the
    /// first edit-shaped call of a session. Nothing about it reaches the
    /// harness; it exists for the tests and for the determination's liveness
    /// input.
    witness: Option<PathBuf>,
    /// Whether this session is performing plan-scale execution in the
    /// orchestrator role, and when it is not, why not.
    arming: Arming,
}

/// Core logic, split out so the store directory is a parameter rather than a
/// process-global env read: given the raw PreToolUse hook JSON, record the
/// per-session witness when this session is one the determination could ever
/// be asked about, and decide arming.
///
/// Every failure path yields [`NotArmed`] and allows.
fn evaluate(input: &str, store: Option<&Path>) -> Evaluation {
    let unusable = |r: NotArmed| Evaluation {
        witness: None,
        arming: Arming::NotArmed(r),
    };

    let Ok(v) = serde_json::from_str::<serde_json::Value>(input) else {
        return unusable(NotArmed::UnusableInput);
    };
    let Some(session_id) = v
        .get("session_id")
        .and_then(|s| s.as_str())
        .and_then(sanitize_session_id)
    else {
        return unusable(NotArmed::UnusableInput);
    };
    let Some(cwd) = resolve_cwd(&v) else {
        return unusable(NotArmed::UnusableInput);
    };

    // The cheap check. One stat, and the overwhelming majority of sessions on
    // a machine stop here having written nothing.
    if !hosts_plans(&cwd) {
        return unusable(NotArmed::NoPlansDirectory);
    }

    // The witness is written here deliberately: after the existence check, so
    // it is not created in every repository on the machine, and before the
    // arming ladder, so it records evaluations that did *not* arm. The common
    // case by volume is a hook that evaluates and allows, and a witness that
    // only armed sessions left behind would be absent exactly where the
    // determination needs it.
    let body = witness_body(&v, &session_id, &cwd, disabled());
    let witness = store.and_then(|s| write_witness_once(s, &session_id, &body));

    // The fold's cache lives beside the witness. Without a store it is `None`
    // and the scan re-derives from the start every call: slower, never wrong.
    let cache = store.map(|s| scan_cache_path(s, &session_id, &v));

    Evaluation {
        witness,
        arming: decide_arming(&v, &cwd, cache.as_deref()),
    }
}

/// Backwards-compatible view of [`evaluate`] for the witness-only callers:
/// returns the witness path when this call created it.
#[cfg(test)]
fn observe(input: &str, store: Option<&Path>) -> Option<PathBuf> {
    evaluate(input, store).witness
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

// --- arming ----------------------------------------------------------------

/// The arming decision for one edit-shaped call.
enum Arming {
    /// Positively established: the instructions this session was given name a
    /// plan that resolves inside the working tree, carries the plan schema, and
    /// is not coordinated, and carry no single-issue delegation marker. The
    /// path is the resolved plan.
    Armed(PathBuf),
    /// Not established, with the reason. Every variant allows.
    NotArmed(NotArmed),
}

/// Why a call did not arm. Recorded rather than discarded: during the
/// observe-only stage these reasons are the measurement, and a refusal that
/// silently stood down for an over-cap read would be indistinguishable from one
/// that correctly saw no plan.
#[derive(Debug)]
enum NotArmed {
    /// The hook JSON, session id, or working directory was unusable.
    UnusableInput,
    /// The repository cannot host plan-scale execution.
    NoPlansDirectory,
    /// The hook input named no transcript, or named a relative one.
    NoTranscript,
    /// The transcript could not be opened, stat-ed, or read.
    TranscriptUnreadable,
    /// The transcript exceeded [`MAX_TRANSCRIPT_BYTES`].
    TranscriptOverCap,
    /// The instructions carried a single-issue delegation marker.
    SingleIssueDelegation,
    /// No prompt-shaped record named a plan. The overwhelmingly common case,
    /// and the one that holds for a session that merely read a plan file.
    NoPlanReference,
    /// More than [`MAX_PLAN_REFERENCES`] references were named.
    TooManyReferences,
    /// Every reference failed to resolve inside the working tree, or named a
    /// missing file, a symlink, or something that is not a regular file.
    UnresolvableReference,
    /// A referenced plan could not be read, or exceeded [`MAX_PLAN_BYTES`].
    PlanUnreadable,
    /// A referenced plan resolved and was read, but its frontmatter did not
    /// parse or did not declare the plan schema.
    NotAPlan,
    /// The resolved plan declared the coordinated execution mode.
    Coordinated,
}

impl Arming {
    /// The resolved plan when armed. The refusal increment's entry point.
    fn armed_plan(&self) -> Option<&Path> {
        match self {
            Arming::Armed(p) => Some(p),
            Arming::NotArmed(_) => None,
        }
    }

    /// A stable token for the decision, for the trace and the tests.
    fn reason(&self) -> &'static str {
        match self {
            Arming::Armed(_) => "armed",
            Arming::NotArmed(r) => match r {
                NotArmed::UnusableInput => "unusable-input",
                NotArmed::NoPlansDirectory => "no-plans-directory",
                NotArmed::NoTranscript => "no-transcript",
                NotArmed::TranscriptUnreadable => "transcript-unreadable",
                NotArmed::TranscriptOverCap => "transcript-over-cap",
                NotArmed::SingleIssueDelegation => "single-issue-delegation",
                NotArmed::NoPlanReference => "no-plan-reference",
                NotArmed::TooManyReferences => "too-many-references",
                NotArmed::UnresolvableReference => "unresolvable-reference",
                NotArmed::PlanUnreadable => "plan-unreadable",
                NotArmed::NotAPlan => "not-a-plan",
                NotArmed::Coordinated => "coordinated",
            },
        }
    }
}

/// The arming ladder. Reads the transcript holding *this* agent's received
/// records, scans only the prompt-shaped ones, and requires a plan reference
/// that resolves inside `cwd` to a regular file carrying the plan schema.
/// `cache` is the session's persisted fold (see [`CachedFold`]); `None` scans
/// the whole transcript, which is what every failure to resolve the store falls
/// back to.
fn decide_arming(v: &serde_json::Value, cwd: &Path, cache: Option<&Path>) -> Arming {
    let Some(transcript) = transcript_for(v) else {
        return Arming::NotArmed(NotArmed::NoTranscript);
    };
    let scan = match fold_transcript(&transcript, cache) {
        Ok(f) => {
            // The cost measure, readable in the field during the observe-only
            // stage: after the first call of a session these bytes track what
            // was appended, not the size of the transcript.
            trace(&format!(
                "fold bytes={} resumed_from={} offset={}",
                f.bytes_scanned, f.resumed_from, f.offset
            ));
            f.scan
        }
        Err(e) => return Arming::NotArmed(e),
    };
    // Checked before the references: an instruction that both names a plan and
    // scopes the session to one of its issues is a child, not the orchestrator.
    if scan.single_issue_marker {
        return Arming::NotArmed(NotArmed::SingleIssueDelegation);
    }
    if scan.references.is_empty() {
        return Arming::NotArmed(NotArmed::NoPlanReference);
    }
    // The working tree the references are confined to. Resolved once, so the
    // prefix test below compares two canonical paths.
    let Ok(root) = cwd.canonicalize() else {
        return Arming::NotArmed(NotArmed::UnresolvableReference);
    };

    let mut last = NotArmed::UnresolvableReference;
    for reference in &scan.references {
        match read_plan(&root, reference) {
            Ok(plan) => {
                // The first reference that resolves to a real plan decides. A
                // later reference cannot override it, so an instruction cannot
                // be padded with junk to change the verdict.
                if plan.execution_mode.as_deref() == Some(COORDINATED_MODE) {
                    return Arming::NotArmed(NotArmed::Coordinated);
                }
                return Arming::Armed(plan.path);
            }
            Err(e) => last = e,
        }
    }
    Arming::NotArmed(last)
}

/// The transcript holding this agent's own received records.
///
/// `transcript_path` is the harness's answer for the invoking agent. The
/// subagent identity field is used only as a **routing key**: when the harness
/// hands the parent's transcript to a subagent's hook call, the subagent's own
/// records live in a sibling file named for its agent id, and that file is
/// preferred when it exists. Identity is never used as an orchestrator test —
/// its absence is an open-world assumption, and the design declined it on
/// exactly that ground.
fn transcript_for(v: &serde_json::Value) -> Option<PathBuf> {
    let given = v.get("transcript_path").and_then(|t| t.as_str())?;
    let given = Path::new(given);
    if !given.is_absolute() {
        return None;
    }
    // A relative or traversal-shaped agent id would escape the sibling
    // directory; the same filename-component discipline as the session id.
    let agent_id = v
        .get("agent_id")
        .and_then(|a| a.as_str())
        .and_then(sanitize_session_id);
    if let Some(agent_id) = agent_id {
        let sibling = given
            .parent()?
            .join(given.file_stem()?)
            .join("subagents")
            .join(format!("agent-{agent_id}.jsonl"));
        if sibling.is_file() {
            return Some(sibling);
        }
    }
    Some(given.to_path_buf())
}

/// What one transcript scan found in the records the session was *given*.
///
/// This is a **fold state**, not a verdict: both fields accumulate in the
/// append direction and neither is ever cleared, which is what lets a scan
/// resume from a persisted copy of it rather than starting over. The verdict is
/// derived from it fresh on every call, in [`decide_arming`].
#[derive(Clone, Default, PartialEq, Eq, Debug)]
struct Scan {
    /// Plan-shaped references, in first-seen order, deduplicated.
    references: Vec<String>,
    /// Whether any instruction marked this session a delegated single-issue
    /// child.
    single_issue_marker: bool,
}

/// Whether a transcript record is an **instruction the agent was given**,
/// rather than output the agent pulled in.
///
/// This is the security boundary described in the module header. A record is
/// admitted only when all of these hold:
///
/// - its top-level `type` is `user`. Excludes `attachment` records outright,
///   along with `assistant`, `system`, and the harness's own bookkeeping rows.
/// - it is not `isMeta`. Meta records are harness injections — system
///   reminders, skill bodies loaded by the Skill tool — not messages anyone
///   sent.
/// - it carries no tool-result provenance: `toolUseResult`,
///   `sourceToolUseID`, or `sourceToolAssistantUUID`. Each marks a record the
///   agent's own tool call produced.
/// - its message content is text, either a bare string or an array whose parts
///   are **all** `text`. One `tool_result` part disqualifies the record.
///
/// The last two clauses overlap deliberately. A tool result carries both a
/// provenance field and a `tool_result` content part, and either alone would
/// exclude it; keeping both means a harness that drops one of them does not
/// silently open the boundary.
fn is_prompt_shaped(record: &serde_json::Value) -> Option<String> {
    if record.get("type").and_then(|t| t.as_str()) != Some("user") {
        return None;
    }
    if record.get("isMeta").and_then(|m| m.as_bool()) == Some(true) {
        return None;
    }
    for provenance in [
        "toolUseResult",
        "sourceToolUseID",
        "sourceToolAssistantUUID",
    ] {
        if record.get(provenance).is_some_and(|p| !p.is_null()) {
            return None;
        }
    }
    match record.get("message").and_then(|m| m.get("content")) {
        Some(serde_json::Value::String(s)) => Some(s.clone()),
        Some(serde_json::Value::Array(parts)) => {
            let mut text = String::new();
            for part in parts {
                if part.get("type").and_then(|t| t.as_str()) != Some("text") {
                    return None;
                }
                if let Some(t) = part.get("text").and_then(|t| t.as_str()) {
                    text.push_str(t);
                    text.push('\n');
                }
            }
            Some(text)
        }
        _ => None,
    }
}

/// A byte offset into the transcript and the scan state derived to **exactly**
/// that offset, together with the identity of the file the offset indexes into.
///
/// # The pair is the race guard
///
/// The offset and the state are one value, read as one and published as one.
/// Hooks for a single event run in parallel, so two hook processes can read and
/// publish this concurrently. Because a reader always gets a matched pair or
/// nothing, a stale read costs a re-fold from an earlier offset — a redundant
/// rescan over a *superset* of the new bytes — and can never produce a wrong
/// answer. Split into two independently-read values, a state carried from an
/// earlier offset would be re-folded against a later one, and the records in
/// between would be applied twice or skipped entirely.
///
/// Publication is by `rename(2)`, which is atomic within a directory, so a
/// concurrent reader observes the complete old pair or the complete new one and
/// never a mix. See [`publish_cached_fold`].
struct CachedFold {
    /// Device and inode of the transcript the offset was derived against. An
    /// offset means nothing against a different file. The length check alone
    /// would not catch this: a transcript *replaced* by a longer one leaves the
    /// stored offset in range while it no longer means what it meant.
    dev: u64,
    ino: u64,
    /// End of the last newline-terminated record folded into `scan`. Never the
    /// end of a record that ran to end of input: that record may be an append in
    /// progress, and resuming past it would silently drop its remainder.
    offset: u64,
    /// The state derived from the transcript's first `offset` bytes.
    scan: Scan,
}

/// Where a session's cached fold lives: beside its witness in the same store,
/// keyed by session and — when the evaluated call came from a Task subagent —
/// by agent as well.
///
/// The agent key matters because [`transcript_for`] hands each subagent a
/// different file. One key covering two transcripts would fail the identity
/// check on every alternating call and reset the fold each time, which is
/// correct but pays the full rescan the cache exists to avoid.
fn scan_cache_path(store: &Path, session_id: &str, v: &serde_json::Value) -> PathBuf {
    match v
        .get("agent_id")
        .and_then(|a| a.as_str())
        .and_then(sanitize_session_id)
    {
        Some(agent) => store.join(format!("{session_id}.agent-{agent}.scan.json")),
        None => store.join(format!("{session_id}.scan.json")),
    }
}

/// Read the cached pair, or `None` when there is none, it is unreadable, or it
/// does not parse into a **complete** pair.
///
/// Free to be this strict because every rejection is a re-derivation from the
/// start: an unrecognized cache costs one full scan, while a half-trusted one
/// costs correctness. The same `O_NOFOLLOW` and regular-file discipline the
/// transcript and the plan get applies here — the store is machine-local and
/// mode 0700, but a file this code seeks by is not worth treating as trusted.
fn read_cached_fold(path: &Path) -> Option<CachedFold> {
    let file = open_regular_nofollow(path)?;
    if regular_file_len(&file)? > MAX_SCAN_CACHE_BYTES {
        return None;
    }
    let mut raw = String::new();
    file.take(MAX_SCAN_CACHE_BYTES)
        .read_to_string(&mut raw)
        .ok()?;
    let v: serde_json::Value = serde_json::from_str(&raw).ok()?;
    if v.get("contract_version").and_then(|c| c.as_u64())
        != Some(SCAN_CACHE_CONTRACT_VERSION as u64)
    {
        return None;
    }
    // Re-imposed on read rather than trusted from the write, so a cache file
    // cannot smuggle in a state the live scan's own caps would have refused.
    let raw_refs = v.get("references")?.as_array()?;
    if raw_refs.len() > MAX_PLAN_REFERENCES {
        return None;
    }
    let mut references = Vec::with_capacity(raw_refs.len());
    for r in raw_refs {
        let r = r.as_str()?;
        if r.len() > MAX_REFERENCE_LEN {
            return None;
        }
        references.push(r.to_string());
    }
    Some(CachedFold {
        dev: v.get("dev")?.as_u64()?,
        ino: v.get("ino")?.as_u64()?,
        offset: v.get("offset")?.as_u64()?,
        scan: Scan {
            references,
            single_issue_marker: v.get("single_issue_marker")?.as_bool()?,
        },
    })
}

/// Publish the pair atomically: write the whole thing to a uniquely named
/// temporary in the same directory, then `rename(2)` it into place.
///
/// Unlike the witness, publication is last-writer-wins rather than
/// exclusive-create, and deliberately so: a later offset is strictly better
/// than an earlier one, and losing the race costs the loser's next call a
/// slightly longer re-fold rather than an error. What must not happen is a
/// *torn* pair, and `rename` is what rules that out.
fn publish_cached_fold(path: &Path, fold: &CachedFold) {
    let body = serde_json::json!({
        "contract_version": SCAN_CACHE_CONTRACT_VERSION,
        "dev": fold.dev,
        "ino": fold.ino,
        "offset": fold.offset,
        "references": fold.scan.references,
        "single_issue_marker": fold.scan.single_issue_marker,
    })
    .to_string();
    let Some(dir) = path.parent() else {
        return;
    };
    let tmp = dir.join(format!(
        ".scan.{}.{}.tmp",
        std::process::id(),
        unique_suffix()
    ));
    if write_new(&tmp, &body) && std::fs::rename(&tmp, path).is_ok() {
        return;
    }
    // Fail-open, as everywhere else here: an unpublishable cache costs the next
    // call a full rescan and changes no decision.
    let _ = std::fs::remove_file(&tmp);
}

/// What one fold of the transcript produced.
struct Folded {
    /// The state derived from the whole file, whatever this call had to read to
    /// get there.
    scan: Scan,
    /// The offset the published pair names.
    offset: u64,
    /// Where this call started folding. Zero means it re-derived from the start.
    resumed_from: u64,
    /// Bytes this call read from the transcript. The cost measure the design
    /// asks for: after the first call it tracks the appended bytes rather than
    /// the file size. Reported on the trace, and asserted by
    /// `cost_after_the_first_call_tracks_appended_bytes`.
    bytes_scanned: u64,
}

/// Fold the transcript's prompt-shaped records into a [`Scan`], resuming from
/// the cached pair when one is present and usable, and publishing the new pair.
///
/// # Why the state and not the answer
///
/// Two tempting simplifications are both wrong, and this function is shaped by
/// avoiding them.
///
/// **A cached verdict would be wrong.** The write-target comparison is a
/// property of the target path, not of the session, so a session-level verdict
/// would permit or refuse every write in a session alike — which contradicts
/// the requirement that an in-set write be permitted in the same session where
/// an out-of-set write is refused. Only the transcript-derived state is cached
/// here. Reference resolution and the plan's frontmatter read stay per-call, so
/// a plan that gains `execution_mode: coordinated` mid-session stands the
/// refusal down on the very next call.
///
/// **A frozen arming decision would also be wrong, because the predicate is not
/// monotone.** Presence is monotone in the append direction — once an
/// instruction names a resolvable plan, no later record can unname it — but the
/// exclusion is not, and the counterexample is ordinary rather than
/// adversarial. An author who re-scopes mid-session ("actually, just do issue
/// three") appends a record that *should* disarm. A frozen decision stays
/// armed, which is stricter-when-stale: it runs against the fail-open direction
/// and produces exactly the false-refusal class this predicate exists to avoid.
/// `a_session_rescoped_to_one_issue_disarms` is that case.
///
/// Folding the state and re-deriving the verdict gets both: presence stays
/// monotone, and the disarming exclusion still fires late.
fn fold_transcript(transcript: &Path, cache: Option<&Path>) -> Result<Folded, NotArmed> {
    let file = open_regular_nofollow(transcript).ok_or(NotArmed::TranscriptUnreadable)?;
    let meta = file
        .metadata()
        .map_err(|_| NotArmed::TranscriptUnreadable)?;
    if !meta.is_file() {
        return Err(NotArmed::TranscriptUnreadable);
    }
    let size = meta.len();
    if size > MAX_TRANSCRIPT_BYTES {
        return Err(NotArmed::TranscriptOverCap);
    }

    // Whichever pair is on disk. Both filters below re-derive from the start
    // rather than resume at a position that no longer means what it meant: a
    // different file, or a file that has since become shorter than the offset
    // through truncation or replacement in place.
    let resume = cache
        .and_then(read_cached_fold)
        .filter(|c| c.dev == meta.dev() && c.ino == meta.ino())
        .filter(|c| c.offset <= size);

    let mut reader = BufReader::new(file);
    let mut start = resume.as_ref().map_or(0, |c| c.offset);
    if start > 0 && reader.seek(SeekFrom::Start(start)).is_err() {
        // A failed seek leaves the reader at the beginning; re-derive rather
        // than fold new records onto a resumed state at an unknown position.
        start = 0;
    }
    let mut scan = match &resume {
        Some(c) if start > 0 => c.scan.clone(),
        _ => Scan::default(),
    };

    let mut buf: Vec<u8> = Vec::new();
    let mut offset = start;
    let mut bytes_scanned = 0u64;

    while let Some(record) = read_capped_line(&mut reader, &mut buf) {
        bytes_scanned += record.consumed;
        // Only a newline is a safe place to stop. A record that ended at end of
        // input may be an append in progress, and an offset past it would drop
        // the rest of that record once the writer finishes it.
        if record.terminated {
            offset += record.consumed;
        }
        // An over-cap record is skipped, not parsed. A prompt-shaped record is
        // small; anything past the cap is a tool-result payload we discard
        // anyway.
        if !record.complete {
            continue;
        }
        // Cheap gate before the expensive one. The scan's only outputs are plan
        // references and the delegation marker, so a record whose raw bytes
        // contain neither cannot contribute to either, whatever its shape, and
        // is not worth deserializing. On a real 13MB transcript this is the
        // difference between scanning the whole file and parsing 862 tool-result
        // payloads to discard every one of them.
        //
        // Sound in the fail-open direction, which is the direction that
        // matters: the pattern is built from the same constants the
        // authoritative match below uses, and a reference obfuscated past it —
        // JSON lets any letter be written as a unicode escape — simply does not
        // arm.
        if !relevance_prefilter().is_match(&buf) {
            continue;
        }
        let Ok(record) = serde_json::from_slice::<serde_json::Value>(&buf) else {
            // One malformed line does not condemn the transcript. The parse is
            // total by construction: `serde_json` returns an error, it does not
            // throw, and a hook that died on a hostile record would deny
            // service to every session on the machine.
            continue;
        };
        let Some(text) = is_prompt_shaped(&record) else {
            continue;
        };
        let lowered = text.to_ascii_lowercase();
        if SINGLE_ISSUE_MARKERS.iter().any(|m| lowered.contains(m)) {
            scan.single_issue_marker = true;
        }
        for m in plan_reference_pattern().find_iter(&text) {
            let reference = m.as_str();
            if reference.len() > MAX_REFERENCE_LEN {
                continue;
            }
            if scan.references.iter().any(|r| r == reference) {
                continue;
            }
            if scan.references.len() == MAX_PLAN_REFERENCES {
                // Returning here abandons the fold, so nothing is published:
                // there is no offset this partial state was derived to. The
                // next call rescans from the last published pair and reaches
                // the same conclusion, which is the correct trade — a session
                // whose instructions name more than [`MAX_PLAN_REFERENCES`]
                // distinct plans is an anomaly, and it allows either way.
                return Err(NotArmed::TooManyReferences);
            }
            scan.references.push(reference.to_string());
        }
    }

    // Publishing only when the offset moved keeps the common case — an armed
    // session's second and later calls with nothing appended since — down to
    // the read. The `resume.is_none()` arm covers the first call of a session,
    // which must establish a pair even when the transcript is empty.
    if let Some(path) = cache {
        if resume.is_none() || offset != start {
            publish_cached_fold(
                path,
                &CachedFold {
                    dev: meta.dev(),
                    ino: meta.ino(),
                    offset,
                    scan: scan.clone(),
                },
            );
        }
    }

    Ok(Folded {
        scan,
        offset,
        resumed_from: start,
        bytes_scanned,
    })
}

/// One record read from the transcript.
#[derive(PartialEq, Eq, Debug)]
struct RawRecord {
    /// The record was under [`MAX_RECORD_BYTES`] and is in `buf`. False when it
    /// exceeded the cap and its remainder was walked past without being held.
    complete: bool,
    /// Bytes consumed from the reader, including the terminating newline and any
    /// discarded remainder.
    consumed: u64,
    /// The record ended at a newline rather than at end of input. This is the
    /// only kind of boundary an offset may be persisted at, since a record that
    /// ran to end of input may be a write still in progress.
    terminated: bool,
}

/// Read one JSONL record into `buf`, bounded by [`MAX_RECORD_BYTES`].
///
/// Returns `None` at end of input or on an I/O error, otherwise a [`RawRecord`]
/// describing what was consumed. Peak memory is one record, not one transcript.
fn read_capped_line<R: BufRead>(reader: &mut R, buf: &mut Vec<u8>) -> Option<RawRecord> {
    buf.clear();
    let n = reader
        .by_ref()
        .take(MAX_RECORD_BYTES as u64)
        .read_until(b'\n', buf)
        .ok()?;
    if n == 0 {
        return None;
    }
    let terminated = buf.last() == Some(&b'\n');
    // Newline-terminated, or short of the cap and therefore ended by EOF.
    if terminated || n < MAX_RECORD_BYTES {
        return Some(RawRecord {
            complete: true,
            consumed: n as u64,
            terminated,
        });
    }
    // Over the cap: walk to the end of the record without holding it.
    let mut consumed = n as u64;
    let mut scratch: Vec<u8> = Vec::new();
    loop {
        scratch.clear();
        let m = reader
            .by_ref()
            .take(MAX_RECORD_BYTES as u64)
            .read_until(b'\n', &mut scratch)
            .ok()?;
        consumed += m as u64;
        if m == 0 || scratch.last() == Some(&b'\n') {
            return Some(RawRecord {
                complete: false,
                consumed,
                terminated: scratch.last() == Some(&b'\n'),
            });
        }
    }
}

/// Whether a raw JSONL line could possibly contribute to the scan: it names
/// something plan-shaped, or carries a delegation marker.
///
/// Built from the same constants the authoritative matches use, so the two
/// cannot drift apart. It runs over raw bytes, before deserialization and
/// before the prompt-shaped test — it is a cost filter, never a decision. A
/// record it admits is still subject to [`is_prompt_shaped`], which is where
/// tool output is excluded.
fn relevance_prefilter() -> &'static regex::bytes::Regex {
    static PATTERN: OnceLock<regex::bytes::Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        let markers = SINGLE_ISSUE_MARKERS
            .iter()
            .map(|m| regex::escape(m))
            .collect::<Vec<_>>()
            .join("|");
        regex::bytes::Regex::new(&format!("PLAN-|(?i:{markers})"))
            .expect("the prefilter is built from escaped literals and compiles")
    })
}

/// A plan-shaped reference: an optional relative directory prefix followed by a
/// `PLAN-`-prefixed Markdown filename. Deliberately narrow — it only proposes
/// candidates, and everything it admits is still resolved, confined, and
/// schema-checked before it can arm anything.
fn plan_reference_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(r"(?:[A-Za-z0-9._][A-Za-z0-9._/-]*/)?PLAN-[A-Za-z0-9._-]+\.md")
            .expect("the plan reference pattern is a literal and compiles")
    })
}

/// A plan that resolved, opened, and parsed.
struct PlanDoc {
    path: PathBuf,
    execution_mode: Option<String>,
}

/// Resolve a reference inside `root`, open it, and read its frontmatter.
///
/// Resolution and use are not separable here, which is the point. The final
/// component is opened with `O_NOFOLLOW` so a symlink planted between the
/// resolution and the read is refused rather than followed, the opened
/// descriptor is confirmed to be a regular file, and every subsequent operation
/// — the size check and the read — goes through that same descriptor. The name
/// is never resolved twice.
fn read_plan(root: &Path, reference: &str) -> Result<PlanDoc, NotArmed> {
    let relative = confine(reference).ok_or(NotArmed::UnresolvableReference)?;
    let candidate = root.join(&relative);

    // Canonicalize the *directory* only. The final component must not be
    // resolved by name, so it is re-attached to the canonical parent and opened
    // with `O_NOFOLLOW`.
    let (parent, file_name) = match (candidate.parent(), candidate.file_name()) {
        (Some(p), Some(f)) => (p, f),
        _ => return Err(NotArmed::UnresolvableReference),
    };
    let parent = parent
        .canonicalize()
        .map_err(|_| NotArmed::UnresolvableReference)?;
    if !parent.starts_with(root) {
        // A symlinked directory component pointing out of the working tree.
        return Err(NotArmed::UnresolvableReference);
    }
    let path = parent.join(file_name);

    let file = open_regular_nofollow(&path).ok_or(NotArmed::UnresolvableReference)?;
    let size = regular_file_len(&file).ok_or(NotArmed::UnresolvableReference)?;
    if size > MAX_PLAN_BYTES {
        return Err(NotArmed::PlanUnreadable);
    }
    let mut text = String::new();
    file.take(MAX_PLAN_BYTES)
        .read_to_string(&mut text)
        .map_err(|_| NotArmed::PlanUnreadable)?;

    let front = parse_front_matter(&text).ok_or(NotArmed::NotAPlan)?;
    if front.schema.as_deref() != Some(PLAN_SCHEMA) {
        return Err(NotArmed::NotAPlan);
    }
    Ok(PlanDoc {
        path,
        execution_mode: front.execution_mode,
    })
}

/// Validate a reference as a working-tree-relative path before any filesystem
/// access, and normalize it. A bare filename is taken to mean the conventional
/// plans directory, which is how `/execute` is invoked with one.
///
/// Runs before any filesystem access, so a hostile reference costs a string
/// walk rather than a `stat`. It is not the confinement check on its own — the
/// canonical-parent prefix test in [`read_plan`] is, since a symlinked
/// directory component is invisible to a lexical walk.
fn confine(reference: &str) -> Option<PathBuf> {
    let raw = Path::new(reference);
    if raw.is_absolute() {
        return None;
    }
    let mut normalized = PathBuf::new();
    for component in raw.components() {
        match component {
            Component::Normal(c) => normalized.push(c),
            // A `.` cannot escape anything, so it is dropped rather than
            // refused: `/execute ./docs/plans/PLAN-x.md` is an ordinary way to
            // name a plan.
            Component::CurDir => {}
            // `..` and a root or prefix component are refused outright rather
            // than resolved, since resolving them lexically is where traversal
            // checks usually go wrong.
            _ => return None,
        }
    }
    if normalized.as_os_str().is_empty() {
        return None;
    }
    if normalized.parent() == Some(Path::new("")) {
        return Some(Path::new(PLANS_DIR).join(normalized));
    }
    Some(normalized)
}

/// The two frontmatter fields the arming predicate needs.
struct FrontMatter {
    schema: Option<String>,
    execution_mode: Option<String>,
}

/// Read `schema:` and `execution_mode:` out of a leading YAML frontmatter
/// block.
///
/// A line scanner rather than a YAML parse: the input is attacker-supplied, two
/// top-level scalars are all that is needed, and a scanner is total by
/// construction where a general parser's behavior on hostile input is a larger
/// surface than the fields are worth. Returns `None` when there is no closing
/// delimiter within [`MAX_PLAN_FRONT_MATTER_LINES`], which is a parse failure
/// and therefore an allow.
fn parse_front_matter(text: &str) -> Option<FrontMatter> {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut lines = text.lines();
    if lines.next()?.trim_end() != "---" {
        return None;
    }
    let mut front = FrontMatter {
        schema: None,
        execution_mode: None,
    };
    for line in lines.take(MAX_PLAN_FRONT_MATTER_LINES) {
        let trimmed = line.trim_end();
        if trimmed == "---" || trimmed == "..." {
            return Some(front);
        }
        // Top-level keys only: an indented line belongs to a nested mapping and
        // a `schema:` nested under something else is not the document's schema.
        if line.starts_with([' ', '\t']) {
            continue;
        }
        let Some((key, value)) = trimmed.split_once(':') else {
            continue;
        };
        let value = unquote(value.trim());
        match key.trim() {
            "schema" => front.schema = Some(value),
            "execution_mode" => front.execution_mode = Some(value),
            _ => {}
        }
    }
    None
}

/// Strip one layer of matching YAML quotes.
fn unquote(value: &str) -> String {
    for q in ['"', '\''] {
        if value.len() >= 2 && value.starts_with(q) && value.ends_with(q) {
            return value[1..value.len() - 1].to_string();
        }
    }
    value.to_string()
}

/// Open a path for reading, refusing a symlink at the final component and
/// anything that is not a regular file. `None` on any failure.
fn open_regular_nofollow(path: &Path) -> Option<std::fs::File> {
    use rustix::fs::{Mode, OFlags};
    let fd = rustix::fs::open(
        path,
        OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .ok()?;
    let file = std::fs::File::from(fd);
    // `O_NOFOLLOW` refuses a symlink; this refuses a directory, a fifo, or a
    // device, any of which would make the read below misbehave.
    file.metadata().ok()?.is_file().then_some(file)
}

/// The length of an already-opened regular file, read from the descriptor
/// rather than by re-stating the path.
fn regular_file_len(file: &std::fs::File) -> Option<u64> {
    let meta = file.metadata().ok()?;
    meta.is_file().then_some(meta.len())
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

        /// Write a plan at `docs/plans/<name>` and return the path relative to
        /// the repository, which is the form an instruction names it in.
        fn with_plan(&self, name: &str, body: &str) -> String {
            self.with_plans();
            std::fs::write(self.repo().join(PLANS_DIR).join(name), body).unwrap();
            format!("{PLANS_DIR}/{name}")
        }

        /// Write a JSONL transcript and return its path.
        fn transcript(&self, records: &[serde_json::Value]) -> PathBuf {
            static N: AtomicUsize = AtomicUsize::new(0);
            let n = N.fetch_add(1, Ordering::SeqCst);
            let path = self.dir.join(format!("transcript-{n}.jsonl"));
            let body: String = records
                .iter()
                .map(|r| format!("{r}\n"))
                .collect::<Vec<_>>()
                .concat();
            std::fs::write(&path, body).unwrap();
            path
        }

        /// Evaluate one edit-shaped call against a transcript built from
        /// `records`, and return the arming decision.
        fn arm(&self, records: &[serde_json::Value]) -> Arming {
            let transcript = self.transcript(records);
            self.arm_with_transcript(&transcript)
        }

        fn arm_with_transcript(&self, transcript: &Path) -> Arming {
            let mut v: serde_json::Value =
                serde_json::from_str(&hook("sess-arm", &self.repo())).unwrap();
            v["transcript_path"] = serde_json::json!(transcript.to_string_lossy());
            evaluate(&v.to_string(), Some(&self.store())).arming
        }

        /// Append records to an existing transcript, as the harness does while
        /// the session runs, and return the bytes appended. In-place: the
        /// inode is unchanged, which is what a resumed fold requires.
        fn append(&self, transcript: &Path, records: &[serde_json::Value]) -> u64 {
            let before = std::fs::metadata(transcript).unwrap().len();
            let mut f = std::fs::OpenOptions::new()
                .append(true)
                .open(transcript)
                .unwrap();
            for r in records {
                writeln!(f, "{r}").unwrap();
            }
            drop(f);
            std::fs::metadata(transcript).unwrap().len() - before
        }

        /// The cached pair for the session [`Fx::arm_with_transcript`] uses.
        fn cache(&self) -> PathBuf {
            self.store().join("sess-arm.scan.json")
        }

        /// Device and inode of a path, for building pairs by hand.
        fn identity(&self, path: &Path) -> (u64, u64) {
            let m = std::fs::metadata(path).unwrap();
            (m.dev(), m.ino())
        }
    }

    /// A plan the arming predicate should accept.
    const SINGLE_PR_PLAN: &str = "---\nschema: plan/v1\nstatus: Active\nexecution_mode: single-pr\nissue_count: 9\n---\n\n# PLAN: Whatever\n";

    /// An instruction the session was given: a typed prompt, a teammate
    /// message, a dispatched brief. String content, no tool provenance.
    fn prompt(text: &str) -> serde_json::Value {
        serde_json::json!({
            "type": "user",
            "userType": "external",
            "isSidechain": false,
            "message": { "role": "user", "content": text },
        })
    }

    /// A tool result: output the agent pulled in. Carries both the provenance
    /// fields and a `tool_result` content part, as the real records do.
    fn tool_result(text: &str) -> serde_json::Value {
        serde_json::json!({
            "type": "user",
            "userType": "external",
            "sourceToolAssistantUUID": "0d1e-abc",
            "toolUseResult": { "type": "text", "file": { "content": text } },
            "message": {
                "role": "user",
                "content": [ { "type": "tool_result", "tool_use_id": "toolu_1", "content": text } ],
            },
        })
    }

    /// An attachment record: harness-injected context, not a message.
    fn attachment(text: &str) -> serde_json::Value {
        serde_json::json!({
            "type": "attachment",
            "attachment": { "type": "file_content", "content": text },
        })
    }

    /// A meta record: a system reminder or a skill body the Skill tool loaded.
    fn meta(text: &str) -> serde_json::Value {
        serde_json::json!({
            "type": "user",
            "isMeta": true,
            "sourceToolUseID": "toolu_2",
            "message": { "role": "user", "content": text },
        })
    }

    /// The agent's own turn.
    fn assistant(text: &str) -> serde_json::Value {
        serde_json::json!({
            "type": "assistant",
            "message": { "role": "assistant", "content": [ { "type": "text", "text": text } ] },
        })
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

    // --- arming: the scan boundary ----------------------------------------

    #[test]
    fn a_plan_reference_in_the_given_instructions_arms() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let arming = fx.arm(&[prompt(&format!("/execute {reference}"))]);
        assert_eq!(arming.reason(), "armed");
        assert_eq!(
            arming.armed_plan().unwrap(),
            fx.repo().canonicalize().unwrap().join(&reference)
        );
    }

    #[test]
    fn a_plan_filename_in_tool_output_does_not_arm() {
        // THE regression test. The plan below is real, resolvable, and valid:
        // the only thing standing between this session and a refusal is the
        // scan boundary. Without it, any agent that reads or reviews a plan
        // file arms the refusal against itself, and an outside contributor can
        // write-deny a maintainer's agent by opening a pull request that adds a
        // valid plan plus any readable file naming it. One pull request, no
        // merge required.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let mention = format!("see {reference} for the sequencing");

        let pulled_in = [
            // `Read` of the plan itself.
            tool_result(SINGLE_PR_PLAN),
            // `Read` or `Grep` of a file that merely names the plan.
            tool_result(&mention),
            // `Bash` output: `ls docs/plans`, `git log --stat`, `grep -r`.
            tool_result(&format!("docs/plans/PLAN-topic.md\n{mention}")),
            // A harness attachment carrying file content.
            attachment(&mention),
            // A skill body or system reminder the harness injected.
            meta(&mention),
            // The agent's own turn talking about the plan.
            assistant(&mention),
        ];

        for record in &pulled_in {
            let arming = fx.arm(std::slice::from_ref(record));
            assert_eq!(
                arming.reason(),
                "no-plan-reference",
                "a plan named in pulled-in output must not arm: {record}"
            );
        }
        // And all of them together still do not add up to an instruction.
        assert_eq!(fx.arm(&pulled_in).reason(), "no-plan-reference");
    }

    #[test]
    fn the_scan_boundary_admits_only_prompt_shaped_records() {
        // The predicate itself, independent of the ladder above it.
        assert_eq!(
            is_prompt_shaped(&prompt("hello")).as_deref(),
            Some("hello"),
            "a typed prompt is an instruction"
        );
        for excluded in [
            tool_result("hello"),
            attachment("hello"),
            meta("hello"),
            assistant("hello"),
            serde_json::json!({ "type": "system", "content": "hello" }),
            serde_json::json!({ "type": "user" }),
            // A `user` record whose content mixes text with a tool result: one
            // disqualifying part is enough.
            serde_json::json!({
                "type": "user",
                "message": { "content": [
                    { "type": "text", "text": "hello" },
                    { "type": "tool_result", "content": "pulled in" },
                ] },
            }),
            // Provenance alone disqualifies, even with text-shaped content, so
            // a harness that stops emitting `tool_result` parts does not
            // silently open the boundary.
            serde_json::json!({
                "type": "user",
                "sourceToolUseID": "toolu_9",
                "message": { "content": "hello" },
            }),
        ] {
            assert!(
                is_prompt_shaped(&excluded).is_none(),
                "must be excluded: {excluded}"
            );
        }
        // A prompt delivered as text parts rather than a bare string.
        let parts = serde_json::json!({
            "type": "user",
            "message": { "content": [ { "type": "text", "text": "hello" } ] },
        });
        assert_eq!(is_prompt_shaped(&parts).as_deref(), Some("hello\n"));
    }

    #[test]
    fn a_teammate_message_is_an_instruction() {
        // A dispatched child receives its brief as a string-content user record
        // with no tool provenance, exactly like a typed prompt.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let brief = format!(
            "<teammate-message teammate_id=\"team-lead\">\nDrive {reference} to merged code.\n</teammate-message>"
        );
        assert_eq!(fx.arm(&[prompt(&brief)]).reason(), "armed");
    }

    // --- arming: the stand-down clauses -----------------------------------

    #[test]
    fn a_single_issue_delegation_marker_stands_down() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        for marker in [
            "You are a `/work-on` single-issue child dispatched by `/execute`",
            "This is a SINGLE-ISSUE DELEGATION",
            "run the /work-on single-issue engine",
        ] {
            let arming = fx.arm(&[prompt(&format!("{marker} for {reference}, issue 3 of 9"))]);
            assert_eq!(
                arming.reason(),
                "single-issue-delegation",
                "marker {marker:?} must stand the refusal down"
            );
        }
    }

    #[test]
    fn a_coordinated_plan_does_not_arm() {
        let fx = Fx::new();
        let plan = SINGLE_PR_PLAN.replace("single-pr", "coordinated");
        let reference = fx.with_plan("PLAN-topic.md", &plan);
        assert_eq!(
            fx.arm(&[prompt(&format!("/execute {reference}"))]).reason(),
            "coordinated"
        );
    }

    #[test]
    fn a_document_without_the_plan_schema_does_not_arm() {
        let fx = Fx::new();
        for body in [
            // A design doc that happens to be named like a plan.
            "---\nschema: design/v1\nstatus: Accepted\n---\n\n# Not a plan\n",
            // No frontmatter at all.
            "# PLAN: looks like one\n\nBut declares nothing.\n",
            // An unterminated frontmatter block: a parse failure, so allow.
            "---\nschema: plan/v1\nstatus: Active\n\n# PLAN\n",
            // `schema` nested under another key is not the document's schema.
            "---\nupstream:\n  schema: plan/v1\n---\n\n# PLAN\n",
        ] {
            let reference = fx.with_plan("PLAN-topic.md", body);
            assert_eq!(
                fx.arm(&[prompt(&format!("/execute {reference}"))]).reason(),
                "not-a-plan",
                "must not arm on: {body}"
            );
        }
    }

    // --- arming: every failure path allows ---------------------------------

    #[test]
    fn a_missing_or_unnamed_transcript_allows() {
        let fx = Fx::new();
        fx.with_plans();
        // No `transcript_path` at all.
        let arming = evaluate(&hook("sess-notrans", &fx.repo()), Some(&fx.store())).arming;
        assert_eq!(arming.reason(), "no-transcript");
        // A relative one, which we refuse rather than join.
        assert_eq!(
            fx.arm_with_transcript(Path::new("relative/transcript.jsonl"))
                .reason(),
            "no-transcript"
        );
        // Named but absent.
        assert_eq!(
            fx.arm_with_transcript(&fx.dir.join("gone.jsonl")).reason(),
            "transcript-unreadable"
        );
        // Named but not a regular file.
        assert_eq!(
            fx.arm_with_transcript(&fx.repo()).reason(),
            "transcript-unreadable"
        );
    }

    #[test]
    fn an_over_cap_transcript_allows() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let path = fx.transcript(&[prompt(&format!("/execute {reference}"))]);
        // Grow past the cap without writing 64 MiB: the size check reads the
        // descriptor's metadata, so a sparse file is enough.
        let f = std::fs::OpenOptions::new().write(true).open(&path).unwrap();
        f.set_len(MAX_TRANSCRIPT_BYTES + 1).unwrap();
        drop(f);
        assert_eq!(
            fx.arm_with_transcript(&path).reason(),
            "transcript-over-cap"
        );
    }

    #[test]
    fn an_over_cap_plan_allows() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let f = std::fs::OpenOptions::new()
            .write(true)
            .open(fx.repo().join(&reference))
            .unwrap();
        f.set_len(MAX_PLAN_BYTES + 1).unwrap();
        drop(f);
        assert_eq!(
            fx.arm(&[prompt(&format!("/execute {reference}"))]).reason(),
            "plan-unreadable"
        );
    }

    #[test]
    fn an_over_cap_match_count_allows() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        // Every reference distinct, so deduplication does not absorb them.
        let mut text = format!("/execute {reference}");
        for i in 0..=MAX_PLAN_REFERENCES {
            text.push_str(&format!(" docs/plans/PLAN-decoy-{i}.md"));
        }
        assert_eq!(
            fx.arm(&[prompt(&text)]).reason(),
            "too-many-references",
            "a padded instruction costs a resolution apiece and must allow"
        );
        // The same reference repeated past the cap is deduplicated, so an
        // instruction that names one plan many times still arms.
        let repeated = vec![format!("/execute {reference}"); MAX_PLAN_REFERENCES * 2].join(" ");
        assert_eq!(fx.arm(&[prompt(&repeated)]).reason(), "armed");
    }

    #[test]
    fn an_unresolvable_reference_allows() {
        let fx = Fx::new();
        fx.with_plans();
        for reference in [
            // Names nothing on disk.
            "docs/plans/PLAN-absent.md",
            // Traversal out of the working tree.
            "../PLAN-outside.md",
            "docs/plans/../../PLAN-outside.md",
            // Absolute, refused before any filesystem access.
            "/etc/PLAN-passwd.md",
        ] {
            assert_eq!(
                fx.arm(&[prompt(&format!("/execute {reference}"))]).reason(),
                "unresolvable-reference",
                "reference {reference:?} must not resolve"
            );
        }
    }

    #[test]
    fn a_malformed_record_does_not_stop_the_scan() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let path = fx.dir.join("mixed.jsonl");
        let body = format!(
            "not json at all\n{{\"type\":\n[]\n{}\n",
            prompt(&format!("/execute {reference}"))
        );
        std::fs::write(&path, body).unwrap();
        assert_eq!(fx.arm_with_transcript(&path).reason(), "armed");
    }

    // --- arming: resolution and use are not separable ----------------------

    #[test]
    fn a_symlinked_plan_is_refused() {
        // The final component is opened with `O_NOFOLLOW`, so a symlink planted
        // where the plan should be cannot redirect the read. Otherwise a
        // session arms on one file and reads another.
        let fx = Fx::new();
        fx.with_plans();
        let outside = fx.dir.join("outside-plan.md");
        std::fs::write(&outside, SINGLE_PR_PLAN).unwrap();
        std::os::unix::fs::symlink(&outside, fx.repo().join(PLANS_DIR).join("PLAN-link.md"))
            .unwrap();
        assert_eq!(
            fx.arm(&[prompt("/execute docs/plans/PLAN-link.md")])
                .reason(),
            "unresolvable-reference"
        );
    }

    #[test]
    fn a_plan_that_is_not_a_regular_file_is_refused() {
        let fx = Fx::new();
        fx.with_plans();
        std::fs::create_dir_all(fx.repo().join(PLANS_DIR).join("PLAN-dir.md")).unwrap();
        assert_eq!(
            fx.arm(&[prompt("/execute docs/plans/PLAN-dir.md")])
                .reason(),
            "unresolvable-reference"
        );
    }

    #[test]
    fn a_symlinked_directory_component_out_of_the_tree_is_refused() {
        // Confinement is checked against the canonical parent, so a symlinked
        // directory inside the tree cannot smuggle a plan in from outside it.
        let fx = Fx::new();
        fx.with_plans();
        let outside = fx.dir.join("elsewhere");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("PLAN-topic.md"), SINGLE_PR_PLAN).unwrap();
        std::os::unix::fs::symlink(&outside, fx.repo().join("linked")).unwrap();
        assert_eq!(
            fx.arm(&[prompt("/execute linked/PLAN-topic.md")]).reason(),
            "unresolvable-reference"
        );
    }

    #[test]
    fn a_bare_plan_filename_resolves_under_the_plans_directory() {
        let fx = Fx::new();
        fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        assert_eq!(
            fx.arm(&[prompt("/execute PLAN-topic.md")]).reason(),
            "armed"
        );
    }

    #[test]
    fn a_leading_dot_is_dropped_rather_than_refused() {
        let fx = Fx::new();
        fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        assert_eq!(
            fx.arm(&[prompt("/execute ./docs/plans/PLAN-topic.md")])
                .reason(),
            "armed"
        );
        assert_eq!(
            confine("./docs/plans/PLAN-x.md").unwrap(),
            Path::new("docs/plans/PLAN-x.md")
        );
        assert_eq!(
            confine("PLAN-x.md").unwrap(),
            Path::new("docs/plans/PLAN-x.md")
        );
        assert!(confine("../PLAN-x.md").is_none());
        assert!(confine("/abs/PLAN-x.md").is_none());
        assert!(confine(".").is_none());
    }

    // --- arming: routing and bounded reads ---------------------------------

    #[test]
    fn the_subagent_file_is_preferred_when_it_exists() {
        // Identity routes to the right transcript. It is never an orchestrator
        // test: absence of the field means nothing about the role.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let parent = fx.transcript(&[prompt(&format!("/execute {reference}"))]);
        let child_dir = parent
            .parent()
            .unwrap()
            .join(parent.file_stem().unwrap())
            .join("subagents");
        std::fs::create_dir_all(&child_dir).unwrap();
        std::fs::write(
            child_dir.join("agent-child-7.jsonl"),
            format!("{}\n", prompt("Review this file and report back")),
        )
        .unwrap();

        let mut v: serde_json::Value =
            serde_json::from_str(&hook("sess-routed", &fx.repo())).unwrap();
        v["transcript_path"] = serde_json::json!(parent.to_string_lossy());
        v["agent_id"] = serde_json::json!("child-7");
        // The child's own instructions name no plan, so it does not inherit the
        // parent's arming.
        assert_eq!(
            evaluate(&v.to_string(), Some(&fx.store())).arming.reason(),
            "no-plan-reference"
        );
        // Without the routing key, the parent's transcript arms.
        v["agent_id"] = serde_json::json!(null);
        assert_eq!(
            evaluate(&v.to_string(), Some(&fx.store())).arming.reason(),
            "armed"
        );
    }

    /// A record read: `(complete, consumed, terminated)`, for the assertions
    /// below.
    fn record(complete: bool, consumed: u64, terminated: bool) -> Option<RawRecord> {
        Some(RawRecord {
            complete,
            consumed,
            terminated,
        })
    }

    #[test]
    fn an_over_cap_record_is_skipped_rather_than_parsed() {
        let over = MAX_RECORD_BYTES + 10;
        let mut long = vec![b'x'; over];
        long.push(b'\n');
        long.extend_from_slice(b"second\n");
        let mut reader = std::io::Cursor::new(long);
        let mut buf = Vec::new();
        // Skipped, but every byte of it is accounted for, and it ended at a
        // newline: the offset may advance past it.
        assert_eq!(
            read_capped_line(&mut reader, &mut buf),
            record(false, over as u64 + 1, true)
        );
        assert_eq!(
            read_capped_line(&mut reader, &mut buf),
            record(true, 7, true)
        );
        assert_eq!(buf, b"second\n");
        assert_eq!(read_capped_line(&mut reader, &mut buf), None);
    }

    #[test]
    fn a_final_record_without_a_newline_is_still_read() {
        let mut reader = std::io::Cursor::new(b"one\ntwo".to_vec());
        let mut buf = Vec::new();
        assert_eq!(
            read_capped_line(&mut reader, &mut buf),
            record(true, 4, true)
        );
        assert_eq!(buf, b"one\n");
        // Read and parsed, but *not* newline-terminated, which is what stops
        // the persisted offset from advancing past a record that may still be
        // being written.
        assert_eq!(
            read_capped_line(&mut reader, &mut buf),
            record(true, 3, false)
        );
        assert_eq!(buf, b"two");
        assert_eq!(read_capped_line(&mut reader, &mut buf), None);
    }

    #[test]
    fn front_matter_reads_the_two_fields_it_needs() {
        let f = parse_front_matter(SINGLE_PR_PLAN).unwrap();
        assert_eq!(f.schema.as_deref(), Some("plan/v1"));
        assert_eq!(f.execution_mode.as_deref(), Some("single-pr"));

        // Quoted scalars, and a closing `...` rather than `---`.
        let f =
            parse_front_matter("---\nschema: \"plan/v1\"\nexecution_mode: 'coordinated'\n...\n")
                .unwrap();
        assert_eq!(f.schema.as_deref(), Some("plan/v1"));
        assert_eq!(f.execution_mode.as_deref(), Some("coordinated"));

        // No opening delimiter, and no closing one: both are parse failures.
        assert!(parse_front_matter("# PLAN\n").is_none());
        assert!(parse_front_matter("---\nschema: plan/v1\n").is_none());
        // A frontmatter block longer than the cap never closes as far as we
        // are concerned.
        let long = format!(
            "---\n{}\n---\n",
            "filler: x\n".repeat(MAX_PLAN_FRONT_MATTER_LINES + 5)
        );
        assert!(parse_front_matter(&long).is_none());
    }

    #[test]
    fn the_reference_pattern_admits_only_plan_shaped_names() {
        let re = plan_reference_pattern();
        for admitted in [
            "docs/plans/PLAN-topic.md",
            "PLAN-topic.md",
            "public/shirabe/docs/plans/PLAN-a_b.2.md",
        ] {
            assert_eq!(
                re.find(admitted).map(|m| m.as_str()),
                Some(admitted),
                "must admit {admitted:?}"
            );
        }
        for rejected in [
            "docs/plans/PRD-topic.md",
            "plan-topic.md",
            "PLAN-topic.txt",
            "PLANNING.md",
        ] {
            assert!(
                re.find(rejected).is_none(),
                "must not admit {rejected:?}: {:?}",
                re.find(rejected).map(|m| m.as_str())
            );
        }
    }

    #[test]
    fn the_prefilter_admits_everything_the_matchers_need() {
        // It runs before deserialization, so a marker or reference it drops is
        // a decision the scan never gets to make. Both matchers' inputs must
        // survive it.
        let re = relevance_prefilter();
        assert!(re.is_match(b"docs/plans/PLAN-topic.md"));
        for marker in SINGLE_ISSUE_MARKERS {
            assert!(re.is_match(marker.as_bytes()), "drops marker {marker:?}");
            assert!(
                re.is_match(marker.to_uppercase().as_bytes()),
                "marker matching is case-insensitive: {marker:?}"
            );
        }
        // And it drops the bulk of a transcript, which is why it exists.
        assert!(!re.is_match(b"{\"type\":\"assistant\",\"message\":{\"content\":\"ok\"}}"));
    }

    #[test]
    fn an_over_long_reference_is_skipped() {
        let fx = Fx::new();
        fx.with_plans();
        let long = format!("docs/{}/PLAN-topic.md", "a".repeat(MAX_REFERENCE_LEN));
        assert_eq!(
            fx.arm(&[prompt(&format!("/execute {long}"))]).reason(),
            "no-plan-reference"
        );
    }

    #[test]
    fn arming_is_decided_per_call_rather_than_once_per_session() {
        // The witness is written once; the arming decision is not cached here,
        // and two calls in the same session are evaluated independently. The
        // caching increment must preserve that, because a session can be
        // re-scoped mid-run.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let armed = fx.transcript(&[prompt(&format!("/execute {reference}"))]);
        assert_eq!(fx.arm_with_transcript(&armed).reason(), "armed");
        let rescoped = fx.transcript(&[
            prompt(&format!("/execute {reference}")),
            prompt("Actually, you are a single-issue child: just do issue 3."),
        ]);
        assert_eq!(
            fx.arm_with_transcript(&rescoped).reason(),
            "single-issue-delegation"
        );
    }

    #[test]
    fn a_repository_without_plans_does_not_reach_the_scan() {
        let fx = Fx::new();
        // No plans directory: the cheap check stops before any transcript read.
        assert_eq!(
            fx.arm(&[prompt("/execute docs/plans/PLAN-x.md")]).reason(),
            "no-plans-directory"
        );
    }

    #[test]
    fn unusable_input_allows() {
        let fx = Fx::new();
        fx.with_plans();
        for input in ["", "not json", "{}", "[]", "{\"session_id\": 7}"] {
            assert_eq!(
                evaluate(input, Some(&fx.store())).arming.reason(),
                "unusable-input",
                "input {input:?} must be tolerated"
            );
        }
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

    // --- the tail scan -----------------------------------------------------

    #[test]
    fn a_session_rescoped_to_one_issue_disarms() {
        // The case a frozen arming decision gets wrong, and the reason the
        // cache holds a fold state rather than a verdict. The session arms on a
        // plan reference; the author then appends "actually, just do issue
        // three". The exclusion half of the predicate is not monotone, so that
        // later record has to be able to disarm a session that already armed —
        // and it has to manage it through the cache, from a fold that resumed
        // rather than one that started over.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let transcript = fx.transcript(&[prompt(&format!("/execute {reference}"))]);

        assert_eq!(fx.arm_with_transcript(&transcript).reason(), "armed");
        let armed_at = read_cached_fold(&fx.cache()).expect("the first call publishes a pair");
        assert!(!armed_at.scan.single_issue_marker);

        let appended = fx.append(
            &transcript,
            &[prompt(
                "Actually, you are a single-issue child: just do issue 3 of that plan.",
            )],
        );

        // The disarm arrives through a resumed fold, not a restarted one: this
        // call reads only the bytes the author just appended.
        let folded = fold_transcript(&transcript, Some(&fx.cache())).unwrap();
        assert_eq!(folded.resumed_from, armed_at.offset);
        assert_eq!(folded.bytes_scanned, appended);
        assert!(folded.scan.single_issue_marker);
        assert_eq!(
            folded.scan.references, armed_at.scan.references,
            "the presence half is monotone: the plan reference survives the append"
        );

        // And the verdict follows the state.
        assert_eq!(
            fx.arm_with_transcript(&transcript).reason(),
            "single-issue-delegation",
            "a later instruction re-scoping the session must disarm it"
        );
    }

    #[test]
    fn any_stale_pair_re_folds_to_the_same_answer() {
        // The concurrency guarantee, stated as a property rather than raced
        // for. Hooks for a single event run in parallel, so a reader can be
        // handed a pair published at any earlier offset. Every one of them —
        // including no pair at all — must fold to the same state as a scan from
        // the start. That is what "a redundant rescan over a superset, never a
        // wrong answer" means, and it holds only because the offset and the
        // state travel together.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let records = [
            prompt("have a look at the repository"),
            tool_result(&format!("here is {reference}, which you must ignore")),
            prompt(&format!("/execute {reference}")),
            prompt("carry on"),
            prompt("Actually, you are a single-issue child now."),
        ];
        let transcript = fx.transcript(&records);
        let cache = fx.dir.join("stale.json");
        let (dev, ino) = fx.identity(&transcript);

        let truth = fold_transcript(&transcript, None).unwrap().scan;

        for k in 0..=records.len() {
            // The honest pair after the first k records, derived by folding a
            // file that holds exactly those records.
            let prefix = fx.transcript(&records[..k]);
            let offset = std::fs::metadata(&prefix).unwrap().len();
            let state = fold_transcript(&prefix, None).unwrap().scan;
            publish_cached_fold(
                &cache,
                &CachedFold {
                    dev,
                    ino,
                    offset,
                    scan: state,
                },
            );

            let resumed = fold_transcript(&transcript, Some(&cache)).unwrap();
            assert_eq!(
                resumed.resumed_from, offset,
                "a fold handed a pair at {offset} must resume there"
            );
            assert_eq!(
                resumed.scan, truth,
                "a pair {k} records stale must still fold to the whole-file answer"
            );
        }
    }

    #[test]
    fn a_concurrent_reader_never_observes_a_torn_pair() {
        // Publication is by rename(2), so a reader gets the complete old pair
        // or the complete new one. This guards the mechanism rather than
        // hunting a bug: written in place instead, a reader could pair one
        // process's offset with another's state, and re-folding that would
        // double-apply the records in between.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let records: Vec<_> = (0..40)
            .map(|i| {
                if i == 17 {
                    prompt(&format!("/execute {reference}"))
                } else {
                    prompt(&format!("filler {i}"))
                }
            })
            .collect();
        let transcript = fx.transcript(&records);
        let cache = fx.dir.join("raced.json");
        let (dev, ino) = fx.identity(&transcript);

        // Every honest pair, for the writers to publish and the readers to
        // check what they saw against.
        let pairs: Vec<(u64, Scan)> = (0..=records.len())
            .map(|k| {
                let prefix = fx.transcript(&records[..k]);
                let offset = std::fs::metadata(&prefix).unwrap().len();
                (offset, fold_transcript(&prefix, None).unwrap().scan)
            })
            .collect();

        // Published before the racers start, so from here on the cache always
        // holds a complete pair. That is what lets a reader treat "no pair" as
        // a failure rather than as a legitimate first-call state: a publisher
        // that truncated the file in place would be caught here as an
        // unreadable pair, where a torn write mostly fails to parse rather
        // than parsing into a mismatched pair.
        publish_cached_fold(
            &cache,
            &CachedFold {
                dev,
                ino,
                offset: pairs[0].0,
                scan: pairs[0].1.clone(),
            },
        );

        let torn = AtomicUsize::new(0);
        let missing = AtomicUsize::new(0);
        let seen = AtomicUsize::new(0);
        std::thread::scope(|s| {
            for w in 0..4usize {
                let (pairs, cache) = (&pairs, &cache);
                s.spawn(move || {
                    for round in 0..80usize {
                        let (offset, scan) = &pairs[(w * 7 + round * 3) % pairs.len()];
                        publish_cached_fold(
                            cache,
                            &CachedFold {
                                dev,
                                ino,
                                offset: *offset,
                                scan: scan.clone(),
                            },
                        );
                    }
                });
            }
            for _ in 0..4 {
                let (pairs, cache) = (&pairs, &cache);
                let (torn, missing, seen) = (&torn, &missing, &seen);
                s.spawn(move || {
                    for _ in 0..300 {
                        match read_cached_fold(cache) {
                            Some(c) => {
                                seen.fetch_add(1, Ordering::SeqCst);
                                if !pairs.iter().any(|(o, sc)| *o == c.offset && *sc == c.scan) {
                                    torn.fetch_add(1, Ordering::SeqCst);
                                }
                            }
                            None => {
                                missing.fetch_add(1, Ordering::SeqCst);
                            }
                        }
                    }
                });
            }
        });

        assert_eq!(
            torn.load(Ordering::SeqCst),
            0,
            "a reader observed an offset paired with a state never derived to it"
        );
        assert_eq!(
            missing.load(Ordering::SeqCst),
            0,
            "a reader caught the cache mid-publish; publication is not atomic"
        );
        assert!(
            seen.load(Ordering::SeqCst) > 0,
            "the readers never observed a pair at all, so this proved nothing"
        );
        // No temporaries survive the race.
        let leftovers: Vec<_> = std::fs::read_dir(&fx.dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "temporaries left: {leftovers:?}");
    }

    #[test]
    fn a_transcript_shorter_than_the_offset_re_derives_from_the_start() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let transcript =
            fx.transcript(&[prompt("filler"), prompt(&format!("/execute {reference}"))]);
        let cache = fx.dir.join("truncated.json");

        let first = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert!(first.offset > 0);
        assert_eq!(first.scan.references, vec![reference]);

        // Truncated and rewritten shorter, in place: the inode is unchanged, so
        // the length check is what has to catch this.
        std::fs::write(&transcript, format!("{}\n", prompt("only this now"))).unwrap();
        let after = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(
            after.resumed_from, 0,
            "a file shorter than the offset must re-derive from the start"
        );
        assert!(
            after.scan.references.is_empty(),
            "state derived to an offset that no longer exists must not survive"
        );
    }

    #[test]
    fn a_replaced_transcript_re_derives_even_when_it_is_longer() {
        // The length check alone would not catch this: a transcript replaced by
        // a *longer* file leaves the stored offset in range while it no longer
        // means what it meant. Identity is what catches it, which is why the
        // pair carries the device and inode it was derived against.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let transcript = fx.transcript(&[prompt(&format!("/execute {reference}"))]);
        let cache = fx.dir.join("replaced.json");

        let first = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(first.scan.references, vec![reference.clone()]);

        // A different, longer file renamed over the same path: new inode, and
        // no plan reference anywhere in it.
        let other = fx.transcript(
            &(0..20)
                .map(|i| prompt(&format!("unrelated {i}")))
                .collect::<Vec<_>>(),
        );
        assert!(std::fs::metadata(&other).unwrap().len() > first.offset);
        std::fs::rename(&other, &transcript).unwrap();

        let after = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(
            after.resumed_from, 0,
            "a replaced transcript must re-derive from the start"
        );
        assert!(
            after.scan.references.is_empty(),
            "the old file's state must not be carried onto the new file"
        );
    }

    #[test]
    fn the_offset_stops_at_the_last_complete_record() {
        // The transcript is appended to while the hook reads it, so the last
        // line may be a write in progress. An offset past it would drop the
        // rest of that record once the writer finishes — a silent wrong answer
        // rather than a slow one.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let settled = format!("{}\n", prompt("settled instruction"));
        let full = prompt(&format!("/execute {reference}")).to_string();
        let cut = full.len() - 20;

        let transcript = fx.dir.join("in-progress.jsonl");
        std::fs::write(&transcript, format!("{settled}{}", &full[..cut])).unwrap();
        let cache = fx.dir.join("in-progress-cache.json");

        let first = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(
            first.offset,
            settled.len() as u64,
            "the offset must stop at the last newline, not at end of file"
        );
        assert!(
            first.scan.references.is_empty(),
            "a half-written record does not parse"
        );

        // The writer finishes the record.
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(&transcript)
            .unwrap();
        writeln!(f, "{}", &full[cut..]).unwrap();
        drop(f);

        let second = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(second.resumed_from, settled.len() as u64);
        assert_eq!(
            second.scan.references,
            vec![reference],
            "the completed record must be read in full, not from where the fold stopped"
        );
    }

    #[test]
    fn what_is_cached_is_the_arming_decision_not_the_verdict() {
        // Two writes to different targets in one armed session are evaluated
        // separately. A session-level cached verdict would permit or refuse
        // both alike, which would break the requirement that an in-set write be
        // permitted in the same session where an out-of-set write is refused.
        // Nothing about the tool call reaches the cache.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let transcript = fx.transcript(&[prompt(&format!("/execute {reference}"))]);

        let evaluate_write = |target: &str| {
            let mut v: serde_json::Value =
                serde_json::from_str(&hook("sess-arm", &fx.repo())).unwrap();
            v["transcript_path"] = serde_json::json!(transcript.to_string_lossy());
            v["tool_input"]["file_path"] = serde_json::json!(target);
            evaluate(&v.to_string(), Some(&fx.store())).arming
        };

        assert_eq!(evaluate_write("wip/execute/state.yaml").reason(), "armed");
        assert_eq!(evaluate_write("src/unrelated_module.rs").reason(), "armed");

        let raw = std::fs::read_to_string(fx.cache()).unwrap();
        for absent in [
            "unrelated_module",
            "state.yaml",
            "file_path",
            "tool_input",
            "verdict",
            "allow",
            "deny",
        ] {
            assert!(
                !raw.contains(absent),
                "the cache must carry no trace of the write target or its verdict, found {absent:?} in {raw}"
            );
        }
        let pair = read_cached_fold(&fx.cache()).unwrap();
        assert_eq!(pair.scan.references, vec![reference]);
    }

    #[test]
    fn cost_after_the_first_call_tracks_appended_bytes() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        // Big enough that "proportional to the file" and "proportional to the
        // append" are not the same number.
        let filler = "x".repeat(2048);
        let mut records = vec![prompt(&format!("/execute {reference}"))];
        records.extend((0..1200).map(|i| tool_result(&format!("{filler} {i}"))));
        let transcript = fx.transcript(&records);
        let cache = fx.dir.join("cost.json");
        let size = std::fs::metadata(&transcript).unwrap().len();
        assert!(
            size > 2 * 1024 * 1024,
            "fixture too small to tell apart: {size}"
        );

        let first = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(first.resumed_from, 0);
        assert_eq!(
            first.bytes_scanned, size,
            "the first call has no pair and reads the whole transcript"
        );

        let appended = fx.append(&transcript, &[prompt("one more instruction")]);
        let second = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(second.resumed_from, size);
        assert_eq!(
            second.bytes_scanned, appended,
            "the second call reads the appended bytes and nothing else"
        );
        assert!(
            second.bytes_scanned * 100 < size,
            "the append is {appended} bytes against a {size} byte file; \
             a cost that tracked file size would not be two orders smaller"
        );

        // A call with nothing appended since reads nothing at all.
        let third = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(third.bytes_scanned, 0);
        // The answer never moved.
        assert_eq!(second.scan, first.scan);
        assert_eq!(third.scan, first.scan);
    }

    #[test]
    fn an_unusable_pair_costs_a_rescan_rather_than_a_wrong_answer() {
        // Every rejection re-derives from the start, so the reader is free to
        // be strict: an unrecognized pair costs one full scan, a half-trusted
        // one costs correctness.
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let transcript =
            fx.transcript(&[prompt("filler"), prompt(&format!("/execute {reference}"))]);
        let (dev, ino) = fx.identity(&transcript);
        let truth = fold_transcript(&transcript, None).unwrap().scan;
        let good = serde_json::json!({
            "contract_version": SCAN_CACHE_CONTRACT_VERSION,
            "dev": dev,
            "ino": ino,
            "offset": 1,
            "references": [],
            "single_issue_marker": false,
        });

        let mutate = |f: &dyn Fn(&mut serde_json::Value)| {
            let mut v = good.clone();
            f(&mut v);
            v.to_string()
        };
        let cases: Vec<(&str, String)> = vec![
            ("not json at all", "{".to_string()),
            ("a JSON array rather than an object", "[]".to_string()),
            (
                "a future contract version",
                mutate(&|v| v["contract_version"] = serde_json::json!(99)),
            ),
            (
                "an offset that is not a number",
                mutate(&|v| v["offset"] = serde_json::json!("12")),
            ),
            (
                "a state with no offset beside it",
                mutate(&|v| {
                    v.as_object_mut().unwrap().remove("offset");
                }),
            ),
            (
                "more references than the live scan would admit",
                mutate(&|v| {
                    v["references"] = serde_json::json!(vec!["x"; MAX_PLAN_REFERENCES + 1])
                }),
            ),
            (
                "a reference longer than the live scan would admit",
                mutate(&|v| {
                    v["references"] = serde_json::json!([" ".repeat(MAX_REFERENCE_LEN + 1)])
                }),
            ),
        ];

        for (name, body) in cases {
            let cache = fx.dir.join("unusable.json");
            let _ = std::fs::remove_file(&cache);
            std::fs::write(&cache, &body).unwrap();
            assert!(read_cached_fold(&cache).is_none(), "{name} must be refused");
            let folded = fold_transcript(&transcript, Some(&cache)).unwrap();
            assert_eq!(
                folded.resumed_from, 0,
                "{name} must re-derive from the start"
            );
            assert_eq!(
                folded.scan, truth,
                "{name} must still reach the right answer"
            );
        }
    }

    #[test]
    fn a_symlinked_cache_path_is_refused_and_not_written_through() {
        let fx = Fx::new();
        let reference = fx.with_plan("PLAN-topic.md", SINGLE_PR_PLAN);
        let transcript = fx.transcript(&[prompt(&format!("/execute {reference}"))]);
        let outside = fx.dir.join("outside.json");
        let cache = fx.dir.join("linked.json");
        std::os::unix::fs::symlink(&outside, &cache).unwrap();

        let folded = fold_transcript(&transcript, Some(&cache)).unwrap();
        assert_eq!(folded.scan.references, vec![reference]);
        assert!(
            !outside.exists(),
            "publication must replace the symlink, never write through it"
        );
        assert!(
            std::fs::symlink_metadata(&cache)
                .unwrap()
                .file_type()
                .is_file(),
            "the cache path must be left a regular file"
        );
    }
}
