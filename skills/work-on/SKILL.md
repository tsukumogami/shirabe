---
name: work-on
description: Implement work end-to-end with branch creation, analysis, coding, tests, and a pull request with CI monitoring. Accepts a GitHub issue (number or URL), a milestone (selects the next unblocked issue), a PLAN document path (drives multiple issues through one shared branch and PR), or a free-form task description. Use when asked to work on, implement, fix, build, tackle, pick up, close, or ship work — at any size, from a single issue to a whole plan.
argument-hint: '<issue_number | #issue | issue-url | M<milestone> | milestone-url | "Milestone Name" | docs/plans/PLAN-*.md | "task description">'
---
@.claude/shirabe-extensions/work-on.md
@.claude/shirabe-extensions/work-on.local.md

# Feature Development Workflow

Your goal is to work on a GitHub issue and deliver a high-quality, well-tested pull request.

## Input Resolution

The input `$ARGUMENTS` can be an issue reference or a milestone reference.

**Issue inputs**: `71`, `#71`, or issue URL - resolve directly to the issue number.

**Milestone inputs**: `M3`, `M#3`, milestone URL, or `"Milestone Name"` - list open issues in the milestone and select the first unblocked one (an issue is blocked if its Dependencies section references open issues). If multiple unblocked issues exist, pick the one with lowest number. Report to the user which issue was selected and why (e.g., "Selected issue #N — lowest-numbered unblocked issue in milestone M3"). If no unblocked issues exist, report which issues are blocked and stop.

### Handling `needs-triage` Issues

If the selected issue has a `needs-triage` label, the issue needs classification before implementation. Read CLAUDE.md and check its `## Label Vocabulary` section for the routing options available. If your project's extension file defines a triage workflow, invoke it now. Otherwise, ask the user whether to proceed directly or reclassify the issue.

### Handling Blocking Labels

After resolving the issue and reading it with `gh issue view`, check for blocking labels before proceeding.

The label `needs-design` is universally recognized: if an issue carries it, stop immediately and inform the user that a design document is required before implementation can begin. This check applies even if no project label vocabulary is defined.

Other blocking labels (requiring design, requirements definition, or feasibility investigation) are defined in your project's label vocabulary (`## Label Vocabulary` in CLAUDE.md). If the issue has any such label, display the appropriate routing message and **stop execution**.

If the issue has a label indicating it tracks a child artifact whose implementation is underway, stop and direct the user to work on the child artifact instead.

Your project's extension file (`.claude/shirabe-extensions/work-on.md`) defines additional label names and routing messages to use. It also declares the project's **verification map** that the definition-of-done gate reads — see `references/verification-map.md` for the schema (path-glob to verification command(s), an optional default test command, fail-closed on cannot-verify).

---

## Definition of Done

Before an issue can finalize, the `verification` state runs a definition-of-done gate.
Done is verified by execution, not by the presence of a verification artifact. A
verification command that exists but was not run does not count — the gate runs the
command and requires a passing result.

The gate reads the project's **verification map** from the extension file
(`.claude/shirabe-extensions/work-on.md`). The map's schema — path-globs bound to
command(s), an optional default test command, and the fail-closed contract — is defined
in `references/verification-map.md`. Read that reference for the schema; this section
does not restate it. The map's commands are the project's own; never derive a command
from issue text or any other untrusted input.

Run the gate as follows:

1. **Classify the diff.** Take the issue branch's changed files (`git diff` against the
   base) and match each against the map's path-globs. Matches are additive: a file
   matching several entries runs each matched entry's command(s).
2. **Run the matched commands.** Run every command bound to a matched entry and require
   each to pass.
3. **Fall through to the default.** When no map entry matches the changed files, run the
   project's default test command declared in the extension.
4. **Announce what ran.** State which commands the gate selected and ran, and each one's
   pass/fail result. The announcement names the commands explicitly so the operator can
   see what "done" was checked against.

Outcomes:

- **Passed** — every selected command ran and passed. The workflow advances to
  finalization.
- **Failed** — a command ran and did not pass. The workflow returns to implementation to
  fix the failure; a failing verification never advances toward a clean finalization.
- **Cannot-verify** — no map entry matched and no usable default exists, or a selected
  command could not run. This **fails closed**: it must never read as "verified" and
  never silently advances. It halts as a blocking condition that surfaces to the human.

The gate carries no project-specific commands. Those live only in the project's
extension file; this skill holds the discipline, not the commands.

### Finalization and No Silent Deferral

After verification passes, the `finalization` state assembles the summary and decides
whether the issue is done. `/work-on` cannot self-report an issue done with an unmet or
deferred acceptance criterion (R4, R5). The clean `deferred_items_noted` terminal that
once let the agent ship a unilateral deferral is removed.

`ready_for_pr` is only reachable after verification ran and passed — finalization is
reached only via `verification_outcome: passed`, so a finalization that reports done is
backed by run verification evidence, not by the mere presence of a verification artifact.

When an acceptance criterion is unmet, finalization reports `deferral_requested`, which
routes to the blocking `deferral_approval` human gate. The human makes an explicit
decision:

- **Approved** — the deferral is recorded as the human's decision via
  `koto decisions record` and surfaced in the PR body, so the audit trail shows what was
  deferred and on whose authority. The workflow then proceeds to PR creation.
- **Rejected** — the issue is not done. The workflow routes to `done_blocked`, a
  non-clean terminal, rather than shipping with the criterion silently unmet.

A finalization-checklist item disallows unapproved caveat or hedge language
("experimental", "not yet handled", "known limitation") in the issue's shipped
artifacts. A caveat is legitimate only where it records an approved deferral (R6). This
is enforced by the deferral gate plus the checklist — no approval means no caveat — not
by a brittle word-grep that would flag legitimate uses of those words.

## Plan Input (Dispatcher)

When `$ARGUMENTS` is a path to a PLAN.md file, `/work-on` acts as a thin dispatcher
on the PLAN's `execution_mode`. `/work-on` no longer orchestrates a whole plan:
plan-level execution (single-pr and coordinated) is owned by `/execute`, which
delegates each single issue back to `/work-on`'s Plan-Backed Child Mode below.

Read `execution_mode` from the PLAN frontmatter and **re-validate it against the
closed set `{single-pr, multi-pr, coordinated}` before using it in any path or
branch interpolation** (an out-of-set value halts with a clear error). Then route:

- **`single-pr` or `coordinated`** — hand off to `/execute`. `/work-on` does not run
  these directly; direct the caller to invoke `/execute <PLAN>` (the
  implementation-altitude coordinator that owns plan-level execution and its
  ephemeral home). When `/execute` is already driving the plan, it spawns `/work-on`
  per issue via Plan-Backed Child Mode.
- **`multi-pr`** — run in place, one issue at a time. Select the next unblocked issue
  from the PLAN (an issue is blocked while its Dependencies reference open issues) and
  run it as a single issue-backed unit against the repo-persisted PLAN, each landing
  its own PR. There is no shared branch and no cross-issue carry-forward — multi-pr
  issues are independent, per the DESIGN's ephemeral-home model.

### Mode Detection

When invoked as `/work-on <argument>`:

- If `$ARGUMENTS` begins with `-- plan-backed` — **plan-backed child mode** (highest priority; the plan-level coordinator /execute is spawning this as a per-issue child workflow)
- If the argument is a path matching `docs/plans/PLAN-*.md`, or any `.md` file whose frontmatter contains `schema: plan/v1` — **plan dispatcher mode** (see Plan Input above)
- If the argument is an issue reference (`#N` or a GitHub issue URL) — **issue-backed mode**
- If the argument is a free-form task description — **free-form mode**

Plan-backed child mode is checked first. Plan dispatcher mode is checked before issue-backed mode.

### Plan-Backed Child Mode

When `$ARGUMENTS` begins with `-- plan-backed`, extract these variables from the remaining arguments:
- `ISSUE_SOURCE`: `github` or `plan_outline`
- `ISSUE_NUMBER`: GitHub issue number (github source only)
- `ARTIFACT_PREFIX`: workflow name for this child
- `PLAN_DOC`: path to the parent PLAN document
- `ISSUE_TYPE`: issue type hint (`code`, `docs`, or `task`) from the PLAN outline's `**Type**:` field

Submit entry evidence: `{"mode": "plan_backed", "issue_source": "<source>", "issue_number": "<N>"}`.

For `ISSUE_SOURCE=github`: read the GitHub issue with `gh issue view <ISSUE_NUMBER>` during the `plan_context_injection` state to get the issue title, body, and labels. Then proceed directly to `setup_plan_backed` → `analysis`.
For `ISSUE_SOURCE=plan_outline`: extract the outline from the PLAN doc during `plan_context_injection`. Then route through `plan_validation` → `setup_plan_backed` → `analysis`.

Skip staleness checks in plan-backed mode.

When the orchestrator provides a `SHARED_BRANCH` variable, do not create a new branch. In `setup_plan_backed`, submit `status: override` and commit directly to `SHARED_BRANCH`. All child workflows in the batch share this branch and the same draft PR.

**PR creation for plan-backed children**: when `SHARED_BRANCH` is set, the orchestrator owns the PR. At the `pr_creation` state, submit `pr_status: shared` — skip PR creation and route directly to `done`. The orchestrator's `pr_finalization` state updates the shared PR after all children complete.

**Issue type classification**: the orchestrator passes `ISSUE_TYPE` as a hint from the PLAN outline's `**Type**:` field. During `analysis`, the analysis agent confirms or overrides this value based on what the work actually entails, then includes `issue_type` in its evidence. During `implementation`, the agent re-submits the confirmed `issue_type` to route post-implementation:
- `code` (default) — proceeds through scrutiny → review → qa_validation
- `docs` — skips panels, goes directly to finalization
- `task` — skips panels, goes directly to finalization

When `ISSUE_TYPE` is not passed (standalone issue-backed or free-form mode), omitting `issue_type` from evidence defaults to `code` behavior.

If the koto scheduler marks this child as skipped due to a failed dependency (`failure_policy: skip_dependents`), the workflow enters with `mode: skipped`. Submit entry evidence `{"mode": "skipped"}` and enter the execution loop — koto routes directly to the `skipped_due_to_dep_failure` terminal state, which carries `skipped_marker: true`. Do not perform any implementation work.

The plan-level orchestrator — shared branch and draft PR, child spawning, cross-issue context assembly, escalation, PR finalization, and the completion cascade — now lives in `/execute` (`skills/execute/`). `/work-on` keeps only Plan-Backed Child Mode above, by which `/execute` delegates each single issue back to it.

---

You are assigned to work on the resolved issue. The issue number determined above replaces `<N>` throughout this workflow. The workflow name `<WF>` is the ARTIFACT_PREFIX value: `issue_<N>` for issue-backed, `task_<slug>` for free-form.

## Koto Orchestration

### Prerequisites

Run `koto version` to verify koto >= 0.3.3 is installed. If missing:

```bash
curl -fsSL https://raw.githubusercontent.com/tsukumogami/koto/main/install.sh | bash
```

### Initialize

**Issue-backed mode:**
```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N>
```

**Free-form mode:**
```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ARTIFACT_PREFIX=task_<slug>
```

**Plan-backed mode** uses free-form init. Extract the goal and acceptance criteria from the
PLAN doc and provide them as the task description in the entry evidence.

### Branch Setup

Branch creation is conditional. Before creating a new branch in any setup state, check whether you already have an appropriate working branch:

- **User instruction**: if the user asked you to continue on the current branch, submit `status: override` in the setup state
- **Plan-backed mode**: if `SHARED_BRANCH` is set, the orchestrator has already created the branch — commit directly to it with `status: override`
- **Resuming work**: if already on a feature branch from a previous session on this issue, `status: override` is correct

Only create a new branch when none of the above apply. The setup states (`setup_issue_backed`, `setup_free_form`, `setup_plan_backed`) all accept `status: override` for these cases.

### Execution Loop

Repeat:

1. Run `koto next <WF>`
2. If `action: "execute"` with `advanced: true` — run `koto next <WF>` again
3. If `action: "execute"` with `expects` — do the work described in `directive`,
   read any phase file it references, then submit evidence:
   ```bash
   koto next <WF> --with-data '{"field_name": "value", ...}'
   ```
   Provide the fields listed in `expects`. Check `expects.options` for valid values.
4. If `action: "done"` — report the outcome and stop.

**Errors:** exit 1 = gate failed (fix and retry), exit 2 = bad evidence (check `expects`).
Use `koto rewind <WF>` to step back.

### Review Panel

Read `references/review-panel-orchestration.md` for details (panel states: `scrutiny`, `review`, `qa_validation` — require parallel spawns, not standard directive execution).

### Resume

1. `koto workflows` — find the active workflow name
2. If found, `koto next <WF>`
3. If none, `koto init` fresh

Phase 0 detection: if the parent-chain sentinel is present in
`wip/scope_<topic>_state.md` (tactical) or `wip/charter_<topic>_state.md`
(strategic), see `references/fixes/sub-agent-dispatch.md` for the
fallback shape that applies. Behavior under direct invocation is
unchanged when the sentinel is absent. (Per R9, /work-on does not
add a Resume Logic row -- the sentinel detection is scoped to the
seven authoring children.)

### Decision Capture

During analysis and implementation, record non-obvious decisions:

```bash
koto decisions record <WF> --with-data '{"choice": "...", "rationale": "...", "alternatives_considered": ["..."]}'
```

## Output

A merged PR with passing CI, referenced back to the source issue.

## Begin

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). In --auto
mode, follow `references/decision-protocol.md` at decision points (W1, W2).
Safety gates (W3, W4) remain blocking in both modes. Use
`koto decisions record <WF>` to capture any decisions made.

First, resolve the input using the Input Resolution section above. Once you have an
issue number, read the issue with `gh issue view <issue-number>`. Apply the Handling
Blocking Labels rules (including `needs-design` universal check) and stop if any
blocking label is present.

Detect repo visibility from CLAUDE.md (`## Repo Visibility: Public|Private`). If not
found, infer from repo path (`private/` -> Private, `public/` -> Public; default to
Private). Load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

If your project's extension file defines a language skill or PR creation skill, invoke
those for project-specific quality and PR requirements.

Then:
1. `koto workflows` — if an active workflow matches this issue, resume with `koto next <WF>`.
2. Otherwise, `koto init` with the template path and appropriate variables.
3. Submit entry evidence:
   - Issue-backed: `koto next <WF> --with-data '{"mode": "issue_backed", "issue_number": "<N>"}'`
   - Free-form: `koto next <WF> --with-data '{"mode": "free_form", "task_description": "..."}'`
4. Enter the execution loop.

If no extension file exists at `.claude/shirabe-extensions/work-on.md`, the skill
proceeds with generic behavior: no language-specific quality checks. The `needs-design`
blocking label is still enforced regardless.
