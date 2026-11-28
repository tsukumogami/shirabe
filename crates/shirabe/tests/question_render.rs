//! `shirabe question render`: the question tool's input and the plain text,
//! byte for byte from the stored content, deterministic, batched in pending
//! order. Driven against the koto stand-in.

mod question_support;

use question_support::*;
use serde_json::{json, Value};

fn render(s: &Standin, args: &[&str]) -> Value {
    let mut a = vec!["render"];
    a.extend_from_slice(args);
    let out = s.cmd(&a).assert().success().get_output().clone();
    json(&out.stdout)
}

fn tricky() -> Value {
    let mut v = good();
    v["context"] = json!("The café build runs \"nightly\" — and <b>markup</b> stays text. ");
    v["question"] = json!("Which store should the cache use? ");
    v["options"][0]["label"] = json!("SQLite \"embedded\" ");
    v["options"][1]["label"] = json!("Postgres — shared");
    v
}

#[test]
fn header_question_and_labels_equal_the_stored_bytes() {
    let s = Standin::new();
    let stored = stored_of(&tricky());
    let identity = s.serve("solo", "000000000003", &stored, "");
    let r = render(&s, &[&identity]);
    let q = &r["prompts"][0]["questions"][0];
    let stored_v: Value = serde_json::from_slice(&stored).unwrap();
    assert_eq!(q["header"], json!(header(&identity)));
    assert_eq!(q["question"], stored_v["question"]);
    let labels: Vec<_> = q["options"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| o["label"].clone())
        .collect();
    let want: Vec<_> = stored_v["options"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| o["label"].clone())
        .collect();
    assert_eq!(labels, want);
    assert_eq!(q["multiSelect"], json!(false));
}

#[test]
fn the_question_is_context_problem_and_question_as_three_paragraphs() {
    let s = Standin::new();
    let v = good();
    let identity = s.serve("solo", "000000000003", &stored_of(&v), "");
    let r = render(&s, &[&identity]);
    let want = format!(
        "{}\n\n{}\n\n{}",
        v["context"].as_str().unwrap(),
        v["problem"].as_str().unwrap(),
        v["question"].as_str().unwrap()
    );
    assert_eq!(r["prompts"][0]["questions"][0]["question"], json!(want));
}

#[test]
fn descriptions_carry_the_reasons_with_the_recommendation_first() {
    let s = Standin::new();
    let v = good();
    let identity = s.serve("solo", "000000000003", &stored_of(&v), "");
    let r = render(&s, &[&identity]);
    let opts = r["prompts"][0]["questions"][0]["options"]
        .as_array()
        .unwrap()
        .clone();
    assert_eq!(
        opts[0]["description"],
        json!(format!(
            "Recommended. {}",
            v["options"][0]["reason"].as_str().unwrap()
        ))
    );
    assert_eq!(opts[1]["description"], v["options"][1]["reason"]);
    let text = r["prompts"][0]["text"].as_str().unwrap();
    for part in ["context", "problem", "question", "ground"] {
        assert!(text.contains(v[part].as_str().unwrap()), "{part}");
    }
    assert!(text.contains("Recommended: SQLite -- "));
    assert!(text.contains("Alternative: Postgres -- "));
    assert!(text.contains("Alternative: Redis -- "));
}

#[test]
fn a_long_reason_is_shortened_with_a_fixed_marker_and_control_characters_removed() {
    let s = Standin::new();
    let mut v = good();
    v["options"][1]["reason"] = json!(format!("line one\nline\ttwo {}", "r".repeat(1100)));
    let identity = s.serve("solo", "000000000003", &stored_of(&v), "");
    let r = render(&s, &[&identity]);
    let d = r["prompts"][0]["questions"][0]["options"][1]["description"]
        .as_str()
        .unwrap()
        .to_string();
    assert_eq!(d.len(), 1024);
    assert!(d.ends_with(" [shortened]"));
    assert!(d.starts_with("line onelinetwo "));
}

#[test]
fn two_renders_and_one_with_another_in_print_the_same_bytes() {
    let s = Standin::new();
    let identity = s.serve("solo", "000000000003", &stored_of(&tricky()), "");
    let a = s
        .cmd(&["render", &identity])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let b = s
        .cmd(&["render", &identity])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let c = s
        .cmd(&["render", &identity, "--in", "manager"])
        .current_dir(&s.root)
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    assert_eq!(a, b);
    assert_eq!(a, c);
    let text = String::from_utf8(a).unwrap();
    // The identity names the raiser; nothing names the session asking or
    // the directory it asked from.
    assert!(!text.contains("manager") && !text.contains(s.root.to_str().unwrap()));
}

#[test]
fn golden_render_is_byte_identical() {
    let s = Standin::new();
    let stored = std::fs::read(fixture("golden-stored.json")).unwrap();
    let identity = s.serve("solo", "000000000003", &stored, "");
    let out = s
        .cmd(&["render", &identity])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    assert_eq!(out, std::fs::read(fixture("golden-render.json")).unwrap());
}

/// Serve an open question for the owner with `waiting` work items raised at
/// `time`, in session `session`.
fn open_for_owner(
    s: &Standin,
    session: &str,
    waiting: usize,
    time: &str,
    depends: Option<&str>,
) -> (String, Value) {
    let mut v = good();
    v["label"] = json!(format!("q-{session}"));
    v["waiting"] = json!((0..waiting).map(|i| format!("w{i}")).collect::<Vec<_>>());
    let mut stored = stored_of(&v);
    if let Some(d) = depends {
        stored.pop();
        stored.extend_from_slice(format!(",\"depends_on\":\"{d}\"}}").as_bytes());
    }
    let identity = s.serve(session, "000000000001", &stored, "");
    let element = json!({
        "identity": identity, "session": session, "id": "000000000001",
        "question": "q", "text": "t", "need": "decision", "time": time,
        "recipient": {"kind": "person", "handle": "owner", "typed": true},
        "addressee": {"kind": "person", "handle": "owner", "typed": true},
        "addressees": []
    });
    (identity, element)
}

#[test]
fn render_person_owner_batches_four_then_two_in_pending_order_with_the_held_one_out() {
    let s = Standin::new();
    let qs = [
        ("e", 1, "2026-11-27T09:00:05Z"),
        ("b", 3, "2026-11-27T09:00:02Z"),
        ("a", 5, "2026-11-27T09:00:01Z"),
        ("d", 2, "2026-11-27T09:00:03Z"),
        ("c2", 3, "2026-11-27T09:00:00Z"),
        ("f", 0, "2026-11-27T09:00:00Z"),
        ("g", 0, "2026-11-27T09:00:00Z"),
    ];
    let mut elements = vec![];
    let mut ids = std::collections::BTreeMap::new();
    for (name, w, t) in qs {
        let (id, e) = open_for_owner(&s, name, w, t, None);
        ids.insert(name, id);
        elements.push(e);
    }
    // g and f tie on count and time; f sorts first by identity. Drop g: six.
    elements.pop();
    let (held_id, held) = open_for_owner(&s, "h", 9, "2026-11-27T08:00:00Z", Some(&ids["a"]));
    elements.push(held);
    s.write(
        "open-person.json",
        json!({"v": 1, "person": "owner", "questions": elements}).to_string(),
    );

    let r = render(&s, &["--person", "owner"]);
    let prompts = r["prompts"].as_array().unwrap();
    assert_eq!(prompts.len(), 2);
    let order: Vec<String> = prompts
        .iter()
        .flat_map(|p| p["identities"].as_array().unwrap().clone())
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    let want: Vec<String> = ["a", "c2", "b", "d", "e", "f"]
        .iter()
        .map(|n| ids[n].clone())
        .collect();
    assert_eq!(order, want);
    assert_eq!(prompts[0]["questions"].as_array().unwrap().len(), 4);
    assert_eq!(prompts[1]["questions"].as_array().unwrap().len(), 2);
    assert_eq!(r["held"], json!([held_id]));

    // Once `a` is answered, the held one is presented.
    let key = ids["a"].replace('/', "_");
    let h = std::fs::read_to_string(s.data.join("history").join(&key)).unwrap();
    s.write(
        &format!("history/{key}"),
        h.replace("\"open\":true", "\"open\":false"),
    );
    let mut v: Value =
        serde_json::from_str(&std::fs::read_to_string(s.data.join("open-person.json")).unwrap())
            .unwrap();
    v["questions"].as_array_mut().unwrap().remove(2);
    s.write("open-person.json", v.to_string());
    let r = render(&s, &["--person", "owner"]);
    assert_eq!(r["held"], json!([]));
    assert_eq!(r["prompts"][0]["identities"][0], json!(held_id));
}

#[test]
fn render_refuses_a_closed_question_naming_its_state() {
    for outcome in ["answered", "settled", "withdrawn"] {
        let s = Standin::new();
        let identity = s.serve("solo", "000000000003", &stored_of(&good()), "");
        let key = identity.replace('/', "_");
        let h = std::fs::read_to_string(s.data.join("history").join(&key)).unwrap();
        s.write(
            &format!("history/{key}"),
            h.replace(
                "\"open\":true,\"answer\":null",
                &format!("\"open\":false,\"answer\":{{\"outcome\":\"{outcome}\",\"id\":\"000000000009\"}}"),
            ),
        );
        let out = s
            .cmd(&["render", &identity])
            .assert()
            .code(8)
            .get_output()
            .clone();
        let j = json(&out.stdout);
        assert_eq!(j["error"]["code"], json!("question_closed"), "{outcome}");
        assert_eq!(j["error"]["state"], json!(outcome));
        assert!(j["error"]["message"].as_str().unwrap().contains(outcome));
        assert!(j.get("prompts").is_none());
    }
}

#[test]
fn render_person_owner_lists_what_it_cannot_present_under_incomplete() {
    let s = Standin::new();
    let (good_id, good_el) = open_for_owner(&s, "a", 1, "2026-11-27T09:00:00Z", None);
    // Raised with no packet: nothing stored to present.
    s.write(
        "history/sid-np_000000000001",
        r#"{"v":1,"raiser":{"name":"np","id":"sid-np"},"question":{"id":"000000000001"},"open":true,"answer":null,"entries":[]}"#,
    );
    // Its content is gone.
    let (gone_id, gone_el) = open_for_owner(&s, "gone", 1, "2026-11-27T09:00:01Z", None);
    std::fs::remove_file(s.data.join("content").join(gone_id.replace('/', "_"))).unwrap();
    let mut np = good_el.clone();
    np["identity"] = json!("sid-np/000000000001");
    np["session"] = json!("np");
    s.write(
        "open-person.json",
        json!({"v": 1, "questions": [good_el, np, gone_el]}).to_string(),
    );
    let r = render(&s, &["--person", "owner"]);
    assert_eq!(r["prompts"][0]["identities"], json!([good_id]));
    let inc: Vec<String> = r["incomplete"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["identity"].as_str().unwrap().to_string())
        .collect();
    assert!(inc.contains(&"sid-np/000000000001".to_string()), "{inc:?}");
    assert!(inc.contains(&gone_id), "{inc:?}");
}

#[test]
fn identities_with_the_same_time_order_by_identity_bytes() {
    let s = Standin::new();
    let (b, eb) = open_for_owner(&s, "zz", 1, "2026-11-27T09:00:00.500Z", None);
    let (a, ea) = open_for_owner(&s, "aa", 1, "2026-11-27T09:00:00.500Z", None);
    s.write(
        "open-person.json",
        json!({"v": 1, "questions": [eb, ea]}).to_string(),
    );
    let r = render(&s, &["--person", "owner"]);
    assert_eq!(r["prompts"][0]["identities"], json!([a, b]));
}

#[test]
fn a_standing_mark_opens_the_description_and_text_with_the_fixed_phrase() {
    let s = Standin::new();
    let mut v = good();
    v["options"][2]["standing"] = json!(true);
    let id1 = s.serve("solo", "000000000003", &stored_of(&v), "");
    let r = render(&s, &[&id1]);
    let o = r["prompts"][0]["questions"][0]["options"]
        .as_array()
        .unwrap()
        .clone();
    assert!(o[2]["description"]
        .as_str()
        .unwrap()
        .starts_with("This answer sets a standing rule. "));
    assert!(!o[1]["description"]
        .as_str()
        .unwrap()
        .starts_with("This answer"));
    assert!(r["prompts"][0]["text"]
        .as_str()
        .unwrap()
        .contains("This answer sets a standing rule. Alternative: Redis"));

    let mut q = good();
    q["standing"] = json!(true);
    let id2 = s.serve("other", "000000000003", &stored_of(&q), "");
    let r = render(&s, &[&id2]);
    for o in r["prompts"][0]["questions"][0]["options"]
        .as_array()
        .unwrap()
    {
        assert!(o["description"]
            .as_str()
            .unwrap()
            .starts_with("This answer sets a standing rule. "));
    }
}

#[test]
fn a_need_renders_as_a_request_with_no_options() {
    let s = Standin::new();
    let mut v = good();
    let o = v.as_object_mut().unwrap();
    o.remove("options");
    o.insert("need".into(), json!("reserved-step"));
    o.insert("needed".into(), json!("Run the production migration."));
    let identity = s.serve("solo", "000000000003", &stored_of(&v), "");
    let a = s
        .cmd(&["render", &identity])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let b = s
        .cmd(&["render", &identity, "--in", "x"])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    assert_eq!(a, b);
    let r = json(&a);
    assert_eq!(r["prompts"], json!([]));
    assert_eq!(r["requests"][0]["need"], json!("reserved-step"));
    assert!(r["requests"][0]["text"]
        .as_str()
        .unwrap()
        .contains("Run the production migration."));
}

#[test]
fn content_that_does_not_hash_to_its_packet_is_not_presented() {
    let s = Standin::new();
    let stored = stored_of(&good());
    let identity = s.serve("solo", "000000000003", &stored, "");
    let mut changed = stored.clone();
    let marker = b"MARKER-not-shown";
    let at = changed.windows(6).position(|w| w == b"SQLite").unwrap();
    changed.splice(at..at + 6, marker.iter().copied());
    s.write(&format!("content/{}", identity.replace('/', "_")), &changed);
    let out = s
        .cmd(&["render", &identity])
        .assert()
        .code(5)
        .get_output()
        .clone();
    let all = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(all.contains("content mismatch") && all.contains(&identity));
    assert!(!all.contains("MARKER") && !all.contains("build cache"));

    // pending lists it as incomplete.
    s.write(
        "open-person.json",
        json!({"v": 1, "questions": [{"identity": identity, "session": "solo", "id": "000000000003", "need": "decision", "time": "2026-11-27T09:00:00Z", "recipient": {"kind": "person", "handle": "owner"}, "addressee": {"kind": "person", "handle": "owner"}}]}).to_string(),
    );
    let out = s
        .cmd(&["pending", "--in", "solo", "--person", "owner"])
        .assert()
        .success()
        .get_output()
        .clone();
    let p = json(&out.stdout);
    assert_eq!(p["questions"], json!([]));
    assert_eq!(p["incomplete"][0]["identity"], json!(identity));
}

#[test]
fn a_raised_question_with_no_content_renders_nothing_and_pending_names_the_withdrawal() {
    let s = Standin::new();
    let identity = s.serve("solo", "000000000003", &stored_of(&good()), "");
    std::fs::remove_file(s.data.join("content").join(identity.replace('/', "_"))).unwrap();
    let out = s
        .cmd(&["render", &identity])
        .assert()
        .code(5)
        .get_output()
        .clone();
    assert!(json(&out.stdout)["prompts"].is_null());
    s.write(
        "open-person.json",
        json!({"v": 1, "questions": [{"identity": identity, "session": "solo", "id": "000000000003", "need": "decision", "time": "2026-11-27T09:00:00Z", "recipient": {"kind": "person", "handle": "owner"}, "addressee": {"kind": "person", "handle": "owner"}}]}).to_string(),
    );
    let out = s
        .cmd(&["pending", "--in", "solo", "--person", "owner"])
        .assert()
        .success()
        .get_output()
        .clone();
    let p = json(&out.stdout);
    assert_eq!(p["questions"], json!([]));
    assert_eq!(
        p["incomplete"][0]["withdraw"],
        json!("koto decisions answer solo 000000000003 --in solo --outcome withdrawn --reason 'incomplete question' --by session")
    );
}

/// Four healthy questions for the owner, listed in `open-person.json`.
fn four_for_owner(s: &Standin) -> Vec<String> {
    let mut ids = Vec::new();
    let mut els = Vec::new();
    for (i, name) in ["a", "b", "c", "d"].iter().enumerate() {
        let (id, el) = open_for_owner(s, name, 1, &format!("2026-11-27T09:00:0{i}Z"), None);
        ids.push(id);
        els.push(el);
    }
    s.write(
        "open-person.json",
        json!({"v": 1, "questions": els}).to_string(),
    );
    ids
}

/// Run `args`, expecting `code`, and return the parsed output, its raw text
/// and how long the command took.
fn timed(s: &Standin, args: &[&str], code: i32) -> (Value, String, std::time::Duration) {
    let t = std::time::Instant::now();
    let out = s.cmd(args).assert().code(code).get_output().clone();
    let took = t.elapsed();
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    (serde_json::from_str(&text).unwrap(), text, took)
}

fn assert_stopped_on(j: &Value, text: &str, command: &str) {
    assert_eq!(j["error"]["code"], json!("koto_timeout"), "{text}");
    let msg = j["error"]["message"].as_str().unwrap();
    assert!(msg.contains(command), "{msg}");
    assert!(j.get("incomplete").is_none(), "{text}");
    assert!(
        !text.contains("withdrawn"),
        "a withdraw command was printed: {text}"
    );
}

#[test]
fn a_content_read_that_hangs_stops_the_command_and_lists_nothing_incomplete() {
    let s = Standin::new();
    let ids = four_for_owner(&s);
    s.write("sleep", "decisions content read\n");
    // One bound, not one per question: four questions at 10 seconds each
    // would take 40.
    let bound = std::time::Duration::from_secs(18);

    let (j, text, took) = timed(&s, &["render", "--person", "owner"], 6);
    assert_stopped_on(&j, &text, "koto decisions content read");
    assert!(took < bound, "render --person owner took {took:?}");

    let (j, text, took) = timed(&s, &["pending", "--in", "manager", "--person", "owner"], 6);
    assert_stopped_on(&j, &text, "koto decisions content read");
    assert!(took < bound, "pending took {took:?}");

    let (j, text, took) = timed(&s, &["render", &ids[0]], 6);
    assert_stopped_on(&j, &text, "koto decisions content read");
    assert!(took < bound, "render <identity> took {took:?}");
    assert!(s.writes().is_empty());
}

#[test]
fn a_content_read_koto_fails_is_its_failure_not_a_missing_question() {
    let s = Standin::new();
    four_for_owner(&s);
    s.write(
        "fail",
        "decisions content read|store_locked|the store is locked by another process\n",
    );
    let (j, text, _) = timed(&s, &["render", "--person", "owner"], 4);
    assert_eq!(j["error"]["code"], json!("store_locked"), "{text}");
    assert!(j.get("incomplete").is_none(), "{text}");
    assert!(!text.contains("withdrawn"), "{text}");
}

#[test]
fn a_session_origin_that_hangs_stops_pending() {
    let s = Standin::new();
    four_for_owner(&s);
    s.write("sleep", "session origin\n");
    let (j, text, took) = timed(&s, &["pending", "--in", "manager", "--person", "owner"], 6);
    assert_stopped_on(&j, &text, "koto session origin");
    assert!(!text.contains("\"unlinked\""), "{text}");
    assert!(
        took < std::time::Duration::from_secs(18),
        "pending took {took:?}"
    );
}

#[test]
fn a_dependency_read_that_hangs_stops_the_command() {
    let s = Standin::new();
    let (dep, _) = open_for_owner(&s, "first", 1, "2026-11-27T09:00:00Z", None);
    let (_, el) = open_for_owner(&s, "later", 1, "2026-11-27T09:00:01Z", Some(&dep));
    s.write(
        "open-person.json",
        json!({"v": 1, "questions": [el]}).to_string(),
    );
    s.write("sleep", format!("decisions history {dep}\n"));
    let (j, text, took) = timed(&s, &["pending", "--in", "manager", "--person", "owner"], 6);
    assert_stopped_on(&j, &text, "koto decisions history");
    assert!(!text.contains("\"held\""), "{text}");
    assert!(
        took < std::time::Duration::from_secs(18),
        "pending took {took:?}"
    );
}

#[test]
fn a_ruled_standing_question_names_each_options_rule_or_that_it_sets_none() {
    let s = Standin::new();
    let mut v = good();
    v["standing"] = json!(true);
    v["options"][0]["rule"] = json!("Use SQLite for the build cache.");
    let id = s.serve("solo", "000000000003", &stored_of(&v), "");
    let r = render(&s, &[&id]);
    let o = r["prompts"][0]["questions"][0]["options"]
        .as_array()
        .unwrap()
        .clone();
    let rule = "This answer sets the standing rule \"Use SQLite for the build cache.\". ";
    let first = o[0]["description"].as_str().unwrap();
    assert!(
        first.starts_with(&format!("{rule}Recommended. ")),
        "{first}"
    );
    for opt in &o[1..] {
        let d = opt["description"].as_str().unwrap();
        assert!(d.starts_with("This answer sets no standing rule. "), "{d}");
        assert!(!d.contains("sets a standing rule"), "{d}");
    }
    let text = r["prompts"][0]["text"].as_str().unwrap();
    let line = format!("{rule}Recommended: SQLite");
    assert!(text.contains(&line), "{text}");
    assert!(
        text.contains("This answer sets no standing rule. Alternative: Postgres"),
        "{text}"
    );
    // The labels are the stored labels: the rule never changes what koto
    // compares when the owner's answer is recorded.
    assert_eq!(o[0]["label"], json!("SQLite"));
}
