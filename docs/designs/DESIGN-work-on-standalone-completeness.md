---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-work-on-standalone-completeness.md
problem: |
  A single-issue run reaches "PR created, CI green" and stops. The
  document-chain cascade cannot be entered from it at all, because the cascade
  script takes a plan-shaped path as its sole argument and an ordinary issue has
  none to give. Its other finishing obligations exist as prose the template
  delivers and a run may skip, with nothing that catches the omission. An
  obligation reaches a child only if something in the compiled template leads to
  it, so where a fix is written decides whether it reaches one at all.
decision: |
  Move the cascade script under /work-on and have /execute reach it over a
  cross-skill path, the third instance of a dependency direction this repository
  already chose twice. Guard the cascade with two composed conditions: role
  first on ci_monitor, then anchor presence as a gate-only transition that emits
  nothing when there is no anchor. Extend ci_monitor and pr_creation in place
  for the two obligations with an exact precedent, and add one narrow state for
  the rest. Evidence a completed cascade by its observed post-state, with the
  commit half read from the commit's own paths rather than the working tree.
rationale: |
  Every choice follows a shape the repository already has rather than inventing
  one: the cross-skill dependency direction, the gate-only transition, the
  verbatim-copied merge gate. The one place the design deliberately does not
  follow an existing shape is the cascade's evidence, because the existing shape
  there is a self-report the repository has since found to be unreliable in six
  measured places, and building a second caller on it would reproduce inside the
  fix the defect the fix is for.
---

## Status

Planned

## Context and Problem Statement

`/work-on` invoked on one issue runs the work, opens a pull request, watches CI
and stops. What it leaves looks finished and is not, and three dispatched worker
sessions each needed a supervising session to supply the remainder by hand.

The accepted PRD establishes that this is two defects rather than one, and that
the tracking issue's original account is wrong about which.

**The cascade cannot be entered.** `skills/execute/scripts/run-cascade.sh` takes
a plan-shaped document path as its sole positional argument and has no mode that
accepts no document, so a run whose issue was filed on its own has nothing to
hand it. The neighbouring case — an anchor that resolves to no upstream chain —
already behaves correctly and is pinned by its own test.

**The other obligations are delivered and unenforced.** `work-on.md`'s per-state
directives cite the reference files that carry them, so a run receives the
instruction; all three field runs received it and skipped it. What is missing is
anything that catches the omission.

A fourth run, observed live while this design was being written, corroborates
the enforcement diagnosis from an angle the three earlier ones did not. A worker
in another repository ran the tactical chain to completion — brief, PRD, design,
plan, the fold verdict, the full-run exit, exit artifacts and cleanup — and then
implemented the resulting plan's nine issues **by hand**, in dependency order,
one commit per unit, invoking neither entry point. Its own account of why:
implementation is not a hop it tracks. The supervising session then had to supply
pull-request conventions, board completeness checking and per-step verification
by hand, which is the same cost the three earlier runs imposed.

Two things about that evidence are worth stating precisely, because it is
tempting to make it carry more than it does. Part of the cause was a
coordination gap rather than a skill gap: the brief that dispatched that worker
named its entry point and never said what should pick up the finished plan. And
what it demonstrates is that **the handoff at chain exit is undefined** — a
completed plan sits with no driver attached, and a competent agent's fallback is
to hand-run it without any of the finishing discipline this feature is about.
That is a real defect and it is **not** one this design addresses; it is not in
the accepted PRD's scope, and it argues for specifying the handoff rather than
for any of the directions this feature chose between. It belongs in its own
issue.

What it does corroborate is the diagnosis underneath this feature: when the
finishing discipline is not enforced where the work happens, capable agents
reconstruct it by hand or skip it, and the cost lands on whoever is supervising.

Two constraints decide where any fix may be written.

**The first is narrower than an earlier draft of this design claimed, and the
narrower form is the useful one.** That draft said a child never loads
`SKILL.md`, making anything written there unreachable. Settled by inspecting
both codebases:

- koto does not load `SKILL.md`. `src/cli/init_child.rs` contains no reference
  to it, builds no prompt and spawns no process; it seeds session state from the
  compiled template. **Established by file inspection, not by watching a spawn**
  — the remaining points do not depend on it, and an observed materialization
  would be better evidence if one falls out of implementation.
- But a child **can** reach it, because the template cites it.
  `work-on.md:1084` sends the agent to the `## Definition of Done` section of
  `SKILL.md` — the same mechanism by which the template sends it to
  `references/phases/phase-6-pr.md`.
- And a child that never read `SKILL.md` still runs correctly, because the
  template carries the child contract itself. `work-on.md:851-853` describes
  plan-backed mode in the `entry` state's own prose. `SHARED_BRANCH` is a
  declared template **variable** (`:37`), consumed in a transition condition
  (`:287`), and its two behavioural rules are in the template's own prose: do
  not create a branch (`:984-985`) and the shared-PR route (`:1176`), reinforced
  by `references/phases/phase-1-setup.md:17` and `phase-6-pr.md:52`, both
  reached from states that cite them.

  That last point is worth stating because the contrary inference is tempting
  and wrong: it was suggested that a child reading only the template would enter
  the right mode and then create its own branch and its own pull request,
  contradicting the orchestrator. It would not. Both rules are in the template.
  What is genuinely `SKILL.md`-only is the `$ARGUMENTS` parsing that extracts
  the child's inputs — which a koto-seeded child does not need, because koto
  seeds evidence rather than an argument string.

So `SKILL.md` is not privileged in either direction. It is reachable exactly as
a reference file is: **only when a state's prose leads there.** The real
constraint is about the path rather than the filename — *an obligation is
reachable by a child only if something in the compiled template leads to it* —
and the realistic failure is writing an obligation into `SKILL.md` without
citing it from any state, which works under direct invocation, where `SKILL.md`
is loaded wholesale, and silently reaches no child.

That sharpens the test this design applies to any change. Not "name the file it
lands in", but **name the file, and name the state whose prose leads a child to
it.** A change that cannot name the second half does not reach a child. The
sharpened form is checkable by a reviewer who was not party to working it out,
which the original was not.

**The failure it guards against is the one someone will actually commit.** An
obligation written into `SKILL.md` and cited from no state works perfectly under
direct invocation — `SKILL.md` loads wholesale there, the author sees it
running, and every test they think to write passes. It reaches no child, and
nothing reports that. That is the same silent-omission shape as the prose
obligations this feature exists to convert, the cascade steps that report `ok`
having changed nothing, and a missing `schema:` field that produces an absence
of checking rather than a failing check. One level up, the same defect.

**The second is unchanged:** koto templates cannot compose, so sharing between
the two entry points is available as a script or a prose reference and never as
a template fragment.

A third arrived during this design and changes what the cascade's evidence may
be. The cascade script contains six operations that can report `ok` having
changed nothing: two awk rewrites under one unconditional `ok` around
`run-cascade.sh:531-579`, and four `git add ... || true` calls each followed by
an unconditional `ok` *and* an unconditional `STAGED_FILES+=(...)` (`:603-604`,
`:903-919`). Because `git commit` takes no pathspec and the bogus array entry
keeps the commit block running, a failed add produces a finalization commit
missing a document the cascade believes it staged. The post-cascade verification
cannot catch this: it runs `shirabe validate --lifecycle-chain` against a
**path** (`:377-381`, called at `:1093-1100`), so it reads the working tree,
where the document *was* transitioned. Hardening those six sites belongs to the
issue filed for it; what belongs here is not building on their self-report.

## Decision Drivers

- **Dependency direction.** `/execute` depends on `/work-on`; the shared
  machinery must not invert that (PRD R5a).
- **Reachability.** Every new obligation must reach a materialized child, which
  means `work-on.md` and never `SKILL.md` alone (R10).
- **Cadence.** A plan run cascades once per plan (R13).
- **One mechanism, not two.** The root/child discriminator the separately
  landing terminal-record fix establishes is reused rather than re-invented
  (R19b).
- **Invisible when irrelevant.** A run with no anchor emits no cascade-related
  output at all (R3).
- **Evidence over report.** A report of success is not evidence of success.
- **Template-authoring constraints.** `check-template-directives.sh`,
  `check-template-interpolation.sh` and `validate-template-mermaid.sh` bind any
  new state or gate; check 4 in particular requires a gate name shared across
  templates to carry an identical command.
- **Two pull requests, ordered.** Completeness first, migration second (R22).

## Considered Options

Five decisions were decomposed and researched independently, each with its
alternatives weighed in full. The reports are the record of what was considered;
this section states each decision's alternatives and why the chosen one won.

### Decision 1 — where the shared cascade machinery lives

**Chosen: move `run-cascade.sh` and its test under `skills/work-on/scripts/`,
with `/execute` reaching it over a cross-skill path.**

Alternatives weighed: leave it under `/execute` and have `/work-on` call across
(forbidden by R5a — it inverts the dependency direction and fails the PRD's own
acceptance criterion); move it to root-level `scripts/` (the PRD named this the
obvious candidate, and the research disproved it: that directory's runtime
inhabitants are skill-agnostic parameterized tools, and this would be the first
non-generic git-mutating domain script there); duplicate it with a CI drift
check (precedented for a one-line gate expression, not for 1,157 lines); fold
the cascade into a `shirabe` subcommand (a direction the repository suggests,
but out of this PRD's scope and sized for its own design).

The decisive reason is not cost — two options touch nearly the same files — but
that this is the only relocation following a direction the repository has
already chosen twice. `/execute` already reaches `work-on.md` (guarded by
`assert-child-template.sh`) and `plan-to-tasks.sh`; neither dependency runs the
other way. This makes the cascade script the third instance of a shape that
already has tooling, rather than a new category.

### Decision 2 — anchor detection and the no-chain path

**Chosen: search `docs/plans/` for a PLAN whose Implementation Issues table
names this issue, run as a late `command` gate immediately before the
cascade-invoking state, wired through zero-evidence gate-only transitions.**

Alternatives weighed: a caller-supplied plan path (kept as a fast path, but
silent for issues that already exist); a new issue-body `Plan:` field (worth
adding for issues created from here forward, but silent for the population that
surfaced the defect); caching the answer from `context_injection` (pays the cost
on every run including children, and stales).

The gate-only, zero-evidence shape is what satisfies R3's "emits no
cascade-related output": the no-anchor branch produces no agent-facing language
by construction rather than by convention, following `pr_precheck` and
`settled_branch_record`.

The accepted failure direction is the false negative: a PLAN in a shape the
anchored search does not recognise reads as no-anchor and the run completes via
the pass-through rather than cascading. That is the same direction the PRD
already commits to when it rejects synthesizing an anchor to make a control-flow
decision.

### Decision 3 — which obligations become gates, and where they live

**Chosen: a hybrid. Extend in place where an exact precedent exists — merge
cleanliness onto `ci_monitor`, the closing keyword onto `pr_creation` — and add
one narrow new state between `finalization` and `pr_precheck` for the pre-PR
evidence-carried obligations.**

Alternatives weighed, each with what it buys before what it costs:

- **One batching state for everything.** Buys a single place a reader looks for
  every finishing obligation, one new state rather than several, and one mermaid
  entry. Rejected on sequencing: the obligations split cleanly by when they are
  observable. Code cleanup, summary shape, the design diagram and the
  commit-message convention are all decidable *before* `pr_creation` runs; the
  closing keyword and merge cleanliness both need a pull request to exist before
  anything can query one. A single state cannot sit on both sides of
  `pr_creation` in a linear walk without either running twice — which concedes
  that one state cannot hold everything — or deferring the PR-dependent half to
  a second pass that is no longer one state. "One state" therefore degrades in
  practice into a pre-PR batching state plus reuse of the existing post-PR
  states, which is the hybrid actually chosen, reached honestly rather than by
  accident.
- **One state per obligation.** Buys maximal isolation: each obligation's
  failure is its own state, legible in the run record, and a later change to one
  cannot entangle review of another. Rejected because it multiplies states and
  agent turns for checks that are mechanically cheap to co-locate, in a template
  that already declares twenty-eight states.
- **Extending existing states in place throughout.** Buys zero new states and no
  mermaid changes, the smallest diff of the three. Rejected because the pre-PR
  obligations have no natural host: piling five more required fields onto
  `finalization` would entangle them with its existing three-way branch, which
  is load-bearing for the deferral human-gate contract, so a change to the
  design-diagram evidence field would drag review of the human-approval path
  with it.

Two obligations the PRD left optional are gated rather than made advisory:
the design-diagram update and the summary's shape. This is R6 applied rather
than scope added — R6 requires gating whatever resolves to an observable fact,
and the research established that both do. R9's either-or closes on the gating
limb for that reason.

### Decision 4 — one root/child discriminator or two

**Chosen: one discriminator, consulted independently from two places.**

Alternatives weighed: computing it once and caching it into koto context for
both consumers (assumes the two code paths coincide, which they do not, and
leaves the pre-existing terminal ticks without a value to read); two independent
mechanisms (violates R19b's testable definition, and reproduces as a per-site
opt-in exactly the textual-rather-than-runtime defect R19 was written to rule
out).

What settles it is mechanical rather than aesthetic: the two consumption sites
cannot be collapsed because they are different in kind. A terminal state accepts
no evidence, so retention can only be a flag choice made from prose; cascade
suppression must be a branch in the template graph that a child actually
reaches, so it can only be template prose — most naturally a `session_role`
evidence field on `ci_monitor`.

This rests on the described shape of a fix not yet on this branch. If the landed
mechanism differs, the mechanical argument stands and the referent changes; per
R19b that is an escalation, not a licence to invent a parallel one.

### Decision 5 — the multi-pr migration's shape

**Chosen: a third execution path in `/execute` reusing the per-child dispatch
with the shared branch omitted, plus a new end-of-run cascade trigger; a prose
refusal in `/work-on` with no template change; the routing-claim inventory as a
section of this design; and supersession by a decision record plus a dated
`## Amendment` section on each superseded document.**

Alternatives weighed for the two places with real choice. For the inventory: a
new committed file, which buys a single obvious location and a stable path to
cite, but invents an artifact type for something authored once and never
updated; or PR-body text, which buys zero repository footprint and puts the
inventory where reviewers already read, but is not durable — these pull requests
squash-merge and the branch is deleted, so the body is not where a later reader
looking for the routing surface would find it. For the refusal: a koto gate or a new terminal state, both
rejected because no session should exist for a plan that is refused — the
decision happens before one is created, exactly as `/execute`'s mirror-image
refusal does today.

The end-of-run cascade trigger is genuinely new: no cascade exists for multi-pr
today, despite two committed documents stating that one does.

## Decision Outcome

The five decisions compose into one shape, with two constraints folded in that
arrived after the research and belong to the cascade state all five route into.

**The cascade is guarded by two conditions, in one order.** `ci_monitor` decides
role first: a child routes straight to `done`, never reaching the anchor gate
and never paying for the search. A root routes toward the cascade-entry state,
whose gate searches for an anchor and routes past the cascade when there is
none. Reversing the order would search on every child run and discard the answer.

**A completed cascade is evidenced by its observed post-state, not by the
script's report.** Three facts: the anchor absent from disk; each upstream
document at its expected status; and the finalization commit containing each of
those documents, **read from the commit's own paths rather than from the working
tree**. The third is the one that earns the definition — checking the tree there
would inherit the blind spot verified above, where a document transitioned on
disk but missing from the commit satisfies every existing check and is still
absent from the merge.

**One tick can traverse several states, so the obligations here are per-tick
rather than per-state.** This is stated explicitly because an implementer
reading the template state by state will not derive it, and because reasoning
from a state's `accepts:` block gets it wrong.

VERIFIED in koto's source. `koto next` advances in a loop
(`src/engine/advance.rs:592`), chaining onward while the next transition can be
chosen without evidence. A state is an auto-advance candidate when it has no
`accepts`, no integration and no blocking gate, and is not terminal
(`src/cli/next.rs:107-118`). So the unit of reasoning is the chain a single tick
traverses, not the state it nominally routes to.

One guard qualifies that, and this design depends on it. `fresh_evidence` is
set false after each auto-advance, so a state carrying *conditional*
transitions will not fire its unconditional fallback when entered by chaining —
it stops and asks (`advance.rs:571-575`, `:1229-1234`).

**The guard is keyed on having a conditional transition, not on having an
`accepts:` block, and the difference is the whole point.** An earlier draft of
this design said an `accepts:` block was what stopped a tick passing through.
That is wrong, and `execute.md` contains the counter-example: `escalate`
(`:457-466`) declares a *required* `failure_reason` and a single transition to
`done_blocked` with no `when:` clause. Having no conditional transition, its
`has_conditional` is false, the guard does not apply, and a tick chains straight
through it — bypassing the required evidence — which is exactly the behaviour
measured elsewhere in this repository when a bare tick ran
`spawn_and_await` → `escalate` → `done_blocked` in one invocation and destroyed
the record for the batch that had just failed.

**The rule, for anyone adding a state to either template.** An `accepts:` block
does not stop a tick chaining through a state. At least one *conditional*
transition does, because the guard is keyed on `has_conditional`. It has been
stated wrongly in three different forms in one afternoon, so it is recorded here
with both halves of its evidence:

- **By inspection.** `execute.md`'s `escalate` (`:457-466`) has a required
  `failure_reason` and one unconditional transition, and is chained through;
  `plan_completion` (`:439-455`) has evidence *and* three `when:`-conditioned
  edges, and is not.
- **By measurement.** The same state was built twice with a required `reason`
  field in both. With one unconditional transition, a bare tick two states
  upstream returned `done`, landed on the terminal, and destroyed the record.
  With one conditional transition plus an unconditional fallback, the tick
  stopped at the state with `evidence_required` and the record survived.

A related trap for a reader checking the source: `next.rs:107-118` governs what
`koto next` *returns to the agent*, not what the advance loop chains through.
They are different code paths, and citing the first as the chaining rule is how
this was got wrong the first time.

Two consequences for the states this design adds:

- `cascade_run` is protected, but **by its conditional transitions rather than
  by its evidence block**: it routes on `cascade_status`, sending `completed`
  and `skipped` one way and `partial` another, exactly as `plan_completion` does
  at `execute.md:447-455`. That makes `has_conditional` true and stops a chained
  tick. An implementer who collapsed those three edges into one unconditional
  transition — an obvious-looking simplification, since two of them share a
  target — would silently reintroduce the chaining *even while leaving the
  `accepts:` block in place*. That is the specific regression the PLAN's
  chain-level criterion has to catch, and it is not visible in a state-by-state
  reading.
- `cascade_entry` is deliberately zero-evidence and gate-routed, so a tick that
  reaches it **can** continue into `done` on the no-anchor edge within the same
  invocation. That is correct and desirable — it is what keeps the no-anchor
  path silent — but it means the tick that lands on a terminal may be the same
  tick that submitted `ci_monitor`'s evidence. The root-only retention
  obligation is therefore a property of that tick, and cannot be satisfied by
  reasoning about the terminal state in isolation.

The failure this rules out is concrete and has already been observed elsewhere
in this repository: a bare tick chaining through an escalation into a blocked
terminal in one invocation, destroying the context record for the batch that had
just failed. It was initially rejected by reasoning from `accepts:` and measuring
a forced transition instead of a bare tick, and only overturned when someone
applied the fix and watched the suite fail. That is why this design states the
rule rather than assuming it will be re-derived, and why the PLAN carries a
criterion written against a chain rather than a state.

**A `partial` cascade halts and does not reach a success terminal.** This is
PRD R5, and an earlier draft of this design omitted it entirely — a gap its own
Consequences section pointed at by claiming four new states while naming three.

`run-cascade.sh` reports `completed`, `partial` or `skipped`
(`execute.md:439-455`). `/execute` treats `partial` as a halt: it must not mark
the PR ready, and the two shapes differ in what recovery means
(`execute.md:735-740`) — a refused transition *without* `commit` and `push` at
`ok` leaves nothing published, so recovery is local; a refused transition *with*
them published what it reached, so the remote already carries that commit and
recovery is a follow-up commit or a revert rather than a reset.

The single-issue caller handles both shapes identically in **verdict semantics
and recovery guidance**, which is what R5 requires — not identically in routing,
because the two flows differ structurally. `/execute` runs its cascade before
`ci_monitor` and routes all three verdicts there; this design runs the cascade
*after* `ci_monitor`, so there is no later state to absorb a halt. The halt is
therefore an explicit failure **edge** rather than a new state: `cascade_run`
accepts `cascade_status`, routes `completed` and `skipped` to `done`, and routes
`partial` into the pre-existing `done_blocked` terminal carrying the failing
step's detail and the shape-specific recovery guidance quoted above. No new
terminal is introduced — `done_blocked` already exists and already carries a
failure reason.

Routing `partial` to a failure terminal at all is a deliberate divergence from
`/execute`,
which has none and leaves the halt for the agent to observe rather than the
machine to enforce (`execute.md:757`). That is tolerable there because a
following state exists; here it would let a failed cascade reach a success
terminal, which is precisely the class of defect this feature removes. The
divergence is in the routing only, and it is in the direction of more
enforcement rather than less.

**That same evidence makes a retained session safe to re-enter.** Retention
changes resume semantics, and the cascade states are the worst place for it:
unlike the implementation states, they are not re-enterable, because by the time
one has run, documents have moved on disk and a commit may exist. Re-entering a
partially-run cascade is a second walk over a chain whose nodes already moved.
So a resuming run asks not *where did I stop* but *what already happened* — and
answers it from the same three facts, consulted on entry rather than only on
exit, without trusting any record the run wrote about itself. The
finished-versus-resumable signal itself comes from the terminal-record fix; this
design commits to consuming it, not to its shape.

**The six unreliable operations in the cascade script are not hardened here.**
That stays with the issue filed for it, on the same reasoning applied to the
terminal-record defect: a pre-existing, independently testable defect should not
be held behind a large feature pull request. What this design owes in exchange
is that none of its criteria depend on those operations' success meaning
anything, which the evidence definition above satisfies.

## Solution Architecture

### Components

| Component | Change | Pull request |
|---|---|---|
| `skills/work-on/scripts/run-cascade.sh` | Relocated from `skills/execute/scripts/`, with its test | 1 |
| `skills/execute/koto-templates/execute.md` | Invocation path updated to the relocated script | 1 |
| `skills/execute/scripts/assert-child-template.sh` (or a sibling) | Fail-closed existence assertion extended to the relocated cascade script, run before the cascade mutates anything | 1 |
| `skills/work-on/koto-templates/work-on.md` | `session_role` field and branching transition on `ci_monitor`; `merge_state_clean` gate copied verbatim; closing-keyword gate on `pr_creation`; one new pre-PR evidence state; new cascade-entry and cascade states | 1 |
| `skills/work-on/koto-templates/work-on.mermaid.md` | One entry per new state, per check 1 | 1 |
| `skills/work-on/requires.tsv`, `skills/execute/requires.tsv` | Declarations for new tool calls and the relocated path | 1 |
| `skills/work-on/references/phases/` | Obligations moved from prose into the states that now carry them | 1 |
| `skills/execute/SKILL.md`, `execute.md` | Third execution path; end-of-run cascade trigger | 2 |
| `skills/work-on/SKILL.md` | Multi-pr refusal replacing the dispatcher route | 2 |
| Routing surface across five skills, two eval suites | Inverted per the inventory | 2 |
| `docs/decisions/DECISION-*.md`, two `## Amendment` sections | Supersession record and pointers | 2 |

### Data flow through the new states

```
ci_monitor ──(session_role: child)────────────────────────────► done
     │
     └──(session_role: root, ci_outcome: passing)──► cascade_entry
                                                          │
                          ┌───(gate: no anchor found)──────┤
                          │                                │
                          ▼                                ▼
                        done                        cascade_run
                                                          │
                                              (evidence: cascade_status, plus
                                               observed post-state with the
                                               commit read from commit paths)
                                                          │
                    ┌─────────────────────────────────────┼──────────────────┐
                    │                                     │                  │
        (cascade_status: partial)      (completed)   (skipped)                │
                    │                                     │                  │
                    ▼                                     ▼                  ▼
              done_blocked                              done               done
        (failing step's detail +
         shape-specific recovery)
```

`cascade_entry` carries no evidence: both its outgoing edges are gate-decided,
which is what keeps the no-anchor path silent.

### The routing-claim inventory

Per Decision 5 the inventory lives as a section of this design, modelled on the
site table in `DESIGN-multi-pr-plan-decoupling.md`, with columns
`file | line | before | after | disposition` and the R16b command recorded
beside it. It is authored when the second pull request is implemented; this
design establishes its form and location, and the PLAN carries the issue that
fills it.

## Implementation Approach

**Pull request 1 — completeness.** Relocate the cascade script and repoint
`/execute`. Add the `session_role` branch and the two in-place gates. Add the
pre-PR evidence state. Add `cascade_entry` and `cascade_run`. Move the
obligations out of prose into the states that carry them. Update the mermaid
companion and both `requires.tsv` files.

**Pull request 2 — migration.** Add the third execution path and its end-of-run
cascade trigger, which references the script at its relocated path and therefore
depends on the first PR having landed. Invert the routing surface per the
inventory. Update the three eval scenarios. Write the decision record and the
two amendment sections.

The order is load-bearing twice over: the migration rewrites the routing rules
the first body of work is implemented under, and its cascade trigger needs the
relocation.

## Security Considerations

The change surface is shell invoked from koto gates and template-interpolated
values, so the relevant exposures are injection and path traversal rather than
authentication or data handling.

**Interpolated values reaching a shell.** The anchor gate interpolates
`{{ISSUE_NUMBER}}` into a search over `docs/plans/`. The shell-injection surface
here is closed structurally rather than by author care: koto's own variable
pipeline rejects shell metacharacters before a value can reach an interpolation
site at all, so the protection holds regardless of how any given session
behaves.

That is worth stating precisely, because an earlier draft of this section got it
wrong in both directions. It attributed the safety to template-author discipline
and drew an analogy to `/execute` re-validating `execution_mode` — but that
analogy is weaker than it sounds, because `execution_mode` is re-validated by
prose instruction an agent is trusted to follow and can therefore be skipped by
a careless run, where this value's protection is enforced by the runtime.

What anchoring the search pattern actually defends against is **selecting the
wrong PLAN**, not injection: an unanchored match could find an issue number as a
substring of another and cascade the wrong chain. That is a correctness
safeguard with a security-shaped consequence — the cascade mutates documents and
pushes — and **no mechanical check enforces it**.
`check-template-interpolation.sh` does not cover it. So the gate command's
anchoring is a review obligation when it is written, and the PLAN carries it as
one.

**The relocated script's path.** `/execute` reaches the cascade script over a
cross-skill path resolved through `${CLAUDE_PLUGIN_ROOT}`. Decision 1's whole
argument is that this becomes the third instance of an existing cross-skill
pattern — and the other two instances both fail loud and early when the path
does not resolve. This one must too.

**A fail-closed existence assertion on the relocated path SHALL run before the
cascade mutates anything**, either by extending `assert-child-template.sh` to
check both paths or by a sibling check at the same point. Without it the
relocation trades a guard for nothing: a broken `${CLAUDE_PLUGIN_ROOT}`
resolution would surface deep inside a cascade that has already transitioned
documents, rather than before it started. Inheriting the pattern means
inheriting its guard, not just its shape.

**Evidence read from git.** Reading the finalization commit's own paths is a
read-only git operation on the local repository and introduces no new exposure.
It is deliberately not implemented by parsing the cascade script's output, which
would make a value the script controls into a security-relevant input.

**What this change does not touch.** No authentication, no credential handling,
no network surface beyond the `gh` calls the skill already makes, and no change
to what either skill is permitted to write. The write-target set is unchanged.

## Consequences

**Positive.** A single-issue run finishes its own work or stops naming what it
could not discharge. The obligations that decide "finished" become checkable
rather than advisory, and every one of them reaches a child session. The
dependency direction between the two skills stops being ambiguous. Multi-pr
plans gain a cascade for the first time, and two committed documents stop
describing a capability that does not exist.

**Negative.** The cascade script moves, which invalidates path references in
anything not updated with it, and one recorded decision is amended. `work-on.md`
grows **three** states — the pre-PR evidence state, `cascade_entry` and
`cascade_run` — in a template that already declares twenty-eight, plus one new
edge from `cascade_run` into the pre-existing `done_blocked` terminal for a
`partial` cascade. An earlier draft called that edge a fourth state; it is not,
and the miscount is recorded here rather than silently corrected because it is
the second time a stated cardinality in this document disagreed with its own
enumeration. The second
pull request is a breaking change for anyone running a multi-pr plan through the
single-issue entry point today, mitigated by a refusal that names where a plan
is run now but not eliminated. And the design depends on a mechanism not yet on
this branch.

**Mitigations.** The relocation is mechanically checkable and the existing
cross-skill guard pattern extends to it. The new states are contained to one
region of the graph and each has a single job. The breaking change is a prose
refusal reached before any session exists, so it fails fast and legibly rather
than partially. The dependency on the unlanded mechanism is recorded as an
assumption with an escalation rather than assumed away.

**What is deliberately left to other work.** Three things, each named rather
than left implicit:

- The six operations in the cascade script that can report success having
  changed nothing, and the tree-reading post-verify that cannot catch them.
  This design's evidence definition is written so that neither affects whether
  its own criteria hold.
- The undefined handoff at chain exit — a completed plan with no driver
  attached, evidenced by the fourth run described in the problem statement.
  Outside the accepted PRD's scope, and it argues for specifying the handoff
  rather than for anything this design chose. Proposed for its own issue.
- The finished-versus-resumable signal for retained sessions, which the
  terminal-record fix owns. This design commits to consuming it, not to its
  shape.
