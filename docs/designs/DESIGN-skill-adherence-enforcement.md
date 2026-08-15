---
schema: design/v1
status: Proposed
problem: |
  Agents that have shirabe's skills available fail to run plan-scale work under
  the sanctioned workflow, in two distinct ways: the skill is never invoked, or
  it is invoked and the koto loop is skipped mid-run on a precedence conflict.
  Both produce the same loss — no visibility into the run and no record that its
  validation steps happened. Exploration settled what to build (enforce
  /execute's already-declared closed write-target set at write time, delivered
  from skill frontmatter, alongside an interpretation-narrowing ordering
  statement and a delegation detector) and left open how: the exact write-target
  predicate and its subagent exemption, the off-machine publishing mechanism and
  the R9 amendment it needs, where the ordering statement binds, and the koto
  init sequencing change.
---

# DESIGN: Skill Adherence Enforcement

## Status

Proposed

## Context and Problem Statement

Two field incidents produced an identical loss by different routes.

In the first, an agent told to execute a plan never invoked `shirabe:execute`.
It built its own task list and hand-implemented 22 plan outlines in dependency
order. No koto session, no state machine, no per-issue spawn, no review gates.
It surfaced only when the user asked whether koto was being used at all, at
which point the agent named precisely what it should have done.

In the second, the agent *did* invoke the skill. It ran the preflight, confirmed
a defect in the referenced issue, and ran `plan-to-tasks.sh`, producing a valid
koto task payload with all six `waits_on` edges — then used that payload only to
verify the dependency graph, never submitted it, and implemented all six issues
inline. Its stated reason was a precedence conflict: the session instruction "Do
not call the AgentTool unless the user requested it" collided with
`spawn_and_await`, which materializes one `/work-on` child per issue, and it
resolved against the skill. Under the documented rule that user and session
instructions outrank skills, it was not wrong by the letter.

The exploration's opening theory — that shirabe's skills are hard to reach — is
dead. A live probe on Claude Code v2.1.233 confirmed bare `/execute` resolves to
`shirabe:execute`; a plugin skill receives a bare alias unless another command
claims the name, and nothing claims `execute`. Both agents had the skill
available and could name the correct path when asked. The cause is not missing
knowledge, which disqualifies every mechanism whose only effect is to supply it.

Six mechanisms were evaluated adversarially. Two results decided the shape:

**The discriminating state exists only on the machine.** Shirabe's shipped
path-independent checks (L01, L06, PB1–PB4) were live during both incidents and
certified them both — incident 2's agent ticked acceptance criteria, ran the
finalization cascade, and opened a conformant PR. Every candidate off-machine
property was enumerated and each passes both incidents, because a competent
inline implementation satisfies all of them.

**But the machine is the party that failed.** Every client-side mechanism asks
the session that just erred to evaluate itself again, only earlier or louder.

The chosen resolution detects locally, where discrimination is possible, and
publishes off-machine, which is what removes self-grading. The full decision,
with alternatives and rejection reasons, is recorded in
`wip/adherence_decision_report.md` and should be carried into this document's
Considered Options rather than re-derived.

**What remains open** is architectural and interlocking:

- The exact write-target predicate, and how it exempts `/work-on` children.
  Whether skill-registered hooks fire inside subagents is unverified and blocks
  implementation; the hook input carries `agent_id`/`agent_type`, so the
  exemption is expressible, but the behavior needs testing.
- The off-machine publishing mechanism — a `Koto-Session:` trailer versus a
  run-report emit — and the R9 amendment widening `/execute`'s closed
  write-target set that either requires. `SKILL.md:409-412` currently defers
  exactly this.
- Where the ordering statement lives so it binds at every tick rather than only
  at entry, per `DESIGN-execute-skill.md:227`, and how it is worded.
- The `koto init` sequencing change, flagged as a real state-machine change
  rather than a reorder, since `spawn_and_await` calls `plan-to-tasks.sh` twice
  with different evidence.
- How the gate composes with niwa's existing injected hook set without
  double-registering, given `materialize.go`'s marker-based dedup convention.

## Decision Drivers

- **Must catch both failure modes.** A check keyed on "was the skill invoked"
  passes incident 2 and is disqualified. The unit must be an artifact the agent
  does not author.
- **Must not be gameable.** A predicate satisfiable by one honest command teaches
  agents the command that buys permission and leaves a record falsely attesting
  the loop ran — worse than the failure it replaces.
- **Must not block sanctioned paths.** A `coordinated` PLAN has no koto session
  by design (`skills/execute/SKILL.md:242-246`, koto has no cross-repo session).
  Any predicate needs an explicit carve-out or it fails the newest execution path.
- **`ask` is unusable.** Dispatched and headless sessions run under
  `bypassPermissions` with no human; an `ask` stalls the turn. Gates resolve
  allow-or-deny, with a reason precise enough to self-correct.
- **A gate needs a sanctioned bypass.** Without one, an agent that can neither
  delegate nor edit nor ask resolves the bind privately — manufacturing a new
  class of silent failure rather than surfacing the old one.
- **The ordering statement must narrow interpretation, never claim precedence.**
  "Requesting `/execute` requests its children" is defensible; "skills outrank
  session instructions" is not, and shipping it would be worse than either
  incident, generalizing to every constraint a user or operator sets.
- **Fail open on ambiguity.** A `PreToolUse` hook that exits non-zero blocks the
  call; niwa's `materialize.go:592-606` documents how a stale binary would brick
  every session.
- **Prefer guidance, staged toward enforcement.** `P5: Strictness tracks blast
  radius` licenses shipping as a notice and promoting once the corpus conforms.
- **Respect the established division of labor.** niwa declares and distributes;
  shirabe decides. Skill-frontmatter delivery avoids a new policy surface
  entirely and reaches adopters who do not use niwa.

## Decisions Already Made

Settled during exploration. Treat as constraints; do not reopen without new
evidence.

1. **Discoverability is not the problem.** Bare `/execute` resolves. No
   `commands/` directory is needed.
2. **Invocation is the wrong unit of measurement.** Incident 2 ran the skill's
   scripts and produced a valid payload.
3. **Outcome gating is rejected as the primary mechanism** — falsified, not
   argued down: the shipped gate certified both incidents. Its definitional half
   and two cheap checks are adopted.
4. **Injection cannot be the enforcement leg.** `additionalContext` is delivered
   as a system reminder read as plain text, ranking below the session instruction
   that already beat the skill. Only a hook block escapes that ordering.
5. **The primary predicate is R9 write-target conformance**, enforced at write
   time rather than at self-administered finalization. It is ungameable, needs no
   coordinated carve-out, and rests on a contract the skill already declares.
6. **Delivery is skill-frontmatter hook registration** — confirmed against the
   2.1.233 binary, which emits `Registered ${i} hooks from skill '${n}'` and
   `Removing one-shot hook for event ${s} in skill '${n}'`; the one-shot removal
   path proves the default persists.
7. **The `[claude.skills]` niwa policy surface is deferred**, as the most
   machinery in the field for no additional enforcement grade, and it collides
   with the `[workspace]` overlay tombstone reasoning.
8. **The restricted-tool orchestrator vehicle is rejected**, its principle
   retained: an agent-definition tool list misses the interactive path, carries
   no reason string, and degrades into a silent Bash bypass.
9. **`koto overrides` cannot be the pre-session conflict vehicle** — tested, it
   exits 1 with "workflow not found." In-loop it fits; pre-session the vehicle is
   the `shirabe work-summary` hook path, already session-keyed and default-on.
10. **Koto's guarantees are bookkeeping, not enforcement.** The substrate-spawn
    primitive is a logging stub; review gates are directive text koto never
    verifies. No mechanism in this field delivers "the reviews definitely ran."
    The achievable goal is that runs are recorded, visible, and deviation is
    auditable — and the design should say so plainly rather than imply otherwise.

## References

- `wip/adherence_decision_report.md` — the full decision block, alternatives, and
  rejection reasons
- `wip/explore_skill-adherence-enforcement_findings.md` — synthesized round-1
  findings
- `wip/explore_skill-adherence-enforcement_evidence.md` — both incident records
- `wip/adherence_binary_verification.md` — claims checked against the 2.1.233
  binary, including two documented field names that do not exist
- `wip/research/explore_skill-adherence-enforcement_r1_lead-*.md` — seven
  research leads
