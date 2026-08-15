---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-plan-preflight-one-validator.md
milestone: "One validator for whether a PLAN may be built from"
issue_count: 6
---

# PLAN: One validator for whether a PLAN may be built from

## Status

Active

## Scope Summary

Collapse the two pre-flight validators that decide whether a PLAN may be built
from into one, and make the survivor's success verdict mean the document was
checked. Closes issues #276 and #285, in that order.

## Decomposition Strategy

**Walking skeleton, ordered by the hole.** The decomposition is driven by one
sequencing constraint the design names as load-bearing: the bash script is the
only thing failing a PLAN whose `schema:` is missing or wrong, and it holds that
job because the CLI declines those inputs silently. So the CLI must hold every
gate the script holds before the script is deleted, and the ordering is
capability-first rather than file-first.

Issue 1 lays the outcome plumbing every later CLI change reports through. Issues
2 and 3 add the two remaining gates in parallel once that exists. Issue 4
records the new contract for consumers. Only when all of those hold is Issue 5
purely subtractive. Issue 6 verifies the whole against the capture taken before
any of it ran.

Horizontal decomposition was rejected: it would have grouped "all Rust changes"
into one issue and "all CI changes" into another, which puts the script deletion
in the same unit as the R6 additions it depends on.

## Issue Outlines

### Issue 1: feat(validate): report an incomplete run for inputs it declined to check

**Goal**: Give `shirabe validate` a fourth run outcome, Incomplete at exit code
4, emitted when an input was routed to a format and then not checked against it,
and surface the same fact as a `skipped` array in the JSON envelope.

**Acceptance Criteria**:
- [x] `ValidateOutcome` carries an `Incomplete` variant whose exit code is 4 and
      whose label is `incomplete`.
- [x] Severity ranking orders Clean below Incomplete, Incomplete below
      Violations, and leaves ToolError and Io above both, so the existing
      highest-rank-wins merge is unchanged in behaviour for the outcomes that
      already existed.
- [x] A `PLAN-*.md` with no `schema:` field exits 4, and its annotation output
      is byte-identical to what it produced before the change.
- [x] A `PLAN-*.md` whose `schema:` is `plan/v2` exits 4, and its annotation
      output is byte-identical to what it produced before the change.
- [x] A run carrying both an error-level finding and a skipped input exits 2.
- [x] A run whose only skipped input was excluded by `--check` selection exits
      0, so selection continues to drive the outcome as the contract states.
- [x] `--format json` emits a `skipped` array with one entry per declined input,
      each naming the file and the reason, derived from the same finding set the
      envelope already renders.
- [x] The three golden parity `.exit` baselines for schema-skipped documents
      hold `4`; their `.stdout` and `.stderr` baselines are byte-unchanged. This
      is the one existing-test modification the design records as a known
      exception, and it is reported in the pull request body rather than made
      quietly.
- [x] `cargo test --workspace` passes, and no `.rs` test file has been edited.

**Dependencies**: None.

**Type**: code
**Files**: `crates/shirabe/src/main.rs`, `crates/shirabe-validate/src/report.rs`

### Issue 2: fix(validate): refuse a lifecycle root with no artifact directory under it

**Goal**: Make `shirabe validate --lifecycle <root>` fail as a tool error when
none of the artifact directories it walks exists beneath the root, instead of
indexing zero documents and reporting a clean tree.

**Acceptance Criteria**:
- [x] The six-entry artifact-directory list inside the doc-index walk is a
      module-level constant, and a public predicate answers whether any of them
      exists beneath a given root, so the list has one source.
- [x] `shirabe validate --lifecycle docs` run from the repository root exits 1
      and prints a message naming the root and what was expected beneath it.
- [x] `shirabe validate --lifecycle .` run from the repository root indexes the
      corpus and exits 0 under `--mode=draft`.
- [x] A root that carries the artifact directories but no documents in them
      still reports clean, because an empty corpus is a legitimate state and a
      mistyped root is not.
- [x] `cargo test --workspace` passes, and no existing test file has been
      edited.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/lifecycle.rs`

### Issue 3: feat(validate): absorb the upstream symlink and tree-containment refusals into R6

**Goal**: Move the two refusals only the bash script performs into the CLI's
existing upstream-resolution check, so deleting the script drops no coverage.

**Acceptance Criteria**:
- [x] An `upstream:` entry whose resolved target is a symbolic link is refused
      under `R6`, with the entry named in the message.
- [x] An `upstream:` entry whose canonical path resolves outside the working
      tree is refused under `R6`, with the resolved location named in the
      message.
- [x] A refused entry produces exactly one finding rather than falling through
      into the git-tracking branch and producing a second.
- [x] A cross-repo `owner/repo:path` entry is skipped by both new refusals, as
      it already is by the resolution check, because it names no local path.
- [x] Every golden parity baseline is byte-unchanged, because each fixture
      carrying an `upstream:` names a target that does not exist relative to the
      fixture working directory and so returns at the existing finding.
- [x] `cargo test --workspace` passes, and no existing test file has been
      edited.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/checks.rs`

### Issue 4: docs(cli): record the incomplete outcome in the multi-consumer contract

**Goal**: Teach every document that states the validator's exit-code ladder
about the fourth value, so a consumer reading the contract learns it rather than
discovering it.

**Acceptance Criteria**:
- [x] The exit-code table in the multi-consumer CLI contract guide carries the
      new row and states its position in the severity ordering.
- [x] The guide states that a consumer distinguishing only zero from non-zero is
      unaffected, and that the incomplete outcome means an input was accepted and
      then not checked rather than that a document is defective.
- [x] Every skill reference that enumerates the validator's exit codes names the
      new value, and none is left stating a three-value or four-value ladder that
      omits it.
- [x] The JSON envelope's `skipped` array is documented alongside the findings
      list, named as diagnosis that accompanies the exit code rather than
      replacing it.

**Dependencies**: Blocked by <<ISSUE:1>>, Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `docs/guides/multi-consumer-cli-contract.md`

### Issue 5: refactor(plan): retire validate-plan.sh and route its callers at the CLI

**Goal**: Delete the duplicate pre-flight validator and its test suite, and point
every caller at `shirabe validate` plus `shirabe validate --lifecycle-chain`, so
one implementation answers whether a PLAN may name its upstream.

**Acceptance Criteria**:
- [ ] `skills/plan/scripts/validate-plan.sh` and
      `skills/plan/scripts/validate-plan_test.sh` are absent from the tree.
- [ ] No file in the repository references either path, in prose, in workflow
      configuration, or in a script.
- [ ] The PLAN-docs workflow runs the CLI over each changed PLAN and fails the
      job when it reports a violation, covering both the per-file checks and the
      upstream-status rule.
- [ ] The plan-scripts workflow no longer runs the removed suite on either
      matrix leg, and its remaining suites still run on Linux and under the bash
      3.2 floor.
- [ ] The bash floor runner no longer names the removed suite in its plan group,
      and passes for every suite it still covers.
- [ ] The planning skill's pre-flight step invokes the CLI, and its prose
      describes what the CLI checks rather than what the script checked.
- [ ] The surviving upstream-status rule is the lifecycle model's: a PLAN whose
      upstream DESIGN sits at `Accepted` is refused and one at `Current` is
      accepted, which is the reverse of the retired script on both.

**Dependencies**: Blocked by <<ISSUE:3>>, Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `.github/workflows/check-plan-docs.yml`, `.github/workflows/check-plan-scripts.yml`, `scripts/check-bash-floor.sh`, `skills/plan/references/phases/phase-7-creation.md`

### Issue 6: test(validate): verify the corpus diff against the effects named in advance

**Goal**: Re-run the whole-tree validation captured before any of this work
began, diff it, and confirm every difference is one the design named in advance.

**Acceptance Criteria**:
- [ ] The whole-tree per-file validation is re-run over the same tracked
      document set as the pre-change capture, and the diff is reviewed finding
      by finding.
- [ ] Every difference in that diff corresponds to an effect named in the
      design's Decision Outcome or Consequences, and any difference that does
      not is reported rather than accepted.
- [ ] `shirabe validate --lifecycle . --mode=draft` exits 0 from the repository
      root.
- [ ] The upstream-status decision's predicted corpus effect is confirmed empty:
      no committed PLAN changes verdict, because the only PLAN in the tree
      carries no upstream field.
- [ ] The symlink and containment decision's predicted corpus effect is
      confirmed empty: no document under the docs tree is a symlink and no
      upstream entry resolves outside the working tree.
- [ ] `cargo test --workspace`, `cargo fmt --check`, and the bash floor runner
      all pass.

**Dependencies**: Blocked by <<ISSUE:5>>

**Type**: task
**Files**: `docs/plans/PLAN-plan-preflight-one-validator.md`

## Dependency Graph

_(omitted in single-pr mode -- each outline declares its own dependencies above)_

## Implementation Sequence

**Critical path:** Issue 1 -> Issue 2 -> Issue 4 -> Issue 5 -> Issue 6 (5 issues)

**Recommended order:**
1. Issue 1 -- the outcome plumbing every later CLI change reports through
2. Issues 2 and 3 -- the two remaining gates, independent of each other
3. Issue 4 -- the consumer-facing contract, once both gates exist
4. Issue 5 -- the deletion, purely subtractive by this point
5. Issue 6 -- verification against the pre-change capture

**Parallelization:** Issues 2 and 3 can proceed in parallel once Issue 1 lands.
Everything else is serial, because the ordering constraint the design names is a
capability constraint rather than a file one.
