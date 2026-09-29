---
schema: prd/v1
status: Accepted
problem: |
  Every pull request goes through a review panel, and panels are one of the
  largest costs in a delivery run. Many blocking findings are closed
  questions a cheap typed grader could answer, but nobody has measured how
  often a grader's unanimous pass agrees with a clean panel on real pull
  requests, so nobody can decide whether a pass may stand in for a panel.
goals: |
  A maintainer deciding whether a unanimous grader pass may replace a panel
  of a given kind reads an agreement report built from real pull requests,
  with the misses listed, the share of blocking findings a criterion could
  cover, and the uncertainty the sample leaves, while every panel keeps
  running unchanged.
absorbed:
  - docs/briefs/BRIEF-jev-review-shadow.md
---

# PRD: Jev review shadow trial

## Status

Accepted

The completeness, clarity and testability reviewers all passed it on a second
round. The downstream DESIGN owns the approach.

Absorbed [BRIEF-jev-review-shadow](docs/briefs/BRIEF-jev-review-shadow.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so that the decision to let a cheap grader's pass stand in
for a review panel is made from evidence. The brief framed the gap as a
measurement nobody has taken: panels are expensive, many of their blocking
findings are closed questions a typed grader could answer, but no record puts
a grader's verdict and a panel's verdict side by side on the same head. This
document's Problem Statement states that in full, including why open-judgment
findings keep most of a panel's work out of reach.

The outcome it asked for is a maintainer who reads an agreement report, with
the misses and the coverage share visible, and decides the flip from it while
every panel keeps running. That's this document's Goals. The four people it
imagined (a pre-merge reviewer recording a shadow grade, the process owner
recording the panel's outcome, the decision owner reading the report, and a
cost analyst pricing the trial) are its User Stories, with the in-run panels
added as a fifth.

Its boundary held the trial to recording, never approving, and left the flip,
a rule registry, the in-run koto decider check and criteria for other
artifact kinds to later work. Those are this document's Out of Scope. Its two
open questions, what counts as a clean panel and how large a sample is
enough, are settled under Decisions and Trade-offs and in the Terms.

## Problem Statement

Every pull request in shirabe's workflows goes in front of a review panel: a
worker's own scrutiny, review and QA panels during the run, and a pre-merge
panel of three or more reviewers before the process owner merges. Each seat
is a full model session over the whole change, which makes panels one of the
largest costs in a delivery run.

Many of the findings panels block on are narrow and closed: a code comment
still describes the behaviour the change replaced, a document contradicts
itself after an edit, a pull request body claims more or less than the diff,
a public file names a private repository. Jev, the typed decision model koto
already calls as its decider, answers questions of that shape with usable
confidence on short inputs (`docs/spikes/SPIKE-jev-accuracy.md`). But a
pass may only replace a panel if a unanimous pass reliably coincides with a
clean panel, and that has never been measured on real pull requests. Most of
what panels raise (correctness, layering, proportionality, naming, missing
tests) isn't a closed question at all. Deciding to trust a pass without a
record of both verdicts on the same head would be a guess, and a wrong guess
ships defects a panel would have caught.

## Goals

The maintainer who owns the flip, letting a unanimous grader pass stand in
for a panel of one kind, decides it from an agreement report rather than from
intuition. After about fifteen to twenty pull requests per panel kind, the
report tells them how often a unanimous pass matched a clean panel, lists
every pull request the grader passed while the panel blocked it, shows what
share of upheld blocking findings a criterion covers, and bounds the
false-pass rate the sample still allows.

Panels lose nothing while the trial runs. It records beside them and never
approves, skips or shortens one.

## User Stories

- As a pre-merge panel reviewer, I want to run one command on the pull
  request and head I'm about to review, so that a shadow grade is recorded
  beside my panel without changing how the panel runs.
- As the process owner closing a panel, I want to record the panel's outcome
  and each blocking finding's final disposition against the same head, so
  that only findings that held up count as the reference the grader is
  measured against.
- As a worker running its own scrutiny, review or QA panel, I want to write
  the same shadow record and outcome in the same way, so that the in-run
  panels can be measured with the same report.
- As the maintainer who decides the flip, I want a report split by panel
  kind that shows agreement, false passes with their findings, coverage and
  the sample-size bound, so that I can see whether a flip is safe for any
  kind yet.
- As a cost analyst, I want every record to carry the tokens, model, unread
  usage and join keys, and a record even where the grader didn't run, so
  that I can price the trial per pull request without bias.

## Requirements

### Terms

These terms carry the report's numbers, so they're fixed here.

- **Verdict.** Each criterion on each slice gets one of four verdicts:
  `pass`, `fail`, `escape` (the grader chose the escape value, or no value
  reached the threshold), or `unanswered` (no answer could be obtained, with
  a reason from a closed list: over-bound, no key, transport error, provider
  error, unreadable answer, not graded).
- **Criterion verdict.** A criterion with several slices takes the worst of
  its slice verdicts, in the order `fail`, `unanswered`, `escape`, `pass`.
- **Run status.** A grading run is a *unanimous pass* when every criterion
  verdict is `pass`. It's a *dissent* when at least one criterion verdict is
  `fail`. Otherwise (no fail, but at least one escape or unanswered) it's
  *inconclusive*. An inconclusive run isn't a pass: in the flip it would
  escalate to the panel, exactly as a dissent would.
- **Upheld finding.** A blocking finding whose final disposition is `upheld`
  or `narrowed` (it held in reduced form). `dismissed` findings don't count.
  A finding whose disposition is `unknown` is kept apart and counted
  separately.
- **Blocked panel, clean panel.** A panel is *blocked* at a head when at
  least one of its blocking findings at that head is upheld, and *clean*
  when it has no blocking finding or every one was dismissed. A head whose
  only undismissed blocking findings are `unknown` is *undetermined*: it's
  counted and printed separately and left out of every rate. When more than
  one panel of the same kind reviewed one head, the head is blocked if any
  of them was. A seat's vote alone decides nothing.
- **False pass.** A unanimous pass on a head whose panel was blocked.
- **Dissent on a clean panel.** A dissent or inconclusive run on a head
  whose panel was clean.
- **Scored head.** A head of one panel kind with a graded record (run
  status unanimous pass, dissent or inconclusive) and a blocked or clean
  panel. Only scored heads enter the rates. Heads whose record is
  `not-graded`, and undetermined heads, are counted and printed separately.
- **In-sample.** A record graded after the panel's outcome for that head
  was already recorded. Records graded before the outcome exists are
  out-of-sample and are the test.

### Functional

- **R1. Criteria from real findings.** The criteria batch is drawn from the
  groups of findings review panels actually blocked on and advised. Each
  group a closed question can judge becomes a criterion. A committed table
  lists every group with its finding count, whether it became a criterion,
  and, for each that didn't, the reason. Criteria and the table name no
  pull request and quote no review.
- **R2. Criterion form.** Each criterion is a two-value choice (`pass`,
  `fail`) with an escape value, never a boolean. It carries a rule id, a
  rule ref naming the rule text it checks, the artifact kind it applies to,
  the slice kind it reads, and whether a script or Jev observes it. The rule
  id is opaque: a fixed prefix and a number assigned in order, carrying no
  word from the rule. Rule ids are unique. Pull requests are the first
  artifact kind, and the form doesn't assume them.
- **R3. The ladder.** Criteria a script can settle (an attribution or
  session line, a private name in public content, a committed `wip/` path,
  a word from a fixed tense list, a pasted duplicate paragraph) run as local
  scripts before any Jev call is made. Only judgment criteria go to Jev.
  Both count toward the run status, and each verdict records whether a
  script or Jev observed it.
- **R4. Input bound.** The text of every slice sent to Jev, summed over its
  labelled inputs and measured in UTF-8 bytes, is at most 2,560 bytes. The
  criterion's own question and answer descriptions don't count toward it. A
  pull request larger than the bound is cut into several slices, each
  within it. A single unit that can't be cut below the bound is logged as
  over-bound and its verdict is `unanswered` with that reason; nothing is
  truncated, and no over-bound text is sent.
- **R5. Per-criterion input.** Each criterion names its slice kind. A
  criterion comparing a pull request body with its diff takes the body plus
  a diff summary (the file list with per-file added and removed line
  counts), not a diff slice. A criterion about a document contradicting
  itself takes both locations.
- **R6. Grade command.** One command grades a pull request, named by
  repository and number at a stated head sha, with every criterion in the
  criteria file, and writes one record per run. The head may be any commit
  the pull request ever had, so already-merged pull requests can be graded
  at the head their panel reviewed. It runs with no koto session or
  workflow state. A missing or malformed criteria file is an error, and no
  record is written.
- **R7. Record content.** Each record carries the repository, pull request
  number and head sha; per criterion per slice the verdict, the choice
  probabilities (none for a script or an unanswered verdict), the observer
  (script or Jev) and, for unanswered, the reason; each criterion verdict;
  the model string Jev reports; tokens; the run status; and when it was
  recorded, which orders several records for one head.
- **R8. Cost and join fields.** Each record also carries, per Jev request,
  the model, input tokens and output tokens, and a count of billed answers
  whose usage couldn't be read, counted the way koto's decider checks count
  them; a trial marker naming this trial; the join keys (repository, pull
  request number, head sha, and a panel run id); and the host it ran on.
  The panel run id is given to the grade command when the caller knows it,
  and otherwise filled in when the outcome for that head is recorded.
- **R9. No-run records.** Every head with a recorded panel outcome has a
  record. When the grade command couldn't call Jev, its record says so with
  the reason. When the outcome step records an outcome for a head that has
  no record, it writes one whose run status is `not-graded`, so the
  report's per-head counts include heads the grader never saw.
- **R10. Panel outcome.** An outcome command records, for one pull request
  and head: the panel kind (`scrutiny`, `review` or `qa` for a worker's
  in-run panels, `pre-merge` for the panel before merge), the panel run id,
  and each blocking finding with its category and its final disposition
  (`upheld`, `narrowed`, `dismissed` or `unknown`) plus the disposition's
  source (`recorded` or `inferred`). A panel with no blocking findings is
  recorded as clean. Re-recording the same pull request, head and panel run
  replaces the earlier outcome, so a disposition that changes at a fix round
  is corrected in place on the head the panel reviewed.
- **R11. Agreement report.** A report command prints, per panel kind,
  overall and per criterion:
  - the count of scored heads, and separately of not-graded and
    undetermined heads;
  - agreement: unanimous passes on clean panels plus dissents or
    inconclusive runs on blocked panels, over that count;
  - false passes, each listed with its pull request, head and upheld
    findings, and the false-pass rate as false passes over unanimous
    passes;
  - the miss rate as false passes over blocked panels;
  - dissents on clean panels, over clean panels.
  Per criterion the same figures are computed with the criterion verdict in
  place of the run status and the panel narrowed to that criterion's group:
  the panel counts as blocked for a criterion only when it upheld a finding
  in that criterion's group, and a criterion `pass` there is a false pass. Where there is more than one
  record for a head, the latest is used. Rates with a zero denominator
  print as not applicable.
- **R12. Coverage.** Each finding category maps to one of three classes:
  *covered* (a criterion exists for its group), *closed but uncovered*, or
  *open judgment* (correctness, layering, proportionality, naming, test
  gaps, strategy fit and the like). The mapping lives beside the criteria
  file. The report prints the count and share of upheld blocking findings
  in each class, and the three shares sum to 100%. With no upheld findings
  the shares print as not applicable.
- **R13. Sample-size bound.** Next to each false-pass rate the report prints
  the exact one-sided 95% upper bound for a binomial proportion
  (Clopper-Pearson) at the observed count. With zero false passes in n
  unanimous passes that bound is 1 - 0.05^(1/n), close to 3/n.
- **R14. In-sample labelling.** Every record says whether it is in-sample.
  The report prints in-sample and out-of-sample figures in separate tables
  and never pools them.
- **R15. Shadow only.** Nothing in this change skips, replaces or shortens a
  panel, and a pass never approves anything.

### Non-functional

- **R16. Local records.** Records are written under a directory outside any
  git work tree. The commands refuse to write inside one.
- **R17. No private terms committed.** Nothing committed names a private
  repository, vendor, local path, session or job. The private-term list the
  private-name check needs is supplied at run time from a local file; the
  repository carries no copy of it in any form. A local check scans the
  change for each term in plain form, case-folded, and as its base64, hex,
  SHA-1, SHA-256 and MD5 encodings.
- **R18. Offline testability.** Every script check, the slicing, the record
  writer, the outcome command and the report run offline. Each
  script-checkable criterion ships with its script, a test and a CI job. CI
  never calls Jev and never needs a Jev key.
- **R19. Spend separation.** Every record carries the trial marker, and the
  report prints the trial's total Jev tokens from the records alone, so
  trial spend is reported apart from normal work. How an agent session that
  runs the command is marked as trial spend is a design decision; this
  change doesn't verify spend recorded outside the records.

## Acceptance Criteria

Automated, offline:

- [ ] The criteria file parses; every criterion has exactly the values
      `pass` and `fail` plus one escape value, a unique rule id matching the
      fixed prefix-and-number form, a rule ref that resolves to a file in the
      repository, an artifact kind, a slice kind and an observer. No
      criterion is declared as a boolean.
- [ ] A committed table lists each finding group with a count, a
      became-a-criterion column, and a non-empty reason for every group that
      didn't.
- [ ] Graded with a stub in place of Jev, a fixture pull request yields one
      record carrying every field R7 and R8 name, and every script verdict's
      observer is `script`.
- [ ] With a stub that records call order, no Jev request is made before
      every script criterion has a verdict.
- [ ] A slice of exactly 2,560 bytes is sent; a unit of 2,561 bytes that
      can't be cut is not sent, and its verdict is `unanswered` with reason
      over-bound. A multibyte character is counted by its UTF-8 bytes.
- [ ] A body-versus-diff criterion's slice holds the body and the per-file
      summary, and no diff hunk text.
- [ ] A stub run with one criterion at `escape` and the rest at `pass` gives
      run status inconclusive; one `fail` gives dissent; all `pass` gives
      unanimous pass.
- [ ] Each script-checkable criterion has a test that fails on a seeded
      violation, passes on clean input, and passes on a near miss (a
      look-alike word, or a match inside a fenced code example where the
      rule exempts it), and a CI job runs that test.
- [ ] No workflow file names a Jev endpoint or a Jev key.
- [ ] With no key set, and with a stub transport error, the grade command
      writes a record whose Jev verdicts are `unanswered` with reason no key
      or transport error.
- [ ] Recording an outcome for a head with no record creates a record whose
      run status is `not-graded`.
- [ ] Re-recording an outcome for the same pull request, head and panel run
      replaces the earlier one; a finding recorded with source `inferred`
      keeps that label in the report.
- [ ] Against a fixture record set with hand-computed expected output, the
      report prints the expected agreement, false-pass rate, miss rate,
      dissent rate and coverage shares per panel kind, including a case with
      zero blocked panels (miss rate not applicable), a case with one false
      pass in 5 unanimous passes (bound 0.6574), and a case with zero false
      passes in 10 (bound 0.2589).
- [ ] The same fixture with mixed in-sample and out-of-sample records prints
      two tables, and no out-of-sample figure changes when in-sample records
      are added.
- [ ] Dismissed findings don't count toward blocked panels or coverage.
- [ ] In the fixture, a not-graded head and a head whose only blocking
      finding is `unknown` are each printed in their own count and change
      no rate; with no upheld findings the coverage shares print as not
      applicable.
- [ ] A missing criteria file, and one with a boolean criterion, each make
      the grade command exit non-zero without writing a record.
- [ ] A self-contradiction criterion's slice holds two labelled locations.
- [ ] A check over the criteria file and the finding-group table finds no
      pull request number (`#` followed by digits) and no URL.
- [ ] The grade command runs to completion with no koto binary on the path.
- [ ] The commands refuse a records directory inside a git work tree.
- [ ] Every record carries the trial marker, and the report's token total
      equals the sum of the records' tokens.
- [ ] No file under `skills/` or any koto template changes in this change.
- [ ] The local private-term scan passes over the change for plain,
      case-folded, base64, hex, SHA-1, SHA-256 and MD5 forms.

Manual, at ready (needs live Jev):

- [ ] The grade command runs on at least five merged pull requests with
      known panel outcomes, at least one of them blocked, and the report
      prints their agreement table labelled in-sample.

## Out of Scope

- Letting a Jev pass skip or replace any panel. The maintainer decides that
  after reading the report; this change only records.
- A rule registry with promotion and withholding. The criteria live with
  this trial and move to a registry when one exists; opaque ids keep that
  move mechanical.
- Running the in-run version inside a koto decider check in work-on's
  scrutiny state. That's the follow-on home and the design names it, but it
  isn't built here.
- Criteria for other artifact kinds (briefs, PRDs, designs, plans, the
  skills' review panels). The criterion form allows them; building them is
  later work.
- Any change to koto.

## Known Limitations

- The spike measured single fixtures under about 2.5 KB and two criteria in
  depth. Criteria unlike the spike's, and slices cut from a real diff, are
  new ground; the trial measures them rather than assuming the spike's
  numbers carry over.
- Past panel reports carry each seat's first vote, not the final
  disposition. For the in-sample demonstration, dispositions come from the
  process owner's record where it has one and are labelled inferred where
  it doesn't.
- Correctness, layering, proportionality, naming and test gaps make up most
  panel findings and no closed criterion covers them. The coverage share
  exists to make that visible.

## Decisions and Trade-offs

- **"Clean" means no upheld blocking finding.** A panel is clean when none
  of its blocking findings is upheld or narrowed at its final disposition;
  a merge vote conditional on a fix is a blocking finding like any other,
  and its disposition decides. Alternative: take seat votes at face value.
  Rejected, because a vote is a seat's first word and several blocks were
  dismissed or narrowed on re-read.
- **Escape and unanswered aren't passes.** Only a batch where every
  criterion passed counts as a unanimous pass. Alternative: treat escape as
  an abstention. Rejected, because in the flip an escape would have to send
  the change to the panel, so counting it as a pass would overstate what a
  flip could skip.
- **The false-pass rate is over unanimous passes.** The flip question is
  "when the grader passes, how often would the panel have blocked?", so the
  denominator is unanimous passes. The miss rate over blocked panels is
  printed beside it because it's the number that grows the covered share.
- **Enough sample is reported, not fixed.** The report prints the 95% upper
  bound on the false-pass rate beside the count, so the maintainer sees how
  wide the uncertainty is at any n. Alternative: refuse to report below a
  minimum n. Rejected, because the bound says the same thing without hiding
  the data.
- **Script checks count toward unanimity.** A script fail breaks a unanimous
  pass just as a Jev fail does. Alternative: report script and Jev results
  separately only. Rejected, because the flip would replace the whole panel,
  so the pass that matters is the whole batch's.
