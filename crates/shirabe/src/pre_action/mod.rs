//! The pre-action evaluator: a Claude Code **PreToolUse** check on a Bash
//! command, run before the command, that denies a guarded action breaking a
//! rule it guards and fails closed on a guarded action it can't check
//! (DESIGN-pre-action-denies, PRD-pre-action-denies).
//!
//! Both entry points run it. `shirabe pr-body-hook`, the one niwa wires into
//! a host's settings, calls [`run_legacy`]: the PR-body rules only, with the
//! registry compiled into the binary. The plugin's own hook runs it with every
//! rule and the registry the plugin ships.
//!
//! The flow, for one hook call: read the input, tokenize the command
//! ([`tokenize`]), classify its segments ([`classify`]); for each guarded
//! `gh pr create|edit`, read the title and body ([`body`]) and run
//! `shirabe_validate::check_pr_body` / `check_pr_title`, the engine `shirabe
//! validate --pr-body` runs, mapping each finding to a registry id through
//! the entry whose `aliases` holds its PB code ([`registry`]); render the
//! deny ([`reason`]). A command with nothing guarded in it gets no decision
//! whatever else fails, the registry included, and starts no process.
//!
//! Security: the command, title and body are attacker-controlled. Nothing is
//! shell-evaluated, the deny is built with `serde_json`, nothing is written,
//! and a body file's lines never reach the reason. The input's
//! `transcript_path` and `session_id` are ignored, and nothing is logged.

pub mod body;
pub mod classify;
pub mod reason;
pub mod registry;
pub mod tokenize;

use std::io::Read;
use std::path::Path;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use shirabe_validate::{check_pr_body, check_pr_title, is_no_heading_finding, PrBodyFinding};

use classify::{classify, named_in_raw_input, named_in_text, Item, Named};
use reason::{Action, Broken, Case, FailClosed, PrAction};
pub use registry::RegistrySource;
use registry::{Registry, RegistryError};

/// The PR-body rules, checked on `gh pr create` and `gh pr edit`.
pub const PR_RULES: &[&str] = &[
    "pr-body/conventional-title",
    "pr-body/one-separator",
    "pr-body/no-ai-trailer",
    "pr-body/no-heading-in-part1",
    "pr-body/conformance",
];

/// The rule checked on `git push`.
pub const PUSH_RULES: &[&str] = &["commit/no-ai-trailer"];

/// Every rule the evaluator checks, in the order the plugin script's
/// `RULE_IDS` line lists them. The plugin's entry point compares its
/// `--rules` list with it; until that entry point exists only tests read it.
#[allow(dead_code)]
pub const RULES: &[&str] = &[
    "pr-body/conventional-title",
    "pr-body/one-separator",
    "pr-body/no-ai-trailer",
    "pr-body/no-heading-in-part1",
    "pr-body/conformance",
    "commit/no-ai-trailer",
];

/// The registry id for a finding with no PB code, or one no entry aliases.
const CONFORMANCE: &str = "pr-body/conformance";

/// The largest hook input that is tokenized (PRD R7 case 12).
pub const MAX_INPUT: usize = 4 * 1024 * 1024;

/// How long the whole evaluation may run before the entry point gives up on
/// it (PRD R7 case 8), inside Claude Code's 30-second hook timeout.
pub const DEADLINE: Duration = Duration::from_secs(25);

/// Which rules an entry point checks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RuleSet {
    /// The plugin hook's set; until that entry point exists only tests
    /// build it.
    #[allow(dead_code)]
    All,
    /// The legacy entry point: every fail-closed case attached to a `gh pr`
    /// segment, and the segment-less cases (malformed input, an unterminated
    /// quote, an oversize input) when the text names a `gh pr` action.
    PrBodyOnly,
}

impl RuleSet {
    fn keeps(self, a: Action) -> bool {
        match self {
            RuleSet::All => true,
            RuleSet::PrBodyOnly => matches!(a, Action::Pr(_)),
        }
    }
}

/// What an evaluation reads besides its input, so tests inject each.
pub struct Ctx<'a> {
    pub rules: RuleSet,
    pub registry: RegistrySource,
    /// Whether the host opted into the live offload canary (PRD R10). Asked
    /// only when there is a PB4 finding to drop, so the common path reads no
    /// file.
    pub canary_opted_in: &'a dyn Fn() -> bool,
}

/// Entry point for `shirabe pr-body-hook`, after its off switches. Always
/// exits 0: a block is a `deny` decision on stdout, never an exit code.
pub fn run_legacy() -> ExitCode {
    let input = read_stdin();
    let reason = decide(input, RuleSet::PrBodyOnly, DEADLINE, |input| {
        evaluate(
            input,
            &Ctx {
                rules: RuleSet::PrBodyOnly,
                registry: RegistrySource::Embedded,
                canary_opted_in: &canary_opted_in,
            },
        )
    });
    if let Some(reason) = reason {
        emit_deny(&reason);
    }
    ExitCode::SUCCESS
}

/// `SHIRABE_PRE_ACTION_HOOK=off` exactly turns both entry points off (PRD
/// R9); `OFF`, `off ` and `0` leave them on.
pub fn hook_off() -> bool {
    std::env::var_os("SHIRABE_PRE_ACTION_HOOK").is_some_and(|v| v == "off")
}

/// `PR_BODY_HOOK_DISABLE` with any non-empty value other than `0` or `false`
/// turns off the PR-body rules and the fail-closed cases of pull-request
/// commands (PRD R9).
pub fn pr_body_disabled() -> bool {
    match std::env::var("PR_BODY_HOOK_DISABLE") {
        Ok(v) => !v.is_empty() && v != "0" && v != "false",
        Err(_) => false,
    }
}

fn read_stdin() -> String {
    let mut bytes = Vec::new();
    let _ = std::io::stdin().read_to_end(&mut bytes);
    String::from_utf8_lossy(&bytes).into_owned()
}

/// Run `eval` on a worker thread and wait at most `deadline`. A worker that
/// panics or hasn't answered in time becomes the fail-closed deny when the
/// coarse test over the raw input names a guarded action `rules` keeps, and
/// no decision otherwise, so neither a crash nor a hang is the silent pass
/// niwa's `|| exit 0` would make it.
pub fn decide<F>(input: String, rules: RuleSet, deadline: Duration, eval: F) -> Option<String>
where
    F: FnOnce(&str) -> Option<String> + Send + 'static,
{
    let input: Arc<str> = input.into();
    let worker_input = Arc::clone(&input);
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(eval(&worker_input));
    });
    match rx.recv_timeout(deadline) {
        Ok(reason) => reason,
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            segment_less(named_in_raw_input(&input), rules, Case::Deadline)
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            segment_less(named_in_raw_input(&input), rules, Case::Crash)
        }
    }
}

/// A case that belongs to no segment: one paragraph per guarded action
/// `named` holds that `rules` keeps, or no decision when there is none.
fn segment_less(named: Named, rules: RuleSet, case: Case) -> Option<String> {
    let fails: Vec<FailClosed> = named
        .actions()
        .into_iter()
        .filter(|a| rules.keeps(*a))
        .map(|action| FailClosed {
            action,
            case: case.clone(),
        })
        .collect();
    if fails.is_empty() {
        None
    } else {
        Some(reason::render(None, &[], &fails))
    }
}

/// Evaluate one PreToolUse input: `Some(reason)` to deny, `None` for no
/// decision.
pub fn evaluate(input: &str, ctx: &Ctx) -> Option<String> {
    if input.len() > MAX_INPUT {
        return segment_less(named_in_raw_input(input), ctx.rules, Case::Oversize);
    }
    let Ok(v) = serde_json::from_str::<serde_json::Value>(input) else {
        return segment_less(named_in_raw_input(input), ctx.rules, Case::HookInput);
    };
    let Some(command) = v.pointer("/tool_input/command").and_then(|c| c.as_str()) else {
        return segment_less(named_in_raw_input(input), ctx.rules, Case::HookInput);
    };
    let cwd = v.get("cwd").and_then(|c| c.as_str()).map(Path::new);
    let Ok(tok) = tokenize::tokenize(command) else {
        return segment_less(named_in_text(command), ctx.rules, Case::Quote);
    };
    let classified = classify(&tok, cwd);

    let mut fails: Vec<FailClosed> = Vec::new();
    let mut checks: Vec<(PrAction, body::Submitted)> = Vec::new();
    for item in &classified.items {
        match item {
            Item::Fail(f) => {
                if ctx.rules.keeps(f.action) {
                    fails.push(f.clone());
                }
            }
            Item::Gh(g) => match body::read(g, &tok, &classified) {
                Ok(s) if s.title.is_none() && s.body.is_none() => {}
                Ok(s) => checks.push((g.action, s)),
                Err(case) => fails.push(FailClosed {
                    action: Action::Pr(Some(g.action)),
                    case,
                }),
            },
            // The push check reads these; the classifier has already failed
            // closed on every push it could not hand over.
            Item::Push(_) => {}
        }
    }

    let mut broken: Vec<Broken> = Vec::new();
    let mut header = None;
    if let Some((first, _)) = checks.first() {
        match pr_registry(&ctx.registry) {
            Err(e) => fails.push(FailClosed {
                action: Action::Pr(Some(*first)),
                case: Case::Registry {
                    id: e.id,
                    what: e.what,
                },
            }),
            Ok(reg) => {
                for (action, s) in &checks {
                    match broken_rules(&reg, s, ctx) {
                        Ok(b) if b.is_empty() => {}
                        Ok(b) => {
                            header.get_or_insert(Action::Pr(Some(*action)));
                            for rule in b {
                                match broken.iter_mut().find(|x| x.id == rule.id) {
                                    Some(x) => x.details.extend(rule.details),
                                    None => broken.push(rule),
                                }
                            }
                        }
                        Err(e) => fails.push(FailClosed {
                            action: Action::Pr(Some(*action)),
                            case: Case::Registry {
                                id: e.id,
                                what: e.what,
                            },
                        }),
                    }
                }
                broken.sort_by_key(|b| reg.order(&b.id));
            }
        }
    }

    if broken.is_empty() && fails.is_empty() {
        None
    } else {
        Some(reason::render(header, &broken, &fails))
    }
}

/// The registry, checked to answer for every PR-body rule: an active entry
/// and text anchors that resolve (PRD R7 case 6), so a damaged registry
/// denies a checked command even when its body is clean.
fn pr_registry(source: &RegistrySource) -> Result<Registry, RegistryError> {
    let reg = Registry::load(source)?;
    for id in PR_RULES {
        reg.range(reg.entry(id)?)?;
    }
    Ok(reg)
}

/// The PR-body rules `s` breaks, one entry per rule with every finding's
/// detail. What is checked follows what is submitted (PRD R3): a body runs
/// PB2 to PB4, plus PB1 with a title; a title alone runs PB1.
fn broken_rules(
    reg: &Registry,
    s: &body::Submitted,
    ctx: &Ctx,
) -> Result<Vec<Broken>, RegistryError> {
    let findings: Vec<PrBodyFinding> = match (&s.body, &s.title) {
        (Some(b), t) => check_pr_body(b, t.as_deref()),
        (None, Some(t)) => check_pr_title(t).into_iter().collect(),
        (None, None) => Vec::new(),
    };
    let findings: Vec<PrBodyFinding> =
        if findings.iter().any(is_no_heading_finding) && (ctx.canary_opted_in)() {
            findings
                .into_iter()
                .filter(|f| !is_no_heading_finding(f))
                .collect()
        } else {
            findings
        };
    let mut out: Vec<Broken> = Vec::new();
    for f in findings {
        let entry = if f.code.is_empty() {
            reg.entry(CONFORMANCE)?
        } else {
            reg.by_alias(f.code).ok_or_else(|| RegistryError {
                id: CONFORMANCE.to_string(),
                what: format!("no active entry has the alias {}", f.code),
            })?
        };
        let detail = if f.code != "PB1" && f.line > 1 {
            format!("body line {}: {}", f.line, f.message)
        } else {
            f.message
        };
        match out.iter_mut().find(|b| b.id == entry.id) {
            Some(b) => b.details.push(detail),
            None => out.push(Broken {
                id: entry.id.clone(),
                summary: entry.summary.clone(),
                range: reg.range(entry)?,
                details: vec![detail],
            }),
        }
    }
    Ok(out)
}

/// Whether this host opted into the live offload canary:
/// `$XDG_CONFIG_HOME/shirabe/offload-canary` when `XDG_CONFIG_HOME` is set and
/// non-empty, else `$HOME/.config/shirabe/offload-canary`, read the way
/// /work-on's offload-canary.sh reads it. With neither variable set, the host
/// has not opted in. docs/guides/offload-live-canary.md says why PB4 is left
/// to the /work-on gate there.
pub fn canary_opted_in() -> bool {
    let base = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(v) if !v.is_empty() => std::path::PathBuf::from(v),
        _ => match std::env::var_os("HOME") {
            Some(h) if !h.is_empty() => std::path::PathBuf::from(h).join(".config"),
            _ => return false,
        },
    };
    opted_in_at(&base.join("shirabe").join("offload-canary"))
}

/// True when `path` is a regular file, not a symlink, whose first line is
/// exactly the bytes `on`. Compared as bytes, like the shell's `read -r`, so
/// a `on\r` line or invalid UTF-8 later in the file reads the same in both.
/// Any error reads as not opted in, so a broken file keeps PB4 denied.
fn opted_in_at(path: &Path) -> bool {
    match std::fs::symlink_metadata(path) {
        Ok(m) if m.file_type().is_file() => {}
        _ => return false,
    }
    match std::fs::read(path) {
        Ok(bytes) => bytes.split(|b| *b == b'\n').next() == Some(&b"on"[..]),
        Err(_) => false,
    }
}

/// Print the PreToolUse `deny` decision. The reason is a `serde_json` string
/// value, so a title or body can never break out of the JSON or inject a
/// terminal control sequence.
pub fn emit_deny(reason: &str) {
    let value = serde_json::json!({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    });
    if let Ok(s) = serde_json::to_string(&value) {
        println!("{s}");
    }
}

#[cfg(test)]
mod tests;
