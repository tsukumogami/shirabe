---
name: work-on
version: "1.0"
description: >
  Implementation workflow for issue-backed and free-form tasks. Split topology:
  issue-backed mode routes through context_injection, setup, and staleness_check;
  free-form mode routes through task_validation, research, and post_research_validation.
  Both paths converge at analysis and share all subsequent states. Requires two
  variables: ISSUE_NUMBER (issue-backed only) and ARTIFACT_PREFIX (always). Self-loops
  use conditional when blocks (scope_changed_retry, partial_tests_failing_retry,
  creation_failed_retry) to avoid triggering cycle detection.
initial_state: entry

variables:
  ISSUE_NUMBER:
    description: GitHub issue number for issue-backed workflows
    required: false
  ARTIFACT_PREFIX:
    description: >
      Prefix for context keys and branch names. Set at koto init time:
      issue_<N> for issue-backed, task_<slug> for free-form.
    required: true

states:
  entry:
    accepts:
      mode:
        type: enum
        values: [issue_backed, free_form]
        required: true
      issue_number:
        type: string
        description: GitHub issue number (required for issue_backed mode)
      task_description:
        type: string
        description: Task description (required for free_form mode)
    transitions:
      - target: context_injection
        when:
          mode: issue_backed
      - target: task_validation
        when:
          mode: free_form

  context_injection:
    gates:
      context_artifact:
        type: context-exists
        key: context.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: setup_issue_backed
        when:
          status: completed
      - target: setup_issue_backed
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
      - target: setup_issue_backed

  task_validation:
    accepts:
      verdict:
        type: enum
        values: [proceed, exit]
        required: true
      rationale:
        type: string
        description: Reasoning behind the validation verdict
    transitions:
      - target: research
        when:
          verdict: proceed
      - target: validation_exit
        when:
          verdict: exit

  validation_exit:
    terminal: true

  research:
    accepts:
      context_gathered:
        type: enum
        values: [sufficient, insufficient]
      context_summary:
        type: string
        description: Summary of research findings and codebase observations
    transitions:
      - target: post_research_validation

  post_research_validation:
    accepts:
      verdict:
        type: enum
        values: [ready, needs_design, exit]
        required: true
      rationale:
        type: string
        description: Reasoning behind the validation verdict
      revised_scope:
        type: string
        description: Narrowed scope when task can proceed with adjustments
    transitions:
      - target: setup_free_form
        when:
          verdict: ready
      - target: validation_exit
        when:
          verdict: needs_design
      - target: validation_exit
        when:
          verdict: exit

  setup_issue_backed:
    gates:
      on_feature_branch:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      baseline_exists:
        type: context-exists
        key: baseline.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: staleness_check
        when:
          status: completed
      - target: staleness_check
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
      - target: staleness_check

  setup_free_form:
    gates:
      on_feature_branch:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      baseline_exists:
        type: context-exists
        key: baseline.md
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      - target: analysis
        when:
          status: completed
      - target: analysis
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
      - target: analysis

  staleness_check:
    gates:
      staleness_fresh:
        type: command
        command: "check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'"
    accepts:
      staleness_signal:
        type: enum
        values: [fresh, stale_requires_introspection, override, blocked]
        required: true
      detail:
        type: string
        description: Override reason or failure detail
    transitions:
      - target: introspection
        when:
          staleness_signal: stale_requires_introspection
      - target: analysis
        when:
          staleness_signal: fresh
      - target: analysis
        when:
          staleness_signal: override
      - target: done_blocked
        when:
          staleness_signal: blocked
      - target: analysis

  introspection:
    gates:
      introspection_artifact:
        type: context-exists
        key: introspection.md
    accepts:
      introspection_outcome:
        type: enum
        values: [approach_unchanged, approach_updated, issue_superseded]
        required: true
      rationale:
        type: string
        description: What changed or why the issue is superseded
    transitions:
      - target: done_blocked
        when:
          introspection_outcome: issue_superseded
      - target: analysis
        when:
          introspection_outcome: approach_unchanged
      - target: analysis
        when:
          introspection_outcome: approach_updated
      - target: analysis

  analysis:
    gates:
      plan_artifact:
        type: context-exists
        key: plan.md
    accepts:
      plan_outcome:
        type: enum
        values: [plan_ready, blocked_missing_context, scope_changed_retry, scope_changed_escalate]
        required: true
      approach_summary:
        type: string
        description: Summary of the implementation approach
      decisions:
        type: string
        description: >
          JSON array of decision records, each with choice, rationale, and
          alternatives_considered fields. Captures non-obvious judgment calls
          made during analysis.
    transitions:
      - target: implementation
        when:
          plan_outcome: plan_ready
      - target: analysis
        when:
          plan_outcome: scope_changed_retry
      - target: done_blocked
        when:
          plan_outcome: scope_changed_escalate
      - target: done_blocked
        when:
          plan_outcome: blocked_missing_context

  implementation:
    gates:
      code_committed:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\" && test \"$(git log --oneline main..HEAD | wc -l)\" -gt 0 && go test ./... 2>/dev/null"
    accepts:
      implementation_status:
        type: enum
        values: [complete, partial_tests_failing_retry, partial_tests_failing_escalate, blocked]
        required: true
      rationale:
        type: string
        description: What was accomplished or what is blocking progress
      decisions:
        type: string
        description: >
          JSON array of decision records, each with choice, rationale, and
          alternatives_considered fields. Captures non-obvious judgment calls
          made during implementation.
    transitions:
      - target: finalization
        when:
          implementation_status: complete
      - target: implementation
        when:
          implementation_status: partial_tests_failing_retry
      - target: done_blocked
        when:
          implementation_status: partial_tests_failing_escalate
      - target: done_blocked
        when:
          implementation_status: blocked

  finalization:
    gates:
      summary_exists:
        type: context-exists
        key: summary.md
    accepts:
      finalization_status:
        type: enum
        values: [ready_for_pr, deferred_items_noted, issues_found]
        required: true
    transitions:
      - target: implementation
        when:
          finalization_status: issues_found
      - target: pr_creation
        when:
          finalization_status: ready_for_pr
      - target: pr_creation
        when:
          finalization_status: deferred_items_noted
      - target: pr_creation

  pr_creation:
    accepts:
      pr_status:
        type: enum
        values: [created, creation_failed_retry, creation_failed_escalate]
        required: true
      pr_url:
        type: string
        description: URL of the created pull request
    transitions:
      - target: ci_monitor
        when:
          pr_status: created
      - target: pr_creation
        when:
          pr_status: creation_failed_retry
      - target: done_blocked
        when:
          pr_status: creation_failed_escalate

  ci_monitor:
    gates:
      ci_passing:
        type: command
        command: "gh pr checks $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json state --jq '[.[] | select(.state != \"SUCCESS\")] | length == 0' | grep -q true"
    accepts:
      ci_outcome:
        type: enum
        values: [passing, failing_fixed, failing_unresolvable]
        required: true
      rationale:
        type: string
        description: What was fixed or why CI failures are unresolvable
    transitions:
      - target: done
        when:
          ci_outcome: passing
      - target: done
        when:
          ci_outcome: failing_fixed
      - target: done_blocked
        when:
          ci_outcome: failing_unresolvable
      - target: done

  done:
    terminal: true

  done_blocked:
    terminal: true
---

## entry

Determine the workflow mode and provide the initial context for this task.

**Issue-backed mode**: you have a GitHub issue number. Submit evidence with
`mode: issue_backed` and include the `issue_number` field.

**Free-form mode**: you have a task description but no issue. Submit evidence with
`mode: free_form` and include the `task_description` field.

**Plan-backed tasks** (from a PLAN document) use free-form mode. The skill layer
extracts the goal and acceptance criteria from the PLAN doc and provides them as
the task description.

Evidence schema:
- `mode`: `issue_backed` or `free_form`
- `issue_number`: GitHub issue number (issue-backed only)
- `task_description`: what to build (free-form only)

## context_injection

Read `references/phases/phase-0-context-injection.md` for detailed steps.

If the gate fails (artifact missing), submit `status: completed` after creating
the artifact, `status: override` if providing context differently, or
`status: blocked` if the issue cannot be reached.

## task_validation

Assess whether this free-form task description is clear enough and appropriately
scoped for direct implementation.

Read the task description provided at entry. Check for:
- Ambiguous or missing requirements that would make implementation guesswork
- Scope that clearly exceeds a single implementation session
- Requests that need a design document before code can be written

If the task is clear and reasonably scoped, submit `verdict: proceed` with your
rationale. If the task is not ready, submit `verdict: exit` with rationale
explaining what the user should do instead (narrow the scope, create an issue,
write a design doc).

Evidence schema:
- `verdict`: `proceed` or `exit`
- `rationale`: reasoning behind your assessment

## validation_exit

The task was not ready for direct implementation. Communicate the verdict and
rationale to the user. Suggest concrete next steps: create a GitHub issue with
clearer requirements, write a design document, narrow the scope to a single
change, or split into smaller tasks. If the verdict was `needs_design`, explain
which aspects need design work before implementation can proceed.

## research

Gather context about the codebase relevant to this free-form task. Read code,
check existing patterns, understand the architecture around the area you will
modify. Focus on:
- Files and packages that will be touched
- Existing patterns and conventions to follow
- Dependencies and interfaces that constrain the approach
- Tests that cover the affected area

Submit `context_gathered` with a `context_summary` describing what you found.
The summary carries forward to inform the post-research validation and
subsequent analysis.

Evidence schema:
- `context_gathered`: `sufficient` or `insufficient`
- `context_summary`: description of findings and relevant codebase observations

## post_research_validation

Reassess the task against what research revealed about the current codebase.

With the codebase context from research, evaluate whether the task is still
appropriate for direct implementation. Check for:
- Misconceptions in the original task description now visible with codebase context
- Dependencies or prerequisites not apparent from the task description alone
- Scope that research reveals to be larger than initially expected
- Existing code that already solves the problem or conflicts with the approach

Submit `verdict: ready` to proceed, `verdict: needs_design` if a design doc is
needed first (routes to validation_exit), or `verdict: exit` if the task should
not proceed (routes to validation_exit). Include `revised_scope` when the task
can proceed with a narrowed scope.

Evidence schema:
- `verdict`: `ready`, `needs_design`, or `exit`
- `rationale`: reasoning informed by research findings
- `revised_scope`: (optional) narrowed scope description

## setup_issue_backed

Read `references/phases/phase-1-setup.md` for branch naming and baseline format.

If the gate fails, submit `status: completed` after creating the branch and baseline,
`status: override` if reusing an existing branch, or `status: blocked`.

## setup_free_form

Read `references/phases/phase-1-setup.md` for branch naming and baseline format.

If the gate fails, submit `status: completed` after creating the branch and baseline,
`status: override` if reusing an existing branch, or `status: blocked`.

## staleness_check

This state assesses whether the codebase has changed significantly since the issue
was opened. The gate runs `check-staleness.sh --issue {{ISSUE_NUMBER}}` and pipes
through jq to check `introspection_recommended == false`. When fresh (gate passes),
the workflow auto-advances to analysis.

If the gate fails, you are here because the staleness check found significant
changes or could not complete.

Submit `staleness_signal: fresh` if you have confirmed the issue context is still
current, `staleness_signal: stale_requires_introspection` if the codebase has
changed enough to warrant re-reading the issue against current code,
`staleness_signal: override` if the user says to skip the staleness check, or
`staleness_signal: blocked` if the check cannot complete.

Evidence schema:
- `staleness_signal`: `fresh`, `stale_requires_introspection`, `override`, or `blocked`
- `detail`: explanation of the signal or override reason

## introspection

Read `references/phases/phase-2-introspection.md` for steps and evidence options.

The gate checks for context key `introspection.md`. On resume, if the
artifact already exists in koto context, the gate auto-advances.

## analysis

Read `references/phases/phase-3-analysis.md` for plan structure and agent
delegation patterns. Output: koto context key `plan.md`.

Self-loop with `scope_changed_retry` (up to 3 times). After 3,
use `scope_changed_escalate`. Submit `blocked_missing_context` if stuck.
Capture non-obvious decisions in the `decisions` field.

## implementation

Read `references/phases/phase-4-implementation.md` for the implementation cycle,
code review guidance, and commit patterns.

Self-loop with `partial_tests_failing_retry` (up to 3 times). After 3,
use `partial_tests_failing_escalate`. Submit `blocked` for external blockers.
Capture non-obvious judgment calls in the `decisions` field.

## finalization

Read `references/phases/phase-5-finalization.md` for cleanup steps and summary
format. Output: koto context key `summary.md`.

## pr_creation

Read `references/phases/phase-6-pr.md` for PR format, pre-PR verification,
and push instructions.

Check if a PR already exists: `gh pr list --head $(git rev-parse --abbrev-ref HEAD)`

Self-loop with `creation_failed_retry` (up to 3 times). After 3, use
`creation_failed_escalate`.

## ci_monitor

Read `references/phases/phase-6-pr.md` for CI monitoring.

If the gate fails, fix what you can and submit `ci_outcome: failing_fixed`.
If unresolvable, submit `ci_outcome: failing_unresolvable` with rationale.

## done

The workflow is complete. The PR has been created and CI is passing.

## done_blocked

The workflow reached a blocking condition that requires human intervention.
This state is reachable from multiple points in the workflow: analysis
(scope too large or missing context), implementation (persistent test failures
or external blockers), pr_creation (repeated creation failures), ci_monitor
(unresolvable CI failures), and introspection (issue superseded).

If the blocker has been resolved externally, use `koto rewind <name>` to walk
back to the originating state. `koto rewind` rewinds one step per call; call
it repeatedly to reach a non-adjacent origin state. For example, if blocked
from ci_monitor, one rewind reaches pr_creation; from analysis, one rewind
reaches the previous state in the path.
