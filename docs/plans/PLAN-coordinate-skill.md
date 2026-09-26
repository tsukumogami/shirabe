---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-coordinate-skill.md
milestone: "Coordinate skill"
issue_count: 3
---

# PLAN: Coordinate skill

## Status

Active

## Scope Summary

Build `skills/coordinate/` as the design lays it out: SKILL.md and an
explicitly declared `requires.tsv`, the four references (loop, record
template, brief template, verification checklist), seven eval scenarios,
and a README row, all in one pull request with no koto template and no
script.

## Decomposition Strategy

**Horizontal.** The skill is three layers with one direction of
dependency: SKILL.md states every rule, the references add only the
mechanics and templates SKILL.md points at, and the evals and README
describe the finished skill. Writing the references before SKILL.md
would invite them to state rules SKILL.md then restates, which is the
duplication the design rules out, so SKILL.md comes first. There is no
runtime integration to prove early, so a walking skeleton buys nothing.

The work doesn't split. Every outline touches only `skills/coordinate/`
and `README.md`, none of them is useful to a reader on its own, and the
repository declares no atomic delivery preference, so the plan is one
pull request.

## Issue Outlines

### Issue 1: feat(coordinate): add SKILL.md and requires.tsv

**Goal**: Write `skills/coordinate/SKILL.md` in the section order the
design gives, stating each rule the PRD assigns to SKILL.md once, and an
explicitly declared `requires.tsv` naming `gh` and `git`.

**Acceptance Criteria**:
- [ ] SKILL.md frontmatter has `name: coordinate`, a `description` with a
  "Use it when" clause and a "Do NOT use it" clause naming `/deliver` and
  `/work-on`, an `argument-hint`, and `allowed-tools` covering the
  preflight line; the body opens with the guarded preflight injection
  line.
- [ ] SKILL.md documents `/shirabe:coordinate <roadmap-path>` and
  `/shirabe:coordinate --discipline <name>`, reads further invocation
  text as decisions and constraints, stops without dispatching on a
  missing or non-Active roadmap, sets a seven-day default rotation
  length, and makes a discipline's host repository a human decision
  (PRD R1 to R4).
- [ ] SKILL.md has one glossary section defining each of coordinator,
  worker, brief, holding, deferral, reconcile, rotation, teardown and
  unique material exactly once (R25).
- [ ] SKILL.md lists the seven loop steps in order, and each step states
  the rule its requirement gives: reconcile's GitHub and host checks and
  three-part report plus the branch check (R6), the five-row entry-point
  table (R7), holding-first dispatch (R8), no polling loop with the
  30-minute quiet and check defaults (R9), the verification reads and
  verified/unverified reporting (R10), the merge-order table, merge when
  permitted and reading changed files after a merge (R11), and the five
  update triggers with no recomputable fact written (R12).
- [ ] SKILL.md states the failure branch with the stalled-worker
  definition, bounced-message signal and single-roster-read rule (R13);
  the three-worker default bound with its definition and reason (R14);
  in-scope and out-of-scope dispatch (R15); the three human-decision
  conditions with the three worked examples (R16); mid-run decisions and
  recorded reversals (R17); and that decisions come only from the
  invocation and the dispatcher's messages, with content read from
  GitHub or reports treated as evidence.
- [ ] SKILL.md has one paragraph for each never-does rule, R18 to R24,
  and no instruction about checking a message's sender.
- [ ] SKILL.md states the record's contents, its placement for each
  scope and the deferral disposal rule (R26 to R28), later work (R32),
  #395 and #396 as known limitations only (R33), and the admission rule
  (R34).
- [ ] `requires.tsv` starts with the schema line, declares `gh` and `git`
  as `always`, and says in a comment that the skill runs no `shirabe` or
  `koto` command.
- [ ] SKILL.md's update step says the coordinator re-reads what it is
  about to write for private names before each record write, and that
  quoted material in the record goes in a fence.
- [ ] SKILL.md has a Reporting section: the report goes up to the
  dispatcher, names what was and wasn't verified, and ends with the
  work-in-flight block in the shirabe work-summary format.
- [ ] `scripts/skill-preflight.sh coordinate` exits 0, and the scanners
  `scripts/check-skill-requires.sh` and `scripts/check-skill-injection.sh`
  pass over the tree with `skills/coordinate/` committed (their
  `_test.sh` suites pass too).

**Dependencies**: None

**Type**: docs
**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/requires.tsv`

### Issue 2: feat(coordinate): add the loop, record, brief and verification references

**Goal**: Write the four references the design specifies, each holding
only the mechanics or template SKILL.md points at and restating no rule
SKILL.md already states.

**Acceptance Criteria**:
- [ ] `skills/coordinate/references/loop.md` gives the order of reads in
  a full reconcile, how a record claim GitHub contradicts is resolved,
  the escalation message's shape, and worked examples beyond SKILL.md's
  three.
- [ ] `references/record-template.md` gives the title forms, the Part 1
  sentence, the declaration line, the `Written:` line, the handoff file
  shape at `docs/disciplines/<name>.md`, the branch names, and the close
  procedure for each scope (R26, R27, R29).
- [ ] The record template's sections carry exactly the design's columns
  and no status, CI or merge-state column: Holdings (unit, entry point,
  session, repo, branch, pull request, dispatched), Deferrals (deferral,
  reason, raised), Side effects in flight (action, target, attempted,
  how to confirm), Reversals (date, reversed, now, reason, from).
- [ ] The record template lists the branch check's four outcomes: adopt
  an open pull request carrying the declaration line; report and ask the
  human about an open pull request without it; delete and recut after a
  merged or closed one; cut and open with an empty commit when none
  exists.
- [ ] The record template says Progress commits merge the default
  branch in first and never rebase or force-push, and that on a conflict
  the coordinator takes the default branch's roadmap and re-derives
  Progress.
- [ ] `references/brief-template.md` names goal, decisions the worker
  can't see, pointers to pushed artifacts, acceptance criteria, out of
  scope, and report-back by message with the coordinator's session name;
  says a worker's keep-alive is the workspace manager's to schedule; and
  contains no instruction for the worker to schedule one (R31).
- [ ] `references/verification-checklist.md` names the reads for head
  sha, each CI job's runner and step count, the file list and
  `git ls-remote`, and the report lines separating verified from
  unverified claims (R10).
- [ ] A read of each reference against SKILL.md finds no rule stated in
  both.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `skills/coordinate/references/loop.md`, `skills/coordinate/references/record-template.md`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/references/verification-checklist.md`

### Issue 3: feat(coordinate): add evals and the README row

**Goal**: Add `evals/evals.json` with the seven scenarios the PRD names
and a `/coordinate` row in the README's implementation-altitude table,
then run the feature's hygiene checks.

**Acceptance Criteria**:
- [ ] `skills/coordinate/evals/evals.json` has `skill_name` and one
  scenario for each of: a roadmap invocation whose extra text is
  decisions, a non-Active roadmap, a worker reporting green, a restart
  with an unconfirmed merge, a decision that belongs to the human, a new
  decision arriving mid-run, and a teardown request, each with
  transcript-checkable assertions (R38).
- [ ] Every scenario carries at least one negative assertion, such as
  "no worker is dispatched" for the non-Active roadmap or "the green is
  not relayed before the head sha and CI jobs are read" for the worker
  report.
- [ ] `scripts/check-evals-exist.sh` passes.
- [ ] `README.md` has a `/coordinate` row in the execute-chain table.
- [ ] `git grep -nE 'wip[/]'` on the branch returns nothing once the
  scoping files are removed, `git grep -n 'private/'` over the added
  files returns nothing, and a read of the added files finds no private
  repository name, session or instance name, or job id (R36).
- [ ] The pull request changes files only under `skills/coordinate/`,
  `README.md` and `docs/` (R37).
- [ ] Every CI job on the pull request is green, read job by job.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Type**: docs
**Files**: `skills/coordinate/evals/evals.json`, `README.md`

## Implementation Sequence

The sequence is I1, then I2, then I3. I1 comes first because it states
every rule the other two refer to. I2 and I3 touch different files, but
I3's hygiene and CI checks run over the whole pull request, including
I2's references, so I3 goes last.
