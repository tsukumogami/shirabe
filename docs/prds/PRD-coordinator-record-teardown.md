---
schema: prd/v1
status: Draft
upstream: docs/briefs/BRIEF-coordinator-record-teardown.md
problem: |
  The coordinate skill keeps a coordinator's state in two stores: the GitHub
  record (an issue body and comment stream at roadmap scope, a committed handoff
  file on a rotation pull request at discipline scope) and the coordinator's
  koto session. Every state change is made and tested against both, GitHub is
  still the default, a discipline coordinator can't use the session at all, and
  a dozen shipped designs name a store that is meant to go. The session store has
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
---

# PRD: Tear down the GitHub coordinator record

## Status

Draft

## Problem Statement

The coordinate skill drives a coordinator: a long-running session that hands
units of work to other sessions, verifies what they push and lands it. Its state
(holdings, holds, deferrals, side effects, reversals, the run's arguments, the
standing answers people gave it, the next step per holding, its decisions and an
account of what happened) has to survive a crash, a restart and a move between
hosts.

That state has two homes today. The original is the **GitHub record**: at
roadmap scope an issue titled `Coordinator record: ROADMAP-<name>`, whose body
is a set of markdown tables rewritten whole on every write, with an append-only
stream of marked comments beside it whose authors are checked against the
repository's collaborator permissions; at discipline scope a draft pull request
whose diff is a handoff file committed to `docs/disciplines/<name>.md`. The
second is the **coordinator's koto session**, one key per section under
`record/`, entries under `record/entries/`, worker legs under `legs/`. A
coordinator has run on the session end to end, been imported to a fresh instance
twice, and had its state read through koto's session view by its owner, who
signed it off.

The GitHub record was kept as the default and the fallback. It now costs the
people who work on and with the skill:

- **Maintainers make every state change twice.** One read seam serves the state
  from either store. Sixteen `record-*.sh` scripts and a markdown codec sit
  under about thirty-six scripts that read or write the state. The session path
  still renders the state to an issue body and parses it back to validate a
  write, and is still held to a 60,000-byte budget sized for GitHub's body
  limit.
- **Owners get the old store by default.** A new coordinator opens a GitHub
  issue unless someone passes `--store session`, and a coordinator already on
  its session keeps a stub issue so its start-up search can find the row that
  points away from it.
- **Discipline coordinators can't move.** Discipline scope refuses the session
  store in six places, so a rotation still commits its state to a branch and
  carries it on a pull request.
- **Outside readers depend on the issue.** Cost, milestone-verdict,
  milestone-failure and goal-fit entries are posted as comments on the record
  issue, because a cost reviewer and a roadmap reader look for them there, and a
  roadmap's progress notes link to those comments.
- **The designs describe the wrong store.** About a dozen shipped designs and
  half a dozen requirements documents say the record on GitHub is where their
  facts live.

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
  GitHub, on items that are GitHub's own, with the same text.
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
  next rotation to read what the last one left (its holds, its standing answers,
  its next steps and its unsettled decisions) from the session, so that no
  branch, handoff file or pull request carries coordinator state.
- **As the owner of a coordinator that started on the GitHub record**, when the
  removal is ready to build, I want my coordinator left alone until its next
  start, then moved to its session with the move the skill already ships (or its
  rotation left to end), so that nothing changes under a running run.
- **As a cost reviewer**, when I total what a week's units spent, I want to find
  each unit's cost entry on GitHub with the same marker and text as today, so
  that my join still works without a coordinator issue.
- **As a roadmap reader**, when I follow a link in a roadmap's progress notes to
  the milestone verdict behind a status change, I want it to resolve, both for
  links written before the removal and after, so that the reason for a status
  stays one click away.
- **As a reader of the skill's designs**, when I look up where holds, pauses,
  decisions or the dispatch path keep their facts, I want each design to say the
  session, dated, without its logic being rewritten, so that the documents match
  the code.

## Requirements

### Functional

**R1. One store.** A coordinator at roadmap or discipline scope keeps every part
of its state that the GitHub record held (the sections, the stored set, the
decisions, the holds and the account) in its own koto session and nowhere else.
Nothing in the coordinate skill reads coordinator state from, or writes it to, a
GitHub issue body, an issue comment, a pull request body or a committed file.

**R2. No choice of store.** The per-run choice of store is removed: the
`--store` option, the `STORE` template variable, the `store` Run row and the
sealed source it decides, and the refusals that exist only to arbitrate between
stores (`store-malformed`, `store-unverified`, `store-conflict`, `store-moved`,
`store-discipline`). A coordinator's start opens, resumes or imports its
session. The check that koto has the features the session store needs stays, as
a start-up requirement rather than a choice (today's `store-unsupported`).

**R3. The GitHub container goes.** The skill no longer creates, searches for,
edits, closes or reads a coordinator issue, and no longer creates, edits, readies
or reads a rotation pull request or its branch. The open-issue search by title
and the moved-shape stub issue go with it.

**R4. The comment stream goes.** The skill no longer posts or lists marked
record comments on a coordinator issue, and no longer reads collaborator
permissions to decide whether a comment is an entry. The account is the
session's entries alone.

**R5. Outward entries reach their readers on GitHub's own items.** The four
outward kinds (cost, milestone-verdict, milestone-failure, goal-fit) are still
written to the session first and still posted to GitHub with today's marker line
and text, so an exact-prefix join and a byte comparison still match. Each kind
is posted on a GitHub item that is GitHub's own and that its reader already
reaches (a unit's pull request or issue, or the roadmap pull request that records
the status change), never on a coordinator issue. The design names the item per
kind. `roadmap-status.sh --verdict`, `--reopen` and `--confirm` read an entry
back from wherever R5 posts it, and the cost-reading guide in
`skills/coordinate/references/unit-cost.md` says where to read cost entries.

**R6. Links written before the removal keep working.** Nothing the removal does
deletes, closes or edits an existing coordinator issue, comment, rotation pull
request or branch on GitHub. A roadmap progress line that already cites a comment
on a coordinator issue still resolves, and `roadmap-status.sh --confirm` still
accepts it.

**R7. Every write-core guarantee survives on the session.** One writer per key;
a compare against the state the writer read, refusing a write when it changed;
the per-column and per-row grammars the codec enforces today (allowed fields,
control characters, the columns that may be empty, no column that records what
GitHub recomputes, worker and address shapes, hold, stored-set and decision rules
and transitions); and the checks that refuse a private repository name, a
home-directory path or a token-shaped string in any value that can leave the
host. These validate the state as JSON. No write renders a markdown body or
parses one.

**R8. No size limit that only GitHub needed.** The 60,000-byte record budget and
the 65,536-byte body limit stop applying. Any size bound the session keeps is
one the session store needs, stated per key, and the stops and archives that
exist only because a body could fill up are removed or re-justified in the
design.

**R9. Discipline scope runs on the session.** A discipline coordinator opens,
resumes and imports its session as a roadmap coordinator does. A rotation's
window (start and end dates) is kept in the session. A new rotation finds the
previous rotation of the same discipline and reads, from that rotation's
session, everything the committed handoff file carries today: the holds, the
Run, Standing and Work sections, the unsettled decisions and the next decision
number, and the reasoning the reconcile pass classifies. A previous rotation that
can't be read is reported as such, as an unreadable or missing handoff file is
today.

**R10. The committed handoff file and the rotation pull request go.** No
rotation commits `docs/disciplines/<name>.md`, opens or readies a rotation pull
request, or deletes a rotation branch. The template states that exist only for
those steps are removed.

**R11. The session view is the human surface.** The command that renders the
session's state as a record body for a reviewer (`record-source.sh --show`) is
removed, and the skill points a person at koto's session view instead. The relay
duty is unchanged in substance: a person's word reaches the coordinator however
it arrives, and the coordinator writes it to the session, but nothing tells
anyone to comment on a coordinator issue.

**R12. The session layout doesn't change.** The key names and the JSON in each
key stay as the session store writes them today, so a coordinator already on its
session resumes, carries across and imports across the removal with no
migration.

**R13. What's GitHub's own is untouched.** Pull request state, head, checks,
reviews, mergeability and the merge; the review panel table a worker writes in
its pull request body; issues used as units of work; the roadmap read at the
default branch and the roadmap pull requests `roadmap-status.sh` opens; the
merge-order block a person reads; the CI merge-last gate's reads; and the
worker's handoff comment on its merged pull request all keep working as they do
today, read live from GitHub.

**R14. The removal is complete.** After the last change, no script under
`skills/coordinate/` sources a record library or parses a record body. Precisely:

- no file named `record-*.sh` and no `record-codec.jq` remains under
  `skills/coordinate/scripts/`;
- no script under `skills/coordinate/` names `record-common.sh`,
  `record-source.sh`, `record-parse.sh`, `record-render.sh` or `record-codec`;
- no script under `skills/coordinate/` names the title `Coordinator record:`,
  the marker `coordinator-record-entry`, a collaborator-permission endpoint, or
  `docs/disciplines/`.

The session-side behaviour those scripts carry today survives in scripts outside
that namespace, with one writer per key.

**R15. A structure test keeps it removed.** A test refuses any script under
`skills/coordinate/` that matches R14's patterns, and proves with fixtures that
each pattern is refused, so a body parse can't grow back.

**R16. The surrounding registries move with the scripts.** The CI workflows
whose path filters or steps name the removed scripts still trigger on, and run,
the scripts that replace them. The bash-floor list, the check-skill cost rows,
the rule-coverage rows, the `requires.tsv` rows, the template, its diagram, the
skill's text, its references and its eval fixtures name only what exists.

**R17. The shipped documents say what changed.** The record container design
(`DESIGN-coordinate-record-container.md`) is superseded by the removal design,
which states where the stored set it defined (Run, Standing, Work) and its
landed-feature write-back now live. Every other shipped design and requirements
document that names the GitHub record as the store gets a dated amendment that
keeps its logic and records only that the storage moved to the session. The
design enumerates them.

**R18. Nothing touches a live run.** No change that removes a reader or a writer
of the GitHub record merges while any coordinator still runs on that record. A
coordinator runs on the GitHub record while its roadmap's coordinator issue is
open and its body still carries state tables (it hasn't moved), or while a
discipline's rotation pull request is open. A coordinator moves onto its session
at its next start, with the move that ships today, and never mid-run; a
discipline rotation on the record ends its rotation and the next rotation starts
on the session. Changes that remove nothing a running coordinator reads (the
JSON validation, discipline scope on the session, the outward-entry targets, the
new structure test) may land first. The scripts come out last, when nothing reads
them.

### Non-functional

**R19. The skill's floor holds.** bash 3.2 and jq, with no new koto feature and
no raised koto floor.

**R20. The suites run on the session alone.** No suite stands up a GitHub record
or a stand-in for one. Every suite that tested both stores keeps its session
cases, and every behaviour a GitHub-only suite tested that survives (a stored-set
gap, a hold re-read before a merge, a decision transition, a rotation's carry) is
tested on the session.

## Acceptance Criteria

- [ ] With the last change applied, `ls skills/coordinate/scripts/record-*.sh
      skills/coordinate/scripts/record-codec.jq` finds nothing.
- [ ] `grep -rlE 'record-(common|source|parse|render)\.sh|record-codec'
      skills/coordinate/` finds no script (test fixtures that exist to be refused
      by the structure test excepted, and named in that test).
- [ ] `grep -rlE 'Coordinator record:|coordinator-record-entry|/collaborators/|docs/disciplines/'
      skills/coordinate/scripts skills/coordinate/koto-templates` finds nothing.
- [ ] The structure test refuses a fixture script for each R14 pattern and passes
      on the skill's own scripts.
- [ ] `coordinate-open.sh` accepts no `--store` and the template declares no
      `STORE` variable; starting a new roadmap coordinator in a suite opens a
      session, makes no `gh issue create` call and no `gh pr create` call (the
      suite's `gh` stand-in records none).
- [ ] Starting a discipline coordinator in a suite opens a session and makes no
      `gh pr create`, `git push` or contents write; a second rotation of the same
      discipline reads the first rotation's holds, Run, Standing and Work, its
      unsettled decisions and its next decision number from the first rotation's
      session.
- [ ] A suite writes each of the four outward kinds and finds each posted, with
      today's marker line and text, on the item the design names for it, and on
      no coordinator issue.
- [ ] `roadmap-status.sh --confirm` accepts a progress line citing a verdict
      posted where R5 puts it, and still accepts one citing a comment on a
      coordinator issue written before the removal.
- [ ] A suite writes a hold and a pause to the session, and `land-check.sh` and
      `land-merge.sh` both refuse the merge, as they do today.
- [ ] A suite's write that changes a section after the writer read it is refused
      as `record-changed` (exit 12); a write naming a private repository, a
      home-directory path or a token-shaped string is refused; a write with a
      recomputable column is refused.
- [ ] No suite's `gh` stand-in serves an issue body, a record comment list or a
      collaborator-permission read.
- [ ] `handover_engine_test.sh` passes from an imported session, and
      `session-store_engine_test.sh` and `legs-move_engine_test.sh` pass.
- [ ] A coordinator session written by the release before the removal resumes
      and imports on the release after it, with no key renamed or rewritten.
- [ ] Each CI workflow that ran a coordinate suite before the removal still runs
      the suite that replaced it, triggered by a change to the replacing scripts.
- [ ] `DESIGN-coordinate-record-container.md` has status Superseded, sits in
      `docs/designs/archive/`, and names the removal design in `superseded_by`.
- [ ] Every document the design lists for amendment ends with a
      `## Amendment — <date>` section whose first paragraph names the removal
      design and states that the original text is left unedited; each keeps its
      status.
- [ ] `docs/disciplines/performance.md` and the eval fixture that commits a
      discipline handoff file are removed or rewritten to the session form.
- [ ] The PLAN states R18's precondition, and no PLAN issue that removes a reader
      or writer of the GitHub record lists a dependency that lets it merge before
      the issues R18 allows first.

## Out of Scope

- **GitHub's own surfaces** (R13): pull request state, checks, reviews,
  mergeability, issues used as units of work, the merge-order block, the CI
  merge-last gate's reads, the roadmap pull requests, the worker's handoff
  comment. They were never the record.
- **The coordinated `/execute` run's coordination pull request body.** Separate
  work already moved that run's state onto its own session; nothing here changes
  it.
- **Moving any live coordinator.** Coordinators move themselves at their next
  start with the move that ships. Closing or editing existing coordinator issues
  or rotation pull requests on GitHub is their owners' call, not this change's
  (R6).
- **New koto features**, such as a batch write of several keys or an append-only
  key stream. The removal works with the session store as it ships.
- **New state.** This removes a store; it adds no section, column or kind.
- **The teardown archive and worker transcripts.** They are host-local files, not
  coordinator state.
- **Building the removal.** This document scopes it; the build waits for R18's
  precondition.

## Known Limitations

- **A moved coordinator's stub issue stays open.** The skill stops reading it,
  but closing it is its owner's call (R6). A person who finds an open coordinator
  issue after the removal reads a body that says the state moved.
- **Outward entries are only as durable as the item they're posted on.** A
  comment on a unit's pull request or a roadmap pull request lives as long as
  that item, as a comment on a coordinator issue did.
- **The session is single-host between imports.** That was true of the session
  store already; the removal takes away the GitHub fallback, not a second live
  copy.
- **The build has an external gate.** It can't start until the coordinators still
  running on the record have moved or finished, and that depends on their owners,
  not on this work.

## Decisions and Trade-offs

**Rename the surviving session scripts out of the `record-` namespace rather
than keep the names.** Alternatives: keep `record-hold.sh` and the other writers
under their names and strip their GitHub halves; or keep the names and redefine
"record library" to mean only the GitHub helpers. The rename won because the
removal's acceptance is grep-shaped and has to mean one thing: a reader can't
tell a surviving `record-*.sh` from a forgotten one, and "no file named
`record-*`" can't drift. The session key names keep their `record/` prefix
(R12), because renaming keys would touch every session already on the store.

**Post outward entries on GitHub's own items rather than keep them session-only.**
Alternative: stop posting, and have readers read the session or the teardown
archive. Rejected because a roadmap's progress notes are committed text that a
person follows by clicking, and a cost reviewer may not be on the coordinator's
host; both need a public URL. Posting on the item the entry is about keeps a URL
without keeping a coordinator issue.

**Leave existing GitHub records alone.** Alternative: close every coordinator
issue and rotation pull request as part of the removal. Rejected because a
coordinator issue holds outward entries roadmaps already link to (R6), and
because closing a live coordinator's container is exactly the mid-run change R18
forbids.

**Bring discipline scope onto the session in this work.** Alternative: drop
discipline scope's GitHub store without a replacement, or leave discipline scope
on GitHub. The first leaves discipline coordinators with no store; the second
leaves the record in place, which is the thing being removed. The requirements
on the session already settled discipline scope as waiting for this removal.

**Precondition, not a date.** The build waits on a condition anyone can check on
GitHub (R18), not on a release or a calendar date, because the coordinators it
protects finish on their own schedules.
