//! `shirabe question settle` against the koto stand-in: the outcome it asks
//! koto for (answered by the addressee, settled by the raiser), the owner
//! note recorded as the session's own decision and refused for a question
//! waiting on a person, the relayed claim with no question, the inputs
//! refused before any koto write, a basis naming an owner answer checked
//! against koto's precedent read, and a ground reserved for the owner in the
//! question's history refusing the settle. koto's own rules (who may answer, the
//! settle basis, the same-label owner answer) run against the real koto in
//! skills/coordinate/scripts/question-ladder_engine_test.sh.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

const Q: &str = "sid-w2/000000000005";

/// A question raised by `w2`, waiting on `addressee`.
fn setup(addressee: &str) -> Standin {
    setup_with(addressee, "")
}

/// As `setup`, with `entries` (JSON objects, comma-separated) as the
/// question's history entries. `w2` is dispatched by `manager`, and
/// `manager` by `director`.
fn setup_with(addressee: &str, entries: &str) -> Standin {
    let s = Standin::new();
    s.write(
        "origin/w2",
        r#"{"session":"w2","via":"init","origin":{"state":"dispatched","dispatcher":"manager","dispatcher_kind":"session"}}"#,
    );
    s.write(
        "origin/manager",
        r#"{"session":"manager","via":"init","origin":{"state":"dispatched","dispatcher":"director","dispatcher_kind":"session"}}"#,
    );
    let (kind, name) = addressee.split_once(':').unwrap();
    let key = if kind == "person" { "handle" } else { "name" };
    s.write(
        "history/sid-w2_000000000005",
        format!(
            r#"{{"v":1,"identity":"{Q}","raiser":{{"name":"w2","id":"sid-w2"}},"question":{{"id":"000000000005","need":"decision","label":"cache"}},"addressee":{{"kind":"{kind}","{key}":"{name}","typed":true}},"open":true,"answer":null,"entries":[{entries}]}}"#
        ),
    );
    s
}

fn settle(s: &Standin, session: &str, rest: &[&str]) -> assert_cmd::Command {
    let mut args = vec!["settle", Q, "--in", session];
    args.extend_from_slice(rest);
    s.cmd(&args)
}

fn the_write(s: &Standin) -> String {
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    w[0].clone()
}

fn refused(out: &std::process::Output, field: &str) -> Value {
    let j = json(&out.stdout);
    assert_eq!(j["error"]["exit"], json!(1), "{j}");
    assert_eq!(j["error"]["field"], json!(field), "{j}");
    j
}

#[test]
fn the_addressee_settles_as_answered_by_a_session_decider() {
    let s = setup("session:manager");
    let out = settle(
        &s,
        "manager",
        &[
            "--chosen",
            "SQLite",
            "--reason",
            "same store as the owner chose",
            "--basis",
            "w1:000000000001",
        ],
    )
    .assert()
    .success()
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["outcome"], json!("answered"));
    let r = the_write(&s);
    assert!(r.starts_with("decisions answer w2 000000000005 "), "{r}");
    for part in [
        "--in manager",
        "--outcome answered",
        "--by session",
        "--text SQLite",
        "--basis w1:000000000001",
    ] {
        assert!(r.contains(part), "{part} in {r}");
    }
    assert!(!r.contains("person:"), "{r}");
}

#[test]
fn the_raiser_settles_as_settled() {
    let s = setup("session:manager");
    settle(
        &s,
        "w2",
        &[
            "--chosen",
            "SQLite",
            "--reason",
            "the owner's answer to the same label",
            "--basis",
            "w1:000000000001",
        ],
    )
    .assert()
    .success();
    assert!(the_write(&s).contains("--outcome settled"));
}

#[test]
fn kotos_refusal_of_a_settle_passes_through_as_exit_4() {
    // A raiser settling a need, a settle with no basis koto takes, and a
    // session that is neither addressee nor raiser: koto refuses each.
    let s = setup("session:manager");
    s.write(
        "fail",
        "decisions answer|invalid_decision|a settle of a question waiting on session:manager needs a --basis\n",
    );
    let out = settle(&s, "w2", &["--chosen", "SQLite", "--reason", "r"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["error"]["code"], json!("invalid_decision"));
}

#[test]
fn an_empty_chosen_or_reason_is_refused_before_koto() {
    let s = setup("session:manager");
    let out = settle(&s, "manager", &["--chosen", " ", "--reason", "r"])
        .assert()
        .code(1)
        .get_output()
        .clone();
    refused(&out, "chosen");
    let out = settle(&s, "manager", &["--chosen", "B", "--reason", ""])
        .assert()
        .code(1)
        .get_output()
        .clone();
    refused(&out, "reason");
    let out = settle(&s, "manager", &["--chosen", "B"])
        .assert()
        .code(1)
        .get_output()
        .clone();
    refused(&out, "reason");
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn content_shaped_like_a_secret_is_refused_without_printing_it() {
    let s = setup("session:manager");
    let tok = format!("ghp_{}", "b".repeat(30));
    let out = settle(&s, "manager", &["--chosen", "B", "--reason", &tok])
        .assert()
        .code(1)
        .get_output()
        .clone();
    refused(&out, "reason");
    let printed = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(!printed.contains(&tok), "{printed}");
    assert!(s.writes().is_empty());
}

#[test]
fn an_owner_note_is_the_sessions_own_decision_with_the_note_in_its_text() {
    let s = setup("session:manager");
    let out = settle(
        &s,
        "manager",
        &[
            "--chosen",
            "B",
            "--reason",
            "the owner's word, relayed",
            "--owner-note",
            "the owner said B in a message",
        ],
    )
    .assert()
    .success()
    .get_output()
    .clone();
    let j = json(&out.stdout);
    let text = j["text"].as_str().unwrap();
    assert!(text.contains("the owner said B in a message"), "{text}");
    assert!(text.contains("relayed, not the owner's answer"), "{text}");
    let r = the_write(&s);
    assert!(r.contains("--by session"), "{r}");
    assert!(!r.contains("person:owner"), "{r}");
}

#[test]
fn an_owner_note_on_a_question_waiting_on_the_owner_is_refused() {
    let s = setup("person:owner");
    let out = settle(
        &s,
        "manager",
        &[
            "--chosen",
            "B",
            "--reason",
            "r",
            "--owner-note",
            "the owner said B",
        ],
    )
    .assert()
    .code(1)
    .get_output()
    .clone();
    let j = refused(&out, "owner_note");
    assert!(j["error"]["message"]
        .as_str()
        .unwrap()
        .contains("stays open"));
    assert!(s.writes().is_empty());
}

#[test]
fn a_claim_with_no_question_records_a_judgment_by_the_session() {
    let s = Standin::new();
    let out = s
        .cmd(&[
            "settle",
            "--in",
            "manager",
            "--what",
            "licence for the package",
            "--chosen",
            "MIT",
            "--owner-note",
            "the owner said MIT in the channel",
        ])
        .assert()
        .success()
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["kind"], json!("judgment"));
    let r = the_write(&s);
    assert!(r.starts_with("decisions record manager "), "{r}");
    for part in [
        "--kind judgment",
        "--by session",
        "--subject what=licence for the package",
    ] {
        assert!(r.contains(part), "{part} in {r}");
    }
    assert!(r.contains("the owner said MIT in the channel"), "{r}");
}

#[test]
fn a_claim_with_no_question_needs_what_and_owner_note() {
    let s = Standin::new();
    let out = s
        .cmd(&["settle", "--in", "manager", "--chosen", "MIT"])
        .assert()
        .code(1)
        .get_output()
        .clone();
    refused(&out, "what");
    let out = s
        .cmd(&["settle", "--in", "manager", "--what", "licence", "--chosen", "MIT"])
        .assert()
        .code(1)
        .get_output()
        .clone();
    refused(&out, "owner_note");
    assert!(s.writes().is_empty());
}

#[test]
fn a_malformed_basis_is_refused() {
    let s = setup("session:manager");
    let out = settle(
        &s,
        "manager",
        &["--chosen", "B", "--reason", "r", "--basis", "w1"],
    )
    .assert()
    .code(1)
    .get_output()
    .clone();
    refused(&out, "basis");
}

// ---------------------------------------------------------------------------
// A basis naming an owner answer

const OWNER_DECIDER: &str =
    r#"{"kind":"person","handle":{"source":"handed","value":"owner"},"surface":"terminal"}"#;

/// `koto decisions show w1 000000000003`: an answer by `decider`.
fn show_answer(s: &Standin, decider: &str) {
    s.write(
        "show/w1_000000000003",
        format!(
            r#"{{"v":1,"id":"000000000003","session":"w1","status":"in-effect","reading":"verified","decision":{{"id":"000000000003","kind":"answer","outcome":"answered","decider":{decider},"subject":{{"id":"000000000002","session":"w3","text":"SQLite","label":"cache"}}}}}}"#
        ),
    );
}

fn precedent_row(s: &Standin, reading: &str) {
    s.write(
        "precedent.json",
        format!(
            r#"{{"v":1,"person":"owner","chain":"manager","answers":[{{"below":true,"cited":false,"id":"000000000003","identity":"sid-w3/000000000002","label":"cache","reading":"{reading}","session":"w1","text":"SQLite"}}]}}"#
        ),
    );
}

fn settle_on_owner_answer(s: &Standin) -> assert_cmd::Command {
    settle(
        s,
        "manager",
        &[
            "--chosen",
            "SQLite",
            "--reason",
            "the owner chose SQLite for the cache",
            "--basis",
            "w1:000000000003",
        ],
    )
}

#[test]
fn a_basis_naming_an_owner_answer_in_effect_in_the_chain_is_taken() {
    let s = setup("session:manager");
    show_answer(&s, OWNER_DECIDER);
    precedent_row(&s, "verified");
    settle_on_owner_answer(&s).assert().success();
    assert!(
        s.log()
            .iter()
            .any(|l| l.starts_with("decisions precedent") && l.contains("--chain manager")),
        "{:?}",
        s.log()
    );
    assert!(the_write(&s).contains("--basis w1:000000000003"));
}

#[test]
fn a_basis_naming_an_owner_answer_not_in_effect_in_the_chain_is_refused() {
    let s = setup("session:manager");
    show_answer(&s, OWNER_DECIDER);
    s.write("precedent.json", r#"{"v":1,"person":"owner","answers":[]}"#);
    let out = settle_on_owner_answer(&s)
        .assert()
        .code(1)
        .get_output()
        .clone();
    let j = refused(&out, "basis");
    assert!(
        j["error"]["message"]
            .as_str()
            .unwrap()
            .contains("not in effect in manager's chain"),
        "{j}"
    );
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn a_basis_naming_an_owner_answer_that_does_not_read_verified_is_refused() {
    let s = setup("session:manager");
    show_answer(&s, OWNER_DECIDER);
    precedent_row(&s, "a remote session's answer");
    let out = settle_on_owner_answer(&s)
        .assert()
        .code(1)
        .get_output()
        .clone();
    let j = refused(&out, "basis");
    assert_eq!(j["error"]["reading"], json!("a remote session's answer"));
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn a_basis_naming_a_sessions_decision_is_only_shape_checked() {
    let s = setup("session:manager");
    show_answer(
        &s,
        r#"{"kind":"session","session":{"source":"observed","value":"w1"}}"#,
    );
    settle_on_owner_answer(&s).assert().success();
    assert!(
        !s.log().iter().any(|l| l.starts_with("decisions precedent")),
        "{:?}",
        s.log()
    );
}

// ---------------------------------------------------------------------------
// A ground reserved for the owner

/// A history entry by `session`: an attempt in effect, a reversed attempt,
/// or a counted pass-up.
fn entry(kind: &str, session: &str, id: &str) -> String {
    match kind {
        "attempt" => format!(
            r#"{{"entry":"attempt","session":"{session}","id":"{id}","kind":"judgment","result":"undecided","status":"in-effect"}}"#
        ),
        "reversed-attempt" => format!(
            r#"{{"entry":"attempt","session":"{session}","id":"{id}","kind":"judgment","result":"undecided","status":"reversed"}}"#
        ),
        _ => format!(
            r#"{{"entry":"pass-up","session":"{session}","id":"{id}","kind":"readdress","outcome":"passed","counted":true}}"#
        ),
    }
}

/// `koto decisions show <session> <id>` for an entry whose reason is `reason`.
fn show_reason(s: &Standin, session: &str, id: &str, reason: &str) {
    s.write(
        &format!("show/{session}_{id}"),
        format!(
            r#"{{"v":1,"id":"{id}","session":"{session}","status":"in-effect","decision":{{"id":"{id}","kind":"judgment","outcome":"settled","reason":"{reason}"}}}}"#
        ),
    );
}

fn plain_settle(s: &Standin) -> assert_cmd::Command {
    settle(
        s,
        "manager",
        &[
            "--chosen",
            "SQLite",
            "--reason",
            "r",
            "--basis",
            "manager:000000000001",
        ],
    )
}

#[test]
fn a_reserved_ground_recorded_below_refuses_the_settle_and_says_pass_it_up() {
    // w2, dispatched by manager, recorded its attempt with ground
    // changes-scope: the question is the owner's, so manager passes it up.
    let s = setup_with("session:manager", &entry("attempt", "w2", "000000000004"));
    show_reason(&s, "w2", "000000000004", "ground: changes-scope");
    let out = plain_settle(&s).assert().code(1).get_output().clone();
    let j = refused(&out, "ground");
    assert_eq!(j["error"]["ground"], json!("changes-scope"));
    assert_eq!(j["error"]["recorded_by"], json!("w2:000000000004"));
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains("shirabe question pass-up"), "{msg}");
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn a_reserved_ground_in_the_sessions_own_pass_up_refuses_the_settle() {
    let s = setup_with(
        "session:manager",
        &entry("pass-up", "manager", "000000000006"),
    );
    show_reason(&s, "manager", "000000000006", "ground: reserved-step");
    let out = plain_settle(&s).assert().code(1).get_output().clone();
    let j = refused(&out, "ground");
    assert_eq!(j["error"]["ground"], json!("reserved-step"));
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn a_ground_after_other_reason_parts_is_read() {
    let s = setup_with("session:manager", &entry("attempt", "w2", "000000000004"));
    show_reason(
        &s,
        "w2",
        "000000000004",
        "chosen: SQLite; undo: costly: a server to keep; ground: outward-facing",
    );
    let out = plain_settle(&s).assert().code(1).get_output().clone();
    assert_eq!(
        refused(&out, "ground")["error"]["ground"],
        json!("outward-facing")
    );
}

#[test]
fn grounds_that_do_not_reserve_the_question_leave_the_settle_to_koto() {
    // Each case settles: a ground recorded above the session (director), an
    // outside-scope ground (a coordinator's to settle), a reversed attempt,
    // and an attempt with no ground at all.
    let cases: [(&str, &str, &str, &str); 4] = [
        ("pass-up", "director", "000000000007", "ground: changes-scope"),
        ("pass-up", "manager", "000000000006", "ground: outside-scope"),
        ("reversed-attempt", "w2", "000000000004", "ground: changes-scope"),
        ("attempt", "w2", "000000000004", "chosen: SQLite"),
    ];
    for (kind, session, id, reason) in cases {
        let s = setup_with("session:manager", &entry(kind, session, id));
        show_reason(&s, session, id, reason);
        plain_settle(&s).assert().success();
        assert_eq!(
            s.writes().len(),
            1,
            "{kind} {session} {reason}: {:?}",
            s.writes()
        );
    }
}
