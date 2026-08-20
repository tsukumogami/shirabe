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
#331 actually happened.** (disclosure-mechanics) **FALSIFIED IN ROUND 2 -- see
below.** The claim was that the fabricated Status section was written at exit
finalization. It was not: it is a Phase 2 write, at the `/plan` hop.
`phase-3-exit-finalization.md:384` says outright "Phase 3 does not delete and
does not write the PLAN", and the `## Status` absorption line is written at
`phase-2-chain-orchestration.md:650`. The issue itself says so in its second
paragraph. The tension dissolves and the disclosure case is aimed at the right
site after all.

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


## Round 2

Three leads dispatched, three returned. No agent failed. Round 2 was scoped to
one thing: the exit-finalization hole round 1 opened.

The hole was not real. Round 1's disclosure lead asserted that #331's fabricated
Status section was written at exit finalization; two independent round-2 leads
established it was a Phase 2 write, at the `/plan` hop. The round therefore
answered a different and more useful question than the one it was commissioned
for, and it closes the exploration.

### Key Insights

**The founding premise of the round is falsified, and the correction runs in the
adoption's favour.** (exit-finalization, resident-at-exit -- independently)
`phase-3-exit-finalization.md:384` says outright "Phase 3 does not delete and
does not write the PLAN", and the `## Status` absorption line is written at
`phase-2-chain-orchestration.md:650` with a pinned shape #331's prose does not
match. Issue #331 says the same thing in its own second paragraph: the agent
"authored a Status section in the PLAN". So making the reader-economy argument
physically absent until both artifacts exist puts it out of context at the
moment the incident agent quoted it. The tension recorded in round 1 dissolves.

**The accumulation objection, correctly scoped, does not weaken the case.**
(exit-finalization) A single agent carrying its own reasoning across four hops
can restate an argument that disclosure later removes -- but that failure mode
requires *running* the hops. #331's agent skipped them and quoted the source
text nearly verbatim at hop zero. Disclosure is strongest against exactly the
reported shape. The accumulation risk applies to future runs that do the work
and then rationalize a fold, which is a different and less-evidenced concern.

**The sharpest statement of what disclosure buys.** (resident-at-exit) The
reduction argument is unremovable from a transcript once delivered, and it must
be delivered at the judgment, which a full run enters three times. What
disclosure can do is ensure the **general** form never enters the transcript at
all, so what an agent can restate at the end is a scoped claim about two
documents that exist rather than a general claim about artifact sets. #331's
agent quoted the general form. There is no general form to quote if it is never
written down.

**Phase 3 is the wrong place for any fix, and that is a clean result.**
(exit-finalization) Phase 3 contains no argument, reads no filesystem on the
exit path the incident took, writes nothing into the PLAN, and its check is a
pure state-file consistency pass. A koto terminal state there would sequence a
transcription.

**A koto terminal state can require nothing, refuse nothing, and say nothing.**
(terminal-binding) The terminal check fires at step 3 of the advance loop before
gates ever run (`koto:src/engine/advance.rs:243-250`); gates on a terminal are a
D5 compile error; `accepts` on a terminal compiles silently as dead config;
evidence submission there is refused outright (`koto:src/cli/mod.rs:3581-3592`);
and a terminal's directive never crosses the wire. Every terminal body section
in every shipped shirabe template is documentation for template readers, not
instruction for agents.

**The binding is entirely the pre-terminal state's, and the workable shape is
"agent proposes, koto vetoes."** (terminal-binding) A `finalize` state can force
the agent to stop and submit a typed `exit:` enum and a `status_section:`
string, provided every route out carries an agent field, and koto can then
refuse the exit path the agent proposed against what is on disk. **Verified: a
`full-run` claim submitted with the plan gate failing returned
`advanced: false`.** koto cannot judge the claim, and cannot stop
`koto next --to done_full` -- but that leaves a trace.

**The answer to round 1's "who reads the log" exists and nobody had found it.**
(terminal-binding) Claude Code's `/workflows` render does, natively, with no
skill and no reader (`koto:.../workflows_surface/mod.rs:1-5`). It is on by
default via `CLAUDE_CODE_SESSION_ID` self-discovery, and it rendered the #331
signature as `Brief: FAIL / Prd: FAIL / Plan: PASS / Finalize: PASS` under a
completed `full-run` exit. Four lines, machine-authored.

**Round 1's gating conclusion needs amending on durability, not substance.**
(terminal-binding) "A typed event in a log the agent does not author" is true
about the writer and false about the artifact. The event log is deleted by
`fs::remove_dir_all` on the terminal tick by default (`koto:src/cli/mod.rs:2586`,
`koto:src/session/local.rs:76-83`), leaving one index line that says only
`"completed"` and does not name which terminal was reached -- and it is trivially
rewritable by `sed -i` while it lives. `--no-cleanup` preserves it and forfeits
the index entry; the two durability modes are mutually exclusive. The
`/workflows` render survives the deletion. **Any design that repeats round 1's
wording without the `--no-cleanup` requirement ships a `/scope` whose audit
trail evaporates at exit.**

**The context-economy case does not survive measurement.** (resident-at-exit)
`/scope`'s own `SKILL.md` is 7.5% of documented end-of-run load, and the
genuinely bindable slice is 3.7%. Against that, koto adds 20,000-32,000
characters of directive traffic over a 25-40 tick run. The net delta at exit
finalization is approximately zero and plausibly negative. **Any claim that koto
reduces total resident context over a `/scope` run is false as measured.** The
adoption is argued on physical absence *at the moment of judgment*, and that
qualifier is load-bearing rather than decorative.

**The largest number in the stack is `/plan`, at 180,985 characters, and no
proposal on the table touches it.** (resident-at-exit) If total resident context
is the concern, `/plan` is 3.5x the lever `/scope`'s `SKILL.md` is. If the
concern is what is in context at a specific decision, the total is the wrong
measure and should stop being cited.

**A compliant `/scope` run may not fit a 200k window.** (resident-at-exit)
115,500 tokens at the floor, 172,000 as documented, before a single word of
conversation or a single artifact draft. The path that follows the skill's
instructions is the expensive one; the path #331 took is cheap. That is a
structural pressure toward the shortcut that no prose placement addresses, and
it is the most uncomfortable finding in the exploration.

**R9 provably does not catch #331, and `chain_ran: []` fails open.**
(resident-at-exit) `exit: full-run` + `chain_ran: []` + omitted
`plan_execution_mode:` + `exit_artifacts:` naming the PLAN passes all five R9
conditions, because `plan_execution_mode:` is gated on chain membership
(`state-schema.md:176`) and nothing gates `exit: full-run` on `/plan` being in
`chain_ran:`. Worse, four downstream readers key on `chain_ran:` -- the
consolidation judgment's firing condition, the R8 tie-break, the PR-body record,
and `plan_execution_mode:`'s presence condition -- so an empty list makes all
four vacuous. The audit surface disarms rather than trips.

**`accepts` is not a stop condition; a state stops iff nothing resolves.**
(terminal-binding) A `required: true` field on a state with two conditional
transitions was skipped entirely because gate output resolved one of them. Round
1's "`accepts` plus a single unconditional transition" is a corollary of the
general rule, and the general rule is documented nowhere in koto's
template-format reference. koto and shirabe have each already shipped a template
with the narrower version of the bug. A `/scope` template needs the review rule
stated in the template's own description, the way `/work-on`'s line 11 states
the self-loop rule.

**Real subagent boundaries do exist in the stack.** (resident-at-exit) `/prd`
Phase 2, `/design` Phase 6, and `/plan` Phase 4 all use the Agent tool, which
needs no `requires.tsv` declaration
(`references/tool-declaration-policy.md:11-27` scopes it to CLI tools). Round
1's "no fresh-child boundary" holds for chain hops, but the mechanism is
present, used, and cheap. `references/fixes/sub-agent-dispatch.md:52-58`
documents a serial-self-jury fallback that collapses those boundaries back into
one process under a parent chain.

**Every filesystem-touching validator check in the corpus is gated on a
self-declared frontmatter field.** (resident-at-exit) FC18 on `absorbed:`, R6
and the lifecycle walk on `upstream:`, FC20 on a surviving basename. Nothing
anywhere asks "what should exist here" without first being told by the document.
That is a structural property, not four coincidences. And `upstream:` is not a
required field on a PLAN (`crates/shirabe-validate/src/formats.rs:405`), so the
sourcing property #331 proposes as its cheapest fix has no validator that could
notice its absence.

### Tensions

**The design's largest exposure is an authoring error, not an agent.**
(terminal-binding) A `finalize` state whose routes resolve without the agent is
silent, ships once, and holds forever -- and it is the exact #331 reproduction.
The rule that prevents it is undocumented, and both koto and shirabe have
already shipped the narrower version of the bug. This argues that the adoption's
risk is concentrated in template review rather than in runtime behaviour, which
is a different risk profile than the exploration has been assuming.

**The audit surface's durability and its discoverability are mutually
exclusive.** (terminal-binding) `--no-cleanup` preserves the rich event log and
forfeits the terminal index line. The `/workflows` render survives either way
but lives under `~/.claude/projects/<projectDir>/<sessionId>/workflows/`, keyed
to a Claude Code session id, outside git and outside any PR. In an ephemeral
instance the home directory may not outlive the run. Either `/scope` copies
something into the PR body at finalize -- which reintroduces the agent as the
copier, and forgeability with it -- or the author accepts a machine-local audit
surface.

**The cheap path and the compliant path diverge by roughly 150,000 tokens.**
(resident-at-exit) Nothing in the adoption changes that, and the adoption adds
directive traffic on the compliant side. A design that argues koto makes
compliance cheaper is arguing against the measurement.

### Gaps

- **Does a `/scope` run on the single-pr path have a PR at all?**
  (exit-finalization) Phase 3 writes its durable record into "the run's
  pull-request body", and `requires.tsv` declares `gh` only for
  `mode:coordinated`. Either the author is expected to have opened one, the
  record is written by whatever later opens one, or it is dead text. Changes
  whether the durable-record contract is broken or merely under-specified.
- **Whether the `/workflows` render is durable enough to be the answer**, or
  whether `/scope` must drive its terminal tick with `--no-cleanup` and copy the
  log into the PR body itself.
- **Whether `/scope`'s hop states carry an ungated skip route.** With one, the
  #331 reproduction stays possible with no bypass at all -- legible in the trace,
  but possible. Without one, `/scope` loses `chain_skipped:` semantics and its
  re-entry protection has nowhere to go. A scoping call, not a research finding,
  and the sharpest thing round 2 hands the author.
- Round 1's gaps on two state stores, where koto session state lives relative to
  git, and child-level dashboard legibility all stand unchanged.

### Decisions

Recorded in `wip/explore_scope-koto-adoption_decisions.md`.

### Findings that bear on other work

Added to round 1's list.

- **Phase 3's durable record has no sink on a `single-pr` full run.**
  (exit-finalization) It is written into a PR body that only the coordinated
  path has. Phase 4 then deletes the state file. The audit trail is removed with
  nowhere to have gone.
- **`exit: full-run` has no predicate anywhere in the skill.**
  (exit-finalization) The pattern layer defines the entitlement -- every required
  child produced its durable doc (`parent-skill-pattern.md:86-88`) -- and nothing
  converts it into a condition. `re-evaluation` is determined by a git commit and
  `full-run` by nothing, so the skill's most common exit is its least evidenced.
  A one-line R9 condition 6 (`exit: full-run` requires `/plan` in `chain_ran:`)
  would have caught #331 at finalization using only fields already in the state
  file. Recorded rather than proposed: whether that is a checker under the
  author's exclusion is the author's call, and the lead's read is that it is the
  same class of self-consistency rule R9 already applies four times.
- **Three koto terminal-region hazards**, all independent of this effort:
  `accepts` on a terminal compiles silently as dead config; a completed
  workflow's terminal phase renders `"in progress"`
  (`koto:.../materialize.rs:136-143`, cosmetic); and the template-format
  reference documents neither the "a state stops iff nothing resolves" rule nor
  that a terminal state's directive is never delivered.
- **`expects.options` hands the agent the routing table**, including which exit
  route is ungated. (terminal-binding)
- **The koto event log is trivially forgeable** -- no seq-chain hash, despite
  `audit.rs` being otherwise adversarially designed. (terminal-binding)
- **The override bypass renders as FAIL**, because `advance.rs:363` emits no
  `GateEvaluated` for an overridden gate so the render keeps the stale failing
  evaluation. Accidentally the most legible of the three bypasses.
  (terminal-binding)

## Accumulated Understanding

*Rewritten after round 2. Supersedes the round-1 statement.*

Adopt koto for `/scope`, as a phase substrate, for one reason stated narrowly:
so that the general form of the artifact-reduction argument never enters a run's
transcript. Everything else the reframe was launched with has been falsified or
cut down, and the surviving case is better evidenced than the one it replaces.

Four premises went in and three came out changed. The deciding obstacle -- that
`/scope` is a conversation and cannot be a workflow -- does not survive `/scope`'s
own `--auto` mode, `/prd`'s statement that `/scope` pre-populates nothing for it,
or `/charter` already serializing parent conversation into a child under the
inline binding. The gating guarantee does not survive `koto next --to` and
`koto overrides record`, which let a parent walk its own declared edges to a
terminal having produced nothing. The fresh-child boundary does not exist to
adopt, and #331's mechanism is precisely a single agent accumulating its own
reasoning across four hops in one window. And the exit-finalization hole that
round 2 was commissioned to investigate was a factual error: the fabricated
Status section is a Phase 2 write at the `/plan` hop, which the issue itself
says.

What survives is specific. The phase-substrate shape is legal, supported, and is
the base case that materialization extends by one state -- `/execute` is twelve
phase states plus one materialization state -- so it costs one template rather
than four, leaves the Dispatch Contract untouched, and forecloses nothing. Its
payoff is that `## Why the Artifact Set Shrinks` lives in a state's details,
physically absent until both artifacts exist. The reduction argument cannot be
removed from a transcript once delivered, and it has to be delivered at the
judgment; what disclosure prevents is the *general* form ever being written
down, so the most an agent can restate at the end is a scoped claim about two
documents in hand. #331's agent quoted the general form at hop zero, having run
nothing. That is the failure the adoption addresses, and it addresses it at the
site where it happened.

Alongside that, koto can force the exit to be a state the agent must stop at and
account for, and can veto the exit path the agent proposes against what is on
disk -- verified, a `full-run` claim with the plan gate failing returns
`advanced: false`. It cannot judge the claim, and `koto next --to done_full`
still reaches the terminal. But the bypass leaves a trace, and the trace has a
reader that already exists: Claude Code's `/workflows` render, on by default,
which showed the #331 signature as four lines of `FAIL / FAIL / PASS / PASS`.
That closes round 1's open question about who reads the log, and it is why the
author's ruling -- that a trace the agent did not author is a substrate property
rather than a checker -- has something concrete behind it. The durability
caveat is load-bearing: the rich event log is deleted at the terminal tick by
default and needs `--no-cleanup`, and the render is machine-local under
`~/.claude/projects/`.

Three things should be said plainly in whatever is authored next, because the
enthusiasm runs past them. Context economy is not a reason to do this: `/scope`'s
own `SKILL.md` is 7.5% of end-of-run load, koto adds 20,000-32,000 characters of
directive traffic over a run, and the net delta at exit is about zero. A
compliant run is 115,500-172,000 tokens of instruction before any conversation,
so the path that follows the instructions is the expensive one and the path #331
took is cheap -- a structural pressure toward the shortcut that no placement
fixes. And the adoption's real risk is an authoring error rather than a
motivated agent: a state whose routes resolve without the agent is silently
skipped, the rule is undocumented, and koto and shirabe have each already
shipped a template with it.

The framing content is where most of the value is and it rides inside this
effort, because koto governs when a directive arrives and never what it says.
The premise/verdict cut needs four categories -- premise, verdict, bound,
obituary -- and under them the bootstrap that survives is roughly eight short
passages of purpose and bound, with no machinery inventory, no reader-economy
argument, and no obituaries. That is close to the inverse of what `SKILL.md`
front-loads today, and the file should end meaningfully shorter rather than
longer.

## Decision: Crystallize

The author elected to crystallize after round 2.
