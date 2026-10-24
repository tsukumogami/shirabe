# Unit cost entries

Every unit the coordinator dispatches gets one `cost` entry on its record.
The teardown pass writes it between the archive and `niwa destroy`, through
`scripts/unit-cost.sh capture`; a unit niwa removes outside the pass gets
its entry from the sweep described under [Capture after a
removal](#capture-after-a-removal). Nobody runs anything for it, and nothing
about the teardown depends on it. This page says what the entry holds, how
each figure is defined, how a removed unit is captured, and how to read
entries back.

## Where it comes from

The capture reads four things and writes two:

- the teardown archive the pass just made: the unit's koto sessions
  (`koto/<session>/`), their verdict ledgers, the job's `state.json`, the
  pass's `teardown.json`, and `claude-projects/`, every Claude Code project
  directory of the instance (below);
- the unit's koto request, which stays on the host after teardown (koto's
  request directory, `KOTO_REQUESTS`; found through a session's
  `request-leg.toml`), for dispatch;
- GitHub, read only: each of the holding's pull requests' merge time and
  head branch, its commits, each head's own workflow runs and every earlier
  attempt of each; each linked pull request's state, times, merge commit,
  branches and head owner, for credit and `opened`; the state of the pull
  request the holding's Pull request cell names; and repository visibility;
- the record's run facts and the Holdings row for the unit's topic, for the
  milestone, else the leg key the dispatch wrote in the coordinator's
  session.

**The archive's layout.** The pass copies each Claude Code project
directory of the instance whole into `claude-projects/<directory name>/`:
the one named for the instance path (every character outside `[A-Za-z0-9]`
made `-`) always, and one named for it followed by `-` (a worktree or a
clone under the instance) only when at least one line of a `.jsonl` file in
it carries a `cwd` at or under the instance path and none carries one
outside it, so a sibling instance whose name extends this one's is never
taken. It never follows a symbolic link, and the archive's README lists
each directory taken, each skipped with its reason (`cwd outside the
instance`), and each link skipped. A **main session transcript** is a
`<session id>.jsonl` directly in one of those directories. The worker's
session is the torn-down job's: `job/state.json`'s `sessionId`, else
`teardown.json`'s `job.session`. An archive made before this layout holds
`transcript/` instead (the worker's transcript and its subagents); the
capture still reads its worker row from there.

It writes `unit-cost.json` into the archive (to a temporary name, then
renamed; it is not in the MANIFEST, and the archive's README says so) and
posts one `cost` entry through `record-append.sh`. A record that already
holds a `cost` entry with the same capture key, or with the same non-null
`"niwa.dispatch.id"`, gets nothing new, so the pass and a removal's sweep
never leave two entries for one unit. The list and the post run under one
host lock, `.post-lock` in the removals directory (below), which every
capture takes: a capture that finds it held by a live process waits inside
its list and post bounds, one whose holder is gone or older than 60 seconds
takes it over, and a removals directory that can't be used leaves the
capture posting with only the list check, saying so in one line.

The entry is kept in the coordinator's session (`record-append.sh --on
none`): the unit's own pull requests and issues carry nothing about the
tools. A repository opts in to
today's placement with the header `## PR Workflow Content: include` in its
`CLAUDE.local.md` or `CLAUDE.md` (#1114), read only through
`scripts/pr-workflow-content.sh`. `record-append.sh` makes that check itself
for every entry it posts with `--on`, this one included: it fetches the
repository's `CLAUDE.md` from GitHub into a directory of its own and hands
that to the reader, since it has no checkout, so an opt-in only in an uncommitted
`CLAUDE.local.md` reads as omit here. Only the reader's `include` restores
placement; a missing reader, a failed read or any other answer keeps the
entry in the session. With `include`, the entry is posted with
`record-append.sh --on` on the holding's pull request (its Pull request
cell, else the first pull request of the sealed verdict), else the unit's
issue (a Unit of `#n: ...` on the host, or `owner/repo#n: ...`), else
nowhere. The text is checked against the destination's visibility when it
is posted, so an entry naming a private repository is not posted on a
public pull request; it stays in the session, and in the archive.

The capture's last line on stderr says where the entry went:

- `unit-cost: kept the cost entry in the session: it is posted on no pull
  request or issue unless the repository opts in`;
- `unit-cost: posted the cost entry on <owner/repo#n>`;
- `unit-cost: the record already holds this unit's cost entry`;
- `unit-cost: the post failed (record-append exit <n>)`;
- `unit-cost: the post did not finish in time`;
- `unit-cost: the entry could not be computed`.

The capture has 90 seconds for its reads, each GitHub read bounded on its
own, and the pass stops it at 120. Whatever it hasn't taken when time runs
out is posted as `not recoverable` with reason `time limit`; a missing
source, a failed read or input outside its expected shape does the same with
its own reason. Either way the teardown goes on exactly as it would have.

## Definitions

Every figure is in one of four states. **measured**: read from its source
by the definition below. **bound**: a lower bound, never the figure itself.
**not recoverable**: the source is gone, unreadable or out of time; the
entry's `missing` list says which and why. **not applicable**: the figure
means nothing for this unit. Nothing is estimated.

- **Dispatch**: the earliest of three: the `created_at` of the unit's
  koto request (requests a session inside the unit made, a `/deliver`
  asking its `/scope` say, are not the dispatch; the earliest of the rest
  is), the job's `createdAt`, and the first event (the earliest `timestamp`)
  of every main session transcript in `claude-projects/`, since a unit can
  run as several jobs and the torn-down one need not be the first. The
  request wins a tie. `source` is `koto-request` when the request is the
  earliest, else `job-state`, which covers a job's start read from its
  record or from its transcript. `dispatch.jobs` counts the main session
  transcripts read, relocated copies included. With none of the three, not
  recoverable. A request id outside koto's grammar makes it not
  recoverable, since the request it names can't be read.
- **Green**: among a pull request's heads, in commit order, the first where
  every workflow run on that head (each run's final attempt) concluded
  `success` or `skipped`; green is the latest finish time among those runs.
  A unit with several pull requests is green when the last of them is. If
  the first such head still has runs that haven't concluded (none failing),
  green is `bound` at the latest finish so far.
- **Merge**: the pull request's merge time; for several, the last.
- **State time**: within one koto session, a state lasts from the
  `transitioned` or `rewound` event that entered it to the next such event.
  A state's total is the sum of its visits. Nothing after the session's
  first entry into `done` counts; a session with no `done` ends at its last
  event.
- **Unit sessions**: the archived sessions run from the `work-on` template
  (a plan's children, or a single issue's session). The others feed only
  plan shape and the per-session state totals.
- **Writing code**: the unit sessions' total time in `implementation`. It
  includes the worker's test runs; no source separates them.
- **Review**: the unit sessions' total time in `scrutiny`, `review` and
  `qa_validation`.
- **Outside share**: one minus writing code divided by dispatch to green.
  **Review share**: review divided by dispatch to green.
- **Session span**: from a session's first state change to its first entry
  into `done` (or its last event). Its implementation and review shares
  divide its own time in those states by its span.
- **Summed session spans**: every unit session's span added up. Where
  sessions overlapped it exceeds the wall-clock it covers; it is never
  wall-clock.
- **Minutes per unit**: for a unit that ran a plan, the mean of its unit
  sessions' spans.
- **Panel rounds**: per session and per panel in its verdict ledger
  (`ctx/verdict_ledger.json`, `.history[]`), the distinct rounds beyond the
  first, summed over the unit sessions. Not recoverable when no unit session
  has a ledger.
- **Failing heads**: the pull request heads, up to and including the green
  head, on which any attempt of any workflow run concluded `failure` or
  `timed_out`. A head that failed once and passed on a rerun counts;
  `cancelled` doesn't. Each head's runs are read on their own
  (`actions/runs?head_sha=<sha>`), oldest head first, through every page of
  100 the head holds, stopping after the green head, so a pull request with
  many pushes has every head counted. When a head's runs can't all be read,
  the count is a floor: `bound` over the heads read, with `missing` naming
  `failing_heads` and the reason, `time limit` (the read budget ran out),
  `read failed`, `invalid input` (a page outside its shape) or `entry size`
  (a head past 50 pages). Green is not recoverable when its head wasn't
  reached. A reader summing failing heads leaves `bound` values out, or
  reports the sum as a floor.
- **Tokens**: assistant lines with a string message id and a usage object
  (a line without either isn't counted), each message once by its id, each of the
  four classes (input, output, cache creation, cache read) at the largest
  value written for that id, since a streamed message is written several
  times with growing usage. `worker` is the worker's session: its main
  session transcript and every `.jsonl` under `<session id>/subagents/`, in
  every directory of `claude-projects/`. `nested` is every other `.jsonl`
  there: other jobs' transcripts and their subagents, workflows, and
  relocated copies (the transcript Claude Code writes under a new session
  id when a session moves into a worktree, repeating its earlier messages).
  Each message id counts once across the whole archive: the worker's files
  are read first, and an id the worker row holds is never counted in
  `nested`. An archive made before `claude-projects/` has no whole nested
  row to read: `nested` is not recoverable, `no source`.
- **Credit**: `pulls` holds the holding's merged pull requests (the sealed
  verdict's) and every other pull request the unit made. A `pr-link` record
  in `claude-projects/` (`prRepository`, `prNumber`, `timestamp`) names a
  candidate; one is credited when GitHub reads it, at capture, as meeting
  all four of:
  1. its base repository's owner is the holding repository's owner,
     case-insensitively;
  2. its head repository's owner is the same: not a fork;
  3. it was created at or after dispatch, and it is merged;
  4. its head branch, which isn't its base branch, is the `gitBranch` of
     some line in `claude-projects/`, or some `pr-link` record for it is
     within 120 seconds of its creation, inclusive, either way.

  A link alone credits nothing, since sessions also link pull requests they
  only viewed or merged: one linked more than 120 seconds after its creation
  on a branch the unit never worked on is not credited. A pull request the
  unit opened on another branch (a coordinated plan's node branch, say) is
  credited by the 120-second link. A link's repository and number, and each
  `gitBranch`, are matched to their patterns before any use, and only the
  repository and number ever reach a command. Candidates are read in order
  of their earliest link, at most 200, one `gh pr view` each out of the
  capture's read budget. Credit changes `pulls` only: green, merge and
  failing heads read the holding's pull requests alone. A unit with no
  holding pull request (a capture after a removal) has those three read
  from its credited pull requests instead.
- **Opened**: `opened` holds the pull requests still open at capture,
  drafts included (GitHub reads a draft as open). A candidate meeting
  conditions 1, 2 and 4, created at or after dispatch and read as open, is
  listed `via: session`, from the same `gh pr view` credit makes. The
  holding's Pull request cell, when it names a pull request the verdict
  doesn't and that reads open, is listed `via: holding`, one read of its own,
  and is then no candidate. A pull request closed without merging is in
  neither list. An open one is never moved to `pulls` later: the entry is
  written once, and a reader joins a later merge on the pull request's
  number.
- **Precision**: minutes to 0.1 and shares to 0.1 percentage point, rounded
  half up once from the unrounded value; counts and tokens exact. A figure
  can differ by 0.1 from one computed out of the rounded figures beside it.
- **Weakest state**: a figure computed from others (the two dispatch spans,
  both shares) takes the weakest state among its inputs: not recoverable if
  any is, else bound if any is, else measured. Failing heads is bound with
  green, since a run still going may yet fail.

With no unit session at all, the session-based figures are not applicable.

## Plan shape and milestone

**Plan shape**, one per unit, from the archived sessions in byte order of
their names, first match wins:

1. a `/deliver` session's context key `plan_execution_mode`: `single-pr`,
   `multi-pr` or `coordinated`;
2. an `/execute` session's template: `execute-coordinated.md` is
   `coordinated`, `execute.md` is `single-pr`;
3. a `/work-on` session's entry `mode`: `plan_backed` is `multi-pr`,
   `issue_backed` and `free_form` are `issue`;
4. otherwise `none`.

A session that matches but whose value can't be read, or a session whose
header can't be read at all, makes the shape not recoverable.

**Milestone**, one per unit, from the Holdings row's Unit for the topic, cut
at its first `: ` (so `Feature 4: Title` gives `Feature 4`). On a roadmap
record it is `{roadmap: ROADMAP-<name>, tag}`; on a discipline record, or
when the Unit is an issue reference (`#12`, `owner/repo#12`), it is `none`.
A Unit outside `^[A-Za-z0-9][A-Za-z0-9 _.#/-]{0,63}$` is dropped and the
milestone is not recoverable, as it is when the run facts or the Holdings
row can't be read.

When no Holdings row names the topic (the unit was retired, or removed
before its pass), the milestone comes from the Unit the dispatch wrote on
its leg key in the requesting coordinator's session
(`legs/<request>/<leg>`, found through the unit's own koto request), cut
and matched the same way. `scripts/dispatch-worker.sh` writes the Unit
there only when its tag has that shape, and a re-leg carries it to the new
key. A row, when there is one, wins over the key. A key with no Unit (a
dispatch from before it was recorded) leaves the milestone not
recoverable.

## The entry

The comment, after `record-append.sh`'s marker and stamp, is one summary
line, a blank line and one fenced `json` block holding a compact object:

````
Cost of <topic> (<capture key>): <n> sessions, <worker output> output tokens, dispatch to merge <m> min.

```json
{"schema":"unit-cost/1", ...}
```
````

| Field | Shape |
|---|---|
| `schema` | `"unit-cost/1"`; a reader treats any other value as unreadable |
| `key` | the archive directory's name, `<UTC date>-<topic>-<job id>` |
| `captured_at` | UTC, to the second |
| `topic` | the dispatch topic |
| `record` | `{scope, name, repo}` from the run facts, with `ref` kept in the shape and always `""`, or `null` |
| `unit` | the Unit's tag, `"not public"`, or `null` |
| `milestone` | `{value, state, source: "record"}` |
| `plan_shape` | `{value, state, source: "koto-state"}` |
| `pulls` | `[{repo, number, merge_commit, merged_at, via}]`, `via` `holding` or `session`; or `{repo: "not public"}` alone for one the host may not name |
| `opened` | `[{repo, number, via}]`, the pull requests open at capture, by number, at most 100; `{repo: "not public"}` alone as in `pulls` |
| `dispatch` | `{value, state, source, jobs}`, source `koto-request` or `job-state`, `jobs` the main session transcripts read |
| `"niwa.dispatch.id"` | niwa's dispatch id for the instance, from the archive's `teardown.json`, or `null` |
| `figures` | `dispatch_to_green_min`, `dispatch_to_merge_min`, `writing_code_min`, `review_min`, `outside_share_pct`, `review_share_pct`, `panel_rounds`, `failing_heads`, `sessions_without_done`, `summed_session_span_min`, `minutes_per_unit`, each `{value, raw, state, source}` |
| `sessions` | per archived session, in byte order of the names: `{index, template, unit_session, done, span_s, states, figures}`; `figures` holds `span_min`, `impl_share_pct` and `review_share_pct`, the shares not applicable outside unit sessions |
| `tokens` | `{worker, nested}`, each `{messages, input, output, cache_creation, cache_read, state, source: "transcripts"}` |
| `complete` | `true` when `missing` is empty |
| `missing` | `[{figure, reason}]`, reason one of `no source`, `read failed`, `time limit`, `entry size`, `invalid input` |

`pulls` lists the holding's pull requests first, in the verdict's order
(`via: holding`), then the credited ones by merge time, then number (`via:
session`), at most 100. When a pull request is left out, `missing` holds
one `pulls` entry with the reason of the first one left out: `no source`
(dispatch is not recoverable, so condition 3 can't be judged and nothing is
credited), `read failed` (its read failed or was cut at its bound), `time
limit` (the budget ran out before its read; what was read is kept) or
`entry size` (past 100 objects, or 200 candidates). `opened` follows the
same rule with its own `missing` entry: the reason the holding cell's read
failed, else credit's (both lists come from the same reads), else `entry
size` past 100 objects. A capture with nothing open writes `opened: []` and
adds nothing to `missing`.

`"niwa.dispatch.id"` is a top-level key whose name holds dots. It is the
`dispatch_id` niwa listed for the instance at teardown, which the handoff
sealed and the pass wrote into `teardown.json` (`niwa.dispatch_id`),
unchanged; when that holds none, it is the dispatch id of the removal
record whose instance path is the archive's (below). When there is none,
it is `null` and `missing` names
`niwa.dispatch.id`: `no source` when niwa listed none, the unit was removed
before teardown, or the archive has no `teardown.json`; `invalid input`
when the value isn't `^[A-Za-z0-9._:-]{1,128}$` or the file can't be read
as JSON.

The version stays `unit-cost/1`. Every field above that came before keeps
its name, type and meaning; the additions (`via`, `dispatch.jobs`,
`"niwa.dispatch.id"`, `opened`, the credited pull requests, and `missing`
naming `pulls`, `opened`, `tokens.nested` or `niwa.dispatch.id`) are new
keys or new entries under the existing shapes, with no new state, source or
reason. A reader
treats any schema but `unit-cost/1` as unreadable, so bumping the version
for additive fields would drop every new entry from every existing reader;
keeping it lets a reader that knows the additions use them and one that
doesn't ignore them.

A figure's `value` is a number (`null` unless the state is measured or bound),
rounded as above; `raw` keeps what it was rounded from: seconds for the time
figures, the percentage for shares, the count for counts. `source` is one of
`koto-request`, `job-state`, `koto-state`, `verdict-ledger`, `transcripts`,
`github-pr`, `github-runs`, `derived`. A session's `states` maps each state
to its seconds and `span_s` is its span, both to the millisecond, so the
states sum to the span exactly. `template` is one of `deliver`, `scope`,
`execute`, `work-on`, `other`; sessions carry no names, since a plan's child
names carry its issue titles.

An entry over 50,000 bytes is posted without the `states` maps (each set to
`null`, `missing` naming `sessions.states` with reason `entry size`); the
archive's `unit-cost.json` keeps them.

On a public host (the record's repository is public, or its visibility
can't be read), a pull request whose repository isn't read as public,
credited ones included, is written as `{repo: "not public"}` and nothing
else, and an `owner/repo#n` Unit naming one as `"not public"`. A failed
lookup counts as not public. The figures are kept.

## Capture after a removal

niwa removes sessions the coordinator never tears down: `niwa destroy`,
`niwa reap`, and the reaps `niwa dispatch`, `niwa create` and `niwa watch`
run first. For each one it runs the workspace's `[session.on_reap]` command
from the workspace root, with `NIWA_REAP_KEY` (the dispatch id),
`NIWA_SESSION_ID` and `NIWA_INSTANCE_PATH`, in a 10-second run. A capture
takes up to 120 seconds, so the step only records the removal and starts a
sweep in the background that does the rest.

**The removal record.** `scripts/unit-removed.sh record` writes
`<dispatch id>.json` in the removals directory,
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/removals`, which must be the
user's, mode 0700 and not a symbolic link: `{schema: "unit-removal/1",
dispatch_id, session_id, instance_path, removed_at, attempts, last}`. A
second removal of the same dispatch id at the same path keeps the first
`removed_at`; one at another path replaces the record. The step refuses,
printing one line, writing nothing and exiting 0, when the reap key is
missing, outside `^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$` or equal to the
session id, when the session id or the instance path isn't one (absolute,
no `..`, strictly under the directory it runs in), when the removals
directory fails its checks, or when its own script or a library it sources
is writable by group or others. It exits 0 in every case and never waits
for the sweep, so it is never in niwa's way.

**The sweep.** `unit-removed.sh sweep` reads every record in the removals
directory, one at a time, under a lock of its own (`.<dispatch id>.lock`
there): a record a live sweep holds is passed over, and a lock whose holder
is gone, or older than three minutes (the capture's 120 seconds and a
minute for the archive), is taken over, so two
sweeps on one host (two coordinators waking together, or a pass and a wake)
never capture one record twice. With no record it does nothing. For each
record it:

1. finds the unit's koto sessions (their execution directory at or under
   the instance path) and, from their `request-leg.toml` files, the
   earliest coordinator request: the dispatch;
2. requires the leg key that dispatch wrote, `legs/<request>/<leg>`, in the
   requesting coordinator's own session, naming that request and topic, so a
   request a worker forged names no coordinator;
3. takes the requesting coordinator while it is live for its scope, else the
   scope's one live run, so the entry goes to the record the dispatch named,
   never to whichever coordinator happens to sweep;
4. archives what survives as the pass's removed mode does
   (`<archive root>/<UTC date>-<topic>-<session id's first 8>`,
   `teardown.json` with `removed: true` and the dispatch id);
5. runs `unit-cost.sh capture` on that archive under the 120-second bound,
   with no pull request a verdict sealed, so credit supplies the pull
   requests and the removal record supplies the dispatch id.

The sweep reads GitHub only with a token. With `GH_TOKEN` unset or empty it
makes no GitHub call at all (a bare `gh` would fall back to a stored login),
archives, and keeps the record `pending github`; with one, every `gh` call
runs with `GH_CONFIG_DIR` an empty directory of the sweep's own, so no
stored login is ever used. niwa's step usually runs without the
coordinator's token, so the token-bearing sweep comes from two places, each
detached and never inside a koto action or gate: the end of every teardown
pass (`teardown-pass.sh run` starts `unit-removed.sh start`), and the
coordinator's wait guidance, which runs `scripts/unit-removed.sh start` at
each wake. `start` launches the sweep the way `record` does and returns at
once.

**Retry.** A record whose capture wrote no entry is kept, its `attempts`
counted and `last` set to `{at, outcome}`, and every later sweep tries it
again: `pending github`, `no coordinator`, `several coordinators`, `read
failed`, `post failed` and `timed out` all wait for the next sweep. A
written entry, or one another capture already wrote (`already recorded`),
deletes the record; so does a record outside its shape (`invalid input`). No
record is deleted for its age: one kept more than 24 hours after its
`removed_at` is listed `stale` by every sweep that keeps it, so a person
sees it, since a removal can't tell a unit nobody dispatched from one whose
coordinator hasn't started. The usual causes are a unit with no koto session
left under its instance, or a dispatch whose coordinator has ended with no
live run for its scope; someone removes such a record by hand. Before it
exits, a sweep reads the directory again and handles any record written
since it started.

**`removals.log`.** Beside the records, one line per record a sweep
handles, `<UTC time> <dispatch id> <outcome>`, the same line it prints. The
outcome is `captured` (the first two last lines above), `already
recorded`, `post failed` (the post failed or didn't finish), `read failed`
(the record couldn't be read, the archive couldn't be made, or the entry
couldn't be computed), `timed out` (the capture was stopped at 120
seconds), `pending github`, `no coordinator`, `several coordinators` or
`invalid input`; a kept record past 24 hours adds a line `stale`.

**The on-reap line.** A workspace adds the step to its niwa configuration.
This runs the newest released shirabe in the plugin cache, by numeric
version order, only when the user owns the script:

```toml
[session.on_reap]
command = '''
c=$(ls -d "$HOME"/.claude/plugins/cache/shirabe/shirabe/*/ 2>/dev/null \
    | sed 's#/$##; s#.*/##' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
s="$HOME/.claude/plugins/cache/shirabe/shirabe/$c/skills/coordinate/scripts/unit-removed.sh"
[ -n "$c" ] && [ -O "$s" ] && [ -x "$s" ] && "$s" record
exit 0
'''
```

A workspace that wants one version pins the path instead of choosing the
newest. niwa refuses an on-reap command whose environment names look like
credentials, and the step needs none. Combined with another tool's on-reap
step, shirabe's goes first, without its `exit 0`, since it returns at once:

```toml
[session.on_reap]
command = '''
c=$(ls -d "$HOME"/.claude/plugins/cache/shirabe/shirabe/*/ 2>/dev/null \
    | sed 's#/$##; s#.*/##' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
s="$HOME/.claude/plugins/cache/shirabe/shirabe/$c/skills/coordinate/scripts/unit-removed.sh"
[ -n "$c" ] && [ -O "$s" ] && [ -x "$s" ] && "$s" record
<the other tool's step>
'''
```

## Evidence, not proof

Every figure comes from files the worker itself could write: its koto state,
its ledgers, its transcripts, and the `pr-link` records and `gitBranch`
values credit reads. The capture reads them as untrusted input (it
keeps only numbers, ids, timestamps and closed-set words, each matched to
its shape) but it can't tell an honest record from a shaped one. A second
derivation from the same archive agreeing with the entry shows the capture
computed what the archive holds, not that the archive holds what happened.

## Reading entries

The entries are ordinary comments carrying the `kind=cost` marker. A run from
before the GitHub record was removed posted them all on its record issue; with
`gh` and `jq`, for such a record `owner/repo#n`:

```bash
gh api "repos/<owner>/<repo>/issues/<n>/comments" --paginate \
  --jq '.[] | select(.body | startswith("<!-- coordinator-record-entry v1 kind=cost -->")) | .body' \
  | sed -n '/^```json$/,/^```$/p' | grep -v '^```' \
  | jq -c 'select(.schema == "unit-cost/1")
           | {key, unit, plan_shape: .plan_shape.value,
              minutes: .figures.summed_session_span_min.value,
              output_tokens: .tokens.worker.output, complete}'
```

A run now keeps every entry in the coordinator's session,
where `record-append.sh --session <session> --list` returns them as entries
of kind `cost`, each one's text the same summary line and fenced block:

```bash
"${CLAUDE_SKILL_DIR}/scripts/record-append.sh" --session <session> --list \
  | jq -r '.[] | select(.kind == "cost") | .text' \
  | sed -n '/^```json$/,/^```$/p' | grep -v '^```' \
  | jq -c 'select(.schema == "unit-cost/1")
           | {key, unit, milestone: .milestone.value, plan_shape: .plan_shape.value,
              dispatch_id: ."niwa.dispatch.id", opened: (.opened | length), complete}'
```

For a repository that opts in to placement, the entries are on its units'
pull requests or issues instead. List the scope's units (the pull requests
in the session's Holdings, or the ones the roadmap's Delivered lines name),
one `owner/repo#n` per line in `units.txt`, and read each one's comments.
Anyone can comment on a pull request, so keep only the comments the
coordinator posted: filter on the login it posts as (`gh api user` on its
host), compared without case.

```bash
# gh's --jq takes no arguments, so the login goes into the filter; a login
# is letters, digits and hyphens (and `[bot]`), nothing a filter misreads.
login=$(printf '%s' '<the coordinator login>' | tr 'A-Z' 'a-z')
while read -r unit; do
  gh api "repos/${unit%#*}/issues/${unit##*#}/comments" --paginate \
    --jq '.[] | select((.user.login | ascii_downcase) == "'"$login"'")
          | select(.body | startswith("<!-- coordinator-record-entry v1 kind=cost -->")) | .body'
done < units.txt \
  | sed -n '/^```json$/,/^```$/p' | grep -v '^```' \
  | jq -c 'select(.schema == "unit-cost/1")
           | {key, unit, plan_shape: .plan_shape.value,
              minutes: .figures.summed_session_span_min.value,
              output_tokens: .tokens.worker.output, complete}'
```

Every entry is also in its archive's `unit-cost.json`.

A record can hold the same key twice, or the same `"niwa.dispatch.id"` under
two keys (a capture that couldn't list the record, had no read budget left
to list it, or couldn't take the post lock posts anyway, saying so, and a
takeover of a live lock holder past its bound can let
two captures post); keep the latest per key and per dispatch id, and report
the repeat. Read a figure's `state` before its `value`: a `bound` or `not
recoverable` figure is not a measurement and doesn't belong in a sum. A pull
request in `opened` may have merged since; join it on its number rather
than expecting the entry to change.
