---
schema: design/v1
status: Proposed
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

Proposed

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

**Chosen: probe with `koto status scope-<topic>` and branch on its exit code**,
reattaching on 0 and opening a session on 2.

**Rejected: `koto init` first, treating the collision error as the signal.** It
reaches a destructive remediation path in koto's own error text and distinguishes
a live session from a stale one only after the fact.

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

### The state graph

Twenty-one states. Five structural rules hold across all of them, and each exists
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

**Phase 3 — the template.** The 21 states, their directives, the `phase:` map.
This is where the fold state's details payload lands, so the content work in
Phase 4 has a destination.

**Phase 4 — the prose.** The `SKILL.md` rewrite, the phase-2 twin's desirability
clause, the design amendment and the three by-title citations.

**Phase 5 — the tests.** The deterministic pull-request test and the two
model-graded scenarios.

## Security Considerations

**The closed write-target set does not widen.** The template writes no durable
artifact; the children write theirs at the paths `/scope`'s security section
already enumerates, and the commit in R17 commits files already inside the set.
The predicate reads only, and the session store is outside the repository.

**No untrusted input reaches a command.** The gate command's only interpolated
value is the topic slug, which Phase 0 validates against `^[a-z0-9-]+$` before
any state exists and re-validates on resume. The slug also composes the session
name, so the same validation bounds what reaches `koto init`.

**A machine-global namespace is a new surface, and it is the sharpest risk here.**
Session names are topic-keyed and resolve from any working directory on the
machine, so two worktrees scoping the same topic collide. koto's own collision
error recommends `koto session cleanup` and `koto cancel --cleanup`, either of
which destroys the other worktree's live run. The design forbids `/scope` from
running either against a session it did not open, records the session it did open
in the state file so ownership is a fact rather than an assumption, and reports
the collision rather than remediating it. The residual risk is that the
prohibition is prose an agent could compose around at runtime after reading
koto's suggestion; the mitigation is a grep over the shipped skill, which bounds
the code this repository ships and not what an agent invents.

**The evidence the exit gate trusts is partly run-authored.** Limb (b) reads an
`absorbed:` declaration the run wrote. The mitigation is that FC18 requires the
declaration and its contribution section as a pair and `/scope`'s validator
pass-through halts the chain on violations, so forging a fold costs most of the
work of performing one, and both halves land in a diff a reviewer reads. The
honest bound: this raises the cost of a false claim, it does not make one
impossible.

**Bypasses remain, by design.** A directed transition and a recorded override
both reach a terminal past a failing gate. Each leaves a typed entry in the
per-hop record, which is the property claimed. Nothing here should be read as
preventing a determined skip.

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

The concurrency prohibition widens from same-worktree to same-machine. The
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
