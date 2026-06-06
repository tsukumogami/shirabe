# /design --auto decision log: doc-vs-github-state-reconciliation (FC09)

Mode: --auto. Worktree: shirabe-4b5eb18b. Visibility: Public. Scope: Tactical.

Decision-protocol record per /design phase. Every architectural gate is captured here. Per `references/decision-protocol.md` in --auto mode: pick recommended defaults and record `assumed` for any human-judgment gates.

## Scoped decisions (Phase 1 decomposition)

The PRD's "Downstream Artifacts" names the sub-DESIGN owns: transport, exact notice strings, timeout values, test fixture mechanism, gh module layout, `is_notice` extension wording. Mapping those plus the design's own architectural questions, FC09's sub-DESIGN scopes seven decisions:

1. **Transport choice** -- `gh` CLI subprocess vs raw HTTP. Recommended: `gh` subprocess. `assumed` (rationale below; team-lead asked for inline call).
2. **GitHub client module layout** -- where the trait lives, who implements it, how it's reached from `check_fc09`. Recommended: new module `crates/shirabe-validate/src/gh.rs` with `IssueStateClient` trait, `GhSubprocessClient` impl, `MockIssueStateClient` (cfg(test)).
3. **Test-fixture mechanism** -- trait-based mocking vs recorded HTTP fixtures. Recommended: trait-based, mirrors FC07 sub-DESIGN Decision 4.
4. **Notice-string wording** -- the three sub-check defect strings plus the four self-disable strings, in FC05/FC06/FC07 voice. Recommended: fixed strings, one per case, public-clean.
5. **Timeout, retry, back-off values** -- single retry on 429, fixed back-off, 5s default per-request timeout, abort on second 429.
6. **`is_notice` extension wording** -- exact match-arm change.
7. **PR-context env-var plumbing** -- which env vars, fallback chain, override variable.

Each decision is researched inline in Phase 2 (no decision-researcher Agent inside this team). Per-decision artifact lands at `wip/research/design_doc-vs-github-state-reconciliation_decision-<N>-<slug>.md`.

## Phase decisions

| Phase | Gate | Outcome |
|-------|------|---------|
| Phase 1 | Add or drop decisions vs the brief list | Kept 7 (transport, client module, test fixture, notice strings, timeout/retry, is_notice extension, PR-context env vars). No additions. `confirmed` -- enumeration matches the PRD's downstream-artifacts list. |
| Phase 1 | Decision-researcher dispatch | INLINE per team-lead's adaptation note (no Agent tool inside team). `confirmed` (team-lead directive). |
| Phase 5 | Security reviewer dispatch | SendMessage `security-researcher`. `confirmed`. |
| Phase 6 | Final jury dispatch | SendMessage `architecture-reviewer` + `security-reviewer` in parallel. `confirmed`. |
| Phase 7 | Terminal status target | `Current` per FC07 sub-DESIGN precedent (`docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`). `confirmed`. |
