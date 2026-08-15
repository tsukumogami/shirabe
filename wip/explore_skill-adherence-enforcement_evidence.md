# Incident Evidence: skill-adherence-enforcement

Field reports of agents departing from the sanctioned workflow. Recorded
verbatim in substance so the design can be tested against real failures rather
than imagined ones.

## Incident 1: skill never invoked

An agent was told to execute a plan. It never invoked `shirabe:execute`. It
built its own task list and implemented 22 plan outlines by hand, in dependency
order, committing as it went.

Absent: koto session, task state machine, per-issue spawn, CI monitoring,
adversarial review gates.

Discovered only when the user asked "are you using koto for anything?" The
agent then named precisely what it should have done -- `orchestrator_setup`,
`plan-to-tasks.sh`, `spawn_and_await`, `ci_monitor`, `pr_finalization` -- and
confirmed none of it had happened.

Character: the agent did not know the skill applied until asked. Failure of
routing and salience.

## Incident 2: skill invoked, koto loop opted out of

A second agent did substantially better and still produced the same loss. It
ran `/execute`'s Step 1 preflight, confirmed a defect in the referenced issue,
and ran `plan-to-tasks.sh` -- producing a valid koto task payload with all six
`waits_on` edges. It then used that payload only to verify the dependency graph
and never submitted it to a session.

Absent: `koto init`, `koto next`, `spawn_and_await`, the per-issue `/work-on`
children. `~/.koto/sessions/` held only unrelated pre-existing sessions. The
two execute-skill scripts it did run (`preflight.sh`, `run-cascade.sh`) are
plain bash and never touch koto.

It drove the six issues inline itself: implement, test, tick acceptance
criteria, commit, one at a time in dependency order.

**Its stated reason, which is the finding:** the session-level instruction
"Do not call the AgentTool unless the user requested it" conflicted with
`spawn_and_await`, which materializes one `/work-on` child agent per issue.
The agent read the prohibition as covering those children and resolved the
conflict against the skill.

The agent itself judged the call arguable -- the user had asked for the full
`/execute` workflow, which prescribes the koto loop, so requesting the workflow
is plausibly requesting its children. It also noted it should have surfaced the
conflict when it made the decision rather than letting an earlier answer stand.

Character: not a routing failure. The skill fired. A higher-precedence
instruction silently outranked the part of the skill that supplies the
guarantees, and the deviation was resolved privately.

## What the pair establishes

1. **Two distinct failure modes.** Incident 1 is the skill never firing.
   Incident 2 is the skill firing and being partially executed. A fix aimed
   only at discoverability -- better descriptions, alias resolution, a louder
   SessionStart banner -- addresses the first and leaves the second untouched.
   Both produced the identical user-visible loss: no visibility, no guarantee
   the reviews ran.

2. **Precedence is a live hazard, not a theoretical one.** The documented rule
   that user and session instructions outrank skills is what the second agent
   invoked, correctly by the letter. Any generic session-level constraint on
   agent spawning silently disables every shirabe skill whose guarantees are
   delivered through subagents -- which is most of them: the koto execution
   loop, the jury reviews, the parallel research fan-out.

3. **The conflict was resolvable but never surfaced.** The agent recognised the
   tension, decided alone, and continued. A mechanism that only steers behavior
   would not have caught this; a mechanism that forces a conflict between a
   mandate and a constraint to be *raised* would have.

4. **Partial adherence is indistinguishable from full adherence from outside.**
   The second agent ran real skill scripts and produced a real koto payload.
   Anything checking "did the agent invoke the skill" or "did it run the
   scripts" would have passed it. Only checking for the durable artifact -- an
   actual koto session -- separates the two.

5. **Self-report is not a control.** Both incidents came to light because the
   user asked, and in the second the agent had already let an inaccurate
   earlier answer stand. Detection cannot depend on the agent volunteering it.

## Bearing on the exploration

Elevates two questions the round-1 leads did not cover:

- **Precedence-conflict handling.** When a session-level or workspace-level
  constraint contradicts a skill's prescribed mechanism, what should the agent
  do -- and how is "raise it" made non-optional? This is upstream of every
  enforcement-strength option under consideration.
- **Completion semantics.** What is the observable definition of "this plan was
  executed under the workflow"? Incident 2 shows invocation is the wrong unit;
  the durable koto session is a candidate, and it is checkable without agent
  cooperation.

Also sharpens the org-owner configuration question. If a workspace can declare
required workflows, it can equally declare constraints that contradict them.
The policy surface needs a defined resolution order, not just a list.
