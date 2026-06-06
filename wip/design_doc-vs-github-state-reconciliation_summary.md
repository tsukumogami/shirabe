# /design Phase 0 summary: doc-vs-github-state-reconciliation (FC09)

Mode: --auto. Worktree: shirabe-4b5eb18b. Branch: session/4b5eb18b.

## Input

Upstream PRD: `docs/prds/PRD-doc-vs-github-state-reconciliation.md` (status: Accepted; 17 requirements R1-R17; 28 acceptance criteria; 6 PRD-level decisions; 9 OUT items).

Parent DESIGN: `docs/designs/DESIGN-roadmap-plan-standardization.md`, Decision 3 (the staged-reconciliation increment behind a spike and a notice-then-error rollout). The FC09 sub-DESIGN refines, does not supersede.

Architectural precedent: `docs/designs/current/DESIGN-table-diagram-reconciliation.md` (FC07 sub-DESIGN). Decision 6 (`Row.terminal` + class-versus-Status pass) is the loop FC09 extends with `observed_state` from a `gh::IssueStateClient` instead of `row.terminal`.

## Topic slug

`doc-vs-github-state-reconciliation`. Output path: `docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`.

## Detected context

- **Repo visibility:** Public (CLAUDE.md: `## Repo Visibility: Public`). Notice strings and rule prose stay public-clean (no private repo names, paths, filenames, external issue numbers, or pre-announcement features).
- **Planning context:** Tactical (CLAUDE.md: `## Planning Context: Tactical`). FC09 is implementation-level work; the design scopes the HOW for one feature.

## Decision count

7 (see decisions.md). Each is researched inline in Phase 2 because the coordinator runs inside a TeamCreate team and the Agent tool is not available there. Per-decision artifacts land at `wip/research/design_doc-vs-github-state-reconciliation_decision-<N>-<slug>.md`.

## Workflow path

Phase 0 (this) -> Phase 1 (already inline in this summary) -> Phase 2 (inline decision research, 7 artifacts) -> Phase 3 (cross-validate) -> Phase 4 (draft DESIGN) -> Phase 5 (security via SendMessage) -> Phase 6 (jury via SendMessage, 3-iteration cap) -> Phase 7 (`shirabe transition`).

No commit at any phase. Team-lead handles git ops.
