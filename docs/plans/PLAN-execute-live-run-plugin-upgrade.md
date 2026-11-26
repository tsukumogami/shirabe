---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-execute-live-run-plugin-upgrade.md
milestone: "Moving a live execute run onto a newer installed plugin version"
step_count: 5
---

# PLAN: Moving a live execute run onto a newer installed plugin version

## Status

Active

## Scope Summary

A live `/shirabe:execute` run, single-pr or coordinated, moves onto the newer
installed plugin root only when asked, through a new `--move-plugin-root` flag
on `execute-open.sh`. The move rebinds `PLUGIN_ROOT` in place through
`koto-open.sh --attach-live`, for the parent and then each live work-on child,
and only when each session's compiled template fingerprint is listed in a
compat table at the current compat number. It's journaled under `run/move`,
all or nothing under the opener's lock, and a failed attach undoes to the
journaled values. Without the flag, an ordinary reopen keeps the recorded
root and reports `root=held` with `root_move=movable` or
`root_move=not-movable:<reason>`. The work is in shirabe only.

The move reads each session's current bindings from its koto event log: the
`workflow_initialized` variables, then variable captures, then
`variables_rebound` events. koto already appends a `variables_rebound` event
on every attach that changes a value and folds the log the same way, so the
design's possible koto command for printing a session's bindings isn't
needed, and this plan asks for no koto change. The plan does depend on that
log format staying as it is.

One known risk: koto#307 (open) reports that an attach passing one rebind
variable empties the other rebind variables. The move's attach passes every
rebindable value with only `PLUGIN_ROOT` changed, and step 1's check seeds
non-default values for the others so that a regression fails it.

## Decomposition Strategy

Walking skeleton. Step 1 is the thinnest path that moves a live run: a
single-pr run with no children, whose compiled template is listed in the
execute compat table, reopened with `--move-plugin-root`. It crosses the
compat helper shared with coordinate, one compat-table entry, the opener
flag, `root-move.sh` with its `run/move` journal and the attach that rebinds
`PLUGIN_ROOT`, on one real run. Proving that path first exposes the koto
log-format and attach risks before anything is built on top. Each later step
adds one behaviour to it: holding the root on an ordinary reopen, refusing a
session that can't be checked, moving live children with the parent, and
undoing a failed move.

## Steps

### Step 1: A single-pr run moves onto the installed root when asked

**Goal**: A live single-pr execute run with no children, opened under plugin root A and reopened with `execute-open.sh <plan> --move-plugin-root` from root B, continues as the same `execute-<slug>` session with `PLUGIN_ROOT` rebound to B, provided root B's `execute.compat.json` lists the run's compiled template fingerprint at its current compat number. The path crosses the compat helper shared with coordinate, the compat table, the opener flag, `root-move.sh` with its `run/move` journal written through `run-record.sh`, and koto's live attach through `scripts/koto-open.sh --attach-live`.

**Acceptance Criteria**:

- [ ] `coord-log_test.sh`, `coord-log_engine_test.sh` and `coordinate-open_engine_test.sh` pass with their expected outputs unchanged once `coord-log.sh` gets its compiled-copy read, fingerprint and verdict from `scripts/lib/template-compat.sh`: coordinate's verdicts for a listed fingerprint, an unlisted one and an unreadable compiled copy are the same as before.
- [ ] The helper's own test gets a listed verdict for a fixture `execute.md` compiled template whose fingerprint `execute.compat.json` lists at its `compat` number, and an unlisted verdict when the table lists only some other fingerprint. Pointed at `coordinate.compat.json`, it returns the same verdicts `coord-log.sh` returned before the move.
- [ ] A single-pr run opened under root A, then reopened under root B with `--move-plugin-root` where B's table lists A's compiled fingerprint, prints `root_move=moved` and `session=execute-<slug>` and exits 0.
- [ ] After that move, the session's koto event log has exactly one new `variables_rebound` event, and it changes only `PLUGIN_ROOT`, from A to B.
- [ ] The fixture seeds non-default values for the other rebindable variables before the move: `MERGE=true`, `REVIEW_FLOOR=standard` and `STEP_DRAFTS=off` at the first open, then `REVIEW_CEILING=full` through a later ordinary attach under root A. After the move, the bindings read back from the log (`workflow_initialized` variables, then captures, then `variables_rebound` events) still hold all four values. This catches koto#307, where an attach that passes one rebind variable empties the others.
- [ ] After the move, the `run/move` key on the parent reads phase `done` and target root B. It holds one entry for `execute-<slug>` carrying the session's koto session id, its directory, old root A and the full set of values it was attached with, `REVIEW_CEILING=full` included.
- [ ] After the move, koto lists one session named `execute-<slug>` with the same session id as before. No other session is created, and the run's `run/` keys other than `run/move`, its `run_id` and its `settled_branch` read the same as before the move.
- [ ] The next tick after the move runs root B's copy of the gate script. A marker that only B's copy prints shows up in the gate output, and A's marker doesn't.
- [ ] If B's `execute.compat.json` doesn't list A's compiled fingerprint, the same reopen with `--move-plugin-root` prints `root_move=refused:not-listed:execute-<slug>` and exits non-zero. `PLUGIN_ROOT` stays A, the `run/move` key reads the same as before the reopen (no `pending` journal is left behind), the event log gets no new `variables_rebound` event, and the seeded `MERGE`, `REVIEW_FLOOR`, `REVIEW_CEILING` and `STEP_DRAFTS` values are unchanged.
- [ ] `execute-open.sh <plan> --move-plugin-root` on a plan with no session opens the run the way an open without the flag does: it prints no `root_move=` line and writes no `run/move` key.
- [ ] For Step 2: the opener can get the compat verdict for a session without writing anything to it. A verdict-only call against the run above leaves its event log and `run/` keys byte-for-byte unchanged, so an ordinary reopen can report movability from the same check.
- [ ] For Steps 3 and 4: `root-move.sh` takes its targets as a list. Given a one-session list, it checks every target before the first write, so a refusal leaves no `run/move` key. A refusal reason and the journal's `sessions` array both name the target session, so extra refusal reasons and child targets can go in without changing the journal's shape.

**Check**: Run `skills/execute/scripts/root-move_engine_test.sh` (the new opener engine test) and see it pass. It opens a single-pr fixture run under root A with the seeded variables, then reopens it with `execute-open.sh --move-plugin-root` from root B. It asserts `root_move=moved`, a single `variables_rebound` event that changes only `PLUGIN_ROOT` to B, the four seeded values intact in the log, `run/move` at phase `done`, the session name and id unchanged, and B's marker in the next tick's gate output. The same test then runs the refusal case against a B table that doesn't list the fingerprint and asserts `root_move=refused:not-listed:execute-<slug>`, a non-zero exit, `PLUGIN_ROOT` still A, `run/move` unchanged and no new rebind event. Then run `scripts/lib/template-compat_test.sh`, `skills/coordinate/scripts/coord-log_test.sh` and `skills/coordinate/scripts/coordinate-open_engine_test.sh` and see all three pass with no expected output edited.

**Dependencies**: None

**Files**: `scripts/lib/template-compat.sh`, `scripts/lib/template-compat_test.sh`, `skills/coordinate/scripts/coord-log.sh`, `skills/execute/koto-templates/execute.compat.json`, `skills/execute/scripts/execute-open.sh`, `skills/execute/scripts/root-move.sh`, `skills/execute/scripts/root-move_engine_test.sh`, `skills/execute/scripts/run-record.sh`, `skills/execute/scripts/run-record_test.sh`

### Step 2: An ordinary reopen holds the recorded root and reports whether the run can move

**Goal**: Reopening a live execute run with `execute-open.sh` and no `--move-plugin-root` keeps the run on the plugin root it recorded instead of moving the parent onto the installed one, and says whether a move is available: `root=held` with `root_move=movable` or `root_move=not-movable:<reason>`. Single-pr runs are now held under the opener's lock, and an open that finds a lock whose holder is no longer running (its pid gone, or reused by another process with a different start time) takes the lock over.

**Acceptance Criteria**:

- [ ] A live single-pr run opened under root A, whose compiled template's fingerprint is listed in `execute.compat.json` at the current compat, reopened without the flag under installed root B prints `opened=attached`, `root=held`, `root_move=movable` and `session=execute-<slug>`, and exits 0.
- [ ] In that listed case, the session's `PLUGIN_ROOT` read from its event log is A before the reopen and still A after it, and the reopen's reported rebind does not include `PLUGIN_ROOT`.
- [ ] A live single-pr run under root A whose fingerprint is not listed, reopened without the flag under root B, prints `root=held` and `root_move=not-movable:not-listed:execute-<slug>`, still attaches (`opened=attached`, `session=execute-<slug>`, exit 0), and its `PLUGIN_ROOT` is A both before and after the reopen.
- [ ] A live run whose compiled template copy can't be read, reopened without the flag under root B, prints `root=held` and `root_move=not-movable:unreadable:execute-<slug>`, exits 0, and keeps `PLUGIN_ROOT` at A.
- [ ] Each held reopen prints one stderr line that names root A, root B and `--move-plugin-root`; no `root=` or `root_move=` stdout line carries a control character.
- [ ] After a held reopen, listed or not, the parent holds no `run/move` key and no other session's `PLUGIN_ROOT` has changed, so the verdict came from the compat check alone and nothing was moved.
- [ ] The first tick after a held reopen runs scripts from root A: a marker script placed only under A runs, and B's copy of it does not.
- [ ] A live run whose recorded root equals the installed root, reopened without the flag, prints no `root=held` line and no `root_move=` line, and its `PLUGIN_ROOT` is unchanged.
- [ ] A finished run under root A reopened under root B prints `opened=replaced`, no `root=held` line, and the replacement's `PLUGIN_ROOT` is B.
- [ ] While a single-pr open is running, the run's lock file under the carry root records that opener's pid and its process start time; after the open exits, on success or refusal, the lock file is gone.
- [ ] A second open of a single-pr run whose lock records a live process with a matching pid and start time prints `error=session-busy`, exits 64, names the holder's pid on stderr, and leaves the session's `PLUGIN_ROOT` and the lock file's recorded holder unchanged.
- [ ] An open of a single-pr run whose lock records a pid that is no longer running takes the lock over: it prints `session=execute-<slug>`, exits 0, and the lock file it held recorded its own pid, not the stale one.
- [ ] An open of a single-pr run whose lock records the pid of a live process but a start time that differs from that process's start time takes the lock over the same way and completes with `session=execute-<slug>` and exit 0, without waiting out the busy retries.
- [ ] A coordinated run's lock follows the same rule: a matching live holder still gets `error=session-busy` and exit 64, and a lock whose pid is gone or whose start time differs is taken over.
- [ ] E2E flow still works (do not break the skeleton): reopening a listed single-pr run under root B with `--move-plugin-root` still prints `root_move=moved`, leaves `run/move` at `done`, and rebinds `PLUGIN_ROOT` to B, now under the single-pr lock.

**Check**: Run `bash skills/execute/scripts/execute-open_test.sh` and see the new cases pass: a listed and an unlisted single-pr run opened under one root and reopened under another print `root=held` with `root_move=movable` and `root_move=not-movable:not-listed:execute-<slug>`, with `PLUGIN_ROOT` read from the session log equal before and after in both; a lock held by a live process with a matching start time gets `error=session-busy` (exit 64); and a second open takes over a lock whose recorded pid is gone and one whose pid is live but whose start time differs, finishing with `session=execute-<slug>`. The skeleton's `--move-plugin-root` case still prints `root_move=moved`.

**Dependencies**: Step 1

**Files**: `skills/execute/scripts/execute-open.sh`, `skills/execute/scripts/execute-open_test.sh`, `scripts/lib/template-compat.sh`, `skills/execute/SKILL.md`

### Step 3: A move refuses before any write when a session can't be checked

A move refuses with its reason and changes nothing when a session's fingerprint (extended with invocations, plugin-root paths and every sourcing variable) isn't listed or a digest differs, with the remaining compat tables and a CI matrix checking every table entry.

### Step 4: A coordinated run moves together with its live work-on children

A coordinated run, and a single-pr run with materialized work-on children, moves parent first and then each live child, new children get the run's own root, a child refuses with error=parent-move-split in the hand-off and work-on-open.sh while the parent's run/move journal is pending, moving or split, and coordinate's execute entry can pass the flag.

### Step 5: A failed move undoes itself and a split blocks the run until the next open finishes the undo

A failed attach mid-move rebinds every moved session to its journaled values, a split blocks the run with failed=move-split read as a blocked unit to re-dispatch, and the next execute-open.sh finishes the undo from the journal.

## Implementation Sequence

The steps run in order, all in one pull request. Step 1 comes first. Steps 2
and 3 each depend on step 1 alone. Step 4 depends on steps 1, 2 and 3: its
child moves run under the single-pr lock that step 2 adds, and its refusals
use step 3's checks. Step 5 depends on step 4. The critical path is
1, 3, 4, 5, and step 2 runs beside step 3 without lengthening it.

## Open Questions

The design leaves these open, and this plan doesn't settle them. Each is
settled where the design says, and the step that meets it is named.

- Which koto refusal the runs in #1556 received. Reading the refusal on a
  cited run's request leg settles it, and step 1's opener test settles which
  refusals a newer opener produces for a session compiled from an older
  template.
- Whether older template structures can be listed in the compat tables. That
  is the release author's call, checked by compiling the template at its
  release tag, and it decides which existing runs step 3's tables make
  movable.
- Whether materializing a child runs its first state's action. If it does,
  the move must refuse while a single-pr run still has unmaterialized tasks.
  A koto test on `materialize_children` settles it before step 4.
- Whether `failed=move-split` should answer the coordinate leg or leave it
  open for the next open to finish the undo. Step 5 meets it.
- The remedy when the undo keeps failing. Today it's a manual re-attach to
  the journaled roots; step 5 meets whether a documented recovery command is
  needed.

## References

- Upstream design: `docs/designs/DESIGN-execute-live-run-plugin-upgrade.md`
- Issue: #1556
