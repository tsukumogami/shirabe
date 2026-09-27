# Review panel, round 2: Issue 2 (GitHub re-checks for reconcile), commit d839101

Scope: `skills/coordinate/scripts/reconcile-check.sh`, `reconcile-deps.sh`,
`reconcile-check_test.sh`, and the `docs_unsettled` change in
`reconcile-report.sh` / `_test.sh`, as of HEAD.

Suites run: `reconcile-check_test.sh` passed=68 failed=0;
`reconcile-report_test.sh` passed=66 failed=0.

Experiments: a scratch copy of the test file's harness (lines 1-91) plus extra
cases, run once and removed; and one real, read-only `gh api` compare call
against `octocat/Hello-World` to see how `gh --jq` frames raw string output.

## Round-1 blocking findings: status

| Round-1 finding | Status |
|---|---|
| Merge: changed file absent at both refs confirms | Closed. Now "a changed file is missing at the verified head" (not_verified); tested (`merge-404-both`). |
| Merge: rename's old path never checked | Closed in logic (old path emitted as a `removed` entry); tested. See B1: in production it only works when the rename is the first entry. |
| Merge: file reverted after the verified head | Closed. File list is now `compare/<base.sha>...<verified head>`; tested (`merge-reverted`). |
| Merge: zero files confirms vacuously | Closed. Refused as not_verified. |
| Files truncation hides scoping contradiction | Closed. `docs_unsettled` keeps the flag off and lists the holding under not_verified; tested. |
| Env overrides choose the board/deferral check | Closed. Overrides removed; tests run a copied tree; `board-env` test proves the variable is ignored. |
| `rd_deadline` doesn't bound a forking command | Closed. Stdout goes to a file, children get TERM then KILL; the `slow` case (stub forks `sleep 6`) now returns within 3 s for a 1 s deadline. |
| Newline/control characters accepted in paths | Closed. `case *[[:cntrl:]]*` plus `jq -Rs`; newline and tab now tested. |
| Vacuous path-refusal tests | Closed. Every `new_case` gets a fresh directory, and the loop asserts the "refused a file path" reason and an empty contents log. |
| Stub ignores `--jq`, so the `gh api` jq programs never run | **Not closed**, and it hides B1 below. |

## New blocking defects

### B1. Real `gh --jq` output breaks the merge list for every entry after the first

`gh api --jq` prints each string result followed by a newline (go-gh's
`EvaluateFormatted` uses `Fprintln`). Checked against GitHub:

```
gh api repos/octocat/Hello-World/compare/7fd1a60...b3cbd5b --jq '<the merge program>' | od -c
a d d e d \0 C O N T R I B U T I N G . m d \0 \n
```

So the list file is `modified\0src/a.go\0\nremoved\0src/gone.go\0\n`, and the
`read -d ''` loop reads the second status as `"\nremoved"`. That is not
`removed`, so the deleted file is looked up at the verified head, 404s, and
the check refuses. Reproduced with the harness serving the real framing:

```
compare: 'modified\0src/a.go\0\nremoved\0src/gone.go\0\n'
-> {"status":"not_verified","reason":"a changed file is missing at the verified head"}
compare: 'modified\0src/a.go\0\nremoved\0src/old.go\0\nrenamed\0src/new.go\0\n'
-> same
```

Result: any merged pull request that deletes or renames a file anywhere but
first in the compare list can never read confirmed. It fails closed (no false
confirm), but the AC "a file deleted at the verified head is confirmed only
by a not-found on the default branch" is unmet against real `gh`, and the
suite passes only because `serve_nul` hands the loop a framing `gh` never
produces. Fix: strip the separator (`status=${status#$'\n'}`), or have the jq
program emit one `tojson` line per `[status, path]` and parse that (as `files`
already does); and make the stub apply `--jq` to a served JSON body so the
real program runs in tests.

### B2. A removed-only merge confirms when the base ref itself 404s

`blob_at` maps any output containing `HTTP 404` to `absent`. The contents
API also returns 404 for a ref that doesn't exist (`No commit found for the
ref main`). For a `removed` entry, `absent` is the wanted value, so a pull
request whose verified-head diff is only deletions, merged into a base that
has since been deleted (common for a stacked pull request whose base branch
was auto-deleted after its own merge), reads confirmed without a single
successful read of the base:

```
compare: 'removed\0src/gone.go\0\n'
contents?ref=main: rc 1, "gh: No commit found for the ref main (HTTP 404)"
-> {"status":"ok","verdict":"confirmed"}
```

Fix: tell a missing file from a missing ref (match "Not Found" on the
file-level message only, or resolve the base ref to a sha once with
`gh api repos/R/commits/<ref> --jq .sha` before the loop and read contents at
that sha, refusing when it fails).

## 1. Completeness

**Blocking**

- The `--jq` programs are still never executed by the suite (round-1 C4).
  The `files` rename test only greps the log for the word
  `previous_filename`, and the merge tests serve hand-made NUL framing. This
  is how B1 passed. Fix as in B1.

**Advisory**

- The merge-late case asserts only not_verified; `blob_at` reports a
  timed-out contents read as "contents read failed ...", not "timed out",
  and the AC asks for the reason. The deferral 124 branch has no test.
- Still unowned from round 1: board "at the live head too when they differ,
  reporting head moved with both shas" (the subcommand takes one sha), and
  "a side effect of unknown kind reads not re-checked and its How to confirm
  text appears in no stub log" (covered only by `reconcile-report_test.sh`,
  not by any stub log). Record in Issue 5 or the plan who owns them.
- The topic half of the row-validation AC has no subcommand here;
  `rd_valid_topic` is defined and unused.
- No test serves a malformed pull-request read to `merge` (see Intent).

## 2. Justification

**Blocking**: none.

**Advisory**

- `MERGE_FILE_CAP=100` and `FILES_CAP=300` still appear in neither PRD nor
  design; the comments now say why they exist but not why these numbers.
- `merge` compares against the pull request's `base.ref`, not the
  repository's default branch the AC names; the variable is still `DEFAULT`
  and the reasons say "default branch". Either state that the base is
  intended or read the repository default.
- The board subcommand still takes one sha; calling it twice for "head
  moved" is left to the caller without a note saying so.

## 3. Intent

**Blocking**

- B1 (deletions/renames after the first entry never confirm).
- B2 (removed-only merge into a deleted base confirms with no base read).

**Advisory**

- `merge` turns an unreadable pull-request read into a verdict, against the
  commit's own "never a verdict" claim: `{}` yields
  `status: ok, verdict: not_confirmed, reason: "pull request is unknown, not merged"`,
  and `not json` yields `reason: "pull request is , not merged"`. Real
  `gh` won't return these with exit 0, so advisory; fix by requiring
  `.merged | type == "boolean"` and a known state, else not_verified.
- `compare/<base.sha>...<verified head>` is a three-dot diff from the merge
  base. If the branch merged main in after `base.sha` was recorded, main's
  files join the list, and a later change to one of them on main reads not
  confirmed. Fails closed; worth a comment.
- A single `merge` can make 2 + 2x100 reads, each with the full deadline.
  The pass can clip the per-read deadline but can't bound the subcommand's
  total, so Issue 5's "never plans past its budget" has no handle here.
  Consider a total-budget argument.
- `RECONCILE_READ_DEADLINE` / `RECONCILE_BOARD_DEADLINE` accept up to 9999,
  so the environment can lengthen a read, not only shorten it. Issue 5's
  `env -i` re-exec drops them, so no action needed here beyond the header
  (see Maintainer).

## 4. Pragmatic

**Blocking**: none.

**Advisory**

- `rd_valid_topic` is unused in this issue; land it with Issue 3.
- `pkill -P "$watcher"` after `wait "$watcher"` is a no-op: the watcher's
  `sleep` has already been reparented. Delete it or kill the sleep another
  way.
- `files` still reads the full paginated list before cutting it to 300, so
  the cap bounds nothing but output size.

## 5. Architect

**Blocking**: none (B2's root is architectural, below, but is counted under
Intent).

**Advisory**

- `blob_at` folds two different 404s (missing file, missing ref) into one
  `absent`. That ambiguity is the root of B2 and will recur for Issue 3's
  host reads if the helper is reused; resolve the ref once, then read by sha.
- `rd_deadline` keeps stdout off the pipe but lets stderr through, and
  `blob_at` routes that stderr into its `$(...)` with `2>&1`. A grandchild
  that survives TERM and holds stderr would hold the caller open. Today `gh`
  doesn't fork, so this is latent; say so, or send stderr to a file too.
- Grandchildren (below the command's direct children) are not signalled, and
  each read leaves an orphan `sleep $secs`. Neither blocks the caller now.
- bash 3.2: no incompatibilities found. No associative arrays, `mapfile`,
  case-modification expansions, `;;&`, `|&`, `wait -n` or `printf -v`;
  `read -r -d ''`, `$'\n'` in case patterns, `[[:cntrl:]]`, unquoted `=~`
  literals and `"$@"` (always non-empty under `set -u`) are fine in 3.2. BSD
  `tr -cd '\0'`, `wc -c` padding (stripped), `mktemp` templates and `pkill
  -P` are fine on macOS.

## 6. Maintainer

**Blocking**: none.

**Advisory**

- The comment "status NUL path NUL" describes a framing `gh` doesn't
  produce (there's a newline after each pair); fix with B1.
- `reconcile-check.sh`'s header says "A deadline can only make a read give
  up sooner" — the variables can raise it to 9999 s.
- The `rd_deadline` comment "The watcher's own sleep may outlive it; it
  holds nothing of ours" sits on a line that does nothing.
- `DEFAULT` and "on the default branch" name the pull request's base branch.
- `blob_at` / `blob_or_refuse` are still defined inside the `merge` arm, away
  from `read_or_fail`.
