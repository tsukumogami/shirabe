---
schema: design/v1
status: Planned
problem: |
  A finished /work-on run leaves the build tree its verification commands
  wrote in the worktree, and no work-on state removes it. A repo has no place
  to say which paths are build output, a workspace has no switch to have
  finished runs remove them, and koto's suite builds larger trees than it
  needs because a cargo setting exported in the shell never reaches it.
decision: |
  An optional top-level `build_output` array of literal paths in the
  verification map, read at the run's pinned base. A `## Build Output
  Cleanup: on` header in the uncommitted CLAUDE.local.md turns the cleanup
  on. A new `clean-build-output.sh` checks each path in a fixed order,
  renames the passing ones into the worktree's git directory and deletes them
  detached, recording the end; the verification runner waits on a running
  removal. A plan's parent cleans once per worktree; a fix round cleans at its
  own end.
rationale: |
  Every piece reuses something shirabe already has: the map read at the
  merge base, the fence-aware header reader, the run's pinned base. Renaming
  first takes the tree off its path at once, so the state returns inside
  koto's 30 s action limit and no later build races the deleter. Only the
  local file can turn it on, so a developer's clone keeps its warm tree
  whatever the repo declares.
upstream: docs/prds/PRD-build-output.md
decision_provenance: inline-resolved
---

# DESIGN: Build Output

## Status

Planned

## Context and Problem Statement

A `/work-on` run verifies a change by running the commands the repo's
verification map selects (`skills/work-on/scripts/run-verification.sh`, which
reads `.claude/shirabe-extensions/verification-map.json` with `git show` at
the run's pinned merge base). For a compiled repo those commands write a
build tree into the worktree, and no state in the work-on template removes
it. The PRD asks for four pieces, and each lands on code that already exists.

The declaration has to live in the verification map, as a new optional
top-level field next to `schema`, `commands`, `entries` and `default`, made
of literal repo-relative paths (R1). It has to be read from the same base the
run already pinned: verification's recorded `merge_base`, or `impl_base` for
a run that has no `result.json` because it relies on hosted CI. It is never
recomputed at cleanup time, because after a merge and fetch the merge base
can be HEAD itself (R2). A malformed declaration must not make the map
invalid, so its check stays out of `SELECT_JQ`, the jq program that turns the
map into the selected invocations (R8). Each declared path is refused, in a
fixed order and with a fixed word, when it's absolute, outside the repo, a
symlink or under one, tracked, not ignored, or protected (it holds the git
directory, a nested clone or a mount, or is one of a fixed set of local
files). After `absolute` and `outside`, a path that doesn't exist is
reported `gone` and checked no further (R3). Only the paths that pass are
removed (R5).

The switch has to be per workspace and never come from the repo. The cleanup
runs only when the declaration exists and a header with its one on value sits
in the uncommitted `CLAUDE.local.md`; the committed `CLAUDE.md` is never read
for it (R4). That differs from `scripts/pr-workflow-content.sh`, which reads
local and then committed; `scripts/lib/claude-md-header.sh` is the
fence-aware reader to reuse.

The cleanup runs once per run, at the run's successful end with hosted CI
green, or at the successful end alone in a repo with no hosted checks (R6).
It never runs on a verification pass, on a return to implementation, in the
CI fix loop, when the run is blocked, or at `done_already_complete`. After CI
is green the order is the closing step, then the handoff brief, then the
cleanup, and nothing after it reaches implementation or verification (R7).
Which work-on state carries it is held for the design of
tsukumogami/shirabe#1230 (draft PR tsukumogami/shirabe#1881), which is
changing implementation, verification and `done_blocked`. This design fixes
the mechanism and the order and leaves the state named as open. The cleanup
never changes the run's outcome (R8).

A plan complicates the once-per-run rule. A child on a shared branch (the
`pr_creation` to `done` edge on `pr_status: shared`) and a child whose
worktree a later child uses must not clean, or the next child rebuilds from
cold; the plan's parent cleans once per plan, once per worktree in
coordinated mode, at its own successful end (R9).

Removal has to fit koto. A default action returns within koto's fixed 30 s
limit with no override, while gates take a `timeout:`. Removing a 9 GiB tree
can take longer than that on a loaded disk, so the state must return control
within 30 s, record when the removal ends, and keep a later run in the same
worktree from building while a removal is still running (R12).

The suite side is separate and small: `CARGO_INCREMENTAL=0` on every cargo
command in koto's map, set in the same place on each of those commands,
right after the wrapper script every command in that map already runs
through, with koto's prose command list changed
alongside, planned against tsukumogami/koto#490 (R11). The field is a stable
part of the map's schema (R10), older shirabe releases ignore it (R13), and
there's no telemetry (R14) and no debug-information setting until the
measured build runs (R15).

## Decision Drivers

- **Nothing on by default.** A repo's declaration alone changes nothing; only
  a workspace's local header turns the cleanup on (R4).
- **The branch can't widen its own cleanup.** Every read of the declaration
  uses the base the run pinned before the branch's changes, and a base that
  isn't an ancestor of HEAD and of the upstream default branch counts as
  unreadable (R2).
- **Fail toward keeping.** Any doubt about a path (its shape, a symlink, a
  tracked file, a nested clone or mount, an unreadable base) keeps the tree
  and says why (R3, R8).
- **Reuse, don't fork.** Read the map the way `run-verification.sh` already
  does, and the header with `scripts/lib/claude-md-header.sh`.
- **Fit koto's limits.** The state returns within 30 s and records the end of
  any removal still running (R12).
- **Don't place what's held.** The work-on state that carries the cleanup
  waits on the tsukumogami/shirabe#1230 design; the mechanism, the order and
  the declaration don't (R7).
- **Backward compatible.** Older releases ignore the field, and the map's
  schema string doesn't change (R10, R13).
- **One mechanism for every caller.** The same script serves a work-on run's
  end, a plan parent's end and any instance remover that reads the field.

## Considered Options

### Decision 1: The declaration's name and shape

Resolved inline. The cleanup and any instance remover need one repo-wide list of the paths
that are build output. It has to sit in the verification map, read at the
run's pinned base, and must not disturb the map's existing parse (R1, R10,
R13).

#### Chosen: a top-level `build_output` array of literal paths

```json
{
  "schema": "shirabe-verification-map/v1",
  "commands": { "...": {} },
  "entries": [],
  "build_output": ["target/"]
}
```

Each entry is a repo-relative path string. A leading `./` and a trailing `/`
are dropped before comparison, duplicates collapse, and a path nested under
another declared path is handled once, under its parent (R1). The schema
string stays `shirabe-verification-map/v1`, because an older release ignores
an unknown top-level field (R13). The field's check runs in the cleanup
script, not in `SELECT_JQ`, so a malformed declaration never makes the map
invalid for verification (R8): a non-list is one `malformed` line and removes
nothing, and a non-string or empty entry, or one holding a newline or other
control character, is named `malformed` and skipped.

#### Alternatives Considered

**Per-command `outputs`**: each entry under `commands` names the paths it
writes. Rejected because two commands that share `target/` would both declare
it, and every reader would have to union the lists to learn what the repo's
build output is.

**An object (`build_output: {paths: [...]}`)**: leaves room for options per
path. Rejected because no caller needs an option, and every reader pays an
extra level for room that R10 would make a schema change to use anyway.

### Decision 2: The switch

Resolved inline. The cleanup must stay off unless a workspace turns it on, and a line
committed to the repo must never turn it on for someone's own clone (R4).

#### Chosen: `## Build Output Cleanup: on` in CLAUDE.local.md

The script reads the header with `claude_md_header "Build Output Cleanup"
CLAUDE.local.md` from `scripts/lib/claude-md-header.sh`, which is fence-aware
and refuses a duplicate. That reader matches the header's name in any case,
so the script also checks that the matched line spells the name exactly
`Build Output Cleanup`; a wrongly cased name means off, as the PRD asks. The
value `on`, trimmed and case-insensitive, turns it on. An absent file or
header, a wrongly cased name, any other value, a duplicate or an
unreadable file means off; the last two are reported, since they mean
someone tried to set it. The committed `CLAUDE.md` is never read for this
header. A `CLAUDE.local.md` that git tracks, or one that is a symlink, leaves
the switch off and the script says which, so committed content can't reach
the switch through a link either. A workspace that generates
`CLAUDE.local.md` adds the line once in its config, and every worktree it
makes carries it.

#### Alternatives Considered

**An environment variable**: an operator exports a variable. Rejected
because koto runs a session's commands with a fixed environment, so a
variable exported in the ticking shell never reaches the state
(tsukumogami/koto#578).

**Local then committed, as `scripts/pr-workflow-content.sh` reads**: the
script reads the header from `CLAUDE.local.md` and, when that has none, from
the committed `CLAUDE.md`, so a repo could ship the switch on. Rejected
because a committed line would turn the cleanup on for every
developer who clones the repo, which R4 forbids.

**A setting in a workspace manager's config**: the manager that provisions
the worktree records the switch, and the script asks it. Rejected because it
ties the feature to one manager and gives a plain clone no way to turn it on;
the header works with one manager, another, or none.

### Decision 3: Fitting removal into koto's time limit

Resolved inline. A default action returns within 30 s with no override, and removing a 9 GiB
tree can take longer on a loaded disk. The state has to return in time,
record when the removal ends, and keep a later run in the same worktree from
building while it's still running (R12).

#### Chosen: rename into the git directory, then delete detached

`clean-build-output.sh` checks each path. Each one that passes is renamed, in
declaration order, to a numbered entry `trash-<stamp>/<n>` (n from 1) under
`$(git rev-parse --git-path shirabe-build-output)`, the worktree's own git
directory. That's on the same filesystem, so the rename takes constant time,
and numbering means `a/target` and `b/target` can't collide. The script first
compares the device ids of the path and the trash directory: a path on
another filesystem can't be renamed in constant time, so it's reported
`failed` and left in place. Then it writes `removal-<stamp>.json` beside
`trash-<stamp>` (`started_at`, a map from each n to the path as written, the
deleter's pid, `status: running`), starts a detached `rm -rf` of that trash
that rewrites the same record with `status: done` or `failed` and `ended_at`
when it exits, prints one line per path, and returns.

There's one record per removal, and a call never rewrites another removal's
record. A second call while a deleter is still running (a plan parent
cleaning its worktrees in turn, a fix round right after `done`, a retry)
leaves that deleter's record and trash alone. At its start the script reaps:
a record whose status is `running` but whose pid is dead is marked `failed`,
and its trash goes to this call's detached delete.

Before it builds, `run-verification.sh` reads the records and waits, inside
its own budget, while any of them says `running` with a live pid. A record
whose pid is dead counts as ended; the runner leaves its trash for the
script's next call to reap. If the budget runs out while a record still says
`running` with a live pid, as it can with a reused pid, the runner builds
nothing: it starts no command, reports the verification as not run, and
prints one line naming the record. That keeps R12's rule that nothing builds
during a removal. The git directory is never part of the work
tree, is never tracked, and is private to each worktree.

The rename frees the build path at once, so a later build can't race the
deleter on the path itself. R12 asks for more than that: a later run in the
same worktree mustn't build while a removal is still running, because the
build and the delete compete for the same disk. A 9 GiB delete and a fresh
build in the same worktree on a full disk is the case the PRD names, and the
runner's wait is what meets it. Reaping lives in the script, so the runner's
change is that one wait.

#### Alternatives Considered

**A gate running `rm -rf` with a `timeout:`**: Rejected because a gate that
times out leaves the tree half removed and the run held on its cleanup, and
the cleanup must never change the outcome (R8).

**A detached `rm -rf` in place**: Rejected because a later run that builds
in the same path races the deleter, and the two can interleave.

**Rename now, sweep later**: Rejected because the disk stays used until
something sweeps it, which is the problem this feature removes.

**Rename, and drop the runner's wait**: the rename already frees the build
path, and the script could reap a dead record's trash at its next call.
Rejected for R12: without the wait, a fresh build and a 9 GiB delete run
against the same disk at once, which is the case R12 exists to stop. The
reaping half of this option is taken; the wait stays in the runner.

### Decision 4: Where a plan's parent cleans

Resolved inline. A child on a shared branch, or one whose worktree a later child uses, must
not clean, and the plan's parent cleans once per worktree at its own
successful end (R9). Where the parent cleans is settled here: at
`/execute`'s successful end, after CI is green, once per recorded worktree,
and at the end of the multi-pr driver's item loop. What stays open is the
work-on state that calls the script for a single run, held for the
tsukumogami/shirabe#1230 design.

#### Chosen: the run that owns the worktree's last use cleans it

A `/work-on` run that a plan parent dispatched never cleans, whatever its
edge, and the shared-branch edge (`pr_creation` to `done` on `pr_status:
shared`) never cleans either. `/execute` cleans at its successful end, and
the two templates reach that end differently.

In single-pr mode, `plan_completion` runs before `ci_monitor`, so it can't
carry the cleanup: CI isn't being watched yet. The successful ends are the
two terminals past `ci_monitor`, `merge_readiness` and `merge_route`:
`merged`, which only `merge_confirm` reaches (`merge_attempt` hands it a
called merge, and `merge_route` hands it one already merged), and
`ready_awaiting_merge`, which `merge_route`, `merge_attempt` and
`merge_confirm` can each route to. The parent cleans once, in its one
worktree, on the way into either terminal, and only when the owned pull
request's hosted CI is green at the head it reached them with; `ci_monitor`
can hand `merge_readiness` a pending CI, so the call checks rather than
assumes. With CI not green it cleans nothing and the tree stays. It never
cleans at `plan_completion`, and never on `done_blocked`, which `ci_monitor`
and `merge_route` can both reach.

The coordinated template, `execute-coordinated.md`, has no
`plan_completion` state. Its successful ends are `ready_awaiting_merge`,
which `coord_verdict` or `coord_merge_confirm` routes to, and `merged`,
which only `coord_merge_confirm` reaches. It cleans once per recorded
worktree on the way into either, under the same CI-green check.
`paused_awaiting_merges`, `done_blocked` and `done_error` aren't successful
ends, and none of them cleans.

Which exact state carries the call in each template is the implementer's to
wire, within those bounds. These are `/execute` states, outside the work-on
states the tsukumogami/shirabe#1230 design is changing.

A plan parent has no `result.json` or `impl_base` of its own, so it pins
its own base. When its run starts it records, in its own session, one base
per repository: the commit the default branch's remote ref names at that
moment. It passes that as `--base` for every worktree of that repository
and never recomputes it. Every child's base comes after it, so the pinned
base is an ancestor of every child's head and the script's ancestry check
passes. After the branch's pull request merges and the default branch is
fetched, a recomputed merge base would be the branch head itself, which is
why the parent keeps the base it pinned at its start (R2).

In a multi-pr PLAN, `/work-on` is the driver: it takes the items one at a
time, so the driver itself, not a child, knows when no item remains. It calls
the script once, when its item loop finds no next item, in the one worktree
the items share. That loop is prose in `skills/work-on/SKILL.md`, not a
template state, and each item runs in its own session, so no state of the
tsukumogami/shirabe#1230 design carries the call: the skill's loop makes it
itself after the last item. Each item would otherwise reach an ordinary
single run's successful end and clean the worktree the next item reuses
(R9), so every item session the driver opens counts as dispatched by a plan
parent and never cleans; the driver records that on the item's session when
it opens it, and the single run's caller skips the cleanup when it finds
the mark. The driver has one result per item and no base of its own that
covers them all, so it pins its base the way a plan parent does: when its
run starts it records the commit the default branch's remote ref names then,
and passes that as `--base`, never an item's `merge_base` or a recomputed
one.

#### Alternatives Considered

**The last dispatched child of a plan parent cleans**: Rejected because
`/execute`'s children run independently, and none of them can know it's the
last. The multi-pr case isn't this option: no child decides anything there,
because the driver iterates the items itself and sees its loop end.

**Every child cleans**: Rejected because each later child then rebuilds from
cold, the cost R9 exists to prevent.

### Decision 5: A fix round's end

Resolved inline. `fix-round.sh` starts a new run on the same worktree after `done`. The
question is whether that run's own successful end cleans again.

#### Chosen: yes, like any run

A fix round is a run of its own, and it rebuilt the declared tree. Its
successful end with CI green cleans it, the same way. It already starts
cold, because the first run's end cleaned, and that cold build is the cost
of a finished run leaving nothing.

#### Alternatives Considered

**Skip the cleanup at a fix round's end**: Rejected because the fix round's
tree stays, which is the original problem in a smaller form, and it would
need a second rule in the template that readers have to know about.

## Decision Outcome

The repo declares `build_output` in its verification map, and a workspace
turns the cleanup on with one header in `CLAUDE.local.md`. At a run's
successful end, after the closing step and the handoff brief, one script
reads the declaration at the run's pinned base, checks every path, renames
the passing ones out of the work tree and deletes them in the background,
then returns. Nothing a branch commits can widen what its own run removes, a
developer's clone keeps its tree, and a later build waits for a removal that
hasn't finished.

The pieces fit because they all resolve to one script and the records it
writes, one per removal. The work-on end, the multi-pr driver's item loop,
`/execute`'s successful end after CI is green (once per recorded worktree,
with the base the parent pinned at its start) and a fix round's end all call
`clean-build-output.sh`; `run-verification.sh` reads its records and waits on
any that's still running. The script never fails the run: it prints its
lines and exits 0, whatever it found. The exact work-on state it runs in
stays open until the tsukumogami/shirabe#1230 design settles; the order
(closing step, handoff brief, cleanup) is fixed here.

koto's suite gets `CARGO_INCREMENTAL=0` on every cargo command in its
verification map, in the map itself. All twelve commands in koto's map, the
seven cargo commands among them, already run through koto's wrapper
`scripts/without-session-env.sh`, which ends in `exec "$@"` and so passes its
arguments on unchanged. Each of the seven cargo commands gets
`env CARGO_INCREMENTAL=0` in the same place, right after the wrapper and
before `cargo`; the wrapper itself doesn't change, so nothing else that runs
through it is touched, and the five other commands stay as they are. There's
no
`.cargo/config.toml` change and no `pass_env`. koto's prose command list
changes alongside (R11). That is its own plan item against
tsukumogami/koto#490.

## Solution Architecture

### Components

| Component | Change |
|-----------|--------|
| `skills/work-on/references/verification-map.md` | Documents `build_output` as a fifth, optional top-level field: literal paths, the normalization, the refusal words, and that a remover may read it and the field isn't renamed or changed in meaning without a schema change (R10). |
| `skills/work-on/scripts/verification-map-schema_test.sh` | Accepts a map with and without the field; a malformed field doesn't fail the map. |
| `skills/work-on/scripts/clean-build-output.sh` (new) | Reads the switch at the root, checks its own directory, reaps dead removals, checks the base's ancestry and reads the declaration there, checks each path, renames the passing ones into numbered trash entries, writes one record per removal, starts the deleter, prints one line per path, exits 0. |
| `skills/work-on/scripts/run-verification.sh` | Before building, waits inside its budget on every removal record that says `running` with a live pid. If the budget runs out first, it starts no command, reports the verification as not run and names the record. It doesn't reap; the script does. `SELECT_JQ` is unchanged. |
| work-on template, single run | Calls the script once at the run's successful end with CI green (or the successful end alone with no hosted checks), after the closing step and the handoff brief. Never on a verification pass, a return to implementation, the CI fix loop, a blocked run or `done_already_complete` (R6). The state is named when the tsukumogami/shirabe#1230 design settles. Dispatched children and the shared-branch edge don't call it. |
| `skills/work-on/SKILL.md`, multi-pr item loop | In a multi-pr PLAN, `/work-on` is the driver that takes the items one at a time, so the driver, not a child, knows when no item remains. The loop is skill prose, not a template state: it calls the script itself, once, when it finds no next item, in the one worktree the items share, with the base it pinned when its run started (as a plan parent does). It marks each item session it opens as plan-dispatched, so no item's own successful end cleans. |
| `/execute` templates, successful end | Pin one base per repository at the run's start, in the parent's session. Single-pr: calls the script once on the way into `merged` or `ready_awaiting_merge`, only with the owned pull request's hosted CI green at that head; never at `plan_completion` or on `done_blocked`. Coordinated (`execute-coordinated.md`): calls it once per recorded worktree on the way into `ready_awaiting_merge` (from `coord_verdict` or `coord_merge_confirm`) or `merged` (from `coord_merge_confirm`), under the same CI check; never on `paused_awaiting_merges`, `done_blocked` or `done_error`. The implementer picks the exact state within those bounds. |
| koto's verification map and command list | `env CARGO_INCREMENTAL=0` right after `scripts/without-session-env.sh` on each of the seven cargo commands; the wrapper is unchanged (koto's own item). |

### The script's contract

```
clean-build-output.sh --base <sha> [--root <dir>]
```

`--root` is the work tree root: `CLAUDE.local.md` is read there, and every
declared path resolves against it. It defaults to `git rev-parse
--show-toplevel`. `--base` is the base the run pinned: verification's
recorded `merge_base` from `result.json`, or the run's `impl_base` when it
relied on hosted CI and has no `result.json`. A plan parent has neither, so
it passes the base it pinned when its run started: for each repository, the
commit the default branch's remote ref named at that moment, recorded in the
parent's own session and passed unchanged for every worktree of that
repository. Each child's base comes after it, so it's an ancestor of every
child's head. Neither the script nor its caller ever computes a merge base at
cleanup time.

Callers run it once, at a run's successful end with CI green, or at the
successful end alone in a repo with no hosted checks. It never runs on a
verification pass, a return to implementation, the CI fix loop, a blocked
run or `done_already_complete` (R6). In order:

1. Read the switch from `CLAUDE.local.md` at the root. Off: print
   `build-output: cleanup off` and exit 0. A `CLAUDE.local.md` that git
   tracks, or that is a symlink, counts as off, and the line says which:
   `build-output: cleanup off (CLAUDE.local.md is tracked)` or
   `build-output: cleanup off (CLAUDE.local.md is a symlink)`. A duplicate
   header or an unreadable file counts as off and is reported the same way,
   naming the duplicate or the unreadable file.
2. Check the script's own directory, `<git-dir>/shirabe-build-output`. If it
   exists and is a symlink, or isn't a directory owned by the current user,
   print one `build-output: <dir> failed` line naming it, remove nothing and
   exit 0. If it's missing, create it with plain `mkdir` (no `-p`).
3. Reap. Find each `removal-<stamp>.json` whose status is `running` but whose
   pid is dead. Its trash directory is derived from the record's file name
   (`trash-<stamp>`), never from a path inside the record. Every exit from
   here on goes through step 7, which marks these records `failed` and hands
   their trash to this call's deleter.
4. Check the base. `--base` must name a commit that is an ancestor of HEAD
   (`git merge-base --is-ancestor <base> HEAD`) and, when the upstream
   default branch's remote ref exists locally, an ancestor of or equal to
   that ref. Then read the map with
   `git show <base>:.claude/shirabe-extensions/verification-map.json`. A base
   that fails either check, or an unreadable base or map: print
   `build-output: base unreadable, removed nothing`. No field: print nothing
   more. A non-list: one `malformed` line. Each of these goes to step 7.
5. Normalize each entry. A non-string or empty entry, or one holding a
   newline or other control character, is `malformed`, named and skipped.
   Then check in this order and stop at the first refusal:
   - `absolute`.
   - `outside`: a `..`, any other route out of the root, or `.` itself.
   - A path that passes those two and doesn't exist is `gone` and checked no
     further.
   - `symlink`: the path or any directory on the way. A path that passes has
     its dev:inode recorded here.
   - Before the next two, the path is resolved to its on-disk spelling.
     `tracked`: `git ls-files` names anything at or under it. When
     `core.ignorecase` is true, a path whose on-disk or case-folded spelling
     matches any tracked path is `tracked` too. macOS case-insensitive
     volumes, and NFC against NFD spellings of one name, are the case this
     covers.
   - `not-ignored`: `git check-ignore` doesn't match it.
   - `protected`: the path is or contains the git directory or the common
     git directory; contains a `.git` entry at any depth (a nested clone or
     worktree); contains a directory whose device id differs from the work
     tree's (a mount); or is one of `.git`, `.claude`, `CLAUDE.md`,
     `CLAUDE.local.md`, `.env`, `.env.*` and the `shirabe-build-output`
     directory itself. The walk shares about 20 s across all paths, inside
     koto's 30 s bound; a path whose walk can't finish in its share is
     reported `failed` and not removed.
6. Create `trash-<stamp>` with plain `mkdir`. If it already exists, print one
   `build-output: trash-<stamp> failed` line, rename nothing and go to step
   7. Otherwise, for each path that passed, in declaration order, n from 1:
   compare the device ids of the path and the trash directory; right before
   the rename, re-check that neither the path nor any directory on the way is
   a symlink and that its dev:inode still matches the recorded one; rename it
   to `trash-<stamp>/<n>`; right after, stat `trash-<stamp>/<n>` and compare
   its dev:inode with the recorded one. A match prints `<path> removed`. A
   mismatch renames the entry back and prints `<path> failed`. A cross-device
   path, a failed re-check or a failed rename prints `<path> failed` and
   stays in place.
7. If this call renamed a path or reaped a record, check that neither
   `removal-<stamp>.json` nor `removal-<stamp>.log` is a symlink, write the
   record (`started_at`, the map from each n to the path as written, the
   reaped trash directories, the deleter's pid, `status: running`), mark the
   reaped records `failed`, and start the deleter detached on this call's
   trash and the reaped trash, with its output to the log. It rewrites this
   record with `status: done` or `failed` and `ended_at` when it exits.
   Exit 0.

A path's line is the path as the maintainer wrote it, then its word (R3).
Lines about the switch, the base and the script's own directories start with
`build-output:`.

### Data flow

```
run ends, CI green
  -> closing step -> handoff brief
  -> clean-build-output.sh --base <pinned> [--root <work tree>]
       switch? -- off, tracked or symlink --> exit 0
       <git-dir>/shirabe-build-output ok? -- no --> failed, exit 0
       reap: running record, dead pid -> its trash joins this call's deleter
       base ancestor of HEAD and default branch? -- no --> unreadable
       git show <base>:map -> build_output
       per path: absolute/outside/gone/symlink/tracked/not-ignored/protected
       passing: rename -> <git-dir>/shirabe-build-output/trash-<stamp>/<n>
                dev:inode re-checked; mismatch -> rename back, failed
       removal-<stamp>.json {status: running, pid, n -> path}
       detached rm -rf trash -> removal-<stamp>.json {status: done, ended_at}
  -> exit 0 (outcome unchanged)

/execute parent
  start: pin one base per repository (default branch's remote ref, now)
  single-pr: ci_monitor -> merge_readiness -> merge_route
       -> ([merge_attempt ->] merge_confirm ->) merged | ready_awaiting_merge
       -> hosted CI green at head? clean-build-output.sh --base <parent's pinned base>, once
  coordinated: coord_verdict -> ready_awaiting_merge,
       or coord_merge_confirm -> merged | ready_awaiting_merge
       -> hosted CI green? clean-build-output.sh --base <parent's pinned base>, per worktree
  done_blocked, done_error, paused_awaiting_merges -> no cleanup

next run, same worktree
  -> run-verification.sh reads every removal-*.json
       any running with a live pid -> wait inside budget
       budget out, still running -> build nothing, not run, name the record
       dead pid -> counts as ended (the script's next call reaps it)
  -> build
```

## Implementation Approach

1. **The declaration.** Add `build_output` to `verification-map.md` and the
   schema test. Nothing reads it yet, so it's safe to land first.
2. **The script.** Add `clean-build-output.sh` with its own test suite
   covering every refusal word including `protected` (a nested clone, a
   mount, the fixed list, a walk past its share), the order, `gone`,
   `malformed`, the switch values including a tracked or symlinked
   `CLAUDE.local.md`, an unreadable base and a base that fails the ancestry
   check, a case-folded tracked path, a cross-device path, a dev:inode
   mismatch, a symlinked or foreign trash directory, a pre-existing
   `trash-<stamp>`, numbered entries, a second call during a live removal,
   reaping a dead one, and the record.
3. **The guard.** Teach `run-verification.sh` to wait on every live running
   removal record. It's verification code the tsukumogami/shirabe#1230
   design also changes, so it lands after that design's PR, or rebased onto
   it.
4. **The callers.** Wire `/execute`'s successful ends: the way into
   `merged` or `ready_awaiting_merge` in both templates, only with hosted
   CI green at the head, each with the base the parent pinned at its
   start. Wire the work-on end once the tsukumogami/shirabe#1230 design
   names its state, and the multi-pr driver's loop in
   `skills/work-on/SKILL.md` with it, since the item runs' skip of the
   cleanup sits in that same end.
5. **koto's suite.** `env CARGO_INCREMENTAL=0` on the seven cargo commands
   in koto's verification map, and koto's command list, against
   tsukumogami/koto#490. Independent of the rest.

The measured build that would decide a debug-information setting runs
outside this work, and no such setting is added until it does (R15).

## Security Considerations

The script deletes files, so its checks are the security boundary.

**Where the switch reaches.** The cleanup runs in every repo whose
`CLAUDE.local.md` carries the header, including repos whose map the
developer didn't write. A workspace that writes the header into every repo's
local file turns it on for every repo, whoever wrote that repo's
declaration. The header in each repo is the control, and the deletion is
irreversible.

**What it trusts.** It reads the `build_output` declaration only at the base
the run pinned before the branch's own changes, so a branch can't add a path
to what its own run removes. That base comes from files the working agent can
write (`result.json`, `impl_base`), so the script checks it: the base must be
an ancestor of HEAD and, when the upstream default branch's remote ref exists
locally, an ancestor of or equal to that ref. A branch's own commit, or an
unmerged commit carrying a wider map, fails and counts as unreadable, so
nothing is removed. That closes the case of a confused or prompt-injected
agent widening the cleanup by editing a state file. It doesn't stop the
worker itself, which could run `rm` directly. The switch is read only from
`CLAUDE.local.md` at the work tree root, and only when that file is neither
tracked by git nor a symlink; either leaves the cleanup off and says so, so
committed content can't turn it on for someone's own clone.

**What it checks before anything moves.** Each path must be relative, stay
inside the root, pass through no symlink, cover no tracked file, be ignored
by git, and not be protected. Tracking is checked against the path's on-disk
spelling and, when `core.ignorecase` is true, its case-folded spelling, so
`Target/` against a tracked `target/` on a macOS case-insensitive volume, or
an NFC name against its NFD form, reads as `tracked`. Being ignored doesn't
make a path disposable, so `protected` refuses a path that is or holds the
git directory or the common git directory (in a non-linked clone `.git` sits
inside the work tree), a path holding a `.git` entry at any depth (a nested
clone or worktree, whose unpushed commits exist nowhere else), a path holding
a mount, and a fixed list of local files: `.git`, `.claude`, `CLAUDE.md`,
`CLAUDE.local.md`, `.env`, `.env.*` and the script's own directory. The walk
behind it shares about 20 s of koto's 30 s; a path it can't finish is
`failed` and kept. A path that fails any check is named and kept. Entries are
literal data: the script quotes them, passes them after `--`, never expands
globs, and treats an entry with a newline or other control character as
`malformed`.

**How it removes.** The script refuses to start if
`<git-dir>/shirabe-build-output` is a symlink or isn't a directory the
current user owns, and it creates that directory and each `trash-<stamp>`
with plain `mkdir`, so a planted entry fails the call instead of redirecting
it. Each path is renamed to a numbered entry in the worktree's own git
directory (the script's test suite asserts that `git rev-parse --git-path`
resolves there in a linked worktree), after a device-id comparison that fails
toward `failed` and leaves the path in place, and after a last symlink and
dev:inode re-check. Right after the rename, the entry's dev:inode is compared
with the one recorded at the symlink check, and a mismatch renames it back
and reports `failed`. Records and logs are written only after a check that
their path isn't a symlink. The detached `rm -rf` runs only on `trash-*`
directories the script created or reaped, with each path computed from the
git directory and the record's file name and a non-empty and prefix check,
never from a path inside a record. The runner only reads records and waits;
it removes nothing. A recorded pid that has been reused makes a later run
wait, at most its own budget; if the budget runs out first, the run builds
nothing and reports its verification as not run, naming the record.

**Data.** Nothing is sent anywhere (R14). The records and the deleters' logs
hold only paths from the repo's own map, pids and timestamps, in the git
directory, and go with the worktree.

**Residual risk.** Deletion can't be undone once the detached removal runs. A
declared tree that holds untracked files a worker wrote by hand loses them;
the maintainer's declaration, made at the pinned base and limited to ignored,
unprotected paths, is the accepted boundary. The dev:inode comparison catches
a path swapped between the check and the rename, and the rename back keeps
it. What remains is a change inside the tree after its walk: a mount or a
clone placed inside a declared tree between the `protected` walk and the
detached delete isn't seen. That needs a process writing to the worktree at
the run's end. In a clone with no local remote ref for its default branch,
the base check falls back to ancestry from HEAD alone, which a branch's own
earlier commit passes.

## Consequences

### Positive

- A finished run in a workspace that turned the cleanup on leaves no declared
  build tree, and every other checkout keeps its tree.
- A remover gets a declaration it can read for build systems that write no
  marker.
- koto's suite builds a smaller tree, and hand-run builds don't change.

### Negative

- A fix round and a re-run after `done` build from cold.
- Files a worker wrote by hand inside a declared tree go with it.
- The verification runner gains a wait on a running removal.
- Rarely, a verification doesn't run: when the runner's budget runs out while
  a record still says `running` with a live pid (a reused pid, say), it
  builds nothing and reports the verification as not run.
- A run that blocks, or a worker that dies, keeps its tree; the cleanup only
  bounds runs that finish.

### Mitigations

- The cold build is the accepted cost of leaving nothing, and only fix
  rounds and re-runs pay it.
- The wait is bounded by the runner's own budget, a dead deleter's record
  counts as ended, and the script's next call reaps its trash. A wait that
  runs out builds nothing and names the record it waited on, so the
  verification that didn't run says why.
- Trees left by blocked or dead runs are the instance remover's to trim, and
  it reads the same declaration.
