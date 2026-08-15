# Alternatives: Which mechanism should make shirabe's sanctioned workflow the path an agent actually takes?

The six raw options from research are not mutually exclusive. They are clustered
here into five coherent strategies that differ in **what they treat as the root
cause** and therefore in what they would ship first. Each is stated at its
strongest, with its own honest cost, so the bakeoff evaluates real positions
rather than strawmen.

---

## Alternative 1: Salience stack (guidance only)

**Root-cause claim:** the agent's attention at action-selection time, not its
knowledge or its capability.

Ship, in one release: repair `execute`'s description (replace the ~40 words of
internal vocabulary with trigger conditions naming the moment, matching the house
pattern ten sibling skills already follow); build trigger evals via
`skill-creator`'s `run_loop` so description changes are falsifiable and the
`execute`/`work-on` boundary is quantified; add a shirabe `hooks.json` declaring a
SessionStart hook that injects an anti-rationalization table on
`startup|clear|compact`, following the superpowers mechanism but **without** its
`<SUBAGENT-STOP>` exemption; add a workflow slot to the `/dispatch` brief template
(step 1b, mirroring step 1a's treatment of the reporting block); prepend a short
generic mandate at `dispatch.go:421`.

**Strongest case.** It is the only alternative that matches the user's stated
preference exactly. Every component is cheap, reversible, and independently
valuable -- the description is defective by shirabe's own published standard
regardless of what else ships, and the eval gap means shirabe currently cannot
measure the thing it is trying to fix. It attacks the correct moment (turn-1
action selection), and the `compact` matcher keeps the policy alive through long
runs, which is exactly the shape of run both incidents were. It ships this week.

**Honest cost.** It is a probability play and must be sold as one. It fails the
disqualifying test: the agent already knew. `work-on`'s near-ideal description
did not fire. And nothing in this stack addresses incident 2 at all -- the agent
was already inside the skill, reading its prose, when it decided the session
constraint outranked `spawn_and_await`.

---

## Alternative 2: Path-independent outcome gating

**Root-cause claim:** trying to control the path is the mistake; control the
outcome instead.

Shirabe's shipped doctrine, applied twice (the #220 DRAFT-vs-READY discipline and
the PR-body gate), with `references/pr-body-conformance.md` stating the goal --
"pointing every consumer here makes conformance a property of the repo." Extend
the same move: define what a plan-derived PR must look like regardless of who
produced it (per-issue commit structure, acceptance criteria ticked, review
evidence present), and enforce it in CI. Plus close the payload/submission seam
so `plan-to-tasks.sh` cannot emit a payload it does not also register.

**Strongest case.** It is the only alternative with two shipped precedents in
this exact repo, and the brief that established the pattern names
path-independence as *the acceptance property*. It cannot be bypassed by an agent
choosing a different route, needs no hook, no policy surface, and no niwa change,
and it degrades gracefully -- a human opening a PR by hand is held to the same
bar. Closing the payload seam is the single cheapest intervention identified in
the entire round.

**Honest cost.** The brief that established the doctrine also shows its limit:
it works where the sanctioned path's value is a **checkable artifact property**
(a title format, a `---` separator). Both incidents' loss was a *process* -- the
task state machine, the per-issue spawn, the adversarial review gates. Those
leave weak artifact traces. Adversarial review in particular leaves almost none.
And it catches everything after the fact, which does not answer the user's stated
loss of *visibility while it was happening*.

---

## Alternative 3: Graded workspace policy over a koto-session predicate

**Root-cause claim:** there is one observable condition that distinguishes
adherence from every failure mode, and the only open question is when to
evaluate it and how hard to push.

One predicate -- *a plan is in play and no koto session is bound to it* -- behind
one org-owner-set level:

| Level | Surface | Behavior |
|---|---|---|
| `off` | -- | nothing |
| `advertise` | generated CLAUDE.md fragment | names the sanctioned workflows |
| `remind` | UserPromptSubmit hook | restates the policy when the predicate is unsatisfied |
| `gate` | PreToolUse deny | refuses the edit that would bypass the workflow |

Declared in `[claude.skills]` with a per-repo override and an off switch,
distributed by niwa (which already injects exactly this shape of hook), decided
by a `shirabe` subcommand (preserving the established niwa-declares/shirabe-decides
split). Shipped at `remind` and promoted to `gate` once behavior settles, per
`P5: Strictness tracks blast radius`, which already licenses precisely this
staging.

**Strongest case.** It is the only alternative that catches **both** incidents
with one mechanism, on both entry paths, because it keys on the durable artifact
rather than on invocation -- and the predicate is confirmed computable, verified
live. It spans the user's whole requested spectrum in one knob, so "guidance now,
enforcement later" is a config change rather than a redesign. Every part already
ships: niwa's `pr-body-hook` is the gate template, `work-summary absence` is the
remind template, `appendToWorkspaceRulesFile` is the advertise template. It gives
org owners the configuration option that was explicitly requested.

**Honest cost.** The most machinery of any alternative, and it introduces a
policy surface niwa does not have. It has an unsolved implementation gap: the
grep answers "is there a session for plan X" but something upstream must supply
X, and a wrong answer either misses (no gate) or blocks legitimate work (false
positive on a repo that merely contains plan docs). The PreToolUse footgun is
real and documented. And the org-owner placement question collides head-on with
niwa's `[workspace]` tombstone reasoning: a mandate changes what an agent does
for a contributor who cannot read the layer imposing it, which is the exact class
that design excludes.

---

## Alternative 4: Structural constraint (restricted-tool orchestrator)

**Root-cause claim:** an orchestrator that *can* implement inline eventually
will. Remove the capability rather than discourage its use.

Ship an agent definition for plan-scale execution whose tool list omits Edit and
Write (and constrains Bash enough that it is not a bypass). Its only route to code
is spawning `/work-on` children -- which is the sanctioned loop. Pair it with
atomic payload registration so the orchestrator cannot hold an unregistered
payload.

**Strongest case.** It is the only alternative that converts a *should* into a
*cannot*, and it would have caught both incidents outright: incident 1's agent
could not have hand-implemented 22 outlines, and incident 2's agent could not have
implemented six inline no matter how it resolved the precedence conflict. It
also formalizes an invariant shirabe's architecture already asserts --
`DESIGN-execute-skill.md` describes `/execute` as holding "only the metadata
surface" and offloading "every issue's real work to a fresh `/work-on` child." It
needs no policy surface, no hook, and no niwa release.

**Honest cost.** Coverage is the problem: it binds to an agent definition, so it
reaches dispatched workers launched with `--agent` and does **not** reach a human
typing `/execute` in an ordinary session, which is half the requirement. It is
coarse -- the orchestrator legitimately authors a wip state projection and a PR
body, so carve-outs are needed, and a Bash-capable agent can write files anyway.
And it changes *what the agent is* rather than *what it chooses*, which is a
heavier and less reversible commitment than any other alternative here.

---

## Alternative 5: Conflict-surfacing protocol

**Root-cause claim:** incident 2's deviation was defensible; what was
indefensible was that it was silent. Deviation is sometimes correct. Unrecorded
deviation never is.

Treat the precedence conflict as the primary target. When an agent concludes that
a session or workspace constraint forbids a skill's prescribed mechanism, the
sanctioned response is to record it -- plausibly through `koto overrides`, a
shipped verb for exactly this -- and surface it to the user, not to resolve it
privately and continue. Pair with an explicit ordering statement in shirabe's
skills so an agent knows a generic constraint on spawning does not silently void
the workflow that depends on spawning.

**Strongest case.** It is the only alternative addressing the root cause of
incident 2 rather than its symptom, and that root cause generalizes badly if left
alone: *any* blanket session-level constraint on subagents silently disables most
of shirabe, since the koto loop, the juries, and the research fan-out are all
delivered through subagents. The infrastructure exists (`koto overrides`). It
respects agent judgment, which matches the stated preference more honestly than a
gate does -- the agent may still deviate, it just cannot do so invisibly. And it
is the only alternative that would have given the user the thing they actually
said they lost: knowing what was happening while it happened.

**Honest cost.** It does nothing for incident 1, where no conflict was ever
recognized. It depends on the agent noticing and reporting the conflict, which
brushes against the constraint that detection must not rely on self-report -- a
weaker version, since it governs a moment of explicit reasoning rather than a
retrospective claim, but the same failure mode. And "surface the conflict" has no
teeth on its own: incident 2's agent conceded it *should* have flagged the
conflict and did not.

---

## Comparison

| | Catches #1 | Catches #2 | Covers dispatch | Covers human `/execute` | Org-configurable | Cost | Precedent in repo |
|---|---|---|---|---|---|---|---|
| 1. Salience stack | Raises odds | No | Partly | Yes | Weakly | Low | superpowers |
| 2. Outcome gating | Partly | Partly | Yes | Yes | No | Low | **Twice, shipped** |
| 3. Graded policy | **Yes** | **Yes** | Yes | Yes | **Yes** | High | `pr-body-hook` |
| 4. Restricted tools | **Yes** | **Yes** | Yes | **No** | No | Medium | Design invariant |
| 5. Conflict protocol | No | **Yes** | Yes | Yes | No | Low | `koto overrides` |

## Decider's provisional recommendation, for the validators to attack

**Alternative 3, staged at `remind`, with Alternative 1's description repair and
Alternative 2's payload-seam closure shipped alongside as independent hygiene,
and Alternative 5 folded in as the sanctioned response when the predicate fires
and the agent believes it has cause to proceed anyway.**

The reasoning: 3 is the only single mechanism that catches both incidents on both
paths and is configurable by an org owner, and its predicate is confirmed
computable. Shipping it at `remind` rather than `gate` honors the stated
preference without foreclosing enforcement, and `P5` is the existing doctrine
that sanctions exactly that staging. 1 and 2's cheapest parts are worth shipping
whatever else happens. 5 supplies the escape valve that keeps a `gate` from being
ripped out the first time it is wrong.

Validators should attack this hard on: whether 3's machinery is justified when 2
is shipped doctrine and cheaper; whether the "which plan is in play" gap is fatal;
whether `remind` is just Alternative 1 with extra steps and a worse cost profile;
and whether the `[workspace]` tombstone reasoning should veto the org-owner
placement outright.
