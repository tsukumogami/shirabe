---
status: Accepted
decision: |
  The work-on skill template performs the atomic chain finalization inline,
  using existing primitives — `shirabe transition` for BRIEF and PRD Accepted
  to Done transitions, `git rm` for the PLAN, single commit covering all
  mutations. The cascade runs before `gh pr ready` fires. The CI gate (the
  reusable lifecycle workflow in strict mode, triggered by the
  `ready_for_review` pull_request event) is the safety net for PRs that bypass
  work-on or have a buggy cascade.
rationale: |
  Uses existing primitives; the shirabe binary gets no new mutation surface.
  Keeps the cascade where authors already expect chain orchestration to live —
  in the work-on skill template — rather than introducing a new subcommand
  whose only consumer is work-on itself. The CI gate is non-optional regardless
  of cascade choice, so layering "work-on drives the cascade as the path of
  least resistance" on top of "CI gate as the backstop" gives both the
  ergonomic and the safety properties. Avoids the failure mode where authors
  invoking `gh pr ready` outside work-on bypass the cascade silently — the CI
  gate catches them.
---

# DECISION: work-on cascade trigger mechanism

## Status

Accepted

## Context

The DRAFT-vs-READY discipline says single-pr chains and multi-pr
work-completing chains must reach their terminal (PLAN deleted,
BRIEF/PRD at Done, DESIGN at Current) by the time the PR flips from
draft to ready. The chain-aware lifecycle check in strict mode is
what CI enforces; the work-on cascade is what drives the
transitions so the author does not have to do them by hand.

Three alternatives can carry the cascade. They differ in where the
finalization logic lives and how authors who skip the work-on path
interact with it.

The lifecycle check (in strict mode) already runs in CI on every PR
that flips to ready. That CI gate is non-optional for this
increment — without it the DRAFT-vs-READY discipline has no
enforcement. The remaining question is whether the cascade is a
separate mechanism that runs before the gate, or whether the gate is
the cascade.

## Decision

The work-on skill template performs the atomic finalization inline,
before invoking `gh pr ready`. The finalization consists of:

- For single-pr chains: `git rm docs/plans/PLAN-<topic>.md`, then
  `shirabe transition docs/briefs/BRIEF-<topic>.md Done` (if the
  chain has a BRIEF), then `shirabe transition
  docs/prds/PRD-<topic>.md Done`, then a single commit with
  message `docs: finalize chain (PLAN deleted, BRIEF/PRD Done)`.
- For multi-pr chains in the work-completing PR: edit the PLAN
  frontmatter status from Active to Done (one `shirabe transition`
  call would be appropriate if PLAN transitions existed; the
  current workspace edits PLAN frontmatter directly), then `git rm`
  the PLAN file, then transition BRIEF and PRD via `shirabe
  transition` to Done, then commit.
- For multi-pr chains in an intermediate PR: no-op. The chain is at
  its passing in-flight state.

The work-on skill runs `shirabe validate --lifecycle . --strict`
twice: once before the finalization to verify the expected violator
condition is present (which confirms the cascade has work to do),
and once after to verify the chain is now at its passing state.
Push the finalization commit, then run `gh pr ready`.

CI separately runs the reusable lifecycle workflow on every PR. The
workflow's self-caller triggers on `pull_request.types: [opened,
synchronize, reopened, ready_for_review, converted_to_draft]`. On
ready-for-review events the workflow invokes the validator in strict
mode. This is the CI gate: PRs that bypass the cascade (manual
authors who run `gh pr ready` directly) hit the gate, which fails
with a precise error naming the missing transitions.

## Options Considered

### Option A — `ready_for_review` workflow event hook as the cascade

The lifecycle workflow's `ready_for_review` event run is the only
mechanism. There is no work-on cascade; authors are expected to make
the finalization commit themselves (with or without work-on's help)
before flipping the PR to ready.

**Pros.**

- Zero new code in work-on or in the shirabe binary. The workflow
  already exists per R3 and R4; this option uses it as the cascade.
- Single source of truth — the lifecycle check is the only gate,
  and authors learn the discipline by failing it once.

**Cons.**

- The cascade is "fail-and-fix" rather than "atomic finalization."
  Authors mark the PR ready, see the CI failure, push a fix-up
  commit, and the PR sits in a failed state in between.
- Work-on, which is the workspace's primary path for shipping work,
  no longer provides any forcing function for the chain transitions
  — the discipline is enforced only on CI, not at the gesture
  authors actually make.

### Option B — A `shirabe finalize` subcommand

A new subcommand on the shirabe binary that reads the chain at the
working tree, performs the atomic finalization, and exits. Work-on
invokes it before `gh pr ready`; authors can invoke it directly
outside work-on.

**Pros.**

- Reusable. The finalization is exposed as a primitive both
  work-on and other workflows (or manual authors) can call.
- Atomic semantics in the binary, not in a skill template. The
  binary is the right home for chain mutations if multiple
  consumers need them.

**Cons.**

- Adds a new mutation surface to the shirabe binary. Today the
  binary's only mutation surface is `shirabe transition`, which
  mutates a single doc; introducing a multi-doc atomic operation
  that also performs `git rm` is a non-trivial expansion of the
  binary's responsibilities.
- The only known consumer is work-on. Adding a new subcommand
  with one consumer is over-engineering relative to the present
  scope. The subcommand's value lives entirely in hypothetical
  future consumers.
- Test surface expansion. The subcommand has its own state
  machine (which mutations to perform per posture, what to do if
  the working tree is dirty, what to do if `shirabe transition`
  fails partway through) that needs its own test coverage.

### Option C — Work-on skill template performs the finalization inline (chosen)

The cascade lives in the work-on skill template. Before invoking
`gh pr ready`, the skill runs the strict-mode check to find what
needs to change, applies `shirabe transition` to BRIEF and PRD,
runs `git rm` on the PLAN, commits, pushes, and only then runs `gh
pr ready`. The CI workflow's `ready_for_review` event is the
backstop.

**Pros.**

- Uses existing primitives. `shirabe transition` already exists for
  the BRIEF/PRD transitions; `git rm` is a standard operation.
  No new binary code.
- Lives where the discipline is already authored. The work-on
  skill template is the canonical place for "what work-on does
  before marking the PR ready"; the cascade is one more step in
  the template.
- Easy to extend. The skill template can be updated to handle
  posture-specific branches (single-pr, multi-pr work-completing,
  multi-pr intermediate) without touching the binary.

**Cons.**

- Authors who invoke `gh pr ready` directly outside work-on bypass
  the cascade. The CI gate catches them, but the bypass is a
  silent skip rather than an active forcing function.
- The skill template carries logic that is conceptually a
  workspace primitive ("how to finalize a chain"). Future
  consumers needing the same logic would have to duplicate it
  rather than calling a subcommand.

## Consequences

The work-on skill template's koto YAML and SKILL.md are updated to
add a finalization step before `gh pr ready`. The step:

1. Detects chain posture (single-pr vs multi-pr work-completing vs
   multi-pr intermediate) by reading the PLAN's `execution_mode`
   and the chain's open-issue count.
2. Runs `shirabe validate --lifecycle . --strict` and inspects the
   output to confirm the expected violator condition (PLAN
   present, BRIEF/PRD at Accepted for single-pr; PLAN at Done,
   BRIEF/PRD at Accepted for multi-pr work-completing).
3. Performs the transitions atomically: `shirabe transition` for
   BRIEF and PRD, `git rm` for the PLAN, single commit.
4. Pushes the commit, re-runs the strict check to verify the
   chain is at its passing state, and only then invokes `gh pr
   ready`.

The reusable lifecycle workflow is added with the
`ready_for_review` event hook in its self-caller. PRs that
bypass work-on (manual `gh pr ready` invocations) hit the gate
and fail with the expected precise error.

The shirabe binary gets no new mutation surface beyond the
`--strict` flag the sibling decision adds.

A future `shirabe finalize` subcommand may be added if other
consumers need the same logic. The present decision does not
preclude that extension; it defers it until a second consumer
materializes.

## References

- `docs/prds/PRD-lifecycle-draft-ready-discipline.md` — R6 names
  the three alternatives and defers the choice to this decision
  record.
- `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`
  — the sibling decision settling the `--strict` flag interface
  the cascade invokes.
- `skills/work-on/SKILL.md` and `skills/work-on/koto-templates/`
  — the skill template surface the cascade lives in.
