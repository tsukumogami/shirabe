---
schema: prd/v1
status: Accepted
problem: |
  The scope chain and /work-on run a dozen or more review seats per feature,
  each as a full agent, and many of their criteria are closed checks against
  documents and diffs already on disk. No record says which seats a one-shot
  decider could serve with input a script gathers, and no seat in either
  workflow has a decider verdict recorded beside its own, so a maintainer
  has nothing to rule on when asked whether a decider can take a seat's place.
goals: |
  Every jury and review site in the scope chain and /work-on is classified as
  decider-fit or agent-only with its reason. Each decider-fit site sends its
  closed criteria to the decider in shadow, with input a script assembles
  from disk, and the decider's verdict lands in the review-shadow store next
  to the seat's own verdict, while every route, gate and seat stays as it is.
upstream: docs/briefs/BRIEF-jev-closed-criteria.md
source_issue: 592
---

# PRD: Closed-criteria review checks in decider shadow

## Status

Accepted

## Problem Statement

A feature taken through `/scope` and `/execute` meets review seats at every
step: two on the brief, three on the PRD, a security seat and three
final-review seats on the design, `/review-plan`'s category checks on the
PLAN, and on every implementation `/work-on`'s scrutiny, review, QA or
light-review panels. Each seat is a full agent reading a packet of 28 KB to
150 KB. Some of what they check is judgment: whether a problem is real,
whether an architecture holds, whether the code is correct. Some of it is
closed: whether each user journey names a user, a trigger and an outcome,
whether an acceptance criterion answers yes or no, whether a PLAN issue
covers a design component, whether a diff touches the code an acceptance
criterion names.

A typed decider answers closed questions in one shot at a small fraction of
a seat's cost, and the review-shadow trial already measures one beside
pull-request panels. It doesn't reach these seats. Three things are missing.
Nobody has written down which seats can be fed by a script, which is the
condition for using the decider at all: when the main agent has to write the
decider's input, the writing costs more than the seat saved and the decider
judges only what the agent chose to show it. No seat in the scope chain or
in `/work-on` has a decider verdict recorded beside its own, so there is no
evidence for any later move. And no step asks whether an artifact should
exist, or whether its framing holds, before requirements are written against
it.

## Goals

- A maintainer can read, per site, whether the decider is a candidate and
  why, in one table.
- For each candidate site, every run leaves the seat's verdict and the
  decider's verdict on the same artifacts side by side, read back by the same
  report the pull-request trial uses.
- The agent running a workflow does no extra writing and sees no change in
  where its run goes.
- The framing question between brief and PRD has a recorded answer.

## User Stories

- As the maintainer who rules on moving a seat to the decider, I want each
  candidate site's seat and decider verdicts recorded together across many
  runs, so that I can rule on out-of-sample agreement rather than on an
  impression of how often a seat blocks.
- As an agent running `/scope` or `/work-on`, I want the shadow check to
  happen without my writing any input for it and without any route reading
  it, so that a missing key, a slow provider or a wrong answer can't change
  my run.
- As a reviewer approving a change to a review site, I want a written
  classification that names the artifacts a decider-fit site reads or the
  reason a site stays agent-only, so that I can judge the change against a
  rule.
- As a maintainer reading the cost case, I want each site's decider input
  size measured next to the packet size of the seat it shadows, with the
  command that produced both, so that the saving is a number I can re-run.

## Requirements

### Functional

- **R1. Site classification.** The design carries one table that classifies
  each of these sites as decider-fit or agent-only: the brief jury, the PRD
  jury, the design security review, the design final review, `/review-plan`,
  scrutiny's completeness check, the review panel's closed criteria, QA, the
  intent reviewer and the light review seat. A decider-fit row names the
  artifacts its input comes from; an agent-only row names the reason. A
  site whose seats split (some criteria closed, some judgment) gets one row
  per part.
- **R2. Fit rule.** A site is decider-fit only when a script can assemble its
  decider input from artifacts that exist on disk or in the run's koto
  context when the seat finishes. A site whose input would have to be
  written by the main agent is agent-only.
- **R3. Closed criteria only.** Each decider-fit site sends only criteria a
  reader can answer yes or no from the slice alone. A criterion that repeats
  a check `shirabe validate` already makes is not sent.
- **R4. Script-assembled input.** For each decider-fit site, one command
  assembles the decider input from the named artifacts. The command takes
  only identifiers (a topic slug, a koto session name, a git ref, an issue
  number or a path) and never free text from the agent.
- **R5. One shadow path.** The decider calls, slicing and records reuse the
  review-shadow trial's tool under `scripts/review-shadow/`: its 2,560-byte
  slice bound, its never-truncate rule, its batching, its credential
  redaction, its record store and its report. No second store or Jev client
  is added.
- **R6. Seat verdict beside the decider's.** One shadow run of a site writes
  one record holding the verdict of every seat it shadows at that site, each
  read by the script from where the seat already writes it, and the
  decider's per-criterion verdicts. A seat verdict that can't be read is
  recorded as `unreadable` with one reason from this closed list:
  `seat-verdict-missing` (no verdict where the seat writes it),
  `seat-verdict-unparsed` (present but not in the seat's verdict format) or
  `seat-verdict-stale` (given on a different artifact than the one graded).
  An identifier the command takes is a topic slug matching `^[a-z0-9-]+$`, a
  koto session name, a git ref, an issue number or a repository path.
- **R7. Shadow only.** No route, gate, retry count, seat count, model or
  budget reads or changes because of a decider verdict. The shadow command's
  exit status and output are ignored by every caller, and a run with no
  decider key behaves exactly as one before this change.
- **R8. Runs before cleanup.** At each decider-fit site the shadow command
  runs after the seats' verdicts are written and before the skill's cleanup
  removes them.
- **R9. Measure mode.** The shadow command can print, without any network
  call or record, the byte size of each decider slice it would send for a
  site, so input size can be compared with the packet the seat reads.
- **R10. Report by site.** The review-shadow report can print agreement,
  false passes with their upper bound, and no-verdicts per site, from the
  shadow records, in-sample and out-of-sample apart, as it does per panel
  kind for pull requests.
- **R11. Framing seat.** A judgment seat at the step from brief to PRD (does
  this artifact need to exist, does its framing hold) either exists or a
  decision recorded in the design explains why it doesn't.

### Non-functional

- **R12. Floors.** Shell code runs on bash 3.2; Python runs on 3.8 with the
  standard library only. Nothing is installed.
- **R13. Offline tests.** Every part except the live decider call is covered
  by tests that run offline in CI, and no test can reach a real transport.
- **R14. No private text.** Records hold hashes, counts, verdicts and values
  from closed lists, never artifact text, as review-shadow records do today,
  and live outside every work tree.

## Acceptance Criteria

Classification and fit (R1, R2, R3, R11):

- [ ] The design has a table with one row per site named in R1 (one row per
      part where a site splits), each marked decider-fit or agent-only, each
      decider-fit row naming its input artifacts and each agent-only row
      giving a reason.
- [ ] Every decider-fit row's input artifacts exist on disk or in the run's
      koto context at the moment the shadow step runs, as the site's phase
      file orders it.
- [ ] No decider criterion's question restates a check listed in the
      design's table of `shirabe validate` checks for that artifact type.
- [ ] The design records whether a framing seat is added at the brief-to-PRD
      step and, if not, why not.

Input assembly (R4, R9):

- [ ] For each decider-fit row, `review-shadow.py` measure mode, given only
      identifiers, prints one line per slice with its id and byte size, makes
      no network call (the test transport refuses one) and writes no record.
- [ ] Run against a fixture artifact for each decider-fit site, measure mode
      prints the slice count and sizes the test expects.
- [ ] A grep of every changed skill and phase file for the shadow command
      finds only identifier arguments; no line asks the agent to write a
      summary, argument or other text for the decider.

Shadow records (R5, R6, R14):

- [ ] A shadow run with a stub decider writes exactly one record per site run
      to the existing review-shadow store, holding every shadowed seat's
      verdict as read from its on-disk location and the decider's verdict per
      criterion.
- [ ] With a seat's verdict absent, unparseable, or given on another
      artifact, the record marks that seat `unreadable` with
      `seat-verdict-missing`, `seat-verdict-unparsed` or `seat-verdict-stale`
      respectively.
- [ ] The decider client used is review-shadow's existing one: the change
      adds no second HTTP client, store directory or record schema family.
- [ ] A record holds no line of artifact text: a test greps a written record
      for a sentinel string planted in the fixture artifact and finds none.
- [ ] A slice of exactly 2,560 bytes is sent; one of 2,561 bytes is not sent,
      is not truncated, and is recorded `unanswered` with reason `over-bound`.

Shadow only (R7, R8):

- [ ] With no decider key, with a stub decider that errors, and with one that
      times out, the shadow command exits 0 and records the criteria
      `unanswered` with reasons `no-key`, `provider` and `transport`.
- [ ] No koto template's routes, gates, accepts fields or evidence change,
      and no seat commissioning line changes its seat count, model or call
      budget (a diff of the commissioning lines shows them unchanged).
- [ ] In each changed phase file, the shadow step comes after the step that
      writes the seats' verdicts and before the step that deletes them, and
      the text says its result is not read.

Report (R10):

- [ ] Over a fixture store with known seat and decider verdicts, the report's
      per-site table prints the agreement, false passes, false-pass upper
      bound and no-verdict counts the test computes by hand, out-of-sample
      and in-sample in separate tables.

Floors and delivery (R12, R13):

- [ ] Any shell added or changed passes `scripts/check-bash-floor.sh`; the
      Python passes its suite under the 3.8 floor the existing CI job uses
      and imports only the standard library.
- [ ] The review-shadow test suite runs in CI with the real transport
      refused, and every CI job on the implementation pull request passes.
- [ ] The implementation pull request body states, per decider-fit site, the
      measured decider input size and the seat packet size, with the command
      that produced each.

## Out of Scope

- Flipping any seat from shadow to trust. That ruling is made later, per
  seat kind, after fifteen to twenty out-of-sample runs.
- Removing a seat or changing any seat's count, model or budget.
- Release-time evals for these criteria (shirabe#593). The skill evals are
  waived as a definition of done for this work (shirabe#612).
- The review-level rules and thresholds from the review-level change.
- Checks `shirabe validate` already makes, and closed checks a plain script
  answers better than a decider (a word list, a path pattern): those belong
  in the validator or in review-shadow's script criteria, not in decider
  questions.
- Moving the in-run version into koto `decider-check` gates. That is a later
  step once a criterion earns trust.

## Decisions and Trade-offs

- **Record the seat verdict by reading it, not by asking for it.** The seat
  verdict could be passed on the command line, but that is agent-typed
  input. Each site's seats already write their verdict somewhere a script
  can read (a pinned verdict file, a YAML block, the work-on verdict
  ledger), so the script reads it. Where a seat writes none today, the
  design decides whether giving it a verdict line counts as changing the
  seat; it changes no count, model or budget.
- **Reuse review-shadow over koto gates.** koto's decider-check gate only
  exists on a koto template state, holds at most four criteria per state and
  sends one request per criterion. Four of the sites (brief, PRD, design,
  `/review-plan`) have no koto template, and a gate added to `/work-on`'s
  template would change a template's gates. The review-shadow tool calls the
  same decider without those limits.

## Known Limitations

- The decider sees slices, not whole documents. A criterion that needs a
  whole design in view can't be decider-fit, and slicing a large document
  per section can miss a cross-section problem.
- The verdict files most jury sites write are deleted at cleanup, so a
  shadow run that misses its window has nothing to compare against.
- Seat verdicts are per seat, while decider verdicts are per criterion. A
  seat that blocks on a judgment criterion will show as disagreement with a
  decider that passed every closed criterion; the report has to keep that
  from reading as a false pass of the closed criteria.
