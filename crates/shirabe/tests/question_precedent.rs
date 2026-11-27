//! `shirabe question precedent` against the koto stand-in: what it hands koto,
//! what it prints for each answer in effect, the label filter, what it leaves
//! out, its refusals, and that it writes nothing. The chain walk itself is
//! koto's; skills/work-on/scripts/decide-first-routes_test.sh runs the command
//! against a real koto store.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

fn answer(
    identity: &str,
    label: &str,
    text: &str,
    session: &str,
    id: &str,
    reading: &str,
) -> Value {
    json!({
        "identity": identity, "label": label, "text": text, "session": session,
        "id": id, "time": "2026-11-20T10:00:00Z", "decider": {"kind": "person", "person": "owner"},
        "reading": reading, "cited": false, "below": false,
    })
}

fn serve(s: &Standin, rel: &str, answers: Vec<Value>) {
    let body = json!({"v": 1, "person": "owner", "chain": ["worker", "manager"], "label": null, "answers": answers});
    s.write(rel, body.to_string());
}

fn precedent(s: &Standin, rest: &[&str]) -> assert_cmd::Command {
    let mut args = vec!["precedent", "--in", "worker"];
    args.extend_from_slice(rest);
    s.cmd(&args)
}

#[test]
fn precedent_with_a_label_passes_it_to_koto_and_prints_each_answer_with_its_basis_form() {
    let s = Standin::new();
    serve(
        &s,
        "precedent/cache.json",
        vec![answer(
            "sid-manager/000000000004",
            "cache",
            "SQLite",
            "manager",
            "000000000007",
            "verified",
        )],
    );
    let out = precedent(&s, &["--label", "cache"])
        .assert()
        .success()
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["in"], json!("worker"));
    assert_eq!(j["label"], json!("cache"));
    assert_eq!(
        j["answers"],
        json!([{
            "identity": "sid-manager/000000000004", "label": "cache", "text": "SQLite",
            "session": "manager", "id": "000000000007", "basis": "manager:000000000007",
            "reading": "verified",
        }])
    );
    assert_eq!(
        s.log(),
        vec![
            "version".to_string(),
            "decisions precedent --person owner --chain worker --label cache".to_string()
        ]
    );
}

#[test]
fn precedent_without_a_label_lists_every_answer_and_sends_no_label() {
    let s = Standin::new();
    serve(
        &s,
        "precedent.json",
        vec![
            answer(
                "sid-manager/000000000009",
                "licence",
                "MIT",
                "manager",
                "000000000010",
                "verified",
            ),
            answer(
                "sid-manager/000000000004",
                "cache",
                "SQLite",
                "manager",
                "000000000007",
                "verified",
            ),
        ],
    );
    let out = precedent(&s, &[]).assert().success().get_output().clone();
    let j = json(&out.stdout);
    assert_eq!(j["label"], Value::Null);
    let ids: Vec<&str> = j["answers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["identity"].as_str().unwrap())
        .collect();
    assert_eq!(
        ids,
        vec!["sid-manager/000000000004", "sid-manager/000000000009"],
        "sorted by identity"
    );
    assert!(
        s.log().iter().all(|l| !l.contains("--label")),
        "{:?}",
        s.log()
    );
}

#[test]
fn precedent_prints_byte_identical_output_on_two_runs() {
    let s = Standin::new();
    serve(
        &s,
        "precedent.json",
        vec![
            answer(
                "sid-manager/000000000009",
                "licence",
                "MIT",
                "manager",
                "000000000010",
                "verified",
            ),
            answer(
                "sid-manager/000000000004",
                "cache",
                "SQLite",
                "manager",
                "000000000007",
                "verified",
            ),
        ],
    );
    let a = precedent(&s, &[])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let b = precedent(&s, &[])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    assert_eq!(a, b);
}

#[test]
fn precedent_leaves_out_an_answer_that_does_not_read_as_verified() {
    let s = Standin::new();
    serve(
        &s,
        "precedent.json",
        vec![
            answer(
                "sid-other/000000000002",
                "cache",
                "Redis",
                "other",
                "000000000003",
                "remote",
            ),
            answer(
                "sid-worker/000000000005",
                "cache",
                "SQLite",
                "worker",
                "000000000006",
                "noted",
            ),
        ],
    );
    let out = precedent(&s, &[]).assert().success().get_output().clone();
    assert_eq!(json(&out.stdout)["answers"], json!([]));
}

#[test]
fn precedent_with_no_answers_prints_an_empty_list() {
    let s = Standin::new();
    let out = precedent(&s, &["--label", "cache"])
        .assert()
        .success()
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["answers"], json!([]));
}

#[test]
fn precedent_refuses_an_empty_label_with_exit_1_before_koto() {
    let s = Standin::new();
    for l in ["", "  "] {
        let out = precedent(&s, &["--label", l])
            .assert()
            .code(1)
            .get_output()
            .clone();
        let j = json(&out.stdout);
        assert_eq!(j["error"]["field"], json!("label"), "{l:?}");
    }
    assert!(s.log().is_empty(), "{:?}", s.log());
}

#[test]
fn precedent_refuses_a_malformed_session_name_with_exit_1() {
    let s = Standin::new();
    let out = s
        .cmd(&["precedent", "--in=-x"])
        .assert()
        .code(1)
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["error"]["field"], json!("in"));
    assert!(s.log().is_empty());
}

#[test]
fn precedent_naming_no_session_exits_4_with_kotos_refusal() {
    let s = Standin::new();
    s.write(
        "fail",
        "decisions precedent|invalid_decision|no session or anchor named 'nosuch' in the local store\n",
    );
    let out = s
        .cmd(&["precedent", "--in", "nosuch"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["code"], json!("invalid_decision"));
    assert!(
        j["error"]["message"].as_str().unwrap().contains("nosuch"),
        "{j}"
    );
}

#[test]
fn precedent_with_koto_below_the_minimum_exits_3() {
    let s = Standin::new();
    s.write("version", "0.41.9");
    precedent(&s, &[]).assert().code(3);
    assert_eq!(s.log(), vec!["version".to_string()]);
}

#[test]
fn precedent_without_koto_exits_3() {
    let s = Standin::new();
    s.cmd_without_koto(&["precedent", "--in", "worker"])
        .assert()
        .code(3);
}

#[test]
fn precedent_writes_nothing() {
    let s = Standin::new();
    serve(
        &s,
        "precedent.json",
        vec![answer(
            "sid-manager/000000000004",
            "cache",
            "SQLite",
            "manager",
            "000000000007",
            "verified",
        )],
    );
    precedent(&s, &[]).assert().success();
    assert!(s.writes().is_empty(), "{:?}", s.writes());
}
