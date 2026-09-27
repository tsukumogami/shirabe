# Panel review, round 2: Issue 3 (host re-checks for reconcile), commit 77a074c

Subject: `host`, `teardown`, `leg`, `inventory` (the `inv_*`/`ig*`/`filters_off`
helpers plus the `inventory` case) in `skills/coordinate/scripts/reconcile-check.sh`,
`reconcile-check_test.sh`, and the `nowhere_else`/`not_verified` change in
`reconcile-report.sh`, as of HEAD.

Test runs (git 2.43, bash 5.2, Linux): `reconcile-check_test.sh` passed=121
failed=0; `reconcile-report_test.sh` passed=66 failed=0.

Same suites on the bash 3.2 floor (the repo's own `shirabe-bash-floor:3.2`
image, git 2.49, worktree mounted read-only): `reconcile-check_test.sh`
passed=99 failed=22 (every inventory case); `reconcile-report_test.sh`
passed=44 failed=22 (pre-existing harness bug, see M3).

Probes: `/tmp/rcp2/probe.sh`, `/tmp/rcp2/probe2.sh`, `/tmp/rcp2/probe3.sh`
(not committed), run against the real script with a PATH `git` wrapper that
serves `ls-remote` and forwards everything else to real git, and a `gh` stub
that serves default-branch blobs by path or 404s. Output quoted below is
actual.

## Round-1 blockers: status

| Round-1 | Closed in code? | Regression test that would fail? |
|---|---|---|
| B1 deep worktrees / nested repos | Worktrees yes; nested repos only when git status shows them (see N6) | Deep worktree: yes (depth 5, beyond find). Nested repo: no -- `vendor/inner/.git` is depth 4, so `find` reaches it and the test passes with the untracked-directory walk deleted |
| B2 detached HEAD, stash | Yes | Yes (both) |
| B3 clean filter runs | For filter names in the clone's own config without `=`; not for submodules (N2) or names with `=` (N3) | Yes for the plain case; nothing covers process drivers, submodules or odd names |
| B4 truncation lost | Yes (report renders "not everything was read" and a Not verified line) | Clone cap and report rendering: yes. File cap (200): no test (works: 205 files -> 200 items, `truncated: true`) |
| B5 no deadlines in-clone | Every `ig` call, yes; the two `config` reads in `filters_off` and `inv_clone`, no (N4) | No test at all for an in-clone call past its deadline |
| A2 500-ref cap | Yes (rev-list with exclusions) | Yes (600 refs, the feature ref last) |
| A13/A14 vacuous tests | Index mtime (ns on Linux) and a widened write grep | Yes |

## Blocking findings

### N1. On bash 3.2 the inventory dies before printing a fact (architect)

`inv_queue` runs `for q in "${QUEUE[@]}"` on an empty array, and `ig`/`ig_in`
expand `"${FILTERS_OFF[@]}"`, which is empty for any clone whose config names
no filter. Under `set -u`, bash < 4.4 treats an empty `"${a[@]}"` as unbound.
The header says "Requires: bash 3.2+".

Failing input: any instance, macOS `/bin/bash`. In `shirabe-bash-floor:3.2`:

    reconcile-check.sh: line 180: QUEUE[@]: unbound variable
    exit=1

No fact is printed (the contract is exit 0 with a fact, or 64). Fixing
`QUEUE` alone just moves the crash to `FILTERS_OFF` in `ig`. 22 check-suite
cases fail on the floor.

CI doesn't catch this: `check-coordinate-reconcile-scripts.yml`'s macOS leg
runs a bare `bash`, which on the runner resolves to Homebrew bash 5 -- the
hole `check-execute-scripts.yml` documents and closes with
`scripts/check-bash-floor.sh --backend system`. Reconcile isn't registered
in that runner.

Fix: `${QUEUE[@]+"${QUEUE[@]}"}` and the same for `FILTERS_OFF` (or seed
`FILTERS_OFF` with a harmless always-present `-c` pair), and add a
`reconcile` suite to `scripts/check-bash-floor.sh`, run from the reconcile
workflow's macOS leg.

### N2. A submodule's clean filter runs through the superproject's `git status` (intent)

`git status` in a superproject spawns `git status` inside each submodule.
The `-c` flags reach the child through `GIT_CONFIG_PARAMETERS`, but
`FILTERS_OFF` only blanks filter names from the superproject's config. The
submodule's own config (`.git/modules/<name>/config`) can name another
driver, and its `.gitattributes` applies it.

Failing input (P1): submodule `sub` with `*.txt filter=sneaky` committed,
`git -C repo/sub config filter.sneaky.clean "sh -c 'touch MARK; cat'"`, a
same-size edit to `sub/s.txt`. After `inventory`: `MARK` exists. This
breaks "neither ... runs anything the clone's config names" (Security
Considerations) for a common layout.

Fix: run the superproject's status with `--ignore-submodules=all` (the
submodule is walked as its own clone with its own blanking anyway), and
queue submodules from `ls-files --stage` gitlinks (mode 160000) so a deep
one is still found. Add the P1 case as a test.

### N3. A filter name containing `=` defeats the blanking (intent)

`git -c` splits its argument at the first `=`. For a driver named `a=b`,
`-c filter.a=b.clean=` sets key `filter.a` to `b.clean=`, and the real
`filter.a=b.clean` stays in force.

Failing input (P2b): `.gitattributes` `*.txt filter=a=b`,
`git config 'filter.a=b.clean' "sh -c 'touch MARK; cat'"`, same-size edit.
After `inventory`: `MARK` exists.

Fix: pass the blanking through `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_<n>` /
`GIT_CONFIG_VALUE_<n>` (git 2.31+, which `--path-format=absolute` already
needs), which has no `=` parsing; or treat a clone with any filter name
containing `=` as unchecked and skip status. Test it.

### N4. Two in-clone config reads have no deadline; the timeout AC has no test (justification)

`filters_off` runs `rd_git -C <clone> config --name-only --get-regexp ...`
and `inv_clone` runs `rd_git -C <clone> config --get remote.origin.url`,
both outside `rd_deadline`. The commit says "every such call runs under the
read deadline".

Failing input (Q2): `git config include.path /path/to/fifo` (or an include
on a hung mount). With `RECONCILE_READ_DEADLINE=2`, `inventory` was still
blocked in the `config --get-regexp` call when an outer `timeout 100`
killed it; the stub log shows that single call. No fact is printed.

Separately, the AC ("a timed-out in-clone git call ... yield[s] a
not-verified fact") has no test. The code path works for `ig` calls (a
wrapper sleeping on `status` gives `unchecked: the working tree could not
be read`), but nothing would catch a regression.

Fix: run both config reads under `rd_deadline` (a failure or 124 ->
`unchecked`), and add a test that stubs one in-clone verb to sleep past
`DL=1`.

### N5. A staged change whose working file matches the default branch is missed (completeness)

The file loop hashes only the working file. For `MM` (index differs from
HEAD, working tree differs from index), the staged blob is never compared.

Failing input (P3): `echo staged-work > a.txt; git add a.txt; echo a > a.txt`
(the working file back to main's content). `status: MM a.txt`;
inventory: `{"items":[]}` -> "nothing unique found". The staged blob is lost
with the instance.

Fix: when the index column is not ` `/`?`, also compare the index blob
(`rev-parse :<path>` via `ig`) against the default branch's blob and list
the file when either differs.

### N6. A clone inside an ignored directory, deeper than depth 4, is never found (completeness)

Discovery is `find -maxdepth 4`, worktree lists, and untracked directories
from `git status`. Ignored directories are in none of them. The commit says
nested repositories "are walked wherever they sit".

Failing input (P5): `repo/.gitignore` has `build/`; a clone at
`public/repo/build/deps/other` (depth 6) with an unpushed commit.
Inventory: `{"items":[]}`.

Fix: find without `-maxdepth`, pruning inside `.git` directories and
stopping at the clone cap (anything more marks truncated); or add
`ls-files --others --ignored --exclude-standard --directory` and check each
for a `.git`.

### N7. skip-worktree and assume-unchanged edits are invisible (completeness)

`git status` skips files with either bit set, and nothing else reads them.

Failing input (P4): `update-index --skip-worktree a.txt` then edit it;
`update-index --assume-unchanged b.txt` then edit it. Inventory:
`{"items":[]}`. (Sparse checkout itself is fine, see below.)

Fix: `ls-files -v -z`: for entries tagged `S` or lower-case, hash the
working file and compare as for a changed file. Lower frequency than N5,
but a one-call fix.

## Advisory findings

Completeness

- C1. A commit reachable only from a local tag (P8: commit, tag, delete the
  branch) or only from the reflog (P13: `reset --hard`) reads as nothing
  unique. Tags at least are cheap: add `refs/tags` tips that aren't on the
  remote.
- C2. A top-level clone whose `.git` is a symlink out of the instance (Q3) is
  silently skipped (`find -type d -o -type f` doesn't match a symlink), so
  its untracked files read as "nothing unique". When the same clone is
  reached through `git status` it gets an `unchecked` item. List it as
  unchecked in both cases.
- C3. Files at the instance root or in any non-repository directory (P12:
  `NOTES.md`, `scratch/s.md`) are never read. The design scopes the walk to
  clones; say so in the design, since teardown deletes them.
- C4. Ignored files are never listed (design says so). `.env`-style scratch
  work is the likeliest loss; worth one sentence in Known Limitations.
- C5. A worktree inside the instance of a clone also inside it is walked
  with the same refs, so the stash is listed twice (Q4). Dedupe by common
  git dir for stash and branch items.

Verified fine: a process driver in the clone's own config is blanked (P2,
marker not created); a branch whose tip merges a pushed branch plus local
work, and an evil merge that adds a file only in the merge commit, are both
listed (P6, P6b); a sparse checkout with a file written at an excluded path
is listed (P7); a status read past its deadline gives `unchecked` (P9);
205 untracked files give 200 items and `truncated: true` (Q1); an instance
root that is itself a clone is walked (Q5).

Intent

- I1. `core.worktree` pointing outside the instance (P11) makes `status`
  read files outside the instance, and the outside tree's changes vanish
  (items `[]`, because `$C/<path>` still holds the committed content).
  Containment checks the common git dir but not the work tree. Compare
  `rev-parse --show-toplevel` with the clone path and mark a mismatch
  unchecked.
- I2. Security Considerations says anything past a cap "is counted"; no
  count is recorded (`truncated` only). Either record skipped counts or
  change the sentence.
- I3. An outside worktree is listed by `basename` only; the design says
  "listing it by path" (round-1 A9, still open).

Justification (tests)

- J1. "a nested repository is walked as a clone" passes with the untracked
  directory walk deleted, because `vendor/inner/.git` is at depth 4 and
  `find` reaches it. Put the nested repo at depth 5 or deeper.
- J2. No tests for the 200-file cap, a process driver, a submodule filter
  (N2), or an odd filter name (N3).
- J3. `host-absent` runs `bash "$S"` with `PATH=$T/nobin:/usr/bin:/bin`; in
  an image where bash lives in `/usr/local/bin` (the floor image) the case
  fails because bash itself isn't found, not because niwa isn't. Use
  `"$BASH"`.

Architect

- R1. The blanking is an enumeration of names from one repository's config
  applied through a parser that splits on `=`; N2 and N3 are both gaps in
  that enumeration. Moving the blanking to `GIT_CONFIG_*` env and stopping
  status from descending into submodules removes both classes rather than
  patching cases.
- R2. The reconcile workflow's macOS leg is not a floor check (see N1);
  register a `reconcile` suite with `scripts/check-bash-floor.sh`.

Pragmatic

- P-1. Worst-case cost is unbounded in wall time: up to 20 clones x 200
  files x one contents read (8 s deadline each), plus up to 200 more per
  unpushed tip in `inv_landed`. That's thousands of `gh api` calls against
  a 5000/hour limit for a pathological instance. Consider one tree read
  (`git/trees/<sha>?recursive=1`) per clone instead of one contents read
  per file.
- P-2. `host` and `teardown` still repeat the same jq match (round-1 A11).
- P-3. `teardown` can't confirm when the listing is empty or its instances
  sit under different parents (round-1 A10; safe direction, unchanged).

Maintainer

- M1. `reconcile-report.sh`'s schema header still lists inventory kinds
  `commit|change|file` and leg dispositions `open|resolved|abandoned`; the
  check emits `unchecked`, `worktree` and `bound`.
- M2. `inv_clone` sets the globals `REPO`, `DEFAULT`, `DEFAULT_SHA`, and
  `blob_at`/`inv_landed` read them implicitly; `REPO` is also the `--repo`
  flag variable. Make them locals passed to `blob_at`, or name them
  `INV_*`.
- M3. Pre-existing, outside this commit: `reconcile-report_test.sh` line 45
  uses `"${3:-{\}}"`, which bash 3.2 expands to `{\}`, so 22 report cases
  fail on the floor with `jq: invalid JSON text passed to --argjson`. Use
  `"${3:-"{}"}"` or a variable.
- M4. `ig_in`/`ig_stdin` exist only because a background job's stdin is
  `/dev/null`; the comment says so, good. The `local nf=0` inside the
  `else` branch of `inv_clone` works but reads as a block-scoped local
  it isn't.

Host, teardown and leg are unchanged since round 1; nothing new found there.
