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
`children-complete` gate dereferences, so **the child's result never reaches its
parent**: the gate reports `all_complete: true` with `results_in: false`.

What that does to the parent depends on how the parent's transitions read the
gate, and the two cases measured differently:

| parent's converge transition | flagged child |
|---|---|
| waits for the gate to pass — e.g. a single unconditional exit | parent reports `converge_blocked: true` and never advances; the child is no longer tickable, so nothing can clear it |
| keys on `gates.<gate>.all_complete: true`, as `/execute`'s `spawn_and_await` does | parent advances as normal, without that child's result |

So under `/execute` today a flagged child is silent rather than stuck: the batch
proceeds, and the one child's outcome is missing from what the parent received.
A child cannot see which kind of parent it has, and neither outcome is one it
should cause, so retention is **root-only**.

The costs of a wrong answer are asymmetric: a root misread as a child loses one
run's record, which is recoverable; a child misread as a root withholds its
result from its parent, and against a parent that waits on the gate that is a
batch that cannot finish. Code deciding this fails toward `child`.

An earlier version of this section said a flagged child wedges `/execute`
permanently. That was measured against a fixture whose parent had an
unconditional exit, and `/execute`'s transitions differ in exactly that respect.
It is corrected here rather than softened, because the claim had already been
repeated into two skills, a script header and a test.

`skills/work-on/scripts/session-role.sh` is the discriminator. It reads koto's
own `parent_workflow` field rather than the `<parent>.<task>` name shape, which
is unsound in both directions — koto supports non-composed children, and nothing
stops a root being named with a dot.

koto#240 is the platform fix. It should make retention and result-emission
separable, at which point the exception can go; a skill relying on the exception
should carry a tripwire that fails when it is no longer needed rather than
leaving it as folklore.

## A leg-attached root reports by promotion

The exception above is about `--parent` children. A **root** session attached
to a koto request leg (a child run with `--koto-leg=<request-id>:<leg>`; see
Parent-of-the-Parent Binding in
[`parent-skill-pattern.md`](parent-skill-pattern.md)) doesn't face that choice.
koto's request store keeps retention and the result apart for it: at the
terminal tick koto promotes the session's declared `result:` map to the leg,
**even under `--no-cleanup`**, and the session keeps its record. So a
leg-attached root passes `--no-cleanup` on every tick like any other root, and
its driver still receives its result. Retention stays root-only; attaching to a
leg doesn't make a session a child.

## What retention does not buy

A retained session keeps its name, so a skill whose re-entry initializes a
well-known session name has to deal with the finished session it retained, or
its own resume path is blocked by it. Retention buys a record that can be read
after the fact, not a session a later run resumes in place.

The recovery is **`koto init --replace-terminal`**. It replaces a session only
when that session is terminal, hands back the old run's result so the skill may
print it, and starts a fresh session under the same name in one step. A live
session is never replaced: paired with `--attach-live`, the same `koto init`
joins it instead when its template, origin, and non-rebind variables match,
and refuses otherwise. The skill therefore needs no separate probe to tell a
live session from a finished one, and no read-then-`koto session cleanup`
sequence that a crash between the two steps could leave half done. shirabe's
koto-backed skills pass these flags through the shared `scripts/koto-open.sh`.

Don't discover a finished session by ticking it. A tick on a terminal session
answers `action: "done"`, which an execution loop reports as the run's outcome,
claiming work it didn't do. `koto workflows` lists a retained terminal session
with nothing marking it terminal, so finding a session isn't evidence that it's
resumable either; `is_terminal` from `koto status` remains the read-only way to
ask when a skill needs to know outside its entry path.

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
| `/execute` | Every tick, unconditionally. An orchestrator session is always a root, including under `--koto-leg`, where its result reaches the leg by promotion. |
| `/scope` | Every tick, unconditionally. Its session is always a root, including under `--koto-leg`, where its result reaches the leg by promotion. This replaces the selective per-state form it stated before the findings above. |
| `/deliver` | Every tick, unconditionally. Its session is a root and a request coordinator; its children report through their legs, not through its session. |
