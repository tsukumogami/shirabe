//! `shirabe question pass-up`, `settle` and `seen`: what a coordinator does
//! with a question it holds, recorded in koto.
//!
//! - `pass-up` hands a question to the session's own dispatcher or to
//!   `person:owner`. A decision question passes up only on the calling
//!   session's own undecided attempt, in effect, tied to that question: an
//!   attempt by the worker that raised it, an attempt tied to another
//!   question, a reversed or refused attempt and a deciding attempt are each
//!   refused before koto is asked. A need passes with no attempt. koto
//!   records a `readdress` with outcome `passed`; the question keeps its
//!   identity.
//! - `settle` answers a question the calling session holds, as a session:
//!   outcome `answered` when it is the question's current addressee,
//!   `settled` when it raised the question (koto then needs a basis). With
//!   `--owner-note` a relayed claim is recorded as the session's own
//!   decision with the note in its text, never as the owner's answer, and it
//!   is refused for a question waiting on a person. With no identity and
//!   `--what`, it records a `judgment` for a claim that answers no recorded
//!   question. A `--basis` naming an owner answer must be one koto's
//!   precedent read lists in the session's chain, verified; any other basis
//!   is only shape-checked. A question whose history holds a ground reserved
//!   for the owner, recorded by the session or one below it, is refused: it
//!   is passed up, not settled. A ground nobody recorded can't be checked.
//! - `seen` marks an owner's answer given at or below the session as read:
//!   one `judgment` whose basis names the answer. The answer is not changed,
//!   and a second `seen` adds nothing.
//!
//! koto is the authority for every rule it holds: who may answer or pass up
//! a question, the settle basis, the twenty-question limit. Its refusals are
//! passed through as exit 4. What shirabe checks itself it checks before
//! any koto write, exit 1.

use std::collections::BTreeMap;

use serde_json::{json, Map, Value};

use super::attempt::GROUNDS;
use super::content::holds_secret;
use super::koto::{self, History};
use super::{
    check_identity, check_name, default_recipient, name_ok, parse_recipient, recipient_string,
    run_mode, Failure, OWNER,
};

/// The ground a coordinator may give when a question is merely outside the
/// brief: that question is the coordinator's to settle, not the owner's, so
/// it passes up only to a coordinator.
pub const OUTSIDE_SCOPE: &str = "outside-scope";

fn owner() -> String {
    format!("person:{OWNER}")
}

/// A caller's text: present, not blank, free of control characters and of
/// anything shaped like a secret. The match is never printed.
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
    if holds_secret(v) {
        return Err(Failure::refused(
            field,
            format!("{flag} holds text shaped like a secret (a token, a key or a private key block); remove it"),
        ));
    }
    Ok(())
}

/// A decision id: twelve digits, as koto writes them.
fn decision_id_ok(s: &str) -> bool {
    s.len() == 12 && s.bytes().all(|b| b.is_ascii_digit())
}

/// `<session>:<decision id>`, both in koto's shape.
fn parse_ref<'a>(field: &str, flag: &str, s: &'a str) -> Result<(&'a str, &'a str), Failure> {
    match s.split_once(':') {
        Some((sess, id)) if name_ok(sess) && decision_id_ok(id) => Ok((sess, id)),
        _ => Err(Failure::refused(
            field,
            format!("{flag} {s:?} is not <session>:<decision id>"),
        )),
    }
}

fn need_of(h: &History) -> String {
    h.raw
        .pointer("/question/need")
        .and_then(Value::as_str)
        .unwrap_or("decision")
        .to_string()
}

fn addressee_of(h: &History) -> String {
    recipient_string(h.raw.get("addressee").unwrap_or(&Value::Null))
        .as_str()
        .unwrap_or("")
        .to_string()
}

fn printed_id(rec: &Value, what: &str) -> Result<String, Failure> {
    rec.get("id")
        .and_then(Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| {
            Failure::new(
                super::EXIT_KOTO_REFUSED,
                "koto_output",
                format!("koto recorded the {what} but printed no id"),
            )
        })
}

fn run_argv(args: &[String]) -> Result<Value, Failure> {
    let argv: Vec<&str> = args.iter().map(String::as_str).collect();
    Ok(koto::run(&argv)?)
}

// ---------------------------------------------------------------------------
// pass-up

pub struct PassUp<'a> {
    pub identity: &'a str,
    pub session: &'a str,
    pub ground: Option<&'a str>,
    pub attempt: Option<&'a str>,
    pub to: Option<&'a str>,
}

/// The session's own undecided attempt for `identity`: in its run, in effect
/// (not reversed or refused), tied to that question, with result
/// `undecided`. Returns `<session>:<id>`.
fn own_attempt(session: &str, identity: &str, attempt: Option<&str>) -> Result<String, Failure> {
    let Some(given) = attempt else {
        return Err(Failure::refused(
            "attempt",
            format!("{session} gave no attempt of its own for {identity}: a decision question is passed up only after the session passing it up tried to decide it and could not. Record that attempt in {session} (shirabe question attempt --in {session} --result undecided --basis <raiser>:<question id>) and give its id with --attempt; the raiser's own attempt does not count"),
        ));
    };
    let (want_session, want_id) = match given.split_once(':') {
        Some((s, i)) => (Some(s), i),
        None => (None, given),
    };
    if !decision_id_ok(want_id) || want_session.is_some_and(|s| !name_ok(s)) {
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
            format!("--attempt {given} names no attempt in {session}'s run; a pass-up rests on {session}'s own attempt, not the raiser's"),
        ));
    };
    // koto prints each attempt's standing as `status`: `in-effect`, or
    // `reversed` once a reversal of it wins, or `refused`. A reversed attempt
    // still reads its old `result`, so the result alone can't be trusted.
    let status = a.get("status").and_then(Value::as_str).unwrap_or("");
    if status != "in-effect" {
        let read = if status.is_empty() {
            "with no status".to_string()
        } else {
            format!("as {status}")
        };
        return Err(Failure::refused(
            "attempt",
            format!("--attempt {given} is not in effect: koto lists it {read}. A reversed or refused attempt is no ground for a pass-up; record a new undecided attempt in {session} and give its id"),
        ));
    }
    let result = a.get("result").and_then(Value::as_str).unwrap_or("");
    if result != "undecided" {
        return Err(Failure::refused(
            "attempt",
            format!("--attempt {given} names a {result} attempt: a decided question is settled, not passed up (shirabe question settle)"),
        ));
    }
    let tied = a
        .get("questions")
        .and_then(Value::as_array)
        .is_some_and(|qs| qs.iter().any(|q| q.as_str() == Some(identity)))
        || a.get("question").and_then(Value::as_str) == Some(identity);
    if !tied {
        return Err(Failure::refused(
            "attempt",
            format!("--attempt {given} is {session}'s attempt at another question, not {identity}: its basis must name the question passed up"),
        ));
    }
    let s = a
        .get("session")
        .and_then(Value::as_str)
        .unwrap_or(session)
        .to_string();
    Ok(format!("{s}:{want_id}"))
}

pub fn pass_up(i: &PassUp) -> Result<Value, Failure> {
    check_name("in", "--in", i.session)?;
    check_identity(i.identity)?;
    koto::check_version()?;
    let ground = i.ground.ok_or_else(|| {
        Failure::refused(
            "ground",
            format!(
                "pass-up needs --ground: why the question is not {}'s to settle, one of {}, or {OUTSIDE_SCOPE} toward a coordinator",
                i.session,
                GROUNDS.join(", ")
            ),
        )
    })?;
    if !GROUNDS.contains(&ground) && ground != OUTSIDE_SCOPE {
        return Err(Failure::refused(
            "ground",
            format!(
                "--ground {ground:?} is not one of {}, {OUTSIDE_SCOPE}",
                GROUNDS.join(", ")
            ),
        ));
    }
    // The session's own recorded dispatcher, or person:owner for a session
    // nothing dispatched.
    let (above, _) = default_recipient(i.session)?;
    let target = match i.to {
        None => above.clone(),
        Some(t) => {
            let r = parse_recipient(t)?;
            if r != owner() && r != above {
                return Err(Failure::refused(
                    "to",
                    format!("--to {t}: a question passes up to {}'s own dispatcher ({above}) or to {}, and nowhere else", i.session, owner()),
                ));
            }
            r
        }
    };
    if ground == OUTSIDE_SCOPE && target.starts_with("person:") {
        return Err(Failure::refused(
            "ground",
            format!("--ground {OUTSIDE_SCOPE} passes up only to a coordinator: a question merely outside the brief is the coordinator's to settle, not the owner's"),
        ));
    }
    let h = History::read(i.identity)?;
    if !h.open() {
        return Err(Failure::refused(
            "identity",
            format!(
                "{} is no longer open; a closed question is not passed up",
                i.identity
            ),
        ));
    }
    let need = need_of(&h);
    let basis = if need == "decision" {
        Some(own_attempt(i.session, i.identity, i.attempt)?)
    } else {
        if i.attempt.is_some() {
            return Err(Failure::refused(
                "attempt",
                format!(
                    "{} is a {need} need, which rests on no attempt; leave --attempt out",
                    i.identity
                ),
            ));
        }
        None
    };
    let mut args: Vec<String> = vec![
        "decisions".into(),
        "readdress".into(),
        format!("--in={}", i.session),
        format!("--to={target}"),
        "--by=session".into(),
        format!("--reason=ground: {ground}"),
    ];
    if let Some(b) = &basis {
        args.push(format!("--basis={b}"));
    }
    if let Some(m) = run_mode().as_koto() {
        args.push(format!("--run-mode={m}"));
    }
    args.push("--".into());
    args.push(h.raiser());
    args.push(h.id());
    let rec = run_argv(&args)?;
    let id = printed_id(&rec, "pass-up")?;
    let mut out = Map::new();
    out.insert("v".into(), json!(1));
    out.insert("identity".into(), json!(i.identity));
    out.insert("session".into(), json!(i.session));
    out.insert("id".into(), json!(id));
    out.insert("to".into(), json!(target));
    out.insert("ground".into(), json!(ground));
    out.insert("need".into(), json!(need));
    out.insert("attempt".into(), json!(basis));
    out.insert(
        "addressee".into(),
        rec.get("addressee")
            .map(recipient_string)
            .unwrap_or_else(|| json!(target)),
    );
    Ok(Value::Object(out))
}

// ---------------------------------------------------------------------------
// settle

pub struct Settle<'a> {
    pub identity: Option<&'a str>,
    pub session: &'a str,
    pub what: Option<&'a str>,
    pub chosen: Option<&'a str>,
    pub reason: Option<&'a str>,
    pub basis: &'a [String],
    pub owner_note: Option<&'a str>,
}

/// The text recorded for a relayed claim: the choice, then the note, marked
/// as relayed so no reader takes it for the owner's answer.
pub fn relayed_text(chosen: &str, note: &str) -> String {
    format!("{chosen} (relayed, not the owner's answer: {note})")
}

/// The most dispatch links `at_or_below` follows up from a session before it
/// gives up; a real chain is a handful deep, and a loop never ends otherwise.
const MAX_CHAIN: usize = 64;

/// Whether `s` is `session` or a session dispatched under it, by following
/// `koto session origin` up from `s`. A session koto does not hold is not
/// below anything; any other koto failure is an error.
fn at_or_below(
    s: &str,
    session: &str,
    cache: &mut BTreeMap<String, bool>,
) -> Result<bool, Failure> {
    if let Some(v) = cache.get(s) {
        return Ok(*v);
    }
    let mut cur = s.to_string();
    let mut found = false;
    for _ in 0..MAX_CHAIN {
        if cur == session {
            found = true;
            break;
        }
        if !name_ok(&cur) {
            break;
        }
        let o = match koto::run(&["session", "origin", "--", &cur]) {
            Ok(o) => o,
            Err(r) if r.not_found() => break,
            Err(r) => return Err(r.into()),
        };
        if o.pointer("/origin/state").and_then(Value::as_str) != Some("dispatched") {
            break;
        }
        match o.pointer("/origin/dispatcher").and_then(Value::as_str) {
            Some(d) if !d.is_empty() => cur = d.to_string(),
            _ => break,
        }
    }
    cache.insert(s.to_string(), found);
    Ok(found)
}

/// A ground that reserves `h`'s question for the owner, recorded by
/// `session` or a session below it: the `ground: <g>` part of the reason of
/// an attempt tied to the question or of a pass-up of it, read with
/// `koto decisions show`. Returns the ground and the entry (`<s>:<id>`). An
/// attempt koto lists as reversed or refused, and a pass-up it does not
/// count, are skipped; one whose standing koto does not print counts.
fn reserved_ground(h: &History, session: &str) -> Result<Option<(String, String)>, Failure> {
    let mut cache = BTreeMap::new();
    for e in h.entries() {
        let entry = e.get("entry").and_then(Value::as_str);
        let counts = match entry {
            Some("attempt") => e
                .get("status")
                .and_then(Value::as_str)
                .is_none_or(|st| st == "in-effect"),
            Some("pass-up") => e.get("counted").and_then(Value::as_bool) != Some(false),
            _ => false,
        };
        if !counts {
            continue;
        }
        let (Some(es), Some(id)) = (
            e.get("session").and_then(Value::as_str),
            e.get("id").and_then(Value::as_str),
        ) else {
            continue;
        };
        if !name_ok(es) || !decision_id_ok(id) || !at_or_below(es, session, &mut cache)? {
            continue;
        }
        let shown = koto::run(&["decisions", "show", "--", es, id])?;
        let reason = shown
            .pointer("/decision/reason")
            .and_then(Value::as_str)
            .unwrap_or("");
        for part in reason.split("; ") {
            if let Some(g) = part.strip_prefix("ground: ") {
                if GROUNDS.contains(&g) {
                    return Ok(Some((g.to_string(), format!("{es}:{id}"))));
                }
            }
        }
    }
    Ok(None)
}

/// Each `--basis` that names an answer by `person:owner` must be an owner
/// answer in effect in `session`'s chain that reads as verified here: one
/// `koto decisions precedent --person owner --chain <session>` lists with
/// `reading` `verified`. A basis that names any other decision is left to
/// koto, which checks only that it exists.
fn check_owner_basis(session: &str, basis: &[String]) -> Result<(), Failure> {
    let mut prec: Option<Value> = None;
    for b in basis {
        let (s, id) = parse_ref("basis", "--basis", b)?;
        let shown = koto::run(&["decisions", "show", "--", s, id])?;
        let d = shown.get("decision").cloned().unwrap_or(Value::Null);
        let owners = d.get("kind").and_then(Value::as_str) == Some("answer")
            && d.pointer("/decider/kind").and_then(Value::as_str) == Some("person")
            && d.pointer("/decider/handle/value").and_then(Value::as_str) == Some(OWNER);
        if !owners {
            continue;
        }
        if prec.is_none() {
            let chain_arg = format!("--chain={session}");
            prec = Some(koto::run(&[
                "decisions",
                "precedent",
                "--person=owner",
                &chain_arg,
            ])?);
        }
        let row = prec
            .as_ref()
            .and_then(|p| p.get("answers"))
            .and_then(Value::as_array)
            .and_then(|rows| {
                rows.iter().find(|r| {
                    r.get("session").and_then(Value::as_str) == Some(s)
                        && r.get("id").and_then(Value::as_str) == Some(id)
                })
            });
        let Some(row) = row else {
            return Err(Failure::refused(
                "basis",
                format!("--basis {b} names an owner answer that is not in effect in {session}'s chain: koto decisions precedent --person owner --chain {session} does not list it. Rest the settle on an owner answer in effect, or on the session's own decision"),
            ));
        };
        let reading = row.get("reading").and_then(Value::as_str).unwrap_or("");
        if reading != "verified" {
            return Err(Failure::refused(
                "basis",
                format!(
                    "--basis {b} names an owner answer that does not read as verified here (koto reads it as {}); a settle rests only on an owner answer this host verified",
                    if reading.is_empty() { "nothing" } else { reading }
                ),
            )
            .with("reading", json!(reading)));
        }
    }
    Ok(())
}

pub fn settle(i: &Settle) -> Result<Value, Failure> {
    check_name("in", "--in", i.session)?;
    if let Some(id) = i.identity {
        check_identity(id)?;
    }
    for b in i.basis {
        parse_ref("basis", "--basis", b)?;
    }
    let chosen = i.chosen.unwrap_or("");
    text("chosen", "--chosen", chosen)?;
    if let Some(r) = i.reason {
        text("reason", "--reason", r)?;
    }
    if let Some(n) = i.owner_note {
        text("owner_note", "--owner-note", n)?;
    }
    if let Some(w) = i.what {
        text("what", "--what", w)?;
    }
    let Some(identity) = i.identity else {
        // A claim that answers no recorded question.
        let what = i.what.ok_or_else(|| {
            Failure::refused(
                "what",
                "settle with no question identity records a relayed claim: give --what, --chosen and --owner-note",
            )
        })?;
        let note = i.owner_note.ok_or_else(|| {
            Failure::refused(
                "owner_note",
                "settle with no question identity records a relayed claim: give --owner-note with what was relayed",
            )
        })?;
        koto::check_version()?;
        check_owner_basis(i.session, i.basis)?;
        let mut reason = relayed_text(chosen, note);
        if let Some(r) = i.reason {
            reason = format!("{reason}; {r}");
        }
        let mut args: Vec<String> = vec![
            "decisions".into(),
            "record".into(),
            "--kind=judgment".into(),
            "--outcome=settled".into(),
            format!("--subject=what={what}"),
            format!("--reason={reason}"),
        ];
        for b in i.basis {
            args.push(format!("--basis={b}"));
        }
        if let Some(m) = run_mode().as_koto() {
            args.push(format!("--run-mode={m}"));
        }
        args.push("--by=session".into());
        args.push("--".into());
        args.push(i.session.to_string());
        let rec = run_argv(&args)?;
        let id = printed_id(&rec, "judgment")?;
        return Ok(json!({
            "v": 1,
            "identity": Value::Null,
            "session": i.session,
            "id": id,
            "kind": "judgment",
            "what": what,
            "text": reason,
            "basis": i.basis,
        }));
    };
    if i.what.is_some() {
        return Err(Failure::refused(
            "what",
            "--what is for a claim that answers no recorded question; with a question identity, leave it out",
        ));
    }
    let reason = i.reason.ok_or_else(|| {
        Failure::refused(
            "reason",
            "settle needs --reason: why the session chose as it did",
        )
    })?;
    koto::check_version()?;
    let h = History::read(identity)?;
    let addressee = addressee_of(&h);
    let raiser = h.raiser();
    if i.owner_note.is_some() && addressee.starts_with("person:") {
        return Err(Failure::refused(
            "owner_note",
            format!("{identity} waits on {addressee}: a relayed claim is not the owner's answer and does not close it. The question stays open; present it to the owner, or record the claim as this session's own with settle --what"),
        ));
    }
    if let Some((ground, by)) = reserved_ground(&h, i.session)? {
        return Err(Failure::refused(
            "ground",
            format!("{identity} carries the ground {ground}, recorded by {by} at or below {}: that ground reserves the question for the owner, so {} does not settle it. Pass it up (shirabe question pass-up {identity} --in {} --ground {ground} --attempt <its own undecided attempt>)", i.session, i.session, i.session),
        )
        .with("ground", json!(ground))
        .with("recorded_by", json!(by)));
    }
    check_owner_basis(i.session, i.basis)?;
    let outcome = if i.session == raiser {
        "settled"
    } else {
        "answered"
    };
    let recorded_text = match i.owner_note {
        Some(n) => relayed_text(chosen, n),
        None => chosen.to_string(),
    };
    let mut args: Vec<String> = vec![
        "decisions".into(),
        "answer".into(),
        format!("--in={}", i.session),
        format!("--outcome={outcome}"),
        "--by=session".into(),
        format!("--text={recorded_text}"),
        format!("--reason={reason}"),
    ];
    for b in i.basis {
        args.push(format!("--basis={b}"));
    }
    if let Some(m) = run_mode().as_koto() {
        args.push(format!("--run-mode={m}"));
    }
    args.push("--".into());
    args.push(raiser);
    args.push(h.id());
    let rec = run_argv(&args)?;
    let id = printed_id(&rec, "answer")?;
    Ok(json!({
        "v": 1,
        "identity": identity,
        "session": i.session,
        "id": id,
        "kind": "answer",
        "outcome": outcome,
        "text": recorded_text,
        "basis": i.basis,
    }))
}

// ---------------------------------------------------------------------------
// seen

pub struct Seen<'a> {
    pub answer: &'a str,
    pub session: &'a str,
}

pub fn seen(i: &Seen) -> Result<Value, Failure> {
    check_name("in", "--in", i.session)?;
    let (s, id) = match i.answer.split_once(':') {
        Some((s, id)) if name_ok(s) && decision_id_ok(id) => (s, id),
        _ => {
            return Err(Failure::usage(format!(
                "{:?} is not an answer, <session>:<answer id>",
                i.answer
            )))
        }
    };
    koto::check_version()?;
    let shown = koto::run(&["decisions", "show", "--", s, id])?;
    let d = shown.get("decision").cloned().unwrap_or(Value::Null);
    let kind = d.get("kind").and_then(Value::as_str).unwrap_or("");
    let decider = d.pointer("/decider/kind").and_then(Value::as_str);
    let handle = d.pointer("/decider/handle/value").and_then(Value::as_str);
    let outcome = d.get("outcome").and_then(Value::as_str);
    if kind != "answer"
        || decider != Some("person")
        || handle != Some(OWNER)
        || outcome != Some("answered")
    {
        return Err(Failure::refused(
            "answer",
            format!(
                "{} is not an answer the owner gave: koto shows a {} by {}{}",
                i.answer,
                if kind.is_empty() { "decision" } else { kind },
                decider.unwrap_or("an unknown decider"),
                handle.map(|h| format!(":{h}")).unwrap_or_default()
            ),
        ));
    }
    let reading = shown
        .get("reading")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if reading != "verified" {
        let why = if reading.contains("remote") {
            "it reads as a remote session's answer, whose prompt this host did not check"
                .to_string()
        } else if reading.is_empty() {
            "koto gives it no reading".to_string()
        } else {
            format!("koto reads it as {reading}")
        };
        return Err(Failure::refused(
            "answer",
            format!("{} does not read as verified here: {why}", i.answer),
        )
        .with("reading", json!(reading)));
    }
    let chain_arg = format!("--chain={}", i.session);
    let prec = koto::run(&["decisions", "precedent", "--person=owner", &chain_arg])?;
    let row = prec
        .get("answers")
        .and_then(Value::as_array)
        .and_then(|rows| {
            rows.iter()
                .find(|r| {
                    r.get("session").and_then(Value::as_str) == Some(s)
                        && r.get("id").and_then(Value::as_str) == Some(id)
                })
                .cloned()
        });
    let Some(row) = row else {
        return Err(Failure::refused(
            "answer",
            format!("{} is not an owner answer in effect in {}'s chain: only an answer given at or below the session is marked seen there", i.answer, i.session),
        ));
    };
    // The same answers `pending`'s `unseen` lists: given in the session or
    // below it. One given above reached the session as precedent, not as
    // something it was waiting to read.
    let below = row.get("below").and_then(Value::as_bool) == Some(true);
    if !below && s != i.session {
        return Err(Failure::refused(
            "answer",
            format!("{} was given in {s}, above {} in its chain: seen marks only an answer given at or below the session, the ones its unseen listing holds. It is listed unseen in {s} and the sessions above it, and is marked seen there", i.answer, i.session),
        ));
    }
    let identity = row
        .get("identity")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if row.get("cited").and_then(Value::as_bool) == Some(true) {
        return Ok(json!({
            "v": 1,
            "answer": i.answer,
            "identity": identity,
            "session": i.session,
            "id": Value::Null,
            "recorded": false,
        }));
    }
    let mut args: Vec<String> = vec![
        "decisions".into(),
        "record".into(),
        "--kind=judgment".into(),
        "--outcome=settled".into(),
        format!("--subject=what=seen: the owner's answer to {identity}"),
        format!("--basis={s}:{id}"),
        "--reason=marked seen; the answer was already in effect, and this changes nothing".into(),
    ];
    if let Some(m) = run_mode().as_koto() {
        args.push(format!("--run-mode={m}"));
    }
    args.push("--by=session".into());
    args.push("--".into());
    args.push(i.session.to_string());
    let rec = run_argv(&args)?;
    let new_id = printed_id(&rec, "judgment")?;
    Ok(json!({
        "v": 1,
        "answer": i.answer,
        "identity": identity,
        "session": i.session,
        "id": new_id,
        "recorded": true,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refs_are_session_and_id() {
        assert!(parse_ref("basis", "--basis", "w1:000000000001").is_ok());
        for bad in ["w1", ":000000000001", "w1:", "w1:abc", "-x:000000000001"] {
            assert!(parse_ref("basis", "--basis", bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn relayed_text_names_the_note_as_relayed() {
        let t = relayed_text("B", "the owner said B in a message");
        assert!(t.starts_with("B "));
        assert!(t.contains("relayed, not the owner's answer"));
    }

    #[test]
    fn text_refuses_a_secret_without_echoing_it() {
        let tok = format!("ghp_{}", "a".repeat(30));
        let f = text("chosen", "--chosen", &tok).unwrap_err();
        assert_eq!(f.exit, super::super::EXIT_REFUSED);
        assert!(!f.message.contains(&tok));
    }
}
