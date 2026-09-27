# Panel review, round 3: Issue 3 (host re-checks for reconcile), commit 12b79aa

Subject: the inventory in `skills/coordinate/scripts/reconcile-check.sh`
(`ig`, `ig_stdin`, `inv_*`, `default_blob`, `nul_lines`, the `inventory`
case), `reconcile-check_test.sh`, the `coordinate-reconcile` suite in
`scripts/check-bash-floor.sh`, and `.github/workflows/check-coordinate-reconcile-scripts.yml`,
as of HEAD. Six reviewers: completeness, justification, intent, pragmatic,
architect, maintainer.

## Test runs

The session's worktree guard refuses `bash <script>` on the host, so the
suites ran only through the floor runner:
`scripts/check-bash-floor.sh --backend docker coordinate-reconcile` ->
`reconcile-report_test.sh` passed=66 failed=0, `reconcile-check_test.sh`
passed=131 failed=0, `check-bash-floor: PASS`. The host bash 5 run wasn't
possible in this session; nothing in the findings below depends on the
bash version.

Probes: `/tmp/rcp3/probe.sh` (not committed), run in `shirabe-bash-floor:3.2`
(bash 3.2, git 2.49) against a copy of the real script. A PATH `git` stand-in
forwards every call to real git except `ls-remote`, which it answers from a
local bare origin; a `gh` stand-in serves `git/trees?recursive=1` from that
origin (optionally truncated, leaving out paths matching a regex) and the
contents API by `rev-parse ref:path`. Output quoted below is actual.

## Round-2 blockers: status

| Round 2 | Closed in code? | Test that fails on regression? |
|---|---|---|
| N1 bash 3.2 crash | Yes (`${QUEUE[@]+...}`; no `-c` arrays left) | Yes: the docker floor job runs both suites with every bash at 3.2, and the first `inv_queue` call iterates an empty `QUEUE` |
| N2 submodule filter via status | Yes: status is gone; gitlinks are queued as clones; hashing is `--no-filters` | Indirectly: "git status is never run" and "hash-object runs unfiltered" greps, plus the top-level filter case. No submodule case exists at all (see J2) |
| N3 `=` in a filter name | Moot: no `-c` blanking remains | n/a |
| N4 undeadlined config reads; no timeout test | Code yes (every in-clone call is `ig`; P11 below: a hanging `ls-files` or `hash-object` gives `unchecked`) | No. There is still no in-clone timeout case, and it's an AC line (J1) |
| N5 MM staged change | Yes (index vs HEAD compared) | Yes (`staged.txt`) |
| N6 clone in an ignored dir | Partly: `find -maxdepth 8` instead of 4 | Yes for depth 6; depth 9+ is still missed (B3) |
| N7 skip-worktree / assume-unchanged | Yes (`ls-files -v`, every present entry hashed) | Yes |

## Blocking findings

### B1. A truncated tree turns deletions in the omitted part into "nothing unique" (completeness)

In the jq `verdict`, the equality test runs before the truncation test:

    def verdict($p; $sha): if ($def[$p] // "absent") == $sha then empty
                           elif ($def | has($p)) or ($trunc | not) then "unique"
                           else "ask" end;

For a deletion `$sha` is `"absent"`. When GitHub truncated the tree and the
path is in the part it left out, `$def[$p]` is null, `// "absent"` makes it
`"absent"`, and the deletion is judged to agree with the default branch
without ever asking. Both the staged-deletion branch (HEAD entries missing
from the index) and the working-tree deletion branch go through it.

Failing input (P5): default branch has `deep/d1.txt`, `deep/d2.txt`,
`deep/d3.txt`; the tree comes back `truncated: true` without `deep/`;
`git rm deep/d1.txt`, `rm deep/d2.txt`, edit `deep/d3.txt`.

    {"items":["repo|change|deep/d3.txt"],"truncated":false,...}
    contents reads: 1

Both deletions are gone and the fact says `truncated: false`. A worker whose
task was a cleanup in a large repository reads as holding nothing unique.

Fix: test `($def | has($p)) or ($trunc | not)` first and return "ask"
otherwise, before comparing. Add a truncated-tree case: every `mktree` in
the suite serves `truncated: false`, so the "ask" path (and `default_blob`'s
contents fallback) has no test at all.

### B2. A tracked path with a leading or trailing tab loses its change (completeness)

`inv_files` splits `ls-files -s -v` lines with `IFS=$'\t' read -r meta path`.
Tab is IFS whitespace, so `read` strips it from both ends of `path`:
`"\tlead.txt"` becomes `lead.txt` and `"end.txt\t"` becomes `end.txt`. The
stripped name isn't a file, so it goes to the deleted list, where `verdict`
finds it absent on the default branch too and drops it; the real path never
reaches the hash list, so its working-tree edit is never compared.

Failing input (P7): commit `$'\tlead.txt'`, `$'end.txt\t'` and
`$'mid\tdle.txt'`, push, then edit all three.

    {"items":["repo|change|mid\tdle.txt"],...}

Two unique edits read as nothing. The jq side (`metapath`) already handles
tabs correctly; only the bash loop is wrong.

Fix: take the path as `${line#*$'\t'}` from a whole-line `IFS= read -r line`
(and the meta as `${line%%$'\t'*}`). Add the three names to a case.

### B3. A clone deeper than depth 8 inside an ignored directory is still never found (completeness)

Round-2 N6 moved from `-maxdepth 4` to `-maxdepth 8`; the discovery gap is
the same shape. `ls-files --others --exclude-standard` doesn't show ignored
directories, so nothing else reaches the clone. The commit message says
"clones inside ignored directories are walked as clones". `find` also
prunes `node_modules`, `.venv` and `target` outright, so a clone under an
ignored `target/` is missed at any depth.

Failing input (P10): `build/` and `target/` in `.gitignore`; a clone with an
unpushed commit at `repo/build/a/b/c/d/e/f/g/other`, and another at
`repo/target/dep`.

    {"items":[],"truncated":false,...}

Fix: per clone, `ig "$C" ls-files -z --others --ignored --exclude-standard --directory`
and queue each listed directory that holds a `.git` (the clone cap already
bounds the walk), or drop `-maxdepth` and rely on the clone cap plus a
visit counter for truncation. A test at depth 9 and one under `target/`.

## Advisory findings

### Completeness

- C1. Ignored files are never listed (P2: `build/notes.md`, a `.env.local`
  excluded via `info/exclude`, both absent). The design says so in one
  clause; no user-facing Known Limitations line says teardown deletes them
  unread. Add one (Issue 6's SKILL.md pass).
- C2. A skip-worktree entry whose file is missing is taken as sparse and
  never reported, even outside a sparse checkout (P12, `a.txt`). An entry
  with both bits (`s`) is reported. Acceptable; say it in a comment.
- C3. `inv_landed` runs `diff --name-only` with the clone's rename
  detection, so a rename shows only its new name. P13: a branch renames
  `a.txt` to `z.txt`; main gained a copy `z.txt` but kept `a.txt`. The
  branch's deletion of `a.txt` exists nowhere else, yet the branch is
  judged landed (`items: []`). Contrived; `--no-renames` closes it.
- C4. Reflog-only commits (after `reset --hard`) are still not listed
  (round-2 C1 remainder). Deliberate discards; fine as a documented limit.
- C5. A merge conflict lists the path twice (P3: stage 1-3 each produce a
  change line after `from_entries` keeps stage 3). Noise only; the conflict
  is found, and a staged new file during the conflict is found too.

Verified fine: a staged deletion whose working file still holds main's
content, and a staged deletion with the file gone (P1: both listed); file ->
symlink, staged and unstaged (P4: listed); unborn HEAD with a staged file
equal to main and one unique (P6: only the unique one); staged and unstaged
renames (P8: both halves of each listed); a hanging `ls-files` or
`hash-object` gives `unchecked` (P11).

### Justification (tests)

- J1. The AC "a timed-out in-clone git call ... yield[s] a not-verified
  fact" still has no test (round-2 N4's test half). The git stand-in
  forwards all non-ls-remote calls to real git, so there's no sleep hook for
  them; a `HANG_VERB`-style switch in the stub (what P11 used) would do it.
- J2. No case for: the 200-file cap (an AC line), a truncated default-branch
  tree (where B1 lives), a submodule (gitlink queueing is untested), a path
  with tabs (B2), a clone past depth 8 (B3).
- J3. The test at depth 6 ("a clone deep inside an ignored directory is
  walked") fails on a regression to depth 4 but passes with the current gap.

### Intent

- I1. Security Considerations says "A file is hashed only when it is a
  regular file whose real path lies inside its clone." The check is
  `[ -f "$C/$path" ]` on the full path, which follows a symlinked parent.
  P14: tracked `d/f`, `d` replaced by a symlink to a directory outside the
  instance: `d/f` is hashed from outside (listed as `change d/f`, beside
  `d (symlink, not read)`). Nothing is lost or written and no content leaks
  beyond a hash comparison, so not blocking, but the claim is false. Check
  `cd -P "$(dirname ...)"` against `$C` before hashing, or reword the
  sentence.
- I2. The design no longer describes the code. Decision 4 still says
  `git status --porcelain`, filter blanking, and one contents API read per
  file; Security Considerations lists `status` among the verbs, says
  `hash-object --no-filters -- <path>` "never with ... `--stdin-paths`"
  (the code uses exactly that), and says "every filter driver ... blanked".
  "Anything past a cap is counted" is still not true (round-2 I2). Update
  both sections to the plumbing approach.
- I3. `hash-object --stdin-paths` C-unquotes a line that starts with `"`,
  so a file named `"a.txt"` is hashed as `a.txt`. A missing unquoted twin
  fails the whole clone to `unchecked` (safe); an existing one with equal
  content hides an edit to the quoted file (contrived miss). Paths starting
  with `-` are fine: they come on stdin, not argv (P9: `-n`, `--help`
  listed as files).
- I4. Nothing config-named ran (P9): clean and process filters, textconv,
  `diff.external` (with `inv_landed`'s `diff --name-only` exercised by an
  unpushed branch), `core.fsmonitor`, `core.pager`, `core.sshCommand`,
  `credential.helper`, `gpg.program`, `core.alternateRefsCommand` and four
  hooks all left no marker. Outside the clone, `ls-remote` runs in the
  caller's cwd, so that directory's repository config (`url.*.insteadOf`,
  `credential.helper`, `http.proxy`) applies to it; running it with
  `-C /` or `GIT_DIR=/dev/null` would take the coordinator's cwd out of it.

### Pragmatic

- P1. The per-entry loop forks `printf | awk` for every index entry to get
  the mode. P15: a clean clone with 20,000 tracked files took 21 s in the
  floor container, none of it under a deadline. Use
  `mode=${meta#* }; mode=${mode%% *}`. Hashing every present tracked file
  each run is also O(repo size); fine at this scale, and the deadline turns
  a giant repo into `unchecked`, not a miss.
- P2. In a truncated tree each "ask" is one contents read at up to the
  deadline, and it runs even after `INV_ITEM_CAP` is hit; a `git rm -r` of a
  big directory in a huge repo costs one read per path. Stop asking once the
  item cap is reached.
- P3. Tracked symlinks are listed on every run even when unchanged, so a
  repo that commits symlinks never reads "nothing unique". Compare
  `readlink` via `hash-object --stdin` of the target string, or accept the
  noise and say so.

### Architect

- R1. The file comparison is now one jq program over four snapshots
  (index, HEAD tree, working hashes, untracked hashes) against one tree
  read. That's the right shape: B1 and B2 are local bugs in it, not in the
  approach.
- R2. The workflow comment says "On macOS the suites run under /bin/bash",
  but `run()` starts the script under test with `bash "$S"`, which on the
  runner is Homebrew bash 5. The docker floor job is what actually covers
  3.2; either use `"$BASH" "$S"` in the harness or reword the comment.

### Maintainer

- M1. `inv_item`'s header says `CLONE KIND PATH`; for `unchecked` the third
  argument is a reason. The report schema header says so; say it here too.
- M2. The "Globals inv_clone sets" comment names `REPO`, which is still the
  `--repo` flag variable (round-2 M2).
- M3. Leftover `ITEMS.*` scratch names (`.idx0`, `.head0`, `.oth0`, `.othp`,
  `.othh`, `.wt`, `.wt0`) collide in meaning (`.wt` is working-tree hashes,
  `.wt0` is the worktree list). Rename one.
