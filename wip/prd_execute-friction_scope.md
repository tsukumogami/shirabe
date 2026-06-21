# /prd Scope: execute-friction

## Upstream
docs/briefs/BRIEF-execute-friction.md (Accepted)

## Discover reuse
Phase 2 research is satisfied by the committed exploration
(`wip/explore_execute-friction_findings.md` + the six `wip/research/explore_*`
lead files): each friction cluster already has root-cause confirmation, fix
options with trade-offs, and direct-fix-vs-needs-design verdicts grounded in
`skills/execute/` and `skills/plan/` source. No new discovery fan-out needed.

## Requirements map (friction → R#)
- F1 → R1 (existing branch/PR targeting), with F5a auto-cascade consequence
- F3 → R2 (pause-for-review before finalization)
- F4 → R3 (docs coverage when plan adds user-visible surface)
- F6 → R4 (template-conformant PR from finalization)
- F5b → R5 (manual/fallback finalization-not-done guard)
- F7 → R6 (durable home for report-upstream artifacts)
- non-functional → R7 (backward-compatible default), R8 (autonomy interaction)

## Deferred to DESIGN (BRIEF Open Questions)
The exact surfaces/mechanisms (existing-PR surface; pause shape; docs detection
signal + owning layer; guard home; durable-capture home) are recorded under the
PRD's Decisions and Trade-offs as requirements-level decisions that constrain but
do not pre-empt the DESIGN.
