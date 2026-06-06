# Phase 2 Research: Codebase Analyst

Investigation of the three contract surfaces being fixed, the verification
primitives available to bind them as ACs, and the boundary between requirement
("contract that must hold") and mechanism ("approach DESIGN picks").

## Lead 1: #156 contract surface and failure shape boundary

### Findings

The broken contract lives at `skills/plan/scripts/plan-to-tasks.sh:288`:

```bash
if [[ -n "$current_number" && "$line" =~ \*\*Dependencies\*\*:[[:space:]]*(.+)$ ]]; then
    current_deps="${BASH_REMATCH[1]}"
```

The regex matches `**Dependencies**:` (colon strictly outside the bold markers)
and nothing else. When the PLAN author writes `**Dependencies:**` (colon inside),
`current_deps` is never assigned, the per-issue accumulator stays empty, and
downstream `waits_on` resolution emits `[]` for every issue. The script
terminates with success and the orchestrator spawns all children in parallel
on the shared branch.

The parser does recognize an alternative `### Dependencies` section format
(lines 313-339), but the bold-inline form with the wrong colon placement falls
through into neither path.

There is no validator gate on this. `shirabe validate` accepts both colon
placements as valid PLAN frontmatter because the validator never inspects the
dependency-line text inside the issue outline section.

### Implications for Requirements

The PRD must bind two distinct contracts that together close the silent-failure
shape:

1. **Surface contract**: the parser SHALL accept the dependency line regardless
   of which colon placement the author used.
2. **Failure-shape contract**: when the parser yields empty dependencies for a
   PLAN issue AND the PLAN declares more than one issue, the workflow SHALL
   surface a signal the operator can act on before the parallel-spawn step
   runs.

Both contracts are necessary because either alone leaves a failure mode open:
loosening the regex without the warning means the next regex-format drift still
fails silently; emitting a warning without loosening the regex leaves the
common-case author stuck behind a warning every run.

The verification surface for (1) is grep-checkable (test both colon variants
through the parser, assert deps are populated). The verification surface for
(2) is also grep-checkable but at a different level (run the parser on a
fixture with empty deps + >1 issue, assert a warning fires).

### Open Questions

- Whether the failure-shape contract belongs at the parser level, the
  orchestrator level (refuse to spawn parallel when deps are empty and there
  are >1 issues), or at the FC validator level (refuse to validate a PLAN with
  ambiguous dependency lines). DESIGN owns this choice. The PRD must state the
  contract without picking the level.

## Lead 2: #159 chain-handoff symmetry contract

### Findings

The asymmetry is real and codified in three locations:

- `/prd` `SKILL.md` (lines 132-136 + Phase 0 execution block) explicitly
  transitions a Draft BRIEF to Accepted when receiving one as input. The skill
  exposes this as "Upstream brief transition (brief input mode only)" and
  invokes `shirabe transition <brief-path> Accepted`.
- `/design` `references/phases/phase-0-setup-prd.md:29-31` hard-stops:
  > Status is "Accepted"
  > If the PRD status is not "Accepted", STOP and inform the user. Design work
  > requires accepted requirements.
- `/plan` `references/phases/phase-1-analysis.md:38-50` hard-stops on DESIGN
  status with a per-status error message table; lines 65-67 do the same for
  ROADMAP status.

The asymmetry surfaces every chain handoff under `/scope` because `/scope`'s
child-invocation pattern hands each child its upstream artifact at the status
the prior child left it in (BRIEF -> Accepted is fine for `/prd`; PRD -> Draft
trips `/design`; DESIGN -> Proposed trips `/plan`).

### Implications for Requirements

The PRD must bind the chain-handoff symmetry as a contract without picking the
mechanism. Three mechanisms are candidates (auto-transition unconditionally;
documented-contract with operator action; sentinel-gated auto-transition); each
has different invariants the contract must preserve.

What MUST hold post-fix:

1. **Handoff completes without operator intervention** when the chain is being
   driven by a parent (e.g., `/scope`) — the operator does not drop into a
   shell between `/brief -> /prd -> /design -> /plan` to satisfy a status gate
   for any of `/design` or `/plan`.
2. **Asymmetry is closed**: whatever pattern `/prd` uses to handle its upstream
   BRIEF, `/design` (with PRD upstream) and `/plan` (with DESIGN upstream) use
   the same pattern, OR the asymmetry is removed by aligning all three on a
   different pattern. The PRD MUST NOT prescribe which side aligns to which.
3. **No regression for direct invocation**: when a child is invoked outside a
   parent chain (no orchestration context), the existing protective behavior
   (refusing to consume a Draft upstream) MUST still be reachable. The
   silent-by-default surface is the parent-chain case, not the direct-invocation
   case.

The verification surface mixes grep-checkable (status-gate invocation matches
across the three skills) and integration-test (running `/scope` end-to-end on a
fresh BRIEF reaches PLAN without operator intervention).

### Open Questions

- Whether the symmetry contract requires `/prd`, `/design`, and `/plan` to all
  use the same mechanism, or whether each can use a different mechanism as long
  as the end-to-end chain-handoff property holds. DESIGN owns this choice; the
  PRD binds the end-to-end property, not the per-skill alignment.

## Lead 3: #162 dual-surface failure (worktree-discipline + ci_monitor)

### Findings

Two contract surfaces are involved:

1. **`/work-on` orchestrator worktree-discipline**: the
   `references/parent-skill-worktree-discipline.md` reference (line 51+)
   prescribes a `git fetch` + rebase against `origin/<tracking-branch>` + impact
   analysis + classification (None / Informational / Intent-changing) flow. The
   reference is named for the parent-skill pattern; `/work-on` is the long-running
   single-pr surface that needs the same discipline but the existing `/work-on`
   skill body (`skills/work-on/references/phases/*.md`) does not invoke this
   flow between per-issue commits during single-pr execution. PR-141 hit
   exactly this: shirabe#139 merged to main mid-PR, deleted the package the
   PLAN was implementing against, and `/work-on` kept building against the
   deleted package.
2. **`ci_monitor` step**: `skills/work-on/koto-templates/work-on-plan.md:75-111`
   defines a `ci_monitor` step that waits on CI check-runs. When the PR's
   `mergeStateStatus=DIRTY`, GitHub silently stops creating workflow runs, so
   the `ci_monitor` step waits indefinitely on checks that will never appear.
   The step has no DIRTY-detection branch; it treats "no checks reported" as
   pending.

### Implications for Requirements

The PRD must bind both surfaces, but as two separate contracts. They share the
sweep's "silent-by-default" failure shape but have independent verification
surfaces and independent mechanism options.

For surface (1):

- **Contract**: long-running single-pr execution under `/work-on` SHALL detect
  an upstream change to the tracking branch between commits and classify its
  impact against the PLAN's foundational assumptions.
- **Failure-shape contract**: intent-changing upstream changes SHALL surface an
  escalation the operator can act on mid-chain, not at PR finalization.

For surface (2):

- **Contract**: `ci_monitor` SHALL distinguish between "checks are pending" and
  "checks cannot be reported because the PR state suppresses workflow creation"
  (typically `mergeStateStatus=DIRTY` or similar zero-checks-after-N-minutes
  signals).
- **Failure-shape contract**: the suppressed-checks case SHALL route to an
  escalation, not to indefinite wait.

The PRD MUST bind both contracts independently because the issue body explicitly
notes the `ci_monitor` fix is separable from the worktree-discipline fix
(candidate (d) in the issue's enumeration). DESIGN may fix only one and leave
the other for follow-up; the PRD's job is to make both contracts reviewable.

The verification surface for (1) is integration-test (run `/work-on` against a
PLAN, land a conflicting commit on main mid-run, assert escalation fires). The
verification surface for (2) is grep-checkable (the `ci_monitor` step body
contains a DIRTY-detection or zero-checks-after-timeout branch).

### Open Questions

- Whether the PRD treats both surfaces as in-scope or scopes one out to a
  separate work stream. Recommendation from the BRIEF's framing: both in scope,
  both as separate requirements, because the failure shape only closes when
  both surfaces are covered.

## Lead 4: Validator and verification primitives in v0.9.1-dev

### Findings

The shirabe validator in v0.9.1-dev (`crates/shirabe-validate`) handles
`schema:` frontmatter via `checks.rs:check_schema()`. The behavior is:

```rust
pub fn check_schema(doc: &Doc, spec: &FormatSpec) -> Option<ValidationError> {
    if doc.schema == spec.schema_version {
        return None;
    }
    Some(ValidationError {
        file: doc.path.clone(),
        line: 1,
        code: "SCHEMA".to_string(),
        message: format!("schema {:?} not in supported range, skipping", doc.schema),
    })
}
```

A PRD without `schema: prd/v1` (or with an unknown schema) gets a SCHEMA notice
and the validator stops running downstream FC checks against it. This is the
same silent-skip behavior #157 named for v0.7.0-era PRDs — it has been
preserved in the Rust cutover. The notice is emitted but the document is not
hard-rejected, so a PRD missing the schema field passes `shirabe validate`
overall (notice-level, not error-level).

Implication: setting `schema: prd/v1` is mandatory if the PRD wants the
downstream FC validators to run against it. Omitting it does not fail loud.

### Implications for Requirements

This finding is meta to the three bugs but relevant to verifying the PRD
itself. The PRD MUST include `schema: prd/v1` in frontmatter or it will be
silently skipped by the validator that the chain downstream of it relies on.

For the three bugs' ACs: grep-checkable ACs are realistic for parser regex
coverage (#156 surface contract), skill-body status-gate alignment (#159
mechanism-agnostic surface check: search for "STOP and inform" patterns in
`/design` and `/plan` Phase 0/1), `ci_monitor` body inspection (#162 surface
2), and worktree-discipline invocation (#162 surface 1, grep for `git fetch
origin` or the discipline-reference inclusion in `/work-on` Phase X). The
integration-test ACs (end-to-end chain handoff under `/scope`, end-to-end
upstream-change escalation under `/work-on`) need to be marked as
judgment/integration-tested rather than grep-checkable.

### Open Questions

None.

## Summary

The three bugs decompose into four contract surfaces (#156: parser regex +
silent-empty warning; #159: chain-handoff symmetry across three skills; #162:
worktree-discipline in `/work-on` + DIRTY-aware `ci_monitor`). Each surface
gets independent requirements with mechanism-deferred language. ACs split
roughly evenly between grep-checkable (parser variants, skill-body
status-gate sentinels, `ci_monitor` DIRTY branch, worktree-discipline
invocation) and judgment/integration-tested (end-to-end chain handoff,
end-to-end upstream escalation, symmetry preservation across direct vs.
parent-driven invocation). The PRD also needs `schema: prd/v1` to avoid
the validator silently skipping it.
