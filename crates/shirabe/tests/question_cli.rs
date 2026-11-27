//! `shirabe question pending` and `answer` against the koto stand-in: the
//! listing's merge and order, that it only reads, and what `answer` takes and
//! refuses. The answers koto verifies against a harness record run in
//! scripts/question-commands_test.sh against the real koto.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

fn element(identity: &str, session: &str, addressee: &str, relation: Option<&str>) -> Value {
    let (kind, name) = addressee.split_once(':').unwrap();
    let key = if kind == "person" { "handle" } else { "name" };
    let mut e = json!({
        "identity": identity, "session": session, "id": "000000000001",
        "question": "q", "text": "t", "need": "decision", "time": "2026-11-27T09:00:00Z",
        "recipient": {"kind": kind, key: name, "typed": true},
        "addressee": {"kind": kind, key: name, "typed": true},
        "addressees": []
    });
    if let Some(r) = relation {
        e["relation"] = json!(r);
    }
    e
}

#[test]
fn pending_with_neither_flag_lists_both_sets_once_with_one_open_call_each() {
    let s = Standin::new();
    let a = s.serve("worker", "000000000001", &stored_of(&good()), "");
    let mut v = good();
    v["standing"] = json!(true);
    let b = s.serve("manager", "000000000001", &stored_of(&v), "");
    // `a` was raised in worker and passed up to the owner: in both listings.
    s.write("open-person.json", json!({"v": 1, "questions": [element(&a, "worker", "person:owner", None)]}).to_string());
    s.write(
        "open-at.json",
        json!({"v": 1, "questions": [element(&a, "worker", "person:owner", Some("below")), element(&b, "manager", "session:manager", Some("both"))]}).to_string(),
    );
    let out = s.cmd(&["pending", "--in", "manager"]).assert().success().get_output().clone();
    let p = json(&out.stdout);
    let qs = p["questions"].as_array().unwrap();
    assert_eq!(qs.len(), 2);
    let qa = qs.iter().find(|q| q["identity"] == json!(a)).unwrap();
    assert_eq!(qa["relation"], json!("below"));
    assert_eq!(qa["addressee"], json!("person:owner"));
    assert_eq!(qa["for_owner"], json!(true));
    assert_eq!(qa["waiting"], json!(2));
    assert_eq!(qa["label"], json!("build cache store"));
    assert_eq!(qa["question"], json!("Which store should the build cache use?"));
    for k in ["session", "need", "age_seconds", "recipient", "standing", "unlinked", "depends_on"] {
        assert!(qa.get(k).is_some(), "{k}");
    }
    let qb = qs.iter().find(|q| q["identity"] == json!(b)).unwrap();
    assert_eq!(qb["standing"], json!(true));

    let log = s.log();
    assert_eq!(log.iter().filter(|l| l.starts_with("decisions open --person")).count(), 1);
    assert_eq!(log.iter().filter(|l| l.starts_with("decisions open --at")).count(), 1);
    assert!(s.writes().is_empty(), "pending wrote: {:?}", s.writes());
}

#[test]
fn pending_flags_a_question_addressed_to_another_person() {
    let s = Standin::new();
    s.write("history/sid-x_000000000001", r#"{"v":1,"raiser":{"name":"x","id":"sid-x"},"question":{"id":"000000000001","label":"other"},"open":true,"answer":null,"entries":[]}"#);
    s.write("open-at.json", json!({"v": 1, "questions": [element("sid-x/000000000001", "x", "person:alex", Some("raised"))]}).to_string());
    let out = s.cmd(&["pending", "--in", "x", "--at", "x"]).assert().success().get_output().clone();
    let q = &json(&out.stdout)["questions"][0];
    assert_eq!(q["other_person"], json!(true));
    assert_eq!(q["stored"], json!(false));
}

#[test]
fn pending_refuses_a_person_other_than_owner() {
    let s = Standin::new();
    s.cmd(&["pending", "--in", "x", "--person", "alex"]).assert().code(1);
}

#[test]
fn question_usage_errors_exit_2() {
    let s = Standin::new();
    s.cmd(&["raise"]).assert().code(2);
    s.cmd(&["pending"]).assert().code(2);
    s.cmd(&["frobnicate"]).assert().code(2);
    assert!(s.log().is_empty());
}

#[test]
fn answer_takes_no_answer_text() {
    let s = Standin::new();
    for flag in ["--text", "--answer"] {
        s.cmd(&["answer", "sid-solo/000000000001", "--in", "manager", flag, "B"]).assert().code(2);
    }
    s.cmd(&["answer", "sid-solo/000000000001", "--in", "manager", "--by", "person:alex"]).assert().code(2);
    s.cmd(&["answer", "sid-solo/000000000001", "--in", "manager"])
        .write_stdin("B\n")
        .assert()
        .code(2);
    assert!(s.writes().is_empty());
}

#[test]
fn answer_help_holds_no_option_for_text() {
    let s = Standin::new();
    let out = s.cmd(&["answer", "--help"]).assert().success().get_output().stdout.clone();
    let help = String::from_utf8(out).unwrap();
    let options: Vec<&str> = help
        .lines()
        .map(str::trim_start)
        .filter(|l| l.starts_with("--") || l.starts_with("-h"))
        .collect();
    let names: Vec<&str> = options.iter().map(|l| l.split_whitespace().next().unwrap().trim_end_matches(',')).collect();
    assert_eq!(names, vec!["--in", "--call", "--position", "-h"], "{help}");
}

#[test]
fn answer_in_an_unattended_session_records_nothing_and_calls_no_koto() {
    for (var, val) in [("KOTO_RUN_MODE", "unattended"), ("CLAUDE_CODE_SESSION_ATTENDED", "0")] {
        let s = Standin::new();
        s.cmd(&["answer", "sid-solo/000000000001", "--in", "solo"]).env(var, val).assert().code(1);
        assert!(s.log().is_empty(), "{var}");
    }
    // A run mode koto reads as unknown goes on to koto's checks.
    let s = Standin::new();
    s.cmd(&["answer", "sid-solo/000000000001", "--in", "solo"]).env("KOTO_RUN_MODE", "unknown").assert().code(4);
    assert!(!s.log().is_empty());
}

#[test]
fn answer_with_a_non_default_config_dir_says_the_answer_cannot_be_verified() {
    let s = Standin::new();
    s.serve("solo", "000000000001", &stored_of(&good()), "");
    let out = s
        .cmd(&["answer", "sid-solo/000000000001", "--in", "manager"])
        .env("CLAUDE_CONFIG_DIR", "/nonexistent")
        .env("CLAUDE_CODE_SESSION_ID", "harness-1")
        .assert()
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["check"], json!("record"));
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains("cannot be verified") && msg.contains("still open"));
    assert!(s.writes().is_empty());
}

#[test]
fn answer_with_no_matching_call_exits_4_check_call_with_the_relayed_claim_message() {
    let s = Standin::new();
    s.serve("solo", "000000000001", &stored_of(&good()), "");
    let out = s
        .cmd(&["answer", "sid-solo/000000000001", "--in", "manager"])
        .env("CLAUDE_CODE_SESSION_ID", "no-such-harness-session-for-test")
        .assert()
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["check"], json!("call"));
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains("koto decisions record") && msg.contains("closes no question") && msg.contains("grants nothing"));
    assert!(s.writes().is_empty());
}

#[test]
fn answer_passes_kotos_refusal_through_with_its_check() {
    let s = Standin::new();
    s.serve("solo", "000000000001", &stored_of(&good()), "");
    s.write(
        "fail",
        "decisions answer|prompt_unverified|the prompt pointer fails the 'question-text' check: the call's question differs\n",
    );
    let out = s
        .cmd(&["answer", "sid-solo/000000000001", "--in", "manager", "--call", "toolu_1", "--position", "1"])
        .env("CLAUDE_CODE_SESSION_ID", "harness-1")
        .assert()
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["code"], json!("prompt_unverified"));
    assert_eq!(j["error"]["check"], json!("question-text"));
    let call = s.log().into_iter().find(|l| l.starts_with("decisions answer")).unwrap();
    assert_eq!(call, "decisions answer solo 000000000001 --in manager --by person:owner --prompt harness-1/toolu_1/1");
}

#[test]
fn answer_that_does_not_read_verified_exits_5_with_kotos_reading() {
    let s = Standin::new();
    s.serve("solo", "000000000001", &stored_of(&good()), "");
    s.write("show-answer.json", r#"{"v":1,"id":"000000000009","session":"manager","reading":"a remote session's answer","decision":{"text":"Postgres"}}"#);
    let out = s
        .cmd(&["answer", "sid-solo/000000000001", "--in", "manager", "--call", "toolu_1", "--position", "2"])
        .env("CLAUDE_CODE_SESSION_ID", "harness-1")
        .assert()
        .code(5)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["reading"], json!("a remote session's answer"));
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains("remote session's answer") && msg.contains("no authority"));
    assert!(!msg.contains("owner's answer"));
}

#[test]
fn a_verified_answer_prints_kotos_reading() {
    let s = Standin::new();
    s.serve("solo", "000000000001", &stored_of(&good()), "");
    s.write("show-answer.json", r#"{"v":1,"id":"000000000009","session":"manager","reading":"verified","decision":{"text":"Postgres"}}"#);
    let out = s
        .cmd(&["answer", "sid-solo/000000000001", "--in", "manager", "--call", "toolu_1", "--position", "1"])
        .env("CLAUDE_CODE_SESSION_ID", "harness-1")
        .assert()
        .success()
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["reading"], json!("verified"));
    assert_eq!(j["text"], json!("Postgres"));
}

#[test]
fn answer_to_an_identity_koto_does_not_hold_passes_decision_not_found() {
    let s = Standin::new();
    let out = s
        .cmd(&["answer", "sid-none/000000000001", "--in", "manager", "--call", "c", "--position", "1"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["error"]["code"], json!("decision_not_found"));
}
