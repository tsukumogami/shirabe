---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-check-lifecycle.md
milestone: "Check lifecycle"
issue_count: 7
---

# PLAN: Check lifecycle

## Status

Active

## Scope Summary

The shirabe half of the check lifecycle: `stage`, `stage_since`, `gates` and
`stage_backstops` on script-checked registry entries, the registry check's
shape, safety, gate and transition rules, stage-aware findings in the shared
library and the five gate scripts, the figures reader, the dispute wrapper,
and the reference that writes the lifecycle down. The koto change the design's
Phase 4 describes ships as its own pull request in `tsukumogami/koto` and is
not an outline here; everything below works on koto 0.20.0.

## Decomposition Strategy

**Horizontal.** The registry fields are the interface every other piece reads,
so they land first; the registry check, the library and the two new scripts
each build on them and don't depend on one another; the gate scripts need the
library; the reference describes what the others built. The components have
stable boundaries (a JSON entry, a sourced library, standalone scripts), so a
walking skeleton would add a throwaway path without lowering any integration
risk. One pull request, since nothing here is useful alone: a stage nobody
honours or a reader with no stage to read are building blocks, not value.

## Issue Outlines

### Issue 1: feat(registry): add stage, stage_since and gates to script entries

**Goal**: Every script-checked registry entry carries `stage`, `stage_since`
and `gates`, and `rule-registry.sh` reads the effective stage.

**Acceptance Criteria**:
- [ ] Every active script entry in `references/rule-registry.json` has `stage:
      block`, `stage_since` set to the landing date and a non-empty `gates`
      list of `<skill>:<state>:<gate>` values matching the templates' command
      gates that run its script; both `status: retired` script entries have
      `stage: retired`; no non-script entry has any of the fields.
- [ ] `rule-registry.sh stage <id>` prints `block` for every active script
      entry, `retired` for the two retired ones, and fails (non-zero) for an
      id with no entry and for a review-shadow entry.
- [ ] Against a test registry, `stage` prints `block` for a script entry with
      no stage, for an unknown stage value, and for an entry guarding
      `pr-create` at `warn` whose `stage_backstops` is missing, names a path
      that doesn't exist, or names its own `check.path`. It prints `block` for
      an entry guarding `pr-create` and `push` at `warn` with an existing,
      distinct backstop for `pr-create` only, and for an entry guarding
      `pr-create` at `warn` whose only backstop names `merge`. It prints
      `warn` when every protected guard has a backstop whose path exists and
      differs from the entry's own check.
- [ ] `rule-registry.sh resolve <id>` prints the same reference, summary and
      effective stage as `ref`, `summary` and `stage`, tab-separated, on one
      line.
- [ ] `scripts/rule-registry_test.sh` covers the cases above and passes.

**Dependencies**: None

**Type**: code
**Files**: `references/rule-registry.json`, `scripts/rule-registry.sh`, `scripts/rule-registry_test.sh`

### Issue 2: feat(registry): check stages, backstops, gates and transitions

**Goal**: `scripts/check-rule-registry.sh` enforces the new fields' shape, the
guarded-rule safety rule, the gate names and the stage transitions against the
merge base.

**Acceptance Criteria**:
- [ ] The check fails on: a script entry with no `stage`, `stage_since` or
      `gates`; a `stage` outside `shadow`, `warn`, `block`, `retired`; a
      non-YYYY-MM-DD `stage_since`; a non-script entry with any new field; a
      `status: retired` entry at another stage; an empty `gates` on an active
      script entry; a malformed `gates` value; `stage_backstops` without
      `notes`, with a `before` outside the protected set or repeated.
- [ ] It fails an active entry guarding `pr-create` at `warn` with no backstop,
      one guarding `pr-create` and `push` with a backstop for `pr-create`
      only, one whose backstop path doesn't exist, one whose backstop path is
      its own `check.path`; it passes one at `retired` whose every protected
      guard has a backstop whose path exists. The withhold rules' results on
      every existing entry are unchanged.
- [ ] It fails a `gates` value whose state isn't in that skill's templates,
      whose gate isn't a command gate of that state, or whose command names no
      script listing the id on its `RULE_IDS` line; it passes the review-panel
      gates for any active rule.
- [ ] With `--base`, it passes: no change; a new entry at `shadow`, `warn` or
      `block`; a base entry with no stage taking `block` (or `retired` when
      its status is retired); shadow to warn; warn to block; block to shadow;
      warn to retired; retired to shadow on an active entry. It fails: shadow
      to block; retired to warn; a new entry at `retired`; a stage change
      whose `stage_since` isn't later than the base's; a status change to
      `retired` with the stage left at `block`; any change to a `status:
      retired` entry's status or stage; an active entry that drops a protected
      guard while leaving `block` in the same change; and an unreadable base
      (exit 2).
- [ ] `scripts/check-rule-registry_test.sh` covers each case and passes on the
      Linux and macOS bash 3.2 legs; the check passes on the repository.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `scripts/check-rule-registry.sh`, `scripts/check-rule-registry_test.sh`

### Issue 3: feat(gates): stage-aware findings in the shared library

**Goal**: `scripts/lib/rule-findings.sh` prints each finding at its rule's
stage level, suppresses retired findings, counts block findings in
`RF_BLOCKING`, and `verify-findings` checks levels.

**Acceptance Criteria**:
- [ ] `rf_require` and `rf_require_any` cache the stage through `rule-registry.sh
      resolve`: a test with a stub `rule-registry.sh` that logs each call sees
      one call per resolved id (today's code makes two).
- [ ] `rf_finding` prints `error`, `warning` or `info` for `block`, `warn` or
      `shadow`, prints nothing for `retired`, increments `RF_BLOCKING` only for
      `block`, and sets `RF_COUNTED`.
- [ ] `rf_emit <json> [<stage-id>]` sets the finding's level from `<stage-id>`'s
      stage (default: its own rule) with the same retired and counting
      behaviour.
- [ ] `rf_dispute_hint` prints one standard-error line naming
      `scripts/rule-dispute.sh` with the session, gate, rule and reason
      placeholders.
- [ ] `rule-registry.sh verify-findings [--stage-source <id>] <log>` fails a
      logged finding whose level doesn't match the stage of its rule, or of
      `<id>` when given.
- [ ] A gate script's suite can run the script against a copy of the registry
      with one named rule set to a given stage, and the existing case where a
      gate hits a `status: retired` rule still exits 2.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `scripts/lib/rule-findings.sh`, `scripts/lib/rule-findings-testlib.sh`, `scripts/rule-registry.sh`

### Issue 4: feat(gates): gate scripts exit on block-stage findings only

**Goal**: The five gate scripts decide their exit from `RF_BLOCKING`, with the
verification route, PR-body fallback and PB4 release, and panel stage source
handled as the design says, and print the dispute hint before failing.

**Acceptance Criteria**:
- [ ] For each of `check-pr-output.sh`, `check-branch-output.sh`,
      `check-verification.sh`, `panel-scope.sh` and `check-hop-document.sh`, a
      test sets a rule it reports to each stage and feeds input breaking it: at
      `block` an `error` finding and today's exit (1, or the verification
      route); at `warn` a `warning` finding and exit 0; at `shadow` an `info`
      finding and exit 0; at `retired` no finding and exit 0.
- [ ] `check-verification.sh --verdict` with a block-stage `command-failed`
      and a warn-stage `needs-person` exits 1.
- [ ] `check-pr-output.sh --pr-body` whose only listed finding is warn-stage
      exits 0 with no `pr-body/conformance` finding; with no listed finding it
      still prints the fallback and exits 1; PB4 at `shadow` releases no text,
      and at `warn` and at `block` releases it once.
- [ ] A koto-driven test on the installed koto (the 0.20.0 floor) runs a
      minimal template whose command gate is a gate script reporting only a
      warn-stage rule; the gate passes and `koto next` advances the session.
- [ ] `panel-scope.sh --verdict` prints a finding citing a warn-stage rule at
      `error` while `panel/open-finding` is `block`, and at `warning` with exit
      0 when `panel/open-finding` is `warn` in a test registry.
- [ ] A script failing on a block finding prints the dispute-hint line on
      standard error; one passing with only warn or shadow findings doesn't.
- [ ] The pre-action hook still denies a PR body breaking PB2 with
      `pr-body/one-separator` at each of the four stages.
- [ ] Every changed script's suite passes, including on the macOS bash 3.2
      leg, and `scripts/check-skill.sh work-on` and `scripts/check-skill.sh
      scope` pass.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-branch-output.sh`, `skills/work-on/scripts/check-verification.sh`, `skills/work-on/scripts/panel-scope.sh`, `skills/scope/scripts/check-hop-document.sh`

### Issue 5: feat(registry): reference reader for the lifecycle figures

**Goal**: `scripts/rule-lifecycle.sh figures [--json] [<file>...]`, a
fixture-tested reference implementation of the figure definitions for tests
and single-host spot checks (never the source of a stage decision, which
comes from log queries over the exported journal), prints each script rule's
evaluations, fires by level, passes, disputes by source, unconverged visits,
window days and the criterion met.

**Acceptance Criteria**:
- [ ] Given fixture journal lines and a test registry, the output matches
      hand-computed values for a rule meeting each of demote, retire, promote
      to warn and promote to block, and one meeting none.
- [ ] Boundaries, each with a fixture just below and one exactly at the bound:
      promote to warn at 99 and 100 evaluations, 13 and 14 days, 26% and 25%
      fires; promote to block at 99 and 100 evaluations, 13 and 14 days, 4 and
      5 fires, disputes at 6% and 5% of fires; demote at 2 and 3 disputes, 6
      and 7 days, disputes at 20% (no) and 21% (yes) of fires; retire at 299
      and 300 evaluations, 55 and 56 days; zero evaluations holds without
      error. Only the at-bound fixture meets its criterion.
- [ ] A rule meeting both demote and promote-to-block's evaluation minimum
      reports `demote`, the first criterion in the table's order; the window
      end is the newest `at` across all input lines, including lines for
      other rules.
- [ ] Records before `stage_since` don't count; evaluations without
      `koto.check.finding_count` don't count; evaluations whose findings were
      cut don't count toward retire; a finding at a gate not in the rule's
      `gates` doesn't count; one session disputing twice counts once; a visit
      with two `error` fires and no passing evaluation is one unconverged
      visit.
- [ ] `--json` prints one object per rule with the same values; standard input
      and several files give the same result as one concatenated file.
- [ ] Run with its inputs in a read-only directory it creates and modifies no
      file; an unreadable input or registry exits 2.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `scripts/rule-lifecycle.sh`, `scripts/rule-lifecycle_test.sh`

### Issue 6: feat(registry): dispute wrapper with a fallback for older koto

**Goal**: `scripts/rule-dispute.sh` records a dispute through `koto disputes
record` when koto has it and as a koto decision otherwise, refusing rule ids
that aren't active registry entries.

**Acceptance Criteria**:
- [ ] It exits 2, recording nothing, for a rule id with no active registry
      entry, a missing `--session`, `--gate`, `--rule` or `--reason`, and
      `--by` other than `agent` or `person`.
- [ ] With a stub koto that has `disputes record`, it passes the session,
      gate, rule, reason and any `--state` and `--by` as separate arguments and
      prints `dispute=journaled`.
- [ ] With a stub koto without it, it runs `koto decisions record` with
      choice `dispute:<rule-id>` and a rationale carrying gate, state, source
      and reason, built so a reason holding quotes, `$()` or JSON reaches the
      record verbatim, and prints `dispute=session-only`.
- [ ] `scripts/rule-dispute_test.sh` covers these with stub koto binaries and
      passes on the bash 3.2 leg.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `scripts/rule-dispute.sh`, `scripts/rule-dispute_test.sh`

### Issue 7: docs(registry): write the check lifecycle down

**Goal**: `references/check-lifecycle.md` states the stages, transitions,
safety rule, figures, thresholds and dispute path, and
`references/rule-registry.md` describes the new fields and links it.

**Acceptance Criteria**:
- [ ] `references/check-lifecycle.md` names all four stages with their gate
      behaviour and level, lists every allowed transition, states the safety
      rule with the protected-action list, defines each figure (evaluations,
      fires by level, passes, disputes by source, unconverged visits, window)
      by record kind, filter fields, grouping and join in the exported
      `koto.*` names, in both the flat form and the nested form a log backend
      shows (`koto.check.name` on `check_evaluated`), says the figures a
      stage-change pull request quotes come from log queries over the
      exported journal, names `scripts/rule-lifecycle.sh figures` as the
      definitions' tested reference for single-host spot checks only, gives
      the threshold table from the PRD
      (`docs/prds/PRD-check-lifecycle.md`) with the same four criteria and
      bounds, and documents
      `scripts/rule-dispute.sh` and `scripts/rule-lifecycle.sh figures`.
- [ ] `references/rule-registry.md` has rows for `stage`, `stage_since`,
      `gates` and `stage_backstops`, explains how `stage` differs from
      `status` and `level`, and links the lifecycle reference.
- [ ] Both files pass `shirabe validate` and the writing-style banned-word
      check, and name no private repository.

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>

**Type**: docs
**Files**: `references/check-lifecycle.md`, `references/rule-registry.md`

## Implementation Sequence

Critical path: Issue 1, then Issue 3, then Issue 4, then Issue 7. Issues 2, 5
and 6 depend only on Issue 1 and can be built alongside Issues 3 and 4. Issue 7
comes last because it describes the interfaces the others settle. The koto
companion pull request is independent of every outline; the floor stays at
koto 0.20.0 until a koto release carries it.

One external precondition: Issues 5, 6 and 7 are written in koto's journal
record names (`check_finding`, `check_disputed`, `koto.finding.level`,
`koto.dispute.source` and the rest), which are provisional until the
measurement owners review them. If the review renames any, those three issues
change with it before the pull request leaves draft. Nothing in this plan adds
a scheduled workflow or an evaluation run.
