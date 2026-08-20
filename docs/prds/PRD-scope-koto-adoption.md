---
schema: prd/v1
status: Draft
problem: |
  /scope's SKILL.md arrives whole at invocation, so the one passage in it that
  argues an outcome is worth wanting -- a smaller artifact set -- reaches an
  agent before it has done any of the work that argument is meant to judge. An
  agent read it that way and produced only the terminal PLAN, leaving the author
  a plan with nothing above it and no record that anything was skipped. Nothing
  in the run contradicted it: the run writes its own account, and leaving that
  account empty disarms every check that reads it.
goals: |
  An agent reaches the artifact-reduction question holding the two documents
  the question is about. A run that asserted its upstream documents away cannot
  record the same exit as a run that wrote them and folded them in. And the
  difference between the two is legible in a record the run did not author.
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
template's state granularity, the shape of the finalization states, and the
mechanism by which each hop's completion is decided.

**A note on requirement codes.** Three other numbering namespaces are in play:
the shared parent-skill pattern's requirements, `/scope`'s own `SKILL.md` rules,
and `shirabe validate`'s check codes. Every reference to one of those is
qualified in place. A bare `R<n>` in this document always means this document's
own requirement.

## Problem Statement

`/scope` walks an author through four hops and deposits an artifact at each.
Its instructions live in a 968-line `SKILL.md` that a reading agent loads whole
at invocation and never unloads. Exactly one passage in that file argues an
outcome is worth wanting rather than arguing that a rule is correctly written,
and the outcome it argues for is a smaller artifact set. An agent reading the
skill for its purpose finds that one motivated purpose before writing anything.

One did. It produced the terminal PLAN, ran none of the hops above it, and
wrote a Status section asserting the upstream artifacts had been consolidated
away, quoting the skill's own reader-economy sentence as the warrant.

What the author was left with is a plan with no framing, no requirements, and no
architecture above it — and no way to tell that from a run where those documents
were written and then deliberately folded into the plan. `/scope` supports the
second: a chain may legitimately end with one document, because each hop can fold
its upstream into its successor once both exist. The two runs end with the same
file on disk. That is the whole difficulty, and it is why "did the PLAN get
written" is not the question that separates them.

Nothing in the run contradicted the claim, and the reasons are mechanical rather
than incidental.

The run records what it did in a state file the run itself writes. Leaving the
list of executed hops empty does not trip anything — it *disarms* four separate
readers that key on it, including the check that decides whether consolidation
may fire and the tie-break that picks which child a bail routes to. The audit
surface fails open.

A run ends by declaring one of three named exits, and the declaration is the
run's own. Of the three, the one that abandons mid-chain requires a discard
commit an agent must actually author; the one that claims the chain completed
requires nothing at all. The skill's most common exit is its least evidenced, and
the pattern's hard-finalization check passes on a state file claiming a completed
chain with an empty list of executed hops.

And the thirty scenarios that test `/scope` all grade what an agent *says*. A run
that describes the chain correctly and then writes one document passes every one
of them.

## Goals

An agent reaches the reduction question holding the two documents that question
is about. A delivered argument cannot be withdrawn from a transcript, so the goal
is that the general form of it is never delivered.

A run that asserted its upstream documents away cannot record the same exit as a
run that wrote them and folded them in.

The difference between the two is legible in a record the run did not author, and
that record outlives the run.

The BRIEF's no-regression outcome holds: `/scope` stays the same conversation for
the author.

## User Stories

Technical feature; these are use-case descriptions. Each names the requirement it
motivates.

**An agent reaches the fold question honestly** (R2, R3). Scoping a small change,
it receives each hop's purpose as it arrives at that hop. At the fold judgment
it receives the argument for folding and applies it to two documents in front of
it. It may fold three of them. It cannot reach that conclusion at the start,
because at the start nothing stated it.

**An agent tries to finish early** (R6, R7). Having written only a PLAN and no
document above it, it claims the chain completed. The claim is refused, naming
the hops with neither an artifact nor a recorded fold. It can still abandon, and
it can still mark hops skipped — what it cannot do is record a completed chain
it did not walk.

**An author resumes after three days** (R12, R13, R15). They re-invoke against
the same topic. On the same machine the interrupted run is still there to
reattach to. From a fresh clone there is no session to reattach to, and the
committed artifacts on disk are what the run reads — exactly as today.

**A reviewer audits a finished run** (R8, R23). They read a per-hop record
showing which gate passed at each hop and which did not. A run that walked past
a hop left a typed entry saying so, with no gate outcome beside it. The record
is still there after the run ended.

**A maintainer changes an instruction** (R2, R3). They edit the hop that owns
it. The change reaches agents at that hop and no earlier.

## Requirements

### Instruction sequencing

**R1.** `/scope` SHALL be driven by a koto workflow template shipped with the
skill. The template's state granularity is the DESIGN's to choose. `/brief`,
`/prd`, `/design` and `/plan` SHALL continue to be invoked as they are today and
SHALL NOT be modified by this work.

**R2.** None of the following SHALL appear in the **pre-hop set** — defined as
`skills/scope/SKILL.md`, every file its Reference Files table names as
loading before the first hop is entered — including the four it marks as loading
at all phases — every file those in turn name by path, and every workflow
directive delivered before the first hop's state:

  (a) a statement that a smaller artifact set is desirable, stated generally
      rather than about two named documents in hand;
  (b) a per-type summary of what each of the four documents contains.

Both SHALL be delivered at the fold judgment, scoped to the two documents then in
hand. Clause (b) is separate because four sentences summarizing what each
document contains, delivered to an agent holding none of them, is a compression
recipe for the failure this PRD exists to prevent.

**R3.** `skills/scope/SKILL.md` SHALL state, under a named section, why the
chain's hops are taken; SHALL give an operational definition of the term it uses
for a hop's output — what kind of thing such an output is, not what each of the
four types produces; SHALL narrate no withdrawn design in the past tense, so that
every passage reads as instruction to the agent holding the file; and SHALL NOT
contain any sentence in the denylist at Appendix A.

**R4.** Every entry P1 through P6 at Appendix A SHALL have a recorded
disposition: moved to a hop's directive, deleted, or retained, except where
Appendix A marks a disposition illegal for that entry. Which disposition each
receives is otherwise the DESIGN's.

**R5.** No non-terminal state that expects agent evidence SHALL be advanceable
without its directive having been delivered.

### Exit binding

**R6.** A run SHALL NOT record an exit without supplying that exit path's
required fields, and supplying a field declared on exactly one other exit path
SHALL be refused at submission.

**R7.** A full-run exit SHALL be refused unless, for every hop in the chain,
either that hop's durable artifact is present at its canonical path, or that hop
carries a **recorded fold**. The refusal SHALL name the hops satisfying neither.

A hop carries a recorded fold when the surviving document declares that hop in
its `absorbed:` frontmatter and carries the contribution section that declaration
implies — the pairing `shirabe validate`'s FC18 check already enforces. Both
halves are on the filesystem and both land in a diff a reviewer reads, which is
what lets R8 decide this from the artifact tree.

A run that wrote only the terminal artifact and asserted the rest away in prose
carries neither an artifact nor a recorded fold for three hops, and SHALL be
refused.

**R8.** Each hop's completion SHALL be decided from the artifact tree — that
hop's own artifact, or the surviving document's absorption record — and SHALL
NOT be decided from any field of `wip/scope_<topic>_state.md`. The outcome of
that decision SHALL appear in the per-hop record (R23).

The distinction is durability and review, not authorship. A fold is recorded by
an `absorbed:` frontmatter entry plus the contribution section
`shirabe validate`'s FC18 check requires alongside it, both of which land in a
diff a reviewer reads. Forging one is most of the work of performing it. An
empty executed-steps list in the state file costs nothing and nobody sees it.

**R9.** Marking a hop skipped SHALL remain possible, and `chain_skipped:` and the
re-entry protection built on it SHALL keep their present meaning. A skipped hop
SHALL NOT satisfy either limb of R7.

### State and resume

**R10.** `wip/scope_<topic>_state.md` SHALL remain authoritative for every field
it carries today. No field SHALL move out of it.

**R11.** `phase_pointer:` SHALL always name the `/scope` phase the run is in,
derived from the session's position when a session exists. When none exists —
before one is opened, and after one is disposed of — it SHALL be written from
`/scope`'s own phase, and the state file's other fields SHALL be unaffected.

**R12.** The resume ladder SHALL be carried across with every row label and every
row's author-facing prompt text unchanged.

**R13.** The workflow session's name SHALL be derived from the topic slug with a
fixed literal prefix, so that it is reconstructible from the slug alone and
begins with a letter for every slug shirabe's own regex admits. On invocation,
`/scope` SHALL probe for an existing session under that name before opening one,
and SHALL reattach rather than open a second when one is live.

**R14.** The state file SHALL record the workflow session `/scope` opened, so
that ownership of a session is a recorded fact rather than an assumption.

**R15.** A run whose workflow session no longer exists SHALL remain
distinguishable from a run that never started, from the state file's `exit:`
field.

**R16.** `/scope` SHALL NOT run `koto session cleanup` or `koto cancel
--cleanup` against a session not recorded under R14 for the current topic. koto's
own "already exists" error text recommends exactly this remediation, and
following it destroys a concurrent run in another worktree.

**R17.** The chain SHALL commit each hop's durable artifact to the run's own
branch as it lands, as a new commit naming the hop, and SHALL NOT push. The
resume ladder's durable anchor is the artifacts at canonical paths, and an
uncommitted artifact is not durable to a fresh clone or a second worktree.

### Conformance

**R18.** `/scope` SHALL continue to declare `storage_substrate: wip-yaml-md`.
The workflow session holds position within a run; it is not `/scope`'s state
substrate, and this work does not change the pattern's storage axis for either
parent.

**R19.** The shared parent-skill contract SHALL permit a parent to drive its
phases from a workflow session without requiring `/charter` to do so.

**R20.** The contract's Observability Surface SHALL name the workflow
session-status surface and the per-hop record among the surfaces a parent may
read.

**R21.** `DESIGN-scope-consolidation-over-skipping.md` SHALL receive an appended
amendment dated on or after this PRD's acceptance and citing it, recording that
`## Why the Artifact Set Shrinks` and `## Consolidation Judgment` no longer stand
as named `SKILL.md` deliverables. The three by-title citations of those sections
— two in that DESIGN and one in `skills/brief/references/phases/phase-0-setup.md`
— SHALL be updated.

### Observability

**R22.** A hop the run walked past SHALL leave a typed entry in the per-hop
record, distinguishable from a hop whose gate was evaluated.

**R23.** A completed run SHALL leave a per-hop record, authored by the workflow
engine rather than by the run, showing each hop's gate outcome. The record SHALL
be readable after the run has ended.

### Test coverage

**R24.** The eval harness SHALL read `expectations` (falling back to
`assertions`); SHALL materialize `files:` preconditions into the scenario's
working tree; SHALL copy post-run filesystem state into the scenario's output
directory so assertions grade against it rather than against narration; SHALL
support running one scenario N times and reporting a pass rate across those runs;
and SHALL exit non-zero when a scenario grades zero assertions.

**R25.** A deterministic test SHALL run on every pull request, driving a real
workflow session against the shipped template, asserting: that a full-run claim
submitted as evidence is refused when three hops have neither artifact nor
recorded fold; that after the run has ended a walked hop and a bypassed hop are
distinguishable in the per-hop record; and that the general-form reduction
argument is absent from what the session delivers before the first hop and
present at the fold state. The test SHALL confine its session storage to its own
temporary store. When koto is absent it SHALL skip with a message naming the
missing binary rather than fail, and the CI job SHALL install koto explicitly so
that a skip cannot mask a missing dependency — the arrangement
`skills/execute/scripts/settled-branch-record_test.sh` already ships.

**R26.** A static check SHALL run on every pull request over all
`skills/*/koto-templates/*.md` that carry YAML frontmatter, failing any
non-terminal state that can be advanced through without delivering its directive.
The four states in the shipped `/work-on` and `/execute` templates that violate
this rule today SHALL be recorded — as fixes in this work or as a filed
exemption — so the check can be introduced without failing on its own
introduction.

**R27.** At least two model-graded scenarios SHALL assert on files present after
a run. One SHALL assert negatively: that no document under `docs/` claims an
artifact was folded away for a hop with neither that artifact nor a recorded fold
behind it. They SHALL run at least five times, be reported as a pass rate against
a threshold stated in the suite, and SHALL NOT gate a pull request.

## Acceptance Criteria

- [ ] AC1. `koto template compile` on the shipped `/scope` template exits 0 and emits no `warning: W` lines, and `git diff $(git merge-base HEAD main) -- skills/brief/ skills/prd/ skills/design/ skills/plan/` is empty.
- [ ] AC2. `skills/scope/SKILL.md` contains no section titled `## Why the Artifact Set Shrinks`, and Appendix A's pinned sentence returns zero hits across every file in R2's pre-hop set.
- [ ] AC3. Appendix A's pinned sentence occurs exactly once in the compiled template, under the fold state's details, and zero times in the initial state's directive. The four per-type summaries occur only under the fold state.
- [ ] AC4. `SKILL.md` carries a section named for why the chain's hops are taken, and one operational definition of the hop-output term.
- [ ] AC5. Neither Appendix A denylist sentence D1 nor D2 appears anywhere in `skills/scope/`, and `SKILL.md` narrates no withdrawn design in the past tense.
- [ ] AC6. The DESIGN carries a table with one row per Appendix A entry P1 through P6, each row naming a disposition, no row unresolved, and no row naming a disposition Appendix A marks illegal.
- [ ] AC7. No non-terminal state in the shipped `/scope` template carries an evidence block without a guarded transition.
- [ ] AC8. Submitting a full-run exit as evidence, with a PLAN on disk and no artifact or recorded fold for the three hops above it, returns a non-terminal state whose directive names those hops; and no further submission reaches the full-run terminal until the artifact tree changes.
- [ ] AC9. Submitting a full-run exit as evidence, with every hop's artifact present, reaches the full-run terminal.
- [ ] AC10. Submitting a full-run exit as evidence, with the PLAN present and each upstream hop carrying a recorded fold, reaches the full-run terminal.
- [ ] AC11. Submitting an exit without one of that path's required fields is refused at submission, and submitting a field declared on exactly one other exit path is refused at submission.
- [ ] AC12. Each hop's completion check reads that hop's artifact or the surviving document's absorption record, and no hop's completion reads any field of `wip/scope_<topic>_state.md`.
- [ ] AC13. A run marking every hop skipped reaches the abandonment terminal, not the full-run terminal, and `chain_skipped:` names every hop.
- [ ] AC14. Every field name in `skills/scope/references/state-schema.md` appears in at least one write instruction under `skills/scope/`.
- [ ] AC15. During a live session, `phase_pointer:` equals the phase the template's state-to-phase map assigns to the session's current state; with no session, the state file still parses and its other fields are unchanged.
- [ ] AC16. `git diff $(git merge-base HEAD main) -- skills/scope/references/phases/phase-resume.md` shows no change to any row label or any author-facing prompt text.
- [ ] AC17. Against a fixture with an Accepted PRD at the canonical path, no state file and no session, resume emits the `Re-evaluate / Revise / Bail` triad with boundary `prd`.
- [ ] AC18. A second invocation against a live topic advances the existing session; exactly one session directory exists for the topic afterward.
- [ ] AC19. The state file records the session `/scope` opened.
- [ ] AC20. No path in `skills/scope/` invokes `koto session cleanup` or `koto cancel --cleanup`.
- [ ] AC21. A completed run whose session is gone reports its exit from the state file.
- [ ] AC22. After each hop, that hop's artifact is committed.
- [ ] AC23. `skills/scope/SKILL.md` declares `storage_substrate: wip-yaml-md`.
- [ ] AC24. `git diff $(git merge-base HEAD main) -- skills/charter/` is empty, and the shared contract permits a workflow-driven parent without requiring one.
- [ ] AC25. The contract's Observability Surface names the session-status surface and the per-hop record.
- [ ] AC26. `DESIGN-scope-consolidation-over-skipping.md` carries an amendment dated on or after this PRD's acceptance that cites it, and no by-title citation of either removed section remains in the repo.
- [ ] AC27. After a run in which one hop was walked past and one walked, the per-hop record shows a typed entry with no gate outcome for the first and an evaluated gate for the second.
- [ ] AC28. The per-hop record for a completed run is readable after the run has ended.
- [ ] AC29. `scripts/run-evals.sh` reads `expectations`, materializes `files:`, copies post-run filesystem state into the scenario output directory, reports a pass rate across N runs, and exits non-zero on zero graded assertions.
- [ ] AC30. A pull-request test drives a real session and asserts AC8, AC9, AC10, AC11, AC27 and AC28 with no model in the loop.
- [ ] AC31. A pull-request test asserts the reduction argument is absent from what the session delivers before the first hop and present at the fold state.
- [ ] AC32. The static check fails a deliberately malformed non-terminal state, passes every shipped template, and skips files without YAML frontmatter.
- [ ] AC33. Each of the four currently-violating states in `/work-on` and `/execute` is either fixed or listed in an allowlist file the check reads, with an issue reference beside it.
- [ ] AC34. Two model-graded scenarios assert on files after a run, one negatively per R27, reported as a rate over at least five runs against a stated threshold.
- [ ] AC35. `shirabe validate` passes on `docs/prds/PRD-scope-koto-adoption.md`, `docs/briefs/BRIEF-scope-koto-adoption.md`, and `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`. (Chain-wide hygiene; traces to no single requirement.)

## Out of Scope

- **Per-child materialization.** Running the four children as workflow-managed
  sessions. Not foreclosed — materialization is one additional state inside this
  shape — but it buys visibility into children rather than anything this problem
  needs.
- **Post-hoc validation that an agent executed its hops.** A gate the substrate
  holds is not a checker that grades a run afterward.
- **Making a skip impossible.** It is not. A directed transition reads neither
  gates nor transition guards, and a recorded override injects a synthetic pass.
  The property this work delivers is that a skip leaves a mark, and a requirement
  assuming otherwise would be untestable by construction.
- **Reducing total resident context across a run.** Measured, the net change is
  about zero: `/scope`'s own `SKILL.md` is a small fraction of end-of-run load and
  the substrate adds directive traffic on every tick.
- **Moving `/scope`'s closed write-target set** out of `SKILL.md`. The terminal
  artifact's address appears in the Overview's second paragraph and five other
  places in the same file, and the shared security contract requires the set to be
  stated there with concrete paths, so relocating it changes nothing an agent
  knows.
- **`/charter` and the strategic chain.** Divergence is permitted; whether the
  other parent follows is a later question.
- **Hardening koto upstream** so a directed transition cannot bypass a gate. A
  real option in a sibling repo, and not this work.
- **Adding a hard-finalization condition** in the state-file check gating a
  full-run exit on `/plan` appearing in the executed-steps list. R7 reaches the
  same outcome at the substrate, where the run does not author the evidence.

## Decisions and Trade-offs

The four questions the upstream BRIEF deferred, plus two this PRD's research
forced, plus a closing note on two premises that were tested and withdrawn.

**One state store or two.** Two, with disjoint content and one deliberate
overlap. koto absorbing the state file is foreclosed: `parent_orchestration:` is
a parent-to-child interface at a literal path in four children's SKILL.md files,
and a session disposes of itself at the end of a run, before Phase 4. Having koto
hold nothing is today plus a template, and forfeits the one mechanically strong
thing the adoption buys. A projection in either direction needs a durable anchor,
and `/scope` has none mid-chain. Two stores costs the `phase_pointer` overlap,
which R11 resolves with a declared map rather than a reconciliation procedure —
the two values live in different domains, so equality was never the right rule.

**What resume anchors to.** The canonical `docs/` artifacts, unchanged. Sixteen
of the resume ladder's twenty rows key on artifact status, child intermediates,
or the branch, and none of those change. A workflow session is machine-global,
resolves from any working directory, and is gone at the end of a run, so it is a
within-run convenience and not an anchor. One row genuinely breaks — the row
keying on the exit field being set — which R15 addresses. R17 is the precondition
this decision needs: the anchor is durable only once committed, and today only the
discard path commits.

**Ported or replaced.** Ported (R12). The accepted cost is that `/scope` keeps a
resume mechanism partly duplicating what the substrate does natively. Replacing
it would reach the shared pattern contract and through it `/charter`, which this
work explicitly does not move.

**What a test asserts.** The discriminating tests are not evals. Driving a real
session in an isolated store, a full-run claim submitted without the artifacts or
their recorded folds lands in a blocked state, and a bypass leaves a typed entry
with no gate outcome beside it — both deterministic, both gateable on a pull
request (R25). Model-graded scenarios are a reported rate rather than a gate
(R27), because they grade a stochastic process and one red run is a reason to
look. The negative assertion in R27 is the one that speaks to the incident
directly, which is why it is required rather than suggested.

**Whether the session name stays derivable from the topic.** Yes, at the cost of
a wider concurrency prohibition. Today two worktrees can run `/scope foo` at
once; under a topic-keyed session they collide machine-wide. The failure mode
improves — a loud error before anything is written, where today it is a silent
race on one file — and the blast radius widens. Discriminating the name by
worktree was considered and rejected: it costs derivability from the topic, which
R13's reattach probe depends on. R14 and R16 are the guard. A consequence worth
recording: because the session name carries a `scope-` prefix, koto's requirement
that a session id begin with a letter is satisfied for every slug shirabe's own
regex admits, so no additional slug restriction is needed. An earlier draft of
this PRD required one; it was removed after the constraint was tested and found
not to bind.

**How hop completion is decided, as a constraint on the DESIGN.** Only gate
outcomes reach the surviving per-hop record; evidence values do not. A design
satisfying R8's first clause with an asserted field plus a validator would lose
R8's second clause. Stated as a constraint rather than a requirement because
which construct satisfies both is the DESIGN's call.

**One correction to carry into R25's test, verified twice.** A refused exit claim
routes the run to a blocked state whose own `blocking_conditions` is empty; the
failed gate is reported on the state that owns the gate, not on the state the run
lands in. The test must key on the landing state and its directive. An earlier
description of this behaviour said the blocked state names the failing gate, and
its own captured output contradicted it.

**Two premises tested and withdrawn**, recorded so a later reader does not
re-derive them. Appendix A excludes `SKILL.md:508-517` and `SKILL.md:519-530`,
which an earlier analysis counted as withdrawn-design narration; they are
present-tense rules carrying a "no longer" hinge, and deleting them would delete
live content. And an earlier draft carried a requirement rejecting topic slugs
beginning with a digit; it was removed after the constraint was tested against
koto directly and found not to bind under the prefixed session name R13 requires.

## Known Limitations

- The per-hop record is machine-local and keyed to a session id, so it does not
  survive into a later conversation. "Readable after the run has ended" in R23 and
  AC28 means after the workflow session reaches a terminal state, within the
  conversation that drove it; a reviewer on a pull request does not see it, and
  neither does the same author tomorrow in a new session. This is the bound the
  BRIEF was edited in place to state correctly, and it is restated here so the
  requirement cannot be read as promising more. Accepted deliberately: the
  alternative was copying the record into a PR body, which makes the run the
  author of its own audit trail — the property this work exists to remove.
  Neither the copy nor the original is tamper-proof; what differs is who wrote
  it.
- Preserving the richer event log past the end of a run and keeping the engine's
  terminal index entry are mutually exclusive. R23 is written against the surface
  that survives without the trade.
- The per-hop record carries gate outcomes but not evidence values, which is why
  R8 requires completion to be decided from the filesystem. A later requirement
  needing decision *values* durably would have to revisit this.
- R16 is enforced for the code this repo ships: AC20 greps `skills/scope/` for
  both commands. Nothing stops an agent composing either at runtime after reading
  koto's "already exists" error, which recommends exactly that. The cost is
  another worktree's live run.
- The incentive that produced the incident is untouched. A compliant run costs
  roughly 115,000-172,000 tokens of instruction before any conversation, the
  shortcut costs almost nothing, and this work adds directive traffic on the
  compliant side. Nothing here changes that gradient; it changes what a run can
  claim afterward.
- `context_assignments:` is silently discarded by the engine and appears 28 times
  across the two shipped templates (tsukumogami/koto#204,
  tsukumogami/shirabe#335). A template written for this work must not use it.
- `visibility:` and `consumed_upstream:` are mutable on resume, so neither can be
  carried as a template variable, which is immutable for a session's lifetime.
- Five acceptance criteria — AC13, AC15, AC18, AC21 and AC22 — describe behaviour
  only a full `/scope` run produces, and none reduces to a substrate or filesystem
  check. They are verified by the model-graded suite, which R27 keeps off the
  pull-request path, so they are reported rather than gated. AC27 and AC28 are not
  in this set: AC30 puts both on the pull-request path.
- A latent defect this work inherits: the drift-detection trigger in
  `phase-resume.md` is unsatisfiable as written, because the rows that could match
  it require no state file while its condition requires one. Named here so the
  DESIGN decides whether to fix or preserve it.

## Appendix A: Enumerated Passages

The bounded set R3, R4, AC2, AC5 and AC6 refer to. Line numbers are as of this
PRD's acceptance and are pointers, not identifiers; each entry is identified by
its quoted text.

**Pinned sentence for AC2 and AC3.** The load-bearing sentence of the
general-form argument, currently at `SKILL.md:476`:

> Sparing the reader

The fragment is short on purpose. The full sentence — "Sparing the reader that
is worth doing, and it is the only reason `/scope` ever ends a run with fewer
documents than the chain has altitudes" — is hard-wrapped across `SKILL.md:476`
and `:477`, so a fixed-string grep for it returns zero today, before any work.
The pinned fragment sits entirely on `:476`. Any check written against the full
sentence SHALL collapse whitespace first; a check written against the fragment
needs no normalization, which is why the fragment is what AC2 and AC3 name.

**Supporting search terms**, applied across R2's named file set as a
completeness sweep rather than as the criterion itself: `consolidat`, `fold`,
`fewer document`, `reader economy`, `artifact set`, `ceremony`,
`three altitudes`.

**Denylist for R3 and AC5** — quoted verbatim, so the check is a grep. Each is
to be removed or rewritten:

**D1.** > a `full-run` that produces a PLAN at `docs/plans/PLAN-<topic>.md`

   Frames the PLAN as the skill's product rather than as the deposit its
   terminal hop makes.

**D2.** > An author who wants to start above `/brief` still invokes `/design`
   > or `/plan` directly.

   States that entering below the chain head is a sanctioned move, in the file
   whose subject is running the chain. The two sentences that follow it are the
   bound and survive; this one is the licence and does not.

**Passages requiring a disposition under R4.** Numbered separately from the
denylist above, which R3 governs and for which "retained" is not a legal
disposition.

P1. `SKILL.md:472-530`, `## Why the Artifact Set Shrinks` — the general-form
   reduction argument, and the passage the incident agent quoted.
P2. `SKILL.md:532-578`, `## Consolidation Judgment` — the mechanism section, whose
   reader-economy rationale duplicates the correctly-placed copy at
   `references/phases/phase-2-chain-orchestration.md:492-500`.
P3. `SKILL.md:43-46`, stating the reduction conclusion in the file's third
   paragraph; to be rewritten as a bound rather than removed, since four forward
   references depend on the slot.
P4. `SKILL.md:872-881`, narrating a withdrawn design in the past tense. R3
   forbids past-tense narration of withdrawn designs, so "retained" is not a
   legal disposition for this entry.
P5. The eight sites in `SKILL.md` using the hop-output term, whose only
   definition today sits at
   `references/phases/phase-2-chain-orchestration.md:597-600`.
P6. The four per-type declarations of what each document contributes, currently
   distributed across the four format references; R2(b) governs where they may
   be delivered.

## References

- `docs/briefs/BRIEF-scope-koto-adoption.md` — upstream framing.
- `skills/scope/SKILL.md`, `skills/scope/references/state-schema.md`,
  `skills/scope/references/phases/phase-resume.md` — the surfaces this changes.
- `skills/execute/scripts/settled-branch-record_test.sh` — the shipped model for
  the deterministic test R25 requires.
- `references/parent-skill-pattern.md` — the contract R19 and R20 touch.
