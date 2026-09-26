---
upstream: docs/prds/PRD-coordinate-record.md
---

# DESIGN: The coordination record and the coordinator's workflow

## Status

Proposed

## Context and Problem Statement

`/coordinate` today is a prose skill: `skills/coordinate/SKILL.md` plus four references
(`loop.md`, `brief-template.md`, `verification-checklist.md`, `record-template.md`) and nine
eval scenarios. It has no koto template and no scripts. Every check it asks for is a
sentence the coordinator can skip, and the record is markdown the coordinator writes by
hand from a template.

The PRD asks for four checks that no value the coordinator supplies can satisfy: the record
exists exactly once before any dispatch (found by listing every open issue at roadmap scope,
or the rotation's draft pull request at discipline scope, never by search); the record has
its four sections; no deferral raised before the run started is undisposed when the run
first dispatches, including every deferral in a predecessor rotation's handoff; and the land
step is reachable only after the workflow itself has read the pull request's head from the
remote and found a board that really ran at that head (non-empty, finished, each non-skipped
job on a named runner with a succeeded step, every required check present and green, not
`DIRTY`), with the head re-read on entering land.

The technical problem is that koto gives shirabe three ways to decide a transition, and only
some of them resist a coordinator that wants to skip a step:

- **Evidence** the agent submits. Anything here is the agent's word.
- **Context keys** read by `context-matches` or `context-exists` gates. The agent can write a
  context key itself with `koto context add`, so a gate over a key is only as good as the
  guarantee that the key was written by the check and not by the agent.
- **Command gates** and **default actions** the engine runs. A command gate exposes only an
  exit code; a default action runs on entry, before the state's gates, and can write
  context. shirabe's rule (`references/default-action-conversion.md`) keeps any command whose
  success is an externally visible write, such as opening an issue or merging, out of
  default actions.

So the design has to put each check where the agent can't pre-empt it, keep every GitHub
write agent-run (opening, rewriting and closing the record; merges), and still carry a loop
that runs for days, is driven by cross-session messages rather than engine wakes (koto's
leg waker is a stub, koto#250), and hands most workers no koto leg at all (only `/scope` and
`/execute` accept `--koto-leg`, shirabe#401).

The record's shape is the second problem. The PRD fixes four sections and their columns
(Holdings: Unit, Entry point, Mode, Phase, Worker, Repo, Branch, Verified head, Dispatched,
Pull request; Deferrals: Deferral, Reason, Raised, Disposition; Side effects in flight:
Action, Target, Verified head, Attempted, How to confirm; Reversals: Date, Reversed, Now,
Reason, From), requires a body that parses back to the input it was rendered from, and cells
that can't break a table whatever the coordinator quotes into them. It also requires the
same renderer to write the discipline handoff file, and a find that tells apart four
discipline-branch situations and a predecessor's still-open rotation.

The third is the loop itself. The PRD's pick rules (a cap of five active workers kept full,
scoping ahead, asking up when the scope runs dry, a parked bound of three) and its two shadow
deciders (pick, report classification) must sit in states whose inputs koto can gate, and
every one of the prose skill's roughly 190 rules has to land in the state that uses it.

## Decision Drivers

- **No check satisfiable by the agent's value (PRD R7-R13).** Each of the four checks reads
  GitHub itself, and the gate that routes on it can't be overridden or pre-written.
- **Every GitHub write stays agent-run (R17).** Default actions may read GitHub and write koto
  context; they may not open, edit, close or merge anything.
- **Prose rules survive (R4) and the skill file gets thin (R5).** Step guidance moves into
  states behind details markers; the four references stay and are named from the states.
- **Message-driven, no unbounded watcher (R26).** The workflow is advanced by the coordinator
  on each message or notification; any bounded wait states its deadline.
- **Deciders in shadow only (R25).** Inputs are gated context keys or variables; an automatic
  answer can't end the run or pass a confirmation; the coordinator's answer always wins.
- **shirabe CI constraints.** The template passes compile, directives (every state with
  `accepts` has a `when`), mermaid freshness, interpolation (no `$VAR` in command fields, so
  logic lives in scripts reached through a `PLUGIN_ROOT` variable), decider declarations
  (TSV rows and at least 40 fixtures per decider), the entry floor, and bash 3.2.
- **koto 0.13.0 floor.** Non-overridable gates, constrained variables and result maps need it;
  the template carries the `# koto-floor: pinned` marker.
- **Default actions run within 30 seconds and re-run on every entry.** A GitHub read in one
  must be bounded and idempotent, and must clear the keys it owns before rewriting them.
- **Offline tests (R29).** Every script is testable with stand-in `gh` and `koto` on `PATH`,
  following `/deliver`'s and `/execute`'s test harnesses.
- **Out of scope stays prose.** Dispatch tooling and mechanised reconcile are later work; the
  dispatch and reconcile states call the prose procedure.
