# /scope Handoff: scope-koto-adoption

## Provenance

Written by `/explore` on 2026-08-20 from
`wip/explore_scope-koto-adoption_crystallize.md`. Research files:
`wip/explore_scope-koto-adoption_findings.md`,
`wip/explore_scope-koto-adoption_decisions.md`, and
`wip/research/explore_scope-koto-adoption_r*_lead-*.md`.

Two discover-converge rounds, eleven leads, all returned. Round 1 ran seven
leads and falsified three of the four premises the exploration was launched
with. The author then narrowed twice: gating stays in the case at reduced
strength, because a trace the agent did not author is different in kind from a
checker; and one further round was spent on what looked like a hole at exit
finalization. Round 2's three leads found the hole was a factual error and
answered a better question instead. A prior exploration on a superseded
prose-and-framing framing, complete through crystallize, is this run's input and
was read rather than re-derived.

## Problem Statement

`/scope`'s `SKILL.md` states exactly one thing as worth wanting, and that thing
is a smaller artifact set. An agent read the file for intent, found the only
motivated argument in 968 lines, and acted on it -- producing the terminal PLAN,
running no chain, and writing a Status section that quoted the skill's own
reader-economy sentence back at it as justification. Prose can shrink that file,
delete its duplicated argument, define its undefined terms, and convert its
withdrawn-design narration into live instruction. Prose cannot stop the general
form of the reduction argument from being resident at hop zero, because the file
arrives whole at invocation. Expressing `/scope` as a koto workflow puts each
directive behind the state that needs it, so the general argument is never
written into the transcript at all and the most an agent can restate at the end
is a scoped claim about two documents it actually holds.

## Scope Boundary

### In scope

- Expressing `/scope` as a koto **phase substrate**: koto sequences `/scope`'s
  own phases and gates them; children stay on inline Skill-tool dispatch. One
  template, not five.
- The framing and prose rewrite of `SKILL.md`'s purpose-bearing sections. This
  rides inside the effort. koto governs when a directive arrives and never what
  it says, so a koto-driven `/scope` whose first state delivers the current
  `## Why the Artifact Set Shrinks` reproduces the incident with better plumbing.
- A `finalize` state binding in an agent-proposes / koto-vetoes shape, so a run
  cannot claim `full-run` against a failing hop gate.
- The paperwork the content change forces: an appended `## Amendment -- <date>`
  section on `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`,
  and edits to two by-title citations at
  `skills/brief/references/phases/phase-0-setup.md:315` and
  `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:427`.
- Widening `parent-skill-pattern.md` to name a second substrate value for
  `/scope`, and the one Observability Surface bullet that needs it.
- `/scope`'s own eval suite, which today cannot express this failure at all.

### Out of scope

- **Full per-child materialization.** Ranked lower on evidence, not deferred out
  of caution: it costs four additional koto templates over children that ship
  none, and it buys only child-level dashboard legibility. It is also not
  foreclosed -- materialization is one extra state inside a phase substrate, so
  the substrate is its prerequisite rather than its rival.
- **Deterministic post-hoc validation that an agent executed the steps.** Ruled
  out by the author. koto gating is in scope because it is a substrate property;
  the distinction stays sharp and the work must not drift into building a
  checker.
- **Relocating the closed write-target set out of `SKILL.md`.** Established as
  theatre: the terminal address appears in the Overview's second paragraph and
  five other places in the same file, and `parent-skill-security.md:49-73` binds
  the set to `SKILL.md` by name and requires concrete paths.
- **The sourcing property** -- that an agent which skipped a hop holds nothing
  to pass along. Falsified: neither dispatch binding was ever artifact-carrying,
  and children source their own upstream.
- **Committing `/charter` to the adoption.** Divergence is permitted and cheap;
  `/charter` has no reported failure driving it.
- **Context economy as a justification.** Withdrawn on measurement.
- **`tsukumogami/shirabe#320`**, which is related and not a duplicate, and
  `tsukumogami/dot-niwa-overlay#7` / `tsukumogami/niwa#258`.

## Decisions Already Settled

- **The adoption shape is the phase substrate.** koto sequences `/scope`'s own
  phases; children stay inline. It is legal and supported -- every E-series and
  F5 compile rule is guarded on `materialize_children` being present -- and it
  is the base case that materialization extends by one state, as `/execute`
  demonstrates with twelve phase states plus one.
- **The framing content rides inside this effort** rather than being superseded
  by it.
- **The disclosure claim is stated at one strength and no higher:** koto
  prevents the *general* form of the reduction argument from ever entering the
  transcript. It cannot withdraw a delivered argument, and the scoped form must
  still arrive at the judgment.
- **Context economy is withdrawn as a reason to adopt.** Measured, `/scope`'s
  own `SKILL.md` is 7.5% of end-of-run load and koto adds 20,000-32,000
  characters of directive traffic per run. No artifact this effort produces may
  claim koto reduces total resident context.
- **The gating claim is stated as legibility, not enforcement.** `koto next --to
  <state>` reads neither gates nor `when` clauses, and `koto overrides record
  --rationale <anything>` injects a synthetic pass. What survives is that a
  skipped hop stops being indistinguishable from compliance. **The author ruled
  this counts**, because no checker runs, nothing grades the agent, and a bypass
  is a deliberate command carrying a rationale rather than silence.
- **Hop states carry an ungated skip route; the binding goes on the exit.**
  `chain_skipped:` semantics and the re-entry protection built on them survive.
  A run that skipped every hop can still reach `finalize`; what it cannot do is
  claim `full-run` there.
- **The machine-local `/workflows` render is the audit surface.** Copying the
  event log into a PR body was declined because it reintroduces the agent as the
  copier, making the copy forgeable where the original was not. Accepted cost:
  the trace does not leave the machine.
- **Terminal states are not a binding surface.** They can require nothing,
  refuse nothing, and say nothing. Any binding belongs on the pre-terminal
  `finalize` state.
- **Phase 3 is not a place to intervene.** It carries no argument, reads no
  filesystem on the exit path the incident took, and writes nothing into the
  PLAN.
- **The placement cut has four categories, not two:** premise, verdict, bound,
  obituary. Bounds are most of what belongs in the bootstrap; obituaries are
  most of what should be deleted.
- **`tsukumogami/shirabe#331` is re-scoped to the koto framing** rather than kept
  as a prose bug beside a new adoption issue. Its diagnosis survives; only its
  two proposed remedies were falsified.
- **`/charter` is not committed.** Substrate divergence is permitted three ways
  over in the pattern, and the one divergence already shipped cost three-to-four
  stale sentences across a full release cycle.

## Coverage Notes

What the exploration did not answer, and the chain should.

- **Two state stores or one.** `/scope` keeps `wip/scope_<topic>_state.md` under
  a 255-line schema; a koto session carries current state, evidence, and a
  context store. Keeping both risks divergence; folding the state file into koto
  context is a larger change than the template itself. Which fields migrate is
  unsettled.
- **Where a koto session sits relative to git.** `~/.koto/sessions/<name>/ctx`
  is untracked and machine-local. `/execute` anchored resume on a durable home
  PR; `/scope` has no PR mid-chain, so that solution does not transfer. Whether
  `/scope` gets a durable anchor, accepts a machine-local resume boundary, or
  keeps `wip/` authoritative with koto as a projection is open.
- **Whether the 360-line artifact-status resume ladder survives.** Nine rows of
  status-aware re-entry plus four rows of partial-child-run handling, every one
  keyed on artifact status on disk, against a koto session that resumes
  natively. This may be a change to the parent-skill pattern's required
  structural elements, which reaches `/charter`.
- **Which passages land where.** A first draft of the replacement prose exists
  and has been reviewed, with three corrections recorded. What has not been done
  is the actual assignment of every passage to bootstrap, state directive, or
  `<!-- details -->`, under the four-category cut.
- **Whether a `single-pr` `/scope` run has a PR at all.** Phase 3 writes its
  durable record into "the run's pull-request body" and `requires.tsv` declares
  `gh` only for `mode:coordinated`. This decides whether the durable-record
  contract is broken or merely under-specified.
- **Whether `<!-- details -->` or pointer-to-file is right per state.** koto's
  actual progressive-disclosure feature is unused by both shipped adopters. A
  39,808-character details payload for the phase-2 material would ride in every
  first-entry tool result, and a self-loop does not re-deliver details.
- **The eval surface.** All 30 `/scope` evals are plan-only, so none can catch
  this failure. Three harness defects compound it. Any claim that the adoption
  works needs an eval shape that does not exist yet.
- **A structural pressure nothing here addresses.** A compliant `/scope` run is
  115,500-172,000 tokens of instruction before a word of conversation. The path
  that follows the instructions is the expensive one and the path the incident
  took is cheap. The chain should decide whether that is in its scope or a named
  non-goal.

## Upstream Observations

No BRIEF, PRD, DESIGN, or PLAN exists for this topic. Nothing was found at any
of the five canonical `<topic>` paths.

`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` is status
Current and is the design this work amends rather than supersedes. Its Decision
Outcome names `SKILL.md` conjunctively with the phase references, so removing
`## Why the Artifact Set Shrinks` withdraws a named deliverable -- but the
decision itself holds, and only a deliverable narrows. It already carries two
amendments, so the convention exists. One correction worth carrying: its own
text at `:858-864` explicitly retracts the "zero strategic hops are absorbable"
reasoning that had been cited as the ground for `/charter` lacking a
consolidation judgment. The parents differ because nobody built the second one,
not because types forbade it.

`docs/plans/PLAN-work-on-friction-fixes.md` exists, is `multi-pr`, and is
off-topic. It is named here only because the crystallize step checked it.

The prior exploration's artifacts live on branch `origin/docs/scope-process-framing`
under `wip/`. They are non-durable and will be deleted before that branch can
merge; everything from them that this effort needs has been carried into this
run's own artifacts rather than cited by path.

Three issues were filed during this exploration for defects found along the way,
all independent of this work: `tsukumogami/shirabe#333`,
`tsukumogami/koto#202`, and `tsukumogami/koto#203`.

## Framing-Shift Answer

**Pre-supplied answer:** no signal surfaced.

**Evidence:** the question asks whether the framing has shifted since the
upstream artifacts were last accepted, in a way that would invalidate an
existing BRIEF, PRD, or DESIGN on disk. No such artifact exists for this topic,
so there is nothing to invalidate and the override has nothing to fire against.

Recorded for accuracy, because it is easy to misread as a shift: the subject did
change during this line of work, from a prose-and-placement bug to a substrate
adoption carrying the prose work inside it. That change happened between two
explorations and before any chain artifact was written. It is a reason the
exploration exists, not a shift since an accepted upstream.

## Shape Signals

### Architectural alternatives left open

- **Two state stores versus one.** Keeping `wip/scope_<topic>_state.md` beside a
  koto session costs two sources of truth to reconcile, which `/execute` already
  lives with. Folding the 255-line schema into koto context costs a larger
  change than the template itself and reaches the resume ladder and the
  pattern's required structural elements.
- **Where resume anchors.** A durable anchor (something git- or PR-backed) costs
  new machinery `/scope` does not have mid-chain. A machine-local koto session
  costs resumability across machines and worktrees, and interacts with the
  existing same-topic concurrency no-go by adding a second, machine-global
  contention surface. Keeping `wip/` authoritative with koto as a projection
  costs the weakest form of the gating property.
- **`<!-- details -->` versus pointer-to-file per state.** Both shipped adopters
  chose pointer-to-file and neither uses details. Details are delivered on first
  visit and not re-delivered on a self-loop, so the choice trades delivery-window
  cost against re-entry behaviour, and it may differ per state rather than
  uniformly.
- **Whether the resume ladder is ported or replaced.** Porting keeps thirteen
  rows of artifact-status logic beside a state machine that resumes natively.
  Replacing reaches the parent-skill pattern, and through it `/charter`.

### Complexity signals

- The work spans one skill's `SKILL.md`, a new koto template, six phase
  references, a shared pattern document, one Current design's amendment, two
  by-title citations in a second skill, and an eval suite that cannot currently
  express the failure. That is architectural complexity rather than volume.
- Two contested trade-offs were settled by author ruling during exploration --
  the skip route and the audit surface -- and both remain live design inputs
  rather than closed questions, because their consequences reach the resume
  ladder and the pattern.
- The adoption's dominant risk is an authoring error rather than a runtime one:
  a state whose routes resolve without the agent is silently skipped, the
  governing rule is documented nowhere, and koto and shirabe have each already
  shipped a template carrying the narrower version of that bug. Whatever this
  chain produces needs a stated template-review rule, the way `/work-on`'s
  template description states its self-loop rule.
- The exploration falsified three widely-held premises. Any design that reaches
  for isolation, for a sourcing property, or for context economy is building
  toward something the evidence says is not there.
