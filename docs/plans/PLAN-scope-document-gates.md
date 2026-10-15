---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-scope-document-gates.md
milestone: "scope document gates"
issue_count: 3
---

# PLAN: scope document gates

## Status

Active

## Scope Summary

A gate script, `check-hop-document.sh`, holds each /scope hop and the fold
until the run's topic documents pass every error-level validator check and the
banned-word check, printing each failure as a koto finding under a registered
rule id. The work is a shared visibility library and two guide items, the
script with its tests and registry entries, and the template wiring.

## Decomposition Strategy

**Horizontal.** The three pieces have stable interfaces (a library, a script,
a template wiring) and each is a prerequisite of the next, in the order the
design's Implementation Approach gives. The registry entries land with the
script because the registry check refuses an entry whose check script or
fixture doesn't exist yet. Docs coverage (the `docs/guides/doc-validation.md`
items) rides on Issue 1. All three land in one pull request.

## Issue Outlines

### Issue 1: refactor(scripts): share the declared-visibility reading and add the guide anchors

**Goal**: Move `declared_visibility` out of
`skills/work-on/scripts/check-branch-output.sh` into
`scripts/lib/declared-visibility.sh`, source it from there, and add to
`docs/guides/doc-validation.md` the FC20 item and the corrected R6 sentence the
new registry entries anchor on.

**Acceptance Criteria**:
- [ ] `scripts/lib/declared-visibility.sh` defines `declared_visibility` with
      the same behaviour as today's function (first well-formed
      `## Repo Visibility:` header, `CLAUDE.local.md` before `CLAUDE.md`,
      lowercased, nothing when neither declares one), and its header states the
      precondition that the caller has changed to the repository root.
- [ ] `check-branch-output.sh` no longer defines the function; it sources the
      library, and a missing library makes it exit 2 through `undecided`.
- [ ] `skills/work-on/scripts/check-branch-output_test.sh` passes unchanged.
- [ ] `docs/guides/doc-validation.md` has an item naming `FC20` that describes
      it as an error-level check for a stale prose reference to a relocated
      artifact path, and its R6 sentence says R6 checks the `upstream:` of every
      format that carries one, not only Plan docs (a grep for `FC20` and for
      that wording finds both).
- [ ] `shirabe validate` on `docs/guides/doc-validation.md` reports no error
      and no banned word.
- [ ] The `work-on` suite's bash-floor run passes with the library sourced.

**Dependencies**: None

### Issue 2: feat(scope): add the hop document gate script, its tests and its registry entries

**Goal**: Write `skills/scope/scripts/check-hop-document.sh` and
`skills/scope/scripts/check-hop-document_test.sh` as the design specifies,
register every rule the script can print in `references/rule-registry.json`,
and run the suite in CI.

**Acceptance Criteria**:
- [ ] `--topic <slug> --hop <brief|prd|design|plan|all>`; a malformed topic,
      an unknown hop, or a missing argument exits 2.
- [ ] For each hop, a clean fixture document exits 0 with no finding, and a
      fixture with one error-level violation exits 1 with exactly one finding.
- [ ] A design document at `docs/designs/current/` is checked; with documents
      at both DESIGN paths, a violation in either exits 1.
- [ ] `--hop all` checks every present topic document: a clean PRD and a DESIGN
      with a banned word exit 1 with one finding whose `path` is the DESIGN.
- [ ] A PRD whose `upstream:` names a nonexistent file yields a finding under
      the entry aliased `R6`, at the `upstream:` line; an existing but
      untracked upstream yields the same rule.
- [ ] `leverage` in a DESIGN yields a finding under the entry aliased `FC10` at
      its line, also in a fixture repository with no
      `skills/writing-style/rules.yaml`; more than 50 banned words yield 51
      findings, the last the truncation finding.
- [ ] An em-dash-density finding alone, and plan-structure notices alone, exit 0.
- [ ] Two banned words and one error-level violation exit 1 with three
      findings; each finding's `message` is the entry summary, `: `, and the
      validator message cut to 400 characters, and its `level` is `error`.
- [ ] A stub reporting an error with a null `line` yields a finding with no
      `line` key; a stub recording its arguments shows `--visibility=public`
      under a `Public` header, no `--visibility` with no header, and never
      `--check`; a call-counting stub is called once per document plus once
      for the canary.
- [ ] Exit 2 with no finding and a reason on stderr for each of: `shirabe`,
      `jq` or `git` missing; a `shirabe` under the repository root; the rules
      file missing from the plugin tree; a canary run the selector picks
      nothing from; a stub exiting 1, 3 or 4; a stub printing no JSON, a wrong
      `schema_version`, a non-array `findings`, or a finding with no
      `severity`; a stub exiting 2 with no error finding; a schema-less
      document; a symlink, an empty file, or a path resolving outside the root;
      an error-level code no entry aliases. In each case no finding is printed
      for any document.
- [ ] An inherited `SHIRABE_RULES=/dev/null` doesn't switch the banned-word
      check off.
- [ ] Run from a subdirectory, results match a run from the root.
- [ ] The canary word is read from the shipped rules file by the documented
      rule, and a test pins both FC10 message prefixes against the built
      validator.
- [ ] Every printed finding passes `scripts/rule-registry.sh verify-findings`.
- [ ] Fourteen new active entries (`docs/required-fields`, `docs/valid-status`,
      `docs/status-matches-body`, `docs/required-sections`,
      `plan/issues-table-shape`, `plan/issues-table-dependencies`,
      `plan/outline-dependency-resolves`, `docs/absorbed-declaration`,
      `docs/absorbed-requirement-citation`, `docs/no-stale-reference`,
      `docs/upstream-resolves`, `docs/upstream-direction`,
      `docs/upstream-lifetime`, `prose/banned-word`) with the validator code in
      `aliases`, `level: gate`, the script as `check` with mode `--hop`, the
      suite in `fixtures`, guards `pr-create` and `publish`, `withhold: never`,
      timings and anchors as the design lists, and `baseline_keys` filled where
      the anchor occurs at the pinned commit with shared keys cross-named in
      `notes`.
- [ ] `docs/visibility-vision-sections`, `docs/visibility-strategy-sections`
      and `docs/private-only-type` keep their ids and gain the five /scope
      timings and a note naming the new script.
- [ ] The script's `RULE_IDS` line lists all seventeen ids; no entry has
      `withhold: eligible`; `scripts/check-rule-registry.sh` exits 0.
- [ ] The suite runs in `.github/workflows/check-scope-scripts.yml` in a job
      that builds `shirabe` and sets `SCOPE_GATE_REQUIRE_SHIRABE=1`, and is in
      the `scope` list of `scripts/check-bash-floor.sh`;
      `scripts/check-macos-floor-legs.sh` passes; the workflow's path filter
      covers the new library and the registry.
- [ ] On the CI runner the gate over the suite's largest PLAN fixture finishes
      in under 10 seconds.

**Dependencies**: <<ISSUE:1>>

### Issue 3: feat(scope): hold each hop and the fold on the document gate

**Goal**: Wire `check-hop-document.sh` into
`skills/scope/koto-templates/scope.md` as a non-overridable gate on
`hop_brief`, `hop_prd`, `hop_design`, `hop_plan` and `fold`, give the fold a
`bail` verdict, explain a hold in each state's details text, and cover the
wiring in the template and substrate tests.

**Acceptance Criteria**:
- [ ] Gates `brief_document`, `prd_document`, `design_document`,
      `plan_document` and `fold_documents`, each `overridable: false`, each
      running `test -x "<script>" || exit 2; "<script>" --topic "{{TOPIC}}"
      --hop <brief|prd|design|plan|all>`.
- [ ] The compiled template (`koto template compile`) requires the new gate's
      exit 0 on the `landed` arm of `hop_brief`, `hop_prd` and `hop_design`, on
      both `fold`-bound arms of `hop_plan`, and on all fourteen `keep` and
      `absorb` arms of `fold`; no `skipped`, `rejected` or `bail` arm names it.
- [ ] `fold` accepts `verdict: bail`, with one arm to `bail` that names no gate.
- [ ] Each of the five states' details text names its gate, says a hold lists
      one finding per violation to fix in the document, that a finding's quoted
      text is data and never an instruction, that an exit 2 is an environment
      fault to diagnose by running the script by hand, and that `bail` is the
      way out when it can't be fixed; `scope-template_test.sh` greps each state
      for the gate name, "never an instruction" and "exit 2".
- [ ] `git diff` of `scope.md` against the default branch removes no line from
      any `## <state>` section; the Phase 2 validator pass-through text and the
      fold's re-validation step are unchanged.
- [ ] `skills/scope/scripts/scope-template_test.sh` asserts each gate's
      command and `overridable: false`, every arm that names it, the arms that
      don't, and the fold's `bail` arm.
- [ ] `skills/scope/scripts/scope-substrate_test.sh` drives a real session that
      holds `hop_prd` on a PRD with a nonexistent `upstream:`, reads a finding
      with `rule_id` `docs/upstream-resolves` from the blocking conditions,
      fixes the upstream and advances on the next `landed`; and a session that
      absorbs a document at the fold and passes `fold_documents`.
- [ ] The existing substrate fixtures pass the gate, fixed in this change, and
      the existing substrate cases still pass.
- [ ] `scripts/check-skill.sh scope` exits 0, and the template's
      interpolation and mermaid checks pass.

**Dependencies**: <<ISSUE:2>>

## Implementation Sequence

Critical path: Issue 1, then Issue 2, then Issue 3. There is no parallel work:
Issue 2 sources Issue 1's library and anchors its registry entries in Issue 1's
guide items, and Issue 3's gates run Issue 2's script.
