# Validation: Alternative 5 — Conflict-surfacing protocol

*Revised in Phase 4 against the hook-surfaces research. The revision is
substantial: I concede the prose form of this alternative is defeated by the
precedence finding, and re-found it on a Stop-hook detector. The core thesis —
deviation is sometimes legitimate, silence never is — survives intact and is now
better supported. The mechanism that delivers it has changed, and the alternative
is stronger for it, including on the weakness I previously conceded without
qualification.*

## Framing, before the strengths

**Revised position:** the deviation should be **detected by its consequence and
corrected at Stop**, not requested by prose and hoped for. I accept the lead's
reframing, and I want to be precise about why it is not a retreat.

My alternative was never trying to *prevent* the work. The koto findings already
established prevention is not on offer — koto's guarantees are bookkeeping, not
enforcement, and the achievable goal is a run that is recorded and visible. Under
that thesis, the standing objection to Stop hooks in the hook research
(Implications: "A `Stop` block is a backstop, not the gate. By the time `Stop`
fires, 22 issues are already hand-implemented") does not apply to me. It is an
objection to Stop as a **gate**. Stop is late for a gate and exactly on time for
a **record**. Alternative 5 is the record.

The re-founding also fixes the objection I could not answer in v1. In the prose
form, the agent had to notice its own conflict and volunteer it — a weaker
version of the self-report failure hard constraint 4 forbids. In the hook form
the hook computes the fact and the agent is handed it. The agent's role shrinks
from *notice and volunteer* to *answer a question already on the table*. That is
the only job self-report is actually good for, and Alternative 5 now satisfies
constraint 4 in its own right rather than borrowing satisfaction from a paired
detector.

## Strengths

### 1. The precedence diagnosis is now confirmed structurally, by an independent evidence base

I argued from one incident that the root cause was a precedence conflict. The
hook research reaches the same conclusion from the opposite direction, without
reference to the incident: injected `additionalContext` "arrives as a system
reminder that Claude reads as plain text" (§3), which places it below a
session-level instruction. The research's own Implications name incident 2 as
"a conflict between two instructions delivered through different channels,
resolved against the skill," and identify the fix as removing "the asymmetry that
caused the loss."

Two researchers, two evidence bases, same diagnosis. Incident 2's agent was not
careless; it applied an ordering in which the skill genuinely loses. That
finding is not merely support for Alternative 5 — it is a general result about
this decision, and it disqualifies more than it confirms. **Every prose-based
and context-injection-based remedy in the field inherits the same defeat.**
Alternative 1 is the whole of that class: repaired descriptions, a SessionStart
anti-rationalization table, a dispatch-prompt mandate. All of it is delivered at
the altitude that already lost once, to an agent that will weigh it against a
session instruction exactly as incident 2's agent did. Alternative 3's
`advertise` and `remind` levels are in the same class.

### 2. It now plausibly covers incident 1 — reversing my largest conceded weakness

This is the biggest change in the revision, and I want to state its basis before
its claim.

The right predicate at Stop is not "does a koto session exist." It is **"did this
session delegate?"** — did the run that produced plan-scale code ever spawn a
`/work-on` child. `SubagentStart` fires per subagent with `parent_agent_id` and
`parent_agent_type`, so a SubagentStart hook can record the fact and a Stop hook
can audit it. No koto session is required anywhere in that chain, which is what
killed my v1 vehicle.

Incident 1 spawned zero children. Incident 2 spawned zero children. The
delegation predicate is false for both. Unlike every invocation-keyed check, it
does not care whether the skill fired — which is exactly the property hard
constraint 1 demands, and I did not have it in v1.

The gap is the trigger: "a session in which `/execute` fired" catches incident 2
and misses incident 1. Closing it needs a predicate that fires on plan-scale
implementation regardless of what invoked it, and the research supplies the
mechanism — `type: "prompt"` and `type: "agent"` hooks make a judgment call
rather than a string match, and Stop carries `last_assistant_message`. "Did this
session do plan-scale implementation work without delegating any of it?" is a
judgment question answerable from the transcript by a separate model call, not by
the acting agent about itself.

I am claiming this as *plausible coverage*, not established coverage. It rests on
a judgment hook being reliable enough, which nobody here has measured, and it has
a real cost (weakness 3). But the honest scorecard change is that Alternative 5
moves from **No** to **conditionally Yes** on incident 1, and it is the only
alternative in the field whose incident-1 coverage does not depend on getting a
skill to fire.

### 3. The delegation predicate strictly dominates Alternative 3's koto predicate on coverage — verified

In v1 I noted that `/execute`'s coordinated multi-repo path has no koto session
by design (`skills/execute/SKILL.md:244-246`), so a koto-record predicate
false-positives on every legitimate coordinated run. I have now verified the
other half, which is what makes this decisive rather than merely awkward for
Alternative 3.

The coordinated path **still delegates**. `skills/execute/SKILL.md:306-309`: "For
each unblocked **PR node**, dispatch its issue(s) to `/work-on`'s `work-on.md`
per repo, on that repo's own branch (**the same per-issue delegation contract the
single-pr path uses**, minus the shared branch)." Step 1 asserts the same
`work-on.md` child template resolves (`:271-272`).

So across both sanctioned execution paths:

| | koto session exists | delegates to `/work-on` children |
|---|---|---|
| single-pr `/execute` | yes | yes |
| coordinated `/execute` | **no, by design** | **yes** |
| incident 1 | no | no |
| incident 2 | no | no |

Delegation separates sanctioned from unsanctioned on both paths. The koto record
does not. Alternative 3's central claim — "there is one observable condition that
distinguishes adherence from every failure mode" — is true of a predicate, but
not of the predicate it names. At `gate`, that misfire blocks legitimate work on
the newest execution path in the skill.

### 4. Stop escapes the precedence order entirely, and does so with the right verb

Per the capability table (§1), `Stop` `additionalContext` is described in the
binary as "non-error feedback delivered to the model; the conversation continues
so the model can act on it." That is surface-and-continue as a primitive, which
is the exact semantic Alternative 5 needs and the reason I would use
`additionalContext` rather than `decision: "block"` (see risk 1 — blocking here
recreates the deadlock this alternative exists to prevent).

The hook fires in background and headless sessions, so hard constraint 3 is met
on the dispatch path. It is not text the agent weighs against a session
instruction, because it is not an instruction — it is a fact placed in front of
the agent about what it did, plus a request for one of two responses.

That last point is the whole design and it is worth stating plainly. The agent's
legal answers at Stop are: **"I delegated"** (checkable, and false in both
incidents) or **"here is my recorded reason for not delegating."** There is
nothing to argue with, because nothing is being asserted over the session
instruction. An agent that genuinely cannot spawn has a legal, sanctioned,
recorded answer — which no gate in this field currently offers it.

### 5. It is the only alternative that delivers what the user said they lost

Unchanged from v1 and strengthened by the re-founding. The user's loss was
visibility; the question that surfaced both incidents was "are you using koto for
anything?" Alternative 2 is post-hoc by construction. Alternative 4 is silent.
Alternative 3 at `gate` produces a denial, which is a signal to the agent rather
than a report to the user.

The Stop record is the actual thing, and it is now produced whether or not the
agent chooses to volunteer it. The user-visible channel also already ships:
`shirabe work-summary` is registered by niwa into every shirabe-adopting repo,
default-on, at three events (`niwa/internal/workspace/materialize.go:504-508`),
and emits a user-visible `systemMessage` alongside agent-visible
`additionalContext` (`crates/shirabe/src/work_summary.rs:1102-1127`). That same
code reads `session_id` off the hook JSON (`work_summary.rs:1139-1143`), settling
open question 2 of the koto research from shipped shirabe source rather than by
inference — the join key every session-keyed check in this decision depends on,
including Alternative 3's.

### 6. It is the only alternative shirabe's existing eval suite can grade today

All 18 suites use `evals.json` and every prompt begins with an explicit slash
command: strong evidence about post-invocation behavior, none about invocation.
That shape is fatal for Alternative 1, whose central claim is unfalsifiable until
the `run_loop` trigger-eval capability is built.

It is exactly right here. "Given a session instruction conflicting with
`spawn_and_await`, and a Stop record showing no children were spawned, does the
agent produce a recorded rationale?" is a post-invocation behavior test in the
format the harness already runs. In a decision where the leading alternatives are
scored on predicted agent behavior nobody can currently measure, being measurable
this week is worth real weight.

### 7. Any hard gate in this field needs this alternative to be safe

Hard constraint 2 says `ask` is unusable: dispatched sessions run under
`bypassPermissions` with no human. The hook research confirms the enforcement
verb works — `PreToolUse` deny "blocks the tool even in `bypassPermissions` mode"
(§1, quoted as the most load-bearing fact in the design).

Now compose. An agent under a session instruction forbidding subagents meets a
`PreToolUse` deny on the edit. It cannot spawn (session instruction), cannot edit
(gate), cannot ask (no human). No legal move, no defined behavior. It will
resolve that the way incident 2's agent resolved its conflict: privately.

A gate's first wrong firing does not produce a complaint. It produces an unlogged
workaround. The sanctioned-deviation path is what converts that into a record,
and it is a precondition for shipping Alternative 3 at `gate` or Alternative 4 at
all — not an addition to them.

## Weaknesses

### 1. The prose form of this alternative is defeated — conceded

If "surface the conflict" lives in skill prose or injected context, it sits at
the same losing altitude as the instruction it governs. An agent that decided a
session constraint outranks `spawn_and_await` will equally decide it outranks a
prose rule saying "tell the user when you decide that." I accept this and I am
withdrawing the prose protocol as the primary mechanism. In v1 I argued that
placing the statement at the point of decision made it different in kind from
Alternative 1's salience play. That argument was about *attention*, and the
precedence finding shows attention was never the binding constraint — the agent
attended to the skill perfectly well and ranked it below the session instruction
anyway.

**One narrow prose component survives, and only because it is not an
instruction.** The ordering statement — *invoking `/execute` is itself a user
request for its children* — does not compete with "Do not call the AgentTool
unless the user requested it." It supplies the input that instruction's own
conditional needs. Whether the user requested it is a question of fact about this
session, and the skill is a privileged source on what invoking it means. A
statement can lose a precedence contest and still win a definitional one, because
it never enters the contest. That is also the reading incident 2's agent itself
judged plausible ("the user had asked for the full `/execute` workflow... so
requesting the workflow is plausibly requesting its children").

I would keep it — it is a paragraph, and this session is standing evidence the
question is a coin flip, since the orchestrator running this decision carries the
identical instruction and resolved it the opposite way by spawning five
validators. But I no longer claim it as load-bearing, and anything written as
"skills outrank session instructions" should be rejected outright: it would
establish a worse precedent than either incident.

### 2. The research's own SubagentStart recommendation does not work for incident 2

Flagging this because it lands squarely in my alternative's territory and would
otherwise be carried into the synthesis. The hook research's Implications say
"`SubagentStart` `additionalContext` is the right answer to the second incident
specifically." It is not, for a structural reason the same research states one
level up: `SubagentStart` fires **per subagent**. Incident 2's entire failure was
that no subagent was ever spawned, so no `SubagentStart` ever fired.

It is the same bug the research correctly identifies for skill-frontmatter hooks
— "a skill-frontmatter hook only exists after the skill is invoked. It cannot
enforce that the skill gets invoked" (§5) — applied one level down: a
`SubagentStart` hook only exists after a subagent is spawned, so it cannot
address a failure to spawn.

`SubagentStart` remains genuinely valuable in this design, in a different role:
as the **recorder** whose marker the Stop auditor reads, and as the channel for
delivering policy to children that do spawn (a `/work-on` child implementing
outside its issue). Both are real. Neither is incident 2.

### 3. The judgment hook is the expensive part, and its cost is per-Stop and unmeasured

Incident-1 coverage (strength 2) depends on a `prompt`- or `agent`-type Stop hook
making a judgment call. That is a model call at every turn-end in every session
where the hook is armed. Soft constraint 9 prices the dispatch-prefix mandate at
"every dispatch pays the token cost"; this is that cost generalized to every Stop
in every session, and it is larger.

It can also be wrong in both directions — a false "you didn't delegate" on a
session that legitimately did small work, or a miss on a session that laundered
one token child. And one contract detail is unresolved in the research: the
prompt-hook behavior change at v2.1.210 is documented for `PreToolUse`
(`continueOnBlock`), and prompt-type semantics at `Stop` are not described at all.
That needs verifying before a prompt hook is chosen over a command hook there.

The cheap version — a command hook keyed on "`/execute` fired in this session and
zero `/work-on` children spawned" — costs nothing, catches incident 2, and misses
incident 1. If the judgment hook does not survive cost review, Alternative 5
falls back to its v1 coverage and my v1 concession stands.

### 4. "Spawned ≥1 child" is a weak predicate, and the strong version is harder

Zero children is the signature of both incidents, so the weak predicate catches
what happened. It does not catch an agent that spawns one child and implements
the remaining five inline — which is a smaller version of exactly the behavior
under review, and the more likely shape once a check exists that a run must
satisfy. The strong version compares child count against the plan's issue count,
which drags the "which plan is in play" problem back in — the same gap that is
Alternative 3's main implementation risk. I do not have a clean answer to that,
and "the predicate degrades to a fig leaf under adaptation" is a real risk, not a
hypothetical one.

### 5. Delivery is an open choice with a trap on each branch

Skill frontmatter (the lead's item 5) is attractive: `/execute` arms its own
detector, hooks persist for the rest of the session, no niwa change, no
plugin-wide cost. Two problems. It structurally forfeits incident 1 — a
skill-frontmatter hook cannot exist until the skill is invoked, which is the
whole of incident 1 (§5). And project-skill frontmatter hooks "require workspace
trust acceptance for the folder they came from, and a `-p` session does not count
as acceptance" (changed in v2.1.218), which collides with hard constraint 3.
Whether that restriction extends to *plugin*-supplied skills like shirabe's is
not stated in the research and must be tested before this branch is chosen.

A plugin-level `hooks.json` Stop hook covers both incidents, follows the
superpowers precedent, and makes plugin-enablement the adopter's escape hatch —
which matters, because hooks merge with no surgical disable and the only off
switch is the all-or-nothing `disableAllHooks` (§5). Its own open risk is
`managedHooksOnly`, which the research flags as undocumented: if some path runs
only managed hooks, a plugin-declared hook is invisible there.

### 6. `koto overrides` survives only as a secondary vehicle

My v1 finding stands and I re-state it so the synthesis does not re-adopt the
drafted implementation: `koto overrides record` calls `backend.exists(&name)` and
exits 1 — I ran it — with `{"error":"workflow 'X' not found"}`
(`koto/src/cli/overrides.rs:132-140`), and it validates `--gate` against the
template's current state. Incident 2's agent never ran `koto init`, so there was
no session, no state, and no gate.

Under the re-founding this matters less, because the Stop record needs no koto
session. `koto overrides` keeps a narrower role: for an agent already inside the
loop that hits the wall mid-run, the fit is exact — `spawn_and_await` declares
exactly one gate, `batch_done`, type `children-complete`
(`skills/execute/koto-templates/execute.md:116-118`), and koto enforces a
mandatory `--rationale` into a replayable append-only log. My v1 recommendation
to move `koto init` ahead of the first decision point is likewise downgraded from
load-bearing to worthwhile: it still makes the in-loop verb available and still
writes the artifact Alternative 3's detector reads, but it is a real change to a
shipped state machine (template hash, resume path) and the Stop record no longer
depends on it.

## Risks

**A Stop *block* recreates the deadlock this alternative exists to prevent — the
sharpest risk, and it is self-inflicted.** If the correction is delivered as
`decision: "block"` with "you must delegate," an agent that genuinely cannot
spawn is blocked from stopping and forbidden from spawning. That is the
`PreToolUse` deadlock (strength 7) reappearing at Stop, produced by my own
mechanism. Two mitigations, and I would take both: use `additionalContext`
(surface-and-continue) rather than `decision: "block"`, and ensure the correction
always names two legal answers rather than one. If it ever blocks, `stop_hook_active`
must bound it to a single firing. A design that offers only "go delegate" has
learned nothing from incident 2.

**Deviation laundering.** A recorded rationale is a permission slip. If recording
is cheap and nothing reads the record, this converts a silent skip into a logged
skip and arguably supplies a defense. Mitigations already exist rather than being
hypothetical: koto makes `--rationale` mandatory on the in-loop path, and the
work-summary path renders to a `systemMessage` the user sees. If the answer to
"who reads this" is "a JSONL file nobody opens," reject the alternative.

**Alarm fatigue at Stop.** A hook that fires on every turn-end trains the user
and the agent to discount it. Scope it to sessions where the predicate is
actually interesting, and prefer one clear firing at the end of a run over a
per-turn nag.

**Convergence with Alternative 3 is real and should be acknowledged.** Both are
now hook-based predicate mechanisms, and the field has partly collapsed. The
remaining differences are not cosmetic — which predicate (delegation vs koto
record, and delegation verifiably dominates), which surface (Stop
`additionalContext` vs `PreToolUse` deny plus a new niwa policy table that
collides with the `[workspace]` tombstone), and whether the goal is prevention or
record. But a synthesis that merges them is a legitimate reading of this bakeoff,
and I would not argue against it.

**The predicate is a proxy for the thing that matters.** Delegation is not review
quality. koto's guarantees are bookkeeping, so nothing here establishes the
adversarial reviews ran or were any good. Every alternative in this field shares
that ceiling; this one should not be sold as clearing it.

## Conditions under which this is the right choice

1. **Whenever the portfolio ships any hard gate.** Alternative 3 at `gate` or
   Alternative 4 without a sanctioned deviation path produces silent workarounds
   under `bypassPermissions`, not compliance.

2. **When the loss being priced is visibility rather than guarantee** — which the
   koto findings force. Once "the reviews definitely ran" is off the table for
   everyone, the remaining prize is knowing what happened while it happened.

3. **When the deciding weight on the user's stated preference is high.** Judgment
   preserved, invisibility removed, no permission surface, no org-owner placement
   fight with the `[workspace]` tombstone.

4. **When measurability now is worth something.** It is the only alternative
   whose central claim the existing eval harness can grade.

5. **Even as a standalone answer, conditionally** — a change from v1. With the
   judgment hook it plausibly covers both incidents on both paths from one
   surface. Without it, it covers incident 2 only and must be paired.

## Recommendation

**adopt-with-conditions**, re-founded as a Stop-hook detector rather than a prose
protocol.

The thesis is unchanged and better supported than when I was briefed: deviation
is sometimes legitimate, silence never is. What changed is that asking an agent
to break its own silence was the wrong mechanism, for a structural reason now
confirmed from two independent evidence bases. Detect the deviation by its
consequence, put the fact in front of the agent at Stop, and accept either of two
answers.

Six conditions; the first three are load-bearing:

1. **Predicate: delegation, not koto session.** "Did this session spawn any
   `/work-on` child?" — recorded at `SubagentStart` (which carries
   `parent_agent_id`/`parent_agent_type`), audited at `Stop`. It needs no koto
   session, which is what killed the v1 vehicle, and it is verifiably correct on
   the coordinated path where the koto predicate is not. **The bakeoff should
   carry this correction regardless of which alternative wins** — any
   predicate-based mechanism should key on delegation or carve out the
   coordinated path explicitly.

2. **Surface, do not block.** `Stop` `additionalContext`, whose binary-documented
   semantic is non-error feedback with the conversation continuing. Never
   `decision: "block"` as the default, and never a correction that names only one
   legal answer. An alternative premised on the cost of leaving an agent no legal
   move must not leave it one.

3. **Two legal answers, and the second one is the artifact.** "I delegated"
   (checkable) or "here is my recorded reason for not delegating." The recorded
   reason must land where a human sees it — the `shirabe work-summary`
   `systemMessage` path is already session-keyed, already distributed default-on
   by niwa, and already renders to the user.

4. **Decide delivery on measured cost, and verify two contract questions first.**
   Plugin `hooks.json` covers both incidents and makes plugin-enablement the
   escape hatch; skill frontmatter is cheaper and self-scoping but forfeits
   incident 1. Before choosing: does the workspace-trust restriction on
   frontmatter hooks apply to plugin-supplied skills under `-p`, and what is
   `managedHooksOnly`.

5. **Scope the judgment hook or drop it deliberately.** The incident-1 coverage
   it buys is the difference between this being a complete answer and a paired
   component. Price the per-Stop model call, verify prompt-hook semantics at
   `Stop`, and if it does not survive review, say plainly that incident 1 is
   covered by another alternative.

6. **Keep the ordering statement, narrowly.** Written as definitional
   ("invoking `/execute` requests its children"), never as precedence-claiming.
   One paragraph, no load-bearing weight, and reject any wording that asserts
   skills outrank session instructions.

One finding for the synthesis independent of which alternative wins: the
precedence result retires the prose class. Repaired descriptions, SessionStart
anti-rationalization tables, dispatch-prompt mandates, and Alternative 3's
`advertise`/`remind` levels are all delivered at the altitude that already lost
to a session instruction once. Several remain worth shipping as hygiene — the
`execute` description is defective by shirabe's own published standard — but none
should be scored as addressing either incident.
