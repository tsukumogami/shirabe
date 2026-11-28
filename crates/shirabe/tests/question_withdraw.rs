//! `shirabe question withdraw` against the koto stand-in: what it hands koto,
//! its own refusals before any write, and koto's refusals passed through. Who
//! may withdraw and whether the question is still open are koto's rules;
//! skills/work-on/scripts/decide-first-routes_test.sh runs them against a real
//! koto store.

mod question_support;

use question_support::*;
use serde_json::json;

const Q: &str = "sid-w2/000000000002";

/// A question raised by `w2` that the stand-in's history serves as open.
fn raised(s: &Standin) {
    s.write(
        "history/sid-w2_000000000002",
        json!({
            "v": 1, "identity": Q, "raiser": {"name": "w2", "id": "sid-w2"},
            "question": {"id": "000000000002", "packet": "x", "content_stored": true},
            "open": true, "answer": null, "entries": [],
        })
        .to_string(),
    );
}

fn withdraw(s: &Standin, in_: &str, rest: &[&str]) -> assert_cmd::Command {
    let mut args = vec!["withdraw", Q, "--in", in_];
    args.extend_from_slice(rest);
    s.cmd(&args)
}

#[test]
fn withdraw_by_the_raiser_records_a_withdrawn_answer_with_the_reason() {
    let s = Standin::new();
    raised(&s);
    let out = withdraw(&s, "w2", &["--reason", "the dependency landed"])
        .assert()
        .success()
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["identity"], json!(Q));
    assert_eq!(j["outcome"], json!("withdrawn"));
    assert_eq!(j["reason"], json!("the dependency landed"));
    assert_eq!(j["entry"], json!("w2:w1"));
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    assert_eq!(
        w[0],
        "decisions answer w2 000000000002 --in w2 --outcome withdrawn --reason the dependency landed --by session"
    );
}

#[test]
fn withdraw_by_the_raisers_successor_names_the_raiser_and_runs_in_the_successor() {
    let s = Standin::new();
    raised(&s);
    withdraw(&s, "w3", &["--reason", "settled another way"])
        .assert()
        .success();
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    assert!(
        w[0].starts_with("decisions answer w2 000000000002 --in w3 "),
        "{w:?}"
    );
}

#[test]
fn withdraw_with_no_reason_or_an_empty_one_exits_1_and_records_nothing() {
    for rest in [&[][..], &["--reason", ""][..], &["--reason", "   "][..]] {
        let s = Standin::new();
        raised(&s);
        let out = withdraw(&s, "w2", rest)
            .assert()
            .code(1)
            .get_output()
            .clone();
        assert_eq!(
            json(&out.stdout)["error"]["field"],
            json!("reason"),
            "{rest:?}"
        );
        assert!(s.writes().is_empty(), "{rest:?}: {:?}", s.writes());
        assert!(s.log().is_empty(), "{rest:?}: {:?}", s.log());
    }
}

#[test]
fn withdraw_from_a_session_neither_raiser_nor_successor_exits_4_with_kotos_refusal() {
    let s = Standin::new();
    raised(&s);
    s.write(
        "fail",
        "decisions answer|invalid_decision|a question is withdrawn only in the session that raised it or a session continuing it; 'manager' is neither\n",
    );
    let out = withdraw(&s, "manager", &["--reason", "x"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["code"], json!("invalid_decision"));
    assert!(
        j["error"]["message"]
            .as_str()
            .unwrap()
            .contains("is neither"),
        "{j}"
    );
}

#[test]
fn withdraw_of_a_closed_question_exits_4_naming_the_entry_in_effect() {
    let s = Standin::new();
    raised(&s);
    s.write(
        "fail",
        "decisions answer|invalid_decision|decision 000000000002 in 'w2' is already closed (answered): entry in effect manager:000000000003, so it isn't withdrawn\n",
    );
    let out = withdraw(&s, "w2", &["--reason", "x"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert!(
        j["error"]["message"]
            .as_str()
            .unwrap()
            .contains("entry in effect manager:000000000003"),
        "{j}"
    );
}

#[test]
fn withdraw_of_an_identity_that_does_not_exist_exits_4_with_decision_not_found() {
    let s = Standin::new();
    let out = withdraw(&s, "w2", &["--reason", "x"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    assert_eq!(
        json(&out.stdout)["error"]["code"],
        json!("decision_not_found")
    );
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}

#[test]
fn withdraw_of_a_malformed_identity_is_a_usage_error() {
    let s = Standin::new();
    s.cmd(&["withdraw", "not-an-identity", "--in", "w2", "--reason", "x"])
        .assert()
        .code(2);
    assert!(s.log().is_empty());
}

#[test]
fn withdraw_with_koto_below_the_minimum_exits_3() {
    let s = Standin::new();
    raised(&s);
    s.write("version", "0.41.9");
    withdraw(&s, "w2", &["--reason", "x"]).assert().code(3);
    assert!(s.writes().is_empty());
}
