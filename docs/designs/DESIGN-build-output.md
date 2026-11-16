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
its own budget, while any of them says `running` with a live pid. The same
wait runs once more, earlier, at a run's start, since an agent can build
during implementation before verification ever runs.
`run-verification.sh --await-removals` does only the wait, builds nothing and
exits 0 once no record says `running` with a live pid, or non-zero while one
still does. koto gates sit on states and guard the way out of them, so the
gate sits on each of the three setup states, `setup_issue_backed`,
`setup_free_form` and `setup_plan_backed`. Every run leaves one of those
before it reaches `analysis`, `reproduce` or `implementation`, where an
agent first builds. A gate takes its own timeout, so it isn't held to the
30 s action bound. A gate that fails holds the run in setup until a later
tick finds the removal ended. A person can override it, as with any gate,
for the reused-pid case. The setup states are at the start of the run,
outside the end-of-run stretch the tsukumogami/shirabe#1230 design changes. A record
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
only change is the wait, run in the two places above.

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
  more line: right after the `koto init`, the child writes
  `work/plan-dispatched` on its own session, holding the parent's name.
- The multi-pr driver writes `work/plan-dispatched` on each item session
  right after it opens it. The driver has no koto session of its own, so no
  link could name it.

A dispatched-by link alone isn't the mark. A coordinator that dispatches a
standalone `/work-on` run links it the same way, and that run owns its
worktree and cleans at its own end. The single run's caller reads the mark
before it calls the script. It reads `parent_workflow` from its own row in
`koto session list`, and the key with `koto context list <session> --prefix
work/plan-dispatched`, which prints a JSON array: empty when the key is
absent, holding the key when it's present. It doesn't use `koto context
exists`, which exits 1 both for an absent key and for a session it can't
find, so it can't tell absence from failure. A failed list, output that
isn't a JSON array, or a missing row counts as plan-dispatched, so a doubt
leaves the tree in place rather than removing it.

In single-pr mode, `plan_completion` runs before `ci_monitor`, so it can't
carry the cleanup: CI isn't being watched yet. The successful ends are the
two terminals past `ci_monitor`, `merge_readiness` and `merge_route`:
`merged`, which only `merge_confirm` reaches (`merge_attempt` hands it a
called merge, and `merge_route` hands it one already merged), and
`ready_awaiting_merge`, which `merge_route`, `merge_attempt` and
`merge_confirm` can each route to. The parent cleans once, in its one
worktree, on the way into either terminal, when the owned pull request's
hosted CI is green at the head it reached them with, or, in a repo with no
hosted checks, at that successful end alone (R6); `ci_monitor` can hand
`merge_readiness` a pending CI, so the call checks rather than assumes. With
hosted CI present and not green it cleans nothing and the tree stays. It never
cleans at `plan_completion`, and never on `done_blocked`, which `ci_monitor`
and `merge_route` can both reach.

The coordinated template, `execute-coordinated.md`, has no
`plan_completion` state. Its successful ends are `ready_awaiting_merge`,
which `coord_verdict` or `coord_merge_confirm` routes to, and `merged`,
which only `coord_merge_confirm` reaches. It cleans once per recorded
worktree on the way into either, under the same CI-green check.
`paused_awaiting_merges`, `done_blocked` and `done_error` aren't successful
ends, and none of them cleans.

The call doesn't trust the route that reached the terminal to mean CI is
green: `ready_awaiting_merge` can be reached on a merge state of `DIRTY`
before CI is assessed, and from `merge_attempt`. So it reads hosted CI at
the head itself, with the same check read `ci_monitor` makes for the owned
pull request, and cleans only when every check at that head has completed
green, or when that read reports the repo has no hosted checks.

Which exact state carries the call in each template is the implementer's to
wire, within those bounds. One placement meets all of them: a new
pass-through state on the edges into `merged` and `ready_awaiting_merge`
only. It can't sit in a state that also routes to `done_blocked`. These are `/execute` states, outside the work-on
states the tsukumogami/shirabe#1230 design is changing.

A plan parent has no `result.json` or `impl_base` of its own, so it pins a
base per worktree. It pins when it records that worktree's branch: in
single-pr mode at `settled_branch_record`, and in coordinated mode at the
step that cuts or attaches a node's worktree (`node-cut.sh`, which prints
`worktree=`). The pin is `git merge-base <recorded head> <default branch's
remote ref>`, taken at that moment, before any of the plan's work has
merged. For a branch freshly cut from the default branch that is the remote
ref itself; for an adopted branch, a reused or attached node branch, or one
that already carries commits, it is the branch's fork point. The parent
writes one key per worktree in its own session, `run/cleanup/<worktree-id>`,
holding the worktree's path and its pin. `<worktree-id>` is the node id in
coordinated mode, the same id `run/node/<node>` uses, and the literal
`single` for single-pr mode's one worktree. Those keys are the "recorded
worktrees" the cleanup walks, and nothing else writes them. They live under
`run/`, so they join the run record: `run-record-lib.sh`'s key layout
(`RR_KEY_RE`) gains `cleanup/<id>`. Without that, the library reports the
keys as outside the layout and ignores them.

The pin sits on the default branch and is an ancestor of the recorded head.
A branch only moves forward from there: `worktree_sync` merges the default
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
`run/cleanup/*` key from the session it replaces and never pins again. The
copy is `execute-open.sh`'s, not the template's: it already snapshots a
finished session's run record before koto replaces it and writes the
snapshot into the replacement, and with the layout change above the pins
ride in that snapshot. A run
recovered with `--adopt-run` reads the keys from the session it adopts. When
it can't read them, it doesn't pin afresh, because after a merge a fresh
merge base is the branch head. For each worktree it prints
`build-output: base unreadable, removed nothing` itself, without calling
the script.

In a multi-pr PLAN, `/work-on` is the driver: it takes the items one at a
time, so the driver itself, not a child, knows when no item remains. That
loop is prose in `skills/work-on/SKILL.md`, not a template state, and each
item runs in its own session, so no state of the tsukumogami/shirabe#1230
design carries the call: the skill's loop makes it itself. It calls the
script once, in the one worktree the items share, when every item in the
PLAN has reached its successful end. A loop that stops because the items
left are blocked on open dependencies is a pause, not an end, and cleans
nothing; the driver that resumes it cleans when the last item ends. Each
item would otherwise reach an ordinary single run's successful end and clean
the worktree the next item reuses (R9), so the driver marks each item
session plan-dispatched when it opens it, as above.

The driver has one result per item and no base of its own that covers them
all, so it pins a base by the same rule as a plan parent: before its first
item it records `git merge-base HEAD <default branch's remote ref>`, taken
then. A raw remote-ref tip would fail the ancestry check whenever HEAD
doesn't yet contain it, for example after a fetch moved the remote ref past
a stale local default branch; the merge base sits on the default branch and
is an ancestor of HEAD either way. Each item's branch is cut later from a
default branch at or past that point, so the pin stays an ancestor of every
item's head. It has no session to keep it in, so it writes it to
`<git-dir>/shirabe-build-output/pin-<plan-slug>`, the worktree's private
directory the script already checks. A resumed driver reads that file and
never pins again. After its cleanup call it removes the file, so a later run
of the same PLAN pins afresh. It passes the pin as `--base`, never an item's
`merge_base` or a recomputed one.

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
successful end with CI green (or alone, with no hosted checks) cleans it,
the same way, unless the round is plan-dispatched. It already starts cold,
because the first run's end cleaned, and that cold build is the cost of a
finished run leaving nothing.

`fix-round.sh` opens the round's session, so it carries both things the
round's end reads:

- **The base.** Today the script records `base` as the fix round's HEAD,
  which is the round's review base and stays as it is. It gains a second
  field, `cleanup_base`, in the same round record: the base the original run
  pinned, read the way the original's caller reads it (verification's
  recorded `merge_base` from the original's `result.json`, or its
  `impl_base`). "The original" is always the first run, never an earlier
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
  when the original carries it. A fix round of a plan's child is then
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
`/execute`'s successful end after CI is green (once per recorded worktree,
with the base the parent pinned when it recorded that worktree's branch) and
an undispatched fix round's end all call `clean-build-output.sh`.
`run-verification.sh` reads its records and waits on any that's still
running, before verification and at the run's start. The script never fails the run: it prints its
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
| `skills/work-on/scripts/clean-build-output.sh` (new) | Reads the switch at `--switch-root` (default `--root`), checks its own directory, reaps dead removals, checks the base's ancestry and reads the declaration there, checks each path, renames the passing ones into numbered trash entries, writes one record per removal, starts the deleter, prints one line per path, exits 0. |
| `skills/work-on/scripts/run-verification.sh` | Before building, waits inside its budget on every removal record that says `running` with a live pid. If the budget runs out first, it starts no command, reports the verification as not run and names the record. Gains `--await-removals`, which does only the wait and exits non-zero while a live record remains. It doesn't reap; the script does. `SELECT_JQ` is unchanged. |
| work-on template, single run | A gate on each of `setup_issue_backed`, `setup_free_form` and `setup_plan_backed` runs `run-verification.sh --await-removals` (R12). Calls the script once at the run's successful end with CI green (or the successful end alone with no hosted checks), after the closing step and the handoff brief, unless the session is plan-dispatched (Decision 4's mark, read fail-safe). Never on a verification pass, a return to implementation, the CI fix loop, a blocked run or `done_already_complete` (R6). The end state is named when the tsukumogami/shirabe#1230 design settles. The shared-branch edge doesn't call it. |
| `skills/work-on/scripts/fix-round.sh` | Adds `cleanup_base` (the original run's pinned base) to the round record beside the existing `base`, and copies `work/plan-dispatched` from the original when it carries it, as it already copies `parent_workflow`. |
| `skills/work-on/SKILL.md`, multi-pr item loop | In a multi-pr PLAN, `/work-on` is the driver that takes the items one at a time, so the driver, not a child, knows when no item remains. Before its first item it writes its pin to `<git-dir>/shirabe-build-output/pin-<plan-slug>`, or reads that file on resume. It writes `work/plan-dispatched` on each item session it opens. The loop is skill prose, not a template state: it calls the script itself, once, when every item has reached its successful end, in the one worktree the items share, with that pin, then removes the pin file. A loop that stops on blocked items cleans nothing. |
| `skills/execute/references/step-agent-handoff.md` | After the coordinated child's `koto init ... --dispatched-by execute-<plan-slug>`, the child writes `work/plan-dispatched` on its own session. |
| `scripts/lib/claude-md-header.sh` | Gains a way to return the matched header line, or its name as written, beside the value, so the script can refuse a wrongly cased name; its existing callers are unchanged. Lands with the script, in the plan's Issue 2. |
| `skills/execute/scripts/run-record-lib.sh` | `RR_KEY_RE` gains `cleanup/<id>`, so `run/cleanup/*` keys are part of the run record and `execute-open.sh`'s existing snapshot carries them into a replacement session. |
| `/execute` templates, successful end | Pin a base per worktree when the parent records its branch (`settled_branch_record`, or the step that cuts or attaches a node's worktree), as `run/cleanup/<worktree-id>` in the parent's session holding the path and the pin; those keys are the recorded worktrees. Single-pr: calls the script once on the way into `merged` or `ready_awaiting_merge`, with the owned pull request's hosted CI green at that head, or at that end alone in a repo with no hosted checks; never at `plan_completion` or on `done_blocked`. A paused run's replacement session gets every `run/cleanup/*` key through `execute-open.sh`'s run-record snapshot; an `--adopt-run` recovery that can't read them prints `base unreadable` per worktree and calls nothing. Every call passes the parent's own checkout root as `--switch-root`, and reads hosted CI at the head itself rather than trusting the route. Several calls in one action share the walk budget through `--walk-budget`. Coordinated (`execute-coordinated.md`): calls it once per recorded worktree on the way into `ready_awaiting_merge` (from `coord_verdict` or `coord_merge_confirm`) or `merged` (from `coord_merge_confirm`), under the same CI check; never on `paused_awaiting_merges`, `done_blocked` or `done_error`. The implementer picks the exact state within those bounds. |
| The workspace's `CLAUDE.local.md` (outside shirabe) | The operator, or a workspace manager's config, adds `## Build Output Cleanup: on`. No component of this feature writes it; `verification-map.md` documents the line. |
| koto's verification map and command list | `env CARGO_INCREMENTAL=0` right after `scripts/without-session-env.sh` on each of the seven cargo commands; the wrapper is unchanged (koto's own item). |

### The script's contract

```
clean-build-output.sh --base <sha> [--root <dir>] [--switch-root <dir>] [--walk-budget <seconds>]
```

`--root` is the work tree root: every declared path resolves against it, and
it is the tree cleaned. It defaults to `git rev-parse --show-toplevel`.
`--switch-root` is the work tree root whose `CLAUDE.local.md` holds the
switch, and it defaults to `--root`. A single run, a fix round and the
multi-pr driver clean their own tree and pass neither. An `/execute` parent
passes its own checkout's root as `--switch-root` for every worktree it
cleans, because a node worktree has no `CLAUDE.local.md` of its own
(Decision 2). The tracked and symlink checks on `CLAUDE.local.md` are made in
the switch root's own repository. `--base` is the base the run pinned: verification's
recorded `merge_base` from `result.json`, or the run's `impl_base` when it
relied on hosted CI and has no `result.json`. A fix round passes its round
record's `cleanup_base`. A plan parent passes the pin in that worktree's
`run/cleanup/<worktree-id>` key, and the multi-pr driver passes the pin in
its `pin-<plan-slug>` file (Decision 4). Neither the script nor its caller
ever computes a merge base at cleanup time.

`--walk-budget` is the time the `protected` walk may take across all paths,
20 s by default. A caller that makes several calls inside one action, such
as a coordinated parent cleaning two worktrees in one tick, splits the 20 s
between them, so the action stays inside koto's 30 s bound whatever the
number of worktrees. A path whose walk can't finish in its share is `failed`
and kept.

Callers run it once, at a run's successful end with CI green, or at the
successful end alone in a repo with no hosted checks. It never runs on a
verification pass, a return to implementation, the CI fix loop, a blocked
run or `done_already_complete` (R6). In order:

1. Read the switch from `CLAUDE.local.md` at the switch root. Off: print
   `build-output: cleanup off` and exit 0. A `CLAUDE.local.md` that git
   tracks, or that is a symlink, counts as off, and the line says which:
   `build-output: cleanup off (CLAUDE.local.md is tracked)` or
   `build-output: cleanup off (CLAUDE.local.md is a symlink)`. A duplicate
   header or an unreadable file counts as off and is reported the same way,
   naming the duplicate or the unreadable file.
2. Check the script's own directory, `<git-dir>/shirabe-build-output`. If it
   exists and is a symlink, or isn't a directory owned by the current user,
   print one `build-output: <dir> failed` line naming it, remove nothing and
   exit 0. If it's missing, create it with plain `mkdir` (no `-p`). Then
   pick this call's stamp, `<UTC time to the second>-<pid>` (for example
   `20261116T080412Z-48213`), so two calls in the same second can't share
   one, and check that none of `removal-<stamp>.json`,
   `removal-<stamp>.log` and `trash-<stamp>` exists, as a file, a directory
   or a symlink. If one does, print one `build-output: <name> failed` line
   naming it, reap nothing, rename nothing and exit 0.
3. Reap. Find each `removal-<stamp>.json` whose status is `running` but whose
   pid is dead. Its trash directory is derived from the record's file name
   (`trash-<stamp>`), never from a path inside the record. Every exit from
   here on goes through step 7, which marks these records `failed` and hands
   their trash to this call's deleter.
4. Check the base. `--base` must name a commit that is an ancestor of HEAD
   (`git merge-base --is-ancestor <base> HEAD`) and, when the upstream
   default branch's remote ref exists locally, an ancestor of or equal to
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
   starts no deleter and exits 0. Otherwise it writes the record
   (`started_at`, the map from each n to the path as written, the names of
   the reaped trash directories, the deleter's pid, `status: running`). The
   reaped names are there for a reader auditing what was deleted. No later
   call takes a trash path from them, since step 3 derives trash only from a
   record's file name. The record is written, and the log opened, with
   no-clobber, so a file or symlink planted there since step 2 fails the
   write instead of being followed. On that failure it prints one
   `build-output: <name> failed` line, renames this call's entries back to
   their paths (each such path's line reads `failed`), leaves the reaped
   records as they were, starts no deleter and exits 0. Otherwise it marks
   the reaped records `failed` and starts the deleter detached on this call's
   trash and the reaped trash, with its output to the log. The deleter
   rewrites this record with `status: done` or `failed` and `ended_at` when
   it exits. Exit 0.

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
  branch recorded (settled_branch_record, or node cut/attach):
       run/cleanup/<worktree-id> = {path, merge-base(head, default remote ref)}
  single-pr: ci_monitor -> merge_readiness -> merge_route
       -> ([merge_attempt ->] merge_confirm ->) merged | ready_awaiting_merge
       -> hosted CI green at head, or no hosted checks? clean-build-output.sh --base <the worktree's pin>, once
  coordinated: coord_verdict -> ready_awaiting_merge,
       or coord_merge_confirm -> merged | ready_awaiting_merge
       -> hosted CI green, or no hosted checks? clean-build-output.sh --base <that worktree's pin>, per recorded worktree
  done_blocked, done_error, paused_awaiting_merges -> no cleanup

multi-pr driver (skill prose, no session)
  before item 1: pin-<plan-slug> in <git-dir>/shirabe-build-output (read on resume)
  each item: open session, write work/plan-dispatched -> item never cleans
  every item ended successfully? clean-build-output.sh --base <pin>, then remove pin
  items left blocked -> pause, no cleanup

next run, same worktree
  -> gate on each setup_* state: run-verification.sh --await-removals
       a live running record -> gate fails, run holds in setup
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
   removal record, add `--await-removals`, and put the gate on the work-on
   template's three setup states. It's verification code the
   tsukumogami/shirabe#1230 design also changes, so it lands after that
   design's PR, or rebased onto it.
4. **The callers.** Wire `/execute`: the per-worktree pin at
   `settled_branch_record` and at the node cut, the `work/plan-dispatched`
   line in the coordinated handoff, and the successful ends (the way into
   `merged` or `ready_awaiting_merge` in both templates, with hosted CI green
   at the head or with no hosted checks, each worktree with its own pin).
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
write (`result.json`, `impl_base`, a round's `cleanup_base`, a parent's
`run/cleanup/*` keys, the driver's pin file), so the script checks it: the base must be
an ancestor of HEAD and, when the upstream default branch's remote ref exists
locally, an ancestor of or equal to that ref. A branch's own commit, or an
unmerged commit carrying a wider map, fails and counts as unreadable, so
nothing is removed. That closes the case of a confused or prompt-injected
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
- A plan child's fix round that runs after the parent's successful end
  keeps the tree it rebuilt, and so does a branch rewritten onto a base that
  isn't on the default branch, which reads as `base unreadable`.
- A run can hold before implementation while an earlier removal in its
  worktree is still running.

### Mitigations

- The cold build is the accepted cost of leaving nothing, and only fix
  rounds and re-runs pay it.
- The wait is bounded by the runner's own budget, a dead deleter's record
  counts as ended, and the script's next call reaps its trash. A wait that
  runs out builds nothing and names the record it waited on, so the
  verification that didn't run says why.
- Trees left by blocked or dead runs, by a late fix round of a plan child
  or by a rewritten branch are the instance remover's to trim, and it reads
  the same declaration.
