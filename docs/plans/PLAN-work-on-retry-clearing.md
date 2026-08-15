---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-work-on-retry-clearing.md
milestone: "work-on retry clearing"
issue_count: 4
---

# PLAN: /work-on Retry Clearing

## Status

Active

## Scope Summary

Repairs the retry contract for `/work-on`'s three review phases: a
`blocking_retry` invalidates all three panel artifacts through a command koto
has, and a `context-matches` gate makes the invalidated state un-advanceable.
Adds the harness that drives the shipped text against real koto, wires it into
CI, and updates the evals the contract change touches.

## Decomposition Strategy

Horizontal. The components have clear boundaries and one is a prerequisite for
the rest: a harness that extracts the shipped text cannot be written before the
shipped text exists, and CI cannot register a suite whose script is missing.
There is no integration risk to surface early -- the mechanism was driven end to
end against real koto while the design was being decided -- so a walking
skeleton would buy nothing this ordering does not.

The first issue is deliberately not split further. Converting the gates without
the clearing block is fail-open: the previous round's artifact already contains
`"passed": true` and satisfies the new pattern, so a partial landing silently
reproduces the defect through a different gate type rather than blocking
loudly. Single-pr mode makes the halves land together regardless, but keeping
them in one issue keeps that reasoning in front of whoever works it.

## Issue Outlines

### Issue 1: fix(work-on): invalidate every panel artifact on a blocking retry

**Goal**: A `blocking_retry` raised in any review phase invalidates all three
panel artifacts, and the phases refuse to advance on an invalidated one.

**Acceptance Criteria**:
- [ ] `scrutiny`, `review`, and `qa_validation` in
      `skills/work-on/koto-templates/work-on.md` each declare
      `type: context-matches` with
      `pattern: '(?s)^\{.*"passed" *: *true.*\}\s*$'`, and no `override_default`
      block.
- [ ] Each phase's `passed` transition references `gates.<name>.matches: true`
      in its `when` clause. The `blocking_retry` and `blocking_escalate`
      transitions reference no gate, so both stay reachable when the store is
      what is broken.
- [ ] A comment beside the first converted gate states the separating rule **in
      substance**: that presence-only gating is sound only when the key cannot
      survive from one evaluation of that gate into another, *by any path*, and
      that this is a property of the key rather than of the state. A sentence
      that merely mentions staleness does not satisfy this -- the "by any path"
      clause is what makes the rule correct for `deferral_approval`, whose state
      is entered once and whose key still arrives stale.
- [ ] `phase-4a-scrutiny.md`, `phase-4b-review.md`, and `phase-4c-qa.md` each
      carry the clearing block on the `blocking_retry` path, ahead of the
      `koto next` submission, byte-identical below its first line. The loop is
      unconditional -- no `koto context exists ... || continue` guard, which
      would skip a key whose store was transiently unreadable.
- [ ] The block writes the sentinel over all three keys, reads each back,
      compares against the literal it wrote, and on mismatch prints a
      diagnostic naming the key on **stdout** and exits non-zero.
- [ ] Each of the three phase files states that the value written to context
      carries `"passed": true`. `phase-4c-qa.md` currently shows two JSON
      shapes -- the tester's return format without the key and the context-write
      heredoc with it -- and must not leave a reader to guess which the gate
      reads.
- [ ] `phase-4a-scrutiny.md`'s Retry Loop no longer claims a stale artifact
      fails the gate. It states that the invalidation is what makes the gate
      fail. No `koto context remove` survives anywhere in the file.
- [ ] `review-panel-orchestration.md` states specifically that a
      `blocking_retry` invalidates **all three** panel artifacts, not only the
      raising phase's. A sentence saying a retry "affects" or "clears" the
      artifacts without the all-three scope does not satisfy this: the scope is
      the requirement.
- [ ] `review-panel-orchestration.md`'s claim that `override_default` is what
      makes skipping auditable via `koto overrides list` is corrected --
      `built_in_default` already supplies that, and the blocks are gone.
- [ ] `koto template compile skills/work-on/koto-templates/work-on.md` exits 0
      and emits exactly one warning, the pre-existing W3 on
      `skipped_due_to_dep_failure`.
- [ ] `work-on.mermaid.md` is regenerated and matches the edited template.

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/references/phases/phase-4a-scrutiny.md`, `skills/work-on/references/phases/phase-4b-review.md`, `skills/work-on/references/phases/phase-4c-qa.md`, `skills/work-on/references/review-panel-orchestration.md`

### Issue 2: test(work-on): drive the shipped retry contract against real koto

**Goal**: A harness that runs the text the phase files and template ship, so an
edit that breaks the contract fails a test rather than a production run.

**Acceptance Criteria**:
- [ ] `skills/work-on/scripts/retry-clearing_test.sh` extracts the clearing
      block from the shipped phase file and the gate definitions from the
      shipped template at run time. The extraction marker is `blocking_retry`,
      not `koto context add` -- both blocks in each phase file contain the
      latter.
- [ ] **The drift assertion runs first, and all three of its checks are
      persisted in the shipped script.** It extracts the sentinel from the phase
      file, drives the shipped template's gate with that value through real
      koto, and asserts the state holds.
- [ ] **The two mutation checks are derived at run time inside
      `retry-clearing_test.sh` and asserted on every run**, not demonstrated
      once by hand. The script builds a mutated-sentinel variant and a
      mutated-pattern variant from the shipped text itself and asserts each one
      *fails*, alongside the baseline pass. A harness shipping only the baseline
      satisfies the extraction clause and still cannot catch a later edit that
      lets the sentinel and the pattern re-agree -- which is the fail-open drift
      this case exists for, so a one-time manual proof leaving no trace in the
      committed script does not satisfy this criterion.
- [ ] All three shipped heredoc payloads advance their phase, including
      `qa_validation`'s, which carries no `round` field.
- [ ] The sentinel holds each phase on `passed`, and koto's response names the
      phase's gate with `matches: false`.
- [ ] The traversal is exercised from all three entry points: a retry raised in
      `qa_validation`, in `review`, and in `scrutiny`.
- [ ] The `scrutiny`-raised retry exits 0 with the other two keys never written,
      and leaves all three holding the sentinel.
- [ ] An unreadable key is caught, not skipped: with one key file `chmod 0444`,
      the block exits non-zero and names it. A variant carrying
      `koto context exists ... || continue` passes every other case and fails
      this one.
- [ ] A failed clear prints on stdout with stderr redirected to `/dev/null`, and
      the diagnostic says which outcome not to submit.
- [ ] Both failure exits stay reachable with the gate failing.
- [ ] The harness exits 0 with a loud SKIP when koto is absent, so the bash 3.2
      floor leg can run it.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/scripts/retry-clearing_test.sh`

### Issue 3: ci(work-on): run the retry-clearing suite

**Goal**: CI runs the harness on Linux against a real koto, and on the bash 3.2
floor for portability.

**Acceptance Criteria**:
- [ ] `.github/workflows/check-work-on-scripts.yml` runs
      `skills/work-on/scripts/retry-clearing_test.sh` on Linux, installing tsuku
      and the project tool manifest to get koto the way
      `check-execute-scripts.yml` does.
- [ ] The macOS leg runs the suite through
      `scripts/check-bash-floor.sh --backend system work-on`.
- [ ] The workflow triggers on changes to `skills/work-on/scripts/**` and to
      `scripts/check-bash-floor.sh`.
- [ ] `scripts/check-bash-floor.sh` registers a `work-on` suite in `SUITES`,
      `suite_scripts()`, and `suite_workflow()`. `suite_needs_shirabe()` is left
      alone -- the harness drives koto only and never invokes `shirabe`.
- [ ] `scripts/check-bash-floor_test.sh` passes. Adding `work-on` to its
      hardcoded suite list extends coverage; it is not a relaxed assertion, and
      the suite passes with or without the addition.
- [ ] **The workflow is observed running, not just written.** A real run of
      `check-work-on-scripts.yml` on this PR is green, and its run URL or log
      excerpt is recorded in the PR description. Every other criterion here is a
      static check on YAML and shell, which a typo, a wrong step order, or a leg
      that silently no-ops would satisfy without the suite ever executing.
- [ ] **A failing harness turns the job red.** The workflow step invokes
      `bash skills/work-on/scripts/retry-clearing_test.sh` directly, with no
      `continue-on-error:` and no `|| true` swallowing its exit status --
      checked by grep against the workflow, and by running the harness locally
      with one assertion deliberately broken and confirming it exits non-zero.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `.github/workflows/check-work-on-scripts.yml`, `scripts/check-bash-floor.sh`, `scripts/check-bash-floor_test.sh`

### Issue 4: test(work-on): update and run the evals for the changed contract

**Goal**: `/work-on`'s evals describe the contract the skill now has, and the
suite has actually been run.

**Acceptance Criteria**:
- [ ] Every eval assertion naming the review phases' gate or retry behaviour
      matches the new contract. `review-panel-passed` asserts a
      `context-exists` gate today and must not still say so.
- [ ] `scrutiny-blocking-retry-entry` asserts that the retry invalidates all
      three panel artifacts, not only scrutiny's.
- [ ] `scripts/run-evals.sh work-on` has been run by an agent with
      `/skill-creator` loaded, and **its output is pasted verbatim into the PR
      description** -- the full pass/fail summary, not a claim that it passed.
      Without a durable artifact the run is unauditable after the fact.
- [ ] **Any failing assertion is named in the PR description as a finding, and
      cross-referenced to a filed issue or an explicit callout, separately from
      the assertion-text updates the first two criteria mandate.** This
      separation is the whole point: those two criteria *require* editing
      assertion text, so from the committed diff alone a reviewer cannot tell a
      legitimate contract update from a failing assertion quietly rewritten to
      match a buggy implementation. The two look identical in the diff and must
      not look identical in the record.
- [ ] `scripts/check-evals-exist.sh` still passes, and is not treated as a
      substitute for the run.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/evals/evals.json`

## Implementation Sequence

**Critical path**: Issue 1 → Issue 2 → Issue 3.

Issue 1 gates everything. It is the only issue that changes behaviour, and both
of the others read what it wrote -- the harness extracts the shipped text, and
CI runs the harness.

**Parallelization**: Issue 4 can run alongside Issues 2 and 3 once Issue 1
lands. It touches only `skills/work-on/evals/evals.json`, which no other issue
writes, so there is no conflict to sequence around.

**Ordering note that is not a dependency.** Issue 3 is blocked by Issue 2 for a
mechanical reason rather than a logical one: `check-bash-floor.sh`'s self-test
asserts every registered script exists, so registering the suite before the
script lands fails a test that has nothing to do with this work.
