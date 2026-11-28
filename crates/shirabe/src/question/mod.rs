//! `shirabe question`: raise, list, render, answer, pass up and settle a
//! question a session cannot settle alone, recorded in koto.
//!
//! The commands validate, store, record and render. They never author a
//! question: every part comes from the raising session's content, and nothing
//! missing is filled in. koto keeps the record; shirabe writes nothing of its
//! own outside a temporary file it removes.
//!
//! Exit codes, the same for every subcommand:
//!   0  done
//!   1  shirabe refused the input before any koto write
//!   2  a usage error
//!   3  koto is missing or below shirabe's koto minimum
//!   4  koto refused; its code, field and check are passed through
//!   5  a question that cannot be presented, or an answer that does not read
//!      as verified
//!   6  a koto call ran past its time bound and was stopped
//!   7  koto recorded the owner's answer, but reading it back failed
//!   8  `render` was given a question that is no longer open

pub mod answer;
pub mod attempt;
pub mod content;
pub mod koto;
pub mod ladder;
pub mod render;

use std::collections::{BTreeMap, BTreeSet};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Args, Subcommand};
use serde_json::{json, Map, Value};

use content::{packet, Body, Content, Refusal};
use koto::{History, Refused};

pub const EXIT_REFUSED: u8 = 1;
pub const EXIT_USAGE: u8 = 2;
pub const EXIT_KOTO_MISSING: u8 = 3;
pub const EXIT_KOTO_REFUSED: u8 = 4;
pub const EXIT_UNPRESENTABLE: u8 = 5;
pub const EXIT_KOTO_TIMEOUT: u8 = 6;
pub const EXIT_UNCONFIRMED: u8 = 7;
pub const EXIT_CLOSED: u8 = 8;

/// The one person handle these commands take.
pub const OWNER: &str = "owner";

/// Whether this process was invoked as `shirabe question ...`, for the usage
/// exit code.
pub fn invoked() -> bool {
    std::env::args_os().nth(1).is_some_and(|a| a == "question")
}

#[derive(Args)]
pub struct QuestionArgs {
    #[command(subcommand)]
    command: QuestionCommands,
}

#[derive(Subcommand)]
enum QuestionCommands {
    /// Validate a question's content, record it in koto as an escalate and
    /// store its content once. Prints the identity, recipient, need, label,
    /// packet, stored byte count and prompt header as one JSON object.
    Raise(RaiseArgs),
    /// List the questions open for the owner and those at and below a
    /// session, the ones held behind another, the incomplete ones, and the
    /// answers that have arrived and that no decision cites yet. Reads only.
    Pending(PendingArgs),
    /// Render stored questions into the question tool's input and a plain
    /// text form. The output holds no time, path or session name.
    Render(RenderArgs),
    /// Record the owner's answer by handing koto the pointer to the
    /// question-tool call that asked it. Takes no answer text: the answer is
    /// what the person chose in that call.
    Answer(AnswerArgs),
    /// Record what came of an attempt to decide: decided, undecided or, in an
    /// unattended run, provisional. Prints the attempt's id, session, result
    /// and state as one JSON object.
    Attempt(AttemptArgs),
    /// Pass a question up to the session's own dispatcher or to the owner,
    /// keeping its identity. A decision question needs the session's own
    /// undecided attempt tied to it; a need passes with none.
    PassUp(PassUpArgs),
    /// Answer a question the session holds, as the session: answered by its
    /// addressee, settled by its raiser. With --owner-note, a relayed claim
    /// is recorded as the session's own decision, never the owner's.
    Settle(SettleArgs),
    /// Mark an owner's answer given at or below the session as seen: one
    /// judgment citing it. The answer itself is not changed.
    Seen(SeenArgs),
}

#[derive(Args)]
struct PassUpArgs {
    /// The question's identity, <raiser session id>/<decision id>.
    #[arg(value_name = "IDENTITY")]
    identity: String,
    /// The koto session passing the question up: the question's current
    /// addressee or its raiser.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
    /// Why the question is not this session's to settle: contradicts-answer,
    /// changes-scope, outward-facing or reserved-step, or outside-scope when
    /// passing up to a coordinator.
    #[arg(long, value_name = "GROUND")]
    ground: Option<String>,
    /// The session's own undecided attempt tied to the question, as
    /// <decision id> or <session>:<decision id>. Required for a decision
    /// question; refused for a need.
    #[arg(long, value_name = "ID")]
    attempt: Option<String>,
    /// The new recipient: the session's own dispatcher (the default) or
    /// person:owner.
    #[arg(long, value_name = "RECIPIENT")]
    to: Option<String>,
}

#[derive(Args)]
struct SettleArgs {
    /// The question's identity. Left out with --what for a relayed claim
    /// that answers no recorded question.
    #[arg(value_name = "IDENTITY")]
    identity: Option<String>,
    /// The koto session settling it.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
    /// What was decided, for a claim that answers no recorded question.
    #[arg(long, value_name = "TEXT", conflicts_with = "identity")]
    what: Option<String>,
    /// The option chosen.
    #[arg(long, value_name = "TEXT")]
    chosen: Option<String>,
    /// Why. Required with a question identity.
    #[arg(long, value_name = "TEXT")]
    reason: Option<String>,
    /// An earlier decision this one rests on, <session>:<decision id>, such
    /// as the owner's answer to a question with the same label. Repeatable.
    #[arg(long, value_name = "SESSION:ID")]
    basis: Vec<String>,
    /// What was relayed as the owner's word. Recorded in the session's own
    /// decision, never as the owner's answer.
    #[arg(long = "owner-note", value_name = "TEXT")]
    owner_note: Option<String>,
}

#[derive(Args)]
struct SeenArgs {
    /// The owner's answer, <session>:<answer id>.
    #[arg(value_name = "SESSION:ID")]
    answer: String,
    /// The koto session marking it seen.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
}

#[derive(Args)]
struct RaiseArgs {
    /// The koto session or anchor raising the question.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
    /// The content file, or - for standard input.
    #[arg(long, value_name = "FILE")]
    content: String,
    /// Who the question is for: session:<name>, anchor:<name> or
    /// person:owner. Without it, the session's dispatcher, or person:owner
    /// for a session nothing dispatched.
    #[arg(long, value_name = "RECIPIENT")]
    to: Option<String>,
    /// The undecided attempt the question rests on, as <decision id> or
    /// <session>:<decision id>. Required for a decision question.
    #[arg(long, value_name = "ID")]
    attempt: Option<String>,
    /// The workflow state and visit the question was raised in,
    /// <state>:<visit>.
    #[arg(long, value_name = "STATE:VISIT")]
    state: Option<String>,
}

#[derive(Args)]
struct PendingArgs {
    /// The session listing its questions.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
    /// List the questions open for this person (only `owner`).
    #[arg(long, value_name = "HANDLE")]
    person: Option<String>,
    /// List the questions at and below this session or anchor.
    #[arg(long, value_name = "SESSION_OR_ANCHOR")]
    at: Option<String>,
}

#[derive(Args)]
struct RenderArgs {
    /// Question identities, <raiser session id>/<decision id>, rendered in
    /// the order given.
    #[arg(
        value_name = "IDENTITY",
        required_unless_present = "person",
        conflicts_with = "person"
    )]
    identities: Vec<String>,
    /// Render every question open for this person (only `owner`), in
    /// pending order.
    #[arg(long, value_name = "HANDLE")]
    person: Option<String>,
    /// The session running the command. Does not change the output.
    #[arg(long = "in", value_name = "SESSION")]
    in_: Option<String>,
}

#[derive(Args)]
struct AnswerArgs {
    /// The question's identity, <raiser session id>/<decision id>.
    #[arg(value_name = "IDENTITY")]
    identity: String,
    /// The koto session or anchor recording the answer.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
    /// The question-tool call's id in this harness session's record. Without
    /// it, the latest call that carried the question's prompt header.
    #[arg(long, value_name = "CALL_ID", requires = "position")]
    call: Option<String>,
    /// The question's position in that call, from 1.
    #[arg(long, value_name = "N", requires = "call", value_parser = clap::value_parser!(u32).range(1..))]
    position: Option<u32>,
}

#[derive(Args)]
struct AttemptArgs {
    /// The koto session the attempt is recorded in: the session that will
    /// raise the question if the attempt ends undecided.
    #[arg(long = "in", value_name = "SESSION")]
    in_: String,
    /// What was being decided, in a few words.
    #[arg(long, value_name = "TEXT")]
    what: String,
    /// decided, undecided or provisional.
    #[arg(long, value_name = "RESULT")]
    result: String,
    /// The workflow state and visit the attempt was made in, <state>:<visit>.
    /// Left out for a session with no workflow state.
    #[arg(long, value_name = "STATE:VISIT")]
    state: Option<String>,
    /// The option chosen. Required for decided and provisional; refused for
    /// undecided.
    #[arg(long, value_name = "TEXT")]
    chosen: Option<String>,
    /// The cheap-or-costly judgment: cheap when undoing the choice changes
    /// only the session's own unpublished work, costly otherwise.
    #[arg(long, value_name = "cheap|costly")]
    undo: Option<String>,
    /// What undoing the choice would take. Required with --undo.
    #[arg(long = "undo-reason", value_name = "TEXT")]
    undo_reason: Option<String>,
    /// Why the session may not settle the question: contradicts-answer,
    /// changes-scope, outward-facing or reserved-step. Only with undecided.
    #[arg(long, value_name = "GROUND")]
    ground: Option<String>,
    /// An earlier decision the attempt rests on, <session>:<decision id>.
    /// Repeatable.
    #[arg(long, value_name = "SESSION:ID")]
    basis: Vec<String>,
}

/// The run mode a session reads as, from the environment the harness and
/// koto's hook set: unattended when `KOTO_RUN_MODE` is `unattended` or
/// `CLAUDE_CODE_SESSION_ATTENDED` is `0`, attended when either says
/// attended (`attended`, `1`) and neither says unattended, unknown
/// otherwise. koto 0.42.0 keeps no run mode per session: it reads the mode
/// for each call from the same variable, so this is the reading koto
/// records.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunMode {
    Attended,
    Unattended,
    Unknown,
}

impl RunMode {
    pub fn as_str(self) -> &'static str {
        match self {
            RunMode::Attended => "attended",
            RunMode::Unattended => "unattended",
            RunMode::Unknown => "unknown",
        }
    }
    /// The value handed to koto's `--run-mode`, or `None` for unknown,
    /// which koto records by itself.
    pub fn as_koto(self) -> Option<&'static str> {
        (self != RunMode::Unknown).then(|| self.as_str())
    }
}

pub fn run_mode() -> RunMode {
    let koto = std::env::var("KOTO_RUN_MODE").ok();
    let attended = std::env::var("CLAUDE_CODE_SESSION_ATTENDED").ok();
    if koto.as_deref() == Some("unattended") || attended.as_deref() == Some("0") {
        RunMode::Unattended
    } else if koto.as_deref() == Some("attended") || attended.as_deref() == Some("1") {
        RunMode::Attended
    } else {
        RunMode::Unknown
    }
}

/// A command's failure: its exit code and what it prints.
#[derive(Debug)]
pub struct Failure {
    pub exit: u8,
    pub code: String,
    pub field: Option<String>,
    pub check: Option<String>,
    pub message: String,
    pub extra: Box<Map<String, Value>>,
}

impl Failure {
    fn new(exit: u8, code: &str, message: impl Into<String>) -> Self {
        Failure {
            exit,
            code: code.to_string(),
            field: None,
            check: None,
            message: message.into(),
            extra: Box::default(),
        }
    }
    fn refused(field: &str, message: impl Into<String>) -> Self {
        let mut f = Failure::new(EXIT_REFUSED, "refused", message);
        f.field = Some(field.to_string());
        f
    }
    fn usage(message: impl Into<String>) -> Self {
        Failure::new(EXIT_USAGE, "usage", message)
    }
    pub fn koto_missing(message: String) -> Self {
        Failure::new(EXIT_KOTO_MISSING, "koto_minimum", message)
    }
    pub fn koto(r: &Refused) -> Self {
        if r.timed_out() {
            return Failure::new(EXIT_KOTO_TIMEOUT, &r.code, r.error.clone());
        }
        let mut f = Failure::new(
            EXIT_KOTO_REFUSED,
            &r.code,
            format!("koto refused: {}", r.error),
        );
        f.field = r.field.clone();
        f.check = r.check.clone();
        f
    }
    fn unpresentable(code: &str, message: impl Into<String>) -> Self {
        Failure::new(EXIT_UNPRESENTABLE, code, message)
    }
    fn with(mut self, key: &str, v: Value) -> Self {
        self.extra.insert(key.to_string(), v);
        self
    }
}

impl From<Refusal> for Failure {
    fn from(r: Refusal) -> Self {
        Failure::refused(&r.field, r.message)
    }
}

impl From<Refused> for Failure {
    fn from(r: Refused) -> Self {
        Failure::koto(&r)
    }
}

fn emit(v: &Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(
        out,
        "{}",
        serde_json::to_string(v).expect("JSON serializes")
    );
}

pub fn run(args: QuestionArgs) -> ExitCode {
    let (name, result) = match args.command {
        QuestionCommands::Raise(a) => ("raise", raise(&a)),
        QuestionCommands::Pending(a) => ("pending", pending_cmd(&a)),
        QuestionCommands::Render(a) => ("render", render_cmd(&a)),
        QuestionCommands::Answer(a) => ("answer", answer_cmd(&a)),
        QuestionCommands::Attempt(a) => ("attempt", attempt_cmd(&a)),
        QuestionCommands::PassUp(a) => (
            "pass-up",
            ladder::pass_up(&ladder::PassUp {
                identity: &a.identity,
                session: &a.in_,
                ground: a.ground.as_deref(),
                attempt: a.attempt.as_deref(),
                to: a.to.as_deref(),
            }),
        ),
        QuestionCommands::Settle(a) => (
            "settle",
            ladder::settle(&ladder::Settle {
                identity: a.identity.as_deref(),
                session: &a.in_,
                what: a.what.as_deref(),
                chosen: a.chosen.as_deref(),
                reason: a.reason.as_deref(),
                basis: &a.basis,
                owner_note: a.owner_note.as_deref(),
            }),
        ),
        QuestionCommands::Seen(a) => (
            "seen",
            ladder::seen(&ladder::Seen {
                answer: &a.answer,
                session: &a.in_,
            }),
        ),
    };
    match result {
        Ok(v) => {
            emit(&v);
            ExitCode::SUCCESS
        }
        Err(f) => {
            eprintln!("shirabe question {name}: {}", f.message);
            let mut err = Map::new();
            err.insert("exit".into(), json!(f.exit));
            err.insert("code".into(), json!(f.code));
            if let Some(field) = &f.field {
                err.insert("field".into(), json!(field));
            }
            if let Some(check) = &f.check {
                err.insert("check".into(), json!(check));
            }
            err.insert("message".into(), json!(f.message));
            for (k, v) in *f.extra {
                err.insert(k, v);
            }
            emit(&json!({"v": 1, "error": Value::Object(err)}));
            ExitCode::from(f.exit)
        }
    }
}

// ---------------------------------------------------------------------------
// Names and recipients

/// koto's own session-name shape, `^[a-zA-Z0-9][a-zA-Z0-9._-]*$`, within
/// 128 bytes. A name that passes can never read as an option to koto.
fn name_ok(s: &str) -> bool {
    let mut chars = s.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphanumeric())
        && s.len() <= 128
        && s.chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

/// Refuse a caller's session or anchor name that is not koto's name shape,
/// before it reaches any koto call.
fn check_name(field: &str, flag: &str, s: &str) -> Result<(), Failure> {
    if name_ok(s) {
        return Ok(());
    }
    Err(Failure::refused(
        field,
        format!("{flag} {s:?} is not a koto session name: it must start with a letter or digit and hold only letters, digits, `.`, `_` and `-`"),
    ))
}

/// Refuse a caller's question identity that is not `<session id>/<decision id>`.
fn check_identity(s: &str) -> Result<(), Failure> {
    if content::is_identity(s) {
        return Ok(());
    }
    Err(Failure::usage(format!(
        "{s:?} is not a question identity, <raiser session id>/<decision id>"
    )))
}

/// The recipients `raise` takes: `session:<name>`, `anchor:<name>` and
/// `person:owner`.
fn parse_recipient(to: &str) -> Result<String, Failure> {
    let refuse = |why: &str| {
        Failure::refused(
            "to",
            format!(
                "the recipient {to:?} {why}; give session:<name>, anchor:<name> or person:{OWNER}"
            ),
        )
    };
    match to.split_once(':') {
        Some(("session", n)) | Some(("anchor", n)) if name_ok(n) => Ok(to.to_string()),
        Some(("session", _)) | Some(("anchor", _)) => Err(refuse("has an empty or malformed name")),
        Some(("person", OWNER)) => Ok(to.to_string()),
        Some(("person", _)) => Err(refuse(&format!(
            "names a person other than {OWNER}; these commands take one person handle"
        ))),
        _ => Err(refuse("has no recipient type")),
    }
}

fn state_ok(s: &str) -> bool {
    match s.rsplit_once(':') {
        Some((state, visit)) => {
            name_ok(state)
                && !visit.is_empty()
                && !visit.starts_with('0')
                && visit.chars().all(|c| c.is_ascii_digit())
        }
        None => false,
    }
}

/// The default recipient: the session's dispatcher, or person:owner when
/// nothing dispatched it. `true` when the origin reads unrecorded.
fn default_recipient(session: &str) -> Result<(String, bool), Failure> {
    let o = koto::run(&["session", "origin", "--", session])?;
    let origin = o.get("origin").cloned().unwrap_or(Value::Null);
    let state = origin.get("state").and_then(Value::as_str).unwrap_or("");
    match state {
        "dispatched" => {
            let d = origin
                .get("dispatcher")
                .and_then(Value::as_str)
                .unwrap_or("");
            let kind = match origin.get("dispatcher_kind").and_then(Value::as_str) {
                Some("anchor") => "anchor",
                _ => "session",
            };
            if !name_ok(d) {
                return Err(Failure::refused(
                    "to",
                    format!("koto names a dispatcher for {session} that is not a session name; give --to"),
                ));
            }
            Ok((format!("{kind}:{d}"), false))
        }
        "none" => Ok((format!("person:{OWNER}"), false)),
        _ => Ok((format!("person:{OWNER}"), true)),
    }
}

/// Whether koto reads `session`'s origin as unrecorded. A session koto says
/// does not exist reads as recorded (nothing to link); a koto that did not
/// answer is an error.
fn origin_unrecorded(session: &str, cache: &mut BTreeMap<String, bool>) -> Result<bool, Refused> {
    if let Some(v) = cache.get(session) {
        return Ok(*v);
    }
    // A session koto names in its own listing; one not in koto's name shape
    // is never passed back to it.
    if !name_ok(session) {
        return Ok(false);
    }
    let v = match koto::run(&["session", "origin", "--", session]) {
        Ok(o) => !matches!(
            o.pointer("/origin/state").and_then(Value::as_str),
            Some("dispatched") | Some("none")
        ),
        Err(r) if r.not_found() => false,
        Err(r) => return Err(r),
    };
    cache.insert(session.to_string(), v);
    Ok(v)
}

// ---------------------------------------------------------------------------
// raise

fn read_content(path: &str) -> Result<Vec<u8>, Failure> {
    let limit = (content::MAX_STORED as u64) * 4;
    let mut buf = Vec::new();
    let res = if path == "-" {
        std::io::stdin()
            .lock()
            .take(limit + 1)
            .read_to_end(&mut buf)
    } else {
        std::fs::File::open(path).and_then(|f| f.take(limit + 1).read_to_end(&mut buf))
    };
    res.map_err(|e| Failure::refused("content", format!("the content could not be read: {e}")))?;
    if buf.len() as u64 > limit {
        return Err(Failure::refused(
            "content",
            "the content file is far past the 16 KiB bound on stored content",
        ));
    }
    Ok(buf)
}

/// The attempt a decision question rests on: it must be in the raising
/// session's run with result `undecided`. Returns `<session>:<id>`.
fn check_attempt(session: &str, attempt: Option<&str>) -> Result<String, Failure> {
    let Some(given) = attempt else {
        return Err(Failure::refused(
            "attempt",
            "a decision question needs the undecided attempt behind it: record the attempt (shirabe question attempt --result undecided) and give its id with --attempt",
        ));
    };
    let (want_session, want_id) = match given.split_once(':') {
        Some((s, i)) => (Some(s), i),
        None => (None, given),
    };
    if want_id.is_empty()
        || !want_id.bytes().all(|b| b.is_ascii_digit())
        || want_session.is_some_and(|s| !name_ok(s))
    {
        return Err(Failure::refused(
            "attempt",
            format!("--attempt {given:?} is not <decision id> or <session>:<decision id>"),
        ));
    }
    let in_arg = format!("--in={session}");
    let listed = koto::run(&["decisions", "attempts", &in_arg])?;
    let attempts = listed
        .get("attempts")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let found = attempts.iter().find(|a| {
        a.get("id").and_then(Value::as_str) == Some(want_id)
            && want_session.is_none_or(|s| a.get("session").and_then(Value::as_str) == Some(s))
    });
    let Some(a) = found else {
        return Err(Failure::refused(
            "attempt",
            format!("--attempt {given} names no attempt in {session}'s run"),
        ));
    };
    if a.get("result").and_then(Value::as_str) != Some("undecided") {
        return Err(Failure::refused(
            "attempt",
            format!("--attempt {given} names an attempt whose result is not undecided; a question rests on an undecided attempt"),
        ));
    }
    let s = a
        .get("session")
        .and_then(Value::as_str)
        .unwrap_or(session)
        .to_string();
    Ok(format!("{s}:{want_id}"))
}

/// The stored content of a question, or why there is none to use.
enum Stored {
    Good(Box<Content>),
    /// The question was raised with no packet: nothing is stored for it.
    NoPacket,
    Missing,
    Mismatch,
    Unreadable,
}

/// A question's stored content. Only koto's own not-found answer makes it
/// `Missing`; a koto that did not answer (a timeout, any other failure) is an
/// error, so a healthy question is never reported broken during a stall.
fn read_stored(identity: &str, packet_want: Option<&str>) -> Result<Stored, Refused> {
    let Some(want) = packet_want else {
        return Ok(Stored::NoPacket);
    };
    match koto::run_raw(&["decisions", "content", "read", "--", identity]) {
        Ok(bytes) => {
            if packet(&bytes) != want {
                return Ok(Stored::Mismatch);
            }
            Ok(match Content::from_stored(&bytes) {
                Ok(c) => Stored::Good(Box::new(c)),
                Err(_) => Stored::Unreadable,
            })
        }
        Err(r) if r.not_found() => Ok(Stored::Missing),
        Err(r) => Err(r),
    }
}

/// A question's history, `None` when koto answers that it holds no such
/// question, and an error when koto did not answer.
fn history_if_any(identity: &str) -> Result<Option<History>, Refused> {
    match History::read(identity) {
        Ok(h) => Ok(Some(h)),
        Err(r) if r.not_found() => Ok(None),
        Err(r) => Err(r),
    }
}

/// `depends_on` must name a question that exists, and following the chain
/// from it must not come back round.
fn check_dependency(dep: &str) -> Result<(), Failure> {
    match History::read(dep) {
        Ok(_) => {}
        Err(r) if r.code == "decision_not_found" => {
            return Err(Failure::refused(
                "depends_on",
                format!("`depends_on` names {dep}, which is no question koto holds"),
            ))
        }
        Err(r) => return Err(r.into()),
    }
    let mut seen = BTreeSet::new();
    seen.insert(dep.to_string());
    let mut cur = dep.to_string();
    for _ in 0..256 {
        let Some(h) = history_if_any(&cur)? else {
            break;
        };
        let Stored::Good(c) = read_stored(&cur, h.packet().as_deref())? else {
            break;
        };
        let Some(next) = c.depends_on else { break };
        if !seen.insert(next.clone()) {
            return Err(Failure::refused(
                "depends_on",
                format!("`depends_on` names {dep}, whose own dependencies come back round to {next}: that would close a cycle"),
            ));
        }
        cur = next;
    }
    Ok(())
}

struct TempFile(PathBuf);

impl TempFile {
    fn create(bytes: &[u8]) -> std::io::Result<TempFile> {
        use std::os::unix::fs::OpenOptionsExt;
        let mut rnd = [0u8; 8];
        getrandom::getrandom(&mut rnd).map_err(|e| std::io::Error::other(e.to_string()))?;
        let hex: String = rnd.iter().map(|b| format!("{b:02x}")).collect();
        let path = std::env::temp_dir().join(format!("shirabe-question-{hex}.json"));
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        let t = TempFile(path);
        f.write_all(bytes)?;
        Ok(t)
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

fn withdraw(session: &str, id: &str, reason: &str) -> bool {
    let in_arg = format!("--in={session}");
    let reason_arg = format!("--reason={reason}");
    koto::run(&[
        "decisions",
        "answer",
        &in_arg,
        "--outcome=withdrawn",
        &reason_arg,
        "--by=session",
        "--",
        session,
        id,
    ])
    .is_ok()
}

fn raise(a: &RaiseArgs) -> Result<Value, Failure> {
    check_name("in", "--in", &a.in_)?;
    koto::check_version()?;
    let bytes = read_content(&a.content)?;
    let content = content::parse_input(&bytes)?;
    if let Some(s) = &a.state {
        if !state_ok(s) {
            return Err(Failure::refused(
                "state",
                format!("--state {s:?} is not <state>:<visit> (a state name, then a whole number from 1)"),
            ));
        }
    }
    let is_need = matches!(content.body, Body::Need { .. });
    let owner = format!("person:{OWNER}");
    let (recipient, unlinked) = match &a.to {
        Some(to) => {
            let r = parse_recipient(to)?;
            if is_need && r != owner {
                return Err(Failure::refused(
                    "to",
                    format!("a need goes to {owner}; --to {to} names someone else"),
                ));
            }
            (r, false)
        }
        None if is_need => (owner.clone(), false),
        None => default_recipient(&a.in_)?,
    };
    let basis = if is_need {
        if a.attempt.is_some() {
            return Err(Failure::refused(
                "attempt",
                "a need rests on no attempt; leave --attempt out",
            ));
        }
        None
    } else {
        Some(check_attempt(&a.in_, a.attempt.as_deref())?)
    };
    if let Some(dep) = &content.depends_on {
        check_dependency(dep)?;
    }

    let stored = content.stored();
    let hash = packet(&stored);
    // Every caller-derived value goes in `--option=value` form, so none can
    // read as an option of its own, and the session follows `--`.
    let mut args: Vec<String> = vec![
        "decisions".into(),
        "record".into(),
        "--kind=escalate".into(),
        "--outcome=escalated".into(),
        "--subject=question=q".into(),
        format!("--subject=text={}", content.ask),
        format!("--subject=recipient={recipient}"),
        format!("--subject=label={}", content.label),
        format!("--subject=need={}", content.need()),
        format!("--subject=packet={hash}"),
    ];
    if let Some(s) = &a.state {
        args.push(format!("--subject=state={s}"));
    }
    if let Some(b) = &basis {
        args.push(format!("--basis={b}"));
    }
    args.push("--by=session".into());
    args.push("--".into());
    args.push(a.in_.clone());
    let argv: Vec<&str> = args.iter().map(String::as_str).collect();
    let rec = koto::run(&argv)?;
    let id = rec
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            Failure::new(
                EXIT_KOTO_REFUSED,
                "koto_output",
                "koto recorded the question but printed no id",
            )
        })?
        .to_string();

    let file = TempFile::create(&stored).map_err(|e| {
        let withdrawn = withdraw(
            &a.in_,
            &id,
            "shirabe question raise could not stage the content for koto",
        );
        Failure::new(
            EXIT_KOTO_REFUSED,
            "content_write",
            format!("the content could not be staged for koto ({e}); the question was withdrawn"),
        )
        .with("withdrawn", json!(withdrawn))
    })?;
    let path = file.0.to_string_lossy().to_string();
    let file_arg = format!("--file={path}");
    let written = koto::run(&[
        "decisions",
        "content",
        "write",
        &file_arg,
        "--",
        &a.in_,
        &id,
    ]);
    drop(file);
    let written = match written {
        Ok(w) => w,
        Err(r) => {
            let withdrawn = withdraw(
                &a.in_,
                &id,
                &format!(
                    "the content write failed ({}), so the question was withdrawn",
                    r.code
                ),
            );
            let mut f = Failure::koto(&r)
                .with("withdrawn", json!(withdrawn))
                .with("id", json!(id));
            f.message = format!(
                "{}; the escalate {id} was {}",
                f.message,
                if withdrawn {
                    "withdrawn"
                } else {
                    "left in place and could not be withdrawn"
                }
            );
            return Err(f);
        }
    };
    let identity = written
        .get("question")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let back = koto::run_raw(&["decisions", "content", "read", "--", &identity]);
    if let Err(r) = &back {
        if r.timed_out() {
            // A timeout after the escalate was recorded takes the cleanup path
            // a failed content write takes: withdraw it, so no listing shows a
            // question whose content was never confirmed.
            let withdrawn = withdraw(
                &a.in_,
                &id,
                "reading the stored content back timed out, so the question was withdrawn",
            );
            let mut f = Failure::koto(r)
                .with("withdrawn", json!(withdrawn))
                .with("id", json!(id));
            f.message = format!(
                "{}; the escalate {id} was {}",
                f.message,
                if withdrawn {
                    "withdrawn"
                } else {
                    "left in place and could not be withdrawn"
                }
            );
            return Err(f);
        }
    }
    if back.as_deref().ok() != Some(stored.as_slice()) {
        let withdrawn = withdraw(
            &a.in_,
            &id,
            "the stored content did not read back as written",
        );
        return Err(Failure::unpresentable(
            "content_mismatch",
            format!("the content koto stored for {identity} does not read back as written; the question was {}", if withdrawn { "withdrawn" } else { "left in place" }),
        )
        .with("identity", json!(identity)));
    }
    let mut out = Map::new();
    out.insert("v".into(), json!(1));
    out.insert("identity".into(), json!(identity));
    out.insert("session".into(), json!(a.in_));
    out.insert("id".into(), json!(id));
    out.insert("recipient".into(), json!(recipient));
    out.insert("unlinked".into(), json!(unlinked));
    out.insert("need".into(), json!(content.need()));
    out.insert("label".into(), json!(content.label));
    out.insert("packet".into(), json!(hash));
    out.insert("bytes".into(), json!(stored.len()));
    out.insert(
        "prompt_header".into(),
        written.get("prompt_header").cloned().unwrap_or(Value::Null),
    );
    if let Some(s) = &a.state {
        out.insert("state".into(), json!(s));
    }
    if let Some(b) = &basis {
        out.insert("attempt".into(), json!(b));
    }
    if let Some(d) = &content.depends_on {
        out.insert("depends_on".into(), json!(d));
    }
    Ok(Value::Object(out))
}

// ---------------------------------------------------------------------------
// time

/// Seconds since the epoch of a koto time, `YYYY-MM-DDTHH:MM:SS[.fff]Z`.
fn epoch_seconds(t: &str) -> Option<i64> {
    let b = t.as_bytes();
    if b.len() < 20
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
        || !t.ends_with('Z')
    {
        return None;
    }
    let n = |r: std::ops::Range<usize>| t.get(r)?.parse::<i64>().ok();
    let (y, m, d) = (n(0..4)?, n(5..7)?, n(8..10)?);
    let (hh, mm, ss) = (n(11..13)?, n(14..16)?, n(17..19)?);
    // Days from the civil date (Howard Hinnant's algorithm).
    let y2 = if m <= 2 { y - 1 } else { y };
    let era = if y2 >= 0 { y2 } else { y2 - 399 } / 400;
    let yoe = y2 - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 86400 + hh * 3600 + mm * 60 + ss)
}

fn now_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

// ---------------------------------------------------------------------------
// pending

fn recipient_string(v: &Value) -> Value {
    if let Some(s) = v.as_str() {
        return json!(s);
    }
    let kind = v.get("kind").and_then(Value::as_str);
    let name = v
        .get("name")
        .or_else(|| v.get("handle"))
        .and_then(Value::as_str);
    match (kind, name) {
        (Some(k), Some(n)) => json!(format!("{k}:{n}")),
        _ => v.get("value").cloned().unwrap_or(Value::Null),
    }
}

/// One open question with what `pending` lists for it.
struct Listed {
    identity: String,
    element: Map<String, Value>,
    waiting: usize,
    time: String,
    held: bool,
    content: Option<Content>,
    header: Option<String>,
}

struct Pending {
    questions: Vec<Listed>,
    incomplete: Vec<Value>,
}

/// The open questions for the owner and/or at a position, merged by identity
/// and ordered: most waiting work items first, then oldest, then identity as
/// bytes, with the held ones after.
fn gather(person: bool, at: Option<&str>) -> Result<Pending, Failure> {
    let mut merged: BTreeMap<String, (Value, bool, Option<String>)> = BTreeMap::new();
    if person {
        let o = koto::run(&["decisions", "open", "--person=owner"])?;
        for q in o
            .get("questions")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
        {
            if let Some(id) = q.get("identity").and_then(Value::as_str) {
                merged.insert(id.to_string(), (q.clone(), true, None));
            }
        }
    }
    if let Some(at) = at {
        let at_arg = format!("--at={at}");
        let o = koto::run(&["decisions", "open", &at_arg])?;
        for q in o
            .get("questions")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
        {
            let Some(id) = q.get("identity").and_then(Value::as_str) else {
                continue;
            };
            let relation = q
                .get("relation")
                .and_then(Value::as_str)
                .map(str::to_string);
            merged
                .entry(id.to_string())
                .and_modify(|e| e.2 = relation.clone())
                .or_insert((q.clone(), false, relation));
        }
    }
    let now = now_seconds();
    let mut origins = BTreeMap::new();
    let mut questions = Vec::new();
    let mut incomplete = Vec::new();
    for (identity, (q, for_owner, relation)) in merged {
        let h = History::read(&identity)?;
        let raiser = h.raiser();
        let qid = h.id();
        let stored = read_stored(&identity, h.packet().as_deref())?;
        let content = match stored {
            Stored::Good(c) => Some(*c),
            Stored::NoPacket => None,
            other => {
                let reason = match other {
                    Stored::Missing => "no content is stored for it",
                    Stored::Mismatch => "its stored content does not hash to its packet",
                    _ => "its stored content is not in the form shirabe stores",
                };
                incomplete.push(json!({
                    "identity": identity,
                    "session": raiser,
                    "reason": reason,
                    "withdraw": format!("koto decisions answer {raiser} {qid} --in {raiser} --outcome withdrawn --reason 'incomplete question' --by session"),
                }));
                continue;
            }
        };
        let time = q
            .get("time")
            .and_then(Value::as_str)
            .or_else(|| h.raw.pointer("/question/time").and_then(Value::as_str))
            .unwrap_or("")
            .to_string();
        let addressee = q.get("addressee").cloned().unwrap_or(Value::Null);
        let addressee_s = recipient_string(&addressee);
        let other_person = addressee_s
            .as_str()
            .is_some_and(|s| s.starts_with("person:") && s != format!("person:{OWNER}"));
        let depends_on = content.as_ref().and_then(|c| c.depends_on.clone());
        // Held while the question it depends on is open; one koto answers it
        // doesn't hold holds nothing.
        let held = match &depends_on {
            Some(d) => history_if_any(d)?.is_some_and(|dh| dh.open()),
            None => false,
        };
        let waiting = content.as_ref().map_or(0, |c| c.waiting.len());
        let mut e = Map::new();
        e.insert("identity".into(), json!(identity));
        e.insert("session".into(), json!(raiser));
        e.insert("id".into(), json!(qid));
        e.insert(
            "question".into(),
            match &content {
                Some(c) => json!(c.ask),
                None => q.get("text").cloned().unwrap_or(Value::Null),
            },
        );
        e.insert(
            "label".into(),
            content.as_ref().map(|c| json!(c.label)).unwrap_or_else(|| {
                h.raw
                    .pointer("/question/label")
                    .cloned()
                    .unwrap_or(Value::Null)
            }),
        );
        e.insert("need".into(), q.get("need").cloned().unwrap_or(Value::Null));
        e.insert("waiting".into(), json!(waiting));
        e.insert("raised".into(), json!(time));
        e.insert(
            "age_seconds".into(),
            epoch_seconds(&time).map_or(Value::Null, |t| json!((now - t).max(0))),
        );
        e.insert(
            "recipient".into(),
            recipient_string(q.get("recipient").unwrap_or(&Value::Null)),
        );
        e.insert("addressee".into(), addressee_s.clone());
        e.insert("relation".into(), relation.map_or(Value::Null, Value::from));
        e.insert(
            "for_owner".into(),
            json!(for_owner || addressee_s == json!(format!("person:{OWNER}"))),
        );
        e.insert("other_person".into(), json!(other_person));
        e.insert(
            "standing".into(),
            json!(content.as_ref().is_some_and(Content::any_standing)),
        );
        e.insert(
            "unlinked".into(),
            json!(origin_unrecorded(&raiser, &mut origins)?),
        );
        e.insert(
            "depends_on".into(),
            depends_on.map_or(Value::Null, Value::from),
        );
        e.insert("held".into(), json!(held));
        // Whether the session listing recorded a pass-up of this question:
        // it then waits on someone above that session.
        e.insert(
            "passed_up".into(),
            json!(at.is_some_and(|at| h.entries().iter().any(|x| {
                x.get("entry").and_then(Value::as_str) == Some("pass-up")
                    && x.get("session").and_then(Value::as_str) == Some(at)
            }))),
        );
        e.insert("stored".into(), json!(content.is_some()));
        if let Some(s) = q.get("state") {
            e.insert("state".into(), s.clone());
        }
        questions.push(Listed {
            identity,
            element: e,
            waiting,
            time,
            held,
            content,
            header: None,
        });
        let _ = &raiser;
    }
    questions.sort_by(|a, b| {
        a.held
            .cmp(&b.held)
            .then(b.waiting.cmp(&a.waiting))
            .then(epoch_order(&a.time).cmp(&epoch_order(&b.time)))
            .then(a.identity.as_bytes().cmp(b.identity.as_bytes()))
    });
    Ok(Pending {
        questions,
        incomplete,
    })
}

/// A koto time as nanoseconds since the epoch, its fraction included, so
/// times written at different precisions order by the instant they name. A
/// time that does not parse sorts last.
fn epoch_order(t: &str) -> i128 {
    epoch_nanos(t).unwrap_or(i128::MAX)
}

fn epoch_nanos(t: &str) -> Option<i128> {
    let secs = epoch_seconds(t)? as i128;
    let frac = match t.as_bytes()[19] {
        b'Z' if t.len() == 20 => "",
        b'.' => &t[20..t.len() - 1],
        _ => return None,
    };
    if frac.len() > 9 || (t.as_bytes()[19] == b'.' && frac.is_empty()) {
        return None;
    }
    if !frac.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let mut nanos: i128 = 0;
    for i in 0..9 {
        let d = frac.as_bytes().get(i).map_or(0, |b| (b - b'0') as i128);
        nanos = nanos * 10 + d;
    }
    Some(secs * 1_000_000_000 + nanos)
}

/// The answers that have arrived for `session` and that no decision in its
/// run cites yet: to questions it raised, and owner answers given at or below
/// it.
fn answered(session: &str) -> Result<Vec<Value>, Failure> {
    let mut out: BTreeMap<String, Value> = BTreeMap::new();
    let listed = koto::run(&[
        "decisions",
        "list",
        "--format=v1",
        "--kind=escalate",
        "--",
        session,
    ])?;
    for d in listed
        .get("decisions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
    {
        let Some(sid) = d.pointer("/decision/session/id").and_then(Value::as_str) else {
            continue;
        };
        let Some(id) = d.get("id").and_then(Value::as_str) else {
            continue;
        };
        let identity = format!("{sid}/{id}");
        let Some(h) = history_if_any(&identity)? else {
            continue;
        };
        let Some(ans) = h.answer() else { continue };
        if ans.get("outcome").and_then(Value::as_str) != Some("answered") {
            continue;
        }
        let ans_id = ans.get("id").and_then(Value::as_str);
        let ans_session = ans.get("session").and_then(Value::as_str);
        let cited = h.entries().iter().any(|e| {
            e.get("entry").and_then(Value::as_str) == Some("citing")
                && e.get("session").and_then(Value::as_str) == Some(session)
        });
        if cited || ans_id.is_none() || ans_session.is_none() {
            continue;
        }
        out.insert(
            identity.clone(),
            json!({"identity": identity, "answer": ans}),
        );
    }
    let chain_arg = format!("--chain={session}");
    let prec = koto::run(&["decisions", "precedent", "--person=owner", &chain_arg])?;
    for a in prec
        .get("answers")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
    {
        let below = a.get("below").and_then(Value::as_bool) == Some(true);
        let here = a.get("session").and_then(Value::as_str) == Some(session);
        if a.get("cited").and_then(Value::as_bool) != Some(false) || !(below || here) {
            continue;
        }
        let Some(identity) = a.get("identity").and_then(Value::as_str) else {
            continue;
        };
        out.entry(identity.to_string())
            .or_insert_with(|| json!({"identity": identity, "answer": a}));
    }
    Ok(out.into_values().collect())
}

/// The owner's answers in effect at or below `session` that no decision in
/// its run cites yet: what reached it as knowledge and that it has not marked
/// seen (`shirabe question seen`). Each carries the question it answers, its
/// label, the answer's text, the session it was given in and koto's
/// `reading`, as koto prints them.
fn unseen(session: &str) -> Result<Vec<Value>, Failure> {
    let chain_arg = format!("--chain={session}");
    let prec = koto::run(&["decisions", "precedent", "--person=owner", &chain_arg])?;
    let mut out = Vec::new();
    for a in prec
        .get("answers")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
    {
        let below = a.get("below").and_then(Value::as_bool) == Some(true);
        let here = a.get("session").and_then(Value::as_str) == Some(session);
        if a.get("cited").and_then(Value::as_bool) != Some(false) || !(below || here) {
            continue;
        }
        let Some(identity) = a.get("identity").and_then(Value::as_str) else {
            continue;
        };
        let question = match history_if_any(identity)? {
            Some(h) => h
                .raw
                .pointer("/question/text")
                .cloned()
                .unwrap_or(Value::Null),
            None => Value::Null,
        };
        let answer_session = a.get("session").cloned().unwrap_or(Value::Null);
        let answer_id = a.get("id").cloned().unwrap_or(Value::Null);
        let answer = match (answer_session.as_str(), answer_id.as_str()) {
            (Some(s), Some(i)) => json!(format!("{s}:{i}")),
            _ => Value::Null,
        };
        out.push(json!({
            "identity": identity,
            "question": question,
            "label": a.get("label").cloned().unwrap_or(Value::Null),
            "text": a.get("text").cloned().unwrap_or(Value::Null),
            "session": answer_session,
            "id": answer_id,
            "answer": answer,
            "reading": a.get("reading").cloned().unwrap_or(Value::Null),
            "time": a.get("time").cloned().unwrap_or(Value::Null),
        }));
    }
    Ok(out)
}

fn owner_only(person: Option<&str>) -> Result<bool, Failure> {
    match person {
        None => Ok(false),
        Some(OWNER) => Ok(true),
        Some(p) => Err(Failure::refused(
            "person",
            format!("--person {p}: these commands take one person handle, {OWNER}"),
        )),
    }
}

fn pending_cmd(a: &PendingArgs) -> Result<Value, Failure> {
    check_name("in", "--in", &a.in_)?;
    if let Some(at) = &a.at {
        check_name("at", "--at", at)?;
    }
    koto::check_version()?;
    let person = owner_only(a.person.as_deref())?;
    let (person, at) = match (person, a.at.as_deref()) {
        (false, None) => (true, Some(a.in_.as_str())),
        (p, at) => (p, at),
    };
    let p = gather(person, at)?;
    let (held, ready): (Vec<_>, Vec<_>) = p.questions.into_iter().partition(|q| q.held);
    let answered = answered(&a.in_)?;
    let unseen = unseen(&a.in_)?;
    Ok(json!({
        "v": 1,
        "in": a.in_,
        "questions": ready.into_iter().map(|q| Value::Object(q.element)).collect::<Vec<_>>(),
        "held": held.into_iter().map(|q| Value::Object(q.element)).collect::<Vec<_>>(),
        "incomplete": p.incomplete,
        "answered": answered,
        "unseen": unseen,
    }))
}

// ---------------------------------------------------------------------------
// render

fn render_item(identity: &str) -> Result<render::Item, Failure> {
    let h = History::read(identity)?;
    if !h.open() {
        // Presenting a closed question would ask the owner again.
        let state = h
            .answer()
            .and_then(|a| a.get("outcome"))
            .and_then(Value::as_str)
            .unwrap_or("closed")
            .to_string();
        return Err(Failure::new(
            EXIT_CLOSED,
            "question_closed",
            format!("{identity} is no longer open (it reads as {state}); a closed question is not presented"),
        )
        .with("identity", json!(identity))
        .with("state", json!(state)));
    }
    match read_stored(identity, h.packet().as_deref())? {
        Stored::Good(c) => {
            let header = koto::prompt_header(&h.raiser(), &h.id())?;
            Ok(render::Item {
                identity: identity.to_string(),
                header,
                content: *c,
            })
        }
        Stored::NoPacket => Err(Failure::unpresentable(
            "no_content",
            format!("{identity} was raised with no stored content; it cannot be presented"),
        )
        .with("identity", json!(identity))),
        Stored::Missing => Err(Failure::unpresentable(
            "content_missing",
            format!("{identity} has no stored content; it cannot be presented"),
        )
        .with("identity", json!(identity))),
        Stored::Mismatch => Err(Failure::unpresentable(
            "content_mismatch",
            format!("content mismatch: the stored content of {identity} does not hash to its packet; it is not presented"),
        )
        .with("identity", json!(identity))),
        Stored::Unreadable => Err(Failure::unpresentable(
            "content_unreadable",
            format!("the stored content of {identity} is not in the form shirabe stores; it is not presented"),
        )
        .with("identity", json!(identity))),
    }
}

fn render_cmd(a: &RenderArgs) -> Result<Value, Failure> {
    if let Some(s) = &a.in_ {
        check_name("in", "--in", s)?;
    }
    for identity in &a.identities {
        check_identity(identity)?;
    }
    koto::check_version()?;
    if owner_only(a.person.as_deref())? {
        let p = gather(true, None)?;
        let mut items = Vec::new();
        let mut held = Vec::new();
        // The open questions that cannot be presented, listed as `pending`
        // lists them rather than dropped without a word.
        let mut incomplete = p.incomplete;
        for mut q in p.questions {
            if q.held {
                held.push(q.identity);
                continue;
            }
            let Some(content) = q.content.take() else {
                incomplete.push(json!({
                    "identity": q.identity,
                    "session": q.element.get("session").cloned().unwrap_or(Value::Null),
                    "reason": "it was raised with no stored content",
                }));
                continue;
            };
            let raiser = q
                .element
                .get("session")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let id = q
                .element
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            let header = match q.header.take() {
                Some(h) => h,
                None => koto::prompt_header(&raiser, &id)?,
            };
            items.push(render::Item {
                identity: q.identity,
                header,
                content,
            });
        }
        let mut out = render::render(&items, &held);
        out["incomplete"] = Value::Array(incomplete);
        return Ok(out);
    }
    let mut items = Vec::new();
    for identity in &a.identities {
        items.push(render_item(identity)?);
    }
    Ok(render::render(&items, &[]))
}

// ---------------------------------------------------------------------------
// answer

/// What `answer` says when there is no answered prompt to point at.
pub const RELAYED: &str = "No answered prompt records the owner's answer here, so nothing was recorded for the owner. \
A relayed claim (\"the owner said ...\") is not the owner's answer: record it as this session's own decision with the owner noted, \
`shirabe question settle --in <session> --what <question> --chosen <choice> --owner-note \"the owner said ...\"`. \
That decision closes no question waiting on the owner and grants nothing to another session. The question stays open.";

/// Whether standard input holds data now, without blocking.
fn stdin_has_data() -> bool {
    use std::os::fd::AsRawFd;
    let stdin = std::io::stdin();
    let fd = stdin.as_raw_fd();
    // SAFETY: isatty and poll read a descriptor we hold; the pollfd is ours.
    unsafe {
        if libc::isatty(fd) == 1 {
            return false;
        }
        let mut p = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        if libc::poll(&mut p, 1, 0) != 1 || p.revents & libc::POLLIN == 0 {
            return false;
        }
    }
    let mut one = [0u8; 1];
    matches!(stdin.lock().read(&mut one), Ok(n) if n > 0)
}

fn reading_of(shown: &Value) -> Value {
    shown
        .get("reading")
        .or_else(|| shown.pointer("/decision/reading"))
        .cloned()
        .unwrap_or(Value::Null)
}

fn attempt_cmd(a: &AttemptArgs) -> Result<Value, Failure> {
    attempt::run(&attempt::Input {
        session: &a.in_,
        what: &a.what,
        result: &a.result,
        state: a.state.as_deref(),
        chosen: a.chosen.as_deref(),
        undo: a.undo.as_deref(),
        undo_reason: a.undo_reason.as_deref(),
        ground: a.ground.as_deref(),
        basis: &a.basis,
    })
}

fn answer_cmd(a: &AnswerArgs) -> Result<Value, Failure> {
    // The koto minimum comes first, so a koto too old to verify a prompt
    // exits 3 whatever else is wrong; `koto version` takes no caller value.
    koto::check_version()?;
    check_name("in", "--in", &a.in_)?;
    check_identity(&a.identity)?;
    if stdin_has_data() {
        return Err(Failure::usage(
            "answer takes no answer text, on standard input or otherwise: the answer is what the person chose in the prompt",
        ));
    }
    if run_mode() == RunMode::Unattended {
        return Err(Failure::refused(
            "run_mode",
            "this session runs unattended, so no person answered a prompt in it; nothing was recorded",
        ));
    }
    let h = History::read(&a.identity)?;
    let (raiser, id) = (h.raiser(), h.id());
    let header = koto::prompt_header(&raiser, &id)?;
    let sid = std::env::var("CLAUDE_CODE_SESSION_ID").unwrap_or_default();
    let unverifiable = |check: &str, why: &str| {
        let mut f = Failure::new(
            EXIT_KOTO_REFUSED,
            "prompt_unverified",
            format!("{why} The owner's answer cannot be verified from this session, and {} is still open. {RELAYED}", a.identity),
        );
        f.check = Some(check.to_string());
        f.field = Some("prompt".into());
        f
    };
    let (call, position) = match (&a.call, a.position) {
        (Some(c), Some(p)) => (c.clone(), p as usize),
        _ => {
            if std::env::var_os("CLAUDE_CONFIG_DIR").is_some() {
                return Err(unverifiable(
                    "record",
                    "CLAUDE_CONFIG_DIR is set, so this harness keeps its record where koto does not read it.",
                ));
            }
            if sid.is_empty() {
                return Err(unverifiable(
                    "call",
                    "No harness session id (CLAUDE_CODE_SESSION_ID) names a record to look in.",
                ));
            }
            let found = answer::account_home()
                .and_then(|home| answer::record_path(&home, &sid))
                .and_then(|p| answer::find_call(&p, &header));
            match found {
                Some(f) => f,
                None => {
                    return Err(unverifiable(
                        "call",
                        &format!("No question-tool call in this session's record carries the header {header}."),
                    ))
                }
            }
        }
    };
    let pointer = format!("{sid}/{call}/{position}");
    let in_arg = format!("--in={}", a.in_);
    let by_arg = format!("--by=person:{OWNER}");
    let prompt_arg = format!("--prompt={pointer}");
    let rec = koto::run(&[
        "decisions",
        "answer",
        &in_arg,
        &by_arg,
        &prompt_arg,
        "--",
        &raiser,
        &id,
    ]);
    let rec = match rec {
        Ok(r) => r,
        Err(r) => {
            let mut f = Failure::koto(&r);
            if r.check.as_deref() == Some("record") || r.check.as_deref() == Some("call") {
                f.message = format!("{} The owner's answer cannot be verified from this session, and {} is still open. {RELAYED}", f.message, a.identity);
            }
            return Err(f);
        }
    };
    let entry = rec
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let session = rec
        .get("session")
        .and_then(Value::as_str)
        .unwrap_or(&a.in_)
        .to_string();
    // From here koto holds the answer. A failed read-back is not a refusal:
    // it exits 7 with the entry, so the caller does not answer again and run
    // into koto's call-position-reused check.
    let shown = match koto::run(&["decisions", "show", "--", &session, &entry]) {
        Ok(s) => s,
        Err(r) => {
            return Err(Failure::new(
                EXIT_UNCONFIRMED,
                "answer_unconfirmed",
                format!("koto recorded the owner's answer as entry {session}:{entry}, but reading it back failed ({}: {}); do not answer again: read it with `koto decisions show {session} {entry}`", r.code, r.error),
            )
            .with("identity", json!(a.identity))
            .with("entry", json!(format!("{session}:{entry}")))
            .with("prompt", json!(pointer)));
        }
    };
    let reading = reading_of(&shown);
    if reading.as_str() != Some("verified") {
        let reads_as = match &reading {
            Value::String(s) => s.clone(),
            Value::Null => "no reading at all".to_string(),
            other => other.to_string(),
        };
        return Err(Failure::unpresentable(
            "not_verified",
            format!("koto recorded the entry {session}:{entry}, but it does not read as verified here: koto reads it as {reads_as}, so it carries no authority of the owner in this session"),
        )
        .with("reading", reading)
        .with("entry", json!(format!("{session}:{entry}"))));
    }
    Ok(json!({
        "v": 1,
        "identity": a.identity,
        "session": session,
        "id": entry,
        "prompt": pointer,
        "reading": reading,
        "text": shown.pointer("/decision/text").or_else(|| shown.pointer("/decision/subject/text")).cloned().unwrap_or(Value::Null),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn epoch_of_a_koto_time() {
        assert_eq!(epoch_seconds("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(epoch_seconds("2026-11-27T09:33:58.639Z"), Some(1795772038));
    }

    #[test]
    fn mixed_precision_times_order_by_instant() {
        // As strings, ".5Z" sorts after ".123456Z" and "Z" after both; as
        // instants the whole second comes first and .123456 before .5.
        let whole = epoch_order("2026-11-27T09:00:00Z");
        let micro = epoch_order("2026-11-27T09:00:00.123456Z");
        let tenth = epoch_order("2026-11-27T09:00:00.5Z");
        let milli = epoch_order("2026-11-27T09:00:00.500Z");
        assert!(whole < micro && micro < tenth);
        assert_eq!(tenth, milli);
        assert!(epoch_order("2026-11-27T08:59:59.999999999Z") < whole);
        for bad in [
            "2026-11-27T09:00:00.Z",
            "2026-11-27T09:00:00.1234567890Z",
            "x",
        ] {
            assert_eq!(epoch_order(bad), i128::MAX, "{bad}");
        }
    }

    #[test]
    fn session_names_are_koto_shaped() {
        for ok in ["manager", "a1", "task_x-1.2", "A"] {
            assert!(check_name("in", "--in", ok).is_ok(), "{ok}");
        }
        for bad in ["--help", "-x", "", "a b", "a/b", ".a", "_a", "a\n"] {
            assert_eq!(
                check_name("in", "--in", bad).unwrap_err().exit,
                EXIT_REFUSED,
                "{bad:?}"
            );
        }
    }

    #[test]
    fn recipients() {
        assert!(parse_recipient("session:manager").is_ok());
        assert!(parse_recipient("anchor:a1").is_ok());
        assert!(parse_recipient("person:owner").is_ok());
        for bad in [
            "coord",
            "session:",
            "session:-x",
            "robot:x",
            "person:someone-else",
        ] {
            assert_eq!(
                parse_recipient(bad).unwrap_err().field.as_deref(),
                Some("to"),
                "{bad}"
            );
        }
    }

    #[test]
    fn states() {
        assert!(state_ok("implement:1"));
        assert!(!state_ok("implement:0"));
        assert!(!state_ok("implement:01"));
        assert!(!state_ok("implement"));
    }
}
