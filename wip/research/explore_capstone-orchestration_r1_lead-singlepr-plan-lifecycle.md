# Lead: How is shirabe's single-pr PLAN lifecycle implemented today, and can it generalize to a multi-repo "capstone"?

## Findings

### 1. The unified Draft -> Active -> Done -> DELETED lifecycle (confirmed)

The hint is correct and grounded in the code/docs. PLAN docs use **one** lifecycle for both modes; only the **Draft -> Active gate** differs.

- `skills/plan/SKILL.md:58-63` states it verbatim: "PLAN docs use a unified Draft -> Active -> Done -> DELETED lifecycle, identical for single-pr and multi-pr. Only the Draft -> Active gate differs: multi-pr requires human approval (GitHub issues + milestone are created on the transition); single-pr auto-fires when /plan finishes authoring (no human gate, no GitHub side effects). A committed PLAN at `status: Draft` is a violation in either mode."
- The PLAN format reference (`skills/plan/references/plan-format.md:211-246`) documents the state table and transitions:
  - **Draft -> Active** (multi-pr only) — Phase 7 populate materialized GitHub issues + milestone. (`plan-format.md:227-229`)
  - **Draft -> Done** (single-pr only) — implementing agent shipped all issues in one PR; cascade fires. (`plan-format.md:230-231`)
  - **Active -> Done** (multi-pr only) — all materialized issues closed; cascade fires. (`plan-format.md:232-233`)
  - Note: `plan-format.md:218` still says "single-pr mode skips this [Active] state" — a slight wording mismatch with SKILL.md/run-cascade.sh, which now treat Active -> Done as an ephemeral in-process marker for BOTH modes. The cascade always flips Active -> Done immediately before `git rm` (see below). Doc-vs-code drift worth noting.

### 2. Where single-pr vs multi-pr is decided

Decision happens at **Phase 3.5/3.6 of `/plan`** (`skills/plan/SKILL.md:137-172`, `:358-378`), entirely separate from work-slicing (walking-skeleton vs horizontal):

- **Default: single-pr** (SKILL.md:144-148), anchored on principle P1 (usable value is the unit of work, `references/workflow-principles.md`).
- **Escape to multi-pr only on a named condition** (SKILL.md:150-159): (1) a hard constraint forces multiple PRs — explicitly including "Cross-repo landing order"; or (2) each PR is independently useful.
- A roadmap input is always multi-pr (SKILL.md:160-163).
- The frontmatter field `execution_mode: single-pr | multi-pr` (`plan-format.md:24-31`, `:40-44`) records the decision and determines whether GitHub issues are materialized at Phase 7.
- Phase 7 outputs (SKILL.md:373-378, :424-444): single-pr writes Issue **Outlines** with local anchors into the PLAN doc and leaves status Draft (no GitHub artifacts); multi-pr creates milestone + issues and sets status Active.

### 3. CI enforcement (two distinct checks)

**(a) Chain lifecycle check — the ephemeral-deletion enforcer.** `.github/workflows/lifecycle.yml` is a reusable workflow that builds the `shirabe` binary and runs:
```
shirabe validate --visibility=<repo> --lifecycle . $STRICT_FLAG   (lifecycle.yml:105-108)
```
The DRAFT-vs-READY discipline is the enforcement mechanism (lifecycle.yml:88-108):
```
STRICT_FLAG=""
if [ "${{ github.event.pull_request.draft }}" = "false" ]; then
  STRICT_FLAG="--strict"   # ready-for-review PR
fi
```
Quoted intent (lifecycle.yml:20-22): "DRAFT PRs run in non-strict mode and pass against mid-PR chain states; READY PRs run in strict mode and require single-pr chains to be at their terminal (PLAN deleted, BRIEF/PRD Done, DESIGN Current)." So an ephemeral single-pr PLAN that still exists on disk when the PR flips ready-for-review **fails strict mode** — that is the forcing function that deletes it before merge. There is no `docs/plans/done/` directory; "verify-then-delete is the single forcing function" (SKILL.md:65-73).

**(b) PLAN doc format check.** `.github/workflows/check-plan-docs.yml` runs `bash skills/plan/scripts/validate-plan.sh` on every changed `docs/plans/PLAN-*.md` (FC01-FC15: required fields, status enum, frontmatter-vs-body status, sections, issue-table shape, diagram reconciliation). This validates shape, not lifecycle posture.

**The deletion itself** is performed by the work-on cascade, not CI. `skills/work-on/scripts/run-cascade.sh` runs in the `plan_completion` state BEFORE `gh pr ready` (work-on/SKILL.md:151-166). It: (1) pre-probes `shirabe validate --lifecycle-chain <PLAN> --strict` expecting failure on the present PLAN; (2) calls `shirabe finalize-chain` to walk upstream and transition DESIGN->Current, PRD->Done, BRIEF->Done; (3) flips PLAN Active->Done then `git rm`s it in the same commit (run-cascade.sh:711-720, :839-845); (4) post-verifies the same strict check now passes. The Active->Done flip is "ephemeral by design: it exists only in the commit that also deletes the file" (run-cascade.sh:836-838).

### 4. Single-repo-bound assumptions (the crux for capstone generalization)

The lifecycle machinery is **structurally single-repo**. Concrete bindings:

- **Upstream chain resolution is local-filesystem only.** `crates/shirabe-validate/src/lifecycle.rs:395-435` (`extract_upstreams`): every `upstream:` value is resolved with `canon_root.join(bare)` and `fs::canonicalize` against the local tree. The whole-tree lifecycle scan walks files under one `<ROOT>` (`--lifecycle .`).
- **Cross-repo references explicitly STOP the chain walk.** `finalize.rs:344-345, 399-405`: a cross-repo `owner/repo:path` upstream is detected by `is_cross_repo_ref` and produces `NodeAction::Stop("cross-repo reference ... is out of scope; stopping chain walk")`. The cascade's `stop` handler does nothing (run-cascade.sh:785-788). So finalize-chain transitions only same-repo nodes; a cross-repo upstream is a dead end.
- **The cascade operates inside one git repo.** `run-cascade.sh:610` does `git rev-parse --show-toplevel`; `validate_upstream_path` (`:89-118`) hard-rejects any path that "resolves outside repository root" and any path not tracked by *this* repo's git. `git add/commit/push` (`:849-852`) act on one repo.
- **One shared branch + one PR per plan.** work-on plan-orchestrator mode derives `impl/<plan-slug>` and a single draft PR (work-on/SKILL.md:99-119); all children share `SHARED_BRANCH` and the one PR. There is no notion of multiple repos' branches.
- **GitHub artifacts assume the origin repo.** Issue creation (Phase 7), milestone, and `check_issue_closed` (`run-cascade.sh:126-167`) validate issue URLs against the single `origin` remote and reject mismatches.
- **PLAN frontmatter has no repo dimension.** Fields are `schema, status, execution_mode, milestone, issue_count, upstream` (`plan-format.md:19-55`). Issues are local anchors (single-pr) or `#N` in the origin repo (multi-pr). Nothing names a repo per issue, a branch per repo, or a merge order across repos.

### 5. Liftable vs blocking for a capstone

What **already generalizes** to the author's capstone framing:
- The conceptual lifecycle (created up front in Draft, consumed in-PR, deleted before merge as the completion signal) is *exactly* the single-pr PLAN lifecycle. The DRAFT-vs-READY strict gate already makes "PR can't merge until the plan is consumed" a CI invariant.
- Cross-repo `upstream:` syntax (`owner/repo:path`) already exists and is recognized (`references/cross-repo-references.md`), and `execution_mode` already names "cross-repo landing order" as the canonical multi-pr trigger (SKILL.md:152-153).
- `/plan`'s dependency graph (Mermaid `I<N> --> I<M>` edges, `plan-format.md:143-160`) already encodes the ordering data a merge-order computation would need — but only intra-plan, not per-repo.

What **must change** for a multi-repo capstone:
- **Chain walk + finalize-chain must cross repos** instead of stopping at `owner/repo:path`. Today `Stop` is a hard wall; a capstone needs the cascade to reach into sibling repos (or delegate per-repo cascades).
- **The PLAN schema needs a per-issue repo dimension** (which repo each issue lands in) plus a **merge-order field** across the per-repo PRs. The dependency graph would have to express cross-repo edges.
- **work-on plan-orchestrator must drive N branches/PRs (one per repo)** rather than one `impl/<slug>` branch + one PR, while the capstone PR holds the plan and merges last.
- **The strict lifecycle check must run against the capstone repo's tree** while tolerating that implementation PRs live in other repos — i.e. the "PLAN deleted before merge" invariant has to be scoped to the capstone PR, with the per-repo PRs as preconditions, not as the thing the validator deletes.
- **`check_issue_closed` / GitHub-artifact logic must accept multiple repos**, not just `origin`.

## Implications

- The capstone is genuinely "a single-pr PLAN generalized to multi-repo": the lifecycle states and the consume-before-merge CI invariant transfer 1:1. What does NOT transfer is every piece of *resolution and execution* machinery, all of which assumes one repo, one git root, one origin, one branch, one PR.
- The cleanest seam is the **cross-repo `Stop`** in `finalize.rs` and the **single-`origin`** assumptions in `run-cascade.sh`. A capstone design must decide whether the capstone repo's cascade reaches into siblings or delegates per-repo cascades (niwa mesh is the natural delegation primitive — out of this lead's scope, covered by Lead 3).
- The PLAN frontmatter/schema is the second seam: it needs a repo-per-issue field and an explicit cross-repo merge-order, neither of which exist in `plan/v1`.

## Surprises

- `plan-format.md:218` ("single-pr mode skips this [Active] state") contradicts the now-authoritative SKILL.md + run-cascade.sh model, where Active -> Done is an ephemeral in-process flip applied in BOTH modes immediately before `git rm` (run-cascade.sh:702-720). The format reference predates the unified-lifecycle reconciliation and is stale.
- Deletion is enforced **negatively** by a strict-mode validator failure on ready-for-review, not by an explicit "delete the plan" CI step. The forcing function is "the chain must be at terminal," and a present PLAN file makes that fail. This is elegant but means a capstone needs the equivalent negative invariant scoped correctly, or merges can slip.
- "Cross-repo landing order" is already named in the SKILL.md as the canonical reason to choose multi-pr — the multi-repo case is anticipated in prose but unimplemented in the tooling.

## Open Questions

- Should a capstone be a new `execution_mode` (e.g. `capstone`) or a flag on `single-pr`? The schema currently has only `single-pr | multi-pr`.
- How does the strict lifecycle check verify "all per-repo PRs merged" before allowing the capstone to flip ready? That state lives in other repos' GitHub, which the current validator never queries.
- Where does cross-repo merge order get computed — extend `/plan`'s dependency graph with repo-tagged nodes, or a separate capstone session-state artifact? (Overlaps Lead 5.)
- Does finalize-chain's per-node transition need to run once per repo (delegated) or once centrally with cross-repo writes? (Overlaps Lead 3 on niwa primitives.)

## Summary

shirabe's single-pr PLAN lifecycle (Draft -> Active -> Done -> DELETED, unified across modes with only the Draft->Active gate differing) is implemented as a local-filesystem, single-git-repo, single-origin, one-branch/one-PR pipeline: `/plan` picks `execution_mode`, the work-on cascade (`run-cascade.sh` + `shirabe finalize-chain`) flips the PLAN Active->Done and `git rm`s it before `gh pr ready`, and `.github/workflows/lifecycle.yml` enforces deletion negatively by failing the strict-mode chain check on ready-for-review PRs that still carry a live PLAN. The conceptual lifecycle and the consume-before-merge CI invariant lift cleanly to a multi-repo capstone, but every resolution/execution mechanism is single-repo-bound — most sharply, `finalize.rs` explicitly STOPS the chain walk at any cross-repo `owner/repo:path` upstream, and `run-cascade.sh` rejects paths outside one git root and validates issues only against a single `origin`. Generalizing requires a repo-per-issue + cross-repo-merge-order PLAN schema, a chain walk/cascade that crosses (or delegates across) repos, an N-branch/N-PR orchestrator, and a strict-check scoped to the capstone PR with per-repo PRs as merge preconditions.
