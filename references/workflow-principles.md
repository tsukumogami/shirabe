# Workflow Principles

Five principles the roadmap and plan workflows derive from. Each
principle states the rule, names the consequence, and lists the
specific workflow rules that flow from it. Skill surfaces reference
these by name -- when a surfaced rule cites a principle, it's citing
this file.

The set is intentionally small enough to hold in mind. Use it to
reason at the edges where a procedure doesn't fit.

## P1: Usable value is the unit of work

Every PR and every roadmap feature delivers observable value on its
own. Default to one PR; split only for a hard constraint or genuine
incremental value, never by mechanism (e.g., "because the input is
a roadmap").

**Rules derived from this:**

- The plan workflow defaults to single-pr execution. Multi-pr requires
  a named escape condition: a hard constraint forces multiple PRs
  (cross-repo landing order, a workflow that must reach main before
  it can be invoked) or each PR is independently useful.
- A roadmap is multi-pr because each feature should deliver
  observable incremental value as a cohesive deliverable, not
  because "the input is a roadmap."
- A value-confirmation step checks every roadmap feature, and every
  PR for a plan whose split delivers incremental value. The step can
  fail: a unit that isn't a standalone increment is flagged for
  re-scoping, not waved through.

## P2: Default to the lowest ceremony

Reach for the least machinery the work needs. Escalate only when a
named condition forces it.

**Rules derived from this:**

- One PR over many (see P1).
- A self-contained PLAN doc over GitHub issues when the work is
  single-pr.
- Don't promote a check to error-level when a notice suffices for the
  current corpus state (see P5 for the inverse: strictness when blast
  radius warrants).

## P3: Decisions need a durable home

A choice that affects downstream work or rests on a falsifiable
assumption gets recorded where a later reader finds it, not left
implicit in the procedure.

**Rules derived from this:**

- Decision blocks captured in the design doc carry their assumptions
  and consequences forward.
- Under `--auto`, judgment-call gates record `confirmed` or `assumed`
  (the latter at high review priority) rather than hard-stopping.
  Recording is the durable home; the loud surfacing in the PR body and
  terminal summary is the visibility.
- An implicit decision called out in the design's Implementation
  Approach makes the assumption visible to the plan author.

## P4: One canonical format per concern, defined once

Each shared shape (the issues table, the dependency diagram) has a
single source both workflows consume. Per-skill restatement is the
drift source the standardization removes.

**Rules derived from this:**

- The issues-table framework lives in
  `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md`, parameterized by
  altitude into a plan profile (issue-keyed) and a roadmap profile
  (feature-keyed).
- The dependency-diagram convention lives in
  `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`.
- The two skill references (`plan-doc-structure.md`, `roadmap-format.md`)
  cite the shared references and keep only their profile-specific
  deltas and lifecycle content.

## P5: Strictness tracks blast radius

How hard a rule is enforced scales with the consequence of getting it
wrong. A check whose retrofit cost is contained can land strict; a
check whose retrofit cost is corpus-wide lands as a notice first, then
is promoted to error once the corpus conforms.

**Rules derived from this:**

- Issues-table schema conformance (FC05) and cross-reference
  existence (FC06) land at error-level on day one -- their retrofit
  cost is contained to a small migration.
- Table-diagram reconciliation (FC07) is staged into a later
  increment behind a feasibility spike and ships as a notice, then is
  promoted to error after the committed-diagram corpus is reconciled.
- Doc-vs-GitHub state reconciliation (FC09) follows the same staged
  posture as FC07: notice-level for v1 via `is_notice` membership,
  promoted to error through a one-line membership change once the
  committed corpus settles against the live-GitHub signal. FC09 also
  self-disables when its preconditions are absent (no credentials,
  no PR context, rate limit exhausted, cross-repo access denied),
  so a CI environment without GitHub access degrades to a skip
  notice instead of a noisy false defect.
- The lifecycle CI checks (L01/L02) are error-level because their
  function is to force the deletion of a Done multi-pr doc or a
  single-pr plan; a notice can't carry that forcing function.
