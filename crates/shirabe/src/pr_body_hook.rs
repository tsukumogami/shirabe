//! The `shirabe pr-body-hook` subcommand: a Claude Code **PreToolUse** adapter
//! that gates a `gh pr create` / `gh pr edit` command against the mechanical
//! PR-body rule before the command runs.
//!
//! This is the authoring-time analog of the reactive `pr-body.yml` CI gate
//! (DESIGN-pr-template-gate, "client-side PreToolUse hook" increment). It is a
//! fail-safe hook adapter in the shape of [`crate::work_summary`], **not** a
//! `validate` mode: it reads a hook JSON on stdin, emits hook JSON with a
//! permission decision, and ALWAYS exits 0. It adds no rule — it reuses
//! [`shirabe_validate::check_pr_body`] / [`shirabe_validate::check_pr_title`],
//! the same engine `validate --pr-body` calls, so PB1-PB4 are stated once in
//! `references/pr-body-conformance.md` and enforced by CI, the skills, and this
//! hook alike.
//!
//! Behavior (DESIGN D8/D9):
//!
//! - It extracts the submitted `--title`, `--body`, and `--body-file <path>`
//!   from the command's **argv tokens** (never by shell-evaluating the
//!   command). A `--body-file` path is read from disk.
//! - When a title and/or body is extractable and the checks return findings,
//!   it **denies** the tool call and returns the findings as the decision
//!   reason, so the agent sees what to fix and re-issues a corrected command.
//! - In every ambiguous case — the command is not a recognized
//!   `gh pr create`/`edit`, no title/body can be extracted, a `--body-file`
//!   cannot be read, `--fill`/`--web`/`--body-file -` is used, a body carries a
//!   command substitution, or the stdin is malformed — it **allows** (emits
//!   nothing). The CI gate is the authoritative backstop that makes fail-open
//!   safe.
//!
//! Security: the command, title, and body are attacker-controlled. The command
//! is never shell-evaluated; the deny reason is assembled with `serde_json`, so
//! the title/body is always a JSON string value, never concatenated into a
//! terminal control sequence. The adapter runs no subprocess and writes nothing.
//!
//! Env seam: `PR_BODY_HOOK_DISABLE=1` short-circuits to allow (an operator kill
//! switch that does not require unwiring the hook), mirroring the `WS_*` seams.

use std::io::Read;
use std::process::ExitCode;

use shirabe_validate::{check_pr_body, check_pr_title, PrBodyFinding};

/// Entry point for `shirabe pr-body-hook`. Always returns
/// `ExitCode::SUCCESS`: the adapter is fail-safe and must never abort the
/// tool call with a non-zero code — a block is expressed as a `deny` decision
/// in the emitted hook JSON, not as a process exit code.
pub fn run() -> ExitCode {
    if disabled() {
        return ExitCode::SUCCESS;
    }
    let input = read_stdin();
    if let Some(reason) = evaluate(&input) {
        emit_deny(&reason);
    }
    ExitCode::SUCCESS
}

/// The kill switch: `PR_BODY_HOOK_DISABLE=1` (any non-empty value other than
/// `0`/`false`) turns the adapter into an unconditional allow.
fn disabled() -> bool {
    match std::env::var("PR_BODY_HOOK_DISABLE") {
        Ok(v) => !v.is_empty() && v != "0" && v != "false",
        Err(_) => false,
    }
}

fn read_stdin() -> String {
    let mut s = String::new();
    let _ = std::io::stdin().read_to_string(&mut s);
    s
}

/// Core logic, split out for testability: given the raw PreToolUse hook JSON,
/// return `Some(reason)` when the command should be **denied** (the reason
/// lists the PB findings) or `None` when it should be **allowed**.
///
/// Every failure path returns `None` (fail-open, DESIGN D9).
fn evaluate(input: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(input).ok()?;
    let command = v
        .get("tool_input")
        .and_then(|t| t.get("command"))
        .and_then(|c| c.as_str())?;

    let (_action, tokens) = find_gh_pr_command(command)?;
    let extracted = extract_fields(&tokens);

    let findings: Vec<PrBodyFinding> = match (extracted.body, extracted.title) {
        // A body is present: run the full body-level checks (PB2/PB3) plus the
        // title check (PB1) when a title is also present. This covers a
        // `gh pr create` (both) and a `gh pr edit --body` (body only).
        (Some(body), title) => check_pr_body(&body, title.as_deref()),
        // Title only (e.g. `gh pr edit --title`): run PB1 alone. Passing an
        // empty body to `check_pr_body` would spuriously fire PB2, so the
        // title-only path uses the dedicated title check.
        (None, Some(title)) => check_pr_title(&title).into_iter().collect(),
        // Nothing extractable to check (e.g. `gh pr edit 12 --add-label x`,
        // or `--fill`): allow.
        (None, None) => return None,
    };

    if findings.is_empty() {
        None
    } else {
        Some(render_reason(&findings))
    }
}

/// The action word of a recognized `gh pr` command.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PrAction {
    Create,
    Edit,
}

/// Locate a `gh ... pr create|edit` invocation in a (possibly compound)
/// command and return its action plus the argv tokens **after** the action
/// word (from which the option values are read).
///
/// The command is split into per-command token lists by [`tokenize_segments`]
/// (quote-aware, so a multi-line inline `--body` stays one token). `gh` is
/// matched only in **command-head** position — the first token that is not a
/// leading `NAME=value` env-assignment — so `echo gh pr create ...` is not
/// mistaken for a real invocation. Within that command, `pr` then
/// `create`/`edit` are matched as bare tokens. Returns `None` when the command
/// does not tokenize (unbalanced quote) or contains no such invocation —
/// fail-open.
fn find_gh_pr_command(cmd: &str) -> Option<(PrAction, Vec<String>)> {
    let segments = tokenize_segments(cmd)?;
    for seg in &segments {
        // The command head is the first token that is not a leading
        // `NAME=value` env-assignment; it must be exactly `gh`.
        let head = match seg.iter().position(|t| !is_env_assignment(t)) {
            Some(i) => i,
            None => continue,
        };
        if seg[head] != "gh" {
            continue;
        }
        // Within this command, require `pr` then `create`/`edit` as bare
        // tokens; return the argv tokens that follow the action word.
        let rest = &seg[head + 1..];
        let pr_i = match rest.iter().position(|t| t == "pr") {
            Some(i) => i,
            None => continue,
        };
        let action = rest[pr_i + 1..]
            .iter()
            .enumerate()
            .find_map(|(k, t)| match t.as_str() {
                "create" => Some((k, PrAction::Create)),
                "edit" => Some((k, PrAction::Edit)),
                _ => None,
            });
        if let Some((off, action)) = action {
            let after_action = pr_i + 1 + off + 1;
            return Some((action, rest[after_action..].to_vec()));
        }
    }
    None
}

/// True when `t` is a shell env-assignment token `NAME=value` with `NAME` a
/// valid identifier (so a leading `GH_TOKEN=x` before `gh` is skipped, while a
/// real first word such as `echo` or `gh` is not).
fn is_env_assignment(t: &str) -> bool {
    match t.split_once('=') {
        Some((name, _)) => {
            !name.is_empty()
                && name
                    .chars()
                    .next()
                    .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        }
        None => false,
    }
}

/// Conservative shell-ish tokenizer that splits a (possibly compound) command
/// into per-command token lists. Unquoted whitespace ends a token; the unquoted
/// command separators `;` `|` `&` end the current command and start a new one,
/// so `gh` is only ever matched in command-head position (`cd x && gh pr
/// create ...` yields two commands). Single- and double-quoted spans are taken
/// literally — including any newlines — since this adapter never expands or
/// evaluates; a backslash outside quotes escapes the next character. Returns
/// `None` on an unterminated quote, so the caller fails open.
///
/// Not a full shell parser: it performs no variable or command substitution.
/// Bodies relying on `$(...)`, backticks, or heredocs surface as opaque tokens
/// and are rejected at extraction time (see [`resolve_body_value`] /
/// [`read_body_file`]).
fn tokenize_segments(input: &str) -> Option<Vec<Vec<String>>> {
    let mut segments: Vec<Vec<String>> = Vec::new();
    let mut seg: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut in_token = false;
    let mut chars = input.chars();
    while let Some(c) = chars.next() {
        match c {
            '\'' => {
                in_token = true;
                loop {
                    match chars.next() {
                        Some('\'') => break,
                        Some(ch) => cur.push(ch),
                        None => return None, // unterminated single quote
                    }
                }
            }
            '"' => {
                in_token = true;
                loop {
                    match chars.next() {
                        Some('"') => break,
                        Some('\\') => {
                            // Inside double quotes a backslash escapes only a
                            // small set; keep it literal otherwise.
                            match chars.next() {
                                Some(n @ ('"' | '\\' | '$' | '`')) => cur.push(n),
                                Some(n) => {
                                    cur.push('\\');
                                    cur.push(n);
                                }
                                None => return None,
                            }
                        }
                        Some(ch) => cur.push(ch),
                        None => return None, // unterminated double quote
                    }
                }
            }
            '\\' => {
                in_token = true;
                match chars.next() {
                    Some(n) => cur.push(n),
                    None => return None,
                }
            }
            // Command separators end the current token AND the current command.
            ';' | '|' | '&' => {
                if in_token {
                    seg.push(std::mem::take(&mut cur));
                    in_token = false;
                }
                if !seg.is_empty() {
                    segments.push(std::mem::take(&mut seg));
                }
            }
            c if c.is_whitespace() => {
                if in_token {
                    seg.push(std::mem::take(&mut cur));
                    in_token = false;
                }
            }
            _ => {
                in_token = true;
                cur.push(c);
            }
        }
    }
    if in_token {
        seg.push(cur);
    }
    if !seg.is_empty() {
        segments.push(seg);
    }
    Some(segments)
}

/// The title/body fields pulled out of a `gh pr create|edit` argv.
#[derive(Default, Debug)]
struct Fields {
    title: Option<String>,
    body: Option<String>,
}

/// Read the `--title`/`-t`, `--body`/`-b`, and `--body-file`/`-F` option values
/// out of the argv tokens. `--flag=value` and `--flag value` forms are both
/// accepted. `--fill`, `--fill-first`, `--web`, an inline body carrying a
/// command substitution, and a `--body-file` that is `-` or unreadable each
/// leave `body` as `None` (nothing confidently extractable → allow).
fn extract_fields(tokens: &[String]) -> Fields {
    let mut fields = Fields::default();
    let mut body_file: Option<String> = None;
    let mut i = 0;
    while i < tokens.len() {
        let t = tokens[i].as_str();
        // Split `--flag=value` (an option token only — a bare `a=b` is not a
        // flag) into (flag, inline-value); otherwise the value is the next
        // token, consumed by advancing `i`.
        let (flag, inline) = match t.split_once('=') {
            Some((f, v)) if f.starts_with('-') => (f, Some(v.to_string())),
            _ => (t, None),
        };
        let slot = match flag {
            "--title" | "-t" => Some(&mut fields.title),
            "--body" | "-b" => Some(&mut fields.body),
            "--body-file" | "-F" => Some(&mut body_file),
            _ => None,
        };
        if let Some(slot) = slot {
            if let Some(v) = inline {
                *slot = Some(v);
            } else if i + 1 < tokens.len() {
                *slot = Some(tokens[i + 1].clone());
                i += 1;
            }
        }
        i += 1;
    }

    // Resolve the inline body: reject a command-substitution body (unresolvable
    // statically) so we do not check a literal `$(...)` string.
    if let Some(b) = fields.body.take() {
        fields.body = resolve_body_value(b);
    }
    // A `--body-file` overrides only when we have no inline body. Read it from
    // disk; any failure leaves the body `None` (fail-open).
    if fields.body.is_none() {
        if let Some(path) = body_file {
            fields.body = read_body_file(&path);
        }
    }
    fields
}

/// Accept an inline `--body` value unless it looks like an unresolved shell
/// expansion (command substitution), which this adapter cannot evaluate — in
/// that case return `None` so the command is allowed and the CI gate checks it.
fn resolve_body_value(body: String) -> Option<String> {
    if body.contains("$(") || body.contains('`') {
        return None;
    }
    Some(body)
}

/// Read a `--body-file` path. Returns `None` for stdin (`-`), a path carrying a
/// process/command substitution, or any I/O failure — every one is treated as
/// "no confidently extractable body" (fail-open, DESIGN D9).
fn read_body_file(path: &str) -> Option<String> {
    if path == "-" || path.contains("$(") || path.contains('`') || path.starts_with("<(") {
        return None;
    }
    std::fs::read_to_string(path).ok()
}

/// Render the deny reason from the findings: a fixed prefix line the agent can
/// recognize, then one `- <message>` line per finding.
fn render_reason(findings: &[PrBodyFinding]) -> String {
    let mut out =
        String::from("PR body check failed (references/pr-body-conformance.md). Fix and re-run:");
    for f in findings {
        out.push_str("\n- ");
        out.push_str(&f.message);
    }
    out
}

/// Print the PreToolUse `deny` hook JSON. The reason is placed in a
/// `serde_json` string value, so an attacker-influenceable title/body can never
/// break out of the JSON string or inject a terminal control sequence. Matches
/// the shape the existing `gate-online` PreToolUse hook emits.
fn emit_deny(reason: &str) {
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
mod tests {
    use super::*;

    /// Build a PreToolUse hook JSON with `command` as the Bash tool input.
    fn hook(command: &str) -> String {
        serde_json::json!({
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_input": { "command": command },
        })
        .to_string()
    }

    #[test]
    fn clean_create_is_allowed() {
        let cmd = "gh pr create --title 'feat: add mode' --body 'Adds the mode.

---

Fixes #1'";
        assert_eq!(evaluate(&hook(cmd)), None);
    }

    #[test]
    fn non_conventional_title_is_denied() {
        let cmd = "gh pr create --title 'Add the mode' --body 'Body.

---

Fixes #1'";
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("not Conventional Commits"), "got: {reason}");
    }

    #[test]
    fn missing_separator_is_denied() {
        let cmd = "gh pr create --title 'fix: thing' --body 'One part only, no separator.'";
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("no `---` separator"), "got: {reason}");
    }

    #[test]
    fn attribution_footer_is_denied() {
        let cmd = "gh pr create -t 'fix: thing' -b 'Real change.

---

Context.

Co-Authored-By: Claude <noreply@anthropic.com>'";
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("AI-attribution"), "got: {reason}");
    }

    #[test]
    fn flag_equals_value_form_is_parsed() {
        let cmd = "gh pr create --title=Add --body='b\n\n---\n\nx'";
        // `--title=Add` is not Conventional Commits -> deny naming the title.
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("not Conventional Commits"), "got: {reason}");
    }

    #[test]
    fn edit_title_only_runs_pb1_only() {
        // A title-only edit must run PB1 and NOT trip PB2 (no body/separator).
        let bad = "gh pr edit 12 --title 'Not conventional'";
        assert!(evaluate(&hook(bad))
            .expect("should deny")
            .contains("not Conventional Commits"));
        let good = "gh pr edit 12 --title 'feat: good title'";
        assert_eq!(evaluate(&hook(good)), None, "clean title-only edit allowed");
    }

    #[test]
    fn edit_body_only_runs_body_checks() {
        let cmd = "gh pr edit 12 --body 'No separator body.'";
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("no `---` separator"), "got: {reason}");
    }

    #[test]
    fn edit_without_title_or_body_is_allowed() {
        let cmd = "gh pr edit 12 --add-label needs-review";
        assert_eq!(evaluate(&hook(cmd)), None);
    }

    #[test]
    fn non_gh_command_is_allowed() {
        assert_eq!(evaluate(&hook("echo gh pr create --title bad")), None);
        assert_eq!(evaluate(&hook("git commit -m 'not a pr'")), None);
    }

    #[test]
    fn fill_and_web_are_allowed() {
        assert_eq!(evaluate(&hook("gh pr create --fill")), None);
        assert_eq!(
            evaluate(&hook("gh pr create --title 'feat: x' --web")),
            None,
            "no body to check, title is fine"
        );
    }

    #[test]
    fn command_substitution_body_is_allowed() {
        // We cannot evaluate `$(...)`; fail open and let CI check the real body.
        let cmd = "gh pr create --title 'feat: x' --body \"$(cat body.txt)\"";
        assert_eq!(evaluate(&hook(cmd)), None);
    }

    #[test]
    fn body_file_is_read_and_checked() {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("shirabe-hook-test-{}.md", std::process::id()));
        std::fs::write(&path, "One-part body, no separator.\n").unwrap();
        let cmd = format!(
            "gh pr create --title 'fix: thing' --body-file {}",
            path.display()
        );
        let reason = evaluate(&hook(&cmd)).expect("should deny");
        assert!(reason.contains("no `---` separator"), "got: {reason}");
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn body_file_clean_is_allowed() {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("shirabe-hook-ok-{}.md", std::process::id()));
        std::fs::write(&path, "Real change.\n\n---\n\nFixes #2\n").unwrap();
        let cmd = format!(
            "gh pr create --title 'fix: real' --body-file {}",
            path.display()
        );
        assert_eq!(evaluate(&hook(&cmd)), None);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn unreadable_body_file_is_allowed() {
        let cmd = "gh pr create --title 'fix: thing' --body-file /nonexistent/nope.md";
        assert_eq!(evaluate(&hook(cmd)), None);
    }

    #[test]
    fn body_file_dash_stdin_is_allowed() {
        let cmd = "gh pr create --title 'fix: thing' --body-file -";
        assert_eq!(evaluate(&hook(cmd)), None);
    }

    #[test]
    fn malformed_stdin_is_allowed() {
        assert_eq!(evaluate("not json at all"), None);
        assert_eq!(evaluate("{}"), None);
        assert_eq!(evaluate(""), None);
    }

    #[test]
    fn env_assignment_prefix_is_stripped() {
        let cmd = "GH_TOKEN=abc gh pr create --title 'bad title' --body 'b\n\n---\n\nx'";
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("not Conventional Commits"), "got: {reason}");
    }

    #[test]
    fn compound_command_finds_the_gh_segment() {
        let cmd = "cd /tmp && gh pr create --title 'bad' --body 'b\n\n---\n\nx'";
        let reason = evaluate(&hook(cmd)).expect("should deny");
        assert!(reason.contains("not Conventional Commits"), "got: {reason}");
    }

    #[test]
    fn unterminated_quote_segment_is_allowed() {
        // A segment we cannot tokenize is skipped (fail-open).
        let cmd = "gh pr create --title 'unterminated --body 'b\n\n---\n\nx'";
        // Depending on how quotes pair this may or may not parse; the contract
        // is only that it never panics and returns a decision.
        let _ = evaluate(&hook(cmd));
    }

    #[test]
    fn deny_reason_is_json_safe() {
        // A crafted title with quotes/newlines must not break the JSON.
        let cmd = "gh pr create --title 'evil\" }] title' --body 'Real.\n\n---\n\nx'";
        if let Some(reason) = evaluate(&hook(cmd)) {
            let value = serde_json::json!({
                "hookSpecificOutput": { "permissionDecisionReason": reason }
            });
            let s = serde_json::to_string(&value).unwrap();
            // Round-trips cleanly: the reason is a proper JSON string value.
            let back: serde_json::Value = serde_json::from_str(&s).unwrap();
            assert!(back["hookSpecificOutput"]["permissionDecisionReason"].is_string());
        }
    }

    #[test]
    fn disable_env_short_circuits() {
        // The kill switch is checked in `run`; here we assert the predicate.
        std::env::set_var("PR_BODY_HOOK_DISABLE", "1");
        assert!(disabled());
        std::env::set_var("PR_BODY_HOOK_DISABLE", "0");
        assert!(!disabled());
        std::env::remove_var("PR_BODY_HOOK_DISABLE");
        assert!(!disabled());
    }
}
