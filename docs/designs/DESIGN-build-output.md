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
  removal. A plan's parent cleans once per worktree with the base it pinned
  for that worktree, and a session it dispatched never cleans; a fix round
  cleans at its own end unless it's plan-dispatched.
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
run already pinned: the `merge_base` of the settled result that
`check-verification.sh` stores as the `verification_results.json` context
key, or `impl_base` for a run with `VERIFICATION=hosted-ci`. It is never
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

The script reads the header through `scripts/lib/claude-md-header.sh`, which
is fence-aware and refuses a duplicate. That reader matches the header's name
in any case and can't tell a dangling link, an unreadable file and a
duplicate apart, so the script makes its own checks first, in this order, on
`<switch-root>/CLAUDE.local.md`: a symlink (`-L`), tracked (`git -C
<switch-root> ls-files --error-unmatch`), readable (`-r`). Only then does it
call the library's new `claude_md_header_named <name> <file>`, which prints
`<name as written><TAB><value>`, so its exit 2 can only mean a duplicate. The
script checks that the name as written is exactly `Build Output Cleanup`; a
wrongly cased name means off, as the PRD asks. The
value `on`, trimmed and case-insensitive, turns it on. An absent file or
header, a wrongly cased name, any other value, a duplicate or an
unreadable file means off; the last two are reported, since they mean
someone tried to set it. The committed `CLAUDE.md` is never read for this
header. A `CLAUDE.local.md` that git tracks, or one that is a symlink, leaves
the switch off and the script says which, so committed content can't reach
the switch through a link either. A workspace that generates
`CLAUDE.local.md` adds the line once in its config, and every worktree the
workspace manager makes carries it. Worktrees a run makes for itself don't:
`/execute`'s `node-cut.sh` creates each node worktree with a plain `git
worktree add`, which brings no untracked file along. So the switch is read
where the run's own instructions are, not in every tree it cleans. The
script takes `--switch-root`, the work tree whose `CLAUDE.local.md` holds the
switch. It defaults to `--root`, and a plan parent passes its own checkout's
root for every worktree it cleans. Nothing in this feature writes the header. The operator,
or the workspace manager's config, adds it, and the schema reference in
`verification-map.md` says how.

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
declaration order, to a numbered entry `trash-<stamp>/<n>` (n from 1) in the
worktree's own git directory (`bo_dir`, in the script's contract). That's on
the same filesystem, so the rename takes constant time, and numbering means
`a/target` and `b/target` can't collide. The script first compares the
device ids of the path and the trash directory: a path on another
filesystem is reported `failed` and left in place. Then it starts a detached
deleter on that trash, writes `removal-<stamp>.json` beside it, prints one
line per path, and returns. The deleter rewrites the record with `status:
done` or `failed` and `ended_at` when it exits. The git directory is never
part of the work tree, is never tracked, and is private to each worktree.

The deleter is `clean-build-output.sh --delete <stamp>`, started the way
`run-verification.sh` starts its supervisor: a `set -m` job, so koto's group
kill of the action never reaches it, with stdin from `/dev/null`, output to
`removal-<stamp>.log` and `KOTO_TICK_SESSION` unset. Its command line is how
a pid is judged. `bo_record_live <record>`, in the new
`skills/work-on/scripts/build-output-lib.sh`, reads a record live only when
it parses, says `status: running`, its `pid` answers `kill -0`, and `ps -p
<pid> -o command=` names `clean-build-output.sh --delete <stamp>` for that
record's stamp. The reaper and the runner both source it, so a record can't
read ended to one and live to the other, and a recycled pid running another
program reads ended. A record that doesn't parse (not one JSON object, no
string `status`, or `status: running` without a positive integer `pid`)
counts as ended for the runner; the reaper leaves it and its trash in place
and says so.

There's one record per removal, and a call never rewrites another removal's
record. A second call while a deleter is still running (a plan parent
cleaning its worktrees in turn, a fix round right after `done`, a retry)
leaves that deleter's record and trash alone. At its start the script reaps:
a record that says `running` but reads ended is marked `failed`, and its
trash goes to this call's deleter.

The removal's end is recorded in `removal-<stamp>.json`, which lives as long
as the tree it removed: `git worktree remove` takes both at once, and then
nothing is left to wait on or audit. The script prints that record's
absolute path as `build-output: removal recorded at <path>`, and the caller
stores the script's lines once in the run's session as the context key
`build_output_cleanup`. The deleter writes nothing to koto.

`run-verification.sh` waits in two places. The supervisor (`--supervise`),
after it takes `sup_start` and before its first command, waits while any
record reads live, so the wait spends the run's own budget and `--start`
still returns within a second. Out of budget with a record still live, it
starts no command and writes a result with the new status
`removal-running`, `commands: []` and `detail` naming the record, the way it
writes `supervisor-error`. `check-verification.sh` holds the gate on it at
exit 2, as on `supervisor-error`: no finding, a message naming the record,
and the same two ways on (move the result aside and tick once the removal
has ended, or submit `verification_status: blocked`). `--start` keeps the
result, so a held tick never starts another full wait by itself. Under the
tsukumogami/shirabe#1230 design it's never eligible for a re-run:
`verification-eligibility.sh` lists it as ineligible beside
`supervisor-error`, so it isn't archived and doesn't count against the
per-head cap. Nothing builds during a removal (R12).

The second place is the run's start, since setup's baseline step builds
before verification runs. `run-verification.sh --await-removals` takes no
`--session`, resolves no merge base, reads only the records' directory, and
checks once: exit 0 when nothing reads live (no directory, no records, or
only ended or unparsable ones), 1 when a record does (named on stderr), 2
only for a usage error. koto gates guard the way out of a state, and setup
runs the baseline, so the command gate `await_removals` sits on the state
each path passes just before setup: `context_injection` (issue-backed),
`post_research_validation` (free-form) and `plan_context_injection`
(plan-backed, `/execute` children included, since none of the three has a
`skip_if`). Its command is `test -x <runner> || exit 0; <runner>
--await-removals`, and every forward edge out of those states, override and
fallback edges included, requires `gates.await_removals.exit_code: 0`. A
gate isn't held to the 30 s action bound. One that fails holds the run
before setup, and each directive says a removal is running and to tick
again in a minute; a person can override it, for the reused-pid case. These
states are outside the ones the tsukumogami/shirabe#1230 design changes, and
a workspace with the cleanup off never makes the directory, so it never
holds.

The rename frees the build path at once, so a later build can't race the
deleter on the path itself. R12 asks for more than that: a later run in the
same worktree mustn't build while a removal is still running, because the
build and the delete compete for the same disk. A 9 GiB delete and a fresh
build in the same worktree on a full disk is the case the PRD names, and the
runner's wait is what meets it. Reaping lives in the script; the runner only
reads records and waits.

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

**A wait that runs out stops the run, or joins the re-run hold**: exit 4 to
`done_blocked`, or the tsukumogami/shirabe#1230 design's exit 5. Rejected.
The first ends a run that never ran a command at a failure terminal a rewind
can't take back. The second would spend the per-head re-run cap and write a
ledger line for a suite that never started, outside that design's
eligibility. Letting `--start` relaunch on the next tick, as it does after
`dirty-tree`, starts another full wait on every tick, and counting the result
`timed-out` invents a command that never ran. `removal-running` takes
`supervisor-error`'s shape: no rule, no exit and no edge are added.

**The start gate on the three setup states**: Rejected. A gate is read on
the way out, after setup's baseline has built, and `setup_plan_backed`'s
`skip_if` takes every `/execute` child past it without the gate routing.
Telling the agent in setup's prose to wait isn't enforced; a default action
is held to 30 s and gives a person no override; a gate on `entry` would have
to be folded into `entry`'s `skip_if`.

**An unparsable record counts as live**: Rejected. Its pid can't be read, so
liveness can't be tested, and waiting on it would hold every later run in
that worktree before setup and spend every verification's budget, for a file
that isn't a removal anyone can identify (R8). Reaping it isn't safe either:
its trash may still have a live deleter. Rewriting a record in place is
rejected too: a rewrite is an overwrite, which no-clobber forbids, and it can
be read half done; `mv -h` and `mv -T` aren't portable across BSD and GNU.

**The deleter records its end in the koto session**: Rejected. It's a
detached process that outlives the action, run where koto's cloud backend may
not answer for the session, for a session a fix round or a replacement may
have moved past. koto's log of an action's output isn't a contract a test can
count against, and stdout alone leaves nothing to count once the transcript
is gone.

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

"Dispatched by a plan parent" is one mark, defined here once: a session is
plan-dispatched when koto's `parent_workflow` is set on it, or when it
carries the key `work/plan-dispatched`. Each opener that makes a plan's
child writes one of the two, and nothing else does:

- `/execute`'s single-pr `spawn_and_await` creates every child with
  `parent_workflow` set. koto writes it, and `session-role.sh` already reads
  it as `child`.
- A coordinated child is opened by its own agent with `koto init ...
  --dispatched-by execute-<plan-slug>`
  (`skills/execute/references/step-agent-handoff.md`). That handoff gains one
  step: on every start, after the `koto init` or on finding the session
  already there, and before its first tick, the step agent writes
  `work/plan-dispatched` holding `execute-<plan-slug>` when the session
  doesn't carry it yet. A retried step agent then can't leave a child
  unmarked. A failed write stops the step agent before its first tick.
- The multi-pr driver writes `work/plan-dispatched`, holding
  `multi-pr:<plan-slug>`, on each item session right after it opens it, and
  stops its loop before driving an item whose write failed. The driver has no
  koto session of its own, so no link could name it.

A dispatched-by link alone isn't the mark. A coordinator that dispatches a
standalone `/work-on` run links it the same way, and that run owns its
worktree and cleans at its own end. The single run's caller reads the mark
before it calls the script, from the session's own directory. It first reads
its own row in `koto session list`: a failed list or no row counts as
plan-dispatched, and a row with `parent_workflow` set is plan-dispatched.
Only once the row is found does it read the key with `koto context list
<session> --prefix work/plan-dispatched`, which prints a JSON array. It
tests for the exact key, `any(.[]; . == "work/plan-dispatched")`, since
`--prefix` is a plain string prefix that a key such as
`work/plan-dispatched-old` would also match. Neither `koto context exists`
nor `list` alone tells absence from failure: `exists` exits 1 for an absent
key and for a session it can't find, and `list` prints `[]` for a session it
can't find. The row check comes first for that reason. A failed list or
output that isn't a JSON array also counts as plan-dispatched, so a doubt
leaves the tree in place. The work-on preflight, `skills/work-on/requires.tsv`,
declares `koto context list --prefix` beside its other context verbs.

In single-pr mode, `plan_completion` runs before `ci_monitor`, so it can't
carry the cleanup: CI isn't being watched yet. The successful ends are the
two terminals past `ci_monitor`, `merge_readiness` and `merge_route`:
`merged`, which only `merge_confirm` reaches (`merge_attempt` hands it a
called merge, and `merge_route` hands it one already merged), and
`ready_awaiting_merge`, which `merge_route`, `merge_attempt` and
`merge_confirm` can each route to. The parent cleans once, in its one
worktree, at either terminal, from its directive, when the owned pull
request's hosted CI is green, or, in a repo with no hosted checks, at that
successful end alone (R6). With hosted CI present and not green the tree
stays. It never cleans at `plan_completion`, or on `done_blocked`, which
`ci_monitor` and `merge_route` can both reach.

The coordinated template, `execute-coordinated.md`, has no
`plan_completion` state. Its successful ends are `ready_awaiting_merge`,
which `coord_verdict` or `coord_merge_confirm` routes to, and `merged`,
which only `coord_merge_confirm` reaches. It cleans each recorded worktree
at either, from its directive. Each node worktree is gated on its own node
pull request: the call reads that PR's hosted CI with the chain
`owned_ci_passing` uses, with the node's repository from `run/node/<node>`
and its branch `impl/<plan-slug>-<node>`, and cleans that worktree only when
the chain passes. A node whose PR is pending or red keeps its tree, and the
others are still cleaned. The coordination PR's CI gates no worktree, since
no recorded worktree builds it. The chain's fallbacks run from the
coordination checkout with the execute session and write
`ci_cancelled_after_merge.txt` and `ci_none_declared.txt` there, after the
terminal: the `merged` directive reads the first before the call, nothing
reads either afterwards, and a per-node overwrite is accepted. For a node in
another repository, the cancel-after-merge fallback reads the coordination
checkout's floor list and can't match, so a merged node there whose only
non-green checks are cancelled floor runs keeps its tree. `paused_awaiting_merges`,
`done_blocked` and `done_error` aren't successful ends, and none of them
cleans.

The call runs after the run has reached one of the two successful
terminals, `merged` or `ready_awaiting_merge`, in each template: their
directives, which already render the exit lines with `print-exit.sh`, then
run `test -x <script> && <script> --session <session>; true` for the new
`skills/execute/scripts/build-output-end.sh`. A terminal fixes the outcome
before the call starts, so nothing the call finds can change it, and nothing
koto-timed runs it, so the CI read isn't held to 30 s. The session and its
keys outlive the terminal: every tick carries `--no-cleanup`, and `koto
context add` refuses only a missing or superseded session. The call doesn't
trust the route to mean CI is green, since `ready_awaiting_merge` can follow
a `DIRTY` merge state before CI is assessed, or `merge_attempt`, and
`ci_monitor` can hand on a pending CI. So for each
recorded worktree it reads hosted CI with the same check chain
`ci_monitor`'s `owned_ci_passing` runs (`pr-checks.sh`, then
`ci-cancel-after-merge.sh --owned`, then `ci-none-declared.sh --owned`),
single-pr with that gate's own `repos` and `settled_branch`, and it passes
`--run-id` on every `owned-pr.sh` line and guards an empty selector as that
gate does. No state, edge or reason in either template changes, and
`done_blocked`, `done_error`, `paused_for_review` and
`paused_awaiting_merges` carry no call. No structure-test invariant changes
either: `merged` is still reached only from `merge_confirm` and
`coord_merge_confirm`, and the coordinated template keeps its nine states.

`build-output-end.sh` reads the run record with `run-record-lib.sh` and
writes none of it. For each `run/cleanup/<id>` it first checks the recorded
path: it must be a work tree root (`git -C <path> rev-parse --show-toplevel`
prints it) whose checked-out branch is the one recorded for it,
`settled_branch` for `single` and `impl/<plan-slug>-<node>` for a node.
Otherwise it prints `build-output: <id> worktree unverified, removed
nothing`, so a stale path, or one naming the developer's own clone, is never
cleaned. A verified worktree whose CI isn't green prints `build-output: <id>
CI not green, removed nothing`. The rest get `clean-build-output.sh --base
<pin> --root <path> --switch-root <the parent's checkout root>`, with the
default walk budget. In coordinated mode each `run/node/<node>` with no
`run/cleanup/<node>` prints `build-output: <node> base unreadable, removed
nothing`, so a pin that was never written isn't silent. Each worktree's
lines are led by `build-output: <id>`; all of them are written once to
`build_output_cleanup` in the parent's session, and the script exits 0
whatever happened.

A plan parent has no `result.json` or `impl_base` of its own, so it pins a
base per worktree: `git merge-base <head> <ref>`, where `<ref>` is the
default branch's remote ref as `default_remote_ref <dir>`, in the new
`scripts/lib/default-remote-ref.sh`, resolves it: the
`refs/remotes/origin/HEAD` symref, else `refs/remotes/origin/main` when it
exists, else none. The script's ancestry check, both `/execute` pins and the
multi-pr driver's pin all use that one function, so they can't resolve
different refs, and none falls back to a local branch. With no ref, nothing
is pinned. Every `/execute` pin is written by one new script,
`skills/execute/scripts/build-output-pin.sh --session <S> --id <id>
--worktree <dir> [--fetch]`. It fetches `origin` in the worktree's clone
when given `--fetch`, resolves the ref there with `git -C <dir>`, and writes
through `run-record.sh pin`. It pins nothing when the head is already an
ancestor of the ref, since that head is on the default branch and a pin
there would read the branch's own declaration (R2), or when the run carries
`run/recovered`. Its output goes to stderr and it exits 0 whatever happened,
so a pin it can't write never changes the run (R8).

- Single-pr: `drift-facts.sh` calls it with `--id single` and the
  checkout's root right after its own fetch of `origin`, before
  `worktree_sync` merges. Not in `settled_branch_record`: that action's
  stdout is captured as `SETTLED_BRANCH`, and its failure can only end at
  `done_blocked`.
- Coordinated: `node-push.sh node`, which already runs from the coordination
  checkout and writes the node's run record, calls it with `--id <node>
  --worktree <node worktree> --fetch` on every push of the node. The merge
  base is computed in the node's own clone, against that clone's remote ref,
  and the koto write runs from the coordination checkout, where the session
  answers. The first push comes before the node's PR exists, so before its
  work can merge.

The pin is write-once: `run-record.sh pin` writes an absent key, does
nothing when the key holds the same value, and when it holds a different one
keeps it, prints `kept=<key>` and exits 0. It has no `run/setup`
precondition, since single-pr has none. The key is
`run/cleanup/<worktree-id>` in the parent's session, holding `{"path":
"<absolute worktree root>", "pin": "<40-hex sha>"}`. `<worktree-id>` is the
node id in coordinated mode, the same id `run/node/<node>` uses, and the
literal `single` for single-pr mode's one worktree; a session runs in one
mode, so a node named `single` never meets single-pr's key. Those keys are
the "recorded worktrees" the cleanup walks, and nothing else writes them.
They live under `run/`, so `run-record.sh` gains a `cleanup` kind in all five
places a kind is known: `RR_KEY_RE` in `run-record-lib.sh`
(`cleanup/[a-z][a-z0-9-]*`), the verb-to-field table (`pin` and `carry` may
write `path` and `pin`), `kind()`, `valid()` (`path` an absolute one-line
string, `pin` `^[0-9a-f]{40}$`) and `required()` (`path`, `pin`). With
`RR_KEY_RE` alone, `execute-open.sh`'s carry refuses the key and the run
can't be resumed. The coordinated structure test's check of which script
calls each verb gains `pin` for `build-output-pin.sh`.

For a branch freshly cut from the default branch the pin is the ref's tip at
that moment; for an adopted, reused or attached branch it's the branch's
fork point. The pin sits on the default branch and is an ancestor of the
recorded head. A branch only moves forward from there: `worktree_sync` merges the default
branch in, or, under `sync_status: override`, leaves it out. A rebase onto a
newer default branch keeps the pin as an ancestor too, since the pin is on
that branch. Either way it stays an ancestor of every later head, and the
script's ancestry checks pass. A branch rewritten onto some other base fails
them; the script then prints `base unreadable`, removes nothing, and the tree
is left for the instance remover. After the branch's pull request merges and
the default branch is fetched, a recomputed merge base would be the branch
head itself, which is why the parent passes the pin unchanged as `--base`
and never recomputes it (R2).

A paused run that resumes in a replacement session gets every
`run/cleanup/*` key from the session it replaces, carried by
`execute-open.sh` before the replacement's first tick, so the write-once pin
keeps the first value. In coordinated mode the keys ride in the run-record
snapshot `execute-open.sh` already takes. Single-pr has no snapshot today, so
`execute-open.sh` gains a single-pr path keyed on `run/cleanup/single`: it
makes its carry directory and takes its lock as the coordinated path does,
snapshots only that key from the finished session, carries it with
`run-record.sh carry` only when the replacement lacks it, and removes the
snapshot once carried, or once the session already holds the key. A
recovered coordinated run (any start that carries `run/recovered`, with or
without `--adopt-run`) rebuilds its record from GitHub, where the pins never
were, so it has no `run/cleanup/*` key and pins nothing afresh, because after
a merge a fresh merge base is the branch head. At its end every node prints
`build-output: <node> base unreadable, removed nothing`, and nothing is
cleaned.

In a multi-pr PLAN, `/work-on` is the driver: it takes the items one at a
time, so the driver itself, not a child, knows when no item remains. That
loop is prose in `skills/work-on/SKILL.md`, not a template state, and each
item runs in its own session, so no state of the tsukumogami/shirabe#1230
design carries the call: the skill's loop makes it itself. It calls the
script once, in the one worktree the items share, when every item in the
PLAN has reached its successful end: each item's session reads `done` as
its `current_state` in `koto status <session>`, and no other terminal
counts, `done_already_complete` included (R6). A loop that stops because the items
left are blocked on open dependencies is a pause, not an end, and cleans
nothing; the driver that resumes it cleans when the last item ends. Each
item would otherwise reach an ordinary single run's successful end and clean
the worktree the next item reuses (R9), so the driver marks each item
session plan-dispatched when it opens it, as above.

The driver has one result per item and no base of its own that covers them
all, so it pins a base by the same rule as a plan parent: before its first
item it records `git merge-base HEAD <ref>`, with `default_remote_ref`'s
ref, taken then. A raw remote-ref tip would fail the ancestry check whenever
HEAD doesn't yet contain it, for example after a fetch moved the remote ref
past a stale local default branch; the merge base sits on the default branch
and is an ancestor of HEAD either way. Each item's branch is cut later from
a default branch at or past that point, so the pin stays an ancestor of
every item's head. It has no session to keep it in, so it writes it with
`clean-build-output.sh --write-pin <plan-slug> --base <sha>`, which reads
the switch first (off: it writes nothing), makes step 2's checks on its
directory, and writes `<git-dir>/shirabe-build-output/pin-<plan-slug>` the
way it writes a record (a temp file linked into place with `ln -n`), holding
`{"pin": "<sha>", "plan": "<PLAN path>", "written_at": "<UTC ISO-8601>"}`.
`<plan-slug>` is the PLAN's file name less `PLAN-` and `.md`, and it must
match `^[a-z0-9][a-z0-9-]*$`; a PLAN whose name doesn't is never pinned. A
resumed driver reads that file and never pins again. One that finds no pin
file while any of the PLAN's item sessions already exists doesn't pin
either, since an item may have merged: it ends with `build-output: base
unreadable, removed nothing` and calls nothing. A driver that died between
the pin and item 1 reads its file as a resume, and a file left by an
abandoned PLAN waits for the next run of that PLAN; both pins sit on the
default branch, and the script's ancestry check reads them again at the end.
After its cleanup call the driver removes the file, so a later run of the
same PLAN pins afresh. It passes the pin as `--base`, never an item's
`merge_base` or a recomputed one.

#### Alternatives Considered

**The last dispatched child of a plan parent cleans**: Rejected because
`/execute`'s children run independently, and none of them can know it's the
last. The multi-pr case isn't this option: no child decides anything there,
because the driver iterates the items itself and sees its loop end.

**Every child cleans**: Rejected because each later child then rebuilds from
cold, the cost R9 exists to prevent.

**`/execute`'s call in new states before the terminals**: one pass-through
state whose action reads CI and cleans, or a CI gate state (timeout 180)
feeding a clean state. Rejected. One CI read can take about 28 s and koto
runs a default action, held to 30 s, before the state's gates, and a failed
action holds a finished run (R8). New states would move `merged`'s incoming
edge off `merge_confirm` and `coord_merge_confirm`, raise the coordinated
template's nine states and move reason literals the structure tests pin;
those exist so `merged` is reached only on a live read of MERGED, which
isn't worth weakening for a step that's off by default. `merge_confirm` and
`merge_route` also route elsewhere, and SKILL.md's end-of-run prose isn't
scoped to one terminal. The accepted cost: nothing koto-enforced stands
behind the call, and a skipped call keeps every tree, the direction this
feature already fails in; the structure tests pin it into the two
directives.

**Coordinated cleanup gated on every node PR, or on the coordination PR**:
Rejected. One pending node would keep every tree, and in a repo with
cancelled floor runs one such run on any node would block the whole run's
cleanup. The coordination PR never builds in a node worktree, so its CI says
nothing about whether that tree is still needed. Cleaning a merged node
whatever its CI is closer to the need, but R6 asks for CI green.

**A `context list` arm in the eval koto shim**: Rejected. The shim's
`session list` answers `[]`, so every eval already reads plan-dispatched
before the list is consulted; evals run on canned `koto next` replies and
never run a default action; and a new arm would change what every unrelated
eval sees, the regression the shim's own comment records. The cleaning and
plan-dispatched cases are proved by script tests against real koto.

### Decision 5: A fix round's end

Resolved inline. `fix-round.sh` starts a new run on the same worktree after `done`. The
question is whether that run's own successful end cleans again.

#### Chosen: yes, like any run

A fix round is a run of its own, and it rebuilt the declared tree. Its
successful end with CI green (or alone, with no hosted checks) cleans it,
the same way, unless the round is plan-dispatched. It already starts cold,
because the first run's end cleaned, and that cold build is the cost of a
finished run leaving nothing.

`fix-round.sh` opens the round's session, so it carries both things the
round's end reads:

- **The base.** Today the script records `base` as the fix round's HEAD in
  the round session's `fix_round.json`, which is the round's review base and
  stays as it is. `fix_round.json` gains a second field, `cleanup_base`; the
  original's `fix_rounds.jsonl` doesn't carry it. It is the base the original
  run pinned, read the way a single run's caller reads its own: `koto context
  get <original> verification_results.json`, taking `.merge_base`, or the
  original's `impl_base` when its `VERIFICATION` variable is `hosted-ci`. A
  missing `result.json` never means hosted CI: `result.json` sits under the
  head it verified, and the run's finalization commit moves HEAD past it.
  The round's caller reads `koto context get <round> fix_round.json | jq -r
  '.cleanup_base // empty'`. "The original" is always the first run, never an earlier
  round: `fix-round.sh` already opens every round from the first run's
  session (`$ORIG`), so round 2 and round 3 read the same first-run base,
  never a round's own `merge_base`. The round's caller passes `cleanup_base` as `--base`, never
  the round's own `impl_base`. A hosted-CI fix round starts from the branch,
  so its `impl_base` is a branch commit that fails the script's ancestry
  check and would read the branch's own declaration (R2). When the original's
  base can't be read, `cleanup_base` is left empty, and the round's caller
  prints `build-output: base unreadable, removed nothing` instead of calling
  the script.
- **The mark.** `fix-round.sh` already copies the original's
  `parent_workflow` with `--parent`. It also copies `work/plan-dispatched`
  when the original carries it, read before `koto init` with `koto context
  list "$ORIG" --prefix work/plan-dispatched` and the exact-key test, never
  with its `koto context exists` idiom. A failed read, or output that isn't
  a JSON array, exits 2 before any round session exists; a failed write
  after `koto init` exits 2 without printing `session=`, so no caller drives
  an unmarked round. A fix round of a plan's child is then
  plan-dispatched like the child, and never cleans, so a multi-pr item's
  fix round can't clean the worktree the next item reuses.

A plan child's fix round that runs after the parent has already reached its
successful end leaves the tree it rebuilt. The parent's cleanup ran once and
doesn't run again. That tree is the instance remover's to take, the same as a
blocked run's.

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
`/execute`'s two successful terminals through `build-output-end.sh` (once
per recorded worktree whose own CI is green, with the base the parent pinned
for it) and an undispatched fix round's end all call `clean-build-output.sh`,
and each caller stores its lines once as `build_output_cleanup`.
`run-verification.sh`'s supervisor waits on any record that reads live
before its first command, and the `await_removals` gate holds a run before
setup while one does. The script never fails the run: it prints its
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
| `skills/work-on/scripts/verification-map-schema_test.sh` | Adds `build_output` to its documented-field loop. The selection cases (with and without the field, and malformed) go in `run-verification_test.sh`'s selection section, since the schema test never runs `SELECT_JQ`. |
| `skills/work-on/scripts/clean-build-output.sh` (new) | Reads the switch at `--switch-root` (default `--root`), checks its own directory, reaps ended removals, checks the base's ancestry and reads the declaration there, checks each path, renames the passing ones into numbered trash entries, writes one record per removal, starts the deleter (`--delete <stamp>`), prints one line per path, exits 0. `--write-pin <plan-slug>` writes the multi-pr driver's pin file. |
| `skills/work-on/scripts/build-output-lib.sh` (new) | Sourced by the script and the runner: `bo_dir <root>` (the absolute records directory) and `bo_record_live <record>` (Decision 3's one liveness and parse rule). |
| `scripts/lib/default-remote-ref.sh` (new) | `default_remote_ref <dir>`: the `origin/HEAD` symref, else `refs/remotes/origin/main`, else none. Used by the script's ancestry check and every pinner. |
| `skills/work-on/scripts/run-verification.sh` | The supervisor waits inside its budget, after `sup_start` and before its first command, on every record that reads live; out of budget, it starts no command and writes a `removal-running` result naming the record. `--start` keeps that result. Gains `--await-removals` (exit 0 nothing live, 1 a live record, 2 usage). It doesn't reap. `SELECT_JQ` is unchanged. |
| `skills/work-on/scripts/check-verification.sh`, `verification-eligibility.sh` | A branch right after `supervisor-error`'s holds at exit 2 on `removal-running` with a message naming the record and the two ways on; no rule or edge is added. The eligibility script lists `removal-running` as ineligible beside `supervisor-error`. The exit-2 row of `references/verification-map.md`'s verdict table, and `docs/designs/current/DESIGN-output-gates.md`, name it. |
| work-on template, single run | The command gate `await_removals` on `context_injection`, `post_research_validation` and `plan_context_injection`, required by every forward edge out of them; `work-on.mermaid.md` is regenerated. Calls the script once at the run's successful end with CI green (or the successful end alone with no hosted checks), after the closing step and the handoff brief, unless the session is plan-dispatched (Decision 4's mark, read fail-safe), as `test -x <script> && <script> ...; exit 0`, and stores its lines as `build_output_cleanup`. Never on a verification pass, a return to implementation, the CI fix loop, a blocked run or `done_already_complete` (R6). The end state is named when the tsukumogami/shirabe#1230 design settles. The shared-branch edge doesn't call it. |
| `skills/work-on/scripts/fix-round.sh` | Adds `cleanup_base` to `fix_round.json` beside the existing `base`, and copies `work/plan-dispatched` from the original, both as Decision 5 says. |
| `skills/work-on/SKILL.md`, multi-pr item loop | Before its first item the driver writes `pin-<plan-slug>` through `clean-build-output.sh --write-pin`, or reads it on resume. It writes `work/plan-dispatched` (`multi-pr:<plan-slug>`) on each item session it opens. It calls the script itself, once, when every item's session reads `done`, in the one worktree the items share, with that pin, then removes the pin file. A loop that stops on blocked items cleans nothing. |
| `skills/work-on/requires.tsv` | Declares `koto context list --prefix`, naming the single run's end caller as its reader. The eval koto shim is unchanged. |
| `skills/execute/references/step-agent-handoff.md` | On every start, before the first tick, the coordinated step agent writes `work/plan-dispatched` (`execute-<plan-slug>`) when the child lacks it. |
| `scripts/lib/claude-md-header.sh` | Gains `claude_md_header_named <name> <file>`, printing `<name as written><TAB><value>`; its existing callers are unchanged. Lands with the script, in the plan's Issue 2. |
| `skills/execute/scripts/run-record.sh`, `run-record-lib.sh` | The `cleanup` kind in `RR_KEY_RE`, the verb-to-field table, `kind()`, `valid()` and `required()`, and the write-once verb `pin`. |
| `skills/execute/scripts/build-output-pin.sh` (new) | Computes a worktree's pin with `default_remote_ref` and writes it through `run-record.sh pin`; output to stderr, exit 0. Called by `drift-facts.sh` (single-pr) and `node-push.sh node` (coordinated). |
| `skills/execute/scripts/execute-open.sh` | A single-pr snapshot and carry of `run/cleanup/single`, under the carry lock. |
| `skills/execute/scripts/build-output-end.sh` (new) | Reads `run/cleanup/*`, checks each recorded path, reads each worktree's CI, calls `clean-build-output.sh`, writes `build_output_cleanup`, exits 0. |
| `/execute` templates, successful end | The `merged` and `ready_awaiting_merge` directives of both templates run `build-output-end.sh` after `print-exit.sh`; no state, edge or reason literal changes. `skills/execute/SKILL.md`'s closed write-target set gains the declared build output of each recorded worktree, removed only through `build-output-end.sh` and `clean-build-output.sh`. |
| The workspace's `CLAUDE.local.md` (outside shirabe) | The operator, or a workspace manager's config, adds `## Build Output Cleanup: on`. No component of this feature writes it; `verification-map.md` documents the line. |
| koto's verification map and command list | `env CARGO_INCREMENTAL=0` right after `scripts/without-session-env.sh` on each of the seven cargo commands; the wrapper is unchanged (koto's own item). |

### The script's contract

```
clean-build-output.sh --base <sha> [--root <dir>] [--switch-root <dir>] [--walk-budget <seconds>]
clean-build-output.sh --write-pin <plan-slug> --base <sha> [--root <dir>]
clean-build-output.sh --delete <stamp> [--root <dir>]     (the deleter; started only by the script)
```

Every caller runs it as `test -x <script> && <script> ...; exit 0` (or
`; true` in a directive), so a missing script, a usage error or a killed
process can't stop the tick or change the run (R8), and stores its stdout
once as the context key `build_output_cleanup`.

`--root` is the work tree root: every declared path resolves against it, and
it is the tree cleaned. It defaults to `git rev-parse --show-toplevel`.
`--switch-root` is the work tree root whose `CLAUDE.local.md` holds the
switch, and it defaults to `--root`. A single run, a fix round and the
multi-pr driver clean their own tree and pass neither. An `/execute` parent
passes its own checkout's root as `--switch-root` for every worktree it
cleans, because a node worktree has no `CLAUDE.local.md` of its own
(Decision 2). The tracked and symlink checks on `CLAUDE.local.md` are made in
the switch root's own repository. `--base` is the base the run pinned:
`.merge_base` of the run's `verification_results.json` context key, or the
run's `impl_base` when its `VERIFICATION` is `hosted-ci`; a failed read
leaves it empty, and the caller prints `build-output: base unreadable,
removed nothing` instead of calling. A fix round passes `fix_round.json`'s
`cleanup_base`. A plan parent passes the pin in that worktree's
`run/cleanup/<worktree-id>` key, and the multi-pr driver passes the pin in
its `pin-<plan-slug>` file (Decision 4). Neither the script nor its caller
ever computes a merge base at cleanup time.

`--walk-budget` is the time the `protected` walk may take across all paths,
20 s by default. A caller that runs it inside a koto action and makes
several calls there splits the 20 s between them, so the action stays inside
koto's 30 s bound; `build-output-end.sh` runs outside any action and passes
none. A path whose walk can't finish in its share is `failed` and kept. The
limit is a polling one, as the supervisor's is, since the macOS floor has no
`timeout`.

Callers run it once, at a run's successful end with CI green, or at the
successful end alone in a repo with no hosted checks. It never runs on a
verification pass, a return to implementation, the CI fix loop, a blocked
run or `done_already_complete` (R6). In order:

1. Read the switch from `CLAUDE.local.md` at the switch root, with
   Decision 2's checks in order (symlink, tracked, readable, then
   `claude_md_header_named`). Off: print `build-output: cleanup off` and
   exit 0. A `CLAUDE.local.md` that is a symlink, or that git tracks, counts
   as off, and the line says which: `build-output: cleanup off
   (CLAUDE.local.md is a symlink)` or `build-output: cleanup off
   (CLAUDE.local.md is tracked)`. An unreadable file or a duplicate header
   counts as off and is reported the same way, naming it.
2. Check the script's own directory, `bo_dir <root>`, which is `git -C
   <root> rev-parse --path-format=absolute --git-path shirabe-build-output`.
   If it exists and is a symlink, or isn't a directory owned by the current user,
   print one `build-output: <dir> failed` line naming it, remove nothing and
   exit 0. If it's missing, create it with plain `mkdir` (no `-p`). Then
   pick this call's stamp, `<UTC time to the second>-<pid>` (for example
   `20261116T080412Z-48213`), so two calls in the same second can't share
   one, and check that none of `removal-<stamp>.json`,
   `removal-<stamp>.log` and `trash-<stamp>` exists, as a file, a directory
   or a symlink. If one does, print one `build-output: <name> failed` line
   naming it, reap nothing, rename nothing and exit 0.
3. Reap. Find each `removal-<stamp>.json` that parses, says `running` and
   that `bo_record_live` reads ended. One that doesn't parse prints
   `build-output: removal-<stamp>.json unreadable, left in place`, and it
   and its trash are left alone. A reaped record's trash directory is
   derived from its file name (`trash-<stamp>`), never from a path inside
   the record. Every exit from here on goes through step 7, which marks
   these records `failed` and hands their trash to this call's deleter.
4. Check the base. `--base` must name a commit that is an ancestor of HEAD
   (`git merge-base --is-ancestor <base> HEAD`) and, when
   `default_remote_ref <root>` resolves a ref, an ancestor of or equal to
   that ref. With no such ref, only the first check applies (see Residual
   risk). Then read the map with
   `git show <base>:.claude/shirabe-extensions/verification-map.json`. A base
   that fails either check, or an unreadable base or map: print
   `build-output: base unreadable, removed nothing`. No field, or an empty
   list: print nothing more. A non-list: one `malformed` line. Each of these
   goes to step 7.
5. Normalize each entry. A non-string or empty entry, or one holding a
   newline or other control character, is `malformed`, named and skipped.
   Then check in this order and stop at the first refusal:
   - `absolute`.
   - `outside`: a `..`, any other route out of the root, or `.` itself.
   - A path that passes those two and doesn't exist is `gone` and checked no
     further.
   - `symlink`: the path or any directory on the way. A path that passes has
     its dev:inode recorded here, with `stat -f '%d:%i'` on macOS and `stat
     -c '%d:%i'` on Linux.
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
     directory itself. A declared `.git` never reaches this check: git never
     reports `.git` as ignored, so `not-ignored` refuses it first. It stays
     on the list as a second guard. The walk shares `--walk-budget` (20 s by default)
     across all paths, inside koto's 30 s bound; a path whose walk can't
     finish in its share is reported `failed` and not removed.
   - Duplicates collapse after normalization, and a path under another
     declared path is handled with that path: it gets no line of its own
     and no error.
6. Create `trash-<stamp>` with plain `mkdir`. If that fails (something made
   it since step 2), print one `build-output: trash-<stamp> failed` line,
   rename nothing and go to step 7. Otherwise, for each path that passed, in
   declaration order, n from 1:
   compare the device ids of the path and the trash directory; right before
   the rename, re-check that neither the path nor any directory on the way is
   a symlink and that its dev:inode still matches the recorded one; rename it
   to `trash-<stamp>/<n>`; right after, stat `trash-<stamp>/<n>` and compare
   its dev:inode with the recorded one. A match prints `<path> removed`. A
   mismatch renames the entry back and prints `<path> failed`. A cross-device
   path, a failed re-check or a failed rename prints `<path> failed` and
   stays in place.
7. If this call renamed nothing and reaped nothing, it writes no record,
   starts no deleter and exits 0. Otherwise it opens the log with
   no-clobber, starts the deleter (`--delete <stamp>`, detached as Decision
   3 says, on this call's trash and the reaped trash), and writes the
   record:

   ```json
   {"schema": "shirabe-build-output-removal/v1",
    "started_at": "2026-11-16T08:04:12Z", "pid": 48230,
    "paths": {"1": "target/"}, "reaped": ["trash-20261116T070000Z-41100"],
    "status": "running"}
   ```

   `started_at` and `ended_at` are UTC ISO-8601 to the second with a `Z`;
   `pid` is the deleter's; `paths` maps each n to the path as written;
   `reaped` names the reaped trash directories for a reader auditing what
   was deleted, and no later call takes a trash path from it. The deleter
   removes nothing until the record names its pid (it gives up after 10 s
   and exits, removing nothing). Every record write is atomic: the first is
   a temp file made with `mktemp` in the same directory (mode 0600) and
   linked into place with `ln -n <tmp> removal-<stamp>.json`, which fails if
   the name exists as a file, a directory or a symlink and never follows
   one. Every rewrite (the deleter's end, a reaper's `failed`) writes a temp
   file and renames it over the record with `mv -f`, only while the record
   is still a regular file and not a symlink; otherwise the record is left
   alone and the temp removed. A failed link or log open prints one
   `build-output: <name> failed` line, stops the deleter, renames this
   call's entries back to their paths (each such path's line reads
   `failed`), leaves the reaped records as they were and exits 0. Otherwise
   it marks the reaped records `failed`, prints `build-output: removal
   recorded at <absolute path of removal-<stamp>.json>` once, and exits 0.
   The deleter rewrites the record with `status: done` or `failed` and
   `ended_at` when it exits.

`--write-pin <plan-slug> --base <sha>` runs step 1 (off: it writes nothing
and exits 0) and step 2's directory check, then writes `pin-<plan-slug>` as
step 7 writes a record (Decision 4 gives its fields). `--delete <stamp>` is
the deleter itself and is started only by step 7.

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
       reap: running record that bo_record_live reads ended -> its trash joins this call's deleter
       base ancestor of HEAD and default_remote_ref? -- no --> unreadable
       git show <base>:map -> build_output
       per path: absolute/outside/gone/symlink/tracked/not-ignored/protected
       passing: rename -> <bo_dir>/trash-<stamp>/<n>
                dev:inode re-checked; mismatch -> rename back, failed
       deleter (--delete <stamp>) started; removal-<stamp>.json {status: running, pid, paths}
       "build-output: removal recorded at <path>"
       deleter ends -> removal-<stamp>.json {status: done | failed, ended_at}
  -> exit 0 (outcome unchanged); caller writes build_output_cleanup once

/execute parent
  single-pr: drift-facts.sh fetch -> build-output-pin.sh --id single
  coordinated: node-push.sh node -> build-output-pin.sh --id <node> --fetch
       -> run-record.sh pin: run/cleanup/<id> = {path, pin} (write-once)
  merged | ready_awaiting_merge (terminal) -> print-exit.sh -> build-output-end.sh:
       per run/cleanup/<id>: path verified? CI chain green or no hosted CI?
           clean-build-output.sh --base <pin> --root <path> --switch-root <parent>
       run/node/<node> with no run/cleanup/<node> -> base unreadable
  done_blocked, done_error, paused_for_review, paused_awaiting_merges -> no call

multi-pr driver (skill prose, no session)
  before item 1: clean-build-output.sh --write-pin <plan-slug> (read on resume)
  each item: open session, write work/plan-dispatched -> item never cleans
  every item's session at done? clean-build-output.sh --base <pin>, then remove pin
  items left blocked -> pause, no cleanup

next run, same worktree
  -> await_removals gate on context_injection | post_research_validation |
     plan_context_injection: run-verification.sh --await-removals
       exit 1 (a live record) -> run holds before setup
  -> supervisor, after sup_start: any record live -> wait inside budget
       budget out, still live -> no command, removal-running result, exit 2 hold
       ended or unparsable -> doesn't wait (the script's next call reaps it)
  -> build
```

### Names shared across the plan's issues

| Name | Written by | Read by |
|------|-----------|---------|
| `removal-<stamp>.json` fields `schema`, `started_at`, `pid`, `paths`, `reaped`, `status`, `ended_at` | `clean-build-output.sh` (Issue 2) | `bo_record_live`, the runner and `--await-removals` (Issue 3) |
| `build-output-lib.sh`: `bo_dir`, `bo_record_live` | Issue 2 | Issue 3 |
| `default-remote-ref.sh`: `default_remote_ref` | Issue 2 | `build-output-pin.sh` (Issue 4), the driver (Issue 5) |
| `clean-build-output.sh --write-pin`, `pin-<plan-slug>` | Issue 2 | the driver (Issue 5) |
| `build-output: removal recorded at <path>`; the script's exit 0 | Issue 2 | the callers (Issues 4, 5) |
| `build_output_cleanup` context key | `build-output-end.sh` (Issue 4), work-on end callers (Issue 5) | Issue 5's count of one per run |
| `work/plan-dispatched` (`execute-<plan-slug>` or `multi-pr:<plan-slug>`) | the coordinated handoff (Issue 4); the driver and `fix-round.sh` (Issue 5) | the single run's end caller and `fix-round.sh` (Issue 5) |

## Implementation Approach

1. **The declaration.** Add `build_output` to `verification-map.md` and the
   schema test. Nothing reads it yet, so it's safe to land first.
2. **The script.** Add `clean-build-output.sh`, `build-output-lib.sh`,
   `default-remote-ref.sh` and `claude_md_header_named`, with a test suite
   covering every refusal word including `protected` (a nested clone, a
   mount, the fixed list, a walk past its share), the order, `gone`,
   `malformed`, the switch values including a tracked or symlinked
   `CLAUDE.local.md`, an unreadable base and a base that fails the ancestry
   check, a case-folded tracked path, a cross-device path, a dev:inode
   mismatch, a symlinked or foreign trash directory, a pre-existing
   `trash-<stamp>`, numbered entries, a second call during a live removal,
   reaping an ended one, the record, `--write-pin`, and a plain clone with
   the caller's directory outside the root. The test joins the bash 3.2
   floor list, `scripts/bash-floor/work-on.list`.
3. **The guard.** Teach the supervisor to wait on every live record and
   write `removal-running`, teach `check-verification.sh` to hold on it, add
   `--await-removals`, and put the `await_removals` gate on the three
   pre-setup states. It's verification code the
   tsukumogami/shirabe#1230 design also changes, so it lands after that
   design's PR, or rebased onto it.
4. **The callers.** Wire `/execute`: the `cleanup` kind and the `pin` verb,
   `build-output-pin.sh` from `drift-facts.sh` and `node-push.sh`, the
   single-pr carry in `execute-open.sh`, the `work/plan-dispatched` step in
   the coordinated handoff, and `build-output-end.sh` in the `merged` and
   `ready_awaiting_merge` directives of both templates.
   Wire the work-on end once the tsukumogami/shirabe#1230 design names its
   state, together with `fix-round.sh`'s two additions and the multi-pr
   driver's loop in `skills/work-on/SKILL.md`, since the item runs' skip of
   the cleanup sits in that same end.
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
to what its own run removes. That base comes from places the working agent can
write (`verification_results.json`, `impl_base`, a round's `cleanup_base`, a
parent's `run/cleanup/*` keys, the driver's pin file), so the script checks
it: the base must be an ancestor of HEAD and, when `default_remote_ref`
resolves a ref, an ancestor of or equal to that ref. A branch's own commit, or an
unmerged commit carrying a wider map, fails and counts as unreadable, so
nothing is removed. A parent's recorded worktree path is writable the same
way, so `build-output-end.sh` cleans a path only when it's a work tree root
on the branch recorded for it. That closes the case of a confused or prompt-injected
agent widening the cleanup by editing a state file. It doesn't stop the
worker itself, which could run `rm` directly. The switch is read only from
`CLAUDE.local.md` at the switch root (the run's own work tree, or an
`/execute` parent's checkout), and only when that file is neither
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
their path isn't a symlink: a record is linked into place with `ln -n`, and
rewritten by a rename over a regular file only. The deleter runs only on `trash-*`
directories the script created or reaped, with each path computed from the
git directory and the record's file name and a non-empty and prefix check,
never from a path inside a record. The runner only reads records and waits;
it removes nothing. A recorded pid reused by another deleter makes a later
run wait, at most its own budget; then the supervisor writes
`removal-running`, which holds the gate and names the record.

**Data.** Nothing is sent anywhere (R14). The records and the deleters' logs
hold only paths from the repo's own map, pids and timestamps, in the git
directory, and go with the worktree. The `build_output_cleanup` key holds the
script's lines in the run's own session; it isn't under `run/`, so it never
reaches the run record or a PR body.

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
  a record still reads live, it builds nothing, writes `removal-running`, and
  the gate holds at exit 2 until a person moves the result aside or blocks.
- A run that blocks, or a worker that dies, keeps its tree; the cleanup only
  bounds runs that finish.
- A plan child's fix round that runs after the parent's successful end
  keeps the tree it rebuilt, and so does a branch rewritten onto a base that
  isn't on the default branch, which reads as `base unreadable`.
- A run can hold before implementation while an earlier removal in its
  worktree is still running.

### Mitigations

- The cold build is the accepted cost of leaving nothing, and only fix
  rounds and re-runs pay it.
- The wait is bounded by the runner's own budget, an ended or unparsable
  record never holds it, and the script's next call reaps an ended one's
  trash. A wait that runs out names the record in its `removal-running`
  result, so the verification that didn't run says why.
- Trees left by blocked or dead runs, by a late fix round of a plan child
  or by a rewritten branch are the instance remover's to trim, and it reads
  the same declaration.
