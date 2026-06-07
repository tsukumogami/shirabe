---
schema: design/v1
status: Current
upstream: docs/prds/PRD-lifecycle-draft-ready-discipline.md
problem: |
  The chain-aware lifecycle check landed in the previous increment but
  accepts single-pr-mid-PR as a passing state. CI does not run the check,
  and the work-on cascade does not drive the chain to its terminal at
  ready time. Authors must remember the verify-then-delete sequence from
  memory; CI has no signal when they forget.
decision: |
  Add a `--strict` CLI flag to the validate subcommand that re-routes the
  lifecycle module's single-pr posture computation through the at-merge
  branch (so a present PLAN fails, BRIEF/PRD at Accepted fails). Ship a
  reusable `.github/workflows/lifecycle.yml` workflow that builds the
  shirabe binary from source and invokes the check, with strict mode
  conditional on `github.event.pull_request.draft == false`. Add a
  self-caller workflow with the `ready_for_review` event surface. Update
  the work-on skill template to perform the atomic finalization commit
  (PLAN delete via `git rm`, BRIEF/PRD Done via `shirabe transition`)
  before invoking `gh pr ready`.
rationale: |
  The strict-mode toggle reuses the existing `--visibility` flag pattern,
  the lifecycle workflow mirrors the validate-docs.yml supply-chain
  shape, and the work-on cascade lives where chain orchestration already
  is. The two settled-by-decision questions (strict-mode interface,
  cascade trigger) have separate Decision Records; this DESIGN consumes
  both outcomes and the implementation encodes them.
---

# DESIGN: lifecycle-draft-ready-discipline

## Status

Current

The DESIGN is at Planned while the implementation lands. On chain
completion the file promotes to `docs/designs/current/` at status
Current.

## Context and Problem Statement

The previous increment landed `shirabe validate --lifecycle <root>` —
a chain-aware passing-state check that walks every artifact chain in
the tree and verifies each member is at its passing state for the
chain's posture. The check accepts single-pr-mid-PR as a passing
state, which is correct while an author iterates on a DRAFT PR but
wrong when the PR flips to ready-for-review.

The chain settles into its terminal — PLAN deleted, BRIEF and PRD at
Done, DESIGN at Current — only at PR-merge time, and the
verify-then-delete commit that performs the transitions is the
forcing function that pulls the chain across the line. Without CI
running the check and without the work-on cascade pulling the chain
to its terminal at ready time, the verify-then-delete commit is
optional in practice. The previous two corpus reconciliation PRs
shipped this drift and required after-the-fact correction.

The PRD names 12 requirements (R1-R12) and tags two architectural
alternatives for the DESIGN to settle:

- The strict-mode toggle interface (R2): `--strict` CLI flag,
  `SHIRABE_LIFECYCLE_STRICT` env var, or both.
- The cascade trigger mechanism (R6): `ready_for_review` workflow
  hook, `shirabe finalize` subcommand, or work-on skill template
  intercepting `gh pr ready`.

Both questions are settled out-of-band in Decision Records and the
DESIGN consumes both outcomes (D1 and D2 below). The remaining
design surface is the implementation shape of the strict-mode branch,
the workflow YAML structure, and the cascade's posture-detection
logic in the work-on skill template.

## Decision Drivers

- **Doc-tree-only execution.** The lifecycle check reads the working
  tree alone. The strict-mode branch adds no I/O outside the existing
  doc-tree read.
- **Reuse existing infrastructure.** Strict-mode is one flag on the
  existing CLI; the lifecycle workflow mirrors `validate-docs.yml`'s
  SHA-pinning and binary-build patterns; the cascade reuses `shirabe
  transition` and `git rm` rather than introducing new mutation
  primitives.
- **Single-PR delivery.** The strict-mode flag, the two workflows,
  the cascade template updates, the stale-wording removal, and the
  skill reference updates ship in one PR. The PR is single-pr
  execution mode; the PLAN driving it is ephemeral and deleted at
  finalization.
- **Author-explainable failure messages.** Strict-mode failures
  emit the same `Lnn` family annotations the non-strict mode emits,
  with the posture name in the message; no new check codes.
- **Permissions discipline.** The lifecycle workflow runs read-only.
  No write token, no PR-edit, no branch push.
- **SHA-pinned actions.** All workflow YAML uses commit-SHA pins per
  PRD R5, matching the existing `validate-docs.yml` pattern.

## Considered Options

The DESIGN settles three implementation choices (D3-D5) and points
at two pre-settled decisions (D1-D2).

### Decision 1 (PRE-SETTLED): Strict-mode interface — `--strict` CLI flag

The PRD's R2 left three alternatives open (CLI flag, env var, both).
The choice is settled out-of-band in
[`DECISION-lifecycle-strict-mode-interface-2026-06-06.md`](../decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md).
Outcome: a `--strict` CLI flag on the validate subcommand. Default
off. The CI workflow templates the flag conditionally via a shell
conditional reading `github.event.pull_request.draft`.

The implementation consumes the outcome:

- Add `strict: bool` to the `ValidateArgs` clap struct in
  `crates/shirabe/src/main.rs` with `#[arg(long, default_value_t =
  false)]`.
- Thread the value into `run_lifecycle` and then into the lifecycle
  module's `Config` extension, or as a separate parameter on
  `run_lifecycle_check`.
- In `compute_passing_state` (or an adjacent helper), branch on
  strict mode: when strict is set, `SinglePrMidPR` posture computes
  passing states as if the chain were `SinglePrAtMerge` (PLAN
  Deleted, BRIEF/PRD Done, DESIGN Current).

The other two alternatives were rejected. Env-var-only loses CLI
discoverability and breaks parallel with `--visibility`. Both-flag-
and-env adds API surface and a precedence rule with no proven need.

### Decision 2 (PRE-SETTLED): Cascade trigger mechanism — work-on skill template inline

The PRD's R6 left three alternatives open (workflow hook,
subcommand, in-skill intercept). The choice is settled out-of-band
in
[`DECISION-cascade-trigger-mechanism-2026-06-06.md`](../decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md).
Outcome: the work-on skill template performs the atomic
finalization inline (PLAN delete via `git rm`, BRIEF/PRD Done via
`shirabe transition`, single commit) before invoking `gh pr ready`.
The CI gate (the reusable lifecycle workflow on the
`ready_for_review` event surface) is the safety net.

The implementation consumes the outcome:

- Update `skills/work-on/SKILL.md` and `skills/work-on/koto-templates/`
  with the cascade step.
- The cascade runs `shirabe validate --lifecycle . --strict` to
  identify the violator, performs the transitions, commits, runs
  the check again to verify the passing state, then runs `gh pr
  ready`.

The other two alternatives were rejected. The workflow-hook-only
option leaves the cascade as a "fail-and-fix" loop rather than an
"atomic finalization." The new-subcommand option adds binary
surface with one known consumer.

### Decision 3: Strict-mode branching in the lifecycle module

The strict-mode flag flips the single-pr-mid-PR exemption to
fail. Two implementation shapes are viable:

- **Option A (chosen):** Pass a `strict: bool` into
  `run_lifecycle_check` as a parameter. Inside, when computing the
  posture for a chain, if `strict && posture == SinglePrMidPR`,
  re-target the passing-state computation to `SinglePrAtMerge`.
- **Option B:** Add `strict: bool` to the `Config` struct passed
  through validate's call chain. The lifecycle module reads
  `cfg.strict` in `compute_passing_state` and chooses the at-merge
  branch.

Option A is chosen because it keeps the strict-mode toggle as a
local parameter on the one function that consumes it, rather than
threading a new field through `Config` that's irrelevant to every
non-lifecycle check. The `Config` struct already carries
`custom_statuses` and `visibility` — both consumed by multiple
checks; adding `strict` (consumed by exactly one check) is a
weaker fit.

The shape:

```rust
pub fn run_lifecycle_check(
    root: &Path,
    cfg: &Config,
    strict: bool,
) -> Vec<ValidationError>
```

Call sites: `main.rs::run_lifecycle` passes `args.strict` through.
Tests pass `false` or `true` explicitly.

### Decision 4: Workflow file layout

The PRD R3 specifies a reusable workflow at
`.github/workflows/lifecycle.yml`. The R4 self-caller workflow
needs a separate file name. Two viable layouts:

- **Option A (chosen):** Reusable at `.github/workflows/lifecycle.yml`,
  self-caller at `.github/workflows/validate-lifecycle.yml`. Mirrors
  the existing `validate-docs.yml` / `validate-shirabe-docs.yml`
  pair.
- **Option B:** Reusable at `.github/workflows/lifecycle-reusable.yml`,
  self-caller at `.github/workflows/lifecycle.yml`. Less consistent
  with the existing naming pattern.

Option A is chosen because it matches the existing precedent. A
reader scanning `.github/workflows/` sees `validate-docs.yml` and
`validate-shirabe-docs.yml` together, then sees `lifecycle.yml` and
`validate-lifecycle.yml` together — the pattern is uniform.

### Decision 5: Cascade posture detection in the skill template

The cascade needs to identify chain posture to decide what
transitions to perform. Two viable approaches:

- **Option A (chosen):** Read the PLAN's `execution_mode` and
  `status:` frontmatter fields directly from the working tree (same
  signals the lifecycle module uses). Posture detection lives in
  the skill template's shell logic.
- **Option B:** Add a `shirabe lifecycle posture <plan-path>`
  subcommand that prints the inferred posture. The skill template
  invokes the subcommand and branches on output.

Option A is chosen because it reuses the doc-tree-only contract
without introducing a new binary command. The work-on skill
already does shell-level frontmatter inspection (the existing
template reads `execution_mode` to detect single-pr vs multi-pr);
adding a posture-detection branch on top is straightforward.
Option B has the same "new subcommand with one consumer" problem
the cascade-trigger decision already rejected.

The shape — pseudocode for the skill template's bash conditional:

```bash
PLAN="docs/plans/PLAN-${TOPIC}.md"
EXEC_MODE=$(grep '^execution_mode:' "$PLAN" | awk '{print $2}')
PLAN_STATUS=$(grep '^status:' "$PLAN" | head -1 | awk '{print $2}')

if [ "$EXEC_MODE" = "single-pr" ]; then
  # Single-pr finalization: delete PLAN, Done BRIEF/PRD
  ...
elif [ "$EXEC_MODE" = "multi-pr" ] && [ "$PLAN_STATUS" = "Active" ] && [ <last child closed> ]; then
  # Multi-pr work-completing: Active to Done to deleted, Done BRIEF/PRD
  ...
else
  # Multi-pr intermediate: no-op
  echo "Multi-pr chain in flight; no finalization needed."
fi
```

The "last child closed" condition reads the GitHub milestone
state via `gh api`; this is the same mechanism the existing
work-on template uses for cross-issue context.

## Decision Outcome

The implementation lands four code surfaces in one PR:

1. **`crates/shirabe-validate/src/lifecycle.rs`** — add a `strict:
   bool` parameter to `run_lifecycle_check`. Re-target the
   single-pr posture's passing-state computation when strict is
   set. Update unit tests to cover both branches.

2. **`crates/shirabe/src/main.rs`** — add `#[arg(long, default_value_t
   = false)] strict: bool` to `ValidateArgs`. Thread into the
   `run_lifecycle` call. Reject `--strict` without `--lifecycle`
   (or accept silently — the latter is simpler and the upstream
   precedent for `--visibility` in per-file mode is silent
   acceptance).

3. **`.github/workflows/lifecycle.yml` and `.github/workflows/validate-lifecycle.yml`**
   — the reusable workflow and self-caller. SHA-pinned actions,
   `permissions: contents: read`, shell-conditional templating of
   `--strict` based on `github.event.pull_request.draft`.

4. **`skills/work-on/SKILL.md`, `skills/work-on/koto-templates/*.md`,
   `skills/plan/references/quality/plan-doc-structure.md`,
   `skills/roadmap/SKILL.md` (and references), `skills/plan/SKILL.md`
   (and references)** — the cascade template update, the stale-
   wording removal, and the skill-reference updates per R8 and R9.

Tests at three levels:

- **Unit tests** in `crates/shirabe-validate/src/lifecycle.rs` for
  the strict-mode branches: single-pr-mid-PR fails under strict,
  single-pr at-merge passes under strict, multi-pr in-flight passes
  under strict, multi-pr work-completing fails under strict and
  non-strict, multi-pr mid-transition (PLAN Done, BRIEF/PRD
  Accepted) fails under strict.
- **CLI integration tests** in `crates/shirabe/tests/cli.rs` for the
  `--strict` flag threading: with and without `--lifecycle`, with
  and without `--strict`.
- **Workflow self-caller in CI** runs against the present PR's tree,
  exercising the conditional branch on its own draft state.

## Solution Architecture

### Component layout

```
crates/shirabe-validate/src/
  lifecycle.rs            # run_lifecycle_check(root, cfg, strict)
                          # compute_passing_state(role, posture, strict)
crates/shirabe/src/
  main.rs                 # ValidateArgs.strict: bool
                          # run_lifecycle(root, visibility, strict)

.github/workflows/
  lifecycle.yml           # reusable workflow_call workflow
  validate-lifecycle.yml  # self-caller on pull_request events

skills/work-on/
  SKILL.md                # cascade step documented
  koto-templates/*.md     # cascade step in koto YAML

skills/plan/references/quality/
  plan-doc-structure.md   # stale-wording removal

skills/roadmap/, skills/plan/  # skill reference updates
```

### Data flow

```
GitHub PR opened/synchronized/ready_for_review
  -> validate-lifecycle.yml self-caller triggers
  -> calls lifecycle.yml reusable workflow
  -> reusable workflow:
       checkout caller repo
       checkout shirabe at workflow_sha
       install Rust toolchain
       cargo build --release --bin shirabe
       set STRICT_FLAG based on github.event.pull_request.draft
       shirabe validate --lifecycle . $STRICT_FLAG
       exit code is the job result
```

### Cascade flow (work-on skill template)

```
work-on completes implementation
  -> detect chain posture (single-pr | multi-pr work-completing | multi-pr intermediate)
  -> if single-pr or multi-pr work-completing:
       run shirabe validate --lifecycle . --strict  (expect failure naming PLAN+BRIEF+PRD)
       perform atomic finalization (PLAN Active -> Done is an
       ephemeral in-memory flip that bridges to deletion; both modes
       follow the same Active -> Done -> DELETED sequence under the
       unified PLAN lifecycle):
         shirabe transition docs/plans/PLAN-<topic>.md Done    (Active -> Done; in-process)
         git rm docs/plans/PLAN-<topic>.md                      (Done -> DELETED)
         shirabe transition docs/briefs/BRIEF-<topic>.md Done  (if BRIEF exists)
         shirabe transition docs/prds/PRD-<topic>.md Done       (if PRD exists)
       git commit -m "docs: finalize chain (PLAN Active -> Done -> deleted, BRIEF/PRD Done)"
       git push
       run shirabe validate --lifecycle . --strict  (expect pass)
       gh pr ready
  -> if multi-pr intermediate:
       no-op; gh pr ready directly
```

### Strict-mode passing-state table (extension of upstream)

The strict-mode flag only affects the single-pr postures. Multi-pr
postures are unchanged. PLAN docs use a unified Draft -> Active ->
Done -> DELETED lifecycle, identical for single-pr and multi-pr; the
on-disk passing state for a committed mid-PR PLAN is `Active` in
both modes (the Draft -> Active gate auto-fires for single-pr and is
human-approved for multi-pr).

| Posture | Strict | BRIEF passing | PRD passing | DESIGN passing | PLAN passing |
|---------|--------|---------------|-------------|----------------|--------------|
| SinglePrMidPR | off | Accepted | Accepted | Planned/Current | Active |
| SinglePrMidPR | on | Done | Done | Current | Deleted |
| SinglePrAtMerge | off or on | Done | Done | Current | Deleted |
| MultiPrInFlight | off or on | Accepted | Accepted/In Progress | Planned/Current | Active |
| MultiPrWorkCompleting | off or on | Done | Done | Current | Deleted |
| MultiPrAtMerge | off or on | Done | Done | Current | Deleted |

The `SinglePrMidPR + strict` row is the new branch; it reuses the
`SinglePrAtMerge` row's computation. The other rows are unchanged
from the upstream.

## Implementation Approach

Single PR, single commit chain. The PLAN driving this work is
single-pr execution mode; the PLAN itself is ephemeral and is
deleted at the cascade-finalization step.

### Phase 1: Strict-mode flag and lifecycle branch

Land the `--strict` flag, the `run_lifecycle_check` parameter
threading, and the `compute_passing_state` branch. Add unit tests
for the strict-mode shapes named in the PRD's R12. Verify
`cargo build` and `cargo test` pass.

### Phase 2: Workflow YAML

Add `lifecycle.yml` and `validate-lifecycle.yml`. SHA-pin every
action reference using the same SHAs as the existing
`validate-docs.yml`. Set the shell conditional template for the
`--strict` flag. Verify the self-caller triggers on the right
events.

### Phase 3: Cascade template update

Update the work-on skill's SKILL.md and koto templates with the
cascade step. Update the planning-context for the cascade (the
work-on skill already has bash conditionals for execution-mode
branching; extend them).

### Phase 4: Stale-wording removal and skill-reference updates

Remove `docs/plans/done/` wording from
`skills/plan/references/quality/plan-doc-structure.md`. Update
`skills/roadmap` and `skills/plan` skill references to describe the
verify-then-delete terminal, the whole-tree CI gate, and the
DRAFT-vs-READY discipline.

### Phase 5: Self-validate at finalization

Run `shirabe validate --lifecycle .` in both modes against the
final tree. Non-strict passes (the chain is at single-pr-mid-PR
during the PR's life). Strict passes only after the
cascade-finalization commit deletes the PLAN and transitions
BRIEF/PRD to Done.

## Security Considerations

The lifecycle check is read-only; the workflow declares `permissions:
contents: read` per PRD R11. No write token, no PR comment write,
no branch push from the workflow.

The cascade in the work-on skill template uses the same authority
the skill already has — `git`, `gh pr ready`, `shirabe transition`.
The new mutations (`git rm` on the PLAN doc, `shirabe transition`
on BRIEF and PRD) are constrained to the chain's canonical paths
under `docs/`. No path traversal surface.

The SHA-pinned actions in the workflow YAML close the supply-chain
surface the workflow's `uses:` references would otherwise open. The
self-caller invokes the reusable workflow via local relative path
(`uses: ./.github/workflows/lifecycle.yml`); downstream consumers
invoking the reusable workflow externally pin the workflow ref
(`uses: tsukumogami/shirabe/.github/workflows/lifecycle.yml@<sha>`)
per the existing precedent.

The strict-mode flag is a boolean toggle; no user input
interpolation, no shell expansion of user content. The
`STRICT_FLAG` shell variable in the workflow is set by a comparison
against `github.event.pull_request.draft`, which is a documented
GitHub Actions context field. No injection surface.

## Consequences

### Positive

- The DRAFT-vs-READY discipline is enforced at the gesture authors
  make (`gh pr ready`) and at the CI surface that backstops it.
- Future single-pr chains land at their terminal atomically without
  the author having to remember the verify-then-delete dance.
- The corpus no longer drifts after the increment lands; the next
  reconciliation PR — if one ever fires — is caught at PR time
  rather than discovered months later.
- The two settled-by-decision questions have durable Decision
  Records future contributors can read to understand why the
  interface and trigger mechanism are what they are.

### Negative

- The work-on skill template gains a posture-detection branch and a
  finalization step. The template grows in complexity.
- Authors invoking `gh pr ready` directly outside work-on are
  caught only by the CI gate. The cascade is the path of least
  resistance, not the only path.
- Posture detection in the skill template is bash-level and relies
  on grep-against-frontmatter. A future enhancement could move
  this into a `shirabe` subcommand if a second consumer emerges.

### Mitigations

- The bash posture-detection logic in the skill template is small
  enough to read in one screen and tested by the CI self-caller
  exercising its own conditional branch.
- The CI gate is non-optional. Even authors who skip work-on hit
  the strict-mode check on `ready_for_review`.
- The strict-mode flag defaults off, so the upstream non-strict
  invocation behavior (the PR #173 surface) is preserved
  byte-for-byte.

## References

- `docs/prds/PRD-lifecycle-draft-ready-discipline.md` — the upstream
  PRD; R2 and R6 named the two settled-by-decision alternatives this
  DESIGN consumes.
- `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`
  — Decision 1; settles R2 in favor of the `--strict` CLI flag.
- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
  — Decision 2; settles R6 in favor of the work-on skill template
  inline cascade with the CI gate as backstop.
- `docs/designs/current/DESIGN-lifecycle-passing-state-validation.md`
  — the upstream DESIGN; codifies the chain-walker and posture
  inferencer the strict-mode flag filters through.
- `.github/workflows/validate-docs.yml` — the existing reusable
  validator workflow whose SHA-pinning and binary-build patterns the
  lifecycle workflow mirrors.
- `crates/shirabe-validate/src/lifecycle.rs` — the upstream module
  the `--strict` parameter threads into.
- `skills/work-on/SKILL.md` and `skills/work-on/koto-templates/` —
  the surface the cascade template update lands in.
