//! `shirabe hook question-guard`: the plugin's PreToolUse hook on the
//! question tool (`AskUserQuestion`).
//!
//! A question prompt opened in a turn no person typed blocks a session that
//! nobody is watching, so the guard denies it (PRD-decision-escalation-ladder
//! R27). It leaves alone a prompt opened in a turn a person typed, including
//! one a skill the person invoked opens later in that turn.
//!
//! The rule comes from docs/spikes/SPIKE-question-guard-turn-origin.md, which
//! records what the harness reported for each way a turn starts:
//!
//! - The hook's input names the turn by `prompt_id`. The session record the
//!   input's `transcript_path` names holds, for the entry that started that
//!   turn, `turnOrigin`, `origin.kind` and `promptSource`. A background-task
//!   notification, a scheduled wake-up and a message from another session
//!   each carry a label of their own there, and the guard denies them.
//! - A continuation a Stop hook injected keeps the person's `prompt_id`; the
//!   injected entry carries `rowSource: "hook"` (and `hookText: true`), and
//!   the guard denies a turn holding one.
//! - A call from a subagent carries `agent_id` in the hook's input, and the
//!   guard denies it.
//! - A dispatch brief starting a session carries the same label as a typed
//!   prompt, so a typed label doesn't establish that a person typed it. Such
//!   a turn, and one whose origin can't be read at all, falls back to the run
//!   mode: denied when the session is unattended, allowed otherwise.
//!
//! The run mode is `CLAUDE_CODE_SESSION_ATTENDED`, which the harness sets for
//! every hook (1 attended, 0 unattended) and which koto's own hook reads as
//! the session's run mode. Any other value, or none, is no recorded run mode,
//! which is not unattended.
//!
//! The origin is taken only from structured fields, never from message text.
//! The record is opened only when its path, with symbolic links resolved,
//! lies under the harness's own directory and is a regular file. The guard
//! decides only for the question tool, prints nothing or one deny line,
//! never `allow` or `ask`, and writes nothing. `SHIRABE_PRE_ACTION_HOOK=off`
//! turns it off, as it turns off the plugin's Bash hook.

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
    /// Labelled as typed by a person. A dispatch brief carries the same
    /// label, so this alone doesn't establish a person typed it.
    TypedLabel,
    /// Labelled as something no person typed: a background-task
    /// notification, a scheduled wake-up, a message from another session, or
    /// a hook-injected continuation.
    NotTyped,
    /// Not established: no record, a record outside the harness's directory,
    /// no entry for the turn, or a label the spike's capture never showed.
    Unknown,
}

/// The labels the capture showed for turns no person typed.
const NOT_TYPED_TURN_ORIGINS: [&str; 3] = ["task_notification", "scheduled", "peer"];
const NOT_TYPED_ORIGIN_KINDS: [&str; 2] = ["task-notification", "peer"];

fn str_field<'a>(v: &'a Value, key: &str) -> Option<&'a str> {
    v.get(key).and_then(Value::as_str)
}

/// One record entry's contribution, or `None` when it carries no origin
/// fields (a tool result, a skill's expanded text, a queued notice).
pub fn classify_entry(e: &Value) -> Option<Origin> {
    if str_field(e, "rowSource") == Some("hook") || e.get("hookText") == Some(&Value::Bool(true)) {
        return Some(Origin::NotTyped);
    }
    let turn = e.get("turnOrigin").filter(|v| !v.is_null());
    let origin = e.get("origin").filter(|v| !v.is_null());
    if turn.is_none() && origin.is_none() {
        return None;
    }
    let turn = turn.and_then(Value::as_str);
    let kind = origin.and_then(|o| str_field(o, "kind"));
    if turn.is_some_and(|t| NOT_TYPED_TURN_ORIGINS.contains(&t))
        || kind.is_some_and(|k| NOT_TYPED_ORIGIN_KINDS.contains(&k))
    {
        return Some(Origin::NotTyped);
    }
    let source = e.get("promptSource").filter(|v| !v.is_null());
    let source_typed = match source {
        None => true,
        Some(s) => s.as_str() == Some("typed"),
    };
    let kind_human = match origin {
        None => true,
        Some(_) => kind == Some("human"),
    };
    let meta = e.get("isMeta") == Some(&Value::Bool(true));
    if turn == Some("human") && kind_human && source_typed && !meta {
        Some(Origin::TypedLabel)
    } else {
        Some(Origin::Unknown)
    }
}

/// The turn's origin from the record's entries for `prompt_id`: any entry
/// labelled as not typed wins, then any label the capture never showed;
/// otherwise a typed label, and with no labelled entry at all, unknown.
pub fn origin_from_record<R: BufRead>(mut reader: R, prompt_id: &str) -> Origin {
    let needle = prompt_id.as_bytes();
    let mut line = Vec::new();
    let mut typed = false;
    let mut unknown = false;
    loop {
        line.clear();
        match reader.read_until(b'\n', &mut line) {
            Ok(0) => break,
            Ok(_) => {}
            Err(_) => return Origin::Unknown,
        }
        // Parse only the lines that name the turn.
        if !contains(&line, needle) {
            continue;
        }
        let Ok(e) = serde_json::from_slice::<Value>(&line) else {
            continue;
        };
        if str_field(&e, "type") != Some("user") || str_field(&e, "promptId") != Some(prompt_id) {
            continue;
        }
        match classify_entry(&e) {
            Some(Origin::NotTyped) => return Origin::NotTyped,
            Some(Origin::Unknown) => unknown = true,
            Some(Origin::TypedLabel) => typed = true,
            None => {}
        }
    }
    if unknown || !typed {
        Origin::Unknown
    } else {
        Origin::TypedLabel
    }
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && hay.windows(needle.len()).any(|w| w == needle)
}

/// The record path, resolved, when it lies under the harness's directory
/// and is a regular file; `None` otherwise, and then nothing is opened.
pub fn checked_record_path(path: &str, harness_dir: Option<&Path>) -> Option<PathBuf> {
    let p = Path::new(path);
    if !p.is_absolute() {
        return None;
    }
    let root = std::fs::canonicalize(harness_dir?).ok()?;
    let resolved = std::fs::canonicalize(p).ok()?;
    if !resolved.starts_with(&root) {
        return None;
    }
    if !std::fs::metadata(&resolved).ok()?.is_file() {
        return None;
    }
    Some(resolved)
}

fn turn_origin(input: &Value, env: &Env) -> Origin {
    let (Some(path), Some(prompt_id)) = (
        str_field(input, "transcript_path"),
        str_field(input, "prompt_id").filter(|s| !s.is_empty()),
    ) else {
        return Origin::Unknown;
    };
    let Some(resolved) = checked_record_path(path, env.harness_dir.as_deref()) else {
        return Origin::Unknown;
    };
    match File::open(resolved) {
        Ok(f) => origin_from_record(BufReader::with_capacity(1 << 16, f), prompt_id),
        Err(_) => Origin::Unknown,
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
    match turn_origin(&v, env) {
        Origin::NotTyped => true,
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

    fn origin_of(rows: &[Value], pid: &str) -> Origin {
        let text: String = rows.iter().map(|r| format!("{r}\n")).collect();
        origin_from_record(text.as_bytes(), pid)
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
    fn notification_scheduled_and_peer_are_not_typed() {
        for e in [
            json!({"type":"user","promptId":"p","origin":{"kind":"task-notification"},"promptSource":"system","turnOrigin":"task_notification"}),
            json!({"type":"user","promptId":"p","promptSource":"system","turnOrigin":"scheduled","isMeta":true}),
            json!({"type":"user","promptId":"p","origin":{"kind":"peer"},"promptSource":"system","turnOrigin":"peer","isMeta":true}),
        ] {
            assert_eq!(origin_of(&[e], "p"), Origin::NotTyped);
        }
    }

    #[test]
    fn hook_row_after_a_typed_entry_is_not_typed() {
        let typed = json!({"type":"user","promptId":"p","origin":{"kind":"human"},"promptSource":"typed","turnOrigin":"human"});
        let hook =
            json!({"type":"user","promptId":"p","isMeta":true,"rowSource":"hook","hookText":true});
        assert_eq!(origin_of(&[typed, hook], "p"), Origin::NotTyped);
    }

    #[test]
    fn unseen_or_absent_labels_are_unknown() {
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
        let typed =
            json!({"type":"user","promptId":"p","origin":{"kind":"human"},"turnOrigin":"human"});
        assert_eq!(origin_of(&[other, typed], "p"), Origin::TypedLabel);
    }

    #[test]
    fn decision_without_a_record_follows_the_run_mode() {
        let input = br#"{"tool_name":"AskUserQuestion","prompt_id":"p","transcript_path":"/nonexistent/x.jsonl"}"#;
        let env = |m| Env {
            off: false,
            run_mode: m,
            harness_dir: None,
        };
        assert!(should_deny(input, &env(RunMode::Unattended)));
        assert!(!should_deny(input, &env(RunMode::Attended)));
        assert!(!should_deny(input, &env(RunMode::Unknown)));
    }

    #[test]
    fn other_tools_and_bad_input_get_no_decision() {
        let env = Env {
            off: false,
            run_mode: RunMode::Unattended,
            harness_dir: None,
        };
        assert!(!should_deny(b"", &env));
        assert!(!should_deny(b"not json", &env));
        assert!(!should_deny(br#"{"prompt_id":"p"}"#, &env));
        assert!(!should_deny(
            br#"{"tool_name":"Bash","agent_id":"a"}"#,
            &env
        ));
    }

    #[test]
    fn subagent_call_is_denied_and_off_switch_wins() {
        let input = br#"{"tool_name":"AskUserQuestion","agent_id":"a1"}"#;
        let on = Env {
            off: false,
            run_mode: RunMode::Attended,
            harness_dir: None,
        };
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
