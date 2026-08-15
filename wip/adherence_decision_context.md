# Decision Context: Which mechanism should make shirabe's sanctioned workflow the path an agent actually takes?

## Question

Given two field incidents -- one where the skill never fired, one where it fired
and the agent silently opted out of the koto loop -- what mechanism should
shirabe and niwa adopt so that plan-scale work runs under the sanctioned
workflow, and how hard should it push?

## Complexity

critical

Contested on three independent axes: the user's stated preference (guidance)
points away from what the evidence says would actually work (gates); shirabe's
own shipped doctrine argues against the mechanism class being proposed; and the
org-owner configuration requirement collides with a security-motivated design
decision niwa has already made in the opposite direction.

## Constraints

**Hard constraints (violating these disqualifies an alternative):**

1. **Must cover both failure modes.** Incident 1 (skill never fired) and
   incident 2 (skill fired, koto loop skipped). A mechanism that keys on "was
   the skill invoked" passes incident 2 and is disqualified.
2. **`ask` is unusable.** Dispatched and headless sessions run under
   `bypassPermissions` with no human; an `ask` response stalls the turn.
   Rejected on these grounds already in `DESIGN-pr-template-gate.md:214`.
3. **Must cover the dispatch path.** Agents launched by `niwa dispatch` are half
   the requirement. Note SessionStart does not fire for subagents, and the
   superpowers precedent explicitly exempts dispatched agents via
   `<SUBAGENT-STOP>`.
4. **Must not depend on agent self-report.** Both incidents surfaced only because
   the user asked, and in the second the agent had let an inaccurate earlier
   answer stand.
5. **A PreToolUse hook matching every Bash call must fail open.** niwa's own
   source documents this: a non-zero exit blocks the call, so a stale binary
   would brick every session (`materialize.go:592-603`).

**Soft constraints (weigh, do not disqualify):**

6. User prefers strong guidance over hard enforcement, while explicitly asking
   for the full spectrum to be mapped.
7. Ambition is a general mechanism, not a patch for the acute bug.
8. Org owners should be able to configure it.
9. Every dispatch pays the token cost of whatever a prompt-prefix mandate says.

## Known Options

Drawn from round-1 research. Not mutually exclusive; the decision includes
whether to compose them and in what order.

- **A. Prose and salience stack.** Repair `execute`'s description (it is an
  architecture inventory, not a trigger); build trigger evals via
  `skill-creator`'s `run_loop`; ship a shirabe SessionStart hook injecting an
  anti-rationalization table; add a workflow slot to the `/dispatch` brief
  template; prepend a mandate at `dispatch.go:421`.
- **B. Path-independent outcome gating.** Shirabe's shipped doctrine, applied
  twice already. Do not make the skill unskippable; make the loss checkable
  regardless of which path produced the work.
- **C. Graded workspace policy with a koto-session predicate.** One condition --
  "a plan is in play and no koto session is bound to it" -- evaluated at a level
  the org owner sets: `off` / `advertise` / `remind` (UserPromptSubmit) / `gate`
  (PreToolUse deny). Declared in `[claude.skills]`, distributed by niwa,
  decided by a `shirabe` subcommand.
- **D. Restricted-tool orchestrator.** An agent definition without Edit/Write, so
  the orchestrator physically cannot implement and its only route to code is
  spawning children. Converts a should into a cannot. Formalizes an invariant
  `DESIGN-execute-skill.md` already asserts.
- **E. Close the payload/submission seam.** `plan-to-tasks.sh` emits a koto
  payload; submitting it is a separate skippable step that looks like progress
  and leaves no trace. Make production and registration atomic.
- **F. Precedence-conflict protocol.** Make an agent that concludes a session
  constraint forbids a skill's mechanism surface the conflict rather than
  resolve it silently -- plausibly by routing it through `koto overrides`, a
  shipped verb for recording a deliberate gate bypass.

## Background

### The two incidents

**Incident 1.** An agent told to execute a plan never invoked `shirabe:execute`.
It built its own task list and hand-implemented 22 plan outlines in dependency
order. No koto session, no state machine, no per-issue spawn, no review gates.
Surfaced only when the user asked "are you using koto for anything?", at which
point the agent named precisely what it should have done.

**Incident 2.** An agent *did* invoke `/execute`. It ran the Step 1 preflight,
confirmed a defect in the referenced issue, and ran `plan-to-tasks.sh`, producing
a valid koto payload with all six `waits_on` edges. It then used that payload
only to verify the dependency graph, never submitted it, and implemented all six
issues inline. Its stated reason: the session instruction "Do not call the
AgentTool unless the user requested it" conflicted with `spawn_and_await`, which
spawns one `/work-on` child per issue, and it resolved the conflict against the
skill. Under the documented precedence rule -- user and session instructions
outrank skills -- it was not wrong by the letter.

Both produced the identical loss: no visibility, no guarantee the adversarial
reviews and validation steps ran.

### What round-1 research established

**The discoverability theory is dead.** A live probe on Claude Code v2.1.233
confirmed bare `/execute` resolves to `shirabe:execute`; plugin skills get a bare
alias unless another command claims the name, and nothing else claims `execute`.
Shirabe needs no `commands/` directory.

**Descriptions have a measurable ceiling.** `skill-creator/SKILL.md:396-400`
states first-party that "Claude only consults skills for tasks it can't easily
handle on its own" -- a filter upstream of description matching. Executing a plan
reads as directly handleable. The decisive evidence is `work-on`, whose
description is near-ideal (claims PLAN docs explicitly, lists eight trigger
verbs, says "at any size, from a single issue to a whole plan") and which also
failed to fire. `execute`'s description is separately defective -- ~40 words of
internal vocabulary, no trigger phrases -- and worth repairing regardless.

**Shirabe's eval suite cannot see this failure.** All 18 suites use
`evals.json`, and every prompt begins with an explicit slash command. Strong
evidence the skills behave correctly once invoked; zero evidence about whether
they get invoked.

**Shirabe has never attempted this, and its doctrine cuts both ways.**
"Parent-skill conformance" is a SKILL.md authoring checklist; the "autonomy
mandate" governs not-stopping once already running. The gap was named in
`BRIEF-pr-template-gate.md` and scoped out as "an orthogonal workflow-authoring
change." Two positions must be answered: outcome-gating is the shipped doctrine
(twice), and `DESIGN-execute-skill.md:230` argues a mandate is load-bearing "for
/execute specifically and not bolted onto every skill."

Three transferable insights from the same body of work: bind at every tick rather
than only at entry (`DESIGN-execute-skill.md:227`, shirabe's own conclusion that
entry-time instruction decays); enumerate the specific rationalization rather
than exhorting generally; and `P5: Strictness tracks blast radius`
(`references/workflow-principles.md:87`) already licenses shipping as a notice
and promoting to a gate once the corpus conforms.

**Distribution is solved.** niwa already injects a shirabe-specific PreToolUse
allow/deny gate (`shirabe pr-body-hook`) plus three work-summary hooks into every
instance with the shirabe plugin, by default, gated on a `shirabePluginName`
const in niwa's source, with a `[claude] pr_body_hook = false` off switch. The
established division of labor is niwa declares and distributes, shirabe decides.
The whole spectrum maps onto parts already in the binary.

**The dispatch mandate is one line.** `niwa dispatch` composes `prefix + body`
with niwa-authored prefix text already carrying the keep-alive instruction;
`dispatch.go:421` is the injection point, prefix-first ordering is test-pinned,
and there is no size budget. Separately, the `/dispatch` brief template (embedded
in the niwa binary) lists Goal, Context, Pointers, Acceptance criteria, Out of
scope, and the work-in-flight block -- and has **no slot for which workflow the
worker must use**, though step 1a spends 23 lines making the reporting block
non-negotiable.

**The gate condition is computable.** Koto session state is append-only JSONL at
`~/.koto/sessions/<name>/koto-<name>.state.jsonl`; the header names the template
and the init event carries `PLAN_DOC`. So:

```bash
grep -l "\"PLAN_DOC\":\"docs/plans/PLAN-<slug>.md\"" \
     ~/.koto/sessions/*/koto-*.state.jsonl 2>/dev/null
```

Verified live against 32 plan-bound sessions, and it returns nothing for incident
2's plan even though that agent ran the scripts and produced a valid payload.
The same predicate can fire at Stop (report), UserPromptSubmit (remind), or
PreToolUse (gate).

**Koto already models deliberate deviation.** `koto overrides` is a shipped verb
for recording a gate override. `koto dashboard` already provides the visibility
the user lost -- nothing appeared in it because nothing was registered.

### The disqualifying test

The agent already knew. In both incidents it could name the correct path when
asked. Any mechanism whose only effect is to supply knowledge cannot fix a
failure whose cause is not missing knowledge. Applying that test, only two
catalogued mechanisms would have caught either incident: a restricted-tool
orchestrator (dispatch path only) and a PreToolUse deny gate (both paths, now
that the condition is known computable).

### Open tension the decision must resolve

The user asked for an org-owner configuration option. niwa's `[workspace]` table
is deliberately overlay-proof -- `OverlayWorkspaceTombstone` exists solely to warn
that overlay `[workspace]` does nothing, and the stated reason (`config.go:312-320`)
is to keep "a contributor's first run un-alterable by a configuration layer they
cannot read." A skill mandate changes what an agent does for a contributor who
cannot read the layer imposing it. Placement under `[claude]` is overlay-reachable
and would satisfy the request; placement under `[workspace]` would not. This is a
values question niwa has answered once already, in the opposite direction.
