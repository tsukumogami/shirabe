---
schema: design/v1
status: Planned
complexity: Complex
upstream: docs/prds/PRD-scope-koto-adoption.md
decision_provenance: inline-resolved
problem: |
  `/scope`'s instructions arrive as one 968-line file at invocation, so the only
  passage in it that argues an outcome is worth wanting -- a smaller artifact set
  -- reaches an agent before it has done any of the work that argument judges. A
  run that skipped its hops and asserted them away in prose ends with the same
  file on disk as a run that wrote them and folded them in, and nothing
  distinguishes the two.
decision: |
  Drive `/scope` from a 21-state koto workflow template that delivers each hop's
  instructions at that hop and puts the reduction argument in the fold state's
  details. Decide hop completion with one shell predicate reading the artifact
  tree, and gate the full-run exit on every hop having either its artifact or a
  declared fold. Children stay on inline Skill-tool dispatch; the `wip/` state
  file stays authoritative; the resume ladder is carried across unchanged.
rationale: |
  The reduction argument cannot be withdrawn from a transcript once delivered, so
  the only available property is that its general form is never delivered. A
  state machine is what makes delivery conditional on arrival. Distinguishing the
  two runs falls to the exit gate, and grounding it in `absorbed:`
  frontmatter plus the contribution section FC18 enforces keeps the evidence on
  the filesystem where a reviewer sees it, rather than in a state file the run
  writes and nobody reads.
---

# DESIGN: koto as /scope's instruction substrate

## Status

Planned

Authored under `/scope`'s chain; the parent owns the approval gate. Six decisions
were evaluated. Two ran as delegated evaluations with empirical verification
against koto 0.11.6; four were resolved inline after the delegated evaluations
died on a session limit, per the decision-bypass-with-inline-resolution shape in
`references/fixes/sub-agent-dispatch.md`, and the frontmatter records that. The
verification those four would have run was run directly rather than dropped, and
every claim below that rests on reasoning rather than a command says so.

## Context and Problem Statement

`/scope` walks an author through four hops and deposits an artifact at each. Its
instructions live in a 968-line `SKILL.md` that a reading agent loads whole at
invocation and never unloads. One passage in that file argues an outcome is worth
wanting rather than arguing a rule is correctly written, and the outcome it
argues for is a smaller artifact set.

An agent read the file for its purpose, found that one motivated purpose, and
acted on it: it produced the terminal PLAN, ran none of the hops above it, and
wrote a Status section asserting the upstream artifacts had been consolidated
away, quoting the skill's own sentence as the warrant.

The technical difficulty is that the two runs are indistinguishable at rest.
`/scope` legitimately supports ending with one document — each hop may fold its
upstream into its successor once both exist — so "only a PLAN on disk" is both a
supported outcome and the incident's outcome. Any fix that refuses one refuses
the other unless it can tell them apart, and the thing that tells them apart has
to be something other than the run's own account of itself.

Two prior framings were falsified before this design and are not available.
Nothing here creates a context boundary: koto does not launch child agents, and
no such boundary exists in this repository to adopt. And nothing here reduces
total resident context across a run; measured, the net change is about zero,
because the substrate adds directive traffic on every tick.

## Decision Drivers

**A delivered argument cannot be withdrawn.** Whatever an agent reads, it can
restate. The only reachable property is that the general form is never written
where a pre-hop reader finds it.

**The distinguishing evidence must not be the run's self-report.** `/scope`'s
existing audit field fails open: leaving the executed-hop list empty disarms four
readers rather than tripping any.

**Gates are bypassable and the design must not pretend otherwise.** A directed
transition reads neither gates nor transition guards, and a recorded override
injects a synthetic pass. The claim is that a skip leaves a mark.

**The children are out of bounds.** `/brief`, `/prd`, `/design` and `/plan` stay
on inline dispatch and are not modified, so nothing here may require a change to
them.

**Two engine traps are live and filed.** A non-terminal state carrying an
evidence block with no guarded transition is advanced through silently without
delivering its directive; and `context_assignments:` is discarded without a
diagnostic. Both appear in shipped templates today.

**The author's experience should not change.** Four hops, confirmed up front,
resumable, reducible per hop once the artifacts exist.

## Considered Options

Six decisions, each with the alternative it beat.

### State granularity

**Chosen: 21 states**, mapping `/scope`'s five phases onto one setup state, two
for discovery and the chain proposal, four hop states plus one shared fold state,
six for the exit region, three cleanup states and four terminals.

**Rejected: one state per phase.** Five states cannot carry per-hop gates, which
is where the whole exit binding gets its evidence.

**Rejected: one state per hop-step**, expanding the eight-step per-child loop
into states. It multiplies the surface the static check has to police for no
property the coarser graph lacks.

### How hop completion is decided

**Chosen: a `command` gate running one shared predicate over the artifact tree.**

**Rejected: an agent-submitted evidence field plus a validator.** It satisfies
the requirement that completion be computed from the filesystem, and loses the
requirement that the outcome reach the surviving record — evidence values do not,
gate outcomes do. A reviewer would see the run's claim rather than the engine's
finding.

**Rejected: a `context-exists` gate.** The context store is written by the run,
which re-admits the self-report the design exists to remove.

### Exit region shape

**Chosen: a blocked state for the full-run path, evidence-guarded self-loops for
the other two.** A blocked state re-declaring its gate reports the failing check
in its own `blocking_conditions`; a self-loop does not. That is worth a state
where the refusal is the feature, and the full-run refusal is the feature.

**Rejected: blocked states for all three,** which adds two states carrying no
assertion any test needs. **Rejected: self-loops for all three,** which makes the
one criterion the exit binding exists for harder to assert against.

### Session lifecycle

**Chosen: probe for the session, then reattach only when its recorded origin
worktree matches this invocation's.** The probe distinguishes no-session from
live-session, and the origin check distinguishes this worktree's run from
another's. On a mismatch the run reports the collision and stops.

**Rejected: branching on the probe's exit code alone.** This was chosen first and
is wrong in exactly the case it was meant to handle. A cross-worktree collision is
the case where the probe succeeds, so an exit-code-only branch reattaches to
another worktree's live run and ticks its position forward against a different
artifact tree — replacing a loud refusal with a silent adoption.

**Rejected: `koto init` first, treating the collision error as the signal.** It
reaches a destructive remediation path in koto's own error text, and the error is
raised only after the fact.

**Rejected: discriminating the session name by worktree.** It removes the
collision at the cost of the name's derivability from the topic, which the probe
depends on.

### Phase recovery

**Chosen: a declared `phase:` key per state in the template**, with the static
check asserting every state has one.

**Rejected: a naming convention** such as a phase prefix on state identifiers. It
encodes the map in identifiers, so a rename silently changes the reported phase
and there is nothing for a check to assert.

### Passage placement

**Chosen: delete the general-form argument from `SKILL.md` and deliver it, with
the four per-type contribution rows, in the fold state's details.**

**Rejected: relocating it into the phase-2 reference file**, which is where a
correctly-scoped copy already lives. That file is inside the pre-hop set by
transitive path-naming, so the relocation would satisfy a fixed-string grep on
`SKILL.md` and leave the requirement violated.

## Decision Outcome

`/scope` gains a koto template whose states correspond to its own phases and
hops. The template is the instruction surface: each hop's directive arrives when
its state is entered, and the fold judgment's directive — including the argument
for folding and the four per-type contribution rows — arrives only at the fold
state, which an agent reaches holding two documents.

Each hop carries a `command` gate running `hop-complete.sh`, which returns 0 when
that hop's artifact is at its canonical path or a downstream survivor declares it
in `absorbed:` frontmatter. The same predicate runs chain-wide at the full-run
exit, which is refused unless every hop satisfies one limb or the other, naming
those that satisfy neither.

The `wip/` state file stays authoritative for every field it carries today; the
session holds position within a run and nothing else. The resume ladder is
carried across unchanged, because sixteen of its twenty rows key on artifact
status, child intermediates or the branch, none of which the substrate replaces.

Together these produce the property the whole effort is for: a run that wrote its
documents and folded them reaches the full-run terminal, a run that asserted them
away does not, and the difference is a gate outcome the engine wrote.

## Solution Architecture

### Components

| Component | Path | Responsibility |
|---|---|---|
| Workflow template | `skills/scope/koto-templates/scope.md` | 21 states, their directives, gates and guards; the `phase:` map |
| Completion predicate | `skills/scope/scripts/hop-complete.sh` | Decides one hop under both limbs; shared by per-hop and chain-wide gates |
| Deterministic test | `skills/scope/scripts/scope-substrate_test.sh` | Drives a real session; asserts the refusal, the record contrast, and disclosure |
| Template lint | `scripts/check-template-directives.sh` | Both static predicates over every shipped template |
| Rewritten prose | `skills/scope/SKILL.md` | Purpose stated, terms defined, licence sentences bounded, argument removed |
| Tool declarations | `skills/scope/requires.tsv` | The koto verbs `/scope` now invokes, and the flags each carries |

### The state graph

Twenty-one states, carried here rather than referenced, because the working
notes that produced them are non-durable and this table is the specification
the implementation builds from.

`outcome` is the per-hop evidence enum; `verdict` is the fold's. Guards combine a
gate's exit code with an evidence field, never a gate alone.

| State | Terminal | Accepts | Gates | Routes on | Phase |
|---|---|---|---|---|---|
| `setup` | no | `setup_result: [ready, blocked]` | — | ready → `discovery`; blocked → `bail` | 0 |
| `discovery` | no | `discovery_result: [proposed, blocked]` | — | proposed → `chain_proposal`; blocked → `bail` | 1 |
| `chain_proposal` | no | `author_decision: [proceed, adjust, bail]` | — | proceed → `hop_brief`; adjust → `discovery`; bail → `bail` | 1 |
| `hop_brief` | no | `outcome: [landed, skipped, bail]` | `brief_complete` | landed → `hop_prd`; skipped → `hop_prd`; bail → `bail` | 2 |
| `hop_prd` | no | `outcome: [landed, skipped, rejected, bail]` | `prd_complete` | landed → `fold`; skipped → `hop_design`; rejected → `exit_re_evaluation`; bail → `bail` | 2 |
| `hop_design` | no | `outcome: [landed, skipped, rejected, bail]` | `design_complete` | landed → `fold`; skipped → `hop_plan`; rejected → `exit_re_evaluation`; bail → `bail` | 2 |
| `hop_plan` | no | `outcome: [landed, skipped, bail]` | `plan_complete` | landed → `fold`; skipped → `finalize`; bail → `bail` | 2 |
| `fold` | no | `verdict: [keep, absorb]` | `plan_present`, `design_present` | routes back to the next unrun hop, or forward to `finalize` when none remains | 2 |
| `finalize` | no | `exit: [full-run, re-evaluation, abandonment-forced]` | — | one route per exit value | 3 |
| `exit_full_run` | no | `exit_artifacts`, `plan_execution_mode` (both required) | `chain_complete` | pass → `cleanup_full_run`; fail → `full_run_blocked` | 3 |
| `full_run_blocked` | no | `next_move: [recheck, abandon]` | `chain_complete` (re-declared) | recheck+pass → `cleanup_full_run`; recheck+fail → self; abandon → `exit_abandonment` | 3 |
| `exit_re_evaluation` | no | `boundary`, `decision_record_sub_shape`, `exit_artifacts`, `retry_or_abandon` (required) | `decision_record_present` | every arm carries `retry_or_abandon`: pass+retry → `cleanup_re_evaluation`; fail+retry → self; abandon → `exit_abandonment` | 3 |
| `exit_abandonment` | no | `triggering_child`, `exit_artifacts`, `retry_or_cancel` (required) | `forced_artifact_present` | every arm carries `retry_or_cancel`: pass+retry → `cleanup_abandonment`; fail+retry → self; cancel → `done_cancelled` | 3 |
| `bail` | no | `bail_ack: [cancel, force_materialize]` | `child_intermediate_present` | force_materialize routes to `exit_abandonment` on both gate outcomes; cancel → `done_cancelled` | 3 |
| `cleanup_full_run` | no | `cleanup_result: [done]` | — | → `done_full_run` | 4 |
| `cleanup_re_evaluation` | no | `cleanup_result: [done]` | — | → `done_re_evaluation` | 4 |
| `cleanup_abandonment` | no | `cleanup_result: [done]` | — | → `done_abandonment` | 4 |
| `done_full_run` | **yes** | — | — | — | 4 |
| `done_re_evaluation` | **yes** | — | — | — | 4 |
| `done_abandonment` | **yes** | — | — | — | 4 |
| `done_cancelled` | **yes** | — | — | — | 4 |

Four properties of this table are load-bearing and were each corrected after a
run of an earlier version exposed the alternative.

**`rejected` appears only on `hop_prd` and `hop_design`.** Those are the two
children with a Phase-N reject, and a reject is not a bail: it sets a
re-evaluation exit with a `boundary` of `prd` or `design`. Offering the value on
`hop_brief` or `hop_plan` would route to an exit state whose required `boundary`
enum has no legal value for it.

**Every gate that decides a design hop reads both DESIGN locations.** An earlier
version had `fold`'s `design_present` test only `docs/designs/current/`, which is
reached by a lifecycle transition long after a `/scope` run ends, so the gate was
false on every run and `hop_design ↔ fold` livelocked with `hop_plan` unreachable.
The canonical DESIGN path is the pair, stated once and read identically by
`design_complete`, `design_present` and the completion predicate.

**Every gate-failing state has an escape.** `exit_re_evaluation` and
`exit_abandonment` retry on their own evidence and also offer a route out, so an
agent that cannot produce the required artifact is not stuck permanently.

**`bail` can reach abandonment.** Its evidence is a two-value choice rather than
an acknowledgement, so the resume ladder's Force-materialize option has a route
regardless of what the child-intermediate gate finds. An earlier version made
that option's destination depend on unrelated files, so the same author choice
silently cancelled or force-materialized.

Two compile-level rules bind the routing and were established by compiling the
graph rather than reasoning about it. A state that declares a gate must route on
that gate somewhere, so `force_materialize` names the gate on both outcomes
rather than ignoring it — a state whose evidence routes past its own gate is
rejected. And every branch out of a state must be distinguishable by a shared
field, so the discriminating value appears on the passing arm too, not only on
the escapes; transitions that share no field are rejected as not mutually
exclusive.

Five structural rules hold across all twenty-one states, and each exists
because something breaks without it.

**Every non-terminal state carries at least one guarded transition keyed on an
agent evidence field.** This is the defence against the silent-skip trap, and it
is stated in the template's own description so a reviewer reads it before the
states.

**Every gate is co-routed with an evidence field.** A guard referencing only gate
output resolves without the agent, which delivers no directive — the same trap
through a different door. So a hop's forward transition reads
`{gates.<hop>_complete.exit_code: 0, outcome: landed}` rather than the gate alone.

**Every hop gate reads the artifact tree and nothing else.** No gate command in
the graph contains `wip/scope_`, so the static check has nothing to catch and the
prohibition holds by construction. The bail state's gate does read `wip/`, but
child-intermediate prefixes only, never the parent's own.

**Each exit path's required fields live on that path's own state.** The
finalization state accepts only the exit enum. Submitting a field belonging to
another path is an unknown field there, and koto refuses unknown fields at
submission before any write.

**Cleanup is a pre-terminal state.** A terminal's directive never crosses the
wire, so the cleanup phase has to be instructed somewhere the agent still ticks.

### The completion predicate

One script decides a hop under both limbs, and the per-hop and chain-wide gates
share it so two gates cannot disagree about the same file.

**Limb (a) — the artifact is present.** Not `test -f`. The path must be a regular
file, not a symlink, non-empty, and it must pass `shirabe validate` clean. `test
-f` alone accepts `touch` and follows a symlink to any file on the machine, and
under the per-hop commit either would then be committed as a completed hop. The
validator requirement is what stops a three-line stub — a frontmatter delimiter
and a `schema:` key and nothing else — from counting as a landed hop; the
validator rejects such a file with eight errors, and limb (a) has no business
being satisfied by something limb (b) would refuse.

**Limb (b) — the hop is declared absorbed.** Two scoping rules, and dropping
either one defeats the limb.

*Frontmatter only.* The scan stops at the closing `---`, so a mention anywhere in
the body cannot satisfy the gate — including a fenced YAML block that looks like a
declaration. This matters more than it appears: `shirabe validate` returns clean
on such a document, because FC18 is gated on `absorbed:` being present as the
validator's own frontmatter parser sees it, so a body-block declaration is
invisible to the backstop as well as to the reader.

*The `absorbed:` key specifically, matched as whole entries.* Not a grep over the
frontmatter block for the artifact's basename. An earlier version did that, and
the consequence was decisive: the `upstream:` line that a hundred documents in
this repository already carry as ordinary convention satisfied the check, so the
reported incident plus three lines of routine YAML made all four hops pass and
reached the full-run terminal carrying an engine-authored gate outcome vouching
for a chain it never walked. That version made the incident easier to get away
with than it is today.

Having found a declaration, the predicate checks the FC18 pairing itself — the
`## Status` absorption line and the contribution heading each entry implies — and
then requires `shirabe validate` to come back clean as a second condition. The
order is deliberate twice over. A clean validation means no violation was found,
not that an absorption was verified, so relying on it alone would let a
declaration the validator cannot see pass unexamined. And matching the
declaration before validating is what makes the refusal accurate: validating
first skips a survivor that declares the fold and fails to validate, and the run
is then told no declaration exists when one does — a true refusal with a false
reason, which sends an author to the wrong file.

**The predicate refuses rather than degrades when the validator is absent.** Both
limbs answer to `shirabe validate`, so a missing binary would silently reduce
this check to bare existence — which four `cp` commands defeat, copying one
artifact onto every canonical path and walking the whole chain past the gate with
a passing outcome recorded at each hop. It exits 2 with a diagnostic naming the
missing binary instead, and the environment running the gate carries the
validator explicitly, the same arrangement the deterministic test requires for
koto.

Exit 2 is deliberate rather than incidental, because the hop guards enumerate 0
and 1. No transition matches it, so the run holds position: the gate is reported
in the state's blocking conditions as agent-actionable, carrying the exit code,
and the directive is re-delivered. That is the right semantics for a missing
dependency and it is better than exit 1, which advances the hop with a recorded
failure and so conflates "this hop is not done" with "I cannot tell whether it is
done." The author is not trapped — the `skipped` and `bail` routes do not
reference the gate and still resolve.

**One bound, wider than the requirement it serves.** Crediting only on a clean
whole-document result is stricter than the FC18 pairing: an unrelated lint error
anywhere in a survivor, or in a hop's own artifact, fails that hop's gate. Phase
2's validator pass-through halts the chain on such violations first, so this is
expected to be redundant rather than restrictive — but it couples hop completion
to whole-document lint, which is wider than "that hop's durable artifact is
present at its canonical path", and a narrower implementation may filter to the
FC18 and FC04 codes.

**Cascading folds need no recursion**, because a survivor carries and declares
every absorbed ancestor, so a flat scan over downstream survivors finds a
twice-folded hop.

### Data flow at a hop

```
enter hop state
  -> directive delivered (this hop's purpose, not the chain's)
  -> agent invokes the child inline via the Skill tool
  -> child returns; artifact lands in the working tree
  -> hop gate runs hop-complete.sh --hop <name> --topic <slug>
  -> agent submits {outcome: landed|skipped|rejected|bail}
  -> guard combines gate exit code with outcome
  -> commit the artifact to the run's branch, naming the hop
  -> route: fold (both endpoints ran) | next hop | exit path
```

The gate runs before the commit so its result is independent of git state, and
the commit follows so a failed gate never produces a commit claiming a hop
landed.

### Passage dispositions

The disposition for each entry the PRD's Appendix A enumerates. Two were
foreclosed by the PRD itself and are marked; the rest were decided here.

| Entry | Disposition | Destination |
|---|---|---|
| D1 — the PLAN-as-product framing | Rewritten in place | `SKILL.md` Overview. The framing goes; the protected path statement stays, since the exit enumeration loses a limb without it. |
| D2 — the direct-entry licence | Licence deleted, bound kept | `SKILL.md` Chain-Proposal Output. The replacement leads with what direct entry costs and keeps the following bound, given an antecedent the deleted sentence used to supply. |
| P1 — `## Why the Artifact Set Shrinks` | Deleted; general form moved | The fold state's details. Its slot takes `## Why Each Hop Is Taken`. |
| P2 — `## Consolidation Judgment` | Retained, rewritten as bounds | Same slot in `SKILL.md`. The notice that files get deleted stays; every sentence arguing the reduction is worth making goes. |
| P3 — the reduction conclusion in the lede | Retained, rewritten as a bound | `SKILL.md` Overview. Four forward references depend on the slot, so the slot survives with a bound in place of a purpose. |
| P4 — withdrawn-design narration | **Deleted** (retention foreclosed) | — Every correction it narrates is already materialized in the enumeration above it. |
| P5 — the eight undefined-term sites | Retained; one definition added | Inside `## Why Each Hop Is Taken`. The definition says what kind of thing a hop's output is; the per-type values are P6 and stay out. |
| P6 — the four per-type declarations | **Retained** (only legal disposition) | The four format references, untouched, since the children may not be modified. The template quotes all four at the fold state. |

One passage outside Appendix A needs the same treatment and is recorded here so
the work is not discovered later: `phase-2-chain-orchestration.md`'s
reader-economy clause. `phase-1-discovery.md` names that file by path, so it is
inside the pre-hop set by transitive closure, and deleting only the `SKILL.md`
copy would satisfy a fixed-string grep while leaving the requirement violated.
Its desirability clause moves to the fold state's details with the rest.

### State, resume and the record

Three behaviours the requirements name that the graph alone does not show.

**A finished run stays distinguishable from one that never started.** The state
file's `exit:` field is written at the exit state and survives the session, so a
run whose session is gone still reports how it ended. This is the one resume-ladder
row the substrate genuinely breaks — the row keying on the exit field being set —
and keeping `exit:` in the state file is what repairs it.

**`phase_pointer:` is written after the tick, not before.** It names the `/scope`
phase the run is in, derived from the session's position through the template's
declared `phase:` map when a session exists, and written from `/scope`'s own phase
when none does. Ordering it after the tick that advances the session is what keeps
the durable resume decision from depending on a value that could be half-updated:
on reattach the session's position overwrites the recorded pointer before the
ladder evaluates it.

**A skipped hop is recorded and satisfies nothing.** `chain_skipped:` keeps its
present meaning and its re-entry protection, and the completion predicate has no
skip limb — so a skipped hop cannot be laundered into a completed one at the exit.

**Four resume rows interact with the session** and the rest do not. The row that
offers Discard on a malformed state file removes the ownership record, so the
probe must treat an orphaned session as a collision rather than as its own. The
row that resumes at the recorded pointer is covered by the ordering rule above.
The row offering Force-materialize needs a route to abandonment regardless of what
the child-intermediate gate finds, which is why the bail state's evidence is a
choice rather than an acknowledgement. And the row keying on the exit field is
covered by the first paragraph here.

### The pre-hop set

The requirement that the reduction argument reach no reader before the first hop
is only mechanizable against a named set of files. The set is a transitive
closure: `skills/scope/SKILL.md`, every file its Reference Files table names as
loading before the first hop is entered, and every file those in turn name by
path. Enumerated it is sixteen files.

| Level | Files |
|---|---|
| 0 | `skills/scope/SKILL.md` |
| 1 | `references/parent-skill-pattern.md`, `references/parent-skill-state-schema.md`, `references/parent-skill-resume-ladder-template.md`, `references/parent-skill-security.md`, `skills/scope/references/state-schema.md`, `skills/scope/references/phases/phase-0-setup.md`, `skills/scope/references/phases/phase-1-discovery.md`, `skills/scope/references/phases/phase-resume.md` |
| 2 | `references/parent-skill-child-inspection.md`, `references/worktree-discipline.md`, `references/cross-repo-references.md`, `references/pipeline-model.md`, `skills/scope/references/phases/phase-2-chain-orchestration.md`, `skills/charter/references/phases/phase-finalization.md`, `docs/prds/PRD-shirabe-charter-skill.md` |

Two things about this table are the reason it is carried here rather than
re-derived. The closure pulls in files the Reference Files table marks as loading
at Phase 2 — the child-inspection and worktree-discipline references, and the
phase-2 orchestration file itself — because a Phase 0 or Phase 1 file names them
by path. Treating the phase-2 file as a one-off catch rather than as an instance
of the closure rule is how a later edit to either of the other two violates the
requirement silently.

And a sweep of all sixteen found exactly one violation beyond `SKILL.md`: the
reader-economy clause in the phase-2 orchestration file. The other matches are
bounds rather than desirability arguments — statements that Phase 1 decides
nothing about the size of the artifact set, and that a parent may not decide an
artifact is not worth producing before it exists — which are the opposite claim
and stay.

### Conformance changes

Two edits to the shared parent-skill contract, both additive.

The contract gains a statement that a parent may drive its phases from a workflow
session while declaring `storage_substrate: wip-yaml-md`, because the session
holds position within a run rather than persisting state between invocations.
This is a widening rather than a variance: it names a second thing a parent may
do, and `/charter` is not required to do it. The precedent is the contract's own
anticipation of a second parent adopting a different dispatch binding.

The Observability Surface gains the session-status surface and the per-hop record
alongside the durable-artifact polling and `git log` reads it already enumerates,
because its current wording closes with "nothing else" and a workflow-driven
parent reads both.

`/charter` is unmodified. Substrate divergence between the two parents is
permitted three ways over in the contract, and the one divergence that has
already shipped cost three or four stale sentences across a full release cycle.

### The exit gate

```
exit_full_run
  gate chain_complete: for each hop in planned_chain, hop-complete.sh
  exit 0 -> cleanup_full_run -> done_full_run
  exit 1 -> full_run_blocked   (gate re-declared here, so blocking_conditions
                                names the failing check)
              recheck  -> re-evaluate the same gate
              abandon  -> exit_abandonment
```

## Implementation Approach

Five phases, ordered so nothing lands before the thing it depends on.

**Phase 1 — the harness, before any new scenario.** The four eval-runner fixes
plus rate reporting. Written first because a new scenario against the current
runner reports green having graded nothing.

**Phase 2 — the predicate and the lint.** `hop-complete.sh` with its fixture
suite, and the template lint with its allowlist. The lint's allowlist carries the
four known violations with issue references so it can land without failing on its
own introduction.

**Phase 3 — the template and the tool declarations.** The 21 states, their
directives, the `phase:` map. This is where the fold state's details payload
lands, so the content work in Phase 4 has a destination.

`skills/scope/requires.tsv` gains a record per koto verb the skill now invokes —
`init` with its template and variable flags, `next` with its evidence and
retention flags, `status`, and the context verbs the origin-worktree record uses.
`/scope` declares none today, and a checker enforces that declarations match call
sites, so the template and the declarations land together or CI fails on the
template alone. `/execute`'s file is the shape to follow.

**Phase 4 — the prose.** The `SKILL.md` rewrite, the phase-2 twin's desirability
clause, the design amendment and the three by-title citations.

**Phase 5 — the tests.** The deterministic pull-request test and the two
model-graded scenarios.

## Security Considerations

**The closed write-target set widens, and the widening is declared.** An earlier
version of this section claimed it did not, which was false three ways. Three
groups are added to `skills/scope/SKILL.md`'s enumeration. First,
`docs/designs/current/DESIGN-<topic>.md` joins the Mutations group and the
`abandonment-forced` group, because Phase 2 already treats it as a canonical
design path and both the completion predicate and the per-hop commit reach it;
the same edit adds `docs/plans/` to the `abandonment-forced` group, closing a
pre-existing inconsistency with the Mutations group. That inconsistency is inert
today and stops being inert here: the per-hop commit turns the enumeration into
one that governs commits, at which point every omitted path is a live write at an
undeclared target. Second, a Commits group names the four canonical artifact
paths plus the design fallback and confines the resulting `.git/` writes to `git
add` and `git commit` restricted to those pathspecs. Third, an out-of-repo
ephemeral group names the koto session store and koto's template compile cache.
Neither is version-controlled and neither is referenced from a committed
artifact; naming them is what keeps the set enumerable rather than repo-scoped.

**The per-hop commit carries four preconditions.** HEAD must be a named branch;
that branch must not be the repository's default branch; the recovered name is
validated before it reaches any emitted shell. `/execute`'s own template records
why the second one cannot be skipped — `main` is a well-formed branch name that no
pattern check rejects, so the precondition has to be positional. Staging is `git
add --` on the one canonical path, never `-A` and never `commit -a`, so a hop
commit cannot sweep the run's own `wip/` intermediates into the tree. The message
is composed only from the hop enum and the validated slug; any future rationale
text goes through `git commit -F -` rather than `-m`, per the pattern's
interpolation surface, which this is the first parent action to touch.

**The topic slug is the only value interpolated into a gate command, and koto
does not check it.** Phase 0 validates it and the resume ladder re-validates any
slug recovered from a path on disk before interpolation, which bounds the session
name too. koto's own variable validation is not a second line here: its pattern
rejects shell metacharacters but permits dots and slashes, so a traversal-shaped
topic renders into a gate command intact. Path traversal is closed by shirabe's
regex alone, and the predicate re-asserts the slug pattern before composing any
path. `--upstream` never reaches a gate.

**Two values now live in the session, and both are re-validated coming back.**
The recorded session name is never interpolated: the name is recomputed from the
validated slug at every use and the stored value is compared to it for equality,
which is all the ownership test needs. Every other value recovered from the
session is re-validated at the resume entry under the rule the pattern states for
state-file fields — enums against their enum, path-valued fields against the
anchored pattern for their type. This extends the existing rule rather than
restating it, because koto does not constrain a string-typed evidence field at
all, and several exit-path required fields are path-valued strings.

**The session namespace is the sharpest risk, and reattach is where it bites.**
Session names resolve from any working directory sharing a session store, so the
same name is one session across every worktree using that store. A probe that
reattaches on a successful status alone is therefore wrong in exactly the case it
was meant to handle: in a cross-worktree collision the status succeeds, so the
probe would silently adopt another worktree's live run and tick its position
forward against a different artifact tree — a failure the collision error at
least refuses out loud. So the probe reattaches only when the session's own record
of its origin worktree matches this invocation's, and reports the collision
otherwise. That record lives in the **session's context store**, not in the
state file: the state file is per-worktree and absent in the colliding worktree,
which is the whole failing case, so putting the origin there makes the check
inert. Reading an identity another run wrote is a different use of that store
than a run attesting to its own completion, which is why this does not reopen the
rejected `context-exists` gate above. The store location is itself an environment
input rather than a constant, so the record carries it alongside the name; two
invocations against one topic under different stores would otherwise each find
nothing and open a second session.

`/scope` never runs a cleanup or cancel verb against a session it did not open —
which is what koto's collision text recommends and what would destroy the other
run. The residual is stated plainly: the prohibition is prose an agent can
compose around, and the grep over the shipped skill bounds this repository's code
rather than what an agent invents. One live prompt for that behaviour is worth
naming because it fires on every tick rather than only on a collision — koto emits
discovery warnings about unrelated corrupted sessions regardless of which store
is configured, and "state file corrupted" reads as an invitation to clean up. The
template's own directive says to ignore them.

**The evidence the exit gate trusts is run-authored, and forging it is cheap.**
Limb (b) reads an `absorbed:` declaration the run wrote. FC18 enforces the
declaration and its contribution headings as a pair, but it checks structure
only: the path pattern, chain position, heading adjacency, and one well-formed
status line per entry. It never inspects a section's body. A document declaring
three absorptions whose contribution sections each contain a single character
validates clean. An earlier version of this section claimed forging a fold costs
most of the work of performing one; that is false, and the honest bound is about
ten lines of boilerplate. What the pairing buys is that the forgery is structural
and on the filesystem, so it lands in a diff a reviewer reads, where an empty
executed-hops list in a state file does not. That is the whole of the claim: the
evidence moves from a place nobody looks to a place someone might.

**Bypasses remain, and the mark they leave has to be retained deliberately.** A
directed transition reaches a terminal past a failing gate without evaluating it,
and a recorded override injects a synthetic pass whose log entry does not even
preserve what the gate would have said. Each leaves a distinguishable typed entry.
But reaching a terminal deletes the session by default — the run then returns not
found, and disappears from the workflow listing — so every terminal transition
passes `--no-cleanup`. An earlier decision here ruled the opposite, on the ground
that retaining the session forfeits the terminal index entry; that was measured
and is false, and without the flag the per-hop record is destroyed at the exact
moment a run finishes and an author would go looking. The record is machine-local
and outside the repository. It is read, never copied into a committed artifact or
a pull-request body — both because copying makes the run the author of its own
audit trail, and because the record carries absolute filesystem paths that can
name private repositories.

**The deterministic test drives a real session, in an isolated store.** It points
the session store at a temporary directory, names its session outside the
production prefix, and calls no cleanup verb against a name it did not create
there. Given the shared namespace, a test skipping any of the three could destroy
a live run on a developer machine or in CI.

**The prohibition on reading the state file covers the scripts gates invoke, not
only the gate command strings.** The template lint sees the strings; a later
`wip/scope_` read added inside the predicate would be invisible to it, so the
lint reads both.

**No secrets, tokens or credentials are named, and no external URL is fetched or
executed.**

## Consequences

### Positive

The reported incident is refused by a shell predicate with no model in the loop,
which is what makes the pull-request test buildable. Verified against fixtures:
the incident shape returns exit 1 for three hops.

The instruction an agent holds at the fold judgment is scoped to the two
documents in its hands, and the general form is nowhere in the pre-hop set.

`SKILL.md`'s motive prose drops from about 70 lines to about 12, which is the
change the exploration predicted, even though the file's total length falls only
about 3.6%.

Two engine traps are policed by a check that runs on every template in the
repository, not just this one.

### Negative

Two state stores, reconciled by one rule rather than a procedure: the session is
authoritative for position, the state file for everything else.

The concurrency prohibition widens from one worktree to every worktree sharing a
session store. The
failure mode improves — a loud error before anything is written, where today it
is a silent race on one file — and the blast radius grows.

A `/scope` run now produces commits it did not before. This is a visible change
to the author's experience, accepted because the resume anchor is worthless
uncommitted.

The per-hop record is local to the session that produced it, so a pull-request
reviewer does not see it. Accepted rather than mitigated: copying it into a PR
body would make the run the author of its own audit trail.

### Mitigations

The predicate is one file with one job, so a fifth artifact type edits one place.

The template's description states the two structural rules a future author must
follow, the way `/work-on`'s template states its self-loop rule, so the traps are
documented at the point of authoring rather than discovered at runtime.

## References

- `docs/prds/PRD-scope-koto-adoption.md` — the requirements this design serves.
- `docs/briefs/BRIEF-scope-koto-adoption.md` — the framing.
- `skills/execute/scripts/settled-branch-record_test.sh` — the model for the
  deterministic test.
- `references/parent-skill-pattern.md` — the contract this widens.
- `references/fixes/sub-agent-dispatch.md` — the fallback shape the frontmatter's
  `decision_provenance` records.
