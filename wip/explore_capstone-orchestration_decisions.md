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
