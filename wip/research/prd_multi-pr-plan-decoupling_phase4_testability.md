# Verdict: FAIL

## Factual claims (all verified true against the current tree)

1. **`execution_mode` enum and location.** `skills/plan/scripts/plan-to-tasks.sh:1209-1224` switches on `single-pr | multi-pr | coordinated` and dies on anything else; `skills/execute/SKILL.md:45,669`, `skills/work-on/SKILL.md:113`, `skills/plan/references/plan-to-tasks-contract.md:101,109`, and `references/coordination-strategy.md:42-43` all confirm the closed three-value set, held in PLAN frontmatter (`skills/plan/references/plan-format.md:27`). Note: `skills/plan/references/plan-format.md:40` itself is stale ("one of `single-pr` or `multi-pr`", omitting `coordinated`) — not a PRD error, but worth flagging to the author since a design/plan reader who opens that specific line will be misled independent of this PRD.
2. **Validator posture-class mechanism.** Confirmed live and general-purpose, not lifecycle-only. `crates/shirabe/src/main.rs:566-580` resolves `posture` once from `--mode` (`PostureMode::Draft`/`Ready`), and `crates/shirabe/src/main.rs:741` (`if !is_notice(&ve, posture) { worst = worst.merge(ValidateOutcome::Violations); }`) applies that posture to every per-file finding on the plain `shirabe validate <file>` path, not only `--lifecycle`/`--lifecycle-chain`. `docs/guides/lifecycle-posture.md:41-49` documents `--mode=draft|ready`. R19's plan to hang R8/R10 off this mechanism is realistic.
3. **`plan-to-tasks.sh` keys multi-pr work items on `#N`.** `skills/plan/scripts/plan-to-tasks.sh:245` (`local re_issue_num="#([0-9]+)"`) and the surrounding `process_multi_pr` table walk (lines ~264-300) extract the issue number as the row's identity from the Implementation Issues table. Confirmed.
4. **Reviewability ceiling has no concrete value anywhere.** `CLAUDE.md:59-69` ("Reviewability Ceiling: default ... `default` defers to the ceiling defined in `references/coordination-strategy.md`") points at `references/coordination-strategy.md:134`, which only repeats "the configured reviewability ceiling" with no number, unit, or formula anywhere in that file. The chain is circular and terminates in nothing. Confirmed.

Also spot-checked and confirmed: the workflow-principles/coordination-strategy contradiction the Problem Statement and R11/AC12 depend on is real — `references/workflow-principles.md:15-16` permits splitting only for "a hard constraint or genuine incremental value," while `references/coordination-strategy.md:134` and `docs/guides/coordinated-multi-repo.md:86` list "a single PR would exceed the configured reviewability ceiling" as a third, distinct trigger.

## Per-criterion findings

- **AC1 ("fewest pull requests" + no-constraint change → `single-pr`) — DISCRIMINABILITY FAILURE.** Per the Goals section and AC4, the *current* default behavior for a no-constraint, no-incremental-value change is already `single-pr` (the governing principle's own default). So AC1's expected output is identical to what an implementation that silently ignores the new preference-resolution machinery would also produce. A build where R1's `flag > CLAUDE.md-header > default` resolution is entirely broken or not wired in passes this criterion. It does not discriminate feature-present from feature-absent. Contrast with AC3, which forces a *different* outcome (non-single-pr) for the same input change under a different declared preference — AC3 is discriminating; AC1 is not, as currently worded. Fix: either drop AC1 (its only content — "explicit default preference matches current default" — is a corollary of AC4, not new coverage) or rewrite it to assert something only a working implementation produces, e.g. that the resolved preference is visibly recorded/traceable even when it doesn't change the outcome.

- **AC2 (forcing-constraint change → non-single-pr, R8 names the constraint) — checkable but underspecified.** Procedure is nameable (run `/plan` against a fixture change with a real forcing constraint, inspect the resulting PLAN frontmatter) once the field name from R8 is fixed by the design doc. The PRD never gives that field's name (R18 deliberately leaves it as "free text naming its branch" but doesn't name the *key*), so the criterion is checkable only in conjunction with a downstream artifact this PRD doesn't own. Acceptable at PRD altitude but should be flagged so the design doc is required to fix the key name before this AC is executable.

- **AC3 (reviewability preference + no-constraint change → non-single-pr, R8 names the preference not a fabricated value claim) — discriminating, checkable.** No issue.

- **AC4 (no preference stated → current behavior unchanged) — checkable, discriminating by construction** (it's the regression-safety criterion). No issue.

- **AC5 ("no issues" + multi-PR → no issues/milestone, "work items remain readable from the document") — half vague.** The no-issues/no-milestone half is mechanically checkable (`gh issue list`, `gh api .../milestones` against the test repo, or absence of any `gh issue create` calls in a dry-run trace). "The plan's work items remain readable from the document" names no procedure: readable by what test? Compare against R14/AC10, which already state the concrete, checkable form of this same requirement (a schedulable dependency graph with no unresolved work-item keys). As worded, "remain readable" invites subjective judgment, which the rubric and the PRD's own Acceptance Criteria quality guidance ("binary pass/fail — no subjective judgment") both rule out. Fix: delete the readability clause from AC5 (AC10 already owns it) or replace it with the same concrete test AC10 uses.

- **AC6 ("issues" + single-PR → issues filed) — discriminating, checkable.** No issue.

- **AC7 (coordinated unaffected by tracking preference) — checkable but should name the comparison.** "Unaffected... in all of the above" is verifiable only by re-running the coordinated path under both tracking-preference values and diffing the result; the AC doesn't say diffing is the procedure, but a reader can infer it. Minor — acceptable.

- **AC8/AC9 (validator notice-in-draft/error-in-ready for missing R8 on non-single-pr; no finding on single-pr) — discriminating, checkable, confirmed against the real `--mode` mechanism** (see factual claim 2 above). No issue.

- **AC10 (multi-PR plan with no issues yields a schedulable graph with no unresolved keys) — discriminating, checkable.** No issue.

- **AC11 (approval gate keyed on GitHub-artifact creation, not PR count) — checkable in principle**, but the PRD never states what "human approval" vs. "automatic" is observed as (a prompt? an exit code? a state-file field?). Without that, "requires human approval" isn't independently verifiable by a developer who didn't write the PRD. Minor gap — should point at the existing approval-gate surface (R13 implies one exists today) so the AC inherits a concrete observable.

- **AC12 (workflow-principles and coordination-strategy agree in prose) — checkable via diff/grep**, confirmed the current disagreement is real (see factual claims). No issue.

- **AC13 (both headers documented with values/default/precedence) — checkable**, plain doc-presence check. No issue.

## Requirement coverage (R1-R19)

Traced against the 13 acceptance criteria:

- R1 (precedence order `flag > CLAUDE.md-header > default`) — **not covered**. No AC exercises the precedence itself (e.g., a flag overriding a conflicting CLAUDE.md header). AC1/AC3/AC4 only test header-vs-default, never flag-vs-header.
- R2 (two values, default = fewest) — covered by AC1/AC4 (weakened by AC1's discriminability problem above).
- R3 (must not be named "Execution Mode") — **not covered by any AC.** AC13 checks that headers are documented but not that the name avoids the collision R3 calls out. This is a static/naming constraint the AC set never touches.
- R4 (tracking preference resolved independently) — covered by AC5+AC6 jointly.
- R5 (all four {PR count}×{tracking} combinations reachable) — **partially covered.** AC5 and AC6 each demonstrate one non-default combination; the other two (issues+multi-pr, no-issues+single-pr) are asserted as "today's behavior" in prose but no AC states them as reachable-by-declared-preference. Only 2 of 4 cells are actually exercised.
- R6 (tracking default = today's behavior) — **not covered.** AC4 covers this for delivery shape only; there is no tracking-preference analog ("repository declares no tracking preference → produces exactly today's issues-iff-multi-pr behavior").
- R7 (tracking preference excluded from coordinated) — covered by AC7.
- R8 (record why, naming the branch) — covered by AC2/AC3.
- R9 (single-pr exempt from R8) — covered by AC9.
- R10 (notice-in-draft/error-in-ready) — covered by AC8/AC9.
- R11 (principle amendment resolves contradiction) — covered by AC12.
- R12 (value-confirmation guard keeps running unchanged) — **not covered by any AC.** Nothing in the Acceptance Criteria exercises that the existing guard still fires against whatever unit the resolved preference defaults to, or that no preference creates an exemption from it.
- R13 (approval gate re-keyed to GitHub-artifact creation) — covered by AC11 (weakened by the missing observable, above).
- R14 (schedulable graph without issue-number keys) — covered by AC10.
- R15 (both preferences in canonical header reference) — covered by AC13.
- R16 (no new config channel; binds to CLAUDE.md headers) — implicitly covered (AC1/3/5/6 presumably exercise the header path) but no AC asserts the *absence* of a new channel. Weak but acceptable as a non-functional constraint the AC set can't cleanly test.
- R17 (unstated preference → identical behavior, no new prompts, no new required fields) — **partially covered.** AC4/AC9 cover the "no new required fields" and "identical execution_mode" halves; nothing covers "no new prompts."
- R18 (free text, not enumeration) — **not covered.** No AC checks that the R8 field accepts arbitrary text rather than a closed set; AC2/AC3 only check content, not the schema shape.
- R19 (implemented on existing posture-class mechanism) — implicitly covered by AC8/AC9's use of `--mode`.

## Required Changes

1. Rewrite or drop AC1 — as worded it passes vacuously against a broken/no-op implementation of R1's preference resolution (its expected output equals today's default, identical to AC4's scenario).
2. Replace AC5's "work items remain readable from the document" clause with a concrete, binary test, or delete it and rely on AC10 (which already states the checkable form of the same requirement).
3. Add an AC for R1's precedence order specifically (flag overrides CLAUDE.md header overrides default), not just header-vs-default.
4. Add an AC (or extend AC4) covering the tracking-preference default: a repository stating no tracking preference produces exactly today's issues-iff-multi-pr behavior — this is R6/part of R17 and currently has zero coverage.
5. Add an AC demonstrating all four {PR count}×{tracking} combinations are reachable via a stated preference, not just two of the four (R5 is stated as "all four" but only two are exercised).
6. Add an AC (or note as consciously untestable and move to Known Limitations) for R3 — that the new header's name doesn't collide with "Execution Mode" — and for R12 — that the value-confirmation guard still runs unchanged regardless of the resolved delivery preference.
7. AC11 should name the observable it means by "human approval" (a prompt, an exit code, a state-file field) so a developer who didn't write the PRD can verify it without guessing at a mechanism this PRD doesn't define.
