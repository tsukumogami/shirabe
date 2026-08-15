//! Static, offline conformance check for a pull-request body and title.
//!
//! This is the PR-body analog of [`crate::coordination::check_coordination_body`]:
//! it reads an authored PR title and body and checks the **mechanical,
//! objectively-decidable** parts of the tsukumogami two-part squash-merge
//! convention, with no `gh` and no network. It is the single source both the
//! CI gate and the authoring skills consume; the rule it enforces is stated in
//! prose in `references/pr-body-conformance.md`.
//!
//! Four checks are gated (DESIGN-pr-template-gate, PB1-PB4):
//!
//! 1. **PB1 — Conventional Commits title** (only when a title is supplied):
//!    `<type>[optional scope][!]: <description>`, `<type>` in the accepted set,
//!    a non-empty description, and a scope that is not an issue-number scope.
//! 2. **PB2 — separator and non-empty Part 1**: exactly one top-level bare
//!    `---` separator, with non-whitespace Part 1 above it. Part 1 becomes the
//!    squash commit body; everything from `---` down is deleted at merge.
//! 3. **PB3 — no AI-attribution footer**: no `Co-Authored-By:` trailer
//!    attributing to an AI assistant and no "Generated with Claude Code" line.
//! 4. **PB4 — no markdown section heading in Part 1**: Part 1 (the squash
//!    commit body) carries no markdown ATX heading line (`#`..`######` followed
//!    by a space). A clean commit message is prose; only a template-style,
//!    heading-structured Part 1 has one. Checked only when Part 1 is
//!    well-defined (exactly one separator, non-empty Part 1) and scoped to the
//!    text above the separator — Part 2 may use `## Section` headings freely.
//!
//! Everything else — which Part 2 sections a change needs, whether Part 1
//! mentions an issue — is subjective and stays advisory, owned by the
//! downstream PR-creation skill's reasoning framework, not this check.
//!
//! Structural scans (PB2, PB3, PB4) run over the body with fenced code blocks
//! removed, so a `---`, a `Co-Authored-By:` line, or a `##` shown inside an
//! example fence does not trip the check. Indented (4-space) code blocks are
//! not stripped; that residual is documented in
//! `references/pr-body-conformance.md`.

/// One finding from the static PR-body check. `line` is 1-based (or `1` for a
/// title-level finding, which has no body line); `message` is an actionable
/// "what to fix and why" string the CLI renders in any `--format`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PrBodyFinding {
    pub line: usize,
    pub message: String,
}

/// The Conventional Commits types accepted in a PR title (PB1). Mirrors the
/// set the PR-creation guidance lists.
const CONVENTIONAL_TYPES: &[&str] = &[
    "feat", "fix", "docs", "style", "refactor", "perf", "test", "chore", "ci", "build", "revert",
];

/// Statically check an authored PR `body` and optional `title`, offline.
///
/// Runs PB1 (only when `title` is `Some`), PB2, PB4, and PB3 and returns the
/// findings in source order. An empty vec means the PR is mechanically
/// conformant. The title check is skipped entirely when `title` is `None`, so a
/// caller checking a body-in-progress gets only the body-level rules; the CI
/// gate always supplies both.
pub fn check_pr_body(body: &str, title: Option<&str>) -> Vec<PrBodyFinding> {
    let mut findings: Vec<PrBodyFinding> = Vec::new();

    // PB1 — Conventional Commits title.
    if let Some(title) = title {
        if let Some(message) = check_title(title) {
            findings.push(PrBodyFinding { line: 1, message });
        }
    }

    // Structural checks scan the body with fenced code blocks removed.
    let top_level = top_level_lines(body);

    // PB2 — exactly one top-level `---` separator, non-empty Part 1.
    let separators: Vec<usize> = top_level
        .iter()
        .filter(|(_, line)| line.trim() == "---")
        .map(|(n, _)| *n)
        .collect();

    match separators.len() {
        0 => findings.push(PrBodyFinding {
            line: 1,
            message: "the PR body has no `---` separator. Add a single line that is exactly \
                      `---` between Part 1 (the squash commit body) and Part 2 (reviewer \
                      context deleted at merge); see references/pr-body-conformance.md."
                .to_string(),
        }),
        1 => {
            let sep_line = separators[0];
            // Part 1 is every line above the separator (1-based sep_line ->
            // lines[0..sep_line-1]). Non-empty means it has non-whitespace.
            let part1_empty = body
                .lines()
                .take(sep_line - 1)
                .all(|l| l.trim().is_empty());
            if part1_empty {
                findings.push(PrBodyFinding {
                    line: sep_line,
                    message: "Part 1 (everything above the `---` separator) is empty. Part 1 \
                              becomes the squash commit body, so it must contain a factual \
                              description of the change; see references/pr-body-conformance.md."
                        .to_string(),
                });
            } else {
                // PB4 — Part 1 carries no markdown section heading. A clean
                // commit body is prose; an ATX heading (`#`..`######`) above the
                // separator means the commit message was written as a
                // template-style document. Scoped to the fence-stripped Part 1
                // (lines above the separator); Part 2 headings are untouched.
                if let Some((n, _)) = top_level
                    .iter()
                    .take_while(|(n, _)| *n < sep_line)
                    .find(|(_, line)| is_atx_heading(line))
                {
                    findings.push(PrBodyFinding {
                        line: *n,
                        message: "Part 1 (the squash commit body, above the `---` separator) \
                                  contains a markdown section heading. Part 1 lands permanently \
                                  on `main` as the commit message and must be plain prose, not a \
                                  heading-structured document; rewrite Part 1 as prose and move \
                                  any `## Section` headings below the `---` into Part 2 (see \
                                  references/pr-body-conformance.md)."
                            .to_string(),
                    });
                }
            }
        }
        n => findings.push(PrBodyFinding {
            line: separators[1],
            message: format!(
                "the PR body has {} top-level `---` separators; it must have exactly one. \
                 Everything from the first `---` down is deleted at merge, so a second bare \
                 `---` is ambiguous — use `***` or `___` for a horizontal rule in Part 2, or \
                 fence the example; see references/pr-body-conformance.md.",
                n
            ),
        }),
    }

    // PB3 — no AI-attribution / co-author footer.
    for (n, line) in &top_level {
        if is_attribution_line(line) {
            findings.push(PrBodyFinding {
                line: *n,
                message: "the PR body carries an AI-attribution / co-author footer. Remove the \
                          `Co-Authored-By:` AI trailer or the \"Generated with Claude Code\" \
                          line; the org convention forbids AI attribution and co-author lines \
                          (see references/pr-body-conformance.md)."
                    .to_string(),
            });
        }
    }

    findings
}

/// Check only PB1 (the Conventional Commits title) and nothing else.
///
/// This exposes the same title rule [`check_pr_body`] applies, without the
/// body-level PB2/PB3 checks, for a caller that has a title but no body — for
/// instance the client-side PreToolUse hook evaluating a `gh pr edit --title`
/// that changes only the title. It reuses the existing private [`check_title`]
/// scan; it does not restate PB1. Returns `Some(finding)` (with `line: 1`, the
/// title-level line) when the title is non-conforming, `None` when it passes.
pub fn check_pr_title(title: &str) -> Option<PrBodyFinding> {
    check_title(title).map(|message| PrBodyFinding { line: 1, message })
}

/// PB1: return `Some(message)` when `title` is not a valid Conventional Commits
/// header, `None` when it conforms. The parse is a small hand-written scan
/// (no regex dependency), matching this crate's style.
fn check_title(title: &str) -> Option<String> {
    let title = title.trim();
    let generic = || {
        format!(
            "PR title {:?} is not Conventional Commits. Use `<type>[optional scope]: \
             <description>` with <type> one of feat|fix|docs|style|refactor|perf|test|chore|\
             ci|build|revert; see references/pr-body-conformance.md.",
            title
        )
    };

    // Split on the first ':'. The description follows a `: ` (colon-space).
    // A title with no colon is not a Conventional Commits header.
    let (head, rest) = match title.split_once(':') {
        Some(pair) => pair,
        None => return Some(generic()),
    };
    if head.is_empty() {
        return Some(generic());
    }
    // Conventional Commits requires a space after the colon and a non-empty
    // description.
    if !rest.starts_with(' ') || rest.trim().is_empty() {
        return Some(generic());
    }

    // head is `type`, `type!`, `type(scope)`, or `type(scope)!`. Strip the
    // optional breaking-change `!` first.
    let head = head.strip_suffix('!').unwrap_or(head);

    let (type_part, scope) = match head.split_once('(') {
        Some((t, scope_rest)) => {
            let scope = match scope_rest.strip_suffix(')') {
                Some(s) => s,
                None => return Some(generic()),
            };
            (t, Some(scope))
        }
        None => (head, None),
    };

    if !CONVENTIONAL_TYPES.contains(&type_part) {
        return Some(generic());
    }

    if let Some(scope) = scope {
        if scope.trim().is_empty() {
            return Some(format!(
                "PR title {:?} has an empty scope `()`. Omit the parentheses or name a real \
                 subsystem; see references/pr-body-conformance.md.",
                title
            ));
        }
        if is_issue_number_scope(scope) {
            return Some(format!(
                "PR title {:?} uses an issue-number scope `({})`. Issue numbers are never a \
                 scope; put `Fixes #N` in Part 2 instead (see references/pr-body-conformance.md).",
                title, scope
            ));
        }
    }

    None
}

/// True when `scope` is an issue-number scope such as `issue-8`, `#8`, or `8`.
/// Pinned to a numeric shape so a legitimate word scope like `issue-tracker`
/// or `issues` is not over-matched.
fn is_issue_number_scope(scope: &str) -> bool {
    let lower = scope.trim().to_ascii_lowercase();
    let mut s = lower.as_str();
    if let Some(rest) = s.strip_prefix("issue") {
        s = rest.trim_start_matches(|c| c == '-' || c == '_');
    }
    s = s.strip_prefix('#').unwrap_or(s);
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

/// PB3 predicate: is `line` an AI-attribution / co-author footer line?
/// Matches the specific trailer/footer shapes rather than any mention of the
/// words, so prose that merely discusses the convention does not trip it.
fn is_attribution_line(line: &str) -> bool {
    let lower = line.to_ascii_lowercase();
    let trimmed = lower.trim_start();
    if trimmed.starts_with("co-authored-by:")
        && (lower.contains("claude") || lower.contains("anthropic"))
    {
        return true;
    }
    lower.contains("generated with claude code") || lower.contains("\u{1f916} generated with")
}

/// PB4 predicate: is `line` a markdown ATX section heading? Matches CommonMark
/// ATX: up to three leading spaces of indentation, a run of one-to-six `#`, then
/// a space/tab or the end of the line. A `#` run of seven or more, or a `#`
/// immediately followed by a non-space character (`#123`, `#!/bin/sh`,
/// `#include`), is not a heading — so an issue reference, a shebang, or a
/// preprocessor line in a prose commit body does not trip the check.
fn is_atx_heading(line: &str) -> bool {
    // CommonMark allows up to three spaces of indent; four or more makes the
    // line an indented code block, not a heading.
    let indent = line.len() - line.trim_start_matches(' ').len();
    if indent > 3 {
        return false;
    }
    let rest = &line[indent..];
    let hashes = rest.bytes().take_while(|&b| b == b'#').count();
    if hashes == 0 || hashes > 6 {
        return false;
    }
    // The `#` run must be followed by a space/tab or be the whole line (an empty
    // heading such as a bare `##` still counts).
    let after = &rest[hashes..];
    after.is_empty() || after.starts_with(' ') || after.starts_with('\t')
}

/// Yield the body's `(1-based line number, line)` pairs with fenced code
/// blocks removed. A fence opener is a line whose first non-indent run is three
/// or more backticks or tildes, optionally followed by an info string; the
/// block closes only on a bare same-marker line of at least the opener's
/// length (the two marker families do not cross-toggle). Opener, content, and
/// closer lines are all excluded, so PB2/PB3 see only top-level content. This
/// is the false-positive mitigation for `---` and attribution text shown
/// inside example fences (DESIGN D6, PB2/PB3).
fn top_level_lines(body: &str) -> Vec<(usize, &str)> {
    let mut out = Vec::new();
    // (marker char, opener run length) while inside a fence.
    let mut fence: Option<(char, usize)> = None;
    for (idx, line) in body.lines().enumerate() {
        let trimmed = line.trim_start();
        let marker = if trimmed.starts_with("```") {
            Some('`')
        } else if trimmed.starts_with("~~~") {
            Some('~')
        } else {
            None
        };
        match fence {
            None => match marker {
                Some(m) => {
                    let len = trimmed.chars().take_while(|&c| c == m).count();
                    fence = Some((m, len));
                }
                None => out.push((idx + 1, line)),
            },
            Some((fm, flen)) => {
                // A closer is a bare same-marker line of length >= opener, with
                // nothing but whitespace after the run.
                if marker == Some(fm) {
                    let run = trimmed.chars().take_while(|&c| c == fm).count();
                    let rest = trimmed[run..].trim();
                    if run >= flen && rest.is_empty() {
                        fence = None;
                    }
                }
                // Fenced content (and the closer) are not emitted.
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOD_BODY: &str = "\
Add the `--pr-body` validate mode enforcing the mechanical PR conventions.

---

## What this accomplishes

Path-independent CI now catches malformed PR bodies.

Fixes #221
";

    fn messages(findings: &[PrBodyFinding]) -> String {
        findings
            .iter()
            .map(|f| f.message.clone())
            .collect::<Vec<_>>()
            .join("\n")
    }

    #[test]
    fn well_formed_pr_passes() {
        let findings = check_pr_body(GOOD_BODY, Some("feat(validate): add --pr-body mode"));
        assert!(findings.is_empty(), "expected clean, got: {:?}", findings);
    }

    #[test]
    fn non_conventional_title_fails() {
        let findings = check_pr_body(GOOD_BODY, Some("Add the pr-body mode"));
        assert!(messages(&findings).contains("not Conventional Commits"));
    }

    #[test]
    fn unknown_type_fails() {
        let findings = check_pr_body(GOOD_BODY, Some("feet: add a mode"));
        assert!(messages(&findings).contains("not Conventional Commits"));
    }

    #[test]
    fn revert_type_passes() {
        // `revert` is a Conventional Commits type; a PR that reverts an earlier
        // change titled `revert: ...` must pass PB1.
        let findings = check_pr_body(GOOD_BODY, Some("revert: undo the pr-body mode"));
        assert!(findings.is_empty(), "expected clean, got: {:?}", findings);
    }

    #[test]
    fn issue_number_scope_fails() {
        for title in ["docs(issue-8): update", "chore(#8): update", "fix(8): update"] {
            let findings = check_pr_body(GOOD_BODY, Some(title));
            assert!(
                messages(&findings).contains("issue-number scope"),
                "expected issue-number rejection for {:?}",
                title
            );
        }
    }

    #[test]
    fn word_scope_and_breaking_change_pass() {
        for title in [
            "feat(validate): add mode",
            "feat(issue-tracker): add mode",
            "feat(issues): add mode",
            "feat!: breaking change",
            "feat(api)!: breaking change",
        ] {
            let findings = check_pr_body(GOOD_BODY, Some(title));
            assert!(
                findings.is_empty(),
                "expected {:?} to pass, got: {:?}",
                title,
                findings
            );
        }
    }

    #[test]
    fn missing_separator_fails() {
        let body = "A one-part body with no separator at all.\n\nFixes #1\n";
        let findings = check_pr_body(body, Some("fix: thing"));
        assert!(messages(&findings).contains("no `---` separator"));
    }

    #[test]
    fn more_than_one_separator_fails() {
        let body = "Part 1.\n\n---\n\nPart 2.\n\n---\n\nStray third block.\n";
        let findings = check_pr_body(body, Some("fix: thing"));
        assert!(messages(&findings).contains("exactly one"));
    }

    #[test]
    fn empty_part1_fails() {
        let body = "\n\n---\n\nPart 2 only, Part 1 is blank.\n";
        let findings = check_pr_body(body, Some("fix: thing"));
        assert!(messages(&findings).contains("Part 1"));
    }

    #[test]
    fn attribution_footer_fails() {
        let coauthor = "Real change.\n\n---\n\nContext.\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n";
        assert!(messages(&check_pr_body(coauthor, Some("fix: thing")))
            .contains("AI-attribution"));

        let generated = "Real change.\n\n---\n\nContext.\n\n\u{1f916} Generated with Claude Code\n";
        assert!(messages(&check_pr_body(generated, Some("fix: thing")))
            .contains("AI-attribution"));
    }

    #[test]
    fn docs_only_minimal_part2_passes() {
        let body = "Fix a typo in the installation guide.\n\n---\n\nFixes #42\n";
        let findings = check_pr_body(body, Some("docs: fix a typo in the install guide"));
        assert!(findings.is_empty(), "expected clean, got: {:?}", findings);
    }

    #[test]
    fn separator_and_footer_inside_fence_pass() {
        // A body whose Part 2 shows a `---` and a Co-Authored-By line inside a
        // fenced example must not trip PB2 (double separator) or PB3.
        let body = "\
Explain the two-part body format.

---

## Example

```text
Part 1 text.

---

Part 2 text.

Co-Authored-By: Claude <noreply@anthropic.com>
```

Fixes #7
";
        let findings = check_pr_body(body, Some("docs: explain the two-part body format"));
        assert!(
            findings.is_empty(),
            "fenced --- and footer should be ignored, got: {:?}",
            findings
        );
    }

    #[test]
    fn tilde_fence_and_mixed_markers() {
        // A ~~~ fence containing a ``` line and a --- must be fully skipped.
        let body = "\
Body.

---

~~~
```
---
~~~

Fixes #9
";
        let findings = check_pr_body(body, Some("docs: thing"));
        assert!(findings.is_empty(), "got: {:?}", findings);
    }

    #[test]
    fn title_none_skips_title_check() {
        // With no title, only body-level rules run; a bad "title" cannot fail
        // because it is not supplied.
        let findings = check_pr_body(GOOD_BODY, None);
        assert!(findings.is_empty(), "got: {:?}", findings);
        // But body rules still apply.
        let bad = check_pr_body("no separator here\n", None);
        assert!(messages(&bad).contains("no `---` separator"));
    }

    #[test]
    fn heading_structured_part1_fails() {
        // Part 1 written as markdown sections (ATX `##` headings) is not a
        // clean commit body. It is mechanically conformant otherwise (one
        // `---`, non-empty Part 1, Conventional title, no AI footer), so only
        // PB4 catches it.
        let body = "\
## Root cause

The reaper reclaimed an instance a live session was rooted in.

## Fix

Skip reclamation when a session is rooted in the instance.

---

## What this fixes

Prevents a live session's instance from being reaped.

Fixes #190
";
        let findings = check_pr_body(body, Some("fix(reap): never reclaim a rooted instance"));
        assert!(
            messages(&findings).contains("section heading"),
            "expected a PB4 heading rejection, got: {:?}",
            findings
        );
    }

    #[test]
    fn pr_190_regression_single_hash_and_atx_levels() {
        // A Part 1 with a single `#` (h1) or a deeper `###` heading is rejected
        // the same way; the level does not matter.
        for part1 in ["# Summary\n\nText.", "### Detail\n\nText."] {
            let body = format!("{}\n\n---\n\nFixes #1\n", part1);
            let findings = check_pr_body(&body, Some("fix: thing"));
            assert!(
                messages(&findings).contains("section heading"),
                "expected heading rejection for Part 1 {:?}, got: {:?}",
                part1,
                findings
            );
        }
    }

    #[test]
    fn prose_part1_with_fenced_heading_passes() {
        // A `##` shown inside a fenced example in Part 1 is not a real heading
        // and must not trip PB4 (mirrors the PB2/PB3 fence-stripping behavior).
        let body = "\
Rework the reaper so a rooted instance is never reclaimed.

An example of the shape we reject looks like:

```md
## Root cause
## Fix
```

---

Fixes #190
";
        let findings = check_pr_body(body, Some("fix(reap): never reclaim a rooted instance"));
        assert!(
            findings.is_empty(),
            "fenced heading in Part 1 should be ignored, got: {:?}",
            findings
        );
    }

    #[test]
    fn part2_headings_still_pass() {
        // Part 2 (below the `---`) may use `## Section` headings freely; PB4 is
        // scoped to Part 1 only. GOOD_BODY already exercises this, but assert it
        // explicitly with several Part 2 headings.
        let body = "\
Prose Part 1 describing the change in plain sentences.

---

## What this fixes

Text.

## Test plan

Text.

Fixes #7
";
        let findings = check_pr_body(body, Some("fix: thing"));
        assert!(
            findings.is_empty(),
            "Part 2 headings must pass, got: {:?}",
            findings
        );
    }

    #[test]
    fn one_line_prose_part1_passes() {
        // The minimal well-formed shape — a one-line prose Part 1, one `---`,
        // and a Part 2 that is only `Fixes #N` — must keep passing.
        let body = "Fix a typo in the installation guide.\n\n---\n\nFixes #42\n";
        let findings = check_pr_body(body, Some("docs: fix a typo in the install guide"));
        assert!(findings.is_empty(), "expected clean, got: {:?}", findings);
    }

    #[test]
    fn hash_prefixed_prose_lines_are_not_headings() {
        // A `#` that is not an ATX heading — an issue reference (`#123`), a
        // shebang, a C preprocessor line, or a `#` run of seven or more — must
        // not trip PB4 when it appears in a prose Part 1.
        for part1 in [
            "Resolves the crash reported in #123 during startup.",
            "The recipe now emits `#!/bin/sh` at the top of the wrapper.",
            "Guard the header with `#include <stdio.h>` as documented.",
            "The banner uses ####### as a divider, not a heading.",
        ] {
            let body = format!("{}\n\n---\n\nFixes #1\n", part1);
            let findings = check_pr_body(&body, Some("fix: thing"));
            assert!(
                findings.is_empty(),
                "expected {:?} to pass PB4, got: {:?}",
                part1,
                findings
            );
        }
    }
}
