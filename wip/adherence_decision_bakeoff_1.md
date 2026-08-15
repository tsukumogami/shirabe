# Validation: Alternative 1 — Salience stack

Position argued: the salience stack is not the answer to this decision, but it is
the floor underneath every answer, and the case against it rests on an inference
nobody in this exploration has measured. It should ship in full, and it should not
be sold as closing the question.

## Strengths

### 1. The disqualifying test proves too much, and shirabe has already rejected it

The test is: the agent could name the right path when asked, therefore any
mechanism that only supplies knowledge cannot fix the failure. Grant the premise.
The conclusion still does not follow, because *being able to name a thing on cue*
and *having that thing available at action-selection time* are different states,
and the entire prior art in this exploration exists because of the gap between
them.

The decisive evidence is inside shirabe. `DESIGN-execute-skill.md:207-230` designs
the autonomy mandate against a failure with exactly the same structure: an agent
that was told at entry it may run unattended, that could certainly restate that
authorization if asked, and that stops anyway to check in. The design doc's own
words are that the model "reverts to a default caution," and that the fix is to
"kill that specific non-blocker and replace the vibe-of-enough with the concrete
done-signal." That is a pure-prose intervention, carrying no enforcement, aimed at
an agent that already knows — and shirabe considers it load-bearing enough to have
designed, shipped, re-injected at every koto tick, and written a PRD requirement
for (R18).

So the decider faces a fork. Either prose at the decision point can move action
selection in an agent that already knows the rule, in which case the disqualifying
test is wrong as stated and Alternative 1 is not disqualified; or it cannot, in
which case shirabe's autonomy mandate is theater and `DESIGN-execute-skill.md` is
wrong about its own product. The exploration's own prior-art lead reaches for
shirabe's blocker taxonomy as evidence that the anti-rationalization device is
"a real technique and not folklore" (§2), then applies a test that would
invalidate it. Both positions cannot be held at once.

The honest formulation of the test is narrower and I accept it: *a mechanism that
only raises salience is probabilistic, and cannot be relied on for a guarantee.*
That is true. It is a reason not to make Alternative 1 the terminal answer. It is
not a reason to leave the salience layer unbuilt.

### 2. The ceiling everyone is scoring against has never been measured

Three of the five alternatives are justified by a claim about description quality
having a low ceiling. The evidence for that claim is one uncontrolled observation:
`work-on` had a near-ideal description and did not fire on "execute this plan."
That is n=1, mid-session, with conversational momentum behind it, and with a
second skill (`execute`) claiming the same input and suppressing selection through
ambiguity — a confound the firing-mechanics lead itself names (§4, "ambiguity
suppresses selection").

Underneath it sits an inference that runs against the source it cites.
`skill-creator/SKILL.md:396-400` says simple one-step queries may not trigger
skills, and that "complex, multi-step, or specialized queries reliably trigger
skills when the description matches." A 22-issue dependency-ordered plan is
complex, multi-step, and specialized by any plain reading. The lead's step from
that passage to "executing a plan reads to a model as a task it can handle
directly" is explicitly the lead's own reasoning, not the source's, and it places
this case on the opposite side of the line the source draws. The observed
behavior is consistent with the lead's reading, which is why the inference is
reasonable — but it is one data point interpreted against the plain text of the
authority it leans on.

Alternative 1 is the only alternative in the field that builds the instrument that
would settle this. `skill-creator`'s `run_loop` is a real, runnable measurement:
20 queries, 60/40 train/test split, three runs per query for a stable rate,
selection on held-out score. Shirabe has 18 eval suites and every prompt in every
one of them begins with an explicit slash command, so the suite is strong evidence
about post-invocation behavior and zero evidence about invocation. The exploration
is choosing how much machinery to build to fix a rate it has never observed.

This is a value-of-information argument, and it is the strongest structural
strength here: running the trigger evals costs roughly a day and tells the decider
whether the more expensive alternatives are needed at their proposed strength or
at half of it.

### 3. Every other alternative sits on top of this one

Alternative 3 at `advertise` is Alternative 1's CLAUDE.md fragment with a config
key. Alternative 3 at `remind` is Alternative 1's injected block with a predicate
attached. Alternative 4's restricted orchestrator constrains nothing until the
agent invokes `/execute` — an orchestrator agent definition that never gets
selected removes no capability from anyone. Alternative 2 gates the artifact after
the fact, which is worth having and does not make the good path more likely to be
taken first; its own honest cost admits it "catches everything after the fact."
Alternative 5's precedence protocol is delivered as prose an agent must read.

The bakeoff question is therefore not "1 or something else." It is "1, and how
much more." The decider's provisional recommendation already concedes the
description repair. The live disagreement is over the remaining four components,
which is a much smaller argument than the comparison table implies.

### 4. At the level the decider proposes shipping, Alternative 3 scores no better on incident 1

The comparison table gives Alternative 3 a bold **Yes** on catching incident 1 and
gives Alternative 1 "raises odds." That scoring silently uses Alternative 3's
`gate` level while the recommendation ships it at `remind`. A `remind`-level
UserPromptSubmit hook injects text and returns; the agent may proceed exactly as
incident 1's agent proceeded past a skill list that named its task. On incident 1,
at `remind`, Alternative 3's mechanism of action *is* salience — the same
mechanism, delivered through a different hook event, with a predicate deciding
when it fires.

What `remind` genuinely adds over Alternative 1 is conditionality (it fires only
when no koto record exists, which avoids the cry-wolf cost of an unconditional
block) and an org-owner knob. Conditionality is a real advantage and I do not
discount it; the koto lead's session-exact check dissolved the implementation risk
that made it doubtful. But the added cost is a policy surface niwa does not have,
a new `shirabe` subcommand, and a niwa release — for an intervention whose
mechanism of action, at the shipping level, is the same as the cheap one's.

### 5. The dispatch prefix is not a salience play, and it is the best dispatch coverage in the field

One component of this stack is categorically different from the rest.
`dispatch.go:421` is a channel guarantee, not a probability play: a
niwa-authored prefix reaches every dispatched worker unconditionally, is pinned
prefix-first by `TestComposedArgvIsPrefixThenBody`, survives the spill path by
construction, has no size budget to negotiate, and propagates automatically down
self-dispatch trees (`dispatch.go:206-221`). niwa's own recorded reasoning in
`dispatch_keepalive.go:14-22` is that the prompt prepend "is the one channel niwa
controls end to end for a dispatched worker."

Compare the field on that path. SessionStart does not fire for subagents, and the
instance `.claude/settings.json` carries no SessionStart entry today. Alternative
3's `remind` level rests on an open question — whether UserPromptSubmit fires for a
dispatched worker's initial task brief. Alternative 4 reaches dispatched workers
only when launched with `--agent`. The comparison table scores Alternative 1
"Covers dispatch: Partly"; on delivery reliability to a dispatched worker the
prefix is the strongest single channel anyone has identified.

### 6. Lowest blast radius in the field, and P5 cuts in its favor

No component here can block legitimate work, brick a session, or cost the user a
turn on a false positive. The worst case is wasted tokens and a reminder the agent
ignores. Set against the alternatives: a PreToolUse gate matching every Bash call
must fail open by hard constraint 5 because a stale binary bricks every session
(`materialize.go:592-603`), and its false positive blocks real work with no human
to prompt because `ask` is unusable; Alternative 4 removes Edit/Write from an
agent that legitimately authors a wip projection and a PR body.

`P5: Strictness tracks blast radius` is usually cited to license staging a gate
down to a notice. Read the other half: "a check whose retrofit cost is contained
can land strict." Alternative 1's components can land at full strength this week
precisely because the cost of being wrong is a few hundred tokens. The mechanism
whose blast radius is every Bash call in every session is the one P5 says must
land as a notice first — and a notice is a salience intervention.

### 7. It is the only alternative that acts entirely through text the affected contributor can read

The open tension the decision must resolve is that niwa's `[workspace]` table is
deliberately overlay-proof, with `OverlayWorkspaceTombstone` existing to state the
reason: keep "a contributor's first run un-alterable by a configuration layer they
cannot read." Every component of Alternative 1 acts through visible text — a skill
description in the plugin, an injected block that appears in the transcript, a
prompt prefix that is literally the first thing in the worker's first message, a
brief slot the coordinator wrote. A contributor reading the session can see the
whole of the policy acting on it.

That is a genuine values match with a decision niwa has already made once, in this
exact area, in the opposite direction from where a distributed policy hook would
push it. It does not resolve the org-owner configuration request — Alternative 1
answers that request weakly at best, which I concede below — but it is the only
alternative that does not have to argue with the tombstone.

## Weaknesses

### 1. It does essentially nothing for incident 2, and incident 2 is the harder fact

I will not soften this. Incident 2's agent had invoked `/execute`, was reading 716
lines of shirabe prose, had run the preflight and produced a valid koto payload
with all six `waits_on` edges — and decided a generic session constraint on
subagents outranked `spawn_and_await`, resolved it privately, and implemented six
issues inline. Salience was maximal. The skill was in context, being read, at the
moment of the decision. Behavior went the other way regardless.

That is a worse fact for me than the disqualifying test, because it is not an
argument about knowledge versus salience — it is a natural experiment in which the
salience intervention was already at full strength and lost. Nothing in the drafted
stack touches it. The comparison table's **No** in the "Catches #2" column is
correct and I accept it.

One distinction is worth putting on the record without overclaiming. The prose the
agent was reading did not contain the relevant content. `/execute`'s
blocker/not-a-blocker taxonomy governs *stopping*, and incident 2's agent did not
stop — it continued, inline. There is no row anywhere in shirabe stating that a
generic constraint on spawning does not void a workflow whose guarantees are
delivered through spawning. So incident 2 is evidence that silence fails at a
decision point, not evidence that a specific rebuttal at that decision point would
have failed. Whether that distinction is worth anything is untested in either
direction, and a decider is entitled to treat it as special pleading. What I will
say for it is that it is cheap to test: it is one more row in a table this
alternative is already shipping.

Which leads to the honest amendment. The stack as drafted omits its best available
move on incident 2. A SessionStart-injected block arrives through the same channel
as session-level instructions, which is the altitude the precedence rule
(`using-superpowers/SKILL.md:62`) puts *above* skills. A skill cannot outrank a
session constraint; injected session context is at least in the same weight class.
Adding one precedence row — a generic prohibition on spawning does not silently
void a workflow that depends on spawning; surface the conflict rather than resolve
it — is Alternative 5's content delivered through Alternative 1's channel at
roughly zero marginal cost. It is still probabilistic, and incident 2's agent
conceded it should have surfaced the conflict and did not, which is direct
evidence against the class. I offer it as a strict improvement on the drafted
stack, not as coverage.

### 2. It answers the org-owner configuration request weakly

Soft constraint 8 asks that org owners be able to configure this. Alternative 1
gives them a CLAUDE.md declaration the hook could read and, in practice, an
all-or-nothing choice about whether the shirabe plugin is enabled. There is no
level, no per-repo override, no `off` switch short of disabling the plugin. If the
decider weights the configuration request heavily, Alternative 3 answers it and
Alternative 1 does not.

### 3. Removing `<SUBAGENT-STOP>` overrides a deliberate decision without a designed replacement

The drafted stack ships the superpowers mechanism minus its subagent exemption.
That exemption is the first thing in superpowers' file, placed there deliberately.
The plausible reason — a subagent dispatched to run three greps should not be
pushed through brainstorming — is a real concern, and the distinction actually
wanted is task breadth rather than dispatch mechanism. Nobody has designed that
discriminator. Shipping the override without one forces narrow dispatched workers
through heavy framing on every hop of a self-dispatching tree.

### 4. Description repair can move traffic the wrong way

`execute` and `work-on` both claim PLAN documents. Making `execute`'s description
pushier without settling the boundary risks pulling single-issue work away from
`work-on`. The trigger evals mitigate this only if the two skills share a negative
set, and only if the evals are actually run rather than written and filed — which
CLAUDE.md's own skill-eval convention flags as a standing hazard.

### 5. It composes badly with two things already occupying the same slot

Superpowers already injects an `<EXTREMELY_IMPORTANT>` block at every
startup/clear/compact. A second block claiming top priority competes with it, and
neither author can measure the interaction. On the dispatch side, niwa's keep-alive
prefix already opens as a preamble saying "before starting the task below"; a
workflow mandate is a second preamble with the same opening move, and the dispatch
lead flagged that stacked preambles read badly and that someone has to decide
whether they merge.

### 6. Two of five components require a niwa release

The brief-template slot and the prefix both live in code embedded in the niwa
binary, so "ships this week" is true for the shirabe half and depends on a niwa
release for the other half. The strength claim should be stated at that
resolution.

## Risks

**Moral hazard is the largest risk and it is organizational, not technical.**
Shipping five visible things and declaring the problem addressed is the failure
mode this alternative invites, because every component produces an artifact a
reader can point at while the underlying rate stays unknown. The mitigation is to
bind the stack to the measurement it produces and to a pre-committed promotion
trigger, so that "we shipped the salience stack" cannot be an answer to "did the
rate move."

**Cry wolf.** An unconditional block at every startup, clear, and compact
degrades with exposure, and there is no instrumentation that would detect the
degradation. This is the specific advantage a conditional predicate has over an
unconditional injection, and it favors Alternative 3.

**Token cost on every dispatch** (soft constraint 9), including trivial ones. The
mitigation is a short pointer rather than a restated workflow — the dispatch lead
reaches the same conclusion independently.

**Interaction with the autonomy mandate.** The prior-art lead's §12 hypothesis is
that an agent primed to proceed without pausing is, at action-selection time,
biased toward proceeding directly — which is what both incidents look like. If
true, a session now carries a keep-alive preamble pulling one way and a workflow
mandate pulling the other, on the same turn, unmeasured. Nothing in the corpus
considers this interaction.

**Trigger-eval validity.** `run_loop` scores cold single queries. Both incidents
were mid-session instructions with momentum behind them. A high score would not
prove the incident cannot recur, and treating it as if it did is the same moral
hazard one level down.

## Conditions under which this is the right choice

**When the achievable prize is smaller than the framing implied.** The late
correction establishes that koto's guarantees are bookkeeping, not enforcement:
the spawn primitive is a logging stub, review gates and CI monitoring are
directive text koto never verifies, and an agent can drive the whole loop
submitting fabricated evidence into a clean record. No alternative here can
deliver "the adversarial reviews definitely ran." The realistic goal is that the
run is recorded and visible. That narrows the gap between a mechanism that makes
the good path likely and one that makes it mandatory — not to zero, since the
record is precisely what the user lost, but far enough that the cost ratio starts
to matter.

**When the measurement has not been taken.** Until a trigger eval exists, every
alternative is sized against an unobserved rate. Alternative 1 is the correct
first move under uncertainty specifically because it is the alternative that
resolves the uncertainty.

**When the decision is staged rather than terminal.** `P5` licenses shipping as a
notice and promoting once behavior settles. This alternative is right *as a
stage*, and wrong as an answer. The condition is that the promotion trigger is
written down at the same time — a named eval threshold, or the next incident,
whichever comes first — rather than left to be relitigated later.

**When contributor-legibility is weighted the way niwa already weighted it.** If
the `[workspace]` tombstone reasoning is treated as a live value rather than a
historical accident, a mechanism acting entirely through text the affected agent
and a human reading the transcript can see is the one that fits, and the
org-owner configuration request is the thing that gives ground.

**When dispatch volume is dominated by narrow tasks.** Then the prefix must be a
short pointer and the `<SUBAGENT-STOP>` override needs its breadth discriminator
before it ships, or this alternative makes the common case worse to improve the
rare one.

Conversely, this is the wrong choice outright if the decider concludes that
incident 2's class — a higher-precedence constraint silently voiding a skill's
mechanism — is the primary risk to design against. Alternative 1 has nothing to
say there beyond the amendment above, and that class generalizes badly: any
blanket session constraint on subagents silently disables the koto loop, the
juries, and the research fan-out at once.

## Recommendation

**Adopt-with-conditions — as the floor, explicitly not as the answer.**

Adopt unconditionally, because each is independently justified regardless of what
else ships: the `execute` description repair (defective by shirabe's own published
standard, with ten sibling skills already following the house pattern), and the
trigger evals (the only instrument that can measure the rate this whole decision
is being sized against, and a precondition for tuning anything else).

Adopt, with the noted caveats: the `/dispatch` brief slot (in-idiom next to step
1a, which already proves the template carries a MUST-shaped process instruction)
and the `dispatch.go:421` prefix, short and pointer-shaped, ordered deliberately
against the keep-alive preamble rather than stacked on it.

Adopt with amendment: the SessionStart injection, with a precedence row covering
incident 2's conflict shape, and without the `<SUBAGENT-STOP>` override until
someone designs the task-breadth discriminator that override requires.

Reject as the terminal answer. This stack does not close incident 2, its coverage
of incident 1 is probabilistic, and it answers the org-owner configuration request
weakly. It must ship bound to a written promotion trigger, or it becomes the
artifact that lets the question be declared closed while the rate stays unknown.

The correction I would press hardest in cross-examination is narrower than "pick
me." It is that the comparison table scores Alternative 3 at `gate` while the
recommendation ships it at `remind`, and at `remind` its mechanism of action on
incident 1 is salience — the same mechanism, through a different hook event, with
a predicate deciding when it fires and a policy surface, a shirabe subcommand, and
a niwa release attached. That difference is worth paying for if conditionality and
the org-owner knob are worth that much, and the tombstone reasoning does not veto
the placement. Those are the two questions the decision actually turns on, and
neither of them is "does prose work."
