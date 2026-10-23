---
schema: brief/v1
status: Done
problem: |
  Whoever reads a green check after a shirabe run can't tell whether it means
  the behaviour landed: a pass that came from editing the test counts exactly
  like one that came from changing the code, and for a fix nothing shows the
  check ever failed for the reported reason, because shirabe doesn't know the
  work is a fix.
outcome: |
  Whoever reads a fix's run sees the check fail for the reported reason
  before the correcting change and pass after it. A pass that came from a
  changed test shows as not counted until someone other than its author
  accepted the change, with who and under what authority, and review treats
  an edited test differently from an added one, in autonomous and
  person-gated environments alike.
motivating_context: |
  shirabe's delivery skills are increasingly run unattended, with one agent
  writing the code and the tests that judge it, and the people and
  coordinators downstream reading a passing check as the proof a behaviour
  landed. The ImpossibleBench study (Zhong et al., 2025) found that coding
  agents given impossible tasks mostly cheated by modifying tests, and that
  making tests read-only stopped that kind of cheating. Nothing in shirabe today keeps a pass from a
  changed test from counting.
---

# BRIEF: red-first-fixes

## Status

Done

How a fix is recognised, what counts as a recorded observation for a bug no
check can reproduce, the interim acceptance rule, and whether the red-first
order and the held-back pass ship together are left to the PRD and design.

## Problem Statement

A fix is work whose purpose is to correct behaviour someone reported as
wrong. The engineering habit for it is old and simple: reproduce the bug with
a check that fails for the reason the report gives, then change the code until
that same check passes, without touching the check. The failing run is the
evidence that the check exercises the reported case; the passing run after the
code change is the evidence the behaviour changed.

shirabe doesn't follow that habit, and nothing in it could tell whether a run
did. `/work-on` never learns that an issue is a fix in any way that changes
what runs: a bug label picks the `fix/` branch prefix and nothing else. Tests
are written after the code, so a run has no record of the check failing before
the change. When a local test fails mid-implementation, the guidance lists
"Test bug: update test" as one of the ways forward, with no definition of what
makes it a test bug and no record that the call was made.

The second half of the gap reaches past fixes. Any step whose check is a test
can be made green by editing the test instead of the code, and today that pass
counts like any other. The review-level rules put an edited test and an added
test in the same path class and give them the same floor, so a reviewer sees
"tests changed" and can't tell a new test pinning new behaviour from an old
test loosened until it agrees with the code. The person or coordinator who
reads a green check as "this behaviour landed" has no way to know the check
still checks what it used to.

The gap matters more now than it did when a person wrote every test. In an
autonomous run the same session writes the code and edits the test that
judges it, and nobody else is placed to notice.

## User Outcome

A maintainer or coordinator can tell, from the run alone, whether a green
check reflects changed behaviour or a changed test, and trusts it accordingly.

A person reading a fix's run afterwards, or a coordinator judging the work it
delivered, finds the check that reproduces the report failing for the reported
reason before any correcting change, and the same check passing after it.
When the bug can't be reproduced by an automated check, they find a recorded
observation of the reported failure instead, and know it's weaker evidence.

When a step's check passed only after a test it runs was changed, that reader
sees the pass held back: not counted until someone other than the author
accepted the test change, and then counted with who accepted it and under what
authority. If a higher authority overrules that acceptance, they see the pass
stop counting. An environment that requires a person to accept a test change
gets exactly that: an agent can't accept on the person's behalf, and its
attempt is refused and kept on the record.

A reviewer on the pull request is told which tests were edited and which were
added, and an edited test gets more scrutiny than a new one. None of this asks
an autonomous run to stop and wait for a person unless its environment says it
must.

## User Journeys

### An agent fixes a reported bug through `/work-on`

An agent picks up an issue reporting that a command crashes on an empty input
file. Because the issue is a fix, the run first adds a check that runs the
command on an empty file, runs it, and records it failing with the crash the
report describes. Only then does the agent change the code; the same check is
recorded passing afterwards. The maintainer who later judges the delivered fix
sees red, then green, on the reported case, and can confirm the failing check
is the one that exercises it.

### An agent makes a failing check pass by editing its test

Partway through a step, an existing test fails, and the agent decides the test
is wrong and changes its expected value. The step's check now passes, but the
step isn't counted as passing: the run shows the test edit and holds the pass
back. A reviewing agent, not the author, accepts the test change, and the step
is counted, showing who accepted and under what authority. Later the
dispatching coordinator, checking the work before calling it done, reads the
edit as loosening the assertion rather than correcting it and overrules that
acceptance as the higher authority. The step stops counting until the change
is accepted again.

### A repository owner keeps agents from approving test changes

A repository owner whose team policy says only a person approves a weakened
or rewritten test sets the repository to require a person's acceptance. When
an agent's run there edits a test and another agent tries to accept the
change, the attempt is refused and recorded with the agent's identity. The
owner later finds the step was counted only from the moment a named person
accepted, and that no agent approved on anyone's behalf.

### A reviewer reads a fix's pull request

A review seat opens a pull request whose diff touches three test files. Its
packet says one test was added and two existing tests were edited, and points
at the edited assertions. The seat checks that each edit corrects the test
rather than weakening it to match the code, and its verdict says so.

### A bug no automated check can reproduce

An issue reports a rendering glitch that only shows in one terminal. No test
in the repository can reproduce it. The run records how the failure was
observed (the command, the environment and the output that shows the glitch)
before the change, and the same observation after it showing the glitch gone,
marked as an observation rather than an automated check.

## Scope Boundary

### In scope

- Knowing that a unit of work is a fix, whether it arrives as an issue to
  `/work-on` or as a step of a plan `/execute` runs.
- A fix starting from a check that fails for the reported reason, recorded
  before the correcting change, and the same check recorded passing after it.
- What "fails for the reported reason" asks of a bug no automated check can
  reproduce.
- Noticing that a step's check passed after a test it runs changed, and
  holding that pass back until someone other than the author accepts the
  change.
- Recording each acceptance and refusal with the accepting identity and its
  authority, and letting a higher authority overrule an acceptance.
- An environment setting that requires the accepting identity to be a person.
- Review telling an edited test from an added one, and the guidance no longer
  offering a test edit as a way past a failing check without that acceptance.

### Out of scope

- Stopping a test edit while the agent works (read-only tests, edit-time
  guardrails). This feature needs a test edit surfaced, not prevented; the
  guardrail that stops one is separate work.
- Deciding who may accept a test change at each authority level, and the
  shared decision record every delegated decision will use. This feature ships
  an interim rule and is built to switch to that record when it exists.
- Detecting a weakened test that nobody edited in this run (a test loosened in
  an earlier pull request, or special-casing in the code under test).
- Any change to koto or niwa.
- Measuring how often fixes were later found wrong before and after this
  lands; that's the job of whoever judges the feature, not of the feature.
