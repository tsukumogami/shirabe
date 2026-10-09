---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-findings-ledger.md
milestone: "Findings Ledger"
issue_count: 6
split_mode_source: none
---

# PLAN: Findings Ledger

## Status

Active

## Scope Summary

Implements the accepted design: `/work-on`'s panel ledger records findings
with ids and checked records, a retry re-verifies only the findings that are
due through one run per panel plus one fix-diff review per retry, and the
panel gate passes only on closing records, printing open findings under
their own rule or the new `panel/open-finding`.

## Decomposition Strategy

**Horizontal.** The work sits almost entirely in one script,
`panel-scope.sh`, with a few satellites (the rule resolver, the retry budget,
the packet builder, the prose that tells the agent what to run). The layers
have stable interfaces between them: the resolver is needed before the gate
prints anything, the ledger's record shape before the planner can compute a
due set from it, and the planner's scope shape before the packet builder can
read it. Building each layer fully, in that order, keeps every intermediate
commit's suites green.

A walking skeleton was considered and rejected: a thin end-to-end slice would
have to stub the ledger's record checks, which are where the design's
guarantees live, and the slice would be rewritten rather than thickened.

## Execution Mode

**single-pr.** The repository's delivery preference is consolidated and no
split branch applies: the ledger, the planner and the gate must change
together (the gate reads what the planner and the recorder write), nothing
needs to reach the default branch before other work can be written, and no
unit is useful to a reader on its own. The registry entry and resolver could
land alone, but they print nothing until the gate uses them.

## Issue Outlines

### Issue 1: feat(registry): resolve any active rule at run time and add panel/open-finding

**Goal**: Give `rule-findings.sh` a declared, allowlisted way to resolve any
active registry id at run time, and register the generic panel rule the gate
will print.

**Acceptance Criteria**:
- [ ] `rf_require_any <id>...` resolves an active id and calls `undecided`
      (exit 2) for an unknown or retired one; `rf_emit` still refuses an id
      the run didn't resolve.
- [ ] `check-rule-registry.sh` passes a script carrying both the
      `RULE_IDS_ANY_ACTIVE=1` marker and an `rf_require_any` call, and fails
      one with either alone or with the marker outside `panel-scope.sh`;
      check 6 still runs on every static `RULE_IDS` line.
- [ ] `references/rule-registry.json` holds `panel/open-finding` with
      `level: gate`, guards `pr-create` and `merge`, `withhold: never`, the
      four panel states as timing, and a text anchor that resolves.
- [ ] `rule-registry_test.sh` and `check-rule-registry_test.sh` pass with
      the counts updated, and no existing entry's `withhold` changes.

**Dependencies**: None

**Type**: code
**Files**: `scripts/lib/rule-findings.sh`, `scripts/check-rule-registry.sh`, `references/rule-registry.json`, `references/rule-registry.md`, `scripts/rule-registry_test.sh`, `scripts/check-rule-registry_test.sh`

### Issue 2: feat(work-on): record findings with ids and checked records in the panel ledger

**Goal**: Make `panel-scope.sh --record` and a new `--mark-fixed` write a
`findings` map of content-id findings with ordered records, deriving the
seat entries the existing readers use, and refusing any write the design's
writer rules don't allow.

**Acceptance Criteria**:
- [ ] A recorded round writes each finding with id (16 hex), panel, severity,
      round, raiser, run, location (`lines`, `file` or `none`), summary and
      records, and each seat entry keeps `verdict`, `judged_at`, `ac_sha` and
      `findings` with `path` and `lines`.
- [ ] The same panel, raiser, path and summary give one id across rounds,
      whatever the whitespace or lines; a change in any of the four gives a
      different id; two findings of one run with the same id are refused
      with a message asking for distinct summaries.
- [ ] Each row of the PRD's record table yields its status, and only
      `reverified` and `dismissed` close; an advisory finding is recorded
      with `raised` and nothing else.
- [ ] An answer naming an id the panel doesn't hold is refused, and a due
      finding the answer omits keeps its status.
- [ ] Each of these is refused with exit 65 and a byte-identical ledger
      (scope files for these cases are fixtures, since `--plan` mints runs
      only from Issue 3 on): a run the scope didn't mint, a run recorded
      twice, an answer for an id the run wasn't planned to answer, a decider
      `reverified` on a reviewer's finding, a `dismissed` from the re-verifier or
      without a reason, a `reverified` without a reason from the re-verifier,
      an inactive or unknown rule id, a malformed id, commit, path, name or
      over-long text, and a decider entry koto's session log doesn't hold or
      whose event already backed an entry.
- [ ] `--mark-fixed` writes only `fixed` records by writer `agent`, refuses an
      unknown or closed id, and never closes a finding.
- [ ] A decider `fail` raises, `pass` closes only that decider's own finding,
      and `escape`, `unanswered`, `not_graded` or an unknown outcome writes
      `unverified`, creating the criterion's finding when none exists.
- [ ] A write that finds the stored `rev` changed since it read the ledger
      exits 69 and stores nothing.
- [ ] `review-shadow.py`'s ledger reader (`test_review_shadow.py`) and
      `review-level.sh report` pass their suites against a ledger the new
      script wrote, and each history entry's `spawned` equals the runs in
      that round's file.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/panel-scope_test.sh`, `scripts/review-shadow/test_review_shadow.py`

### Issue 3: feat(work-on): plan retries over due findings and gate the panel on closing records

**Goal**: Make `--plan` compute each round from findings (full-round
triggers, the due table, one `reverifier` run, the once-per-retry fix-diff
review, minted run ids) and make `--verdict`, `--carried`, `--recorded` and a
new `--open-count` read findings, retiring `panel/blocking-finding`.

**Acceptance Criteria**:
- [ ] Each full-round trigger makes the round full, one case each: a seat
      with no verdict, a ledger with no `findings` key, changed criteria,
      changed plan, a recorded commit off HEAD's history, a dirty tree, no
      commits, a 201-line fix; a 200-line fix doesn't. A full round hands
      each seat its own unclosed findings by id and plans a `reverifier` for
      unclosed findings no seat raised. Every first-round case plans every
      seat `full`.
- [ ] Each cell of the PRD's due table is driven by one case; a finding
      judged at HEAD is not due unless a later `fixed` record asks for it;
      a `lines` finding is touched by an overlapping hunk and not by a hunk
      elsewhere in the file; a regression check answering `holds` re-opens
      the finding and `--verdict` exits 1.
- [ ] A passed seat with no unclosed findings whose cited file the fix
      touched is not spawned in a non-full round.
- [ ] A non-full round with two due findings plans exactly one run carrying
      both ids; one with none due, no fix review and no unclosed blocking
      finding plans no run and `--carried` exits 0.
- [ ] On the fixture with three scrutiny seats each blocking on one finding
      in its own file and a fix touching one file, round two's history
      records `spawned: 1` and its single decision lists exactly the touched
      finding; the same fixture under the previous seat-level rule records 3.
- [ ] The fix-diff review is planned at the first panel with a non-empty
      diff from the newest recorded ancestor commit, never counting an agent
      record (a `--mark-fixed` at HEAD does not empty the diff), and not at
      the next panel once recorded; a full round plans none. A finding it
      raises is `open` under raiser `fix-review` and makes that panel's
      `--verdict` exit 1.
- [ ] `--carried` exits 0 only with every decision `keep` and no unclosed
      blocking finding; with an untouched open finding it exits 1 and
      `--verdict` exits 1 with no run planned.
- [ ] `--verdict` exits 0 when every blocking finding is closed by an allowed
      writer, including when only advisory findings are open; 1 printing one line per open, fixed or unverified finding under
      its own active rule or `panel/open-finding`; 2 on an unrecorded run or
      seat, an unreadable ledger, or a missing `findings` key, winning over
      1; a rule retired after recording prints under `panel/open-finding`.
- [ ] A decider escape in round one with no earlier finding gives `--verdict`
      exit 1 under the criterion's rule id.
- [ ] `--open-count` prints the number of findings `--verdict` printed.
- [ ] `panel/blocking-finding` is `retired` with notes naming
      `panel/open-finding`, and no `RULE_IDS` line or directive names it.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/panel-scope_test.sh`, `references/rule-registry.json`, `references/rule-registry.md`

### Issue 4: feat(work-on): read the retry count from the ledger

**Goal**: `panel-retry-budget.sh` takes no count argument and reads the
round's count through `panel-scope.sh --open-count`, keeping its floor, its
ceiling and its `panel_retries` key.

**Acceptance Criteria**:
- [ ] On one panel's counts 5, 5, 5 it grants two retries and refuses the
      third; on 5, 5, 3 it grants three; a fourth is refused.
- [ ] It refuses a count argument and maps `qa_validation` and
      `light_review` to the ledger's `qa` and `light`.
- [ ] A count it can't read is a refusal, never a grant.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `skills/work-on/scripts/panel-retry-budget.sh`, `skills/work-on/scripts/panel-retry-budget_test.sh`

### Issue 5: feat(review-packet): build re-verification packets by finding id

**Goal**: `review-packet.sh recheck --seat reverifier` lists the due findings
by id with the fix diff and, when the scope plans a fix review, every panel's
blocking criteria; `code` packets list a seat's unclosed findings; the
re-check prompt answers by id.

**Acceptance Criteria**:
- [ ] A `reverifier` decision's packet lists each due finding's id, text,
      location and raiser, and carries `fix review:` and `review from:`
      lines; a bad `review_from` or `fix_diff_from` falls back to the code
      packet's base and says so.
- [ ] With a fix review planned, the packet carries the scrutiny, review and
      QA criteria; without one, it doesn't.
- [ ] A full-round seat's code packet lists that seat's unclosed blocking
      findings by id.
- [ ] The re-check prompt in `review-seat-commissioning.md` asks for `holds`
      or `reverified` per id, with a reason for each `reverified`, and no
      longer says a passing re-check records the seat as passed.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `scripts/review-packet.sh`, `scripts/review-packet_test.sh`, `references/review-seat-commissioning.md`

### Issue 6: docs(work-on): tell the agent how to run, record and mark findings

**Goal**: The phase files, the template's panel directives and the
implementation phase describe the new round file, `--mark-fixed`, the budget
call without a count, and the carried rule, and the shadow workflow re-runs
when `panel-scope.sh` changes.

**Acceptance Criteria**:
- [ ] `phase-4a` to `4d` show the round file with `run` and `answers`, the
      re-verifier's allowed answers, and the budget call without a count; the
      anchor `panel/open-finding` resolves to text in `phase-4a`.
- [ ] `phase-4-implementation.md` tells the agent to run `--mark-fixed` for
      findings it fixed outside their recorded location, after committing.
- [ ] The template's panel directives and comments name `panel/open-finding`
      and the count source, and the template suites
      (`output-gates-routing_test.sh`, `settled-policy_test.sh`,
      `retry-clearing_test.sh`) pass.
- [ ] `check-review-shadow.yml`'s path filter includes `panel-scope.sh`.
- [ ] `scripts/check-skill.sh work-on` passes, and the work-on eval scenarios
      that named seat re-checks describe the new shape.
- [ ] Every suite named in the PRD's R18 runs in CI on the pull request, with
      `panel-scope_test.sh` on the macOS bash 3.2 leg, and every job is green.
- [ ] `scripts/ablation/check-public-content.sh` passes on the branch diff
      and on the pull request body.

**Dependencies**: Blocked by <<ISSUE:4>>, <<ISSUE:5>>

**Type**: code
**Files**: `skills/work-on/references/phases/phase-4a-scrutiny.md`, `skills/work-on/references/phases/phase-4b-review.md`, `skills/work-on/references/phases/phase-4c-qa.md`, `skills/work-on/references/phases/phase-4d-light.md`, `skills/work-on/references/phases/phase-4-implementation.md`, `skills/work-on/koto-templates/work-on.md`, `.github/workflows/check-review-shadow.yml`, `skills/work-on/evals/evals.json`

## Dependency Graph

## Implementation Sequence

**Critical path:** Issue 1, Issue 2, Issue 3, Issue 5, Issue 6.

Issues 4 and 5 can proceed in parallel once Issue 3 lands; both feed Issue 6,
which rewrites the prose after the behaviour it describes exists.
