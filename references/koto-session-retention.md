# koto session retention: keeping a run's record past its terminal tick

The normative rule for `koto next --no-cleanup` across shirabe's koto-driven
skills, and the koto behaviour it rests on. Normative prose like
[`tool-declaration-policy.md`](tool-declaration-policy.md) and
[`wip-hygiene.md`](wip-hygiene.md): no skill loads this file at runtime, and it
is reviewed as part of a PR. A skill states the rule where its loop ticks, in
one or two sentences with the reason its own reader needs at the call site, and
cites here for the argument. What a skill should not do is re-derive the
mechanism: that is what drifts.

The rule lives here rather than in a skill because what it describes is a
property of koto's session disposal, not of any one skill. Five skills drive
koto; an argument copied into each drifts, and shirabe#360 demonstrated the
drift before the copies were consolidated.

It describes koto 0.14.0 and later. shirabe's koto minimum is 0.22.0
(`scripts/assert-koto-floor.sh`). Two parts of it arrived in koto 0.23.0, the
hierarchy case at the terminal tick and the move aside under
`--replace-terminal`, and a host still on koto 0.22.x has neither; each is
marked where it appears.

## What koto does

koto decides at the tick that reaches a terminal state whether to keep the
session. A session it does not keep is disposed of, and every context key the
run accumulated goes with it at once —
for `/work-on` that is `plan.md`, `summary.md` and the panels' verdicts among
others.

A session is kept when any of these holds:

- the terminal is declared `failure: true` (`done_blocked`, for example), with
  or without `--no-cleanup`;
- a hierarchy still holds the session, with or without `--no-cleanup`: it has a
  live dispatcher or parent, a `chain/parent` link, or another session names
  it (koto 0.23.0 and later; on 0.22.x this case doesn't exist, and such a
  session is kept only by one of the other two); or
- the tick that reached the terminal carried `--no-cleanup`.

The `koto next` response to that tick says which, in its `retention` object:
`retained`, and a `reason` of `failure_terminal`, `hierarchy` or `no_cleanup`.
A parent kept for its hierarchy lists its finished children under
`kept_children`.

The rule below doesn't change with the hierarchy case. Whether a hierarchy
holds a session at its terminal tick depends on what else is live at that
moment, which a skill can't know in advance, so it can't stand in for
`--no-cleanup`.

Keeping a session is separate from reporting its result. Every arrival at a
terminal records the result and delivers it to the session's parent and to any
bound request leg on that same tick, whether the session is kept or not. So
`--no-cleanup` means only "keep the session", on a root and on a child alike;
it never withholds a result.

A kept session stays readable with koto's own commands: `koto status <name>`
reports its state (`current_state`, `is_terminal`), and `koto context get <name>
<key>` reads any context key, including the `failure_reason` a blocked edge
writes. For a kept child, the parent's `retry_failed` and `koto rewind` still
act on it.

A kept session stays until something removes it, and every removal follows
the same retention rule. `koto session prune` and `koto workspace prune
--root <name>` keep any session whose hierarchy still has a live member,
listing it with the members that hold it, and remove a released hierarchy
only once its retention period has passed since the release.
`koto session cleanup <name>` removes the one session it
names; when that session still holds live hierarchy members, the removal goes
ahead and koto warns, naming the members it leaves without a link. `koto
session hierarchy <name>` shows what holds a session and when it will be
released, and writes nothing.

## The rule

**A skill whose record should outlive its run passes `--no-cleanup` on every
`koto next` it issues, not on the tick it believes will terminate.**

That holds for a root session and for a child materialized by a parent's
`materialize_children`. A skill has no root/child split for retention.

The flag is inert on any tick that does not reach a terminal, so a blanket rule
costs nothing. A failure terminal is kept without it, but a success terminal
(`done`, `paused_for_review`, `merged`) is not, and a selective rule has to be
correct on every tick. It is wrong in both of the ways below, each of which was
shipped and then measured during shirabe#360.

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
| `accepts: {reason, required}`, transitions `[-> dead_end]` | `action: "done"`, landed on the terminal |
| `accepts: {reason, required}`, transitions `[-> other when …, -> dead_end]` | `action: "evidence_required"`, stopped at `middle` |

koto's own advance engine says the same in its comment on `fresh_evidence`:
fresh evidence is re-granted to a state with no conditional
transitions, so its unconditional fallback fires within the same invocation.

## A leg-attached root reports by promotion

A root session attached to a koto request leg (a child run with
`--koto-leg=<request-id>:<leg>`; see Parent-of-the-Parent Binding in
[`parent-skill-pattern.md`](parent-skill-pattern.md)) follows the same rule. At
the terminal tick koto promotes the session's declared `result:` map to the leg
(or, with no map, its status and final state), under `--no-cleanup` as without
it, and the session keeps its record. Attaching to a leg doesn't make a session
a child, and changes nothing about retention.

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

From koto 0.23.0, a finished session its hierarchy still holds isn't removed
by the replace. koto renames it and its subtree to `<name>_r<N>`, where its
record stays readable, gives the fresh session the name, and moves the old
one back if the new init fails. `koto-open.sh` reports this as
`opened=replaced` followed by `moved_to=<name>_r<N>` and `moved_reason=`.
When the move can't happen, the replace is refused and nothing changes:
`replace_held_live` when the old run's subtree still has live work
(`koto-open.sh` exits 75 and lists that work on a `live=` line), and
`replace_failed` when the move itself failed (exit 74). A caller reports
either and stops; `replace_held_live` clears once that work finishes. On koto 0.22.x
the replace removes the finished session outright and neither line nor
refusal occurs.

Don't discover a finished session by ticking it. A tick on a terminal session
answers `action: "done"`, which an execution loop reports as the run's outcome,
claiming work it didn't do. `koto workflows` lists a retained terminal session
with nothing marking it terminal, so finding a session isn't evidence that it's
resumable either; `is_terminal` from `koto status` remains the read-only way to
ask when a skill needs to know outside its entry path.

## Where a skill states its position

In the skill's own `SKILL.md`, next to the loop that issues the ticks, in the
operative form only: that every tick carries the flag, and a citation here. A
koto template that shows `koto next` command lines in its directives carries
the flag on each of them.

## Adopters

| Skill | Position |
|---|---|
| `/work-on` | Every tick, unconditionally, whether the run is a root or a child `/execute` materialized from `work-on.md`. A run under `--koto-leg` is a root, and its result reaches the leg by promotion. |
| `/execute` | Every tick, unconditionally. An orchestrator session is a root, including under `--koto-leg`, where its result reaches the leg by promotion. |
| `/scope` | Every tick, unconditionally. Its session is a root, including under `--koto-leg`, where its result reaches the leg by promotion. This replaces the selective per-state form it stated before the findings above. Its entry, `scope-open.sh`, passes `--attach-live --replace-terminal`, so a re-run after a finished run gets a fresh session and never ticks the retained one. |
| `/deliver` | Every tick, unconditionally. Its session is a root and a request coordinator; its children report through their legs, not through its session. Under its own `--koto-leg`, its result reaches the caller's leg by promotion. |
| `/coordinate` | Every tick, unconditionally. Its session is a root and runs for days. Each invocation opens a fresh per-run session, `coordinate-<scope>-<stamp>`, through `coordinate-open.sh`, which cancels (never cleans up) any earlier live run of the scope, so every run's log stays readable, including the one a directed-transition scan reads. |

## History

Before koto 0.14.0, `--no-cleanup` on a child also suppressed the events that
carry its result to the parent (tsukumogami/koto#240), so shirabe kept the flag
off child sessions and decided per `/work-on` run with
`skills/work-on/scripts/session-role.sh`. A child that ended at `done_blocked`
lost its context. koto 0.14.0 (tsukumogami/koto#259) separated retention from
result delivery and began keeping failure terminals, and shirabe#439 dropped the
child exception when it moved the koto minimum to that release.

koto 0.22.0 (tsukumogami/koto#423) made `koto session prune`, `koto workspace
prune` and explicit removal follow one retention rule. koto 0.23.0
(tsukumogami/koto#427) applied it at the terminal tick, adding the `hierarchy`
reason, and to `--replace-terminal`, which moves a held predecessor aside
instead of removing it.
