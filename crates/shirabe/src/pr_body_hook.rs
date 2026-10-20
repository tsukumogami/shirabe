//! The `shirabe pr-body-hook` subcommand: the Claude Code **PreToolUse** entry
//! point niwa wires into a host's settings, which denies a `gh pr create` or
//! `gh pr edit` whose title or body breaks a PR-body rule before it runs.
//!
//! It is the pre-action evaluator ([`crate::pre_action`]) restricted to the
//! PR-body rules, reading the rule registry compiled into the binary; the
//! plugin's own hook runs the same evaluator with every rule. It reuses the
//! engine `validate --pr-body` calls, so PB1 to PB4 are stated once in
//! `references/pr-body-conformance.md` and enforced by CI, the skills and
//! this hook alike. Each deny names the registered rule, its summary and
//! where its text is (PRD-pre-action-denies R5), and a pull-request command
//! it can't check (`--fill`, an unreadable body file, an unterminated quote)
//! is denied with the reason rather than let through (R7, R11).
//!
//! It always exits 0. Off switches, for the person running the host:
//! `SHIRABE_PRE_ACTION_HOOK=off` turns every deny off, as it does for the
//! plugin's hook; `PR_BODY_HOOK_DISABLE` (any non-empty value other than `0`
//! or `false`) turns off the PR-body rules, which here is everything.
//!
//! Offload canary: on a host that opted into the live offload canary, PB4 is
//! not denied, so a PB4 violation reaches the /work-on gate that counts it
//! and the required PR-body CI check keeps it from merging. PB1 to PB3 are
//! denied as everywhere else. docs/guides/offload-live-canary.md says why.

use std::process::ExitCode;

use crate::pre_action;

/// Entry point for `shirabe pr-body-hook`.
pub fn run() -> ExitCode {
    if pre_action::hook_off() || pre_action::pr_body_disabled() {
        return ExitCode::SUCCESS;
    }
    pre_action::run_legacy()
}
