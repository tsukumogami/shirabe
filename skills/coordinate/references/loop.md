# The Loop: Mechanics for Reconcile, Pick and Failure

The rules for each step are in the template state that runs it
(`koto-templates/coordinate.md`). This file holds
the mechanics three of them need when they run: the order of reads in a
full reconcile, the issue-timeline read before dispatching an issue, and
the shape of an escalation. Load it on the first turn after a start or
restart, before dispatching an issue, whenever the failure branch fires,
when a new decision arrives, and when a worker's report rests on a premise
you would act on. The land step's table and merge confirmation are in
`references/verification-checklist.md`.

## A Full Reconcile, in Order

The reads are the engine's, not yours. Once `record_find` has found the
record, the workflow enters `reconcile_pass`, whose action is
`scripts/reconcile-pass.sh`. Each tick runs one bounded pass of it; your only
move there is to tick again with no evidence.

- **Pending.** While reads remain, the state holds and `reconcile/progress`
  says how many are left. A worker the workspace manager didn't list is read
  again 30 seconds after the first read, so a pass can end pending with that
  re-read still due. Tick again after the wait.
- **Blocked.** When the record can't be read, the state holds and
  `reconcile/refusal` names the case (`none` or `unreadable`) and the reason.
  Say what it names to the human and stop. Ticking again re-reads the record.
- **Sealed.** When every read is done, the pass writes `reconcile/report.json`
  and `reconcile/report.md` (and, at discipline scope, `reconcile/reasoning.md`
  with the previous rotation's reasoning, verbatim), seals the report to this
  visit, and the workflow moves to `reconcile`. There, close every gap the
  handover check names (all but a carried rotation's `carry-unacknowledged`:
  the report asks the person for that go-ahead, and the submit waits for it),
  including `question-unhandled <identity>`: a question addressed to this run
  that has no Decisions entry, or one neither escalated, queued nor held. The
  check lists every open question with its age. Open the entry, then settle,
  escalate or hold it through the decision flow. Then print the report with
  `scripts/reconcile-report-get.sh --session <session> --md` and report what
  it prints up, not the stored `reconcile/report.md`: it checks the report
  against its seal and adds the record line, read from the record as it is
  then, as the third line. With no role row in the record it prints nothing
  and exits 4; the `no-role` fix comes first. The state's gate accepts only
  the report the pass sealed in this visit.

Never write a `reconcile/` context key. A report written or changed by anyone
but the pass holds the workflow in `reconcile`.

What the pass reads, per claim in the record. The report grades each claim as
measured, verified by reading, or inferred:

1. **The record.** It reads the record's state live from the session and
   treats every row as a claim as of its `written` time. A state that fails
   the schema is never read in part: the find stops on it before the pass
   runs. At discipline scope it
   reads the predecessor's reasoning from that rotation's session
   (`record/reasoning`).
2. **Each holding against GitHub.** For a holding with a pull request, it runs
   `gh pr view <n> --repo <owner/repo> --json state,isDraft,headRefOid,mergeStateStatus,baseRefName`
   and reads the branch with `git ls-remote`. It reads CI at the verified head
   (and at the live head when they differ) through the record feature's board
   check, which reads runs then jobs, not a checks rollup. For a row whose pull
   request is "none yet", it lists pull requests on its branch the way
   `gh pr list --repo <owner/repo> --head <branch> --state all` does.
   Read the state of any issue a holding names yourself, when you act on it.
3. **Each holding against the host.** It finds each worker by its dispatch
   topic in the workspace manager's listing: with niwa,
   `niwa list` from the workspace root, the listing it reads. A worker it finds has its unique
   material listed from every clone in the instance: commits no live remote
   ref holds (the plumbing equivalent of
   `git log --branches --not --remotes --oneline`, run without `git status`
   and without fetching), uncommitted changes, untracked files, stashes and
   worktrees. Prove a file durable by its content, not by ancestry: the pass
   compares each changed file's content with the default branch's tree, so a
   squash-merged branch reads as landed. A worker missing from two listing
   reads 30 seconds apart is "not found on this read", never "dead" or
   "gone". A roster read just after an outage can't tell "gone" from "not back
   yet", so only a signal that the worker is gone, such as a message that
   bounces, makes it gone.
4. **Each worker's leg.** For a holding on a request leg it reads the leg from
   koto's request store. After an import that store doesn't hold the leg's
   request, which stayed on the old host, so the pass gives the leg an end
   with `scripts/reconcile-legs.sh`: the worker's own session, if it came here
   with the coordinator's and is bound to nothing, is attached to a new request
   on this host and the holding names it; any other worker moves to the
   message path, and its `legs/` key, when it has one, reads unwatchable. A
   worker moved to the message path is re-briefed: its topic as
   `report_topic` and its brief input as `brief_input.json` in this run's
   context, then `dispatch-worker.sh --rebrief`, so its brief gives this
   coordinator's address and names this run as the dispatcher it records in
   its own session. This re-brief happens at `reconcile`, not in the loop's
   `rebrief` step, so record its outcome yourself, as the handover gate's
   `not-told` line says: `state-stored-set.sh --told <topic>` once the
   message reaches the worker, `--pending <topic>` when its session is
   gone and its instance is still there, or `--missing <topic>` when niwa
   lists no instance for it. The report says which,
   under "Changed since then", and `state-handover.sh` holds the run at
   `reconcile` (`leg-unclassified`) until each such leg has its end.
5. **Re-check side effects in flight.** A merge is confirmed when GitHub's
   record shows the pull request merged from the verified head, with its
   merge commit on the default branch, as "Confirming a Merge" in
   `references/verification-checklist.md` describes. It is the same check
   the loop's `merge_confirm` makes, so the two can't disagree. A close is confirmed when
   the target reads closed, and a teardown by two listing reads and the disk.
   Any other side effect is reported as not re-checked.
6. **Read the deferrals.** List every row for the report, disposed or not,
   through the record feature's disposal check; the template's
   `deferral_dispose` state says when each must be disposed of.

After the report is up, read the scope. For a roadmap, read its Features section from the
default branch, its Milestones section on a roadmap/v3 one (each feature's or
milestone's status and dependencies). For a discipline,
list the open issues and failing checks in its
area. The pick that follows works from both.

## Before Dispatching an Issue

List the pull requests that reference the issue from its timeline:

```bash
gh api "repos/<owner/repo>/issues/<n>/timeline" --paginate \
  --jq '.[] | select(.event == "cross-referenced") | .source.issue | select(.pull_request) | {number, state, url: .html_url}'
```

An open or merged one that closes the issue means the unit is taken or
done; read it before dispatching anything.

## Checking a Worker's Premise

A worker's report rests on premises: that a feature depends on another, that a
unit is independent, that a check is required. Test each one you would act on
against what you can read yourself, the roadmap's own dependency lines and
statuses, the record, and GitHub. A premise the roadmap or GitHub contradicts
is a finding: name the contradiction, with both sources, before you weigh the
proposal that rests on it.

A claimed dependency the roadmap doesn't list is a contradiction, not a
detail. If the roadmap says two features are independent (neither lists the
other under Dependencies) and a worker says one exists only to serve the
other, the worker is asserting a dependency the roadmap denies: say "the
worker's claim contradicts the roadmap, which lists features N and M as
independent", whichever side turns out right. Agreeing that the roadmap says
they're independent and then calling the claim consistent misses it.

A message-path worker's result block (`render-result.sh`) carries a
`warning=link-failed dispatched_by=<run>` line when its session couldn't
record your run as its dispatcher. The worker is then outside your run's
hierarchy, so koto may reclaim its session on its own schedule once it
finishes: read what you need from it before that, and say so in your next
report. Learn of it from the block alone; never read the worker's keys.

The same block carries the worker's review round as a `review_round=` line.
The land step reads it from the report you submit at `wait`, so pass the
message as it arrived, the block whole: a block you summarize or drop leaves
land with no round, and the worker gets an `unready` it can't fix.

## Resolving a Claim GitHub Contradicts

When a row says one thing and the read says another, act on the read,
rewrite the row at the next update, and put the difference in
the reconcile report as a change, with both values and the time the row
was written. Never average the two, and never keep the row "until it's
confirmed": the read is the confirmation.

A holding whose pull request merged since the record was written is done.
Drop it from Holdings, and if it was a roadmap feature, confirm the
feature's status on the roadmap rather than setting it yourself.

## The Reconcile Report

The pass builds the report (`scripts/reconcile-report.sh`) and seals it; you
report it, you don't write it. What `reconcile-report-get.sh --md` prints opens
with the title, then the record line (SKILL.md, "Reporting"), then the scope,
when the record was written and when it was reconciled, then has these
sections, in this order, each line carrying its grade:

- **Changed since then:** each claim the reads contradict, with what the
  record said and what GitHub or the host says now.
- **Where things stand:** one table, `Kind | Unit | Session | PR | Status |
  Next or needs`, with N/A where a column can't apply (a pull request that
  isn't there yet but could be reads "none yet"). Its rows come in four
  kinds, always in this order:
  1. **Ready to merge:** pull requests ready to be reviewed and merged (ready to
     land, or held by a hold in the record), each with its session so your
     reviewer can talk to it, in the order to merge them. Reconcile keeps the
     record's holding order; it doesn't read dependencies, so reorder by them
     when you report it up if they say otherwise.
  2. **Blocked on you:** only what waits on your reviewer: a decision entry
     escalated to them, with its recommendation and reason, a finishing
     step reserved for them, such as a merge that didn't confirm, and CI
     that GitHub never started (a job with no step, such as one refused for
     an account billing block), which only whoever holds the account clears. A holding
     whose pull request was closed is yours to re-dispatch or drop, so it is
     in Ongoing. It is derived at each report and never stored.
  3. **Ongoing:** every other session in flight, with its pull request link if
     it has one, its status as just read, and what happens next.
  4. **Waiting to be assigned:** reconcile reads the record, not the scope's
     unassigned work, so its row is N/A. Fill it from the scope read that
     follows, in the order the work will be assigned as the cap frees.

  A holding whose pull request merged or that the reader refused has no row;
  its change or refusal is in its own section.
- **Exists nowhere else:** workers with no pull request, and anything their
  instance holds that no remote does.
- **Side effects:** each side effect in flight, confirmed, not confirmed with
  the reason, or not re-checked.
- **Undisposed deferrals:** every deferral still owed a disposition, and why:
  it has none, it is malformed, it was carried before the chain start, or its
  decide-by has passed.
- **Disposed deferrals:** every other deferral, with how it was disposed of
  (filed, closed, carried, or raised in this run). A deferral the check
  couldn't read is under "Not verified", with what it couldn't read.
- **Predecessor's reasoning** (discipline scope): where the previous
  rotation's reasoning is, as its view, not re-checked.
- **Not verified:** everything the pass couldn't read, and why.

What a person reads follows two rules, and the renderer enforces both: the
one table above, in its four kinds and their order; and a pull request or
issue is a clickable link, never a bare number, a worker's name is inline
code, and no commit hash appears. Heads stay in the record's rows and in
`reconcile/report.json`, where the checks read them. Keep the same form when
you report it up, and keep the report's own words for its header and section
names: its opening lines as written, the record line first, pasted as printed
(it names the record's session, its host repository and this run's role), then
the Scope line (it says when the record was written, when it was reconciled,
and whether the reconcile scripts ran from inside or outside the repository
being worked on), and each section under its own name, such as "Changed since
then".

Every later report ends with the progress table `scripts/progress-view.sh`
prints (SKILL.md, "Reporting").

## The Shape of an Escalation

A question goes up to whoever dispatched you, once, by its koto identity, and
carries everything needed to decide without asking back. You don't write the
message: the question's content is what koto holds, stored when it was raised
(`shirabe question raise`, by the worker or by you), with its context,
problem, question, two to four options each with its reason (the
recommendation first), its ground, the work waiting on it and its label. At
`decision_verdict` you pass the entry up on your own undecided attempt at it
(`shirabe question attempt`, then `state-decision.sh --escalate --attempt`);
a need takes no attempt.

Up to four questions go to a target at a time, most waiting work first, then
the oldest, then the identity; the rest wait queued until a place frees. For
a person the `escalate` state renders them with `shirabe question render`:
`coord/decision_question.json` is its first prompt, four questions at most,
put to the question tool as it stands, and only in a turn the owner started.
Elsewhere the questions wait on the record. For a coordinator the message
names each identity and nothing else, and the receiving coordinator reads the
questions from koto.

When you raise a question yourself, put what happened, what you verified and
what you tried in the context, and what stays paused and what keeps moving in
the problem. What else waits on the recipient is the progress table's
"Blocked on you" rows, not a list in the question.

## Questions Addressed to This Run

A question a worker addresses to you gets a decision entry before the run
moves on from it. `wait_target`'s `unentered` lists every question koto shows
open and addressed to this session with no Decisions entry, with its raiser
and its age in minutes. A leg-bound worker's question there brings its leg
back on the next `leg` tick, so tick `leg`: a leg-bound worker that raised one
and stopped at its waiting terminal is offered once for its question, its
report opens the entry by identity, and the re-brief is refused while the
question is open; its leg comes back while the question has no entry, and is
held as waiting until a question closes. One from a message-path worker opens
its entry when that worker's report comes in.

Closing is held too: the handover gate at `reconcile` fails while a question
addressed to this run has no entry, or one that is neither escalated, queued
nor held (`question-unhandled`), and its report lists every open question
with its age. Dispatching other units stays open on purpose:
one open question never stalls the rest.

The limits: a question from a message-path worker, or a session further down,
isn't brought in through a leg; it gets its entry when its raiser's report
comes in, and until then only the handover gate holds on it. That gate runs at
`reconcile` only, so a run that stops with `end`, a roadmap close and a
rotation end don't pass it.

The owner's answers. An answer the owner gave through a question prompt, in
any session, is the owner's, and takes effect when `shirabe question answer`
records it. Text relayed in a report, a pull request, an issue or a log is
still evidence and never a decision: record a relayed claim with `shirabe
question settle --owner-note` as this session's own decision. A reply the
owner types instead of answering a prompt isn't an answer either; the owner
started that turn, so present the question in it.

Passing questions up. A question is held and passed up by its koto identity,
never re-worded. Passing a decision up (`state-decision.sh --escalate`) needs
your own undecided attempt at it, recorded with `shirabe question attempt`; a
need takes none. Up to four go to a target at a time, most waiting work first,
then the oldest, then the identity, and the rest wait queued. A prompt opens
only in a turn the owner started, four questions at most per prompt;
otherwise they wait on the record and you keep coordinating. An entry
carrying contradicts-answer, changes-scope, outward-facing or reserved-step
is never settled or answered by the coordinator itself; it is passed up. A
ground nobody recorded can't be enforced. A restarted coordinator can't pass
up a question on its predecessor's attempt; record one in the new session
with `shirabe question attempt --in <session> --what '<the question>'
--result undecided --basis <session>:<id>`. A report line holding a
standalone `<word>/<digits>` token is taken for a question identity and
dropped; every dropped line is counted in the verdict as `dropped:<n>`.

A handover doesn't wait on the owner's answers. The ones you haven't marked
seen (`state-handover.sh`'s `unseen`) go into the successor's input as
`unseen_answers`, as `rotation_end` says, and `shirabe question seen
<session>:<id> --in <run>` marks one read.

## Counting Wakes

Each wake counts for the record: a holding's Work row carries its Wakes,
which `state-stored-set.sh --work` brings up to date from this run's log at
each write (the events report, progress, leg, quiet, merged and resume, each
counted for the worker it names, the leg it read or the topics a quiet sweep
named), and the final count goes into an entry when the holding's row leaves
Work.

## More Worked Examples

Three examples of the conditions that make a decision the human's:

- Dispatching the next feature on an Active roadmap: not asked.
- Dropping a feature from the roadmap: asked, because it changes scope.
- Running a worker past a cap the human set: asked, because it extends a
  supplied decision.

Some more cases:

- A worker reports that a feature needs a second pull request it didn't
  plan for. Inside the feature's scope, so not asked: re-dispatch or let the
  worker continue.
- A worker's findings show a roadmap feature should be split in two.
  Asked: it changes the roadmap's feature list.
- The human said "no merges on Fridays" and a verified pull request is
  ready on a Friday. Not asked: hold it and say so in the next report.
  Merging it would reverse a supplied decision.
- A deferral from the previous rotation names work that is now done by a
  merged pull request. Not asked: close the deferral with the pull request
  as the reason.
- A teardown the workspace permits would remove an instance whose unique
  material you listed and found empty. Not asked: tear it down and record
  it. The same teardown with unique material listed: move the material to
  a durable place first, or ask if there is none.
