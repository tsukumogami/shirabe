# Decision 3: Coordinating-record + merge-order representation

Where is the capstone's PR-index and merge-order CANONICALLY held; how is
merge order modeled so it supports non-PR gate nodes (PRD R12) and stays
acyclic (R13); and where does the post-grouping acyclicity check + cycle
resolution live?

## Options Considered

### Option 1 — Canonical-in-PLAN

The PR-index and the merge-order DAG live inside the PLAN doc (the #511
pattern): a `### Per-Repo PR Breakdown` (one `### PR-N — <title> (<repo>,
public|private)` per PR with **Depends on:** / verification gates), an
`## Implementation Sequence` carrying ASCII + Mermaid, a by-repo gates
table, and explicit `### PUBLISH GATE` nodes. The capstone PR body mirrors
only a prose summary. The post-grouping acyclicity check runs in `/plan`
when it collapses the issue-level `waits_on` DAG into the per-repo-PR DAG.

- **Fits the existing machinery.** The merge order is a quotient of the
  issue-level `waits_on` DAG that already lives in the PLAN
  (`plan-format.md` Dependency Graph + Implementation Issues table) and is
  already serialized by `plan-to-tasks.sh`. The collapse is a direct
  generalization of the `**Files**:`-collision derived-edge logic that
  `plan-to-tasks.sh` already ships.
- **Validatable.** PLAN already has a Rust validator surface
  (`crates/shirabe-validate`, FC05/FC06/FC07/FC08, `validate-plan.sh`,
  `schema: plan/v1`). A two-node DAG and a post-contraction acyclicity
  check extend that surface rather than inventing a new validation target.
- **The fatal flaw — durability under R8.** The single-pr PLAN is
  DELETED before merge. The work-on cascade flips PLAN Active→Done and
  `git rm`s it in the `plan_completion` state *before* `gh pr ready`
  (`run-cascade.sh:711-720,839-845`), and `lifecycle.yml` enforces this
  negatively: a ready-for-review PR that still carries a live PLAN fails
  the strict chain check. So if the PLAN is the *sole* canonical home, the
  PR-index and merge-order vanish from the tree at exactly the moment the
  capstone becomes mergeable — the audit trail for "which PRs, in what
  order, did this capstone coordinate" is destroyed precisely when a
  reader (or a re-entering agent after context reset) most needs it. This
  is the same dangling-pointer hazard the wip-hygiene rule guards against,
  here applied to the capstone's own coordinating record.

### Option 2 — Canonical-in-PR-body

The index + a fenced merge-order block live in the capstone PR
description; the PLAN stays issue-level (no per-repo-PR breakdown).

- **Survives R8.** The PR body is not `git rm`d by the cascade; it
  persists on the capstone PR through merge and is re-discoverable after a
  context reset (it is the agreed capstone-state home —
  `explore_capstone-orchestration_decisions.md`: "Capstone state home =
  the capstone branch/PR itself"). The merge-order data does not vanish
  when the PLAN is consumed.
- **Forward-declaration works.** #511 shows a fresh capstone forward-
  declares planned PRs by repo+role with a reserved terminal slot and
  backfills real PR numbers as they open — the PR body is the natural home
  for that mutable index.
- **Weak on validatability and on the acyclicity check's home.** A PR body
  is unstructured GitHub markdown; the Rust validator does not parse PR
  descriptions today (FC09 reads PR bodies only for `Closes #N` lines).
  Putting the canonical DAG only in the PR body strands the
  post-contraction acyclicity check (R13) with no authoring-time,
  in-tree artifact to run against — the check would have to run at
  execution time in `/work-on`, i.e. fail-late, after the author has
  already committed to a grouping. It also duplicates ordering data the
  issue DAG already encodes, with no in-tree source to reconcile against.

### Option 3 — Both, one source of truth: PLAN canonical, PR body rendered from it

PLAN holds the canonical per-repo-PR breakdown + two-node DAG; the PR body
is auto-rendered from it; acyclicity check runs in `/plan` at collapse.

- Inherits Option 1's machinery-fit and validatability **and** Option 2's
  PR-body summary — but inherits Option 1's R8 flaw at the root: the
  canonical copy is in the doc that gets deleted before merge. "Rendered
  from PLAN" is only true while the PLAN exists; after the cascade `git
  rm`s it, the rendered PR body is an orphan with no source to re-render
  from. The single-source-of-truth claim is *temporally* false across the
  exact lifecycle boundary that matters.

## Recommendation

**A split model that assigns canonical status by lifecycle phase, not a
single fixed home — closest to Option 2 but borrowing Option 1's rich
representation and authoring-time check. Concretely:**

1. **Authoring-time canonical = the PLAN's collapsed DAG.** `/plan` tags
   each issue with `repo` + `pr_group` (Phase 3 decomposition, alongside
   `**Type**`/`**Dependencies**`/`**Files**`), then collapses the
   issue-level `waits_on` DAG into a `(repo, pr_group)`-level two-node DAG
   (PR nodes + non-PR gate nodes). This is where the merge order is
   *derived and validated*. The PLAN renders it as the #511-style
   per-repo-PR breakdown + Mermaid + by-repo gate table.

2. **Merge-time canonical = the capstone PR body's PR-index + fenced
   merge-order block.** Because R8 deletes the PLAN before merge, the PR
   body is the durable record that survives. `/plan` (or the capstone
   seeding step) writes the index + fenced two-node merge-order block into
   the PR body *from* the PLAN's collapsed DAG at capstone-creation time.
   The PR body carries the live mutable state (planned → open #N → merged)
   through merge; the PLAN carries the immutable derivation while it
   exists. They agree at creation; only the PR body must outlive the PLAN.

3. **The post-grouping acyclicity check + cycle resolution lives in
   `/plan`, at the collapse step (fail-at-authoring).** This is the
   wip-hygiene-friendly and correctness-friendly answer: the issue DAG is
   acyclic (Phase 5.5), but a quotient of an acyclic graph is NOT
   guaranteed acyclic, so the collapse must re-run a cycle check on the
   contracted graph. A detected cycle is a mis-grouping signal; resolution
   follows the established preference order **split-at-seam → re-sequence
   → stack** (`granularity_lead-rule-tradeoffs.md` Finding 3). Failing here
   means the author never commits an unschedulable capstone; a `/work-on`
   execution-time check would fail-late after grouping is locked.

### Data model

Merge order is a **DAG with two node types**, not a list and not a PR-only
graph:

- **PR nodes** — keyed `(repo, pr_group)`; each maps to one per-repo PR.
- **Non-PR gate nodes** — publish/release/schema gates that serialize
  between PR nodes (#511's publish gate is the existence proof). A gate is
  also a natural human-in-the-loop pause/resume seam.

Edges: `G1 → G2` exists iff any issue in G1 `waits_on` any issue in G2,
plus author-declared gate edges (`PR → gate → PR`). R13 (acyclic) is the
hard correctness constraint on this contracted graph; R12 (non-PR gates)
is satisfied by the second node type.

### Expression in existing conventions

The two-node DAG fits `dependency-diagram.md` + `issues-table.md` with
modest, precedented extensions:

- **Mermaid:** reuse `graph TD`; PR nodes keyed by group; gate nodes get a
  distinct overlay class (precedent: `external` mnemonic nodes, the
  `bundleReleaseChain` overlay class). Subgraphs already group by repo
  (`subgraph KT ["koto (KT)"]` precedent) — one subgraph per repo gives
  the by-repo view for free.
- **Table:** the plan profile already allows one profile-specific column;
  a capstone-flavored breakdown adds a `Repo`/`PR-group` dimension. Gate
  rows are non-`I<n>` rows, mirroring how the roadmap profile tolerates
  `Issues = None` rows that contribute zero diagram nodes — so FC07
  bijection can be taught to exclude gate nodes the same way it already
  excludes external mnemonic nodes.

## Trade-offs / Consequences

- **Drift risk between PLAN and PR body.** Two homes that must agree at
  creation is a reconciliation surface. Mitigation: render the PR body
  *from* the PLAN's collapsed DAG (don't hand-author both), and have the
  capstone validator check agreement *while the PLAN still exists*; after
  the PLAN is deleted, only the PR body remains and there is nothing left
  to drift against. The drift window is bounded to the PLAN's lifetime.
- **The acyclicity check needs the collapse logic to run inside `/plan`.**
  This is new code (a `plan-to-tasks.sh` sibling, e.g. a group-collapse +
  cycle-check pass), but it reuses the existing derived-edge precedent and
  keeps the failure at authoring time. Cost is real but localized.
- **Cycle resolution can force splitting *related* work.** split-at-seam
  produces a repo with >1 PR for purely topological reasons (another
  repo's gate sits between two of its issues). This is correct but
  counter-intuitive; the skill must explain *why* it split (topology, not
  relatedness) so the author doesn't "fix" it back into a cycle.
- **Validatability is asymmetric across the lifecycle.** While the PLAN
  exists, the full DAG is Rust-validatable (extend FC05/FC07). After the
  PLAN is deleted, the PR body is the only record and is checked by a
  lighter, PR-body-aware pass (the capstone validator / `shirabe validate`
  reaching the PR body, analogous to FC09's existing PR-body read). We
  accept a weaker post-merge check in exchange for surviving R8 — the
  alternative (keep the PLAN canonical) gives a stronger check that
  validates a record that no longer exists at merge.
- **`/work-on` cross-repo execution is out of this decision's scope** but
  is the consumer: it reads the PR body's merge-order DAG to schedule
  per-group branch/PR fan-out and to gate on non-PR nodes. The fenced,
  machine-readable block in the PR body is what makes that consumable.

## Open sub-questions for the design

1. **Exact fenced-block grammar in the PR body.** What serialization
   (fenced YAML? a fenced DAG mini-language?) is both human-readable and
   parseable by the capstone validator and by `/work-on`? It must encode
   PR nodes, gate nodes, edges, and per-node state (planned/open-#N/merged).
2. **Does the capstone validator parse the PR body, and how does it get
   it?** FC09 already reads PR bodies via `gh` with documented
   self-disable paths (no creds, no PR context, rate limit). Reuse that
   harness, or add a separate capstone-body check?
3. **Auto-split vs refuse on a detected contraction cycle.** Should
   `/plan` auto-split-at-seam, or refuse and hand the cycle back to the
   author for re-sequencing? Correctness demands *something*; ergonomics
   favors auto-split, plan-integrity favors feedback. (Open per
   `granularity_lead-rule-tradeoffs.md`.)
4. **Is `pr_group` author-assigned or inferred?** Explicit assignment adds
   Phase 3 authoring burden; inference (by shared files / `waits_on`
   density) risks surprising groupings.
5. **Does "grouped" become a third `execution_mode`**, or do single-pr (1
   group) and multi-pr (N singleton groups) become degenerate cases of one
   general collapse path in `plan-to-tasks.sh`? The latter is cleaner but
   touches the stable `plan-to-tasks-contract.md`.
6. **How does the strict lifecycle check scope to the capstone PR?** The
   "PLAN deleted before merge" invariant must hold on the capstone PR
   while treating per-repo PRs as *preconditions*, not as the thing being
   validated/deleted (the cross-repo `Stop` wall in `finalize.rs` and the
   single-`origin` assumptions in `run-cascade.sh` are the seams).

## Summary

The capstone's merge order should be DERIVED and validated authoring-time
as a two-node DAG (PR nodes + non-PR gate nodes) inside the PLAN by `/plan`
collapsing its existing issue-level `waits_on` graph, with the
post-contraction acyclicity check (R13) and split-at-seam→re-sequence→stack
resolution living right there at the collapse step so an unschedulable
capstone never gets committed. But because R8 DELETES the single-pr PLAN
before the capstone PR can merge, the PLAN cannot be the durable canonical
home — the capstone PR body must carry the merge-time canonical PR-index +
fenced merge-order block, rendered from the PLAN at creation and outliving
it through merge. The net is a phase-split canon (PLAN canonical while it
lives, PR body canonical at merge) that keeps the rich #511 representation
and authoring-time validatability while surviving the consume-before-merge
lifecycle.
