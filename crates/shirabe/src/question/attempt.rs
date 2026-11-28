//! `shirabe question attempt`: record what came of an attempt to decide.
//!
//! An attempt is a koto `judgment` (outcome `settled`, a session decider)
//! carrying the subject fields koto reads attempts by: `what`, `result` and,
//! when the caller gives one, `state`. koto's judgment subject takes no other
//! field, so the chosen option, the cheap-or-costly judgment, its reason and
//! the ground go into the entry's reason, laid out in a fixed order from the
//! caller's values. Nothing is composed: each part is a flag the caller gave.
//!
//! The rules the command enforces before any koto write:
//!   - `decided` needs `--chosen`; `undecided` takes none, since it chose
//!     nothing;
//!   - `provisional` is accepted only in a session that reads as unattended,
//!     with `--undo cheap`, an `--undo-reason` and `--chosen`: an attended run
//!     asks the person, and a costly choice is raised, not decided;
//!   - an `undecided` attempt in a session that reads as unattended records
//!     the cheap-or-costly test with `--undo`, and `--undo cheap` there needs
//!     a `--ground` saying why the session may not settle it, since a cheap
//!     choice is otherwise decided provisionally;
//!   - `--undo` always comes with an `--undo-reason`, and `--ground` only with
//!     an `undecided` result.
//!
//! The run mode is read the way `answer` reads it (see [`super::run_mode`]),
//! never from the fact that a caller asked for no prompts. koto 0.42.0 keeps
//! no run mode per session for this command to read instead, so the mode and
//! the cheap-or-costly judgment are the session's own declarations: the
//! command checks that they are consistent with the result, not that they are
//! true. When the two run-mode variables name opposite modes, `provisional`
//! is refused. Nothing here stops a session recording `decided` for a matter
//! it should have raised; only the procedure does.

use serde_json::{json, Map, Value};

use super::{check_name, koto, name_ok, run_mode, state_ok, Failure, RunMode};

/// The results an attempt takes, as koto stores them.
pub const RESULTS: [&str; 3] = ["decided", "undecided", "provisional"];

/// The cheap-or-costly judgment.
pub const UNDO: [&str; 2] = ["cheap", "costly"];

/// Why a session may not settle a question itself, as
/// `references/question-procedure.md` lists the grounds: it would contradict
/// an answer the owner gave, change the scope of the work, take an action
/// that is outward-facing, spends money or cannot be undone, or take a step
/// reserved to the owner.
pub const GROUNDS: [&str; 4] = [
    "contradicts-answer",
    "changes-scope",
    "outward-facing",
    "reserved-step",
];

/// The flags, as clap parsed them.
pub struct Input<'a> {
    pub session: &'a str,
    pub what: &'a str,
    pub result: &'a str,
    pub state: Option<&'a str>,
    pub chosen: Option<&'a str>,
    pub undo: Option<&'a str>,
    pub undo_reason: Option<&'a str>,
    pub ground: Option<&'a str>,
    pub basis: &'a [String],
}

/// A text value the caller gave: present, not blank, and free of control
/// characters, so the reason's fixed layout reads back unambiguously.
fn text(field: &str, flag: &str, v: &str) -> Result<(), Failure> {
    if v.trim().is_empty() {
        return Err(Failure::refused(field, format!("{flag} is empty")));
    }
    if v.chars().any(char::is_control) {
        return Err(Failure::refused(
            field,
            format!("{flag} holds a control character"),
        ));
    }
    Ok(())
}

/// A value that goes into the entry's reason, whose parts are joined by `; `
/// (see [`reason`]): a `;` inside it would let one value read as two parts,
/// so `--chosen "A; ground: reserved-step"` is refused rather than recorded.
fn part(field: &str, flag: &str, v: &str) -> Result<(), Failure> {
    text(field, flag, v)?;
    if v.contains(';') {
        return Err(Failure::refused(
            field,
            format!("{flag} holds a ';', which separates the parts of the entry's reason"),
        ));
    }
    Ok(())
}

/// The two run-mode variables when both are set and name opposite modes
/// (`KOTO_RUN_MODE=unattended` with `CLAUDE_CODE_SESSION_ATTENDED=1`, or
/// `attended` with `0`). [`run_mode`] then reads unattended, which is the
/// unsafe direction for a provisional decision, so `provisional` is refused.
fn run_mode_conflict() -> Option<(String, String)> {
    let koto = std::env::var("KOTO_RUN_MODE").ok()?;
    let attended = std::env::var("CLAUDE_CODE_SESSION_ATTENDED").ok()?;
    let clash =
        (koto == "unattended" && attended == "1") || (koto == "attended" && attended == "0");
    clash.then_some((koto, attended))
}

/// Check every input. Returns the run mode read, for the record.
pub fn validate(i: &Input) -> Result<RunMode, Failure> {
    check_name("in", "--in", i.session)?;
    text("what", "--what", i.what)?;
    if !RESULTS.contains(&i.result) {
        return Err(Failure::refused(
            "result",
            format!(
                "--result {:?} is not one of {}",
                i.result,
                RESULTS.join(", ")
            ),
        ));
    }
    if let Some(s) = i.state {
        if !state_ok(s) {
            return Err(Failure::refused(
                "state",
                format!("--state {s:?} is not <state>:<visit> (a state name, then a whole number from 1)"),
            ));
        }
    }
    if let Some(c) = i.chosen {
        part("chosen", "--chosen", c)?;
    }
    if let Some(u) = i.undo {
        if !UNDO.contains(&u) {
            return Err(Failure::refused(
                "undo",
                format!("--undo {u:?} is not cheap or costly"),
            ));
        }
        match i.undo_reason {
            Some(r) => part("undo_reason", "--undo-reason", r)?,
            None => {
                return Err(Failure::refused(
                    "undo_reason",
                    "--undo needs an --undo-reason saying what undoing the choice would take",
                ))
            }
        }
    } else if i.undo_reason.is_some() {
        return Err(Failure::refused(
            "undo",
            "--undo-reason was given without --undo cheap or --undo costly",
        ));
    }
    if let Some(g) = i.ground {
        if !GROUNDS.contains(&g) {
            return Err(Failure::refused(
                "ground",
                format!("--ground {g:?} is not one of {}", GROUNDS.join(", ")),
            ));
        }
        if i.result != "undecided" {
            return Err(Failure::refused(
                "ground",
                "--ground says why the session may not settle a question, so it goes only with --result undecided",
            ));
        }
    }
    for b in i.basis {
        let ok = match b.split_once(':') {
            Some((s, id)) => name_ok(s) && !id.is_empty() && id.bytes().all(|c| c.is_ascii_digit()),
            None => false,
        };
        if !ok {
            return Err(Failure::refused(
                "basis",
                format!("--basis {b:?} is not <session>:<decision id>"),
            ));
        }
    }

    let mode = run_mode();
    match i.result {
        "decided" => {
            if i.chosen.is_none() {
                return Err(Failure::refused(
                    "chosen",
                    "a decided attempt names the option chosen: give --chosen",
                ));
            }
        }
        "undecided" => {
            if i.chosen.is_some() {
                return Err(Failure::refused(
                    "chosen",
                    "an undecided attempt chose nothing: leave --chosen out",
                ));
            }
            if mode == RunMode::Unattended {
                match i.undo {
                    None => {
                        return Err(Failure::refused(
                            "undo",
                            "this session reads as unattended, so the attempt records the cheap-or-costly test: give --undo cheap or --undo costly with --undo-reason",
                        ))
                    }
                    Some("cheap") if i.ground.is_none() => {
                        return Err(Failure::refused(
                            "undo",
                            format!("a cheap choice is decided provisionally in an unattended run (--result provisional); it stays undecided only with a --ground saying why the session may not settle it ({})", GROUNDS.join(", ")),
                        ))
                    }
                    _ => {}
                }
            }
        }
        _ => {
            // provisional
            if let Some((koto, attended)) = run_mode_conflict() {
                return Err(Failure::refused(
                    "run_mode",
                    format!("the run-mode variables disagree (KOTO_RUN_MODE={koto}, CLAUDE_CODE_SESSION_ATTENDED={attended}), so this session can't be read as unattended for a provisional decision"),
                ));
            }
            match mode {
                RunMode::Unattended => {}
                RunMode::Attended => {
                    return Err(Failure::refused(
                        "run_mode",
                        "this session reads as attended, and an attended run asks the person rather than deciding provisionally",
                    ))
                }
                RunMode::Unknown => {
                    return Err(Failure::refused(
                        "run_mode",
                        "a provisional decision is recorded only in a session that reads as unattended (KOTO_RUN_MODE=unattended or CLAUDE_CODE_SESSION_ATTENDED=0), and this one does not",
                    ))
                }
            }
            match i.undo {
                Some("cheap") => {}
                Some(_) => {
                    return Err(Failure::refused(
                        "undo",
                        "a costly choice is raised, not decided: record --result undecided and raise the question",
                    ))
                }
                None => {
                    return Err(Failure::refused(
                        "undo",
                        "a provisional decision needs --undo cheap and an --undo-reason",
                    ))
                }
            }
            if i.chosen.is_none() {
                return Err(Failure::refused(
                    "chosen",
                    "a provisional decision names the option chosen: give --chosen",
                ));
            }
        }
    }
    Ok(mode)
}

/// The entry's reason: the caller's values in a fixed order, or `None` when
/// none was given.
pub fn reason(i: &Input) -> Option<String> {
    let mut parts = Vec::new();
    if let Some(c) = i.chosen {
        parts.push(format!("chosen: {c}"));
    }
    if let (Some(u), Some(r)) = (i.undo, i.undo_reason) {
        parts.push(format!("undo: {u}: {r}"));
    }
    if let Some(g) = i.ground {
        parts.push(format!("ground: {g}"));
    }
    (!parts.is_empty()).then(|| parts.join("; "))
}

pub fn run(i: &Input) -> Result<Value, Failure> {
    check_name("in", "--in", i.session)?;
    koto::check_version()?;
    let mode = validate(i)?;
    let mut args: Vec<String> = vec![
        "decisions".into(),
        "record".into(),
        "--kind=judgment".into(),
        "--outcome=settled".into(),
        format!("--subject=what={}", i.what),
        format!("--subject=result={}", i.result),
    ];
    if let Some(s) = i.state {
        args.push(format!("--subject=state={s}"));
    }
    let why = reason(i);
    if let Some(r) = &why {
        args.push(format!("--reason={r}"));
    }
    for b in i.basis {
        args.push(format!("--basis={b}"));
    }
    if let Some(m) = mode.as_koto() {
        args.push(format!("--run-mode={m}"));
    }
    args.push("--by=session".into());
    args.push("--".into());
    args.push(i.session.to_string());
    let argv: Vec<&str> = args.iter().map(String::as_str).collect();
    let rec = koto::run(&argv)?;
    let id = rec.get("id").and_then(Value::as_str).ok_or_else(|| {
        Failure::new(
            super::EXIT_KOTO_REFUSED,
            "koto_output",
            "koto recorded the attempt but printed no id",
        )
    })?;
    let mut out = Map::new();
    out.insert("v".into(), json!(1));
    out.insert("id".into(), json!(id));
    out.insert("session".into(), json!(i.session));
    out.insert("attempt".into(), json!(format!("{}:{id}", i.session)));
    out.insert("what".into(), json!(i.what));
    out.insert("result".into(), json!(i.result));
    out.insert("state".into(), json!(i.state));
    out.insert("run_mode".into(), json!(mode.as_str()));
    out.insert("chosen".into(), json!(i.chosen));
    out.insert("undo".into(), json!(i.undo));
    out.insert("undo_reason".into(), json!(i.undo_reason));
    out.insert("ground".into(), json!(i.ground));
    out.insert("basis".into(), json!(i.basis));
    out.insert("reason".into(), json!(why));
    Ok(Value::Object(out))
}
