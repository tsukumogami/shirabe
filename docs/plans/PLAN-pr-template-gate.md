---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-pr-template-gate.md
milestone: "PR-template conformance gate"
issue_count: 4
---

# PLAN: pr-template-gate

## Status

Active

Single-pr decomposition of DESIGN-pr-template-gate. The four issues ship on
one branch and one PR; the implementing agent works the outlines in
dependency order. On completion the PLAN is deleted and the chain finalizes
(BRIEF/PRD to Done, DESIGN to Current) per the single-pr lifecycle.

## Scope Summary

Implement the `shirabe validate --pr-body` offline mode (three mechanical,
code-fence-aware checks: Conventional Commits title, one `---` separator with
a non-empty Part 1, no AI-attribution footer), state the rule once in a
shirabe-owned reference the skills cite, and wire a path-independent
`pull_request` CI gate that runs the mode against any PR. The mode mirrors the
existing `--coordination-body` static check; the CI workflow mirrors
`lifecycle.yml`. The boundary is fixed by the DESIGN: only the three
mechanical checks are gated, and subjective Part 2 section selection stays
advisory in the downstream PR-creation skill, which is not modified.

## Decomposition Strategy

**Horizontal, by layer.** The DESIGN names three batches; the mechanical
grouping rule is "one issue per layer that can be reviewed and tested on its
own." The validator mode (library check plus CLI wiring plus unit tests) is
one atomic issue because the dispatch and the check are tested together. The
single-source reference and the skill citations are separate issues so the
authority lands before the citations point at it. The CI workflows are last so
the gate goes live only once the mode exists — the PR that ships them
self-tests the gate on its own body.

Cross-issue edges: two. I3 depends on I2 (the citations point at the
reference); I4 depends on I1 (the workflow runs the mode). I1 and I2 are
independent roots and can proceed in parallel.

## Issue Outlines

### I1: feat(validate) add the --pr-body mode

**Goal**: Add the `shirabe validate --pr-body <file> [--pr-title <string>]`
offline mode implementing the three mechanical checks from the DESIGN
(PB1 Conventional Commits title; PB2 exactly one code-fence-aware `---`
separator with a non-empty Part 1; PB3 no AI-attribution footer), mirroring
the `--coordination-body` static check.

**Acceptance Criteria**:

- `crates/shirabe-validate/src/pr_body.rs` exposes
  `pub fn check_pr_body(body: &str, title: Option<&str>) -> Vec<PrBodyFinding>`
  and `pub struct PrBodyFinding { line, message }`, re-exported from `lib.rs`.
- A shared helper yields top-level lines with fenced code blocks removed
  (CommonMark fences: three-or-more backticks or tildes with an optional info
  string, closing only on a bare same-marker line; the two marker families do
  not cross-toggle). PB2 and PB3 scan only top-level lines.
- PB1 runs only when `title` is `Some`; the issue-number-scope rejection is
  pinned to `^(issue[-_]?)?#?\d+$` (case-insensitive) so `issue-tracker` is
  not over-matched.
- `--pr-body` is added to `ValidateArgs` with `conflicts_with` declared
  explicitly for `lifecycle`, `lifecycle_chain`, `merge_gate`, and
  `coordination_body`; a run-time guard rejects positional files; `--pr-title`
  without `--pr-body` is a tool-error.
- `run_pr_body_mode(file, title, format)` renders `human`/`json`
  (`shirabe-pr-body/v1`) like `run_coordination_body_mode`, and the
  `annotation` arm emits the fileless `::error::<message>` form.
- Unit tests cover every case: well-formed pass; non-conventional title fail;
  issue-number-scope fail; missing separator fail; more-than-one separator
  fail; empty Part 1 fail; attribution-footer fail; docs-only minimal Part 2
  pass; and a body with `---`/`Co-Authored-By:` shown inside a code fence that
  still passes.
- `cargo build` and `cargo test --workspace` pass.

**Dependencies**: None

**Type**: code

**Files**: `crates/shirabe-validate/src/pr_body.rs`,
`crates/shirabe-validate/src/lib.rs`, `crates/shirabe/src/main.rs`.

### I2: docs add the pr-body-conformance reference

**Goal**: Author `references/pr-body-conformance.md`, the single shirabe-owned
authority stating the mechanical rule (PB1-PB3) that the validate mode
implements and the skills cite.

**Acceptance Criteria**:

- The file states the three gated checks in prose, names `shirabe validate
  --pr-body` as their enforcement, and scopes itself to the mechanical rule
  (pointing at the downstream PR-creation skill's reasoning framework for
  advisory Part 2 selection).
- It records the issue-number-scope pattern and the fenced-only carve-out
  with its two accepted residuals (top-level literal footer/`---`; indented
  code blocks).
- Public-visibility clean; no banned writing-style words; no `wip/` path
  references.

**Dependencies**: None

**Type**: docs

**Files**: `references/pr-body-conformance.md`.

### I3: docs single-source /execute and /work-on to the reference

**Goal**: Point `/execute` and `/work-on` at `references/pr-body-conformance.md`
for the mechanical rule and remove the dangling cross-plugin pointer.

**Acceptance Criteria**:

- `skills/execute/koto-templates/execute.md` cites
  `references/pr-body-conformance.md` for the mechanical checks and no longer
  points at the nonexistent `skills/pr-creation/SKILL.md`; its inline Part
  1/Part 2 assembly guidance stays.
- `skills/work-on/references/phases/phase-6-pr.md` cites the reference for the
  mechanical checks (the subjective section-selection guidance still defers to
  the project's PR-creation skill).
- The `/execute` evals asserting the old `skills/pr-creation/SKILL.md`
  citation are updated to the new reference.
- The downstream `tsukumogami:pr-creation` skill is NOT modified.
- No remaining path-shaped reference to `skills/pr-creation/SKILL.md` in the
  shirabe repo.

**Dependencies**: I2

**Type**: docs

**Files**: `skills/execute/koto-templates/execute.md`,
`skills/work-on/references/phases/phase-6-pr.md`,
`skills/execute/evals/evals.json`.

### I4: ci add the reusable pr-body workflow and self-caller

**Goal**: Wire the path-independent CI gate: a reusable workflow that runs the
`--pr-body` mode against a PR, and a self-caller on this repo's PRs.

**Acceptance Criteria**:

- `.github/workflows/pr-body.yml` declares `on: workflow_call`, builds
  `shirabe` from source at the called workflow's ref (mirroring
  `lifecycle.yml`), fetches the PR title and body via `gh pr view --json
  title,body`, writes the body to a temp file, passes the title via an env
  var (never a `${{ }}` expression in the run script), and runs `shirabe
  validate --pr-body "$BODY_FILE" --pr-title "$PR_TITLE" --format annotation`.
- `.github/workflows/validate-pr-body.yml` invokes it on `pull_request` with
  `types: [opened, edited, reopened, synchronize, ready_for_review]` and no
  `paths:` filter.
- All actions are SHA-pinned; permissions are `contents: read` +
  `pull-requests: read` only.
- The PR shipping this work self-exercises the gate and the check is green on
  a well-formed body.

**Dependencies**: I1

**Type**: task

**Files**: `.github/workflows/pr-body.yml`,
`.github/workflows/validate-pr-body.yml`.


## Implementation Sequence

**Critical paths:** I1 → I4 and I2 → I3 (two independent chains of length 2).

**Recommended order:**

1. I1 — the validator mode (the single source everything consumes).
2. I2 — the reference authority (independent of I1; can be authored in
   parallel).
3. I3 — the skill citations (after I2 exists to cite).
4. I4 — the CI workflows (after I1 exists to run).

**Parallelization:** I1 and I2 are independent roots. After I1, I4 opens;
after I2, I3 opens.
