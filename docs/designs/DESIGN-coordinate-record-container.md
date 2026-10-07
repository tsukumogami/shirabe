---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-coordinate-skill.md
problem: |
  The coordinate skill's record is a set of tables in an issue or pull
  request body, rewritten whole on each write. That fits state, but a
  coordinator also keeps an account of what happened, and the coordinators
  that ran the skill kept it elsewhere: dated prose in a pull request body
  that hit GitHub's size limit and was split into archive files three
  times, a throwaway script per entry, a tools directory on the host that a
  workspace apply deleted twice, and a handoff file a replacement session
  needed because the record didn't hold the run's arguments, its cap, the
  next step per holding, work outside the holdings, the standing answers or
  where reports should go. And the skill reads a feature's state from the
  roadmap without ever writing it back, so a landed feature is offered
  again until someone opens a roadmap pull request by hand.
decision: |
  The container stays the issue at roadmap scope and the rotation's pull
  request at discipline scope. Its body keeps the state; its comments
  become the record's entries, each appended by `record-append.sh` with a
  host-clock stamp and a marker the reader keys on, so no body holds the
  account and no archive rotation is needed. Three optional body sections
  hold the rest of the stored set: Run (the arguments, the cap, the
  coordinator's address and who has been told it), Standing (the events
  only a person owns that still bind the run, each with its owner, who
  relayed it and when) and Work (a next step for every holding and a row
  for work outside the holdings, local agents included). One writer,
  `record-state.sh`, changes them and appends the matching entry. A gate
  on `reconcile` holds a start while a holding has no next step or a live
  worker hasn't been told the current address. Holds stay the section the
  merge policy added. A landed feature's Status and Outcome reach the
  roadmap through `roadmap-status.sh`, run from a new `landed` event: it
  opens the roadmap pull request and records it as a side effect in
  flight, which pick reads so the feature isn't offered again while the
  pull request waits for whoever merges roadmap changes.
rationale: |
  What outgrew a body was an account, not a table: the skill's own records
  are 3 to 18 KB of tables against a 60,000-byte budget. A comment stream
  takes an account with no limit on the whole, records each entry's author
  and time, and keeps the strategy's reason for an issue, that a roadmap
  record commits nothing. The stored set goes in the body because a
  replacement acts on it and a check reads it, and both read the body
  through the codec. The write-back is a pull request and not a direct
  commit because the roadmap is a reviewed document whose merges a person
  owns.
---

# DESIGN: coordinate-record-container

## Status

Proposed

## Context and Problem Statement

The coordinate skill keeps one record per scope on GitHub: an issue titled
`Coordinator record: ROADMAP-<name>` at roadmap scope, and a draft pull request
per rotation at discipline scope. Its body is the codec's render of a fixed set
of tables (Holdings, Deferrals, Side effects in flight, Reversals, and since the
merge policy an optional Holds and the Decisions section), rewritten whole by
the write core behind a compare-and-swap on its `Written:` line and refused over
60,000 bytes (`skills/coordinate/references/record-template.md`). The strategy
behind the skill chose an issue on 2026-09-26 because a roadmap record commits
nothing: no branch to maintain, no merges from the default branch to absorb.

What the coordinators that ran the skill kept outside the record is the problem
this design solves. It is the coordinator roadmap's Feature 7, amended on
2026-10-01, and the strategy's dated decision of 2026-10-07 settles its first
question, the container. Every claim below traces to the process owner's
coordinator-session record (cited as the record, with the entry's date and
subject), the surveys of three coordinators taken on 2026-09-30, or an issue or
pull request.

**The account outgrew its container.** The process owner's record is a pull
request body written as dated prose. An edit to it was refused at 262,279 bytes
on 2026-09-29, and it was split into archive files on its branch three times,
on 2026-09-29 and 2026-09-30, each committed by a session dispatched for the
purpose (the record, 2026-09-29 09:53 and 21:23 and 2026-09-30 11:32, the
archive splits). Read on 2026-10-07 it held more than 160,000 bytes again. The
two records the skill opened are tables of 3,059 and 17,817 bytes, and one of
their coordinators already posted its running notes as comments on its record,
seven of them on 2026-09-29. The tables fit; the account doesn't.

**Every entry was a script.** Until 2026-09-29 the process owner wrote each
entry with a throwaway script, about ten that day, until the human asked why;
then a local append script took over: it stamps the host clock, inserts before
an anchor, keeps a snapshot copy and pushes the body, with no size check and no
compare-and-swap (the record, 2026-09-29 22:08, the record append). Every
progress table, by contrast, is one call to the skill's `progress-view.sh`, by
the human's ruling of the same day.

**State kept on the host was lost.** A workspace apply deleted the process
owner's tools directory on 2026-09-28 and again on 2026-09-29: the runbook, the
verification scripts, the friction logs and a lane's verbatim standing answers
(the record, 2026-09-28 20:09 and 2026-09-29 17:34, the tools directory). The
cause was fixed in the workspace manager (tsukumogami/niwa#345, fixed by
tsukumogami/niwa#350), but the directory still holds things only a coordinator
should know.

**A replacement couldn't continue from the record alone.** On 2026-09-29 one of
the coordinators running the skill was replaced by a second session to cut its
context cost. A handoff file beside the record carried the run's arguments, the
cap, the worker ids, a next step per holding and the standing decisions, and the
replacement still lost what neither held: a pull request built by a local agent
existed only as prose (tsukumogami/shirabe#571), the human's standing answers
were in a local file, and workers kept reporting to the old session until the
replacement sent each a line (the record, 2026-09-29 22:01 and 2026-09-30 12:56,
the handover; the survey of that coordinator, 2026-09-30). The roadmap makes
that handover Feature 7's acceptance test.

**Events only a person owns have no place.** Pauses, resumes, cap changes,
release go-aheads, relayed approvals and standing answers are dated prose in
the process owner's record, Reversals rows with a From column in the skill's
two records, or a timer that dies with its session; one record keeps its holds
inside Deferrals cells (the surveys of three coordinators, 2026-09-30). All
three surveys found coordinators recovering these from prose.

**The roadmap is read, never written.** `pick-facts.sh` reads each feature's
Status from the roadmap on the default branch, and nothing writes it back, so a
feature whose pull request merged is offered again until a hand-made roadmap
pull request merges (tsukumogami/shirabe#497). One lane had a local agent open
one after every merge, six of them by 2026-09-30, one taking three rounds (the
survey of that lane's coordinator, 2026-09-30).

## Decision Drivers

- **Every record entry is one tool call.** The roadmap's functional outcome for
  Feature 7, and the cost the human named on 2026-10-01: features that make the
  coordination cheaper to run come first (the record, 2026-10-01 13:50, the
  directive on cheaper running).
- **A replacement continues from the record alone.** No handoff file, no tools
  directory, no session's memory.
- **The workflow reads, the coordinator writes.** The template's one rule: no
  check reads what the coordinator writes except the record on GitHub through
  its codec.
- **One writer per section.** Holds and Decisions already work this way; a
  section a gate reads can't be changed by any other script.
- **State outside the session and outside anything the workspace manager
  converges; what outlives the host lives on GitHub.** The roadmap's rule,
  adopted here.
- **The roadmap stays a reviewed document.** A feature's Status reaches it as a
  pull request someone merges.
- **bash 3.2 and jq**, the skill's floor.

## Considered Options

### Decision 1: The container, and what goes where in it

The strategy's dated decision of 2026-10-07 settled this, and this design
carries it out. The container is unchanged: the issue at roadmap scope, the
rotation's pull request at discipline scope. The body holds what is true now,
the tables every check reads, and stays canonical and under the budget. The
container's comments hold the record's entries: the coordinator's dated
account, and an entry for each event a person owns.

The tables that only grow stay in the body. Reversals, Holds and the Decisions
section are read by checks (the record step waits for a Reversals row after a
merge made while held, the land check reads Holds, the decision flow reads its
entries), so they are state in the sense that matters here, and settled
decisions already compact.

An entry is a comment the reader can tell from any other: its first line is a
marker, `<!-- coordinator-record-entry v1 kind=<kind> -->`, and the reader counts
only comments carrying the marker whose author has write access to the host,
the same authorisation the record find applies to the record itself, since
anyone can comment on a public repository.

On the history the roadmap asked for: GitHub keeps each revision of an issue or
pull request body, readable through GraphQL `userContentEdits` (98 revisions for
one of the skill's records and 100 for the other, read on 2026-10-07), so the
roadmap's statement that a body "keeps no history" doesn't hold. But a revision
is a whole body with no account of why it changed, so the comment stream is the
history a successor reads, and the body's revisions are the audit trail of the
tables.

#### Alternatives considered

- **A committed file on a coordination branch.** Proposed in the record on
  2026-09-29 at 22:09 (the finding for the roadmap amendment). Rejected in the
  strategy: a branch per roadmap record that never merges, a commit per entry,
  a branch view in place of the issue the find adopts, and an entry committed
  to a public host's history can't be withdrawn.
- **Entries in the body with archive rotation.** What the process owner did by
  hand. Rejected: the archive is a second container, each rotation is a
  multi-step write that can stop half-done, and the body's budget would be
  shared between state and account.
- **The record as a view over the run's koto log.** Also proposed on 2026-09-29.
  Rejected: the koto log is host-local and deleted at a terminal state, which is
  why the strategy calls it the journal between checkpoints, not the record.

### Decision 2: The append

`skills/coordinate/scripts/record-append.sh` is the one way an entry is written:

```
record-append.sh --session S [--kind entry] --text-file F
record-append.sh --scope roadmap|discipline --name N --repo O/R --ref N [--kind entry] --text-file F
record-append.sh (--session S | --scope ... --ref N) --list
```

It re-reads the target first and refuses unless it is open and carries the
scope's declaration line. It stamps the entry from the host clock in UTC to the
second, so the stamp is the coordinator's time even when GitHub's time on the
comment differs, and posts:

```markdown
<!-- coordinator-record-entry v1 kind=entry -->
**2026-10-07T23:41:05Z** (host clock) entry

<the text>
```

`--kind` defaults to `entry`; the event kinds of Decision 3 are written only by
`record-state.sh`, which calls the same append. The text gets the checks the
Decisions section's text columns already get: on a public host it may not name
a private repository, a home-directory path or a token-shaped string, `@` is
encoded so an entry never mentions anyone, and a control character other than a
line break or tab is refused. An entry over 60,000 bytes is refused before
GitHub sees it, the record's own budget.

`--list` prints the entries as a JSON array in order, each with its comment id,
GitHub's creation time, its stamp, author, kind, text and whether it has been
edited since. That is the read a successor and a test use.

The addressed form exists because not every writer is a run: the process owner
migrating its record, or a coordinator writing one entry after its run ended.
It needs no session because an entry changes no state any check reads.

There is no archive rotation: no comment grows, and the number of comments has
no limit that matters at a coordinator's rate.

### Decision 3: The stored set

The roadmap's acceptance test names the properties a replacement must find in
the record: the run's arguments and the cap; the worker ids; a next step per
holding; a row for every piece of work in flight, local-agent work included;
the human's standing answers, with who and when; the holds, with who and when;
and the current coordinator's address and who has been told it. Holds are the
merge policy's section, unchanged. Worker ids are the Holdings table's Worker
cells, which are dispatch topics by design, since reconcile finds sessions by
topic. The rest need three optional sections, after Holds and before Decisions,
each rendered only once it has a row, so existing records keep their bytes:

```markdown
## Run

| Key | Value | Set by | Set |
|---|---|---|---|
| arguments | --roadmap docs/roadmaps/ROADMAP-x.md --cap 2 | the human | 2026-09-28T11:27Z |
| cap | 1 | the human, via the process owner | 2026-09-29T22:53Z |
| coordinator | lane-coordinator-v2 | lane-coordinator-v2 | 2026-09-29T21:45Z |
| told | worker-f2 | lane-coordinator-v2 | 2026-09-29T21:50Z |

## Standing

| Standing | Kind | What | Owner | Relayed by | Set |
|---|---|---|---|---|---|
| s1 | answer | panels at the head are the cost to cut, not instruction length | the human | the process owner | 2026-09-29T17:40Z |
| s2 | pause | all lanes, until a resume | the human | | 2026-09-30T11:56Z |

## Work

| Item | Kind | Who | Next step | Updated |
|---|---|---|---|---|
| Feature 2 | holding | worker-f2 | waiting on the panel at the head | 2026-09-29T21:48Z |
| fix for the ablation check | local-agent | local agent | ready report, then the merge | 2026-09-29T21:49Z |
```

**Run** is the run's facts a replacement needs before its first pick: the
arguments it was started with, the cap in force, the parked bound if a person
changed it, the coordinator's address (the name messages to it reach, held to
the Worker cell's grammar, so no session id, path or job id is written) and one
`told` row per party that has been sent that address. Writing a new
`coordinator` row clears the `told` rows. `pick-facts.sh` reads the cap and
parked bound from Run over the session's variables when Run has them, so a cap
a person changed survives a restart that didn't pass it.

**Standing** holds the events only a person owns while they still bind:
`pause`, `go-ahead` (a release or another step a person allowed once),
`approval` (a relayed approval, which the strategy says is confirmed where it is
used), and `answer` (a standing answer). A resume ends a pause, a go-ahead or
approval ends when used, an answer when a person withdraws it; ending a row
removes it from the body, and the entry that records the end keeps it in the
account. Owner is who decided; Relayed by is the session or person that carried
it, blank when the owner said it to this coordinator directly. A cap change is
a Run row with the same who and when.

**Work** has one row per holding (Item is the holding's Unit, Who its Worker)
and one per piece of work no holding covers, with a next step a successor can
act on. Local agents stay outside the cap, as the skill already says; the row is
how they stop being invisible.

`skills/coordinate/scripts/record-state.sh` is the one writer of the three
sections, the way `record-hold.sh` is of Holds: `--run KEY VALUE --by WHO`,
`--told WHO --by WHO`, `--standing KIND --what TEXT --owner WHO [--relayed-by
WHO]`, `--end ID --by WHO`, `--work ITEM --kind K --who W --next TEXT`,
`--done ITEM`, and `--list`. Each change goes through the write core
(`STATE_WRITER=1`, so any other writer must carry the sections as the live
record has them) and then appends the matching entry, kind `run`, `told`, the
standing kind, `end` or `work`, with the same who and when. The body is written
first: an entry that fails to post after a written body exits 11 with the
change named, and `record-append.sh` posts it by hand, so the account never
claims a change the state doesn't hold.

The skill tells the coordinator when to write each: the arguments and its
address at its first start, a cap or Standing row when a person's message
arrives, a Work row with every dispatch, report or local-agent launch, and a
`told` row after each line sent. A worker's brief already names the address of
the coordinator that dispatched it, so the Work row written for a new holding
writes that worker's `told` row too.

**The handover gate.** `record-handover.sh` reads the record and reports the
stored set as JSON with its gaps: a missing `arguments`, `cap` or `coordinator`
row, a holding with no Work row, and a holding whose Worker has no `told` row.
The `reconcile` state gets one more non-overridable command gate over it, so a
start, a restart or a replacement can't leave reconcile while the stored set has
a gap. A replacement writes its own address, which clears the `told` rows, and
the gate then lists every live worker until the replacement has told each. That
closes the third loss of the handover with a gate rather than a habit. A record
written before these sections existed has every gap at its first start under
this release, and the coordinator fills them once.

What a pause does to the loop is Feature 9's paused state; this design stores
it with its who and when, and changes no routing for it.

### Decision 4: The write-back

A landed feature's Status and Outcome reach the roadmap as a pull request from a
new close-out step, entered by a new `wait` event, `landed`, whose `unit` names
the feature's heading tag. It is an event the coordinator sends, not a
consequence of a merge, because a feature can land as several pull requests (a
design, then its implementations), and only the coordinator knows the last one
has merged; a spike's or a design's "done" is an acceptance call
(tsukumogami/shirabe#497's last criterion).

The new state `roadmap_status` runs nothing on entry. Its directive has the
coordinator run `skills/coordinate/scripts/roadmap-status.sh --session S --unit
<tag> --outcome <text>`, which:

1. reads the roadmap at the default branch's head through the contents API,
   refuses a unit that isn't a feature there or already reads Done or Dropped,
   and refuses when a roadmap pull request for the unit is already recorded;
2. sets the feature's `**Status:**` to `Done`, writes `**Outcome:**` after it
   (replacing one that's there), removes its `**Needs:**` line, and runs
   `shirabe roadmap populate` over the result so the generated sections agree;
   nothing else in the roadmap changes, so the rule that an Active roadmap's
   feature text is locked holds;
3. pushes it on a new branch through the git data API (no checkout needed, as
   with the record's other writes) and opens the pull request, titled
   `docs(roadmap): record <tag>, <title>, as done`, with a Part 1 naming the
   outcome;
4. writes a Side effects in flight row, Action `roadmap-status`, Target
   `<tag> [#n](URL)`, How to confirm `the roadmap on <default> reads <tag>
   Done`, through the write core.

`roadmap_status` accepts `status: opened | failed`; `opened` goes to `record`,
whose confirm reads the new row, and `failed` to `failure`. The skill never
merges the pull request: it goes to whoever merges roadmap changes, in the
merge-order table, as any reserved merge does, and the Active roadmap's rules
are reviewed there.

`pick-facts.sh` reads the `roadmap-status` rows: a unit named by one is
`landed`, never offered for dispatch, and still not Done for its dependents
until the roadmap says so. When the roadmap on the default branch reads Done,
`roadmap-status.sh --confirm <tag>` removes the row; pick lists rows whose unit
now reads Done, so the coordinator knows to run it. A pull request closed
unmerged leaves the unit `landed` until the coordinator runs
`roadmap-status.sh --drop <tag> --reason <text>`, which removes the row and
appends the reason as an entry.

#### Alternatives considered

- **The merged tick writes it.** `merge_confirm` and `merged_facts` see one
  pull request; they can't tell the feature's last pull request from its first.
  Rejected.
- **The land step writes it.** The same problem, earlier, and land is already
  the loop's most guarded step. Rejected.
- **A "landed" fact in the record only, no roadmap change.** Stops the re-offer
  but leaves the roadmap stale for every person reading it, which the issue
  calls the source of truth. Rejected as the whole answer; it is the pending
  half of the chosen one.
- **A direct commit to the roadmap.** Skips the review the roadmap's own rules
  require. Rejected.

### Decision 5: Where state lives

The rule, adopted from the roadmap: a coordinator's state lives outside its
session and outside any directory the workspace manager converges, and what
must outlive the host lives on GitHub. In this skill that is two places: the
koto session, the crash-safe journal on the host between checkpoints, and the
record on GitHub, everything else. The coordinator keeps no tools directory.

What a coordinator keeps on the host today, and where it goes:

| Kept on the host | Where it lives under this design |
|---|---|
| A local append script and a snapshot copy of the body | `record-append.sh`; GitHub keeps the comment and the body's revisions |
| Archive files split from the body | No longer made; entries are comments |
| Progress facts and a script that renders them | `progress-view.sh` over pick's facts, already the skill's |
| Standing answers in a local file | Standing rows and their entries |
| A list of stopped workers' session ids, for a resume by hand | The Work rows' next step; resuming a session is the workspace manager's, and a session id is never written to the record |
| Scripts that read a board, wait on checks, build a squash message and check a teardown | `board-verdict.sh`, `land-check.sh`, `squash-message.sh` and `teardown-inventory.sh`, already the skill's |
| Scripts that export a pull request for a merge panel, and a review-trial wrapper | Retired with the merger's panel by the merge policy, or the trial's own tooling; not a coordinator's state |
| A runbook, friction logs and briefs | The process owner's method and observations: method belongs in the skill (the strategy's first falsifier counts it), observations in issues or record entries; not state |

The skill's record reference says so, with the rule.

## Decision Outcome

The record keeps its container and becomes two things in it: the body, the
state every check reads, and the comments, the account. One script appends an
entry; one script writes the stored set and the entry that goes with each
change; a gate at reconcile holds a start until the stored set is complete and
every live worker knows where to report; and a landed feature reaches the
roadmap as a pull request the skill opens and whoever merges roadmap changes
merges, with the record saying it is pending so pick passes over it.

What the roadmap's Feature 7 block asks for that this declines:

- **A committed file as the container.** The strategy's 2026-10-07 decision.
- **Archive rotation.** Not needed: no comment grows.
- **A state file with two writers**, the shape a workspace coordinator keeps
  with the release coordinator it runs. The roadmap puts that shape out of
  scope; here each section has one writer.
- **The loop acting on a pause.** Feature 9's. This design stores the pause and
  who set it.
- **Carrying a new address to sessions automatically.** Session control is the
  workspace manager's. The skill sends the lines and records who has them.
- **Migrating the process owner's record by tool.** It predates the skill and
  isn't canonical. The strategy's migration is a cutover the process owner
  runs: a new roadmap-scope record whose first entry links the old one,
  written with `record-append.sh`'s addressed form.

## Solution Architecture

### The template

```
wait --landed--> roadmap_status --opened--> record --> pick_facts
                                --failed--> failure
reconcile: + gate reconcile_handover (record-handover.sh --check)
```

`wait` gains the event value `landed`. `roadmap_status` is evidence-closed, as
`decision_apply` is. `record-confirm.sh` gains a `roadmap_status` case: a Side
effects row with Action `roadmap-status` whose Target names the unit, written
after the step became due.

### Files

| File | Change | Pull request |
|---|---|---|
| `skills/coordinate/scripts/record-append.sh` | new: append and list entries | 1 |
| `skills/coordinate/scripts/record-common.sh` | the entry marker, the text checks shared with the Decisions columns, the write-access read | 1 |
| `skills/coordinate/references/record-template.md`, `SKILL.md` | the body and the comments; where state lives | 1 |
| `skills/coordinate/scripts/record-codec.jq` | Run, Standing and Work, optional after Holds, in the record and the handoff | 2 |
| `skills/coordinate/scripts/record-state.sh` | new: the sections' one writer | 2 |
| `skills/coordinate/scripts/record-write-core.sh` | `STATE_WRITER`; the new sections in the private-repository scan | 2 |
| `skills/coordinate/scripts/record-handover.sh` | new: the stored set and its gaps | 2 |
| `skills/coordinate/scripts/pick-facts.sh` | the cap and parked bound from Run | 2 |
| `skills/coordinate/scripts/predecessor-handoff.sh`, `rotation-close.sh` | a handoff carries Run, Standing and Work | 2 |
| `skills/coordinate/koto-templates/coordinate.md`, `coordinate.mermaid.md`, `references/loop.md` | the reconcile gate and directives | 2 |
| `skills/coordinate/scripts/roadmap-status.sh` | new: open, confirm and drop the roadmap pull request | 3 |
| `skills/coordinate/scripts/pick-facts.sh` | `landed` units from `roadmap-status` rows | 3 |
| `skills/coordinate/scripts/record-confirm.sh`, `coord-verdict.sh` | the `roadmap_status` case | 3 |
| `skills/coordinate/koto-templates/coordinate.md`, `coordinate.mermaid.md` | `landed`, `roadmap_status` | 3 |
| `skills/coordinate/requires.tsv` | `shirabe roadmap populate` | 3 |
| tests | `record-append_test.sh`, `record-state_test.sh`, `record-handover_test.sh`, `roadmap-status_test.sh`, codec and pick cases, and an engine test of the handover | 1 to 3 |

## Implementation Approach

Three pull requests after this design, each landing before the next opens.

1. **The append.** `record-append.sh` and the reference text. A test appends
   two entries to a stubbed record and reads both back in order with their
   stamps, author and edit flag, then refuses a closed or foreign target, a
   private name on a public host and an oversized entry. No template change.
2. **The stored set and the handover gate.** The three sections, their writer,
   the handover read and the gate, and the cap from Run. The engine test is the
   2026-09-29 handover: a fixture record holding two holdings (one with a pull
   request), a local-agent Work row, a standing answer relayed by the process
   owner, a hold, a cap of one set by the human, and an old coordinator's
   address with both workers told. A replacement session started on it with no
   other file and no cap argument reaches reconcile, is held by the gate until
   it writes its own address and tells both workers, then reaches pick with the
   cap of one, and the stored set it reads carries every property the roadmap
   names. It is checked against the three losses: the local-agent work has a
   row, the standing answer is in the record, and the gate lists each worker
   until it is told.
3. **The write-back.** `roadmap-status.sh`, the `landed` event and its state,
   pick's `landed` units. An engine test lands a unit, confirms the merge, sends
   `landed`, sees the roadmap pull request opened against a stubbed roadmap
   with the Status, Outcome and Needs changes and nothing else, and asserts the
   next pick doesn't offer the unit; then the stubbed roadmap reads Done,
   `--confirm` removes the row, and pick sees the unit Done.

Template changes run the evals for every scenario that reaches a changed state.

## Security Considerations

An entry is text a coordinator wrote, posted where anyone with access can read
it, so it gets the checks the Decisions text already gets on a public host, and
the reader counts only marked comments by authors with write access to the
host. A comment's author is GitHub's fact, not the entry's claim. The stored
set's cells go through the codec like every other cell; the address is a topic,
never a session id, path or job id, and the codec refuses one.
`roadmap-status.sh` changes only three lines of one feature and the generated
sections, on a new branch, and opens a pull request; it never merges and never
pushes to the default branch. Nothing here widens what the coordinator may do.

## Consequences

### Positive

- An entry is one call, and the account has no size limit.
- A replacement finds the run's arguments, the cap, the next step per holding,
  the work outside the holdings, the standing answers, the holds and where
  reports go, in the record, and can't dispatch until every live worker knows
  the new address.
- A landed feature is never offered again, and the roadmap is updated without
  a hand-made pull request.
- Nothing a coordinator needs lives in a directory on the host.

### Negative

- A successor reads two things, the body and the comment stream, and a long
  stream costs context.
- The handover gate stops the first start of every existing record until its
  stored set is filled.
- The roadmap pull request waits on a person; until it merges, the feature's
  dependents stay blocked.

### Mitigations

- `record-append.sh --list` prints the stream as JSON, so a successor reads
  only the kinds it needs (the events and the last entries) through a local
  agent.
- The gate's report names each gap and the command that fills it.
- Pick lists the pending roadmap pull requests, so the coordinator can ask for
  the merge when a dependent is waiting.
