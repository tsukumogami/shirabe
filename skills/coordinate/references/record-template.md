# The Record: Template and Procedures

What the record holds, and where it lives for each scope, are in
`skills/coordinate/SKILL.md`. This file holds the literal shapes and the
steps that open, update and close it. Load it when you open or update the
record.

## Container and Host

| Scope | Host repository | Container |
|---|---|---|
| Roadmap `docs/roadmaps/ROADMAP-<name>.md` | the roadmap's repository | an issue titled `Coordinator record: ROADMAP-<name>` |
| Discipline `<name>` | the host repository the human named | a draft pull request from `coordinate/discipline-<name>` |

A roadmap's record is an issue because an issue fits a record that commits
nothing: there is no branch to maintain, no merges from the default branch
to absorb, and it closes cleanly when the roadmap finishes. A rotation's
record is a pull request because its diff is the handoff file it commits
at the end.

Name every worker, in the record and in every pull request, by its dispatch
topic, never by session id, instance path or job id: those are host facts
that don't survive a restart or a move, and reconcile finds sessions by
topic. When the record's host repository is public, it never names a
private repository, path or issue; a holding that would need one is a
scope question for the human.

## Finding or Opening the Record

The workflow finds the record itself, on every start, before the first
dispatch: `scripts/record-find.sh` runs as the `record_find` state's check,
and you open a record only when it reports none, with `scripts/record-open.sh`.

**Roadmap scope.** The find lists every open issue and matches the record's
title exactly. It never uses GitHub's search: the search index can lag a newly
created issue, so a coordinator restarted just after opening its record would
find none and open a second, and a phrase search also matches longer titles
such as a `-v2` roadmap. One open issue with the title, the declaration line,
an author and last editor with write access, and a canonical body is adopted;
never open a second one. A title match without the declaration line, more than
one match, a body that isn't canonical, or an author without write access is a
stop for the human: don't pick, report what you found and ask.

**Discipline scope.** The find reads the branch `coordinate/discipline-<name>`
and its pull requests, and reports one of these:

1. **An open pull request carrying the declaration line, whose title's end date
   hasn't passed:** a restart of that rotation; it is adopted, never replaced.
2. **The same, past its end date:** the previous rotation's record; close it out
   as "Closing a Predecessor's Rotation" says, and once it has merged, the find
   runs again.
3. **An open pull request without the declaration line:** not adopted; a scope
   question for the human.
4. **A branch whose last pull request merged or closed, or that never had one:**
   `record-open.sh --recut` deletes it and cuts it again from the default
   branch, so a squash-merged history never comes back.
5. **No branch:** `record-open.sh` cuts it from the default branch, makes an
   empty commit, and opens the draft pull request.

Report the record's issue number or pull request URL up with every report,
so a successor is handed it as a decision and reads it directly.

## The Rotation's Pull Request Title

`docs(coordinate): <name> rotation <start> to <end>`, with both dates in
`YYYY-MM-DD` form from the day it opens. The end date is the start plus
the rotation's length. If the human ends the rotation early, or sets a new
length, edit the end date to match in the same update that records the
decision; the title is where a successor reads it.

## The Body

The body is rendered by `scripts/record-render.sh` from its JSON form and read
back by `scripts/record-parse.sh`; never write it by hand. A body is valid only
when rendering what was parsed reproduces it byte for byte, so the tables below
are the whole record and nothing else may sit between them. A rotation's pull
request body starts with the fixed Part 1 line and a single `---`, which the
renderer writes (`--container pr`); an issue body starts at the declaration
line.

```markdown
> This is a **coordinator record** for <ROADMAP-<name> | the <name> discipline>.

Written: <YYYY-MM-DDTHH:MM:SSZ>

## Holdings

| Unit | Entry point | Mode | Phase | Dispatch status | Return path | Worker | Repo | Branch | Verified head | Dispatched | Pull request |
|---|---|---|---|---|---|---|---|---|---|---|---|
| <feature, issue, question or choice> | <skill> | <--auto and flags> | <scoping-ahead, executing or held> | <dispatching, dispatched or dispatch-failed> | <message, or leg <request-id>:<leg>> | <dispatch topic> | <owner/repo> | <branch, blank until known> | <full sha once verified, else blank> | <YYYY-MM-DD> | <[#n](URL), blank for none yet> |

## Deferrals

| Deferral | Reason | Raised | Disposition |
|---|---|---|---|
| <what> | <why not now> | <YYYY-MM-DDTHH:MMZ> | <blank, filed #n, closed: <reason>, or carried <YYYY-MM-DDTHH:MMZ> [until <YYYY-MM-DDTHH:MMZ>]: <reason>> |

## Side effects in flight

| Action | Target | Verified head | Attempted | How to confirm |
|---|---|---|---|---|
| <merge, close, teardown> | <pull request, issue, worker> | <full sha verified before acting or asking> | <YYYY-MM-DDTHH:MMZ> | <the read that settles it> |

## Reversals

| Date | Reversed | Now | Reason | From |
|---|---|---|---|---|
| <YYYY-MM-DDTHH:MMZ> | <earlier decision> | <new decision> | <why> | <who decided> |
```

An empty section reads `None.` in place of its table. No table carries a
status, CI or merge-state column: those are read from GitHub every time, and
the renderer refuses one. Phase says whether a worker is scoping a unit whose
execution waits on another feature landing (`scoping-ahead`), executing it, or
holding a verified pull request whose merge a hold in the record stops (`held`).
A row leaves Side effects in flight once confirmed. Reversals only grow.
A Holdings row outlives its pull request's merge: a confirmed merge blanks
its Pull request cell and keeps its Verified head, and the row goes when the
worker is torn down.

A deferral is disposed of when its Disposition reads `filed #<n>`,
`closed: <reason>`, or `carried <time>: <reason>` with a time at or after the
run's start. Filed and closed rows drop out at the first rewrite after the
run's first dispatch; a carried row stays with its new reason.

On a restart (a run opened over a live run of the same scope, which it
cancels), the carry time is compared with the start of the first of those
cancelled runs instead of this run's start, so a carry made since then still
counts; a run that ended at a handover or a finish breaks the chain. A carry
can name a decide-by, `carried <time> until <time>: <reason>`; once the until
time passes, the deferral is open again.

The verified head is the sha the workflow verified before you acted or asked.
After a crash, confirming a merge compares the default branch against that sha,
not against whatever the branch holds now.

The renderer refuses a Worker cell holding anything but a dispatch topic (a
`/`, a UUID, a `session_` prefix, a `+`, or only digits), a malformed
structured cell, and a control character. Quoted text such as a CI log line
is safe in any cell: pipes, newlines and backticks are encoded so they can't
break a table.

### The Holds section

A record that holds a merge carries one more section, after Reversals and
before Decisions, rendered only once it has a row:

```markdown
## Holds

| Hold | On | Until | Set by | Set | Lifted |
|---|---|---|---|---|---|
| <short name> | <owner/repo#n> | <merged owner/repo#m, tag owner/repo <tag>, or lifted> | <who asked for it> | <YYYY-MM-DDTHH:MMZ> | <blank, or <YYYY-MM-DDTHH:MMZ> by <who>> |
```

A hold is a condition on another lane's state or a person's word, and the land
check reads each one live before it reports a pull request ready: another pull
request merged, a tag pushed, or the Lifted cell filled. One it reads as unmet,
or can't read, is `held`, and the pull request goes to the person as held.
`scripts/record-hold.sh` is the only writer: `--add` a hold someone asked for,
and `--lift` one whose Until is `lifted` when the person lifts it. A hold is
never deleted. When a pull request merges while a hold on it is unmet, write a
Reversals row whose Reversed names `hold <name>` and whose Now says `merged
while held` and who merged it, as GitHub names them; the record step waits for
it. The section's grammars are the codec's (`scripts/record-codec.jq`), and the
write core refuses any other writer's change to it.

### The stored set: Run, Standing and Work

What a replacement coordinator needs to continue from the record alone, and
nothing else, sits in three more sections after Holds and before Decisions,
each rendered only once it has a row:

```markdown
## Run

| Key | Value | Set by | Set |
|---|---|---|---|
| <arguments, cap, coordinator or told> | <the value> | <who set it> | <YYYY-MM-DDTHH:MMZ> |

## Standing

| Standing | Kind | On | Until | What | Owner | Relayed by | Set |
|---|---|---|---|---|---|---|---|
| <s<n>> | <pause, go-ahead, approval or answer> | <a pause's or go-ahead's scope, or blank> | <a pause's resume condition, or blank> | <what it says> | <the person who decided it> | <who carried it here, or blank> | <YYYY-MM-DDTHH:MMZ> |

## Work

| Item | Kind | Who | Next step | Wakes | Updated |
|---|---|---|---|---|---|
| <a holding's Unit, or what the work is> | <holding or local-agent> | <its Worker, or who does it> | <what happens next> | <the holding's wakes so far; 0 for a local agent> | <YYYY-MM-DDTHH:MMZ> |
```

**Run** holds the run's arguments, the cap in force (the readers of the cap
take it over the `--cap` the session was opened with), this coordinator's
address (a dispatch topic, never a session id) and one `told` row per party
that has been sent that address. A new address clears the `told` rows.
**Standing** holds the events only a person owns while they still bind: a
pause, a go-ahead (a release or another step allowed once), a relayed approval,
a standing answer. Owner is the person who decided it; Relayed by is who
carried it to you, blank when they told you directly. A pause names its
scope in On, `all` (the whole coordinator) or one unit as pick lists it
(`Feature 2`, `ED1`, `#12`, `owner/repo#12`), and its resume condition in
Until: `lifted` (a person's resume ends it), `time <YYYY-MM-DDTHH:MMZ>` in UTC,
`merged owner/repo#n` or `tag owner/repo <tag>`. pick, the dispatch check, the
land check and the merge read every pause live (`scripts/pause-read.sh`) and
refuse what one holds; a pause whose condition reads met holds nothing, and
the coordinator ends its row. A go-ahead may name one unit in On: it lets that
unit through any pause until it is used and ended. A resume, a used
go-ahead or approval, or a withdrawn answer ends the row. **Work** has a next
step for every holding and a row for any work no holding covers, a local
agent's above all: without its row a successor can't see it.

`scripts/record-state.sh` is the only writer, and every change it makes is
written to the body and then told as an entry:

```
record-state.sh --session S --run arguments|cap|coordinator <value> --by <who>
record-state.sh --session S --told <topic> --by <who>
record-state.sh --session S --standing <kind> [--on <scope>] [--until <condition>] --what <text> --owner <who> [--relayed-by <who>]
record-state.sh --session S --end <s<n>> --by <who>
record-state.sh --session S --work <item> --kind holding|local-agent --who <who> --next <text>
record-state.sh --session S --done <item>
record-state.sh --session S --list
```

Write each when it happens: the arguments, the cap and your address at your
first start; a Standing row or a cap when a person's word arrives, wherever it
arrives (a person's own comment on the record is not an entry, and the reader
never counts it, so you write it, the person as owner and yourself as
relayer); a holding's Work row once its dispatch is sent, which the record step
waits for and which also records its worker as told your address; a
local-agent row before the agent starts, `--done` when it lands. A Work row
whose holding is gone is dropped at the next write. A holding's Wakes are
brought up to date from this run's session log at each write, and its final
count is appended as an entry when its row leaves Work; the count is a floor,
since a wake inside the minute after a write, or one a crashed run logged
after its last write, isn't counted.

`scripts/record-handover.sh` reads the stored set back, with the holds, and
names its gaps: no arguments, cap or address; a live holding (dispatched, and
not merged and waiting for its teardown) with no Work row, or whose worker
hasn't been told the current address. The reconcile step's gate runs it at
every start, so a replacement that writes its own address can't go on until
it has told each live worker. A record written before these sections existed
has every gap at its first start under this version; fill them once. A
rotation's handoff carries the three sections as they stand.

### The Decisions section

After Reversals, any Holds and any of the stored set, once the record holds a
decision, comes one
more section. It
opens with the identifier the next decision takes, and has one row per decision
the scope opened:

```markdown
## Decisions

Next decision: <n>

| Decision | Round | Question | Options | State | Source | Verdict | Recommendation | Reason | Context | Problem | Grounds | Target | Owed | Asked | Evidence | Outcome | Decided by | Updated |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| <n> | <times escalated> | <one line> | <one per line> | <proposed, coordinator-verdict, escalated or settled> | <worker <topic>, coordinator <topic> #<n> round <r>, dispatcher or self, then a stamp> | <blank, settle, escalate or hold> | <one of the options> | <its reason, or what a hold waits on> | <what is being decided and why now> | <what is unresolved and why the coordinator can't settle it> | <scope, supplied-decision, reserved-step, outside-scope> | <a person or coordinator <topic>> | <blank, escalation, withdrawal or reply> | <YYYY-MM-DDTHH:MMZ> | <one line per item: <time> <source> <stamp>: <text>> | <outcome and reason> | <who decided> | <YYYY-MM-DDTHH:MMZ> |
```

Every entry has Decision, Round, Question, State, Source and Updated. What
each state means, and what else it requires:

| State | Means | Also requires | Reached by |
|---|---|---|---|
| `proposed` | Opened, not yet taken up | Options | `--open`, `--open-from-report` |
| `coordinator-verdict` | With the coordinator for a verdict; a Verdict of `hold` waits on the fact in Reason, and `escalate` is queued behind the escalated entry | Reason, when the Verdict is `hold` | `--take`; any evidence, from any state |
| `escalated` | Asked of the run's target, one entry at a time | Options (each `<option> -- <explanation>`), Recommendation, Reason, Context, Problem, Grounds, Target | `--escalate`, or the release of a queued verdict |
| `settled` | Decided | Outcome (`<outcome>; reason: <reason>`), Decided by | `--settle`, `--answer` |

Owed says which message the entry still owes (an escalation, a withdrawal
after new evidence on a sent escalation, or a reply to the source that asked),
and clears when `--sent` marks it. Asked is when the escalation went out.

A record written before the section existed has none and stays canonical. The
section appears at the first decision and stays: `Next decision` only goes up,
so an identifier is never reused, and a section holding `Next decision: 1` and
no entry is not canonical. A stamp, `[<run> <kind> <seq>]`, names the run (the
UTC stamp in its session's name) and the visit that caused a write. `@` is
encoded in the text columns so a record never mentions anyone, and those columns
refuse a private repository, a home-directory path and a token-shaped string.

Only `record-decision.sh` changes the section: `record-write.sh` refuses a body
whose section differs from the live record's, and `record-open.sh` refuses a new
record that carries one. A rotation's handoff carries the unsettled entries and
the same `Next decision`; a predecessor copy carries the section as it stands. A
roadmap record can't close while an entry is unsettled.

The write core refuses a body over 60,000 bytes (`record-full`, exit 13), under
GitHub's 65,536-byte limit.

The declaration line is for readers. It is deliberately different from the
`This is a **coordination PR**` marker that `/execute` uses, so no gate
written for coordination pull requests ever parses a record.

**Updating.** Parse the live body, change the JSON, and render the whole body
again keeping the live body's `Written:` time (`record-render.sh --written
<that time>`); apply it with the record's write script, never by editing the
body on GitHub. The write script compares that time with the live record's,
refuses with `record-changed` (exit 12) when someone wrote since, and stamps
its own time on what it writes. Every pull request in the record is a
link. Follow the host repository's conventions (its CLAUDE.md) for commit
messages and bodies.

## Entries

The body is the record's state: what is true now, rewritten whole. Its account,
what happened and why, is a stream of entries, each one comment on the same
issue or pull request, written only by `scripts/record-append.sh`:

```
record-append.sh --session <session> --text-file <file>
```

It re-reads the record first and refuses one that is closed or isn't this
scope's, stamps the entry from the host clock in UTC to the second, and posts:

```markdown
<!-- coordinator-record-entry v1 kind=entry -->
**<YYYY-MM-DDTHH:MM:SSZ>** (host clock) entry

<the text>
```

An entry never grows and is never rewritten, so the record needs no archive
however long the run. Write one when something happens that a successor would
need the story of: what you dispatched and why, what a person told you, what
you decided and on what evidence. On a public host the text gets the checks the
Decisions section's text gets (no private repository, home-directory path or
token-shaped string), and `@` is written encoded, so an entry never mentions
anyone.

`record-append.sh --session <session> --list` reads the stream back as JSON,
oldest first by GitHub's creation time, with each entry's stamp, author, kind,
text and whether it was edited after it was posted. Only comments carrying the
marker and written by an author with write access to the host count; anything
else on the thread, a person's own comment included, is not an entry. When a
person tells you something on the thread, write it into the record yourself.

Anything a check or a successor acts on stays in the body as state; an entry is
its account, never its only copy, because a deleted comment leaves no trace in
the stream. The addressed form, `--scope --name --repo --ref` in place of
`--session`, writes an entry when no run is open, such as after a run ended.
GitHub limits how fast comments are created; one post per entry stays far
inside it, and a refused post (exit 11) is retried once, later, never in a
loop.

## Where State Lives

A coordinator's state lives outside its session and outside any directory the
workspace manager converges, and what must outlive the host lives on GitHub.
Here that is two places: the koto session (its journal on the host between
checkpoints) and this record, for everything else. Keep no tools directory beside
it. A local script for record entries, a snapshot copy of the body, archive
files, standing answers in a file and progress facts all have homes in the
skill: `record-append.sh`, the body and its revisions on GitHub, the entries,
the record's tables, and `progress-view.sh` over pick's facts.

## Writing a Landed Feature Back to the Roadmap

When a roadmap feature's last pull request has merged (or, for a spike or a
design, its acceptance call is made), tick `wait` with `event: landed` and the
feature's tag as `unit`, and at `roadmap_status` run:

```
roadmap-status.sh --session <session> --unit "<tag>" --outcome "<what landed>"
```

It opens a pull request on the roadmap's repository that sets the feature's
Status to Done, writes its Outcome, removes its Needs line and regenerates
the generated sections, changing nothing else, and adds a Side effects in
flight row:

```markdown
| roadmap-status | <tag> [#<n>](<url>) |  | <YYYY-MM-DDTHH:MMZ> | the roadmap on <default> reads <tag> Done |
```

While the row stands, pick lists the feature as `landed` and no brief renders
for it; it is not Done for its dependents until the roadmap says so. Only one
is pending at a time. Once the roadmap on the default branch reads Done,
`roadmap-status.sh --confirm "<tag>"` removes the row; a pull request closed
unmerged is cleared with `--drop "<tag>" --reason "<why>"`. The skill never
merges the roadmap pull request.

## Closing a Roadmap Record

When every feature reads Done or Dropped on the roadmap, Holdings and Side
effects in flight are empty, every deferral is filed or closed, and every
decision is settled: write
the final body, then close the issue if the workspace permits, or hand the
close to the human.

## The Discipline Handoff

At rotation end, write `docs/disciplines/<name>.md`, one file per
discipline, overwritten each rotation. It is plain markdown with no
shirabe artifact prefix, so `shirabe validate` applies no structural
checks to it, though the host's docs validation still runs its prose
checks on it:

```markdown
# <name> handoff, <YYYY-MM-DD>

Rotation from <start> to <end>. Host repository: <owner/repo>. Record: <pull request URL>, kept on coordinate/discipline-<name>.

<the four sections, and the Decisions section with its unsettled entries when the record has one>

## Reasoning for the next rotation

<Prose: what this rotation learned that the tables can't say.>
```

The same renderer writes it (`--format handoff`). It carries no declaration
line and no `Written:` line, so a search for records never matches a committed
handoff.

Write the reasoning section fresh each rotation. Replace the previous
rotation's text; never append to it, or the handoff grows into a standing
protocol.

## Closing a Rotation

1. Commit the handoff to the record branch and push.
2. If the rotation ended on a different day than the title says, edit the
   title's end date to the actual one.
3. Mark the pull request ready and merge it if the workspace permits;
   otherwise hand it to the human as the last row of the merge-order
   table in `references/verification-checklist.md`.
4. Delete the branch once it has merged.

## Closing a Predecessor's Rotation

When the discipline check finds a previous rotation's record still open
past its end date, the successor closes it, and writes only what it can
stand behind:

- The tables are copied from the predecessor's record body as it stands,
  under a line reading "As written by the previous rotation at <its
  Written time>; not re-checked." Your own reconcile re-checks those rows
  when you carry them into your record.
- The reasoning section says the outgoing rotation's reasoning was not
  recorded. Never write it on the predecessor's behalf.
- Open deferrals carry into your own record, to be disposed of before your
  first dispatch.

Then follow Closing a Rotation for that record.
