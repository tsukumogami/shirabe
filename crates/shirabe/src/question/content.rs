//! A question's content: what the raising session supplies, the checks
//! `raise` makes on it, and the one stored form koto hashes and keeps.
//!
//! Every field is the caller's. The command composes nothing beyond joining
//! the context, the problem and the question into the prompt's question text
//! with one blank line between them, and it fills in no missing part.
//!
//! The stored form is fixed: keys in the order below, compact JSON, no
//! insignificant whitespace. Restore compares bytes, so a change to the order,
//! a key's name or the separator is a format change that breaks every stored
//! question.

use regex::Regex;
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::sync::OnceLock;

/// The most bytes a question's stored content may hold (koto's own cap).
pub const MAX_STORED: usize = 16 * 1024;
/// The most bytes a question's subject label may hold (koto's own cap).
pub const MAX_LABEL: usize = 128;
/// The most bytes of the composed question text (context, problem and
/// question) the prompt is given. shirabe's bound and an estimate: the length
/// the question tool accepts has not been measured, and this moves to the
/// measured figure once it is. See references/decision-presentation.md.
pub const MAX_QUESTION_TEXT: usize = 8 * 1024;
/// The most bytes an option label may hold. shirabe's bound.
pub const MAX_OPTION_LABEL: usize = 64;
/// The most bytes an option's description may hold. shirabe's bound; a
/// longer reason is shortened at render, unless the question is standing.
pub const MAX_DESCRIPTION: usize = 1024;
/// The fewest and most options a decision question offers.
pub const MIN_OPTIONS: usize = 2;
pub const MAX_OPTIONS: usize = 4;

/// The separator between the context, the problem and the question in the
/// composed question text: one blank line.
pub const PARAGRAPH: &str = "\n\n";

/// The kinds a need may name. A decision question has no `need` key.
pub const NEED_KINDS: [&str; 2] = ["credential", "reserved-step"];

/// The keys a caller's content may hold.
const INPUT_KEYS: [&str; 11] = [
    "context",
    "problem",
    "question",
    "standing",
    "options",
    "need",
    "needed",
    "ground",
    "waiting",
    "label",
    "depends_on",
];

/// One option of a decision question. The first is the recommendation.
#[derive(Debug, Clone, PartialEq)]
pub struct Opt {
    pub label: String,
    pub reason: String,
    pub standing: bool,
}

/// What the question asks for: a choice among options, or a need.
#[derive(Debug, Clone, PartialEq)]
pub enum Body {
    Options(Vec<Opt>),
    Need { kind: String, needed: String },
}

/// A question's content, validated.
#[derive(Debug, Clone, PartialEq)]
pub struct Content {
    pub context: String,
    pub problem: String,
    /// The question itself, as the caller wrote it (stored as `ask`).
    pub ask: String,
    /// The question carries the standing mark as a whole.
    pub standing: bool,
    pub body: Body,
    pub ground: String,
    pub waiting: Vec<String>,
    pub label: String,
    pub depends_on: Option<String>,
}

/// A refusal of the content: the part that fails and why.
#[derive(Debug, Clone, PartialEq)]
pub struct Refusal {
    pub field: String,
    pub message: String,
}

fn refuse(field: &str, message: impl Into<String>) -> Refusal {
    Refusal {
        field: field.to_string(),
        message: message.into(),
    }
}

/// The phrase that opens the description and text of anything carrying the
/// standing mark.
pub const STANDING_PHRASE: &str = "This answer sets a standing rule. ";
/// The phrase that opens the first option's description.
pub const RECOMMENDED_PHRASE: &str = "Recommended. ";

/// The secret shapes, one ERE per line: the list the public-content check
/// reads (scripts/lib/secret-shapes.ere).
const SECRET_SHAPES: &str = include_str!("../../../../scripts/lib/secret-shapes.ere");

fn secret_patterns() -> &'static [Regex] {
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    PATTERNS.get_or_init(|| {
        SECRET_SHAPES
            .lines()
            .map(str::trim_end)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .map(|l| Regex::new(l).expect("secret-shapes.ere holds a pattern Rust can't compile"))
            .collect()
    })
}

/// The number of secret shapes the binary holds.
#[cfg(test)]
pub fn secret_shape_count() -> usize {
    secret_patterns().len()
}

fn identity_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^[0-9A-Za-z][0-9A-Za-z-]*/[0-9]+$").unwrap())
}

/// Whether `s` has the shape of a question identity,
/// `<raiser session id>/<decision id>`.
pub fn is_identity(s: &str) -> bool {
    identity_re().is_match(s)
}

fn has_control(s: &str) -> bool {
    s.chars().any(char::is_control)
}

fn text_field(obj: &Map<String, Value>, key: &str, path: &str) -> Result<String, Refusal> {
    match obj.get(key) {
        None => Err(refuse(path, format!("`{path}` is missing"))),
        Some(Value::String(s)) if s.trim().is_empty() => {
            Err(refuse(path, format!("`{path}` is empty")))
        }
        Some(Value::String(s)) => Ok(s.clone()),
        Some(_) => Err(refuse(path, format!("`{path}` must be a string"))),
    }
}

fn plain_text(obj: &Map<String, Value>, key: &str, path: &str) -> Result<String, Refusal> {
    let s = text_field(obj, key, path)?;
    if has_control(&s) {
        return Err(refuse(
            path,
            format!("`{path}` holds a control character (a line break, a tab or another); the prompt shows it as one paragraph"),
        ));
    }
    Ok(s)
}

fn standing_mark(obj: &Map<String, Value>, path: &str) -> Result<bool, Refusal> {
    match obj.get("standing") {
        None => Ok(false),
        Some(Value::Bool(true)) => Ok(true),
        Some(_) => Err(refuse(
            path,
            format!("`{path}` is the standing mark: give it as true, or leave it out"),
        )),
    }
}

/// Parse and validate a caller's content. Nothing is filled in: every
/// required part must be there.
pub fn parse_input(bytes: &[u8]) -> Result<Content, Refusal> {
    let value: Value = serde_json::from_slice(bytes)
        .map_err(|e| refuse("content", format!("the content is not JSON: {e}")))?;
    let obj = value
        .as_object()
        .ok_or_else(|| refuse("content", "the content must be one JSON object"))?;
    // The secret scan runs before anything that names a key or a value, so a
    // refusal never prints text the scan would flag.
    scan_secrets(&value)?;
    for key in obj.keys() {
        if !INPUT_KEYS.contains(&key.as_str()) {
            return Err(refuse(
                key,
                format!("`{key}` is not a key question content takes"),
            ));
        }
    }

    let context = plain_text(obj, "context", "context")?;
    let problem = plain_text(obj, "problem", "problem")?;
    let ask = plain_text(obj, "question", "question")?;
    let standing = standing_mark(obj, "standing")?;
    let ground = text_field(obj, "ground", "ground")?;
    let label = text_field(obj, "label", "label")?;
    if label.len() > MAX_LABEL {
        return Err(refuse(
            "label",
            format!(
                "`label` is {} bytes; the label bound is {MAX_LABEL} bytes",
                label.len()
            ),
        ));
    }
    if has_control(&label) {
        return Err(refuse("label", "`label` holds a control character"));
    }

    let waiting = match obj.get("waiting") {
        None => return Err(refuse("waiting", "`waiting` is missing (give [] for none)")),
        Some(Value::Array(items)) => {
            let mut out = Vec::with_capacity(items.len());
            for (i, item) in items.iter().enumerate() {
                match item {
                    Value::String(s) if !s.trim().is_empty() && !has_control(s) => {
                        out.push(s.clone())
                    }
                    _ => {
                        return Err(refuse(
                            "waiting",
                            format!("`waiting[{i}]` must be a work item identifier: a non-empty string with no control character"),
                        ))
                    }
                }
            }
            out
        }
        Some(_) => {
            return Err(refuse(
                "waiting",
                "`waiting` must be a list of work item identifiers",
            ))
        }
    };

    let depends_on = match obj.get("depends_on") {
        None => None,
        Some(Value::String(s)) if is_identity(s) => Some(s.clone()),
        Some(_) => {
            return Err(refuse(
                "depends_on",
                "`depends_on` must be a question identity, <raiser session id>/<decision id>",
            ))
        }
    };

    let has_options = obj.contains_key("options");
    let has_needed = obj.contains_key("needed") || obj.contains_key("need");
    let body = match (has_options, has_needed) {
        (true, true) => {
            return Err(refuse(
                "needed",
                "content holds both `options` and a need (`need`, `needed`): a question is one or the other",
            ))
        }
        (false, false) => {
            return Err(refuse(
                "options",
                "`options` is missing (a need gives `need` and `needed` instead)",
            ))
        }
        (true, false) => Body::Options(parse_options(obj.get("options").unwrap())?),
        (false, true) => {
            let kind = text_field(obj, "need", "need")?;
            if !NEED_KINDS.contains(&kind.as_str()) {
                return Err(refuse(
                    "need",
                    format!("`need` must be one of {}", NEED_KINDS.join(", ")),
                ));
            }
            if standing {
                return Err(refuse("standing", "a need takes no standing mark"));
            }
            Body::Need {
                kind,
                needed: text_field(obj, "needed", "needed")?,
            }
        }
    };

    let content = Content {
        context,
        problem,
        ask,
        standing,
        body,
        ground,
        waiting,
        label,
        depends_on,
    };
    check_prompt_limits(&content)?;
    let stored = content.stored();
    if stored.len() > MAX_STORED {
        return Err(refuse(
            "content",
            format!(
                "the stored content is {} bytes; the bound is 16 KiB ({MAX_STORED} bytes)",
                stored.len()
            ),
        ));
    }
    Ok(content)
}

fn parse_options(v: &Value) -> Result<Vec<Opt>, Refusal> {
    let items = v
        .as_array()
        .ok_or_else(|| refuse("options", "`options` must be a list"))?;
    if items.len() < MIN_OPTIONS {
        return Err(refuse(
            "options",
            format!(
                "`options` holds {}; a question needs the recommendation and at least one alternative ({MIN_OPTIONS} to {MAX_OPTIONS})",
                items.len()
            ),
        ));
    }
    if items.len() > MAX_OPTIONS {
        return Err(refuse(
            "options",
            format!(
                "`options` holds {}; the prompt shows at most {MAX_OPTIONS}",
                items.len()
            ),
        ));
    }
    let mut out = Vec::with_capacity(items.len());
    for (i, item) in items.iter().enumerate() {
        let path = format!("options[{i}]");
        let o = item
            .as_object()
            .ok_or_else(|| refuse(&path, format!("`{path}` must be an object")))?;
        for key in o.keys() {
            if !["label", "reason", "standing"].contains(&key.as_str()) {
                return Err(refuse(
                    &format!("{path}.{key}"),
                    format!("`{path}.{key}` is not a key an option takes"),
                ));
            }
        }
        let label = plain_text(o, "label", &format!("{path}.label"))?;
        let reason = text_field(o, "reason", &format!("{path}.reason"))?;
        let standing = standing_mark(o, &format!("{path}.standing"))?;
        out.push(Opt {
            label,
            reason,
            standing,
        });
    }
    for (i, a) in out.iter().enumerate() {
        if out[..i].iter().any(|b| b.label == a.label) {
            return Err(refuse(
                &format!("options[{i}].label"),
                format!("`options[{i}].label` repeats an earlier option's label"),
            ));
        }
    }
    Ok(out)
}

fn scan_secrets(v: &Value) -> Result<(), Refusal> {
    let mut found = false;
    walk_strings(v, &mut |s| {
        if !found && secret_patterns().iter().any(|re| re.is_match(s)) {
            found = true;
        }
    });
    if found {
        // The matched text is never printed.
        return Err(refuse(
            "content",
            "the content holds text shaped like a secret (a token, a key or a private key block); remove it",
        ));
    }
    Ok(())
}

fn walk_strings(v: &Value, f: &mut impl FnMut(&str)) {
    match v {
        Value::String(s) => f(s),
        Value::Array(items) => items.iter().for_each(|i| walk_strings(i, f)),
        Value::Object(o) => o.iter().for_each(|(k, i)| {
            f(k);
            walk_strings(i, f)
        }),
        _ => {}
    }
}

/// The prompt's limits, checked at raise so `render` never alters a field koto
/// compares, and a standing question never needs shortening.
fn check_prompt_limits(c: &Content) -> Result<(), Refusal> {
    let q = c.question_text();
    if q.len() > MAX_QUESTION_TEXT {
        return Err(refuse(
            "question",
            format!(
                "the composed question (context, problem and question) is {} bytes; the prompt's question text bound is {MAX_QUESTION_TEXT} bytes",
                q.len()
            ),
        ));
    }
    if let Body::Options(opts) = &c.body {
        for (i, o) in opts.iter().enumerate() {
            if o.label.len() > MAX_OPTION_LABEL {
                return Err(refuse(
                    &format!("options[{i}].label"),
                    format!(
                        "`options[{i}].label` is {} bytes; the prompt's label bound is {MAX_OPTION_LABEL} bytes",
                        o.label.len()
                    ),
                ));
            }
            let marked = c.standing || o.standing;
            if marked {
                let full = full_description(o, i == 0, marked);
                if full.len() > MAX_DESCRIPTION {
                    let mark = if c.standing {
                        "standing".to_string()
                    } else {
                        format!("options[{i}].standing")
                    };
                    return Err(refuse(
                        &mark,
                        format!(
                            "the standing mark (`{mark}`) needs `options[{i}].reason` shown unshortened, and its description would be {} bytes; the prompt's description bound is {MAX_DESCRIPTION} bytes",
                            full.len()
                        ),
                    ));
                }
            }
        }
    }
    Ok(())
}

/// Remove control characters from a display field.
pub fn display(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).collect()
}

/// An option's description before any shortening.
pub fn full_description(o: &Opt, first: bool, marked: bool) -> String {
    let mut d = String::new();
    if marked {
        d.push_str(STANDING_PHRASE);
    }
    if first {
        d.push_str(RECOMMENDED_PHRASE);
    }
    d.push_str(&display(&o.reason));
    d
}

impl Content {
    /// The prompt's question text: the context, the problem and the question
    /// as three paragraphs.
    pub fn question_text(&self) -> String {
        [self.context.as_str(), &self.problem, &self.ask].join(PARAGRAPH)
    }

    /// The `need` koto records: `decision` for a question with options.
    pub fn need(&self) -> &str {
        match &self.body {
            Body::Options(_) => "decision",
            Body::Need { kind, .. } => kind,
        }
    }

    /// Whether anything in the question carries the standing mark.
    pub fn any_standing(&self) -> bool {
        self.standing || matches!(&self.body, Body::Options(o) if o.iter().any(|o| o.standing))
    }

    /// The stored bytes: keys in the fixed order, compact JSON.
    pub fn stored(&self) -> Vec<u8> {
        fn s(v: &str) -> String {
            serde_json::to_string(v).expect("a string serializes")
        }
        let mut out = String::new();
        out.push('{');
        out.push_str(&format!("\"context\":{}", s(&self.context)));
        out.push_str(&format!(",\"problem\":{}", s(&self.problem)));
        out.push_str(&format!(",\"ask\":{}", s(&self.ask)));
        out.push_str(&format!(",\"question\":{}", s(&self.question_text())));
        if self.standing {
            out.push_str(",\"standing\":true");
        }
        match &self.body {
            Body::Options(opts) => {
                out.push_str(",\"options\":[");
                for (i, o) in opts.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    out.push_str(&format!(
                        "{{\"label\":{},\"reason\":{}",
                        s(&o.label),
                        s(&o.reason)
                    ));
                    if o.standing {
                        out.push_str(",\"standing\":true");
                    }
                    out.push('}');
                }
                out.push(']');
            }
            Body::Need { kind, needed } => {
                out.push_str(&format!(",\"need\":{},\"needed\":{}", s(kind), s(needed)));
            }
        }
        out.push_str(&format!(",\"ground\":{}", s(&self.ground)));
        out.push_str(",\"waiting\":[");
        out.push_str(
            &self
                .waiting
                .iter()
                .map(|w| s(w))
                .collect::<Vec<_>>()
                .join(","),
        );
        out.push(']');
        out.push_str(&format!(",\"label\":{}", s(&self.label)));
        if let Some(d) = &self.depends_on {
            out.push_str(&format!(",\"depends_on\":{}", s(d)));
        }
        out.push('}');
        out.into_bytes()
    }

    /// Read stored bytes back. The bytes must be exactly the stored form of
    /// what they hold, so a hand-edited copy reads as unusable.
    pub fn from_stored(bytes: &[u8]) -> Result<Content, Refusal> {
        let value: Value = serde_json::from_slice(bytes)
            .map_err(|e| refuse("content", format!("the stored content is not JSON: {e}")))?;
        let mut obj = value
            .as_object()
            .cloned()
            .ok_or_else(|| refuse("content", "the stored content is not an object"))?;
        let composed = match obj.remove("question") {
            Some(Value::String(q)) => q,
            _ => {
                return Err(refuse(
                    "question",
                    "the stored content has no question text",
                ))
            }
        };
        let ask = obj.remove("ask");
        if let Some(a) = ask {
            obj.insert("question".into(), a);
        }
        let input = serde_json::to_vec(&Value::Object(obj)).expect("an object serializes");
        let content = parse_input(&input)?;
        if content.question_text() != composed || content.stored() != bytes {
            return Err(refuse(
                "content",
                "the stored content is not in the stored form shirabe writes",
            ));
        }
        Ok(content)
    }
}

/// `sha256:<hex>` of the bytes, the form koto's `packet` subject takes.
pub fn packet(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut hex = String::with_capacity(71);
    hex.push_str("sha256:");
    for b in digest {
        hex.push_str(&format!("{b:02x}"));
    }
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    fn good() -> Value {
        serde_json::json!({
            "context": "The cache sits in front of the build store.",
            "problem": "Two stores fit and neither is clearly better.",
            "question": "Which store should the cache use?",
            "options": [
                {"label": "SQLite", "reason": "One file, no server."},
                {"label": "Postgres", "reason": "Already run for the API."}
            ],
            "ground": "The choice changes the deployment.",
            "waiting": ["issue-12"],
            "label": "cache store"
        })
    }

    #[test]
    fn secret_shapes_compile() {
        assert!(secret_shape_count() >= 6);
    }

    #[test]
    fn stored_form_round_trips() {
        let c = parse_input(good().to_string().as_bytes()).unwrap();
        let bytes = c.stored();
        assert_eq!(Content::from_stored(&bytes).unwrap(), c);
    }

    #[test]
    fn a_reordered_stored_copy_is_refused() {
        let c = parse_input(good().to_string().as_bytes()).unwrap();
        let v: Value = serde_json::from_slice(&c.stored()).unwrap();
        let pretty = serde_json::to_vec_pretty(&v).unwrap();
        assert!(Content::from_stored(&pretty).is_err());
    }
}
