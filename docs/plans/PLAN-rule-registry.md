---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-rule-registry.md
milestone: "Rule registry"
issue_count: 4
---

# PLAN: Rule registry

## Status

Active

## Scope Summary

Build the rule registry `docs/designs/DESIGN-rule-registry.md` describes, in one pull request:
the registry and its reader, the four gate scripts moved onto it, the takeover trigger that
releases a rule's text, and the check script and CI job that hold it all together.

## Decomposition Strategy

**Horizontal.** The registry and `scripts/rule-registry.sh` are a prerequisite for everything
else. The gate scripts and the takeover trigger are independent consumers of the helper and
can be built in either order. The check script and its workflow come last, because their
printable-id, fixture and timing checks read what the consumers declare.

The work lands as one pull request: the delivery preference is the default, consolidated, and
no split trigger fires. A registry no script reads, or gate scripts reading a registry no check
guards, wouldn't be useful on its own.

## Issue Outlines

### Issue 1: feat(rules): add the rule registry and its reader

**Complexity**: critical

**Goal**: Create `references/rule-registry.json` with 39 entries (the 21 gate rules and
`rs-001` to `rs-017` under their existing ids, plus `execute/pr-takeover-needs-signal`), each
carrying every field the design lists, with anchors resolved against the current files and
baseline keys computed from the baseline's pinned commit. Add `scripts/rule-registry.sh`
(`ref`, `summary`, `text`, `release`, `verify-findings`) and `references/rule-registry.md`, and
register a `rule-registry` suite in `scripts/check-bash-floor.sh`.

**Acceptance Criteria**:
- [ ] `references/rule-registry.json` parses, has exactly 39 entries, 21 with `level: gate` and 17 with an `rs-` id, and every id in `skills/work-on/scripts/gate-rules.tsv` and `scripts/review-shadow/criteria.json` is the id of exactly one entry.
- [ ] Every entry with a protected guard, and every entry with `check.kind: none`, has `withhold: never`; the 21 gate entries, `rs-001` to `rs-003` and the takeover entry are `never`, and `rs-004` to `rs-017` are `eligible` with guards `["none"]`.
- [ ] `summary <id>` prints the entry's summary and `text <id>` prints its lines; a `plugin.json` version that doesn't match the version pattern gives the revision `unknown`; a scratch repository with a planted clean filter (which runs if git hashes the file through its filters), and a caller environment with `GIT_DIR` pointing elsewhere, still yields the correct revision and runs no planted command, each shown by a test. (The plumbing the reader uses runs no hook or filesystem monitor, so a planted hook or monitor can't make a test fail; those flags stay as defense in depth.)
- [ ] Every entry with an empty `baseline_keys`, or sharing a key with another entry, has a non-empty `notes` naming the reason or the other entries.
- [ ] `rule-registry.sh ref <id>` prints `<path>#L<a>-L<b>@<revision>` where lines a to b are the entry's first to last line; the revision is the 12-character `HEAD` commit in a clean scratch repository, `worktree` when the file differs from `HEAD`, `vX.Y.Z` in a copy with no `.git` and a release version, `<version>+<12-hex blob>` with a `-dev` version, and `<version>` when `git` is missing, each shown by a test in `scripts/rule-registry_test.sh`.
- [ ] Inserting lines above a rule's text in a scratch copy moves the printed range by the same count, with no registry edit, shown by a test.
- [ ] `ref` exits 1 for an unknown id and for a retired id, and 2 for an unsafe path (absolute, `..`, leading `-`, symlink), an id that matches neither id pattern, or an anchor that doesn't resolve, each shown by a test.
- [ ] `release <id>` prints the marker line, the entry's lines byte for byte, and the end marker on standard error and exits 0; it prints one `rule-registry: could not release` line and exits 0 when the registry is unreadable, the path is outside the releasable directories, or the range exceeds 60 lines, each shown by a test.
- [ ] `verify-findings <log>` exits 0 on a log of correct findings and non-zero on a log with an unregistered id or a wrong range, shown by a test.
- [ ] `scripts/check-bash-floor.sh --list` names a `rule-registry` suite that runs `scripts/rule-registry_test.sh`, and the suite passes under bash 3.2. (Issue 4 adds its own test file to the same suite.)

**Dependencies**: None

### Issue 2: refactor(work-on): read gate rules from the registry

**Complexity**: testable

**Goal**: Move `check-branch-output.sh`, `check-pr-output.sh`, `check-verification.sh` and
`panel-scope.sh --verdict` onto the registry: one `RULE_IDS="..."` line each, ids resolved up
front through `rule-registry.sh`, finding lines built with `jq --arg` carrying the computed
`rule_ref` and `summary: detail` messages, and the `SHIRABE_FINDINGS_LOG` hook. Remove
`gate-rules.tsv`, `gate-rule-refs_test.sh` and every mention of the table.

**Acceptance Criteria**:
- [ ] Each of the four scripts has exactly one line matching `^RULE_IDS="[a-z0-9/ -]+"$`, and the union of those lines is the 21 gate ids.
- [ ] Each script's test suite passes, sets `SHIRABE_FINDINGS_LOG`, and ends by running `rule-registry.sh verify-findings` on the log with exit 0.
- [ ] Each suite has one case asserting a `rule_ref` range for one of its rules against the range found independently of the reader (grep on the entry's anchors), a case where the finding helper is called with an id outside `RULE_IDS` and the script exits 2, and a case where a registry copy marks one of its ids retired and the script exits 2.
- [ ] Every finding's `message` starts with the entry's `summary` followed by `: `, and a commit subject or file name holding a control character yields a finding that is one line with the character replaced, shown by a test in `check-branch-output_test.sh`.
- [ ] With a registry copy whose anchor for one of a mode's ids doesn't resolve, the script exits 2 even when the branch has no violation, shown by a test (ids are resolved before checking).
- [ ] `panel-scope.sh --verdict` exits 2 when `panel/blocking-finding` can't be resolved, shown by a test.
- [ ] `skills/work-on/scripts/gate-rules.tsv` and `gate-rule-refs_test.sh` are deleted, this issue removes the deleted test from `.github/workflows/check-work-on-scripts.yml`, and `git grep gate-rules.tsv -- skills scripts references docs/guides CLAUDE.md .github` finds nothing (Issue 4 updates `DESIGN-output-gates.md`).

**Dependencies**: Issue 1

### Issue 3: feat(execute): release the takeover rule when another run's PR is found

**Complexity**: testable

**Goal**: In `skills/execute/scripts/adopt-or-create-pr.sh`'s exit-6 branch, after its existing
line, run `rule-registry.sh release execute/pr-takeover-needs-signal </dev/null >&2 || true`.

**Acceptance Criteria**:
- [ ] In the exit-6 case, `adopt-or-create-pr_test.sh` asserts standard error contains `::shirabe-rule::`, the lines of `skills/execute/koto-templates/execute.md` from the entry's first to last line exactly (the test reads the anchors from the registry and the lines from the template, hard-coding neither), and `::shirabe-rule-end::`.
- [ ] In the exit-6 case, standard output is empty and the exit code is 6, as before.
- [ ] In the exit-0, 2, 3, 4 and 5 cases the test asserts standard error contains no `::shirabe-rule::` line.
- [ ] With the registry path made unreadable in a scratch copy, the exit-6 case still exits 6 with empty standard output, and standard error has the `rule-registry: could not release` line.
- [ ] `skills/execute/koto-templates/execute.md` is unchanged by this pull request.

**Dependencies**: Issue 1

### Issue 4: ci(rules): check the registry on every pull request

**Complexity**: testable

**Goal**: Add `scripts/check-rule-registry.sh` with the eleven checks the design lists,
`scripts/check-rule-registry-adoption.sh` for the one-time comparison with the merge base,
`scripts/check-rule-registry_test.sh`, the workflow `.github/workflows/check-rule-registry.yml`,
path-filter updates to the work-on and execute workflows, and the registry wording in
`docs/designs/current/DESIGN-output-gates.md`.

**Acceptance Criteria**:
- [ ] `scripts/check-rule-registry.sh` exits 0 on the repository at the pull request's head.
- [ ] `scripts/check-rule-registry_test.sh` shows the check exiting 1 on an altered registry for each of: a missing field, an out-of-vocabulary value, an id matching neither id pattern, a duplicate id, a duplicate alias, an alias equal to an id, `none` mixed with another guard, an eligible entry with a protected guard, an eligible entry with `check.kind: none`, a gate entry guarding `none`, a prose entry with a check, a timing naming a state section that doesn't exist, a summary with a control character, a summary with `::`, a missing check path or fixture, a `review-shadow` criterion absent from `criteria.json`, an unsafe path, an anchor found twice, an anchor found zero times, a last anchor before the first, a marker line in a range, an `rs-` id only in the registry, an `rs-` id only in `criteria.json`, a mismatched criterion path, an unregistered `RULE_IDS` id, a malformed `RULE_IDS` line, a released id outside the releasable directories, a released range over 60 lines, a `template-pin.json` commit that isn't 40 hex characters, a malformed baseline key, a baseline key past its file's end at the pinned commit, an unexplained shared key, an unexplained empty key list, a `text.path` outside the workflow's path filter, `gate-rules.tsv` named in a scanned file, a `rule-registry.md` missing the registered-rule definition, and an id removed relative to `--base`.
- [ ] `scripts/check-bash-floor.sh`'s `rule-registry` suite also runs `scripts/check-rule-registry_test.sh`, and the suite passes under bash 3.2.
- [ ] A retired entry whose anchor no longer resolves passes the check, shown by a test.
- [ ] `scripts/check-rule-registry-adoption.sh <base>` passes on this pull request's merge base; in a scratch repository it fails when the head drops an id the base table or criteria file had, removes a line from a span the load manifest loads (a whole file, its body, or a template state section) or from `/execute`'s template, or changes `review-shadow.py`, `test_review_shadow.py` or `criteria.json`; and it prints that it skipped when the base has no `gate-rules.tsv`; each shown by a test.
- [ ] `.github/workflows/check-rule-registry.yml` triggers on `pull_request` with `permissions: contents: read`, its `paths:` include `references/**`, `skills/**`, `scripts/**`, `docs/guides/**`, `docs/designs/current/DESIGN-output-gates.md`, `CLAUDE.md`, `.claude-plugin/plugin.json` and the workflow itself, it checks out with `fetch-depth: 0`, runs both test files and the check with `--base` on Linux and the floor suite on macOS, and runs the adoption script.
- [ ] This issue owns the workflow edits other than Issue 2's removal: `check-work-on-scripts.yml` and `check-execute-scripts.yml` gain `references/rule-registry.json` and `scripts/rule-registry.sh` in both `paths:` lists.
- [ ] `DESIGN-output-gates.md` names `references/rule-registry.json` where it named `gate-rules.tsv`, and its Decision 9 defines a registered rule as an id with a registry entry.
- [ ] Every CI job on the pull request is green.

**Dependencies**: Issue 2, Issue 3

## Implementation Sequence

**Critical path:** Issue 1, then Issue 2, then Issue 4.

**Parallelization:** Issues 2 and 3 both depend only on Issue 1 and touch different files, so
they can be built in either order.

**Recommended order:** 1, 2, 3, 4. Issue 4 runs its check against the finished tree.
