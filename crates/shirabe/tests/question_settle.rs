//! `shirabe question settle` against the koto stand-in: the outcome it asks
//! koto for (answered by the addressee, settled by the raiser), the owner
//! note recorded as the session's own decision and refused for a question
//! waiting on a person, the relayed claim with no question, and the inputs
//! refused before any koto write. koto's own rules (who may answer, the
//! settle basis, the same-label owner answer) run against the real koto in
//! skills/coordinate/scripts/question-ladder_engine_test.sh.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

const Q: &str = "sid-w2/000000000005";

/// A question raised by `w2`, waiting on `addressee`.
fn setup(addressee: &str) -> Standin {
    let s = Standin::new();
    let (kind, name) = addressee.split_once(':').unwrap();
    let key = if kind == "person" { "handle" } else { "name" };
    s.write(
        "history/sid-w2_000000000005",
        format!(
            r#"{{"v":1,"identity":"{Q}","raiser":{{"name":"w2","id":"sid-w2"}},"question":{{"id":"000000000005","need":"decision","label":"cache"}},"addressee":{{"kind":"{kind}","{key}":"{name}","typed":true}},"open":true,"answer":null,"entries":[]}}"#
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
