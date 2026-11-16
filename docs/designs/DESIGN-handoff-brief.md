---
schema: design/v1
status: Proposed
problem: |
  A session that stops leaves no plain-text statement of its reasoning and no
  record of which of its files matter, so a successor fetches scratch from
  teardown copies, the instance remover keeps everything it can't prove
  disposable, and a worker at its context line is replaced by a cold instance
  it didn't need. shirabe has no script that writes such a statement, no keep
  record for the remover to read, no closing step that clears stray files
  first, and no supported route for a worker to compact in place.
decision: |
  One script, scripts/handoff-brief.sh, writes the brief as keys under
  handover/ in the calling session's koto session (a plain koto session it
  opens when there is none): reasoning and pointers in handover/brief.md, each
  named file at or below 256 KiB as its own key, and a keep record at
  <instance>/.niwa/keep.json that holds the only file list. A closing-step
  script runs before it. A successor taking over through the fallback
  continuation route copies and hash-checks every named file before the
  route's fence and carry, so the carry marker never lands on a bad copy.
  Supervising sessions write the same brief, with a standing-rules section
  whose content and budget belong to other work. Compaction stays off; the
  design states how a role would carry its window and what the note is.
rationale: |
  Keys under handover/ ride the carry the continuation route already does and
  reach a cloud backend with the session, so no second transport exists.
  Keeping the file list in the keep record alone means the remover and the
  successor read one list. Copying before the fence keeps the predecessor
  writable for a retry and keeps a failed copy from ever looking landed. One
  brief format for every role avoids a second format for coordinators, and
  the limits sit far under koto's and shirabe's existing caps.
upstream: docs/prds/PRD-handoff-brief.md
decision_provenance: inline-resolved
---

# DESIGN: Handoff brief

## Status

Proposed

Written from the accepted PRD-handoff-brief under `/scope`. The owner has
since ruled on the PRD's two pending questions; Decision 5 records both
rulings and what they change here.

## Context and Problem Statement

When a session stops, three readers need a statement from it: the session
that picks up the work, the supervising session that dispatched it, and the
remover that later deletes its instance. Today the only statement is a
continuation note a coordinator writes by hand, and the session's own
reasoning is mostly unreadable afterwards: current models return thinking as
an encrypted signature, so one compacted transcript held readable text in
only 52 of 605 thinking blocks. The PRD asks for a deliberate brief (R1-R10),
a separate compaction note (R11), and a worker route through the context line
that stays off until proven (R12-R14).

The technical problem has five parts.

**Where a brief lives and how far it travels.** R1 requires the brief to sit
in the calling session's koto session, so it moves wherever that session goes,
a cloud backend included, with no copy in a transcript or a loose file. A
session with no koto run still needs one. koto stores any bytes as a context
value (it reads raw bytes from a file or stdin), caps a key name at 255 bytes,
and refuses keys under `koto/`; shirabe's own `skill-session.sh put` refuses
content of 1 MiB or more. The fallback continuation route (#1785) already
moves a predecessor's `handover/` keys into its successor with koto's carry.

**What the remover can trust.** R5 requires one copy of the file list, held
in the keep record `<instance>/.niwa/keep.json`, which the brief renders from.
R5 also says when a brief's record is a hold on the instance and when it only
preserves files, and R6 and R7 say what counts as handed forward and what
counts as disposable, all decided mechanically. No keep record exists in niwa
or shirabe today, so this design defines the fields the brief script writes
and leaves the remover's own fields to the removal work.

**The order at a run's end.** R9 puts a closing step (everything pushed, no
stray file, the worktree left but kept on disk) before the brief, both after
hosted CI is green and before done. Where those two steps sit inside a work-on
run is held for the #1230 design, which reworks the verification stretch of
that run. The scripts themselves are not held (R16).

**Fitting the continuation route.** R10 requires a successor taking over
through #1785's route to copy every named file into its own scratch and check
each sha256 before the takeover lands. In that route the predecessor runs
`handover.sh write` and stops. The successor's `handover.sh open` supersedes
it, which fences it from further writes, and carries its `handover/` keys
across. koto writes `koto/superseded-carry-complete` last.

**Compaction without turning it on.** Claude Code compacts a background
session in place when it is given a window and the instance has a PreCompact
hook, and the session id doesn't change. niwa reads a session as live while
`~/.claude/jobs/<id>/state.json` exists with a matching `sessionId`. Its
dispatch launch settings take constant keys only, apart from an `env` object,
and the workspace config already has a `[session.dispatch_env] passthrough`
list. A 100K window over a harness floor near 58K thrashed and blocked a
session. Two trial workers compacted several times each, from about 247K down
to 72K-80K, and finished.

## Decision Drivers

- **One list, one transport.** The remover and a successor must read the same
  file list (R5), and the brief must travel with its koto session (R1), so no
  design may keep a second copy of either.
- **Mechanical only.** Every check the remover relies on is a hash, a size, a
  timestamp or a key's presence (R3, R4, R7). What to name stays the model's
  choice, and that limitation is accepted.
- **Refuse rather than drop.** A brief that silently omits a file reads as
  complete, so every limit refuses and writes nothing (R4).
- **Fit, don't add, routes.** The successor copy goes inside #1785's existing
  open step (R10). /coordinate's record, fenced takeover and handover gate are
  not rebuilt.
- **Hold what is held.** Placement inside a work-on run waits for #1230 (R16),
  and nothing ships compaction on for any role (R14).
- **Small volume.** About 40 of roughly 182 daily instances on one workspace
  are worker continuations, and compaction should shrink that further. The
  design adds no service, queue or index sized for more.
- **Portable shell.** The scripts run on macOS's bash 3.2 and Linux, as
  shirabe's other scripts do, and call only `koto`, `git`, `gh`, `jq` and a
  sha256 tool.

## Considered Options

### Decision 1: Where the brief and its files are stored

Resolved inline.

R1 puts the brief in the calling session's koto session, and R4 lets a named
file travel inside it when it is small enough. The question is the key layout
and the two limit values.

Key assumptions:
- koto context values hold arbitrary bytes, and nothing caps a value below
  the bucket's 16 MiB state-file read.
- #1785 carries the `handover/` prefix and no other prefix a brief would need.

#### Chosen: keys under `handover/`, one per inline file, with limits of 256 KiB and 2 MiB

The brief is `handover/brief.md`. Each named file at or below the inline size
of 262,144 bytes (256 KiB) is stored as `handover/files/<sha256>`, holding its
exact bytes. A larger file is named by reference only. The record cap is
2,097,152 bytes (2 MiB) over every file one record names, by reference
included. Keying file content by hash makes the key name fixed-length and
safe, makes two names for one content share a key, and lets a reader verify
the key against the hash in the record without trusting the path.

Placing the keys under `handover/` means #1785's carry moves a predecessor's
brief and inline files into its successor's session with no change to that
route. 256 KiB holds every kind of scratch the PRD names (a draft comment, a
helper script, review panel output) and sits under shirabe's 1 MiB `put`
limit. 2 MiB keeps a brief's total far under the bucket's limit and is over
three hundred times the largest hand-written continuation note seen, which
sat near 6 KiB.

#### Alternatives Considered

- **One JSON key with files base64-encoded inside.** Rejected: base64 grows
  content by a third, one bad file corrupts the whole brief, and a reader
  can't check one file without parsing all of them.
- **A brief file in the instance, beside the keep record.** Rejected: R1
  forbids it, and a file in the instance can't move hosts.
- **One limit for both questions.** Rejected, as the PRD already did: how big
  one file can be to travel and how much one record may name are different
  questions.

### Decision 2: What the keep record says and how a park's hold is voided

Resolved inline.

R5 to R7 fix the semantics; the design picks the field shapes and the mark
that voids a park's hold.

Key assumptions:
- The removal work owns `reason`, `owner`, `review_by` and `wake`, and reads
  `protects` and `files`.
- A park is resumed by the same session or a successor, both of which can
  call the brief script.

#### Chosen: the script writes its own fields with a whole-file replace, and `resume` voids the hold

`handoff-brief.sh write` reads any existing record, replaces only its own
fields (`unit`, `written_by`, `written_at`, `files`, `brief`, `protects`) and
writes the result to a temporary file in the same directory, then renames it
over `keep.json`, so a reader never sees a half-written record and other
writers' fields survive. `protects` is computed, never passed in:
`["instance", "files", "transcript"]` for a park or whenever a named file is
by reference (the interim rule, R6); `["files", "transcript"]` for a run's
end or a handover that names only inline files. A brief with no files and no
park writes no record and leaves an existing one untouched.

Resumed work runs `handoff-brief.sh resume`, which drops `instance` from
`protects` unless a named file is by reference, records `resumed_at`, and
leaves `files` as written (R7). `written_at` is the brief's time in UTC with
second precision; the remover compares it with the later of each scratch
file's mtime and ctime.

#### Alternatives Considered

- **Voiding the hold by deleting the record.** Rejected: it would also drop
  the named files, which R7 keeps named after resumed work.
- **Letting the caller pass `protects`.** Rejected: the hold rules would then
  live in every caller instead of one script.
- **Writing the record in place.** Rejected: a crash midway leaves a record
  the remover can't parse, and an unparseable record would have to keep the
  unit forever.

### Decision 3: Where the successor's copy runs, and the takeover mark with no run

Resolved inline.

R10 requires the copy and hash check before the takeover lands. In #1785's
route, `handover.sh open` supersedes the predecessor and koto writes
`koto/superseded-carry-complete` at the end of the carry.

Key assumptions:
- `handover.sh open` is the one place every #1785 successor passes before the
  fence.
- A session that stopped without a koto run is picked up by a person or a
  session pointed at its brief session, not through #1785.

#### Chosen: `handoff-brief.sh takeover` runs inside `handover.sh open`, before the fence

`takeover` reads the predecessor's keep record, copies each named file into
the successor's own scratch (from `handover/files/<sha256>` for an inline
file, from the predecessor's path for a by-reference file on the same host),
and checks each sha256 against the record. Any missing file or mismatch exits
non-zero naming the file. `handover.sh open` then stops before the supersede,
so the predecessor stays unfenced for a retry and no carry marker exists. On
success the open proceeds, and koto's marker is the landed mark. The
predecessor's record is read and never written.

With no koto run, `takeover --from <brief-session>` does the same copy and
then writes `handover/taken-by` in the predecessor's brief session, holding
the successor's session name and the time. That key is the takeover mark the
PRD's Terms leave to the design. The brief session itself never ends by rule:
it stays until koto's retention reaps it (seven days idle by default), so a
brief can be read the next day.

#### Alternatives Considered

- **Copy after the carry, from the carried keys.** Rejected: the marker would
  already exist, so a bad copy would look landed, which R10 forbids.
- **A new takeover step in /coordinate.** Rejected: it adds a route, and a
  successor dispatched without a coordinator would skip it.
- **Ending the no-run brief session at takeover.** Rejected: a person may
  point several sessions at one brief, and retention already removes idle
  sessions.

### Decision 4: The closing step, and how compaction would be carried and triggered

Resolved inline.

R9 fixes the closing step's checks; R11 to R13 fix the note and the per-role
switch, and the PRD leaves the window's transport, the margin and the
context-size reader to the design.

Key assumptions:
- niwa's `[session.dispatch_env] passthrough` delivers a named environment
  value to a dispatched session, as it already does for another koto value.
- Claude Code's automatic compaction is the trigger for a worker, so a worker
  needs no context reader.

#### Chosen: a closing-step script, the window as a passed-through value, a 120K margin, and a reader only for supervising sessions' handover line

`scripts/closing-step.sh` takes a worktree path. It fails, naming the cause,
when `git status --porcelain --untracked-files=all` shows an untracked file
that `git check-ignore` doesn't match, or when the branch has no upstream or
`git rev-list @{u}..HEAD` is non-empty. On a pass it prints the instance root
for the caller to move to. It never deletes the worktree, and it checks that
the caller's working directory is outside the worktree before it reports
done. Scratch is outside any worktree, so it is never stray.

A role's compaction window travels as Claude Code's compaction-window
environment value, listed in the workspace's `[session.dispatch_env]
passthrough` only for the roles that set it. The PreCompact hook ships as an
instance hook that the workspace installs, and with no window the hook never
fires. The margin is 120,000 tokens over the harness floor, so with a floor
near 58K the smallest allowed window is 178K; the trials ran near 250K. The
hook tells the session to write `handover/compaction-note.md` in its koto
session and to re-read that key after the compaction.

Supervising sessions keep their stated handover line. For that trigger,
shirabe ships `scripts/context-size.sh`, which reads a transcript and reports
the newest assistant message's usage after the latest compaction boundary.
The existing workspace reader, which isn't part of shirabe, reads one message
behind after a compaction.

#### Alternatives Considered

- **A niwa change to take variable launch keys.** Rejected: the passthrough
  already exists and needs no niwa release.
- **Writing instance settings after dispatch.** Rejected: it races the
  session's start, and nothing re-reads settings mid-session.
- **A margin of 60K.** Rejected: 100K over a 58K floor, a 42K margin,
  thrashed, and the trial evidence sits near a 190K margin, so 120K stays
  well inside what was seen to work.
- **Folding the closing step into the brief script.** Rejected: R9 orders
  them as separate steps, and the brief script must stay callable with no
  worktree at all.

### Decision 5: Which roles write the brief, after the owner's rulings

Resolved inline.

The PRD held two questions for the owner. Both are now ruled. This work
builds the one brief that every session writes, coordinators and the two
top-level supervising sessions included. Separate work keeps the part of that
brief that lists standing rules with their sources, the size budget on that
part, and the incoming session's restatement of it; that work delivers them
as a section of this brief and a check on it, never as a second format.
Coordinators don't compact: they keep handing over.

Key assumptions:
- /coordinate's existing handover keeps its record, fence, gate and rendered
  successor text, and only where that text is written changes.

#### Chosen: one format with a reserved standing-rules section, adopted worker first

The brief format has four fixed sections (Reasoning, Pointers, Files,
Standing rules). The script writes Standing rules from an optional
`--standing-rules <file>` and otherwise leaves the heading with the line
`None stated.` This design defines the slot only: its content, its budget
and the restatement check belong to the other work. Adoption runs in order:
workers first, then /coordinate's handover writing its rendered successor
text as the Reasoning of a brief through the same script, then the two
top-level supervising sessions last.

Compaction for coordinators stays off. Before any trial: two checks that
touch no running coordinator, then one trial on a quiet lane against the
recorded pass criteria, with the top-level session last. Until that trial,
compaction is proven for workers only, and nothing in the plan turns it on
for coordinators.

#### Alternatives Considered

- **A separate supervising-session brief format.** Rejected by the ruling: it
  would be the second format the ruling forbids.
- **Workers only, as the PRD's interim stated.** Rejected: the ruling moved
  supervising sessions into this work.

## Decision Outcome

The five decisions make one path. A session at a run's end runs the closing
step, then `handoff-brief.sh write`, which hashes the named files from disk,
refuses on any limit or bad path, stores the brief and small files as
`handover/` keys in its koto session, and writes the keep record's one file
list with the hold computed from the event and the interim rule. A successor
through #1785 runs `takeover` before its fence, so the carry marker that
lands the takeover only exists after every named file arrived with a matching
hash. A no-run session's brief lives in a plain koto session, and its
takeover mark is a key there. Coordinators and the top-level sessions write
the same format, with a section reserved for standing rules that other work
fills. Compaction is described, carried by an existing niwa passthrough,
margined, and left off.

## Solution Architecture

### Overview

Three scripts and one hook, all in shirabe:

| Component | Path | Job |
|-----------|------|-----|
| Brief script | `scripts/handoff-brief.sh` | `write`, `resume`, `read`, `takeover` |
| Closing step | `scripts/closing-step.sh` | push and stray checks before the brief |
| Context reader | `scripts/context-size.sh` | newest usage after the last compaction |
| Compaction hook | `hooks/pre-compact-note.sh` | tells the session to write its note |

niwa and koto change nothing. #1785's `handover.sh open` gains one call to
`handoff-brief.sh takeover` before its supersede. /coordinate's handover
gains one call to `handoff-brief.sh write` in its adoption step.

### Components

**`handoff-brief.sh write`** takes `--reasoning <file>`, repeated `--file
<path>`, `--event end|park|handover`, `--instance <root>`, optional `--watch
"<label>=<re-arm command>"` and `--standing-rules <file>`. Pointers are read,
not passed: the session (`KOTO_SESSION` when set, otherwise a new plain
session named `handoff-<job-id>` opened through `skill-session.sh`), the
current branch, the open pull request from `gh pr view`, and the remote
branch's commit from `git ls-remote`. It refuses, writing nothing, on: empty
reasoning once whitespace is trimmed; a named directory, symlink, missing or
unreadable path; a total over the record cap. It hashes each file once,
stores the inline ones, writes `handover/brief.md`, then writes the record,
in that order, so a record never points at a brief that isn't there.

**`handoff-brief.sh resume`** voids a park's hold as Decision 2 says.
**`read`** prints a brief with its file list rendered from the record and
verifies each inline key's hash. **`takeover`** is Decision 3.

**`closing-step.sh`** is Decision 4. It takes a worktree and prints
`closing=pass` and the instance root, or `closing=blocked` with one line per
cause.

**`context-size.sh`** reads a transcript JSONL and prints the input-token
total of the newest assistant message after the latest compaction boundary.

**`pre-compact-note.sh`** is a PreCompact hook. It prints the instruction to
write `handover/compaction-note.md` (reasoning and pointers only) and the
summary line naming that key to re-read. It names no files, touches no
record, and changes no scratch.

### Key Interfaces

The brief key, `handover/brief.md`:

```markdown
# Handoff brief
written_at: 2026-11-16T04:30:00Z
event: end
## Reasoning
<concluded, ruled out and why, next step>
## Pointers
koto_session: <name>
branch: <name>   pull_request: <number>   pushed_head: <sha>
watch: <label> = <re-arm command>
## Files
(rendered from the keep record at read time)
## Standing rules
None stated.
```

The keep record fields the script writes:

```json
{
  "unit": {"instance": "<root>", "job_id": "<id>", "session_id": "<id>"},
  "written_by": "handoff-brief.sh",
  "written_at": "2026-11-16T04:30:00Z",
  "brief": {"koto_session": "<name>", "key": "handover/brief.md"},
  "files": [{"path": "<abs>", "sha256": "<hex>", "bytes": 123, "inline": true}],
  "protects": ["files", "transcript"],
  "resumed_at": null
}
```

Exit codes for every subcommand: 0 done, 1 refused with a named cause and
nothing written, 2 environment fault (koto, git or gh unavailable).

### Data Flow

1. The run's end: `closing-step.sh` passes, then `write --event end` hashes,
   stores keys, and writes the record.
2. Pickup on another host: the successor reads `handover/brief.md` and the
   inline file keys from its carried session or from the cloud backend.
3. Takeover through #1785: `takeover` copies and checks, then the open
   supersedes and carries, and koto writes its marker.
4. A park: `write --event park` writes a hold; `resume` later voids it.
5. Removal (other work): the remover reads `protects`, `files` and
   `written_at`.

## Implementation Approach

### Phase 1: The session-id read

The first task, before any build: read the job state file's `sessionId`
before and after one compaction in a test instance, and record the result.
Making compaction the worker default waits on it, on the remaining arms of
the worker trial and on the owner's ruling (R14).

### Phase 2: The brief script

Deliverables: `scripts/handoff-brief.sh` with `write`, `read` and `resume`;
its script tests under `scripts/tests/`; the two limits documented in its
header and in `references/handoff-brief.md`.

### Phase 3: The closing step and the context reader

Deliverables: `scripts/closing-step.sh`, `scripts/context-size.sh`, and their
tests. Neither is placed in a work-on run.

### Phase 4: The takeover copy

Deliverables: `handoff-brief.sh takeover`, and the one call in #1785's
`handover.sh open` once that route lands. It's checked first with the copy
driven directly.

### Phase 5: The compaction hook, shipped off

Deliverables: `hooks/pre-compact-note.sh` and a documented passthrough
example that no shipped workspace config enables.

### Phase 6: Adoption order

Workers adopt the brief at a run's end once #1230's design says where the
steps sit. Then /coordinate's handover writes its successor text through the
script, and the top-level sessions follow last.

## Security Considerations

The brief script reads files the session names and writes their content into
koto keys, which may sync to a cloud backend. That widens where a named
file's bytes live: a file holding a credential would travel with the brief.
The script refuses symlinks, so a named path can't point it at a file outside
what the session meant, and it writes only under `handover/` in a session it
opened or was given. It never reads settings or environment files by name;
naming such a file is the caller's act, and the reference doc says not to.

The keep record is written with a temporary file and a rename in the same
directory, at mode 0600, and the script never follows a symlink at
`keep.json`. A record another writer corrupted makes `write` exit 2 without
touching it, so a corrupt record can't be silently replaced.

`takeover` reads by-reference files from the predecessor's paths on the same
host. It checks each hash before trusting the copy, and copies into the
successor's 0700 scratch, so a file swapped after the brief fails the check
rather than landing. The compaction hook prints fixed text and runs no input
from the transcript.

## Consequences

### Positive

- A successor reads one brief with a verified file list, on any host where
  the koto session reaches, and nothing is fetched from a teardown copy.
- The remover gets mechanical inputs: a file list, a hold flag and a time.
- #1785 and /coordinate gain one call each, and no new route exists.
- Supervising sessions share the worker's format, so there's one reader.

### Negative

- A named file above 256 KiB keeps its unit and can't cross hosts until the
  kept set exists.
- Named file content now lives in koto keys and may sync to a cloud backend.
- A no-run brief session lingers until retention removes it.
- Nothing is placed in a work-on run yet, so the end-to-end check waits for
  #1230.

### Mitigations

- The interim rule makes the by-reference case a hold, which is safe, and the
  reference doc says to keep named scratch small.
- Symlinks are refused, and the reference doc warns against naming any file
  that holds a credential.
- Seven days idle is long enough for a next-day pickup and short enough not
  to pile up.
- Every script has checks that run with no work-on run (R16).
