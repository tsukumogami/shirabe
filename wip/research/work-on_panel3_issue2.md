# Review panel, round 3: Issue 2 (GitHub re-checks for reconcile), commit 53a1732

Scope: `skills/coordinate/scripts/reconcile-check.sh`, `reconcile-deps.sh`,
`reconcile-check_test.sh` as of HEAD.

Suites run: `reconcile-check_test.sh` passed=73 failed=0;
`reconcile-report_test.sh` passed=66 failed=0.

Regression check: the current test file run against HEAD~1's
`reconcile-check.sh` and `reconcile-deps.sh` (copied tree under /tmp, removed
afterwards) fails 10 cases, including "deletions after the first entry
confirm too", "contents are read by resolved sha, never by branch name", "no
contents read without a resolved base", "a malformed pull request read is not
verified" and "a late contents read says it timed out". So the new tests bite
on the round-2 code.

## Round-2 blocking findings: status

| Round-2 finding | Status |
|---|---|
| B1: `gh --jq` newline broke NUL framing after the first entry | Closed. The list is one `tojson` object per line, parsed with `jq` per line; a control character in a path is refused while still JSON. The stub now runs each call's own `--jq` program with `jq -r`, which prints a newline after every string exactly as `gh` does, so a NUL-framed regression would fail `merge-deletions-later` and `merge-confirmed`. |
| B2: 404 on a missing base ref read as absent | Closed. The base branch is resolved once via `git/ref/heads/<base>` and every contents read names that sha; a failed resolve is not_verified before any contents read. `merge-base-gone` asserts both the status and an empty contents log, and `merge-confirmed` asserts no read uses `ref=main`. |
| Stub ignored `--jq` | Closed. Served bodies are API-shaped JSON and the script's programs run over them (`files`, `merge` pull/ref/compare/contents). |

Round-2 advisories also closed: malformed pull request read is now
not_verified (tested), late contents read says "timed out" (tested),
deadlines clamped to 1-60, `blob_at`/`blob_or_refuse` moved to top level,
`DEFAULT` renamed `BASE_BRANCH`, the no-op `pkill -P` after `wait` removed.

## New blocking defects

None found. Every new path examined fails closed: a directory at a path
(contents returns an array, `--jq .sha` errors), an unreachable verified head
(compare 404), an empty compare list, a null `.s` or `.p`, a compare list
over the cap.

## 1. Completeness

**Blocking**: none.

**Advisory**

- The deferral check's timeout branch (rc 124, "disposal check timed out")
  still has no test; the "late" loop covers pr-list, ls-remote, api-files,
  issue-view and board only.
- The 1-60 clamp on `RECONCILE_READ_DEADLINE` / `RECONCILE_BOARD_DEADLINE`
  has no test (e.g. 9999 falling back to 8).
- Still unowned here: board "at the live head too when they differ" (the
  subcommand takes one sha; "head moved" comes from the report comparing the
  pr fact to the row), the topic half of the row-validation AC
  (`rd_valid_topic` defined, unused), and "How to confirm text appears in no
  stub log" (only `reconcile-report_test.sh` touches unknown side effects).
  Say in the plan which issue owns each.

## 2. Justification

**Blocking**: none.

**Advisory**

- `MERGE_FILE_CAP=100` / `FILES_CAP=300` still have no stated basis in the
  PRD or design.
- Over the merge cap the verdict is `not_confirmed`, which the report turns
  into a "merge not confirmed" flag, i.e. the same signal as a merge that
  didn't land. "Too many files to read" is closer to not_verified. Also
  `COUNT` counts list entries, so a rename counts twice and the reason's
  "N changed files" overstates (60 renames read "120 changed files").

## 3. Intent

**Blocking**: none.

**Advisory**

- `compare/<base.sha>...<verified head>` is three-dot. If `base.sha` is older
  than the branch's fork point, or the branch merged main in, main's own
  files join the list and a later change to one of them on main reads not
  confirmed. Fails closed; worth a one-line comment on the merge arm.
- `blob_at` captures stderr with `2>&1` into the value it validates, so a
  successful read that also writes anything to stderr (a gh warning) reads
  "contents read failed". Fails closed, but it would turn every merge into
  not_verified on such a host; read the sha from stdout and grep stderr for
  the 404 separately.
- One `merge` can still make 3 + 2x100 reads at the full per-read deadline;
  no total budget argument for Issue 5 to pass.

## 4. Pragmatic

**Blocking**: none.

**Advisory**

- `rd_valid_topic` is unused in this issue; land it with its first caller.
- `files` reads the full paginated list before cutting to 300; the cap bounds
  output only.

## 5. Architect

**Blocking**: none.

**Advisory**

- `blob_at` mixes stdout and stderr in one capture (see Intent). The ref
  ambiguity that caused B2 is gone, but the helper still decides "absent" by
  substring on combined output; keep the streams apart if Issue 3 reuses it.
- The stub applies `jq -r`, which pretty-prints non-string results where
  `gh --jq` prints compact JSON. Every program in the script ends in a string
  today, so the stub is faithful; a future `--jq` returning an object would
  not be.
- `rd_deadline` still leaves an orphan `sleep $secs` per read (killing the
  watcher subshell doesn't kill its sleep) and doesn't signal grandchildren.
  Harmless now; note it.

## 6. Maintainer

**Blocking**: none.

**Advisory**

- The merge arm's header comment calls the list "the verified head's own
  diff" without saying it is a three-dot diff from the merge base.
- The test header (lines 7-13) doesn't say that served `.out` files are JSON
  bodies run through the caller's `--jq`; that's only in the stub's inline
  comment, and a new case author serving pre-shaped output will get a
  confusing failure.
