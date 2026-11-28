//! `shirabe question seen` against the koto stand-in: one judgment citing an
//! owner answer in the session's chain, nothing added the second time, and
//! each answer it refuses (not an owner answer, outside the chain, given
//! above the session, a remote
//! session's reading, one koto does not hold). Against the real koto, the
//! listing in the session and above it runs in
//! skills/coordinate/scripts/question-ladder_engine_test.sh.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

const ANSWER: &str = "w1:000000000003";

fn show(decider: &str, kind: &str, reading: &str) -> String {
    format!(
        r#"{{"v":1,"id":"000000000003","session":"w1","status":"in-effect","reading":"{reading}","decision":{{"id":"000000000003","kind":"{kind}","outcome":"answered","decider":{decider},"subject":{{"id":"000000000002","session":"w3","text":"SQLite","label":"cache"}}}}}}"#
    )
}

const OWNER: &str = r#"{"kind":"person","handle":{"source":"handed","value":"owner"},"surface":"terminal"}"#;
const SESSION: &str =
    r#"{"kind":"session","session":{"source":"observed","value":"w1"}}"#;

fn precedent(cited: bool) -> String {
    format!(
        r#"{{"v":1,"person":"owner","chain":"manager","answers":[{{"below":true,"cited":{cited},"id":"000000000003","identity":"sid-w3/000000000002","label":"cache","reading":"verified","session":"w1","text":"SQLite"}}]}}"#
    )
}

fn setup(shown: &str, prec: &str) -> Standin {
    let s = Standin::new();
    s.write("show/w1_000000000003", shown);
    s.write("precedent.json", prec);
    s
}

fn seen(s: &Standin) -> assert_cmd::Command {
    s.cmd(&["seen", ANSWER, "--in", "manager"])
}

fn refused(s: &Standin, why: &str) -> Value {
    let out = seen(s).assert().code(1).get_output().clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["field"], json!("answer"), "{j}");
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains(why), "{why} in {msg}");
    assert!(s.writes().is_empty(), "{:?}", s.writes());
    j
}

#[test]
fn seen_records_one_judgment_citing_the_answer() {
    let s = setup(&show(OWNER, "answer", "verified"), &precedent(false));
    let out = seen(&s).assert().success().get_output().clone();
    let j = json(&out.stdout);
    assert_eq!(j["recorded"], json!(true));
    assert_eq!(j["identity"], json!("sid-w3/000000000002"));
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    let r = &w[0];
    assert!(r.starts_with("decisions record manager "), "{r}");
    for part in [
        "--kind judgment",
        "--outcome settled",
        "--basis w1:000000000003",
        "--by session",
    ] {
        assert!(r.contains(part), "{part} in {r}");
    }
    // Nothing is written to the answer's session.
    assert!(!w.iter().any(|l| l.contains("decisions answer")), "{w:?}");
}

#[test]
fn a_second_seen_adds_nothing() {
    let s = setup(&show(OWNER, "answer", "verified"), &precedent(true));
    let out = seen(&s).assert().success().get_output().clone();
    assert_eq!(json(&out.stdout)["recorded"], json!(false));
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn an_entry_that_is_not_an_owner_answer_is_refused() {
    let s = setup(&show(SESSION, "answer", "verified"), &precedent(false));
    refused(&s, "is not an answer the owner gave");
    let s = setup(&show(OWNER, "judgment", "verified"), &precedent(false));
    refused(&s, "is not an answer the owner gave");
}

#[test]
fn an_answer_outside_the_sessions_chain_is_refused() {
    let s = setup(
        &show(OWNER, "answer", "verified"),
        r#"{"v":1,"person":"owner","answers":[]}"#,
    );
    refused(&s, "chain");
}

#[test]
fn an_answer_given_above_the_session_is_refused() {
    // The precedent read lists the answer given in w1 with `below` false:
    // here w1 sits above manager in its chain. `unseen` at manager never lists it, so seen there
    // refuses it rather than marking something manager was never shown.
    let s = setup(
        &show(OWNER, "answer", "verified"),
        r#"{"v":1,"person":"owner","chain":"manager","answers":[{"below":false,"cited":false,"id":"000000000003","identity":"sid-w3/000000000002","label":"cache","reading":"verified","session":"w1","text":"SQLite"}]}"#,
    );
    let j = refused(&s, "above manager");
    assert!(
        j["error"]["message"]
            .as_str()
            .unwrap()
            .contains("at or below the session"),
        "{j}"
    );
}

#[test]
fn an_answer_given_in_the_session_itself_is_marked() {
    // `below` is false for the session's own answers; the session is
    // included, as `unseen` includes it.
    let s = Standin::new();
    s.write(
        "show/manager_000000000003",
        show(OWNER, "answer", "verified").replace("\"session\":\"w1\"", "\"session\":\"manager\""),
    );
    s.write(
        "precedent.json",
        r#"{"v":1,"person":"owner","chain":"manager","answers":[{"below":false,"cited":false,"id":"000000000003","identity":"sid-w3/000000000002","label":"cache","reading":"verified","session":"manager","text":"SQLite"}]}"#,
    );
    let out = s
        .cmd(&["seen", "manager:000000000003", "--in", "manager"])
        .assert()
        .success()
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["recorded"], json!(true));
}

#[test]
fn a_remote_sessions_answer_is_refused() {
    let s = setup(
        &show(OWNER, "answer", "a remote session's answer"),
        &precedent(false),
    );
    let j = refused(&s, "remote session's answer");
    assert_eq!(j["error"]["reading"], json!("a remote session's answer"));
}

#[test]
fn an_answer_koto_does_not_hold_exits_4_decision_not_found() {
    let s = Standin::new();
    s.write(
        "fail",
        "decisions show|decision_not_found|'w1' holds no decision 000000000003\n",
    );
    let out = seen(&s).assert().code(4).get_output().clone();
    assert_eq!(
        json(&out.stdout)["error"]["code"],
        json!("decision_not_found")
    );
}

#[test]
fn a_malformed_answer_is_a_usage_error() {
    let s = Standin::new();
    s.cmd(&["seen", "w1", "--in", "manager"]).assert().code(2);
    s.cmd(&["seen", "w1:abc", "--in", "manager"]).assert().code(2);
}
