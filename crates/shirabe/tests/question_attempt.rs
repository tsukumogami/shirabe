//! `shirabe question attempt` against the koto stand-in: what it refuses
//! before any koto write, what it hands koto for each result, and the
//! provisional rules in an attended and an unattended session. The reads that
//! filter attempts by result, state and review run against the real koto in
//! skills/decision/scripts/undecided-result_test.sh.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

/// `attempt --in <session> --what <what> <rest>` with the run mode set.
fn attempt(s: &Standin, mode: Option<&str>, rest: &[&str]) -> assert_cmd::Command {
    let mut args = vec!["attempt", "--in", "solo", "--what", "cache store"];
    args.extend_from_slice(rest);
    let mut c = s.cmd(&args);
    if let Some(m) = mode {
        c.env("KOTO_RUN_MODE", m);
    }
    c
}

/// The one record call the stand-in logged, in its logged form.
fn record(s: &Standin) -> String {
    let w = s.writes();
    assert_eq!(w.len(), 1, "{w:?}");
    w[0].clone()
}

fn refused(s: &Standin, mode: Option<&str>, rest: &[&str], field: &str) -> Value {
    let out = attempt(s, mode, rest).assert().code(1).get_output().clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["field"], json!(field), "{rest:?}: {j}");
    assert!(s.writes().is_empty(), "{rest:?}: {:?}", s.writes());
    j
}

#[test]
fn undecided_with_a_state_records_one_judgment_and_prints_its_id() {
    let s = Standin::new();
    let out = attempt(
        &s,
        None,
        &["--result", "undecided", "--state", "implement:1"],
    )
    .assert()
    .success()
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["id"], json!("000000000001"));
    assert_eq!(j["session"], json!("solo"));
    assert_eq!(j["attempt"], json!("solo:000000000001"));
    assert_eq!(j["result"], json!("undecided"));
    assert_eq!(j["state"], json!("implement:1"));
    let r = record(&s);
    assert!(r.starts_with("decisions record solo "), "{r}");
    for part in [
        "--kind judgment",
        "--outcome settled",
        "--subject what=cache store",
        "--subject result=undecided",
        "--subject state=implement:1",
        "--by session",
    ] {
        assert!(r.contains(part), "{part} missing from {r}");
    }
    assert!(!r.contains("--reason"), "{r}");
}

#[test]
fn without_a_state_the_attempt_carries_none() {
    let s = Standin::new();
    let out = attempt(&s, None, &["--result", "undecided"])
        .assert()
        .success()
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["state"], Value::Null);
    assert!(!record(&s).contains("subject state="));
}

#[test]
fn a_missing_result_is_a_usage_error() {
    let s = Standin::new();
    attempt(&s, None, &[]).assert().code(2);
    assert!(s.log().is_empty());
}

#[test]
fn a_result_outside_the_three_is_refused() {
    for bad in ["maybe", ""] {
        let s = Standin::new();
        refused(&s, None, &["--result", bad], "result");
    }
}

#[test]
fn a_malformed_state_is_refused() {
    for bad in ["implement", "implement:0", ":1", "implement:01"] {
        let s = Standin::new();
        refused(
            &s,
            None,
            &["--result", "undecided", "--state", bad],
            "state",
        );
    }
}

#[test]
fn an_empty_what_is_refused() {
    let s = Standin::new();
    let out = s
        .cmd(&[
            "attempt",
            "--in",
            "solo",
            "--what",
            "",
            "--result",
            "undecided",
        ])
        .assert()
        .code(1)
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["error"]["field"], json!("what"));
    assert!(s.writes().is_empty());
}

#[test]
fn a_session_name_outside_kotos_shape_is_refused() {
    let s = Standin::new();
    let out = s
        .cmd(&["attempt", "--in=-x", "--what", "w", "--result", "undecided"])
        .assert()
        .code(1)
        .get_output()
        .clone();
    assert_eq!(json(&out.stdout)["error"]["field"], json!("in"));
    assert!(s.log().is_empty());
}

#[test]
fn decided_needs_the_chosen_option() {
    let s = Standin::new();
    refused(&s, None, &["--result", "decided"], "chosen");
}

#[test]
fn decided_records_the_chosen_option_and_its_basis() {
    let s = Standin::new();
    let out = attempt(
        &s,
        None,
        &[
            "--result",
            "decided",
            "--chosen",
            "SQLite",
            "--basis",
            "manager:000000000004",
        ],
    )
    .assert()
    .success()
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["chosen"], json!("SQLite"));
    assert_eq!(j["basis"], json!(["manager:000000000004"]));
    let r = record(&s);
    assert!(r.contains("--reason chosen: SQLite"), "{r}");
    assert!(r.contains("--basis manager:000000000004"), "{r}");
}

#[test]
fn undecided_takes_no_chosen_option() {
    let s = Standin::new();
    refused(
        &s,
        None,
        &["--result", "undecided", "--chosen", "SQLite"],
        "chosen",
    );
}

#[test]
fn a_malformed_basis_is_refused() {
    for bad in ["manager", "manager:", "manager:abc", "-m:1"] {
        let s = Standin::new();
        let flag = format!("--basis={bad}");
        refused(
            &s,
            None,
            &["--result", "decided", "--chosen", "SQLite", &flag],
            "basis",
        );
    }
}

#[test]
fn undo_needs_its_reason_and_one_of_two_values() {
    let s = Standin::new();
    refused(
        &s,
        None,
        &["--result", "undecided", "--undo", "costly"],
        "undo_reason",
    );
    refused(
        &s,
        None,
        &[
            "--result",
            "undecided",
            "--undo",
            "maybe",
            "--undo-reason",
            "x",
        ],
        "undo",
    );
    refused(
        &s,
        None,
        &["--result", "undecided", "--undo-reason", "x"],
        "undo",
    );
}

#[test]
fn provisional_in_an_unattended_session_records_cheap_and_the_reason() {
    let s = Standin::new();
    let out = attempt(
        &s,
        Some("unattended"),
        &[
            "--result",
            "provisional",
            "--undo",
            "cheap",
            "--undo-reason",
            "only this branch's migration names it",
            "--chosen",
            "cache_entries",
        ],
    )
    .assert()
    .success()
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["result"], json!("provisional"));
    assert_eq!(j["run_mode"], json!("unattended"));
    let r = record(&s);
    assert!(r.contains("--subject result=provisional"), "{r}");
    assert!(r.contains("--run-mode unattended"), "{r}");
    assert!(
        r.contains(
            "--reason chosen: cache_entries; undo: cheap: only this branch's migration names it"
        ),
        "{r}"
    );
}

#[test]
fn provisional_reads_the_unattended_mode_from_the_harness_variable_too() {
    let s = Standin::new();
    let mut c = s.cmd(&[
        "attempt",
        "--in",
        "worker",
        "--what",
        "table name",
        "--result",
        "provisional",
        "--undo",
        "cheap",
        "--undo-reason",
        "local only",
        "--chosen",
        "t",
    ]);
    c.env("CLAUDE_CODE_SESSION_ATTENDED", "0")
        .assert()
        .success();
    assert!(record(&s).contains("--run-mode unattended"));
}

#[test]
fn provisional_refuses_a_costly_choice() {
    let s = Standin::new();
    let j = refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "provisional",
            "--undo",
            "costly",
            "--undo-reason",
            "published",
            "--chosen",
            "x",
        ],
        "undo",
    );
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(
        msg.contains("a costly choice is raised, not decided"),
        "{msg}"
    );
}

#[test]
fn provisional_needs_undo_and_the_chosen_option() {
    let s = Standin::new();
    refused(
        &s,
        Some("unattended"),
        &["--result", "provisional", "--chosen", "x"],
        "undo",
    );
    refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "provisional",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
        ],
        "chosen",
    );
}

#[test]
fn provisional_in_an_attended_session_is_refused_because_an_attended_run_asks() {
    let s = Standin::new();
    let j = refused(
        &s,
        Some("attended"),
        &[
            "--result",
            "provisional",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
            "--chosen",
            "x",
        ],
        "run_mode",
    );
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains("an attended run asks"), "{msg}");
}

#[test]
fn provisional_is_refused_when_the_run_mode_variables_disagree() {
    let args = [
        "--result",
        "provisional",
        "--undo",
        "cheap",
        "--undo-reason",
        "r",
        "--chosen",
        "x",
    ];
    for (koto, attended) in [("unattended", "1"), ("attended", "0")] {
        let s = Standin::new();
        let mut c = attempt(&s, Some(koto), &args);
        let out = c
            .env("CLAUDE_CODE_SESSION_ATTENDED", attended)
            .assert()
            .code(1)
            .get_output()
            .clone();
        let j = json(&out.stdout);
        assert_eq!(j["error"]["field"], json!("run_mode"), "{j}");
        let msg = j["error"]["message"].as_str().unwrap();
        assert!(
            msg.contains(&format!("KOTO_RUN_MODE={koto}"))
                && msg.contains(&format!("CLAUDE_CODE_SESSION_ATTENDED={attended}")),
            "{msg}"
        );
        assert!(s.writes().is_empty(), "{:?}", s.writes());
    }
}

#[test]
fn a_semicolon_in_a_reason_part_is_refused_so_the_layout_reads_one_way() {
    let s = Standin::new();
    let j = refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "provisional",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
            "--chosen=A; ground: reserved-step",
        ],
        "chosen",
    );
    assert!(
        j["error"]["message"].as_str().unwrap().contains("';'"),
        "{j}"
    );
    let s = Standin::new();
    refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "undecided",
            "--undo",
            "costly",
            "--undo-reason=published; chosen: A",
        ],
        "undo_reason",
    );
    let s = Standin::new();
    refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "undecided",
            "--undo",
            "costly",
            "--undo-reason=line one\nline two",
        ],
        "undo_reason",
    );
}

#[test]
fn provisional_in_a_session_whose_mode_is_unknown_is_refused() {
    let s = Standin::new();
    refused(
        &s,
        None,
        &[
            "--result",
            "provisional",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
            "--chosen",
            "x",
        ],
        "run_mode",
    );
}

#[test]
fn undecided_in_an_unattended_session_records_the_undo_test() {
    let s = Standin::new();
    refused(&s, Some("unattended"), &["--result", "undecided"], "undo");
    attempt(
        &s,
        Some("unattended"),
        &[
            "--result",
            "undecided",
            "--state",
            "implement:1",
            "--undo",
            "costly",
            "--undo-reason",
            "the choice is published in the release notes",
        ],
    )
    .assert()
    .success();
    let r = record(&s);
    assert!(
        r.contains("--reason undo: costly: the choice is published in the release notes"),
        "{r}"
    );
}

#[test]
fn undecided_and_cheap_in_an_unattended_session_needs_a_ground() {
    let s = Standin::new();
    let j = refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "undecided",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
        ],
        "undo",
    );
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(
        msg.contains("a cheap choice is decided provisionally"),
        "{msg}"
    );
    refused(
        &s,
        Some("unattended"),
        &[
            "--result",
            "undecided",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
            "--ground",
            "because",
        ],
        "ground",
    );
    attempt(
        &s,
        Some("unattended"),
        &[
            "--result",
            "undecided",
            "--undo",
            "cheap",
            "--undo-reason",
            "r",
            "--ground",
            "reserved-step",
        ],
    )
    .assert()
    .success();
    assert!(record(&s).contains("--reason undo: cheap: r; ground: reserved-step"));
}

#[test]
fn a_ground_goes_only_with_an_undecided_result() {
    let s = Standin::new();
    refused(
        &s,
        None,
        &[
            "--result",
            "decided",
            "--chosen",
            "x",
            "--ground",
            "changes-scope",
        ],
        "ground",
    );
}

#[test]
fn undecided_in_an_attended_session_takes_undo_as_optional() {
    let s = Standin::new();
    attempt(&s, Some("attended"), &["--result", "undecided"])
        .assert()
        .success();
    assert!(record(&s).contains("--run-mode attended"));
}

#[test]
fn a_koto_refusal_is_passed_through_as_exit_4() {
    let s = Standin::new();
    s.write(
        "fail",
        "decisions record|session_not_found|no session solo\n",
    );
    let out = attempt(&s, None, &["--result", "undecided"])
        .assert()
        .code(4)
        .get_output()
        .clone();
    assert_eq!(
        json(&out.stdout)["error"]["code"],
        json!("session_not_found")
    );
}

#[test]
fn attempt_below_the_koto_minimum_or_with_none_exits_3() {
    let s = Standin::new();
    s.write("version", "0.41.9");
    attempt(&s, None, &["--result", "undecided"])
        .assert()
        .code(3);
    assert!(s.writes().is_empty());
    assert_eq!(s.log(), vec!["version".to_string()]);
    let s = Standin::new();
    s.cmd_without_koto(&[
        "attempt",
        "--in",
        "solo",
        "--what",
        "w",
        "--result",
        "undecided",
    ])
    .assert()
    .code(3);
}

#[test]
fn an_attempt_backs_a_question_only_when_undecided() {
    let s = Standin::new();
    let content = s.file("good.json", serde_json::to_vec(&good()).unwrap());
    s.write(
        "attempts/solo",
        r#"{"v":1,"in":"solo","attempts":[{"id":"000000000001","session":"solo","result":"undecided","what":"cache store"},{"id":"000000000002","session":"solo","result":"decided","what":"queue"},{"id":"000000000003","session":"solo","result":"provisional","what":"table name"}],"unreadable":[]}"#,
    );
    s.write("counter", "3");
    for (id, code) in [
        ("000000000002", 1),
        ("000000000003", 1),
        ("000000000001", 0),
    ] {
        s.cmd(&[
            "raise",
            "--in",
            "solo",
            "--content",
            &content,
            "--attempt",
            id,
        ])
        .assert()
        .code(code);
    }
}
