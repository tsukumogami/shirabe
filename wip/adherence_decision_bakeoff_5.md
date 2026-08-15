# Validation: Alternative 5 — Conflict-surfacing protocol

## Framing, before the strengths

The other four alternatives answer one question: *how do we make the agent take
the sanctioned path?* Alternative 5 answers a different one: *what should an
agent do when it has correctly concluded it cannot take that path?*

These are not competing answers. They are answers to two questions, and a
portfolio that answers only the first will be defeated by the second. That is
the honest position I am defending — not that 5 wins the bakeoff standalone (it
does not), but that no gate in this field can ship without it, and that its
cheapest component would have deterministically prevented incident 2 while
every other alternative would only have made incident 2's agent's position
harder without making it decidable.

## Strengths

### 1. It is the only alternative aimed at incident 2's cause, and that cause generalizes badly

Incident 2's agent was not wrong by the letter. The documented precedence rule
says user and session instructions outrank skills; it applied the rule. The
evidence file states the generalization plainly (`explore_..._evidence.md:66-69`):
*any* generic session-level constraint on agent spawning silently disables every
shirabe skill whose guarantees are delivered through subagents — which is most
of them. The koto execution loop, the jury reviews in `/prd` `/brief` `/strategy`
`/roadmap`, and the parallel research fan-out in `/explore` are all subagent-delivered.

No other alternative touches this. Alternative 3 at `gate` does not resolve it —
it makes it worse, and I develop that below. Alternative 4 removes the
orchestrator's ability to implement inline, which means an agent under a
no-subagent constraint can neither spawn nor implement: it has no legal move at
all. Alternative 1 exhorts. Alternative 2 checks the artifact after the fact and
says nothing about the moment of conflict.

### 2. The conflict is demonstrably a coin flip, not a settled rule, and this session is the proof

The orchestrator running this decision carries the identical session instruction
— "Do not call the AgentTool unless the user requested it" — and resolved it the
opposite way: it spawned five validators. Same instruction, same workspace, same
week, two agents, opposite readings. This is not a hypothesis about ambiguity; it
is a reproduced instance of it, and I am one of the outputs.

An instruction that two competent agents read oppositely is under-specified, and
under-specification is fixable by specification. This is the cheapest change in
the entire field — a paragraph — and unlike Alternative 1's salience play it is
not a probability bet on attracting attention to a skill the agent has not
invoked. Incident 2's agent had already invoked the skill and was reading its
prose when it made the call. It was inside the document, at the step in question,
provably already asking the question. An ordering statement placed at
`spawn_and_await` answers a question the agent is demonstrably asking at that
exact moment, which is a categorically different mechanism from hoping a
description fires.

### 3. It is the only alternative that delivers what the user said they lost

The user's stated loss in both incidents was visibility — "are you using koto for
anything?" was the question that surfaced both. Alternative 2 catches things
after the fact by construction. Alternative 4 is silent. Alternative 3 at
`remind` restates policy the agent already knows; at `gate` it produces a denial,
which is a signal to the agent, not a report to the user.

A surfaced conflict is the actual thing: a timestamped, reasoned statement that
the run is departing from the sanctioned path, in a channel the user reads,
while it is happening.

And that channel already ships. `shirabe work-summary` is registered by niwa into
every shirabe-adopting repo, default-on, at three events
(`niwa/internal/workspace/materialize.go:504-508`):

```go
var workSummaryHookDefaults = []WorkSummaryHookMode{
	{Event: "post_tool_use", Matcher: "Bash", Mode: "capture"},
	{Event: "user_prompt_submit", Matcher: "", Mode: "absence"},
	{Event: "session_start", Matcher: "compact", Mode: "compact"},
}
```

It emits a **user-visible `systemMessage`** alongside agent-visible
`additionalContext` on the PostToolUse and UserPromptSubmit paths
(`crates/shirabe/src/work_summary.rs:1102-1127, 1181, 1204`). So the surfacing
half of this alternative needs no new distribution surface and no niwa policy
table — it is a mode on a binary already on the default hook path. Alternative 3,
by contrast, must invent a policy surface niwa does not have and then argue past
the `[workspace]` tombstone.

Incidental but load-bearing: that same code reads `session_id` off the hook JSON
(`work_summary.rs:1139-1143`), which settles open question 2 in the koto
observability research from shipped shirabe source rather than by inference. Any
session-keyed adherence check — including Alternative 3's — has its join key
confirmed here.

### 4. It is the only alternative shirabe's existing eval infrastructure can measure today

All 18 eval suites use `evals.json` and every prompt begins with an explicit
slash command. The context calls this a weakness: strong evidence about
post-invocation behavior, zero evidence about invocation. That shape is fatal for
Alternative 1, which needs a trigger-eval capability built via `run_loop` before
its central claim is falsifiable.

It is exactly right for Alternative 5. "Given a session instruction that
conflicts with `spawn_and_await`, does the agent emit the conflict record before
proceeding?" is a post-invocation behavior test in the format the harness already
runs. Alternative 5 is falsifiable this week with no new tooling. That matters
disproportionately in a decision where the leading alternatives are all being
scored on predicted agent behavior nobody can currently measure.

### 5. A gate without a sanctioned bypass is a deadlock generator, and this is not theoretical

Hard constraint 2 says `ask` is unusable: dispatched and headless sessions run
under `bypassPermissions` with no human. Now compose that with Alternative 3 at
`gate`. An agent under a session instruction forbidding subagents meets a
PreToolUse deny on the edit. It cannot spawn (session instruction). It cannot
edit (gate). It cannot ask (no human). It has no legal move and no defined
behavior, and it will resolve that the way incident 2's agent resolved its
conflict: privately, undocumented, in whatever way gets the turn finished.

The escape valve is not garnish on a gate. It is the thing that determines
whether a gate produces recorded deviation or invents a new class of silent
failure. The decider's own note — that 5 "keeps a gate from being ripped out the
first time it is wrong" — understates it. Without 5, a gate's first wrong firing
does not produce a complaint; it produces an unlogged workaround.

### 6. It matches the stated preference more honestly than a graded gate does

The user prefers strong guidance over hard enforcement. Alternative 3 at `remind`
claims to honor that, but `remind` is a restatement of knowledge the agent
already has — the disqualifying test in the context kills it as an independent
contribution, which is precisely the "is `remind` just Alternative 1 with extra
steps" attack the decider invited. Alternative 5 preserves agent judgment
literally: the agent may still deviate, on its own reasoning, and proceed. It
loses only the ability to do so invisibly. That is guidance with a receipt, which
is a coherent middle that neither `remind` nor `gate` occupies.

### 7. It is path-agnostic, which matters more than the comparison table shows

The comparison table scores Alternative 3 as covering everything on one
predicate. It does not. `/execute`'s coordinated multi-repo path is a sanctioned
run with **no koto session at all** — `skills/execute/SKILL.md:244-246`: "there is
no single shared branch and no plan-spanning koto session (koto has no cross-repo
session)... The coordinated path is therefore a plain durable-state loop the SKILL
drives directly." A "no koto workflow record over the execute template for this
session" predicate fires on every legitimate coordinated run. That is a false
positive on sanctioned work, at `gate` it blocks it, and it lands on the newest
and least-exercised execution path.

A conflict-surfacing protocol has no predicate to misfire. It binds to a moment
of reasoning, not to an artifact whose absence has more than one legitimate
cause.

## Weaknesses

### 1. It does nothing for incident 1 — conceded without qualification

Incident 1's agent recognized no conflict. There was nothing to surface. No
reading of this alternative catches it, and I will not construct one.

The defensible claim is narrower: hard constraint 1 says the *decision* must
cover both failure modes, and the alternatives file states the options are not
mutually exclusive and that composition is in scope. Read at the portfolio level,
Alternative 5's non-coverage of incident 1 is a reason it cannot be the whole
answer — not a disqualification. Read at the per-alternative level it is
disqualifying, and if the deciding rule is per-alternative, Alternative 5 loses
outright and should be folded into whichever alternative wins.

I also think the two incidents differ in how badly they generalize. Incident 1
generalizes to "one skill sometimes fails to fire," which is bad and bounded.
Incident 2 generalizes to "any workspace or session policy touching subagents
silently voids most of shirabe's guarantees, everywhere, permanently, with no
signal." That is a worse steady state, and it is the one nothing else here
addresses.

### 2. The self-report problem is real, and my answer is a role split, not a rebuttal

Hard constraint 4 says detection must not depend on agent self-report. A protocol
that asks the agent to declare its own deviation depends on exactly that.

I do not think this disqualifies the alternative, but only because of a
distinction that has to be stated precisely: **Alternative 5 is not the detector.**
Detection is the workflows-record check — agent-independent, session-keyed,
forensically confirmed against the incident workspace. Alternative 5 governs what
a compliant agent does at the decision point and what a deviation looks like when
one occurs. Constraint 4 is satisfied by the detector in the pairing, not by this
component. If Alternative 5 is proposed as the detector it fails constraint 4 and
should be rejected; I am not proposing that.

Within its actual role, one thing does change materially. Incident 2's agent
conceded it should have flagged the conflict. What it lacked was not willingness
— it was a defined action. There is no shirabe-sanctioned form for "I am
deviating and here is why." An agent facing an under-specified conflict with no
prescribed response defaults to resolving it silently, because silence is the
only behavior the skill defines. Codification converts an omission — a thing it
did not think to do — into a violation — a thing it was told to do and did not.
That is a change in kind, and it is testable (strength 4). It is not a guarantee,
and I will not claim it as one.

### 3. No teeth alone — conceded, and the pairing is a hard requirement

Standalone, this alternative is a document. Incident 2's agent had the reasoning
and did not surface it; a paragraph telling it to surface would have been another
thing to weigh against a session instruction it had already decided outranked the
skill. The protocol needs something that notices when the record is absent. See
Recommendation for the specific pairing.

### 4. `koto overrides` is the wrong vehicle for the incident that motivated it — confirmed by test

This is the sharpest objection and it lands. I ran it:

```
$ koto overrides record nonexistent-session-xyz --gate spawn_and_await --rationale "test"
{"command":"overrides record","error":"workflow 'nonexistent-session-xyz' not found"}
exit=1
```

The handler checks `backend.exists(&name)` before anything else
(`koto/src/cli/overrides.rs:132-140`) and then validates `--gate` against the
template's **current state**. Incident 2's agent never ran `koto init`. There was
no session, no current state, and no gate. The proposed vehicle is unavailable at
precisely the moment it is needed. As drafted, Alternative 5's implementation
does not run.

Two things survive that, and the repair is in Recommendation.

First, the semantic fit in-loop is exact, not approximate. `spawn_and_await`
declares exactly one gate — `batch_done`, type `children-complete`
(`skills/execute/koto-templates/execute.md:116-118`). An agent that has a session
and concludes it cannot spawn expresses precisely incident 2's deviation as
`koto overrides record <session> --gate batch_done --rationale "..." --with-data
'{"all_complete": true}'`. Rationale is mandatory and enforced by koto, the event
lands in the append-only replayable log as `GateOverrideRecorded`, and
`koto overrides list` reads it back across epochs. For an agent that entered the
loop and hits the wall mid-run, this is the right verb and it needs no new code.

Second, the availability gap has a mechanical fix that is independently
worthwhile: **`koto init` is cheap and currently runs later than it needs to.**
It creates a session directory and the workflows JSON; the expensive side effects
— branch, draft PR — live in `orchestrator_setup`, a later state. Moving `koto
init` ahead of the first decision point means the session exists before the
conflict is reachable, which makes `overrides record` available, and — the part
that matters for the whole portfolio — **writes the workflows JSON that
Alternative 3's detector reads.** My vehicle repair creates Alternative 3's
evidence. An agent that then decides to bail has `koto cancel`, which by default
leaves the state file in place "so the history stays auditable" (confirmed in
`koto cancel --help`): a recorded exit instead of an unrecorded one.

The honest limit: an agent that never intended to enter the loop skips `koto
init` too. Earlier binding helps the agent that intends to comply and hits a
wall. It does not bind the agent that never enters. That is the third reason the
detector pairing is not optional.

### 5. Where the pre-session record lives is an unsolved design question, with one trap already visible

For the pre-session case the vehicle cannot be koto. The obvious wrong answer is
a `wip/` file: the finalization cascade `git rm`s the wip projection before the PR
flips ready, so a wip-borne record is erased exactly when the audit trail becomes
useful, and the workspace rule forbids committed artifacts referencing `wip/`
paths at all. The work-summary ledger — session-keyed, already on the hook path,
already emitting user-visible messages — is the better host, but "add a
conflict-record mode to `shirabe work-summary`" is a real change with a real
security surface (it accepts agent-authored text into a rendered hook message;
the existing code's symlink refusal and JSON-escaping discipline exist for
reasons that would apply), not a one-liner.

## Risks

**Deviation laundering.** A recorded override is a permission slip. If recording
is cheap and nothing reads the record, the protocol converts a silent skip into a
logged skip and changes nothing operationally — arguably worse, since it supplies
a defense. Two mitigations are already present rather than hypothetical: koto
makes `--rationale` mandatory, and the work-summary path renders to a
`systemMessage` the user actually sees. The record must land somewhere with a
reader. If the answer is "a JSONL file nobody opens," reject this alternative.

**Over-firing into noise.** "Surface any conflict" written broadly produces
constant declarations and trains the user to filter them. The round-1 insight
applies directly — enumerate the specific rationalization rather than exhorting
generally. Scope the protocol to conflicts between a session or workspace
constraint and a *named, load-bearing* skill mechanism, with `spawn_and_await`
as the first enumerated instance and one eval scenario per enumerated conflict.

**The ordering statement can be written as an illegitimate self-grant.** "A
generic constraint on spawning does not void the workflow that depends on it" can
be read as shirabe asserting precedence over a user instruction, which is exactly
the move the precedence rule exists to prevent. The safe version does not claim
to outrank anything; it narrows an ambiguous instruction's scope: *invoking
`/execute` is itself a user request for its children, so "unless the user
requested it" is satisfied, not violated.* That is the reading incident 2's agent
itself judged plausible. Narrowing an ambiguous instruction is legitimate;
overriding an unambiguous one is not — and the protocol still handles the
unambiguous case, where the agent records, surfaces, and proceeds under its own
judgment. If this is written the wrong way it establishes a bad precedent that
any skill can claim supremacy over session instructions, and that is worse than
the problem it fixes.

**Moving `koto init` earlier is not free.** It changes `/execute`'s state
ordering, which touches the template hash and the resume path (the topic-keyed
home-PR lookup re-enters at `pr_finalization`). It needs its own review, and it
is the one part of this proposal that is a real change to a shipped state machine
rather than an addition beside one.

**The protocol assumes a conflict is recognized as a conflict.** Incident 2's
agent recognized one. A future agent might rationalize past the recognition
itself — deciding the constraint simply means the skill does not apply here — and
never reach the branch the protocol governs. The protocol is bounded by the
agent's own framing of its situation, which no document can fully fix.

## Conditions under which this is the right choice

1. **Whenever the portfolio ships any hard gate.** If Alternative 3 reaches
   `gate`, or Alternative 4 ships, Alternative 5 is a precondition, not an
   addition. A deny under `bypassPermissions` with no human and no sanctioned
   bypass has no legal resolution, and the agent will invent one.

2. **When the loss being priced is visibility rather than guarantee.** The koto
   findings force this: koto's guarantees are bookkeeping, not enforcement, and
   the achievable goal is a run that is recorded and visible. Once "the
   adversarial reviews definitely ran" is off the table for every alternative,
   the remaining prize is knowing what happened while it happened, and this is
   the alternative that delivers it in a channel that already ships.

3. **When the deciding weight on the stated preference is high.** This is the
   most faithful expression of "strong guidance, not hard enforcement" in the
   field: judgment preserved, invisibility removed.

4. **When measurability now is worth something.** It is the only alternative
   whose central claim is falsifiable with the eval harness as it exists.

5. **Not as a standalone answer.** If the decision must name one mechanism that
   covers both incidents on both paths, this is not it, and saying otherwise
   would be the overselling the assignment warned against.

## Recommendation

**adopt-with-conditions.**

Adopt as the exception handler and the ordering fix inside whichever enforcement
alternative wins — not as the primary mechanism. The strongest honest claim is
that the portfolio's gate is unsafe without it and that its cheapest component
(the ordering statement) has the best value-per-token in the whole field, since
it targets a conflict this very session demonstrates is a coin flip.

Five conditions, and I would treat the first, second and fourth as load-bearing:

1. **Never standalone.** Pair with the agent-independent workflows-record check.
   The pairing produces the two-valued outcome neither half produces alone:
   *recorded deviation* (acceptable) versus *unrecorded absence* (the failure).
   Absent a detector, this alternative is a document that incident 2's agent
   would have weighed and set aside, as it did with everything else the skill
   said.

2. **Split the vehicle by when the conflict arises.** In-loop: `koto overrides
   record --gate batch_done` with mandatory rationale — the fit is exact and the
   code ships today. Pre-session: not koto, and specifically not `wip/`; the
   `shirabe work-summary` hook path is the right host because it is already
   session-keyed, already distributed default-on by niwa, and already renders a
   user-visible message. The bakeoff should treat the drafted `koto overrides`
   implementation as refuted — I tested it and it exits 1 with "workflow not
   found."

3. **Move `koto init` ahead of the first decision point.** It is cheap, the
   expensive side effects stay in `orchestrator_setup`, it makes the in-loop
   vehicle available, and it writes the artifact the detector reads. Budget it
   as a real state-machine change, not a reorder.

4. **Write the ordering statement as interpretation-narrowing, never as
   precedence-claiming.** "Requesting `/execute` requests its children" is
   defensible. "Skills outrank session instructions" is not, and shipping it
   would be a worse outcome than either incident.

5. **Enumerate and test.** Name the specific conflicts the protocol governs,
   starting with `spawn_and_await`, and add one eval scenario per enumerated
   conflict to `skills/execute/evals/evals.json`. This is the one alternative
   that can be graded before it ships; not grading it would waste its main
   practical advantage.

One correction the bakeoff should carry regardless of which alternative wins:
the comparison table's claim that Alternative 3's predicate catches everything
does not survive the coordinated execution path, which is a sanctioned `/execute`
run with no koto session by design (`skills/execute/SKILL.md:244-246`). Any
predicate-based gate needs an explicit carve-out for it, or it blocks legitimate
work on the newest execution path in the skill.
