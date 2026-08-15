//! The `shirabe conflict` subcommand: the conflict recorder.
//!
//! One route a session takes to declare a departure from the workflow
//! **before** taking it. The recorder is the input that lets the adherence
//! determination tell a justified departure from a silent one: a delegation
//! shortfall covered by a record naming that step is `departed`, the same
//! shortfall uncovered is `non-conforming`.
//!
//! Three subcommands, one of which is the recorder:
//!
//! - [`ConflictCommands::Record`] — the recorder. Requires the instruction,
//!   the conflicting workflow step, and the intended course; refuses to write
//!   with any of the three empty. Writes the durable machine-local record and,
//!   when `--workflow` names an orchestration session, mirrors into that
//!   session's decision log best-effort.
//! - [`ConflictCommands::Notify`] — the surfacing path. A hook adapter: reads a
//!   Claude Code hook JSON on stdin and emits a user-facing `systemMessage`
//!   for records the author has not seen yet, so a recorded conflict reaches
//!   the author without the author querying the session. Always exits 0.
//! - [`ConflictCommands::Publish`] — the published form, for the home pull
//!   request body. Every reference it renders is routed through the existing
//!   fail-closed redaction control, so no path, repository name, or issue
//!   number belonging to a private repository reaches a public surface.
//!
//! # The store, and why it is not the runtime dir
//!
//! Records live in `$XDG_STATE_HOME/shirabe/conflicts/<session-id>.jsonl`,
//! falling back to `~/.local/state` when the variable is unset. One
//! append-only JSON-per-line file per session, directory `0700`, files
//! `0600`.
//!
//! [`crate::work_summary`] resolves *its* store from `XDG_RUNTIME_DIR` first.
//! That is right for what it stores and wrong for what this stores. A
//! work-in-flight snapshot describes the session that is running now and has
//! no meaning once the machine reboots; a conflict record is an audit record,
//! and an audit record that does not survive a reboot is not an audit record.
//! The runtime dir is therefore deliberately not consulted here — see
//! [`store_dir_from`].
//!
//! # The mirror vehicle
//!
//! The mirror is `koto decisions record`, not `koto overrides record`. The
//! override verb exits non-zero with "workflow not found" when no session
//! exists — exactly the case the requirement names — and it requires naming a
//! gate, which a conflict need not be against. The mirror discards the child's
//! output entirely (koto floods stderr with migration notices) and ignores its
//! exit status: a mirror failure never fails the local write.
//!
//! # Redaction
//!
//! The published block reuses [`redacted_label`] and its
//! [`VisibilityResolver`], which is fail-closed: a repository that resolves
//! private, or that cannot be resolved at all, renders as an opaque id
//! carrying no owner, repo, path, or number. The verbatim instruction is
//! machine-local only and never published; the published block carries its
//! digest so a reviewer can match a published line back to the local record.
//!
//! Env seams: `SHIRABE_CONFLICT_DIR` (override the store dir), `KOTO_BIN`
//! (override the `koto` binary path), `SHIRABE_CONFLICT_NOW` (override "now"
//! as epoch seconds).

use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command as ProcCommand, ExitCode, Stdio};
use std::sync::LazyLock;
use std::time::{SystemTime, UNIX_EPOCH};

use clap::{Args, Subcommand};
use regex::Regex;
use rustix::fs::{flock, FlockOperation};
use sha2::{Digest, Sha256};
use shirabe_validate::{
    parse_cross_repo_ref, redacted_label, GhSubprocessClient, GhVisibilityResolver, Visibility,
    VisibilityResolver,
};

/// Record schema tag, written into every line. The determination matches on
/// it, so a future shape change bumps this rather than reinterpreting old
/// lines.
pub(crate) const CONFLICT_SCHEMA: &str = "shirabe.conflict/1";

/// Marker on the author-facing block emitted by `notify`.
const LOCAL_MARKER: &str = "=== WORKFLOW CONFLICT RECORDED ===";

/// Marker on the published block emitted by `publish`.
const PUBLISHED_MARKER: &str = "=== WORKFLOW CONFLICTS ===";

/// Per-field character cap on a stored record. The instruction is
/// attacker-influenceable free text and the store is append-only, so the
/// bound is stated here rather than left to the caller.
const MAX_FIELD_CHARS: usize = 600;

/// Byte cap on a single read of a session's record file. A read that would
/// exceed it is truncated at a line boundary rather than refused, so a large
/// store degrades to a partial render and never to an unbounded read.
const MAX_STORE_READ_BYTES: u64 = 1 << 20;

/// Session ids are used as filenames; keep them to a filename-safe charset.
/// The leading character must be alphanumeric, which also rules out `.` and
/// `..` and any leading-dash name.
static SID_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$").unwrap());

/// Workflow names reach a subprocess argv. Constrain them to koto's own name
/// charset so a crafted value cannot become a path — and require an
/// alphanumeric first character so it cannot become a **flag**: a name of
/// `--with-data` would otherwise land in argv where koto reads an option.
static WF_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$").unwrap());

static ANSI_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\x1b\[[0-9;?]*[A-Za-z]").unwrap());

/// A token that ends in a short file extension (`PLAN-x.md`). Reference-shaped
/// even without a slash, because a bare filename is still a path component
/// that may belong to a private repository.
static EXT_TAIL_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\.[A-Za-z0-9]{1,5}$").unwrap());

// --- CLI surface -----------------------------------------------------------

#[derive(Args)]
pub struct ConflictArgs {
    #[command(subcommand)]
    pub command: ConflictCommands,
}

#[derive(Subcommand)]
pub enum ConflictCommands {
    /// Record a departure from the workflow before taking it. Requires the
    /// instruction that conflicts, the workflow step it conflicts with, and
    /// the course intended instead; refuses with any of the three empty.
    /// Writes the durable machine-local record, and when `--workflow` names
    /// an orchestration session also mirrors into that session's decision
    /// log, best-effort.
    Record(RecordArgs),
    /// Surfacing hook adapter. Reads a Claude Code hook JSON on stdin and
    /// emits a user-facing `systemMessage` for this session's records the
    /// author has not seen yet. Always exits 0.
    Notify,
    /// Render the published, F1-redacted conflict block for the home pull
    /// request body. Every reference is routed through the fail-closed
    /// redaction control; the verbatim instruction is never published.
    Publish(PublishArgs),
}

#[derive(Args)]
pub struct RecordArgs {
    /// The instruction that conflicts with the workflow, verbatim.
    #[arg(long)]
    pub instruction: String,
    /// The workflow step the instruction conflicts with. This is what ties a
    /// record to a specific shortfall; a record naming only an instruction
    /// could excuse an arbitrary number of silent drops.
    #[arg(long)]
    pub step: String,
    /// The course the session intends to take instead.
    #[arg(long)]
    pub course: String,
    /// Session id to record under. When omitted, read from
    /// `CLAUDE_CODE_SESSION_ID` (then `CLAUDE_SESSION_ID`).
    #[arg(long)]
    pub session: Option<String>,
    /// Orchestration session (koto workflow) to mirror into. When omitted,
    /// only the local record is written — the route works with no session.
    #[arg(long)]
    pub workflow: Option<String>,
    /// Cross-repo `owner/repo:path` reference the conflict is about, if any.
    /// Rendered through the redaction control in the published form.
    #[arg(long)]
    pub reference: Option<String>,
    /// Issue number the conflict is about, if any. Published only when its
    /// repository resolves public.
    #[arg(long)]
    pub number: Option<u64>,
}

#[derive(Args)]
pub struct PublishArgs {
    /// Session ids whose records to publish. Repeatable: the determination
    /// publishes the orchestrator's records and each child's, because a
    /// delegated child records under its own session identity. When omitted,
    /// resolves the current session from the environment.
    #[arg(long)]
    pub session: Vec<String>,
}

/// Entry point for `shirabe conflict`.
///
/// Exit codes: `record` exits 2 when it refuses (a required field is empty,
/// or the session id is unusable) and 1 when the local write fails — the
/// caller must know the record does not exist before it departs. `notify` and
/// `publish` always exit 0; both are fail-safe read paths, and `notify` runs
/// in a hook context where a non-zero exit would abort the turn.
pub fn run(command: &ConflictCommands) -> ExitCode {
    match command {
        ConflictCommands::Record(args) => cmd_record(args),
        ConflictCommands::Notify => {
            cmd_notify();
            ExitCode::SUCCESS
        }
        ConflictCommands::Publish(args) => {
            cmd_publish(&args.session);
            ExitCode::SUCCESS
        }
    }
}

// --- storage ---------------------------------------------------------------

/// Resolve the store directory from the three inputs that decide it.
///
/// Taken as parameters rather than read from the environment so the choice is
/// testable without mutating process env. Note what is **absent**:
/// `XDG_RUNTIME_DIR` is deliberately not an input. A runtime directory is
/// cleared on reboot, and a conflict record is an audit record that must
/// outlive the machine's uptime. [`crate::work_summary`] prefers the runtime
/// dir for its own store, and that is correct there — it holds a snapshot of
/// work in flight, which has no meaning after a reboot.
pub(crate) fn store_dir_from(
    explicit: Option<&str>,
    state_home: Option<&str>,
    home: Option<&str>,
) -> PathBuf {
    if let Some(d) = explicit.filter(|s| !s.is_empty()) {
        return PathBuf::from(d);
    }
    let base = match state_home.filter(|s| !s.is_empty()) {
        Some(s) => PathBuf::from(s),
        None => PathBuf::from(home.unwrap_or("")).join(".local/state"),
    };
    base.join("shirabe").join("conflicts")
}

/// The store directory as resolved from this process's environment.
pub(crate) fn store_dir() -> PathBuf {
    store_dir_from(
        nonempty_env("SHIRABE_CONFLICT_DIR").as_deref(),
        nonempty_env("XDG_STATE_HOME").as_deref(),
        nonempty_env("HOME").as_deref(),
    )
}

/// Create the store directory owner-only. Returns `false` when the directory
/// exists as a symlink (refused) or cannot be created.
fn ensure_store(dir: &Path) -> bool {
    if let Ok(meta) = fs::symlink_metadata(dir) {
        if meta.file_type().is_symlink() {
            return false;
        }
    }
    if fs::create_dir_all(dir).is_err() {
        return false;
    }
    let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
    true
}

/// Refuse to operate through a symlinked per-session file. The per-session
/// files are opened by name, which would otherwise follow a symlink out of
/// the store.
fn refuse_symlinked_files(dir: &Path, sid: &str) -> bool {
    for ext in ["jsonl", "lock", "surfaced"] {
        let p = dir.join(format!("{sid}.{ext}"));
        if let Ok(meta) = fs::symlink_metadata(&p) {
            if meta.file_type().is_symlink() {
                return false;
            }
        }
    }
    true
}

pub(crate) fn records_path(dir: &Path, sid: &str) -> PathBuf {
    dir.join(format!("{sid}.jsonl"))
}

fn lock_path(dir: &Path, sid: &str) -> PathBuf {
    dir.join(format!("{sid}.lock"))
}

fn surfaced_path(dir: &Path, sid: &str) -> PathBuf {
    dir.join(format!("{sid}.surfaced"))
}

/// Run `f` under the per-session advisory lock. Concurrent recorders in one
/// session (an orchestrator and a hook, say) append whole lines rather than
/// interleaving partial ones; a record can exceed the atomic-append size, so
/// `O_APPEND` alone is not enough.
fn with_lock<T>(dir: &Path, sid: &str, f: impl FnOnce() -> T) -> Option<T> {
    let file = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .open(lock_path(dir, sid))
        .ok()?;
    flock(&file, FlockOperation::LockExclusive).ok()?;
    let out = f();
    let _ = flock(&file, FlockOperation::Unlock);
    Some(out)
}

/// Append one already-serialized record line. Append-only: the file is opened
/// with `O_APPEND` and never truncated, and is created `0600`.
fn append_line(dir: &Path, sid: &str, line: &str) -> Result<(), String> {
    let path = records_path(dir, sid);
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(&path)
        .map_err(|e| format!("cannot open {}: {e}", path.display()))?;
    // Re-assert the mode: a file that predates this run (or a umask that
    // widened it) must still end up owner-only.
    let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    f.write_all(line.as_bytes())
        .and_then(|_| f.write_all(b"\n"))
        .map_err(|e| format!("cannot append to {}: {e}", path.display()))
}

// --- the record ------------------------------------------------------------

/// One conflict record, as read back from the store.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ConflictRecord {
    pub recorded_at: String,
    pub session: String,
    /// The verbatim conflicting instruction. Machine-local only — never
    /// published.
    pub instruction: String,
    /// The workflow step the instruction conflicts with.
    pub step: String,
    /// The course taken instead.
    pub course: String,
    pub reference: Option<String>,
    pub number: Option<u64>,
    /// Opaque, non-sensitive id for this record, derived from the instruction
    /// digest. Safe to render regardless of visibility.
    pub node_id: String,
    /// Digest of the verbatim instruction, so a published line can be matched
    /// back to the local record without carrying its text.
    pub instruction_digest: String,
}

impl ConflictRecord {
    fn from_json(v: &serde_json::Value) -> Option<ConflictRecord> {
        if v.get("schema").and_then(|x| x.as_str())? != CONFLICT_SCHEMA {
            return None;
        }
        let s = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
        Some(ConflictRecord {
            recorded_at: s("recorded_at"),
            session: s("session"),
            instruction: s("instruction"),
            step: s("step"),
            course: s("course"),
            reference: v
                .get("reference")
                .and_then(|x| x.as_str())
                .map(|x| x.to_string()),
            number: v.get("number").and_then(|x| x.as_u64()),
            node_id: s("node_id"),
            instruction_digest: s("instruction_digest"),
        })
    }
}

/// Read a session's records, byte-capped. A read that would exceed
/// [`MAX_STORE_READ_BYTES`] keeps the leading whole lines and drops the rest;
/// an unparseable line is skipped rather than failing the read.
pub(crate) fn read_records(dir: &Path, sid: &str) -> Vec<ConflictRecord> {
    read_records_from(dir, sid, 0).1
}

/// Read a session's records starting at `offset` bytes, returning the byte
/// length actually consumed alongside the parsed records. `notify` uses the
/// offset to emit only what the author has not seen.
fn read_records_from(dir: &Path, sid: &str, offset: u64) -> (u64, Vec<ConflictRecord>) {
    let path = records_path(dir, sid);
    let Ok(meta) = fs::metadata(&path) else {
        return (0, Vec::new());
    };
    if !meta.file_type().is_file() {
        return (0, Vec::new());
    }
    let len = meta.len();
    // A file shorter than the stored offset means the store was replaced;
    // re-read from the start rather than trusting the stale offset.
    let start = if offset > len { 0 } else { offset };
    let Ok(mut f) = fs::File::open(&path) else {
        return (0, Vec::new());
    };
    if std::io::Seek::seek(&mut f, std::io::SeekFrom::Start(start)).is_err() {
        return (0, Vec::new());
    }
    let mut buf = Vec::new();
    if f.take(MAX_STORE_READ_BYTES).read_to_end(&mut buf).is_err() {
        return (start, Vec::new());
    }
    // Keep whole lines only: a truncated tail is dropped, so the cap can never
    // yield a half-parsed record.
    let consumed = match buf.iter().rposition(|b| *b == b'\n') {
        Some(i) => i as u64 + 1,
        None => 0,
    };
    let text = String::from_utf8_lossy(&buf[..consumed as usize]).into_owned();
    let mut out = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
            if let Some(r) = ConflictRecord::from_json(&v) {
                out.push(r);
            }
        }
    }
    (start + consumed, out)
}

// --- record ----------------------------------------------------------------

/// The refusal the recorder returns when a required field is empty. Named so
/// the message is stated once and asserted on in tests.
fn empty_field_refusal(field: &str) -> String {
    format!(
        "shirabe conflict record: refusing to write: --{field} is empty. \
         A conflict record must name the instruction, the workflow step it \
         conflicts with, and the intended course; a record missing any of the \
         three cannot be matched to the departure it is meant to cover."
    )
}

fn cmd_record(args: &RecordArgs) -> ExitCode {
    let instruction = args.instruction.trim();
    let step = args.step.trim();
    let course = args.course.trim();
    for (name, value) in [
        ("instruction", instruction),
        ("step", step),
        ("course", course),
    ] {
        if value.is_empty() {
            eprintln!("{}", empty_field_refusal(name));
            return ExitCode::from(2);
        }
    }

    let Some(sid) = resolve_session(args.session.as_deref()) else {
        eprintln!(
            "shirabe conflict record: refusing to write: no usable session id \
             (pass --session, or set CLAUDE_CODE_SESSION_ID)."
        );
        return ExitCode::from(2);
    };

    // A malformed --reference is refused rather than stored: an unparseable
    // reference cannot be routed through the redaction control later, and a
    // reference that reaches the published block unredacted is the leak this
    // whole path exists to prevent.
    if let Some(r) = args.reference.as_deref() {
        if let Err(e) = parse_cross_repo_ref(r) {
            eprintln!("shirabe conflict record: refusing to write: --reference {e}");
            return ExitCode::from(2);
        }
    }

    let dir = store_dir();
    let record = build_record(
        &sid,
        instruction,
        step,
        course,
        args.reference.as_deref(),
        args.number,
    );

    match write_record(&dir, &sid, &record) {
        Ok(()) => {}
        Err(e) => {
            eprintln!("shirabe conflict record: {e}");
            return ExitCode::from(1);
        }
    }

    // Best-effort mirror. Never gates the local write: by the time we are here
    // the durable record exists, and a session that cannot be reached is
    // exactly the case the local store covers.
    let mirrored = match args.workflow.as_deref() {
        Some(wf) => mirror_to_session(&koto_bin(), wf, &record),
        None => false,
    };

    println!("{LOCAL_MARKER}");
    println!("{}", record_line(&record));
    println!("recorded to {}", records_path(&dir, &sid).display());
    if args.workflow.is_some() {
        println!(
            "orchestration mirror: {}",
            if mirrored {
                "recorded"
            } else {
                "unavailable (local record stands)"
            }
        );
    }
    ExitCode::SUCCESS
}

/// Assemble the record. Fields are sanitized (control bytes and ANSI stripped,
/// capped) before they reach the store, so nothing downstream has to assume a
/// hostile instruction is terminal-safe.
fn build_record(
    sid: &str,
    instruction: &str,
    step: &str,
    course: &str,
    reference: Option<&str>,
    number: Option<u64>,
) -> ConflictRecord {
    let instruction = sanitize(instruction);
    let digest = sha256_hex(instruction.as_bytes());
    ConflictRecord {
        recorded_at: iso_now(),
        session: sid.to_string(),
        instruction,
        step: sanitize(step),
        course: sanitize(course),
        reference: reference.map(|s| s.to_string()),
        number,
        node_id: format!("conflict-{}", &digest[..8]),
        instruction_digest: digest,
    }
}

/// Serialize and append one record under the session lock.
fn write_record(dir: &Path, sid: &str, record: &ConflictRecord) -> Result<(), String> {
    if !ensure_store(dir) {
        return Err(format!(
            "cannot use conflict store at {} (missing, or a symlink)",
            dir.display()
        ));
    }
    if !refuse_symlinked_files(dir, sid) {
        return Err(format!(
            "refusing a symlinked per-session file under {}",
            dir.display()
        ));
    }
    // Assembled with serde_json, never interpolated: the instruction is
    // free text the session did not author and must stay a JSON string value.
    let value = serde_json::json!({
        "schema": CONFLICT_SCHEMA,
        "recorded_at": record.recorded_at,
        "session": record.session,
        "cwd": std::env::current_dir().map(|p| p.display().to_string()).unwrap_or_default(),
        "instruction": record.instruction,
        "step": record.step,
        "course": record.course,
        "reference": record.reference,
        "number": record.number,
        "node_id": record.node_id,
        "instruction_digest": record.instruction_digest,
    });
    let line =
        serde_json::to_string(&value).map_err(|e| format!("cannot serialize record: {e}"))?;
    match with_lock(dir, sid, || append_line(dir, sid, &line)) {
        Some(r) => r,
        None => Err(format!(
            "cannot lock the conflict store at {}",
            dir.display()
        )),
    }
}

/// Mirror the record into the orchestration session's decision log.
///
/// `koto decisions record <WF> --with-data <JSON>` — the decision verb, not
/// the override verb: `koto overrides record` exits non-zero when no session
/// exists and requires naming a gate, neither of which fits a conflict raised
/// before or outside a session. Output is discarded on both channels (koto
/// writes migration notices to stderr on every invocation) and the exit status
/// is ignored. Returns whether the child reported success, for the confirmation
/// line only.
///
/// `bin` is a parameter rather than an env read so the failure path — a `koto`
/// that is absent, or that exits non-zero because no session exists — is
/// exercised by a test without mutating process env.
fn mirror_to_session(bin: &str, workflow: &str, record: &ConflictRecord) -> bool {
    if !WF_RE.is_match(workflow) {
        return false;
    }
    let data = serde_json::json!({
        "choice": record.course,
        "rationale": format!("workflow conflict at step {}", record.step),
        "conflict_step": record.step,
        "conflict_instruction": record.instruction,
        "conflict_node_id": record.node_id,
        "schema": CONFLICT_SCHEMA,
    });
    let Ok(payload) = serde_json::to_string(&data) else {
        return false;
    };
    ProcCommand::new(bin)
        .arg("decisions")
        .arg("record")
        .arg(workflow)
        .arg("--with-data")
        .arg(payload)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

// --- notify ----------------------------------------------------------------

/// Surfacing path. Reads the hook JSON on stdin for its `session_id`, emits a
/// `systemMessage` carrying the records written since the last emission, and
/// advances the surfaced offset. Emits nothing when there is nothing new, so a
/// hook firing on every turn is silent between conflicts.
fn cmd_notify() {
    let mut input = String::new();
    let _ = std::io::stdin().read_to_string(&mut input);
    let Ok(v) = serde_json::from_str::<serde_json::Value>(&input) else {
        return;
    };
    let sid = match v.get("session_id").and_then(|x| x.as_str()) {
        Some(s) if SID_RE.is_match(s) => s.to_string(),
        _ => return,
    };
    let dir = store_dir();
    if !refuse_symlinked_files(&dir, &sid) {
        return;
    }
    let offset = read_surfaced_offset(&dir, &sid);
    let (new_offset, records) = read_records_from(&dir, &sid, offset);
    if records.is_empty() {
        return;
    }
    let block = local_block(&records);
    write_surfaced_offset(&dir, &sid, new_offset);
    // Carried as a JSON string value, so a crafted instruction cannot escape
    // the object or inject a terminal control sequence.
    let out = serde_json::json!({ "systemMessage": block });
    if let Ok(s) = serde_json::to_string(&out) {
        println!("{s}");
    }
}

fn read_surfaced_offset(dir: &Path, sid: &str) -> u64 {
    fs::read_to_string(surfaced_path(dir, sid))
        .ok()
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0)
}

fn write_surfaced_offset(dir: &Path, sid: &str, offset: u64) {
    if !ensure_store(dir) {
        return;
    }
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .mode(0o600)
        .open(surfaced_path(dir, sid))
    {
        let _ = write!(f, "{offset}");
    }
}

/// The author-facing block. Machine-local, so the instruction appears in the
/// clear — the store never crosses a visibility boundary and the author is the
/// person who needs to see what the session was told.
fn local_block(records: &[ConflictRecord]) -> String {
    let mut out = String::from(LOCAL_MARKER);
    for r in records {
        out.push('\n');
        out.push_str(&record_line(r));
    }
    out
}

fn record_line(r: &ConflictRecord) -> String {
    format!(
        "{} | {} | step: {} | course: {} | instruction: {}",
        r.recorded_at, r.node_id, r.step, r.course, r.instruction
    )
}

// --- publish ---------------------------------------------------------------

fn cmd_publish(sessions: &[String]) {
    let sids: Vec<String> = if sessions.is_empty() {
        resolve_session(None).into_iter().collect()
    } else {
        sessions
            .iter()
            .filter(|s| SID_RE.is_match(s))
            .cloned()
            .collect()
    };
    let dir = store_dir();
    let mut records = Vec::new();
    for sid in &sids {
        records.extend(read_records(&dir, sid));
    }
    if records.is_empty() {
        return;
    }
    let client = GhSubprocessClient::new();
    let resolver = GhVisibilityResolver::new(&client);
    print!("{}", published_block(&records, &resolver));
}

/// Render the published block.
///
/// Every identifier that reaches this output is either a fixed literal, a
/// timestamp, an opaque node id, or a token that resolved to a **public**
/// repository through [`redacted_label`] / [`VisibilityResolver`]. The verbatim
/// instruction is not published at all — only its digest, which is what lets a
/// reviewer match a published line to the machine-local record without the
/// text crossing the boundary.
pub(crate) fn published_block(
    records: &[ConflictRecord],
    resolver: &dyn VisibilityResolver,
) -> String {
    let mut out = String::from(PUBLISHED_MARKER);
    out.push('\n');
    for r in records {
        let reference = match (&r.reference, r.number) {
            (Some(reference), number) => {
                redact_reference_field(reference, number, &r.node_id, resolver)
            }
            (None, _) => r.node_id.clone(),
        };
        out.push_str(&format!(
            "{} | {} | step: {} | course: {} | instruction withheld (sha256:{})\n",
            r.recorded_at,
            reference,
            scrub_public(&r.step, resolver),
            scrub_public(&r.course, resolver),
            &r.instruction_digest[..12.min(r.instruction_digest.len())],
        ));
    }
    out
}

/// Redact a record's structured `reference` field. Delegates to
/// [`redacted_label`] when a number is present (its exact contract) and to the
/// same fail-closed [`VisibilityResolver`] when it is not.
fn redact_reference_field(
    reference: &str,
    number: Option<u64>,
    node_id: &str,
    resolver: &dyn VisibilityResolver,
) -> String {
    let Ok(parsed) = parse_cross_repo_ref(reference) else {
        return node_id.to_string();
    };
    match number {
        Some(n) => redacted_label(&parsed, n, node_id, resolver),
        None => match resolver.visibility(&parsed.slug()) {
            Visibility::Public => parsed.slug_and_path(),
            Visibility::Private => node_id.to_string(),
        },
    }
}

/// Scrub free text for a public surface.
///
/// The rule is set membership, not judgment: a whitespace-delimited token that
/// looks like a path, a repository slug, or an issue number survives **only**
/// when it resolves to a public repository through the fail-closed resolver.
/// Everything else that is reference-shaped becomes an opaque id derived from
/// the token itself. Ordinary prose words are untouched.
///
/// The rule is deliberately over-broad at the edges — a version string like
/// `v1.2` reads as reference-shaped and gets redacted. That is the correct
/// direction to be wrong in: a redacted version number costs a reader nothing,
/// a leaked private path costs the leak this control exists to prevent.
pub(crate) fn scrub_public(text: &str, resolver: &dyn VisibilityResolver) -> String {
    let text = sanitize(text);
    let mut out: Vec<String> = Vec::new();
    for token in text.split_whitespace() {
        let (lead, core, trail) = split_edges(token);
        if !is_reference_shaped(core) {
            out.push(token.to_string());
            continue;
        }
        match resolve_public_token(core, resolver) {
            Some(public) => out.push(format!("{lead}{public}{trail}")),
            None => out.push(format!("{lead}{}{trail}", opaque_id(core))),
        }
    }
    out.join(" ")
}

/// Leading/trailing punctuation that surrounds a token in prose but is not
/// part of the identifier.
fn split_edges(token: &str) -> (&str, &str, &str) {
    let lead_len = token
        .find(|c: char| !matches!(c, '(' | '[' | '{' | '"' | '\''))
        .unwrap_or(token.len());
    let (lead, rest) = token.split_at(lead_len);
    let trail_start = rest
        .rfind(|c: char| !matches!(c, ')' | ']' | '}' | '"' | '\'' | ',' | ';' | ':'))
        .map(|i| i + rest[i..].chars().next().map(|c| c.len_utf8()).unwrap_or(1))
        .unwrap_or(0);
    let (core, trail) = rest.split_at(trail_start);
    (lead, core, trail)
}

/// Whether a token could carry a path, a repository name, or an issue number.
fn is_reference_shaped(core: &str) -> bool {
    core.contains('/') || core.contains('#') || EXT_TAIL_RE.is_match(core)
}

/// Resolve a reference-shaped token to its public rendering, or `None` when it
/// is private, unresolvable, or not a reference at all. `None` is the
/// fail-closed answer and the common one.
fn resolve_public_token(core: &str, resolver: &dyn VisibilityResolver) -> Option<String> {
    let (body, number) = match core.rsplit_once('#') {
        Some((b, n)) => (b, n.parse::<u64>().ok()?),
        None => (core, 0),
    };
    let has_number = core.contains('#');
    // A bare `#42` names no repository, so its visibility cannot be resolved.
    if body.is_empty() {
        return None;
    }
    if body.contains(':') {
        let parsed = parse_cross_repo_ref(body).ok()?;
        let node = opaque_id(core);
        if has_number {
            let label = redacted_label(&parsed, number, &node, resolver);
            return if label == node { None } else { Some(label) };
        }
        return match resolver.visibility(&parsed.slug()) {
            Visibility::Public => Some(parsed.slug_and_path()),
            Visibility::Private => None,
        };
    }
    // No colon: the only shape that can resolve is a bare `owner/repo` slug.
    // Anything else (a repo-relative path, a bare filename) has no resolvable
    // owner and is redacted.
    let mut parts = body.split('/');
    let owner = parts.next()?;
    let repo = parts.next()?;
    if parts.next().is_some() {
        return None;
    }
    // Reuse the reference validator for the owner/repo charset check by
    // parsing a synthetic reference; a slug that fails it is not a slug.
    parse_cross_repo_ref(&format!("{owner}/{repo}:x")).ok()?;
    match resolver.visibility(body) {
        Visibility::Public => Some(core.to_string()),
        Visibility::Private => None,
    }
}

/// A stable, non-sensitive stand-in for a redacted token. Derived from the
/// token so the same private path redacts to the same id everywhere, which
/// keeps a published block readable without revealing what was redacted.
fn opaque_id(token: &str) -> String {
    format!("ref-{}", &sha256_hex(token.as_bytes())[..8])
}

// --- helpers ---------------------------------------------------------------

/// The `koto` binary the mirror invokes. `KOTO_BIN` overrides it.
fn koto_bin() -> String {
    nonempty_env("KOTO_BIN").unwrap_or_else(|| "koto".to_string())
}

fn nonempty_env(key: &str) -> Option<String> {
    match std::env::var(key) {
        Ok(v) if !v.is_empty() => Some(v),
        _ => None,
    }
}

/// Resolve the session id: the explicit flag, then the Claude Code session
/// env vars. Returns `None` when nothing usable is available.
fn resolve_session(explicit: Option<&str>) -> Option<String> {
    let candidate = explicit
        .map(|s| s.to_string())
        .or_else(|| nonempty_env("CLAUDE_CODE_SESSION_ID"))
        .or_else(|| nonempty_env("CLAUDE_SESSION_ID"))?;
    if SID_RE.is_match(&candidate) && candidate != "." && candidate != ".." {
        Some(candidate)
    } else {
        None
    }
}

/// Strip ANSI sequences and control bytes, collapse the cell separator, and
/// cap the length. Applied on the way into the store so every reader — the
/// author-facing block, the published block, the determination — gets text
/// that is already terminal-safe.
fn sanitize(s: &str) -> String {
    let no_ansi = ANSI_RE.replace_all(s, "");
    let mut out: String = no_ansi
        .chars()
        .map(|c| if c == '\n' || c == '\t' { ' ' } else { c })
        .filter(|&c| {
            let u = c as u32;
            !(u <= 0x1F || u == 0x7F || (0x80..=0x9F).contains(&u))
        })
        .collect();
    out = out.replace('|', "/");
    out = out.split_whitespace().collect::<Vec<_>>().join(" ");
    if out.chars().count() > MAX_FIELD_CHARS {
        out = out.chars().take(MAX_FIELD_CHARS).collect();
    }
    out
}

fn sha256_hex(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    let digest = h.finalize();
    let mut s = String::with_capacity(64);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(s, "{:02x}", b);
    }
    s
}

/// ISO-8601 UTC stamp. `SHIRABE_CONFLICT_NOW` overrides the clock for tests.
/// Formatted without `chrono`, matching [`crate::work_summary`]'s offline dep
/// budget.
fn iso_now() -> String {
    let secs = nonempty_env("SHIRABE_CONFLICT_NOW")
        .and_then(|v| v.trim().parse::<i64>().ok())
        .unwrap_or_else(|| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0)
        });
    format_iso_utc(secs)
}

fn format_iso_utc(epoch: i64) -> String {
    let days = epoch.div_euclid(86_400);
    let sod = epoch.rem_euclid(86_400);
    let (hh, mm, ss) = (sod / 3600, (sod % 3600) / 60, sod % 60);
    let (y, m, d) = civil_from_days(days);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, m, d, hh, mm, ss)
}

/// Howard Hinnant's civil-from-days.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (y + if m <= 2 { 1 } else { 0 }, m, d)
}

// --- tests -----------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Visibility stub. Any slug not listed resolves neither public nor
    /// private by name — it falls through to `Private`, which is the
    /// fail-closed answer the real resolver gives for an unresolvable repo.
    struct StubResolver {
        public: Vec<&'static str>,
    }

    impl VisibilityResolver for StubResolver {
        fn visibility(&self, slug: &str) -> Visibility {
            if self.public.contains(&slug) {
                Visibility::Public
            } else {
                Visibility::Private
            }
        }
    }

    fn tmpdir() -> PathBuf {
        static N: AtomicUsize = AtomicUsize::new(0);
        let n = N.fetch_add(1, Ordering::SeqCst);
        let d = std::env::temp_dir().join(format!("cr-test-{}-{}", std::process::id(), n));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn rec(step: &str, course: &str) -> ConflictRecord {
        build_record("s1", "the instruction", step, course, None, None)
    }

    // --- the three required fields ---

    #[test]
    fn refusal_names_each_empty_field() {
        for f in ["instruction", "step", "course"] {
            let msg = empty_field_refusal(f);
            assert!(msg.contains(&format!("--{f} is empty")), "{msg}");
        }
    }

    #[test]
    fn record_refuses_with_any_field_empty() {
        for (i, s, c) in [
            ("", "step", "course"),
            ("instr", "", "course"),
            ("instr", "step", ""),
            ("   ", "step", "course"),
        ] {
            let args = RecordArgs {
                instruction: i.to_string(),
                step: s.to_string(),
                course: c.to_string(),
                session: Some("sess-1".to_string()),
                workflow: None,
                reference: None,
                number: None,
            };
            assert_eq!(
                cmd_record(&args),
                ExitCode::from(2),
                "expected a refusal for ({i:?}, {s:?}, {c:?})"
            );
        }
    }

    #[test]
    fn record_with_all_three_fields_is_written() {
        let dir = tmpdir();
        let r = rec("delegate every issue", "implement issue 4 inline");
        write_record(&dir, "sess-1", &r).unwrap();
        let back = read_records(&dir, "sess-1");
        assert_eq!(back.len(), 1);
        assert_eq!(back[0].step, "delegate every issue");
        assert_eq!(back[0].course, "implement issue 4 inline");
        assert_eq!(back[0].instruction, "the instruction");
    }

    // --- the store ---

    #[test]
    fn store_is_state_home_not_runtime_dir() {
        // The durability requirement, stated as a test: the resolver takes no
        // runtime-dir input at all, so a state home is what decides the path.
        let d = store_dir_from(None, Some("/x/state"), Some("/home/u"));
        assert_eq!(d, PathBuf::from("/x/state/shirabe/conflicts"));
        let fallback = store_dir_from(None, None, Some("/home/u"));
        assert_eq!(
            fallback,
            PathBuf::from("/home/u/.local/state/shirabe/conflicts")
        );
        let explicit = store_dir_from(Some("/tmp/c"), Some("/x/state"), Some("/home/u"));
        assert_eq!(explicit, PathBuf::from("/tmp/c"));
        // An empty state home is not a state home.
        assert_eq!(
            store_dir_from(None, Some(""), Some("/home/u")),
            PathBuf::from("/home/u/.local/state/shirabe/conflicts")
        );
    }

    #[test]
    fn store_is_append_only_and_owner_only() {
        let dir = tmpdir().join("store");
        write_record(&dir, "sess-1", &rec("step-a", "course-a")).unwrap();
        write_record(&dir, "sess-1", &rec("step-b", "course-b")).unwrap();
        let path = records_path(&dir, "sess-1");
        let text = fs::read_to_string(&path).unwrap();
        assert_eq!(text.lines().count(), 2, "append-only: {text}");
        assert!(text.contains("step-a") && text.contains("step-b"));

        let fmode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(fmode, 0o600, "file mode {fmode:o}");
        let dmode = fs::metadata(&dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(dmode, 0o700, "dir mode {dmode:o}");

        let back = read_records(&dir, "sess-1");
        assert_eq!(back.len(), 2);
        assert_eq!(back[0].step, "step-a");
        assert_eq!(back[1].step, "step-b");
    }

    #[test]
    fn store_is_keyed_by_session() {
        let dir = tmpdir().join("store");
        write_record(&dir, "parent", &rec("parent-step", "parent-course")).unwrap();
        write_record(&dir, "child", &rec("child-step", "child-course")).unwrap();
        assert_eq!(read_records(&dir, "parent").len(), 1);
        assert_eq!(read_records(&dir, "child").len(), 1);
        assert_eq!(read_records(&dir, "parent")[0].step, "parent-step");
        // The join reads each session's file, so a child's record is not
        // visible under the orchestrator's key.
        assert!(read_records(&dir, "parent")
            .iter()
            .all(|r| r.step != "child-step"));
    }

    #[test]
    fn store_refuses_a_symlinked_session_file() {
        let base = tmpdir();
        let dir = base.join("store");
        fs::create_dir_all(&dir).unwrap();
        let outside = base.join("outside.jsonl");
        std::os::unix::fs::symlink(&outside, records_path(&dir, "sess-1")).unwrap();
        let err = write_record(&dir, "sess-1", &rec("s", "c")).unwrap_err();
        assert!(err.contains("symlinked"), "{err}");
        assert!(!outside.exists(), "the symlink target must not be written");
    }

    #[test]
    fn read_skips_unparseable_and_foreign_lines() {
        let dir = tmpdir().join("store");
        write_record(&dir, "sess-1", &rec("good", "course")).unwrap();
        let path = records_path(&dir, "sess-1");
        let mut f = fs::OpenOptions::new().append(true).open(&path).unwrap();
        writeln!(f, "not json at all").unwrap();
        writeln!(f, r#"{{"schema":"something.else/9","step":"foreign"}}"#).unwrap();
        drop(f);
        let back = read_records(&dir, "sess-1");
        assert_eq!(back.len(), 1);
        assert_eq!(back[0].step, "good");
    }

    #[test]
    fn read_from_a_stale_offset_past_the_end_restarts() {
        let dir = tmpdir().join("store");
        write_record(&dir, "sess-1", &rec("only", "course")).unwrap();
        let (_, back) = read_records_from(&dir, "sess-1", 1_000_000);
        assert_eq!(
            back.len(),
            1,
            "an offset past the end must re-read, not drop"
        );
    }

    // --- no orchestration session ---

    #[test]
    fn the_route_works_with_no_orchestration_session() {
        let dir = tmpdir().join("store");
        // No workflow named: nothing is mirrored, and the local record stands.
        let r = rec("delegate every issue", "implement inline");
        assert!(write_record(&dir, "sess-1", &r).is_ok());
        assert_eq!(read_records(&dir, "sess-1").len(), 1);
    }

    #[test]
    fn a_mirror_failure_does_not_fail_the_local_write() {
        let base = tmpdir();
        let dir = base.join("store");
        let r = rec("step", "course");
        write_record(&dir, "sess-1", &r).unwrap();

        // An absent `koto` is the worst mirror failure there is.
        let absent = base.join("no-such-koto");
        assert!(!mirror_to_session(
            &absent.display().to_string(),
            "wf-1",
            &r
        ));

        // A `koto` that exits non-zero — the "workflow not found" shape — is
        // the failure the recorder must also survive. `/bin/false` rather than
        // a script written here on the spot: writing an executable and exec'ing
        // it from a test thread can lose an ETXTBSY race against another
        // thread's fork, and this case needs no argv capture to be worth
        // anything.
        assert!(!mirror_to_session("/bin/false", "wf-1", &r));

        // Both failures left the durable record exactly as written.
        let back = read_records(&dir, "sess-1");
        assert_eq!(back.len(), 1);
        assert_eq!(back[0].step, "step");
    }

    #[test]
    fn the_mirror_passes_the_record_as_one_json_argv_value() {
        let base = tmpdir();
        // Capture the child's argv so the payload shape is asserted rather
        // than assumed: `decisions record <wf> --with-data <json>`.
        let capture = base.join("capture-koto");
        let out = base.join("argv.txt");
        fs::write(
            &capture,
            format!(
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > {}\nexit 0\n",
                out.display()
            ),
        )
        .unwrap();
        fs::set_permissions(&capture, fs::Permissions::from_mode(0o755)).unwrap();

        let r = rec("delegate every issue", "implement inline");
        // This is the one test that must exec a script it just wrote, because
        // capturing argv is the whole point. Exec'ing a freshly written file
        // can lose an ETXTBSY race against another test thread's fork, so
        // retry a bounded number of times; a genuine false still fails the
        // assertion after the retries are spent.
        let bin = capture.display().to_string();
        let mut mirrored = false;
        for _ in 0..10 {
            if mirror_to_session(&bin, "wf-1", &r) {
                mirrored = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(mirrored, "the mirror never reached the capture stub");

        let argv: Vec<String> = fs::read_to_string(&out)
            .unwrap()
            .lines()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(argv[0], "decisions");
        assert_eq!(argv[1], "record");
        assert_eq!(argv[2], "wf-1");
        assert_eq!(argv[3], "--with-data");
        let payload: serde_json::Value = serde_json::from_str(&argv[4]).unwrap();
        assert_eq!(payload["choice"], "implement inline");
        assert!(payload["rationale"]
            .as_str()
            .unwrap()
            .contains("delegate every issue"));
        assert_eq!(payload["conflict_step"], "delegate every issue");
    }

    #[test]
    fn the_mirror_refuses_a_workflow_name_that_is_not_a_name() {
        // `/bin/true` succeeds unconditionally, so anything this rejects is
        // rejected by the name check and never reaches argv.
        for bad in ["--with-data", "-w", "../escape", "a/b", "a b", ""] {
            assert!(
                !mirror_to_session("/bin/true", bad, &rec("s", "c")),
                "must refuse workflow name {bad:?}"
            );
        }
    }

    // --- redaction ---

    #[test]
    fn a_public_record_carries_no_private_repo_reference() {
        // The AC: a record written into a public repository is free of
        // private-repo references. The record's text names a private repo's
        // slug, path, and issue number; none of the four may survive.
        let resolver = StubResolver {
            public: vec!["acme/public-docs"],
        };
        let r = build_record(
            "sess-1",
            "the operator said to skip delegation",
            "delegate acme/private-tools:docs/plans/PLAN-secret.md#4242 to a child",
            "implement it here, tracked in acme/public-docs:docs/plans/PLAN-open.md#7",
            Some("acme/private-tools:docs/plans/PLAN-secret.md"),
            Some(4242),
        );
        let block = published_block(&[r], &resolver);

        for leaked in [
            "private-tools",
            "PLAN-secret.md",
            "4242",
            "docs/plans/PLAN-secret",
        ] {
            assert!(
                !block.contains(leaked),
                "published block leaked {leaked:?}:\n{block}"
            );
        }
        // The public reference is not over-redacted.
        assert!(
            block.contains("acme/public-docs:docs/plans/PLAN-open.md#7"),
            "a public reference must survive:\n{block}"
        );
        // The verbatim instruction is never published.
        assert!(
            !block.contains("the operator said to skip delegation"),
            "{block}"
        );
        assert!(block.contains("instruction withheld (sha256:"), "{block}");
    }

    #[test]
    fn redaction_fails_closed_on_an_unresolvable_repo() {
        // The stub resolves nothing public, standing in for a `gh` that cannot
        // answer. Fail-closed means the reference redacts, not that it renders.
        let resolver = StubResolver { public: vec![] };
        let r = build_record(
            "sess-1",
            "instruction",
            "step naming acme/unknown-repo:docs/x.md#9",
            "course",
            Some("acme/unknown-repo:docs/x.md"),
            Some(9),
        );
        let block = published_block(&[r], &resolver);
        assert!(!block.contains("unknown-repo"), "{block}");
        assert!(!block.contains("docs/x.md"), "{block}");
        assert!(!block.contains("#9"), "{block}");
    }

    #[test]
    fn a_bare_path_or_filename_is_redacted() {
        let resolver = StubResolver {
            public: vec!["acme/public-docs"],
        };
        let scrubbed = scrub_public(
            "see docs/plans/PLAN-internal.md and PLAN-other.md and /srv/private/notes.txt",
            &resolver,
        );
        for leaked in [
            "docs/plans/PLAN-internal.md",
            "PLAN-other.md",
            "/srv/private/notes.txt",
        ] {
            assert!(!scrubbed.contains(leaked), "leaked {leaked:?}: {scrubbed}");
        }
        // Prose survives; only reference-shaped tokens are touched.
        assert!(scrubbed.starts_with("see "), "{scrubbed}");
        assert_eq!(scrubbed.matches("ref-").count(), 3, "{scrubbed}");
    }

    #[test]
    fn a_bare_issue_number_is_redacted() {
        let resolver = StubResolver {
            public: vec!["acme/public-docs"],
        };
        let scrubbed = scrub_public("blocked by #4242 in the milestone", &resolver);
        assert!(!scrubbed.contains("4242"), "{scrubbed}");
    }

    #[test]
    fn a_public_slug_survives_scrubbing() {
        let resolver = StubResolver {
            public: vec!["acme/public-docs"],
        };
        let scrubbed = scrub_public("filed in acme/public-docs#12 today", &resolver);
        assert!(scrubbed.contains("acme/public-docs#12"), "{scrubbed}");
        let private = scrub_public("filed in acme/closed-source#12 today", &resolver);
        assert!(!private.contains("closed-source"), "{private}");
        assert!(!private.contains("12"), "{private}");
    }

    #[test]
    fn scrubbing_survives_surrounding_punctuation() {
        let resolver = StubResolver { public: vec![] };
        let scrubbed = scrub_public("(see docs/private/PLAN.md), then stop", &resolver);
        assert!(!scrubbed.contains("docs/private"), "{scrubbed}");
        assert!(
            scrubbed.contains("("),
            "punctuation is preserved: {scrubbed}"
        );
        assert!(
            scrubbed.contains("),"),
            "punctuation is preserved: {scrubbed}"
        );
    }

    #[test]
    fn a_record_without_a_reference_publishes_its_opaque_id() {
        let resolver = StubResolver { public: vec![] };
        let r = rec("delegate", "inline");
        let node = r.node_id.clone();
        let block = published_block(&[r], &resolver);
        assert!(block.contains(&node), "{block}");
        assert!(node.starts_with("conflict-"), "{node}");
    }

    // --- surfacing ---

    #[test]
    fn the_author_facing_block_names_the_step_and_course() {
        let records = vec![rec("delegate every issue", "implement issue 4 inline")];
        let block = local_block(&records);
        assert!(block.starts_with(LOCAL_MARKER), "{block}");
        assert!(block.contains("step: delegate every issue"), "{block}");
        assert!(
            block.contains("course: implement issue 4 inline"),
            "{block}"
        );
        // Machine-local, so the instruction is in the clear for the author.
        assert!(block.contains("instruction: the instruction"), "{block}");
    }

    #[test]
    fn surfacing_advances_its_offset_so_a_record_is_emitted_once() {
        let dir = tmpdir().join("store");
        write_record(&dir, "sess-1", &rec("first", "course")).unwrap();

        let offset = read_surfaced_offset(&dir, "sess-1");
        assert_eq!(offset, 0);
        let (after_first, records) = read_records_from(&dir, "sess-1", offset);
        assert_eq!(records.len(), 1);
        write_surfaced_offset(&dir, "sess-1", after_first);

        // Nothing new: the hook stays silent.
        let (_, again) = read_records_from(&dir, "sess-1", read_surfaced_offset(&dir, "sess-1"));
        assert!(again.is_empty(), "a surfaced record must not re-emit");

        // A second record surfaces, and only the second.
        write_record(&dir, "sess-1", &rec("second", "course")).unwrap();
        let (_, next) = read_records_from(&dir, "sess-1", read_surfaced_offset(&dir, "sess-1"));
        assert_eq!(next.len(), 1);
        assert_eq!(next[0].step, "second");
    }

    // --- sanitization ---

    #[test]
    fn sanitize_strips_ansi_and_control_bytes() {
        assert_eq!(sanitize("hel\x1b[31mlo"), "hello");
        assert_eq!(sanitize("a\nb\tc"), "a b c");
        assert_eq!(sanitize("a\x07b"), "ab");
    }

    #[test]
    fn sanitize_caps_field_length() {
        let long = "x".repeat(MAX_FIELD_CHARS * 2);
        assert_eq!(sanitize(&long).chars().count(), MAX_FIELD_CHARS);
    }

    #[test]
    fn a_crafted_instruction_stays_a_json_string_value() {
        let dir = tmpdir().join("store");
        let r = build_record(
            "sess-1",
            r#"", "step": "forged", "course": "forged"#,
            "real-step",
            "real-course",
            None,
            None,
        );
        write_record(&dir, "sess-1", &r).unwrap();
        let back = read_records(&dir, "sess-1");
        assert_eq!(back.len(), 1);
        assert_eq!(
            back[0].step, "real-step",
            "a crafted instruction forged a field"
        );
        assert_eq!(back[0].course, "real-course");
    }

    #[test]
    fn a_crafted_reference_is_refused_rather_than_stored() {
        let args = RecordArgs {
            instruction: "i".to_string(),
            step: "s".to_string(),
            course: "c".to_string(),
            session: Some("sess-1".to_string()),
            workflow: None,
            reference: Some("acme/repo:../../etc/passwd".to_string()),
            number: None,
        };
        assert_eq!(cmd_record(&args), ExitCode::from(2));
    }

    #[test]
    fn session_ids_are_filename_safe() {
        assert!(resolve_session(Some("abc-123.def")).is_some());
        for bad in ["../escape", "a/b", ".", "..", "-flag", "a b", ""] {
            assert!(resolve_session(Some(bad)).is_none(), "accepted {bad:?}");
        }
    }

    #[test]
    fn iso_stamp_formats_utc() {
        assert_eq!(format_iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(format_iso_utc(1_755_000_000), "2025-08-12T12:00:00Z");
    }
}
