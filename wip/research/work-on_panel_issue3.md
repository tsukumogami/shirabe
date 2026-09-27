# Panel review: Issue 3 (host re-checks for reconcile), commit bb143e8

Subject: `host`, `teardown`, `leg`, `inventory` in
`skills/coordinate/scripts/reconcile-check.sh`, helpers `rd_slug`, `rd_git`,
`rd_github_repo` in `reconcile-deps.sh`, tests in `reconcile-check_test.sh`.

Test runs: `reconcile-check_test.sh` passed=112 failed=0;
`reconcile-report_test.sh` passed=66 failed=0 (git 2.43, bash 5, Linux).

Probes were run against the real script with a PATH wrapper that forwards
every git call to real git except `ls-remote` (served) and a `gh` stub that
returns blob shas by path or HTTP 404. Probe scripts: `/tmp/rcx/probe.sh`,
`/tmp/rcx/probe2.sh` (not committed). Results quoted below are actual output.

`rd_slug` matches niwa's `sanitizeInstanceSlug` (niwa
`internal/cli/dispatch.go:1108`): lowercase, runs outside `[a-z0-9]` to one
`_`, trim, cut to 40, re-trim right. The topic regex keeps input ASCII, so
`tr`/`sed`/`cut` byte semantics equal niwa's rune semantics. `niwa list
--json` does emit `{name, path, session_name?}` as assumed.

---

## Blocking findings (real defects with a failing input)

### B1. Uncommitted work in a worktree inside the instance is never read (false "nothing unique")

`find -P "$IROOT" -maxdepth 4 -name .git` is the only way a clone or worktree
is discovered. The design (Decision 4, "Worktrees") says a worktree inside the
instance "is walked like a clone"; the code never walks worktrees that
`git worktree list` reports inside the instance -- it only lists the outside
ones -- and relies on `find` to have reached them. The workspace's own
convention puts worktrees at `<instance>/<group>/<repo>/.claude/worktrees/<name>/.git`,
which is depth 6.

Failing input (probe P3): instance with `public/repo` and a linked worktree at
`public/repo/.claude/worktrees/feat` holding an untracked `new.txt`.
Output: `items: []`. The report renders that as "nothing unique found".
Commits in that worktree are safe only because its branch ref lives in the
main clone; uncommitted and untracked files are lost silently.

Same root cause, probe P6: a nested repository at `repo/a/b/c/nested` (depth
6) with an untracked file -> `items: []`. The parent's `git status` reports
the nested repo as an untracked directory (`?? a/`), and the file loop's
`[ -f "$full" ] || continue` drops directories without an item.

Fix: after `git worktree list --porcelain`, walk every worktree whose real
path is inside the instance (dedupe by real path) instead of depending on
`find` depth; and emit an item (or at least an `unchecked` item) for any
status entry that is a directory rather than skipping it.

### B2. Commits not on `refs/heads` are never inventoried (detached HEAD, stash)

The commit walk is `for-each-ref refs/heads`. A commit made on a detached
HEAD (common mid-rebase, after `checkout <sha>`, or in a worktree made with
`--detach`) and anything in `refs/stash` are invisible.

Failing inputs: P1 -- clean clone, `checkout --detach`, commit a new file ->
`items: []`. P2 -- modify a tracked file, `git stash push` -> `items: []`.
Both are unpushed work reported as "nothing unique found".

Fix: include `HEAD` of every worktree (`worktree list --porcelain` gives
`HEAD <sha>` and `detached`) and `refs/stash` (and arguably all local refs
other than `refs/remotes/`) in the tip set.

### B3. `git status` runs the clone's configured clean filter

`rd_git` claims (and the design's Security Considerations requires) that no
in-clone call "runs anything the clone's config names". `git status` re-hashes
a tracked file whose stat data differs from the index, and it does that
through the clean filter named by `.gitattributes` + `filter.<name>.clean`.
`--no-optional-locks`, `core.fsmonitor=` and `core.hooksPath` don't touch
this.

Failing input (P4): commit `.gitattributes` with `* filter=evil`, set
`filter.evil.clean = sh -c 'touch /tmp/rcx/pwned; cat'` in the clone's
config, `touch -d 2001-01-01 x.txt`, run inventory. `/tmp/rcx/pwned` exists
afterwards. A filter like `sleep 100000` also hangs the inventory forever
(see B4). `filter.lfs.process` in any LFS clone runs the same way.

Fix options: don't use `status` for tracked files; enumerate with
`ls-files -z --stage` / `ls-files -z --others --exclude-standard` (index and
directory reads only) and compare each tracked file's `hash-object
--no-filters` against its index blob and the default branch's blob; or, on
git >= 2.40, pass `--attr-source=<empty tree>` with
`-c core.attributesFile=/dev/null` and `GIT_ATTR_NOSYSTEM=1` so no filter
attribute applies (not available in Apple's git 2.39, so the ls-files route
is the portable one). Add a test with a clean filter that writes a marker.

### B4. Truncation is lost when the items list is empty (false "nothing unique")

Caps set `truncated: true` but add no item. `reconcile-report.sh`
(`nowhere_else`) prints "nothing unique found" whenever `items` is empty
and appends "(truncated)" only in the non-empty branch.

Failing input (P5): 21 clean clones, `u.txt` untracked in the 21st.
Inventory: `{"items":[],"truncated":true}`; report:
`"inventory":"nothing unique found"`. Same for a clone with more than 200
status entries whose first 200 match the default branch. The design says
"anything past a cap is counted, not listed, and the report says the
inventory was truncated"; the count isn't recorded either.

Fix: record the skipped count (e.g. `skipped_clones`, `skipped_files`) and
make the report's empty-items branch honor `truncated` ("nothing unique found
in the part read (truncated)"), or have the check emit a `truncated` item.
Add tests for both caps; the AC ("caps of 20 clones and 200 files produce a
truncation note") has no test today.

### B5. In-clone git calls have no deadline (AC unmet)

AC: "a timed-out in-clone git call ... yield[s] a not-verified fact". Only
`ls-remote` and the contents reads are under `rd_deadline`. `status`,
`for-each-ref`, the per-sha `cat-file`/`merge-base` loop, `diff`,
`rev-parse`, `hash-object` and `worktree list` run unbounded. Failing input:
B3's filter set to `sleep 100000`, or a slow/stale network mount -- the
inventory never prints a fact, and the pass stalls on that holding. No test
covers it.

Fix: wrap each in-clone call (or the whole per-clone walk) in `rd_deadline`
and turn a 124 into an `unchecked` item or a not_verified fact.

---

## Advisory findings

Inventory correctness

- A1. Fail-open on a failed `diff`: `[ "$NF" -eq 0 ] && landed=true` runs
  after the loop, so if `diff --name-only BASE tip` fails (missing trees in a
  partial clone where the lazy fetch is blocked by `protocol.allow=never`,
  a corrupt object) the branch counts as landed. I couldn't construct a
  natural treeless-clone case (checkout fetches the trees), so advisory, but
  the default should be "not landed" unless the diff exited 0.
- A2. `SHAS=... | sort -u | head -n 500` sorts by hash, then cuts. In a
  repository with thousands of `refs/pull/*` (tsuku), the branch's own
  `refs/heads/<b>` sha can be cut, so a pushed, open-PR branch is reported
  as unique "unpushed work". Conservative, but noisy. Take `refs/heads/*`
  first, then fill with the rest.
- A3. Cost: each unpushed branch runs up to 500 x (`cat-file` +
  `merge-base`) processes with no overall bound. One
  `git rev-list -n1 <tip> --not <present shas...>` answers the same
  question in one call (filter to present objects with
  `cat-file --batch-check` first).
- A4. A staged change that differs from the working file (`MM`) is judged by
  the working file only; the staged version is not considered. Ignored files
  are never listed (matches the design's `status --porcelain`, but worth a
  sentence in the design since `.env`-style scratch work would be lost).
- A5. A linked worktree whose main repository is inside the instance and
  within depth 4 is enumerated twice (main and worktree share refs), giving
  duplicate `commit` items.
- A6. `ls-remote` targets the clone's `remote.origin.url`, not the record
  row's repository as Security Considerations says ("never a clone's
  configured remote"), and only `origin`, while Decision 4 says "one
  `git ls-remote` per remote". For multi-clone instances origin is the only
  thing that can work, but the deviation isn't recorded; a clone whose
  origin names some other github.com repo decides "pushed" and "landed"
  against that repo.

Containment

- A7. A linked worktree inside the instance whose common git dir is outside
  (P7) is listed as an outside worktree, but `for-each-ref`, `status`,
  `config` etc. still read that outside git dir (and, per B3, its config's
  filters). Containment is by working-tree path only.
- A8. `--path` accepts any absolute non-symlink directory (e.g. `/` or
  `$HOME`); nothing ties it to the workspace root. The pass feeds it from
  the listing, so this is defense in depth.
- A9. The outside worktree item carries only `basename` of its path, which
  loses where it is; the design says "listing it by path".

Host, teardown, leg

- A10. `teardown` refuses when the listing is empty or when listed instances
  don't share one parent (it derives the workspace root from `path`s), so a
  teardown can't be confirmed when nothing else is listed. Safe direction.
  `niwa list` also needs a cwd inside the workspace; document that.
- A11. `teardown` repeats `host`'s jq match filter; drift risk. Extract one
  jq def or shell helper.
- A12. Topics longer than 40 slug characters that share a prefix collide
  (niwa's rule, not this code's), so `found` can name the wrong worker when
  the true one is gone. Worth a line in the design.

Tests

- A13. "the clone is unchanged" runs `git status --porcelain -- .git`, which
  is always empty (git never reports `.git`), so it can't fail. Hash
  `.git/index` and list `.git/refs`, `.git/objects` before and after.
- A14. The "never writes" grep is `^git (fetch|...)`, but every inventory
  call starts `git --no-optional-locks ...`, so it can't match them; the
  allowlist check is what actually guards this. The lock-free check greps
  only `--no-optional-locks`, not all four flags (the allowlist covers it).
- A15. Not tested: the `is-ancestor` path (tip behind a remote sha), a
  symlink to a clone outside the instance, both caps, an in-clone timeout,
  a clean filter, detached HEAD, stash, deep worktree.
- A16. `host-absent` uses `PATH=$T/nobin:/usr/bin:/bin`; if `niwa` is
  installed in `/usr/bin` the case silently tests something else.

Schema / maintainability

- A17. The facts schema in `reconcile-report.sh`'s header lists inventory
  kinds `commit|change|file` and leg dispositions `open|resolved|abandoned`;
  the check now emits `unchecked`, `worktree` and `bound`. The report renders
  them, but an `unchecked`-only inventory is reported with why
  "unpushed work", which is wrong for "remote refs could not be read".
  Update the header and give `unchecked` its own wording.
- A18. The inventory branch overwrites the global `REPO` and `BASE` flag
  variables and `blob_at` reads `REPO` implicitly; `NF` is reused across two
  loops; `$ITEMS.blob` isn't in the EXIT trap. A ~110-line case arm would
  read better as `inventory_clone()` with locals.
- A19. Security Considerations' verb list (`status`, `log`, `worktree list`,
  `merge-base --is-ancestor`, `hash-object`) no longer matches the calls
  made (`config --get`, `cat-file -e`, `rev-parse`, `diff --name-only`,
  `for-each-ref`, `merge-base`); update it with the test allowlist.

Portability (bash 3.2 / BSD): nothing found. `find -P ... -maxdepth`,
`sed -E` with `;`-separated commands, one-true-awk `sub()`/`length()`,
`cut -c`, `mktemp` templates, `read -d ''`, `$'\t'`, `${var:0:2}` and
process substitution all work on macOS bash 3.2 and BSD userland. jq's
`IN` needs jq >= 1.6.
