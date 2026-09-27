# Review panel: Issue 2 (GitHub re-checks for reconcile), commit b9672bd

Scope: `skills/coordinate/scripts/reconcile-check.sh`, `reconcile-deps.sh`,
`reconcile-check_test.sh`, plus the `pending` board edit in
`reconcile-report.sh` / `_test.sh` and the CI workflow change.

Suites run: `reconcile-check_test.sh` passed=43 failed=0;
`reconcile-report_test.sh` passed=65 failed=0.

Experiments were run against a scratch copy of the tree under /tmp (since
removed), reusing the test file's own stub harness. Results are quoted below.

---

## 1. Completeness

**Blocking**

- **C1. Two of the three path-refusal tests are vacuous.** The loop at
  `reconcile-check_test.sh:153-161` calls `new_case "merge-path"` on every
  iteration. `new_case` truncates the log but leaves the stub's call counter
  `.n.pr-view` in place, so iteration 2 and 3 get call number 2 for `pr-view`,
  which has no `.out.2`. The script then refuses with "unreadable base
  branch" before it ever sees the path. Observed:
  `A path=/abs/path out={"status":"not_verified","reason":"unreadable base branch"}`
  with a log holding only `gh pr view`. A `rd_urlencode_path` that accepted a
  leading `/` or `a//b` would still pass. Fix: unique case names per
  iteration (`merge-path-$i`), or reset `.n.*` in `new_case`.
- **C2. The control-character half of the path AC is neither met nor
  tested.** `rd_urlencode_path` claims to refuse any control character, but
  its `grep '[[:cntrl:]]'` is line-based, so a newline is never seen, and
  `jq -R` then splits the input into separate lines:
  `rd_urlencode_path $'docs/a\nb'` returns 0 and prints two lines;
  `rd_urlencode_path $'docs/a\n'` returns 0 and prints `docs/a` (a different
  file). No test feeds a control character. Fix: test for a newline
  explicitly (`case "$p" in *$'\n'*) return 1`), or use `jq -Rs`, and add
  tests for tab, newline and NUL-free control chars.
- **C3. "Moved past the verified head reads not confirmed" is only met when
  the move shows up in the final diff.** See I1 for the failing inputs; the
  single `merge-moved` test covers only the case where a file in the final
  file list differs.
- **C4. The stub ignores `--jq`, so the `gh api` jq programs are never
  exercised.** The `files` test serves pre-flattened paths, so the
  "renamed files by both paths" AC (`.previous_filename // empty`) is not
  tested: dropping `previous_filename` from the expression still passes.
  Likewise the merge path's `@tsv` transport is never run against real JSON,
  which is how I2's tab/backslash false confirm goes unseen. Fix: have the
  stub apply `--jq` with `jq` to a served JSON body (the stub already has
  jq available), and serve real pull-request-files JSON including a rename.

**Advisory**

- Only the `pr` read is timeout-tested. The AC says each stubbed read made to
  time out yields a not-verified fact with its reason; `deferral` has its own
  124 branch, and `blob_at` turns a timeout into "contents read failed", not
  a timed-out reason. Neither is tested.
- Two ACs aren't delivered by this commit and aren't claimed by Issue 5's ACs
  either: the board read "at the live head too when they differ, reporting
  head moved with both shas" (the subcommand takes one sha; head moved comes
  from the report's pr fact), and "a side effect of unknown kind reads not
  re-checked and its How to confirm text appears in no stub log" (no code
  path here). Record who owns them, or add them to Issue 5's ACs.
- The topic part of the row-validation AC has no subcommand here;
  `rd_valid_topic` is defined but untested.
- The read-only assertion (`cat case-*/log`) only sees the last iteration of
  every reused case directory (`bad`, `fail`, `merge-path`), so it covers less
  than it appears to.

## 2. Justification

**Blocking**: none.

**Advisory** (deviations present without a stated reason, in code or commit):

- Board takes a single sha; calling it at both heads is left to the caller,
  unexplained.
- `MERGE_FILE_CAP=100` and the `files` default `CAP=300` appear in neither the
  PRD nor the design (whose caps are for the inventory).
- `close` counts a MERGED pull request as a confirmed close.
- A filed deferral whose issue reads not-found is reported not_verified, not
  undisposed; R15 says "disposed when the issue it names exists".
- An unrecognised board verdict string maps to `fails` (`// "fails"`) rather
  than not_verified.
- `deferral` accepts `undisposed raised-this-run` with exit 0, a line the
  interface stated in `reconcile-deps.sh`'s header doesn't list.

## 3. Intent

**Blocking**

- **I1. The merge check can report confirmed when the default branch does not
  match the verified head.** Three failing inputs, the first two reproduced
  with the test harness:
  1. *Non-removed file absent at both refs.* For a status other than
     `removed`, a 404 at the verified head is treated as "absent" and a 404
     on main as "absent", and they compare equal. Any filename that
     `@tsv` escapes (tab, backslash, newline) is read under a different,
     literal-backslash path, 404s at both refs, and confirms:
     `B tab-escaped: {"verdict":"confirmed"}` (log shows
     `contents/src/a%5C%5Ctb.go`). Fix: a changed, non-removed file absent at
     the verified head is not confirmed; carry the list as JSON, not TSV.
  2. *Rename.* `renamed` entries only check the new path; the old path is
     never required absent on main. `C rename: {"verdict":"confirmed"}`
     with no read of the previous path. Fix: include `previous_filename` as a
     must-be-absent path.
  3. *Branch moved past the verified head and reverted a change.* The file
     list comes from the pull request's final head. If the verified head
     changed `W` and a later commit reverted `W`, `W` is not in the list,
     main holds the base content (not the verified head's), and the check
     confirms. This is exactly the AC's "branch moved past the verified head"
     case. Fix: also read `headRefOid`; when it differs from the verified
     head, take the changed files at the verified head (compare API,
     base...verified-head) and union them with the pull request's list.
  Also: a merged pull request with zero listed files confirms vacuously
  (`D zero files: confirmed`); arguably should be not confirmed.
- **I2. File truncation hides the scoping-ahead contradiction.** `files`
  reads the full list (pagination is uncapped) and then keeps the first
  `CAP` (300). `reconcile-report.sh`'s `outside_docs` ignores `truncated`
  for files. GitHub returns files sorted by path, so a scoping-ahead PR with
  300 `docs/` files and one `src/x` reads consistent. Fix: in the report,
  a truncated file list that is all under `docs/` is not verified (or
  flagged); or have `files` emit the classification-relevant paths first.
- **I3. The "test-only" overrides are honoured in production.**
  `RD_BOARD_CHECK=${RECONCILE_BOARD_CHECK:-...}` and
  `RD_DEFERRAL_CHECK=${RECONCILE_DEFERRAL_CHECK:-...}` let the calling
  environment choose which executable runs. With
  `RECONCILE_BOARD_CHECK` pointing at a script that prints
  `{"verdict":"verified"}`, every board reads `holds` and a holding at its
  verified head reads "ready to land". The design's security section says
  the environment is an agent-controlled input and the scrub closes
  variables that change what the scripts run; Issue 5's scrub list doesn't
  name these. Fix: drop the env override and let the tests reach the checks
  through a directory override that the pass scrubs, or add both variables
  (and `RECONCILE_READ_DEADLINE`) to Issue 5's refusal list now.

**Advisory**

- A single `merge` invocation can make 1 + 1 + 2x100 reads, each with the
  full deadline; the pass (Issue 5) can clip a per-read deadline but has no
  way to bound a subcommand's total time. Consider a total budget argument.
- Default deadline 8 s is below `board-verdict.sh`'s own 24 s self-stop, so a
  slow-but-healthy board reads not verified unless the pass raises it.
- `pr` has no shape check: `{}` yields `status: ok` with null state/head
  (`F pr {}`), which the report turns into a "pull request" change with an
  empty live value, graded measured.
- `deferral` accepts multi-line output (`disposed closed\nundisposed x` ->
  disposed, how contains a newline).
- Facts otherwise fit the `coordinate-reconcile-facts/v1` header (board
  `at`/`verdict`/`detail`, branch `state`/`tip`, appeared `prs[]`, files
  `paths`/`truncated`, side-effect fact shape). The pass will need to merge
  a deferral fact with its row, which is fine.

## 4. Pragmatic

**Blocking**: none.

**Advisory**

- `RD_TIMED_OUT_MARK` (`touch "${RD_TIMED_OUT_MARK:-/dev/null}"`) is used
  nowhere. Delete it.
- `rd_valid_topic` is unused in Issue 2; land it with Issue 3.
- The `files` cap truncates after the full list is already read, so it bounds
  nothing and only discards data (see I2).
- The read-only test's second `grep -vE '^gh (pr view|pr list|issue view) '`
  is redundant with the first.
- `usage()` prints the header via `sed -n '17,27p'`, which breaks silently
  when the header moves.

## 5. Architect

**Blocking**

- **A1. `rd_deadline` doesn't bound wall time for a command that forks.**
  It kills only the direct child. When the command is a shell script (the
  board and deferral checks both are) its children keep the command
  substitution's stdout pipe open, so `OUT=$(rd_deadline ...)` blocks until
  they exit. Measured: `rd_deadline 1 script-that-runs-sleep-6` returned 124
  after 6 s; a board stub sleeping 4 s under `DL=1` returned after 4 s. The
  suite's own `slow` case takes 5 s for a 1 s deadline. R30 and Issue 5's
  budget both depend on this. Fix: send the command's stdout to a temp file
  and read it after `wait` (so orphans can't hold the caller), and kill the
  process group (`set -m` for the child, `kill -TERM -- -$pid`), escalating
  to KILL after a grace period.
- **A2. `rd_urlencode_path` is a shared helper that accepts newlines** (see
  C2). Issue 3's inventory sends paths walked from a worker's clone, which
  can contain real newlines, to the contents API; the helper would split
  one path into two lines, or silently drop a trailing newline and read a
  different file.

**Advisory**

- A non-numeric `RECONCILE_READ_DEADLINE` makes `sleep` fail, so the watcher
  never kills and there is no deadline at all; `0` kills every read. Validate
  it.
- No TERM-to-KILL escalation; a command that ignores TERM runs unbounded.
- Exit 143 and 124 from the command itself read as "timed out".
- Every read leaves an orphaned `sleep $DEADLINE` (killing the watcher
  subshell doesn't kill its sleep); a 100-file merge leaves ~200 behind for
  8 s.
- The repository pattern inherited from `coord-common.sh` allows a leading
  `-` (`--repo -x/y` reached `gh`). Harmless as a flag value today, but worth
  tightening at the source.
- Dependency direction (coordinate sourcing `/execute`'s `coord-common.sh`)
  matches Decision 2, and the CI path filter was extended for it. No bash 3.2
  incompatibilities found (`[[ =~ ]]` with unquoted literals, `$'\t'`,
  `local`, heredoc-fed loop so `exit` in `refuse` leaves the script).

## 6. Maintainer

**Blocking**: none.

**Advisory**

- Comments that aren't true: `rd_urlencode_path` "refuses ... any control
  character" (newline passes); `rd_deadline` implies a bounded run (not for
  forking commands); "Overridable for tests only" (not enforced).
- `reconcile-deps.sh`'s stated deferral-check interface omits the
  `undisposed raised-this-run` line the code depends on.
- The test header's read-only claim reads stronger than the reused-case-dir
  logs support (see Completeness).
- The board `detail` jq one-liner (first reason, name-or-code, parenthesised
  detail) is dense enough to deserve a named `def`.
- `blob_at` is defined inside a `case` arm; moving it to top level next to
  `read_or_fail` would make the file's two read helpers easier to find.
