# PRD Discover: doc-vs-github-state-reconciliation (FC09)

Inline research summary -- no Agent tool inside team context. The
research-lead investigation collapsed to direct file reads because the
BRIEF is just-Accepted and every framing question is already settled.

## Inputs Read

- `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md` (Accepted)
- `docs/prds/PRD-table-diagram-reconciliation.md` (FC07 PRD, Done) -- shape precedent
- `docs/designs/current/DESIGN-table-diagram-reconciliation.md` (Decision 6 / class-vs-Status precedent)
- `docs/prds/PRD-roadmap-plan-standardization.md` (parent PRD)
- `docs/designs/DESIGN-roadmap-plan-standardization.md` (parent DESIGN, Decision 3 staging)
- `docs/plans/PLAN-roadmap-plan-standardization.md` (row #153 already scheduled)
- `crates/shirabe-validate/src/validate.rs` (is_notice site value:
  `matches!(code, "SCHEMA" | "FC07")` -- promotion seam already
  documented in doc-comment)
- `references/issues-table.md` (Status column, strikethrough, profile
  rules, FC05/FC06/FC07 binding)
- `references/dependency-diagram.md` (Status classes done/ready/blocked,
  pipeline-stage classes, custom-mnemonic external nodes,
  three edge variants)
- GH issue #153 (canonical acceptance criteria text)
- `wip/handoff-fc09.md` (implementation handoff with phase plan)

## Findings That Bind Requirements

### 1. The is_notice membership seam already exists

`validate.rs::is_notice` is a `matches!(code, "SCHEMA" | "FC07")`
arm-shaped match expression. FC09 adds one arm; promotion removes that
arm. Identical seam shape as FC07 used. Doc-comment on the function
already calls out "promotion seam" language.

### 2. Sub-check binding to corpus state

- Plan profile (issue-keyed): row key `#n` binds to diagram `I<n>`.
  Strikethrough on the entity row signals doc-claims-done.
- Roadmap profile (feature-keyed): Issues column carries `#n` links;
  `Status` column carries `Done`/`In Progress`/`Not Started`/`needs-*`.
  A row whose Status is `Done` signals doc-claims-done.
- Status classes (`done`/`ready`/`blocked`) are the only diagram
  classes FC09 reconciles. Pipeline-stage classes
  (`needsDesign`/`needsPrd`/`needsSpike`/`needsDecision`/`needsPlanning`/
  `needsExplore`/`tracksDesign`/`tracksPlan`) are ignored, matching
  FC07's behavior.
- Custom-mnemonic external nodes (id not matching `^I[0-9]+$`) are
  excluded from FC09's reconciling subset, matching FC07.

### 3. Cross-repo references

`references/issues-table.md` documents `owner/repo#N` in Dependencies
cells. Per the BRIEF, FC09 fetches issue state from the named repo when
the token has access; on 403/404, FC09 emits a per-row skip notice and
continues. This is one of the four self-disable paths.

### 4. PR-context plumbing

GitHub Actions sets `GITHUB_REF` to `refs/pull/<N>/merge` on
`pull_request` events; FC09 parses `<N>` from there or accepts a
dedicated `SHIRABE_PR_NUMBER` override. `GITHUB_REPOSITORY` gives the
current repo. `GITHUB_TOKEN` is the auth surface.

### 5. Sub-check C asymmetry

The BRIEF (Journey 3) settles that Sub-check C fires in both
directions:

- PR body says `Closes #N` but doc shows row #N as `ready` (PR
  over-claims relative to doc).
- Doc shows row #N as `done` but no `Closes #N` line in the PR body
  (doc anticipates closure no PR is delivering).

### 6. Bounded-iteration / SECURITY surface

- Defensive parsing on every GH response (no panic on malformed JSON,
  missing fields, unexpected schemas, unexpected status codes).
- Single retry with back-off then self-disable on 429.
- Explicit timeout on every network call; no unbounded loops.
- Token never logged or echoed to stdout/stderr.

These map to a single non-functional requirement (mirrors FC07 R10
shape).

### 7. Public-cleanliness re-statement

FC07's PRD re-stated R22 as its own R12 to bind implementers writing
notice messages. FC09 should mirror this -- the four self-disable
notice strings and per-defect notice strings are exactly the surface
where private-repo refs could leak otherwise.

### 8. Parent PLAN row already exists

`PLAN-roadmap-plan-standardization.md` row #153 ("feat(validate): add
fc09 doc-vs-github state reconciliation as a notice") is scheduled,
blocked-by #119 (FC07). No new row in the parent PLAN -- that's done.

### 9. Sub-DESIGN ground rules

Items the BRIEF explicitly leaves open for the sub-DESIGN:

- Transport (`gh api` subprocess vs raw HTTP).
- Exact notice message strings.
- Specific timeout values.
- Test fixture mechanism (trait-mock vs recorded fixtures).
- Module layout (e.g. `gh.rs`).

The PRD must NOT pre-commit any of these. It binds the contract (auth,
offline behavior, rate-limit tolerance, defensive parsing, no panics,
token never logged, trait-shaped client surface) and hands the
implementation choices downstream.

## Open Questions

None -- the BRIEF settles all framing. The /prd workflow's normal
"surface open questions in Phase 3" produces an empty section that we
omit (per `references/prd-format.md`: Open Questions is optional and
must be empty/removed before Accepted).

## Requirement Outline (target for Phase 3)

Functional requirements (target ~12, mirroring FC07's R1..R12 density):

- R1: Three sub-checks in one check, dispatched in plan + roadmap arms.
- R2: Sub-check A (doc-claims-done vs GH).
- R3: Sub-check B (doc-claims-open vs GH).
- R4: Sub-check C (PR body `Closes` vs doc, both directions).
- R5: GitHub client surface as a trait, no transport binding.
- R6: Authentication via `GITHUB_TOKEN` or `gh auth status`.
- R7: PR-context detection from env (GITHUB_REF / SHIRABE_PR_NUMBER).
- R8: Self-disable -- missing credentials.
- R9: Self-disable -- missing PR context (C only; A and B still run).
- R10: Self-disable -- rate-limit exhausted after one retry.
- R11: Self-disable -- per-row cross-repo 403 / 404.
- R12: Notice-level shipping via `is_notice` membership.
- R13: Promotion-to-error seam (one-line membership change).
- R14: Per-defect notice messages in FC05/FC06/FC07 voice.

Non-functional requirements:

- R15: Bounded behavior over arbitrary external input (defensive
  parsing, bounded retries, explicit timeouts, no panics, no unbounded
  loops, token never logged).
- R16: Reuse of existing validation infrastructure (no new binary, no
  parallel pipeline, single new module under shirabe-validate).
- R17: Public-visibility cleanliness of surfaced rules and messages.

Acceptance criteria: ~28-30 binary checkbox criteria (one per requirement
clause), mirroring FC07's 26-criterion density adjusted for FC09's
larger surface (four self-disable paths add ACs).

Decisions and Trade-offs (target 4-6):

1. Three sub-checks in one check, not three checks (mirrors FC07
   Decision 1).
2. Notice-level via existing `is_notice` membership, not new staging
   (mirrors FC07 Decision 2).
3. Self-disable on missing substrate, not hard-fail (graceful
   degradation posture).
4. Client surface as a trait, transport deferred to sub-DESIGN.
5. Public-cleanliness re-stated as an FC09-scoped NFR (mirrors FC07
   Decision 4).
