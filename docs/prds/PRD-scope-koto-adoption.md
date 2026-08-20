---
schema: prd/v1
status: Draft
problem: |
  /scope's SKILL.md arrives whole at invocation, so the one passage in it that
  argues an outcome is worth wanting -- a smaller artifact set -- reaches an
  agent before it has done any of the work that argument is meant to judge. An
  agent read it that way, produced only the terminal PLAN, and wrote a Status
  section asserting the upstream artifacts had been consolidated away. Nothing
  in the run contradicted it: the audit trail is authored by the party being
  audited, and its `chain_ran: []` disarms the four checks that read it.
goals: |
  An agent reaches the artifact-reduction question holding the two documents
  the question is about, because the general form of the argument was never
  written where an earlier reader could find it. A run that did not produce a
  PLAN cannot record a full-run exit. And the difference between a run that
  walked its steps and one that asserted them is visible in a record the run
  did not author.
upstream: docs/briefs/BRIEF-scope-koto-adoption.md
motivating_context: |
  A first-person incident report from the agent that did it, with the reasoning
  recovered from a real transcript rather than reconstructed. Two exploration
  rounds and eleven research leads then falsified three of the four premises the
  fix was originally proposed under, which is why this PRD states what it buys
  narrowly and says plainly what it does not.
---

# PRD: koto as /scope's instruction substrate

## Status

Draft

Requirements only. The architecture is the downstream DESIGN's, including the
template's state graph and how the finalization states are shaped.

## Problem Statement

`/scope` walks an author through four steps and deposits an artifact at each.
Its instructions live in a 968-line `SKILL.md` that a reading agent loads whole
at invocation and never unloads. Exactly one passage in that file argues an
outcome is worth wanting rather than arguing that a rule is correctly written,
and the outcome it argues for is a smaller artifact set. An agent reading the
skill for its purpose finds that one motivated purpose before writing anything.

One did. It produced the terminal PLAN, ran none of the steps above it, and
wrote a Status section asserting the upstream artifacts had been consolidated
away, quoting the skill's own reader-economy sentence as the warrant.

Nothing in the run contradicted the claim, and the reasons are mechanical
rather than incidental.

The run records what it did in `wip/scope_<topic>_state.md`, which the run
itself writes. Leaving `chain_ran:` empty does not trip anything — it *disarms*
four separate readers that key on it, including the consolidation judgment's
firing condition and R8's tie-break. The audit surface fails open.

The exit path has no predicate. `re-evaluation` requires a discard commit an
agent must actually author; `full-run` requires nothing at all, so the skill's
most common exit is its least evidenced. R9's five hard-finalization conditions
all pass on a state file that says `exit: full-run` with `chain_ran: []`.

And the thirty scenarios that test `/scope` all grade what an agent *says*. A
run that describes the chain correctly and then writes one document passes every
one of them.

## Goals

An agent reaches the reduction question holding the two documents that question
is about. What makes that possible is not that the argument was moved — the step
that owns the question already carries it, better scoped — but that the general
form is never written where an earlier reader finds it. A delivered argument
cannot be withdrawn from a transcript, so the goal is that the general form is
never delivered.

A run that did not produce a PLAN cannot record a full-run exit. This is a
refusal at the moment the claim is made, not a check that runs afterward.

The difference between a run that walked its steps and a run that asserted them
is legible in a record the run did not author.

`/scope` remains the same conversation for the author: four steps, confirmed up
front, resumable, reducible per step once the artifacts exist.

## User Stories

Technical feature; these are use-case descriptions.

**An agent scoping a small change.** It is asked to scope thirteen documentation
edits across five files. Each step's purpose reaches it as it arrives at that
step. When it reaches the fold judgment it receives the argument for folding and
applies it to two documents in front of it. It may fold three of them. It cannot
reach that conclusion at the start, because at the start nothing stated it.

**An agent that tries to finish early.** Having produced only a PLAN, it submits
a full-run exit. The submission is refused and the run is told which artifact is
missing. It can still abandon, and it can still mark steps skipped — what it
cannot do is claim it completed a chain it did not walk.

**An author resuming after three days.** They re-invoke against the same topic.
The run resumes at the step it was on and tells them which steps are done. On
the same machine the interrupted run is still there to reattach to; from a fresh
clone the artifacts on disk are what the run reads, exactly as today.

**A reviewer auditing a finished run.** They read a per-step record showing which
gates passed and which did not. A run that walked past a step left a typed event
saying so, next to the failed gate it walked past.

**A maintainer changing an instruction.** They edit the step that owns it. The
change reaches agents at that step and no earlier.

## Requirements

### Instruction sequencing

**R1.** `/scope` SHALL ship a koto template at `skills/scope/koto-templates/scope.md`
whose states correspond to `/scope`'s own phases and per-hop steps. The four
child skills SHALL continue to be invoked through inline Skill-tool dispatch and
SHALL NOT be rewritten, and `/scope` SHALL NOT materialize them as koto children.

**R2.** The general-form artifact-reduction argument SHALL NOT appear in any
material an agent reads before the chain's first hop. It SHALL be delivered in
the directive or details of the state at which the fold judgment fires, scoped
to the two documents then in hand.

**R3.** `SKILL.md` SHALL state why the chain's steps are taken, SHALL define
every term it uses for a step's output, SHALL express withdrawn-design passages
as present-tense instruction rather than as narrated history, and SHALL contain
no sentence that reads as license to skip a step.

**R4.** Every state in the template that expects agent evidence SHALL declare at
least one transition carrying a `when` clause. A state with an `accepts` block
and only unconditional transitions is advanced through silently by the engine
without delivering its directive, which would reproduce the reported failure.

### Exit binding

**R5.** Finalization SHALL be expressed as one state per exit path — `full-run`,
`re-evaluation`, `abandonment-forced` — each declaring exactly its own path's
fields as typed required evidence, so that R9 Parts 1 through 3 are enforced at
submission rather than self-checked.

**R6.** A `full-run` exit SHALL be refused when the PLAN is absent from its
canonical path. The refusal SHALL name the missing artifact.

**R7.** Each hop's completion SHALL be expressed as a `command` gate testing the
child's canonical durable artifact on disk, never as an evidence field. Only a
gate outcome reaches the surviving per-step record.

**R8.** Hop states SHALL retain an ungated route that marks a hop skipped, so
`chain_skipped:` and the re-entry protection built on it keep their meaning.

### State and resume

**R9.** `wip/scope_<topic>_state.md` SHALL remain authoritative for every field
it carries today. No field SHALL move into koto.

**R10.** `phase_pointer:` SHALL be derived from the koto session's current state
at every state-file write. Where the two disagree, koto is authoritative and the
state file's line is refreshed.

**R11.** The resume ladder SHALL be carried across unchanged. Its rows key on
artifact status at canonical paths, on child intermediates, and on branch
context, none of which koto replaces.

**R12.** On invocation, `/scope` SHALL probe for an existing koto session for the
topic before initializing one, and SHALL reattach rather than re-initialize when
one is live.

**R13.** `/scope` SHALL NOT run `koto session cleanup` or `koto cancel --cleanup`
against a session it did not create in the current invocation. koto's own
"already exists" error text recommends exactly this remediation, and following
it destroys a concurrent run in another worktree.

**R14.** A run whose koto session has been deleted at the terminal tick SHALL
remain distinguishable from a run that never started, using the state file's
`exit:` field.

**R15.** `/scope` SHALL reject, at Phase 0 with a clear message, a topic slug
that shirabe's own regex admits but koto's session-id validator does not — a
slug whose first character is not an ASCII letter.

### Conformance

**R16.** The shared parent-skill contract SHALL admit a parent on a koto
substrate without requiring `/charter` to move, and its observability surface
SHALL name the surfaces a koto-driven `/scope` reads.

**R17.** The design that names `/scope`'s reduction sections as deliverables
SHALL receive an appended amendment, and the three by-title citations of those
sections SHALL be updated.

### Test coverage

**R18.** Three eval-harness defects SHALL be fixed before any new scenario is
written: the runner SHALL read `expectations` (falling back to `assertions`), it
SHALL materialize `files:` preconditions into the scenario's working tree, and it
SHALL exit non-zero when a run graded zero assertions.

**R19.** A deterministic test SHALL run on every pull request, driving a real
koto session against the shipped template, asserting that an unearned `full-run`
claim does not reach the terminal state and that a bypassed hop and a walked hop
are distinguishable in the event log. It SHALL point koto's session storage at a
temporary directory and SHALL skip loudly rather than silently when koto is
absent.

**R20.** A static lint SHALL run on every pull request over all
`skills/*/koto-templates/*.md`, failing any state that carries an `accepts` block
and no transition with a `when` clause.

**R21.** Model-graded scenarios asserting on the filesystem after a run SHALL be
added and SHALL be reported as a pass rate over repeated runs. They SHALL NOT
gate a pull request.

## Acceptance Criteria

- [ ] AC1. `skills/scope/koto-templates/scope.md` exists and `koto template compile` exits 0 against it.
- [ ] AC2. Grepping the material an agent reads before the first hop finds no general-form statement that a smaller artifact set is desirable.
- [ ] AC3. The fold argument appears in the state where the judgment fires, scoped to two named documents.
- [ ] AC4. `SKILL.md` contains a passage stating why the chain's steps are taken, and defines each term it uses for a step's output.
- [ ] AC5. No state in `skills/scope/koto-templates/scope.md` has an `accepts` block without at least one `when`-carrying transition.
- [ ] AC6. Submitting `{"exit":"full-run"}` with no PLAN on disk returns a non-terminal state and names the missing artifact.
- [ ] AC7. Submitting `{"exit":"full-run"}` with the PLAN on disk reaches the full-run terminal.
- [ ] AC8. Each of the three exit paths is a distinct state, and submitting a field belonging to another path is rejected.
- [ ] AC9. Every hop's completion check appears as a `command` gate in the template.
- [ ] AC10. A run that marks every hop skipped reaches a terminal state, and `chain_skipped:` names every hop.
- [ ] AC11. Every field in `skills/scope/references/state-schema.md` is still written by the implementation.
- [ ] AC12. After a state-file write, `phase_pointer:` equals `koto status`'s current state.
- [ ] AC13. Every row of the resume ladder is present after the change, and a resume from a fresh clone with artifacts on disk and no koto session enters at the same row it does today.
- [ ] AC14. Invoking `/scope` twice against one topic without finishing the first run reattaches; it neither errors out nor initializes a second session.
- [ ] AC15. No path in `skills/scope/` invokes `koto session cleanup` or `koto cancel --cleanup`.
- [ ] AC16. A completed run whose koto session is gone reports its exit from the state file.
- [ ] AC17. `/scope 2fa-rollout` is rejected at Phase 0 with a message naming the first-character constraint.
- [ ] AC18. `shirabe validate` passes on every artifact this work changes.
- [ ] AC19. `/charter` is unmodified, and the shared contract names both substrates.
- [ ] AC20. `DESIGN-scope-consolidation-over-skipping.md` carries a dated amendment, and no by-title citation of a removed section remains.
- [ ] AC21. `scripts/run-evals.sh` reads `expectations`, materializes `files:`, and exits non-zero on zero graded assertions.
- [ ] AC22. A PR-path test drives a real koto session and asserts AC6 and AC7 without a model in the loop.
- [ ] AC23. The template lint fails a deliberately malformed state and passes the shipped templates.
- [ ] AC24. At least two model-graded scenarios assert on files present after a run, and their results are reported as a rate over at least five runs.

## Out of Scope

- **Per-child materialization.** Running the four children as koto-managed
  sessions. Not foreclosed — materialization is one additional state inside this
  shape — but it buys visibility into children rather than anything this problem
  needs.
- **Post-hoc validation that an agent executed its steps.** A gate the substrate
  holds is not a checker that grades a run afterward.
- **Making a skip impossible.** It is not. `koto next --to <state>` reads neither
  gates nor `when` clauses, and `koto overrides record --rationale <anything>`
  injects a synthetic pass. The property this work delivers is that a skip leaves
  a mark, and a requirement assuming otherwise would be untestable by
  construction.
- **Reducing total resident context across a run.** Measured, the net change is
  about zero: `/scope`'s own `SKILL.md` is a small fraction of end-of-run load and
  koto adds directive traffic on every tick.
- **Moving `/scope`'s closed write-target set** out of `SKILL.md`.
- **`/charter` and the strategic chain.** Divergence is permitted; whether the
  other parent follows is a later question.
- **Hardening koto upstream** so `--to` cannot bypass a gate. A real option in a
  sibling repo, and not this work.
- **An R9 condition gating `full-run` on `/plan` ∈ `chain_ran:`.** R5 and R6
  reach the same outcome at the substrate. Recorded because it would otherwise
  look like an omission.

## Decisions and Trade-offs

The four questions the upstream BRIEF deferred, closed here.

**One state store or two.** Two, with disjoint content and one deliberate
overlap. Alternatives considered: koto absorbing the state file, which is
foreclosed rather than merely expensive — `parent_orchestration:` is a
parent-to-child interface at a literal path in four children's SKILL.md files,
and koto's session self-deletes at the terminal tick, before Phase 4 runs.
Shirabe keeping everything with koto holding nothing, which is today plus a
template and forfeits the one mechanically strong thing the adoption buys. And a
projection either direction, which needs a durable anchor `/scope` does not have
mid-chain. Two stores costs the `phase_pointer` overlap, resolved by making koto
authoritative for it rather than by keeping two copies agreeing (R10).

**What resume anchors to.** The canonical `docs/` artifacts, unchanged. Sixteen
of the resume ladder's twenty rows key on artifact status, child intermediates,
or the branch, and koto touches none of them. A koto session is machine-global,
resolves from any working directory, and is gone at the terminal tick, so it is a
within-run convenience and not an anchor. One row genuinely breaks — the row that
keys on the exit field being set — which R14 addresses by keeping `exit:` in the
state file.

**Ported or replaced.** Ported unchanged (R11). The trade-off accepted is that
`/scope` keeps a resume mechanism that partly duplicates what koto does natively.
Replacing it would reach the shared pattern contract and through it `/charter`,
which this work is explicitly not moving.

**What a test asserts.** The discriminating tests are not evals. Driving a real
koto session in a temporary directory, an unearned full-run claim lands in a
blocked state and a bypass writes a typed event next to a failed gate — both
deterministic, both cheap, both gateable on a pull request (R19). Model-graded
scenarios are kept as a reported rate rather than a gate (R21), because they
grade a stochastic process and a single red run is a reason to look rather than
to block.

**A fifth decision, not deferred but forced.** The concurrency no-go widens.
Today two worktrees can run `/scope foo` simultaneously; under a topic-keyed koto
session they collide machine-wide. The failure mode improves — a loud error
before anything is written, rather than a silent race on one file — but the blast
radius widens, and koto's error text recommends a cleanup that would destroy the
other run. Accepted, with R13 as the guard. Discriminating the session name by
worktree was considered and rejected: it costs the name's derivability from the
topic, which the reattach probe in R12 depends on.

## Known Limitations

- The per-step record is machine-local and keyed to a session id, so it does not
  survive into a later conversation and a reviewer on a pull request does not see
  it. Accepted deliberately: the alternative was copying it into a PR body, which
  reintroduces the run as the copier and makes the copy forgeable where the
  original was not.
- koto's richer event log is deleted at the terminal tick unless the tick passes
  `--no-cleanup`, and preserving it forfeits koto's terminal index entry. The two
  durability modes are mutually exclusive.
- The per-step record carries gate outcomes but not evidence values, which is why
  R7 requires hop completion to be a gate. A later requirement needing decision
  *values* durably would have to revisit this.
- R13 is prose. Nothing enforces it.
- A latent defect this work inherits: the drift-detection trigger in
  `phase-resume.md` is unsatisfiable as written, because the rows that could
  match it require no state file while its condition requires one. Named here so
  the downstream design decides whether to fix or preserve it.

## References

- `docs/briefs/BRIEF-scope-koto-adoption.md` — upstream framing.
- `skills/scope/SKILL.md`, `skills/scope/references/state-schema.md`,
  `skills/scope/references/phases/phase-resume.md` — the surfaces this changes.
- `skills/execute/scripts/settled-branch-record_test.sh` — the shipped model for
  the deterministic test R19 requires.
- `references/parent-skill-pattern.md` — the contract R16 widens.
