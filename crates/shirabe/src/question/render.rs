//! Rendering stored questions into the question tool's input and a plain
//! text form.
//!
//! The output depends on the stored bytes and koto's `prompt_header` only: no
//! time, age, path or session name, so any session renders the same bytes
//! after a restart or a compaction. The `question` text and the option labels
//! are the stored bytes unchanged, which is what koto compares when the
//! owner's answer is recorded; `raise` has already refused anything those
//! fields could not carry.

use serde_json::{json, Value};

use super::content::{
    display, full_description, standing_phrase, Body, Content, Opt, MAX_DESCRIPTION, PARAGRAPH,
    STANDING_PHRASE,
};

/// The most questions one prompt holds (the question tool's own bound).
pub const MAX_PER_PROMPT: usize = 4;
/// What ends a reason shortened to fit the prompt.
pub const SHORTENED: &str = " [shortened]";

/// A stored question ready to render.
pub struct Item {
    pub identity: String,
    pub header: String,
    pub content: Content,
}

/// An option's description: the standing phrase when marked (naming the rule
/// the option sets, or that it sets none, on a question whose options carry
/// rule texts, `ruled`), the recommendation phrase on the first, then the
/// reason, shortened at a fixed length with a fixed marker when it does not
/// fit. A marked option never reaches here too long: `raise` refused it.
pub fn description(o: &Opt, first: bool, marked: bool, ruled: bool) -> String {
    let full = full_description(o, first, marked, ruled);
    if full.len() <= MAX_DESCRIPTION {
        return full;
    }
    let mut cut = MAX_DESCRIPTION - SHORTENED.len();
    while !full.is_char_boundary(cut) {
        cut -= 1;
    }
    format!("{}{SHORTENED}", &full[..cut])
}

fn prompt_question(item: &Item, opts: &[Opt]) -> Value {
    let c = &item.content;
    let options: Vec<Value> = opts
        .iter()
        .enumerate()
        .map(|(i, o)| {
            json!({
                "label": o.label,
                "description": description(o, i == 0, c.standing || o.standing, c.ruled()),
            })
        })
        .collect();
    json!({
        "question": c.question_text(),
        "header": item.header,
        "multiSelect": false,
        "options": options,
    })
}

fn option_line(o: &Opt, first: bool, marked: bool, ruled: bool) -> String {
    let mut line = standing_phrase(o, marked, ruled);
    line.push_str(if first {
        "Recommended: "
    } else {
        "Alternative: "
    });
    line.push_str(&o.label);
    line.push_str(" -- ");
    line.push_str(&display(&o.reason));
    line
}

/// The plain text of one question or need: one paragraph per part.
pub fn text(item: &Item) -> String {
    let c = &item.content;
    let mut parts: Vec<String> = Vec::new();
    let mut head = format!("Question {}", item.header);
    if c.standing {
        head = format!("{STANDING_PHRASE}{head}");
    }
    parts.push(head);
    parts.push(c.context.clone());
    parts.push(c.problem.clone());
    parts.push(c.ask.clone());
    match &c.body {
        Body::Options(opts) => {
            for (i, o) in opts.iter().enumerate() {
                parts.push(option_line(o, i == 0, c.standing || o.standing, c.ruled()));
            }
        }
        Body::Need { kind, needed } => {
            parts.push(format!("Needed ({kind}): {}", display(needed)));
        }
    }
    parts.push(format!("Not settled here because: {}", display(&c.ground)));
    if !c.waiting.is_empty() {
        let w: Vec<String> = c.waiting.iter().map(|w| display(w)).collect();
        parts.push(format!("Waiting on it: {}", w.join(", ")));
    }
    parts.join(PARAGRAPH)
}

/// The whole render: prompts of at most four questions, in the order given,
/// needs as requests, and the identities held back.
pub fn render(items: &[Item], held: &[String]) -> Value {
    let mut prompts: Vec<Value> = Vec::new();
    let mut requests: Vec<Value> = Vec::new();
    let mut batch: Vec<&Item> = Vec::new();
    let flush = |batch: &mut Vec<&Item>, prompts: &mut Vec<Value>| {
        if batch.is_empty() {
            return;
        }
        let questions: Vec<Value> = batch
            .iter()
            .map(|i| match &i.content.body {
                Body::Options(o) => prompt_question(i, o),
                Body::Need { .. } => unreachable!("needs are never batched"),
            })
            .collect();
        let texts: Vec<String> = batch.iter().map(|i| text(i)).collect();
        prompts.push(json!({
            "questions": questions,
            "identities": batch.iter().map(|i| i.identity.clone()).collect::<Vec<_>>(),
            "text": texts.join("\n\n\n"),
        }));
        batch.clear();
    };
    for item in items {
        match &item.content.body {
            Body::Options(_) => {
                batch.push(item);
                if batch.len() == MAX_PER_PROMPT {
                    flush(&mut batch, &mut prompts);
                }
            }
            Body::Need { kind, needed } => requests.push(json!({
                "identity": item.identity,
                "header": item.header,
                "need": kind,
                "needed": display(needed),
                "text": text(item),
            })),
        }
    }
    flush(&mut batch, &mut prompts);
    json!({
        "v": 1,
        "prompts": prompts,
        "requests": requests,
        "held": held,
    })
}
