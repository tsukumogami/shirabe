---
schema: brief/v1
status: Draft
problem: |
  Every pull request gets a multi-reviewer panel, and panels are expensive.
  Many of the blocking findings they raise are closed questions a cheap
  typed grader could answer, but nobody knows how often a grader's clean
  pass would agree with a clean panel, so nobody can decide to trust one.
outcome: |
  A maintainer deciding whether a unanimous cheap-grader pass may stand in
  for a panel reads an agreement report built from real pull requests:
  how often the grader agreed, what it missed, and what share of blocking
  findings it could never have caught.
motivating_context: |
  An accuracy spike measured Jev, a typed decision model koto already uses
  as its decider, on six of shirabe's prose criteria and cleared two of
  them for a decider design. It measured single fixtures under about
  2.5 KB. Whether a batch of closed criteria over a whole pull request
  agrees with the review panels shirabe's workflows already run is the
  question the spike could not answer.
---

# BRIEF: Jev review shadow trial

## Status

Draft

## Problem Statement

shirabe's workflows put every pull request in front of a review panel: a
worker's own scrutiny, review and QA panels while it works, and a pre-merge
panel of three or more reviewers before the process owner merges. Each
panel reviewer is a full model session reading the whole change, so panels
are one of the largest costs in a delivery run.

Many of the findings those panels block on are narrow and closed. A code
comment still describes the behaviour the change replaced. A document says
one thing in one section and the opposite in another. The pull request
body claims more, or less, than the diff does. A public file names a
private repository. Questions like these can be put to a cheap typed
grader as a two-value choice with an escape. Jev, the typed decision
model koto already calls as its decider, answers that form with usable
confidence on short inputs, according to the accuracy spike in
`docs/spikes/SPIKE-jev-accuracy.md`.

What's missing is evidence. A grader's pass could replace a panel only if
a unanimous pass reliably coincides with a clean panel, and nobody has
measured that on real pull requests. The spike measured single short
fixtures, not a batch of criteria over a real change. And the panels'
findings are not all closed questions: correctness, layering,
proportionality, naming and missing tests make up most of what reviewers
raise, and no closed criterion catches those. Without a record of both
the grader's verdict and the panel's verdict on the same head, the
decision to trust a pass would be a guess, and a wrong guess ships
blocking defects that a panel would have caught.

## User Outcome

A maintainer who owns the decision to let a grader pass stand in for a
panel (the flip) gets that decision from data instead of from intuition. After
enough pull requests (on the order of fifteen to twenty per panel kind),
they read one report that says how often a unanimous grader pass matched
a clean panel, lists every pull request the grader passed while the panel
blocked it, and shows what share of the panel's upheld blocking findings
fell in a group some criterion covers. They can see that the covered share
is where a flip could ever be safe, and how wide the uncertainty still is
at the sample size they have.

A reviewer running a panel today loses nothing. The trial records
alongside the panel and never approves, skips or shortens it.

## User Journeys

### A pre-merge reviewer records a shadow grade

A reviewer on the pre-merge panel is about to review a pull request at a
given head. Before or after writing their own verdict, they run one
command naming the repository, the pull request and the head. It grades
the change against the full batch of closed criteria, running the
script-checkable ones locally and sending the judgment ones to Jev, and
writes one local record for that head. The reviewer's panel proceeds
exactly as it would have; the record sits beside it, waiting for the
panel's outcome.

### The panel's outcome is recorded against the same head

When the panel finishes, whoever closes it (the process owner at
pre-merge, or a worker's own run for an in-run panel) records the outcome
for the same pull request and head: clean, or blocked with the
categories of the blocking findings. When a fix round later upholds or
dismisses a blocking finding, that disposition is recorded too, so only
findings that held up count as the reference.

### The decision owner reads the agreement report

After a batch of pull requests, the maintainer who will decide the flip
runs the report. It prints agreement per criterion and overall, split by
panel kind, with every false pass listed next to its finding, the share
of upheld blocking findings that a criterion covers, and the statistical
upper bound on the false-pass rate the sample allows. They decide from
that whether to propose letting a unanimous pass stand in for one panel
kind, or whether to keep collecting.

### A cost analyst prices the trial on its own

Someone measuring the cost of shirabe's workflows is asked what the trial
itself costs, and whether a grader round is cheaper than the panel it
might replace. They read the records the trial wrote, separately from
normal work. Each record carries what a
cost model needs: the model, input and output tokens per round, the
count of billed answers whose usage couldn't be read, and join keys back
to the panel run it sat beside. Heads a panel reviewed where the grader
didn't run still have a record with the reason, so a per-pull-request
comparison of grader cost against panel cost isn't biased toward the
cases where the grader happened to run. They come away with a price per pull request for the grader, to set
beside the panel's.

## Scope Boundary

**IN:**

- A batch of closed criteria drawn from what review panels have actually
  blocked on, each a two-value choice with an escape, written so the
  artifact kind it applies to is part of the criterion and pull requests
  are only the first kind.
- One command that grades a pull request at a stated head with the whole
  batch, runs script-checkable criteria before any Jev call, and writes
  a local record per run.
- A step that records a panel's outcome and each blocking finding's final
  disposition against the same head, for either panel kind.
- A report that prints agreement per criterion and overall, split by
  panel kind, with coverage shares and a sample-size bound.
- A demonstration on already-merged pull requests whose panel outcomes
  are known, labelled in-sample.

**OUT:**

- Letting a Jev pass skip, shorten or replace any panel. The trial only
  records; the flip is a separate decision the maintainer makes after
  reading the report.
- A registry of reusable rules with promotion and withholding. The
  criteria live with this trial for now and move there when a registry
  exists.
- Running the in-run version inside a koto decider check in work-on's
  scrutiny state. That is the natural follow-on home, and it needs no
  koto change, but it isn't built here.
- Criteria for briefs, PRDs, designs, plans or the skills' own review
  panels. The criterion format allows them; building them is later work.
- Any change to koto.

## Open Questions

- What exactly counts as a "clean" panel when one reviewer votes merge
  conditional on a small fix? The PRD owns the outcome vocabulary.
- How many pull requests per panel kind are enough to propose a flip?
  The brief names fifteen to twenty as the planned sample; the PRD
  should say how the report shows whether a sample is large enough.
