# Panel review, round 4: Issue 3 (host re-checks for reconcile), commit 6bbd2d0

Subject: the inventory in `skills/coordinate/scripts/reconcile-check.sh` and
its tests, as of HEAD (6bbd2d0, which answers round 3). Six reviewers:
completeness, justification, intent, pragmatic, architect, maintainer.

## Test runs

The session's worktree guard refuses `bash <script>` on the host, so the
suites ran only on the floor:
`scripts/check-bash-floor.sh --backend docker coordinate-reconcile` ->
`reconcile-report_test.sh` passed=66 failed=0, `reconcile-check_test.sh`
passed=140 failed=0, `check-bash-floor: PASS`. No host bash 5 run.

Mutation runs: copies of the scripts under `/tmp/rc4/<m>/` (not committed),
each with one round-3 fix reverted, run through the same floor image.

| Mutation | Result |
|---|---|
| m1: old `verdict` (equality before the truncation test) | FAIL "a staged deletion is found when the tree is truncated" |
| m2: back to `IFS=$'\t' read -r meta path` | FAIL both tab-edged path cases |
| m3: `-maxdepth 8` | FAIL "a clone ten levels down inside an ignored directory is walked" |
| m4: `ls-remote` without `-C /` | FAIL "ls-remote runs outside any repository" and the allowlist |
| m5: symlinks listed every run again | FAIL "an unchanged tracked symlink is not listed" |
| m6: drop the item-cap `break` in the comparison loop | all 140 pass (untested) |

Probes: `/tmp/rc4/base/probe.sh` and `probe_q1b.sh` (not committed), in
`shirabe-bash-floor:3.2` against a copy of HEAD's script, with the suite's
own stubs (real git except `ls-remote`; `gh` served per case). Output below
is actual.

## Round-3 blockers: status

| Round 3 | Closed in code? | Test that fails on regression? |
|---|---|---|
| B1 truncated-tree deletions | Yes: `verdict` checks `has($p)` first, then `$trunc` -> "ask", then absent -> empty | Yes (m1) |
| B2 tab-edged paths | Yes: whole-line read, split by `%%`/`#` | Yes (m2), both leading and trailing |
| B3 clone deep in an ignored dir | Mostly: no prune, depth 16 | Yes for depth (m3). A clone under `target/` is found now (Q4) but no test pins it, so re-adding the old `-prune` passes the suite |
| round-2 N4 test half (in-clone timeout) | n/a | Yes: `inventory-hang` case |

## Blocking findings

### N1. A clone search that outlives the deadline gives a false "nothing unique" (completeness, intent)

The clone search is now under the deadline, but inside a process
substitution:

    done < <(rd_deadline "$DEADLINE" find -P "$IROOT" -maxdepth "$INV_FIND_DEPTH" -name .git ... | sort)

`rd_deadline` kills `find`, prints whatever it had found, and returns 124;
the status is lost in `<( ... | sort)`. Clones `find` hadn't reached yet are
never queued and nothing sets `TRUNC`. Before this commit `find` had no
deadline (slow but complete) and pruned `node_modules`, `.venv` and
`target`; now it walks every dependency tree to sixteen levels in the same
8 s, so the regression is both new and more likely.

Failing input, real tree (Q1b): an instance holding `lib/` (a 223,322-dir
`node_modules` tree, no repository) and `app/` (a clone with an unpushed
commit and an uncommitted edit), `find` visiting `lib` first;
`RECONCILE_READ_DEADLINE=1`:

    {"items":[],"truncated":false}

Same with a `find` that takes 3 s to start (a slow or cold filesystem) and
`DL=2` (Q1). With the default 8 s this needs a bigger or colder tree:
several repos' `node_modules`, a Rust `target/`, a `.venv`, on a cold APFS
cache, are the ordinary case. The design says "A read that fails or runs
late marks the clone unchecked, and a truncated inventory never reads as
'nothing unique'"; this read does neither.

Fix: run `find` into a file with `rd_deadline ... > "$ITEMS.find"`, and on a
nonzero status set `TRUNC=true` (or add an `unchecked` item for the
instance) before walking what was found. Prune `.git` itself
(`-name .git -prune -print`) so the walk doesn't descend into every
`objects/`. Add a case: a `find` stand-in that sleeps past `DL`, expecting
`truncated: true` or an `unchecked` item, never an empty list with
`truncated: false`.

## Advisory findings

### Completeness

- C1. In a truncated tree, every clean submodule reads as deleted on every
  run (Q2: `{"items":["repo|change|sub (deleted)"]}` for a clean
  superproject and clean submodule). `$headmap` keeps gitlinks while
  `$index` drops them, so each gitlink goes through the deletion branch; the
  old `verdict` swallowed it, the new one asks the contents API, which
  answers with the submodule's commit sha. Safe direction, but a large repo
  with submodules never reads "nothing unique". Filter `160000` out of
  `$headmap` as `$index` does.
- C2. `${p% (deleted)}` is applied to every "ask" line, not only deletions.
  Q3: untracked `notes.md (deleted)` with the same bytes as main's
  `notes.md`, tree truncated -> `{"items":[]}`. The content exists on main
  under another name, so nothing is lost; key the strip on `want = absent`.
- C3. Carry-over I3 (round 3): `hash-object --stdin-paths` C-unquotes a line
  starting with `"`. Q4: tracked `"q.txt"` edited, unquoted twin `q.txt`
  unchanged -> the edit isn't listed. Contrived name; unchanged since round 3.
- C4. A directory name holding a newline breaks `find -print | dirname`, and
  `inv_queue` returns 0 on a failed `cd`, so that clone is skipped silently.
  Pre-existing and contrived; `-print0` plus `read -d ''` closes it.
- Carry-overs not addressed, still advisory: symlinked parent directory is
  followed when hashing (round-3 I1; the new design sentence "A symlink in a
  clone is never followed" is still false for `d/f` with `d` a symlink);
  `inv_landed` rename detection (round-3 C3, no `--no-renames`).

Verified fine in Q4 (non-truncated tree): a retargeted tracked symlink is
listed as `change ln`; a staged deletion is listed; a clone with an unpushed
commit under an ignored `target/dep` is found. Q5: with `GIT_DIR` exported
to another repository, the clone reads `unchecked` (its git directory is
outside the instance), not empty.

### Justification (tests)

- J1. Every round-3 blocker's test fails when its fix is reverted (m1-m5).
- J2. `inventory-items-cap` is satisfied by the 200-file cap alone (230
  untracked files): the item cap and the new comparison-loop `break` have no
  test (m6 passes). A case with more than 200 listed items from fewer than
  200 untracked files would pin it.
- J3. No test for the deadline on `find` (where N1 lives), or for a clone
  under `target/`/`node_modules` (the prune removal).
- J4. The round-3 tree in `inventory-r3` is built with `ls-tree` without
  `-z`, so the tab-edged paths would be quoted keys; it works only because
  those paths are left out of the truncated tree. Use `ls-tree -z` in
  `mktree` so a non-truncated case with odd names is possible.

### Intent

- I1. The design's "A read that fails or runs late marks the clone
  unchecked" doesn't hold for the clone search (N1).
- I2. Security Considerations lists "`hash-object --no-filters` over
  `--stdin-paths` or `--stdin`"; the symlink hash runs `hash-object --stdin`
  without `--no-filters`. No filter applies without `--path`, so it's
  harmless, but add the flag or fix the sentence.
- I3. `-C /` keeps a repository's config out of `ls-remote`, as the design
  now says. Global config and `GIT_*` environment still apply (Q5 shows
  `GIT_DIR` is caught downstream by the containment check); fine.

### Pragmatic

- P1. The per-symlink `hash-object --stdin` is one fork each with no overall
  deadline. Q6: 1,500 unchanged tracked symlinks, `DL=3`: 9 s, nothing
  unchecked. Acceptable at this scale; a single `git cat-file --batch`-style
  batch isn't available for link text, so either accept it or cap it.
- P2. `find` without any prune descends into every `.git/objects` and every
  dependency tree; prune `.git` at least (see N1's fix).
- P3. Index-line parsing without `awk` fixed round-3 P1.

### Architect

- R1. The comparison shape holds: all three round-3 blockers were local
  fixes. N1 is the one place a deadline's status is dropped; every other
  `rd_deadline` result is checked. A helper that runs a deadlined read into
  a file and returns its status would make that pattern hard to repeat.
- R2. Round-3 R2 closed: `run` and the report helpers use `"$BASH"`.

### Maintainer

- M1. Round-3 M1 closed (`inv_item` header).
- M2. The "Globals inv_clone sets" comment still names `REPO`, which is also
  the `--repo` flag variable (round-2 M2, round-3 M2).
- M3. `.wt` (working-tree hashes) vs `.wt0` (worktree list) scratch names
  still collide in meaning (round-3 M3).
- M4. The comparison loop's `line` is reused as a cursor while splitting;
  `inv_files` doesn't declare it `local` (both loops use it), so it writes
  `inv_clone`'s local `line`, which `inv_clone` then reuses for the worktree
  list. It works because `inv_files` finishes first; declare
  `line` local in `inv_files`.
