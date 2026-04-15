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

**Milestone inputs**: `M3`, `M#3`, milestone URL, or `"Milestone Name"` - list open issues in the milestone and select the first unblocked one (an issue is blocked if its Dependencies section references open issues). If multiple unblocked issues exist, pick the one with lowest number. If no unblocked issues exist, report which issues are blocked and stop.

### Handling `needs-triage` Issues

If the selected issue has a `needs-triage` label, the issue needs classification before implementation. Check your project's label vocabulary (defined in `## Label Vocabulary` in CLAUDE.md) for the routing options available. If your project's extension file defines a triage workflow, invoke it now. Otherwise, ask the user whether to proceed directly or reclassify the issue.

### Handling Blocking Labels

After resolving the issue and reading it with `gh issue view`, check for blocking labels before proceeding. Your project's label vocabulary is defined in `## Label Vocabulary` in CLAUDE.md.

If the issue has any label indicating it is not yet ready for implementation (such as labels requiring design, requirements definition, or feasibility investigation), display the appropriate routing message and **stop execution**.

If the issue has a label indicating it tracks a child artifact whose implementation is underway, stop and direct the user to work on the child artifact instead.

Your project's extension file (`.claude/shirabe-extensions/work-on.md`) defines the specific label names and routing messages to use.

---

## Plan Mode

When `$ARGUMENTS` is a path to a PLAN.md file, the skill runs as a plan orchestrator rather than working on a single issue. Plan mode coordinates multiple per-issue child workflows and assembles a combined PR after all children complete.

### Mode Detection

When invoked as `/work-on <argument>`:

- If the argument is a path matching `docs/plans/PLAN-*.md`, or any `.md` file whose frontmatter contains `schema: plan/v1` — **plan mode**
- If the argument is an issue reference (`#N` or a GitHub issue URL) — **issue-backed mode**
- If the argument is a free-form task description — **free-form mode**

Plan mode detection takes priority: check for a PLAN.md path before checking for an issue number.

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
${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}} > "$TMP"
koto next <plan-slug> --with-data @"$TMP"
rm -f "$TMP"
```

The script outputs a JSON array of `{name, vars, waits_on}` objects. koto materializes one child workflow per task, using `work-on.md` as the default template with `failure_policy: skip_dependents`.

### Cross-Issue Context Assembly

Read `references/shared/cross-issue-context.md` for details.

### Escalation Handling

When the parent workflow reaches `escalate` state, one or more children reached `done_blocked` or were skipped due to dependency failure:

1. Read per-child data: `koto context get <plan-slug> batch_final_view`
2. Identify failed children (`outcome: failure`, `reason` field) and skipped children (`outcome: skipped`, `skipped_because_chain`)
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

Read `references/shared/review-panel-orchestration.md` for details.

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
issue number, read the issue with `gh issue view <issue-number>`. Check for blocking
labels as defined in your project's label vocabulary (CLAUDE.md `## Label Vocabulary`)
and stop if any are present.

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
proceeds with generic behavior: no language-specific quality checks, no label blocking
(blocking label check is skipped if no label vocabulary is defined in CLAUDE.md).
