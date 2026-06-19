# Decision 1: Cross-repo PR-state tracking

How does a capstone coordinating record learn and stay current with the merge
state of per-repo implementation PRs living in OTHER repositories — so the
PR-index and merge-order gate (PRD R6, R13, R14) reflect reality without the
author hand-updating them?

The toil being automated (from the #511 analysis): a capstone enumerates planned
or live per-repo PRs and a merge order, and today the author flips each row's
state (planned → open → merged) by hand and re-checks the order by reading other
repos' PR pages. Two sub-problems hide inside the question: (a) **discovery** —
reading the live state of N cross-repo PRs; (b) **enforcement** — blocking the
capstone from merging until every indexed PR is MERGED (R14).

## Options Considered

### Option 1 — On-demand polling step inside a skill

A `/work-on` (or `/scope`) step shells out to `gh pr view` / `gh pr list` across
the effort's repos when the skill runs, refreshing the index and recomputing the
order. No daemon, no subcommand — the logic lives in skill prose + inline `gh`
calls, the same shape `skills/work-on/koto-templates/work-on-plan.md` already
uses (`gh pr list --head ... --json number`, `gh pr view --json mergeStateStatus`).

**Pros**
- Maximally R19-aligned: nothing always-on; refresh happens only when a human
  runs a skill.
- Zero new binary surface; reuses the `gh`-in-skill idiom already proven in
  work-on templates.
- Auth is whatever the operator's `gh` already has (public + private), so the
  cross-repo private-access path "just works" for the author.

**Cons**
- The index-rewrite + merge-order recompute + `owner/repo:path` parsing become
  shell/markdown logic embedded in a skill template — hard to unit-test, easy to
  drift, and exactly the brittle-prose surface shirabe pushes into the Rust
  validator elsewhere. The repo *already* moved this class of logic (frontmatter
  parsing, chain walking, owner/repo parsing) into `crates/shirabe-validate`
  precisely to make it testable.
- No reusable enforcement: R14 gating would also have to be re-expressed in
  prose/`gh` per skill, duplicated between `/work-on` and any on-demand path.
- Refresh only happens when *this* skill runs; an author who edits the capstone
  by hand gets no refresh.

### Option 2 — Event/webhook-driven updates (GitHub Actions in each repo posts state to the capstone)

Each participating repo runs a workflow on PR merge that calls back to the
capstone repo (e.g. edits the capstone PR body or dispatches a `repository_dispatch`)
to flip the corresponding index row.

**Pros**
- The index trends toward real-time without anyone running a skill.
- Push model: state arrives as it changes.

**Cons**
- **Violates the spirit of R19** even if not a literal daemon: it is standing,
  always-armed infrastructure that must be installed and maintained in *every*
  participating repo, including repos that may not be ours to modify, and a fresh
  capstone (#511 pattern) forward-declares PRs that *don't exist yet* — there is
  nothing to attach a workflow to at seed time.
- Cross-repo write auth is a hard problem: a workflow in repo B needs a token
  that can write to the capstone repo A (cross-repo, sometimes public→private or
  private→public), which means provisioning and rotating PATs/app installs across
  the workspace — heavy for a single author.
- Public/private leak risk: a public repo's Action writing into a capstone, or
  vice-versa, crosses the visibility boundary the workspace guards (`public/CLAUDE.md`,
  the cross-repo visibility table). High blast radius for a coordination convenience.
- N-way fan-in is fragile: missed/failed callbacks silently desync the index with
  no reconciliation path.

### Option 3 — Author-triggered refresh command only (semi-manual)

A dedicated "refresh now" command the author runs, but with no integration into
`/work-on`. Essentially Option 4's discovery half, minus the automatic invocation.

**Pros**
- Simple; explicit; no surprise mutations.

**Cons**
- Still toil — it just renames "hand-edit the table" to "remember to run the
  refresh." The author must know to run it, and nothing runs it at the natural
  moment (when work-on touches the capstone).
- Provides discovery but punts enforcement (R14) entirely — the gate would have
  to live somewhere else anyway.
- Strictly dominated by Option 4, which is this command *plus* automatic
  invocation from `/work-on`.

### Option 4 — A `shirabe` CLI subcommand: read index, query each cross-repo PR via `gh`, rewrite index + recompute gate; invoked by `/work-on` and on demand

A subcommand (e.g. `shirabe capstone sync`) parses the capstone's PR-index,
resolves each `owner/repo:PR` reference, queries live state through the existing
`gh api` client, rewrites the index rows + recomputes the merge-order DAG state,
and reports whether the R14 gate is satisfied. `/work-on` calls it at the natural
points (before assembling the PR body, before `gh pr ready`); the author can also
run it on demand. **R14 enforcement is split:** the subcommand computes and
surfaces gate state for the human/skill, and the `lifecycle.yml` strict-mode CI
check on the capstone PR is the non-bypassable backstop — mirroring the cascade-
trigger decision exactly ("skill drives via existing primitives + CI gate as the
safety net").

**Pros**
- **Lands on existing rails.** `crates/shirabe-validate/src/gh.rs` already ships a
  production `GhSubprocessClient` over `gh api` with: `gh auth status` preflight,
  5s per-request timeout, 4 MiB output ceiling, owner/repo regex validation, and a
  `ClientError` taxonomy (`Auth`/`NotFound`/`Forbidden`/`RateLimit`/`Network`/
  `Malformed`) that *already names cross-repo private-access* (`Forbidden`). The
  PR-body fetch (`fetch_pr_body`) and a trait seam for offline tests
  (`MockIssueStateClient`) exist. Extending it from issue/PR-state-for-FC09 to
  multi-PR capstone sync is incremental, not greenfield.
- **`owner/repo:path` parsing already exists** (`finalize.rs::is_cross_repo_ref`,
  documented in `references/cross-repo-references.md`). The reference convention,
  the parser, and the visibility table are all in place to resolve index rows.
- **Pull model fits R19 and the fresh-capstone case.** No always-on service; the
  query runs when invoked. Forward-declared PRs (state=planned, no number yet) are
  simply rows the sync skips until a number is filled in — no infra to attach to a
  non-existent PR.
- **Testable + reusable.** Index rewrite, DAG recompute, and gate evaluation are
  Rust with unit tests (the contraction-cycle re-validation from the granularity
  sub-exploration belongs here too), shared by both `/work-on` and the on-demand
  path — no prose duplication.
- **Auth is the operator's `gh`**, so the subcommand never holds token bytes
  (the gh.rs design's deliberate property), and public+private access follows the
  author's own credentials with no cross-repo PAT provisioning.

**Cons**
- New CLI surface to design, version, and document (though small and adjacent to
  existing validate subcommands).
- Refresh is still only as fresh as the last invocation — between runs the index
  can lag reality (acceptable for a single-author coordination record; the CI gate
  is what's authoritative at merge time, not the index snapshot).
- Cross-repo private reads can fail (`Forbidden`) when the author's `gh` lacks
  scope; the subcommand must degrade gracefully (mark the row "unknown," not crash)
  — a handling requirement, not a blocker.

## Recommendation

**Option 4 — a `shirabe capstone sync` subcommand invoked by `/work-on` and on
demand, with R14 enforcement split between the subcommand (compute + surface) and
the `lifecycle.yml` strict-mode CI check on the capstone PR (non-bypassable
backstop).**

It is the only option that satisfies all four constraints at once and is the
cheapest to build because the load-bearing machinery already exists. Concretely:

1. **Cross-repo auth** — the existing `gh api` subprocess client uses the
   operator's own `gh` credentials, so public+private reads work without
   provisioning cross-repo tokens, and the validator never holds token bytes.
2. **R14 gate enforcement** — follows the precedent set by
   `DECISION-cascade-trigger-mechanism-2026-06-06`: the skill/subcommand drives
   the computation as the path of least resistance, and the strict-mode lifecycle
   check in `.github/workflows/lifecycle.yml` (already triggered on
   `ready_for_review`) is the safety net that catches anyone who flips the capstone
   to ready by hand. No new always-on service.
3. **`owner/repo:path` convention** — reuse `is_cross_repo_ref` and
   `references/cross-repo-references.md`; index references resolve through the same
   parser the chain-walk already trusts, with the visibility table forbidding a
   public capstone from indexing a private repo's PR.
4. **R19 (no new always-on service)** — a pull-model subcommand run on invocation
   is the lightest possible mechanism; it is strictly less infrastructure than
   Option 2's per-repo workflows and is consistent with how work-on already shells
   to `gh`.

Option 3 is folded in as the "on demand" invocation path; Option 1's `gh`-in-skill
idiom is retained for the *enumeration* of which PRs exist (`gh pr list`), but the
parse/rewrite/gate logic lives in the testable Rust subcommand rather than skill
prose. Option 2 is rejected on R19 spirit, cross-repo write-auth cost,
visibility-boundary risk, and the fresh-capstone-has-nothing-to-attach-to problem.

## Trade-offs / Consequences

- **Snapshot, not stream.** The index reflects state as of the last sync. For a
  single author this is fine; the authoritative R14 decision happens at merge time
  via CI, not from the possibly-stale index snapshot. Document the index as a
  cached view, not a source of truth.
- **New subcommand surface** must be designed alongside the existing validate
  subcommands and carry its own tests/evals (shirabe's eval discipline applies).
- **Graceful degradation is mandatory.** A `Forbidden`/`Network`/`RateLimit` on
  any row must mark that row "unknown" and refuse to assert the gate is satisfied,
  rather than silently treating an unreadable PR as not-blocking. The existing
  `ClientError` taxonomy already distinguishes these cases.
- **The gate is two-layer by design.** Computing R14 in the subcommand gives the
  ergonomic surface; the CI check gives the guarantee. Both must agree on the same
  "all indexed PRs MERGED" predicate, so that predicate should live in one Rust
  function consumed by both the subcommand and the lifecycle check.
- **Contraction-cycle re-validation** (the per-repo DAG can manufacture cycles, per
  the granularity sub-exploration) naturally belongs in this subcommand's DAG
  recompute, keeping graph logic in one tested place.

## Open sub-questions for the design

1. **PR-index machine-readable form.** The sync must round-trip the index. Does it
   parse the markdown table in the PR body / PLAN, or does the capstone carry a
   structured block (fenced YAML/JSON) the table renders from? A structured source
   of truth is far easier to rewrite deterministically than a hand-formatted table.
2. **Where does sync write?** The capstone state home is the capstone branch/PR
   (per the exploration). Does sync edit the PR body via `gh pr edit`, commit to a
   doc on the branch, or both? This intersects wip-hygiene and the "PR body vs PLAN
   doc" relocation seen in #511.
3. **R14 predicate ownership.** Confirm a single shared Rust predicate
   ("all indexed PRs MERGED, modulo non-PR gate nodes") consumed by both the
   subcommand and `lifecycle.yml`'s strict-mode check, so the ergonomic and
   authoritative answers never diverge.
4. **gh.rs scope extension.** `IssueStateClient` currently narrows PR state to
   Open/Closed for FC09. R14 needs MERGED distinguished from closed-unmerged
   (`mergeStateStatus` / `state=MERGED`). Decide whether to widen `IssueState` or
   add a PR-specific fetch.
5. **Fresh-capstone rows.** Formalize `planned` as a valid index state (no PR
   number yet) so sync skips it cleanly and the draft-PR "don't merge yet" signal
   (#511) covers the gap until numbers backfill.
6. **Degradation policy wording.** Exact behavior when a row is unreadable
   (`Forbidden` on a private repo the author's `gh` can't reach): "unknown" row +
   gate-not-satisfied, surfaced how to the author.

## Summary

The capstone should learn cross-repo PR state through a pull-model `shirabe`
subcommand that reuses the existing `gh api` client (`crates/shirabe-validate/
src/gh.rs`) and `owner/repo:path` parser (`finalize.rs::is_cross_repo_ref`) to
read each indexed PR on the operator's own credentials, rewrite the index, and
recompute the merge-order/R14 gate — invoked by `/work-on` and on demand. R14 is
enforced two ways, mirroring the accepted cascade-trigger decision: the subcommand
computes and surfaces the gate, and the strict-mode `lifecycle.yml` CI check on the
capstone PR is the non-bypassable backstop, so nothing always-on is introduced
(R19). Webhook/Actions push (Option 2) is rejected for its standing per-repo
infrastructure, cross-repo write-auth cost, visibility-boundary risk, and inability
to attach to forward-declared PRs that don't yet exist.
