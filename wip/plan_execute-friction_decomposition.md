# /plan decomposition: execute-friction

**input_type:** design (docs/designs/DESIGN-execute-friction.md, Accepted)
**execution_mode:** single-pr — all substantive work is in the shirabe repo and
delivers one cohesive feature (trustworthy /execute finalization). The D5 workspace
`CLAUDE.md` + dot-niwa-overlay mirror are out-of-repo convention edits, noted as
cross-repo follow-up, not landable in the shirabe PR.
**decomposition strategy:** horizontal — loosely-coupled skill/template/doc edits
with clear boundaries and minimal runtime interaction; not a walking skeleton (no
integration-risk end-to-end path).

**Value confirmation (3.5a):** single-pr unit = the whole PR, which delivers
observable value (an /execute developers can trust to finish). PASS (confirmed).

## Issues (6) — one per DESIGN decision; D5 absorbs the D3 dogfood docs item

1. D1 — mode-aware branch/PR targeting (execute.md SHARED_BRANCH capture + coordinated rule)
2. D6 — template-conformant PR in pr_finalization
3. D2 — interactive pause / --auto finalizes (depends on 2)
4. D3 — docs-coverage in /plan (user_visible_surface + emit + review-plan backstop)
5. D4 — finalization guard (validate --lifecycle-chain --mode=ready usage + CI)
6. D5 + dogfood docs — report-upstream convention + user-facing docs of new behaviors (depends on 1,2,3,5)

All skill-authoring (docs-type). Each issue updates its skill's evals per the
shirabe Skill-Evals rule.

Note: the D3 auto-emit logic ships in Issue 4 but does not exist yet at planning
time, so this PLAN emits the dogfood docs item (Issue 6) manually — honoring this
DESIGN's own `user_visible_surface: true`.
