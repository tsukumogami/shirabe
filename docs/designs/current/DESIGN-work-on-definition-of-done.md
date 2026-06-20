---
status: Current
problem: |
  `/work-on`'s single-issue completion is the agent's discretionary judgment, which accepts
  authored-but-unrun verification and lets the agent ship unilateral caveats/deferrals.
  PRD-work-on-definition-of-done requires completion to become a workflow-enforced gate
  (verified-by-execution, project-declared verification, no silent deferral) without coupling
  the generic skill to any one project's verification commands.
decision: |
  Encode the definition of done in the `/work-on` koto template as a verification-execution
  gate plus a hardened finalization with no silent-deferral path: a new `verification` state
  runs the project-declared verification for what the issue touched and requires pass; the
  `finalization` state's `deferred` outcome routes to a blocking human-approval gate instead
  of a clean terminal. The verification map is project-declared in the existing
  `.claude/shirabe-extensions/work-on.md` extension (path-glob → command), consumed by the
  generic skill; shirabe ships its own extension declaring `skills/** → run-evals.sh` must
  pass. No new CLI subcommand — the skill runs existing project tooling (author-by-skill,
  check-by-existing-verification).
rationale: |
  Reusing the koto state machine and the existing project-extension hook keeps the change
  small and consistent with how `/work-on` already learns project-specific behavior. Holding
  the principle in the generic skill and the commands in project config is the only split
  that keeps `/work-on` general while making "done" enforceable. Fail-closed on
  cannot-verify is the crux: "can't verify" must never read as "verified". Adding no CLI
  honors the established author-by-skill / check-by-validate-or-existing-tooling pattern.
upstream: docs/prds/PRD-work-on-definition-of-done.md
---

# DESIGN: work-on Definition of Done

## Status

Current

## Context and Problem Statement

`/work-on` is narrowing to a single-issue executor; finishing one issue cleanly is its whole
job. Today the point at which it declares the issue done is a koto `finalization` state whose
`finalization_status` accepts `deferred_items_noted` as a clean terminal, and nothing in the
workflow runs the verification appropriate to what the issue changed — the agent decides.
PRD-work-on-definition-of-done requires completion to become an enforced gate:
verified-by-execution (R1, R2), project-declared with a repo-test default (R3, R7, R8),
no silent deferral (R4, R5, R6), fail-closed when verification can't be determined (R11),
single-issue only (R10), reusing existing tooling (R12), and announced (R13). shirabe's own
instance (R9) requires an issue changing a skill to have that skill's evals executed and
passing — the gap that motivated this effort.

## Decision Drivers

- **PRD R7 — generic skill carries no project-specific commands.** `/work-on` is used on any
  project; the verification commands must be project-declared, not baked in.
- **PRD R2/R11 — execution-not-existence, fail-closed.** The gate must run verification and
  require pass; "cannot verify" must route to a human decision, never silently pass.
- **PRD R4/R5 — no silent deferral.** The existing `deferred_items_noted` clean-terminal is
  the exact loophole; deferral must become a surfaced, human-approved decision.
- **Reuse over new surface.** Prefer the existing koto state machine, the existing
  `.claude/shirabe-extensions/work-on.md` hook, and existing runners (`run-evals.sh`, the repo
  test command) over new mechanisms — consistent with the `CLAUDE.md` "author with skills,
  check with validate" pattern (no artifact/▸verification CLI subcommand).

## Considered Options

### Decision A — Where the gate lives in the koto workflow

- **Chosen: a `verification` state before `finalization`, plus a hardened `finalization`
  with no silent-deferral path.** The new `verification` state runs the project-declared
  verification for the issue's touched artifact types and requires pass to advance; evidence
  carries the commands run and their results. `finalization` then accepts `ready_for_pr` only
  with that evidence present, and its deferral outcome routes to a blocking human-approval
  gate (Decision E) rather than terminating clean.
- *Alternative — fold verification into the existing `qa_validation` panel.* Rejected: the
  panel is a review of code quality; conflating "run the project's verification and require
  pass" into it muddies two concerns and hides the gate inside a review step.
- *Alternative — a standalone blocking gate only (no state).* Rejected: the verification
  needs to run commands and capture evidence, which is a state's job; a bare gate has no
  place to record what ran.

### Decision B — How a project declares its verification

- **Chosen: extend the existing `.claude/shirabe-extensions/work-on.md` hook with a
  verification map** — a list of `path-glob → verification command(s)` entries the generic
  skill reads. `/work-on` already consults this extension for project-specific quality and PR
  requirements, so the map has a natural home and no new file is introduced.
- *Alternative — a `CLAUDE.md` header.* Rejected: headers suit single scalar preferences;
  a glob→command map is structured config that belongs in the extension the skill already reads.
- *Alternative — a new dedicated config file.* Rejected: a second project-config surface for
  `/work-on` when one already exists.

### Decision C — Detecting what the issue touched

- **Chosen: classify the issue's diff against the map's path-globs.** The gate takes the
  changed files of the issue's branch (`git diff` against the base), matches them against the
  verification map's globs, and runs each matched entry's command. A change matching multiple
  entries runs each; a change matching none falls through to the default (Decision D).
- *Alternative — infer artifact types from the issue body/labels.* Rejected: the diff is
  ground truth for what changed; issue metadata is not.

### Decision D — Default and fail-closed (PRD R3, R11)

- **Chosen: default to the repo's standard test command; fail closed when neither a map entry
  nor a default applies.** When no map entry matches the diff, the gate runs the repo's
  standard test command (declared in the extension as the default, or detected from the
  repo's conventional runner). When no map entry matches AND no default test command can be
  determined or the verification cannot execute, the gate yields **cannot-verify** and routes
  to the no-silent-deferral human gate (Decision E) — it never passes on absence of
  verification.
- *Alternative — pass when no verification is found.* Rejected outright: silent-pass on
  absence is the precise failure mode this design exists to prevent.

### Decision E — No silent deferral and deferral capture (PRD R4, R5, R6)

- **Chosen: deferral is a blocking human-approval gate; approval is recorded; caveats are
  gated on approval.** Any unmet acceptance criterion, a `cannot-verify` outcome, or a failed
  verification halts `/work-on` and surfaces the specifics to the human as an explicit
  decision: approve the deferral or treat the issue as **blocked**. On approval, the deferral
  is recorded as the human's decision via `koto decisions record` and surfaced in the PR body
  (the audit trail). Unapproved caveat/hedge language in shipped artifacts is disallowed by
  the finalization checklist — a caveat is legitimate only where it records an approved
  deferral, so R6 is enforced by R4/R5 (no approval ⇒ no caveat) plus an explicit
  finalization check, not by a brittle word-grep.
- *Alternative — keep `deferred_items_noted` as a clean terminal with a note.* Rejected: that
  is the loophole the PRD closes; a note is not a human decision.
- *Alternative — a hard CI grep for hedge words.* Rejected as the primary mechanism
  (false-positive-prone; "experimental" is sometimes legitimate). Available as an optional
  future backstop, not the enforcement.

### Decision F — Where shirabe declares its own map (PRD R9)

- **Chosen: shirabe ships `.claude/shirabe-extensions/work-on.md` in its own repo** declaring
  the verification map entry `skills/** → scripts/run-evals.sh <skill>` (evals must run and
  pass) plus the repo default test command (`cargo test --workspace` and the bash harnesses).
  The extension is consumer-side by design; for `/work-on` operating on shirabe-the-repo, the
  file must exist in shirabe's working tree, so shipping it here is what makes shirabe enforce
  its own rule. This makes `/work-on` enforce the existing `CLAUDE.md` `## Skill Evals`
  contract (run, not just exist) rather than relying on the existence check.
- *Alternative — special-case shirabe in the generic skill.* Rejected: violates R7 and the
  generic/project split; shirabe is just the first project to declare a map.

## Decision Outcome

`/work-on` gains a `verification` state that, for a single issue, classifies the issue's diff
against the project's declared verification map (read from
`.claude/shirabe-extensions/work-on.md`), runs each matched verification (defaulting to the
repo's test command), and requires every run to pass before advancing. The `finalization`
state requires that verification evidence and treats any unmet criterion, failed
verification, or `cannot-verify` outcome as a **blocking human decision** — approve-and-record
a deferral, or report the issue blocked — eliminating the silent `deferred_items_noted`
terminal. The generic skill holds this whole discipline; the verification commands live in
project config; shirabe ships its own extension declaring the eval gate. No new CLI
subcommand is added — the gate runs the project's existing tooling, consistent with shirabe's
author-by-skill / check-with-existing-verification pattern.

This is single-issue only (R10): the gate binds the per-issue completion point and does not
define completion for a plan or coordinated set, which the implementation-altitude
coordinator owns.

## Solution Architecture

Components:

- **`/work-on` koto template** (`skills/work-on/koto-templates/work-on.md`) — add the
  `verification` state between `qa_validation` and `finalization`; change `finalization` so its
  deferral path routes to a blocking human-approval gate and `ready_for_pr` requires
  verification evidence. The single-issue template is the target; the plan template is out of
  scope (R10).
- **`/work-on` SKILL.md** — prose for the `verification` state: read the project's verification
  map from the extension, classify the issue diff (Decision C), run matched commands (default
  per Decision D), capture pass/fail evidence, fail closed to the human gate on cannot-verify,
  announce what ran (R13). Bind to the extension contract; do not encode commands.
- **Project-extension contract** (`.claude/shirabe-extensions/work-on.md`) — documented
  schema for the verification map: `path-glob → command(s)` entries plus an optional default
  test command. Generic, project-agnostic.
- **shirabe's extension** (`.claude/shirabe-extensions/work-on.md`, shipped in this repo) —
  declares `skills/** → scripts/run-evals.sh <skill>` and the repo default test command (R9, F).
- **No CLI change.** The gate uses `git diff`, the project's declared commands, and existing
  runners (`run-evals.sh`, `cargo test`, bash harnesses). Per the `CLAUDE.md` CLI-surface
  pattern, no `shirabe` subcommand is added for this.

Data flow: `/work-on` finishes implementation + panels for one issue → `verification` state
classifies the issue diff against the project map → runs each matched verification (or the
default) → all pass ⇒ `finalization` with evidence ⇒ `ready_for_pr`; any fail / unmet
criterion / cannot-verify ⇒ blocking human gate ⇒ approve-and-record-deferral or `blocked`.

## Implementation Approach

1. **Extension contract + shirabe's declaration** — document the verification-map schema in
   the extension contract and ship shirabe's `.claude/shirabe-extensions/work-on.md`
   (`skills/** → run-evals.sh`, default `cargo test --workspace` + bash harnesses). Cheap;
   unblocks the rest and is independently useful.
2. **`verification` state** — add the koto state + SKILL.md prose: diff classification, run
   mapped/default verification, capture evidence, announce, fail closed.
3. **`finalization` hardening** — remove the silent `deferred_items_noted` terminal; route
   deferral to the blocking human gate; require verification evidence for `ready_for_pr`;
   record approved deferrals via `koto decisions record` and in the PR body.
4. **Evals** — add/extend `skills/work-on/evals/evals.json` for the gate behaviors
   (verified-by-execution, fail-closed, no-silent-deferral) and run them (the rule this
   feature enforces applies to itself).

## Security Considerations

The surface is small: `/work-on` runs project-declared shell commands from
`.claude/shirabe-extensions/work-on.md`. That file is repo-controlled config (same trust level
as the skill extensions `/work-on` already executes), so it introduces no new trust boundary —
but the verification map's commands MUST be treated as the project's own (not derived from
issue text or other untrusted input). The diff classification reads file paths only. No new
network or credential surface; the gate runs existing local tooling. No new CLI, so no new
argument-injection surface.

## Consequences

Positive:

- "Done" becomes verified-by-execution and enforced by the workflow, closing the
  authored-but-unrun and silent-deferral gaps directly.
- The generic/project split keeps `/work-on` general; any project gets the discipline by
  declaring a map, and the repo-test default means the gate binds even with no declaration.
- Reuses the koto state machine, the existing extension hook, and existing runners — small,
  consistent surface; no new CLI.

Negative / mitigations:

- A project with no map and no detectable test command hits the fail-closed human gate every
  run; mitigation: declaring a one-line default test command removes it — fail-closed is the
  safe direction (R11), not an accident.
- R6 caveat enforcement is checklist-plus-deferral-gate rather than a mechanical detector;
  mitigation: caveats are gated on approved deferrals (R4/R5), so an unapproved caveat has no
  legitimate path to ship; a CI grep remains available as an optional backstop.
