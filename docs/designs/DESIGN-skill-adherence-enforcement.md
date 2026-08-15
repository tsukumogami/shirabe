---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-skill-adherence-enforcement.md
problem: |
  Agents holding shirabe's skills fail to run plan-scale work under the
  sanctioned workflow in two ways: the skill is never invoked, or it is invoked
  and the step carrying the guarantees is skipped on a defensible reading of a
  conflicting instruction. Both leave the author without visibility during the
  run and without durable evidence afterward, and every check that existed at
  the time passed both incidents.
decision: |
  A plugin-declared PreToolUse hook registers unconditionally and decides arming
  per tool call, refusing writes outside the plan-execution skill's already
  declared write-target set when the session's own inbound instructions name a
  resolvable PLAN and no single-issue delegation marker is present. A separate
  read-only determination reads four koto-authored surfaces plus the conflict
  store and reports one of conforming, non-conforming, coordinated, or
  indeterminate. A single conflict-recording command carries a departure to a
  machine-local store and to the home pull request.
rationale: |
  Separating registration from arming is what makes the arming signal
  independent of skill invocation, which the requirements demand because the
  case that matters is a worker that never invoked the skill. Reading the
  session's inbound instructions rather than its own output keeps the signal
  outside what the evaluated agent authored. The determination needs a liveness
  witness because absence of a koto record was shown, against real machine
  state, not to be evidence of non-registration.
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

The chosen resolution detects locally, because that is the only place the
discriminating state exists, and it defeats self-grading by making the record
one the evaluated agent did not author rather than by moving it off the machine.
Publishing the record to a remote surface was considered and is excluded by the
requirements, which is why the determination is a local read-only check rather
than a merge gate.

**What remained open at design entry**, all now settled in Considered Options:
what evidence the determination reads and what makes it admissible; what signal
arms the refusal without depending on skill invocation; where the enforcement
registers and how an operator disables it; what carries a conflict record when
no orchestration session exists; and how selection is measured reproducibly.

**What is still open** is narrower and named in Consequences and in the staging:
whether plugin hook registration completes before the first tool call in a
session whose opening move is a write, which gates the refusal stage and has a
one-command probe; how the conflict join walks delegated children, which record
under their own session identity; and how the hook composes with the workspace
manager's existing injected hook set, whose deduplication greps installed hook
scripts and does not inspect a plugin's declaration.

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
6. **Delivery is a hook, not prose.** Exploration favored skill-frontmatter
   registration, which the 2.1.233 binary does support (it emits
   `Registered ${i} hooks from skill '${n}'`, and a matching one-shot removal
   path proves the default persists). Design rejected it: a skill-registered
   hook arms when the skill is invoked, and the case this feature exists for is
   a session that never invoked it. See Considered Options, decision 3.
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

## Considered Options

Five independent decisions were evaluated. Each names its rejected alternatives
and the evidence that rejected them.

### Decision 1: what the determination reads

**Chosen: four koto-authored surfaces plus the PLAN, all required to agree.**
Registration comes from the workflows record under the session's project
directory; delegation count from the terminal index entries prefixed with the
parent workflow name; the expected issue count from re-parsing the PLAN; and a
liveness witness from the arming component's own log. Repo scoping comes from
the encoded project directory, whose encoding prefix-matches a worktree to its
repository.

*Rejected: registration record alone.* Falsified against machine state. A
completed eight-child run carries no workflows record, because koto defaulted
that recording on in a commit dated 2026-07-18 while the record only began
appearing in that workspace on 2026-08-04. Treating absence as failure reports a
fully delegated run as non-conforming.

*Rejected: "any koto session for this plan exists" as the corroborator.* Tested
and failed: with an unrelated session present, an inline run that never
registered returned indeterminate where AC2 and AC3 require non-conforming.

*Rejected: the session directory under the koto home.* Cleanup deletes it on
success, so the naive existence test is false for every successful run and
inverts the signal.

### Decision 2: what arms the refusal

**Chosen: a plan reference in the session's own inbound records.** Select the
transcript holding this agent's received instructions, scan only records the
agent received rather than the whole transcript, and require a reference
matching a PLAN filename whose target exists and carries the plan schema. Stand
down on a single-issue delegation marker, on the coordinated execution mode, and
on any parse or resolution failure.

*Rejected: absence of the subagent identity fields as the orchestrator test.*
This was the framing supplied to the researcher and it was declined, correctly:
absence is an open-world assumption. The identity field is used only to select
which transcript to read, where it is a reliable routing key.

*Rejected: arming on workflow state, such as the skill's own state file or a
registered orchestration session.* Both presuppose the skill already ran, which
is what the requirement forbids as a trigger.

*Rejected: arming on branch name.* A naming convention is neither necessary nor
sufficient, and an adopted-branch run legitimately does not use it.

### Decision 3: where the enforcement registers

**Chosen: a plugin-declared hook on the edit tools, running a fail-open
subcommand.** Registration is unconditional and session-long; arming is decided
per call. The handler type is a command handler deliberately, because a prompt
or agent handler's denial ends the turn unless an opt-in flag is set, whereas a
command handler's denial returns as the tool error and the turn continues, which
is what the correction criterion requires.

*Rejected: skill-frontmatter registration.* Structurally unable to satisfy the
arming requirement, since registration would inherit invocation as its trigger.

*Rejected: workspace-manager settings injection as the primary route.* It works
and is the shipped precedent, but it reaches only adopters who use that manager,
and it puts the enforcement's lifetime under a configuration layer the
requirement wanted independent of it. Retained as a fallback if the startup
ordering question resolves badly.

### Decision 4: the conflict record

**Chosen: one command, two backends.** The same invocation writes a durable
machine-local append-only record and, when an orchestration session exists,
also mirrors into the session's decision log. Surfacing reaches a
watching author through the existing session-summary hook emission and an absent
one through a block in the home pull request body.

*Rejected: the gate-override verb as the pre-session vehicle.* Tested: it exits
non-zero with "workflow not found" when no session exists, which is exactly the
case the requirement names.

*Rejected: two vehicles selected by whether a session exists.* One route the
agent learns, not two. A route that changes shape by context is a route with two
chances to be missed, and the incident is an agent that had a route and did not
reach for it.

*Rejected: the runtime directory as the durable home.* An audit record that does
not survive a reboot is not an audit record.

### Decision 5: measuring selection

**Chosen: a committed prompt set separate from the existing eval file, driven by
a wrapper around the evaluation runner, recording a quantized per-query pass rate
with a declared tolerance band.**

*Rejected: the description-optimizing loop.* It is a measurement tool wrapped in
an automatic description rewriter, so pointing it at the description under test
would rewrite the thing being measured.

*Rejected: reusing the existing eval filename.* Two independent blockers: the
existing file is an object while the runner parses a bare list, and the existing
CI existence check keys on that literal filename.

*Rejected: claiming exact reproducibility.* The runner has no seed or
temperature control. Promising bit-equality from a stochastic selector would be
the same class of overclaim this document's scope boundary warns against, and
the requirement was amended upstream to say so.

## Decision Outcome

The feature is three components sharing one contract.

**A refusal** that observes every edit-shaped tool call, arms only when the
session's own inbound instructions name a resolvable plan and no single-issue
marker is present, and denies writes outside the plan-execution skill's declared
write-target set with a reason naming the refused target and the sanctioned
alternative.

**A determination** that runs read-only after the fact, reads four
koto-authored surfaces plus the conflict store, and reports one of four
outcomes. It never reports conformance on unresolved evidence, and it treats a
missing liveness witness as indeterminate rather than as failure.

**A conflict route** that records a departure before it happens, works whether or
not an orchestration session exists, and surfaces to the author without the
author asking.

They work together because registration is separated from arming. The hook is
always present and answers "not armed, allow" for the overwhelming majority of
calls, which is what lets the arming predicate be independent of whether any
skill was invoked. That independence is the whole point: the failure this feature
exists for is a session that never entered the skill.

## Solution Architecture

### Components

| Component | Kind | Runs | Reads | Writes |
|---|---|---|---|---|
| Adherence hook | plugin-declared PreToolUse handler on edit tools | per edit-shaped tool call | hook input, the session's inbound records, the write-target declaration, the referenced PLAN | its own per-session evaluation log |
| Determination | read-only subcommand | on demand, after or during a run | koto workflows records, koto terminal index, the PLAN, the conflict store, the hook's evaluation log | nothing |
| Conflict recorder | subcommand | when a session declares a departure | its arguments | machine-local conflict store; the session decision log when one exists; the home pull request body |
| Write-target declaration | data file shipped with the plugin | read by the hook | n/a | n/a |
| Selection measurement | committed prompt set plus a wrapper script | on demand, before and after a description change | the prompt set | a committed results record |

### Data flow, refusal path

The hook receives the tool call. It selects the transcript holding this agent's
own received instructions, using the subagent identity field only as a routing
key. It scans the received records for a plan reference, resolves the reference
against the working tree, and reads the plan's schema and execution mode. If the
plan does not resolve, or the execution mode is coordinated, or a single-issue
delegation marker is present, it allows and records that it evaluated. Otherwise
it compares the write target against the declaration and either allows or denies
with a target-specific reason. Every path writes an evaluation-log entry, which
is what the determination later uses as its liveness witness.

### Data flow, determination path

The determination resolves the session's project directory from the working
tree, takes the freshest workflows record for that session scoped to this
repository, and establishes registration. It counts delegated children from the
terminal index by parent-name prefix, and takes the expected count from the
PLAN. It reads the conflict store for the session and for its children, since a
child records under its own session identity. It then reports: coordinated when
the plan's execution mode says so; indeterminate when the liveness witness is
absent or evidence is unreadable; conforming when registration holds and
delegation is complete or its shortfall is covered by a recorded conflict; and
non-conforming otherwise.

### Interfaces created by cross-validation

Two interfaces exist only because decisions met, and both are load-bearing.

**The evaluation log is a contract, not an implementation detail.** The hook
writes it so the determination can distinguish "this run did not register" from
"nothing was watching." Without it the determination misreports every run that
predates the recording path.

**The conflict store is an input to the determination.** A delegation shortfall
covered by a recorded conflict is conforming; the same shortfall uncovered is
not. The join walks children as well as the parent, because a child records
under its own session identity.

## Implementation Approach

Five stages, ordered so each is independently useful and the risky one is gated
by a probe.

**Stage 1: the write-target declaration.** Extract the plan-execution skill's
closed write-target set from prose into a data file shipped with the plugin. It
is currently a paragraph in a security section, and two components need to read
it. Nothing else can be built correctly until it is machine-readable.

**Stage 2: the determination, read-only.** Build it first because it is
read-only, it cannot break a session, and it produces the evidence that tells us
whether the refusal is needed as strongly as we think. Ship it with the
liveness-witness input stubbed as always-absent, so it reports indeterminate
rather than lying, until stage 3 provides the witness.

**Stage 3: the hook, in observe-only mode.** Register it, evaluate arming, write
the evaluation log, and never deny. This closes the determination's liveness
gap, and it produces a measured false-positive rate for the arming predicate
before any session is blocked by it.

**Stage 4: the startup-ordering probe, then the refusal.** The probe is one
command and it gates this stage: a plugin-declared hook that appends to a log,
against a session whose opening move is a write, checking whether the log entry
precedes it. If ordering does not hold, the fallback is settings injection.
Enable denial only after stage 3's measured false-positive rate is acceptable.

**Stage 5: the conflict recorder and the selection measurement.** Independent of
the others and of each other. The measurement is worth running before the
description change so there is a baseline.

## Security Considerations

**Untrusted input reaches the arming predicate.** The hook reads the session's
inbound records, which include text written by another agent and, transitively,
by whoever prompted it. Three consequences. The plan reference must be validated
as a path before any filesystem access, since a crafted reference is a traversal
attempt. The reference must be resolved and confined to the working tree rather
than followed as given. And the parse must be total: any malformed record fails
open rather than throwing, because a hook that crashes on hostile input is a
denial of service against every session.

**The refusal reason is fed back to the model.** It carries the refused target,
which is attacker-influenceable in the same sense any path is. The reason must be
assembled as a JSON string value rather than interpolated into text, exactly as
the shipped pull-request-body hook already does, so that a crafted filename
cannot break out of the string or inject a terminal control sequence.

**The hook must not brick a session.** A handler matching every edit-shaped call
that exits non-zero blocks that call. The shipped precedent in this workspace
documents the failure: an outdated binary that does not recognize a new
subcommand exits non-zero on every invocation. The handler must therefore guard
on the binary's presence, must not exec, and must swallow a non-zero exit.

**The conflict record carries an instruction verbatim.** Machine-local that is
free, since the store is user-owned and never crosses a visibility boundary. The
pull-request block is not: a public repository must not carry content from a
private one, so the published form is a reference and a summary rather than the
verbatim instruction.

**The enforcement is reachable by what it governs.** The disable switch, the
plugin's enablement, and a project-level setting that disables all non-managed
hooks are all reachable by an agent with the ability to change configuration.
This is accepted rather than solved, and it must be claimed plainly: the refusal
is a speed bump plus an audit trail, not a sandbox. What gives it teeth is that
an unrecorded departure is non-conforming, so evading the refusal does not
produce a clean record.

**The refusal does not cover indirect writes.** A subprocess the session starts
writes without passing through the observed tool call. Closing that requires
operating-system-level confinement, which is a different class of mechanism and
out of scope. The determination catches the consequence even when the refusal
misses the act, which is the reason both components exist.

**The determination reads user-scoped state.** It reads under the user's home
directory and must not follow symlinks out of it, must not execute anything it
finds, and must treat every field as data.

## Consequences

**Positive.** Conformance becomes checkable by someone other than the agent that
did the work. The failure mode that produced both incidents is caught at the
moment it happens rather than after the branch is finished. A departure that is
genuinely justified stays available and becomes visible, which is a better
outcome than either forbidding it or losing it. The determination is read-only,
so it can ship first and be trusted before anything is blocked.

**Negative.** The design adds a component on the path of every edit-shaped tool
call, with the latency and failure-mode cost that implies. The arming predicate
reads transcripts, which is a larger and less stable surface than a
configuration lookup. The write-target set becomes a machine-readable contract
that must be kept in step with the skill it describes, and drift between them
would produce false refusals. And the enforcement is defeatable by the agent it
governs, which bounds what it can promise.

**Mitigations.** Staging the refusal behind an observe-only mode produces a
measured false-positive rate before any session is blocked. Fail-open is the
default branch at every step rather than an exception path. The determination
does not depend on the refusal being present, so the two degrade independently.

**What this does not deliver.** It does not establish that the delegated work
was done well, that reviews were substantive, or that recorded evidence is true.
The orchestration engine records that evidence was submitted in the expected
order and does not verify it, and its spawn primitive is a stub. A run that
drives the full loop while submitting weak evidence produces a conforming
record. This is stated in the requirements as an explicit exclusion and is
repeated here because it is the single most likely thing for a reader to assume
the feature does.

## References

- `docs/prds/PRD-skill-adherence-enforcement.md` for the requirements this design
  satisfies, including the defined terms the components share.
- `docs/briefs/BRIEF-skill-adherence-enforcement.md` for the framing and the
  four journeys the acceptance criteria trace back to.
- `docs/designs/current/DESIGN-execute-skill.md` and
  `docs/prds/PRD-execute-skill.md` for the plan-execution workflow this feature
  governs, including the closed write-target set the refusal binds to.
- `docs/briefs/BRIEF-pr-template-gate.md`, which names the same class of failure
  and scopes the workflow-routing half of it out as separate work.
- `references/workflow-principles.md` for the principle that enforcement
  strictness scales with the consequence of getting a rule wrong, which is the
  basis for staging the refusal behind an observe-only mode.
