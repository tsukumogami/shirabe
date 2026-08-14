---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: "Upstream Link Legality"
issue_count: 7
upstream: docs/designs/DESIGN-upstream-link-legality.md
---

# PLAN: Upstream Link Legality

## Status

Active

## Scope Summary

Declare each artifact type's lifetime class and legal-parent set on
`FormatSpec`, enforce both properties in `shirabe validate` under two new check
codes, and change the skills so the chain stops producing the links the rule now
forbids — with the roadmap pointer moving from the brief to the plan so the
cascade still finds the roadmap it updates and deletes.

## Decomposition Strategy

Horizontal, in the layering the design already describes: declarations, the
check that reads them, the prose that has to agree with them, the skill
contracts, then the evals and fixtures that pin the new behaviour.

The alternative was a walking skeleton — a thin slice through the empty
brief parent set, the direction check, and `/brief`'s recording change. It was
rejected because there is no integration risk to surface early. The check is a
pure function over two basenames, the skill changes are contracts rather than
components, and the design's own sequencing note says the first two steps are
independent of the rest. A skeleton would front-load ceremony to de-risk a
runtime interaction that does not exist.

**Execution mode: single-pr.** There is no hard constraint forcing several PRs —
one repository, no landing order, no merge gate — so the question is whether any
split delivers independent value.

One does, on paper: Issues 1, 2 and 3 land a working legality check with the
prose agreeing, which is observable on its own. What defeats it is the window it
opens. With Issue 4 unlanded, `/brief` still writes a roadmap upstream, so
between the two PRs the chain produces documents that the validator it just
shipped rejects at error severity. A split whose first half makes the second
half's normal output illegal is not two increments; it is one change with a
regression window in the middle. Single-pr is the documented default, and
nothing here clears the bar to leave it.

## Issue Outlines

### Issue 1: Declare each artifact type's lifetime and legal parents

**Goal**: Add the two declarations to `FormatSpec` so legality is a structural
property of a type rather than prose, and enforce the durable-names-working
prohibition against the declarations themselves.

**Acceptance Criteria**:
- [x] `FormatId` enum with one variant per format and a display form for
      messages, defined in `formats.rs` and separate from `FormatSpec::name`,
      whose casing the format dispatch depends on.
- [x] `Lifetime` enum with `Durable` and `Working` variants.
- [x] `FormatSpec` carries `id`, `lifetime`, and `legal_upstream`, and all eight
      literals are populated per the design's table: VISION names VISION;
      STRATEGY names VISION; ROADMAP names STRATEGY; BRIEF names nothing; PRD
      names BRIEF; DESIGN names PRD and BRIEF; PLAN names DESIGN, PRD, BRIEF and
      ROADMAP; COMP names nothing.
- [x] A test asserts no format whose lifetime is `Durable` lists a `Working`
      format in `legal_upstream`, and fails when one is added.
- [x] A test asserts all eight lifetime classes and all eight parent sets
      verbatim, and fails on a single changed entry in any row.
- [x] A test asserts the new lifetime field agrees with the terminal-status map
      in `lifecycle.rs` on the five types they both cover, with a comment naming
      the new field as the legality authority.
- [x] `cargo test --workspace` passes with no existing test modified, and no
      document's validation result changes — nothing reads the declarations yet.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/formats.rs`

### Issue 2: Enforce upstream legality in `shirabe validate`

**Goal**: One check function reads both declarations and reports an illegal
upstream entry at authoring time, with the lifetime finding taking precedence
over the direction finding on an entry that violates both.

**Acceptance Criteria**:
- [x] One check function takes the document and its spec, walks the `upstream:`
      field through the shared normalizer in `upstream.rs`, resolves each
      target's type from its basename, and emits at most one finding per entry.
- [x] `R10` reports a direction violation and names the resolved type pair;
      `R11` reports a lifetime violation and names the offending value and the
      target's Working class. Neither code is `R5` or `FC99`.
- [x] An entry violating both properties produces exactly one finding, the
      lifetime one.
- [x] An entry whose target basename matches no artifact prefix produces no
      finding. A cross-repo `owner/repo:path` value is judged on its file
      component when that names a known prefix.
- [x] Every entry of a multi-valued `upstream:` is reported independently, each
      finding carrying the field's line number as the resolution check's
      findings already do.
- [x] Both codes are selectable with `--check`, and the CLI's valid-codes
      message names them.
- [x] The check is called from `validate_file`, after the schema gate and after
      the private-only gate. Every golden-corpus fixture's frozen expected
      output is byte-identical — the fixture that carries a durable-names-working
      edge is protected by the schema gate and must stay protected.
- [x] The eight documents named in `docs/prds/PRD-upstream-link-legality.md`
      R24 produce exactly the findings that table predicts, and no other
      document under `docs/` changes its findings.
- [x] A document whose `upstream:` names a `VISION-` or `STRATEGY-` basename is
      judged without that file being read from disk.
- [x] `is_known_check_code` gains exactly the two new codes, and no format's
      required-section list changes.
- [x] `shirabe validate --lifecycle . --mode=draft` exits 0 and emits the same
      single orphan notice it emits before the change.
- [x] `cargo test --workspace` passes with no existing test modified.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/validate.rs`, `crates/shirabe-validate/src/lifecycle.rs`, `crates/shirabe/src/main.rs`, `crates/shirabe/tests/cli.rs`

### Issue 3: Correct the references that name a roadmap as a durable type's parent

**Goal**: Make the prose agree with the declarations, so no reference documents
a shape the validator now rejects.

**Acceptance Criteria**:
- [x] Neither `references/pipeline-model.md` nor
      `skills/prd/references/prd-format.md` documents a ROADMAP as a legal
      upstream for a PRD or a DESIGN. The BRIEF case belongs to Issue 4, which
      owns the brief format reference, and the repo-wide sweep belongs to Issue
      6, the last issue to touch a reference file.
- [x] `references/pipeline-model.md` states the lifetime rule positively — a
      link runs from the shorter-lived document to the longer-lived one — and
      says that the crossing from the strategic chain into the tactical one is
      recorded on the PLAN alone.
- [x] The nearest-produced rule survives with the roadmap case removed: a PRD
      written with no brief above it omits the field rather than reaching past
      it.
- [x] `shirabe validate --lifecycle . --mode=draft` still exits 0.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: docs
**Files**: `references/pipeline-model.md`, `skills/prd/references/prd-format.md`

### Issue 4: `/brief` reads its roadmap and records nothing

**Goal**: A brief grounded in a roadmap carries the framing and not the link,
and the skill says why rather than leaving a flag that writes nothing
unexplained.

**Acceptance Criteria**:
- [x] `/brief` Phase 0 carries a read-versus-record section modelled on
      `/strategy`'s, giving the reason as what a brief is — a type whose legal
      parent set is empty — rather than what it was handed.
- [x] Both roadmap input routes survive: the positional mode and the
      `--upstream` flag, both still loading the roadmap and deriving the
      problem and outcome candidates from the feature entry.
- [x] The produced brief carries no `upstream:` field, and the run announces
      that the field was omitted and why.
- [x] The `ROADMAP-` basename check stays on both routes, re-justified: with
      nothing reaching frontmatter, it is now the only guard against a
      wrong-type input.
- [x] The tracked-by-git check is dropped from the flag, and the canonical path
      is confined to `<root>/docs/roadmaps/` — the constraint the positional
      mode already carries.
- [x] `skills/brief/references/brief-format.md` no longer documents a ROADMAP
      as the brief's upstream, and states that a brief carries no `upstream:`
      field.
- [x] The two `skills/brief/evals/evals.json` scenarios that assert the brief
      declares a roadmap upstream are rewritten to assert grounding without a
      recorded field, and to grade that the run announced the omission and its
      reason.

**Dependencies**: None

**Type**: docs
**Files**: `skills/brief/SKILL.md`, `skills/brief/references/brief-format.md`, `skills/brief/references/phases/phase-0-setup.md`, `skills/brief/references/phases/phase-1-discover.md`, `skills/brief/references/phases/phase-2-draft.md`, `skills/brief/evals/evals.json`

### Issue 5: `/plan` gains `--upstream`, and its pre-flight reads sequences

**Goal**: The plan becomes the node that records a roadmap, validated with the
full record-time check set, and the pre-flight script stops silently skipping
its upstream check when it meets a sequence.

**Acceptance Criteria**:
- [x] `/plan` accepts `--upstream <path>`, parsed before the positional
      argument, never used to derive the topic slug, rejected when bare or
      repeated.
- [x] The value is validated in this order: cross-repo discrimination first,
      then canonicalization with symlink resolution and a bounds check against
      the working tree, then confinement to `<root>/docs/roadmaps/`, then the
      `ROADMAP-` basename, then the `wip/` and tracked-by-git rejections, then
      the private-upstream omission. Running the filesystem checks before the
      cross-repo discrimination would reject every cross-repo roadmap and make
      the visibility check unreachable for exactly the values it governs.
- [x] The private-upstream omission rule is stated in `/plan`'s own contract, so
      a standalone invocation runs the check the chain-driven path performs.
- [x] The produced plan records the design first and the roadmap second in a
      sequence-valued `upstream:`.
- [x] `validate-plan.sh` enumerates sequence entries instead of skipping the
      check, applies the existing status gate to the tactical entry, accepts a
      roadmap entry at Active, canonicalizes the target and rejects one that is
      out of root or a symlink, and passes every path after `--`.
- [x] The Phase 7 hygiene step's prose specifies its per-entry invocation
      quoted and after `--`; it does so unquoted and without a terminator today.
- [x] New `validate-plan_test.sh` cases cover both written shapes of the field
      and the roadmap-at-Active pass. No existing case is modified.
- [x] A `/plan` eval asserts the flag is recorded and the topic slug still comes
      from the positional argument.

**Dependencies**: None

**Type**: code
**Files**: `skills/plan/SKILL.md`, `skills/plan/references/phases/phase-7-creation.md`, `skills/plan/scripts/validate-plan.sh`, `skills/plan/scripts/validate-plan_test.sh`, `skills/plan/evals/evals.json`

### Issue 6: Route the roadmap to `/plan`, and fix `/explore`'s roadmap handoff

**Goal**: A chain run under a roadmap grounds its brief in it and records it on
its plan, and the one live path that hands a vision to `/roadmap` stops
producing an illegal link.

**Acceptance Criteria**:
- [x] `/scope`'s child-argument table carries `--upstream <roadmap-path>` on the
      `/plan` row, and its `/brief` row says the roadmap grounds the framing and
      is not recorded.
- [x] `/scope` Phase 0 confines the flag's canonical path to
      `<root>/docs/roadmaps/`, matching what `/brief` and `/plan` enforce, so no
      chain accepts a path at the parent that a child then rejects.
- [x] The pre-authoring notice no longer says the chain will attach the brief to
      the roadmap. The sentence is committed twice in
      `phase-1-discovery.md` and once in `skills/scope/evals/evals.json`; all
      three change together.
- [x] `/scope`'s durable artifact record names the roadmap the chain consumed,
      so a run that ends before its plan does not lose it with the state file.
- [x] `/explore` passes no `--upstream` value to `/roadmap` that is not a
      STRATEGY. A roadmap's only legal parent is a strategy, and `/roadmap`'s own
      contract already forbids substituting a vision for one.
- [x] A `/scope` run supplied with a roadmap produces a chain in which no
      durable artifact names it and the produced plan does, and where the run's
      consolidation absorbs the brief, the surviving PRD is left with no
      `upstream:` field rather than the roadmap's path.
- [x] The repo-wide sweep holds: no file under `references/` or
      `skills/*/references/` documents a ROADMAP as a legal upstream for a
      BRIEF, a PRD, or a DESIGN. Language describing a roadmap as a grounding
      *input* is not a violation and is expected to remain — the sweep is about
      what a document records, not what a skill reads.

**Dependencies**: Blocked by <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>

**Type**: docs
**Files**: `skills/scope/SKILL.md`, `skills/scope/references/phases/phase-0-setup.md`, `skills/scope/references/phases/phase-1-discovery.md`, `skills/scope/references/phases/phase-2-chain-orchestration.md`, `skills/scope/references/phases/phase-3-exit-finalization.md`, `skills/scope/evals/evals.json`, `skills/explore/references/phases/phase-5-produce-roadmap.md`, `references/cross-repo-references.md`, `skills/vision/references/vision-format.md`, `skills/strategy/references/phases/phase-3-structural-fill.md`, `skills/roadmap/SKILL.md`, `skills/roadmap/references/roadmap-format.md`, `skills/strategy/references/strategy-format.md`, `skills/charter/references/phases/phase-2-chain-orchestration.md`

### Issue 7: Cascade fixtures and the execute eval

**Goal**: Prove the cascade reaches the roadmap through the new route, and that
a corpus authored before this change still cascades through the old one.

**Acceptance Criteria**:
- [x] A new-shape fixture chain exists in which the plan carries the roadmap and
      no durable node does.
- [x] The execute eval's full-chain cascade scenario runs against it and asserts
      the roadmap feature's status is updated and the roadmap is deleted under
      the same conditions the current eval expects.
- [x] The old-shape fixtures — the cascade brief that names a roadmap and the
      short-chain design that names one directly — are kept unchanged as the
      evidence that the chain walkers stayed type-agnostic, and a scenario
      asserts that chain still reaches the roadmap.
- [x] No eval outside the five named in `docs/prds/PRD-upstream-link-legality.md`
      R22 changes. Fixtures added here are deliverables under R23 and are not
      counted against that list.

**Dependencies**: Blocked by <<ISSUE:6>>

**Type**: task
**Files**: `skills/execute/evals/evals.json`, `skills/execute/evals/fixtures/{briefs,prds,designs,plans,roadmaps,scenarios}/`

## Implementation Sequence

Two chains run in parallel from the start and join at Issue 6.

The validator chain is Issue 1 to Issue 2, and it is the critical path: Issue 2
is the largest single piece of work and the only one whose diff has to be
measured against a named list of documents. Issue 3 also hangs off Issue 1 but
is prose and can land alongside Issue 2 rather than after it.

The skills chain has two independent heads. Issue 5 is independent of
everything above it because the flag and the pre-flight script concern what a
plan records rather than what the declarations say. Issue 4 is independent too:
it owns the brief format reference outright rather than waiting on the sweep, so
the brief's whole surface — contract, format, evals — moves in one issue.

Issue 6 is where the strands join. It routes the roadmap to the flag Issue 5
built, reworks the brief entry Issue 4 changed, and carries the repo-wide sweep
that asserts a condition over the references Issue 3 corrected — so it waits on
all three. Issue 7 needs Issue 6, because the new-shape fixture is the shape
Issue 6 produces.

After Issue 1, three strands run in parallel: Issue 2, Issue 3, and the pair
Issue 4 and Issue 5, which depend on nothing. Issue 6 waits on all three of
Issue 3, Issue 4 and Issue 5 — on Issue 3 because its repo-wide sweep asserts a
condition over the references Issue 3 corrects. Issue 2 and Issue 5 are the two
that carry real risk — Issue 2 against golden-corpus byte parity, Issue 5
against a validation gate that is currently silent — so neither should be
sequenced last, where a surprise would have nowhere to go.
