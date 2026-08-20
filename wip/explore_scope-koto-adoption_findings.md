# Exploration Findings: scope-koto-adoption

## Core Question

`/scope`'s `SKILL.md` loads whole at invocation and never unloads, so an agent
holds every one of its 968 lines -- including the only passage in the file that
argues an outcome is worth wanting, and that outcome is a smaller artifact set --
before it has done any work. That is the one defect prose cannot repair, and it
is what koto is being reached for. The question is whether `/scope` can be
expressed as a koto workflow without losing the author conversation that is most
of what `/scope` is, and if so, at what shape.

## Round 1

Seven leads dispatched, seven returned. No agent failed.

Three of the four premises this exploration was launched with are falsified
below. One new premise replaces them. The koto case survives; almost nothing
about it survives in the form it was stated.

### Key Insights

**The phase-substrate shape is legal, supported, already shipped, and is the
base case rather than an alternative.** (substrate-shape) Every E-series and F5
compile rule is guarded on `materialize_children` being present
(`koto:src/template/types.rs:942-953`), so a child-free template is not an
exception to the rules -- the rules simply do not apply to it. A 5-state
child-free template compiled and ran to terminal on koto 0.11.6. `/work-on` is
25 states with zero children and dispatches its review panels inline. And
`/execute` is 12 phase states plus *one* materialization state, so
materialization is one extra state inside a phase substrate rather than a rival
to it: adopting the substrate for `/scope` does not foreclose materializing
children later, it is the prerequisite. Cost collapses from four child templates
to one template plus one mermaid diagram. koto's own engine design names
progressive disclosure as a decision driver (`koto:docs/designs/current/DESIGN-koto-engine.md:141`)
in words that nearly paraphrase the author's framing.

**The prior run's deciding obstacle does not hold.** (conversation-under-koto)
`/scope`'s Phase 1 "563-line author conversation" is two questions: a
framing-shift ask and a three-value `Proceed / Adjust / Bail`, which is a
textbook koto `accepts` enum whose mutual-exclusivity the compiler would enforce
where prose currently only asserts it. The reference file is long because it
argues at length about what Phase 1 must *not* decide. Three independent pieces
of evidence retire the obstacle:

- `/scope` already ships `--auto` (`skills/scope/SKILL.md:106-107`), which runs
  the entire chain across all phases with zero author input. A skill with a
  supported no-conversation mode cannot have the conversation as its identity.
- `/scope` passes children nothing conversational, and `/prd` says so outright
  (`skills/prd/SKILL.md:128-129`): "`/scope` pre-populates nothing for `/prd`;
  it invokes `/prd` and lets Phase 1 do the scoping." The children hold their
  own author conversations.
- `/charter` already serializes parent conversation into a child, via a
  seven-field `wip/roadmap_<topic>_scope.md` written into `/roadmap`'s namespace
  (`skills/charter/references/phases/phase-2-chain-orchestration.md:433-461`) --
  **under the inline binding**. If the shared agent context carried conversation
  to children, that file would be redundant. It ships anyway.

The parent-to-child channel is argv plus a durable artifact plus a two-valued
`rationale:` enum in a state file the child globs for. All three survive
materialization untouched.

**The gating claim is falsified as worded.** (gating-strength) The wording under
test was that a `context-exists` gate would make the parent unable to skip a hop
and still finish. Two documented, unconfigurable commands defeat every gate type:

- `koto next --to <state>` (`koto:src/cli/mod.rs:3286-3322`) validates only that
  the target is a declared edge. It reads neither gates nor `when` clauses --
  `:3309-3311` maps transitions to `t.target` and never consults `t.when`, so
  the template's *routing logic*, not only its gates, is advisory under `--to`.
- `koto overrides record --rationale <anything>` (`koto:src/cli/overrides.rs:54-72`)
  injects a synthetic pass with no evidence; the three-level fallback bottoms out
  in `built_in_default` (`koto:src/gate.rs:239-243`), whose value for
  `context-exists` is literally `{"exists": true}`. The mandatory `--rationale`
  is an unvalidated string.

The parent can skip every hop and still finish, along the template's own declared
edges, with no context keys written and no artifacts produced.

**What survives gating is a change of authorship and legibility, not of
possibility.** (gating-strength) A hop genuinely performed leaves a
koto-authored `GateEvaluated` event. A hop skipped leaves either nothing or a
typed `DirectedTransition` / `GateOverrideRecorded` event naming the bypass. The
two cases become distinguishable in a log the agent does not author. Skipping
stays possible; it stops being *indistinguishable from compliance*. That is
stronger than R20, whose execution is unobservable from outside the agent, and
stronger than `chain_ran:`, which the agent writes. It is much weaker than
"cannot skip."

**No fresh-child context boundary exists anywhere in the repo, under koto or
otherwise.** (child-ticking) Established by exhaustion rather than inference.
koto's own source carries the clearest statement of shirabe's execution model
anywhere: "the dispatched agent is the same process as the spawning batch
scheduler" (`koto:src/engine/epoch.rs:117-127`). koto's scheduler writes state
files and returns (`koto:src/cli/batch.rs:8-21`); koto launches nothing
(`koto:docs/designs/current/DESIGN-hierarchical-workflows.md:69`). The claim at
`skills/execute/koto-templates/execute.md:428-430` (restated at
`skills/execute/SKILL.md:641`) that the coordinator "stays thin by delegating
each issue to a fresh `work-on.md` child" is asserted and not implemented.

**This sharpens #331's mechanism.** (child-ticking) The failure -- an agent
following `/scope`'s structure, producing only the terminal PLAN, and asserting
the upstream artifacts away in prose -- is a single agent accumulating its own
reasoning across all four hops in one context window. That is the actual runtime
today, not a deviation from it. The agent asserted the upstream artifacts away
because it had been reasoning about them continuously and its own prose was as
available to it as any instruction. Framing the fix as "koto would have
prevented this via fresh contexts" would be wrong on the mechanism.

**`/scope` already does progressive disclosure, and koto's measured delta on the
one precedent is small.** (disclosure-mechanics) Six phase reference files
totalling 2,708 lines are not resident at invocation. The pre-koto `/work-on`
had the same shape; koto adoption shrank its `SKILL.md` by 1,019 characters
(7,299 to 6,280), and the adoption commit's own stated win was deduplication
rather than lazy loading. That file has since grown to 17,706. `/execute` is a
koto adopter whose `SKILL.md` is 48,371 characters -- 94% the size of
`/scope`'s -- and a 7,649-character section of it narrates the koto template's
own states in prose, so the state machine is paid for twice.

**Both shipped adopters point directives back into `SKILL.md` for semantic
doctrine.** (disclosure-mechanics) `work-on.md:1027` ("See the
`## Definition of Done` section of SKILL.md") and `execute.md:423` ("per the
SKILL's **Autonomy** section"). Two independent adopters converged on leaving
doctrine resident and pointing directives at it -- which is exactly the pattern
that would leave `## Why the Artifact Set Shrinks` in context at state 1. And
neither template uses `<!-- details -->`, koto's actual progressive-disclosure
feature; both use pointer-to-file instead, so per-state cost is directive *plus*
file read.

**The one thing that matters does land.** (content-placement, disclosure-mechanics)
`## Why the Artifact Set Shrinks` and `## Consolidation Judgment` (5,408
characters combined) are correctly Phase-2 content. Under a koto shape the
reader-economy sentence #331's agent quoted back at the skill sits in the
judgment state's directive and is physically absent from context until both
artifacts exist. That is not a wording fix; it is the mechanism the issue asked
for, and it is the strongest single argument for the adoption.

**Substrate divergence between `/scope` and `/charter` is permitted three ways
over, and is empirically cheap.** (parent-divergence) The Layer-1/Layer-2 split
was built for it (`parent-skill-pattern.md:512-517`); `storage_substrate`
(`:374-384`) names the parent-side value as substitutable; the surface table is
explicitly growable (`parent-skill-child-inspection.md:65-67`). The two parents
already differ on a whole capability with the pattern's blessing (`:141-147`).
One substrate divergence has already run a full release cycle: its cost was
three-to-four stale sentences in the pattern doc, zero behavioral failures, and
zero duplicated Layer-1 text. That number replaces the feared "every future
pattern change is written twice."

**`/execute` ships no `references/phases/` directory and claims full conformance
anyway.** (parent-divergence) Element 6's literal names those files
(`parent-skill-pattern.md:692-693`); `skills/execute/SKILL.md:129-131` declines
them and `:752-756` asserts the conformance binding is complete. This is the
single most useful precedent found: it is exactly the element a koto adoption
would break, and it has already been broken without incident.

**Shape (a) is cheaper than shape (b) on conformance.** (parent-divergence)
Shape (a) leaves the entire Dispatch Contract untouched -- mechanism,
pre-dispatch state, and hand-back all key on a parent/child boundary that does
not move -- and costs element 6's phase-file layout, element 5's resume ladder,
one bullet of the Observability Surface, and plumbing on elements 2, 3, and 7.
Shape (b) costs all of that plus a rewritten dispatch loop. Notably shape (b)
does *not* cost a new surface-table row, because `/scope`'s children emit docs
rather than PRs.

**Premise-versus-verdict is insufficient as a binary and needs two more
categories.** (content-placement) *Bounds* and *obituaries*. Bounds are most of
what belongs in the bootstrap; obituaries are most of what should be deleted.
The bootstrap that falls out is roughly eight short passages -- process-is-the-
product, two foreclosure sentences, the contribution definition, the
"cannot answer, shouldn't try" line, the hop-consumption sentence, two bounds,
and the constant-chain sentence -- with no machinery inventory, no reader-economy
argument, and no obituaries. Close to the inverse of what `SKILL.md` front-loads
today.

**Three corrections to the draft replacement prose.** (content-placement)

- The obituary count is about 13 lines, not 30. `SKILL.md:508-517` and
  `:519-530` are present-tense rule statements that happen to contain a
  "no longer" hinge; treating them as history would delete live content.
  `SKILL.md:813` is not an obituary at all -- it is a within-run back-reference
  in the coordinated-abandonment paragraph.
- Lifting the four per-type contribution declarations into the lede is the most
  dangerous item in the draft. Four sentences summarizing what each of the four
  documents contains, delivered to an agent holding none of them, is a
  compression recipe for exactly the Status section the incident produced. The
  draft's own rejected fallback -- one sentence plus a pointer -- is the safer
  shape, and lede length is not the reason.
- The draft's strongest reasoning is the part koto invalidates. Its (a)+(b)
  duplication recommendation is argued from the incident itself and is a good
  argument about a skill whose control flow is the agent's compliance with
  prose. It stops applying the moment control flow is a state machine.

**The paperwork is three by-title references, not two.** (content-placement)
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:427` names
`## Why the Artifact Set Shrinks` inside a fenced architecture block, alongside
the known `skills/brief/references/phases/phase-0-setup.md:315` citation and the
appended `## Amendment -- <date>` paragraph.

### Tensions

**The disclosure win and the gating win each survive at reduced strength, and
the case is the conjunction rather than either half.** (disclosure-mechanics vs
gating-strength) Disclosure alone does not justify the dependency: relocating
the two sections into `phase-2-chain-orchestration.md` achieves the same
physical absence with no new dependency, and the measured precedent delta is
1,019 characters. Gating alone does not justify it either: two documented
commands defeat every gate, leaving legibility. What koto offers that neither
half offers is the conjunction -- physical absence of the argument at the moment
of judgment, plus a state machine that has to be actively bypassed with a named
rationale rather than merely disregarded. The adoption should be argued that way
or not at all.

**The residual gating value is post-hoc, which is the shape the author ruled
out.** (gating-strength) The value is realized only by something reading the
event log after the run. Answering "nobody reads it" means koto gating buys
nothing over R20. Answering "a post-hoc reader" collides with the exclusion on
#320. The substrate/checker distinction holds formally -- the gate is a
substrate property, and the bypasses are separate code paths rather than gate
weaknesses -- but the practical benefit lands near the ruled-out line.
**Resolved by the author in round 1: it counts, because a trace the agent did
not author is different in kind from a checker that grades the agent.**

**Deferring the reduction argument to Phase 2 does not cover the decision where
#331 actually happened.** (disclosure-mechanics) Removing
`## Why the Artifact Set Shrinks` from context until the consolidation state
removes it from the *chain-proposal* decision. The fabricated Status section was
written at *exit finalization*. No round-1 lead examined exit finalization, and
the disclosure story has an unexamined hole at the exact site of the reported
incident. This is round 2's subject.

**The phase substrate addresses roughly a fifth of total resident context.**
(substrate-shape) It fixes `/scope`'s own 968-line footprint and does nothing
about `/brief`, `/prd`, `/design`, and `/plan` loading whole when invoked inline
via the Skill tool. If the complaint is total resident context across a run
rather than what is resident at `/scope`'s own decision points, this shape
answers a different question than the one asked.

**Whether hop states are unconditional decides a content-placement answer.**
(content-placement vs substrate-shape) If a template routes hop entry on agent
evidence, the draft's original duplication recommendation is right; if hop
states are unconditional, the revision is right. Substrate-shape's sketch makes
every state conditional -- but for an unrelated reason (the pass-through trap
below), so the two leads agree on the mechanism and have not reconciled on the
content consequence.

### Gaps

- **Exit finalization is unexamined.** What Phase 3 reads, what it decides, what
  governs the Status section, and whether a koto terminal-state shape can bind
  it. Round 2's subject.
- **Directive traffic over a full `/scope` run is unmeasured.** Per-state
  directive sizes are known for `/work-on` (677 characters mean), but not how
  many ticks a real `/scope` chain takes including gate blocks, self-loops, and
  retries. Without it, whether accumulated directive traffic offsets the
  `SKILL.md` saving is unknown. koto also splices about 95 characters into every
  directive.
- **Two state stores or one.** `/scope` keeps a 255-line `wip/` state schema;
  koto carries current state, evidence, and a context store. Keeping both risks
  divergence; folding the state file into koto context is a larger change than
  the template.
- **Where koto session state lives relative to git.** `~/.koto/sessions/<name>/ctx`
  is untracked and machine-local. `/execute` anchored resume on a durable home
  PR; `/scope` has no PR mid-chain. Needs an author call on whether `/scope`
  gets a durable anchor, accepts a machine-local resume boundary, or keeps
  `wip/` authoritative with koto as a projection.
- **Whether `/execute` works at all today.** Nothing in the repo instructs
  anyone to tick a materialized child. See below.
- **Child-level dashboard legibility.** The only material thing full
  materialization buys that the phase substrate does not: five rows instead of
  one in `koto workflows`. An observability preference, not a mechanism question.

### Decisions

Recorded in `wip/explore_scope-koto-adoption_decisions.md`.

### User Focus

The author resolved the post-hoc tension in favour of keeping gating in the
case at reduced strength: a trace the agent did not author is a substrate
property rather than a checker, because no checker runs, nothing grades the
agent, and a bypass is a deliberate command carrying a rationale rather than
silence. The author elected one narrow round 2 on the exit-finalization hole
before crystallizing, on the grounds that it decides whether the adoption fixes
the reported incident or an adjacent one. The author elected to file the live
defects found this round as separate issues rather than folding them into this
effort.

### Findings that bear on other work

Live defects found this round, none of them this effort's to fix.

- **`skills/work-on/koto-templates/work-on.md:125` is a live correctness bug.**
  The `research` state has an `accepts` block and a single unconditional
  transition. `resolve_transition` (`koto:src/engine/advance.rs:693-771`) fires
  an unconditional fallback unless `gate_failed || (!fresh_evidence &&
  has_conditional)` (`:758`), and a state with no conditional transition has
  `has_conditional == false`, so the engine advances straight through it -- the
  agent never sees that state's directive. Verified by running it: submitting
  `{"verdict":"proceed"}` at `task_validation` lands the agent at
  `post_research_validation`, whose directive opens "Reassess the task against
  what research revealed about the current codebase", after koto silently
  skipped the state that would have told it to research. Live in `/work-on`
  free-form mode today.
- **koto's own `koto-author` template has the same defect, worse.** Five of nine
  states collapse in one tick: a single `koto next` after
  `koto init ka-test --template koto-author.md --var MODE=new` returns
  `advanced: true` at `compile_validation`, having delivered neither `entry`,
  `context_gathering`, `phase_identification`, `state_design`, nor
  `template_drafting`.
- **koto's documented self-loop polling idiom errors at runtime.**
  `koto-author/references/template-format.md:548-570` presents an `await_file`
  state with a gate and a self-loop and calls it "the idiomatic workaround when
  a `context-exists` gate would otherwise block indefinitely." Copied verbatim,
  compiled clean, and run with the key absent, it returns
  `cycle detected: advancement loop would revisit state 'await_file'`, exit code
  3. Evidence-driven self-loops are fine; gate-driven ones always error after one
  lap.
- **`/execute` has a documented way to create children and none to start them.**
  No instruction anywhere tells anyone to tick a materialized child;
  `skills/execute/requires.tsv`, an enforced enumeration of every command the
  skill runs, declares no child-advancing call; and the eval shim
  (`skills/execute/evals/fixtures/bin/koto:84-85`) exits 1 on any unmatched
  argument with no arm matching a child session name, so the test infrastructure
  is structurally incapable of exercising it.
- **`execute.md:428-430` and `skills/execute/SKILL.md:641` assert a
  context-budget property the implementation does not deliver.**
- **`references/fixes/sub-agent-dispatch.md` is named for a mechanism its own
  body documents workarounds for the absence of.**
- **Four stale passages in `parent-skill-pattern.md`**, all the same failure
  mode -- pattern text that shipped parents have outgrown: `:68-76` on I-6
  (`skills/execute/SKILL.md:479` binds I-6 in v1 through a `gh`-recovered home
  PR, which the pattern reserves for the amplifier layer), `:585-589` on
  "nothing else", `:655-658` on topic-slug-only dispatch, and `:692-693`'s
  phase-file literal. Worth a cleanup PR before any adoption diff, so the
  adoption reads as a clean widening rather than a fifth exception on four
  unacknowledged ones.
- **The R9 write-target defect is confirmed live.** The authoritative closed
  write-target set at `skills/scope/SKILL.md:857-859` gives
  `docs/{briefs,prds,designs}/` for the `abandonment-forced` entry, while
  `:762-766` and `phase-4-cleanup.md:55-56` both include `docs/designs/current/`
  and `docs/plans/`.
- **`/scope`'s `framing_shift` answer is never persisted.** Absent from
  `state-schema.md`, so a resume re-asks it. A koto binding would improve this:
  an `accepts` enum is recorded in the event log by construction.
- **`context_assignments` is undocumented** in koto's template-format reference
  despite being used by the shipped `execute.md` template and validated by the
  engine (`koto:src/template/types.rs:1219-1242`).
- **A constraint worth recording:** koto template variables cannot carry prose.
  The `--var` allowlist rejects newlines, quotes, and shell metacharacters
  (`template-format.md:747-751`). Conversational content must go through
  `koto context add` or a `type: string` accepts field, never `{{VAR}}`.
- **The prior exploration's list still stands**, including `/explore` no longer
  naming `/plan <topic>` as a routing destination, three eval-harness defects,
  and all 30 `/scope` evals being plan-only so none can catch the #331 failure.

## Accumulated Understanding

The koto adoption is worth doing, at a strength materially lower than the
reframe assumed and for a reason the reframe did not name.

Three of the four premises the exploration opened with are falsified. The
deciding obstacle -- that `/scope` is a conversation and `/execute` is not --
does not survive contact with `/scope`'s own `--auto` mode, with `/prd`'s
statement that `/scope` pre-populates nothing for it, or with `/charter`
already serializing parent conversation into a child under the inline binding.
The gating guarantee does not survive `koto next --to` and
`koto overrides record`, which together let a parent walk its own declared
edges to a terminal state having produced nothing. And the fresh-child context
boundary does not exist anywhere in the repo to adopt, which matters because
#331's mechanism is precisely a single agent accumulating its own reasoning
across four hops in one window -- the runtime as designed, not a deviation.

What replaces them is narrower and better evidenced. The phase-substrate shape
is not an untested alternative to materialization; it is the base case that
materialization extends by one state, and `/execute` already demonstrates the
composition. It costs one template rather than four, leaves the Dispatch
Contract untouched, and gives up only child-level dashboard legibility. Its
payoff is specific: the reader-economy sentence the incident agent quoted back
at the skill can be physically absent from context until both artifacts exist.
Prose can relocate that sentence too, and cheaply -- so the honest case for the
dependency is the conjunction of physical absence with a state machine that must
be bypassed by a named command rather than merely disregarded, and the author
has accepted that trace as a substrate property rather than a checker.

Two things about disclosure need saying plainly, because the enthusiasm runs
past them. `/scope` already does progressive disclosure through six per-phase
reference files, and koto's measured delta on the one precedent was about a
thousand characters, with both shipped adopters converging on pointing their
directives back into a resident `SKILL.md` and neither using the
`<!-- details -->` mechanism built for the job. The disclosure win is an
authoring discipline that koto makes expressible and does not confer; a
koto-driven `/scope` authored the way `/work-on` and `/execute` were authored
would reproduce #331 with better plumbing, exactly as the prior run warned.

The framing content therefore rides inside this effort and is where most of the
value is. The premise/verdict cut needs two more categories -- bounds and
obituaries -- and under them the bootstrap that survives is roughly eight short
passages of purpose and bound, with no machinery inventory and no reader-economy
argument, which is close to the inverse of what `SKILL.md` front-loads today.
Three corrections to the drafted prose are recorded above; the sharpest is that
lifting four per-type contribution declarations into the lede would hand an
agent holding none of the four documents a compression recipe for the exact
Status section the incident produced.

What is not yet established is whether any of this reaches the decision where
#331 actually failed. The fabricated Status section was written at exit
finalization, and every disclosure argument so far concerns the chain-proposal
decision at Phase 1 and the judgment at Phase 2. Round 2 is scoped to that hole.
