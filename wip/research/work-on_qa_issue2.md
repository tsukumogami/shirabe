# QA: Issue 2 (GitHub re-checks for reconcile)

Target: `skills/coordinate/scripts/reconcile-check.sh` (with `reconcile-deps.sh`
and `/execute`'s `coord-common.sh`), at worktree HEAD 53a1732.

## Method

A copy of the scripts was built in a temp tree the way
`reconcile-check_test.sh` does: `reconcile-check.sh`, `reconcile-deps.sh` and
`reconcile-report.sh` under `skills/coordinate/scripts/`, `coord-common.sh`
under `skills/execute/scripts/`, and stand-in `board-verdict.sh` and
`deferral-check.sh` beside them. A separately written stub served `gh`, `git`
and both record-feature checks: it logs every call, serves API-shaped JSON
(full pull request, ref, compare and contents bodies, not pre-shaped
answers), applies the caller's `--jq` with `jq -r` the way gh does, emulates
`--paginate` by applying `--jq` to each served page, and can inject exit
codes, stderr (`gh: Not Found (HTTP 404)` and similar), delays and a
grandchild that holds stdout open. Where an acceptance criterion is stated
in report terms ("changed with both values", "head moved", "ambiguous", "not
re-checked"), the facts were fed to `reconcile-report.sh json` to check the
end-to-end result. Each case ran in a fresh directory. The harness and stub
lived in a job scratch directory outside the repo; nothing in the repository
was edited.

18 scenarios, 18 passed, 0 failed. The shipped suites also pass:
`reconcile-check_test.sh` 73 passed, 0 failed; `reconcile-report_test.sh` 66
passed, 0 failed.

## Scenarios

| # | Scenario | Result |
|---|----------|--------|
| S1 | Holding recorded open, PR reads MERGED | pass |
| S2 | Parked holding (verified head set) back in draft | pass |
| S3 | Head moved: board at verified head and live head | pass (see AC 2 note) |
| S4 | Board holds / fails naming a runner-less job / error and garbage verdicts | pass |
| S5 | Files: two pages, rename both paths, removed file, 400 files capped at 300, empty list | pass |
| S6 | 21 hostile row values (repo, branch, sha, base, number, verified head) | pass |
| S7 | Branch gone, tip differs, URL from the row even inside a clone with another remote | pass |
| S8 | Appeared: one, two (ambiguous), none | pass |
| S9 | Merge confirmed (modified, added, removed) | pass |
| S10 | Merge where the branch moved past the verified head, PR merged | pass |
| S11 | Deleted-at-verified-head file: 404 confirms; present, 502 or 403 don't | pass |
| S12 | Deleted base branch; ref body without sha; hostile base ref from API; closed unmerged | pass |
| S13 | Close confirmed / not confirmed; unknown side-effect kind; How-to-confirm text | pass |
| S14 | Deferrals: filed existing, filed missing issue, closed, carried, none, hostile number | pass |
| S15 | Hostile paths in the merge file list; per-segment encoding | pass |
| S16 | 13 distinct reads each made to time out; grandchild holding stdout; deadline clamps | pass |
| S17 | Non-timeout failures (HTTP 502, ls-remote 128, non-array list) | pass |
| S18 | Allowlist over all 144 logged calls | pass |

## Acceptance criteria

1. **Merged and draft changes: pass.** The `pr` fact for a MERGED stub is
   `{state:"MERGED", head, merge_state, read_at}` from one
   `gh pr view 7 --repo acme/widgets --json state,isDraft,headRefOid,mergeStateStatus,baseRefName`.
   Fed to the report with a row recorded `#7`, it gives
   `{what:"pull request", recorded:"open", live:"merged"}` and next `drop`.
   An OPEN draft with a verified head gives `{what:"draft", recorded:"ready (parked)", live:"draft"}`.

2. **Board: met by composition, not by the subcommand alone.** The board
   subcommand calls `board-verdict.sh` beside the script (resolved through
   `reconcile-deps.sh`, no env override) at the sha it's given. Called at
   the verified head and at the live head, the log shows both calls; the
   verified head reads `holds` and the live head
   `fails` with detail `lint (no runner name)`. The report then shows
   `{what:"head moved", recorded:<verified>, live:<live>}` and board
   `fails: lint (no runner name)`, next `fix_ci`. An all-real board reads
   `holds`; `error:deadline` and unparseable output read not verified.
   Gap: the subcommand takes a single `--sha` (`--live-head` is a usage
   error, exit 64). Reading the live head as well is left to the caller
   (the pass, Issue 5), and "head moved" comes from `reconcile-report.sh`
   comparing the pr fact to the row. The AC's wording puts both on the board
   subcommand, so Issue 5 has to own the second read or the AC should be
   reworded.

3. **Files: pass.** Uses `?per_page=100 --paginate`. Two pages (100 + 2
   entries) gave 103 paths, including both sides of a rename (`src/new.go`,
   `src/old.go`) and the removed `src/dead.go`. Four pages of 100 gave 300
   paths with `truncated:true`.

4. **Invalid row values reach no command: pass for repository, branch, sha
   and number; topic not exercisable.** Branches `-x`, `a;b`, `$(id)`,
   `a..b`, `a b`, and one with a newline; repos `acme/widgets;id`, `../x`,
   `acme/..`, `-x/y`, `a;b`; numbers `7;id`, `07`, `-1`, `1e3`; an uppercase
   sha, a 39-char verified head; base `-x` and `a;b`. Each printed a
   not_verified fact with exit 0 and an empty stub log. No Issue 2
   subcommand takes a topic, and `rd_valid_topic` has no caller yet.

5. **Branch: pass.** Empty `ls-remote` reads `gone` and the report says
   "branch gone". Tip `2222…` against pr head `1111…` gives
   `{what:"branch tip differs", recorded:"1111…", live:"2222…"}`. Run from
   a directory whose `.git/config` names `evil/other`, the only git call is
   `git ls-remote https://github.com/acme/widgets.git refs/heads/feat/a`. A
   ref line for `feat/a-other` doesn't count as `feat/a`, and a failed
   `ls-remote` (exit 128) is not verified, never gone.

6. **Appeared: pass.** One PR gives "pull request appeared" with its URL.
   Two give "pull request ambiguous" listing both `pull/9` and `pull/12`.
   The listing uses `--state all`.

7. **Merge: pass.** The file list comes from `compare/<base sha>...<verified head>`,
   and contents are read by resolved sha, never `ref=main` or the live
   head. With modified, added and removed files all matching, the verdict
   is confirmed. With `src/b.go` differing on the base while the PR is
   merged: `not_confirmed` naming `src/b.go`, and the report lists it under
   waiting. A removed file is confirmed by a 404 on the base. The file
   still present, a 502 or a 403 each read not confirmed or not verified.
   A deleted base branch (`git/ref` 404) is not verified, and no compare or
   contents read follows.

8. **Close and unknown side effects: pass.** Closed issue: confirmed. Open
   PR: `not_confirmed`, "target is open". An unknown state: not verified.
   A side-effect row of unknown kind with no fact reads `not rechecked`,
   graded inferred, in the report. Its How-to-confirm text
   (`gh api -X DELETE ...; touch /tmp/qa2-pwned`) appears in none of the 144
   logged calls and was never run. `close --kind label` is a usage error
   (64) with no call.

9. **Deferrals: pass.** `disposed filed #5` plus
   `gh issue view 5 --repo acme/widgets --json number` succeeding reads
   disposed, `filed #5`. Closed and carried read disposed.
   `undisposed no-disposition` with exit 1 reads disposed:false. A filed
   deferral whose issue read fails (GraphQL could-not-resolve) reads **not
   verified**, not disposed or undisposed, and the report lists it under
   Not verified rather than under undisposed deferrals. That's the
   documented choice, since gh can't tell a missing issue from a failed
   read. `disposed filed 5;id` is refused with no gh call.

10. **Hostile paths: pass for the paths that reach a command.** In the merge
    compare list, `../etc/passwd`, `/etc/passwd`, `src/../../x`, `a/..`,
    `src/./a`, and paths holding U+0001, ESC or CR, plus a rename whose
    `previous_filename` is `../../etc/shadow`, are each refused as "refused
    a file path from the pull request" before any contents read.
    `d ir/f%o?o#1&x=é.md` is encoded as
    `d%20ir/f%25o%3Fo%231%26x%3D%C3%A9.md` with the slash kept, and
    `x?ref=main` can't override the ref.
    Observation (not a failure): the `files` subcommand passes list paths
    through unchecked (`["docs/../src/evil.go","/abs"]` reads status ok).
    They reach no command, but `reconcile-report.sh` then treats
    `docs/../src/evil.go` as inside `docs/` and doesn't flag a scoping-ahead
    holding. Git normally rejects `..` tree entries, so the practical risk
    is low. Refusing such paths in `files`, or treating them as outside
    `docs/`, would close it.

11. **Timeouts: pass.** With a 1 s deadline and a 6 s stub delay, each of
    these returned a not_verified fact within 1-2 s, with a reason naming the
    timeout: pr view, board check, ls-remote, pr list, files, and the merge
    reads (pull, git ref, compare, contents at the verified head, contents
    on the base). The same held for close, the deferral check, and the
    deferral's issue view. A stub that leaves a grandchild holding stdout
    still returned at the deadline. Deadlines `abc` and `0` fall back to the
    default rather than timing out at once.

12. **Read-only: pass.** Across all 144 calls: gh pr view (10), gh pr list
    (5), gh issue view (6), gh api GET (100, only `--jq` and `--paginate`),
    git ls-remote (6), board-verdict.sh (8), deferral-check.sh (9). There
    are no `-X`, `--method`, `-f`, `-F`, `--field` or `--input` flags, and
    no git subcommand other than ls-remote.

## Follow-ups

- AC 2's second board read, at the live head, isn't done by the board
  subcommand. Issue 5 (the pass) needs to own it, or the AC should be
  reworded.
- AC 4's topic half has no Issue 2 caller. `rd_valid_topic` should land with
  Issue 3's listing subcommand and be tested there.
- The `files` subcommand accepts `..` and absolute paths into an ok fact,
  and `docs/../x` counts as inside `docs/` in the report (low risk).
