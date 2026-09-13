# koto session retention: keeping a run's record past its terminal tick

The normative rule for `koto next --no-cleanup` across shirabe's koto-driven
skills, and the koto behaviour it rests on. Normative prose like
[`tool-declaration-policy.md`](tool-declaration-policy.md) and
[`wip-hygiene.md`](wip-hygiene.md): no skill loads this file at runtime, and it
is reviewed as part of a PR. A skill states which side of the rule it is on, in
one or two sentences with the reason its own reader needs at the call site, and
cites here for the argument. What a skill should not do is re-derive the
mechanism: that is what drifts.

The rule lives here rather than in a skill because what it describes is a
property of koto's session disposal, not of any one skill. Three skills drive
koto today and a fourth will; an argument copied into each drifts, and this
branch demonstrated the drift before the copies were consolidated.

## What koto does

koto disposes of a session on the tick that reaches a terminal state, and the
disposal takes the session's `ctx/` with it. Every context key the run
accumulated goes at once — for `/work-on` that is `plan.md` and seven others,
including the running record that carries a CORRECTION block per review round.

`koto next --no-cleanup` suppresses the disposal. It is documented on `koto
next` as a debugging convenience, which is why a skill author has to notice that
it is load-bearing for them.

## The rule

**A skill whose record should outlive its run passes `--no-cleanup` on every
`koto next` it issues, not on the tick it believes will terminate.**

The flag is inert on any tick that does not reach a terminal, so a blanket rule
costs nothing. A selective rule has to be correct on every tick, and it is
wrong in both of the ways below — each of which was shipped and then measured
during shirabe#360.

### Why "the tick that reaches the terminal" is not knowable in advance

`expects.options` lists only transitions that carry a `when`. An unconditional
transition's target is never shown, `options` is omitted altogether when a
state's transitions are all unconditional, and even a listed target is a bare
state name with nothing marking it terminal. An agent inspecting the response
cannot tell whether the evidence it is about to submit ends the run.

### Why a tick can end somewhere other than the state it routes to

**A tick does not stop at the state it routes to.** koto keeps auto-advancing,
and a state halts the chain only if it declares **at least one conditional
transition**. A state whose transitions are all unconditional fires straight
through. Declaring `accepts` halts nothing — a state can require evidence and
still be chained past without the agent ever seeing its directive.

Measured on two templates identical but for the middle state's transitions,
each ticked once from two states upstream:

| middle state | result |
|---|---|
| `accepts: {reason, required}`, transitions `[-> dead_end]` | `action: "done"`, landed on the terminal, context destroyed |
| `accepts: {reason, required}`, transitions `[-> other when …, -> dead_end]` | `action: "evidence_required"`, stopped at `middle`, context intact |

koto's own comment says the same at `engine/advance.rs` (search
`fresh_evidence`): fresh evidence is re-granted to a state with no conditional
transitions, so its unconditional fallback fires within the same invocation.

## The exception: a koto child must not pass it

On a session materialized as a koto child, `--no-cleanup` also suppresses the
`request_store.result` event on the child's own log and the `ChildCompleted`
event on the parent's. Those are the only two sources a parent's
`children-complete` gate dereferences, so the parent reports
`converge_blocked: true` permanently, with no event left to emit and the child
no longer tickable. The batch cannot be finished without manual intervention.

So retention is **root-only**, and the cost of each mistake is asymmetric: a
root misread as a child loses one run's record, which is recoverable; a child
misread as a root wedges a batch, which is not. Code deciding this fails toward
`child`.

`skills/work-on/scripts/session-role.sh` is the discriminator. It reads koto's
own `parent_workflow` field rather than the `<parent>.<task>` name shape, which
is unsound in both directions — koto supports non-composed children, and nothing
stops a root being named with a dot.

koto#240 is the platform fix. It should make retention and result-emission
separable, at which point the exception can go; a skill relying on the exception
should carry a tripwire that fails when it is no longer needed rather than
leaving it as folklore.

## What retention does not buy

A retained session keeps its name, and `koto init` refuses a name already in
use. A skill whose re-entry initializes a well-known session name must therefore
recognise a retained finished session before initializing, or its own resume
path is blocked by the session it retained.

Read `is_terminal` from `koto status` to detect this. It reports without
advancing anything, where discovering the same fact by ticking both answers
`action: "done"` — which an execution loop will report as the run's outcome,
claiming work it did not do — and disposes of the session on the way, destroying
the record. `koto workflows` lists a retained terminal session with nothing
marking it terminal, so finding a session is not evidence that it is resumable.

The recovery is to read the record and then `koto session cleanup` it. Retention
buys a record that can be read after the fact, not a session a later run resumes
in place.

## Where a skill states its position

In the skill's own `SKILL.md`, next to the loop that issues the ticks, in the
operative form only: which ticks carry the flag, whether the decision is
conditional, and a citation here. A koto template that must NOT carry the flag —
because it is also a child template — says so in a YAML frontmatter comment,
which koto never renders into a state directive and a child therefore cannot
read as instruction.

## Adopters

| Skill | Position |
|---|---|
| `/work-on` | Root runs pass it on every tick; children pass it nowhere. Decided per run by `session-role.sh`, because `work-on.md` is also `/execute`'s child template. |
| `/execute` | Every tick, unconditionally. An orchestrator session is always a root. |
| `/scope` | States the selective per-state form, predating the findings above, and is **not reconciled**. Measured: `scope.md` declares no state whose transitions are all unconditional, so nothing there chains into a terminal and its selective rule is reachable in practice — inconsistent rather than unsafe. One future state with a single unconditional exit would make it unsafe, with nothing to catch that. Aligning it is tracked separately. |
