---
name: work-on
description: Implement a GitHub issue end-to-end: branch creation, analysis, coding, tests, and pull request with CI monitoring. Use when given an issue number, issue URL, milestone reference, or asked to work on, implement, fix, build, tackle, pick up, or close a specific issue. Automatically selects the next unblocked issue when given a milestone. Handles the full cycle from reading the issue to merging a passing PR.
argument-hint: '<issue_number | #issue | issue-url | M<milestone> | milestone-url | "Milestone Name">'
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

Your project's extension file (`.claude/shirabe-extensions/work-on.md`) defines additional label names and routing messages to use.

---

## Plan Mode

When `$ARGUMENTS` is a path to a PLAN.md file, the skill runs as a plan orchestrator rather than working on a single issue. Plan mode coordinates multiple per-issue child workflows and assembles a combined PR after all children complete.

### Mode Detection

When invoked as `/work-on <argument>`:

- If `$ARGUMENTS` begins with `-- plan-backed` — **plan-backed child mode** (highest priority; the plan orchestrator is spawning this as a per-issue child workflow)
- If the argument is a path matching `docs/plans/PLAN-*.md`, or any `.md` file whose frontmatter contains `schema: plan/v1` — **plan orchestrator mode**
- If the argument is an issue reference (`#N` or a GitHub issue URL) — **issue-backed mode**
- If the argument is a free-form task description — **free-form mode**

Plan-backed child mode is checked first. Plan orchestrator mode is checked before issue-backed mode.

### Plan-Backed Child Mode

When `$ARGUMENTS` begins with `-- plan-backed`, extract these variables from the remaining arguments:
- `ISSUE_SOURCE`: `github` or `plan_outline`
- `ISSUE_NUMBER`: GitHub issue number (github source only)
- `ARTIFACT_PREFIX`: workflow name for this child
- `PLAN_DOC`: path to the parent PLAN document

Submit entry evidence: `{"mode": "plan_backed", "issue_source": "<source>", "issue_number": "<N>"}`.

For `ISSUE_SOURCE=github`: read the GitHub issue with `gh issue view <ISSUE_NUMBER>` during the `plan_context_injection` state to get the issue title, body, and labels. Then proceed directly to `setup_plan_backed` → `analysis`.
For `ISSUE_SOURCE=plan_outline`: extract the outline from the PLAN doc during `plan_context_injection`. Then route through `plan_validation` → `setup_plan_backed` → `analysis`.

Skip staleness checks in plan-backed mode.

If the koto scheduler marks this child as skipped due to a failed dependency (`failure_policy: skip_dependents`), the workflow enters with `mode: skipped`. Submit entry evidence `{"mode": "skipped"}` and enter the execution loop — koto routes directly to the `skipped_due_to_dep_failure` terminal state, which carries `skipped_marker: true`. Do not perform any implementation work.

### Initialization

Derive the plan slug from the filename: `PLAN-foo-bar.md` → `plan-foo-bar`.

```bash
koto init <plan-slug> \
  --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on-plan.md \
  --var PLAN_DOC=<path-to-plan>
```

### First Tick: Submitting Tasks

On the first tick, run `plan-to-tasks.sh` (owned by the `/plan` skill) to generate a tasks JSON array from the PLAN doc, then pipe it to koto:

```bash
# mktemp sandwich — handles large outputs safely
TMP=$(mktemp)
TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})
echo "{\"tasks\": $TASKS}" > "$TMP"
koto next <plan-slug> --with-data @"$TMP"
rm -f "$TMP"
```

The script outputs a JSON array of `{name, vars, waits_on}` objects. Wrap it in `{"tasks": [...]}` before submitting — the `spawn_and_await` state expects the array under the `tasks` field. koto materializes one child workflow per task, using `work-on.md` as the default template with `failure_policy: skip_dependents`.

### Monitoring Children (spawn_and_await)

After submitting tasks, the workflow enters `spawn_and_await`. Monitor child progress via `koto workflows`. When all children reach terminal states, inspect their outcomes and submit:

- `batch_outcome: all_success` — all children completed without failure; routes to `pr_coordination`
- `batch_outcome: needs_attention` — one or more children reached `done_blocked` or were skipped; routes to `escalate`

### Cross-Issue Context Assembly

After each child completes and before dispatching the next, run the context assembly step in `references/cross-issue-context.md`.

### Escalation Handling

When the parent workflow reaches `escalate` state, one or more children reached `done_blocked` or were skipped due to dependency failure:

1. Read per-child data: `koto context get <plan-slug> batch_final_view`
2. Identify failed children (`outcome: failure`, `reason` field, `reason_source`) and skipped children (`outcome: skipped`, `skipped_because_chain`)
3. Write a `failure_reason` summary covering which children failed, why, and what the user should do
4. Submit: `koto next <plan-slug> --with-data '{"failure_reason": "<summary>"}'`

The `failure_reason` field is required — omitting it prevents `context_assignments` from propagating the reason downstream.

### PR Description (pr_coordination)

In `pr_coordination` state, read `batch_final_view` and assemble a PR description table. For each child include: `name`, `outcome`, `reason` (if failed or skipped), `reason_source`, and `skipped_because_chain` (if skipped). Update the PR with `gh pr edit`.

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
koto init <WF> --template ${CLAUDE_SKILL_DIR}/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N>
```

**Free-form mode:**
```bash
koto init <WF> --template ${CLAUDE_SKILL_DIR}/koto-templates/work-on.md \
  --var ARTIFACT_PREFIX=task_<slug>
```

**Plan-backed mode** uses free-form init. Extract the goal and acceptance criteria from the
PLAN doc and provide them as the task description in the entry evidence.

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
