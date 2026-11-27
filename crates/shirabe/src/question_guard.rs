//! `shirabe hook question-guard`: the plugin's PreToolUse hook on the
//! question tool (`AskUserQuestion`).
//!
//! A question prompt opened in a turn no person started blocks a session
//! that nobody is watching, so the guard denies it (PRD-decision-escalation-
//! ladder R27). It leaves alone a prompt opened in a turn a person typed, in
//! any session, including one a skill the person invoked opens later in that
//! turn.
//!
//! The rule comes from docs/spikes/SPIKE-question-guard-turn-origin.md, which
//! records what the harness reported for each way a turn starts:
//!
//! - The hook's input names the turn by `prompt_id`. The session record the
//!   input's `transcript_path` names holds, for the entry that started that
//!   turn, `turnOrigin`, `origin.kind`, `promptSource`, `isMeta` and
//!   `turnPosition`. A background-task notification, a scheduled wake-up, a
//!   message from another session and a harness notice each carry a label of
//!   their own there, and the guard denies them.
//! - A continuation a Stop hook injected keeps the person's `prompt_id`; the
//!   injected entry carries `rowSource: "hook"` (and `hookText: true`), and
//!   the guard denies a turn holding one.
//! - A call from a subagent carries `agent_id` in the hook's input, and the
//!   guard denies it.
//! - A dispatch brief carries the same label as a typed prompt, and it is
//!   always the session's first turn (`turnIndex` 1). A typed turn later in
//!   the session is a person's, and is allowed whatever the run mode. A typed
//!   first turn, the prompt that opened a copy of another session, and a turn
//!   whose origin can't be read at all fall back to the run mode: denied when
//!   the session is unattended, allowed otherwise.
//!
//! The run mode is `CLAUDE_CODE_SESSION_ATTENDED`, which the harness sets for
//! every hook (1 attended, 0 unattended). It reports a background session as
//! unattended for its whole life, even while a person is attached and typing,
//! so it decides only the turns the record can't place. Any other value, or
//! none, is no recorded run mode, which is not unattended.
//!
//! The origin is taken only from structured fields, never from message text.
//! The record is opened only when its path, with symbolic links resolved, is
//! a `.jsonl` regular file under the harness's session records, and no line
//! longer than `MAX_LINE` is buffered. The guard decides only for the
//! question tool, prints nothing or one deny line, never `allow` or `ask`,
//! and writes nothing. `SHIRABE_PRE_ACTION_HOOK=off` turns it off, as it
//! turns off the plugin's Bash hook.

use std::fs::File;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use serde_json::Value;

/// The tool the guard covers.
pub const QUESTION_TOOL: &str = "AskUserQuestion";

/// The deny reason: constant text, quoted in full in README.md.
pub const REASON: &str =
    "A question prompt was denied because no person typed the message that started this turn. \
Do not open a question prompt again in this turn. \
Hand the question to whoever dispatched this session, or record it by the means you already have, \
then continue with work that does not depend on the answer. \
The person running this host can turn this guard off by setting SHIRABE_PRE_ACTION_HOOK to off \
in the env block of their Claude Code settings.";

/// The session's run mode, from `CLAUDE_CODE_SESSION_ATTENDED`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RunMode {
    Attended,
    Unattended,
    /// No run mode recorded: the variable is unset or holds another value.
    Unknown,
}

impl RunMode {
    pub fn from_value(v: Option<&str>) -> Self {
        match v {
            Some("1") => RunMode::Attended,
            Some("0") => RunMode::Unattended,
            _ => RunMode::Unknown,
        }
    }
}

/// What the guard reads from its environment, gathered once so tests can
/// supply it.
#[derive(Debug, Clone)]
pub struct Env {
    /// `SHIRABE_PRE_ACTION_HOOK` is exactly `off`.
    pub off: bool,
    pub run_mode: RunMode,
    /// The harness's own directory: `CLAUDE_CONFIG_DIR` when absolute, else
    /// `$HOME/.claude`; `None` when neither names one.
    pub harness_dir: Option<PathBuf>,
}

impl Env {
    pub fn from_process() -> Self {
        let config = std::env::var_os("CLAUDE_CONFIG_DIR")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute());
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .map(|h| h.join(".claude"));
        Env {
            off: std::env::var("SHIRABE_PRE_ACTION_HOOK").ok().as_deref() == Some("off"),
            run_mode: RunMode::from_value(
                std::env::var("CLAUDE_CODE_SESSION_ATTENDED")
                    .ok()
                    .as_deref(),
            ),
            harness_dir: config.or(home),
        }
    }
}

/// Where the turn the call is in came from, as far as the record shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    /// Labelled as typed by a person. A dispatch brief, and a prompt given
    /// on the command line to a background session, carry the same label.
    TypedLabel,
    /// Labelled as something no person typed: a background-task
    /// notification, a scheduled wake-up, a message from another session, a
    /// harness notice, or a hook-injected continuation.
    NotTyped,
    /// Not established: no record, a record outside the harness's session
    /// records, no entry for the turn, an over-long line naming the turn, or
    /// a label the spike's capture never showed for a person (`sdk` among
    /// them).
    Unknown,
}

/// What the record shows about the turn the call is in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Turn {
    pub origin: Origin,
    /// The turn may be the first the session was given: its entry sits at a
    /// `turnIndex` below 2, it opened a copy of another session, or its position
    /// isn't recorded. A dispatch brief is always such a turn; a person's
    /// later turn never is.
    pub opening: bool,
}

/// The labels the capture showed for turns no person typed.
const NOT_TYPED_TURN_ORIGINS: [&str; 4] = ["task_notification", "scheduled", "peer", "system"];
const NOT_TYPED_ORIGIN_KINDS: [&str; 2] = ["task-notification", "peer"];
/// The prompt sources the capture showed for text a person entered: typed,
/// typed while a turn was running, and a suggested prompt the person
/// accepted. A typed slash command carries none.
const TYPED_PROMPT_SOURCES: [&str; 3] = ["typed", "queued", "suggestion_accepted"];

/// The longest record line the guard buffers. A longer line that names the
/// turn leaves its origin not established.
pub const MAX_LINE: usize = 4 << 20;

fn str_field<'a>(v: &'a Value, key: &str) -> Option<&'a str> {
    v.get(key).and_then(Value::as_str)
}

fn is_true(v: &Value, key: &str) -> bool {
    v.get(key) == Some(&Value::Bool(true))
}

/// One record entry's contribution, or `None` when it carries no origin
/// fields (a tool result, a skill's expanded text, a queued notice).
pub fn classify_entry(e: &Value) -> Option<Origin> {
    if str_field(e, "rowSource") == Some("hook") || is_true(e, "hookText") {
        return Some(Origin::NotTyped);
    }
    let turn = e.get("turnOrigin").filter(|v| !v.is_null());
    let origin = e.get("origin").filter(|v| !v.is_null());
    if turn.is_none() && origin.is_none() {
        return None;
    }
    let turn = turn.and_then(Value::as_str);
    let kind = origin.and_then(|o| str_field(o, "kind"));
    let source = e.get("promptSource").filter(|v| !v.is_null());
    if turn.is_some_and(|t| NOT_TYPED_TURN_ORIGINS.contains(&t))
        || kind.is_some_and(|k| NOT_TYPED_ORIGIN_KINDS.contains(&k))
        || source.and_then(Value::as_str) == Some("system")
        || is_true(e, "isMeta")
    {
        return Some(Origin::NotTyped);
    }
    let source_typed = match source {
        None => true,
        Some(s) => s
            .as_str()
            .is_some_and(|s| TYPED_PROMPT_SOURCES.contains(&s)),
    };
    let kind_human = match origin {
        None => true,
        Some(_) => kind == Some("human"),
    };
    if turn == Some("human") && kind_human && source_typed {
        Some(Origin::TypedLabel)
    } else {
        Some(Origin::Unknown)
    }
}

/// Calls `each` with every record line of at most `MAX_LINE` bytes that
/// contains `needle`. Returns false on a read error or when a longer line
/// contains `needle`; such a line is scanned in pieces, never buffered.
fn scan_lines<R: BufRead>(mut reader: R, needle: &[u8], mut each: impl FnMut(&[u8])) -> bool {
    let keep = needle.len().saturating_sub(1);
    let mut line = Vec::new();
    loop {
        line.clear();
        match (&mut reader)
            .take(MAX_LINE as u64 + 1)
            .read_until(b'\n', &mut line)
        {
            Ok(0) => return true,
            Ok(_) => {}
            Err(_) => return false,
        }
        if line.len() <= MAX_LINE || line.last() == Some(&b'\n') {
            if contains(&line, needle) {
                each(&line);
            }
            continue;
        }
        // Over the bound: look for the turn in the rest of the line, keeping
        // only enough bytes to catch a match split across two pieces.
        let mut hit = contains(&line, needle);
        let mut window = line.split_off(line.len() - keep.min(line.len()));
        loop {
            let start = window.len();
            match (&mut reader).take(1 << 16).read_until(b'\n', &mut window) {
                Ok(0) => break,
                Ok(_) => {}
                Err(_) => return false,
            }
            hit |= contains(&window, needle);
            let done = window.last() == Some(&b'\n');
            if done || start == window.len() {
                break;
            }
            window.drain(..window.len() - keep.min(window.len()));
        }
        if hit {
            return false;
        }
    }
}

/// What the record's entries for `prompt_id` show about the turn.
///
/// An entry belongs to the turn when its `turnPromptId` (or, without one,
/// its `promptId`) is `prompt_id`; a compaction summary restates an earlier
/// entry and is skipped. Any entry labelled as not typed wins, then any
/// label the capture never showed for a person; otherwise a typed label, and
/// with no labelled entry at all, unknown. The turn is the session's opening
/// one when an entry of it sits at a `turnIndex` below 2, when its position
/// isn't recorded, or when earlier turns' entries carry its `promptId`, which
/// a copy of another session writes for the prompt that started the copy.
/// When a line naming the turn is too long to read, a not-typed label or a
/// typed label placed after the first turn, read from its other entries,
/// still stands; otherwise the origin is unknown.
pub fn turn_from_record<R: BufRead>(reader: R, prompt_id: &str) -> Turn {
    let unknown = Turn {
        origin: Origin::Unknown,
        opening: true,
    };
    let mut typed = false;
    let mut odd = false;
    let mut not_typed = false;
    let mut later = false;
    let mut first = false;
    let mut copy = false;
    let complete = scan_lines(reader, prompt_id.as_bytes(), |line| {
        let Ok(e) = serde_json::from_slice::<Value>(line) else {
            return;
        };
        if str_field(&e, "type") != Some("user") || is_true(&e, "isCompactSummary") {
            return;
        }
        let pid = str_field(&e, "promptId");
        let turn_pid = str_field(&e, "turnPromptId").or(pid);
        if turn_pid != Some(prompt_id) {
            if pid == Some(prompt_id) && e.get("turnOrigin").is_some() {
                copy = true;
            }
            return;
        }
        let Some(origin) = classify_entry(&e) else {
            return;
        };
        match origin {
            Origin::NotTyped => not_typed = true,
            Origin::Unknown => odd = true,
            Origin::TypedLabel => typed = true,
        }
        match e
            .get("turnPosition")
            .and_then(|p| p.get("turnIndex"))
            .and_then(Value::as_u64)
        {
            Some(i) if i < 2 => first = true,
            Some(_) => later = true,
            None => {}
        }
    });
    if !complete {
        // An entry of the turn was too long to read. Keep what the entries
        // already read settled: a not-typed label still denies, and a typed
        // label placed after the first turn still stands. Anything else is
        // unknown.
        if not_typed {
            return Turn {
                origin: Origin::NotTyped,
                opening: first || copy || !later,
            };
        }
        if typed && !odd && later && !first && !copy {
            return Turn {
                origin: Origin::TypedLabel,
                opening: false,
            };
        }
        return unknown;
    }
    let origin = if not_typed {
        Origin::NotTyped
    } else if odd || !typed {
        Origin::Unknown
    } else {
        Origin::TypedLabel
    };
    Turn {
        origin,
        opening: first || copy || !later,
    }
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && hay.windows(needle.len()).any(|w| w == needle)
}

/// The record path, resolved, when it is a `.jsonl` regular file under the
/// harness's session records (`<harness dir>/projects/`); `None` otherwise,
/// and then nothing is opened.
pub fn checked_record_path(path: &str, harness_dir: Option<&Path>) -> Option<PathBuf> {
    let p = Path::new(path);
    if !p.is_absolute() {
        return None;
    }
    let root = std::fs::canonicalize(harness_dir?.join("projects")).ok()?;
    let resolved = std::fs::canonicalize(p).ok()?;
    if !resolved.starts_with(&root)
        || resolved.extension().and_then(|x| x.to_str()) != Some("jsonl")
    {
        return None;
    }
    if !std::fs::metadata(&resolved).ok()?.is_file() {
        return None;
    }
    Some(resolved)
}

fn read_turn(input: &Value, env: &Env) -> Turn {
    let unknown = Turn {
        origin: Origin::Unknown,
        opening: true,
    };
    let (Some(path), Some(prompt_id)) = (
        str_field(input, "transcript_path"),
        str_field(input, "prompt_id").filter(|s| !s.is_empty()),
    ) else {
        return unknown;
    };
    let Some(resolved) = checked_record_path(path, env.harness_dir.as_deref()) else {
        return unknown;
    };
    match File::open(resolved) {
        Ok(f) => turn_from_record(BufReader::with_capacity(1 << 16, f), prompt_id),
        Err(_) => unknown,
    }
}

/// True when the call should be denied.
pub fn should_deny(input: &[u8], env: &Env) -> bool {
    if env.off {
        return false;
    }
    let Ok(v) = serde_json::from_slice::<Value>(input) else {
        return false;
    };
    if str_field(&v, "tool_name") != Some(QUESTION_TOOL) {
        return false;
    }
    if str_field(&v, "agent_id").is_some_and(|a| !a.is_empty()) {
        return true;
    }
    let turn = read_turn(&v, env);
    match turn.origin {
        Origin::NotTyped => true,
        // A person's later turn, in any session.
        Origin::TypedLabel if !turn.opening => false,
        // A dispatch brief can't be told from a typed first prompt.
        Origin::TypedLabel | Origin::Unknown => env.run_mode == RunMode::Unattended,
    }
}

/// The deny line, one JSON object.
pub fn deny_line() -> String {
    serde_json::json!({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }
    })
    .to_string()
}

/// Reads the hook input on stdin and prints a deny or nothing. Always exits 0.
pub fn run() -> ExitCode {
    let mut input = Vec::new();
    if std::io::stdin().read_to_end(&mut input).is_err() {
        return ExitCode::SUCCESS;
    }
    if should_deny(&input, &Env::from_process()) {
        println!("{}", deny_line());
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn turn_of(rows: &[Value], pid: &str) -> Turn {
        let text: String = rows.iter().map(|r| format!("{r}\n")).collect();
        turn_from_record(text.as_bytes(), pid)
    }

    fn origin_of(rows: &[Value], pid: &str) -> Origin {
        turn_of(rows, pid).origin
    }

    fn typed(pid: &str, index: u64) -> Value {
        json!({"type":"user","promptId":pid,"turnPromptId":pid,"origin":{"kind":"human"},
               "promptSource":"typed","turnOrigin":"human",
               "turnPosition":{"promptIndex":index,"turnIndex":index}})
    }

    #[test]
    fn typed_entry_is_a_typed_label() {
        let e = json!({"type":"user","promptId":"p","origin":{"kind":"human"},"promptSource":"typed","turnOrigin":"human"});
        assert_eq!(origin_of(&[e], "p"), Origin::TypedLabel);
    }

    #[test]
    fn typed_slash_command_has_no_prompt_source() {
        let e =
            json!({"type":"user","promptId":"p","origin":{"kind":"human"},"turnOrigin":"human"});
        assert_eq!(origin_of(&[e], "p"), Origin::TypedLabel);
    }

    #[test]
    fn queued_and_accepted_suggestions_are_typed() {
        for s in ["queued", "suggestion_accepted"] {
            let e = json!({"type":"user","promptId":"p","origin":{"kind":"human"},"promptSource":s,"turnOrigin":"human"});
            assert_eq!(origin_of(&[e], "p"), Origin::TypedLabel, "{s}");
        }
    }

    #[test]
    fn notification_scheduled_peer_and_system_are_not_typed() {
        for e in [
            json!({"type":"user","promptId":"p","origin":{"kind":"task-notification"},"promptSource":"system","turnOrigin":"task_notification"}),
            json!({"type":"user","promptId":"p","promptSource":"system","turnOrigin":"scheduled","isMeta":true}),
            json!({"type":"user","promptId":"p","origin":{"kind":"peer"},"promptSource":"system","turnOrigin":"peer","isMeta":true}),
            json!({"type":"user","promptId":"p","promptSource":"system","turnOrigin":"system","isMeta":true}),
            json!({"type":"user","promptId":"p","turnOrigin":"system"}),
            json!({"type":"user","promptId":"p","turnOrigin":"human","isMeta":true}),
            json!({"type":"user","promptId":"p","turnOrigin":"human","promptSource":"system"}),
        ] {
            assert_eq!(
                origin_of(std::slice::from_ref(&e), "p"),
                Origin::NotTyped,
                "{e}"
            );
        }
    }

    #[test]
    fn hook_row_after_a_typed_entry_is_not_typed() {
        let hook =
            json!({"type":"user","promptId":"p","isMeta":true,"rowSource":"hook","hookText":true});
        assert_eq!(origin_of(&[typed("p", 2), hook], "p"), Origin::NotTyped);
    }

    #[test]
    fn sdk_unseen_and_absent_labels_are_unknown() {
        let sdk = json!({"type":"user","promptId":"p","promptSource":"sdk","turnOrigin":"sdk",
                         "turnPosition":{"promptIndex":0,"turnIndex":1}});
        assert_eq!(origin_of(&[sdk], "p"), Origin::Unknown);
        let odd =
            json!({"type":"user","promptId":"p","origin":{"kind":"robot"},"turnOrigin":"robot"});
        assert_eq!(origin_of(&[odd], "p"), Origin::Unknown);
        let bare = json!({"type":"user","promptId":"p","message":{"content":"x"}});
        assert_eq!(origin_of(&[bare], "p"), Origin::Unknown);
        assert_eq!(origin_of(&[], "p"), Origin::Unknown);
    }

    #[test]
    fn entries_of_other_turns_are_ignored() {
        let other =
            json!({"type":"user","promptId":"q","origin":{"kind":"peer"},"turnOrigin":"peer"});
        assert_eq!(origin_of(&[other, typed("p", 2)], "p"), Origin::TypedLabel);
    }

    #[test]
    fn position_places_the_turn() {
        assert!(turn_of(&[typed("p", 1)], "p").opening);
        let later = turn_of(&[typed("d", 1), typed("p", 2)], "p");
        assert_eq!(later.origin, Origin::TypedLabel);
        assert!(!later.opening);
        // No recorded position: not placed.
        let e =
            json!({"type":"user","promptId":"p","origin":{"kind":"human"},"turnOrigin":"human"});
        assert!(turn_of(&[e], "p").opening);
    }

    #[test]
    fn a_compaction_summary_does_not_place_the_turn() {
        let summary = json!({"type":"user","promptId":"p","turnPromptId":"p","isCompactSummary":true,
                             "turnOrigin":"human","turnPosition":{"promptIndex":1,"turnIndex":1}});
        let t = turn_of(&[typed("d", 1), typed("p", 2), summary], "p");
        assert_eq!(t.origin, Origin::TypedLabel);
        assert!(!t.opening);
    }

    #[test]
    fn the_prompt_that_opened_a_copy_is_an_opening_turn() {
        // A copy restamps the earlier turns' entries with the new promptId and
        // keeps their own in turnPromptId.
        let mut a = typed("c", 1);
        a["turnPromptId"] = json!("d");
        let mut b = typed("c", 2);
        b["turnPromptId"] = json!("e");
        let t = turn_of(&[a.clone(), b.clone(), typed("c", 3)], "c");
        assert_eq!(t.origin, Origin::TypedLabel);
        assert!(t.opening);
        // A person's later turn in the copy is placed.
        let t = turn_of(&[a, b, typed("c", 3), typed("f", 4)], "f");
        assert!(!t.opening);
        // The restamped entries don't count as the earlier turn's own.
        let mut first = typed("c", 1);
        first["turnPromptId"] = json!("d");
        assert_eq!(turn_of(&[first], "c").origin, Origin::Unknown);
    }

    fn long_row(id: &str) -> String {
        let pad = "x".repeat(MAX_LINE + 10);
        format!("{{\"type\":\"user\",\"promptId\":\"{id}\",\"pad\":\"{pad}\"}}\n")
    }

    #[test]
    fn an_over_long_line_naming_the_turn_leaves_it_unknown() {
        // Nothing settled before it: a typed first turn stays unknown.
        let mut first = format!("{}\n", typed("turn-7f3a", 1));
        first.push_str(&long_row("turn-7f3a"));
        let t = turn_from_record(first.as_bytes(), "turn-7f3a");
        assert_eq!(t.origin, Origin::Unknown);
        assert!(t.opening);
        // A line naming another turn is skipped without being buffered.
        let mut text = format!("{}\n", typed("turn-7f3a", 2));
        text.push_str(&long_row("turn-0c9e"));
        let t = turn_from_record(text.as_bytes(), "turn-7f3a");
        assert_eq!(t.origin, Origin::TypedLabel);
        assert!(!t.opening);
        // A match split across the pieces the scan reads is still found.
        let split = format!(
            "{{\"pad\":\"{}\",\"promptId\":\"turn-7f3a\"}}\n",
            "y".repeat(MAX_LINE + (1 << 16) - 3)
        );
        let mut s = format!("{}\n", typed("turn-7f3a", 1));
        s.push_str(&split);
        assert_eq!(
            turn_from_record(s.as_bytes(), "turn-7f3a").origin,
            Origin::Unknown
        );
    }

    #[test]
    fn an_over_long_line_keeps_a_typed_later_turn() {
        // A person's later turn holding a large tool result is still theirs.
        let mut text = format!("{}\n{}\n", typed("turn-d0", 1), typed("turn-7f3a", 2));
        text.push_str(&long_row("turn-7f3a"));
        let t = turn_from_record(text.as_bytes(), "turn-7f3a");
        assert_eq!(t.origin, Origin::TypedLabel);
        assert!(!t.opening);
    }

    #[test]
    fn an_over_long_line_keeps_a_not_typed_label() {
        let notice = json!({"type":"user","promptId":"turn-7f3a","turnOrigin":"task_notification",
                            "origin":{"kind":"task-notification"},"promptSource":"system",
                            "turnPosition":{"promptIndex":1,"turnIndex":2}});
        let mut text = format!("{notice}\n");
        text.push_str(&long_row("turn-7f3a"));
        let t = turn_from_record(text.as_bytes(), "turn-7f3a");
        assert_eq!(t.origin, Origin::NotTyped);
    }

    #[test]
    fn a_position_below_two_is_an_opening_turn() {
        let t = turn_of(&[typed("p", 0)], "p");
        assert_eq!(t.origin, Origin::TypedLabel);
        assert!(t.opening);
    }

    fn env(m: RunMode) -> Env {
        Env {
            off: false,
            run_mode: m,
            harness_dir: None,
        }
    }

    #[test]
    fn decision_without_a_record_follows_the_run_mode() {
        let input = br#"{"tool_name":"AskUserQuestion","prompt_id":"p","transcript_path":"/nonexistent/x.jsonl"}"#;
        assert!(should_deny(input, &env(RunMode::Unattended)));
        assert!(!should_deny(input, &env(RunMode::Attended)));
        assert!(!should_deny(input, &env(RunMode::Unknown)));
    }

    #[test]
    fn other_tools_and_bad_input_get_no_decision() {
        let e = env(RunMode::Unattended);
        assert!(!should_deny(b"", &e));
        assert!(!should_deny(b"not json", &e));
        assert!(!should_deny(br#"{"prompt_id":"p"}"#, &e));
        assert!(!should_deny(br#"{"tool_name":"Bash","agent_id":"a"}"#, &e));
    }

    #[test]
    fn subagent_call_is_denied_and_off_switch_wins() {
        let input = br#"{"tool_name":"AskUserQuestion","agent_id":"a1"}"#;
        let on = env(RunMode::Attended);
        assert!(should_deny(input, &on));
        let off = Env { off: true, ..on };
        assert!(!should_deny(input, &off));
    }

    #[test]
    fn reason_names_no_future_command() {
        assert!(!REASON.contains("shirabe question"));
        assert!(!REASON.contains("shirabe:pending"));
        assert!(REASON.starts_with("A question prompt was denied because no person typed"));
    }
}
