# Issue 28 Implementation Plan

## Summary

Replace all direct `wip/` filesystem access with koto's content API (`koto context add/get/exists`),
and migrate template gates from `command` type with `test -f` to `context-exists` type. This
centralizes artifact lifecycle in koto, eliminating manual cleanup and enabling future cross-session
content sharing.

## Approach

Migrate bottom-up: template gates first (structural change), then phase files (behavioral change),
then scripts (tooling change). This order lets us validate the template compiles before changing
the files that produce/consume the content.

### Alternatives Considered

- Top-down (scripts first): Would break the workflow mid-migration since gates still expect files
- Big-bang: Higher risk, harder to debug if something breaks

## Key Mapping

| Phase | Current artifact | Context key |
|-------|-----------------|-------------|
| Phase 0 | `wip/IMPLEMENTATION_CONTEXT.md` | `context.md` |
| Phase 1 | `wip/{{ARTIFACT_PREFIX}}_baseline.md` | `baseline.md` |
| Phase 2 | `wip/issue_{{ISSUE_NUMBER}}_introspection.md` | `introspection.md` |
| Phase 3 | `wip/{{ARTIFACT_PREFIX}}_plan.md` | `plan.md` |
| Phase 5 | `wip/{{ARTIFACT_PREFIX}}_summary.md` | `summary.md` |

Session name: the koto workflow name (e.g., `issue_28`). Templates use `{{SESSION_NAME}}`.

## Files to Modify

- `skills/work-on/koto-templates/work-on.md` - Replace 6 gates with content-aware types
- `skills/work-on/references/phases/phase-0-context-injection.md` - Use context API for reads
- `skills/work-on/references/phases/phase-1-setup.md` - Write baseline via context add
- `skills/work-on/references/phases/phase-2-introspection.md` - Write introspection via context add
- `skills/work-on/references/phases/phase-3-analysis.md` - Delegate with context API paths
- `skills/work-on/references/phases/phase-4-implementation.md` - Read plan/context via context get
- `skills/work-on/references/phases/phase-5-finalization.md` - Write summary via context add; remove `rm -rf wip/`
- `skills/work-on/references/agent-instructions/phase-3-analysis.md` - Update wip/ path refs
- `skills/work-on/references/scripts/extract-context.sh` - Write to koto context instead of wip/
- `skills/work-on/SKILL.md` - Update decisions file path reference

## Implementation Steps

- [ ] Step 1: Migrate template gates (koto-templates/work-on.md)
  - Replace `context_artifact` gate: `type: context-exists`, `key: context.md`
  - Split `branch_and_baseline` (setup_issue_backed): branch check stays as command, add `baseline_exists` as context-exists
  - Split `branch_and_baseline` (setup_free_form): same split
  - Replace `introspection_artifact` gate: `type: context-exists`, `key: introspection.md`
  - Replace `plan_artifact` gate: `type: context-exists`, `key: plan.md`
  - Replace `summary_and_tests` gate: split into `summary_exists` (context-exists) + `tests_pass` (command)
  - Validate: `koto template compile`

- [ ] Step 2: Update phase reference files
  - Phase 0: Change "Read wip/IMPLEMENTATION_CONTEXT.md" to "Read via `koto context get <WF> context.md`"
  - Phase 1: Change "Create wip/...baseline.md" to "Write via `koto context add <WF> baseline.md --from-file <path>`"
  - Phase 2: Change "Write findings to wip/..." to "Store via `koto context add <WF> introspection.md --from-file <path>`"
  - Phase 3: Update baseline reference and plan output path to use context API
  - Phase 4: Change "wip/...plan.md" to `koto context get <WF> plan.md`, same for context.md
  - Phase 5: Change summary write to context add; remove `rm -rf wip/` cleanup step

- [ ] Step 3: Update extract-context.sh
  - Accept optional `--session <name>` flag for koto context storage
  - When session provided: pipe content to `koto context add <session> context.md` instead of writing wip/
  - When no session: fall back to wip/ write (backward compat during transition)
  - Update JSON output to reflect new storage location

- [ ] Step 4: Update agent instructions (phase-3-analysis.md)
  - Change baseline reference from `wip/issue_<N>_baseline.md` to `koto context get <WF> baseline.md`
  - Change plan output from `wip/issue_<N>_plan.md` to `koto context add <WF> plan.md`
  - Change context check from file existence to `koto context exists <WF> context.md`

- [ ] Step 5: Update SKILL.md
  - Change `wip/work-on_<N>_decisions.md` reference (decisions are already via `koto decisions`)

- [ ] Step 6: Validate template compiles and evals pass

## Testing Strategy

- Template validation: `koto template compile` must pass
- Eval suite: Run `scripts/run-evals.sh work-on` to verify no regressions
- Manual: Initialize a test workflow and verify context add/get/exists work through the flow

## Risks and Mitigations

- **Risk**: extract-context.sh is called before agent knows the session name
  - Mitigation: Script still writes to a temp location; agent pipes to koto context add after
- **Risk**: Phase files reference `{{SESSION_NAME}}` but agents may not know the variable
  - Mitigation: Use `<WF>` placeholder in prose; agents already know the workflow name from the koto next loop

## Success Criteria

- [ ] No `wip/` path references remain in work-on skill files (except backward-compat in extract-context.sh)
- [ ] All template gates use content-aware types where appropriate
- [ ] `koto template compile` passes
- [ ] Eval suite passes (54+ assertions)
