---
schema: design/v1
status: Accepted
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
  <instance>/.niwa/keep.json that holds the one file list, which the brief
  renders when it is written. It refuses credential-shaped paths, names and
  content rather than storing them. A closing-step
  script runs before it. A successor taking over through the fallback
  continuation route copies and hash-checks every named file before the
  route's fence and carry, so the carry marker never lands on a bad copy.
  Supervising sessions write the same brief, with a standing-rules section
  whose content and budget belong to other work. Compaction stays off; the
  design states how a role would carry its window and what the note is.
rationale: |
  Keys under handover/ ride the carry the continuation route already does and
  reach a cloud backend with the session, so no second transport exists.
  Keeping the file list in the keep record, with the brief carrying only a
  rendering of it, means the remover and the successor read one list. A
  successor treats that list as untrusted and confines every path it copies.
  Copying before the fence keeps the predecessor
  writable for a retry and keeps a failed copy from ever looking landed. One
  brief format for every role avoids a second format for coordinators, and
  every stored key sits far under koto's and shirabe's existing caps.
upstream: docs/prds/PRD-handoff-brief.md
decision_provenance: inline-resolved
---

# DESIGN: Handoff brief

## Status

Accepted

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
- **Inline only, refusing any file over the inline size.** This would drop
  the interim hold rule and the by-reference path checks. Rejected: R4 names a
  larger file by reference rather than refusing it, and a refusal would leave
  a session unable to hand forward the one large file that matters, which
  pushes it back to the teardown copy the brief exists to replace.

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
writes the result to a `mktemp` file in `.niwa/` under `umask 077`, then
renames it over `keep.json`, so a reader never sees a half-written record and
other writers' fields survive. A lock directory made with `mkdir` guards the
read and the rename, since macOS has no `flock`; a lock older than ten
minutes is stale, and a later writer removes it and takes its own. The script refuses when
`--instance` isn't a directory the current user owns, or when `.niwa` or
`keep.json` is a symlink. A record that doesn't parse is moved aside as
`keep.json.corrupt-<time>` and a fresh one is written, so one bad writer
can't block every later brief. `protects` is computed, never passed in:
`["instance", "files", "transcript"]` for a park or whenever a named file is
by reference (the interim rule, R6); `["files", "transcript"]` for a run's
end or a handover that names only inline files. A brief with no files and no
park writes no record and leaves an existing one untouched.

Resumed work runs `handoff-brief.sh resume`, which drops `instance` from
`protects` unless a named file is by reference, records `resumed_at`, and
leaves `files` as written (R7). `written_at` is the brief's time in UTC with
second precision, taken before any file is hashed, so a file edited during
the write reads as newer than the brief; the remover compares it with the
later of each scratch file's mtime and ctime.

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

`takeover` treats the predecessor's list as untrusted input, since the hash
a record supplies proves nothing about the path beside it. On another host
the brief key's Files section is the only list. On the same host it reads both
that section and the keep record, and refuses when they name different files
or hashes, since a predecessor could edit the record after writing the brief.
It copies each named file into the successor's own scratch (from
`handover/files/<sha256>` for an inline file, from the predecessor's path for
a by-reference file on the same host), at a destination built from the hash
and a sanitized basename, never from the record's path. A by-reference path
must resolve under the predecessor's scratch (the PRD's term: the job's
scratch directory and loose files at the instance root outside any repo),
outside `.git/`, `.niwa/` and `.claude/`, as a regular file with no symlink in
it. A sha256 must be exactly 64 lowercase hex characters before it names a key
or a path. The successor reads at most the record's stated bytes for each
file, and never more than the inline size for an inline key or the record cap
in all, so a planted or grown file can't overrun it. It hashes its copy, not
the source, runs the same credential-name check and token scan `write` runs
on that copy, renames it into place only on a match, and leaves it without
an execute bit. Any missing file, refused path
or mismatch exits non-zero naming the file. `handover.sh open` then stops before the supersede,
so the predecessor stays unfenced for a retry and no carry marker exists. On
success the open proceeds, and koto's marker is the landed mark. The
predecessor's record is read and never written.

With no koto run, `takeover --from <brief-session>` does the same copy and
then writes `handover/taken-by` in the predecessor's brief session, holding
the successor's session name and the time, only when that key is absent.
That key is the takeover mark the PRD's Terms leave to the design. It is
advisory and gates nothing: the remover never reads it as a lock. `--from`
must be a legal session name, and `takeover` reads only `handover/brief.md`
and `handover/files/<sha256>` from it. The brief session itself never ends by rule:
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
done. Scratch is outside any worktree, so it is never stray. Every git call
runs with `-c core.fsmonitor=false` and `-c core.hooksPath=/dev/null`, since
the session can edit the worktree's config and these are the settings that
run a program on a status read.

A role's compaction window travels as Claude Code's compaction-window
environment value, listed in the workspace's `[session.dispatch_env]
passthrough` only for the roles that set it. The PreCompact hook ships as an
instance hook that the workspace installs, and with no window the hook never
fires. The margin is 120,000 tokens over the harness floor, so with a floor
near 58K the smallest allowed window is 178K; the trials ran near 250K. The
hook tells the session to write its note through `handoff-brief.sh note`,
which runs the same token scan `write` runs and stores
`handover/compaction-note.md` in its koto session, and to re-read that key
after the compaction.

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
and the restatement check belong to the other work. What it fixes here is
the slot's integrity. The rules file must be a regular, readable file with no
symlink in its path, and its text passes the same scan as a named file's. `write` refuses a line in the
Reasoning, the rules file or a watch value that begins with `## `, so free
text can't open a forged section, and `read` treats only the four fixed
headings, in their fixed order, as structure. A successor reads the section
as the predecessor's claim about its rules, never as rules in force, until
the other work's check compares it with each rule's source. Adoption runs in order:
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
| Brief script | `scripts/handoff-brief.sh` | `write`, `resume`, `read`, `takeover`, `note` |
| Closing step | `scripts/closing-step.sh` | push and stray checks before the brief |
| Context reader | `scripts/context-size.sh` | newest usage after the last compaction |
| Compaction hook | `hooks/pre-compact-note.sh` | tells the session to write its note |

niwa's and koto's code change nothing, though koto's sync, retention and read
access now carry file bytes and so are part of this design's exposure
(Security Considerations). Turning compaction on for a role would be a
workspace-config change (the passthrough entry and the hook install), which
this work documents and doesn't make. #1785's `handover.sh open` gains one
call to `handoff-brief.sh takeover` before its supersede. /coordinate's
handover gains one call to `handoff-brief.sh write` in its adoption step.

### Components

**`handoff-brief.sh write`** takes `--reasoning <file>`, repeated `--file
<path>`, `--event end|park|handover`, `--instance <root>`, optional `--watch
"<label>=<re-arm command>"` and `--standing-rules <file>`. Pointers are read,
not passed: the session (`KOTO_SESSION` when set, otherwise a new plain
session named `handoff-<job-id>` opened through `skill-session.sh`), the
current branch, the open pull request from `gh pr view`, and the remote
branch's commit from `git ls-remote`, by remote name and never by URL. The
job id is the base name of the harness's job directory and the session id is
the `sessionId` in that job's state file; either is null when absent. Both
the `KOTO_SESSION` value and a derived `handoff-<job-id>` must match koto's
session-name grammar before they name a session, and the script refuses
otherwise.

It refuses, writing nothing, on: empty reasoning once whitespace is trimmed;
a named path that isn't a regular file, has a symlink in it, or is missing or
unreadable; a path outside scratch as the PRD defines it (the job's scratch
directory, and loose files at the instance root outside any repo), which
leaves out every repo worktree, since a file there is either pushed or stray,
and `.git/`, `.niwa/` and `.claude/`; a basename matching a credential
pattern (`.env*`, `*.local.*`, `.local.env`, `.mcp.json`, `*.pem`, `*.key`,
`*.p12`, `*.pfx`, `id_*`, `.netrc`, `.npmrc`, `.pypirc`, `.git-credentials`,
`*.tfstate`, `credentials*`, `settings*.json`, `*secret*`, `*token*`); a hit
from a scan for token shapes (private-key headers, `gh[pousr]_`,
`github_pat_`, `glpat-`, `xox[abprs]-`, Slack webhook URLs, `AKIA`, `AIza`,
`sk-ant-`, `sk_live_`, `npm_`, `pypi-`, `SG.`, JWT-shaped strings, bearer
headers, `user:secret@` URLs) over the files, the reasoning, the standing
rules and the watch strings; a newline, a control character, a Unicode format
character (the tag block, bidirectional overrides, zero-width characters) or
a tab in a named path or a watch value; a watch value holding a shell
operator (`;`, `|`, `&`, `$`, a backtick, `<` or `>`), so a watch is one plain
command; `handover/brief.md` over the inline size once rendered; a total over
the record cap. A pointer (pull request number, commit, branch, job id) that
doesn't match its expected shape is left out. Under the owner's 2026-11-16
bucket ruling (scratch is disposable, and no plain transcript leaves the
host), a session transcript is never named, raw or copied: the raw one sits
outside scratch, and the script refuses a copy by its `*.jsonl` name or by a
first line that parses as a transcript record.

It copies each file once into a private 0700 temporary directory and takes
the size, the hash and the stored bytes from that copy; a trap removes that
directory on every exit, refusals included. It stores the inline keys, writes
`handover/brief.md`, then writes the record, in that order, so a record never
points at a brief that isn't there. If a later store fails, it removes the
keys this call already stored before it exits, so no orphan file key is left
on the backend.

**`handoff-brief.sh resume --instance <root>`** voids a park's hold as
Decision 2 says. **`read [--session <name>]`** (the calling session by
default) prints a brief with its Files section apart from and after the free
text, verifies each inline key's hash, replaces control and Unicode format
characters with a visible mark, and prints watch commands as data without
running them. A successor re-arms a watch only by running it itself, under
its own permission settings, never because `read` printed it.
**`takeover --scratch <dir>`** is Decision 3: inside #1785's open it also
takes `--predecessor <session>` and `--instance <predecessor root>`, and with
no koto run it takes `--from <brief session>` instead. **`note --reasoning
<file>`** scans the text as `write` does and stores
`handover/compaction-note.md`; it names no files and writes no record.

The Files section has one line per file, its fields separated by a single
tab, which `write` refuses inside a path: the location (`scratch:` or
`instance:` followed by the path relative to that root), `sha256:<hex>`,
`bytes:<n>`, and `inline:yes` or `inline:no`. A path may hold spaces. The
record holds each file's absolute path, and `write` renders the section from
the file list it is about to write to the record, by taking the path
relative to whichever root contains it. `read` and `takeover` refuse a line
that doesn't have exactly those four fields in that order.

**`closing-step.sh`** is Decision 4. It takes a worktree, checks that the
path is a worktree of the instance, runs git with `git -C` on it, and prints
`closing=pass` and the instance root with exit 0, or `closing=blocked` with
one line per cause and exit 1; exit 2 is an environment fault.

**`context-size.sh`** reads a transcript JSONL and prints the input-token
total of the newest assistant message after the latest compaction boundary.
Its `jq` filter selects only the usage integers and its stderr is dropped, so
no transcript text reaches its output.

**`pre-compact-note.sh`** is a PreCompact hook. It prints the instruction to
write the note through `handoff-brief.sh note` (reasoning and pointers only,
and no credentials) and the summary line naming `handover/compaction-note.md`
as the key to re-read. It ignores its
stdin, exits 0 on every path so it can't block a compaction, names no files,
touches no record, and changes no scratch.

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
scratch:<relative path><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:yes
## Standing rules
None stated.
```

The brief uses four key names under `handover/`: `brief.md`, `files/<sha256>`,
`taken-by` and `compaction-note.md`. #1785's own keys under that prefix must
not reuse them, and Phase 4 checks that when it adds the call to
`handover.sh open`.

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
   inline file keys from its carried session or from the cloud backend. The
   brief's Files section is rendered from the record when the brief is
   written, so a host with no record still has the names and hashes to check;
   the remover reads only the record, which stays the one list R5 names.
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

Deliverables: `scripts/handoff-brief.sh` with `write`, `read`, `resume` and
`note`;
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
script, and the top-level sessions follow last. No supervising session adopts
it before the takeover checks (Phase 4) and the heading, watch and Unicode
refusals (Phase 2) have shipped, since a poisoned brief would otherwise reach
the sessions every other role trusts.

## Security Considerations

The brief script reads files a session names and writes their bytes into koto
keys, which may sync to a cloud backend and may outlive the instance. That is
the main exposure here: a file holding a credential would travel with the
brief and stay on the backend after local scratch is gone. A warning in the
reference doc doesn't stop a model from naming such a file, so the script
refuses instead, on the path rules, name patterns and token scan that `write`
lists. Named files are confined to scratch, so a file in a repo worktree
(where niwa writes the instance's own secrets) can't be named at all. The
name check and the token scan run on the resolved path and the private copy,
and the source is checked again after the copy, so a file swapped after the
check can't put other bytes under a verified hash. The scan is a net with
holes, not a guarantee, and the reference doc says so. Removing a key with
koto's own command doesn't undo a sync or an earlier backend version, so the
reference doc's guidance for a credential the scan missed is to rotate it
first and remove the key second. The script never stores a remote's URL.

Read access follows the koto backend: anyone who can read a session's
backend can read its brief and its inline files, and a session name such as
`handoff-<job-id>` is not a secret. That is a change from today, when scratch
stays on its host and dies with the instance. R1 and R4 ask for it, since a
small named file has to cross hosts to be useful.

Whether a named file travels by default or only when a brief asks is settled
here, not left open: it travels once named. Two facts make that a design call
rather than a new requirement. koto's backend is local unless a host or
workspace turns cloud sync on, and once it's on every context key syncs, so
the workspace has already chosen whether anything leaves the host. And a file
travels only when the session names it, so naming it is the request. A
second, opt-in flag would turn every small file a model forgot to flag into a
by-reference entry, which under the interim rule (R6) holds the instance and
hands nothing across hosts, while the file it does send passes the same scan.
A per-file opt-out has the same cost and gives nothing a session can't get by
not naming the file; it can come back once the kept set exists and by
reference no longer means a hold. Keeping files on their host whatever the
backend would change R1, R4 and R6, which is a requirements change and not
this design's. The reference doc says the backend decides whether a named
file leaves the host.

The script writes in three places: `handover/` keys in its own session, the
keep record in `<instance>/.niwa/` (with the protections Decision 2 lists),
and the takeover mark in a predecessor's brief session, which is written
only when absent, is advisory, and gates nothing. The remover reads the keep
record as untrusted input too, and its own review fields bound how long a
session can pin its instance with a hold.

The successor's side is where hostile text would land. A predecessor steered
by such text can write a brief that tries to instruct its successor, so the
design keeps every part of a brief as data. On takeover the list is
untrusted, and Decision 3 confines paths, caps bytes, re-runs the name check
and the scan, and refuses when the record and the brief disagree. Free text
can't open a forged section (Decision 5), `read` marks control and Unicode
format characters, a watch is one plain command that the successor runs only
under its own permission settings, and the Standing rules section is the
predecessor's claim until the other work's check confirms it. Backend write
access is trusted: someone who can write the koto session can plant a key or
text, which the brief's names and hashes limit for files but can't stop for
prose. Supervising sessions adopt the brief only after these controls ship
(Implementation Approach, Phase 6).

The closing step reads file names and counts from git, never contents, and
turns off the two git settings that run a program on a status read. The
context reader prints one integer from a transcript and nothing else. The
compaction hook ignores its stdin, prints fixed text, and exits 0 on every
path, and the note it asks for goes through `note`, which runs the same scan.
The residual risks are the limits of a pattern scan, the backend's retention
of synced keys, which koto owns, and the read and write trust placed in
whoever can reach the koto backend.

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
- Named file content now lives in koto keys, may sync to a cloud backend, and
  may outlive the instance there.
- A model can still name a credential the pattern scan misses.
- A no-run brief session lingers until retention removes it.
- Nothing is placed in a work-on run yet, so the end-to-end check waits for
  #1230.

### Mitigations

- The interim rule makes the by-reference case a hold, which is safe, and the
  reference doc says to keep named scratch small.
- File content in koto keys is limited to named scratch files at or below
  256 KiB, and it leaves the host only when the workspace has turned koto's
  cloud sync on, which the reference doc states.
- The scratch-only rule, the name patterns and the token scan refuse the
  common cases, and the reference doc says the scan has holes and that a
  missed credential is rotated before its key is removed.
- Seven days idle is long enough for a next-day pickup and short enough not
  to pile up.
- Every script has checks that run with no work-on run (R16), so the scripts
  are proven before #1230 places them.
