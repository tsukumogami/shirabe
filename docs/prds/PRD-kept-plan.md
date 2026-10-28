---
schema: prd/v1
status: In Progress
problem: |
  When a feature's work merges, shirabe deletes the plan that work followed,
  and a single-PR plan never reaches the default branch at all. A reviewer,
  maintainer or later session can't find what was agreed, can't see each
  step's proof or the run's recorded decisions, and can't move between a
  merged PR and its plan. shirabe's references disagree about this, and its
  validator enforces the deletion.
goals: |
  After a feature's work merges, its plan stays on the default branch at
  Done, recording for each step or issue the PR that carried it out and every
  decision the run recorded against it, and for each completed plan/v2 step
  its proof. Each of those PRs names the plan. Nothing in shirabe deletes the
  plan, every reference states the same lifecycle, and a design that names
  its plan validates.
absorbed:
  - docs/briefs/BRIEF-kept-plan.md
---

# PRD: Kept plan

## Status

In Progress

Accepted under `/scope`'s non-interactive mode on a three-seat jury that passed
on its third round; the first two rounds failed on undefined formats, timing
and coverage, which the requirements now settle.

Absorbed [BRIEF-kept-plan](docs/briefs/BRIEF-kept-plan.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so the plan a feature's work followed is still there, and
still reachable, after that work merges. The brief framed who loses when it
isn't: a reviewer judging finished work against what was agreed, a maintainer
starting from one merged pull request, a session picking up related work, and a
design author who can't point a design at its plan without failing
validation. It also framed shirabe's own disagreement about the plan's
lifecycle, and left one question downstream: shirabe's classification of the
plan as a working document changes here, while the same classification held
outside the repository is its owner's call, which nothing here waits on. This
document's Problem Statement, User Stories and Decisions and Trade-offs carry
each of these in full.

## Problem Statement

A plan is where shirabe breaks a feature's work into steps (plan/v2) or issues
(plan/v1), each with acceptance criteria and, in a step plan, a check that
shows the behaviour landed. While the work runs, sessions read the plan as
their contract. When the work finishes, the completion cascade flips the plan
to Done and removes it with `git rm` in the same commit that advances the
brief, PRD and design. For a single-PR plan that commit lands on the plan's
own branch, so the plan is added and removed before the squash merge, and the
default branch never sees it.

Three groups lose something. A reviewer judging whether a finished feature did
what was agreed has no agreement to judge against. A maintainer looking at one
merged pull request can't tell which step or issue it carried out, because no
PR body names its plan and no plan names its PRs (a coordination PR's index is
the one exception, and it lives in a PR body, not the repository). And a later
session picking up related work can't see what the earlier run decided: a
step's proof sits in a session key and each decision is an event in a local
workflow session, and neither is written anywhere a later reader can open.

shirabe contradicts itself here. The plan format reference says a plan stays in
`docs/plans/` through every state; the planning skill says it is deleted by the
cascade; the pipeline reference classes it as a working document, like a
roadmap; and the validator enforces that class three ways: a lifetime rule
(`R11`) that rejects a durable document naming a plan, lifecycle checks (`L01`)
that require a plan to be gone at merge, and a finalize step that reports the
plan for deletion. The pipeline reference's rule that a durable document never
names a working one is why a design can't point at the plan that implemented
it.

## Goals

- A reader on the default branch finds the plan a merged feature followed at
  `docs/plans/PLAN-<topic>.md`, at Done.
- Each step or issue in that plan names the PR that carried it out, or why
  none did, and lists the decisions the run recorded against it with a
  citation the run's own record confirms. Each completed plan/v2 step also
  carries its proof.
- Each PR that carried out a plan names the plan and the step or issue, in the
  text that becomes its squash commit message.
- Single-PR, multi-PR and coordinated plans all end this way.
- shirabe's references state one lifecycle for a plan once its work is done,
  and the validator agrees with them.

## User Stories

- As a **reviewer** asked whether a merged feature did what was agreed, I want
  to open its plan on the default branch and read each step's criteria, proof
  and recorded decisions, so that I judge the work against the agreement.
- As a **reviewer** checking a run's decisions, I want each recorded decision
  in the plan to carry a citation and a matching copy in the PR, so that I can
  confirm any of them against the run's own record and know the plan's copy
  wasn't edited afterwards.
- As a **maintainer** bisecting a regression to one squash commit, I want the
  commit message to name the plan and the step or issue it carried out, so
  that I reach the plan and its sibling PRs without guessing a topic name.
- As an **author** delivering a small feature in one PR, I want the plan on
  the default branch after the squash merge, so that single-PR work leaves the
  same record a multi-PR plan does.
- As a **later session** scoping a follow-up to finished work, I want the
  earlier plan and its recorded decisions on the default branch, and a clear
  answer when my topic name is already taken by a finished plan, so that I
  build on what was decided instead of re-deciding it.
- As a **design author**, I want the design to name the plan that implemented
  it and `shirabe validate` to accept that, so that a reader of the design can
  follow it to the work.
- As a **coordinator** driving a coordinated plan across several PRs, I want
  the coordination PR to write each node's PR into the plan before it is
  marked ready, so that the record does not live only in a PR body.

## Requirements

### Terms

- **Completion cascade**: `run-cascade.sh`, as run by `/execute`'s
  `plan_completion` state and `/work-on`'s `cascade_run` state, together with
  `shirabe finalize-chain` and `verify-cascade-commit.sh`.
- **Delivery run**: a `/execute` or `/work-on` run carrying out a plan. Its
  **piece sessions** are the koto sessions that carry out one step or issue
  each: an `/execute` child session, or the `/work-on` session for one issue.
  Its **owning session** is the `/execute` session that runs the plan, when
  there is one.
- **Entry key**: `Step <N>` for a plan/v2 step; for a plan/v1 issue, its
  GitHub reference `owner/repo#N`, or `Issue <N>` for an outline with no
  filed issue.
- **Decision citation**: `<session>#<seq>`, where `<session>` is the koto
  session name and `<seq>` is the sequence number koto gave the
  `decision_recorded` event in that session's log.
- **Landing PR**: for `single-pr`, the one PR; for `multi-pr`, the PR whose
  run finds every other entry key settled in the default branch's copy of the
  plan, a key being settled when it already has an entry or its work is
  closed without one (its issue closed, or its step dropped), with `### Plan`
  never counted; for `coordinated`, the coordination PR.

### Functional

**Keeping the plan**

- **R1.** The completion cascade sets the plan to Done and leaves the file in
  place. Nothing that runs after a plan's work completes removes it, for
  `single-pr`, `multi-pr` and `coordinated` plans at plan/v1 and plan/v2.
  Running the cascade again on a Done plan makes no commit.
- **R2.** The plan becomes Done in its landing PR, before that PR is marked
  ready, so a `single-pr` plan is on the default branch at Done once its PR is
  squash-merged. For `multi-pr`, a delivery run that finds, after bringing the
  default branch into its branch, that every other entry key is recorded,
  treats its PR as the landing PR; when two PRs race, the second one to bring
  in the default branch finds the first's entry and becomes the landing PR.
- **R3.** A kept plan stays at `docs/plans/PLAN-<topic>.md`, the path it had
  while Active.
- **R4.** No shirabe skill edits a Done plan's content after its landing PR
  merges.
- **R5.** When a topic's plan is at Done, `/scope` and `/deliver` treat the
  topic as executed, with `--intent=continue`, `--intent=stop` or no intent:
  they leave the plan unchanged and print that the topic is executed and that
  follow-up work needs a new topic name.
- **R6.** Abandonment is unchanged: `/scope` still removes an uncommitted plan
  it left on an abandoned run, and a committed Draft plan still fails `L01`.

**The run record**

- **R7.** A Done plan carries a `## Run Record` section with one entry per
  entry key, in plan order, plus a `### Plan` entry for the owning session.
  Each entry is a `### <entry key>` heading followed by these lines, in this
  order:
  - `PRs: owner/repo#N[, owner/repo#N...]` naming each PR whose diff carried
    work for that entry, or `PRs: none (<reason>)` with one reason:
    `dropped` (the owner removed the work from the plan before it started),
    `skipped` (the delivery run ended the piece with a recorded outcome other
    than done), or `no-change` (the piece's run finished with no diff because
    the behaviour already held). The `### Plan` entry has no `PRs:` line.
  - For a completed plan/v2 step only: `Proof: <check> -> <result line>`,
    where `<check>` is the step's `**Check**:` text and `<result line>` is
    the result line the step's report quoted under the plan format
    reference's report rule, or `Proof: not reported.` when the report
    quoted none.
  - `Decisions:` followed by one line per decision,
    `- <session>#<seq>: <choice> -- <reason>`, or the single line
    `Decisions: none recorded.`
- **R8.** A decision belongs to the entry whose piece session recorded it; a
  piece retried in more than one session carries the decisions of each, in
  the order the sessions ran. Decisions the owning session recorded go under
  `### Plan`. Choice and reason
  are copied verbatim with whitespace collapsed to single spaces.
- **R9.** Each entry is written by the delivery run, in its landing PR or in
  the PR that carried the entry's work, before that PR is marked ready, and
  rewritten in the same commit whenever the run pushes to that PR again. A
  `coordinated` plan's entries, whose node PRs may sit in other repositories,
  are written in the coordination PR. A plan is never back-filled from a
  search after merge.
- **R10.** Each PR that carries work for an entry has, in Part 1 of its body
  (above the `---` separator, the part the PR-body convention makes the
  squash commit message), the line
  `Plan: <path> (<entry key>[, <entry key>...])`, where `<path>` is
  `docs/plans/PLAN-<topic>.md` in the plan's repository or
  `owner/repo:docs/plans/PLAN-<topic>.md` from another repository.
- **R11.** The same PR's body has, in Part 2, a `Run record` part that repeats
  the `Decisions:` lines of each entry it carried, byte for byte as the plan
  has them, rewritten whenever the plan's entry is.
- **R12.** A command, `check-plan-record.sh <plan-path>`, reads a kept plan
  and, for each entry: confirms every `PRs:` reference is a full
  `owner/repo#N`; reads each named PR's body with `gh` and confirms its
  `Run record` part holds the entry's `Decisions:` lines byte for byte; and,
  when the cited session's log is in the local koto store, confirms each
  citation's event has the same choice and reason. It prints one line per
  mismatch, prints `session not retained: <session>` for a session it cannot
  read without counting it as a mismatch, and exits 1 on any mismatch, 2 when
  `gh` cannot read a named PR, and 0 otherwise. It also reports, without
  failing, a decision in a retained session that the plan does not carry
  (recorded after the last push).
- **R13.** In a repository whose CLAUDE.md declares `Repo Visibility:
  Public`, a decision whose choice or reason `shirabe validate
  --visibility=Public` would flag as naming private content is written as
  `- <session>#<seq>: withheld (private content)` in both plan and PR, a
  PR reference to a private repository as `withheld (private content)`, and
  a proof naming private content as `Proof: withheld (private content)`. The
  check in R12 compares a withheld entry by citation only.

**Validation**

- **R14.** A plan is a durable document. `shirabe validate` reports no `R11`
  finding for a document that names a plan in `upstream:`, and still reports
  `R11` for a durable document other than an Active plan that names a
  roadmap.
- **R15.** A design names the plan that implemented it in a `plan:`
  frontmatter field, written by the completion cascade when it moves the
  design to Current. `shirabe validate` checks that the field names a
  `PLAN-*.md` file that exists and whose `upstream:` names that design, and
  reports a finding naming both documents when it does not.
- **R16.** The lifecycle checks expect a plan present at Done where they
  expected it absent. For each posture and mode:

  | Posture | Mode | Plan present at | Result |
  |---------|------|-----------------|--------|
  | multi-pr in-flight | multi-pr | Active | pass (unchanged) |
  | multi-pr work-completing | multi-pr | Done | pass (was `L01`) |
  | multi-pr at-merge | multi-pr | Done | pass (was `L01`) |
  | single-pr mid-PR | single-pr, coordinated, outline multi-pr | Active | pass (unchanged) |
  | single-pr at-merge | single-pr, coordinated, outline multi-pr | Done | pass (was `L01`) |
  | any at-merge | any | Active | `L01` (unchanged) |
  | any | any | absent, design at Current | pass (plans deleted before this shipped) |

  In the Done rows the plan's design may be at Current or Superseded.
- **R17.** When the completion cascade sets a plan Done, it replaces a roadmap
  entry in the plan's `upstream:` with that roadmap's own `upstream:` entries
  (the strategy or vision it sequences), omitting it when the roadmap has
  none, and names the roadmap in the plan's Status prose. A kept plan whose
  roadmap is later deleted therefore still validates.
- **R18.** `shirabe finalize-chain` reports the plan as a transition to Done,
  and its output names no `delete_plan` action.

**Agreement and readers of `docs/plans/`**

- **R19.** Each of these documents contains the sentence "A plan stays at
  `docs/plans/PLAN-<topic>.md`, at Done, once its work is done; nothing
  deletes it." and no statement that a plan is deleted when its work
  completes: `README.md`, `references/pipeline-model.md`,
  `references/coordination-strategy.md`, `references/jev-criteria.md`,
  `skills/plan/SKILL.md`, `skills/plan/references/plan-format.md`,
  `skills/plan/references/quality/plan-doc-structure.md`,
  `skills/plan/references/phases/phase-7-creation.md`,
  `skills/execute/SKILL.md`, `skills/work-on/SKILL.md`,
  `skills/scope/SKILL.md`, `skills/scope/references/phases/phase-0-setup.md`,
  `skills/scope/references/phases/phase-resume.md`,
  `skills/scope/koto-templates/scope.md`,
  `skills/design/references/design-format.md`, `skills/roadmap/SKILL.md`,
  `docs/guides/lifecycle-posture.md` and `docs/guides/doc-validation.md`.
- **R20.** These lookups skip a Done plan when resolving work to run, so a
  Done plan never causes an ambiguous match and never receives new work:
  `find-anchor-plan.sh`, `drift-facts.sh`, `/execute`'s setup and its
  plan-gone recovery in `execute-open.sh`, and the `/scope` and `/deliver`
  resume probes. The design confirms this list against the code and adds any
  lookup it finds.

### Non-functional

- **R21.** The change touches no file in koto or niwa. Citations use what a
  koto session already records.
- **R22.** Changed scripts run on bash 3.2.
- **R23.** Plans deleted before this ships stay deleted: nothing reads git
  history to recreate one.
- **R24.** A plan Active on a branch when this ships ends the kept way when
  its cascade runs under the new release; one whose cascade already deleted
  it stays deleted.

## Acceptance Criteria

Keeping the plan

- [ ] `run-cascade_test.sh` has a scenario for each of `single-pr`,
      `multi-pr` and `coordinated`, at plan/v1 and at plan/v2 where the mode
      allows it, in which the plan is present at `status: Done` after the
      cascade and no cascade commit deletes it (R1).
- [ ] A second cascade run on the same chain makes no commit and leaves the
      plan byte-identical (R1).
- [ ] `verify-cascade-commit.sh` passes when the cascade commit sets the plan
      to Done and keeps it, and fails when a commit deletes the plan (R1).
- [ ] A fresh session runs a `single-pr` delivery of a two-step plan/v2 plan
      for a sample topic in a scratch repository through a squash merge, and
      `docs/plans/PLAN-<topic>.md` is on the default branch at `status: Done`
      with a `## Run Record` entry for each step (R2, R3, R7).
- [ ] In a `multi-pr` fixture of three issues, the plan is Active after the
      first two PRs merge and Done in the third PR's diff; with the second
      and third PRs open together, the one that brings in the default branch
      after the other merged is the one that sets Done (R2).
- [ ] In a `coordinated` fixture, the plan is Done in the coordination PR's
      diff and every node PR appears in a `PRs:` line (R2, R9).
- [ ] `/scope <topic>` and `/deliver <topic>`, each with
      `--intent=continue`, `--intent=stop` and no intent, on a topic whose
      plan is Done, leave the plan unchanged and print that the topic is
      executed and needs a new topic name for follow-up work (R5).
- [ ] An abandoned `/scope` run leaves no plan file, and `shirabe validate`
      still reports `L01` for a committed Draft plan (R6).
- [ ] In every fixture, the kept plan's path after the landing PR merges is
      the path it had at Active (R3).
- [ ] In the `multi-pr` fixture, a fourth delivery run started after the
      landing PR merged leaves the Done plan byte-identical (R4).

The run record

- [ ] Every fixture kept plan's `## Run Record` has exactly one entry per
      entry key, in plan order, plus `### Plan`, each with the lines in the
      order R7 gives; a step dropped by the owner shows `PRs: none (dropped)`,
      a step whose run ended blocked shows `PRs: none (skipped)`, and a step
      whose run finished with no diff shows `PRs: none (no-change)` (R7).
- [ ] For a fixture run whose Step 1 session recorded two decisions, whose
      Step 2 session recorded none and whose owning session recorded one, the
      plan shows the two under `### Step 1`, `Decisions: none recorded.`
      under `### Step 2` only, and the one under `### Plan` (R7, R8).
- [ ] A completed fixture step whose report quoted no result line shows
      `Proof: not reported.` (R7).
- [ ] In the fixture runs, each entry appears in a commit on the branch of a
      PR it names, before that PR's ready event; a push after ready that adds
      a decision rewrites the entry and the PR's `Run record` part together
      (R9, R11).
- [ ] Part 1 of each fixture PR's body has a `Plan:` line naming the plan and
      the entry keys it carried; a node PR in another repository uses the
      `owner/repo:` form (R10).
- [ ] `check-plan-record.sh` exits 0 on the fixture; exits 1 naming the entry
      when a plan reason is edited, when a citation's `<seq>` points at
      another event, or when a `PRs:` line holds a bare `#N`; prints
      `session not retained` and still exits 0 when the cited session is
      absent; and exits 2 when a named PR cannot be read (R12).
- [ ] In a Public fixture repository, a decision naming a private issue is
      written as `withheld (private content)` in plan and PR, the kept plan
      passes `shirabe validate --visibility=Public`, and the R12 check passes
      on it (R13).
- [ ] On the first kept plan delivered after release, `check-plan-record.sh`
      exits 0, and a reviewer finds two of its decisions, by citation, in the
      PR copy (R11, R12).

Validation

- [ ] `shirabe validate` reports no `R11` for a design, PRD or brief whose
      `upstream:` names a plan; still reports `R11` for a design naming a
      roadmap and for a Done plan naming a roadmap; and reports none for an
      Active plan naming a roadmap (R14).
- [ ] After the cascade in each fixture, the design at Current has a `plan:`
      field naming the kept plan (R15).
- [ ] A Current design whose `plan:` names its Done plan validates; one whose
      `plan:` names a missing file, or a plan whose `upstream:` names another
      design, fails with a finding naming both documents (R15).
- [ ] Lifecycle tests cover each row of the R16 table with the result it
      gives (R16).
- [ ] After the cascade on a fixture plan naming a roadmap, the plan's
      `upstream:` names the roadmap's strategy instead and its Status prose
      names the roadmap; after the roadmap is then deleted, the plan
      validates (R17).
- [ ] `shirabe finalize-chain` JSON for a chain rooted at a plan lists the
      plan with a transition to `Done` and no `delete_plan` action (R18).

Agreement and readers

- [ ] Each document R19 lists contains the R19 sentence (`grep -F`), and none
      matches `-> DELETED` or `git rm` followed on the same line by `PLAN`
      (R19).
- [ ] With a Done plan and an Active plan both naming issue `#N`,
      `find-anchor-plan.sh` resolves the Active one, and with only the Done
      plan it reports no anchor plan; each other lookup R20 lists has a test
      with one Done and one Active plan for the same work that resolves to the
      Active plan (R20).

Non-functional

- [ ] The implementing PRs change files only in the shirabe repository (R21).
- [ ] The changed scripts' tests pass in CI's macOS floor job, which runs
      bash 3.2 (R22).
- [ ] The cascade on a chain whose plan was deleted before this shipped
      creates no plan file (R23, R24).
- [ ] The cascade on a fixture chain with an Active plan committed before
      the change keeps that plan at Done (R24).

## Out of Scope

- **A record home other than the repository.** Where a team keeps the plan
  when its record isn't the repository is a separate question. The design
  should keep the location decided in one place to leave room for it, but no
  behaviour here depends on another home.
- **Writing departures into the plan as they happen, and accepting them.**
  Keeping the plan in step with the work during a run, with a decider
  accepting each change, is a separate feature. This one copies what the run
  recorded at the point each piece of work lands.
- **Telling a departure from a routine decision.** Every recorded decision is
  kept; classifying them belongs to the feature that keeps the plan in step.
- **Accepting a plan before work starts.**
- **Back-filling plans deleted before this ships** (R23).
- **Keeping roadmaps.** A roadmap stays a working document; R17 only stops a
  kept plan from breaking when its roadmap goes.
- **Reverts.** A PR reverted after merge leaves its record in the plan; the
  revert is new work with its own record.
- **Changes to koto or niwa** (R21).

## Known Limitations

- A koto session lives in the local store of the machine that ran it, so a
  reader elsewhere checks a decision against the PR's copy; the session is
  the stronger check where it is still retained.
- Both copies are written by the delivery run, at different times, from the
  same session. That catches a plan entry edited afterwards, but not a run
  that recorded something false in the first place.
- A finished topic keeps its name: follow-up work needs a new topic slug.
- Two `multi-pr` PRs worked by hand at the same time can conflict on the
  `## Run Record` section; the second to bring in the default branch resolves
  it. Delivery runs carry out one issue at a time, so they don't meet this.
- `docs/plans/` grows with every finished feature. That is the cost of the
  record.

## Decisions and Trade-offs

- **Keep every recorded decision, not only departures.** Alternatives: keep
  only decisions marked as departures; keep none and link to the PR. No
  recorded decision says today whether it departs from the plan, so keeping
  all of them is the superset that contains every departure, at the cost of
  length.
- **The PR body is the reader-reachable copy.** Alternatives: cite only the
  session; add an export to koto. Sessions are local and koto changes are out
  of scope, so the PR body, written from the session, is the copy any later
  reader can open; the citation serves readers who can reach the session.
- **The plan becomes Done in the PR that lands its last work.** Alternatives:
  a follow-up commit on the default branch after merge; a separate
  housekeeping PR. Either alternative writes to the default branch outside a
  reviewed PR, or adds a PR per plan; landing Done with the last work keeps
  the record in the reviewed change, which is also how a single-PR plan
  reaches the default branch.
- **The path does not change at Done.** Alternatives: move to
  `docs/plans/done/`. A move would break every link a PR or design wrote while
  the plan was Active; status already says the plan is finished.
- **The record lives in its own section.** Alternatives: lines inside each
  step block; extra columns in the Implementation Issues table. A step block
  may be a one-line outline the format forbids extending, and the table's
  columns are fixed, so a `## Run Record` section works the same for both plan
  versions and leaves the agreed steps untouched.
- **A design names its plan in frontmatter.** Alternatives: a prose link; an
  `upstream:` entry. `upstream:` points up the chain, so a design naming its
  plan there would break the direction rule, and a prose link can't be
  checked against the plan's own `upstream:`. A `plan:` field written at
  Current can be checked both ways.
- **A Done plan stops naming its roadmap in `upstream:`.** Alternatives:
  keep roadmaps; let a dangling `upstream:` pass. Keeping roadmaps is out of
  scope, and a durable document with a dangling `upstream:` is what the
  lifetime rule exists to prevent, so the plan names the roadmap's own
  durable parent, the way a brief already does, and keeps the roadmap's name
  in prose.
- **PR links in Part 1 of the PR body.** Alternatives: Part 2 only; a label.
  Part 1 becomes the squash commit message, which is where `git log` and
  blame readers start.
- **The plan's working-document classification.** shirabe's own class for
  the plan changes here: a plan becomes durable. The same classification is
  also held outside this repository by the owner of the toolkit's planning
  record, and that call is theirs. Nothing here waits on it, and the design
  records it as an open question for them.

## Downstream Artifacts

- `docs/designs/DESIGN-kept-plan.md` (planned) -- where each record is
  written, which rules change, and the file list.
