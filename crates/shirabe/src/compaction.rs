//! The `shirabe compaction` subcommand: the two hook commands that let a
//! session compact in place and still find its way back to the skill and the
//! koto run it was in.
//!
//! - `pre-compact` runs as a PreCompact hook. It prints an instruction for the
//!   summary: name the koto session, branch, pull request, note key and the
//!   skills to re-read, and keep owner words, ids and hashes verbatim.
//! - `re-anchor` runs as a SessionStart hook matched on `compact`. It prints a
//!   SessionStart hook JSON whose `additionalContext` tells the compacted
//!   session to re-read each recorded `SKILL.md`, run `koto status` on its
//!   koto session, and read its compaction note, before doing anything else.
//!
//! Both read the hook JSON on stdin for `session_id` and look up the ledger
//! entry `scripts/handoff-brief.sh note` wrote for that session:
//! `$XDG_STATE_HOME/shirabe/compaction/<session-id>` (or the same path under
//! `$HOME/.local/state`). The entry is plain `key: value` lines:
//!
//! ```text
//! koto_session: <name>
//! note_key: compaction/note.md
//! branch: <branch>
//! pr: <pull request URL, or none>
//! skill: <name> [<arg> ...] <absolute path to SKILL.md>
//! ```
//!
//! with one `skill:` line per active skill, outermost first.
//!
//! Both commands are fail-open: they always exit 0 and never block a
//! compaction. A session id or a ledger field that fails its grammar, a
//! missing or linked ledger, or a koto session that doesn't match
//! `KOTO_SESSION` where that is set all mean no output at all. Neither command
//! ever prints the note's text or a skill's text; they print where to read
//! them.

use std::fs;
use std::io::Read;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::LazyLock;

use clap::{Args, Subcommand};
use regex::Regex;

/// The one key a compaction note lives under in the session's koto session.
pub const NOTE_KEY: &str = "compaction/note.md";

/// SessionStart `additionalContext` is capped at 10,000 characters; the
/// re-anchor stays under it.
const CONTEXT_CAP: usize = 10_000;

/// The most skill lines a ledger entry may carry.
const MAX_SKILLS: usize = 8;

/// The most bytes read from a ledger entry. A real entry is a few hundred.
const MAX_LEDGER_BYTES: u64 = 16 * 1024;

#[derive(Args)]
pub struct CompactionArgs {
    #[command(subcommand)]
    pub command: CompactionCommands,
}

#[derive(Subcommand)]
pub enum CompactionCommands {
    /// PreCompact hook. Reads the hook JSON on stdin for `session_id` and
    /// prints the summary instruction built from the session's ledger entry.
    /// Prints nothing when there is no valid entry. Always exits 0.
    PreCompact,
    /// SessionStart hook, matched on `compact`. Reads the hook JSON on stdin
    /// for `session_id` and prints a SessionStart hook JSON whose
    /// `additionalContext` sends the session back to its skills, its koto
    /// session and its note. Prints nothing when there is no valid entry.
    /// Always exits 0.
    ReAnchor,
}

/// Entrypoint for `shirabe compaction`. Always returns `ExitCode::SUCCESS`.
pub fn run(command: &CompactionCommands) -> ExitCode {
    let input = read_stdin();
    let out = match command {
        CompactionCommands::PreCompact => pre_compact_output(&input),
        CompactionCommands::ReAnchor => re_anchor_output(&input),
    };
    if let Some(s) = out {
        println!("{s}");
    }
    ExitCode::SUCCESS
}

// --- grammars ----------------------------------------------------------------

static SID_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Za-z0-9-]{1,64}$").unwrap());
static KOTO_SESSION_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$").unwrap());
static BRANCH_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9._/-]{1,200}$").unwrap());
static PR_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^https://github\.com/[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9._-]{1,100}/pull/[0-9]{1,10}$")
        .unwrap()
});
static SKILL_NAME_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9][a-z0-9-]{0,63}(:[a-z0-9][a-z0-9-]{0,63})?$").unwrap());
static SKILL_ARG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9._/=:@+,-]{1,200}$").unwrap());
static SKILL_PATH_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^/[A-Za-z0-9._/+@-]+/SKILL\.md$").unwrap());

fn valid_sid(sid: &str) -> bool {
    SID_RE.is_match(sid)
}

fn valid_branch(b: &str) -> bool {
    BRANCH_RE.is_match(b) && !b.contains("..") && !b.starts_with('-') && !b.starts_with('/')
}

fn valid_skill_path(p: &str) -> bool {
    p.len() <= 512 && SKILL_PATH_RE.is_match(p) && !p.split('/').any(|seg| seg == "..")
}

// --- the ledger entry ----------------------------------------------------------

/// One active skill: its name, the arguments it was invoked with, and the
/// path of its `SKILL.md`.
#[derive(Debug, Clone, PartialEq)]
pub struct Skill {
    pub name: String,
    pub args: Vec<String>,
    pub path: String,
}

/// A parsed, grammar-checked ledger entry.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub koto_session: String,
    pub note_key: String,
    pub branch: String,
    pub pr: Option<String>,
    pub skills: Vec<Skill>,
}

fn parse_skill(v: &str) -> Option<Skill> {
    let toks: Vec<&str> = v.split(' ').collect();
    if toks.len() < 2 || toks.iter().any(|t| t.is_empty()) {
        return None;
    }
    let name = toks[0];
    let path = toks[toks.len() - 1];
    let args = &toks[1..toks.len() - 1];
    if !SKILL_NAME_RE.is_match(name) || !valid_skill_path(path) {
        return None;
    }
    if !args.iter().all(|a| SKILL_ARG_RE.is_match(a)) {
        return None;
    }
    Some(Skill {
        name: name.to_string(),
        args: args.iter().map(|a| a.to_string()).collect(),
        path: path.to_string(),
    })
}

/// Parse a ledger entry. Every field must pass its grammar and each of the
/// four single fields must appear exactly once; anything else is `None`.
pub fn parse_entry(text: &str) -> Option<Entry> {
    let mut koto_session = None;
    let mut note_key = None;
    let mut branch = None;
    let mut pr: Option<Option<String>> = None;
    let mut skills = Vec::new();
    for line in text.lines() {
        if line.is_empty() {
            continue;
        }
        let (k, v) = line.split_once(": ")?;
        match k {
            "koto_session" => {
                if koto_session.is_some() || !KOTO_SESSION_RE.is_match(v) {
                    return None;
                }
                koto_session = Some(v.to_string());
            }
            "note_key" => {
                if note_key.is_some() || v != NOTE_KEY {
                    return None;
                }
                note_key = Some(v.to_string());
            }
            "branch" => {
                if branch.is_some() || !valid_branch(v) {
                    return None;
                }
                branch = Some(v.to_string());
            }
            "pr" => {
                if pr.is_some() {
                    return None;
                }
                if v == "none" {
                    pr = Some(None);
                } else if PR_RE.is_match(v) {
                    pr = Some(Some(v.to_string()));
                } else {
                    return None;
                }
            }
            "skill" => {
                if skills.len() >= MAX_SKILLS {
                    return None;
                }
                skills.push(parse_skill(v)?);
            }
            _ => return None,
        }
    }
    Some(Entry {
        koto_session: koto_session?,
        note_key: note_key?,
        branch: branch?,
        pr: pr?,
        skills,
    })
}

/// The ledger directory: `$XDG_STATE_HOME/shirabe/compaction`, else
/// `$HOME/.local/state/shirabe/compaction`.
fn ledger_dir() -> Option<PathBuf> {
    let base = match std::env::var("XDG_STATE_HOME") {
        Ok(s) if !s.is_empty() => PathBuf::from(s),
        _ => {
            let home = std::env::var("HOME").ok().filter(|h| !h.is_empty())?;
            PathBuf::from(home).join(".local/state")
        }
    };
    Some(base.join("shirabe").join("compaction"))
}

/// Read the session's ledger entry. The directory must be a real directory
/// (not a link) and the entry is opened without following a link.
fn read_entry(sid: &str) -> Option<Entry> {
    if !valid_sid(sid) {
        return None;
    }
    let dir = ledger_dir()?;
    let meta = fs::symlink_metadata(&dir).ok()?;
    if !meta.file_type().is_dir() {
        return None;
    }
    let file = fs::OpenOptions::new()
        .read(true)
        .custom_flags(entry_open_flags())
        .open(dir.join(sid))
        .ok()?;
    if !file.metadata().ok()?.file_type().is_file() {
        return None;
    }
    let mut text = String::new();
    file.take(MAX_LEDGER_BYTES).read_to_string(&mut text).ok()?;
    let entry = parse_entry(&text)?;
    // Trust: where KOTO_SESSION is set, the entry must name that session.
    if let Ok(ks) = std::env::var("KOTO_SESSION") {
        if !ks.is_empty() && ks != entry.koto_session {
            return None;
        }
    }
    Some(entry)
}

/// `O_NOFOLLOW | O_NONBLOCK` through rustix, so no libc dependency is added.
/// `O_NONBLOCK` keeps the open from waiting on a FIFO at the entry path; the
/// regular-file check after the open then refuses it. Reads from a regular
/// file are unaffected.
fn entry_open_flags() -> i32 {
    (rustix::fs::OFlags::NOFOLLOW | rustix::fs::OFlags::NONBLOCK).bits() as i32
}

fn read_stdin() -> String {
    let mut s = String::new();
    let _ = std::io::stdin().take(1024 * 1024).read_to_string(&mut s);
    s
}

fn hook_sid(input: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(input).ok()?;
    let sid = v.get("session_id")?.as_str()?;
    if valid_sid(sid) {
        Some(sid.to_string())
    } else {
        None
    }
}

fn skill_label(s: &Skill) -> String {
    if s.args.is_empty() {
        s.name.clone()
    } else {
        format!("{} {}", s.name, s.args.join(" "))
    }
}

// --- the two outputs -------------------------------------------------------------

/// The summary instruction PreCompact prints, from a valid entry.
pub fn summary_instruction(e: &Entry) -> String {
    let mut s = String::new();
    s.push_str("When you write the summary of this session, carry the way back to its work.\n");
    s.push_str("Name each of these in the summary, exactly as written here:\n");
    s.push_str(&format!("- koto session: {}\n", e.koto_session));
    s.push_str(&format!("- branch: {}\n", e.branch));
    s.push_str(&format!(
        "- pull request: {}\n",
        e.pr.as_deref().unwrap_or("none recorded")
    ));
    s.push_str(&format!(
        "- compaction note: key {} in koto session {}\n",
        e.note_key, e.koto_session
    ));
    if !e.skills.is_empty() {
        s.push_str("- skills to re-read by path after the compaction, outermost first:\n");
        for sk in &e.skills {
            s.push_str(&format!("  - {} ({})\n", sk.path, skill_label(sk)));
        }
    }
    s.push_str("Keep verbatim any words the owner typed, and any ids and hashes still in play.");
    s
}

/// The re-anchor text the SessionStart hook carries, from a valid entry.
pub fn re_anchor_text(e: &Entry) -> String {
    let mut s = String::new();
    s.push_str("This session was just compacted. Before doing anything else, in this order:\n");
    let mut n = 1;
    for sk in &e.skills {
        s.push_str(&format!(
            "{n}. Read {} again: it is the instructions of the skill you were running ({}).\n",
            sk.path,
            skill_label(sk)
        ));
        n += 1;
    }
    s.push_str(&format!(
        "{n}. Run `koto status {}` to see where that run stands.\n",
        e.koto_session
    ));
    n += 1;
    s.push_str(&format!(
        "{n}. Read your compaction note: `koto context get {} {}`.\n",
        e.koto_session, e.note_key
    ));
    s.push_str(&format!(
        "Then carry on from where koto says the run stands, on branch {}",
        e.branch
    ));
    if let Some(pr) = &e.pr {
        s.push_str(&format!(" (pull request {pr})"));
    }
    s.push('.');
    s
}

/// `pre-compact`'s stdout for a hook input, or `None` for no output.
pub fn pre_compact_output(input: &str) -> Option<String> {
    let sid = hook_sid(input)?;
    let e = read_entry(&sid)?;
    Some(summary_instruction(&e))
}

/// `re-anchor`'s stdout for a hook input, or `None` for no output.
pub fn re_anchor_output(input: &str) -> Option<String> {
    let sid = hook_sid(input)?;
    let e = read_entry(&sid)?;
    re_anchor_json(&e)
}

/// The SessionStart hook JSON for an entry, withheld (`None`) rather than
/// truncated when its text would reach the 10,000-character cap.
fn re_anchor_json(e: &Entry) -> Option<String> {
    let text = re_anchor_text(e);
    if text.chars().count() >= CONTEXT_CAP {
        return None;
    }
    let value = serde_json::json!({
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": text,
        }
    });
    serde_json::to_string(&value).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOD: &str = "koto_session: probe-run\n\
note_key: compaction/note.md\n\
branch: session/abc123\n\
pr: https://github.com/acme/widgets/pull/42\n\
skill: shirabe:deliver handoff-brief --no-merge /opt/plugins/shirabe/0.50.0/skills/deliver/SKILL.md\n\
skill: shirabe:scope handoff-brief /opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md\n";

    #[test]
    fn parses_a_good_entry() {
        let e = parse_entry(GOOD).expect("parses");
        assert_eq!(e.koto_session, "probe-run");
        assert_eq!(
            e.pr.as_deref(),
            Some("https://github.com/acme/widgets/pull/42")
        );
        assert_eq!(e.skills.len(), 2);
        assert_eq!(e.skills[0].name, "shirabe:deliver");
        assert_eq!(e.skills[0].args, vec!["handoff-brief", "--no-merge"]);
        assert!(e.skills[1].path.ends_with("/scope/SKILL.md"));
    }

    #[test]
    fn pr_none_is_accepted() {
        let t = GOOD.replace("pr: https://github.com/acme/widgets/pull/42", "pr: none");
        assert_eq!(parse_entry(&t).unwrap().pr, None);
    }

    #[test]
    fn refuses_bad_fields() {
        for (from, to) in [
            ("koto_session: probe-run", "koto_session: ../x"),
            ("note_key: compaction/note.md", "note_key: brief/x.md"),
            ("branch: session/abc123", "branch: a..b"),
            (
                "pr: https://github.com/acme/widgets/pull/42",
                "pr: http://evil/pull/1",
            ),
            (
                "/opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md",
                "/opt/../etc/SKILL.md",
            ),
            (
                "/opt/plugins/shirabe/0.50.0/skills/scope/SKILL.md",
                "relative/SKILL.md",
            ),
            ("shirabe:scope handoff-brief", "shirabe:scope $(id)"),
        ] {
            let t = GOOD.replace(from, to);
            assert!(parse_entry(&t).is_none(), "accepted {to}");
        }
    }

    #[test]
    fn refuses_duplicate_and_unknown_keys() {
        assert!(parse_entry(&format!("{GOOD}branch: other\n")).is_none());
        assert!(parse_entry(&format!("{GOOD}extra: x\n")).is_none());
        assert!(parse_entry("koto_session: a\n").is_none());
    }

    #[test]
    fn skill_path_length_is_capped_at_512() {
        let at = format!("/{}/SKILL.md", "p".repeat(512 - 10));
        assert_eq!(at.len(), 512);
        assert!(valid_skill_path(&at));
        let over = format!("/{}/SKILL.md", "p".repeat(512 - 9));
        assert!(!valid_skill_path(&over));
    }

    #[test]
    fn sid_grammar() {
        assert!(valid_sid("4f08fec0-0720-4fdd-ab29-5f0583eb2031"));
        for bad in ["", "a/b", "..", "a\nb", "a.b", &"x".repeat(65)] {
            assert!(!valid_sid(bad), "accepted {bad:?}");
        }
    }

    #[test]
    fn summary_names_everything_and_inlines_nothing() {
        let e = parse_entry(GOOD).unwrap();
        let s = summary_instruction(&e);
        for want in [
            "probe-run",
            "session/abc123",
            "https://github.com/acme/widgets/pull/42",
            "compaction/note.md",
            "/opt/plugins/shirabe/0.50.0/skills/deliver/SKILL.md",
            "verbatim",
        ] {
            assert!(s.contains(want), "missing {want}");
        }
    }

    #[test]
    fn re_anchor_orders_skills_then_status_then_note() {
        let e = parse_entry(GOOD).unwrap();
        let t = re_anchor_text(&e);
        let deliver = t.find("skills/deliver/SKILL.md").unwrap();
        let scope = t.find("skills/scope/SKILL.md").unwrap();
        let status = t.find("koto status probe-run").unwrap();
        let note = t
            .find("koto context get probe-run compaction/note.md")
            .unwrap();
        assert!(deliver < scope && scope < status && status < note);
        assert!(t.chars().count() < CONTEXT_CAP);
    }

    fn entry_with(skills: usize, arg_len: usize, args: usize) -> Entry {
        let path = format!("/{}/SKILL.md", "p".repeat(480));
        let argv = vec!["a".repeat(arg_len); args].join(" ");
        let mut t =
            String::from("koto_session: k\nnote_key: compaction/note.md\nbranch: b\npr: none\n");
        for _ in 0..skills {
            t.push_str(&format!("skill: n {argv} {path}\n"));
        }
        parse_entry(&t).unwrap()
    }

    #[test]
    fn re_anchor_json_is_hook_shaped() {
        let e = parse_entry(GOOD).unwrap();
        let j: serde_json::Value = serde_json::from_str(&re_anchor_json(&e).unwrap()).unwrap();
        assert_eq!(j["hookSpecificOutput"]["hookEventName"], "SessionStart");
        assert!(j["hookSpecificOutput"]["additionalContext"]
            .as_str()
            .unwrap()
            .contains("koto status probe-run"));
    }

    #[test]
    fn re_anchor_is_withheld_at_the_cap_not_truncated() {
        // Eight skills with long paths and short arguments fit.
        let fits = entry_with(MAX_SKILLS, 20, 3);
        assert!(re_anchor_json(&fits).is_some());
        // Eight skills each carrying 4,000 characters of arguments don't.
        let over = entry_with(MAX_SKILLS, 200, 20);
        assert!(re_anchor_text(&over).chars().count() >= CONTEXT_CAP);
        assert!(re_anchor_json(&over).is_none());
    }

    #[test]
    fn more_than_max_skills_is_refused() {
        let mut t =
            String::from("koto_session: k\nnote_key: compaction/note.md\nbranch: b\npr: none\n");
        for _ in 0..=MAX_SKILLS {
            t.push_str("skill: n /a/SKILL.md\n");
        }
        assert!(parse_entry(&t).is_none());
    }

    #[test]
    fn bad_hook_input_gives_no_sid() {
        assert!(hook_sid("not json").is_none());
        assert!(hook_sid(r#"{"session_id":"../../etc"}"#).is_none());
        assert!(hook_sid(r#"{"session_id":"a\nb"}"#).is_none());
        assert_eq!(
            hook_sid(r#"{"session_id":"abc-1"}"#).as_deref(),
            Some("abc-1")
        );
    }
}
