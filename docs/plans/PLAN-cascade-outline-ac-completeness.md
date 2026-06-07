---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-cascade-outline-ac-completeness.md
milestone: "cascade-outline-ac-completeness"
issue_count: 3
---

# PLAN: cascade-outline-ac-completeness

## Status

Active

## Scope Summary

Implement check `L06` in shirabe-validate: parse a PLAN's
`## Issue Outlines` section, find every `- [ ]` checkbox under
each `### Issue N` outline, and refuse the cascade's finalization
commit when any AC remains unticked. Bundle the work with the
`--allow-untracked-acs` CLI flag and the cascade script's
`WORK_ON_ALLOW_UNTRACKED_ACS=1` environment-variable forwarding. Single
PR; three outline blocks driving the implementation sequence.

## Decomposition Strategy

**Horizontal, single-pr.** The work decomposes into three layers with
clear interfaces between them (parser + check function in the
validator crate -> CLI flag + dispatch wiring -> cascade script
integration + tests). Issue 1 (parser + check + dispatch) is the
foundation; Issue 2 (CLI flag) consumes Issue 1's check function;
Issue 3 (cascade script) consumes Issue 2's CLI flag.

Single-pr execution mode anchored on /plan's default ("Reach for one
PR") under the usable-value principle: the work delivers observable
value as a single increment, no multi-pr escape conditions apply (no
cross-repo landing order, no workflow-must-reach-main gate, no
genuine independent value from splitting). The three outlines collapse
to one PR; /work-on's outline-by-outline traversal sequences the
implementation deterministically, L06 lands as error-level in one
merge alongside the cascade script forwarding and the corpus-
migration commit.

## Issue Outlines

### Issue 1: feat(validate): add parse_outline_acs + check_l06 with strict tolerance

**Goal**: Add a new outline-AC parser `parse_outline_acs(doc: &Doc) -> Vec<OutlineAc>` to `crates/shirabe-validate/src/table.rs` adjacent to the existing `parse_issue_outlines` helper. Add `check_l06(doc: &Doc, cfg: &Config) -> Vec<ValidationError>` to `checks.rs`. Wire the dispatch in the Plan arm of `validate_file` under the `--lifecycle-chain` mode. Register `L06` in `is_notice` as `false` (error-level).

**Acceptance Criteria**:
- [x] `parse_outline_acs(doc: &Doc) -> Vec<OutlineAc>` is exposed from `crates/shirabe-validate/src/table.rs`.
- [x] The parser only fires on docs whose frontmatter `execution_mode` is `single-pr`; multi-pr PLANs do not have outline-AC checkboxes (their issues live in the Implementation Issues table) and the parser returns `Vec::new()` for them.
- [x] `OutlineAc` carries `outline_key: String`, `ac_text: String`, `ticked: bool`, `line: usize` (1-indexed).
- [x] The parser walks the body slice between `## Issue Outlines` and the next `##` heading; within each `### Issue N` block it scans for `- [ ]`, `- [x]`, and `- [X]` checkbox-line prefixes; emits one `OutlineAc` per recognized line.
- [x] Non-canonical AC shapes (bare sentences without the bracket, nested checkboxes, non-canonical bracket spacing like `- [  ]` or `-[]`) are not recognized and do not contribute to the returned vector.
- [x] A doc with no `## Issue Outlines` section returns `Vec::new()`; no panic.
- [x] An outline block with no AC lines does not appear in the returned vector beyond the empty case; no panic.
- [x] `check_l06(doc: &Doc, cfg: &Config) -> Vec<ValidationError>` exists in `checks.rs`; emits one `ValidationError` per unticked `OutlineAc` with code `L06` and message `[L06] outline '<outline_key>' has unticked acceptance criterion: '<ac_text>' (line <line>)`.
- [x] `check_l06` is dispatched in the Plan arm of `validate_file` under the chain-targeted lifecycle mode.
- [x] `L06` is registered in the `is_notice` match arm in `crates/shirabe-validate/src/validate.rs` as `false` (error-level).
- [x] `cargo test -p shirabe-validate` passes including parser unit tests covering each totality case above, plus check tests covering all-ticked passes, any-unticked fails, and the message-format shape.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/table.rs`, `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/validate.rs`

### Issue 2: feat(validate): add --allow-untracked-acs CLI flag and Config wiring

**Goal**: Add the boolean `allow_untracked_acs` field to the validator's `Config` struct; wire the `--allow-untracked-acs` CLI flag (default `false`) into the `validate` subcommand's argument parser; have `check_l06` from <<ISSUE:1>> honor `cfg.allow_untracked_acs` by returning an empty `Vec` when the flag is set.

**Acceptance Criteria**:
- [x] `Config` (or the existing equivalent config struct) has an `allow_untracked_acs: bool` field defaulting to `false`.
- [x] The `validate` subcommand's argument parser accepts `--allow-untracked-acs` as a boolean flag (default `false`).
- [x] When `cfg.allow_untracked_acs == true`, `check_l06` returns an empty `Vec` regardless of the doc's unticked-AC state.
- [x] When `cfg.allow_untracked_acs == false` (the default), `check_l06` behaves exactly as Issue 1 specifies.
- [x] CLI tests verify: `shirabe validate --lifecycle-chain <PLAN> --strict` exits 0 on an all-ticked PLAN; exits non-zero on a PLAN with any unticked AC; exits 0 when `--allow-untracked-acs` is added; the L06 error message includes the outline key and AC text.
- [x] No other check (L01-L05) is affected by the new flag.
- [x] `cargo test -p shirabe` (or the binary's integration-test crate) passes including the new CLI scenarios.

**Dependencies**: <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe/src/cli.rs` (or the equivalent argv-parsing location), `crates/shirabe-validate/src/checks.rs`

### Issue 3: feat(skills,work-on): cascade forwards WORK_ON_ALLOW_UNTRACKED_ACS; corpus migrated

**Goal**: Update `skills/work-on/scripts/run-cascade.sh` to detect `WORK_ON_ALLOW_UNTRACKED_ACS=1` and forward `--allow-untracked-acs` to both the pre-probe and post-verify validator invocations. Emit the documented suppression log line. Update the cascade script's `add_step` instrumentation. Run `shirabe validate --lifecycle . --strict` against the live corpus; tick or descope any pre-existing unticked outline ACs in the same commit so the check goes live without surfacing pre-existing drift.

**Acceptance Criteria**:
- [x] `skills/work-on/scripts/run-cascade.sh` reads `WORK_ON_ALLOW_UNTRACKED_ACS` once and builds a shared `extra_args` array (`(--allow-untracked-acs)` when the env value is `1`, empty otherwise) used by both call sites.
- [x] Both the pre-probe (around line 185 / 553 in the current source) and the post-verify (around line 759) invocations pass `"${extra_args[@]}"` to `shirabe validate --lifecycle-chain "$PLAN_DOC" --strict`.
- [x] When `WORK_ON_ALLOW_UNTRACKED_ACS=1` is set, the script emits the literal log line `[L06-suppressed via WORK_ON_ALLOW_UNTRACKED_ACS=1]` once at script start (before the first validator invocation).
- [x] The `add_step` calls for the lifecycle hooks include a marker reflecting the suppression state (a third positional argument tagged with `l06_suppressed=1` when the env is set, absent otherwise).
- [x] `skills/work-on/scripts/run-cascade_test.sh` exercises: a clean PLAN passes both hooks; an unticked-AC PLAN fails pre-probe with L06; setting `WORK_ON_ALLOW_UNTRACKED_ACS=1` overrides and the cascade proceeds; the post-verify mirrors the pre-probe outcome.
- [x] `shirabe validate --lifecycle . --strict` exits 0 on the live shirabe corpus after the migration commit (i.e. no pre-existing unticked outline ACs remain in committed PLANs; if any existed, they are ticked or removed as part of this PR).
- [x] The cascade's existing single-validator-invocation contract is preserved (no new subprocess, no second validator call per hook).

**Dependencies**: <<ISSUE:2>>

**Type**: code
**Files**: `skills/work-on/scripts/run-cascade.sh`, `skills/work-on/scripts/run-cascade_test.sh`, `docs/plans/PLAN-*.md` (corpus migration as needed)

## Implementation Sequence

The single-PR shape sequences the three issues by dependency:

1. **Issue 1** lands the parser, the check, the dispatch wiring, and the `is_notice` registration. The new code paths exist but are dormant from the cascade's perspective until the CLI flag wiring lands.
2. **Issue 2** lands the `--allow-untracked-acs` CLI flag and the Config plumbing. After this issue the validator binary exposes the full L06 surface; agents and CI consumers can invoke it directly.
3. **Issue 3** lands the cascade script forwarding and the corpus migration. After this issue the cascade enforces L06 by default with the escape hatch as the opt-out, and `shirabe validate --lifecycle .` passes cleanly against the committed corpus.

The single-pr PLAN is ephemeral. The work-on cascade transitions
this PLAN Draft -> Active automatically at first commit, collapses
Active -> Done -> DELETED atomically at the work-completing commit,
and the BRIEF/PRD transition to Done in the same finalization commit.
The DESIGN promotes Accepted -> Planned -> Current across the same
window. The squash-merge erases this PLAN's path from main.
