# Cross-Examination: skill-adherence mechanism

Phase 5. Records the exchanges that changed positions, and the three findings
that decide the synthesis. Two of these came from validators attacking their own
alternatives, which is the outcome the adversarial structure exists to produce.

---

## Finding A: The outcome gate was live during both incidents and certified them both

Validator 2, arguing FOR outcome gating, produced the strongest argument against
its own position and led with it.

Shirabe's shipped path-independent checks (L01, L06, PB1-PB4) were all running
when both incidents occurred. Walked against the incidents:

- Incident 2's agent implemented, tested, **ticked acceptance criteria**, and
  committed one issue at a time in dependency order. L06 passes.
- It ran `run-cascade.sh`, so the chain reached its terminal states. L01 passes.
- Both incidents produced PRs with conformant bodies. PB1-PB4 pass.

> "The shipped outcome gate did not merely fail to prevent the incidents; it
> **certified them**. That is worse than 'insufficient.' A check that passes both
> known instances of the failure it is nominally adjacent to is not evidence for
> the doctrine -- it is evidence that the doctrine, as currently instantiated, is
> blind to this class."

It then enumerated every candidate off-machine property and found each one passes
both incidents: per-issue commit structure, acceptance criteria ticked, chain
cascade, PR body conformance. Its conclusion:

> "The substantive-properties move fails not because those properties are hard to
> check but because **a competent inline implementation satisfies all of them**.
> That is the whole point of incident 2: the agent did the work correctly and
> skipped the machinery. The properties that discriminate are exactly the ones
> with no off-machine representation."

**This retires outcome gating as the primary mechanism.** Not on argument -- on a
falsification datum.

## Finding B: But client-side asks the failing session to grade itself

The same validator's strongest positive point survives Finding A and cuts against
every other alternative:

> "It is the only alternative whose verdict is produced by someone other than the
> party that failed. Alternatives 1, 3, 4, and 5 all run inside the session that
> just made the mistake, on the same machine, under the same agent, subject to the
> same context pressure and the same precedence reasoning that produced incident
> 2. ... Every client-side mechanism asks that same session to evaluate itself
> again, just earlier or louder."

Findings A and B together form the real constraint of this decision. **The
discriminating state exists only on the machine (A), and the machine is the party
that failed (B).** Any mechanism that lives entirely on one side inherits that
side's defect.

The resolution is not to choose a side. It is to **detect locally and publish
off-machine**: the local check is the only thing that can discriminate, and
publishing its result is what removes self-grading. Validator 2 names the reframe
that makes this available:

> "These traces are weak because **koto deletes them and publishes nothing**, not
> because process is intrinsically untraceable. That is a bounded, fixable
> property of one tool, not a law of nature."

## Finding C: The predicate is gameable, and gaming it is worse than failing it

Validator 2's attack on Alternative 3's predicate:

> "'A koto session exists' is satisfiable by one command and should not survive
> this decision unchallenged."

Compounded by the koto research: koto's guarantees are bookkeeping, not
enforcement -- the substrate-spawn primitive is a logging stub, and review gates
are directive text koto never verifies. So a bare session record attests
*registration*, not *delegation*.

The failure mode this creates is worse than the one it replaces. A gate keyed on
session existence teaches an agent the single command that buys permission, after
which it implements inline exactly as before -- and now leaves behind a koto
record that falsely attests the loop ran. The record is the artifact the whole
design proposes to trust.

**The predicate must therefore assert delegation, not registration.** Candidates,
in increasing cost: `currentState` advanced past `orchestrator_setup`; a
`scheduler_ran` event with `spawned_count >= 1`; child session directories
matching `<parent>.o-*`; child count commensurate with the plan's issue count.
The `scheduler_ran` assertion is the cheapest that actually discriminates -- it is
a grep for a recorded fan-out, and it is exactly what incident 2 never produced.

## Finding D: A gate without a sanctioned bypass manufactures silent failure

Validator 5's deadlock argument, which validators 3 and 6 were both asked to
answer:

An agent under a session instruction forbidding subagents meets a PreToolUse deny
on the edit. It cannot spawn (session instruction). It cannot edit (gate). It
cannot ask (`ask` is unusable under `bypassPermissions`, and there is no human).

> "It has no legal move and no defined behavior, and it will resolve that the way
> incident 2's agent resolved its conflict: privately, undocumented, in whatever
> way gets the turn finished. ... Without 5, a gate's first wrong firing does not
> produce a complaint; it produces an unlogged workaround."

The escape hatch is load-bearing, not garnish. This applies to Alternative 4 with
greater force: an orchestrator that can *only* proceed by spawning, in a session
forbidding spawning, has no legal move at all.

## Finding E: The precedence conflict is demonstrably a coin flip

Validator 5 observed that this very session is the reproduction:

> "The orchestrator running this decision carries the identical session
> instruction -- 'Do not call the AgentTool unless the user requested it' -- and
> resolved it the opposite way: it spawned five validators. Same instruction, same
> workspace, same week, two agents, opposite readings. This is not a hypothesis
> about ambiguity; it is a reproduced instance of it, and I am one of the outputs."

An instruction two competent agents read oppositely is under-specified, and
under-specification is fixable by specification. This is the cheapest change in
the field -- a paragraph placed where the agent is provably already asking the
question (at `spawn_and_await`), rather than a probability bet on attracting
attention to a skill that was never invoked.

## Finding F: `remind` does not survive the disqualifying test

Validator 3, arguing FOR the graded policy, conceded the rung:

`remind` restates knowledge the agent already has. The disqualifying test --
*the agent already knew* -- kills it as an independent contribution, which is the
"is `remind` just Alternative 1 with extra steps" attack it was asked to answer.
Its own revised recommendation removes the policy surface and the `gate` rung
from the first release and ships the predicate as a **detector** instead:

> "If only one thing ships, it is this."

## Finding G: The predicate blocks a sanctioned path, by design

Validator 5 caught a false-positive case that would have shipped. Verified
directly against `skills/execute/SKILL.md:242-246`:

> "A `coordinated` PLAN spans more than one repository, so there is no single
> shared branch and **no plan-spanning koto session (koto has no cross-repo
> session)**. The coordinated path is therefore a **plain durable-state loop**
> the SKILL drives directly."

So a coordinated multi-repo `/execute` run is a fully sanctioned execution with no
koto session at all, by design. Every predicate-based check in this decision would
flag it as an adherence failure and, at the `gate` rung, would block legitimate
work on the newest execution path in the skill.

The carve-out is mandatory, not optional, and it must key on something the checker
can see without a koto session -- the plan's own `coordinated` mode, read from the
PLAN doc or from the coordination PR's fenced state block. This also narrows what
the detector can claim: for coordinated plans the durable state lives on the
coordination PR, so that is where the equivalent signal has to be read.

## Finding H: The proposed conflict-record vehicle does not work

Validator 5 tested its own recommended implementation rather than asserting it:
`koto overrides` requires an existing workflow and exits 1 with "workflow not
found." Since incident 2's agent never ran `koto init`, there was no session to
record an override against -- the vehicle is unavailable in exactly the case it
was proposed for.

Its replacement splits by when the conflict arises. In-loop, `koto overrides
record --gate <name>` with a mandatory rationale fits exactly and ships today.
Pre-session, the vehicle must be the `shirabe work-summary` hook path, which is
already session-keyed, already distributed default-on by niwa to every shirabe
adopter, and already renders a **user-visible `systemMessage`** alongside
agent-visible `additionalContext`. That is the surfacing channel, and it needs no
new distribution.

A related sequencing change follows: move `koto init` ahead of the first decision
point in the execute template, keeping the expensive side effects in
`orchestrator_setup`. That makes the in-loop vehicle available earlier and writes
the artifact the detector reads before the agent reaches the step it might skip.

## Finding I: The ordering statement must narrow interpretation, not claim precedence

The single most important safety constraint to come out of the bakeoff, from
Validator 5:

> "Write the ordering statement as interpretation-narrowing, never as
> precedence-claiming. 'Requesting `/execute` requests its children' is
> defensible. 'Skills outrank session instructions' is not, and shipping it would
> be a worse outcome than either incident."

This is correct and binding. The fix for incident 2 is to resolve an ambiguity --
whether asking for a workflow constitutes asking for the subagents that workflow
is defined in terms of -- not to invert the documented precedence order. A skill
that instructs agents to disregard session-level instructions is a materially
worse failure than the one being fixed, and it would generalize to every
constraint a user or operator sets.

## What survives

| Component | Status | Why |
|---|---|---|
| Detector on a delegation-asserting predicate | **Core** | Only thing that discriminates; agent-independent; ~25 lines |
| Ordering statement at the conflict point | **Core** | Cheapest in the field; prevents incident 2; testable with existing evals |
| Publish the record off-machine | **Core** | Resolves Finding B; needs an R9 amendment |
| `execute` description repair + trigger evals | **Adopt** | Independently justified; the only measurement instrument |
| Define the plan-derived-PR completion property | **Adopt** | Cheap; makes every other component better |
| Skill-registered hooks as delivery | **Adopt** | Confirmed in binary; no niwa change, no policy surface |
| `[claude.skills]` policy surface | **Defer** | Unjustified until the detector produces data |
| `gate` rung (PreToolUse deny) | **Defer** | Needs the strengthened predicate and the escape hatch first |
| Restricted-tool orchestrator | **Reject as primary** | Misses the human path; deadlocks under Finding D |
| Outcome gating as primary | **Reject** | Falsified by Finding A |
| `koto overrides` as the pre-session vehicle | **Reject** | Tested: exits 1, "workflow not found" (Finding H) |

Two constraints bind every surviving component: the coordinated-plan carve-out
(Finding G) and the interpretation-narrowing rule (Finding I). Neither is
optional, and both were caught by validators rather than by the framing.
