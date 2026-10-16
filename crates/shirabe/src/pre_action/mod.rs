//! The pre-action evaluator: a Claude Code **PreToolUse** check on a Bash
//! command, run before the command, that denies a guarded action breaking a
//! rule it guards and fails closed on a guarded action it can't check
//! (DESIGN-pre-action-denies, PRD-pre-action-denies).
//!
//! Both entry points run it. `shirabe pr-body-hook`, the one niwa wires into
//! a host's settings, calls [`run_legacy`]: the PR-body rules only, with the
//! registry compiled into the binary. `shirabe pre-action-hook`, the plugin's
//! own hook, calls [`run_plugin`]: every rule and the registry the plugin
//! ships, yielding the PR-body rules to the legacy entry point when the
//! host's settings wire it ([`settings`]).
//!
//! The flow, for one hook call: read the input, tokenize the command
//! ([`tokenize`]), classify its segments ([`classify`]); for each guarded
//! `gh pr create|edit`, read the title and body ([`body`]) and run
//! `shirabe_validate::check_pr_body` / `check_pr_title`, the engine `shirabe
//! validate --pr-body` runs, mapping each finding to a registry id through
//! the entry whose `aliases` holds its PB code ([`registry`]); render the
//! deny ([`reason`]). For each guarded `git push`, find the non-merge commits
//! it would send with local git plumbing and test their messages with PB3's
//! predicate ([`push`]). A command with nothing guarded in it gets no
//! decision whatever else fails, the registry included, and starts no
//! process.
//!
//! Security: the command, title, body and commit messages are
//! attacker-controlled. Nothing is shell-evaluated, the deny is built with
//! `serde_json`, nothing is written, and a body file's lines never reach the
//! reason. Git runs from a fixed environment with the repository's programs
//! switched off. The input's
//! `transcript_path` and `session_id` are ignored, and nothing is logged.

pub mod body;
pub mod classify;
pub mod push;
pub mod reason;
pub mod registry;
pub mod settings;
pub mod tokenize;

use std::io::Read;
use std::path::Path;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use shirabe_validate::{check_pr_body, check_pr_title, is_no_heading_finding, PrBodyFinding};

use classify::{classify, named_in_command, named_in_raw_input, Item, Named, PushSegment};
use push::{GitRunner, SystemGit};
use reason::{Action, Broken, Case, FailClosed, PrAction};
pub use registry::RegistrySource;
use registry::{Registry, RegistryError};
use tokenize::Refused;

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

/// Every rule the evaluator checks: [`PR_RULES`] followed by [`PUSH_RULES`],
/// which a test holds it to. The plugin's entry point checks that every id
/// on its `--rules` list is here, in any order.
///
/// A new rule is added in four places: the plugin script's `RULE_IDS` line
/// (hooks/pre-action-deny.sh), this table, [`PR_RULES`] or [`PUSH_RULES`],
/// and the rule's `deny` field in references/rule-registry.json. Tests and
/// scripts/check-rule-registry.sh hold the four to each other.
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
    /// The plugin hook's set.
    All,
    /// The legacy entry point: every fail-closed case attached to a `gh pr`
    /// segment, and the segment-less cases (malformed input, an unterminated
    /// quote, an oversize input) when the text names a `gh pr` action.
    PrBodyOnly,
    /// The plugin hook when it leaves the PR-body rules to someone else:
    /// under `PR_BODY_HOOK_DISABLE`, and on a call where the host wires the
    /// legacy entry point (PRD R12). The push cases, and the segment-less
    /// cases when the text names `git` ... `push`.
    PushOnly,
}

impl RuleSet {
    fn keeps(self, a: Action) -> bool {
        match self {
            RuleSet::All => true,
            RuleSet::PrBodyOnly => matches!(a, Action::Pr(_)),
            RuleSet::PushOnly => a == Action::Push,
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
    /// Whether the host's settings wire `shirabe pr-body-hook` (PRD R12).
    /// Asked only under [`RuleSet::All`] and only when a pull-request action
    /// is in play, so an unguarded command or a lone push reads no settings.
    pub legacy_wired: &'a dyn Fn() -> bool,
    /// Runs the push check's git children; asked only for a guarded push.
    pub git: &'a dyn GitRunner,
    /// How long the push check's git calls may take together.
    pub git_budget: Duration,
}

impl Ctx<'_> {
    /// The rules this call checks. The plugin's set yields the PR-body rules
    /// and their fail-closed cases when a pull-request action is in play and
    /// the legacy entry point, the same evaluator, will report them.
    fn rules_for(&self, pr_in_play: bool) -> RuleSet {
        if self.rules == RuleSet::All && pr_in_play && (self.legacy_wired)() {
            RuleSet::PushOnly
        } else {
            self.rules
        }
    }

    fn segment_less(&self, named: Named, case: Case) -> Option<String> {
        segment_less(named, self.rules_for(named.pr), case)
    }
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
                legacy_wired: &|| false,
                // The legacy set checks no push, so this is never asked.
                git: &SystemGit::from_env(),
                git_budget: push::git_budget(),
            },
        )
    });
    if let Some(reason) = reason {
        emit_deny(&reason);
    }
    ExitCode::SUCCESS
}

/// Entry point for `shirabe pre-action-hook --plugin-root <root> --rules
/// <ids>`, the plugin's hook. `rules` is the plugin script's `RULE_IDS` line
/// and the version handshake: when it names a rule this binary doesn't
/// check, the binary is older than the plugin, and it exits 3 so the script
/// fails closed. Otherwise it exits 0, a block being a `deny` decision on
/// stdout.
pub fn run_plugin(root: &Path, rules: &str) -> ExitCode {
    if hook_off() {
        return ExitCode::SUCCESS;
    }
    if let Some(id) = rules.split_whitespace().find(|id| !RULES.contains(id)) {
        eprintln!("shirabe pre-action-hook: this binary doesn't check {id}; update shirabe");
        return ExitCode::from(3);
    }
    let rules = if pr_body_disabled() {
        RuleSet::PushOnly
    } else {
        RuleSet::All
    };
    let registry = RegistrySource::PluginRoot(root.to_path_buf());
    let input = read_stdin();
    // The crash and deadline fallback keeps `rules` and reads no settings: a
    // host that wires the legacy entry point may then see a fail-closed
    // paragraph twice, the duplicate R12 prefers to a missing one.
    let reason = decide(input, rules, DEADLINE, move |input| {
        evaluate(
            input,
            &Ctx {
                rules,
                registry,
                canary_opted_in: &canary_opted_in,
                legacy_wired: &settings::legacy_wired,
                git: &SystemGit::from_env(),
                git_budget: push::git_budget(),
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
/// coarse test names a guarded action `rules` keeps, and no decision
/// otherwise, so neither a crash nor a hang is the silent pass niwa's `||
/// exit 0` would make it.
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
            segment_less(named_in_input(&input), rules, Case::Deadline)
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
            segment_less(named_in_input(&input), rules, Case::Crash)
        }
    }
}

/// The coarse test for the crash and deadline fallbacks: on the input's
/// `tool_input.command` when the input parses and holds one, so text
/// elsewhere in it (a `description` saying "git push later") can't deny an
/// unguarded command; on the raw input when it doesn't, or is past
/// [`MAX_INPUT`].
fn named_in_input(input: &str) -> Named {
    if input.len() <= MAX_INPUT {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(input) {
            if let Some(command) = v.pointer("/tool_input/command").and_then(|c| c.as_str()) {
                return named_in_command(command);
            }
        }
    }
    named_in_raw_input(input)
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
        Some(reason::render(&[], &[], &fails))
    }
}

/// Evaluate one PreToolUse input: `Some(reason)` to deny, `None` for no
/// decision.
pub fn evaluate(input: &str, ctx: &Ctx) -> Option<String> {
    if input.len() > MAX_INPUT {
        return ctx.segment_less(named_in_raw_input(input), Case::Oversize);
    }
    let Ok(v) = serde_json::from_str::<serde_json::Value>(input) else {
        return ctx.segment_less(named_in_raw_input(input), Case::HookInput);
    };
    let Some(command) = v.pointer("/tool_input/command").and_then(|c| c.as_str()) else {
        return ctx.segment_less(named_in_raw_input(input), Case::HookInput);
    };
    let cwd = v.get("cwd").and_then(|c| c.as_str()).map(Path::new);
    let tok = match tokenize::tokenize(command) {
        Ok(tok) => tok,
        Err(Refused::Unterminated) => {
            return ctx.segment_less(named_in_command(command), Case::Quote)
        }
        Err(Refused::TooDeep) => return ctx.segment_less(named_in_command(command), Case::Nesting),
    };
    let classified = classify(&tok, cwd);
    let rules = ctx.rules_for(classified.items.iter().any(|i| match i {
        Item::Gh(_) => true,
        Item::Fail(f) => matches!(f.action, Action::Pr(_)),
        Item::Push(_) => false,
    }));

    let mut fails: Vec<FailClosed> = Vec::new();
    let mut checks: Vec<(PrAction, body::Submitted)> = Vec::new();
    let mut pushes: Vec<&PushSegment> = Vec::new();
    for item in &classified.items {
        match item {
            Item::Fail(f) => {
                if rules.keeps(f.action) {
                    fails.push(f.clone());
                }
            }
            // A `gh pr` segment left to the legacy entry point: not even its
            // body file is read.
            Item::Gh(g) if !rules.keeps(Action::Pr(Some(g.action))) => {}
            Item::Gh(g) => match body::read(g, &tok, &classified) {
                Ok(s) if s.title.is_none() && s.body.is_none() => {}
                Ok(s) => checks.push((g.action, s)),
                Err(case) => fails.push(FailClosed {
                    action: Action::Pr(Some(g.action)),
                    case,
                }),
            },
            // The classifier has already failed closed on every push it
            // could not hand over.
            Item::Push(p) if rules.keeps(Action::Push) => pushes.push(p),
            Item::Push(_) => {}
        }
    }

    let mut broken: Vec<Broken> = Vec::new();
    let mut actions: Vec<Action> = Vec::new();
    // The registry is read once, and only when something is checked.
    let reg = if checks.is_empty() && pushes.is_empty() {
        None
    } else {
        Some(Registry::load(&ctx.registry))
    };
    let registry_fail = |action: Action, e: RegistryError| FailClosed {
        action,
        case: Case::Registry {
            id: e.id,
            what: e.what,
        },
    };
    if let (Some((first, _)), Some(reg)) = (checks.first(), &reg) {
        match reg
            .as_ref()
            .map_err(Clone::clone)
            .and_then(|r| answers(r, PR_RULES))
        {
            Err(e) => fails.push(registry_fail(Action::Pr(Some(*first)), e)),
            Ok(()) => {
                let reg = reg.as_ref().expect("checked above");
                for (action, s) in &checks {
                    match broken_rules(reg, s, ctx) {
                        Ok(b) if b.is_empty() => {}
                        Ok(b) => {
                            actions.push(Action::Pr(Some(*action)));
                            for rule in b {
                                match broken.iter_mut().find(|x| x.id == rule.id) {
                                    Some(x) => x.details.extend(rule.details),
                                    None => broken.push(rule),
                                }
                            }
                        }
                        Err(e) => fails.push(registry_fail(Action::Pr(Some(*action)), e)),
                    }
                }
            }
        }
    }
    if let (false, Some(reg)) = (pushes.is_empty(), &reg) {
        match reg.as_ref().map_err(Clone::clone).and_then(|r| {
            answers(r, PUSH_RULES)?;
            Ok(r)
        }) {
            Err(e) => fails.push(registry_fail(Action::Push, e)),
            Ok(reg) => {
                let mut offenders: Vec<push::Offender> = Vec::new();
                for p in &pushes {
                    match push::check(p, ctx.git, ctx.git_budget) {
                        Ok(found) => {
                            for o in found {
                                if !offenders.iter().any(|x| x.id == o.id) {
                                    offenders.push(o);
                                }
                            }
                        }
                        Err(case) => fails.push(FailClosed {
                            action: Action::Push,
                            case,
                        }),
                    }
                }
                if !offenders.is_empty() {
                    let id = PUSH_RULES[0];
                    match reg.entry(id).and_then(|e| Ok((e, reg.range(e)?))) {
                        Ok((entry, range)) => {
                            actions.push(Action::Push);
                            broken.push(Broken {
                                id: entry.id.clone(),
                                summary: entry.summary.clone(),
                                range,
                                details: push::details(&offenders),
                            });
                        }
                        Err(e) => fails.push(registry_fail(Action::Push, e)),
                    }
                }
            }
        }
    }
    if let Some(Ok(reg)) = &reg {
        broken.sort_by_key(|b| reg.order(&b.id));
    }

    if broken.is_empty() && fails.is_empty() {
        None
    } else {
        Some(reason::render(&actions, &broken, &fails))
    }
}

/// Whether the registry answers for every rule in `ids`: an active entry and
/// text anchors that resolve (PRD R7 case 6), so a damaged registry denies a
/// checked command even when nothing in it breaks a rule.
fn answers(reg: &Registry, ids: &[&str]) -> Result<(), RegistryError> {
    for id in ids {
        reg.range(reg.entry(id)?)?;
    }
    Ok(())
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
