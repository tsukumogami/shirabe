# Exploration Decisions: capstone-orchestration

## Round 1

- **Home = shirabe (Public, Tactical):** workflow logic lives in shirabe skills;
  niwa is called only as worktree plumbing. Confirmed up front.
- **Interface model resolved (lead 4):** conventions 1 (capstone), 2 (artifacts
  persist to capstone), 3 (sequencing), and 5 (merge order) become **smart defaults**
  (infer + announce + override); convention 4 (≤1 worktree per repo) becomes a
  **durable CLAUDE.md preference** with per-invocation override, riding the existing
  `Repo Visibility` / `Planning Context` header mechanism.
- **Scope = full cross-repo lifecycle, design-whole + sequence-delivery:** crystallize
  a DESIGN for the complete cross-repo capstone architecture, then sequence delivery
  via a ROADMAP (walking skeleton first). Rationale: the work is itself inherently
  cross-repo (skills + Rust `finalize` binary + niwa + CI), which is the condition for
  a sequenced initiative; designing the end-state up front is cheap insurance.
- **Eliminated:** ergonomics-only (leaves the real toil — manual merge-order table,
  cross-repo PR tracking, cascade — unautomated); scaffolding-first-as-standalone
  (risks designing into a corner without the cross-repo end-state); another explore
  round (remaining unknowns are design decisions, not discovery gaps).
- **Constraint accepted:** all capstone/merge-order orchestration must live in shirabe
  — niwa's mesh/delegation was removed; only `niwa worktree create/apply/destroy/list/attach`
  remains.
- **Capstone state home = the capstone branch/PR itself** (re-discoverable after
  context reset, wip-hygiene-clean, cleared on merge) — not a wip/ file, not niwa state.
- **Merge order = lift `/plan`'s `waits_on` DAG** from issue-level to per-repo-PR level
  by tagging each issue with its target repo; `/plan` keeps ownership of sequencing.

## PR-granularity sub-exploration (round 2)

Triggered by the author's discomfort with a rigid one-PR-per-repo PLAN structure.
Three focused leads (prior-art, /plan-unit, rule-tradeoffs); full findings at
`wip/research/capstone-orchestration_granularity_lead-*.md`.

- **Decomposition model = two forced axes + one discretionary axis.** Forced: (1) one
  PR per repo (repo boundary = PR boundary, a property of git/PRs); (2) a merge order
  over those PRs including non-PR publish/release gates. Discretionary: granularity
  *within* a repo — default one grouped PR per repo, split only for cause.
- **Refined rule = "coarsest *legal* grouping."** Not "fewest PRs unconditionally."
  Inter-repo boundaries are discovered; intra-repo boundaries are designed to minimize
  churn. Split a repo into >1 PR when pieces are independently mergeable, independently
  reviewable/rollback-able, too large to review as one, OR grouping would break the
  merge order.
- **Fourth split trigger (the unseen one) = contraction cycles.** Collapsing the
  issue-level DAG into a per-repo PR DAG is a graph contraction that can manufacture
  ordering cycles (issue X→Y→X collapses to PR-X⇄PR-Y deadlock). So per-repo grouping
  MUST re-validate acyclicity after contraction; resolve by split-at-seam → re-sequence
  in /plan → stacked PRs. This forces splitting *related* work, driven by topology, not
  relatedness. (DESIGN-level mechanism.)
- **Merge order is a DAG with two node types** (PR nodes + non-PR gate nodes), not a
  list, not a PR-only graph. (DESIGN-level.)
- **Cross-repo atomicity is impossible with plain PRs.** "Must ship together" is a
  design smell → reshape into a compatible-intermediate sequence (expand/contract) or a
  release gate; the capstone detects-and-refuses rather than papering over. (DESIGN-level.)
- **Brief impact:** Scope Boundary IN updated from rigid one-PR-per-repo to the coarsest-
  legal-grouping rule; mechanism (cycle check, two-node DAG, atomicity reshaping) pushed
  to OUT (DESIGN territory). Prior art confirms the universal unit is the self-contained
  logical change, never "one repo."
