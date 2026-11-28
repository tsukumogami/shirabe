//! `shirabe question pass-up` against the koto stand-in: the attempt a
//! decision question needs (the calling session's own, in effect,
//! undecided, tied to that question), the need's exemption, the grounds and recipients it
//! takes, and koto's refusals passed through. The same rules against the
//! real koto run in skills/coordinate/scripts/question-ladder_engine_test.sh.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

const Q: &str = "sid-w1/000000000005";

/// `manager`, dispatched by `director`, holding `q1` raised by `w1`
/// (identity `sid-w1/000000000005`, a decision question, open), with the
/// attempts listed in `manager`'s run given as JSON.
fn setup(attempts: &str, need: &str) -> Standin {
    let s = Standin::new();
    s.write(
        "origin/manager",
        r#"{"session":"manager","via":"init","origin":{"state":"dispatched","dispatcher":"director","dispatcher_kind":"session"}}"#,
    );
    s.write(
        "history/sid-w1_000000000005",
        format!(
            r#"{{"v":1,"identity":"{Q}","raiser":{{"name":"w1","id":"sid-w1"}},"question":{{"id":"000000000005","need":"{need}","label":"cache","packet":null}},"addressee":{{"kind":"session","name":"manager","typed":true}},"open":true,"answer":null,"entries":[]}}"#
        ),
    );
    s.write(
        "attempts/manager",
        format!(r#"{{"v":1,"in":"manager","attempts":[{attempts}],"unreadable":[]}}"#),
    );
    s.write("counter", "10");
    s
}

fn att(id: &str, session: &str, result: &str, question: &str) -> String {
    att_status(id, session, result, question, Some("in-effect"))
}

/// An attempt row as `koto decisions attempts` prints it, with the `status`
/// given (left out with `None`).
fn att_status(
    id: &str,
    session: &str,
    result: &str,
    question: &str,
    status: Option<&str>,
) -> String {
    let status = status
        .map(|st| format!(r#","status":"{st}""#))
        .unwrap_or_default();
    format!(
        r#"{{"id":"{id}","session":"{session}","result":"{result}","what":"cache store","question":"{question}","questions":["{question}"]{status}}}"#
    )
}

fn pass_up(s: &Standin, rest: &[&str]) -> assert_cmd::Command {
    let mut args = vec!["pass-up", Q, "--in", "manager"];
    args.extend_from_slice(rest);
    s.cmd(&args)
}

fn refused(s: &Standin, rest: &[&str], field: &str) -> Value {
    let out = pass_up(s, rest).assert().code(1).get_output().clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["field"], json!(field), "{rest:?}: {j}");
    assert!(s.writes().is_empty(), "{rest:?}: {:?}", s.writes());
    j
}

#[test]
fn pass_up_without_an_attempt_is_refused_naming_the_attempt() {
    let s = setup("", "decision");
    let j = refused(&s, &["--ground", "changes-scope"], "attempt");
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains("attempt"), "{msg}");
    assert!(msg.contains("manager"), "{msg}");
}

#[test]
fn the_raisers_own_attempt_does_not_count_for_the_coordinator() {
    // w1's attempt is not in manager's run, so `attempts --in manager` does
    // not list it; naming it is refused.
    let s = setup("", "decision");
    refused(
        &s,
        &["--ground", "changes-scope", "--attempt", "w1:000000000004"],
        "attempt",
    );
}

#[test]
fn an_attempt_by_the_session_at_another_question_is_refused() {
    let s = setup(
        &att(
            "000000000001",
            "manager",
            "undecided",
            "sid-w2/000000000007",
        ),
        "decision",
    );
    let j = refused(
        &s,
        &["--ground", "changes-scope", "--attempt", "000000000001"],
        "attempt",
    );
    assert!(j["error"]["message"]
        .as_str()
        .unwrap()
        .contains("another question"));
}

#[test]
fn a_deciding_attempt_is_refused_as_settled_not_passed_up() {
    for result in ["decided", "provisional"] {
        let s = setup(&att("000000000001", "manager", result, Q), "decision");
        let j = refused(
            &s,
            &["--ground", "changes-scope", "--attempt", "000000000001"],
            "attempt",
        );
        assert!(
            j["error"]["message"]
                .as_str()
                .unwrap()
                .contains("a decided question is settled, not passed up"),
            "{result}: {j}"
        );
    }
}

#[test]
fn a_missing_or_unknown_ground_is_refused() {
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    refused(&s, &["--attempt", "000000000001"], "ground");
    refused(
        &s,
        &["--ground", "because", "--attempt", "000000000001"],
        "ground",
    );
}

#[test]
fn only_the_dispatcher_and_the_owner_are_taken_as_recipients() {
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    for to in ["person:someone-else", "session:w2", "session:other"] {
        refused(
            &s,
            &[
                "--ground",
                "changes-scope",
                "--attempt",
                "000000000001",
                "--to",
                to,
            ],
            "to",
        );
    }
}

#[test]
fn outside_scope_passes_up_only_to_a_coordinator() {
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    refused(
        &s,
        &[
            "--ground",
            "outside-scope",
            "--attempt",
            "000000000001",
            "--to",
            "person:owner",
        ],
        "ground",
    );
    pass_up(
        &s,
        &["--ground", "outside-scope", "--attempt", "000000000001"],
    )
    .assert()
    .success();
}

#[test]
fn with_its_own_undecided_attempt_the_question_passes_up_to_the_dispatcher() {
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    let out = pass_up(
        &s,
        &["--ground", "changes-scope", "--attempt", "000000000001"],
    )
    .assert()
    .success()
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["identity"], json!(Q));
    assert_eq!(j["to"], json!("session:director"));
    assert_eq!(j["attempt"], json!("manager:000000000001"));
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    let r = &w[0];
    assert!(r.starts_with("decisions readdress w1 000000000005 "), "{r}");
    for part in [
        "--in manager",
        "--to session:director",
        "--by session",
        "--basis manager:000000000001",
        "--reason ground: changes-scope",
    ] {
        assert!(r.contains(part), "{part} in {r}");
    }
}

#[test]
fn to_the_owner_with_its_own_attempt() {
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    pass_up(
        &s,
        &[
            "--ground",
            "reserved-step",
            "--attempt",
            "manager:000000000001",
            "--to",
            "person:owner",
        ],
    )
    .assert()
    .success();
    assert!(s.writes()[0].contains("--to person:owner"));
}

#[test]
fn a_need_passes_with_no_attempt() {
    let s = setup("", "credential");
    pass_up(&s, &["--ground", "reserved-step", "--to", "person:owner"])
        .assert()
        .success();
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    assert!(!w[0].contains("--basis"), "{}", w[0]);
}

#[test]
fn a_need_refuses_an_attempt() {
    let s = setup(
        &att("000000000001", "manager", "undecided", Q),
        "credential",
    );
    refused(
        &s,
        &[
            "--ground",
            "reserved-step",
            "--attempt",
            "000000000001",
            "--to",
            "person:owner",
        ],
        "attempt",
    );
}

#[test]
fn kotos_refusal_passes_through_as_exit_4() {
    // koto refuses a pass-up recorded by a session that is neither the
    // question's addressee nor its raiser, and one past the twenty-question
    // limit; the stand-in plays the refusal.
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    s.write(
        "fail",
        "decisions readdress|invalid_decision|a pass-up is recorded by the question's raiser or by the session or anchor it waits on now\n",
    );
    let out = pass_up(
        &s,
        &["--ground", "changes-scope", "--attempt", "000000000001"],
    )
    .assert()
    .code(4)
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["code"], json!("invalid_decision"));
}

#[test]
fn an_identity_koto_does_not_hold_exits_4_decision_not_found() {
    let s = setup("", "decision");
    let out = s
        .cmd(&[
            "pass-up",
            "sid-w9/000000000001",
            "--in",
            "manager",
            "--ground",
            "changes-scope",
        ])
        .assert()
        .code(4)
        .get_output()
        .clone();
    assert_eq!(
        json(&out.stdout)["error"]["code"],
        json!("decision_not_found")
    );
}

#[test]
fn a_closed_question_is_not_passed_up() {
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    s.write(
        "history/sid-w1_000000000005",
        format!(
            r#"{{"v":1,"identity":"{Q}","raiser":{{"name":"w1","id":"sid-w1"}},"question":{{"id":"000000000005","need":"decision"}},"open":false,"answer":{{"outcome":"answered"}},"entries":[]}}"#
        ),
    );
    refused(
        &s,
        &["--ground", "changes-scope", "--attempt", "000000000001"],
        "identity",
    );
}

#[test]
fn an_attempt_that_is_not_in_effect_is_refused() {
    // koto lists a reversed attempt with its old result, so `undecided`
    // alone would pass; its `status` is what says it no longer counts.
    for status in [Some("reversed"), Some("refused"), None] {
        let s = setup(
            &att_status("000000000001", "manager", "undecided", Q, status),
            "decision",
        );
        let j = refused(
            &s,
            &["--ground", "changes-scope", "--attempt", "000000000001"],
            "attempt",
        );
        let msg = j["error"]["message"].as_str().unwrap();
        assert!(msg.contains("not in effect"), "{status:?}: {msg}");
    }
}

#[test]
fn the_limit_of_twenty_passes_through_as_exit_4_with_kotos_code() {
    // A pass-up to the owner when the raiser's run already holds twenty open
    // questions waiting on a person: koto refuses the readdress with
    // invalid_decision on field `to` (its check_person_limit), and shirabe
    // passes code, field and message through.
    let s = setup(&att("000000000001", "manager", "undecided", Q), "decision");
    s.write(
        "fail",
        "decisions readdress|invalid_decision|the run of 'w1' holds 20 open questions waiting on a person, and the limit of twenty (20) is reached: one has to be answered, settled or withdrawn before another waits on a person|to\n",
    );
    let out = pass_up(
        &s,
        &[
            "--ground",
            "changes-scope",
            "--attempt",
            "000000000001",
            "--to",
            "person:owner",
        ],
    )
    .assert()
    .code(4)
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["exit"], json!(4), "{j}");
    assert_eq!(j["error"]["code"], json!("invalid_decision"), "{j}");
    assert_eq!(j["error"]["field"], json!("to"), "{j}");
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.starts_with("koto refused: "), "{msg}");
    assert!(msg.contains("the limit of twenty (20) is reached"), "{msg}");
    // The readdress was tried once and nothing else was written.
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    assert!(w[0].starts_with("decisions readdress"), "{w:?}");
}
