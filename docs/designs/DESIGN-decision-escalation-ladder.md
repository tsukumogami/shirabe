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

The requirements this design answers, by number in the upstream PRD: one
identity and one history read per question (R10); content fixed at raise and
at most 16 KiB (R11); needs sharing the record (R12); "what is open" as a
single koto read by position and by person within five seconds at 1,000
sessions (R14, R15); an answer from any session with no ratifying step (R21),
recorded as the owner's only with a verified prompt behind it (R21a to R21d);
the asker finding it at its next workflow step (R22); the owner's answer in
effect over a session's (R23); byte-for-byte restore (R25); the prompt guard
(R17, R27); no change for sessions that raise nothing (R30); and koto's part
released first (R33). Each section below states what the requirement it
answers asks for.

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

### Decision 1: How koto represents a question from raise to answer

koto has to hold a question under one identity from the moment it is raised
until it is answered, return what is open by position and by person inside
five seconds at 1,000 sessions on both storage backends, accept an answer from
any session, make a person's answer the one every read returns, and tell the
session that asked at its next `koto next`. Its decision record has the trail
of who decided but no open question, no typed addressee and no answer; its
request store has a live wait with a wake but no typed decider and no read by
position.

Delegated to /decision. Four alternatives went through a bakeoff, a peer
revision and a cross-examination; the reviewers arguing for the request store
and for a new question object both ended by recommending against their own
alternative.

Key assumptions:

- koto's decision-record requirements, which declare kinds, outcomes and
  subject fields closed and are still in progress, are amended for this
  consumer the way they were for the previous one. If they are not, only new
  subject fields on existing kinds are available and passing a question up has
  no good home.
- koto's rule that a session's keys are written only by processes acting for
  that session stays as it is.
- A read of this machine's sessions only is acceptable under the cloud
  backend, since reads across machines are out of scope.
- Recording a decision into a dispatch anchor works end to end. It was
  inferred from the code and not run.
- The cost figures beyond one measured scan are estimates from one machine.

#### Chosen: extend the decision record, with the answer stored where it is given

A question is one `escalate` decision in the session that raised it. Its
identity from raise to answer is the pair koto already uses to key entries
aimed at a decision: the raising session's id and the decision's id. It never
moves and is never copied. Everything that happens to it afterward is a new
write-once entry stored in the session or anchor of whoever acts, under
`koto/aimed/<raiser-session-id>/`, naming that pair. No command writes into a
session it is not acting for, nothing is stored outside session directories,
and there is no index.

| Event | Kind and outcome | Subject | Stored in |
|-------|------------------|---------|-----------|
| A question or need is raised | `escalate` / `escalated` (existing) | existing `question`, `text`, `recipient`, with `recipient` typed as `session:<name>`, `anchor:<name>` or `person:<handle>`; new `need` (`decision`, `credential`, `reserved-step`), `label` (the subject label), `packet` (a hash of the content), `state` (the workflow state and visit it was raised from, when a workflow raised it) | the raiser, under `koto/decisions/` |
| An attempt to decide | `judgment` / `settled` (existing) | existing free text and pointer; new optional `state` (the workflow state and visit) and `result` (`decided`, `undecided`, `provisional`) | the session that made the attempt, under `koto/decisions/` |
| The content | none: raw bytes, write-once, at most 16 KiB | none | the raiser, under a new area `koto/packets/<decision-id>` |
| It is passed up | new kind `readdress` / `passed` | the question's pair, the new `recipient` | the session that passed it up |
| It is answered | new kind `answer` / `answered` | the question's pair, the answer `text`, the `label` | the session the answer was given in, with the decider (a person with handle and surface, or a session) and the run mode |
| The raiser settles it from an earlier answer or new evidence | `answer` / `settled` | the pair, `text`, `label`; at least one basis or evidence entry | the raiser |
| The raiser withdraws it | `answer` / `withdrawn` | the pair, `label`; a reason | the raiser |

"Open" and "the answer in effect" are computed when read, from one scan of
this machine's sessions that already collects aimed entries by the decision
they aim at:

1. The addressee history starts with the question's recipient. A pass-up
   counts when it was recorded by the session that was the addressee at that
   point, or by the raiser, and names that recorder's own recorded dispatcher
   or a person. The last counted recipient is the current addressee.
2. A closing entry counts when it is an answer from a person that carries
   evidence, an answer from the session that is the current addressee, a
   withdrawal by the raiser, or a settle by the raiser of a question that is a
   decision. When that question is addressed to a person, the raiser's settle
   counts only if it cites an answer of the person's that is in effect and
   carries the same subject label. When it is addressed to a session, the
   settle must cite a decision or a recorded workflow event as its evidence. A
   credential or reserved-step need cannot be settled by its raiser. Anything
   else is returned marked as not counted, with the reason.
3. Among counted answers from a person, one that a later person answer names
   as its basis is dropped; what remains governs, the latest if a true race
   left several. With no person answer, the earliest counted session entry
   governs. A session entry never outranks a person's, so a session cannot put
   its own answer back, and a person answering again cites their earlier
   answer and wins by that citation; a clock decides only a true race between
   two person answers neither of which cites the other.
4. A question is open when step 2 found nothing.

Three reads, each one scan of this machine's sessions with no bucket request
on either backend:

- **Open by position**: the open questions raised by, or currently addressed
  to, a named session or anchor, its confirmed predecessors, and every session
  below them. A passed-up question appears once, with whether the position
  raised it, is addressed it, or both.
- **Open by person**: every open question whose current addressee is a given
  handle. It takes no session and makes no chain test, so a question from a
  session with no recorded link is returned.
- **Precedent**: the answers a person gave that are in effect, in the chain a
  named session belongs to, optionally narrowed to a subject label. The label
  is copied onto the answer, so the read needs no join and still works after
  the raiser is gone.

A single read of one question returns its whole history: state, need, label,
content hash, the raiser with its run mode and successor, the ordered
addressees, the answer in effect with its decider, the session it was given in
and that session's run mode, and every aimed entry with whether it counted.
Another returns the stored content bytes untouched to any session on the
machine, which is what makes re-presentation byte-for-byte.

Measured on a store of 993 sessions, the scan these reads use takes about a
tenth of a second. The listing that was seen not to return was slow because
the cloud backend's listing issues several bucket requests per session; every
decision a machine writes is also on its own disk, and these reads use that.

The asker finds an answer through a new read on `koto next`. While a
session's run holds a question that is open, or one closed by an entry the
session has not yet cited, the tick looks in each local session for entries
aimed at the session's id or its confirmed predecessors' ids, and reports the
answer in effect on the response, including the response of a workflow that
has already ended. It writes nothing, makes no network request and never
blocks an advance. The session acknowledges by recording what it did with the
answer, citing it; until then every tick repeats it, so a context loss cannot
lose an answer. Recording an answer also rings the asker's existing wake file
so an idle session ticks sooner.

Two retention rules change so nothing waiting is lost: a session holding an
open question is kept, and an aimed entry links its holder to the question's
session so a person's answer recorded in an otherwise unrelated session stays
as long as that chain does. An explicit cleanup of a session holding an open
question, or the answer in effect for one, is refused without a force flag.

#### Alternatives Considered

**Write the answer into the asking session.** Every event of a question
lives in the raiser's own record, written by whoever acts. It has the cheapest
tick read and one object to retain. Rejected because it breaks the rule that
only processes acting for a session write its keys, a supersession arriving
from another machine can make a person's answer read as refused, and cleaning
up the raiser removes the precedent with the question. It stays available as a
later narrowing if that rule is ever relaxed.

**Carry the live wait in the request store.** A raised question is a one-leg
request the answerer resolves; listing, resolving and waking exist today.
Rejected, and withdrawn by its own reviewer, because a person's answer held
there either leaves the decision record or disagrees with it, a leg accepts
one result and has no typed decider, the request's leg, role and template
would be dummies, and request records do not travel with a session.

**A new first-class question object.** A separate log per question with its
own open state and precedence. Rejected, and folded by its own reviewer into
the request-store shape, for the same two-record problem plus the largest
build and a third store to keep authoritative.

### Decision 2: How the worker templates deliver the decide-first step

The requirements ask that the workflow itself deliver the decide-first
procedure at the moment an agent declares it cannot continue, and that the
exit be refused until the session has a recorded attempt and, when the attempt
ended undecided, a raised question. They also ask that a session keep working
on whatever does not depend on the answer. The covered exits are spread over
three templates, and koto has no return-to-caller, so whatever is added has to
say how a session that decides after all gets back to where it was.

Resolved inline.

#### Chosen: one decide-first state per template, in front of the covered exits

Each of `work-on.md`, `execute.md` and `scope.md` gains one state,
`decide_first`. The edges that today leave a covered state for a blocked
terminal point at it instead, and the state the session came from is written
to a context key on the way in. koto delivers a state's directive on arrival,
so the procedure text reaches the agent exactly when it has said it cannot
continue, and the text is a short pointer to the shared reference (Decision 5)
plus the three commands it may run.

The state accepts two outcomes. `decided` means the attempt chose an option:
the session returns to the state it came from by one edge per origin, selected
on the context key, and carries on. `raised` means the attempt ended undecided
and a question is on the record: the session leaves through the exit it was
about to take. A command gate decides which is allowed by reading the
session's own record: `decided` needs a recorded attempt that chose an option
for this state and visit, and `raised` needs an undecided attempt and an open
question that names this state. A session cannot leave by declaring an
outcome; the record has to exist.

What happens after `raised` differs by template, because "work that does not
depend on the answer" differs. `/execute` runs a plan: it parks the issue on
the question's identity and takes the next unblocked issue, and returns to the
parked one when the question closes. A single-issue `/work-on` run and a
`/scope` hop usually have nothing else to do, so they end at a waiting
terminal whose result carries the question's identity in place of a free-text
reason; re-invoking the skill after the answer resumes the run. `/deliver`
forwards that result unchanged.

`deferral_approval`, the one state that halts for a person today, becomes an
entry to `decide_first` like the others: its halt is a question addressed
under the usual rule.

Mechanically decided stops (a failed check, a refused merge) and the review
panels' safety stops keep their edges. A run that never reaches a covered exit
never enters the new state, so its states and result are unchanged.

#### Alternatives Considered

**Gate each exit edge and add no state.** Put the same command gate on every
covered edge. Rejected because nothing is delivered at the exit: the procedure
would have to sit in every origin state's directive, where it arrives when the
state is entered and not when the agent decides to stop, which is the
remembered-instruction problem in a smaller form.

**A shared child workflow per question.** Start a small koto session for each
question, with its own template for sort, decide and raise. Rejected because
it adds a session, a link and a result hand-back for what one state does, and
multiplies sessions on a store whose listing cost is already a constraint.

**Bounce bare questions at the coordinator's intake.** Leave the templates
alone and have the coordinator refuse a reported question with no
recommendation. Rejected because a worker with no coordinator has no intake,
and the requirements cover that shape.

### Decision 3: How the coordinator side is enforced, and the one command

A coordinator must not pass a question up or present it without a recorded
attempt, must stop re-wording a worker's question into a new entry, and must
present everything pending instead of one at a time. Separately, the
requirements ask for one command that runs the whole procedure in any
session, including a coordinator that carries its rules as brief text and runs
in no workflow session.

The constraint that shapes this is the coordinator template's compatibility
rule: a structural change to `coordinate.md` raises its compatibility number,
which blocks taking over a running coordinator and blocks importing one.

Resolved inline.

#### Chosen: enforce in the coordinator's scripts, and ship the command as a thin skill

No state is added to `coordinate.md`. The script the existing verdict state
calls to pass a question up refuses unless the entry names a recorded attempt,
with needs exempt. An entry opened for a worker's question holds the
question's identity and reads its content from the record; the coordinator no
longer writes its own version. The script that releases queued questions
releases up to four, ordered by recorded waiting work items, then age. The
directive text that states the old rules changes with them, which is not a
structural change.

The on-demand command is a small skill whose body is a single shared command
(Decision 5): read what is open at and below this session and what is open for
the person, apply settle-or-pass-up to each question addressed to this
session, and present the rest when the person started the turn. It needs no
koto session of its own: a session with no workflow is still a position
through its dispatch anchor. A template-driven coordinator reaches the same
command from its existing decision states; a brief-driven one reaches it when
the person types it or when its brief's standing rule names it.

#### Alternatives Considered

**A new sweep event and states in the coordinator template.** Route a
person's request through new states that walk every pending item. Rejected
because it forces the compatibility bump, strands running coordinators, and
does nothing for coordinators outside the template.

**Require every coordinator to run in a workflow session.** Rejected because
the author ruled it out: it turns this feature into a migration of how
coordinators are run.

**The command alone, with no script enforcement.** Rejected because a
template-driven coordinator could still pass a question up with no attempt
behind it.

### Decision 4: How the question-prompt guard knows the person started the turn

A question prompt must not open in a turn the person did not start. The only
presence signal either plugin reads today is whether a person is attending the
session, which is true of a coordinator the person is attached to even while
it is processing a worker's report. The guard also has to leave alone the
prompts seven existing skills open in turns their author started.

Resolved inline, and revised after Decision 6's research: the harness labels
each turn-starting message as typed by a person, sent by another session, or a
background notice, but a dispatched session's first prompt and a scheduled
wake-up carry the same label as typed text, and about seven in eight turns so
labelled on one machine were not the owner.

#### Chosen: a pre-tool hook on the question tool that applies a narrow turn test

The shirabe plugin registers a hook that runs before the question tool. It
allows the prompt when the session is attended and the turn it is in was
started by a message a person typed that is not the session's first prompt,
not a scheduled wake-up, and not a message another session or the harness
injected. Otherwise it denies the call with a message telling the session to
leave the question on the record and continue. Where the turn's origin cannot
be established, the guard falls back as the requirements say: deny when the
session is unattended, allow otherwise.

The decision logic lives in the `shirabe` binary behind a shell entry, as the
existing hook does, with the same off switch and the same rule that a guard
which cannot decide does not block unrelated work. The plugin's hook test
assumes one hook command today and is changed to name the command it tests.

Where the hook gets the turn's origin is the one thing left to a spike, which
is the first implementation step: either a second hook on prompt submission
that writes a per-session mark the pre-tool hook reads, or the origin the
harness records in the transcript the hook's input names. The spike captures
what each source reports for a typed prompt, a dispatch brief, a scheduled
wake-up, another session's message and a background notice, and the guard
uses whichever tells them apart. If neither does, the guard ships with the
attended fallback alone and the limitation is recorded.

The guard is the floor under Decision 6: an owner decision needs an answered
prompt, and a prompt opens only where the owner can be the one answering.

#### Alternatives Considered

**Use the session's attended signal alone.** Rejected as the primary test
because an agent-started turn in an attended session would open a prompt,
which is the failure the requirement exists to stop. It remains the fallback.

**Trust the harness's label for a typed turn as it stands.** Rejected because
that label also covers dispatch briefs and scheduled wake-ups.

**Ship the guard from the koto skills plugin.** Rejected because that plugin
updates on its own schedule and does not own what a question prompt means; the
guard has to be present wherever shirabe's skills are.

### Decision 5: Where the procedure's shared logic lives in shirabe

Raising a question, passing it up, settling it, withdrawing it, answering it,
listing what is pending and rendering a question for presentation are needed
by three templates, the coordinator's scripts, `/decision`, the lightweight
protocol, the on-demand command and the guard. The requirements also ask that
a waiting question be re-presented byte-for-byte, that a raised question be
refused when a required part is missing or it exceeds 16 KiB, and that the
prose rules stop living in several places.

Resolved inline.

#### Chosen: a `shirabe question` command family and one shared reference

The `shirabe` binary gains a `question` command with subcommands for each
operation. It is the one place a question's content is validated (context,
problem, question, recommendation with reason, alternatives with reasons, the
ground, the waiting work items, the subject label, the size bound) and the one
place a question is rendered. Rendering is a pure function of the recorded
content, so two renders of the same question are identical whichever session
or tool asks, which is what the exact-restore requirement needs. The
subcommands call koto for identity, addressee, open and answer (Decision 1);
shirabe owns what a question contains and how it is shown.

The prose lives once, in `references/question-procedure.md`, organized by
where a session sits: no dispatcher, a session dispatcher, or a coordinator
with sessions beneath it. Workers have no role, so position is the only key
that covers every session. Each template directive, the decision protocol,
`/decision` and the on-demand command point at it and restate none of it.

`/decision`'s result gains a second status beside `COMPLETE`: `UNDECIDED`,
carrying the question, a recommendation, every alternative with its reason and
what was missing. On that path it keeps its research keys instead of removing
them, so whoever answers can read them. `/design` and `/explore` treat an
undecided result as a question raised by the session they run in. The
lightweight protocol gains a third outcome beside asking and following the
recommendation: raise the question. The coordinator's existing renderer is
replaced by a call to the shared one.

#### Alternatives Considered

**Shell scripts beside each skill.** Rejected because validation and
rendering would be written several times and drift, as the coordinator's
renderer and the decision-presentation reference already have.

**Validate and render in koto.** Rejected because koto would then own the
shape of a shirabe document. Its part is identity, addressee, open and answer.

**A new skill that holds the whole procedure.** Rejected because an agent
reaches a skill by being told to, which is the remembered-prose problem again.
A skill is the right wrapper only for the command a person types.

### Decision 6: How the owner is identified, where the owner's decision may be recorded, and what weight it carries

The read of what is open for a person matches a handle exactly, so every
session has to name the workspace's one owner the same way. Today nothing
does: coordinator records name the owner in free text in four spellings or by
the relaying session's name, and no session had ever recorded a person as a
decider in koto. A second question sits under the first. The requirements let
the owner answer in any session with no ratifying step, while a planned
design for standing rules counts a rule as the owner's only when the decision
behind it was entered at a root coordinator. That test is unbuilt, and that
design names it as the one thing to replace if the owner may speak elsewhere.

Delegated to /decision. Two research agents read the repositories and about
twelve weeks of session transcripts; four alternatives went through a
bakeoff, a revision round and a cross-examination, and two reviewers
abandoned their own alternatives. All four converged on everything below
except whether to replace the planned root test now. They split two against
two and the author ruled: replace it now.

Key assumptions:

- One owner per workspace holds across the machines a workspace uses.
- The harness records an answered question prompt with its call identifier,
  the question, the options and the answer. That is observed behaviour and
  not a documented contract.
- Nothing but the owner can answer a question prompt in an attended session.
  Not tested.
- koto can read the harness's record of a question-tool call for the session
  an answer is recorded in, as it already takes the harness session and
  whether a person is attending as observed facts.
- The standing-rule classifier is still unbuilt for decision citations when
  this lands, so replacing its root test reworks no code.

#### Chosen: one literal handle, recorded anywhere, counted as the owner's only with the answered prompt behind it

The owner is `owner`: `person:owner` as koto's person decider, defined once
in the shared question reference and held as one constant in the one command
that records a person decision. It carries no name. koto stays general and
accepts any handle.

An answer the owner gives through the question prompt is recorded as the
owner's in whatever session they gave it, and takes effect when recorded. It
is recorded with `person:owner` only when it carries the call pointer of a
question prompt the owner answered, and only in an attended run. The
recording command refuses otherwise, at a root coordinator as much as in a
worker: being the root says nothing about whether the owner spoke. The
command copies the question, the option labels and the answer from the
recorded question and the prompt's result, so what is recorded is the owner's
choice and not a session's paraphrase.

The author set the principle for how that evidence is trusted: koto verifies
it once, on the spot, and from then on every reader trusts that it was
verified. The session hands koto the pointer; koto checks it deterministically
when the answer is recorded and records nothing if the check fails; the entry
then carries koto's own mark that the evidence was verified. On that machine
no session and no later reader opens a transcript again. The record lives in
the koto session on the machine where the owner answered, because that is the
only place the answer can be verified. Read on another machine, the same
entry is evidence that a session there answered the question, which is as
much as that machine can verify, and it does not carry the owner's authority
there. Carrying a verified claim between machines that share koto's cloud
storage is a later feature. What is left to agents is what koto cannot do: reading what the
owner said and judging whether an action fits it. If the owner said patches
may be released and a session later wants to release a major version, the
push-back rests on the content of that answer, never on whether the owner
gave it.

Everything else is a relayed claim. A decision naming the owner without that
pointer, and anything the owner typed that was not put back to them through a
prompt, is recorded as the hearing session's own decision with the owner
noted. The hearing session may act on it. For any other session it can
restrict and never grant.

An answer and a standing rule are told apart when the question is raised,
never by reading the words afterward. A question, or one of its options, is
marked as setting a standing rule, and the owner sees the mark when choosing.
An unmarked answer reaches the work items recorded as waiting on its question
and nothing else; a session that settles a similar question from it records
its own decision citing the answer, and that reuse binds nobody. When the
owner types a rule, the hearing session puts the exact text and its scope
back to the owner in a marked prompt in the same turn, and records the rule
on a yes.

The standing-rule classifier's root test is replaced: a rule row reads
owner-said when it cites a `person:owner` decision whose evidence koto
verified and whose question carried the standing mark, wherever it was
entered on this machine. One without them, and one verified on another
machine, reads inferred and grants nothing, as a bound session's did. The
classifier reads koto's mark and checks nothing itself. This amends
`DESIGN-coordinator-standing-rule-provenance.md` and its plan.

A coordinator can list the owner's answers given at and below it that it has
not marked seen. Marking one seen ratifies nothing, and a handover reports
any left unseen.

The evidence behind this shape is what was found in practice. The owner
answers in whatever session is in front of them: about 220 typed turns on one
machine, none at the top coordinator, which runs on another. Carrying those
answers to the top took nine minutes to an hour and once had the owner answer
twice. Every false attribution of the owner's word was typed text or a relay
turned into a rule for other sessions, and none was an answer to a question
the owner had been asked. None could have produced an answered prompt.

#### Alternatives Considered

**Open handle.** Any session records the owner with no evidence, and any
person decision reads owner-said. Rejected because it gives every session an
official way to mint an owner ruling. Its reviewer withdrew that test and
kept only open recording, which the chosen shape has.

**Root only.** Only a root coordinator records the owner; an answer given
elsewhere is a claim until confirmed at the root. Rejected, and withdrawn by
its reviewer, because the confirmation is the same answered prompt moved to
another place, it adds a ratifying step, the root was absent from every owner
turn on the measured machine, and the false attributions happened under
root-by-convention practice anyway.

**Evidence from how the turn started.** Count a turn the transcript labels
as typed by a person. Rejected because that label was the owner in about one
turn in eight; the rest were dispatch briefs, scheduled wake-ups, notices and
injected relays.

**Keep the root test for standing rules for now.** Record the pointer and
the mark from the first release and switch the classifier later. Two
reviewers ended here, because loosening later downgrades nothing and a
pointer cannot be opened from another machine. The author chose to replace
the test now, and settled the other-machine concern: koto verifies the
evidence once, on the machine where the owner answered, and on another
machine the entry reads as a remote session's answer without the owner's
authority until verified claims can be carried over shared storage.

**The workspace manager's principal setting as the handle.** Rejected by all
four reviewers: it is unset on the measured machine, declared per machine,
barred from gates by its own requirement, and puts a personal name in records.

## Decision Outcome

**Chosen: 1 (aimed answers on the decision record) + 2 (one decide-first state) + 3 (script enforcement and a thin command) + 4 (a narrow guard) + 5 (a `shirabe question` command family) + 6 (`owner`, with the answered prompt as evidence)**

### Summary

A question becomes a record in koto the moment a session cannot settle it. The
session that raises it writes one `escalate` decision in its own koto session,
with a typed recipient (`session:`, `anchor:` or `person:owner`), the kind of
need, a subject label and the hash of its content; the content itself (context,
problem, question, recommendation, alternatives with reasons, the ground, the
waiting work items) is stored beside it as write-once bytes of at most 16 KiB.
That pair, the raising session's id and the decision's id, is the question's
identity for good. Passing it up, answering it, settling it and withdrawing it
are each a new write-once entry in the session of whoever acts, aimed at that
identity. koto computes on every read who the question is currently addressed
to, whether it is open, and which answer is in effect, with the owner's answer
ahead of any session's. Three reads serve everything above koto: open questions
at and below a position, open questions for a person, and the owner's earlier
answers in a chain by subject label. Each is one scan of the machine's own
sessions, measured at about a tenth of a second for a thousand.

shirabe wraps those in one command family, `shirabe question`, which is the
only writer and the only renderer. `raise` validates the content and refuses a
question with a part missing or over the size bound; `pass-up`, `settle`,
`withdraw` and `answer` record the matching entries; `pending` lists what is
open at and below a session and for the owner; `render` turns a recorded
question into the text and options of a question prompt, and because it is a
pure function of the stored bytes, a question presented after a context loss is
identical to the one that would have been presented before. `answer` records
the owner's choice as `person:owner` only when given the call pointer of the
prompt the owner answered and only in an attended run, copying the question,
the option labels and the answer from the record and the prompt's result.

The workflows reach those commands at three places. Each worker template has a
`decide_first` state in front of the exits where an agent declares it cannot
continue; koto delivers the procedure there, and a gate refuses to let the
session leave without a recorded attempt and, when undecided, a raised
question. `/execute` then parks the issue and takes the next; a single-issue
run ends at a waiting result naming the question. The coordinator's existing
scripts refuse to pass a question up without an attempt, hold a worker's
question by identity, and release up to four at a time by recorded impact. And
`/shirabe:pending` runs the whole pass on demand in any session, including one
no workflow drives.

A session learns it was answered from `koto next`, which reports any answer to
one of its questions that it has not yet cited, on every tick until it does. A
pre-tool hook keeps a question prompt from opening except in an attended
session, in a turn a person typed. `/decision` and the lightweight protocol can
end undecided and hand back the question with its recommendation.

Edge cases the implementation has to hold: a session whose dispatcher link was
not recorded addresses the owner and marks the question; a superseded raiser's
question is answered at the predecessor's identity and reported to the
successor; an explicit cleanup of a session holding an open question is
refused without a force flag; a need carries no secret; an answer naming a
question that does not exist is refused; a second answer from the owner cites
the first and wins; an entry naming the owner without a prompt pointer is
recorded as the hearing session's own and grants nothing to others.

### Rationale

The decisions hold together because each leaves the next a fact to read. koto
owns identity, addressee, open and answer, so every reader agrees on what is
waiting; shirabe owns content and presentation, so one validator and one
renderer make restore exact; the templates own the moment, so the procedure
arrives when it is needed and not from memory; and the owner's word is tied to
an act the workflow engine can verify, answering a prompt, with the limits of
that verification stated under Security Considerations. Storing each
entry where it is written keeps koto's rule that only a session's own
processes write its keys, at the price of a tick read that looks outside the
session's chain. Enforcing the coordinator in scripts keeps running
coordinators takeable, at the price of no new state to prompt them, which the
on-demand command covers. The guard is narrow so that it can be trusted, and
it falls back to the per-session signal where the turn's origin cannot be
read.

## Solution Architecture

### Overview

Three layers. koto holds the record and answers the reads. The `shirabe`
binary validates, records and renders. The skills (three worker templates, the
coordinator's scripts, the decision skills, one on-demand command and one hook)
decide when those run. Nothing above koto stores a question, and nothing but
`shirabe question` writes one.

### Components

**koto: the decision record (changes in the koto repository)**

- `escalate` gains a typed `recipient` (`session:<name>`, `anchor:<name>`,
  `person:<handle>`) and three optional subject fields: `need` (`decision`,
  `credential`, `reserved-step`), `label` (at most 128 bytes) and `packet` (a
  hash of the content). An untyped recipient on an existing entry stays
  readable.
- `escalate` also gains an optional `state`, the workflow state and visit a
  question was raised from. `judgment` gains two optional subject fields:
  `state`, and `result` (`decided`, `undecided`, `provisional`). An attempt to
  decide is a `judgment` carrying both, and a provisional decision is one
  whose `result` is `provisional`. Listings filter on either field.
- A fourth write-once area, `koto/packets/<decision-id>`, holds the content
  bytes, capped at 16 KiB.
- Two new kinds: `readdress` (outcome `passed`) and `answer` (outcomes
  `answered`, `settled`, `withdrawn`).
- Verification of a person's answer. An `answer` by a person decider names
  the question-tool call the person answered. koto reads the harness's record
  of that call for the session the answer is recorded in and refuses the entry
  unless the call exists, is the question tool, shows the stored question's
  text and option labels exactly, carries the question's identity, holds a
  result from the user, and has not been cited by an earlier answer. koto
  takes the answer text from the call's result itself; the caller does not
  supply it. An accepted entry carries the evidence with koto's observed mark
  that it was verified, and every read returns that mark. If the harness's
  record has a shape koto does not recognize, koto refuses the answer. koto refuses an
  `answer` by a person with no such evidence. Both are stored under
  `koto/aimed/<raiser-session-id>/` in the acting session or anchor; the aimed
  area, which today accepts only reversals, accepts them. A reversal of either
  is refused. Statuses are unchanged.
- Read-time resolution of the current addressee, of open, and of the answer in
  effect, as Decision 1 sets out.
- Reads: open questions at and below a session or anchor; open questions for a
  person handle; a person's answers in effect in a chain, narrowed by label;
  one question's whole history; one question's content bytes. All use the
  scan of this machine's sessions and make no bucket request.
- A question read on `koto next`, active only while the session's run holds an
  open question or an answer it has not cited, reporting answers in a
  `questions` array on every response including a terminal one. It writes
  nothing, makes no network request and never blocks.
- A ring of the asker's wake file when an answer, settle or withdrawal is
  recorded.
- Retention: a session holding an open question is kept; an aimed entry links
  its holder to the question's session. `koto session cleanup` refuses a
  session holding an open question or the answer in effect for one unless
  forced.
- koto's decision-record requirements and design, and its retention design,
  are amended to say all of this; new requirements are numbered after the
  existing ones.

**shirabe: the `question` command family (`crates/shirabe`)**

| Subcommand | Does |
|------------|------|
| `raise` | Validates content (context, problem, question, recommendation with reason, alternatives with reasons, ground, waiting work items, label, optional standing mark, optional dependency on another question), refuses a missing part, content over 16 KiB, content matching known secret patterns, a dependency cycle, or a twenty-first open question addressed to a person from the same session; works out the addressee from `koto session origin` (a session dispatcher, else `person:owner`, marking an unrecorded link); writes the content and the `escalate` entry. A need takes a kind and what is needed in place of options; a credential need names the credential and never holds its value. |
| `attempt` | Records that a decision was attempted for a state and visit, with its outcome: an option chosen, or undecided. It writes a `judgment` with `state` and `result`, which is what the gates read. |
| `pass-up` | Records a `readdress` to the session's own dispatcher or to `person:owner`, with the ground relied on; refused without a recorded attempt unless the question is a need. |
| `settle` | For a question addressed to this session, writes an `answer` with outcome `answered` and a session decider. For the raiser's own question, writes an `answer` with outcome `settled`, citing an earlier answer or evidence. A provisional decision on a contested call that raised no question is a `judgment` with `result` `provisional`, carrying the cheap-or-costly judgment in its text. |
| `withdraw` | Records the raiser's withdrawal with a reason. |
| `answer` | Records the owner's answer as `person:owner`. Requires the call pointer of an answered question prompt and an attended run, and hands the pointer to koto, which verifies it before writing (see the koto components). Copies the question, option labels and answer; cites the owner's earlier answer when one exists. Without a pointer it refuses and names `settle` with an owner note as the way to record a relayed claim. |
| `pending` | Lists open questions at and below the session and those for `owner`, ordered by recorded waiting work items, then age, then identity, with dependent questions held. Also lists the owner's answers given at and below the session that it has not marked seen. |
| `render` | Produces the prompt text and options for up to four questions from their stored content. Deterministic. |
| `seen` | Records that this session has read an owner answer given below it, as a `judgment` in this session whose basis names the answer. Ratifies nothing. An owner answer is unseen by a session while no decision in that session's run names it as a basis. |
| `precedent` | Lists the owner's answers in the session's chain, optionally by label. |
| `provisional` | Lists the `judgment` entries at and below the session whose `result` is `provisional`. |

The owner's handle is one constant here and nowhere else in shirabe.

**shirabe: the shared reference**

`references/question-procedure.md`, organized by where a session sits (no
dispatcher; a session dispatcher; a coordinator with sessions below it). It
states the sort, the settle-unless-reserved rule with its grounds, the
cheap-or-costly test for an unattended run, how to raise and what a question
must contain, the standing mark, present-or-wait, and the meaning of `owner`.
`references/decision-presentation.md` gains the prompt's limits and points
here; `references/decision-protocol.md` gains the third outcome.

**shirabe: the worker templates**

`skills/work-on/koto-templates/work-on.md`,
`skills/execute/koto-templates/execute.md` and
`skills/scope/koto-templates/scope.md` each gain a `decide_first` state and a
waiting terminal. The state's directive names the reference and the three
commands a session runs there: `attempt`, `precedent` and `raise`. Its gate is a command gate calling a script that reads the session's
attempts and questions through `shirabe question`. Each template's result map
gains a `question` field carrying the identity. A run that ended at the
waiting terminal is resumed by invoking the skill again: the new session
continues the waiting one through koto's existing succession, so its first
`koto next` reports the answer to the predecessor's question, and it re-enters
the state the question was raised from.

**shirabe: the coordinator**

`skills/coordinate/scripts/state-decision.sh` refuses a pass-up without an
attempt and stores the question's identity in the entry;
`decision-next.sh` releases up to four by impact; `decision-render.sh` calls
`shirabe question render`; `report-questions.sh` accepts a question's
identity in place of a bare line; `references/brief-template.md` tells a
worker to raise a question instead of listing one. The standing-rule
classifier in `state-schema.jq` reads owner-said for a row citing a
`person:owner` decision that carries the prompt pointer and the standing
mark, wherever entered. No state is added to `coordinate.md`.

**shirabe: the decision skills**

`/decision` gains the `UNDECIDED` result and keeps its research keys on that
path; `/design` and `/explore` raise the handed-back question from the session
they run in.

**shirabe: the command and the guard**

`skills/pending/SKILL.md` is the on-demand command, a thin wrapper around
`pending`, the settle-or-pass-up pass, `render`, the question prompt and
`answer`. `hooks/hooks.json` gains the pre-tool entry for the question tool,
and a second entry if the spike chooses the prompt-submission mark; the logic
is `shirabe hook question-guard`.

### Key Interfaces

**A question's identity**: `<raiser-session-id>/<decision-id>`, printed by
`raise` and accepted by every other subcommand.

**Content**, as stored and hashed: one JSON document with the keys `context`,
`problem`, `question`, `options` (each with `label`, `reason`, and an optional
`standing` mark; the first is the recommendation), `ground`, `waiting` (work
item identifiers), `label`, `depends_on` (an optional question identity), and,
for a need, `need` and `needed` in place of `options`. Keys are written in
that order with no insignificant whitespace, so the same question always
hashes and renders the same. The format is fixed at the first release, since
restore compares bytes.

**The prompt pointer**: the harness session id and the question tool's call
id, handed to koto with the `answer`. koto resolves it to the harness's record
of the call, verifies it, and stores it with its verified mark. `render` puts
the question's identity into the prompt so koto can match the call to the
question. Nothing else resolves the pointer afterward.

**Gate contract** for `decide_first`: exit 0 when the outcome submitted
matches the record (a chosen option for `decided`; an undecided attempt plus
an open question naming this state for `raised`), exit 1 with a finding
otherwise.

**`koto next`'s `questions` array**: each element carries the question's
identity, its state and the answer in effect with its decider. A session
acknowledges by recording a decision that cites the answer.

**The guard's input and output**: the hook's standard input names the tool,
the session and the transcript; its output allows or denies with a reason.

### Data Flow

1. A worker reaches a covered exit. The template routes it to `decide_first`
   and records where it came from.
2. The worker runs the lightweight protocol, or `/decision` when the choice is
   contested, and records the attempt. If an option was chosen it submits
   `decided` and returns. If not, it sorts the question, checks precedent,
   and runs `raise`; the question is now open, addressed to its dispatcher or
   to `owner`. It submits `raised`.
3. The run continues with other work or ends waiting, its result carrying the
   identity.
4. A coordinator's `pending` shows the question as addressed to it. It
   settles it, or passes it up with the ground; the identity does not change.
5. In a turn the owner started, any session that can read the question renders
   it, opens the prompt, and on an answer runs `answer` with the prompt's call
   pointer. The entry is stored in that session, aimed at the question.
6. The asking session's next `koto next` reports the answer. It acts, and
   records a decision citing the answer, which stops the report.
7. Coordinators above see the answer in their unseen list and mark it seen. A
   later session with a similar question finds it through `precedent` and
   settles its own, citing it.

A need follows the same path from step 2's `raise`, skipping the attempt, and
is presented as a request. A standing rule is a question raised with the
standing mark; its `answer` is what a rule row cites.

## Implementation Approach

koto's part ships and is released before shirabe depends on it. Within each
repository the phases land in order.

### Phase 1: koto requirements and designs amended

Amend koto's decision-record requirements and design and its retention design
to state the typed recipient, the new subject fields, the two kinds, the
content area, read-time resolution, the three reads, the tick read, the ring
and the two retention rules. No code.

Deliverables:
- the amended requirements, design and retention design in the koto repository

### Phase 2: koto parses, stores and verifies the new shapes

The typed recipient and new subject fields on `escalate`, the `readdress` and
`answer` kinds, the content area with its cap, and the aimed area accepting
non-reversal entries. This phase ships no later than koto's planned read of
reversals at `koto next`, since a binary that cannot parse an aimed entry
reads it as unreadable.

Deliverables:
- decision body, store and guard changes, with unit tests
- verification of a person's answer against the harness's record of the
  question-tool call, with the verified mark, tested with recorded fixtures
  for a matching call, a missing one, a call for another question, a result
  not from the user and a reused pointer
- refusal of a reversal aimed at an `answer` or `readdress`

### Phase 3: koto reads

Read-time resolution, the open reads by position and by person, the precedent
read, the question history and the content read, all on the local scan, with
the five-second bound tested at 1,000 sessions and 200 open questions on both
storage backends.

Deliverables:
- the reads and their command-line surface
- fixtures for no coordinator, one and two; a passed-up question returned once;
  an unlinked raiser returned by the person read

### Phase 4: koto discovery, ring and retention, then a release

The question read on `koto next`, the wake-file ring on a closing entry, the
two retention rules and the cleanup refusal. Then a koto release.

Deliverables:
- the tick read with its bound tested, the ring, retention changes
- a koto release, and its version number for shirabe's floor

### Phase 5: the guard spike (shirabe, independent of koto)

Capture what a pre-tool hook and a prompt-submission hook receive, and what
the transcript records, for a typed prompt, a dispatch brief, a scheduled
wake-up, another session's message and a background notice. Decide the
guard's source of the turn's origin, or record that only the attended
fallback is available.

Deliverables:
- a short recorded finding and the fixtures the guard's tests use

### Phase 6: `shirabe question` and the shared reference

The command family against the released koto, the reference, and the raised
koto floor. Byte-identical rendering tested from the store alone.

Deliverables:
- `crates/shirabe` subcommands with tests
- `references/question-procedure.md`; updates to `decision-presentation.md`
- the koto version floor

### Phase 7: the decision skills end undecided

`/decision`'s `UNDECIDED` result with its research kept, the lightweight
protocol's third outcome, and `/design` and `/explore` raising the handed-back
question. Supersedes the passages that say an unattended run follows its
recommendation and continues.

Deliverables:
- the skill and reference changes, with script cases for the undecided result
- a decision record superseding the accepted intent-change-owner decision

### Phase 8: worker templates

`decide_first`, its gate script and the waiting terminal in `work-on.md`,
`execute.md` and `scope.md`, with `/execute` parking an issue on a question.
Rebased on the open changes to those templates.

Deliverables:
- the three templates and their engine tests, including the unchanged-path
  tests for runs that reach no covered exit

### Phase 9: coordinator scripts and the standing-rule classifier

Pass-up refusal without an attempt, entries by identity, release of up to
four by impact, the shared renderer, the brief's reporting text, and the
classifier's evidence test in place of its root test, with the standing-rule
design and plan amended to match.

Deliverables:
- the script changes and their tests; the amended design and plan
- the superseded passages changed, checked by the phrase search

### Phase 10: the on-demand command and the guard

`/shirabe:pending` and the pre-tool hook, using the source Phase 5 chose.

Deliverables:
- `skills/pending/SKILL.md`; `hooks/hooks.json` and the hook logic with tests
- a shirabe release

### Phase 11: dogfooding

On the released koto and shirabe, in the tsukumogami organization: one chain
with a worker under a manager and a director, and one unattended worker with
no coordinator. The record must show a question settled below the owner, one
the owner answered in a worker, one answered at the top coordinator, one
restored after an induced context loss, and one raised by the solo worker and
answered on return. Findings go in the tracking issue, and each is fixed or
filed before the work is closed.

Deliverables:
- the record output for each of the five events, attached to the closing pull
  request or issue
- the findings list with a commit or issue against each entry

## Security Considerations

The feature reads and writes local koto session state, runs one hook and a few
gate scripts, and shows recorded text to a person and to other agents. It
downloads nothing and adds no dependency. The risks are impersonation of the
owner, one session acting on another's question, untrusted text reaching a
prompt or an agent, secrets in shared records, and sessions kept alive by
questions nobody answers.

**Impersonating the owner.** koto accepts any person handle from any caller,
so the control is the evidence, and koto is the one that checks it. When an
`answer` by a person is recorded, koto reads the harness's record of the call
the pointer names and writes nothing unless the call exists in that session,
is the question tool, shows the stored question's text and option labels
exactly, carries the identity of the question being answered, holds a result
that came from the user, and has not been used for an earlier answer. koto
takes the answer text from that result, so a caller cannot pair a real
pointer with words the owner did not choose, and a prompt that asked
something other than the stored question cannot be recorded against it. The entry then carries koto's mark that its evidence was verified,
labelled as observed by koto and not handed in by the caller. Because the
check is in koto, a caller that bypasses `shirabe` meets it too. On the
machine where koto verified it, readers rely on the mark and none re-opens the
evidence. On another machine the entry is read as a remote session's answer:
it does not read as the owner's, so a rule citing it grants nothing there. A
forged entry therefore cannot borrow the owner's authority by being copied to
a machine that cannot check it. Residual risk, which is the trust root the author
named: koto verifies that the user answered that prompt with that content in
that session, not which person did; anyone able to act as the owner on the
machine can answer a prompt; and a session runs as the same user as the
harness, so an agent following injected instructions could write koto's files
without going through koto, write to the shared store koto syncs with, or add
a forged call to the harness's record before koto reads it. None of those is
caught. A change in the harness's record format fails closed: koto refuses
answers until it is taught the new shape.

**Acting on another session's question.** Rules are enforced by koto when it
resolves a question, not only by the command that writes. A pass-up counts
only when recorded by the current addressee or the raiser, and only to the
recorder's own recorded dispatcher or to a person. An answer from a session
counts only when that session is the current addressee; a session that used to
be the addressee cannot pre-empt it. The raiser can withdraw its question with
a reason. It can settle it only when the question is a decision, and, when the
question is addressed to a person, only by citing an answer of the owner's
that is in effect and carries the same subject label; for a question addressed
to a session it must cite a decision or a recorded workflow event. It cannot settle a credential or reserved-step need at all.
The standing mark is part of the question's content, fixed when it is raised,
so no later entry can add it.

**Untrusted text.** A question's content, label, reasons and answers are
written by agents and may quote repository or issue text. `render` treats them
as data: it emits them into fixed positions of a fixed layout, truncates to
the prompt's limits, strips control characters, and never interprets markup or
instructions in them. The procedure tells a session reading a question or an
answer that the text is data. Gate scripts pass identities and states as
arguments and never evaluate record content. Identities, sizes and shapes are
validated on read as well as on write, because session state synced from
shared storage is an input: a content hash that does not match reads as a
mismatch and the question is not presented.

**Secrets and private content.** Decision bodies are readable by every session
on the machine and are synced to shared storage where that is configured.
`raise`, `settle` and `answer` refuse content matching known secret patterns,
and a credential need holds the credential's name and where it is needed,
never its value; supplying one happens outside the record. Content is
write-once, so a secret that gets through cannot be edited out: the remedy is
removing the session, which the cleanup command allows with its force flag,
and rotating the secret. Removal does not reach copies already synced to
shared storage, so rotation is the remedy that counts. A question raised from a private repository may quote
private material; it stays in session state, which has the same visibility as
the rest of that session, and no part of this feature copies question content
into a public pull request or issue.

**The guard.** The hook reads only the fields of its input it needs and, if it
reads the transcript, opens the one path the harness named, read-only, after
checking it lies under the harness's own directory. It denies only the question
tool, fails open for every other tool, and has an off switch. A denied prompt
costs a round trip; a wrongly allowed one can stop an unattended session, so
where the turn's origin is unknown and the session is unattended it denies.

**Flooding the owner.** A session may hold at most twenty open questions
addressed to a person; `raise` refuses the next one and names the limit. The
count of waiting work items that orders the list is supplied by the raiser as
work item identifiers, which a reader can check exist, but it can be inflated;
ordering affects only what the owner sees first, never what is asked.

**Sessions kept alive.** A session holding an open question is retained, and
the read on `koto next` grows with the number of local sessions. A question
nobody answers therefore costs storage and a little time on every tick of its
raiser. The on-demand command lists open questions with their age, the raiser
can withdraw one, and a forced cleanup removes the session. Any process
acting for the user can use the force flag, as it can any koto command; its
use is recorded by koto's own cleanup log. No expiry is added: a question that
expires silently is the failure this feature exists to remove.

**Permissions.** No network access or privilege is added. The one new write
area, for question content, sits inside koto's session directories and keeps
their permissions. koto gains read access to the harness's record of a
session's question-tool calls. The hook runs with the session's own
permissions.

## Consequences

### Positive

- A session about to stop is handed the procedure by the workflow and cannot
  leave without a recorded attempt, so "blocked on the owner" stops being a
  sentence and becomes a record with a recommendation behind it.
- One read returns what is open for the owner across a workspace, and another
  what is open under any coordinator, without interpreting prose. A status
  view can show both from session state.
- The owner answers once, in whatever session is in front of them, and the
  answer is found by the session that asked, listed for the coordinators
  above, and reusable by later sessions.
- A waiting question survives a restart, a context loss and a coordinator
  handover, and is shown again exactly.
- The owner's word is distinguishable from a claim of it by a recorded fact,
  and the standing-rule work gets a test that does not depend on position.
- A question prompt can no longer stop an unattended session.
- Every decision made on the way has a decider on the record.

### Negative

- koto's part is a real build across its decision body, store, reads,
  `koto next` path and retention, and it amends requirements that are still
  in progress.
- The read on `koto next` looks outside the session's chain and grows with
  the number of local sessions: about 15 ms at a thousand, an estimated 75 to
  115 ms at ten thousand.
- Hierarchies grow. An answer links its holder to the question's session, and
  a question nobody answers or withdraws keeps its session.
- An owner decision can only come through the question prompt, so a rule the
  owner types costs one extra selection before it binds other sessions.
- Three templates gain a state and a terminal, and sessions opened before the
  change do not get them.
- Coordinators that run in no workflow session are not prompted; they get the
  procedure only when the command is run.
- A planned design and its plan are amended by this work.
- Reads and answer discovery stop at the machine boundary.
- koto gains a dependency on the shape of the harness's record of a
  question-tool call, which is observed behaviour and not a documented
  contract.

### Mitigations

- The koto changes are staged so that parsing ships before anything writes the
  new kinds, and shirabe checks a version floor before using them.
- The tick read runs only for a session that has an unfinished question, and
  its bound is a tested requirement.
- `koto session cleanup` refuses a session holding an open question, and the
  on-demand command surfaces questions nobody has answered.
- The extra selection for a typed rule is one prompt in the same turn, and it
  is what keeps a session from broadening the owner's words.
- Runs that reach no covered exit are tested to be unchanged.
- The on-demand command is named in the coordinators' standing rule, so a
  brief-driven coordinator runs it as it runs its other rules today, and
  moving such coordinators into a workflow session is left to the work that
  owns that.
- The amended standing-rule design changes no merged code, because the test
  being replaced was never built.
- The machine boundary is stated as a limit: an answer given on one machine
  is found on another only after its session is pulled there, and there it
  reads as a remote session's answer without the owner's authority. Carrying
  verified claims between machines that share storage is left for later.
