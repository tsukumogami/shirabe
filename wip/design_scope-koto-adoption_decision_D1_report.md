# Decision D1: Template state graph

Everything here was compiled and run against koto 0.11.6. The skeleton is at
`wip/design_scope-koto-adoption_D1_skeleton.md` and the mechanical trap scan at
`wip/design_scope-koto-adoption_D1_trapscan.py`. Both are wip artifacts and must
not be cited from the committed DESIGN; the DESIGN carries the graph itself.

## Options Considered

Four granularities were built out far enough to test. Two were killed by R2, one
by AC3 plus a reachability hole, and the fourth is what ships.

**Phase-grained, 6-7 states.** One state per `/scope` phase, with Phase 2 as a
single hop state that self-loops four times. Cheapest thing that could work, and
it fails the requirement this whole PRD exists for. The fold judgment gets no
state of its own, so the only place its instruction can live is the Phase-2
state's `<!-- details -->` — and details are delivered on **first entry**, which
under a self-loop means the first lap, which is before `/brief` has run. The
general-form reduction argument would arrive at hop zero holding nothing: the
#331 reproduction, rebuilt in the substrate that was supposed to prevent it. It
also collapses R22 and R23: one hop state carries one gate, so four hops produce
one gate line and a walked hop is not distinguishable from a walked-past one.
Fatal twice over.

**Hop-grained without a fold state, 13 states.** Each hop is one state carrying
both its child dispatch and the fold judgment for the edge it completes. Kills
the details problem — each hop state is entered once, so its details land once.
But it puts the fold instruction on the wrong side of the dispatch. At `hop_prd`
entry the agent holds the BRIEF and nothing else, so R2's "scoped to the two
documents then in hand" is false at the first edge. And the last edge
(design→plan) is completed by `/plan` landing, after which no hop state remains,
so that judgment migrates into `finalize` and the reduction argument ends up
mixed into the exit declaration. Rejected.

**Sub-hop-grained with three fold states, ~23 states.** `fold_prd`,
`fold_design`, `fold_plan`, linear, no routing problem at all. Two objections.
AC3 says the pinned sentence occurs "exactly once in the compiled template, under
the fold state's details" and that the four per-type summaries "occur only under
the fold state" — singular, and with three fold states there is no such state.
Worse, putting the argument in `fold_prd` alone opens a reachability hole: when
`/prd` is held back by re-entry protection the run's first fold judgment is
`fold_design`, and the argument was never delivered at all. Putting it in all
three violates "exactly once." Rejected.

**Sub-hop-grained with one shared fold state, 21 states — chosen.** Four hop
states, one `fold` state entered from `hop_prd`, `hop_design` and `hop_plan`, and
routed onward by two `command` gates over the artifact tree. The argument lives
in one place, is delivered at every fold judgment (verified below — details are
re-delivered on re-entry, only self-loops suppress them), and reaches whichever
fold the run enters first regardless of which hops were held back.

One variant of the chosen shape was rejected inside it: routing `fold` on an
agent-submitted `next_hop` enum instead of on gates. It is simpler to write and
it hands the chain order to the agent, on top of `expects.options` already
handing over the routing table. Artifact-presence gates keep the order in the
substrate and align with R8's "decided from the artifact tree."

A second detail inside the chosen shape is load-bearing and was found by breaking
it: `fold` must route on the **highest artifact present**, not the lowest artifact
absent. Routing on "DESIGN absent → go to `hop_design`" livelocks a run that
skipped `/design` and then landed `/plan` — fold sends it back to `hop_design`
forever. Routing on "PLAN present → finalize; else DESIGN present → `hop_plan`;
else → `hop_design`" terminates under every skip pattern, which is what R9
requires.

## Chosen Graph

21 states, 4 terminal. Phase column is the declared map R11 reads (see Phase
Recovery). `outcome` is the per-hop evidence enum; `verdict` is the fold's.

| State | Terminal | Accepts | Gates | Transitions (guard) | Phase |
|---|---|---|---|---|---|
| `setup` | no | `setup_result: enum[ready, blocked]` | — | `discovery` (ready); `bail` (blocked) | 0 |
| `discovery` | no | `discovery_result: enum[proposed, blocked]` | — | `chain_proposal` (proposed); `bail` (blocked) | 1 |
| `chain_proposal` | no | `author_decision: enum[proceed, adjust, bail]` | — | `hop_brief` (proceed); `discovery` (adjust); `bail` (bail) | 1 |
| `hop_brief` | no | `outcome: enum[landed, skipped, bail]` | `brief_complete` (command, artifact tree) | `hop_prd` (`brief_complete.exit_code: 0` + landed); `hop_prd` (`exit_code: 1` + landed); `hop_prd` (skipped); `bail` (bail) | 2 |
| `hop_prd` | no | `outcome` | `prd_complete` | `fold` (`exit_code: 0` + landed); `fold` (`exit_code: 1` + landed); `hop_design` (skipped); `bail` (bail) | 2 |
| `hop_design` | no | `outcome` | `design_complete` | `fold` (`exit_code: 0` + landed); `fold` (`exit_code: 1` + landed); `hop_plan` (skipped); `bail` (bail) | 2 |
| `hop_plan` | no | `outcome` | `plan_complete` | `fold` (`exit_code: 0` + landed); `fold` (`exit_code: 1` + landed); `finalize` (skipped); `bail` (bail) | 2 |
| `fold` | no | `verdict: enum[keep, absorb]` | `plan_present`, `design_present` (command) | `finalize` (`plan_present: 0` + keep/absorb); `hop_plan` (`plan_present: 1`, `design_present: 0` + keep/absorb); `hop_design` (`plan_present: 1`, `design_present: 1` + keep/absorb) | 2 |
| `finalize` | no | `exit: enum[full-run, re-evaluation, abandonment-forced]` | — | `exit_full_run`; `exit_re_evaluation`; `exit_abandonment` (on `exit`) | 3 |
| `exit_full_run` | no | `exit_artifacts: string` (req), `plan_execution_mode: enum[single-pr, multi-pr, coordinated]` (req) | `chain_complete` (command, R7 check) | `cleanup_full_run` (`exit_code: 0` + `evidence.exit_artifacts: present`); `full_run_blocked` (`exit_code: 1` + present) | 3 |
| `full_run_blocked` | no | `next_move: enum[recheck, abandon]` | `chain_complete` (same gate, re-declared) | `cleanup_full_run` (`exit_code: 0` + recheck); `full_run_blocked` (`exit_code: 1` + recheck); `exit_abandonment` (abandon) | 3 |
| `exit_re_evaluation` | no | `boundary: enum[prd, design]`, `decision_record_sub_shape: enum[re-evaluation, rejection]`, `exit_artifacts: string` — all req | `decision_record_present` (command) | `cleanup_re_evaluation` (`exit_code: 0` + present); `exit_re_evaluation` (`exit_code: 1` + present) | 3 |
| `exit_abandonment` | no | `triggering_child: enum[brief, prd, design, plan]`, `exit_artifacts: string` — both req | `forced_artifact_present` (command) | `cleanup_abandonment` (`exit_code: 0` + present); `exit_abandonment` (`exit_code: 1` + present) | 3 |
| `bail` | no | `bail_ack: enum[confirmed]` | `child_intermediate_present` (command over `wip/{brief,prd,design,plan}_<topic>_*` and `wip/research/*`) | `exit_abandonment` (`exit_code: 0` + confirmed); `done_cancelled` (`exit_code: 1` + confirmed) | 3 |
| `cleanup_full_run` | no | `cleanup_result: enum[done]` | — | `done_full_run` (done) | 4 |
| `cleanup_re_evaluation` | no | `cleanup_result` | — | `done_re_evaluation` (done) | 4 |
| `cleanup_abandonment` | no | `cleanup_result` | — | `done_abandonment` (done) | 4 |
| `done_full_run` | **yes** | — | — | — | 4 |
| `done_re_evaluation` | **yes** | — | — | — | 4 |
| `done_abandonment` | **yes** | — | — | — | 4 |
| `done_cancelled` | **yes** | — | — | — | 4 |

Five structural rules hold across the whole table, and each of them exists
because something breaks without it.

**Every non-terminal state carries at least one `when`-guarded transition keyed
on an agent evidence field.** This is R5 and AC7 in mechanical form, and it is
the only defence against the pass-through trap. Stated in the template's own
`description:` so a reviewer reads it before the states, the way `/work-on`'s
line 11 states its self-loop rule.

**Every gate is co-routed with an evidence field.** A `when` clause referencing
only `gates.*` resolves without the agent, which delivers no directive — the same
trap arriving by a different door. So `hop_prd`'s forward transitions read
`{gates.prd_complete.exit_code: 0, outcome: landed}` rather than the gate alone.

**Each hop's gate reads the artifact tree and nothing else** — that hop's own
artifact at its canonical path, or the surviving document's `absorbed:` record.
No gate command in this graph contains the string `wip/scope_`, so R26's static
check has nothing to catch and AC12 holds by construction. `bail`'s gate does read
`wip/`, but the child-intermediate prefixes, never the parent's own.

**Each exit path's required fields live on that path's own state.** `finalize`
accepts only `exit:`. This is what makes R6's second clause free: submitting
`boundary:` at `exit_full_run` is an unknown field there, and koto refuses it at
submission before any disk write.

**Cleanup is a pre-terminal state, not a terminal one.** A terminal state's
directive never crosses the wire, so Phase 4 has to be instructed somewhere the
agent still ticks. Three cleanup states rather than one shared state, because one
shared state would have to be told which exit path it is cleaning up after, and
the agent already declared that at `finalize` — re-asking hands back a routing
decision the machine is holding.

The `done_cancelled` path is the exception: `bail`'s directive carries the clean
cancel instruction (remove `wip/scope_<topic>_state.md`, record no `exit:`)
because a cancel has no artifacts to clean up after and a fourth cleanup state
would exist to run one `rm`.

## Phase Recovery

The graph is finer than the phases: 21 states over 5 phases, unevenly (Phase 2
holds five states, Phase 0 holds one). R11 needs `phase_pointer:` to name the
`/scope` phase, so something must project state onto phase.

**A declared map, not a naming convention.** The map is the Phase column above,
carried as a table in `skills/scope/references/state-phase-map.md` and read by
Phase 0 and by every write instruction that touches `phase_pointer:`. The PRD
already anticipates this shape — "the DESIGN can resolve with a declared map
rather than a reconciliation procedure — the two values live in different
domains, so equality was never the right rule."

A naming convention was the obvious alternative: prefix every state with its
phase (`p2_hop_prd`). Rejected because it prices the convention into every state
name, which then leaks into the mermaid preview, into R25's test assertions, into
`koto next --to` invocations in the resume ladder, and into anything a future
maintainer greps for. Renaming a state to move it between phases would then be a
rename across all of those. The map is one file and one row per state.

**What it costs.** A second artifact that must move with the template, and a
failure mode where a state added without a map row leaves `phase_pointer:`
underivable. That is cheap to close: R26's static check already walks every state
in `skills/*/koto-templates/*.md`, so it can assert in the same pass that every
`/scope` state has exactly one map row. The check is the mitigation, not
discipline.

The projection is one-way. koto's state is authoritative while a session is live
and `phase_pointer:` is derived from it; with no session, R11's second clause
takes over and `/scope` writes the phase from its own position. The two values
never need to be reconciled because neither is ever computed from the other in
both directions.

## Where the Fold Judgment Lives

**State: `fold`. Content: its `<!-- details -->`.** The general-form reduction
argument (Appendix A's P1) and the four per-type summaries (P6) both sit after
the marker. Nothing before `hop_brief` carries either, which is R2.

The directive — the part always returned — carries the scoped question and
nothing that generalizes: *you are holding the artifact this hop handed the child
as its invocation argument and the artifact that just landed; does the upstream do
work the downstream does not?* It cannot name the two documents literally,
because the pair differs per visit and a directive is static text, but naming them
by their role in the edge is scoped by construction and is how
`phase-2-chain-orchestration.md` already phrases it.

**The first-visit concern does not apply here, and this was tested.** koto
suppresses details on a **self-loop** but re-delivers them on **re-entry from
another state**. `fold` is only ever entered from `hop_prd`, `hop_design` or
`hop_plan` — never from itself — so all three fold judgments receive the argument
and the four summaries. Probe (`loopdet.md`, states `a` self-looping and `b`
returning to `a`):

```
=== submit: -                first entry to a    details: STATE-A-DETAILS-MARKER
=== submit: {"go":"loop"}    self-loop a->a      details: NONE
=== submit: {"go":"loop"}    self-loop a->a      details: NONE
=== submit: {"go":"out"}     to b                details: NONE
=== submit: {"go2":"back"}   re-entry b->a       details: STATE-A-DETAILS-MARKER
```

Confirmed on the real graph too: `fold`'s details were delivered on visits one
and two of the walked session, entered from `hop_prd` and then from `hop_design`.

This is why the shared fold state beats three fold states on the merits and not
only on AC3's wording. One authored copy, delivered every time it is needed, and
a maintainer editing the fold instruction edits one place — which is R3's
maintainer journey.

Two consequences worth writing into the DESIGN. First, AC3's "exactly once in the
compiled template" is a claim about the template text, not about delivery count;
the argument is delivered up to three times per run and that is correct, because
what R2 forbids is the *general form existing in the pre-hop set*, not its
repetition at the judgment. Second, a run's transcript will hold the argument
from the first fold onward, which the exploration already established is
unavoidable — the property being bought is that the most an agent can restate at
the end is a claim it received while holding two documents.

## Attachment Points for D2-D6

Named, not decided.

**D2 — hop completion construct.** Attaches to the four `<hop>_complete` gates,
to the `outcome` enum on the four hop states, and to `chain_complete` on
`exit_full_run` and `full_run_blocked`. Three things are open. (a) The gate
command's contract: what "artifact present or recorded fold" means as a shell
predicate, and whether the same script serves both the per-hop and the chain-wide
check. (b) Whether a hop whose gate failed should *block* rather than advance —
this graph routes `{exit_code: 1, outcome: landed}` forward to `fold` with the
failure recorded, on the reasoning that R7 refuses at the exit and a per-hop block
needs four extra retry states plus a way to route back to the right hop. D2 may
overturn that; the graph accommodates it by retargeting one transition per hop.
(c) Whether `outcome` needs a fourth value for Phase-N in-chain reject, which
today routes through `bail`.

**D3 — three exit-path states.** Attaches to `finalize`, `exit_full_run`,
`full_run_blocked`, `exit_re_evaluation`, `exit_abandonment`, `bail`, the three
`cleanup_*` states and the four terminals — eleven of the graph's twenty-one
states. Open: whether the re-evaluation and abandonment paths need their own
blocked states (this graph gives them evidence-guarded self-loops instead, which
is legal but reports the failure less loudly than `full_run_blocked` does), and
whether `done_cancelled` earns a cleanup state.

**D4 — session lifecycle and reattach.** Attaches at `setup` (R13's probe before
`koto init`, R14's record of the session it opened, R16's prohibition) and at the
terminal region (R15's `exit:` field surviving the session, and the `--no-cleanup`
question). The graph constrains D4 in one way: the session is disposed of at the
terminal tick, and `cleanup_*` is the last state that ticks, so anything D4 wants
read out of the session must be read at `cleanup_*` or earlier.

**D5 — Appendix A passage placement.** P1 and P6 attach to `fold`'s details, and
this decision fixes both — they have nowhere else to go under R2. P5's hop-output
term attaches to a named `SKILL.md` section plus `hop_brief`'s details. P2's
mechanism content attaches to `fold`'s details or stays in
`phase-2-chain-orchestration.md`, which is D5's call. P3, P4, D1 and D2 are
`SKILL.md` prose and touch no state.

**D6 — tests.** AC7 and R26's static check attach to every non-terminal state and
to the five structural rules above. AC8 attaches to `exit_full_run` →
`full_run_blocked` and to that state's self-loop. AC9 and AC10 attach to
`exit_full_run` → `cleanup_full_run` → `done_full_run`. AC11 attaches to
`exit_full_run`'s and `exit_re_evaluation`'s `accepts` blocks. AC13 attaches to
the four `skipped` transitions and `hop_plan` → `finalize`. AC27 and AC28 attach
to the per-hop gates on the four hop states. AC31 attaches to `setup`'s directive
and `fold`'s details.

## Compile Verification

Command and output, verbatim, from
`/home/dgazineu/.claude/jobs/053ac5cc/tmp` against koto 0.11.6:

```
$ koto template compile scope.md
/home/dgazineu/.cache/koto/2f5e18951272f386ffafd207cb66cab6a0128b805756fef6ab2121ac27e0d09c.json
exit status: 0
```

Compiled clean on the first attempt — no fixes were needed and no re-run was
required. stdout and stderr captured separately to confirm AC1's second half:

```
$ koto template compile scope.md >out.txt 2>err.txt; echo "exit=$?"
exit=0
--stdout--
/home/dgazineu/.cache/koto/2f5e18951272f386ffafd207cb66cab6a0128b805756fef6ab2121ac27e0d09c.json
--stderr--
--warnings--
err.txt:0
out.txt:0
```

Zero `warning: W` lines, which AC1 requires. Notably no W6: the two
`evidence.exit_artifacts: present` clauses use the `evidence.` prefix, which is
the only namespace the `present` matcher is valid under.

The mermaid preview exports too, which CI validates for every shipped template:

```
$ koto template export scope.md --format mermaid --output scope.mermaid.md
scope.mermaid.md
exit=0
```

**The graph was also run, not only compiled.** Three sessions in an isolated
store (`KOTO_SESSIONS_BASE`), driving real `koto next` ticks:

- *Full walk to `done_full_run`.* Every state delivered its directive as
  `evidence_required` with `advanced: false` on entry. `fold` was entered three
  times and its details were delivered each time. `hop_plan` ↔ `fold` lapped three
  times with the PLAN absent and never tripped cycle detection.
- *AC8 in the loop.* A `full-run` claim with `chain_complete` exiting 1 landed on
  `full_run_blocked`, a non-terminal state. Three consecutive
  `{"next_move":"recheck"}` submissions each returned `state=full_run_blocked` —
  the self-loop held. Flipping the gate to exit 0 then advanced to
  `cleanup_full_run` and on to `done_full_run`. That is AC8 and AC9 on one path.
- *AC11, both clauses.* Submitting `{"exit_artifacts":"x"}` at `exit_full_run`
  returned `{"error":{"code":"invalid_submission","details":[{"field":"plan_execution_mode","reason":"required field missing"}]}}`, exit 2. Adding `"boundary":"prd"` returned
  `{"error":{"code":"invalid_submission","details":[{"field":"boundary","reason":"unknown field \"boundary\""}]}}`, exit 2. Neither changed state.
- *AC13.* A run submitting `{"outcome":"skipped"}` at all four hops reached
  `finalize` without ever entering `fold`, then was refused at `exit_full_run` and
  routed to `exit_abandonment` on `{"next_move":"abandon"}`.
- *R22's contrast, in the event log.* The walked session's log carried 13
  `gate_evaluated` events and zero `directed_transition`. A session driven with
  `koto next --to` along the same edges carried 4 `directed_transition` and zero
  `gate_evaluated`, and each `--to` response returned `blocking_conditions: []` —
  no gate outcome beside the hop. A bypassed hop and a walked hop are
  distinguishable per hop, which is what the per-hop granularity buys.

**One correction to the PRD's recorded observation.** The PRD's "one correction
to carry into R25's test" says a refused exit claim routes to a blocked state
"whose own `blocking_conditions` is empty" and that the test must key on the
landing state and its directive. That holds when the gate lives only on the state
being left. This graph re-declares `chain_complete` **on `full_run_blocked`
itself**, and the landing response then carries it:

```
state=full_run_blocked  action=evidence_required  advanced=True
blocking=[{"agent_actionable": true, "category": "corrective",
           "name": "chain_complete", "output": {"error": "", "exit_code": 1},
           "status": "failed", "type": "command"}]
```

That matters for AC8's "a non-terminal state whose directive names those hops."
The blocked state's own gate re-runs on every tick, so the script's report of
which hops carry neither an artifact nor a recorded fold reaches the agent at the
state that is holding it, rather than only at the state it left. D6 should key
R25's assertion on the landing state's `blocking_conditions[].name` as well as its
directive.

## Trap Check

**Trap 1 — silent pass-through** (`koto:src/engine/advance.rs:757-758`). No state
in the graph hits it. Every non-terminal state carries at least one
`when`-guarded transition keyed on an agent evidence field, which makes
`has_conditional` true and `fresh_evidence` false on entry, so the engine stops
and delivers. Verified mechanically over the compiled JSON:

```
$ python3 scan.py <compiled>.json
states: 21 (4 terminal: done_abandonment, done_cancelled, done_full_run, done_re_evaluation)
trap 1 (pass-through, no evidence-guarded transition): none
trap 2 (gate-only self-loop):                          none
trap 3 (context_assignments):                          none
```

And verified by reproducing the trap deliberately, so the check is known to
discriminate rather than merely to pass. A three-state probe where state `b` has
`accepts` with a required field and one unconditional transition compiled clean
with zero warnings, and then:

```
$ koto next trap-t1 --with-data '{"go":"yes"}'
{"action":"evidence_required","advanced":true,...,"directive":"State C directive.",...,"state":"c",...}
```

State `b`'s directive never crossed the wire. This is the defect and it is
invisible at compile time — which is exactly why R26 wants a static check and why
the rule is written into the template's `description:`.

**Trap 2 — gate-driven self-loop.** The graph has three self-loops
(`full_run_blocked`, `exit_re_evaluation`, `exit_abandonment`) and every one is
co-guarded by an agent evidence field, so each lap costs a submission and the
engine never chains laps inside one `koto next`. `full_run_blocked` was lapped
three times consecutively with its gate failing and returned normally each time —
no `cycle detected`, no exit 3. The `hop_plan` ↔ `fold` cycle is a two-state cycle,
not a self-loop, and both states require evidence; it lapped three times cleanly.
No state in the graph carries a self-loop guarded by gate output alone.

**Trap 3 — `context_assignments:`** (tsukumogami/koto#204). Absent from the
graph. The scan asserts it, and the shipped template should keep that assertion
so the 28 existing uses across `/work-on` and `/execute` are not copied forward.

**A fourth hazard worth recording, since it bit the test rig.** The rich event
log is deleted on the terminal tick by default. The session that reached
`done_full_run` had its `.state.jsonl` removed, while the two non-terminal
sessions kept theirs. Any D4 or D6 decision that reads the log after a run needs
`--no-cleanup`, and the exploration already established that flag forfeits the
terminal index entry. This is not D1's to resolve, but the graph's terminal
region is where it lands.

## Consequences

**Positive.** The general form of the reduction argument has exactly one home in
the template and that home is `fold`'s details, so nothing an agent receives
before `hop_brief` contains it — R2 is a property of the graph rather than a
property of prose discipline. R6 costs no shirabe code: partitioning each exit
path's fields onto its own state makes koto's own submission validator enforce
both clauses, verified with exit code 2 and no state change. The per-hop
granularity is what makes R22 mechanical — 13 gate evaluations in a walked run
against zero in a bypassed one — and a phase-grained graph could not have produced
that contrast. AC13 falls out rather than being engineered: an all-skipped run has
no artifacts, so `chain_complete` fails, so the full-run terminal is unreachable
without a directed transition.

**Negative, with what to do about each.**

*Twenty-one states is a large artifact.* Comparable to `/work-on`'s 25 and larger
than `/execute`'s 13, and the exploration's sharpest warning was that this
adoption's real risk is an authoring error rather than a motivated agent.
Mitigation: R26's static check plus the trap scan, both of which run over the
compiled JSON rather than the source, and the five structural rules stated in the
template's `description:` where a reviewer meets them first.

*A hop whose gate fails still advances.* An agent that submits `landed` with
nothing on disk moves to `fold` with a recorded failure rather than being stopped.
The refusal is at the exit only. This is deliberate — R7 puts it there and a
per-hop block costs four retry states and a routing problem — but it means the
graph is more legible than it is preventive at the hop level, and the DESIGN
should say so rather than let a reader infer otherwise. D2 owns whether to change
it.

*`fold`'s position routing is coupled to two canonical paths.* `plan_present` and
`design_present` test `docs/plans/PLAN-<topic>.md` and
`docs/designs/current/DESIGN-<topic>.md`. A topic whose artifacts land elsewhere
routes wrong, and the failure is a mis-route rather than an error. Mitigation:
the same two paths are already the closed write-target set `SKILL.md` states, and
R25's deterministic test drives both gates.

*The state-to-phase map is a second artifact.* It must move with the template or
`phase_pointer:` drifts. Mitigation: fold the map's completeness into R26's check,
which is already walking every state.

*Three cleanup states are near-duplicates.* Three states differing only in their
terminal target, existing because a terminal's directive never crosses the wire.
Accepted: the alternative re-asks the agent which exit it declared, which hands
back a routing decision the machine is holding, and that is the class of thing
this work exists to stop doing.

## Summary

`/scope`'s five phases map onto 21 states — one for setup, two for discovery and
the chain proposal, four hop states plus one shared `fold` state, six for the exit
region including a blocked state, and three cleanup states ahead of four
terminals — with phase recovered through a declared map rather than a naming
convention, and R26's static check extended to assert every state has a map row.
The general-form reduction argument and the four per-type summaries live in
`fold`'s `<!-- details -->`, and because koto re-delivers details on re-entry (and
suppresses them only on self-loops, both verified) the single shared fold state
delivers them at every fold judgment while occurring exactly once in the template.
The skeleton compiled clean on the first attempt with zero `warning: W` lines and
was then run to `done_full_run`, reproducing AC8's refusal-and-block, AC9's
terminal, AC11's two submission refusals, AC13's all-skipped routing to
abandonment, and R22's 13-gate-evaluations-versus-zero contrast against a
`--to`-driven bypass. No state hits either engine trap — every non-terminal state
is guarded by an agent evidence field and every self-loop is co-guarded by one —
and one correction to the PRD falls out of the work: re-declaring the R7 gate on
the blocked state makes its own `blocking_conditions` name the failing check,
which R25's test should key on alongside the directive.
