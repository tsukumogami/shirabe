---
schema: prd/v1
status: In Progress
problem: |
  The coordinate skill keeps a coordinator's state in two stores: the GitHub
  record (an issue body and comment stream at roadmap scope, a committed handoff
  file on a rotation pull request at discipline scope) and the coordinator's
  koto session. Every state change is made and tested against both, GitHub is
  still the default, a discipline coordinator can't use the session at all, and
  the shipped designs name a store that is meant to go. The session store has
  run a coordinator end to end and been signed off, so the GitHub record is now
  only a fallback, and it costs something on every change to the skill.
goals: |
  A coordinator at either scope keeps its state in its koto session and nowhere
  else, with every guarantee the record's write core gave. A maintainer changes
  one store. Outside readers of cost and verdict entries still find them on
  GitHub, on items that are GitHub's own. The removal never touches a live
  coordinator, and no coordinate script sources a record library or parses a
  record body when it's done.
motivating_context: |
  The session store passed its dogfood gate: a coordinator moved onto it, ran a
  dispatch-to-merge loop on it, was handed off twice by import, and its owner read
  its state through koto's session view and said that was enough. The removal is
  scoped now and built later, once no coordinator still runs on the GitHub record.
absorbed:
  - docs/briefs/BRIEF-coordinator-record-teardown.md
---

# PRD: Tear down the GitHub coordinator record

## Status

In Progress

The completeness, clarity and testability reviewers passed it over two rounds.
The downstream DESIGN owns the approach.

Absorbed [BRIEF-coordinator-record-teardown](docs/briefs/BRIEF-coordinator-record-teardown.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so the coordinate skill keeps one store for a coordinator's
state instead of two. The brief framed the cost of the GitHub record that the
session store left in place as a fallback: maintainers make and test every
state change against two backends, an owner gets the GitHub issue by default
and a moved coordinator keeps a stub issue, a discipline coordinator can't use
the session at all, outside readers of cost and verdict entries depend on the
issue, and the shipped designs name the wrong store. This document's Problem
Statement states each of these in full.

The outcome it set: a maintainer changes what a coordinator remembers once, in
one store, and the designs they read name it; an owner starts a coordinator at
either scope with nothing to choose, no issue opened and no file committed; a
person reads a coordinator's state through koto's session view; outside
readers still find their entries on GitHub; and a coordinator still running on
the record is never touched mid-run. Goals and User Stories carry that outcome.

Its journeys were a new roadmap coordinator starting after the removal, a
discipline rotation handing over to the next, the owner of a coordinator that
started on the GitHub record, a cost reviewer and a roadmap reader looking for
an entry, and a maintainer amending the skill afterwards. User Stories, R1,
R5, R7, R10, R11, R16, R17 and R20 carry them.

Its scope boundary put in the removal of the record and everything that exists
only because of it, keeping the write core's guarantees on the session,
discipline scope on the session, a destination for the outward entries, the
dated amendments and the supersession, and an order that never touches a live
coordinator; and it put out GitHub's own surfaces, the coordinated `/execute`
run's pull request body, moving any live coordinator, new koto features, new
state, and the teardown archive. Requirements and Out of Scope carry it.

## Problem Statement

The coordinate skill drives a coordinator: a long-running session that hands
units of work to other sessions, verifies what they push and lands it. Its state
(holdings, holds, deferrals, side effects, reversals, the run's arguments, the
standing answers people gave it, the next step per holding, its decisions and an
account of what happened) has to survive a crash, a restart and a move between
hosts.

That state has two homes today. The original is the **GitHub record**. At
roadmap scope it's an issue titled `Coordinator record: ROADMAP-<name>`, whose
body is a set of markdown tables rewritten whole on every write, with an
append-only stream of marked comments beside it whose authors are checked
against the repository's collaborator permissions. At discipline scope it's a
draft pull request whose diff is a handoff file committed to
`docs/disciplines/<name>.md`. The second home is the **coordinator's koto
session**: one key per section under `record/`, entries under
`record/entries/`, worker legs under `legs/`. A coordinator has run on the
session end to end, been imported into a fresh instance twice, and had its state
read through koto's session view by its owner, who signed it off.

The GitHub record was kept as the default and the fallback. It now costs the
people who work on and with the skill:

- **Maintainers make every state change twice.** One read seam serves the state
  from either store. Sixteen `record-*.sh` scripts and a markdown codec sit
  under the other scripts that read or write the state. The session path still
  renders the state to an issue body and parses it back to validate a write,
  and is still held to a 60,000-byte budget sized for GitHub's body limit.
- **Owners get the old store by default.** A new coordinator opens a GitHub
  issue unless someone passes `--store session`, and a coordinator already on
  its session keeps a stub issue so its start-up search can find the row that
  points away from it.
- **Discipline coordinators can't move.** Discipline scope refuses the session
  store, so a rotation still commits its state to a branch and carries it on a
  pull request.
- **Outside readers depend on the issue.** Cost, milestone-verdict,
  milestone-failure and goal-fit entries are posted as comments on the record
  issue, because a cost reviewer and a roadmap reader look for them there, and a
  roadmap's progress notes link to those comments.
- **The designs describe the wrong store.** Shipped designs and requirements
  documents for the skill say the record on GitHub is where their facts live.

## Goals

- A maintainer who changes what a coordinator remembers makes the change once,
  in the session's keys, and tests it once. No markdown table, codec or byte
  budget sized for an issue body is involved, and the designs they read name the
  store that's really there.
- An owner who starts a coordinator, at roadmap or discipline scope, has nothing
  to choose: it starts on its session, opens no issue and commits no file.
- A person reads a coordinator's state through koto's session view. GitHub
  stays where they look for pull requests, checks, reviews, merges and issues
  that are units of work.
- A cost reviewer and a roadmap reader still find the entries they read today on
  GitHub, on items that are GitHub's own, with the same marker line and text.
- No running coordinator is touched. A coordinator moves to its session at its
  next start, or finishes where it is.

## User Stories

- **As a maintainer of the coordinate skill**, when I add a column to a holding,
  I want to change the state's JSON validation and the one writer that owns that
  key, and run the suites against the session alone, so that a change to the
  state is made and tested once.
- **As the owner of a new roadmap coordinator**, when I start it after the
  removal, I want it to open its session and nothing on GitHub, and on a restart
  or another host to resume or import that session, so that I never pick a store
  and the state is in one place.
- **As the owner of a discipline coordinator**, when a rotation ends, I want the
  next rotation to read what the last one left (its holds, standing answers,
  next steps, unsettled decisions and reasoning) from the last rotation's
  session, so that no branch, handoff file or pull request carries coordinator
  state.
- **As the owner of a discipline coordinator starting its first rotation, or
  one whose previous rotation can't be read**, I want the start to say which of
  the two it is, so that I know whether anything was carried.
- **As the owner of a coordinator that started on the GitHub record**, when the
  removal is ready to build, I want my coordinator left alone until its next
  start, then moved to its session with the move the skill ships today (or its
  rotation left to end), so that nothing changes under a running run.
- **As a cost reviewer**, when I total what a week's units spent, I want to find
  each unit's cost entry on that unit's pull request with the same marker and
  text as today, so that my join still works without a coordinator issue.
- **As a roadmap reader**, when I follow a link in a roadmap's progress notes to
  the milestone verdict behind a status change, I want it to resolve, both for
  links written before the removal and after, so that the reason for a status
  stays one click away.
- **As a maintainer of the skill's CI and registries**, when the scripts are
  renamed and removed, I want every workflow, list and coverage row to follow
  them, so that no suite silently stops running.
- **As a reader of the skill's designs**, when I look up where holds, pauses,
  decisions or the dispatch path keep their facts, I want each design to say the
  session, dated, without its logic being rewritten, so that the documents match
  the code.

## Requirements

### Functional

**R1. One store.** A coordinator at roadmap or discipline scope keeps every part
of its state that the GitHub record held (the sections, the stored set, the
decisions, the holds, the account, and at discipline scope the rotation window,
the host repository and the reasoning for the next rotation) in its own koto
session and nowhere else. Nothing in the coordinate skill reads coordinator
state from, or writes it to, a GitHub issue body, an issue comment, a pull
request body or a committed file. Posting an outward entry (R5) is a copy of a
session entry, not state the skill reads back to act on, except as R5 states
for `roadmap-status.sh`.

**R2. No choice of store.** The per-run choice of store is removed: the
`--store` option of `coordinate-open.sh`, the `STORE` template variable, the
`store` Run row and the sealed source it decides, and the refusal codes that
exist only to arbitrate between stores: `store-malformed`, `store-unverified`,
`store-conflict`, `store-moved` and `store-discipline`. A coordinator's start
opens, resumes or imports its session. The check that koto has the features the
session store needs stays, as a start-up requirement rather than a choice: a
koto without them is refused at start with `store-unsupported`, as today.

**R3. The GitHub container goes.** The skill no longer creates, searches for,
edits, closes or reads a coordinator issue, and no longer creates, edits,
readies or reads a rotation pull request, commits to its branch or deletes it.
The open-issue search by title and the moved-shape stub issue go with it. A
start after the removal doesn't look at GitHub for a record at all.

**R4. The comment stream goes.** The skill no longer posts or lists marked
record comments on a coordinator issue, and no longer reads collaborator
permissions to decide whether a comment is an entry. The account is the
session's entries alone.

**R5. Outward entries reach their readers on GitHub's own items.** The four
outward kinds are written to the session first, then posted to GitHub with
today's marker line (`<!-- coordinator-record-entry v1 kind=<kind> -->`) and
today's text, byte for byte, so an exact-prefix join and a byte comparison
still match. They're posted here, never on a coordinator issue:

| Kind | Posted on | When that item doesn't exist |
|---|---|---|
| `cost` | the unit's pull request (the holding's Pull request) | the unit's issue when the unit is an issue; otherwise nowhere, and the entry stays in the session and the teardown archive, with the capture's output saying so |
| `goal-fit` | the pull request the entry names (`Goal fit: <owner/repo#n>`) | refused: a goal-fit judgment always names one |
| `milestone-verdict` | the roadmap pull request `roadmap-status.sh --verdict` opens for the status edit | refused: the verdict is posted by the command that opens its pull request |
| `milestone-failure` | the roadmap pull request `roadmap-status.sh --reopen` opens | refused, as above |

The roadmap's `## Progress` line cites the posted comment's URL, as it does
today. Since a verdict or failure comment can only be posted once its roadmap
pull request exists, the progress line reaches that pull request in a commit
pushed after the comment is posted, before the pull request is handed over. `roadmap-status.sh --verdict`, `--reopen` and `--confirm` read an entry
back by its comment URL whether the comment is on an issue or a pull request of
the roadmap's repository, and check its marker, kind, text and hash as today.
`skills/coordinate/references/unit-cost.md` says where cost entries are and how
to read a scope's set.

**R6. A failed post is kept and retried, never doubled.** When the post fails,
the session entry stays and the write reports it (exit 14, as today); a retry
posts the entry once, and posts nothing when the session's `record/posted/<n>`
key (which the session store writes today) records the comment, or when the
target item already holds a comment with the same marker and text, created at or
after the entry's stamp by the GitHub login the coordinator posts as. A matching
comment by any other login, or older than the entry, never stands in for it. No
collaborator-permission read is involved.

**R7. Existing GitHub records are left alone.** Nothing the removal does
deletes, closes or edits an existing coordinator issue, issue comment, rotation
pull request or rotation branch. A roadmap progress line that already cites a
comment on a coordinator issue is still accepted by `roadmap-status.sh
--confirm`.

**R8. Every write-core guarantee survives on the session.** The baseline is
`skills/coordinate/scripts/record-codec.jq` and `record-write-core.sh` at the
commit the PLAN's first issue starts from. Every refusal they make that is not
about markdown layout or a GitHub byte limit survives, applied to the state's
JSON:

- one writer per key, by the writer flags that hold today;
- a compare against the state the writer read, refusing a changed state as
  `record-changed` (exit 12);
- the top-level field allow-list, and per row: control characters, the columns
  that may be empty, no column that records what GitHub recomputes, the worker
  and address shapes, the pull request link grammar;
- the Holds rules, the stored-set rules (Run keys, Standing and Work rows,
  rework and pause rules) and the Decisions rules (states, transitions,
  stamps);
- the checks that refuse a private repository name, a home-directory path or a
  token-shaped string in any value that can leave the host.

No write renders a markdown body or parses one. The design lists each refusal
and the test case that keeps it.

**R9. No size limit that only GitHub needed.** No check against the
60,000-byte record budget or the 65,536-byte body limit remains, and a state
whose rendered body would have exceeded 60,000 bytes is written. Any size bound
the session keeps has a number and a reason in the design that isn't GitHub's
body limit. The design says, for each stop or archive that exists because a body
could fill up (`record-full`, the settled-decisions archive), whether it is
removed or kept and why.

**R10. Discipline scope runs on the session.** A discipline coordinator opens,
resumes and imports its session as a roadmap coordinator does, and a second live
session of the same discipline on one host is refused. The session holds, beyond
the roadmap scope's keys, the rotation window (start and end dates) and the host
repository, which the rotation pull request's title and branch hold today, and
the reasoning for the next rotation, which the handoff file holds today.

**R11. A rotation reads its predecessor from the predecessor's session.** A
discipline coordinator's session is named as a roadmap coordinator's is, from
the scope's slug and the run's UTC stamp, so a session belongs to a discipline by
its slug and is earlier by its stamp. A new rotation looks on its host for the
session of the same discipline with the latest stamp earlier than its own whose
`record/meta` key exists. A predecessor "can't be read" when that session's
`record/meta` or any section key fails the JSON validation R8 keeps. On another host, the owner imports that session
first with the opener's existing import. From it the new rotation carries
everything the handoff file carries today: the four sections (Holdings,
Deferrals, Side effects in flight, Reversals), Holds, Run, Standing and Work,
the unsettled decisions and the next decision number, and the reasoning for the
next rotation, which the reconcile pass classifies as
`present` or `not_recorded` as it does today. The start reports one of three
outcomes: a predecessor was carried; no earlier rotation exists (a first
rotation); or an earlier rotation exists but can't be read, which stops for the
person as an unreadable handoff file does today. A predecessor whose window has
passed but that never closed is carried with its reasoning recorded as
`not_recorded`, as an expired predecessor's record is today.

**R12. The committed handoff file and the rotation pull request go.** No
rotation commits `docs/disciplines/<name>.md`, opens or readies a rotation pull
request, or deletes a rotation branch. The template states that exist only for
those steps (`rotation_close`, `rotation_step`, `rotation_done` and the
`predecessor_*` states) are removed or replaced by states that read and close
the predecessor's session.

**R13. The session view is the human surface.** `record-source.sh --show`, which
renders the session's state as a record body, is removed. The skill's text, and
the reports that today name a coordinator issue, name koto's session view
(`koto context` over the coordinator's session) instead. The relay duty is
unchanged in substance: a person's word reaches the coordinator however it
arrives and the coordinator writes it to the session, but nothing tells anyone
to comment on a coordinator issue.

**R14. The existing session layout doesn't change.** Every key a session-store
coordinator writes today keeps its name and its JSON shape, so a coordinator
already on its session resumes, carries across and imports across the removal
with no migration. R10's discipline keys are the only additions.

**R15. What's GitHub's own is untouched.** Pull request state, head, checks,
reviews, mergeability and the merge; the review panel table a worker writes in
its pull request body; issues used as units of work; the roadmap read at the
default branch and the roadmap pull requests `roadmap-status.sh` opens; the
merge-order block a person reads; the CI merge-last gate's reads; and the
worker's handoff comment on its merged pull request keep working as they do
today, read live from GitHub.

**R16. The removal is complete.** After the last change, no script sources a
record library or parses a record body. Precisely, for every file under
`skills/coordinate/scripts/` and `skills/coordinate/koto-templates/`, test
files included:

- no file named `record-*.sh` and no `record-codec.jq` exists;
- no file names `record-common.sh`, `record-source.sh`, `record-parse.sh`,
  `record-render.sh` or `record-codec`;
- no file names the title `Coordinator record:`, a `collaborators/` permission
  endpoint, or `docs/disciplines/`;

except the structure test's own refusal fixtures (R17), which are the only files
allowed to contain these patterns and are named in that test. The marker line
`<!-- coordinator-record-entry v1` stays, because R5 posts it.

The session-side behaviour the removed scripts carry survives in scripts under
`skills/coordinate/scripts/` whose names don't start with `record-`. The design
gives a table of each session key and the one script that writes it, and a test
checks the table against the writer flags.

**R17. A structure test keeps it removed.** A test refuses any file in R16's
scope that matches one of R16's patterns, proves with one fixture per pattern
that each is refused, and passes on the skill's own files.

**R18. The surrounding registries move with the scripts.** Every CI workflow
whose path filter or step names a removed script names the script that replaced
it, and still runs the replacing suite. The bash-floor list, the check-skill
rows, the rule-coverage rows, the `requires.tsv` rows, the template's diagram,
the skill's text, its references and its eval fixtures name no removed script,
state, option or file.

**R19. The shipped documents say what changed.** `DESIGN-coordinate-record-container.md`
is superseded by the removal design, which states where the stored set it defined
(Run, Standing, Work) and its landed-feature write-back now live. Every other
shipped design and requirements document that names the GitHub record as the
store gets a dated amendment that keeps its logic and records only that the
storage moved to the session. The design lists them.

**R20. Nothing touches a live run.**

- A coordinator **runs on the GitHub record** while its roadmap's coordinator
  issue is open and its body isn't the moved shape, or while a discipline's
  rotation pull request is open. Its owner ends that by moving it (at its next
  start, with the `record_move` path the skill ships), by letting the rotation
  end, or by closing the issue or pull request, which is how an owner declares a
  coordinator finished or abandoned.
- No change that removes a reader or a writer of the GitHub record merges while
  any coordinator runs on the record. The PLAN gives the check as commands
  anyone can run against GitHub.
- Changes that remove nothing a running coordinator reads may land before
  that: the JSON validation, the outward-entry targets, discipline scope on the
  session, and the structure test in a form that allows the scripts not yet
  removed.
- The move path, the GitHub backend and the codec come out last, when nothing
  reads them.
- A start after the removal doesn't look at GitHub (R3), so a coordinator whose
  state is still on an unmoved record would start empty. The precondition is
  what prevents that, and the release that carries the removal says so.

### Non-functional

**R21. The skill's floor holds.** bash 3.2 and jq, with no new koto feature and
no raised koto floor in `requires.tsv`.

**R22. The suites run on the session alone.** No suite's `gh` stand-in serves an
issue body, a record comment list or a collaborator-permission read, and the
stand-in fails a test on any `gh` or `git push` call the test didn't expect.
Each behaviour a GitHub-only suite tests today that survives the removal is
tested on the session; the design lists those behaviours (at least a stored-set
gap at the handover gate, a hold and a pause re-read before a merge, a decision
transition, and a rotation's carry), and each has a named session test.

## Acceptance Criteria

**Removal and structure (R2, R3, R4, R16, R17)**

- [ ] `ls skills/coordinate/scripts/record-*.sh skills/coordinate/scripts/record-codec.jq`
      finds nothing.
- [ ] `grep -rlE 'record-(common|source|parse|render)\.sh|record-codec|Coordinator record:|collaborators/|docs/disciplines/|store-(malformed|unverified|conflict|moved|discipline)'
      skills/coordinate/scripts skills/coordinate/koto-templates` lists only the
      structure test's fixtures, each named in that test.
- [ ] The structure test fails on a fixture for each R16 pattern and passes on the
      skill's own files.
- [ ] `coordinate-open.sh --store session <roadmap>` exits 64 naming `--store`
      as unknown, and `koto-templates/coordinate.md` declares no `STORE`
      variable.
- [ ] With a koto stand-in that lacks `session import`, a start is refused with
      `store-unsupported`.
- [ ] A write of a Run row with key `store` is refused as an unknown Run key.

**Starts (R1, R3, R10, R11, R14, R22)**

- [ ] A suite starts a new roadmap coordinator and runs it through dispatch,
      land and merge; its `gh` stand-in records no issue create, edit, view,
      close or list of a coordinator issue, no comment list, and no
      collaborator-permission read, and fails on any unexpected `gh` call.
- [ ] A suite starts a discipline coordinator; the stand-in records no
      `gh pr create`, `gh pr ready`, contents write, ref deletion or `git push`,
      and the session holds the rotation's start and end dates and host
      repository.
- [ ] A suite starts a second rotation of the same discipline after a first that
      wrote a hold, a Standing row, a Work row, a deferral, an unsettled
      decision, a next decision number and reasoning text; the second rotation's
      session holds each of them, and reconcile classifies the reasoning
      `present`.
- [ ] A suite starts a discipline coordinator with no earlier rotation and gets
      the first-rotation outcome; one whose earlier rotation's session has
      a malformed `record/meta` gets the unreadable outcome and stops; one whose
      predecessor's window ended without closing carries it with reasoning
      `not_recorded`.
- [ ] A second live session of the same discipline on one host is refused.
- [ ] `koto-templates/coordinate.md` declares no `rotation_close`,
      `rotation_step`, `rotation_done`, `record_move` or `predecessor_*` state
      that commits a file, opens or readies a pull request, or deletes a branch.
- [ ] A fixture of a session-store coordinator's keys, captured from the release
      before the removal and committed with the tests, resumes and imports
      under the removal's scripts, and a diff of key names and JSON before and
      after the resume shows no change.

**Outward entries (R5, R6, R7)**

- [ ] A suite writes a `cost` entry for a unit with a pull request, one for a
      unit that is an issue, and one for a unit with neither; the first two are
      posted on that pull request or issue with today's marker line and text,
      and the third is posted nowhere and the capture's output says so.
- [ ] A suite writes a `goal-fit` entry and finds it on the pull request it
      names; `milestone-verdict` and `milestone-failure` entries are posted on
      the roadmap pull request `roadmap-status.sh --verdict` and `--reopen`
      open, and the `## Progress` line in that pull request cites the posted
      comment's URL.
- [ ] `roadmap-status.sh --confirm` accepts a progress line citing a comment on
      a roadmap pull request, and accepts one citing a comment on a coordinator
      issue; it refuses a cited comment whose marker, kind, text or hash differs.
- [ ] With the post failing, the write exits 14 and the session holds the entry;
      a retry posts it once; a second retry posts nothing; a retry where the
      target already holds the same comment by the coordinator's login, created
      after the entry's stamp, posts nothing; a retry where the matching comment
      is by another login, or older than the entry, posts the entry.
- [ ] A `goal-fit` entry that names no pull request, and a `milestone-verdict`
      or `milestone-failure` entry written other than through
      `roadmap-status.sh --verdict` or `--reopen`, are refused and posted
      nowhere.
- [ ] No suite's stand-in records a close, edit or delete of an issue, comment,
      pull request or branch that the test set up as an existing coordinator
      record.
- [ ] `references/unit-cost.md` gives a command that lists a scope's cost entries
      from where R5 posts them, and it doesn't name a coordinator issue.

**Write-core guarantees (R8, R9)**

- [ ] For each refusal the design lists under R8, a session test makes a write
      that breaks it and gets the refusal: among them a changed state
      (`record-changed`, exit 12), a second writer of an owned key, a disallowed
      top-level field, a control character, an empty required column, a
      recomputable column, a malformed worker, a malformed pull request link, a
      malformed hold, a bad Decisions transition, a private repository name, a
      home-directory path and a token-shaped string.
- [ ] No script under `skills/coordinate/scripts/` calls a markdown renderer or
      parser on coordinator state (covered by the structure test's patterns).
- [ ] A suite writes a state whose rendered body would exceed 60,000 bytes and
      the write succeeds; `grep -rnE '60000|65536' skills/coordinate/scripts`
      finds no size check other than the bound R9 lets the design keep with a
      stated reason (an outward entry's cap, since it is posted as a GitHub
      comment).

**GitHub's own surfaces (R15)**

- [ ] On a session holding a hold and a pause, `land-check.sh` and
      `land-merge.sh` both refuse the merge with the hold and pause reasons
      their suites check today, and the board, panel-evidence, merge-confirm
      and teardown-handoff suites pass unchanged in what they assert about
      GitHub.

**Human surface (R13)**

- [ ] `record-source.sh --show` no longer exists (covered by the first
      criterion), and `skills/coordinate/SKILL.md` names `koto context` over
      the coordinator's session as the way a person reads its state, and names
      no coordinator issue as a place to read or write state; the report
      scripts' output and the template's terminal results name the session,
      not a coordinator issue URL.

**Registries, documents, floor (R18, R19, R21)**

- [ ] For each workflow under `.github/workflows/` that names a path or script
      under `skills/coordinate/scripts/`, every named path exists, and every
      `paths:` filter that named a `record-*` pattern names the replacing
      scripts' pattern.
- [ ] Every script named in `scripts/bash-floor/coordinate.list`, the
      check-skill rows, `scripts/testdata/rule-coverage.tsv` and
      `skills/coordinate/scripts/requires.tsv` exists; none names a removed
      template state; and `requires.tsv` raises no koto floor.
- [ ] The bash-floor CI leg passes on the coordinate suites.
- [ ] `DESIGN-coordinate-record-container.md` has status `Superseded`, sits in
      `docs/designs/archive/`, and names the removal design in `superseded_by`.
- [ ] Each document the design lists for amendment ends with a
      `## Amendment — <date>` section whose first paragraph names the removal
      design and reads "The original text above is left unedited; this section
      records what no longer holds."; `git diff` of each against the PLAN's
      base commit adds lines only at the end; each keeps its status.
- [ ] `docs/disciplines/performance.md` is removed, and the eval fixture that
      commits a discipline handoff file is rewritten to the session form.

**Order (R20)**

- [ ] The PLAN states R20's precondition and its check commands, and every PLAN
      issue that removes a reader or writer of the GitHub record lists, among
      its dependencies, every issue R20 allows to land first.

## Out of Scope

- **GitHub's own surfaces** (R15): pull request state, checks, reviews,
  mergeability, issues used as units of work, the merge-order block, the CI
  merge-last gate's reads, the roadmap pull requests, the worker's handoff
  comment. They were never the record.
- **The coordinated `/execute` run's coordination pull request body.** Separate
  work already moved that run's state onto its own session; nothing here changes
  it.
- **Moving any live coordinator.** Coordinators move themselves at their next
  start with the move that ships. Closing or editing existing coordinator issues
  or rotation pull requests on GitHub is their owners' call, not this change's
  (R7).
- **Handoff files outside this repository.** A discipline whose rotation
  committed `docs/disciplines/<name>.md` in another repository keeps that file
  until its owner removes it; this change removes only this repository's copy.
- **New koto features**, such as a batch write of several keys or an append-only
  key stream. The removal works with the session store as it ships.
- **New state.** This removes a store. The only keys it adds are the discipline
  facts GitHub held (R10); it adds no section, column or entry kind.
- **The teardown archive and worker transcripts.** They are host-local files, not
  coordinator state.
- **Building the removal.** This document scopes it; the build waits for R20's
  precondition.

## Known Limitations

- **A moved coordinator's stub issue stays open.** The skill stops reading it,
  and closing it is its owner's call (R7). A person who finds an open
  coordinator issue after the removal reads a body that says the state moved.
- **An unmoved record started on the new release starts empty.** If an owner
  ignores the precondition and starts a coordinator whose state is still on its
  issue under the release that removes the record, the start doesn't find that
  state (R20). Its issue is untouched, so the owner can go back to the earlier
  release and move it.
- **A cost reviewer reads one item per unit.** A scope's cost entries were one
  comment list on one issue; now they sit on each unit's pull request, so a
  scope's set is a list of pull requests to read, and a unit with no pull
  request or issue has its entry only in the session and the archive.
- **Outward entries are only as durable as the item they're posted on.** A
  comment on a unit's pull request or a roadmap pull request lives as long as
  that item, as a comment on a coordinator issue did.
- **The session is single-host between imports.** That was already true of the
  session store; the removal takes away the GitHub fallback, not a second live
  copy.
- **The build has an external gate.** It can't start until the coordinators still
  running on the record have moved or finished, and that depends on their owners.

## Decisions and Trade-offs

**Rename the surviving session scripts out of the `record-` namespace rather
than keep the names.** Alternatives: keep `record-hold.sh` and the other writers
under their names and strip their GitHub halves; or keep the names and redefine
"record library" to mean only the GitHub helpers. The rename won because the
removal's acceptance is grep-shaped and has to mean one thing: a reader can't
tell a surviving `record-*.sh` from a forgotten one, and "no file named
`record-*`" can't drift. The session key names keep their `record/` prefix
(R14), because renaming keys would touch every session already on the store.

**Post outward entries on the item each is about, rather than keep them
session-only or move them to one new issue.** Keeping them session-only fails
the roadmap reader, who follows a committed link by clicking, and the cost
reviewer, who may not be on the coordinator's host. One new issue per scope
would be a coordinator issue under another name. The item the entry is about (a
unit's pull request, the roadmap pull request that records a status change) is
GitHub's own, already exists, and is where a person reviewing that change
already looks.

**Keep the marker line.** It identifies an outward entry to every existing
reader and to `--confirm`'s check. Changing it would break the cost join and
every progress line written before the removal.

**Leave existing GitHub records alone.** Closing every coordinator issue and
rotation pull request as part of the removal was rejected: a coordinator issue
holds outward entries that roadmaps already link to (R7), and closing a live
coordinator's container is the mid-run change R20 forbids.

**Bring discipline scope onto the session in this work.** Dropping discipline
scope's GitHub store without a replacement leaves discipline coordinators with
no store; leaving discipline scope on GitHub leaves the record in place. The
requirements of the work that introduced the session store already deferred
discipline scope to this removal.

**A predecessor is found by discipline name on the host, and imported from
another host by its owner.** A shared index of rotations would be new state and
would need its own store. The session listing by name already finds a roadmap
coordinator's earlier session for a resume, and the import already moves one
between hosts.

**A precondition, not a date.** The build waits on a condition anyone can check
on GitHub (R20), not on a release or a calendar date, because the coordinators
it protects finish on their own schedules. The owner closing the issue or pull
request is the one way to declare a coordinator finished or abandoned, so an
abandoned record can't hold the build forever.

**No permanent start-up guard for an unmoved record.** A guard that searches
GitHub for a coordinator issue before starting would keep the title search R3
removes. The precondition protects the coordinators that exist when the removal
lands, and nothing after it can create a GitHub record. Whether a guard should
ship for the one release that carries the removal, as a second protection, is
the owner's call; the design and PLAN carry it as a separate item that can be
dropped.
