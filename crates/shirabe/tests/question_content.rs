//! `shirabe question raise`: what is refused before anything is written, and
//! the stored form. Driven against the koto stand-in, whose call log shows
//! which koto commands ran.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

fn raise_value(s: &Standin, v: &Value, extra: &[&str]) -> assert_cmd::assert::Assert {
    let path = s.file("content.json", serde_json::to_vec(v).unwrap());
    let mut args = vec!["raise", "--in", "solo", "--content", path.as_str()];
    args.extend_from_slice(extra);
    s.cmd(&args).assert()
}

fn refused(v: Value, field: &str) {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let out = raise_value(&s, &v, &["--attempt", "000000000001"])
        .code(1)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(
        j["error"]["field"],
        json!(field),
        "{}",
        String::from_utf8_lossy(&out.stdout)
    );
    assert!(String::from_utf8_lossy(&out.stderr).contains(field));
    assert!(s.writes().is_empty(), "koto wrote: {:?}", s.writes());
}

fn without(key: &str) -> Value {
    let mut v = good();
    v.as_object_mut().unwrap().remove(key);
    v
}

fn with(key: &str, val: Value) -> Value {
    let mut v = good();
    v[key] = val;
    v
}

#[test]
fn raise_good_prints_identity_recipient_need_label_packet_bytes_and_header() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let out = s
        .cmd(&[
            "raise",
            "--in",
            "solo",
            "--content",
            fixture("good.json").to_str().unwrap(),
            "--attempt",
            "000000000001",
        ])
        .assert()
        .success()
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["identity"], json!("sid-solo/000000000003"));
    assert_eq!(j["recipient"], json!("person:owner"));
    assert_eq!(j["need"], json!("decision"));
    assert_eq!(j["label"], json!("build cache store"));
    assert_eq!(j["prompt_header"], json!(header("sid-solo/000000000003")));
    let stored = std::fs::read(s.data.join("content/sid-solo_000000000003")).unwrap();
    assert_eq!(j["packet"], json!(packet(&stored)));
    assert_eq!(j["bytes"], json!(stored.len()));
    let rec = s
        .log()
        .into_iter()
        .find(|l| l.starts_with("decisions record"))
        .unwrap();
    assert!(rec.contains("--kind escalate"));
    assert!(rec.contains("--basis solo:000000000001"));
    assert!(rec.contains(&format!("packet={}", packet(&stored))));
}

#[test]
fn refuses_each_missing_or_empty_required_part() {
    for key in [
        "context", "problem", "question", "ground", "label", "waiting",
    ] {
        refused(without(key), key);
    }
    for key in ["context", "problem", "question", "ground", "label"] {
        refused(with(key, json!("")), key);
        refused(with(key, json!("   ")), key);
    }
}

#[test]
fn accepts_an_empty_waiting_list() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    raise_value(
        &s,
        &with("waiting", json!([])),
        &["--attempt", "000000000001"],
    )
    .success();
}

#[test]
fn refuses_fewer_than_two_or_more_than_four_options() {
    let o = good()["options"].clone();
    refused(with("options", json!([o[0]])), "options");
    refused(with("options", json!([])), "options");
    let five =
        json!([o[0], o[1], o[2], {"label": "D", "reason": "d"}, {"label": "E", "reason": "e"}]);
    refused(with("options", five), "options");
}

#[test]
fn refuses_an_option_without_label_or_reason() {
    let mut v = good();
    v["options"][1].as_object_mut().unwrap().remove("label");
    refused(v, "options[1].label");
    let mut v = good();
    v["options"][2].as_object_mut().unwrap().remove("reason");
    refused(v, "options[2].reason");
}

#[test]
fn refuses_an_unknown_key() {
    refused(with("severity", json!("high")), "severity");
    let mut v = good();
    v["options"][0]["weight"] = json!(3);
    refused(v, "options[0].weight");
}

#[test]
fn refuses_a_file_that_is_not_json() {
    let s = Standin::new();
    let path = s.file("content.json", "context: not json\n");
    s.cmd(&[
        "raise",
        "--in",
        "solo",
        "--content",
        &path,
        "--attempt",
        "000000000001",
    ])
    .assert()
    .code(1);
    assert!(s.writes().is_empty());
}

/// Raise `v` and return the stored byte count.
fn stored_len(v: &Value) -> usize {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let out = raise_value(&s, v, &["--attempt", "000000000001"])
        .success()
        .get_output()
        .clone();
    json(&out.stdout)["bytes"].as_u64().unwrap() as usize
}

#[test]
fn stored_size_bound_accepts_16384_and_refuses_16385_bytes() {
    let base = stored_len(&with("ground", json!("x")));
    let exact = "x".repeat(1 + 16384 - base);
    assert_eq!(stored_len(&with("ground", json!(exact))), 16384);

    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let over = "x".repeat(2 + 16384 - base);
    let out = raise_value(
        &s,
        &with("ground", json!(over)),
        &["--attempt", "000000000001"],
    )
    .code(1)
    .get_output()
    .clone();
    assert!(String::from_utf8_lossy(&out.stderr).contains("16 KiB"));
    assert!(s.writes().is_empty(), "koto wrote: {:?}", s.writes());
}

#[test]
fn label_bound_accepts_128_and_refuses_129_bytes() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    raise_value(
        &s,
        &with("label", json!("l".repeat(128))),
        &["--attempt", "000000000001"],
    )
    .success();
    refused(with("label", json!("l".repeat(129))), "label");
}

#[test]
fn refuses_a_control_character_in_the_question_or_an_option_label() {
    refused(with("question", json!("Which store?\nOr not?")), "question");
    refused(with("context", json!("tab\there")), "context");
    let mut v = good();
    v["options"][0]["label"] = json!("SQ\u{7}Lite");
    refused(v, "options[0].label");
}

#[test]
fn refuses_what_exceeds_the_prompt_limits() {
    refused(with("context", json!("c".repeat(8 * 1024))), "question");
    let mut v = good();
    v["options"][1]["label"] = json!("l".repeat(65));
    refused(v, "options[1].label");
}

#[test]
fn refuses_each_recipient_but_session_anchor_and_owner() {
    for to in [
        "coord",
        "session:",
        "session:bad name",
        "robot:x",
        "person:someone-else",
    ] {
        let s = Standin::new();
        undecided_attempt(&s, "solo");
        let out = raise_value(&s, &good(), &["--attempt", "000000000001", "--to", to])
            .code(1)
            .get_output()
            .clone();
        assert_eq!(json(&out.stdout)["error"]["field"], json!("to"), "{to}");
        assert!(s.writes().is_empty());
    }
    for to in ["session:manager", "anchor:desk", "person:owner"] {
        let s = Standin::new();
        undecided_attempt(&s, "solo");
        let out = raise_value(&s, &good(), &["--attempt", "000000000001", "--to", to])
            .success()
            .get_output()
            .clone();
        assert_eq!(json(&out.stdout)["recipient"], json!(to));
    }
}

#[test]
fn default_recipient_follows_the_session_origin() {
    let cases = [
        (
            r#"{"session":"solo","origin":{"state":"dispatched","dispatcher":"manager","dispatcher_kind":"workflow"}}"#,
            "session:manager",
            false,
        ),
        (
            r#"{"session":"solo","origin":{"state":"dispatched","dispatcher":"desk","dispatcher_kind":"anchor"}}"#,
            "anchor:desk",
            false,
        ),
        (
            r#"{"session":"solo","origin":{"state":"none"}}"#,
            "person:owner",
            false,
        ),
        (
            r#"{"session":"solo","origin":{"state":"unrecorded"}}"#,
            "person:owner",
            true,
        ),
    ];
    for (origin, want, unlinked) in cases {
        let s = Standin::new();
        undecided_attempt(&s, "solo");
        s.write("origin/solo", origin);
        let out = raise_value(&s, &good(), &["--attempt", "000000000001"])
            .success()
            .get_output()
            .clone();
        let j = json(&out.stdout);
        assert_eq!(j["recipient"], json!(want));
        assert_eq!(j["unlinked"], json!(unlinked));
    }
}

#[test]
fn refuses_a_secret_shape_without_printing_it() {
    let token = format!("ghp_{}", "A1b2C3d4E5f6G7h8I9j0K1l2");
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let out = raise_value(
        &s,
        &with("ground", json!(format!("use {token}"))),
        &["--attempt", "000000000001"],
    )
    .code(1)
    .get_output()
    .clone();
    let all = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(!all.contains(&token));
    assert!(all.contains("secret"));
    assert!(s.writes().is_empty());
}

#[test]
fn refuses_a_dependency_that_does_not_exist() {
    refused(
        with("depends_on", json!("sid-other/000000000007")),
        "depends_on",
    );
}

#[test]
fn refuses_a_dependency_that_would_close_a_cycle() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let mut a = good();
    a["depends_on"] = json!("sid-b/000000000001");
    let mut b = good();
    b["depends_on"] = json!("sid-a/000000000001");
    // Stored forms written by hand in the order shirabe stores.
    let stored = |v: &Value| stored_bytes(v);
    s.serve("a", "000000000001", &stored(&a), "");
    s.serve("b", "000000000001", &stored(&b), "");
    let out = raise_value(
        &s,
        &with("depends_on", json!("sid-a/000000000001")),
        &["--attempt", "000000000001"],
    )
    .code(1)
    .get_output()
    .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["field"], json!("depends_on"));
    assert!(j["error"]["message"].as_str().unwrap().contains("cycle"));
    assert!(s.writes().is_empty());
}

/// The stored form of `v`, from a raise against a fresh stand-in.
fn stored_bytes(v: &Value) -> Vec<u8> {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let mut v = v.clone();
    let dep = v.as_object_mut().unwrap().remove("depends_on");
    let out = raise_value(&s, &v, &["--attempt", "000000000001"])
        .success()
        .get_output()
        .clone();
    let identity = json(&out.stdout)["identity"]
        .as_str()
        .unwrap()
        .replace('/', "_");
    let bytes = std::fs::read(s.data.join("content").join(identity)).unwrap();
    match dep {
        None => bytes,
        Some(d) => {
            // depends_on is the last key.
            let mut t = bytes[..bytes.len() - 1].to_vec();
            t.extend_from_slice(format!(",\"depends_on\":{d}}}").as_bytes());
            t
        }
    }
}

#[test]
fn a_decision_question_needs_an_undecided_attempt() {
    for attempt in [None, Some("000000000099"), Some("000000000002")] {
        let s = Standin::new();
        undecided_attempt(&s, "solo");
        let mut extra = vec![];
        if let Some(a) = attempt {
            extra = vec!["--attempt", a];
        }
        let out = raise_value(&s, &good(), &extra)
            .code(1)
            .get_output()
            .clone();
        assert_eq!(
            json(&out.stdout)["error"]["field"],
            json!("attempt"),
            "{attempt:?}"
        );
        assert!(s.writes().is_empty());
    }
}

fn need() -> Value {
    let mut v = good();
    let o = v.as_object_mut().unwrap();
    o.remove("options");
    o.insert("need".into(), json!("credential"));
    o.insert(
        "needed".into(),
        json!("A deploy token for the staging registry."),
    );
    v
}

#[test]
fn a_need_takes_no_attempt_goes_to_the_owner_and_stores_its_state() {
    let s = Standin::new();
    s.write("origin/solo", r#"{"session":"solo","origin":{"state":"dispatched","dispatcher":"manager","dispatcher_kind":"workflow"}}"#);
    let out = raise_value(&s, &need(), &["--state", "implement:1"])
        .success()
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["recipient"], json!("person:owner"));
    assert_eq!(j["need"], json!("credential"));
    assert_eq!(j["state"], json!("implement:1"));
    let rec = s
        .log()
        .into_iter()
        .find(|l| l.starts_with("decisions record"))
        .unwrap();
    assert!(rec.contains("state=implement:1"));
    assert!(rec.contains("need=credential"));

    let s = Standin::new();
    raise_value(&s, &need(), &["--to", "session:manager"]).code(1);
    let mut both = need();
    both["options"] = good()["options"].clone();
    refused(both, "needed");
}

#[test]
fn refuses_a_malformed_state() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    raise_value(
        &s,
        &good(),
        &["--attempt", "000000000001", "--state", "implement"],
    )
    .code(1);
    raise_value(
        &s,
        &good(),
        &["--attempt", "000000000001", "--state", "implement:0"],
    )
    .code(1);
    assert!(s.writes().is_empty());
}

#[test]
fn standing_mark_refuses_what_would_need_shortening() {
    let long = "r".repeat(1100);
    let mut v = good();
    v["options"][1]["reason"] = json!(long);
    // Unmarked, the long reason is accepted (render shortens it).
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    raise_value(&s, &v, &["--attempt", "000000000001"]).success();
    // Marked on the question, or on that option, it is refused naming the mark.
    let mut q = v.clone();
    q["standing"] = json!(true);
    refused(q, "standing");
    let mut o = v.clone();
    o["options"][1]["standing"] = json!(true);
    refused(o, "options[1].standing");
}

#[test]
fn twenty_open_questions_carry_kotos_refusal_and_store_nothing() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    s.write(
        "fail",
        "decisions record|invalid_decision|a twenty-first open question waiting on a person: the limit of twenty is reached\n",
    );
    let out = raise_value(&s, &good(), &["--attempt", "000000000001"])
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["code"], json!("invalid_decision"));
    assert!(j["error"]["message"].as_str().unwrap().contains("twenty"));
    assert!(!s
        .log()
        .iter()
        .any(|l| l.starts_with("decisions content write")));
}

#[test]
fn reordered_and_reindented_input_stores_the_same_bytes() {
    let a = stored_bytes(&good());
    let text = std::fs::read_to_string(fixture("good.json")).unwrap();
    let v: Value = serde_json::from_str(&text).unwrap();
    // Reverse the key order and indent differently.
    let mut keys: Vec<_> = v.as_object().unwrap().iter().collect();
    keys.reverse();
    let mut out = String::from("{\n");
    for (i, (k, val)) in keys.iter().enumerate() {
        if i > 0 {
            out.push_str(",\n");
        }
        out.push_str(&format!(
            "        {}:   {}",
            json!(k),
            serde_json::to_string_pretty(val).unwrap()
        ));
    }
    out.push_str("\n}\n");
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    let path = s.file("reordered.json", out);
    let o = s
        .cmd(&[
            "raise",
            "--in",
            "solo",
            "--content",
            &path,
            "--attempt",
            "000000000001",
        ])
        .assert()
        .success()
        .get_output()
        .clone();
    let j = json(&o.stdout);
    let b = std::fs::read(
        s.data
            .join("content")
            .join(j["identity"].as_str().unwrap().replace('/', "_")),
    )
    .unwrap();
    assert_eq!(a, b);
    assert_eq!(j["packet"], json!(packet(&a)));
}

#[test]
fn stored_form_has_the_keys_in_order_and_no_insignificant_whitespace() {
    let bytes = stored_bytes(&good());
    let text = String::from_utf8(bytes.clone()).unwrap();
    // Outside string literals there is no whitespace at all.
    let structure = regex::Regex::new(r#""(?:[^"\\]|\\.)*""#)
        .unwrap()
        .replace_all(&text, "\"\"");
    assert!(!structure.contains(char::is_whitespace), "{structure}");
    let order = [
        "\"context\":",
        "\"problem\":",
        "\"ask\":",
        "\"question\":",
        "\"options\":",
        "\"ground\":",
        "\"waiting\":",
        "\"label\":",
    ];
    let mut at = 0;
    for k in order {
        let i = text[at..]
            .find(k)
            .unwrap_or_else(|| panic!("{k} out of order in {text}"));
        at += i + k.len();
    }
}

/// A change to any of the golden files is a format change: it breaks the
/// restore of every question already stored.
#[test]
fn golden_input_stores_the_golden_bytes_and_hash() {
    let bytes = stored_bytes(
        &serde_json::from_slice(&std::fs::read(fixture("golden-input.json")).unwrap()).unwrap(),
    );
    assert_eq!(bytes, std::fs::read(fixture("golden-stored.json")).unwrap());
    assert_eq!(
        packet(&bytes),
        std::fs::read_to_string(fixture("golden-packet.txt"))
            .unwrap()
            .trim()
    );
}

#[test]
fn a_failed_content_write_withdraws_the_escalate() {
    let s = Standin::new();
    undecided_attempt(&s, "solo");
    s.write("fail", "decisions content write\n");
    let out = raise_value(&s, &good(), &["--attempt", "000000000001"])
        .code(4)
        .get_output()
        .clone();
    let j = json(&out.stdout);
    assert_eq!(j["error"]["withdrawn"], json!(true));
    let w = s
        .log()
        .into_iter()
        .find(|l| l.contains("--outcome withdrawn"))
        .expect("a withdrawal");
    assert!(w.starts_with("decisions answer solo 000000000003 --in solo"));
    assert!(w.contains("content write failed"));
}

#[test]
fn each_subcommand_refuses_a_koto_below_the_minimum() {
    let cases: [&[&str]; 4] = [
        &["raise", "--in", "solo", "--content", "x.json"],
        &["pending", "--in", "manager"],
        &["render", "sid-solo/000000000001"],
        &["answer", "sid-solo/000000000001", "--in", "manager"],
    ];
    for args in cases {
        let s = Standin::new();
        s.write("version", "0.41.0");
        let out = s.cmd(args).assert().code(3).get_output().clone();
        let err = String::from_utf8_lossy(&out.stderr);
        assert!(
            err.contains("0.41.0") && err.contains("0.42.0"),
            "{args:?}: {err}"
        );
        assert_eq!(s.log(), vec!["version".to_string()], "{args:?}");
    }
}

#[test]
fn each_subcommand_names_koto_missing() {
    let cases: [&[&str]; 4] = [
        &["raise", "--in", "solo", "--content", "x.json"],
        &["pending", "--in", "manager"],
        &["render", "sid-solo/000000000001"],
        &["answer", "sid-solo/000000000001", "--in", "manager"],
    ];
    for args in cases {
        let s = Standin::new();
        let out = s
            .cmd_without_koto(args)
            .assert()
            .code(3)
            .get_output()
            .clone();
        assert!(
            String::from_utf8_lossy(&out.stderr).contains("koto is missing"),
            "{args:?}"
        );
    }
}
