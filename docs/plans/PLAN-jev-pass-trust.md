---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-jev-pass-trust.md
milestone: "Jev criteria and pass trust"
issue_count: 7
---

# PLAN: Jev criteria and pass trust

## Status

Active

## Scope Summary

Give every Jev criterion a checked slice contract in the rule registry, a
fixture and live bar for pass trust applied only through reviewed registry
changes, a withhold script that withholds a trusted criterion's rule only
where the decider is active, and retire the review-shadow trial's local store,
as `docs/designs/DESIGN-jev-pass-trust.md` sets out.

## Decomposition Strategy

**Horizontal, in the design's order.** The pieces have stable interfaces
between them: the registry's vocabulary, the slice, the contract checker with
the entries it checks, the runner and reader, the withhold script, the
trial's retirement and the guide. Each outline leaves the repository
consistent, and the checker lands in the same outline as every entry it
checks, so CI never sees one without the other. Everything lands in one pull
request.

## Issue Outlines

### Issue 1: feat(registry): admit the decider check kind and the jev contract field

**Goal**: `check-rule-registry.sh` accepts a `check.kind: decider` entry
(template, state, gate, criterion) and a `jev` object on an entry, and
`references/rule-registry.md` documents both.

**Acceptance Criteria**:
- [ ] A registry with a `decider` entry naming an existing template, and a
  `jev` object on any entry, passes `check-rule-registry.sh`; a `decider`
  entry missing `template`, `state`, `gate` or `criterion`, or naming a
  template that doesn't exist, fails it.
- [ ] A `decider` entry at `level: gate` with `guards: ["none"]` and no
  backstop passes check 2, and a `script` gate entry with the same fields
  still fails it.
- [ ] `scripts/check-rule-registry_test.sh` covers each case above, and the
  suite passes on the bash 3.2 floor.
- [ ] `references/rule-registry.md` describes the `decider` kind and the `jev`
  object, pointing at `references/jev-criteria.md`.

**Dependencies**: None

**Type**: code
**Files**: `scripts/check-rule-registry.sh`, `scripts/check-rule-registry_test.sh`, `references/rule-registry.md`

### Issue 2: feat(work-on): give level_fits_facts a typed, complete slice

**Goal**: `review-level.sh slice` prints a typed projection with the level
order line, through a function a new `project <facts-file> <level>`
subcommand shares.

**Acceptance Criteria**:
- [ ] `review-level.sh project <facts> <level>` and `review-level.sh slice`
  print the same bytes for the same facts and level, ending with
  `levels: light < standard < full` and `level: <level>`.
- [ ] A non-integer or negative `lines` or `files` prints as 0, and
  `classes` keeps at most 16 names matching `[a-z0-9_]`.
- [ ] A test pins the exact output for a known facts file, and checks the
  output is under 2,048 bytes for facts with every class the rules file
  defines, every boolean true and 19-digit counts.
- [ ] The gate's command in `work-on.md` is unchanged, and
  `skills/work-on/references/review-levels.md` says the slice carries the
  level order.

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/scripts/review-level.sh`, `skills/work-on/scripts/review-level_test.sh`, `skills/work-on/references/review-levels.md`

### Issue 3: feat(jev-criteria): check every Jev criterion's contract

**Goal**: `scripts/jev-criteria/jev_criteria.py` (`check`, `declared-hash`,
`measure`) holds every Jev entry to its contract, and the registry carries a
contract for `work-on/review-level-fits-facts` and `rs-007` to `rs-017`.

**Acceptance Criteria**:
- [ ] The registry has `work-on/review-level-fits-facts` (untrusted, budget
  2,048, slice script `skills/work-on/scripts/review-level.sh`, at least 100
  measured runs from `measure sessions`, a fixture file) and a `jev` object
  on each of `rs-007` to `rs-017` in the state the PRD's table gives, every
  one of them `withhold: never`.
- [ ] `jev_criteria.py check` passes on the repository and, in tests, fails
  each case the PRD's registry-contract criteria list: a missing field, an
  empty or unknown source, a missing path or heading, a missing measurement,
  a state that contradicts the over-budget share (exactly 5% passes), a
  budget over 2,560 or unequal to `max_bytes`, a gate not running the slice
  script, fewer than 100 runs, an unresolved template, state, gate or
  criterion, a template-declared criterion without an entry or with a
  rejected or blocked one, and an entry that isn't trusted but is
  `withhold: eligible`.
- [ ] Fixture files are checked for R8's minimums, fields and techniques, and
  a test runs `review-level.sh project` on every case's input and fails on a
  slice that differs.
- [ ] The promotion rules hold in tests: a trusted entry fails on any missing
  promotion field, counts that don't add up, a bar not met, a stale
  declaration, slice-script or fixture hash, a fixture run under another
  declaration, a live window starting on or before a false pass or before
  `declared.since`, `trusted_since` unequal to the window end, a non-veto
  mode or `withhold: never`; an untrusted entry fails with a promotion
  record; a false pass fails without its four fields.
- [ ] With `--base`, a removed `jev` object or false pass fails, and a changed
  declaration hash whose `declared.since` is before the merge base's date
  fails.
- [ ] `declared-hash` prints the canonical JSON and SHA-256, and a test pins
  one hash; `measure sessions`, `measure prs` and `measure records` each
  reproduce the figures of a fixture corpus with network calls refused.
- [ ] `references/jev-criteria.md` has a section per criterion, and
  `.github/workflows/check-jev-criteria.yml` runs the tests and `check --base`
  on `pull_request` with read-only permissions and the pinned yq.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Type**: code
**Files**: `scripts/jev-criteria/jev_criteria.py`, `scripts/jev-criteria/test_jev_criteria.py`, `references/rule-registry.json`, `references/jev-criteria.md`, `.github/workflows/check-jev-criteria.yml`

### Issue 4: feat(jev-criteria): run fixtures against Jev and read live figures

**Goal**: `jev_criteria.py fixtures` runs a criterion's fixture file against
Jev with the template's declaration, and `figures` computes the live bar from
koto session logs.

**Acceptance Criteria**:
- [ ] Against a stub endpoint, `fixtures` sends one request per case with the
  template's question, descriptions, label and threshold, prints counts and
  the `fixture_run` JSON, and exits 0 when the bar is met; 1 for one
  seeded-bad pass, one adversarial pass, 7 of 10 good passes or one `error`
  among answered cases; 0 for 8 of 10 good passes otherwise clean.
- [ ] `fixtures` exits 2 and sends nothing without `KOTO_DECIDER_API_KEY`, for
  a criterion no template declares, for a fixture file below R8, for a plain
  http non-loopback endpoint or one with user information, and exits 2 when
  every request fails.
- [ ] `figures` over a fixture log counts a re-written fallback once, a
  fallback followed by a `pass` as answered, an agent-answered tuple as
  unanswered, events outside the window as absent and on its edge days as
  present, and skips and counts a malformed line; `--bar` fails at 29
  evaluations, 4 sessions, 94.9% answered, one `over_budget` fallback and an
  input one byte over budget, and passes at 30, 5 and 95%.
- [ ] The tests replace the network opener with one that refuses every call.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `scripts/jev-criteria/jev_criteria.py`, `scripts/jev-criteria/test_jev_criteria.py`

### Issue 5: feat(jev-criteria): withhold a trusted rule only where the decider is active

**Goal**: `scripts/jev-withhold.sh` prints the withheld copy of a rule file
only when the entry is trusted and the session's decider is active, and the
checker refuses a template that calls it wrongly.

**Acceptance Criteria**:
- [ ] With all of R14's conditions met (stubbed `koto`, a trusted fixture
  registry entry, a clean session log), the script prints a path under
  `<session-dir>/jev-rules/` whose file is the rule file without the rule's
  range; with any one failing alone, it prints the full file.
- [ ] Bad arguments, koto missing or failing, a missing or malformed log, an
  unreadable registry entry, a symlinked session directory and a project
  config mentioning `decider` each print the full file, and the script
  always exits 0.
- [ ] A `decider_fallback` or `decider_check_answered` for the entry's gate
  and criterion makes every later call print the full file; one for another
  criterion of the same gate doesn't.
- [ ] `jev_criteria.py check` fails a template calling the script for a
  non-trusted rule, for a rule of another template, or from a state whose
  directive lacks `rule-registry.sh` `release <id>`; a test fails when any
  file under `skills/`, `koto-templates/` or `hooks/` other than a template
  calls the script; no template calls it.
- [ ] `jev-withhold_test.sh` runs in the workflow on Linux and on the bash 3.2
  floor on macOS.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `scripts/jev-withhold.sh`, `scripts/jev-withhold_test.sh`, `scripts/jev-criteria/jev_criteria.py`, `.github/workflows/check-jev-criteria.yml`

### Issue 6: refactor(review-shadow): retire the trial's local store

**Goal**: `review-shadow.py` keeps only `check` and `scan`, and nothing in a
skill or script writes or reads the review-shadow store.

**Acceptance Criteria**:
- [ ] `review-shadow.py` has no `grade`, `outcome`, `site` or `report`
  subcommand, no Jev client and no code naming `REVIEW_SHADOW_HOME` or the
  store path; its kept slicers still import and run.
- [ ] `panel-scope.sh` no longer starts the site grader, and the `/brief` and
  `/prd` phase 4 files and the `/review-plan` phase 5 file no longer call
  `review-shadow.py`; their tests and evals pass.
- [ ] `review-shadow.py scan` still runs `rs-001` to `rs-006`, and
  `check-review-shadow.yml`'s jobs pass.
- [ ] `docs/guides/review-shadow.md` says the store is retired and points at
  the Jev criteria guide.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `scripts/review-shadow/review-shadow.py`, `scripts/review-shadow/test_review_shadow.py`, `skills/work-on/scripts/panel-scope.sh`, `skills/work-on/scripts/panel-scope_test.sh`, `docs/guides/review-shadow.md`

### Issue 7: docs(jev-criteria): guide to reading figures, promoting and demoting

**Goal**: `docs/guides/jev-criteria.md` tells a maintainer how to read a
criterion's live figures and how to put together a promotion or a demotion
pull request.

**Acceptance Criteria**:
- [ ] The guide has the sections "Reading the live figures", "Promoting a
  criterion" and "Demoting a criterion", and a doc test fails when one is
  missing.
- [ ] "Reading the live figures" states R10's definitions over the exported
  attributes and the `figures` command that computes them from session logs.
- [ ] The promotion section names the reviewer's re-run of `figures --bar` and
  `fixtures`, and that the author doesn't merge their own promotion.
- [ ] `shirabe validate --visibility=public` passes on every document the
  pull request adds or changes.

**Dependencies**: Blocked by <<ISSUE:4>>, <<ISSUE:5>>

**Type**: docs
**Files**: `docs/guides/jev-criteria.md`, `scripts/jev-criteria/test_jev_criteria.py`

## Implementation Sequence

Issues 1 and 2 are independent and come first. Issue 3 needs both: the
registry must admit the new entry before the entry lands, and the entry's
measured figures come from the new slice. Issues 4 and 5 both build on
Issue 3 and can go in either order. Issue 6 waits on Issue 4, because the Jev
client is copied into the module there before the original is removed.
Issue 7 comes last, since the guide describes the commands Issues 4 and 5
ship. The critical path is 1, 3, 4, 6.
