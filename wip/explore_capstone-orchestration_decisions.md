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

## Integration-shape design lead (leading candidate for DESIGN)

Answers the brief's deferred "integration shape" question. Author-proposed, agreed.

- **Both: a canonical reference + capstone-aware consumers.** Articulate the capstone
  strategy once as a cross-cutting plugin reference (`references/capstone-*.md`) defining
  the lifecycle, the coarsest-legal-grouping rule, the two-node merge-order DAG (PR nodes
  + non-PR gate nodes), and the done-signal. Then make `/scope`, `/work-on`, and the
  `shirabe` CLI (`finalize`/`validate`) capstone-**aware** by binding to that reference.
- **Precedent:** this is shirabe's house style — `references/` already holds cross-cutting
  contracts (`parent-skill-pattern.md` consumed by `/scope` + `/charter`,
  `worktree-discipline.md`, `cross-repo-references.md`, `wip-hygiene.md`). The capstone has
  three consumers (`/scope`, `/work-on`, CLI), so it earns a reference rather than living
  inside one skill. It sits naturally beside `cross-repo-references.md`.
- **Discipline (the failure mode to avoid):** the contract lives in the reference; skills
  and CLI carry only *bindings*, never a restated copy — same anti-drift discipline
  `parent-skill-pattern.md` uses. "Both" must mean one source of truth, not two.
- **Cost location:** the reference doc is cheap; the load-bearing/expensive work is CLI
  enforcement — `finalize`/`validate` learning to walk and gate **across repos** (the
  single-repo edge found in `finalize.rs` / `validate_upstream_path`). Budget effort there.
- **Consistency with brief:** a reference is a contract, not a "separate tool bolted
  alongside," so this honors the brief's IN ("capstone-aware") and answers its OUT
  ("integration shape = DESIGN").

## Dogfooding finding: lifecycle CI vs in-flight capstone chain (DESIGN input)

Surfaced by CI on the dogfood capstone PR #196. The `lifecycle` check
(`shirabe validate --lifecycle`) failed L02 (orphan-doc rule, governed by
`docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`) on the freshly
committed `BRIEF` at status Draft. An orphan doc passes L02 only if terminal (Done),
roadmap-rooted with an Active ROADMAP upstream, or a linked chain member; a from-scratch
tactical chain's HEAD artifact (a BRIEF with no ROADMAP above it and no downstream PRD yet)
satisfies none until its downstream lands. L02 is not strict-gated, so it fails even on a
draft PR.

Design implication: a capstone PR holds an in-flight chain whose head artifact is
**transiently orphaned** until the next chain artifact references it as `upstream:`. The
lifecycle check is not capstone-/in-flight-chain-aware. The DESIGN must reconcile this —
options: (a) a capstone PR is only expected CI-green once its chain is complete (treat
intermediate red as normal, like the docs-only-skips-integration-gates wrinkle from the
#511 analysis); (b) L02 gains awareness of an in-flight capstone chain; (c) some explicit
"chain in progress" marker. This is the concrete instance of the #511 "docs-only capstone
vs CI gates" wrinkle. Resolves naturally here once `/prd` writes PRD with
`upstream: docs/briefs/BRIEF-capstone-orchestration.md`.
