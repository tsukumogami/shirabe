# Design Summary: work-on-koto-unification

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** Unify work-on and /implement into a single koto-backed workflow that handles free-form tasks, single issues, and multi-issue plans, while migrating to koto v0.6.0 structured gate output.

## Design Decisions (Phase 1-3)
Four decisions evaluated with cross-validation, all high confidence:

1. **Template topology:** Single monolithic per-issue template with 3-way entry routing (~24 states)
2. **Orchestrator:** Pure koto orchestration via `materialize_children`. No scripts. Single-state fan-out per koto v0.8.0 E10.
3. **Gate migration:** Strict v0.6.0 mode, selective decomposition of code_committed into 3 atomic gates, mixed routing on all gated states.
4. **Review panels:** Context-exists gates for persistence, evidence enums for transition routing. New scrutiny/review/qa_validation states.

## Post-Design Revisions

### koto v0.7.0 revision (2026-04-05)
Koto shipped hierarchical multi-level workflows (#127, v0.7.0). Decision 2 revised:
- **Dropped:** manifest JSON, reconciliation protocol, 3 of 4 script subcommands
- **Added:** parent workflow template (work-on-plan.md) with children-complete gate
- **Simplified:** dependency script to single `next-ready` subcommand
- **Result:** koto is single source of truth for state; dependency script remains for ordering only

### ISSUE_SOURCE variable (2026-04-11)
Added `ISSUE_SOURCE` enum variable (`github | plan_outline`) to distinguish plan items that are GitHub issues (multi-pr mode: staleness check, gh issue view) from pure outline items (read PLAN section, skip staleness).

### Batch child spawning filed (2026-04-11)
Filed tsukumogami/koto#129 requesting declarative batch child spawning from parent evidence. Would eliminate the dependency script entirely.

### koto v0.8.0 revision (2026-04-14)
Koto shipped declarative batch child spawning (tsukumogami/koto#130, v0.8.0). Decision 2 re-evaluated and revised:
- **Dropped:** `plan-deps.sh` script and its `next-ready` subcommand entirely
- **Dropped:** `jq` runtime dependency
- **Collapsed:** `spawn_and_execute` + `await_completion` into a single
  `spawn_and_await` state per koto's E10 single-state fan-out rule
- **Adopted:** `materialize_children` hook, `tasks`-typed evidence,
  `retry_failed` reserved evidence, `batch_final_view` on terminal,
  derived route booleans (`all_success`, `any_failed`, `needs_attention`)
- **Added to per-issue template:** `failure: true` on `done_blocked`
  (koto Decision 5.1), `skipped_marker: true` terminal state (F5),
  `failure_reason` context writes on escalation paths (W5)
- **Result:** zero orchestration scripts; koto compile-time invariants
  (E10, W4, F5, W5) enforce correctness the design previously had to
  promise by hand

## Security Review (Phase 5, re-run 2026-04-14)
**Outcome:** Option 3 (N/A with justification)
**Summary:** Design restructures internal workflow orchestration without new attack surfaces, external dependencies, or data exposure paths. The v0.8.0 revision shrinks the surface further (no shell script, no jq dependency) and gains typed pre-append validators (koto R0-R9).

### PLAN parser script decision (2026-04-14, late)
Ran `/shirabe:decision` on "how should /work-on obtain koto tasks
evidence from a PLAN doc?" to resolve an open implementation detail.
Outcome: parser script owned by /plan
(`skills/plan/scripts/plan-to-tasks.sh`), /work-on pipes its stdout into
`koto next --with-data @-`. No JSON file lives in the repo tree or in
`wip/`. Decision report at
`wip/decision_plan-parser-script_report.md`.

Design updates applied:
- Frontmatter rationale and decision lines
- Decision 2's "Chosen" description and alternatives note
- `spawn_and_await` directive YAML
- Solution Architecture Overview, Components, Key Interfaces, Data Flow,
  Resume sections
- Implementation Approach: Phase 4 reference, new Phase 4b for the
  script prerequisite, Phase 5 delegation
- Security Considerations task-list submission bullet
- Consequences (Positive, Negative, Mitigations)

## Blockers
None. Koto v0.8.0 resolved the previous blocker (#129/#130). Design is
ready for /plan.

## Current Status
**Phase:** 6 - Final Review (complete, awaiting approval)
**Last Updated:** 2026-04-14 (PLAN parser decision applied)

## Next Steps
1. Human review and approval of the revised design
2. Transition status to Accepted
3. Run /plan to decompose into issues. Plan should assume koto v0.8.0 is
   pinned in the workspace; any issue that authors or modifies templates
   should run `koto template compile` in CI to catch E10/W4/F5/W5
   violations.
