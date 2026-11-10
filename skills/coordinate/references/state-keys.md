# The State: Keys and Procedures

What the record holds, and where it lives for each scope, are in
`skills/coordinate/SKILL.md`. This file holds every key of the record's
state, its JSON shape and its one writer, and the steps that open, update and
close it. Load it when you open or update the record.

## Where the Record Lives

| Scope | Host repository | Record |
|---|---|---|
| Roadmap `docs/roadmaps/ROADMAP-<name>.md` | the roadmap's repository | the coordinator's koto session on this host |
| Discipline `<name>` | the host repository the human named | the coordinator's koto session on this host, one session per rotation |

The record is never an issue, a pull request or a committed file: there is no
branch to maintain and nothing to close on GitHub when the scope finishes. A
coordinator that still ran on a GitHub record when this version arrived is
imported into its session once, at its next fresh start (see Finding or
Opening the Record).

Name every worker, in the record and in every pull request, by its dispatch
topic, never by session id, instance path or job id: those are host facts
that don't survive a restart or a move, and reconcile finds sessions by
topic. When the record's host repository is public, it never names a
private repository, path or issue; a holding that would need one is a
scope question for the human.

## Finding or Opening the Record

The workflow finds the record itself, on every start, before the first
dispatch: `scripts/state-find.sh` runs as the `record_find` state's check,
and you open a record only when it reports none, with `scripts/state-open.sh`.
The find reads this host's koto sessions and nothing on GitHub.

Before the find runs, `coordinate-open.sh` looks for the scope's session. A
live run of the scope is resumed, an earlier one that can't be resumed is
carried into a new run, and `--import` brings a run from another host. On a
fresh start (no session of the scope here holds `record/meta`), the opener
asks the legacy importer once whether a GitHub record of the scope is still
open; when one is, its state is copied into the new session and a `moved`
note is posted on it, and the start stops when that record can't be read or
there are several.

**Roadmap scope.** The find reads this run's session: `found` when it holds the
record, `none` when it doesn't (`record_open` opens it there), and `malformed`
when what it holds doesn't read back as a record of this scope, a stop for the
human.

**Discipline scope.** Each rotation is its own session. The find reads this
host's sessions of the discipline: this run's own rotation (`found`), the
latest earlier rotation once it has ended (`predecessor <session>`, carried
into this run), none at all (`first`, opened in this run's session), or an
earlier rotation that fails a rule (`unreadable <session>`, a stop for the
human). Its window, host and predecessor are its session's `record/rotation`,
and the reasoning it leaves the next rotation `record/reasoning`.

Every report names the record's session name on its record line (SKILL.md,
"Reporting"), so a successor is handed it as a decision and reads it directly.

## The Rotation's Window

A rotation's window is `record/rotation`: the start the day it opens and the
end the start plus the rotation's length less one day. When the human ends the
rotation early, tick the hub with `event: end`, and the rotation ends at
`rotation_end`. There is no pull request title to correct.

## The Keys

The record is its session's keys, each a JSON value, and nothing else: there is
no body to render or parse. A reader is handed the whole state as one JSON
object (`scripts/state-read.sh`'s `rs_record`), every section field present
and an optional section that holds nothing left out, and a writer hands the
write core the next state in the same form (see Updating). Read a key
yourself with `koto context get <session> <key>`; never write one by hand.

| Key | Holds | Writer |
|---|---|---|
| `record/meta` | `{scope: {kind, name}, store: "session", written, pending, template_compat, template_fingerprint, standing_used}`: the scope, the written time, the mark a write sets while it is part way through, the template compat the run was compiled at with its template's structural fingerprint, and the highest Standing id number the record has given out, which `state-stored-set.sh --standing` reads instead of the entries to choose the next id. A seed into a session with no entries and a carry set `standing_used`; a record from before it, one the legacy importer wrote, or one re-seeded over entries has none, and its first `--standing` reads the entries once and records it. A seed, a carry, the legacy import and a takeover set the compat pair from the compat table beside the run's plugin, and `coord-log.sh compat` reads it before the table, so a run the table no longer lists still names its compat; a record from before the pair, or a run whose table didn't list it, has none and is looked up in the table | `state-write-core.sh`, for every writer |
| `record/holdings` | an array of Holdings rows (below), each with its `pushed_head` beside it when one is kept | `state-write.sh` through `state-holding.sh` |
| `record/deferrals` | an array of Deferrals rows | `state-write.sh` through `state-holding.sh` |
| `record/side-effects` | an array of Side effects rows | `state-write.sh` through `state-holding.sh`; `roadmap-status.sh` adds the roadmap edits' rows |
| `record/reversals` | an array of Reversals rows | `state-write.sh` through `state-holding.sh` |
| `record/holds` | an array of Holds rows, a key only once it has one | `state-hold.sh` (`HOLDS_WRITER`) |
| `record/run`, `record/standing`, `record/work` | the stored set's rows, each a key only once it has one | `state-stored-set.sh` (`STATE_WRITER`); `roadmap-status.sh` (`VERDICT_WRITER`) writes the `verdict-owed` and `rework` Work rows; `state-open.sh`'s seed writes the Run `role` row too |
| `record/decisions` | `{next, entries}` (with `archived` and `kept` on a record moved from GitHub), a key from the first decision on | `state-decision.sh` (`DECISIONS_WRITER`) |
| `record/rotation`, `record/reasoning` | a discipline rotation's window, host and predecessor, and the reasoning it leaves the next rotation | `state-stored-set.sh` (`STATE_WRITER`) |
| `record/host` | the host facts (see Where State Lives), never sent to GitHub | `state-stored-set.sh --host` |
| `record/entries/<n>`, `record/posted/<n>` | the account, one entry each, and the URL of an outward entry's comment | `state-entry.sh` |
| `record/archive/<n>` | `{n}`, the marker beside a `decisions` entry, so the archived rows are read without listing every entry | `state-entry.sh`; the legacy importer |
| `legs/<request>/<leg>` | a worker leg (see Where State Lives) | `dispatch-worker.sh`, `wait-target.sh`, `reconcile-legs.sh` |

Any section key may also be written by the core's carry: `state-open.sh`
seeding a new run or carrying a predecessor's state, `coordinate-open.sh`
carrying an earlier run into a new one, and the legacy importer.
`coordinate-template-structure_engine_test.sh` holds each key to its writer.

The JSON examples here and below are fragments of the state a writer hands
`state-write.sh`: each key holds only the value under its field name, so
`record/holdings` holds the array, not the object around it. A key's name
uses a hyphen where its field uses an underscore (`record/side-effects` holds
`side_effects`).

The four sections every record has, as JSON rows:

```json
{"holdings": [{"unit": "<feature, issue, question or choice>", "entry_point": "<skill>", "mode": "<--auto and flags>",
               "phase": "<scoping, scoping-ahead, executing or held>",
               "dispatch_status": "<dispatching, dispatched, dispatch-failed or stranded>",
               "return_path": "<message, or leg <request-id>:<leg>>", "worker": "<dispatch topic>", "repo": "<owner/repo>",
               "branch": "<branch, empty until known>", "verified_head": "<full sha once verified, else empty>",
               "dispatched": "<YYYY-MM-DD>", "pull_request": "<[#n](URL), empty for none yet>"}],
 "deferrals": [{"deferral": "<what>", "reason": "<why not now>", "raised": "<YYYY-MM-DDTHH:MMZ>",
                "disposition": "<empty, filed #n, closed: <reason>, or carried <YYYY-MM-DDTHH:MMZ> [until <YYYY-MM-DDTHH:MMZ>]: <reason>>"}],
 "side_effects": [{"action": "<merge, close, teardown, or a roadmap edit: roadmap-status, milestone-done, milestone-verdict, milestone-reopen>",
                   "target": "<pull request, issue, worker, or <tag> [#n](URL) for a roadmap edit>",
                   "verified_head": "<full sha verified before acting or asking>", "attempted": "<YYYY-MM-DDTHH:MMZ>",
                   "how_to_confirm": "<the read that settles it>"}],
 "reversals": [{"date": "<YYYY-MM-DDTHH:MMZ>", "reversed": "<earlier decision>", "now": "<new decision>",
                "reason": "<why>", "from": "<who decided>"}]}
```

An optional section that holds nothing has no key. No row carries a status,
CI or merge-state field: those are read from GitHub every time, and the write
core refuses one. Phase says whether a worker is scoping a unit whose
scoping is the whole unit (`scoping`), scoping one whose
execution waits on another feature landing (`scoping-ahead`), executing it, or
holding a verified pull request whose merge a hold in the record stops (`held`).
A row leaves Side effects once confirmed. Reversals only grow.
A Holdings row outlives its pull request's merge: a confirmed merge empties
its `pull_request` and keeps its `verified_head`, and the row goes when the
worker is torn down. A message-path worker whose unit you dispatch again
after it went quiet is `stranded` (`state-holding.sh --strand`); its row
goes once the unit's new worker is dispatched (`--retire`, which
dispatch-worker.sh runs). A merged row whose worker was torn down outside
the pass also goes with `--retire`, at destroy, once the removed pass is
done, including one closed with no handoff comment, where the pass's entry
stands in for the link. A `dispatch-failed` row, a launch that never
started, goes through `--retire` too once no worker exists for its topic
(niwa lists no session and no unfinished Claude job carries it); its removal
is told as an `entry` entry.

A deferral is disposed of when its `disposition` reads `filed #<n>`,
`closed: <reason>`, or `carried <time>: <reason>` with a time at or after the
run's start. Filed and closed rows drop out at the first write after the
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

The write core refuses a `worker` holding anything but a dispatch topic (a
`/`, a UUID, a `session_` prefix, a `+`, or only digits), a malformed
structured field, and a control character. Quoted text such as a CI log line
is safe in a text field: the state is JSON, so nothing needs encoding.

### The Holds section

A record that holds a merge carries one more key, `record/holds`, once it has
a row:

```json
{"holds": [{"hold": "<short name>", "on": "<owner/repo#n>",
            "until": "<merged owner/repo#m, tag owner/repo <tag>, or lifted>",
            "set_by": "<who asked for it>", "set": "<YYYY-MM-DDTHH:MMZ>",
            "lifted": "<empty, or <YYYY-MM-DDTHH:MMZ> by <who>>"}]}
```

A hold is a condition on another lane's state or a person's word, and the land
check reads each one live before it reports a pull request ready: another pull
request merged, a tag pushed, or `lifted` filled. One it reads as unmet,
or can't read, is `held`, and the pull request goes to your reviewer as held.
`scripts/state-hold.sh` is the only writer: `--add` a hold someone asked for,
and `--lift` one whose `until` is `lifted` when the person lifts it. A hold is
never deleted. When a pull request merges while a hold on it is unmet, write a
Reversals row whose Reversed names `hold <name>` and whose Now says `merged
while held` and who merged it, as GitHub names them; the record step waits for
it. The section's grammars are `scripts/state-schema.jq`'s, and the write
core refuses any other writer's change to it.

A director's `diverges` call places an `align-` hold (The alignment entry,
under Entries), a row of the same grammar, in the director's record and,
copied, in the manager's:

```json
{"hold": "align-<repo name>-<n>-<40-hex placed-on head>[-<k>]",
 "on": "<owner/repo#n>", "until": "lifted",
 "set_by": "director at <address>, receiver manager at <address>",
 "set": "<YYYY-MM-DDTHH:MMZ>", "lifted": ""}
```

The placed-on head is the call's, and `-<k>` (from 2) is added only when the
same head is held again after a lift. The name is also how the `diverges`
call it was placed on is found: the reason lives in that call. Its release is
the same for every `align-` hold: a new head that the director re-reads and
calls `fits` or `fits with follow-ups`. `scripts/alignment-call.sh` places it
through `state-hold.sh --add` when no unlifted `align-` hold on the pull
request stands and the pull request hasn't merged, and prints the message the
director sends the manager:

```
Alignment hold: <owner/repo#n> at <40-hex placed-on head>
Row: <the hold row, one line of JSON>
Sources: <the call's Sources>
Reason: <the call's Reason>
Receiver: manager at <address>
Release: a new head that the director re-reads and calls fits or fits with follow-ups
```

The director's address is its Run `coordinator` row; the receiver is the
Worker of the Holdings row that links the pull request, or the call's
`--receiver`. The manager copies the hold from that message, as it arrived:

```
alignment-call.sh --session S --copy --add --message-file <the message> --event <n> --from <sender>
```

`--from` must be the address in the manager's Run `reports-to` row
(`director at <address>`), and the message must be those six lines, its head
40 hex, its row a hold row with `until` lifted and Lifted empty, named
`align-<repo name>-<n>-<that head>[-<k>]` for the pull request it names, and
set by `director at <sender>`; anything else is refused (65) with nothing
changed. It adds the identical row through `state-hold.sh` and writes a `hold`
entry naming event `<n>`, the sender, the reason and the release; the same
message again changes nothing. The manager's land check then reads the hold
from its own record and reports the pull request `held`. A successor
director's first message to a lane names the row's current address and its
own, in one line, `Director address: <current address> is now <new address>`;
`--copy --reports-to`, with the same three options and `--from` the new
address, rewrites the row through `state-stored-set.sh --run reports-to`,
`--by` the sender, and writes a `hold` entry naming the event and both
addresses. A message naming any other current address, and one sent to a row
holding no address, change nothing (65).

The hold lifts only on its release. A `fits` or `fits with follow-ups` call
written with `alignment-call.sh` runs the guarded lift in the same run, after
the call: for each unlifted `align-` hold on the pull request it reads the
live head from GitHub, and lifts the hold only when the live head isn't the
placed-on head in its name, the latest call for the live head is `fits` or
`fits with follow-ups` and is the call just written or a later one, and that
call's entry number is above the hold's `diverges` call (the latest
`diverges` entry at the placed-on head). It lifts through `state-hold.sh
--lift`, the Lifted cell reading

```
<YYYY-MM-DDTHH:MMZ> by director at <address>, <fits|fits with follow-ups> at <40-hex head>
```

writes a `hold` entry naming the hold, that head and the call's entry number,
and prints the lift message the director sends the manager:

```
Alignment lift: <owner/repo#n> at <40-hex head it was released on>
Hold: <the hold's name>
Call: <fits|fits with follow-ups>, entry <n>
```

A fits call at the placed-on head, or at a head that isn't the live head,
lifts nothing. When the live head can't be read, the call is still written,
the hold stands, and the script exits 13 naming it. A hold that became
releasable without a lift (that read failed, or the call came before the
push) is lifted by `alignment-call.sh --session S --lift-releasable --on
<owner/repo#n>`, which runs the same guard with no call, writes no
`alignment` entry and prints one lift message per hold it lifts; on a hold
that isn't releasable it lifts and prints nothing.

The manager lifts its copy from that message, as it arrived:

```
alignment-call.sh --session S --copy --lift --message-file <the message> --event <n> --from <sender>
```

The sender must be the `reports-to` address, as for `--copy --add`. The lift
is refused (65, nothing changed) when its head is the placed-on head, and
unless its head is the `verified_head` of the Holdings row that links the
pull request, so a replayed lift naming an older head is refused too. A pull
request no holding links, one the manager wrote, is checked against its live
head from GitHub instead: another head is refused (65), and a head that can't
be read leaves the hold standing (2). An accepted lift stamps the copy's
Lifted cell with the director's text and writes a `hold` entry naming the
hold, the head, the call's entry number and event `<n>`, so a lift with no
matching call shows in the manager's own record; a hold already lifted
changes nothing. A person's lift on an unchanged head doesn't come this way:
the director records it with `state-hold.sh --lift --by <person>`, and the
manager records the relayed word on its copy the same way, as `surface` says
for a person's word. Either lift ends the hold for the land check.

### The stored set: Run, Standing and Work

What a replacement coordinator needs to continue from the record alone, and
nothing else, sits in three more keys, `record/run`, `record/standing` and
`record/work`, each once it has a row:

```json
{"run": [{"key": "<arguments, cap, coordinator, told, pending, rules, briefs, friction, reports-to or role>",
          "value": "<the value>", "set_by": "<who set it>", "set": "<YYYY-MM-DDTHH:MMZ>"}],
 "standing": [{"standing": "<s<n>>", "kind": "<pause, go-ahead, approval, answer, assignment or rule>",
               "on": "<a pause's or go-ahead's scope, an assignment's unit, or empty>",
               "until": "<a pause's resume condition, or empty>", "what": "<what it says>",
               "owner": "<the person who decided it; empty on a rule row>",
               "relayed_by": "<who carried it here, or empty; empty on a rule row>",
               "set": "<YYYY-MM-DDTHH:MMZ>",
               "source": "<where its words come from; a rule row's always, left out when blank>"}],
 "work": [{"item": "<a holding's unit, a parked or follow-up unit, a milestone's tag, or what the work is>",
           "kind": "<holding, local-agent, decision, follow-up, verdict-owed or rework>",
           "who": "<its worker, who does it, decision <n>, owner/repo#n, none, verdict <id> or failure <id>>",
           "next": "<what happens next>", "wakes": "<the holding's wakes so far; 0 otherwise>",
           "updated": "<YYYY-MM-DDTHH:MMZ>"}]}
```

**Run** holds the run's arguments, the cap in force (the readers of the cap
take it over the `--cap` the session was opened with), this coordinator's
address (its messaging address: the session name a worker can message, which
may hold `_`, or a dispatch topic; never a session id, a path or an instance
name), one `told` row per party
that has been sent that address, and one `pending` row per worker that can't
be sent it yet: its session is gone, but its instance is still there to be
started again. A worker is never both told and pending (the record is refused
if it is). A new address clears the `told` rows and carries the `pending`
ones: each stays before the new coordinator row, where it reads as carried
and holds the handover gate until `handover-classify.sh` confirms it. It also
holds the crash set: `rules` and `briefs` rows (`<label> sha256:<64 hex>`, the
digest of a file this coordinator ran with, one row per label, a second write
replacing the first), a `friction` label, and `reports-to` (`<name>` or `<name>
at <address>`: who this coordinator reports up to, a person or the coordinator
that dispatched it, and for a coordinator its messaging address). The start writes the
`rules` rows of the files the session loads as rules, never you: `skill-<file
name>` for the skill's `SKILL.md`, template and references at the plugin root,
and `workspace-<depth>-<file name>` or `workspace-<depth>-rules-<file name>`
for each `CLAUDE.md`, `CLAUDE.local.md` and `.claude/rules/*.md` from the
working directory up to below the home directory (`scripts/rule-files.sh`
lists them, `state-stored-set.sh --rule-files` writes them). The opener writes
them on a resume, a carry, a takeover and an import, and `state-open.sh` after
each seed; a row whose digest didn't change is kept as written, and one `run`
entry names each label added, changed or removed. A failed write prints
`warning=rules-unrecorded` and the next start writes them. Any other `rules`
label is yours, through `--run rules`. A `briefs` row is the brief intake's:
you record the brief's path with `--host briefs:<label> <path>`, and
`--intake <label>` writes the row once it has taken the brief's lines (Rule
rows, below). A session opened before the
GitHub record was removed may also hold a `store session` row; it is kept as it
is, and nothing writes a new `store` row (`state-stored-set.sh --run store` is
refused, exit 65: `store` is no Run key it writes). Run also holds the run's
`role` row, one at most, reading `manager` or `director`. It has two writers:
`state-open.sh`, in the seed it makes when given `--role` and on `--carry
--role`, which adds the row only when the carried copy has none; and
`state-stored-set.sh --run role <manager|director> --by <who>`, which sets it
once. With no row that writes one, the same value again changes nothing (exit
0, the record byte for byte as it was), and a different value is refused (exit
65), naming both. Only `--intervention dispatcher|person` replaces a different
value: a change from above, the dispatching session or a person. The row then
reads the new value, its Set by and Set say who and when, and the entry names
the old role, the new one and the source. `--intervention` with any other
source, or on any other key, is a usage error (exit 64). With it the write may
come before the run's find, as the rules rows' does; without it `--run role`
needs a found record, as every other Run key does. `--by` there is one line of
at most 80 characters. `state-open.sh --carry --role <new> --role-change-by
<who> --role-change-source <source>` replaces a carried row through that same
write. Its reader is `state-read.sh --session S --run`, which prints
`record/run` with no found record needed and exits 2, never an empty section,
when the read fails. The handover read prints it as `role`, or null. Every
worker's brief names that address as where to report, read from here by
`scripts/dispatch-worker.sh`, which refuses a dispatch while it is missing.
**Standing** holds the events only a person owns while they still bind: a
pause, a go-ahead (a release or another step allowed once), a relayed approval,
a standing answer. Owner is the person who decided it; Relayed by is who
carried it to you, blank when they told you directly. A pause names its
scope in On, `all` (the whole coordinator) or one unit as pick lists it
(`Feature 2`, `Milestone 2`, `ED1`, `#12`, `owner/repo#12`; `Feature 2` and
`Milestone 2` are one unit, so a pause written before the roadmap moved to
roadmap/v3 still holds it), and its resume
condition in Until: `lifted` (a person's resume ends it), `time <YYYY-MM-DDTHH:MMZ>` in UTC,
`merged owner/repo#n` or `tag owner/repo <tag>`. pick, the dispatch check, the
land check and the merge read every pause live (`scripts/pause-read.sh`) and
refuse what one holds; a pause whose condition reads met holds nothing, and
the coordinator ends its row. A go-ahead may name one unit in On: it lets that
unit through any pause until it is used and ended. A resume, a used
go-ahead or approval, or a withdrawn answer ends the row. An assignment is work a
person assigned outside the scope, named in On as an issue (`#12`,
`owner/repo#12`) or `release owner/repo <tag>`: pick lists it as a unit from
then on, at roadmap scope too, and its row ends once the work is done. A
rule binds the coordinator until it is ended, and its row is described under
Rule rows below. **Work** has a next
step for every holding and a row for any work no holding covers, a local
agent's above all: without its row a successor can't see it. Two kinds keep a
unit's later work, Item the unit as pick lists it: `decision`, a unit pick
parked on a person's decision, Who `decision <n>` (an unsettled entry); and
`follow-up`, a unit whose scoping alone merged, Who the pull request that
landed it (`owner/repo#n`) and Next step its execution. An Item has one row
per kind, and a holding's row for the unit replaces both. Two more kinds
belong to a milestone roadmap, `verdict-owed` and `rework`, and only
`roadmap-status.sh` writes them (see Milestone Verdicts below).

`scripts/state-stored-set.sh` is the only writer, and every change it makes is
written to the state and then told as an entry:

```
state-stored-set.sh --session S --run arguments|cap|coordinator <value> --by <who>
state-stored-set.sh --session S --run rules|briefs|friction|reports-to <value> --by <who>
state-stored-set.sh --session S --run role manager|director --by <who> [--intervention dispatcher|person]
state-stored-set.sh --session S --host <key> <value> [--host <key> <value>]...
state-stored-set.sh --session S --rule-files <file> --by <session>    (the start's, never yours)
state-stored-set.sh --session S --told <topic> --by <who>
state-stored-set.sh --session S --pending <topic> --by <who>
state-stored-set.sh --session S --pending-confirm <topic>=stopped|missing [--pending-confirm <topic>=...]... --by <who>
state-stored-set.sh --session S --standing <kind> [--on <scope>] [--until <condition>] --what <text> --owner <who> [--relayed-by <who>]
state-stored-set.sh --session S --standing rule --what <text> --source <form>
state-stored-set.sh --session S --end <s<n>> --by <who>
state-stored-set.sh --session S --intake <label> --by <who>
state-stored-set.sh --session S --work <item> --kind holding|local-agent|decision|follow-up --who <who> --next <text>
state-stored-set.sh --session S --done <item> [--kind <kind>]
state-stored-set.sh --session S --list
state-stored-set.sh --session S --rules [--id <s<n>>]...
state-stored-set.sh --session S --rules --counts
```

`--list` prints the three sections as JSON. On a session with no record it
exits 10; on a record the schema refuses (a Standing row of a kind this
plugin doesn't know, as a newer plugin's row looks to it, among others) it
exits 65 with nothing on stdout and the schema's reason on stderr, so a reader
can tell a record it can't read from a missing one. A write mode refuses
either one with 10. `coordinate-open.sh` reads the coordinator row this way:
a 65 stops a takeover at `failed=takeover_read`, before the fence, and the run
keeps its driver.

Write each when it happens: the arguments, the cap and your address at your
first start; a Standing row or a cap when a person's word arrives, wherever it
arrives (you write it, the person as owner and yourself as relayer); a holding's Work row once its dispatch is sent, which the record step
waits for and which also records its worker as told your address; a
local-agent row before the agent starts, `--done` when it lands. A Work row
whose holding is gone is dropped at the next write. A holding's Wakes are
brought up to date from this run's session log at each write, and its final
count is appended as an entry when its row leaves Work; the count is a floor,
since a wake inside the minute after a write, or one a crashed run logged
after its last write, isn't counted.

A re-brief records its worker by itself: the template's `rebrief_record` step
reads what you submitted at `rebrief` and writes `--told` when the worker was
messaged its new brief (which names your address), `--pending` when its
session is gone while niwa still lists its instance, and nothing when the
message was refused or no instance is left. `--told` for a pending worker
turns its `pending` row into a `told` one; `--pending` refuses a worker already
told or already pending, a carried row included.

A carried `pending` row is confirmed for the current address by
`handover-classify.sh` at reconcile, not by you: it reads each carried worker
and writes one `--pending-confirm` for every one it reads as stopped (its
session gone, its instance kept) or missing (its instance gone too), which
moves each row after the coordinator row and tells one entry naming them all.
`--pending-confirm` refuses, writing nothing, a worker with no carried row, one
already told, one named twice and a value other than `stopped` or `missing`.

**Rule rows.** A Standing row of kind `rule` is a rule that binds the
coordinator until `--end` ends it. It has no On and no Until, a blank Owner
and Relayed by, and a Source saying where its words come from, and it holds
nothing: pick, the dispatch check, the land check and the merge read pauses,
go-aheads and assignments only, whatever a rule's What says. `--standing rule
--what <text> --source <form>` writes one, its What one line of at most 400
bytes and its Source in one of four forms:

```
skill <owner/repo> <path> <commit>         a line of a skill's text
doc <owner/repo> <path> <commit>           a document a public host can name
pinned <label> sha256:<64 hex>             a file a Run rules or briefs row pins with that label and digest
inferred [brief <label> sha256:<64 hex>]   your own reading, with the brief you read it from
```

A path is relative, with no `.` or `..` segment and no leading `-`; a commit
is 40 hex. A rule takes no `--on` or `--until` (64), and `--owner` or
`--relayed-by` on one is refused (65), since its Source says who said it. The
checks run in this order, each refusal 65 with nothing written: the Source's
grammar and the row's columns; the What's 400 bytes; the caps, at most 120
rule rows, of which at most 60 read inferred (the event kinds count against
neither, so a pause can always be written); a `pinned` Source's Run row; then
the forge reads. For a `skill` or `doc` Source naming repository R at commit
C, on a public host R must be public; R's default branch must hold C (a
repository that doesn't exist and one that can't be read get the same
refusal); the file must exist at C; and the What must equal one of its
sentences under the normalized match. On a public host each `owner/repo` in
the What, the host excepted, must be public too: a 404 under the host's owner
is refused, one under another owner passes. A read that fails, runs past 10
seconds or can't be parsed exits 2. The entry reads `s<n> (rule): <What>.
Source: <Source>.`, and a stored row is never checked again. `--run
reports-to` or `--run cap` with `--inferred "<sentence>"` writes its value and
a bare `inferred` row quoting the sentence in one write, under the same
checks.

A row's class is worked out from its Source when it's read; no column stores
it. A row with no Source, an event row, reads `relayed`; `inferred` reads
`inferred`, with status `unconfirmed` and `confirm` true, since it waits for a
person; `skill` reads `skill-says`; `doc` and `pinned` read `charter`. The
Run `rules` rows read beside them: a `skill-` label `skill-says`, a
`workspace-` label `charter`, any other label `inferred`. `owner-said`,
`dispatcher-said` and `unreadable` belong to cited decisions, which
`--standing rule` doesn't write.

`state-stored-set.sh` reads rules two ways. `--rules` prints one JSON object
per Standing row in record order (`standing`, `kind`, `class`, `what`,
`owner` for a relayed row, `said`, `set`, `pointer`, `words`, `source`, `status`,
`reversal`, `confirm`), then, without `--id`, one per Run `rules` row
(`{run: "rules", kind, label, digest, class, said, pointer}`, the pointer
naming the `rules:<label>` host key, which isn't read). A pointer is where
the words are: a relayed row's entry (the row itself when no entry matches),
a `skill` or `doc` row's `{repo, path, commit}`, a `pinned` row's `{pinned,
digest}`, an inferred brief row's `{brief, digest}`, a bare inferred row's own
row. Each Standing object also carries `under_session_grant` and
`session_allows`: a row grants nothing itself, and these say whether it
stands under the session's niwa grant and what that grant allows. A pause, an
inferred or `pinned` row, a `skill` row citing a repository other than the
installed plugin's, and a `doc` row citing one other than the record's host
never do, and print `false` and `[]`; when any row may, `--rules` reads the
grant once with `niwa authority check`. No gate reads either field. `--id`
prints only those rows (one the record lacks is refused, 65). `--rules
--counts` prints seven `<class> <count>` lines instead, in the order
`relayed`, `owner-said`, `dispatcher-said`, `inferred`, `skill-says`,
`charter`, `unreadable`, counting every Standing row whatever its status and
each Run `rules` row, so `grep '^inferred '` gives the unsourced rules the
record holds. Neither mode writes.

The brief intake brings a brief's rules in once. You record the brief's path
with `--host briefs:<label> <path>`; `--intake <label> --by <who>` reads that
file once, never edits it and never prints its path. When a Run `briefs` row
already reads `<label> sha256:<its digest>` it writes nothing and exits 0.
Otherwise its candidates are the brief's sentences, less heading lines and
the renderer's Goal, Checkpoints, Read first, Acceptance criteria, Reporting
and Keep-alive sections. Each row whose Source is `inferred brief <label>`
with another digest, and whose What no candidate states, ends; each candidate
no remaining row (of any kind or Source) holds under the normalized match is
written as a rule row, Source `inferred brief <label> sha256:<digest>`. A line
that fails a What check (over 400 bytes, a home-directory path, a
token-shaped string, or on a public host a repository that isn't public) is
left out and named on stderr. When every line is taken it also writes the
`briefs` row, Set by `<who>`; when a cap stops it, it writes the rows up to
the cap and no `briefs` row, and exits 1 naming how many lines it couldn't
take, so a person says which rows to confirm or end. A read that fails exits
2 with nothing written. The rows, the ended rows and the `briefs` row go in
one write, then their entries: one rule entry per row, one end entry per
ended row, and `Run briefs <label> sha256:<digest> set by <who>.`

`scripts/state-handover.sh` reads the stored set back, with the holds, and
names its gaps: no arguments, cap or address; a live holding (dispatched, and
not merged and waiting for its teardown) with no Work row, or whose worker
has been neither told the current address nor recorded pending; a brief
`record/host` names as `briefs:<label>` whose digest no Run `briefs` row
carries (`brief-unread <label>`, its fix the intake, naming how many lines
the caps would leave out; a key whose file can't be read raises none). The
step's gate runs it at every start, so a replacement that writes its own
address can't go on until each live worker is told or pending. A pending
worker doesn't hold the gate; it is told when it can be. A record with no
`pending` row reads, checks and hands over as it did before the row existed.
A record written before these sections existed
has every gap at its first start under this version; fill them once. A
rotation's carry copies the three sections into the next rotation as they
stand.

### The Decisions section

Once the record holds a decision, one more key, `record/decisions`, holds the
identifier the next decision takes and one entry per decision the scope
opened. Every field of an entry is a string; Options and Evidence hold one
item a line:

```json
{"decisions": {"next": 1,
  "entries": [{"decision": "<n>", "round": "<times escalated>", "question": "<one line>",
               "options": "<one per line>", "state": "<proposed, coordinator-verdict, escalated or settled>",
               "source": "<worker <topic>, coordinator <topic> #<n> round <r>, dispatcher or self, then a stamp>",
               "verdict": "<empty, settle, escalate or hold>", "recommendation": "<one of the options>",
               "reason": "<its reason, or what a hold waits on>", "context": "<what is being decided and why now>",
               "problem": "<what is unresolved and why the coordinator can't settle it>",
               "grounds": "<scope, supplied-decision, reserved-step, outside-scope>",
               "target": "<a person or coordinator <topic>>", "owed": "<empty, escalation, withdrawal or reply>",
               "asked": "<YYYY-MM-DDTHH:MMZ>", "evidence": "<one line per item: <time> <source> <stamp>: <text>>",
               "outcome": "<outcome and reason>", "decided_by": "<who decided>", "updated": "<YYYY-MM-DDTHH:MMZ>"}]}}
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

A record written before the section existed has no key. The key appears at
the first decision and stays: `next` only goes up, so an identifier is never
reused, and a key holding `next` 1 and no entry is never written. A stamp, `[<run> <kind> <seq>]`, names the run (the
UTC stamp in its session's name) and the visit that caused a write. `@` is
encoded in the text fields so a record never mentions anyone, and those fields
refuse a private repository, a home-directory path and a token-shaped string.

Only `state-decision.sh` changes the section: `state-write.sh` refuses a state
whose section differs from the live record's, and `state-open.sh` refuses a new
record that carries one. A rotation's carry copies the unsettled entries and the
same `next` into the next rotation. A roadmap record can't close while
an entry is unsettled.

**A record moved from GitHub.** A record imported from a GitHub record may
carry archived entries: their identifiers in `archived`, their rows in
`decisions` entries on the record, and the archiving run's stamps in `kept`.
Nothing archives an entry any more. Evidence, an answer or a worker's citation
naming an archived entry restores it first, from the latest unedited
`decisions` entry holding its row, in the same write that records the arrival,
and its kept stamps go back to its row. A withdrawal reaches only the entries
in the section. `next` is unchanged by a restore.

**Updating.** Read the state (`rs_record`), change the JSON, keeping its
`written` time, and hand the whole next state to the record's write script
in a file (`state-write.sh --state-file <file>`), never by writing the
session's keys by hand. Build the file in a private directory of your own,
readable only by you. The write script compares the state's `written` time
with the live record's, refuses with `record-changed` (exit 12) when someone
wrote since, and stamps its own time on what it writes. Every pull request in
the record is a link. Follow the host repository's conventions (its
CLAUDE.md) for commit messages and bodies.

## Entries

The section keys are the record's state: what is true now, rewritten whole. Its account,
what happened and why, is a stream of entries, each one key of the run's
session, `record/entries/<n>` (`<n>` six digits, one above the highest there),
written only by `scripts/state-entry.sh`:

```
state-entry.sh --session <session> --text-file <file> [--kind <kind>] [--on <owner/repo#n>|none]
```

It stamps the entry from the host clock in UTC to the second and writes
`{n, stamp, kind, text}`. The record's other writers write their own kinds
with `--kind`. The milestone steps write three: `milestone-verdict`,
`goal-fit` and `milestone-failure`, whose lines are under Milestone Verdicts.
A record moved from GitHub may also hold `decisions` entries, the archived
Decisions rows (see Decisions). Each is written with a marker beside it,
`record/archive/<n>`, so a reader of the archived rows lists the markers and
gets those entries alone. A record imported before the markers has none, and
its reader reads every entry instead, as it does when a cited row is in no
marked entry.

An outward entry, one that a reader outside the coordinator may read on
GitHub, names the item it concerns with `--on`: a `cost` entry the holding's
pull request or the unit's issue, a `goal-fit` entry the pull request its
first line names. It is posted as a comment on that item only when the
item's repository, public or private, opts in with `## PR Workflow Content:
include` in the CLAUDE.md on its default branch (read through
`scripts/pr-workflow-content.sh`). Otherwise the append keeps the session
entry, posts nothing and prints its key, as `--on none` does (exit 0, the
reason on stderr), and `--repost` is refused (exit 65), the entry staying in
the session. `--on none` writes the session entry and posts it nowhere; a
`milestone-verdict` or `milestone-failure` entry is written that way and
reaches its roadmap pull request only through `roadmap-status.sh`, under the
same opt-in (The roadmap edits). A posted entry reads:

```markdown
<!-- coordinator-record-entry v1 kind=<kind> -->
**<YYYY-MM-DDTHH:MM:SSZ>** (host clock) <kind>

<the text>
```

and the comment's URL is kept in `record/posted/<n>`, so a retry posts it
once. Before it posts, the text is scanned against the destination's
visibility: on a public destination it may name no private repository,
home-directory path or token-shaped string, and `@` is written encoded, so an
entry never mentions anyone.

An entry is never rewritten. Write one when something happens
that a successor would need the story of: what you dispatched and why, what a
person told you, what you decided and on what evidence.

`state-entry.sh --session <session> --list` reads the stream back as JSON,
oldest first, with each entry's stamp, kind and text. When a person tells you
something, write it into the record yourself.

Anything a check or a successor acts on stays in the state; an entry is
its account, never its only copy. GitHub limits how fast comments are
created; at most one post per outward entry stays far inside it, and a refused post
(exit 14, the entry written but not posted) is finished once, later, with
`state-entry.sh --repost <n> --on <item>`, never in a loop.

### The alignment entry

A director's call on a lane pull request is an `alignment` entry. It stays in
the session, yet it names its pull request with `--on`, the one kind kept in
the session that takes it (any other exits 64 on `--on`):

```
state-entry.sh --session <session> --kind alignment --on <owner/repo#n> --text-file <file>
```

Its first line must name the `--on` pull request; the pull request must be in
the host or a holding's repository; on a public host its text is scanned as
any entry kept in the session is; and it is never posted, whatever the
repository's opt-in. `--on none` and no `--on` are refused (65). The text is
at most 16 KiB, these seven lines in this order with no blank line:

```
Alignment: <owner/repo#n> at <40-hex head> -- <fits|fits with follow-ups|diverges>
Read: <full|one-line>
Sources: <none | <source>; <source>; ...>
Reason: <one line>
Evidence: <none | <n> <met|not met>; ...>
Follow-ups: <none | new: <title>; ...>
Action: <merge|recommend|hold|none>
```

A source is one of `roadmap <path> at <40-hex> <unit> clause <n>`, `strategy
<path> at <40-hex> <section heading>`, `standing s<n>`, `decision <n>` or
`lane <holding> <owner/repo#n | path>` (another lane's open pull request, or
the document or path its rows name). A reader splits each line once on `: `
and a list on `; `. `state-entry.sh` refuses (65, nothing written) a missing,
extra or reordered line; a first line whose pull request isn't `--on`; a head
that isn't 40 hex; a value outside each line's set; `fits with follow-ups`
with Follow-ups `none`, or another call with a follow-up; `diverges` with
Sources `none`; `Read: one-line` with a call other than `fits`; `Action:
hold` with a call other than `diverges`, or `diverges` with another Action.

Write a call with `scripts/alignment-call.sh --session S --on <owner/repo#n>
--text-file <file> [--receiver <address>]`, which writes the entry through
`state-entry.sh` and, for `diverges`, places the `align-` hold and prints its
message (The Holds section). A second `diverges` call while a director's hold
on the pull request stands, and one on a merged pull request, write the entry
and place no hold. The pull request's state, the director's address and the
receiver are read before anything is written, so a call that can't place its
hold writes nothing. A `fits` or `fits with follow-ups` call then runs the
guarded lift on the pull request's `align-` holds and prints a lift message
for each it lifts (The Holds section).

### The refusal entry

When a director's land check stops a head that has no alignment call, the
director records it in one entry of the plain `entry` kind, whose first line
is:

```
Refused: no-alignment-call <owner/repo#n> at <40-hex head>
```

It is written once per pull request and head: when the record already holds
that line for the head, a later refusal of the same head writes nothing, so
the count is of heads stopped, not of visits. It adds no entry kind and no
grammar to `state-entry.sh`.

### Reading the calls back

`scripts/alignment-read.sh --session S [--since <YYYY-MM-DDTHH:MM:SSZ>]` is
the one read of a director's calls, and it writes nothing. It prints one JSON
object with seven keys:

- `calls`: every `alignment` entry, oldest first, with its entry number, its
  stamp, the first line's pull request, head and call, and the other lines,
  Sources, Evidence and Follow-ups as lists split on `; ` (`none` is an empty
  list). `standing` is true only for the latest call on its pull request and
  head, so a call on an older head never stands for a newer one.
- `merges`: each merged lane pull request owed a call (one the manager wrote,
  or one that finishes a unit: a `unit=` line names it, it is a milestone
  verdict pull request, or it changes a roadmap or strategy document), with
  its merged head, merge time, the latest call's value for that head and its
  review: `reviewed` (a call for the merged head stamped at or before the
  merge), `after merge` or `unreviewed`. A pull request a `worker=` line
  names that finishes no unit is `manager-reviewed` instead.
- `recommendations`: each call whose Action is `recommend`.
- `holds`: each `align-` hold, with the latest `diverges` call at the head its
  name carries and that call's reason, and a state: `lifted`, `merged while
  held`, `closed while held`, `releasable` (the guarded lift's three
  conditions hold) or `standing`, flagged `needs_re_read` when the live head
  has no call. A standing or releasable hold carries the latest report that
  names it, or `unconfirmed`.
- `open`: each open lane pull request at its live head, with the standing
  call's value for that head or `none`.
- `refusals`: how many refusal entries the record holds.
- `gaps`: each earlier session of the run's lineage whose log couldn't be
  read.

The lane pull requests are those the calls name, the Holdings rows link and
the `align-` holds are on, and those the director's `report` and `progress`
events name, in their `pull_request`, as links in their message, or in the
`unit=`, `open=` and `worker=` lines of the result block, from every session
of the lineage. Whether a unit finished, and whether a worker wrote a pull
request, is read from those lines alone. With `--since`, `calls`, `merges`,
`recommendations` and `refusals` keep to what is stamped or merged after the
stamp, while each judgment is still made against every call; `holds` and
`open` stay whole. The script's header has the full rules and exit codes.

## Where State Lives

Every script reads the record's state through `scripts/state-read.sh`, from
the run's session: its `rs_record` assembles the state from the keys and
checks it;
`rs_record_api` is the land check's and the merge's read under their deadline;
`rs_facts` gives one holding's repository, pull request, branch, verified head,
holds and pauses. The find writes `coord/source.json` reading `session`, which
a later start's resume reads.

The record's sections live in the run's own session, under `record/`:
`record/meta` (the scope, the written time, a pending mark a write sets
while it is part way through, `standing_used`, the highest Standing id
given out, and the run's template compat and fingerprint), one key per section (`record/holdings`,
`record/deferrals`, `record/side-effects`, `record/reversals`, `record/holds`,
`record/run`, `record/standing`, `record/work`, `record/decisions`), each in
the JSON form The Keys shows, one `record/entries/<n>` per entry
and, for an entry also posted to GitHub, the comment's URL in
`record/posted/<n>`. A discipline rotation adds `record/rotation` and
`record/reasoning`. A write is refused, changing no key, from a run that isn't
the scope's live one or after a `koto next --to` (10), when the state changed
since it was read (12), or when it changes a section its writer doesn't own
(65). A person reads the keys through koto's session view, `koto context get
<session> <key>`.

Two more things live only in the session. `record/host` holds host facts, never
sent to GitHub: where the crash set's files are
(`rules:<label>`, `briefs:<label>` and `friction`, each an absolute path) and,
after an import, where the state came from (`source_workspace`,
`source_session`, `template_hash`). Only `state-stored-set.sh` writes it: `--host`,
which the opener calls after an import, and `--rule-files`, which keeps the
`rules:<label>` key of each `skill-` and `workspace-` row. And each holding keeps its pushed head
beside its row in `record/holdings` (`pushed_head`, 40 hex), set with
`state-holding.sh --topic T --pushed-head <sha>`, by `holding-link.sh` when it
links a pull request and by the report check when a report reads a new head;
`rs_record` hands it over apart from the state. The keys move with the session: a resume
keeps them, a carry copies every `record/` and `legs/` key into the new run,
and an import brings them all from the other host.

Each worker leg is a key of the coordinator's session,
`legs/<request>/<leg>`: the worker's topic, the leg's templates and pinned
inputs, the bound session's name once one attaches, and its result once read.
`dispatch-worker.sh` writes it at dispatch (`open`) and when a new leg
replaces it (`replaced`) or a launch fails (`spent`); `wait-target.sh` adds
the child and the end (`taken` with the result, or `spent`). After an import,
a leg whose request this host's store doesn't hold gets its end from
`reconcile-legs.sh`: re-legged by `dispatch-worker.sh --releg-imported`, which
marks the old key `releg-pending` and then `relegged`, naming the new request,
and writes the new request's key `open` with `from` naming the old one; or
`unwatchable`, its holding moved to message. dispatch-common.sh lists the
states and their meaning.

A coordinator's state lives outside any directory the workspace manager
converges, in two places: the koto session's journal on this host, and the
record's keys in the same session. Keep no tools directory beside it. A local
script for record entries, a snapshot copy of the state, archive files,
standing answers in a file and progress facts all have homes in the skill:
`state-entry.sh`, the record's keys, the entries, the record's sections, and
`progress-view.sh` over pick's facts.

## Writing a Landed Feature Back to the Roadmap

When a roadmap feature's last pull request has merged (or, for a spike or a
design, its acceptance call is made), tick `wait` with `event: landed` and the
feature's tag as `unit`, and at `roadmap_status` run:

```
roadmap-status.sh --session <session> --unit "<tag>" --outcome "<what landed>"
```

It opens a pull request on the roadmap's repository that sets the feature's
Status to Done, writes `--outcome`'s text on a `**Delivered:**` line after it
(replacing an earlier one), removes its Needs line and regenerates the
generated sections, changing nothing else: the feature's `**Outcome:**` line
is the promise and is never touched. The flag is named `--outcome`, but its
text fills the Delivered line. In a public roadmap the text names only
public pull requests. It adds a Side effects row:

```json
{"action": "roadmap-status", "target": "<tag> [#<n>](<url>)", "verified_head": "",
 "attempted": "<YYYY-MM-DDTHH:MMZ>", "how_to_confirm": "the roadmap on <default> reads <tag> Done"}
```

While the row stands, pick lists the feature as `landed` and no brief renders
for it; it is not Done for its dependents until the roadmap says so. Only one
is pending at a time. Once the roadmap on the default branch reads Done
(annotated or not, as in `Done -- shipped in #12`),
`roadmap-status.sh --confirm "<tag>"` removes the row; a pull request closed
unmerged is cleared with `--drop "<tag>" --reason "<why>"`. The skill never
merges the roadmap pull request.

All of this is a feature roadmap's. The script reads the roadmap's
frontmatter first, and on a milestone roadmap (`schema: roadmap/v2` or `roadmap/v3`) the same
`--unit` call opens nothing and marks the milestone's verdict owed, as the
next section says.

## Milestone Verdicts

On a milestone roadmap a milestone reads Done only through a checked verdict,
and Done is taken back only through a checked failure. Each is an entry in the
record, checked by `scripts/milestone.sh` against the roadmap and written by
`state-entry.sh` with its own kind, and each roadmap edit is a pull request
`scripts/roadmap-status.sh` opens, posts the entry on when the host opts in,
and never merges. The steps are the
`milestone_verdict`, `goal_fit` and `milestone_reopen` states of the template.

### The verdict owed

`roadmap-status.sh --unit <tag>` on a milestone roadmap refuses a tag that
isn't a milestone with Evidence, one that already reads Done or Dropped, and
one with a follow-up row; otherwise it writes this Work row and prints
`verdict-owed <tag>`:

```json
{"item": "<tag>", "kind": "verdict-owed",
 "who": "<the topic of the holding whose unit is <tag> or `<tag>: <title>`, or none>",
 "next": "verdict owed since <YYYY-MM-DD>", "wakes": "0", "updated": "<YYYY-MM-DDTHH:MMZ>"}
```

Run again while the row stands, it prints the same and writes nothing, which
is how a deferred verdict comes back to the verdict step. Only
`roadmap-status.sh` writes or removes the row (the write core refuses any
other writer's change to it, and `state-stored-set.sh` refuses the kind), and
`--confirm` removes it once the verdict's edit is on the default branch. Pick
reads the milestone `verdict_owed` while it stands and lists it as a verdict
to give, and the dispatch check (`verdict-owed <tag>`, code 49),
`dispatch-worker.sh` (exit 10) and close-out refuse it.

### The verdict entry

Written with `state-entry.sh --kind milestone-verdict --on none`, at most 16
KiB, these lines in this order, with one blank line before `Evidence:` and one before
`Strategy fit:`:

```
Verdict: <tag> -- <changes needed|verified with follow-ups|verified>
Checked by: <a login, a session name or a plain name, 60 characters at most>
Checked on: <YYYY-MM-DD, no later than today>
Source: <the roadmap's path> at <the 40-character commit it was read at>
Work checked: <owner/repo#n, owner/repo#n | none>

Evidence:
1. <held|not held> -- <what showed it>

Strategy fit: <fits|does not fit> -- <why>
Follow-ups: <none | new: <title>; amend <tag>: <what>>
Changes needed: <none | what must change>
```

with one Evidence line per clause, numbered in the roadmap's order.
`milestone.sh check-verdict <roadmap at Source> <tag> <entry> [--worker <topic>]`
refuses a missing or reordered line, a clause count other than the
milestone's, a future Checked on, and a verdict that breaks its rules:
verified needs every clause held, `fits`, no follow-up and no change;
verified with follow-ups the same with at least one follow-up; changes needed
a clause not held or `does not fit`, and a change named. With `--worker`, a
Checked by containing that topic, in any letter case, is refused: the worker
that did the work never checks it. `--verdict` passes the verdict-owed row's
`who` as `--worker`, and nothing when it is `none`.

### The goal-fit entry

On a milestone run, the land check's `coord/land.json` carries `milestone:
{tag, evidence}` (the holding's milestone and its clauses on the default
branch), or `milestone_error: <why>` when that read failed. Goal fit writes
this entry with `--kind goal-fit --on <the pull request>`, which also posts it
there only when that pull request's repository opts in with `## PR Workflow
Content: include`, and otherwise keeps it in the session:

```
Goal fit: <owner/repo#n> -- <tag>
Fit: <fits|fits with follow-ups|gap>
Clauses: <n, n | advances none>
Rationale: <what in the pull request decided it>
```

`milestone.sh check-goal-fit <roadmap> <tag> <entry>` refuses a clause number
the milestone lacks or names twice, another tag, a pull request not shaped
`owner/repo#n`, a Fit outside its values and an empty Rationale. `advances
none` is recorded, not refused, and the `clauses` field `goal_fit` takes with
it routes nothing.

### The failure entry

Written with `--kind milestone-failure --on none`, these five lines:

```
Failure: <tag>
Reported by: <a login, a session name or a plain name, 60 characters at most>
Seen on: <YYYY-MM-DD, no later than today>
Clause: <n>
What was seen: <one paragraph, at most 600 bytes, no URL or link>
```

`milestone.sh check-failure <roadmap> <tag> <entry>` checks it against the
roadmap on the default branch: the milestone must read Done there, and the
clause must be one of its Evidence clauses. What was seen gets the rework
row's shape, because the milestone's next brief quotes it.

### The roadmap edits

`--verdict` and `--reopen` take the entry by its number, `record/entries/<n>`
as `state-entry.sh` printed it, which must be of the kind each takes and
posted nowhere yet. Either refuses (exit 65, nothing opened) while any roadmap
pull request is pending.

```
roadmap-status.sh --session <session> --verdict "<tag>" --entry <n> [--follow-ups <file>]
roadmap-status.sh --session <session> --reopen "<tag>" --entry <n>
```

Each commits the edit without its Progress lines on a new branch, opens the
pull request with the entry in its body, writes its Side effects row, posts the
entry as a comment on that pull request (`state-entry.sh --repost <n> --on
<host>#<pull request>`, with the same content checks) and then commits the
Progress lines naming that comment. When the post or the second commit fails
it exits 14 naming the pull request; run again with the same entry, it finds
its row, posts once and pushes only the missing commit, so no second pull
request opens.

The entry is posted only where `state-entry.sh` would post it: when the host
opts in with `## PR Workflow Content: include` in the CLAUDE.md GitHub serves
from its default branch, or when `record/posted/<n>` shows an earlier run of
the same edit posted it. Otherwise it stays in the session: nothing is
posted, the pull request's body says so, and the Progress lines cite
`entry <n>` where the comment's URL would go.

`--verdict` needs the tag's verdict-owed row, requires the default branch to
contain the Source commit, and runs `check-verdict` against the roadmap at
that commit. It refuses a tag that already reads Done on the default branch,
and one whose Evidence there differs from its Evidence at Source, since the
clauses are numbered by position. A verified verdict of either kind sets
Done, removes Needs and appends the Work checked pull requests to Delivered;
changes needed leaves Status and Delivered as they are. A verified with
follow-ups verdict needs `--follow-ups`, at most 32 KiB, one `### <tag>:
<title>` section per follow-up with non-empty Outcome, Evidence, Left open and
Dependencies (Needs optional). A `new:` follow-up's section is its title under
a tag the roadmap doesn't use, added after the last milestone, Not started.
An `amend <tag>:` section keeps that milestone's title and Dependencies and
replaces its Outcome, Evidence and Left open. The file is refused for a
section the verdict doesn't name, a follow-up with no section, a missing
field, a control character or tab, a token, a home-directory path or a
staging path. Every verdict appends to Progress:

```markdown
- <Checked on>: <tag> -- <verdict>, checked by <checker> (<cite>, <hash8>)
```

and an amendment adds `- <Checked on>: <tag> amended -- a follow-up of the
verified verdict on <tag> (<cite>)`. cite is the posted entry's comment URL,
or `entry <n>` for an entry kept in the session, and hash8 is the first eight
hex digits of the entry's sha256.

`--reopen` runs `check-failure` against the roadmap at the default branch's
head, sets the milestone In progress, leaves Delivered, Outcome and Evidence
as they are, and appends:

```markdown
- <Seen on>: <tag> -- reopened: clause <n> failed, reported by <reporter> (<cite>, <hash8>)
```

It prints the pull request's URL, then `held-dependent <tag> <worker>` for
each milestone whose Dependencies name this one and that a holding covers.

Each edit opens one pull request with the whole entry in its body, so the
reviewer who approves it reads the judgment, and writes a Side effects row:

```json
{"action": "milestone-done", "target": "<tag> [#<n>](<url>)", "verified_head": "", "attempted": "<YYYY-MM-DDTHH:MMZ>",
 "how_to_confirm": "the roadmap on <default> reads <tag> Done (entry <n>)"}
{"action": "milestone-verdict", "target": "<tag> [#<n>](<url>)", "verified_head": "", "attempted": "<YYYY-MM-DDTHH:MMZ>",
 "how_to_confirm": "the roadmap on <default> carries its entry's comment in Progress (entry <n>)"}
{"action": "milestone-reopen", "target": "<tag> [#<n>](<url>)", "verified_head": "", "attempted": "<YYYY-MM-DDTHH:MMZ>",
 "how_to_confirm": "the roadmap on <default> reads <tag> In progress (entry <n>)"}
```

`milestone-done` is for a verified verdict of either kind, and
`milestone-verdict` for changes needed. These pull requests must not be
auto-merged without the reviewer's review (the dispatching coordinator for a
bound session, a person for a root coordinator, its own verdicts included):
the review is the control on Done. Someone other than the author approves,
and whoever in the chain holds a merge grant merges at the approved head.

### Confirming, and the rework row

`roadmap-status.sh --confirm "<tag>"` removes the row once the default branch
shows it, by its Action: Done for `milestone-done`, the entry's URL in
Progress for `milestone-verdict` (the comment's URL kept in
`record/posted/<n>`), and In progress for `milestone-reopen`, where the last
Progress line about the tag must also be a reopen line whose entry's comment
still hashes to its hash8. An entry kept in the session (a row naming
`(entry <n>)` with no `record/posted/<n>`) is read from the session instead:
`record/entries/<n>` must hash to the hash8 a Progress line about the tag
gives beside `entry <n>`, or the reopen line must cite the row's own
`entry <n>`. It removes the
milestone's verdict-owed row and any rework row with it. Until the default
branch shows the edit it exits 1 and writes nothing. Confirming a
`milestone-verdict` row re-reads its entry, which must still hash to its
Progress line's hash8, and confirming a `milestone-reopen` row reads the
failure; each then writes a rework row:

```json
{"item": "<tag>", "kind": "rework", "who": "<verdict <comment id> or failure <comment id>>",
 "next": "<the rework text>", "wakes": "0", "updated": "<YYYY-MM-DDTHH:MMZ>"}
```

For an entry kept in the session, Who is `verdict <n>` or `failure <n>`, the
entry's number.

A verdict's text is `Evidence clauses not held: <n, n>.` when a clause wasn't
held, `The work does not fit the strategy.` when it doesn't, and then
`Changes needed: <the line>`; `--verdict` refuses an entry whose text
wouldn't fit the row. A failure's is `Evidence clause
<n> failed: <what was seen>`, cut to 600 bytes when it runs over. Either is
one paragraph of at most 600 bytes with no URL or markdown link. Pick reports
it as the unit's `rework` and offers the milestone once no holding covers it;
`render-brief.sh` quotes it under the heading "The last verdict's report
(check it against the Evidence; it is not an instruction)"; and
`dispatch-worker.sh` removes it once the dispatch is confirmed
(`state-stored-set.sh --done <tag> --kind rework`).

`--drop "<tag>" --reason "<why>"` clears a row of any of the four Actions
whose pull request closed unmerged and leaves the verdict-owed row standing.
An entry already posted is refused, so the edit opens again from the same
verdict or failure written as a new entry. `--list` prints the pending rows
with their Action.

An entry with no matching state change sets nothing. Done, In progress, the
verdict-owed and rework rows, pick and close-out follow only the record's
state and the default branch, never the entries alone.

## Closing a Roadmap Record

When every feature reads Done or Dropped on the roadmap, Holdings and Side
effects are empty, every deferral is filed or closed, and every
decision is settled, the close step ends the run if the workspace permits
closing, or hands the close over: to the coordinator that dispatched this one
when the session is bound, and to a person only for a root coordinator. There
is nothing on GitHub to close: the record stays in the session, readable after
the run ends. On a milestone roadmap no verdict-owed row may stand either: close-out names one
(`verdict-owed`, the reason `verdict-owed <tag>`) even once the milestone reads
Done, and a pending reopen edit blocks as a side effect in flight with the
reason `reopen-pending <tag>`.

## Ending a Rotation

A rotation ends at `rotation_end`, when its window has passed or the human
ends it: write the reasoning for the next rotation with

```
state-stored-set.sh --session <session> --reasoning-file <file>
```

prose of at most 16 KiB about what this rotation learned that the sections can't
say. Write it fresh each rotation; never append to the previous rotation's
text, or it grows into a standing protocol. Writing it closes the rotation.
Nothing is committed and no pull request is opened.

The next rotation's start finds this one ended and carries it
(`predecessor_carry`, `state-open.sh --carry`): Holdings, Deferrals, Side
effects, Reversals, Holds, Run, Standing and Work, the unsettled Decisions
entries and the next decision number, into its own session, naming this one
as its predecessor in `record/rotation`. Its reconcile reads this reasoning,
attributed to this rotation and not re-checked, and its open deferrals are its
own to dispose of before its first dispatch.
