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

You are assigned to work on the resolved issue. The issue number determined above replaces `<N>` throughout this workflow.

## Koto Orchestration

This workflow is driven by koto, a state machine engine that tracks progress, enforces
phase ordering, and handles resume. You don't manage phase transitions or resume
detection — koto does that through gate checks and evidence submission.

### Prerequisites

This workflow requires koto >= 0.2.1. Run `koto version` to verify. If koto is not
installed, install it:

```bash
curl -fsSL https://raw.githubusercontent.com/tsukumogami/koto/main/install.sh | bash
```

### Initialize

For a **new workflow** (no active koto state), initialize with the appropriate variables.
`koto init` compiles the template on the fly — no separate compile step needed.

**Issue-backed mode** (GitHub issue number provided):
```bash
koto init work-on --template ${CLAUDE_SKILL_DIR}/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N>
```

**Free-form mode** (task description, no issue):
```bash
koto init work-on --template ${CLAUDE_SKILL_DIR}/koto-templates/work-on.md \
  --var ARTIFACT_PREFIX=task_<slug>
```

Where `<slug>` is a kebab-case summary of the task (e.g., `task_fix-login-timeout`).

**Plan-backed mode** uses free-form init. Extract the goal and acceptance criteria from the
PLAN doc and provide them as the task description in the entry evidence.

### The Execution Loop

After init (or when resuming), repeat this loop:

1. **Get the current directive:**
   ```bash
   koto next work-on
   ```
   This returns JSON with `action`, `state`, `directive`, and optionally `expects`.

2. **Check the action:**
   - `"execute"` with `advanced: true` — koto auto-advanced through a gate. The directive
     tells you what state you're in. Run `koto next work-on` again to continue advancing
     or get the next directive that needs your work.
   - `"execute"` with `advanced: false` and `expects` present — you need to do work. Read
     the directive, execute the corresponding phase guidance (see State-to-Phase Mapping),
     then submit evidence.
   - `"done"` — the workflow reached a terminal state. Report the outcome and stop.

3. **Submit evidence** when work is complete:
   ```bash
   koto next work-on --with-data '{"field_name": "value", ...}'
   ```
   The `expects` field in the previous response tells you which fields to provide, their
   types, and the valid values. Conditional transitions in `expects.options` show which
   evidence values route to which next state.

4. **Handle errors:**
   - Exit code 1 (transient): a gate check failed. Read the error, fix the issue, retry.
   - Exit code 2 (caller error): your evidence was invalid. Check `expects` and resubmit.
   - If stuck, use `koto rewind work-on` to step back one state.

### Resume

If the session was interrupted, koto picks up where you left off:

1. Check for active workflows: `koto workflows`
2. If `work-on` is active, run `koto next work-on` — gates auto-advance past completed
   work (file existence checks pass for artifacts already created).
3. If no workflow is active, start fresh with `koto init`.

### Decision Capture

During judgment states (analysis, implementation), capture non-obvious decisions using
`koto decisions record work-on`:

```bash
koto decisions record work-on --with-data '{"choice": "...", "rationale": "...", "alternatives_considered": ["..."]}'
```

This records the decision in the event log without triggering a state transition. List
captured decisions with `koto decisions list work-on`.

## State-to-Phase Mapping

Each koto state corresponds to a phase reference file with detailed agent guidance. When
`koto next` gives you a directive in a state that needs your work, read the corresponding
phase file for instructions.

| koto state | Phase | Reference file |
|------------|-------|---------------|
| `entry` | — | Submit mode evidence directly (see Koto Orchestration) |
| `context_injection` | 0 | `references/phases/phase-0-context-injection.md` |
| `task_validation` | — | Follow the directive (assess task scope and clarity) |
| `research` | — | Follow the directive (gather codebase context) |
| `post_research_validation` | — | Follow the directive (reassess task against findings) |
| `setup_issue_backed` | 1 | `references/phases/phase-1-setup.md` |
| `setup_free_form` | 1 | `references/phases/phase-1-setup.md` |
| `staleness_check` | 2 | `references/phases/phase-2-introspection.md` |
| `introspection` | 2 | `references/phases/phase-2-introspection.md` |
| `analysis` | 3 | `references/phases/phase-3-analysis.md` |
| `implementation` | 4 | `references/phases/phase-4-implementation.md` |
| `finalization` | 5 | `references/phases/phase-5-finalization.md` |
| `pr_creation` | 6 | `references/phases/phase-6-pr.md` |
| `ci_monitor` | 6 | `references/phases/phase-6-pr.md` |
| `done` | — | Report completion |
| `done_blocked` | — | Report blocker, suggest `koto rewind` to recover |
| `validation_exit` | — | Report verdict and suggest next steps |

States without a reference file have sufficient guidance in the template directive itself.
Read the directive from `koto next` and follow it.

## Output

A merged PR with passing CI, referenced back to the source issue.

## Begin

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). In --auto
mode, follow `references/decision-protocol.md` at decision points (W1, W2).
Safety gates (W3, W4) remain blocking in both modes. Create
`wip/work-on_<N>_decisions.md` if any decisions are recorded.

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
1. Check for an active `work-on` workflow with `koto workflows`. If active, resume
   with `koto next work-on`.
2. If no active workflow, run `koto init` with the template path and appropriate
   variables (see Koto Orchestration).
3. Submit entry evidence to set the mode:
   - Issue-backed: `koto next work-on --with-data '{"mode": "issue_backed", "issue_number": "<N>"}'`
   - Free-form: `koto next work-on --with-data '{"mode": "free_form", "task_description": "..."}'`
4. Enter the execution loop.

If no extension file exists at `.claude/shirabe-extensions/work-on.md`, the skill
proceeds with generic behavior: no language-specific quality checks, no label blocking
(blocking label check is skipped if no label vocabulary is defined in CLAUDE.md).
