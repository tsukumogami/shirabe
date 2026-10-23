---
schema: prd/v1
status: Done
problem: |
  A green check after a shirabe run can't be trusted to mean the behaviour
  landed. A pass that came from editing a test counts exactly like one that
  came from changing the code, review can't tell an edited test from an added
  one, and for a fix nothing shows the check ever failed for the reported
  reason, because /work-on doesn't know the work is a fix. In autonomous runs
  the same session writes the code and edits the test that judges it.
goals: |
  A fix starts from a check that fails for the reported reason, recorded
  before the correcting change, and ends with that same check passing. A
  unit's pass that came with an edited test isn't counted until someone other
  than the author accepts the edit, recorded with who and under what
  authority, and a higher authority can overrule that acceptance. Review
  floors and packets single out edited tests. All of it holds in autonomous
  runs and in repositories that require a person to accept.
upstream: docs/briefs/BRIEF-red-first-fixes.md
---

# PRD: red-first-fixes

## Status

Done

Amended 2026-10-23: pull requests carry no workflow-tool record. R19's pull
request section and the criteria that check it are withdrawn; the record lives
in the run's retained session only, and R18's record command is how anyone
reads who accepted and under what authority. Review's edited-versus-added
distinction (R20) stays in the review packet the seats read.

## Problem Statement

A green check is how anyone other than the author learns that a behaviour
landed: the maintainer reading a delivered fix, the coordinator judging a
step, the reviewer deciding whether a pull request is safe. After a shirabe
run, that green can't be trusted, for three reasons that compound.

First, shirabe doesn't know when work is a fix. A bug label picks the `fix/`
branch prefix and, in the analysis phase's prose, the fuller plan template;
nothing changes what runs. Tests are written after the code, so a run has no
record of any check failing before the correcting change, and nobody can tell
whether the test that now passes ever exercised the reported case.

Second, a pass from an edited test counts like any other. When a local test
fails mid-implementation, the implementation guidance lists "Test bug: update
test" as a way forward, with no definition and no record of the call; the
guidance for fixing a failing CI check lists "test failure" among the things
to fix locally, again with nothing separating a code fix from a test edit.
Nothing downstream notices that the check went green because its test changed.

Third, review can't see the difference. The review-level rules put every test
path in one class with one floor, and the review packet lists changed paths
without separating a new test from an old one loosened until it agreed with
the code.

Autonomous runs make each of these worse, since the session that writes the
code also edits the test that judges it and no one else is placed to notice.

## Goals

- A maintainer or coordinator can tell, from a run's record alone, whether a
  green check came with an edited test, and if so who accepted the edit.
- A fix's record shows the reported failure reproduced against the code as it
  was before the change, and gone after it, or an accepted observation in its
  place when no check can reproduce it.
- A pass that came with an edited test counts only after someone other than
  its author accepted the edit, and stops counting if a higher authority
  overrules that acceptance.
- An edited test raises the review floor and is put in front of every review
  seat; an added test doesn't.
- Autonomous runs keep running without a person unless the repository says a
  person must accept test changes.

## Definitions

These terms carry fixed meanings in every requirement below.

- **Unit.** The work one `/work-on` run delivers: an issue, a free-text task,
  or one plan step handed to `/work-on` by `/execute`.
- **Base.** The commit the run records before any of the unit's changes (the
  run's implementation base). A unit's **diff** is the committed changes from
  base to the run's head commit; uncommitted changes are never part of it.
- **Test file.** A path the `test` class of the review-level rules file
  matches (today `**/test/**`, `**/tests/**`, `**/spec/**`, `**/*.spec.*`,
  `**/*_test.*`, `**/test_*.*`, `**/evals/**`). There is one definition, read
  from that file as it stands at the base, so a unit's own diff can't narrow
  it; a repository widens it by editing that file.
- **Added test.** A test file the diff creates, or one whose diff adds lines
  and removes none.
- **Edited test.** A test file the diff deletes, or one whose diff removes at
  least one line, including a rename that removes lines. A rename that changes
  no line is neither added nor edited.
- **Fix.** A unit whose purpose is to correct behaviour someone reported as
  wrong. How a unit becomes a fix is R1.
- **Report passage.** Text quoted verbatim from the unit's report: the issue
  body for an issue, the task text for a task, or the step's fix declaration
  for a plan step.
- **Failure marker.** A literal string, chosen by the run, that appears in the
  report passage and in the failing check's output.
- **Red.** A recorded failing run of a check command that reproduces the
  report (R4, R5). **Green** is the recorded passing run of the same command
  after the change (R7).
- **Reproducing tests.** The test files the red ran with: those the unit's
  diff touched when the red was recorded. When the diff touched none (an
  existing, untouched test reproduces the bug), the red names the test files
  its command runs, and those are the reproducing tests.
- **Digest.** A file's blob id at the head; a deleted file's digest is the
  literal `deleted`.
- **Identity.** A string naming who acted, of the form `agent:<name>` or
  `person:<name>`. The **author** is the run itself, `agent:<run session
  name>`. An identity is other than the author when the strings differ. An
  acceptance seat the run commissions gets its own identity (R11).
- **Authority.** One of three levels, in ascending order: `reviewer` (an
  agent seat or reviewing person judging this change), `coordinator` (the
  session that dispatched the run), `owner` (a person who owns the
  repository). An agent may act as `reviewer` or `coordinator`; a person may
  act as `reviewer` or `owner`.
- **Acceptance.** A recorded judgment, by an identity other than the author,
  that a unit's edited tests (or its observations, R8) correct the test rather
  than the code. It covers the exact contents of the files it names as they
  stood when it was given.
- **Counted, held.** A unit is counted when its checks passed and every edited
  test and observation is covered by a live acceptance; otherwise it is held.
  A held unit's record says why: `unaccepted`, `declined`, `overruled`, or
  `changed since acceptance`.
- **Person-required.** A repository is person-required when its `CLAUDE.md`
  declares `## Test Change Acceptance: person`. The only other value is
  `agent`, the default. A `CLAUDE.local.md` can set `person` but can't relax a
  committed `person` to `agent`. The declaration is read at the base, so a
  unit's own diff can't relax it. In a person-required repository a person's
  acceptance at `reviewer` or `owner` counts.

## User Stories

- As a maintainer judging a delivered fix, I want the run to show the
  reproducing check failing on the code as it was, with the reported failure
  in its output, and passing after the change, so that I know the check
  exercises the reported case and the code change is what fixed it.
- As a dispatching coordinator checking a unit before calling it done, I want
  a pass that came with an edited test to show as held until someone other
  than the author accepted the edit, with who and under what authority, so
  that I can overrule an acceptance I disagree with and see the unit held
  again.
- As a repository owner whose team policy says only a person approves a
  rewritten test, I want an agent's attempt to accept a test change refused
  and recorded, so that I can see every acceptance that counted came from a
  person at a terminal.
- As that person, I want the held run to say what it waits for and to resume
  once I've accepted, so that I don't have to restart it.
- As a review seat on a pull request, I want the packet to tell me which tests
  were added and which were edited, with the edited hunks first, so that I can
  judge whether each edit corrects the test or weakens it.
- As a plan author, I want to mark a step as a fix and name what it fixes, so
  that `/execute` runs it red-first without an issue behind it.
- As an agent fixing a bug no automated check can reproduce, I want to record
  how I observed the failure and how I observed it gone, so that the fix can
  proceed without a fake test, under the same acceptance a test edit needs.
- As an agent fixing a failing CI check after the pull request is open, I want
  a test edit made there held the same way as during implementation, so that
  CI isn't a side door around the rule.

## Requirements

### Recognising a fix

- **R1.** A `/work-on` run determines whether its unit is a fix before it
  enters implementation, and records the determination and its source. A unit
  is a fix when any of these holds: its issue carries a label listed in the
  repository's `## Fix Labels:` declaration in `CLAUDE.md` (`bug` when there
  is no declaration); the plan step that spawned it carries a fix declaration
  (R3); or the run declares it a fix because the report describes existing
  behaviour as wrong. A unit none of these marks is not a fix and owes no red.
- **R2.** The run can declare a fix up to the moment it enters
  implementation, and on any return to its analysis. It can never withdraw a
  fix determination: an attempt is refused, the refusal names the recorded
  source, and the unit stays a fix.
- **R3.** A plan step declares a fix with a `**Fixes**:` line naming the
  report (an issue reference or one sentence stating the wrong behaviour).
  `/execute` hands that line to the step's `/work-on` run as the unit's fix
  declaration and report. A plan without the line runs as before.

### Starting red

- **R4.** Before a fix's run enters implementation, it records a red: the
  check command, the base commit, the reproducing test files and their content
  digests, the exit status, the last 40 lines (at most 4,096 bytes) of output,
  the report passage, the failure marker, and when it ran. The red runs the
  command against the base code with the run's test files applied, so it
  shows the failure without any of the unit's non-test changes.
- **R5.** A red is recorded only when the command exits non-zero, its output
  contains the failure marker, the failure marker appears in the report
  passage, and the report passage appears verbatim in the report. When any of
  these fails, no red is recorded and the run is told which.
- **R6.** A fix's run doesn't enter implementation until a red or an
  observation (R8) is recorded. A fix declared on a return to analysis owes
  its red before implementation resumes.
- **R7.** Before a fix's run finishes, it re-runs the red's command at its
  head and records the green: exit status, output tail and head commit. The
  fix's checks pass only when the green exits zero. A reproducing test that
  differs from its red digest at the head is an edited test under R10,
  whatever its diff shape.
- **R8.** When no automated check can reproduce the reported failure, the run
  records an observation in place of a red: how the failure was produced, the
  environment, what was seen (with the report passage and failure marker), and
  why no check can reproduce it; and, before finishing, a second observation
  showing the failure gone. The pair counts only once covered by an acceptance
  (R10 to R16), and every record and summary labels it an observation.

### Noticing and holding back a test change

- **R9.** Each time a unit's checks pass (after local verification, after a
  deferral to hosted CI, and after CI passes on the pull request), the run
  classifies every test file in the unit's diff as added or edited.
- **R10.** A unit whose diff has an edited test or an observation is held
  until each edited test and observation is covered by a live acceptance. An
  acceptance stops being live when a file it covers changes or when it is
  overruled. A held unit doesn't reach a finished-and-passing end. When
  several reasons hold a unit, its record lists all of them.
- **R11.** In a repository that isn't person-required, a held run
  commissions one acceptance seat: a fresh agent given the edited tests'
  hunks, the reason the run recorded for each edit, and the unit's acceptance
  criteria, with identity `agent:<run session name>/accept-<n>` and authority
  `reviewer`. The seat accepts or declines each edited file. A decline makes
  the unit held (`declined`) and sends the run back to implementation to
  change the code or restore the test; a third decline of the same set of
  file paths ends the run blocked, naming the files. A dispatching coordinator
  may accept in the seat's place, as `agent:<its session name>` at
  `coordinator`.
- **R12.** In a person-required repository, a held run stops resumably at the
  hold, stating the files that wait and the command a person runs to accept.
  A person's acceptance can be given only from an interactive terminal; an
  attempt without one is refused as not a person. A person can decline the
  same way, which sends the resumed run back to implementation. Once a person
  has accepted, resuming the run continues from the hold.
- **R13.** In a held `/execute` plan, the held step's run doesn't finish
  successfully, so `/execute` treats it as it treats any unfinished step:
  later steps that depend on it don't start.

### Acceptance, refusal and overruling (interim rule)

- **R14.** Every acceptance records the accepting identity, its kind (agent or
  person), its authority, each covered file with its content digest (or each
  observation's digest), a reason, and when it was given.
- **R15.** These attempts are refused, and every refusal is recorded with the
  identity that tried, the action, the files, the rule that refused it, and
  when: an acceptance or overrule by the author; an agent's acceptance in a
  person-required repository; a person's acceptance from no interactive
  terminal; an overrule whose authority isn't higher than the acceptance's;
  an authority a kind can't hold (an agent at `owner`, a person at
  `coordinator`).
- **R16.** An identity whose authority is higher than an acceptance's can
  overrule it with a reason. The unit becomes held (`overruled`), and only a
  new acceptance at an authority no lower than the overruling's makes it
  counted again. An overruling after the run finished is recorded the same
  way and updates the pull request's record.
- **R17.** One rule decides every accept and overrule attempt: it takes the
  attempt (identity, kind, authority, action, the author, and whether the
  repository is person-required) and returns allow or refuse with a reason.
  Every place that accepts, overrules or reports asks that rule and nothing
  else, so the later shared decision rule for delegated decisions replaces it
  in one place.

### Reading the record

- **R18.** One command reports, for a run, whether the unit is a fix and from
  what source; its red or observations and its green; each test file in the
  diff as added or edited; every acceptance, decline, refusal and overruling;
  and the unit's state (counted or held, with the reason). It works while the
  run is held and after the run has finished.
- **R19.** The record lives with the run's retained session, not in any file
  committed to the branch, and the pull request body carries a section
  rendering it: the fix's red and green (or observations), and for each edited
  test whether it is covered and by whose acceptance at what authority.

### Review

- **R20.** The review packet lists added and edited tests in their own
  section, before the full diff, with the edited tests' hunks in it. Every
  review seat's verdict carries, for each edited test, `corrects` or
  `weakens`; a `weakens` is a blocking finding.
- **R21.** A change with an edited test floors at the `full` review level. A
  change whose only test changes are added tests keeps today's `standard`
  floor for the `test` class.
- **R22.** The implementation guidance's failing-test options and the guidance
  for fixing a failing CI check say that a test edit holds the unit until
  accepted, and neither offers a test edit as a way past a failing check
  without that.

### Non-functional

- **R23.** An autonomous run in a repository that isn't person-required
  never stops to wait for a person at a hold.
- **R24.** Everything here works when the only guardrail is classification of
  the diff after the fact; nothing depends on test files being read-only.

## Acceptance Criteria

Each criterion names the requirement it checks. "The record" is R18's output.
Scenarios run in a scratch repository with a verification map whose check
runs the repository's tests.

### Recognising a fix

- [ ] R1: an issue labelled `bug` yields a record showing a fix with source
      `label:bug`; in a repository declaring `## Fix Labels: regression`, an
      issue labelled only `bug` is not a fix and one labelled `regression` is.
- [ ] R1: an unlabelled issue the run declares a fix shows source `declared`;
      an unlabelled issue the run doesn't declare is not a fix and reaches
      implementation with no red.
- [ ] R2: an attempt to withdraw a fix determination exits refused, names the
      recorded source, and the record still shows a fix.
- [ ] R3: a plan step with a `**Fixes**:` line reaches its `/work-on` run as
      a fix with source `step` and that line as its report passage; a step
      without the line in the same plan reaches its run with no fix
      determination from the plan.

### Starting red

- [ ] R4: the red record holds every field R4 lists, its base equals the
      run's base, and the output tail is at most 40 lines and 4,096 bytes.
- [ ] R4: in a scratch repository where the bug's correcting change is
      already committed on the branch, the red still fails, because it ran
      against the base code.
- [ ] R5: each of these leaves no red and names the failed condition: a
      command that exits zero; a non-zero exit without the marker (a compile
      error); a marker absent from the passage; a passage absent from the
      report.
- [ ] R6: a fix run with neither a red nor an observation can't enter
      implementation.
- [ ] R2, R6: a run that changes a non-test file, returns to analysis and
      declares a fix can't resume implementation until a red is recorded, and
      that red fails against the base code.
- [ ] R7: a green that exits non-zero leaves the fix's checks failed; a
      reproducing test changed after the red shows in the record as edited
      even when its diff only adds lines.
- [ ] R8: an observation pair records every field R8 lists, is labelled an
      observation in the record and the pull request, and holds the unit
      until accepted; an observation missing a field is refused naming it.

### Holding back a test change

- [ ] R9: a diff that adds a test file, appends lines to another, removes a
      line from a third, deletes a fourth and renames a fifth unchanged
      classifies them added, added, edited, edited, and neither.
- [ ] R9: an edited test leaves the unit held at each of the three points: a
      run whose local verification passed, a run deferred to hosted CI, and a
      run whose pull request's CI passed after a fix commit.
- [ ] R10, R11: a unit that makes a failing check pass by removing an
      assertion is held (`unaccepted`); its acceptance seat accepts, and the
      record shows it counted with identity `agent:<session>/accept-1` and
      authority `reviewer`; changing the accepted file again makes it held
      (`changed since acceptance`).
- [ ] R10: with two edited files and an acceptance covering one, the unit is
      held and the record names the uncovered file.
- [ ] R11: a seat that declines leaves the record held (`declined`) and sends
      the run back to implementation; three declines of the same file paths
      end the run blocked, naming them.
- [ ] R11: the seat's packet holds the edited hunks, the recorded reason for
      each edit and the unit's acceptance criteria; an acceptance by
      `agent:<coordinator session>` at `coordinator` in the seat's place makes
      the unit counted.
- [ ] R12, R15: in a person-required repository, an agent's accept attempt
      is refused with rule `person-required` and recorded; a `person:`
      acceptance run from a non-interactive shell is refused with rule
      `no-terminal`; the run stops at the hold naming the files and the
      command; after a person accepts at a terminal and the run resumes, the
      record shows it counted with `person:<name>` at `owner`.
- [ ] R13: in a two-step plan whose first step is held, the second step
      doesn't start.
- [ ] R14: an acceptance's record holds every field R14 lists.
- [ ] R15: the author's accept attempt is refused with rule `author`; an
      overrule at `reviewer` of a `reviewer` acceptance is refused with rule
      `not-higher`; an agent claiming `owner` and a person claiming
      `coordinator` are each refused with rule `authority-kind`; each refusal's record holds every field R15 lists.
- [ ] R16: a `coordinator` overrule of a `reviewer` acceptance makes the unit
      held (`overruled`); a new `reviewer` acceptance leaves it held; a new
      `coordinator` acceptance makes it counted; an overrule after the run
      finished shows in the record and in the pull request body.
- [ ] R17: replacing the one file that holds the rule with one that refuses
      every attempt, and changing nothing else, makes every accept and overrule in the scenarios
      above refused with that rule's reason.

### Reading the record and review

- [ ] R18, R19: the record command, run while a unit is held and again after
      its run finished, prints every item R18 lists; the pull request body's
      section shows the same red, green, files and acceptances; no file under
      the branch holds the record.
- [ ] R20: for a diff with one added and one edited test, the packet has a
      tests section before the diff listing them separately with the edited
      hunk; in every panel the change's level runs, a seat verdict missing
      `corrects` or `weakens` for the edited test is refused and a `weakens`
      blocks.
- [ ] R21: the same fixture with an edited test floors at `full`; with only
      an added test it floors at `standard`.
- [ ] R22: the implementation guidance and the CI-fix guidance each state
      that a test edit holds the unit until accepted, and `grep -rn "Test bug"
      skills/` finds no option that edits a test without it.
- [ ] R9, R22: a test edit committed while fixing CI on an open pull request
      makes the unit held before the run can finish.
- [ ] R23: an autonomous run with an edited test in a repository that isn't
      person-required finishes with the unit counted and no stop for a person.
- [ ] R24: every scenario above passes with test files writable.

## Out of Scope

- Stopping a test edit while the agent works: read-only tests and edit-time
  guardrails are separate work. This feature needs a test edit surfaced, not
  prevented (R24).
- The shared decision record for delegated decisions, and the per-level rule
  for who may accept. This feature ships the interim rule in R14 to R17 and is
  built to switch to that record when it exists.
- Proving an identity. The interim rule records the identity it's given and
  refuses the cases R15 names; it doesn't authenticate.
- Detecting a weakened test that nobody edited in this run, such as a test
  loosened by an earlier pull request or special-casing in the code under
  test.
- Changes to what a plan says a step's check is; changing what a plan commits
  to is the plan's own acceptance.
- Test files outside the unit's repository, and diffs spanning repositories.
- Any change to koto or niwa, and any write to a coordinator's own records.
- Measuring how often fixes were later found wrong before and after this
  lands.
- Units and plans started before this lands: they have no fix determination
  and run as before until re-run.

## Known Limitations

- Which test files a check runs isn't known in general, so every edited test
  in the unit's diff holds the unit, even one its check never ran.
- An added line can weaken a test (an early return, a skip). The diff-shape
  definition counts it as added; the packet still shows it to every seat.
- A test-like file outside the `test` class (a fixture or golden file under
  `testdata/`) isn't a test file until the repository widens the class.
- The acceptance seat is commissioned by the run whose work it judges. It
  starts from a fresh context and sees only the packet, but the interim rule
  can't show more independence than that.
- A failure marker shows the check failed with the reported symptom, not that
  it failed for the reported cause; review and the reader still judge whether
  the red exercises the reported case.
- A person's acceptance is recognised by its interactive terminal, which an
  agent's tool shell lacks today; it isn't an authentication.

## Decisions and Trade-offs

- **How a fix is recognised.** Labels, a plan step declaration and the run's
  own declaration all count, and a run can only add the determination. The
  label alone misses issueless plan steps and unlabelled bug reports; asking
  at the issue-type question after implementation is too late for red-first
  and lets the author decide whether its own rule applies.
- **Red against the base.** The red runs the command on the base code with
  the run's tests applied. Recording it before implementation shows the order;
  running it on the base proves the failure doesn't depend on any of the
  unit's code changes, including for a fix declared on a return to analysis.
- **The failure marker ties red to the report.** A marker that must appear in
  a verbatim report passage and in the output is mechanical. Judging "the
  reason the report gives" fully needs a reader; the record gives the reader
  both texts side by side.
- **A bug no check can reproduce.** A recorded observation stands in and needs
  the same acceptance a test edit needs. Exempting such bugs would make "no
  check can reproduce it" an unchecked exit from the rule; always requiring a
  check would force fake tests for terminal-only or timing bugs.
- **Stop or surface a test edit during the work.** Surface after the fact,
  each time checks pass. Stopping an edit while the agent works is the
  edit-time guardrail separate work owns.
- **Edited versus added by diff shape.** A test that only gains lines counts
  as added, so the common case of adding a test function to an existing file
  isn't taxed; any removed line is an edit. Holding every test change would
  tax the reproducing test a fix adds.
- **Interim acceptance rule.** Recorded identity and authority, the author
  can't accept, an agent can't act as `owner`, overruling needs a higher
  authority, and a `CLAUDE.md` declaration can require a person. One rule
  decides every attempt so the shared decision rule can replace it.
- **Where the record lives.** In the run's retained session and the pull
  request body, never in the branch: nothing committed may point at scratch
  state, and the session accepts an overruling after the run finished.

## Downstream Artifacts

- `docs/designs/current/DESIGN-red-first-fixes.md` (planned): the technical approach.
