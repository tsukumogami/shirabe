# QA: Issue 3 (host re-checks for reconcile)

Scope: the `host`, `teardown`, `leg` and `inventory` subcommands of
`skills/coordinate/scripts/reconcile-check.sh`, judged against Issue 3's
acceptance criteria in `docs/plans/PLAN-coordinate-reconcile.md`.

Result: 48 scenarios, 45 passed, 3 failed. Seven of the eight acceptance
criteria pass. The inventory criterion fails in one realistic condition: a clone
that hasn't fetched the default branch since the squash-merge.

## Environment

The QA tree lived in a job temp directory outside the repository. The scripts
(`reconcile-check.sh`, `reconcile-deps.sh`, `reconcile-report.sh`, and
/execute's `coord-common.sh`) were copied into it with the same layout that
`reconcile-check_test.sh` uses. Fakes on PATH logged every call:

- `niwa list --json` served a listing file, with knobs for exit code, delay and
  absence.
- `koto request get <id>` served `<id>.json` from a request-store directory,
  or exited 2 with a JSON error when the id was unknown. It also had knobs for
  delay and garbage output.
- `gh api` stood in for GitHub, backed by real bare repos (`gh/acme/alpha.git`,
  `gh/acme/beta.git`). `git/trees/<sha>?recursive=1` was built from
  `git ls-tree -r -t` in API shape and run through the caller's own `--jq`. The
  contents endpoint was served too.
- The `git` wrapper served `ls-remote https://github.com/<o>/<r>.git` from the
  matching bare repo and passed every other call to the real git. An optional
  hang knob covered one subcommand.

The workspace root held three instances: `tsuku+other_topic-11111111`,
`tsuku+coordinate_reconcile-730e6b0e` (the worker) and `tsuku+recon-22222222`.
Extra instances were added for single scenarios. The worker instance contained:

- `public/alpha`, with a github.com origin, holding:
  - `main`, pushed.
  - `feat/pushed`, still on the remote.
  - `feat/deleted`, pushed and then deleted on the remote, never merged.
  - `feat/unpushed`, never pushed.
  - `feat/squash`, pushed. Its content (config.txt v2, squash1/2) landed on
    GitHub's main as a squash commit plus a later commit, and the branch was
    deleted on the remote. The clone never fetched afterwards.
  - An uncommitted edit to `main.go`, a staged new file `staged.txt`, an
    untracked unique `NOTES.md`, and an untracked `later.txt` whose content is
    on GitHub's main.
  - One stash.
  - A linked worktree inside the instance (`public/alpha-wt`, branch
    `feat/in-wt` with an unpushed commit) and one outside it (`outside/alpha-far`).
- `public/beta`, a clean clone with everything pushed (nothing unique).
- `public/secret-link`, a symlink to a clone outside the instance.

A setup mistake of mine was caught and fixed. The first world stashed after the
`main.go` edit, which reverted it, so the edit was re-applied after the stash
(run `inv-main2`).

## Scenarios

### host (listing)

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | Worker found by topic `coordinate-reconcile` | pass | `state:"found", reads:1, path:.../tsuku+coordinate_reconcile-730e6b0e`; one `niwa list --json` call |
| 2 | Topic with spaces and capitals (`Coordinate Reconcile`) slugs to the same instance | pass | found, same path |
| 3 | Worker missed (`coordinate-dispatch`) | pass | `{"state":"missed","reads":1,"read_at":"2026-09-27T03:21:30Z"}`, exactly one call, took 0s |
| 4 | `reco` (prefix of `recon`/`reconcile`) | pass | missed |
| 5 | `recon` beside `coordinate_reconcile` | pass | found its own `tsuku+recon-22222222` only, not ambiguous |
| 6 | `reconcile` (suffix of `coordinate_reconcile`'s slug) | pass | missed |
| 7 | Two instances for one topic | pass | `state:"ambiguous"` |
| 8 | `niwa` exits 3 | pass | `not_verified`, "read failed (exit 3)" |
| 9 | `niwa` sleeps 5s against a 2s deadline | pass | `not_verified`, "read timed out after 2s", 2s wall time |
| 10 | No `niwa` on PATH | pass | `not_verified`, "read failed (exit 127)" |
| 11 | Topic `../x;rm` | pass | `not_verified`, "invalid dispatch topic", zero calls |
| 12 | GitHub read while `niwa` fails (`branch --repo acme/alpha --branch feat/pushed` with the niwa knob at exit 3) | pass | `branch` fact ok, present, tip read via ls-remote; unaffected |

The host branch contains no `sleep`; the 30-second re-read is left to the pass.

### teardown

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 13 | Instance gone from the listing and from disk | pass | `verdict:"confirmed"` |
| 14 | Unlisted, but its directory is still on disk | pass | `not_confirmed`, "its instance directory is still on disk" |
| 15 | Still listed | pass | `not_confirmed`, "the instance is still listed" |
| 16 | Topic `coordinate` while `..._reconcile-...` is still listed and on disk | pass | confirmed (no prefix bleed) |
| 17 | Directory `tsuku+gone_x-zzzzzzzz` (non-hex suffix) | pass | ignored, confirmed |
| 18 | `niwa` fails | pass | `not_verified`, "read failed (exit 1)" |
| 19 | `niwa` late | pass | `not_verified`, "read timed out after 1s" |
| 20 | Listing is `[]` (last instance torn down) | pass, with a note | `not_verified`, "the workspace root could not be found from the listing". This is a safe fallback, never a false confirmed. But when no instance is left to infer the root from, a real teardown can never read confirmed. |

Minor: the `confirmed` fact carries `reads:1` and `not_confirmed` does not.

### leg (request store)

The request store held `req-7` with legs `deliver` (outcome merged),
`work-on` (engine status failure at `blocked_on_review`), `review` (refused,
reason `scope-outside-repos`) and `later` (open, no child).

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 21 | Deliver leg | pass | `disposition:"resolved", result:"merged"`; call `koto request get req-7` |
| 22 | Work-on leg | pass | `result:"failure at blocked_on_review"` |
| 23 | Refused leg | pass | `result:"refused:scope-outside-repos"` |
| 24 | Open leg without a child | pass | `disposition:"open", result:""` |
| 25 | `return_path` = `message` | pass | `not_verified` "the holding reports by message; no leg to read"; the call log is 0 bytes |
| 26 | Unknown request (koto exits 2) | pass | "request not found on this host" |
| 27 | Unknown leg name | pass | "the request has no readable leg by that name" |
| 28 | koto late | pass | "read timed out after 1s" |
| 29 | koto prints non-JSON | pass | `not_verified` (reason reads "no readable leg by that name", which is imprecise but safe) |
| 30 | No koto on PATH | pass | "read failed (exit 127)" |
| 31 | `leg req-7;id:deliver` | pass | "invalid request id", zero calls |
| 32 | `pr 42` as the return path | pass | "unreadable return path", zero calls |
| 33 | Request file unreadable | pass | `not_verified` |

### inventory

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 34 | Worker instance items | pass | `public/alpha` lists: commit `branch feat/deleted`, commit `branch feat/unpushed`, commit `branch feat/in-wt`, change `stash (1 entries)`, change `main.go`, change `staged.txt`, file `NOTES.md`, worktree `alpha-far (outside the instance, not read)`. It doesn't list `feat/pushed`, `later.txt` (content on main) or `README.md` (restored by stash). `public/beta` lists no items. |
| 35 | Read-only call shape | pass | 65 git calls; every in-clone call starts with `--no-optional-locks -c core.fsmonitor= -c core.hooksPath=/dev/null -c protocol.allow=never`. ls-remote runs with `-C /` plus `protocol.https.allow=always`. hash-object is always `--no-filters --stdin-paths`, never `-w`. No fetch/pull/push/checkout/status/add/commit/stash/reset/update-index in the log. gh calls are only `git/trees/<sha>?recursive=1`. |
| 36 | Clones untouched | pass | index cksums, `.git` listing, for-each-ref and stash list are identical before and after |
| 37 | Squash-merged branch in a clone that has GitHub's merge commit (fresh clone, instance `squash_only`) | pass | `items:[]`, rendered "nothing unique found" |
| 38 | Clean clone alone | pass | `items:[]` |
| 39 | Squash-merged branch in a clone that has not fetched since the merge (`public/alpha`, `feat/squash`) | **FAIL** | listed as commit `branch feat/squash`. `inv_landed` needs `cat-file -e <GitHub main sha>^{commit}` and `merge-base` locally. The clone lacks the squash commit (confirmed "absent in alpha clone"), so it returns 1 and the branch is listed as unique although every changed file's blob matches GitHub's tree. The unit test only covers a default-branch sha that exists locally. |
| 40 | Default branch behind GitHub (someone merged after the clone; no fetch) | **FAIL** | `{"clone":"beta","kind":"commit","path":"branch main"}`. The local main tip is an ancestor of GitHub's main, but the exclusion list only includes live shas the clone already has, so a stale but fully pushed main reads as unpushed work. False positive in a common condition. |
| 41 | Linked worktree inside the instance | **FAIL** (defect, not tied to a criterion) | `public/alpha-wt` repeats every ref-level item of `public/alpha`: four branches, the stash, and the outside worktree. The shared ls-remote and tree reads also run twice. The rendered "Exists nowhere else" line shows each branch twice. |
| 42 | In-clone git call hangs (rev-list sleeps 30s, deadline 2s) | pass | items `unchecked` "branch feat/sq2 could not be compared with the remote" / "branch main ..."; 4s total |
| 43 | 21 clones | pass | exactly 20 clones read (distinct `-C`), `truncated:true`; renders "nothing unique found in what was read, but not everything was read" plus a Not verified line |
| 44 | 205 untracked files | pass | `truncated:true`, 200 items |
| 45 | Symlink to an outside clone; clone with `.git` symlinked outside | pass | symlink not followed (0 calls touching `outside/`); gitlink clone `unchecked` "its .git is a symlink, not read". The outside worktree in #34 was listed, not read (0 `-C .../outside` calls). |

### Rendered through reconcile-report.sh

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 46 | Leg results beside PR state; message makes no leg line | pass | "deliver-leg ...; merged (measured); leg resolved: merged (measured)"; "workon-leg ...; open; leg resolved: failure at blocked_on_review"; "refused-leg ...; open; leg resolved: refused:scope-outside-repos"; "by-message ...; open (measured)" with no leg text. Missed worker: "worker not found on this read". |

Outside Issue 3's scope: a refused leg, and a work-on leg resolved as failure,
both still render "Next: wait on worker". That's the report or pass's next-line
logic, and it's worth a look in Issue 1 or 5.

### Existing suites

| # | Suite | Result |
|---|---|---|
| 47 | `reconcile-check_test.sh` | pass, passed=143 failed=0 |
| 48 | `reconcile-report_test.sh` | pass, passed=66 failed=0 |

## Acceptance criteria

1. **One listing read, no sleep; a miss is "missed" with the read time.** Pass
   (#3, grep of the host branch).
2. **Found, ambiguous, and the prefix non-match.** Pass (#1, #4 to #7).
3. **Failing, absent or timed-out niwa, a timed-out in-clone git call, and a
   timed-out or unreadable request-store read are each not verified with a
   reason; GitHub facts unaffected.** Pass (#8 to #10, #18, #19, #42, #28,
   #29, #33, #12).
4. **Inventory: a deleted-remote-branch commit, an uncommitted change and a
   file not on the default branch are listed; a squash-merged branch yields
   "nothing unique found".** **Fail, partially.** The listing half passes
   (#34). The squash half passes only when the clone already holds GitHub's
   default-branch commit (#37). A clone that hasn't fetched since the
   squash-merge lists the branch as a unique commit (#39). A related false
   positive: any clone whose default branch is merely behind GitHub lists
   `branch main` (#40).
5. **Git flags; hash-object `--no-filters`, never `-w`; no fetch, pull, push
   or checkout.** Pass (#35, #36, test suite).
6. **Containment and caps.** Pass (#43 to #45).
7. **Teardown confirmed or not confirmed.** Pass (#13 to #15). Edge case: an
   empty listing can't be confirmed (#20).
8. **Leg result beside the PR state; a message return path makes no
   request-store call.** Pass (#21 to #25, #46).

## Failures

- The inventory lists a squash-merged branch as a unique commit when the clone
  hasn't fetched GitHub's default branch since the merge. The squash check
  needs the default-branch commit locally.
- The inventory lists a fully pushed default branch as a unique commit when the
  clone's default branch is behind GitHub.
- The inventory walks a linked worktree inside the instance as a separate
  clone, so every branch, the stash and the outside-worktree item are listed
  twice.

## Re-run after f22102b

I copied `reconcile-check.sh` fresh from the worktree at f22102b, then re-ran
the same world, now in a later state. `alpha` still lacks GitHub's main commit
185685d. `beta` (in the worker instance and in `beta_only`) sits at 67a0430,
while GitHub's main moved on to ed0c8a7.

The gh fake now answers `repos/R/compare/<base>...<head>` from the bare repo.
It returns 404 when either sha isn't on "GitHub". Otherwise it returns
`behind_by` = commits in the base that the head doesn't reach, plus `ahead_by`
and `status`, all through the caller's `--jq`. A commit from a branch deleted
on the remote stays in the bare repo, as it does on GitHub.

Result: 5 scenarios, 5 passed. All three earlier failures are fixed.

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 39 | Squash-merged `feat/squash` in a clone that hasn't fetched since the merge | pass | No longer listed. Tip 46b4687 compared against main has behind_by 2, so it isn't contained. The squash check then used local main e426553 (GitHub-contained, compare 0) as the merge base, and every changed blob matched GitHub's tree. |
| 40 | Default branch behind GitHub | pass | `beta_only` gives `items:[]` with one compare (67a0430...ed0c8a7, behind_by 0). `public/beta` in the worker instance, now stale too, lists nothing either. |
| 41 | Linked worktree inside the instance | pass | `public/alpha-wt` has no items. It gets 7 own reads only (rev-parse ×2, symbolic-ref, ls-files ×2, ls-tree, hash-object), with no second ls-remote or tree read. The instance makes 2 ls-remote calls (alpha, beta). The items are listed once: feat/deleted, feat/in-wt, feat/unpushed, stash, main.go, staged.txt, NOTES.md, and the outside worktree alpha-far. |
| 49 | Extra: `feat/pushed` advanced on GitHub by someone else, not fetched | pass | Not listed: it isn't contained in main but is contained in the same-named remote branch. The other items are unchanged. |
| 50 | Extra: the compare API fails with HTTP 502 | pass | `beta` gives `unchecked` "branch main could not be compared with the remote". It is neither silently dropped nor called unique. |

The runs stay read-only:

- Every in-clone git call has all four guard flags (0 without them across 74, 15 and 78 git calls).
- No fetch, pull, push, checkout, status, add, commit, reset, update-ref, update-index or stash verb appears.
- No hash-object call uses `-w`.
- gh calls are only `git/trees/<sha>?recursive=1` and `compare/<sha>...<sha>` with `--jq`, and no write flags appear.
- Index checksums, `.git` listings, refs and the stash list are identical before and after.

The updated `reconcile-check_test.sh` passes 155/155.

One minor observation, not a failure: in `re-main` the same compare (local
main e426553 against GitHub's main) ran 4 times, once for each tip that
reached the squash check. Repeated reads spend the 40-read `INV_COMPARE_CAP`
in a clone with many stale branches, and past the cap tips turn unchecked.
Caching that answer per clone would save the reads.
