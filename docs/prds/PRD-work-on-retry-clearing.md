---
schema: prd/v1
status: In Progress
problem: |
  A blocking finding in any of /work-on's three review phases routes the run
  back to implementation without invalidating the results artifact that phase
  wrote. Each phase gates on a presence-only `context-exists` key, so the
  previous round's verdict keeps the gate satisfied and the phase can advance
  on it. The one step that would invalidate it names `koto context remove`, a
  subcommand koto does not have, and its failure is swallowed by the
  `2>/dev/null` operators already type to escape koto's migration noise.
goals: |
  A blocking retry cannot advance a review phase on the previous round's
  verdict. The invalidation runs through a command koto provides at merge time, is
  verified where it happens with a diagnostic on stdout, and is backed by a
  gate the workflow evaluates rather than prose an agent may skip. All three
  retry-bearing phases behave the same way, and the phase files describe the
  mechanics they actually have.
absorbed: docs/briefs/BRIEF-work-on-retry-clearing.md
source_issue: 304
---

## Status

In Progress

Absorbed [BRIEF-work-on-retry-clearing](docs/briefs/BRIEF-work-on-retry-clearing.md); carried in Absorbed Brief.

Requirements only. The mechanism that satisfies R2 and R3 is left open for the
DESIGN, which settles it through a recorded decision -- one live option changes
another repository, so it is not a choice to make in passing.

## Absorbed Brief

The feature is the contract a blocking retry owes the next round of review.

**The problem it solves.** `/work-on` sends work back when a review panel finds
something blocking, and then lets the same panel's previous verdict satisfy the
gate that was supposed to demand a new one. The verdict that sent the work back
is the verdict that waves it through on the way past. Nothing in the workflow
distinguishes a review that ran this round from one that ran before the fix,
because the only thing guarding each phase asks whether a results artifact
exists and never asks which round produced it.

**The outcome a user should experience.** An agent whose implementation is sent
back gets a genuinely fresh verdict on the next pass: the phases the retry
re-enters refuse a `passed` outcome until this round's reviewers have written
their results, and they refuse it structurally rather than by asking the agent
nicely. An operator whose invalidation step fails learns so from a sentence on
a stream they have not redirected away, instead of from a merged pull request
whose review panel never ran. And a maintainer editing the retry directive
later finds a test failing rather than a workflow quietly degrading.

**Where the boundary sits, and why it is drawn there.** The feature holds in the
retry contract for all three retry-bearing review phases -- `scrutiny`,
`review`, and `qa_validation` -- rather than the one the filed issue names. The
three are not similar bugs; they are one traversal. Every `blocking_retry`
routes to `implementation`, and `implementation` routes forward into `scrutiny`,
so a retry re-enters every review phase at or above the one that raised it. A
fix confined to `scrutiny` would make the first gate of every retry honest and
leave the next two satisfied by the previous round's artifacts -- not a smaller
fix, but the same hole two states further along the same path.

What it holds out is the mechanism. Which command or state-machine shape forces
the fresh verdict is a technical choice with more than one defensible answer and
one option that reaches a second repository, so it belongs to the DESIGN and to
a recorded decision rather than to the framing.

## Problem Statement

`/work-on` runs three review phases after implementation, in order: `scrutiny`
(completeness, justification, intent), `review` (pragmatic, architect,
maintainer), and `qa_validation`. Each ends a round by writing a results
artifact into koto context -- `scrutiny_results.json`, `review_results.json`,
`qa_results.json` -- and submitting a `passed` outcome. Each also accepts
`blocking_retry`, which routes the workflow back to `implementation` so a coder
agent can fix what was found.

Nothing invalidates the results artifact on that return trip, and the gate
guarding each phase cannot tell that it should. All three declare
`type: context-exists`, which reports whether a key is present and nothing
else. The artifact from the round that just failed is present. So when the run
comes back around, the gate is satisfied by the very verdict the retry existed
to supersede, and a `passed` submission advances the phase whether or not any
reviewer ran again.

One phase tries to close this and cannot.
`skills/work-on/references/phases/phase-4a-scrutiny.md` tells the agent to
delete the stale artifact with `koto context remove <WF> scrutiny_results.json`.
koto's context group is `add`, `get`, `exists`, and `list`; there is no
`remove`, so the command exits with `error: unrecognized subcommand 'remove'`
and the artifact stays. The failure is quiet for a structural reason: every koto
invocation in a workspace with accumulated sessions prints `koto: migration
skipped ...` lines to stderr, which makes `2>/dev/null` the routine operator
response, and that filter swallows the unrecognized-subcommand error along with
the noise.

The same passage states its own causality backwards. It says the stale artifact
may make the gate fail and prompt a fresh run, then offers deletion as tidy-up
before re-running. The dependency runs the other way: a stale artifact makes the
gate *pass*, and the deletion is the only thing that would produce a fresh run.
A reader who trusts the prose concludes the deletion is optional housekeeping
when it is the entire mechanism.

`review` and `qa_validation` are worse off. They carry the identical
presence-only gate and the identical return path and document no clearing step
at all, so the same staleness sits there unnamed. And the three phases are not
independent instances of one bug -- they are on one traversal. Every
`blocking_retry` targets `implementation`, and `implementation` transitions
forward to `scrutiny` for `issue_type: code`, so a retry raised in `review`
re-enters `scrutiny` and then `review`, and one raised in `qa_validation`
re-enters all three. A retry always re-enters every review phase at or above the
one that raised it, each holding a gate open with its own previous verdict.

The cost lands exactly where it is most expensive. The runs that report a clean
review panel nobody ran that round are the runs where a reviewer had just
objected.

## Goals

- A `passed` submission carried by the previous round's artifact does not
  advance a review phase. The workflow refuses it rather than the prose
  discouraging it.
- The step that invalidates the previous round's artifacts runs a command koto
  provides at merge time, and a failure of that step is distinguishable from
  success on a stream that survives `2>/dev/null`.
- The guarantee does not rest on an agent reading and following prose. Something
  the workflow evaluates enforces it.
- `scrutiny`, `review`, and `qa_validation` carry the same contract, stated the
  same way, so understanding one is understanding all three.
- The phase files and the panel-orchestration summary describe the mechanics the
  workflow actually has, including the direction of the dependency between the
  invalidation step and the gate.

Throughout this document, **invalidate** is the operative verb and is defined in
R2. Where the text says *delete* or *remove*, it is quoting the phase file's
current broken instruction, not naming the requirement.

## User Stories

**As an orchestrating agent driving a `/work-on` run**, I want a phase that sent
work back for a blocking finding to refuse a `passed` outcome until this round's
reviewers have written their results, so that I cannot accidentally close a
review panel on a verdict that predates the fix.

**As an orchestrating agent whose retry was raised two phases down**, I want
every review phase the retry re-enters to demand a fresh verdict, so that the
phases the run already passed do not wave it through on last round's record.

**As an operator reading a run's output with koto's stderr redirected**, I want
a failed invalidation to print a sentence naming what failed and what to do, so
that I find out from the output rather than from a merged PR whose review panel
never ran.

**As a maintainer editing a review phase's directive a year from now**, I want a
test that runs the text the phase file ships to fail when my edit breaks the
invalidation, so that a broken directive is caught by CI rather than by the next
run that needed it.

## Requirements

### Functional

- **R1 -- Every koto subcommand an instruction names resolves.** After this
  work, every `koto context` invocation in an instruction under `skills/` names
  a subcommand koto actually provides at merge time. Today that set is `add`,
  `get`, `exists`, and `list`; if the DESIGN's chosen mechanism adds one to
  koto, the requirement is that the named subcommand exists and works, not that
  the set is unchanged. Prose that quotes a nonexistent verb in order to
  describe a defect is not an instruction and is not covered; an instruction the
  agent is told to run is.

- **R2 -- A blocking retry invalidates every panel artifact the retry will
  re-enter, not only the phase's own.** A `blocking_retry` from any of the three
  phases routes to `implementation`, and the run then walks forward through
  `scrutiny`, `review`, and `qa_validation` in order. Every one of those phases
  is re-entered, and the code they reviewed is about to change, so every panel
  results artifact standing at that moment is stale -- including the artifacts
  of phases that passed this round and will not themselves submit
  `blocking_retry`. The retry invalidates all of them. "Invalidate" means the
  artifact stops satisfying its phase's gate, whether by removal or by
  replacement with a value the gate rejects, through a koto subcommand that
  exists and works at merge time.

  Scoping the invalidation to the raising phase alone would leave the PRD's own
  headline scenario unfixed: a retry raised in `qa_validation` would re-enter
  `scrutiny` and `review` with their previous verdicts intact and their gates
  satisfied, which is the defect this document is about.

  A phase whose artifact does not exist yet -- `review` and `qa_validation` on a
  retry raised in `scrutiny`, before either has run -- is not an error. The
  requirement is that no stale artifact survives the retry, not that every key
  is written.

- **R3 -- The workflow, not the prose, enforces R2.** After the invalidation,
  the phase's gate reports failure, and that gate result is referenced by the
  `when` clause of the transition that advances the phase on `passed`. An agent
  that submits `passed` without writing this round's artifact does not advance.
  A gate declared but not referenced by a `when` clause is evaluated and ignored
  by koto, so the reference is the requirement, not the declaration.

- **R4 -- The failure exits stay reachable.** `blocking_retry` and
  `blocking_escalate` from each phase must remain reachable while the gate is
  failing. A run whose context store is broken must still be able to reach a
  terminal state rather than being trapped.

- **R5 -- A failed invalidation announces itself, on stdout.** The invalidating
  step reads its own result back and compares it, rather than testing for an
  empty string or trusting an exit status it cannot see. On mismatch it prints a
  diagnostic naming the step, the key, and what to submit instead of a success,
  on **stdout**. `koto context get` on a missing key writes a JSON error to
  stdout and exits 3, so a comparison against the expected value is the only
  check that catches every case.

- **R6 -- The three phases carry one contract.** The gate shape, the transition
  references, and the prose describing them are the same across `scrutiny`,
  `review`, and `qa_validation`, differing only in the key and outcome names.
  Because R2 makes the invalidation cover all three artifacts regardless of
  which phase raised the retry, the invalidation step itself is not merely
  parallel across the three phase files -- it is the same step. A reviewer
  checks one and confirms the other two match.

- **R7 -- The prose states the true causality.** The retry passage in each phase
  file says that the invalidation is what makes the gate fail, not that a stale
  artifact makes it fail. The current claim in
  `phase-4a-scrutiny.md` -- that the stale artifact will fail the gate -- is
  false and does not survive this work.
  `skills/work-on/references/review-panel-orchestration.md`, the summary a
  reader meets before the phase files, gains the contract too.

- **R8 -- Existing `passed` behaviour is unchanged on a first pass.** A run that
  reaches a review phase for the first time, runs its reviewers, writes its
  results artifact and submits `passed` advances exactly as it does today. The
  change is visible only on a retry and on a malformed or invalidated artifact.

### Non-functional

- **R9 -- Demonstrated against real koto, not asserted.** A test drives real
  koto sessions and shows the gate's behaviour on both sides of the
  invalidation: an artifact that satisfies the gate advances the phase, and the
  invalidated artifact holds it. The koto version the test runs against is the
  one CI installs from the project tool manifest.

- **R10 -- The test runs the shipped text.** The invalidation block and the gate
  definition the test exercises are extracted from
  `skills/work-on/references/phases/*.md` and
  `skills/work-on/koto-templates/work-on.md` at run time rather than pasted into
  the test. A pasted copy keeps passing after the shipped text drifts, which is
  the failure mode this class of defect is made of.

- **R11 -- The template still compiles clean.** `koto template compile` on
  `skills/work-on/koto-templates/work-on.md` exits 0 and introduces no warning
  that was not there before.

- **R12 -- `/work-on`'s evals reflect the changed contract, and are run.** Any
  eval assertion describing the review phases' gate or retry behaviour is
  updated to match, and `scripts/run-evals.sh work-on` is executed. A failing
  assertion is reported rather than rewritten to match the implementation.

## Acceptance Criteria

- [ ] For every verb `V` appearing in a `koto context V` **instruction** under
      `skills/`, `koto context V --help` exits 0 against the koto CI installs.
      This is the mechanism-neutral form of the check: it passes if the verb was
      already there and it passes if the chosen mechanism added it, and it fails
      for `remove` today. Prose citing a verb to describe a defect is excluded,
      which is a judgment the reviewer makes against each hit rather than a
      property of the grep.
- [ ] `skills/work-on/references/phases/phase-4a-scrutiny.md` contains no
      instruction to run `koto context remove` unless that subcommand exists.
- [ ] For each of `scrutiny`, `review`, and `qa_validation`: with the phase's
      results artifact invalidated, submitting the phase's `passed` outcome does
      not advance the workflow, and koto's response names the phase's gate as
      the failing condition. Captured as test output, not asserted in prose.
- [ ] **Traversal.** After a `blocking_retry` raised in `qa_validation`, neither
      `scrutiny` nor `review` advances on `passed` until each has a fresh
      artifact -- even though neither raised the retry and both passed that
      round. Exercised as a sequence against a real koto session, not inferred
      from the single-phase cases.
- [ ] **Traversal, from the middle.** After a `blocking_retry` raised in
      `review`, neither `scrutiny` nor `review` advances on `passed` until each
      has a fresh artifact. Covered separately from the `qa_validation` case so
      that all three entry points into the retry are exercised rather than the
      deepest and the shallowest standing in for the middle one.
- [ ] **Traversal, upward.** After a `blocking_retry` raised in `scrutiny`,
      before `review` or `qa_validation` has ever run, the invalidation step
      exits 0 rather than failing on the two artifacts that do not exist yet.
- [ ] Whichever phase raises the retry, the invalidation of **all three**
      artifacts runs on the same path as that phase's `blocking_retry`
      submission -- checked by extracting the shipped block and confirming it
      covers the three keys, not only the raising phase's own.
- [ ] For each of the three phases: with a well-formed results artifact present,
      submitting `passed` advances the workflow to the next state.
- [ ] For each of the three phases: with the gate failing, submitting
      `blocking_retry` advances to `implementation` and `blocking_escalate`
      advances to `done_blocked`.
- [ ] The invalidation block, run against a session whose context store cannot
      be written, exits non-zero and prints a diagnostic containing the key name
      on **stdout** with stderr redirected to `/dev/null`.
- [ ] The diagnostic tells the agent which outcome to submit instead of a
      success.
- [ ] The test extracts the invalidation block from the shipped phase file and
      the gate definitions from the shipped template at run time; editing either
      to break the contract fails the test.
- [ ] The retry passage in each of the three phase files states that the
      invalidation is what makes the gate fail. No surviving sentence claims a
      stale artifact fails the gate.
- [ ] `skills/work-on/references/review-panel-orchestration.md` states what a
      `blocking_retry` does to the three panel artifacts.
- [ ] `koto template compile skills/work-on/koto-templates/work-on.md` exits 0
      with no new warning relative to `main`.
- [ ] `cargo test --workspace` passes with no pre-existing test modified.
- [ ] `scripts/run-evals.sh work-on` has been run and its result reported,
      including any assertion that failed.
- [ ] `shirabe validate --lifecycle . --mode=ready` exits 0 on the finalized
      chain.

## Out of Scope

- **Which mechanism satisfies R2 and R3.** DESIGN altitude. The requirements
  above are written so that removal via a new koto subcommand, replacement with
  a value a content gate rejects, and any third shape can each satisfy them; the
  DESIGN picks one and records why.
- **`/execute`'s settled-branch record (#279, PR #306).** Merged. Precedent to
  read, not work to redo.
- **Every other `/work-on` phase, gate, and directive.** Only the three
  retry-bearing review phases and the prose describing them change.
- **Making `context_assignments:` work.** Probing the option space established
  that a transition's `context_assignments:` block is not a koto feature: koto's
  `Transition` struct carries `target` and `when` only, the key is silently
  dropped at compile time, and the context store is empty after the transition
  fires. The `failure_reason` assignments already in `work-on.md` are therefore
  no-ops, which makes this a wider defect than this PRD frames. It is recorded
  under Known Limitations and left for its own issue.
- **A general context-freshness primitive for koto gates.** If the chosen
  mechanism needs something koto does not have, the boundary is the smallest
  addition that serves these three phases, not a gate type that solves staleness
  for every future workflow.
- **The pre-existing template warning on `work-on.md`.** `koto template compile
  skills/work-on/koto-templates/work-on.md` on `main` emits exactly one warning
  -- W3, that `skipped_due_to_dep_failure` looks like a failure state without
  `failure: true`. That is the baseline R11 is measured against, and it is not
  fixed here. (The issue brief names two warnings, W3 and W4 on
  `spawn_and_await`; those are on `execute.md`, a different template.
  `spawn_and_await` is not a state in `work-on.md` at all, so anyone
  establishing the before-baseline by hand should expect one warning, not two.)

## Known Limitations

- **The invalidation is agent-performed under the chosen mechanism.** koto's
  engine never writes to the context store: `context_assignments:` on a
  transition is silently dropped, and a gate's `key:` is a static literal the
  compiler copies verbatim. So an invalidation-based mechanism has to put the
  step in something an agent runs, and an agent that skips it leaves the stale
  artifacts in place. R3 bounds the damage rather than eliminating it -- once
  the invalidation has run, no amount of prose-skipping advances a phase without
  a fresh artifact -- and R5 makes a *failed* invalidation loud. A *skipped* one
  remains possible. R2 mitigates by placing the step on the same path as the
  `blocking_retry` submission, whichever phase raises it, so skipping it means
  skipping part of a command the agent is already running rather than forgetting
  a separate step later.

  **An earlier draft of this bullet said koto "cannot make it otherwise." That
  was false and is corrected here.** koto can: `koto context add` appends a
  first-class `ContextAdded` event carrying the key and an envelope `timestamp`
  into `koto-<session-id>.state.jsonl`, a file koto's own `docs/workspace-layout.md`
  lists under AUTHORITATIVE state and whose envelope keys `docs/STABILITY.md`
  freezes behind a schema bump. A `command` gate reading that log can compute
  genuine freshness -- was this artifact written after the most recent re-entry?
  -- and needs no invalidation step at all. That mechanism was evaluated, is
  reachable, and was verified end to end; the DESIGN records why it was not
  chosen. The limitation above is a property of the mechanism this chain picked,
  not of koto.

- **R3's guarantee is structural modulo a recorded override.** `koto overrides
  record` works whether or not a gate declares `override_default`, so an
  operator or agent can advance past a failing gate deliberately. That is the
  correct behaviour -- an override is auditable through `koto overrides list` --
  but R3's wording implies the gate is absolute, and it is not.

- **`context_assignments:` is a no-op throughout `work-on.md`.** Found while
  establishing the option space. Every `context_assignments: failure_reason:`
  block on a `done_blocked` transition -- there are several, and
  `review-panel-orchestration.md` and eval 14 both document the behaviour as
  real -- silently does nothing. The escalation paths therefore propagate no
  `failure_reason` to context. Out of scope here and recorded so it is not
  rediscovered as a surprise.

## Decisions and Trade-offs

**All three retry-bearing phases, not `scrutiny` alone.** The filed issue names
`scrutiny`, and stopping there was the defensible smaller scope. It was rejected
on the traversal evidence: because every `blocking_retry` targets
`implementation` and `implementation` routes forward into `scrutiny`, a
`scrutiny`-only fix makes the first gate of every retry honest and leaves the
next two satisfied by the previous round's artifacts. That is not a smaller fix;
it is the same hole two states further along the same path. The precedent that
confined `/execute`'s fix to one state and filed the remainder separately
confined it across *skills*; here the remainder is two states on one path inside
the same two files, with no independent decision to make. Recorded because the
alternative was genuinely available and the reason it lost is not obvious from
the issue title.

**The requirements do not name a mechanism.** R2 says "invalidate" and defines
it by effect -- the artifact stops satisfying the gate -- rather than by verb.
This is deliberate: one live mechanism adds a subcommand to koto, which under
this workspace's coarsest-legal PR-grouping policy makes the work a coordinated
two-repo effort, and that is a cost the DESIGN should weigh against the
alternatives rather than inherit from a requirement's wording. Writing R2 around
`remove` would have decided the question here, in the document least equipped to
justify it.

An earlier draft failed its own neutrality test on this point, and the fix is
recorded because the trap is easy to fall back into. R1 pinned the legal verbs
to koto's four current ones and an acceptance criterion grepped for `remove` as
a defect marker, which between them foreclosed the add-a-subcommand mechanism
that the same document presented as open. Both now key on whether the named
subcommand resolves against the koto CI installs, which is the property that
actually matters and is true under either answer.

**A retry invalidates all three panel artifacts, not just the raising phase's.**
The narrower reading -- each phase clears its own on its own `blocking_retry` --
is the obvious one and it does not work. It leaves exactly the scenario the
Problem Statement leads with: a retry raised in `qa_validation` re-enters
`scrutiny` and `review`, neither of which raised anything, both of which still
hold the verdict they recorded before the code changed. An implementation could
satisfy the narrower reading in full and leave the headline defect in place. The
broader reading is also the more honest one: once a coder agent is about to
change the code, every review verdict about that code is stale, whatever phase
recorded it.

**R5 requires a comparison, not an emptiness test.** `koto context get` on a
missing key writes its error as JSON to stdout and exits 3, so the variable
holding the read-back contains an error payload rather than nothing when the
read fails. `test -z` would pass in exactly the case the check exists to catch.
This is the same finding the `/execute` fix recorded, reused rather than
re-derived.
