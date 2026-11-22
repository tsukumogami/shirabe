---
schema: design/v1
status: Proposed
problem: |
  A live coordinated /shirabe:execute run keeps its recorded PLUGIN_ROOT and
  compiled template until it finishes, so a script fix in a newer installed
  release never reaches it. Its work-on children record their own roots, so a
  fix in a child-run script is out of reach even if the parent moved.
decision: |
  A live run moves onto the installed root only when asked, with an explicit
  --move-plugin-root flag on execute-open.sh. The move rebinds PLUGIN_ROOT in
  place through koto-open.sh --attach-live, for the parent and its live
  work-on children together, and only when each session's compiled template
  is listed in a compat table the newer release ships and CI checks. A new
  root-move.sh journals the old values under run/move, holds the opener's
  lock, and moves the parent first and then each child. Any refusal before
  the first write changes nothing, and a failed attach undoes to the
  journaled values. Without the flag, an ordinary reopen keeps the recorded
  root and reports root=held and whether the run is movable.
rationale: |
  Rebinding in place keeps the session name, the run's history and its live
  children. Its only possible koto dependency is a command that prints a
  session's current bindings, needed only if the state log doesn't carry
  them. Gating it on coordinate's
  fingerprint and compat tables reuses machinery shirabe already maintains,
  and it makes compatibility a claim a release states and CI checks rather
  than one the opener guesses. An ungated rebind would move a parent onto
  scripts its template was never checked against and leave its children
  behind. A supersede takeover or park-then-replace needs a koto
  suspend-terminal attribute, so it stays the follow-on route for fixes that
  change a template's structure. A koto recompile verb would put a shirabe
  concern in the engine. The journaled, all-or-nothing move with an explicit
  trigger keeps each step reversible and keeps a move from ever happening
  silently.
---

# DESIGN: Moving a live execute run onto a newer installed plugin version

## Status

Proposed

## Context and Problem Statement

A coordinated `/shirabe:execute` run records the plugin root it was opened
under in its `PLUGIN_ROOT` variable, and koto compiles its template once, when
the run is created. Every script the run's directives call lives under that
root: `coord-common.sh`, sourced by seven of execute's scripts from their own
directory, runs from whichever copy `PLUGIN_ROOT` names. When a later release
fixes one of those scripts, the run keeps calling the copy under its own root
until it finishes whenever a reopen's attach is refused (#1556; which refusal
is an open question below). A reopen whose attach is admitted moves only the
parent, never its work-on children.

Each per-issue work-on child records a root of its own. A child's
`PLUGIN_ROOT` is set when the child is opened (`execute.md` passes
`vars.PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}` to each materialized child, and a
coordinated step opens its named `work-on-<slug>-<node>-<item>` session the
same way), and nothing re-attaches a child when its parent's root changes. The
gates a child runs, such as `tests_counted` calling `test-change.sh status`,
which sources `scripts/lib/test-classify.sh` from its own root, run from the
child's root. So the two fixes #1556 cites land in different places: the
verification-deferral wording fix (#1541 for #1537) changes a script the
parent calls, and the test-classifier fix (#2012 for #1603) changes one a child
calls. A route that moved only the parent would not have reached the second.

### What exists today

- **The execute opener.** `execute-open.sh` has one entry for an existing run:
  `koto-open.sh <session> <template> <vars> --attach-live --replace-terminal`,
  with `--koto-leg <request>:execute` when the run answers a request. A live
  session is attached; a finished one is replaced and its `run/` record,
  `run_id` and review round are carried into the replacement through
  `run-record.sh carry`. There is no supersede, continue or upgrade path, and
  `run-record.sh carry` restores only a finished session.
- **koto's attach.** In koto since #249, `koto init --attach-live` admits a
  live session when the caller's template has the same source file name as the
  one the session was built from; it does not compare template content. It
  validates the passed variables against the caller's compiled template, then
  validates each change against the session's own compiled template: a
  variable that template declares `rebind: true` may change, a variable it
  doesn't know is refused, and a non-rebind variable passed with another value
  is refused. A successful attach rebinds the variables and leaves the session
  on the compiled template it was created with.
- **Rebindable roots.** `execute.md`, `execute-coordinated.md` and `work-on.md`
  all declare `PLUGIN_ROOT` rebindable ("a plugin update moves it"). Execute
  has no compat table, no structural fingerprint and no takeover.
- **What the coordinate skill has.** `coordinate-open.sh` resumes a run whose
  template's structural fingerprint is listed in `coordinate.compat.json` at
  the shipped compat number, rebinds its `PLUGIN_ROOT` when the run's compiled
  template declares it rebindable, and otherwise either takes the run over
  with `koto init --continues --supersede --carry` or carries its `record/` and
  `legs/` keys into a new run and cancels the old one. CI's
  `check-template-compat` job holds the table to its rules.

The issue reports that the attach is refused when the run's compiled template
differs from the installed one (`step=execute:refused`, recorded on the run's
request leg), and that a hand-run `koto init --supersede --carry` would drop
the run's request leg and parent link, orphan its work-on child, and break its
settled branch record. Which koto refusal code the cited runs received isn't
stated; the design treats that as an open question.

### What has to survive a move

- **The request leg.** The coordinate run creates a request with one leg named
  `execute`, admitting `execute.md` and `execute-coordinated.md` and pinning
  `PLAN_SLUG`; the execute session `execute-<slug>` is bound to it, and the
  leg is the run's parent link.
- **The children.** A single-pr run's children are koto-materialized,
  `execute-<slug>.o-<step>`. A coordinated run's children are named sessions,
  `work-on-<slug>-<node>-<item>`, opened `--dispatched-by execute-<slug>`.
- **The branch record.** `settled_branch` (single-pr) and `repos`, `home_repo`
  and `coord_branch` (coordinated) are read by gates that name the session
  literally as `execute-{{PLAN_SLUG}}`, so a run under any other session name
  blocks.
- **The run record.** The `run/` keys, `run_id` and the review round.
- **The recorded root**, which is the thing that has to change.

### In scope

- How a live execute run, single-pr or coordinated, gets onto the installed
  plugin root with its leg, children, branch record and run record intact.
- What makes an older run movable, and how a release declares it.
- Moving the run's live work-on children with it.
- What the move refuses, and the order that keeps a refused move from
  changing anything.

### Out of scope

- Moving a run across a change to its template's structure (a new state, gate
  or directive). That needs a different route, named here as a follow-on.
- Patching an older plugin root in place.
- Moving runs across hosts; the existing import path keeps that job.
- The coordinate skill's own move, which its own design work covers.

## Decision Drivers

- **Same session, same name.** The branch record and the request leg are
  keyed on `execute-<slug>`; a route that renames the session has to rewrite
  both.
- **The children move with the parent.** A fix can land in a script only a
  child calls. Parent and live children move together, or none of them move.
- **Nothing is movable by accident.** Newer scripts driven by an older
  template's directives is a compatibility claim. A release states it, and CI
  checks the statement.
- **A refused move changes nothing.** Every check runs before the first write,
  and a failure after a write leaves the run where it started.
- **Prefer reversible steps.** A variable rebind can be undone by rebinding
  back; a supersede fence or a cancel can't.
- **shirabe-only where possible.** A koto change comes in only for a gap
  shirabe can't close, and is named as a dependency.
- **Reuse what coordinate already ships.** Its fingerprint, compat table and
  CI check are a working pattern; a second, different one costs more to keep.

## Considered Options

### Decision 1: The route onto the installed root

A live run has to reach scripts under a newer root without losing what ties it
together: the session name `execute-<slug>`, the request leg bound to that
name, its children, the branch record its gates read by that name, and its
`run/` record. The route decides most of what the rest of the design can
carry, so it was settled first.

The two fixes #1556 cites shape the question. Both are script changes, not
template changes, and the second lands in a script a child calls from its own
root. A child sitting at a held gate, like the `tests_counted` case, is the
one that most needs the fix, so whatever route is chosen has to reach live
children, not only the parent.

Key assumptions:
- The older plugin root stays on disk while a run uses it; the compiled
  template koto keeps for the session points into it.
- Nothing ticks the run while it is being moved.
- koto's attach works on a materialized child the same way it works on a
  root session; `review-level.sh` already re-attaches one.

#### Chosen: compat-gated root rebind in place, parent and children together

The move re-attaches the existing sessions through the attach the opener
already makes, `koto-open.sh --attach-live`, with `PLUGIN_ROOT` set to the
installed root and every other variable unchanged. It does this for the
parent and for each live work-on child, and only when the installed release
declares that its scripts can drive each session's compiled template
(Decision 2). Because no session is created, renamed, fenced or cancelled,
the request leg, the parent link, the children, the branch record and the
run record all stay exactly where they are; the only value that changes is
the root.

It needs no koto change. Every template involved already declares
`PLUGIN_ROOT` rebindable, and koto validates a rebind against the session's
own compiled template, so a newer template's additions can't leak into an
older run. A rebind is also reversible: rebinding back to the recorded root
undoes it.

What it can't do is carry a template change. The run keeps the states, gates
and directive text it was compiled with. A fix that lives in directive text,
such as the instruction to pass `--public-reason` that accompanies the #1541
wording fix, reaches the run only as far as the scripts carry it.

#### Alternatives Considered

**Today's ungated rebind**: keep passing the installed root on every attach,
which already moves a parent whose template file name matches. Rejected
because it moves the parent with no check that the newer scripts still mean
what the older directives expect, and it leaves every live child on its old
root, which is where one of the two cited fixes lives.

**Supersede takeover, as coordinate does**: open a successor with
`koto init <new> --continues <old> --supersede --carry ...`. Rejected because
koto refuses to supersede a session with itself, so the successor needs a new
name, and the branch record gates name `execute-{{PLAN_SLUG}}` literally.
`--supersede` can't be combined with `--koto-leg`, so the leg stays bound to
the fenced run. A single-pr run's materialized children aren't carried, the
successor starts at its template's first state, and the fence can't be
undone if anything after it fails.

**Park, then replace**: add a transition that takes the live run to a
terminal state, and let the existing `--replace-terminal` reopen compile the
installed template under the same name, carrying `run/`, `run_id` and the
review round. Rejected as the route for script fixes because a terminal
state, like a cancel, answers the request leg, so the replacement is refused
with `leg_already_resolved`; a run compiled before the park state ships
can't park at all; and a live single-pr child blocks the replace. It is the
right shape for a template-structure fix, and is named below as that
follow-on.

**A koto verb that recompiles a live session in place**: let koto swap a
session's compiled template for a newer one when its current state exists in
both. Rejected because it is a large koto change aimed at template changes,
while the cited fixes are script changes; it still needs the same walk over
live children; and narrowed to a safe form it can't move a run that is
waiting inside `spawn_and_await` or the coordinated loop, which is where held
runs sit.

### Decision 2: How a release declares an older template drivable

Rebinding the root means newer scripts run under older directives and gates.
That is safe only when every script the older template calls still takes the
same arguments and returns the same meanings. Someone has to state that, and
CI has to check the statement. The question is what form the statement takes
and what the move compares against it.

Key assumptions:
- The compiled copy of a session's template stays readable at the path koto
  recorded when the session was created, as `coord-log.sh` already relies on.
- The fingerprint program is frozen once the tables ship; changing it
  re-lists every structure.
- koto's attach keeps admitting a live session by template file name, so a
  move from another root isn't refused as `template_mismatch`.

#### Chosen: coordinate's fingerprint and compat table, one table per template, with three extensions

Each of `execute.md`, `execute-coordinated.md` and `work-on.md` gets a compat
table next to it (`execute.compat.json`, `execute-coordinated.compat.json`,
`work-on.compat.json`), in the shape of `coordinate.compat.json`: a current
`compat` number, a map from structural fingerprint to compat, and a digest of
the scripts the template reaches. A session is movable when the table for
its template's source file lists its compiled template's fingerprint at the
table's current compat. Listing an older fingerprint at the current number is
the release's statement that its scripts drive that structure; CI refuses a
listing that its rules don't allow.

The move reads, for the parent and each live child, the session's compiled
template (through koto's session directory and the `workflow_initialized`
event's template path), fingerprints it with the installed root's program,
and picks the table by the template's source file name. An unreadable
compiled copy is refused. The reading and verdict code that coordinate keeps
in `coord-log.sh` (`run_copy`, `run_fingerprint`, `compat_verdict`) moves into
a shared `scripts/lib` helper both skills use.

Coordinate's digest scan, reused as it is, would under-cover execute and
work-on without saying so, for three reasons the code confirms, so the scan
is extended for these tables:

- **Paths resolve against the plugin root.** The current scan looks a script
  up only in the template's own skill and skips a miss. `execute.md`'s gates
  call five work-on scripts and some top-level `scripts/*.sh`, which would
  never reach the digest. The extended scan keys each script by its path
  relative to the plugin root and fails on a path that doesn't resolve.
- **Sourcing is followed for every pattern the scripts use.** The current
  scan follows only `$HERE/`, and misses `$HERE/../../../scripts/lib/`. The
  scripts also use `$SELF_DIR`, `$COORD_SELF_DIR`, `$VR_HERE`,
  `$PLUGIN_ROOT_SELF`, `$PLUGIN_ROOT_PS`, `$PLUGIN_DIR` and `$LIB`. Each gets a
  pinned base (the script's own directory, the plugin root, or
  `scripts/lib`); an unknown variable fails the check.
- **Scripts named only in directives count.** Directive text is stripped
  before the current scan, and `execute.md` names `adopt-or-create-pr`,
  `start-commit`, `push-and-record`, `merge-message`, `merge-exec` and
  `print-exit` only in directives. The extended fingerprint adds an
  `invocations` field: each script a directive or details text names, with
  the sorted `--flag` tokens on its line. A change to how a directive calls a
  script then changes the structure and needs a new compat entry, instead of
  slipping past as a directive edit.

The new digest is stored under a new key, `script_digest`, so coordinate's
table and its existing check are untouched.

#### Alternatives Considered

**A content-hash allowlist**: list the compiled template hashes a release can
drive. Rejected because CI can't check any entry (a hash says nothing about
what the scripts expect), every directive edit needs a new entry, and the
hashes depend on koto's compiled output bytes.

**No gate**: rebind on every reopen, as the templates' `PLUGIN_ROOT`
description implies today. Rejected because a script whose exit meaning
changed, or one a release removed, would fail a moved run in the middle of a
gate, with nothing having warned that the move was unsafe.

**Per-script interface versions**: version each script's interface and have
directives ask for a version. Rejected because it touches about sixty scripts
and every invocation, refuses inside a gate instead of at the move, and can't
see a change to the state machine itself.

**Replaying released templates in CI**: drive each released template against
the new scripts. Rejected for now because no harness can drive a whole
execute or work-on run; it could complement the table later.

### Decision 3: Moving the parent and its children together

A move writes several sessions: the parent, and each live work-on child. A
single-pr run's children are materialized by koto and share the parent's
directory; a coordinated run's children are named sessions in node
worktrees, possibly in another repository's clone. Each attach is its own
write, so the move has to say what it checks before the first one, what
order it writes in, and how it gets back to where it started if a write
fails. The answer has to keep Decision 1's rule: no child stays on the old
root when the parent moves.

This decision was evaluated twice. Its first pass let an unreachable child,
or a failed undo that a compat table declared safe, stay behind; that
contradicted Decision 1, so it was re-run with "together or not at all" as a
constraint, and both exceptions were dropped.

Key assumptions:
- Step agents tick only in the foreground of the session that owns the run,
  and nothing else ticks the parent; the opener's lock serializes openers.
- Materializing a child doesn't advance it past its initial state.
- Older roots stay on disk.

#### Chosen: a journaled, all-or-nothing move under the opener's lock, parent first

**Before any write**, the move takes the opener's lock, which today covers
only coordinated runs and is extended to single-pr ones. It then lists every
live child. For a single-pr run that is the parent's non-terminal children,
including a relocated one. For a coordinated run the candidates are the
`work-on-<slug>-<node>-<item>` names the PLAN's issues give (the derivation
`node-push.sh` already uses). An absent or finished candidate is skipped, and
a live one is found in its node worktree by its `impl/<slug>-<node>` branch:
first in this repository's worktrees, then in a clone the caller names with
the `--repo-dir` form `node-cut.sh` already takes. Every target, the parent
included, needs a compat verdict from its own compiled template (Decision 2)
and a complete set of rebind values: the new `PLUGIN_ROOT`, and the current
values of the other rebindable variables, such as a child's `REVIEW_LEVEL`,
`UNIT_KIND` and `PLAN_DOC_MOVED`, so that nothing but the root changes. A
target that can't be found, read or admitted refuses the whole move with
`root_move=refused:<reason>`, naming the session and, for an unreachable
child, the clone it needs. No session has been written at that point: the
only write so far is a `pending` journal that holds off new ticks while the
checks run (Security Considerations), and a refusal clears it.

**The journal.** Only then does the move set its journal key on the parent,
`run/move`, to `moving`. It holds the target root, the phase, and for each
session its directory, its old root and the values it will be attached
with. The old values come from the session's own event log: the `variables`
its `workflow_initialized` event recorded, as later attaches rebound them.
`root-move.sh` reads them once, before any write. No koto command prints a
session's current bindings, and an attach reports only the new values, so
reading the log is a dependency on koto's state format. If that format turns
out not to carry rebound values, the move needs a small koto change that
prints a session's current bindings, and Phase 4 waits for it. Either way the
journal is the copy the undo trusts, since nothing after the first write can
read the old values back.

**The writes.** The parent goes first, through the opener's ordinary attach
with `PLUGIN_ROOT` changed. It is the likeliest refusal (template, origin,
leg and flags are all checked there), and a refused attach writes nothing.
Its one window, a moved parent with unmoved children, is the state today's
ungated rebind already leaves every run in. Each child is then attached
from its own directory, and its reported rebind has to be exactly
`PLUGIN_ROOT` to the new root. When all of them succeed the phase becomes
`done`.

**Failure.** If any write fails, every journaled session is attached again
with its old values. Re-attaching an unchanged value writes nothing, so the
undo can be repeated safely. A successful undo sets the phase to
`rolled-back` and the opener reports `root_move=refused:<reason>`. A failed
undo sets it to `split`: the opener prints `failed=move-split`, exits
non-zero, prints no `session=` line, and the skill stops without a tick, as
it does for a failed carry. A journal left at `moving` by a crash is treated
the same way. While the journal says `moving` or `split`, every later open
retries the undo first, under the lock, and the step hand-off and
`work-on-open.sh` refuse to open or tick a child of that parent
(`error=parent-move-split`). A split is never accepted as a resting state.

**Children born after the move.** A single-pr run materializes later
children from the task list it stored, so a child born after a move starts
on the old root. Before such a child's first tick, the hand-off rebinds it to
the parent's root, but only when the child's root is the journaled old root
and its template was judged by the move's compat check.

#### Alternatives Considered

**Children first, parent last**: rebind the children, then the parent.
Rejected because the parent's refusals can't be checked in advance without a
dry-run attach koto doesn't have, so a late refusal means undoing every
child, and it passes through a mix no run has been in, an old parent driving
new children.

**Best effort per child, with a recorded partial state**: move what can be
moved and record the rest. Rejected because it can strand the one child the
move exists for, a child stuck mid-gate, and leaves a mixed run that no
compat statement covers.

**No journal**: rely on the attach output and re-derive the old roots.
Rejected because the attach output gives only new values and koto prints no
bindings, so a crash or a failed write would leave no record of what to undo
to.

**Rolling a split forward**: finish the move instead of undoing it. Rejected
because whatever made a write fail may still be there, while the old state
is known to have been working.

### Decision 4: What triggers the move

Coordinate rebinds a run's root automatically on resume when the run is
movable. Execute's move is a wider write: the parent and every live child,
some of them in other worktrees, with a rollback if any of them fails. The
question is whether that should happen on every reopen or only when asked
for, and what an ordinary reopen does with a run on an older root.

Key assumptions:
- Older roots stay on disk; the plugin cache keeps earlier versions.
- The session's recorded root can be read on every backend execute uses.

#### Chosen: an explicit `--move-plugin-root` flag; an ordinary reopen keeps the recorded root

`execute-open.sh` takes a new flag, `--move-plugin-root`. Without it, an
ordinary reopen of a live run passes the run's recorded root back as
`PLUGIN_ROOT` instead of the installed one; it has to pass it explicitly,
because koto resets a rebindable variable an attach leaves out. When the
recorded root differs from the installed one, the reopen prints `root=held`
and `root_move=movable` or `root_move=not-movable:<reason>`, from the compat
check alone, plus one line on stderr naming both roots and the flag. The
skill's text relays that line; an unattended run never acts on it.

With the flag, the opener runs the move (Decision 3) in place of the
ordinary attach, inside the same lock and with the same leg and variables,
so `MERGE`, the review bounds and the coordinated variables are carried as
an ordinary attach carries them. A refused move prints
`root_move=refused:<reason>` and exits non-zero without having written
anything. On a first open the flag does nothing.

Coordinate's execute entry in `entry-points.tsv` gains the flag, so a
coordinate run can pass it on a re-dispatch it was asked to make. It never
passes it on its own judgment or on a first dispatch.

Two places that open or re-attach children pass the installed root today and
change with this: `execute.md` spawns children with
`PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}`, and the coordinated step hand-off fills
its `{{PLUGIN_ROOT}}` placeholder from `${CLAUDE_PLUGIN_ROOT}`. Both take the
run's own `{{PLUGIN_ROOT}}` instead, so a held run's new children are born on
the run's root, and a step agent's re-attach doesn't move one child alone.
The `PLUGIN_ROOT` descriptions in the three templates are rewritten to match.

This is a behaviour change for anyone reopening an execute run after a
plugin update: the parent no longer picks up script fixes silently. A run on
the current root sees no difference.

#### Alternatives Considered

**Automatic, when the run is movable**: move on every reopen whose sessions
are all listed. Rejected because every resume becomes a multi-session write
with a rollback path, a coordinate re-dispatch would move a run in the middle
of a batch without anyone asking, and the move would run on a path nobody
chose to take it.

**Opt-in, with the ordinary reopen unchanged**: add the flag but keep passing
the installed root otherwise. Rejected because any reopen would still move
the parent with no check and leave the children behind, which is the state
this design exists to remove, and it makes the flag meaningless for the
parent.

**A separate script**: run the move from its own command. Rejected because it
would have to rebuild the opener's variable assembly or reset `MERGE` and the
review bounds, it would run outside the opener's lock and leg, and a
coordinate run dispatches skills, not scripts.

### Decision 5: Where the move's journal lives

The journal (Decision 3) needs a home on the parent that survives a crash
and is written by something that already owns run state.

#### Chosen: `run/move`, written through `run-record.sh`

`run-record.sh` is the only writer of `run/` keys, so the journal gets a new
key kind there and inherits its write rules. A finished run's replacement
carries `run/` keys, so a `done` or `rolled-back` journal travels with the
run as history.

#### Alternatives Considered

**A key outside `run/`**: keep the journal out of what a replacement
carries. Rejected because it would need a second writer for run state, and
an open journal can't be carried anyway: the undo runs before any
replacement.

### Decision 6: Where the move's code lives

#### Chosen: its own script, `root-move.sh`, called by the opener

The child walk, the per-session reads, the attaches and the undo are a
self-contained sequence with their own tests; the opener keeps the flag, the
lock and the variable assembly, and hands the move its inputs.

#### Alternatives Considered

**Inline in `execute-open.sh`**: one script fewer. Rejected because the
opener is already long, and the move's failure paths are easier to test on
their own.

### Decision 7: The lock for single-pr runs

#### Chosen: extend the opener's lock to single-pr runs

The move assumes nothing else opens the run while it writes. Today the lock
covers only coordinated runs, so it is extended rather than leaving the move
unguarded on single-pr runs.

#### Alternatives Considered

**Refuse `--move-plugin-root` on single-pr runs until a lock exists**:
smaller first step. Rejected because the test-classifier case is a single-pr
child, and refusing single-pr runs would leave the second cited fix out of
reach.

### Decision 8: Which root a held run's new children get

#### Chosen: the run's own `{{PLUGIN_ROOT}}`

A child spawned by a parent that is held on its recorded root is born on
that same root, so a held run never mixes roots, and a later move finds
every child where the parent is.

#### Alternatives Considered

**The installed root, as today**: new children get the newest scripts.
Rejected because the child would then be driven by a release its parent's
directives were never checked against, which is the unchecked mix this
design removes.

## Decision Outcome

**Chosen: compat-gated rebind in place, declared per template, moved as one journaled unit, on an explicit flag.**

### Summary

A live execute run moves onto the installed plugin root by having its
existing sessions re-attached with a new `PLUGIN_ROOT` and nothing else
changed. Nothing is created, renamed, fenced or cancelled, so the request
leg, the parent link, the children, the branch record and the `run/` record
stay exactly as they were. The move covers the parent and every live work-on
child, because a fix can sit in a script that only a child calls: the
test-classifier fix for #1603 runs from the child's own root, and a
parent-only move would never have reached the child held at `tests_counted`.

The move runs only when the opener is given `--move-plugin-root`. Before it
writes anything it finds every live child, reads each session's compiled
template, and checks that the installed release lists that template's
structural fingerprint in the compat table for its file (`execute.compat.json`,
`execute-coordinated.compat.json` or `work-on.compat.json`) at the current
compat number. A session it can't find, read or admit refuses the move with
`root_move=refused:<reason>`, and nothing has changed. Otherwise it records a
journal on the parent, attaches the parent, then attaches each child; if any
attach fails it re-attaches everything with the journaled old values. A
failed undo leaves the run blocked (`failed=move-split`) until a later open
finishes the undo. A split is never a resting state.

Without the flag, an ordinary reopen stops moving the parent silently, which
is a change from today, where a reopen passes the installed root. It passes
the run's recorded root back instead, and when the
installed root differs it reports `root=held` and whether the run is movable.
The compat tables follow coordinate's shape and CI rules, with a digest scan
extended to cover the scripts execute and work-on actually reach (scripts in
other skills and in `scripts/`, every sourcing pattern they use, and scripts
named only in directive text), so a listed fingerprint is a statement CI can
hold the release to.

What the move doesn't carry is a change to a template's structure: a new
state, gate or directive. The run keeps the template it was compiled from,
and a fix in directive text reaches it only as far as the scripts carry it.
That case gets a different route, park-then-replace, named below as the
follow-on.

### Rationale

The four choices lean on each other. Rebinding in place is what makes the
carry question disappear, because nothing has to be carried when nothing is
replaced, and it is reversible, which is what lets the multi-session move be
all-or-nothing with a plain undo instead of an unrecoverable fence. The
compat table is what makes a rebind safe to offer at all: without it, newer
scripts under older directives is a guess. Making the move explicit keeps
that wider write off the routine resume path, and holding the recorded root
on an ordinary reopen closes the hole the current behaviour leaves, a parent
moved with no check and its children left behind. Coordinate's machinery is
reused rather than paralleled, at the cost of the three scan extensions it
needs to see what execute's templates reach.

### The follow-on route for template-structure fixes

A fix that changes an execute or work-on template's structure can't be
carried by a rebind; the run needs the newer template compiled. The shape for
that is park-then-replace: a sanctioned transition takes the live run to a
parking state, and the existing `--replace-terminal` reopen compiles the
installed template under the same name, carrying `run/`, `run_id` and the
review round as it does for a finished run. Two things stand in its way and
make it a separate piece of work. A terminal state answers the request leg,
so the replacement is refused with `leg_already_resolved`; it needs a koto
change, a terminal attribute that parks a session without answering its leg.
And a run compiled before the parking state ships can't reach it. A
single-pr run could park only outside `spawn_and_await`, and would restart
its batch. This design leaves that route to its own design.

## Solution Architecture

### Overview

The move lives in the execute opener. `execute-open.sh` gains a flag, a
compat check shared with coordinate, a child walk, a journal written through
`run-record.sh`, and an undo; three templates change how they pass the root
to children; and CI gains a compat check for the three templates.

### Components

- **`skills/execute/scripts/execute-open.sh`.** Parses `--move-plugin-root`.
  On an ordinary attach it reads the recorded root and passes it as
  `PLUGIN_ROOT`; when that differs from `${CLAUDE_PLUGIN_ROOT}` it prints
  `root=held` and `root_move=movable|not-movable:<reason>`. With the flag on
  a live run it runs the move in place of the ordinary attach, under the
  existing lock, which now covers single-pr runs too. On any open, a journal
  at `moving` or `split` makes it run the undo first.
- **`skills/execute/scripts/root-move.sh`** (new, called by the opener).
  Finds the live children, reads each session's compiled template and
  rebind values, asks the compat helper for a verdict, writes the journal,
  performs the attaches through `scripts/koto-open.sh --attach-live`, checks
  each reported rebind, and undoes on failure.
- **`scripts/lib/template-compat.sh`** (new, shared). The compiled-copy read,
  the fingerprint and the verdict that `coord-log.sh` keeps today
  (`run_copy`, `run_fingerprint`, `compat_verdict`), parameterized by table.
  `coord-log.sh` sources it, so coordinate's verdicts don't change.
- **Compat tables.** `skills/execute/koto-templates/execute.compat.json`,
  `skills/execute/koto-templates/execute-coordinated.compat.json` and
  `skills/work-on/koto-templates/work-on.compat.json`, each with `compat`,
  `fingerprints` and `script_digest`.
- **Fingerprint and digest programs.** The structural fingerprint for these
  three templates adds an `invocations` field (each script named in directive
  or details text, with the sorted `--flag` tokens on its line). The digest
  scan resolves every script against the plugin root, follows each sourcing
  variable from a pinned base, and fails on anything it can't resolve.
  Coordinate's own programs are left as they are.
- **`scripts/check-template-compat.sh` and CI.** The check takes the
  extended programs for the new tables and keeps its existing rules (current
  fingerprint listed at `compat`, no entry above it, digest matches, compat
  never goes down, a new structure needs a raise, no renumbering). A new
  workflow runs it as a matrix over the three tables on changes under
  `skills/**` and `scripts/**`, using the base branch's check and table, and
  the head's when the base has no table yet.
- **`skills/execute/scripts/run-record.sh`.** Gains a `move` key kind,
  `run/move`, so the journal is written by the one script that owns `run/`
  keys.
- **Templates.** `execute.md` spawns children with `{{PLUGIN_ROOT}}` instead
  of `${CLAUDE_PLUGIN_ROOT}`; the coordinated step hand-off
  (`skills/execute/references/step-agent-handoff.md`) fills its root from the
  run's `{{PLUGIN_ROOT}}`, refuses while the parent's journal is `moving` or
  `split`, and catches up a late-born single-pr child. The `PLUGIN_ROOT`
  descriptions in `execute.md`, `execute-coordinated.md` and `work-on.md` say
  the root moves only through the move. Each of these is a structural change
  to the template, so the first tables list only the structures that ship
  with them.
- **`skills/work-on/scripts/work-on-open.sh`.** Refuses to open a child of
  an execute parent whose journal is `moving` or `split`.
- **`skills/coordinate/references/entry-points.tsv`.** The execute row
  admits `--move-plugin-root`; coordinate passes it only on a re-dispatch it
  was asked to make.
- **`skills/execute/SKILL.md`.** Documents the flag, relays `root=held`, and
  treats `failed=move-split` as a stop.

### Key Interfaces

- **Opener flag:** `execute-open.sh <plan> --move-plugin-root`. On a first
  open it does nothing.
- **Opener output lines:** `root=held`, `root_move=movable`,
  `root_move=not-movable:<reason>`, `root_move=moved`,
  `root_move=refused:<reason>`, `failed=move-split`. Reasons include
  `not-listed:<session>`, `unreadable:<session>`,
  `child-unreachable:<session>:<repo>`, `attach-refused:<session>:<code>`
  and `digest-mismatch`.
- **Journal key `run/move`:** `{target_root, phase, sessions: [{name,
  session_id, dir, old_root, values}]}`, with `phase` one of `pending`,
  `moving`, `done`, `rolled-back`, `split`. A finished run's replacement
  carries `run/` keys, so a `done` or `rolled-back` journal is carried as
  history; a `moving` or `split` one can't be, because the undo runs before
  the replacement. A `pending` journal holds no writes, so an open that finds
  one from a process that is no longer running clears it.
- **Compat table:** coordinate's shape with `script_digest` in place of
  `gate_scripts`.
- **Child refusal:** `error=parent-move-split` from the hand-off and
  `work-on-open.sh`.

### Data Flow

1. The opener takes the lock and reads the session's state. A live run with
   a journal at `moving` or `split` goes to the undo first.
2. With `--move-plugin-root`, `root-move.sh` writes `run/move` at `pending`,
   which stops new ticks, and waits for any tick in flight. It lists the
   targets (the parent and its live children), reads each compiled template
   and each session's current values from its event log, recomputes the
   target root's script digests, and gets a verdict per target from
   `template-compat.sh` against the installed tables. Any refusal clears the
   `pending` journal and stops, with no session written.
3. It sets `run/move` to `moving`, attaches the parent with the new root,
   then each child from its own directory, checking each reported rebind.
4. On success it sets `done` and the opener prints `root_move=moved`. On a
   failed attach it re-attaches every target with its old values and sets
   `rolled-back`, or `split` if that fails too.
5. Without the flag, the opener attaches with the recorded root and reports
   whether a move is available.

### Open questions

These are stated here because the issue and the code don't settle them; each
names how to settle it.

- **Which refusal the runs #1556 cites received.** The issue reports
  `step=execute:refused` without koto's refusal code. koto has compared an
  attaching template by file name since #249, so `template_mismatch` is
  likely only for a single-pr and coordinated run sharing a name; a variable
  refusal is the other candidate. The refusal is recorded on the run's
  request leg, so reading that leg's result settles it, and an opener test
  that attaches a session compiled from an older template settles which
  refusals a newer opener produces.
- **Whether the cited runs' template structures will be listable.** The
  first tables list the structures that ship with them; an older run is
  movable only if its fingerprint is listed. Whether an older structure can
  be listed is the release author's call, checked by compiling the template
  at its release tag.
- **Whether materializing a child runs its first state's action.** If it
  does, the late-born child catch-up comes too late, and the move must
  refuse while a single-pr run still has unmaterialized tasks. A koto test
  on `materialize_children` settles it.
- **Whether `failed=move-split` should answer the coordinate leg** or leave
  it open for the next open to finish the undo.
- **The remedy when the undo keeps failing.** Today it is a manual
  re-attach to the journaled roots; a documented recovery command may be
  needed.

## Implementation Approach

### Phase 1: Shared compat helper and extended programs

Move the compiled-copy read, fingerprint and verdict out of `coord-log.sh`
into `scripts/lib/template-compat.sh`, with coordinate's behaviour pinned by
its existing tests. Add the extended fingerprint (`invocations`) and digest
scan for execute and work-on, with tests over the scan's three gaps.

Deliverables:
- `scripts/lib/template-compat.sh` and its test
- extended fingerprint and digest programs and their tests

### Phase 2: Template changes and the first tables

Change `execute.md`'s child spawn and the step hand-off to use the run's
root, rewrite the three `PLUGIN_ROOT` descriptions, and add the three compat
tables listing the structures that ship. Add the CI matrix job.

Deliverables:
- `execute.md`, `execute-coordinated.md`, `work-on.md`,
  `step-agent-handoff.md`
- `execute.compat.json`, `execute-coordinated.compat.json`,
  `work-on.compat.json`
- the compat workflow and `check-template-compat.sh` support

### Phase 3: Hold the recorded root on an ordinary reopen

Make `execute-open.sh` pass the recorded root, report `root=held` and the
movability verdict, and extend its lock to single-pr runs. This is the
behaviour change, and it ships before the move so that no reopen moves a
parent unchecked once the tables exist.

The lock's stale-lock rule covers single-pr runs from this phase on: a lock
records its holder's process id and start time, and an open that finds a
holder no longer running takes the lock over.

Deliverables:
- `execute-open.sh` and its tests, including the single-pr lock and its
  stale-lock takeover; `SKILL.md`

### Phase 4: The move

Add `root-move.sh`, the `run/move` kind in `run-record.sh`, the flag, the
undo-first rule, and the child refusals in the hand-off and
`work-on-open.sh`. Add the flag to coordinate's execute entry.

Deliverables:
- `root-move.sh`, `run-record.sh`, `execute-open.sh`, `work-on-open.sh`,
  `step-agent-handoff.md`, `entry-points.tsv`, `SKILL.md`
- the documented recovery for a split: the next `execute-open.sh` finishes
  the undo from the journal, and the coordinate leg reads
  `failed=move-split` as a blocked unit to re-dispatch, not a failed one
- engine tests for a single-pr and a coordinated run moved with live
  children, a refused move, a rolled-back move, a split and its recovery,
  and a digest mismatch at move time

## Security Considerations

This design adds no network access and no new system privilege, and it uses
the same local attach the opener already uses. It does add reach: one
invocation can write sessions outside the run's own directory, in other
worktrees or in a clone the caller names. It also changes which plugin root a
live run's scripts come from, and a moved run keeps the authority it already
holds (`MERGE`, its branch record) while it applies that authority with newer
scripts. The risks sit in what the move trusts and what it writes.

**Trust in newer scripts.** A move runs scripts from a newer installed root
under a template compiled by an older release. The compat tables are the
control: a session moves only if its compiled template's structural
fingerprint is listed at the current compat number, and CI holds each table to
its rules, including a script digest that now covers every script a template
reaches. That guards against an accidental incompatibility in a release. It
doesn't guard against a release that ships a harmful script on purpose, since
such a release could ship the script directly.

CI alone doesn't cover the root on disk, which can be a development checkout,
a locally edited cache copy or a partial update. So `root-move.sh` recomputes
each table's `script_digest` against the target root before the first write,
and a mismatch refuses the move with `root_move=refused:digest-mismatch`.

The CI gate holds only if a pull request can't edit it:

- The compat check runs from the base ref, with the base branch's check
  script, workflow definition and table. A pull request's own workflow file
  doesn't run the check.
- It is a required status check with no path filter, so a change outside
  `skills/` and `scripts/` can't skip it.
- The three tables, `check-template-compat.sh` and the compat workflow file
  get a CODEOWNERS entry, so a person who owns the gate approves every change
  to it.
- A pull request that adds or raises a listing says which scripts' exit
  meanings it checked.

The pull request that first adds a table has no base table to check against,
and that CODEOWNERS review covers it.

**Recorded paths and journal contents.** The move reads session directories,
recorded roots and rebind values from the run's sessions and the `run/move`
journal, and it acts on them later, including in the undo a later open runs.
`root-move.sh` checks those inputs before using them:

- The target root and every journaled old root must exist. Each one's real
  path, with symlinks resolved and refused, must sit under the plugin cache.
  It must also be a shirabe plugin root: the manifest names shirabe and
  carries a compat table for the session's template.
- Each journaled session directory must resolve to the run's session store or
  to a worktree of the expected repository. The journal records each
  session's koto session id, and the undo refuses a session whose id no
  longer matches.
- A directory named with `--repo-dir` must have an `origin` URL that matches
  the repository the PLAN names.
- Slugs, node names and paths that come from the journal or the PLAN are
  quoted wherever they're passed to a script.

The journal records only the variables each session's compiled template
declares rebindable, such as `PLUGIN_ROOT`, `REVIEW_LEVEL`, `UNIT_KIND` and
`PLAN_DOC_MOVED`. Before an undo re-attaches a value, it checks the value
against the type or enum the template declares. The journal never copies
environment contents, so it holds no credentials.

Every value that `root=` and `root_move=` lines print has control characters
stripped and its length capped. The skill text treats those lines as data to
report, never as instructions.

**Scope of the write.** One invocation can write several sessions, some in
other worktrees or in a clone the caller names. The move takes the opener's
lock and checks every target before the first write. It journals the old
values and undoes on failure, so a refused move changes nothing.

Step agents and coordinated children tick without the opener's lock. So the
move writes the `run/move` journal at phase `pending` before its compat
checks. The hand-off and `work-on-open.sh` refuse to start a tick while the
journal reads `pending` or `moving`, and the move waits for any tick already
in flight to finish before its first write.

The late-born child catch-up rebinds a new child only while the journal reads
`done`, and only for a child born after that move. It never acts on a
`rolled-back` or `split` journal.

The flag is explicit. Coordinate passes it only on a re-dispatch someone asked
for, and that rule is enforced rather than left to skill text:
`execute-open.sh` refuses `--move-plugin-root` from the coordinate entry
unless the run's request record carries an explicit move marker. An
unattended run reports `root=held` and doesn't act on it. A lock left by a
crashed process is taken over under the stale-lock rule in Phase 3, which now
covers single-pr runs.

**Residual risks.** A wrong compat listing is the one control between newer
scripts and a live run that may be mid-gate or mid-merge, and rebinding back
can't undo a script's side effects. CI checks the listing's form and the
script digest, not how the scripts behave. So the listing has an owner: the
CODEOWNERS approver, who reviews the stated exit-meaning checks. An old root
altered on disk after the run started still runs as altered on an ordinary
reopen, which is no change from today. The move-time digest check covers only
the target root. A split, where an undo fails, blocks the run until a later
open completes the undo. That recovery ships in Phase 4 with its own test. The `root=held` line and the journal name local filesystem paths,
so they shouldn't be copied into public pull request text.

## Consequences

### Positive

- A live run picks up a script fix from a newer release without losing its
  leg, children, branch record or run record, including a fix in a script a
  child calls.
- The move is reversible end to end, so a failure never leaves a run worse
  off than a refused move would.
- Whether a run is movable is a statement CI checks, not a guess made when
  the run is held.
- The ordinary reopen stops moving a parent onto unchecked scripts and away
  from its children.
- No koto change is needed.

### Negative

- Template changes aren't carried. A fix in directive text, or a new state
  or gate, needs the follow-on route.
- Every structural change to the three templates makes older runs
  unmovable until a release lists their fingerprints. The first tables list
  only the structures that ship with them, so a run compiled before this
  design is movable only once a release has checked its scripts against that
  run's older structure and listed it.
- A reopen after a plugin update no longer picks up parent-level script
  fixes for free; someone has to ask for the move.
- The digest scan's extensions make the check stricter, and some existing
  script layouts may need adjusting before it passes.
- A failed undo blocks the run until it is repaired.

### Mitigations

- The follow-on route is named, with its koto dependency, so template
  changes have a path.
- `root=held` and `root_move=movable` tell whoever reopens the run that a
  move is available, so the flag isn't a hidden requirement.
- The release author can list an older structure once its scripts are
  checked against it, and CI holds the listing to the same rules as the
  current one.
- The split block is explicit and retried on every open, and the journal
  records exactly which roots to restore.
