---
name: work-on
version: "1.0"
description: >
  Implementation workflow for issue-backed, free-form, and plan-backed tasks. Split topology:
  issue-backed mode routes through context_injection, setup, and staleness_check;
  free-form mode routes through task_validation, research, and post_research_validation;
  plan-backed mode routes through plan_context_injection, optional plan_validation, and
  setup_plan_backed, skipping staleness. All paths converge at analysis and share all
  subsequent states. Requires two variables: ISSUE_NUMBER (issue-backed only) and
  ARTIFACT_PREFIX (always). Self-loops use conditional when blocks (scope_changed_retry,
  partial_tests_failing_retry, creation_failed_retry) to avoid triggering cycle detection.
initial_state: entry

variables:
  ISSUE_NUMBER:
    description: GitHub issue number for issue-backed workflows
    required: false
  ISSUE_TYPE:
    description: >
      Issue type hint supplied by the plan orchestrator (code, docs, or task).
      The analysis agent confirms or overrides this value during analysis and
      re-submits it with implementation evidence for routing.
    required: false
    default: code
  ARTIFACT_PREFIX:
    description: >
      Prefix for context keys and branch names. Set at koto init time:
      issue_<N> for issue-backed, task_<slug> for free-form.
    required: true
  ISSUE_SOURCE:
    description: Source of issue data for plan-backed mode (github or plan_outline)
    required: false
  PLAN_DOC:
    description: Path to the PLAN document for plan-backed mode
    required: false
  SHARED_BRANCH:
    description: >
      Shared branch name provided by the plan orchestrator. When set, skip branch
      creation in setup states and commit directly to this branch.
    required: false

states:
  entry:
    accepts:
      mode:
        type: enum
        values: [issue_backed, free_form, plan_backed, skipped]
        required: true
      issue_number:
        type: string
        description: GitHub issue number (required for issue_backed mode)
      task_description:
        type: string
        description: Task description (required for free_form mode)
      issue_source:
        type: enum
        values: [github, plan_outline]
        description: Source of issue data (plan-backed mode only)
    transitions:
      - target: context_injection
        when:
          mode: issue_backed
      - target: task_validation
        when:
          mode: free_form
      - target: plan_context_injection
        when:
          mode: plan_backed
      - target: skipped_due_to_dep_failure
        when:
          mode: skipped

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
          gates.context_artifact.exists: true
      - target: setup_issue_backed
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "context_injection blocked: ${evidence.detail}"
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
          gates.on_feature_branch.exit_code: 0
          gates.baseline_exists.exists: true
      - target: staleness_check
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup_issue_backed blocked: ${evidence.detail}"
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
          gates.on_feature_branch.exit_code: 0
          gates.baseline_exists.exists: true
      - target: analysis
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup_free_form blocked: ${evidence.detail}"
      - target: analysis

  plan_context_injection:
    gates:
      context_artifact:
        type: context-exists
        key: context.md
        override_default:
          exists: true
          error: ""
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      issue_source:
        type: enum
        values: [github, plan_outline]
        description: >
          Source of issue data. github routes directly to setup; plan_outline routes
          through plan_validation first since the outline item needs validation before setup.
      detail:
        type: string
        description: Override type or failure reason
    transitions:
      # github path: context injected from GitHub issue, proceed to setup directly
      - target: setup_plan_backed
        when:
          status: completed
          issue_source: github
          gates.context_artifact.exists: true
      # plan_outline path: outline extracted from PLAN doc, validate before setup
      - target: plan_validation
        when:
          status: completed
          issue_source: plan_outline
          gates.context_artifact.exists: true
      - target: setup_plan_backed
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "plan_context_injection blocked: ${evidence.detail}"
      - target: setup_plan_backed

  plan_validation:
    accepts:
      verdict:
        type: enum
        values: [proceed, exit]
        required: true
      rationale:
        type: string
        description: Reasoning behind the validation verdict
    transitions:
      - target: setup_plan_backed
        when:
          verdict: proceed
      - target: validation_exit
        when:
          verdict: exit

  setup_plan_backed:
    skip_if:
      vars.SHARED_BRANCH:
        is_set: true
      status: override
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
          gates.on_feature_branch.exit_code: 0
          gates.baseline_exists.exists: true
      - target: analysis
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "setup_plan_backed blocked: ${evidence.detail}"
      - target: analysis

  staleness_check:
    gates:
      staleness_fresh:
        type: command
        command: "check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e '.introspection_recommended == false'"
        override_default:
          exit_code: 0
          error: ""
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
          gates.staleness_fresh.exit_code: 0
      - target: analysis
        when:
          staleness_signal: override
      - target: done_blocked
        when:
          staleness_signal: blocked
        context_assignments:
          failure_reason: "staleness_check blocked: ${evidence.detail}"
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
        context_assignments:
          failure_reason: "issue superseded: ${evidence.rationale}"
      - target: analysis
        when:
          introspection_outcome: approach_unchanged
          gates.introspection_artifact.exists: true
      - target: analysis
        when:
          introspection_outcome: approach_updated
          gates.introspection_artifact.exists: true
      - target: analysis

  analysis:
    gates:
      plan_artifact:
        type: context-exists
        key: plan.md
    accepts:
      plan_outcome:
        type: enum
        values: [plan_ready, already_complete, blocked_missing_context, scope_changed_retry, scope_changed_escalate]
        required: true
      approach_summary:
        type: string
        description: Summary of the implementation approach
      issue_type:
        type: enum
        values: [code, docs, task]
        description: >
          Issue type classification confirmed during analysis. Flows as ISSUE_TYPE context
          for downstream routing. Defaults to code when omitted.
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
          gates.plan_artifact.exists: true
      - target: done_already_complete
        when:
          plan_outcome: already_complete
      - target: analysis
        when:
          plan_outcome: scope_changed_retry
      - target: done_blocked
        when:
          plan_outcome: scope_changed_escalate
        context_assignments:
          failure_reason: "scope changed: escalation required: ${evidence.approach_summary}"
      - target: done_blocked
        when:
          plan_outcome: blocked_missing_context
        context_assignments:
          failure_reason: "analysis blocked: missing context: ${evidence.approach_summary}"

  implementation:
    gates:
      on_feature_branch_impl:
        type: command
        command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
      has_commits:
        type: command
        command: "test \"$(git log --oneline main..HEAD | wc -l)\" -gt 0"
      tests_passing:
        type: command
        command: "[ ! -f go.mod ] || go test ./... 2>/dev/null"
    accepts:
      implementation_status:
        type: enum
        values: [complete, partial_tests_failing_retry, partial_tests_failing_escalate, blocked]
        required: true
      issue_type:
        type: enum
        values: [code, docs, task]
        description: >
          Issue type confirmed during analysis. Required when submitting complete —
          determines post-implementation routing. Use code if unsure.
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
      # code: run scrutiny/review/QA panels (all gates must pass)
      - target: scrutiny
        when:
          implementation_status: complete
          issue_type: code
          gates.on_feature_branch_impl.exit_code: 0
          gates.has_commits.exit_code: 0
          gates.tests_passing.exit_code: 0
      # docs: skip panels, go directly to finalization (no tests_passing check)
      - target: finalization
        when:
          implementation_status: complete
          issue_type: docs
          gates.on_feature_branch_impl.exit_code: 0
          gates.has_commits.exit_code: 0
      # task: skip panels, go directly to finalization (no commits required)
      - target: finalization
        when:
          implementation_status: complete
          issue_type: task
          gates.on_feature_branch_impl.exit_code: 0
      - target: implementation
        when:
          implementation_status: partial_tests_failing_retry
      - target: done_blocked
        when:
          implementation_status: partial_tests_failing_escalate
        context_assignments:
          failure_reason: "implementation blocked: ${evidence.rationale}"
      - target: done_blocked
        when:
          implementation_status: blocked
        context_assignments:
          failure_reason: "implementation blocked: ${evidence.rationale}"

  scrutiny:
    gates:
      scrutiny_results:
        type: context-exists
        key: scrutiny_results.json
        override_default:
          exists: true
          error: ""
    accepts:
      scrutiny_outcome:
        type: enum
        values: [passed, blocking_retry, blocking_escalate]
        required: true
      failure_reason:
        type: string
        description: Reason for blocking escalation (required when scrutiny_outcome is blocking_escalate)
    transitions:
      - target: review
        when:
          scrutiny_outcome: passed
          gates.scrutiny_results.exists: true
      - target: implementation
        when:
          scrutiny_outcome: blocking_retry
      - target: done_blocked
        when:
          scrutiny_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  review:
    gates:
      review_results:
        type: context-exists
        key: review_results.json
        override_default:
          exists: true
          error: ""
    accepts:
      review_outcome:
        type: enum
        values: [passed, blocking_retry, blocking_escalate]
        required: true
      failure_reason:
        type: string
        description: Reason for blocking escalation
    transitions:
      - target: qa_validation
        when:
          review_outcome: passed
          gates.review_results.exists: true
      - target: implementation
        when:
          review_outcome: blocking_retry
      - target: done_blocked
        when:
          review_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

  qa_validation:
    gates:
      qa_results:
        type: context-exists
        key: qa_results.json
        override_default:
          exists: true
          error: ""
    accepts:
      qa_outcome:
        type: enum
        values: [passed, blocking_retry, blocking_escalate]
        required: true
      failure_reason:
        type: string
        description: Reason for blocking escalation
    transitions:
      - target: finalization
        when:
          qa_outcome: passed
          gates.qa_results.exists: true
      - target: implementation
        when:
          qa_outcome: blocking_retry
      - target: done_blocked
        when:
          qa_outcome: blocking_escalate
        context_assignments:
          failure_reason: ${evidence.failure_reason}

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
          gates.summary_exists.exists: true
      - target: pr_creation
        when:
          finalization_status: deferred_items_noted
          gates.summary_exists.exists: true
      - target: pr_creation

  pr_creation:
    accepts:
      pr_status:
        type: enum
        values: [created, shared, creation_failed_retry, creation_failed_escalate]
        required: true
      pr_url:
        type: string
        description: URL of the created pull request
    transitions:
      - target: ci_monitor
        when:
          pr_status: created
      - target: done
        when:
          pr_status: shared
      - target: pr_creation
        when:
          pr_status: creation_failed_retry
      - target: done_blocked
        when:
          pr_status: creation_failed_escalate
        context_assignments:
          failure_reason: "pr_creation failed after retries: ${evidence.pr_url}"

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
          gates.ci_passing.exit_code: 0
      # failing_fixed: agent pushed a follow-up commit to fix CI; the gate
      # polls the PR and may be stale relative to the new push. Gate check
      # is inappropriate here -- the agent's direct observation is the
      # authoritative signal.
      - target: done
        when:
          ci_outcome: failing_fixed
      - target: done_blocked
        when:
          ci_outcome: failing_unresolvable
        context_assignments:
          failure_reason: "ci_monitor: unresolvable CI failures: ${evidence.rationale}"
      - target: done

  done:
    terminal: true

  done_already_complete:
    terminal: true

  done_blocked:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
        description: >
          Reason for the blocking failure. Written to context via context_assignments
          on incoming transitions so koto can populate the batch view's reason field.

  skipped_due_to_dep_failure:
    terminal: true
    skipped_marker: true
---

## entry

Determine the workflow mode and provide the initial context for this task.

**Issue-backed mode**: you have a GitHub issue number. Submit evidence with
`mode: issue_backed` and include the `issue_number` field.

**Free-form mode**: you have a task description but no issue. Submit evidence with
`mode: free_form` and include the `task_description` field.

**Plan-backed mode**: you have an issue from a koto parent workflow (spawned via
plan orchestrator). Submit with `mode: plan_backed` and include `issue_source`
(either `github` or `plan_outline`).

Evidence schema:
- `mode`: `issue_backed`, `free_form`, `plan_backed`, or `skipped`
- `issue_number`: GitHub issue number (issue-backed only)
- `task_description`: what to build (free-form only)
- `issue_source`: `github` or `plan_outline` (plan-backed only)

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

## plan_context_injection

Obtain the issue context for a plan-backed task. Behavior differs by ISSUE_SOURCE:

- If ISSUE_SOURCE is `github`: read the GitHub issue with `gh issue view $ISSUE_NUMBER`
  and write it to koto context as `context.md`. Then proceed to setup_plan_backed.
- If ISSUE_SOURCE is `plan_outline`: the PLAN doc is already available via the
  PLAN_DOC variable. Extract the specific issue outline from the PLAN doc and write
  it as `context.md`, then proceed to plan_validation.

Submit `status: completed` with `issue_source` set to match the source used,
`status: override` if context is provided differently, or `status: blocked` if context cannot be obtained.

Evidence schema:
- `status`: `completed`, `override`, or `blocked`
- `issue_source`: `github` or `plan_outline` (required when status is completed; determines next state)

## plan_validation

Validate that the plan outline item (ISSUE_SOURCE=plan_outline path) is clear
enough for direct implementation. Check that acceptance criteria exist and are
specific enough to code against.

Submit `verdict: proceed` to continue to setup_plan_backed, or `verdict: exit`
with rationale to route to validation_exit.

Evidence schema:
- `verdict`: `proceed` or `exit`
- `rationale`: reasoning behind the validation verdict

## setup_plan_backed

Read `references/phases/phase-1-setup.md` for branch naming and baseline format.
For plan-backed tasks, use ARTIFACT_PREFIX as the baseline key.

When `SHARED_BRANCH` is set, submit `status: override` — the orchestrator has already
created the branch. Commit directly to `SHARED_BRANCH` without creating a new one.

Submit `status: completed` after creating the branch and baseline, `status: override`
if reusing an existing branch (including when `SHARED_BRANCH` is set), or `status: blocked`.

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

**Already-complete detection**: during analysis, check whether the issue goal is
already fully satisfied by current code. If all acceptance criteria are already met,
submit `plan_outcome: already_complete` — no implementation needed. Routes to
`done_already_complete` (a non-failure terminal).

**Issue type classification**: confirm or override the `ISSUE_TYPE` hint from the
plan context. Set `issue_type` to:
- `code` — implementation work that runs through scrutiny/review/QA
- `docs` — writing or structural changes that skip code review panels
- `task` — operational work (scripts, commands) with no meaningful review artifact

When `issue_type` is omitted, downstream states treat it as `code`.

Self-loop with `scope_changed_retry` (up to 3 times). After 3,
use `scope_changed_escalate`. Submit `blocked_missing_context` if stuck.
Capture non-obvious decisions in the `decisions` field.

## implementation

Read `references/phases/phase-4-implementation.md` for the implementation cycle,
code review guidance, and commit patterns.

When submitting `implementation_status: complete`, also submit `issue_type` as the
value confirmed during analysis (from `analysis.accepts.issue_type`). This determines
post-implementation routing:
- `code` (default) — proceeds through scrutiny → review → qa_validation
- `docs` — skips panels, goes directly to finalization
- `task` — skips panels, goes directly to finalization

**`issue_type` is required when submitting `complete`.** Omitting it means no transition
fires and the workflow stalls with no error. Use `code` if the issue type is unclear.

Self-loop with `partial_tests_failing_retry` (up to 3 times). After 3,
use `partial_tests_failing_escalate`. Submit `blocked` for external blockers.
Capture non-obvious judgment calls in the `decisions` field.

## scrutiny

Run the scrutiny panel (three parallel reviewers: completeness, justification, intent). Read `references/phases/phase-4a-scrutiny.md` for detailed steps and reviewer prompts. Output: koto context key `scrutiny_results.json`.

Note on gate discoverability: The gate name is `scrutiny_results`; the context key is `scrutiny_results.json` (with `.json` suffix).

Submit `scrutiny_outcome: passed` when all reviewers clear the implementation, `blocking_retry` when reviewers find correctable issues and the implementation agent has addressed them, or `blocking_escalate` when the work cannot proceed without escalation. Include `failure_reason` for `blocking_escalate`.

## review

Run the code review panel (three parallel reviewers: pragmatic, architect, maintainer). Read `references/phases/phase-4b-review.md` for detailed steps and reviewer prompts. Output: koto context key `review_results.json`.

Note on gate discoverability: The gate name is `review_results`; the context key is `review_results.json` (with `.json` suffix).

Submit `review_outcome: passed` when all reviewers approve, `blocking_retry` when reviewers find correctable issues and the implementation agent has addressed them, or `blocking_escalate` when the work cannot proceed without escalation. Include `failure_reason` for `blocking_escalate`.

## qa_validation

Run the QA validation panel. Read `references/phases/phase-4c-qa.md` for detailed steps. Output: koto context key `qa_results.json`.

Note on gate discoverability: The gate name is `qa_results`; the context key is `qa_results.json` (with `.json` suffix).

Submit `qa_outcome: passed` when QA approves the implementation, `blocking_retry` when QA finds correctable defects, or `blocking_escalate` when defects cannot be resolved without escalation. Include `failure_reason` for `blocking_escalate`.

## finalization

Read `references/phases/phase-5-finalization.md` for cleanup steps and summary
format. Output: koto context key `summary.md`.

## pr_creation

If `SHARED_BRANCH` is set, this child is running on the orchestrator's shared
branch and the orchestrator owns the PR. Submit `pr_status: shared` — no PR
creation step is needed here.

Otherwise, read `references/phases/phase-6-pr.md` for PR format, pre-PR
verification, and push instructions.

Check if a PR already exists: `gh pr list --head $(git rev-parse --abbrev-ref HEAD)`

Self-loop with `creation_failed_retry` (up to 3 times). After 3, use
`creation_failed_escalate`.

## ci_monitor

Read `references/phases/phase-6-pr.md` for CI monitoring.

If the gate fails, fix what you can and submit `ci_outcome: failing_fixed`.
If unresolvable, submit `ci_outcome: failing_unresolvable` with rationale.

## done

The workflow is complete. The PR has been created and CI is passing.

## done_already_complete

Analysis confirmed the issue goal is already satisfied by current code. All
acceptance criteria were met before any implementation was needed. No commits
were required. This is a successful terminal state — it is not a failure.

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

## skipped_due_to_dep_failure

This task was skipped because a dependency failed. The parent orchestrator set
`mode: skipped` at entry. No action needed — this terminal state records that the
task was intentionally bypassed due to an upstream failure.
