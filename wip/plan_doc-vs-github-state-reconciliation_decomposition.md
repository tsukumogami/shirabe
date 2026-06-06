---
design_doc: docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md
input_type: design
decomposition_strategy: horizontal
strategy_rationale: "Six implementation steps with a clear prerequisite chain (trait surface, impl, consumer, wiring, two verification scans); no end-to-end thread to thicken, so horizontal not walking-skeleton -- mirrors the parent DESIGN's Decision 3 and the FC07 sub-DESIGN's Decision 6."
confirmed_by_user: false
issue_count: 6
execution_mode: single-pr
---

# Plan Decomposition: doc-vs-github-state-reconciliation

## Strategy: Horizontal

The six implementation steps in the DESIGN's Implementation Approach
section are horizontally coupled by a clear prerequisite chain:

- Step 1 declares the new module's surface (trait + types + PR-context
  detector). No internal dependency.
- Step 2 implements the trait and adds the test stand-in. Depends on
  Step 1's declarations.
- Step 3 consumes the impl inside `check_fc09` and wires the dispatch
  into `validate_file`. Depends on Step 2.
- Step 4 is the membership wiring in `is_notice` that turns the
  check's emissions into notices rather than errors. Depends on
  Step 3 (the check has to exist before its arm is added to the
  membership).
- Step 5 verifies notice cleanliness against the committed corpus.
  Depends on Step 4 (notices have to be in the notice-membership
  to be inspected as notices).
- Step 6 captures notice volume against the committed corpus.
  Depends on Step 4 (same reason).

There is no end-to-end runtime path to thicken; each step builds one
capability fully before the next can build on top. Horizontal, not
walking skeleton -- consistent with the parent DESIGN's Decision 3
posture and the FC07 sub-DESIGN's Decision 6 single-bundled-PR
default.

## Issue Outlines

### Outline O1: feat(validate): add gh.rs with IssueStateClient trait and PR-context detector

- **Type**: standard (code)
- **Complexity**: testable
- **Goal**: Create `crates/shirabe-validate/src/gh.rs` with the
  `IssueStateClient` trait, `IssueState`/`ClientError`/`PrContext`
  data types, the constructor-only `GhSubprocessClient` struct, and
  `detect_pr_context()`; register the module in `lib.rs`. No
  network method impls yet -- the impl ships in O2.
- **Section**: DESIGN Decisions 2, 7 (Solution Architecture
  Components -- "`crates/shirabe-validate/src/gh.rs` (new)").
- **Milestone**: doc-vs-github-state-reconciliation
- **Dependencies**: None

### Outline O2: feat(validate): implement GhSubprocessClient and MockIssueStateClient

- **Type**: standard (code)
- **Complexity**: critical
- **Goal**: Implement the two `IssueStateClient` methods on
  `GhSubprocessClient` (subprocess spawn, 5s user-space
  poll-and-kill timeout, depth-aware top-level JSON field
  extraction, stderr-pattern classification), add the
  `#[cfg(test)] MockIssueStateClient` test stand-in, and unit-test
  the success path, every `ClientError` variant, the timeout, the
  auth probe, and the mock's behavior across the six pinned cases.
- **Section**: DESIGN Decisions 1, 3, 5 + Security Considerations
  (subprocess timeout enforcement, output byte bound, defensive
  parsing, token handling, argument validation).
- **Milestone**: doc-vs-github-state-reconciliation
- **Dependencies**: Blocked by <<ISSUE:O1>>

### Outline O3: feat(validate): add check_fc09 with three sub-checks and wire into validate_file

- **Type**: standard (code)
- **Complexity**: critical
- **Goal**: Implement `check_fc09(doc, spec, client, pr_ctx) ->
  Vec<ValidationError>` in `checks.rs` with Sub A (doc claims done
  vs GH open), Sub B (doc claims non-done vs GH closed), and Sub C
  (PR `Closes #N` reconciliation in both directions); wire FC09
  into the `Plan` and `Roadmap` arms of `validate_file` with a
  single `GhSubprocessClient::new()` plus `detect_pr_context()` at
  function entry. Integration-test the eleven pinned fixtures from
  Decision 3 using `MockIssueStateClient`.
- **Section**: DESIGN Solution Architecture Components/Data Flow +
  Decisions 1, 4, 5, 6.
- **Milestone**: doc-vs-github-state-reconciliation
- **Dependencies**: Blocked by <<ISSUE:O2>>

### Outline O4: feat(validate): extend is_notice membership to include FC09

- **Type**: standard (code)
- **Complexity**: simple
- **Goal**: Extend the `is_notice` `matches!` expression in
  `crates/shirabe-validate/src/validate.rs` to include the `"FC09"`
  arm, rewrite the doc comment to the FC09-aware wording (Decision
  6), rename the test `is_notice_only_schema_and_fc07` to
  `is_notice_only_schema_fc07_fc09`, update its body (add FC09
  positive assertion, remove FC09 from the negative for-loop).
- **Section**: DESIGN Decision 6.
- **Milestone**: doc-vs-github-state-reconciliation
- **Dependencies**: Blocked by <<ISSUE:O3>>

### Outline O5: chore(validate): public-cleanliness scan against the committed corpus

- **Type**: task
- **Complexity**: simple
- **Goal**: Run the built validator with FC09 enabled against
  `docs/plans/*.md` and `docs/roadmaps/*.md`. Inspect every emitted
  notice for token bytes, private repo names, paths to private
  files, pre-announcement features, or external issue numbers from
  private repos. Verify the `ClientError::Malformed(String)`
  payload never reaches a notice body, log message, or any
  user-visible surface. Result: one PR-body verification bullet
  recording a clean pass.
- **Section**: DESIGN Implementation Approach Step 5 + Security
  Considerations (Malformed payload boundary).
- **Milestone**: doc-vs-github-state-reconciliation
- **Dependencies**: Blocked by <<ISSUE:O4>>

### Outline O6: chore(validate): notice-volume survey against the committed corpus

- **Type**: task
- **Complexity**: simple
- **Goal**: Run the built validator with FC09 enabled against the
  full `docs/plans/*.md` and `docs/roadmaps/*.md` corpus locally.
  Capture the notice count. Record the number in the PR body's
  verification section as evidence FC09 ships at tractable notice
  volume (parent DESIGN's no-day-one-breakage invariant; PRD Known
  Limitation #1).
- **Section**: DESIGN Implementation Approach Step 6.
- **Milestone**: doc-vs-github-state-reconciliation
- **Dependencies**: Blocked by <<ISSUE:O4>>

## Value Confirmation (Step 3.5a)

### The unit shape

In single-pr mode the unit is the whole plan (the one PR delivers
the whole feature). Per the parent SKILL surface and the parent
PRD's R10/R12, the value guard for a single-pr plan is degenerate
by construction: a plan that lands in one PR carries one unit, and
that unit passes the value test trivially.

### Decision block (per `--auto` decision-protocol)

```
decision: single-pr-delivers-usable-value
status: assumed
priority: high
unit: the FC09 PR (one outline-bundle landing the whole feature)
value-landed: |
  The PR delivers FC09 -- a new validator check that catches a
  class of drift no existing check covers (doc-vs-GitHub state).
  A reader of the merged PR observes a new notice-level check
  shipping against the committed corpus, the `is_notice`
  membership now naming the new check, the `gh.rs` module
  declaring the trait surface, and the test corpus exercising the
  eleven pinned cases. The PR's value does not depend on a later
  PR landing.
reason: |
  Single-pr mode pre-committed by the parent /scope chain. The
  value-guard is recorded `assumed` at high review priority per
  R12 of the parent PRD; this surfaces it in the PR body's
  terminal summary.
```

## Execution Mode Selection (Step 3.6)

### Mode

`execution_mode: single-pr` (pre-committed by parent /scope).

### Rationale

The default per `skills/plan/SKILL.md`'s surfaced rule is single-pr;
no hard constraint forces multiple PRs (the six steps share a single
crate, do not cross repos, and do not require any intermediate state
to reach main before subsequent work can use it); the steps are not
each independently useful to a reader before the whole check is wired
(O1 alone ships a trait nobody calls; O2 alone ships an impl nobody
calls; only O3 + O4 + O5 + O6 together deliver the observable
value). Therefore: single-pr per the surfaced rule's default branch.

### Recorded under --auto

```
decision: execution-mode-single-pr
status: confirmed
priority: standard
rationale: |
  Default per the plan SKILL surface; no hard-constraint and no
  per-outline independent-value rationale. The six outlines compose
  into one observable increment (the wired-in notice-level check
  with corpus verification).
```
