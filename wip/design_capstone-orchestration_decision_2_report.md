# Decision 2: Cross-repo finalize / consume cascade

## Decision Question

How does the consume-before-merge completion cascade generalize ACROSS
repositories — finalizing upstream artifacts to terminal states and consuming
the spent PLAN before the capstone record merges (PRD R8, R21) — given that the
cascade is single-repo today and deliberately STOPS at cross-repo boundaries?

## Grounding (confirmed in code)

- **`finalize.rs:399-415`** — when the chain walk reaches a cross-repo
  `owner/repo:path` upstream, it pushes `NodeAction::Stop("... out of scope;
  stopping chain walk")` and breaks. It never fetches or reads the other repo.
  `is_cross_repo_ref` (`finalize.rs:589-598`) detects the `owner/repo:` prefix
  (a `:` before the first `/`-rooted segment).
- **`run-cascade.sh:610`** — `REPO_ROOT=$(git rev-parse --show-toplevel)`. One
  git root for the whole run.
- **`validate_upstream_path` (`run-cascade.sh:89-118`)** — rejects any path that
  resolves outside `$REPO_ROOT` (`:100-101`) or isn't tracked by this repo's git
  (`:113`).
- **`check_issue_closed` (`run-cascade.sh:126-167`)** — parses an issue URL and
  rejects any `owner/repo` that doesn't match the single `origin` remote
  (`:154-155`).
- **`lifecycle.yml:97-108`** — the strict gate runs `shirabe validate --lifecycle .`
  against ONE tree on ready-for-review; deletion is enforced negatively (a live
  PLAN on disk makes strict fail). The PLAN physically lives in the capstone repo.
- **`run-cascade.sh:833-852`** — `git rm` the PLAN, then `git commit` + `git push`
  on one repo, immediately before `gh pr ready` (the done-signal).

The cascade has exactly two single-repo seams: (1) the `Stop` wall in the Rust
chain walk, and (2) the `$REPO_ROOT` / single-`origin` assumptions in the bash
wrapper. The conceptual lifecycle and the negative consume-before-merge invariant
already transfer 1:1; only resolution/execution is repo-bound.

## Options Considered

### Option 1 — Capstone-local cascade + cross-repo upstreams verified terminal (read-only)
The capstone's finalize walks only its own repo's chain (PLAN → DESIGN/PRD/BRIEF
that live in the capstone repo). Cross-repo `owner/repo:path` upstreams are not
finalized by the capstone; instead the cascade verifies (via `gh`/read) that each
is already at terminal status — finalized by that repo's own per-repo work — and
refuses to proceed if any is not. The `Stop` wall stays; it gains a read-only
"verify terminal" probe before stopping.

- **Write access:** capstone repo only. No cross-repo writes.
- **R8 (consume PLAN before merge):** PLAN lives in the capstone repo; consumed
  locally exactly as today. Direct fit.
- **R21 (failure halts, no partial state):** a cross-repo upstream that isn't
  terminal becomes a hard refusal — the capstone never flips ready, nothing
  half-finalizes. Strong fit; the verify probe is read-only so it cannot leave a
  partial write.
- **Cost in the Rust binary:** small. Replace the unconditional `Stop` with a
  `gh`-backed (or injected-status) terminal-status check, then stop. No fetch/clone
  of sibling trees, no cross-repo transition logic, no new write paths.

### Option 2 — Full cross-repo chain walk (finalize resolves and writes across boundaries)
Lift `finalize.rs` to resolve `owner/repo:path` upstreams by fetching/reading the
other repos and applying terminal transitions across boundaries (one central
cascade writes DESIGN→Current, PRD→Done, etc. in sibling repos).

- **Write access:** the capstone runner needs write + push to every upstream repo.
- **R8/R21:** a single central walk can finalize everything, but a partial failure
  midway (repo B finalized, repo C push rejected) leaves cross-repo partial state —
  precisely what R21 forbids — and there is no cross-repo transaction to roll back.
- **Cost:** large and invasive. The chain walk must clone/fetch sibling trees,
  resolve `owner/repo:path` to a working tree, run `run_transition` against foreign
  trees, and commit/push N repos atomically (impossible with plain git/PRs, per the
  round-2 "cross-repo atomicity is impossible" finding). High blast radius in the
  one binary the whole org's lifecycle CI depends on.

### Option 3 — Per-repo finalize runs in each repo's own PR; capstone finalize is capstone-repo artifacts + an all-terminal verification gate
Each implementation repo's PR runs its own (existing, single-repo) cascade and
finalizes the artifacts that live in that repo. The capstone repo's finalize
consumes only the capstone-repo artifacts (the PLAN and any capstone-local
chain), plus a verification gate asserting every cross-repo artifact reached
terminal status before the capstone PR may flip ready and merge last.

- **Write access:** each repo writes only its own artifacts. Capstone writes only
  the capstone repo. No cross-repo writes anywhere.
- **R8:** the PLAN lives in the capstone repo and is consumed by the capstone's own
  local cascade before its merge — unchanged from today, direct fit.
- **R21:** failure is naturally partitioned. A repo's own finalize halts that
  repo's PR (existing single-repo invariant). The capstone's verification gate
  halts the capstone if any cross-repo artifact is non-terminal. No central
  multi-repo write means no cross-repo partial-write state is even representable.
- **Cost in the Rust binary:** moderate-but-additive. No change to the existing
  per-repo cascade (it already does the right thing in each repo). The new work is
  a verification subcommand/mode (a `gh`-backed "is every cross-repo upstream
  terminal and is every per-repo PR merged?" gate) wired into the capstone's strict
  lifecycle check. The `Stop` wall stays a wall for the *write* walk; verification
  is a separate read-only pass.

## Recommendation

**Option 3** — per-repo finalize in each repo's PR, with the capstone's finalize
limited to capstone-repo artifacts plus an all-terminal verification gate — with
**Option 1's read-only verify probe as its implementation primitive**. The two
converge: both keep writes repo-local and both turn the cross-repo boundary into a
read-only terminal-status check rather than a write boundary. Option 3 is the
fuller framing because it explicitly assigns each repo's finalize to that repo's
own PR (which already works today) and reserves the capstone for verification +
merge-last; Option 1 is essentially Option 3 viewed from the capstone repo alone.

Reject Option 2: it is the only option that requires the capstone runner to hold
write access to sibling repos, it is the only one that can produce cross-repo
partial-write state (a direct R21 violation with no rollback), and it is by far the
largest, highest-blast-radius change to the shared binary — to buy a property
(central atomic cross-repo finalize) that plain PRs cannot deliver anyway.

## Trade-offs / Consequences

- **Write surface stays minimal and safe.** Under the recommendation, no process
  ever writes to a repo it isn't the PR for. This preserves the current security/
  permission posture of the binary and the cascade script: a capstone run needs
  only read (`gh`) access to siblings, never push.
- **R21 holds by construction, not by discipline.** Partial-finalize across repos
  is unrepresentable because there is no central cross-repo write. The only failure
  is a *refusal* (verification gate fails → capstone doesn't flip ready → doesn't
  merge), which is exactly the "no partial state, record doesn't merge if finalize
  incomplete" contract.
- **The `Stop` wall is reinterpreted, not removed.** It stays a wall for the
  *write* walk (finalize never transitions a foreign node). A new read-only verify
  pass is added alongside it. This is the smallest defensible change to
  `finalize.rs` and keeps the existing single-repo tests intact.
- **New dependency on `gh` for cross-repo state.** The capstone repo learns sibling
  PR/artifact state by querying GitHub, not the filesystem. This matches the
  exploration's "cross-repo PR-state tracking is the genuinely unsolved part" and is
  where the design risk concentrates. `check_issue_closed`'s single-`origin`
  assumption must be relaxed to accept an explicit per-repo `owner/repo` (a small,
  contained change).
- **Merge-last ordering becomes the capstone's job.** Because each repo finalizes
  itself, the capstone's remaining responsibility is sequencing (per-repo PRs merge
  first, capstone merges last) and the verification gate. This aligns with the
  separately-decided merge-order DAG and keeps finalize out of sequencing.
- **Cost is paid where the exploration said to pay it** — CLI enforcement of a
  cross-repo *read* gate — without paying for cross-repo *writes*, which is the
  expensive and unsafe part.

## Open sub-questions for the design

1. **Where does the verification gate live** — a new `shirabe validate
   --capstone`/`--cross-repo-terminal` mode invoked by `lifecycle.yml` on the
   capstone PR, or a step in `run-cascade.sh` before `gh pr ready`? (Leaning:
   both — a read-only probe in the cascade for the local refusal, plus the strict
   CI check as the merge-blocking backstop, mirroring the existing pre/post-verify
   pattern.)
2. **How does the capstone enumerate its cross-repo upstreams and their target
   status?** Walk the capstone PLAN's chain collecting every `owner/repo:path`
   `Stop` node, then map each to its terminal status by artifact type (DESIGN→Current,
   PRD/BRIEF→Done)? This needs the chain walk to *report* cross-repo nodes (it
   already does, as `Stop` entries) and a `gh`-read of each foreign file's
   frontmatter status.
3. **Does "terminal" mean the foreign artifact's status frontmatter is terminal, or
   that the foreign PR carrying that finalization is MERGED?** These can disagree
   transiently. R21 ("record doesn't merge if finalize incomplete") argues for
   gating on *merged*, which subsumes status.
4. **Relaxing `check_issue_closed` / `validate_upstream_path`** to accept explicit
   per-repo `owner/repo` selectors without re-opening path-traversal safety. The
   `$REPO_ROOT` containment check must stay for the *local* tree; cross-repo
   verification must route through `gh`, never through a foreign filesystem path.
5. **What if a sibling repo never finalizes its own artifact** (e.g. its work
   shipped without the lifecycle chain)? The gate must distinguish "no chain
   expected here" from "chain expected and not terminal" to avoid false refusals —
   ties into the L02 orphan-doc / in-flight-chain wrinkle already noted in the
   dogfooding finding.
6. **`gh` availability and auth in CI** for the capstone repo to read sibling repos
   (public repos: read is unauthenticated-friendly; still needs a token in
   Actions). Failure-to-read must be a halt (R21), not a silent pass.

## Summary

The cross-repo cascade should keep every finalize *write* repo-local — each repo
finalizes its own artifacts in its own PR, the capstone consumes only its own PLAN
(R8, unchanged) — and replace the cross-repo boundary with a read-only "all
upstreams terminal / all per-repo PRs merged" verification gate that blocks the
capstone from merging last (R21). Reject the full cross-repo write walk: it is the
only option needing push access to sibling repos and the only one that can leave
cross-repo partial state, violating R21, while being the largest change to the
shared binary for an atomicity plain PRs can't provide. The change to the Rust
binary stays small and safe — the `Stop` wall persists for writes; a new
`gh`-backed read pass is added alongside it — concentrating design risk exactly
where the exploration flagged it: cross-repo PR-state tracking.
