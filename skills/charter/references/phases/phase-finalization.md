# Phase: Finalization (Exit-Path Orchestration)

`/charter`'s finalization phase routes every chain to one of the three
named exits documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` — full-run,
re-evaluation, or abandonment-forced — or, when nothing has been
produced to materialize, to clean-cancel. The three exits are
`/charter`'s parent-specific binding of the pattern-level Three Exit
Paths section; clean-cancel is the explicit fallthrough that prevents
incomplete state from being written when no chain progress exists.

This file owns the **orchestration logic** — which exit fires for each
trigger, which sub-shape applies (when relevant), the R8 three-step
tie-break for "most-recently-running" with its clean-cancel
fallthrough, and the load-bearing distinction between `/strategy`
Phase 5 Reject and mid-chain Bail. The **state-field semantics** are
defined in `skills/charter/references/phases/phase-state-management.md`
(see `<<ISSUE:5>>`); this file cites them rather than re-deriving. The
**artifact authoring** (Decision Record bodies, the HTML-comment
abandonment marker) is owned by a companion outline.

After this orchestration writes the state file, the R9 hard
finalization check (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` and
`skills/charter/references/phases/phase-state-management.md`) runs and
either accepts the state or surfaces a clear error. The orchestration
below produces the writes; the R9 check validates them.

## Table of Contents

- [Three Exits + One Fallthrough](#three-exits--one-fallthrough)
- [Exit 1 — full-run](#exit-1--full-run)
- [Exit 2 — re-evaluation, re-evaluation Sub-Shape (US-2)](#exit-2--re-evaluation-re-evaluation-sub-shape-us-2)
- [Exit 2 — re-evaluation, rejection Sub-Shape (US-3a) and the Reject-vs-Bail Distinction](#exit-2--re-evaluation-rejection-sub-shape-us-3a-and-the-reject-vs-bail-distinction)
- [AC12b — Revise Branch](#ac12b--revise-branch)
- [Exit 3 — abandonment-forced](#exit-3--abandonment-forced)
- [R8 Tie-Break — Most-Recently-Running Resolution](#r8-tie-break--most-recently-running-resolution)
- [Reject vs Bail — The Load-Bearing Distinction](#reject-vs-bail--the-load-bearing-distinction)
- [State-Field References](#state-field-references)
- [Routing-Source Citations](#routing-source-citations)
- [Exit-Artifact Template References](#exit-artifact-template-references)
- [Security Considerations](#security-considerations)

## Three Exits + One Fallthrough

- **Exit 1 — full-run** — the chain completes through its terminal
  artifact (STRATEGY, optionally plus ROADMAP).
- **Exit 2 — re-evaluation** — the chain produces a Decision Record
  rather than re-authoring an artifact. Two sub-shapes:
  - **re-evaluation sub-shape** — the existing STRATEGY's bet still
    holds; the Decision Record records the re-evaluation.
  - **rejection sub-shape** — `/strategy` Phase 5 Reject fired
    INSIDE the `/charter` chain; the Decision Record records the
    rejection with the discard commit SHA.
- **Exit 3 — abandonment-forced** — the author bails mid-chain; the
  most-recently-running child's intermediate is force-materialized
  as a schema-compliant Draft with an HTML-comment marker.
- **Clean-cancel** — the author bails before any chain progress
  exists. NOT an exit value; no state file written, no terminal
  artifact, no contract violation. See R8 Tie-Break below.

## Exit 1 — full-run

### Trigger

Exit 1 fires when `/strategy` completes with a Draft STRATEGY and no
`/strategy` Phase 5 Reject occurs. `/roadmap` MAY also fire per the
R7 gates in
`skills/charter/references/phases/phase-2-chain-orchestration.md`
(both Building Blocks ≥ 3 and at least one non-empty Coordination
Dependencies entry). When `/roadmap`'s gates hold, the chain
completes through STRATEGY + ROADMAP; when they don't, the chain
completes through STRATEGY alone.

### State-Field Assignments

The state file at `wip/charter_<topic>_state.md` is written with:

- `exit: full-run`
- `chain_completed: <ISO-8601 timestamp>` (set at the finalization
  moment)
- `chain_ran: [<children that ran>]` (`/strategy` always; `/vision`
  if R4 fired; `/roadmap` if R7 gates held; the gated feeder if its
  three-condition gate held)
- `exit_artifacts:` populated per the chain shape (see AC coverage
  below)

### AC11a — STRATEGY-only Full-Run

When the chain completes through STRATEGY alone (no `/roadmap`), the
`exit_artifacts` list contains exactly one entry:

```yaml
exit_artifacts:
  - path: docs/strategies/STRATEGY-<topic>.md
    status: Draft
```

### AC11b — STRATEGY + ROADMAP Full-Run

When the chain completes through both children, the `exit_artifacts`
list contains exactly two entries (STRATEGY first, ROADMAP second,
each with its own status):

```yaml
exit_artifacts:
  - path: docs/strategies/STRATEGY-<topic>.md
    status: Draft
  - path: docs/roadmaps/ROADMAP-<topic>.md
    status: Draft
```

### Conditional-Field Absence (R9)

For Exit 1, the following conditional fields MUST be absent from the
state file (not set to null, empty string, or placeholder):
`decision_record_sub_shape`, `referenced_strategy`,
`discard_commit_sha`, `rejection_rationale`, `triggering_child`,
`partial_phase_reached`. R9 conditional-field gating (defined in
`<<ISSUE:5>>`'s state schema and enforced by the R9 hard finalization
check) makes any of these fields' presence a contract violation under
`exit: full-run`.

### Draft STRATEGY Validation Pass-Through (AC24)

Before declaring full-run success, `/charter` MUST invoke
`shirabe validate --visibility=<repo-visibility>` as a sub-process
against the Draft STRATEGY produced by the chain. The pass-through
is the chain-level enforcement gate that catches visibility-gated
content `/strategy` did not catch — `/charter` does NOT re-implement
`shirabe validate`'s checks; it invokes the validator as a sub-process
and surfaces its result.

Procedure:

1. Read the repository visibility from CLAUDE.md's
   `## Repo Visibility:` header (the detection lives in
   `skills/charter/references/phases/phase-1-discovery.md` section
   1.1; the value defaults to Private per R12 when the header is
   missing).
2. **Lowercase the detected value before invoking the validator.**
   The `## Repo Visibility:` header convention in CLAUDE.md uses
   Title Case (`Public`, `Private`) per the visibility-detection
   idiom in
   `skills/charter/references/phases/phase-1-discovery.md` section
   1.1; `shirabe validate`'s `--visibility` flag expects lowercase
   (`public`, `private`). `/charter` lowercases the detected value
   before passing it to the validator: `Public → public`,
   `Private → private`. The case-translation seam lives here, not
   in the detection prose — the detection records the visibility
   in its source convention; the validator invocation translates
   to the validator's expected convention.
3. Invoke `shirabe validate --visibility=<repo-visibility>` as a
   sub-process against the Draft STRATEGY at
   `docs/strategies/STRATEGY-<topic>.md`, substituting the
   lowercased visibility value (`public` or `private`) into the
   flag.
4. On the validator's exit code:
   - **0 (pass)** — proceed to write the Exit 1 state-field
     assignments and declare full-run success.
   - **non-zero (fail)** — surface the validator's error message
     **verbatim** (not absorbed, not paraphrased, not summarized).
     Block chain finalization until the violation is resolved; do
     NOT write `exit: full-run` to the state file. The chain
     remains in progress (the state file's `exit:` field stays
     UNSET) and the author addresses the violation in the Draft
     STRATEGY before re-invoking `/charter` to retry finalization.

The pass-through is NOT a re-implementation of `shirabe validate`.
`/charter` does not duplicate the validator's checks, does not
parse the Draft STRATEGY structurally, and does not maintain its
own visibility-rule list. The validator is the single source of
truth for visibility-gated content rules; `/charter` only invokes
it at chain-level and respects its verdict.

**Canonical example violation.** A public-repo Draft STRATEGY
containing a `## Competitive Considerations` section fails the
validator's R8 check (the visibility-gated-section rule for
public-visibility STRATEGYs). `shirabe validate
--visibility=public` returns non-zero with an error message naming
the offending section; `/charter` surfaces that message verbatim
and blocks finalization. The author either removes the
Competitive Considerations section from the public-repo Draft or
re-declares the repo visibility (in the latter case, the validator
re-passes on next invocation when invoked with
`--visibility=private`).

The pass-through fires only for Exit 1 (full-run); re-evaluation
and abandonment-forced exits produce different artifacts (Decision
Records and force-materialized partials respectively) that go
through their own validation paths owned by the artifact-template
authoring documented in the templates referenced below.

## Exit 2 — re-evaluation, re-evaluation Sub-Shape (US-2)

### Trigger

The re-evaluation sub-shape fires when:

1. The resume-ladder row 5 prompt fires (STRATEGY at
   `docs/strategies/STRATEGY-<topic>.md` is Accepted or Active,
   offering "Re-evaluate / Revise / Bail"), AND
2. The author selects "Re-evaluate", AND
3. `/charter` walks the existing STRATEGY's Bet-Specific
   Falsifiability claims, AND
4. All claims hold (none has been invalidated by new evidence).

The row 5 prompt routing originates from
`skills/charter/references/phases/phase-resume.md`; the routing
decision logic — when re-evaluation fires versus when revision
fires versus when bail fires — lives here.

### State-Field Assignments

The state file is written with:

- `exit: re-evaluation`
- `decision_record_sub_shape: re-evaluation`
- `referenced_strategy: docs/strategies/STRATEGY-<topic>.md` (the
  existing STRATEGY the Decision Record references)
- `chain_completed: <ISO-8601 timestamp>`
- `exit_artifacts:` lists the Decision Record path:
  `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`
  with status `Accepted` (the durable Decision Record artifact)

### Conditional-Field Absence (R9)

For the re-evaluation sub-shape, the following fields MUST be absent:
`discard_commit_sha`, `rejection_rationale`, `triggering_child`,
`partial_phase_reached`. `decision_record_sub_shape: re-evaluation`
gates `referenced_strategy:` ON; the other rejection-sub-shape fields
stay OFF.

## Exit 2 — re-evaluation, rejection Sub-Shape (US-3a) and the Reject-vs-Bail Distinction

### Trigger

The rejection sub-shape fires when `/strategy` Phase 5 Reject fires
**INSIDE** a `/charter` chain. Phase 5 Reject is `/strategy`'s own
deliberate finalization judgment — the author worked through
`/strategy` to its terminal phase, weighed the Draft on its merits,
and consciously chose to reject it. Reject is NOT a bail; it is a
deliberate strategic decision that the Draft STRATEGY's bet is wrong
or unwarranted.

### End-to-End Flow

The rejection sub-shape's full flow:

1. `/charter` invokes `/strategy` against the topic per the chain
   plan.
2. `/strategy` runs through its phases up to Phase 5.
3. At Phase 5, the author chooses Reject.
4. `/strategy` runs the discard procedure:
   - `git rm docs/strategies/STRATEGY-<topic>.md` — the Draft is
     removed from the worktree.
   - Cleans up `wip/strategy_<topic>_*.md` — `/strategy`'s
     intermediate files are removed.
   - Commits `docs(strategy): discard STRATEGY draft for <topic>` —
     the discard commit captures the removal as durable git
     history.
5. Control returns to `/charter`.
6. `/charter` captures the discard commit SHA via read-only
   `git log` — no git writes from `/charter`.
7. `/charter` writes the state file with the rejection sub-shape
   fields.

`/charter` issues **no git writes** during rejection orchestration.
The discard commit is `/strategy`'s responsibility; `/charter` only
captures the SHA via `git log`.

### State-Field Assignments

The state file is written with:

- `exit: re-evaluation`
- `decision_record_sub_shape: rejection`
- `discard_commit_sha: <git SHA from git log>`
- `rejection_rationale: <free-text from the author>` — the prose
  reason the author rejected the Draft, captured at Phase 5
- `chain_completed: <ISO-8601 timestamp>`
- `exit_artifacts:` lists the Decision Record path:
  `docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`
  with status `Accepted`

The Decision Record body itself (the prose that cites the discard
commit SHA and the rejection rationale) is authored by the companion
outline that owns exit-artifact authoring. This orchestration outline
captures the SHA and the rationale into state; the artifact authoring
outline reads from state to write the Decision Record body.

### Conditional-Field Absence (R9)

For the rejection sub-shape, the following fields MUST be absent:
`referenced_strategy`, `triggering_child`, `partial_phase_reached`.
`decision_record_sub_shape: rejection` gates `discard_commit_sha:`
and `rejection_rationale:` ON; the other sub-shape's and Exit 3's
fields stay OFF.

### AC18b — Manual-Fallback Reject Is Non-Retroactive

When `/strategy` Phase 5 Reject fires **OUTSIDE** a `/charter`
chain — the author invokes `/strategy` directly, walks through to
Phase 5, and picks Reject — `/charter` does **not** retroactively
write a rejection Decision Record on a later resume against the
same topic. The rejection sub-shape is `/charter`-orchestrated
only. The resume ladder behavior in
`skills/charter/references/phases/phase-resume.md` enforces this:
nothing in the resume path attempts to reconstruct a Decision
Record from the discard commit, from the absence of a STRATEGY at
the published path, or from any other inferred signal. The discard
commit stands as the durable record on its own.

## AC12b — Revise Branch

### Trigger

The Revise branch fires when the resume-ladder row 5 prompt selects
"Revise" against an existing Accepted STRATEGY. `/charter` invokes
`/strategy` with the existing STRATEGY path as its argument —
`/strategy`'s Input Mode 2 (the lifecycle-verb / resume-from-Accepted
revise flow). `/strategy` produces a revised Draft STRATEGY that
supersedes the prior version on commit.

### State-Field Assignments

The chain exits at `exit: full-run` with the revised STRATEGY in
`exit_artifacts`. The Revise branch produces a full-run exit, NOT a
re-evaluation exit, because `/strategy` produced a revised Draft. No
Decision Record is written; `decision_record_sub_shape:` is absent
per R9.

```yaml
exit: full-run
exit_artifacts:
  - path: docs/strategies/STRATEGY-<topic>.md
    status: Draft
```

This matches the AC11a shape — the Revise branch is a full-run exit
that happens to be authored from a starting point of an existing
STRATEGY. The "revised draft" framing matters because it preserves
the discipline-vs-artifact decoupling: a Revise is the author
electing to produce a new artifact, not the author concluding the
existing artifact is wrong (which would be Reject).

## Exit 3 — abandonment-forced

### Triggers

Exit 3 fires when the author bails mid-chain. Four triggers route
into Exit 3:

1. **Author explicitly says "wrap it up"** — the author types a
   wrap-up phrase mid-conversation; `/charter` recognizes the
   intent and routes here.
2. **Chain-proposal Bail** — the author picks "Bail" at the R7.5
   chain-proposal prompt (originating from
   `skills/charter/references/phases/phase-1-discovery.md` section
   1.5, the chain-proposal confirmation prompt). The Bail routing
   originates there; the routing decision logic — when Bail produces
   abandonment-forced versus clean-cancel — lives here.
3. **Force-materialize at the stale-session prompt** — the
   resume-ladder row 4 prompt (state file `last_updated` ≥ 7 days
   old) offers Resume / Force-materialize / Discard; the author
   picks Force-materialize. The row 4 prompt originates from
   `skills/charter/references/phases/phase-resume.md`; the routing
   decision logic lives here.
4. **Resume-ladder row 4 fires** AND the author chooses
   Force-materialize. (Triggers 3 and 4 are the same case; trigger 3
   names the prompt option and trigger 4 names the ladder row that
   produces the prompt — both fire on `≥ 7 days` stale state.)

### State-Field Assignments

The state file is written with:

- `exit: abandonment-forced`
- `triggering_child: <child-name>` — the child that was running at
  time of bail, resolved via the R8 tie-break (see below)
- `partial_phase_reached: <phase-name>` — the phase pointer the
  triggering child had reached when the chain bailed
- `chain_completed: <ISO-8601 timestamp>`
- `exit_artifacts:` lists the force-materialized partial artifact
  path with status `Draft`

### Conditional-Field Absence (R9)

For Exit 3, the following fields MUST be absent:
`decision_record_sub_shape`, `referenced_strategy`,
`discard_commit_sha`, `rejection_rationale`. The R9 hard finalization
check (in `<<ISSUE:5>>`'s schema spec) enforces this. Notably,
`decision_record_sub_shape: null` under `exit: abandonment-forced` is
a contract violation, not a "field present but unset" — the field is
omitted from the YAML body entirely.

### Force-Materialized Artifact Shape

The artifact force-materialized is the child resolved by the R8
tie-break (next section). The artifact is a schema-compliant Draft
for the child's normal terminal artifact shape (e.g., a Draft
STRATEGY at `docs/strategies/STRATEGY-<topic>.md` if `/strategy` was
the triggering child), with an HTML-comment marker embedded in the
Status section of the artifact body:

```
<!-- charter-status-block: abandonment-forced; ... -->
```

The marker carries the abandonment metadata (triggering child,
partial phase reached, the `wip/charter_<topic>_state.md` path for
the durable record). The marker authoring (specific marker content,
placement in the artifact body, schema compliance) is owned by the
companion outline that writes exit artifacts; this orchestration
outline names the marker convention and forwards the responsibility.

### AC14b — Bail Inside an Invoked Child

When the author bails **inside** an invoked child (`/vision`,
`/comp` if active, `/roadmap`, not just `/strategy`), the resume
ladder on the next entry routes to abandonment-forced per US-3b
semantics. The triggering child is resolved via the R8 tie-break
below — the most-recently-running child at the time of bail is the
one whose intermediate is force-materialized.

This generalizes Exit 3 across all invoked children, not just
`/strategy`. The bail-inside-child case is symmetric to the
bail-at-the-chain-proposal-prompt case: the most-recently-running
child gets force-materialized, regardless of which specific child it
is.

## R8 Tie-Break — Most-Recently-Running Resolution

When abandonment-forced fires, `/charter` resolves which child's
intermediate to force-materialize via a **three-step procedure** with
explicit clean-cancel fallthrough. The steps run in order; the first
step that resolves to a child takes the child as the
`triggering_child`. Step 3 is the clean-cancel fallthrough.

### Step 1 — Last Entry in `chain_ran`

Take the last entry in the state file's `chain_ran` field. If
`chain_ran` is non-empty, that child is the most-recently-running;
the tie-break resolves to it and `triggering_child` is set to the
child name. Proceed to artifact materialization.

If `chain_ran` is empty (no child has completed within the chain),
proceed to step 2.

### Step 2 — First `planned_chain` Entry with Non-Empty wip/

Take the first entry in `planned_chain` that has a non-empty wip/
intermediate on disk. The check inspects the documented partial-run
filenames per child (e.g., `wip/strategy_<topic>_discover.md` for
`/strategy`, `wip/vision_<topic>_scope.md` for `/vision`, the
analogous filenames for `/roadmap` and the gated feeder if any).

If such a child is found, the tie-break resolves to it and
`triggering_child` is set to the child name. Proceed to artifact
materialization.

If no `planned_chain` entry has a non-empty wip/ intermediate,
proceed to step 3.

### Step 3 — Clean-Cancel Fallthrough

When neither step 1 nor step 2 resolves to a child — no `chain_ran`
history exists AND no `planned_chain` entry has a wip/ intermediate
on disk — the chain ends with **clean-cancel**.

Clean-cancel means:

- **No state file is written.** The state file at
  `wip/charter_<topic>_state.md` is NOT created (or, if it already
  exists from Phase 0, is removed).
- **No terminal artifact is produced.** No STRATEGY, no Decision
  Record, no abandonment-forced partial; nothing gets force-
  materialized because nothing exists to materialize.
- **No `exit:` value is written.** The chain ends without recording
  an exit because there is no chain progress to record.

Clean-cancel is **NOT a contract violation** of the three-exits
invariant (semantic invariant I-2 in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`). The
invariant requires every chain that produces a terminal artifact to
record an exit; a clean-cancel chain produces no terminal artifact
because the chain never started in a load-bearing sense. Phase 0
state-file creation occurred (per Phase 0's spec), but no chain
progress followed; tearing down the empty state file is correct.

### AC12c — Chain-Proposal Bail Routing

The R8 tie-break governs the routing of every Bail event. At the
R7.5 chain-proposal Bail (or any other Bail trigger):

- **With no prior wip/ intermediate AND no `chain_ran` history** —
  the chain ends with clean-cancel (R8 step 3).
- **With prior wip/ intermediate OR `chain_ran` history** — the
  chain ends with abandonment-forced (R8 step 1 or step 2 resolves
  the triggering child).

A chain-proposal Bail fired immediately after Phase 1 with no child
invocation and no prior partial wip/ artifacts is the canonical
clean-cancel case; a Bail fired after several phases or after a
prior session left wip/ artifacts is the canonical
abandonment-forced case.

## Reject vs Bail — The Load-Bearing Distinction

`/strategy` Phase 5 Reject and mid-chain Bail look superficially
similar — both terminate a `/charter` chain without producing a
Draft STRATEGY in the conventional full-run shape. They are NOT
the same. Conflating them collapses the design's discipline-vs-
artifact decoupling and silently absorbs chain abandonments into
Decision Records.

### `/strategy` Phase 5 Reject → rejection sub-shape of Exit 2

- The author worked through `/strategy` to its terminal Phase 5.
- The author weighed the Draft STRATEGY on its merits.
- The author chose Reject as a deliberate strategic finalization
  judgment.
- `/strategy` discarded the Draft and committed the discard.
- `/charter` writes a re-evaluation exit with the rejection
  sub-shape, capturing the discard SHA and the rejection rationale.
- The Decision Record is the durable artifact recording the
  judgment.

### Bail mid-chain → Exit 3 abandonment-forced

- The author abandoned the chain before any child reached a
  deliberate finalization judgment.
- The triggers are mid-chain interruptions: "wrap it up", the
  chain-proposal Bail option, the stale-session Force-materialize
  prompt, the resume ladder row 4 firing with author Force-
  materialize selection.
- `/charter` force-materializes the most-recently-running child's
  intermediate as a Draft with the HTML-comment marker.
- The partial artifact is the durable trace of the abandonment.

### Why the Distinction Is Load-Bearing

The design's discipline-vs-artifact decoupling rests on this
distinction. Conflating Reject (a deliberate finalization
judgment) with Bail (an interruption) would:

- **Silently absorb chain abandonments into Decision Records.** A
  Bail fired in the middle of `/strategy` would produce a Decision
  Record claiming the author "rejected" the STRATEGY — but the
  author never weighed the Draft, never reached the deliberate
  judgment; the abandonment was an interruption.
- **Erase the discard commit signal.** Reject's durable evidence is
  the discard commit plus the Decision Record; Bail's durable
  evidence is the force-materialized partial. Treating them
  identically loses the distinction between "I made a strategic
  judgment" and "I had to stop".
- **Collapse the discipline-vs-artifact axis.** The pattern
  distinguishes strategic discipline (Decision Records) from
  authored artifacts (STRATEGY drafts); Bail produces an authored
  partial, Reject produces a strategic Decision Record. Collapsing
  them collapses the axis.

The two paths are documented as distinct contract paths so a future
reader cannot conflate them. The tie-break (above) resolves Bail's
triggering child; the rejection-sub-shape flow (Exit 2 section
above) resolves Reject's discard SHA capture. They never share a
state-field combination — the R9 conditional-field gating in
`<<ISSUE:5>>`'s schema spec makes Reject's `decision_record_sub_shape:
rejection` mutually exclusive with Bail's `triggering_child:` and
`partial_phase_reached:`.

## State-Field References

Every state field this orchestration writes is defined in
`skills/charter/references/phases/phase-state-management.md` (the
`/charter` state-schema spec from `<<ISSUE:5>>`). Field semantics are
not re-derived here:

- `exit` — see Full Field Schema § exit
- `decision_record_sub_shape` — see Conditional Fields §
  decision_record_sub_shape
- `chain_ran` / `chain_completed` — see Always-Present Fields §
  chain_ran / chain_completed
- `exit_artifacts` — see Always-Present Fields § exit_artifacts
- `referenced_strategy` — see Conditional Fields §
  referenced_strategy
- `discard_commit_sha` / `rejection_rationale` — see Conditional
  Fields § discard_commit_sha / rejection_rationale
- `triggering_child` / `partial_phase_reached` — see Conditional
  Fields § triggering_child / partial_phase_reached

The R9 hard finalization check (defined in the state-schema spec)
runs immediately after this orchestration writes the state file. The
check verifies the exit-field consistency above; orchestration
writes that violate the check (e.g., a stray `referenced_strategy`
under `exit: full-run`) surface as clear errors at finalization.

## Routing-Source Citations

Two of the four abandonment-forced triggers originate in other
phase reference files; the routing decision logic for both lives
here.

- **R7.5 chain-proposal Bail** originates in
  `skills/charter/references/phases/phase-1-discovery.md` section
  1.5 (the Chain-Proposal Confirmation Prompt). The prompt option
  lives there; the routing decision (when Bail produces
  abandonment-forced versus clean-cancel) lives here in the R8
  tie-break.
- **Resume-ladder row 4 Force-materialize** originates in
  `skills/charter/references/phases/phase-resume.md` (the
  stale-session prompt at row 4). The prompt option lives there;
  the routing decision (Force-materialize maps to abandonment-
  forced, tie-break resolves the triggering child) lives here.

This file is the single home for the exit-routing decisions; the
prompt-emitting outlines are the origination sources.

## Exit-Artifact Template References

Each exit produces a durable artifact whose body shape is specified
by a template under `skills/charter/references/templates/`. The
orchestration above writes the state-file fields each artifact
consumes; the templates specify the artifact body content and (for
the abandonment-forced marker) the placement rules.

- **Re-evaluation Decision Record** — template at
  `skills/charter/references/templates/decision-record-re-evaluation.md`.
  Populated when Exit 2 fires with the re-evaluation sub-shape.
  Filename: `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`.
- **Rejection Decision Record** — template at
  `skills/charter/references/templates/decision-record-rejection.md`.
  Populated when Exit 2 fires with the rejection sub-shape.
  Filename: `docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`.
- **Abandonment-forced HTML-comment marker** — snippet plus
  placement instructions at
  `skills/charter/references/templates/abandonment-forced-marker.md`.
  Emitted into the force-materialized artifact's existing Status
  section when Exit 3 fires; the host artifact type (STRATEGY,
  VISION, or ROADMAP) is determined by the R8 tie-break above.

Each template names the state-file fields it consumes at runtime
population (see `<<ISSUE:5>>`'s state schema for the field
semantics).

## Security Considerations

The exit-path orchestration is the contract enforcement surface for
semantic invariant I-2 (every chain ends at a durable file). Mis-
routed exits, silently-lost bails, and conflated Reject/Bail paths
are contract violations that produce durable evidence on public-repo
feature branches from push time. The security properties below bound
the orchestration's permitted behavior.

### Three-Exits Invariant Enforced

Every chain orchestrated by `/charter` terminates at exactly one of
`{full-run, re-evaluation, abandonment-forced}` OR at clean-cancel
when nothing exists to materialize. Bail never silently loses; the
R8 tie-break either resolves to a child (producing abandonment-
forced) or to clean-cancel (no contract violation). The invariant is
semantic invariant I-2 from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`.

### Tie-Break Clean-Cancel Fallthrough

Step 3 of the R8 tie-break explicitly prevents writing incomplete
state when nothing exists to force-materialize. The clean-cancel
case ends the chain with NO state file, NO terminal artifact, and NO
`exit:` value written. Without the explicit fallthrough, a Bail
event with no prior chain progress would either write an empty
`exit: abandonment-forced` state (corrupting the contract) or fail
silently (violating the three-exits invariant).

### Reject vs Bail as Distinct Contract Paths

Reject (deliberate `/strategy` Phase 5 finalization judgment) and
Bail (mid-chain abandonment) are documented as distinct contract
paths. Conflating them would collapse the design's discipline-vs-
artifact decoupling and silently absorb chain abandonments into
Decision Records. The state-field assignments above enforce the
distinction structurally — `decision_record_sub_shape: rejection`
and `triggering_child:` never co-occur; the R9 check makes their
co-occurrence a contract violation.

### Read-Only Git for Discard SHA Capture

The discard commit SHA in the rejection sub-shape is captured via
read-only `git log` (e.g., `git log -1 --pretty=%H -- <path>`).
`/charter` issues NO git writes during exit orchestration. The
discard commit itself is `/strategy`'s responsibility (`/strategy`
runs `git rm` and the commit); `/charter` only reads the SHA from
git history.

### `rejection_rationale` Treated as Opaque Free-Text

The `rejection_rationale` free-text field is captured from the
author's Phase 5 Reject input and stored in state for the Decision
Record body authoring (a companion outline). The exit orchestration
MUST NOT echo `rejection_rationale` content into other state fields
where it could be parsed differently; it is treated as opaque text
passed to the downstream artifact authoring step. Echoing the text
into a parsed field (e.g., a structured "rejection reason category"
field) would introduce a contract-confusion vector — the same prose
would mean different things in different fields.

### AC18b Non-Retroactivity Enforced

Manual-fallback `/strategy` Reject (outside a `/charter` chain) does
NOT retroactively produce a rejection Decision Record. The rejection
sub-shape is `/charter`-orchestrated only; the resume-ladder
behavior in
`skills/charter/references/phases/phase-resume.md` enforces this
(nothing in the resume path synthesizes a Decision Record from
inferred signals). The non-retroactivity rule prevents fabricated
audit trails — `/charter` does not narrate decisions the author did
not take through `/charter`.

### R9 Conditional-Field Gating Enforced per Exit

Each exit's state-field assignments include an explicit absence
requirement for fields that do not apply. Examples:
`decision_record_sub_shape` MUST be absent for `exit: full-run` and
`exit: abandonment-forced`; `triggering_child` MUST be absent for
`exit: full-run` and `exit: re-evaluation`; `referenced_strategy`
MUST be absent for `exit: full-run` and `exit: abandonment-forced`
and for the rejection sub-shape of `exit: re-evaluation`. The R9
hard finalization check enforces this.

### No Third-Party Dependencies

This file is documentation only. No third-party libraries are
introduced; the orchestration uses only filesystem reads and
read-only `git log`. No executable code is added in this issue; the
runtime that implements the orchestration logic is part of the
`/charter` skill's main flow, and the validation that enforces R9
lives in the state-schema spec from `<<ISSUE:5>>`.

### Public-Repo Durable-Evidence Surface

The state file at `wip/charter_<topic>_state.md` is durably public
on feature branches from the moment the branch is pushed (squash-
merge removes the file from main's history but not from the feature
branch's pre-merge commits). Two fields in the exit orchestration
above are user-supplied free-text or path-shaped:

- **`rejection_rationale`** — author's prose explaining the
  rejection. Durable on the feature branch pre-merge; public.
- **`triggering_child`** — child name string. Not free-text but
  identifies which child was running when the chain bailed.
- **`referenced_strategy`** — path string. The path itself is
  unlikely to be sensitive, but the STRATEGY body it points at is
  also durably public on the feature branch.

Authors MUST NOT paste secrets, customer-identifiable context, or
unpublished competitive positioning into the `rejection_rationale`
field. The discipline matches the broader free-text discipline
documented in
`skills/charter/references/phases/phase-state-management.md`'s
Security Considerations section; this file names the rule again at
the field level where it is most relevant.
