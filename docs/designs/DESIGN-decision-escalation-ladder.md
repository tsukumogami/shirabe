---
schema: design/v1
status: Draft
problem: |
  Worker workflows let an agent stop at about a dozen points with a free-text
  reason, the decision skills can only choose or assume, and the workflow
  engine's decision record has no open question, no typed addressee and no
  answer tied to a question. Nothing prompts a session to decide before it
  stops, nothing durable holds a question for a person, and no read returns
  what is waiting on whom.
upstream: docs/prds/PRD-decision-escalation-ladder.md
---

# DESIGN: Decision Escalation Ladder

## Status

Draft

## Context and Problem Statement

The requirements ask for one procedure: a session that hits a question sorts
who it belongs to, tries to settle it, and only then raises it; the question
lives on a durable record until someone entitled answers it; and a person can
read what is waiting on them from any session and answer there. Building that
touches three systems that today do not meet.

**The worker workflows.** `/work-on`, `/execute` and `/scope` are koto
templates. Each has a handful of edges on which the agent itself declares that
it cannot continue: `/work-on`'s `analysis` (`blocked_missing_context`,
`scope_changed_escalate`), `implementation` (`blocked`,
`partial_tests_failing_escalate`), `introspection` (`issue_superseded`), its
three validation states (`verdict: exit`, `needs_design`) and
`deferral_approval`; `/execute`'s `worktree_discipline_check`
(`intent-changing`); `/scope`'s hop `outcome: bail` and `full_run_blocked`'s
`next_move: abandon`. Every one of them takes a free string and ends the run.
None checks that a decision was attempted, and a template has no way to say
"question raised, carry on with the rest". koto has no return-to-caller, so a
shared step that several states enter has to route back by a recorded origin.

**The decision skills.** `/decision` returns one status, `COMPLETE`, and
removes its research when it finishes. The lightweight protocol in
`references/decision-protocol.md` ends in "ask the user" or "follow the
recommendation and continue". Neither can return a question with its
recommendation and alternatives to whoever called it, and `/design` and
`/explore` expect a choice back. Most blocking questions sit below
`/decision`'s floor, in the lightweight protocol.

**The coordinator.** `/coordinate`'s template already gives each question a
verdict of settle, hold or pass up, limits passing up to closed grounds,
refuses to send a question without context, problem, a recommendation and an
explanation of every option, and allows the question prompt only in a turn the
person started. But it accepts a pass-up with no evidence a decision was
attempted, releases one question at a time, re-words a worker's question into
a new entry at each level, and keeps its entries in its own session key, so no
other session can read them. Coordinators also exist that run in no koto
session at all and carry these rules as brief text.

**koto's decision record.** It has write-once entries under
`koto/decisions/<id>`, typed deciders (`session`, `person:<handle>`,
`check:<name>`), a run mode, `--basis` links, reversal, and a listing of
everything below a session. Its `escalate` kind stores three strings
(`question`, `text`, `recipient`); the recipient is untyped; no kind records
an answer to a question; nothing is open or closed; the read for "what was
addressed to me" (`--received`) is specified and unbuilt; and the read that
would let a session notice another session's entry about its own decision at
`koto next` is unbuilt. Its kinds, outcomes and subjects are declared closed
in koto's own requirements. Every listing scans the whole local store and,
under the cloud backend, lists the bucket once per session, which is why a
single-session listing was seen not to return in minutes on a store of about a
thousand sessions.

**Chain structure.** `koto session origin <name>` reports the session or
anchor that dispatched a session, `none`, or `unrecorded`. Two trees exist:
sessions linked to a coordinating koto session, and sessions linked to a
harness session's anchor. Sessions started by hand are linked to nothing.

**The question prompt.** Nothing guards it. A session can open it in a turn
nobody started and wait indefinitely; the prompt's options exist only in that
session's transcript. The plugin ships one hook today, and the only presence
signal either plugin reads is per session (attended or not), not per turn.

What the requirements fix in the body of this design: a question keeps one
identity from raise to answer, and one read returns its history (who raised
it, its content, every addressee, its answer, who answered and where). Its
content is fixed at raise and at most 16 KiB. "What is open" is a single koto
read with no joining by the caller, by position and by person, returning
within five seconds with 1,000 sessions and 200 open questions on both of
koto's storage backends. A person's answer can be recorded from any session
that can read the question, takes effect with no ratifying step, is the one in
effect over any session's answer, and reaches the session that asked at its
next workflow step. A waiting question is re-presented byte-for-byte after the
asking session loses its context. Needs that are not decisions share the
record. A question prompt cannot open in a turn the person did not start.
Sessions that raise nothing behave as before. koto's part ships before any
skill depends on it.

## Decision Drivers

- **Delivered by the workflow, never remembered.** The cause of the problem is
  instruction decay in long sessions. Anything that depends on a session
  recalling prose fails the requirement that the workflow prompt the attempt.
- **One writer per session.** koto's cloud sync is not multi-writer, and its
  design says a session's keys are written only by processes acting for that
  session. An answer given in another session has to be stored there and found
  by reading.
- **Write-once keys.** koto decisions cannot be edited. "Open" and "the answer
  in effect" have to be computed when read.
- **One rule for "open".** The requirements make "what is open" koto's to
  answer so the session, the command line and a later status view cannot
  disagree.
- **Read cost on a large store.** Any read that scans every session, or lists
  the bucket per session, misses the five-second bound.
- **koto's closed tables are a contract.** Adding a kind, a subject field or a
  status changes a requirements document that is still in progress, and has to
  be done there, not around it.
- **Running sessions are pinned to their template.** A structural change to a
  template reaches only new sessions, and a structural change to
  `coordinate.md` forces a compatibility bump that blocks taking over a running
  coordinator.
- **The `wait` hub's directive has a size ceiling** judged at the merge base,
  so the decide-first text cannot go there.
- **Testable without a model.** Nothing in the repository runs an agent, so
  each behaviour needs a script, template or engine test, with judgment left to
  the dogfooding run.
- **No change for sessions that raise nothing,** and the guard must not break
  the seven skills that open question prompts in turns their author started.
- **Release order.** koto releases first; shirabe raises its koto floor and
  only then merges anything that calls the new commands.
- **A later answering surface.** Recording an answer must need only the
  question's identity, the answer and who gave it.

## Considered Options

Not written yet: a later /design phase replaces this line.

## Decision Outcome

Not written yet: a later /design phase replaces this line.

## Solution Architecture

Not written yet: a later /design phase replaces this line.

## Implementation Approach

Not written yet: a later /design phase replaces this line.

## Security Considerations

Not written yet: a later /design phase replaces this line.

## Consequences

Not written yet: a later /design phase replaces this line.
