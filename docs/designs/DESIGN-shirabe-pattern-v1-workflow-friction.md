---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-shirabe-pattern-v1-workflow-friction.md
problem: |
  PRD-shirabe-pattern-v1-workflow-friction binds three independent
  contracts across three pattern-v1 surfaces (the single-pr parser
  in `plan-to-tasks.sh` for tsukumogami/shirabe#156, the `/design`
  and `/plan` Phase-0/Phase-1 status-gates for
  tsukumogami/shirabe#159, and `/work-on`'s plan-orchestrator loop
  plus the `ci_monitor` koto state for tsukumogami/shirabe#162) and
  defers the mechanism choice for each. R12-R13 add a sweep-level
  envelope: no fix may silently change behavior outside the three
  named bugs, and each bug's fix must be independently shippable.
  The design picks one fix candidate per bug from each issue body's
  enumerated options, names the specific files and entry points each
  fix edits, and proves the chosen combination keeps the sweep
  within R12-R13's blast radius.
decision: |
  Three substrate-disjoint fixes ship across three native substrates
  with one shared rename. Bug #156 lands as a loosened regex on
  `plan-to-tasks.sh` line 288 plus an asymmetric-empty-deps stderr
  warning before the `waits_on` resolution loop. Bug #159 lands as
  a sentinel-gated auto-transition branch added before the existing
  hard-stop check in `/design` Phase 0 step 0.2 and `/plan` Phase 1
  step 1.1; the `parent_orchestration:` sentinel (already written
  by `/scope` Phase 2) is the chain-context discriminator that
  preserves R6's direct-invocation protection. Bug #162 lands as a
  combined per-child `worktree_discipline_check` koto state plus a
  `ci_monitor` extension distinguishing DIRTY mergeStateStatus from
  pending checks, plus a rename of
  `references/parent-skill-worktree-discipline.md` to
  `references/worktree-discipline.md` reflecting its
  substrate-agnostic content.
rationale: |
  Substrate-disjointness discharges R12 and R13 directly — the bash
  regex fix cannot reach koto template parsing, the phase-prose
  edit cannot regress the parser, and the koto template edit
  cannot regress `/prd`'s shipped transition behavior. Sentinel-
  gating over unconditional auto-transition is the discriminator
  that lets `/design` and `/plan` match `/prd`'s symmetric handoff
  shape without violating R6's direct-invocation protection: when
  no parent is driving the chain, the sentinel is absent and the
  existing hard-stop fires unchanged. The combined #162 fix
  (worktree-discipline plus DIRTY-distinction) is necessary because
  the BRIEF's catastrophic surface hit both modes; fixing only one
  would leave the other silent-success mode in place. The
  worktree-discipline rename earns its scope by making the
  reference's already-substrate-agnostic content available to
  `/work-on` as a second consumer without re-deriving the rule.
---

# DESIGN: shirabe pattern-v1 workflow friction sweep

## Status

Planned

## Context and Problem Statement

PRD-shirabe-pattern-v1-workflow-friction binds three independent
contracts against the three pattern-v1 surfaces it covers
(`plan-to-tasks.sh` for `tsukumogami/shirabe#156`, the `/design` and
`/plan` Phase-0/Phase-1 status-gates for `tsukumogami/shirabe#159`,
and `/work-on`'s plan-orchestrator loop plus the `ci_monitor` state
for `tsukumogami/shirabe#162`). The PRD's R12-R13 add a sweep-level
constraint pair: no fix may silently alter behavior outside the three
named bugs, and each bug's fix must be independently shippable.

The technical problem this design solves is picking one fix candidate
per bug from the enumerations in the three issue bodies, naming the
specific files and entry points each fix edits, and proving the chosen
combination keeps the sweep within R12-R13's blast-radius envelope.
Three substrate surfaces are in scope:

- **Bash script substrate** for #156. The single-pr parsing path in
  `skills/plan/scripts/plan-to-tasks.sh` lives in shell. Line 288's
  regex `\*\*Dependencies\*\*:[[:space:]]*(.+)$` is the silent-failure
  surface; the multi-line `### Dependencies` accumulator at lines
  312-339 is the surface R3 protects.
- **Skill-phase prose substrate** for #159. `/design`'s Phase 0 lives
  at `skills/design/references/phases/phase-0-setup-prd.md` step 0.2;
  `/plan`'s Phase 1 lives at `skills/plan/references/phases/phase-1-analysis.md`
  step 1.1; `/prd`'s reference behavior is documented in
  `skills/prd/SKILL.md` lines 132-138. The contract is symmetric
  reads against symmetric writes.
- **Koto template + phase prose substrate** for #162. The
  `ci_monitor` state declared at `skills/work-on/koto-templates/work-on-plan.md`
  lines 84-111 (gate command at line 89-90, prose at line 226) is the
  silent-wait surface; the per-issue commit loop in `/work-on`'s
  plan-orchestrator mode (driven by the same koto template) is the
  upstream-drift surface. The substrate-shared reference
  `references/parent-skill-worktree-discipline.md` already defines
  the None/Informational/Intent-changing classification R8 names.

The three substrates do not interact — a fix that edits one shell
regex cannot inadvertently change a koto gate command, and a phase-prose
edit in `/design` Phase 0 cannot regress the single-pr parser. R13's
independent-shippability constraint is therefore substrate-protected
and the design honors it by routing each decision to its native
substrate.

The chain-handoff asymmetry decision (#159) carries the meta-irony
that this `/design` invocation itself was driven by `/scope` against
the same Phase 0 gate the bug names. The handoff worked here only
because `/scope` Phase 2 pre-transitioned the PRD to Accepted before
dispatching `/design` — exactly the operator-side workaround the bug
calls out. The fix needs to make that pre-transition the skill's
contract, not the operator's.

## Decision Drivers

PRD-derived:

- **R12 minimal blast radius.** No fix may silently change behavior
  in surfaces outside the three named bugs. Cited shared infrastructure
  is `transition-status.sh` for `/prd`, but the fix MAY touch shared
  substrate if every touch is documented and called out at review.
- **R13 independent shippability.** Each bug's fix is a separately
  reviewable, separately revertable unit. The design SHOULD NOT
  introduce cross-bug shared code that creates a hard dependency
  ordering.
- **R6 direct-invocation preservation.** The Phase 0 / Phase 1
  hard-stop must remain reachable when no parent-orchestration
  sentinel is present. The fix is parent-chain-shape-only.
- **R7 symmetry direction left open.** The PRD allows alignment in
  either direction (change `/prd` to match `/design`+`/plan`, change
  `/design`+`/plan` to match `/prd`, or introduce a shared helper).
  The design must pick one and justify it.

Implementation-specific:

- **Substrate fidelity.** Each fix lives in its native substrate
  (shell regex, phase-prose markdown, koto gate definition). Cross-
  substrate refactors are rejected unless they pay back beyond the
  sweep's frame.
- **Sentinel-availability assumption.** Bug #159's Option (c) names
  the `parent_orchestration:` sentinel from
  `tsukumogami/shirabe#151` (the child-dispatch-contract work). That
  contract is shipped; sentinel detection is an available primitive.
  Options that depend on it are not speculative.
- **Read-time discoverability.** Future operators inspecting any of
  the three fixed surfaces should see a single clearly-named branch
  that handles the previously-silent case, not a buried conditional.
- **Test-fixture verifiability.** The PRD's ACs are largely grep-
  checkable or executable. The design SHOULD choose fix shapes whose
  presence and behavior the named ACs can verify without DESIGN
  inventing new verification machinery.

## Considered Options

The design decomposes into four decisions. Decisions 1-3 map 1:1 to
the three bug numbers (one fix-shape choice per bug, from the
issue-body enumerations). Decision 4 surfaces from PRD R12-R13: how
to keep the sweep's blast radius minimal across three substrate
touches that could plausibly be unified.

### Decision 1: Fix shape for parser silent-empty-deps (#156)

The line-288 regex in `skills/plan/scripts/plan-to-tasks.sh` matches
`\*\*Dependencies\*\*:[[:space:]]*(.+)$`, which silently misses the
`**Dependencies:**` (colon-inside-bold) authoring form. R1 binds
parser tolerance for both colon placements; R2 binds a signal when
empty-deps coincide with a multi-issue PLAN; R3 protects the
multi-line `### Dependencies` accumulator at lines 312-339.

Key assumptions:

- Line 288 is the silent surface; the `### Dependencies` accumulator
  at line 313 is a separate code path with its own regex and lives
  through any single-line fix unchanged.
- The bash regex engine has cheap inline alternation via `?` quantifiers
  (no backreference issues).
- The single-pr parser is the only consumer of line 288; the
  multi-pr / GitHub-issue-backed parser at lines 104-141 reads a
  table column header (`hcell == "Dependencies"`) and is untouched
  by any line-288 edit.
- Existing PLAN authorship in the wild uses both colon placements;
  the BRIEF cites operator hits during dogfooding (v0.7.0/0.7.1-dev).

#### Chosen: Loosen the regex AND emit an empty-deps warning (combined a+b)

Edit `skills/plan/scripts/plan-to-tasks.sh` at line 288 to match
either colon placement:

```bash
# Detect dependencies line within an issue outline
if [[ -n "$current_number" && "$line" =~ \*\*Dependencies:?\*\*:?[[:space:]]*(.+)$ ]]; then
    current_deps="${BASH_REMATCH[1]}"
    # Remove trailing period
    current_deps="${current_deps%.}"
    continue
fi
```

The regex `\*\*Dependencies:?\*\*:?` accepts four shapes (the two
colon placements named in the bug, plus the trailing-colon-free
`**Dependencies**` and `**Dependencies:**` which the existing engine
already silently re-permits via the optional `[[:space:]]*(.+)$` tail).
Operators who write the regex's pre-fix supported shape continue to
parse identically; the only new behavior is `**Dependencies:**`
(colon-inside) now captures into `BASH_REMATCH[1]`.

For R2's empty-deps signal, add an after-the-loop check after the
parser finishes accumulating outlines but before `waits_on` resolution
at line 448. The check fires when the single-pr issue count is
greater than one AND any issue carries empty deps:

```bash
# R2 signal: empty deps on a multi-issue single-pr PLAN is almost
# always an authoring error. Surface a warning to stderr naming the
# offending issue numbers and the likely cause.
if [[ ${#issue_numbers[@]} -gt 1 ]]; then
    local empty_count=0
    local empty_list=""
    for i in "${!issue_numbers[@]}"; do
        if [[ -z "${issue_deps[$i]}" || "${issue_deps[$i]}" == "None" ]]; then
            empty_count=$((empty_count + 1))
            empty_list="${empty_list:+$empty_list, }${issue_numbers[$i]}"
        fi
    done
    if [[ $empty_count -gt 0 && $empty_count -lt ${#issue_numbers[@]} ]]; then
        echo "[plan-to-tasks] WARNING: empty Dependencies on issue(s) $empty_list of ${#issue_numbers[@]}; check '**Dependencies**:' line formatting (both '**Dependencies**:' and '**Dependencies:**' are accepted)." >&2
    fi
fi
```

The `$empty_count -lt ${#issue_numbers[@]}` guard suppresses the
warning when the PLAN is a strictly-independent multi-issue set (every
issue carries `None`); that's a legitimate authoring pattern, not the
silent-failure case. The warning fires only when SOME issues have deps
and some do not — the asymmetry that indicates the regex previously
dropped edges.

Why this shape:

- **Closes the silent-failure path AND adds a signal even after
  closure.** Option (a) alone fixes the regex but leaves the next
  silent surface — any future regex strictness, any future authoring
  form that escapes the regex — without a warning. Combining (a)+(b)
  pays once for both layers: the regex is permissive AND the asymmetric-
  empty-deps case has a named signal.
- **AC1.1 + AC1.2 + AC2.1 + AC2.2 land on the same surface.** AC1.2
  is a grep against line 288's regex (the loosened form satisfies);
  AC1.1 is an executable test fixture (both colon placements parse);
  AC2.1 is an executable check that the warning fires (the
  asymmetric-empty-deps fixture triggers the stderr line); AC2.2 is
  a judgment-based check that the warning names what to do (the
  warning explicitly cites both colon placements as the likely
  authoring root cause).
- **R3 grep-safe by construction.** The edit is line 288 only; lines
  312-339 are untouched. The after-the-loop signal block is added
  in a new location, not interleaved with the existing `### Dependencies`
  accumulator.
- **No dependency on shared infrastructure.** The change is entirely
  self-contained in `plan-to-tasks.sh`; no edit to any other file
  satisfies #156. R12 blast-radius minimal by construction.

#### Alternatives Considered

- **(a) Loosen the regex only, no warning.** Rejected for partial
  R2 satisfaction. Option (a) alone closes the named silent-failure
  shape (the regex stops dropping `**Dependencies:**` matches) but
  does not satisfy R2's stronger contract that empty-deps on a
  multi-issue PLAN must surface a signal regardless of the cause.
  A future regex regression (someone adds a stricter check; an
  authoring form not anticipated by the loosened regex appears) would
  re-introduce the silent shape with no warning surface. Option (a)
  alone optimizes for minimum diff at the cost of R2's signal-
  durability promise.

- **(c) FC-level validator check enforcing parseable
  `**Dependencies**:` lines.** Rejected on two grounds. First, it
  moves the failure surface from `plan-to-tasks.sh` runtime
  (immediate, where the operator is running the parser) to a
  separate `shirabe validate` invocation that the operator may or
  may not run before invoking `/work-on`. Second, an FC-level check
  would need to encode the same regex tolerance the parser fix
  already adds — duplicating the rule across two enforcement layers
  with no payoff over the runtime warning. The validator path is
  appropriate for whole-doc schema enforcement (PRD R13 in the
  PRD-shirabe-comp-skill design's R7) but the parser-runtime path
  is appropriate for parser-runtime errors. AC2.1's "before parallel
  dispatch step runs" timing is satisfied by either; the runtime
  warning is satisfied by smaller diff.

- **(d) Refactor the single-pr parser to share line-parsing
  infrastructure with the multi-pr GitHub-issue path.** Rejected as
  out-of-scope per R12. The two paths share no parsing
  infrastructure today (the multi-pr path reads a table column at
  lines 104-141, the single-pr path reads issue-outline lines at
  lines 280-340). Unifying them would touch substantial surface
  outside the named bug and would have to absorb the multi-pr path's
  separate testing burden. R13's independent-shippability constraint
  also weighs against — a unifying refactor would couple #156's fix
  to changes the bug doesn't name.

### Decision 2: Fix shape for chain-handoff status-gate asymmetry (#159)

`/prd` SKILL.md lines 132-138 already auto-transitions a Draft BRIEF
to Accepted when invoked with a BRIEF input. `/design` Phase 0 step
0.2 (in `skills/design/references/phases/phase-0-setup-prd.md`) and
`/plan` Phase 1 step 1.1 (in `skills/plan/references/phases/phase-1-analysis.md`)
both hard-stop if their respective upstream is not Accepted. R4 binds
the `/design` handoff, R5 binds the `/plan` handoff, R6 preserves
direct-invocation protection, R7 binds symmetry across all three
skills.

Key assumptions:

- The `parent_orchestration:` sentinel block at `wip/<parent>_<topic>_state.md`
  (per `skills/scope/references/state-schema.md` line 78-83 and
  `skills/scope/references/phases/phase-2-chain-orchestration.md`
  lines 122-135) is the available primitive for detecting "parent
  is driving this invocation". `/scope` writes the block immediately
  before each child invocation and clears it immediately after.
- `/prd`'s existing brief-handoff transition is unconditional on
  sentinel presence — it fires whenever the input is a BRIEF path
  and the brief is Draft, regardless of whether `/prd` was invoked
  by `/scope` or directly. This is a deliberate `/prd`-side contract
  inherited from before the sentinel landed.
- `shirabe transition <path> <status>` is the canonical mechanism
  for status updates (per `/prd` SKILL.md line 143).
- R6 forbids silent auto-promotion under direct invocation; the
  sentinel's presence or absence is exactly the discriminator R6
  needs.

#### Chosen: Sentinel-gated auto-transition in /design and /plan (option c)

`/design` Phase 0 step 0.2 (in
`skills/design/references/phases/phase-0-setup-prd.md`) gains a new
branch that fires before the hard-stop check:

```markdown
### 0.2 Read PRD

Read the PRD file from the path provided in `$ARGUMENTS`. Verify:
- File exists and is a valid PRD (`docs/prds/PRD-*.md`)
- Status is "Accepted"

**Parent-orchestration auto-transition (sentinel-gated).** Before
the status check, look for the `parent_orchestration:` sentinel
block in any `wip/<parent>_<topic>_state.md` file matching the current
topic. When the sentinel is present AND its `invoking_child:` field
is `design` AND the PRD status is `Draft` or `Accepted`, run
`shirabe transition <prd-path> "In Progress"` and proceed. The
sentinel's presence is the explicit signal that a parent drove this
invocation; the auto-transition is the symmetric counterpart to
`/prd`'s brief-handoff. When the sentinel is absent, fall through
to the existing hard-stop check.

If the PRD status is not "Accepted" (and the sentinel was absent or
did not match), STOP and inform the user. Design work requires
an accepted PRD.
```

`/plan` Phase 1 step 1.1 (in
`skills/plan/references/phases/phase-1-analysis.md`) gains the
analogous branch, with `invoking_child: plan` and a DESIGN upstream:

```markdown
### 1.1 Validate Source Document Status

[existing prose for design input-type]

**Parent-orchestration auto-transition (sentinel-gated).** Before
the status check, look for the `parent_orchestration:` sentinel
block in any `wip/<parent>_<topic>_state.md` file matching the
current topic. When the sentinel is present AND its `invoking_child:`
field is `plan` AND the upstream's status is `Proposed` or
`Accepted`, run `shirabe transition <design-path> Planned` and
proceed. When the sentinel is absent, fall through to the existing
hard-stop table.
```

`/prd`'s reference behavior (SKILL.md lines 132-138) is NOT
modified — it remains the symmetric reference all three skills
align to. The direction R7 leaves open is settled toward
`/prd`'s existing behavior because:

1. `/prd`'s transition is already shipped and dogfooded across
   the BRIEF-handoff (the v0.9.1-dev contract).
2. `/prd`'s transition fires on input-mode signal (BRIEF path
   present), which is symmetric to how `/design` and `/plan`
   would gate on sentinel-presence signal — both are
   "input-shape declares the chain context" signals.
3. The shipped `shirabe transition` subcommand is the single
   transition primitive; reusing it across all three skills
   keeps the transition surface unified.

The symmetric three-skill contract documented in DESIGN body:
"When a chain-context signal is present (BRIEF input for `/prd`,
`parent_orchestration:` sentinel for `/design` and `/plan`), the
skill auto-transitions its upstream artifact forward by one
status before consuming it. When no chain-context signal is
present, the skill applies its protective hard-stop."

Why sentinel-gating over unconditional auto-transition:

- **R6 satisfied by construction.** Direct `/design` invocation
  against a Draft PRD writes no sentinel; the sentinel check
  returns absent; the hard-stop fires. The "silent auto-promote
  on direct invocation" failure mode R6 forbids cannot reach
  this code path because the sentinel is the explicit signal.
- **Mirrors `/prd`'s input-mode discriminator.** `/prd`'s
  BRIEF-handoff fires only on Input Mode 2 (BRIEF path); a topic-
  string input does NOT auto-transition any upstream. The sentinel
  is the structurally-equivalent signal for `/design` and `/plan`:
  parent-driven invocation declares its chain context via sentinel
  presence, direct invocation does not.
- **Read-time discoverable.** The new branch in the phase prose
  is a single named block ("Parent-orchestration auto-transition
  (sentinel-gated)") that future operators reading
  `phase-0-setup-prd.md` or `phase-1-analysis.md` cannot miss.
  Compare with option (a) (unconditional auto-transition), which
  would have to live inside the existing status-check logic and
  whose presence would not be visually obvious.
- **No new infrastructure.** Sentinel reads use the existing
  state-file schema; transitions use the existing `shirabe
  transition` subcommand. No new helper, no new shared module.

#### Alternatives Considered

- **(a) Unconditional auto-transition in /design Phase 0 and /plan
  Phase 1.** Mirrors `/prd`'s brief-handoff shape exactly — whenever
  the upstream is at Draft/Proposed/Accepted, transition it
  forward. Rejected for R6 violation: a direct `/design` invocation
  against a Draft PRD with this option would silently promote the
  PRD to Accepted and then to In Progress, eliminating the
  protective hard-stop the PRD explicitly preserves. `/prd`'s
  brief-handoff doesn't have this exposure because its discriminator
  (Input Mode 2: BRIEF path) is itself a chain-context signal — the
  operator must explicitly invoke `/prd <brief-path>`, which is
  more chain-shape-specific than `/design <prd-path>`. The /design
  and /plan input surfaces don't carry that discrimination; the
  sentinel provides it externally.

- **(b) Document the operator-transitions-upstream-first contract.**
  Rejected for not satisfying R4 or R5. The PRD's contract is
  explicit: "the operator does not drop into a shell to satisfy the
  gate when a parent is driving the chain." Documentation alone
  leaves the per-handoff operator cost in place. The PRD's User
  Story 1 calls this exact recovery step out as the friction the
  sweep removes. Option (b) is the no-op alternative — it would
  preserve the status quo behavior under a different framing.

- **(d) Introduce a shared `chain-handoff.sh` helper that all three
  skills (`/prd`, `/design`, `/plan`) consume.** Rejected on R12
  and R13 grounds. R12 forbids silent behavior changes to `/prd`;
  factoring `/prd`'s existing inlined transition into a shared
  helper would alter its execution path (different sourcing, different
  error-handling surface) for zero behavioral gain. R13 forbids
  hard cross-bug dependencies; a shared helper would couple #159's
  fix to a refactor unrelated to either #156 or #162. The shared-helper
  shape is more attractive when more than three consumers exist; with
  three consumers and one already shipping the transition pattern
  inline, the duplication cost is below the abstraction-pay-back line.

### Decision 3: Fix shape for /work-on upstream-drift + ci_monitor (#162)

`/work-on`'s plan-orchestrator mode (driven by
`skills/work-on/koto-templates/work-on-plan.md`) doesn't fetch main
between per-issue commits, and the `ci_monitor` state (lines 84-111
of the same template) treats missing checks as pending. R8 binds the
fetch+classify flow; R9 binds the escalation surface; R10 binds the
DIRTY-versus-pending distinction; R11 binds the actionable escalation
for the suppressed-checks case.

Key assumptions:

- `references/parent-skill-worktree-discipline.md` (lines 1-100)
  already defines the None / Informational / Intent-changing
  classification and the rebase + analyze + escalate flow. The
  reference is named for the parent-skill pattern but its rule is
  substrate-agnostic per its own lines 11-14.
- The koto template substrate already supports gate definitions,
  enum-typed `accepts`, and transitions to terminal states (e.g.,
  the existing `done_blocked` state at line 116 in `work-on-plan.md`).
- `gh pr view --json mergeStateStatus` is the canonical way to
  query merge-state; DIRTY is the documented value for "checks
  suppressed by merge state".
- The `ci_monitor` gate command at lines 89-90 of
  `work-on-plan.md` runs `gh pr checks ... select(.state != "SUCCESS")
  | length == 0`. Zero check-runs evaluate to `length == 0` →
  passing — the same gate that fires for an actually-green PR also
  fires (incorrectly as success) when checks haven't been created.
  This is the silent-success surface R10 names.

#### Chosen: Combined (a)+(d) — extend /work-on with worktree-discipline AND fix ci_monitor DIRTY-vs-pending

The fix is two coupled edits in the koto template substrate plus
one rename in the references substrate; all three live in
`skills/work-on/` and `references/`, no shared-substrate touch
outside #162's named surfaces.

**Part 1: per-issue worktree-discipline (option a).** Extend the
plan-orchestrator's per-child loop in
`skills/work-on/koto-templates/work-on-plan.md` to invoke the
rebase + impact-analysis + escalation flow defined in
`references/parent-skill-worktree-discipline.md`. The flow fires
before each per-child invocation (matching the reference's own
trigger condition at lines 30-44 of the reference).

The koto template gains a new state `worktree_discipline_check`
positioned before the existing per-child dispatch:

```yaml
worktree_discipline_check:
  gates:
    impact_classified:
      type: command
      command: "test -f wip/work-on_${PLAN_SLUG}_impact.json"
  accepts:
    impact:
      type: enum
      values: [none, informational, intent-changing]
      required: true
    rationale:
      type: string
      required: false
  transitions:
    - target: next_child_dispatch
      when:
        impact: none
    - target: next_child_dispatch
      when:
        impact: informational
    - target: escalate_upstream_drift
      when:
        impact: intent-changing
```

The phase prose in `skills/work-on/references/phases/phase-3-analysis.md`
(or a new `phase-2.5-worktree-discipline.md` file — DESIGN allows
either; the implementing PR chooses based on prose-flow fit) is
extended with the per-child instruction: "Before invoking the next
child workflow, fetch origin/main, rebase the shared branch, classify
the upstream impact per
`references/parent-skill-worktree-discipline.md` (rename to
`worktree-discipline.md` per Part 3 below), and write the
classification to `wip/work-on_${PLAN_SLUG}_impact.json`."

**Part 2: ci_monitor DIRTY-vs-pending distinction (option d).**
Edit `skills/work-on/koto-templates/work-on-plan.md` `ci_monitor`
state (lines 84-111) to add a second gate that checks merge state
before evaluating check-runs. The new gate logic:

```yaml
ci_monitor:
  gates:
    ci_passing:
      type: command
      command: "gh pr checks $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number // empty') --json state --jq '[.[] | select(.state != \"SUCCESS\")] | length == 0' | grep -q true"
    merge_state_clean:
      type: command
      command: "[ \"$(gh pr view --json mergeStateStatus --jq .mergeStateStatus)\" != \"DIRTY\" ]"
  accepts:
    ci_outcome:
      type: enum
      values: [passing, failing_fixed, failing_unresolvable, dirty_merge_state]
      required: true
    rationale:
      type: string
      description: What was fixed or why CI failures are unresolvable
  transitions:
    - target: plan_completion
      when:
        ci_outcome: passing
        gates.ci_passing.exit_code: 0
        gates.merge_state_clean.exit_code: 0
    - target: plan_completion
      when:
        ci_outcome: failing_fixed
    - target: done_blocked
      when:
        ci_outcome: failing_unresolvable
      context_assignments:
        failure_reason: "ci_monitor: unresolvable CI failures: ${evidence.rationale}"
    - target: escalate_dirty_merge_state
      when:
        ci_outcome: dirty_merge_state
      context_assignments:
        failure_reason: "ci_monitor: PR merge state is DIRTY; checks suppressed. ${evidence.rationale}"
```

The prose at line 226 (`## ci_monitor` section) gains an explicit
DIRTY-handling paragraph: "If `gh pr view --json mergeStateStatus`
returns `DIRTY`, the PR has merge conflicts and GitHub will not create
new check-runs. Submit `ci_outcome: dirty_merge_state` with rationale
naming the conflict files. Do NOT loop on `ci_passing` — the
suppressed-checks case is structurally different from pending and
requires rebase before checks can resume."

The new terminal state `escalate_dirty_merge_state` routes to
`done_blocked` after surfacing the actionable signal:

```yaml
escalate_dirty_merge_state:
  accepts:
    rationale:
      type: string
      required: true
  transitions:
    - target: done_blocked
      when: {}
```

**Part 3: Rename the worktree-discipline reference (option c).**
Rename `references/parent-skill-worktree-discipline.md` to
`references/worktree-discipline.md` and update every cross-reference
in the repo. The reference itself notes at lines 11-14 that its
rule is substrate-agnostic; the `parent-skill-` prefix is
historically accurate (only `/scope` consumed it before this design)
but constrains its name to one consumer family. With `/work-on`
becoming a second consumer, the prefix-free name reflects the
reference's actual scope.

Why this combination:

- **R8 + R10 are the same shape: routine-path silence.** R8 names
  the silent surface where main moves under a long-running PR with
  no signal until finalization; R10 names the silent surface where
  CI suppression looks identical to CI slowness. Both fixes share
  the substrate (koto template `work-on-plan.md`) and the same
  reviewer attention surface — separating them across two PRs
  would couple the reviewer to context-switching cost for no
  benefit.
- **R9 + R11 share escalation discipline.** Both route to
  named terminal states (`escalate_upstream_drift` and
  `escalate_dirty_merge_state` respectively), both surface
  actionable signals (impact classification with the
  intent-changing rationale; merge-state with the conflict-file
  listing). The PRD explicitly allows sharing one surface or using
  two; the chosen split (two surfaces) keeps the escalation message
  specific to the failure mode rather than a generic "something
  blocked" prompt the operator has to decode.
- **R13 satisfied within #162's frame.** Parts 1 and 2 are
  independently shippable: Part 1 (worktree-discipline) edits the
  per-child dispatch path, Part 2 (ci_monitor) edits the finalization
  state. Either can ship without the other. Part 3 (rename) is a
  pure-rename PR that can ship before, between, or after Parts 1
  and 2 — only its cross-reference touches need to coordinate with
  whichever PR consumes the renamed path first. The combined choice
  preserves shippability granularity even though the PRD names the
  combination as one design surface.
- **Reuses existing classification vocabulary.** The
  None / Informational / Intent-changing trio is already authored
  and validated against `/scope`'s consumption; reusing it for
  `/work-on` aligns the cross-skill mental model. Option (b)
  (document operator manual rebase) discards this vocabulary; option
  (a) alone preserves it but leaves ci_monitor silent on DIRTY.

#### Alternatives Considered

- **(a) Worktree-discipline only (no ci_monitor fix).** Rejected
  for partial #162 closure. The PRD names the ci_monitor
  silent-wait surface as a distinct contract from upstream-drift
  detection (R10/R11 separate from R8/R9). The BRIEF's catastrophic
  surface (SE11 PR-141) hit BOTH failure modes — main moved AND CI
  silently stopped reporting. Fixing only the upstream-drift surface
  would leave operators in the silent-wait state even after the
  worktree-discipline check fires (because main has moved, the next
  commit may still be DIRTY, and the operator would proceed to
  `ci_monitor` with no signal that something's wrong). The PRD's D3
  explicitly defends keeping both in scope.

- **(b) Document explicitly that PLAN consumption is non-atomic and
  operators should rebase manually.** Rejected for the same reason
  as Decision 2's option (b): the PRD's contract is that the
  failure becomes actionable mid-chain, not that the operator is
  given guidance about a manual recovery step. The User Story 3
  framing ("I find out at the point recovery is cheapest") is
  satisfied only by runtime detection. Documentation-only options
  preserve the manual-recovery tax the PRD goals explicitly remove.

- **(c) Rename the worktree-discipline reference only, no behavioral
  change.** Rejected as the no-op alternative. The rename is
  worthwhile companion work but is not the bug fix; without
  Parts 1 and 2, the rename has zero behavioral impact on either
  the upstream-drift or the ci_monitor surface.

- **(e) Build a custom DIRTY-aware retry loop on the existing
  ci_monitor command.** Rejected for opacity. A retry loop that
  silently detects DIRTY and tries to rebase before re-running
  ci_passing would hide the failure mode from the operator at exactly
  the moment R11 says it should escalate. The koto-state-machine
  shape with an explicit `dirty_merge_state` enum value preserves
  the failure-state visibility the PRD requires.

### Decision 4: Sweep-level blast radius (R12/R13)

R12 and R13 constrain the design's behavior across the three bug
fixes: no silent changes outside the named surfaces, and each fix
must be independently shippable. The three bug-decisions above are
substrate-disjoint (bash, phase-prose, koto template + reference)
and the question is whether they need a fourth coordinating
decision or whether the substrate-disjointness already discharges
the constraint.

Key assumptions:

- The three substrates do not share runtime infrastructure. A
  change to `plan-to-tasks.sh` cannot affect koto template parsing;
  a change to `/design`'s phase prose cannot affect `/prd`'s
  shipped transition behavior; a change to `work-on-plan.md`'s
  gate definitions cannot affect parser regex matching.
- R12's named surfaces are concrete: `/prd`'s existing
  brief-handoff transition (Decision 2 option a/d would touch this;
  the chosen option c does NOT); the multi-pr / GitHub-issue parsing
  path in `plan-to-tasks.sh` (Decision 1's chosen option does NOT
  touch lines 104-141); `/work-on`'s phases unrelated to
  upstream-drift detection (Decision 3 touches only the per-child
  dispatch and `ci_monitor`).
- R13's independent-shippability is observable at the PR level
  (no commit references "depends on PR for bug N" as a
  precondition).

#### Chosen: Substrate-disjointness discharges R12/R13; no shared coordination required

The three fixes ship as three independent PRs (or one combined PR;
the PRD explicitly allows either grouping). The DESIGN body
enumerates the shared-substrate touches and proves each is
contained within its bug's named surface:

| Bug | Substrate Touch | Surfaces Outside Bug? |
|-----|----------------|----------------------|
| #156 | `plan-to-tasks.sh` line 288, plus new empty-deps signal block before line 448 | No. Multi-pr path lines 104-141 untouched. `### Dependencies` accumulator lines 312-339 untouched. |
| #159 | `skills/design/references/phases/phase-0-setup-prd.md` step 0.2, `skills/plan/references/phases/phase-1-analysis.md` step 1.1 | No. `skills/prd/SKILL.md` lines 132-138 untouched. The chosen sentinel-gated mechanism does not refactor or wrap `/prd`'s existing transition. |
| #162 | `skills/work-on/koto-templates/work-on-plan.md` `ci_monitor` state lines 84-111 plus new per-child worktree-discipline check, `references/parent-skill-worktree-discipline.md` rename | The rename touches every cross-reference in the repo. Cross-references are mechanical; the prose content of the reference is unchanged. The rename is called out at review per R12's documentation requirement. |

The single shared touch — the rename in Part 3 of Decision 3 — is
a pure-rename surface; it changes the path that all consumers
import, not the content they consume. The DESIGN body documents the
rename and the implementing PR carries the cross-reference
inventory at review time per AC12.1's enumeration requirement.

R13's independent-shippability is preserved by:

1. **No shared code introduced.** Decision 2 explicitly rejects
   option (d)'s shared `chain-handoff.sh` helper. Decision 3's
   parts are coupled by substrate but ship as separately
   reviewable units within the same PR-or-separate-PRs choice.
2. **No fix references another bug as a precondition.** Decision 1
   touches no file Decision 2 or 3 touches. Decision 2 touches no
   file Decision 1 or 3 touches. Decision 3's rename is mechanical
   and not behavior-coupled to Decisions 1 or 2.
3. **Rollback granularity preserved.** A reverter undoing any one
   bug's fix does not destabilize the other two; the substrates do
   not interact at runtime.

Why no fourth coordinating decision:

- **Substrate-disjointness is the structural property R12/R13 ask
  for.** Adding a fourth decision (e.g., "sweep CI gate", "shared
  rollback strategy") would manufacture coordination where the
  substrates ensure none is needed.
- **AC12.1 and AC13.1 are review-time checks, not design-time
  decisions.** The PRD's acceptance criteria for R12/R13 are
  judgment-based — a reviewer agrees each touch is justified, a
  reviewer verifies no commit declares cross-bug dependency. Both
  surfaces fire at PR time against the artifact set this design
  produces; neither requires DESIGN to invent a new mechanism.

#### Alternatives Considered

- **Treat R12/R13 as a Decision-5-shaped "sweep coordination"
  surface and propose a new shared module.** Rejected: the design
  has no shared surface to coordinate. Inventing one would violate
  R12 by introducing code outside the named bugs' surfaces. The
  PRD's D1 ("Sweep as a unit vs. three independent PRDs") settles
  the framing concern at the PRD level; this design inherits that
  framing and does not re-litigate it.

- **Add a top-level "blast-radius checklist" that the implementing
  PRs reference.** Rejected: AC12.1 already requires the design
  body to enumerate touches outside the three bugs; the table above
  satisfies that requirement. A separate checklist would duplicate
  the table without adding signal.

## Decision Outcome

The four decisions converge on a design that ships three
substrate-disjoint fixes with one shared rename, all
substrate-fidelity-preserving:

- **Decision 1 (parser):** loosen the regex AND emit an
  asymmetric-empty-deps warning. Two edits to
  `skills/plan/scripts/plan-to-tasks.sh`; no other file touched.
- **Decision 2 (chain-handoff):** sentinel-gated auto-transition
  in `/design` Phase 0 and `/plan` Phase 1; `/prd` SKILL.md is the
  reference behavior all three align to. Two phase-prose edits;
  `/prd` SKILL.md is untouched.
- **Decision 3 (work-on):** combined per-child worktree-discipline
  check AND ci_monitor DIRTY-vs-pending distinction AND
  worktree-discipline reference rename. Edits land in
  `skills/work-on/koto-templates/work-on-plan.md`, one
  `skills/work-on/references/phases/` prose file, and one rename
  across the repo's cross-reference graph.
- **Decision 4 (blast radius):** substrate-disjointness discharges
  R12/R13 directly. The design body enumerates every touch in a
  single table; reviewer judgment satisfies AC12.1 and AC13.1.

Cross-validation across the four decisions surfaced no conflicts.
Decision 1's bash-substrate fix cannot reach Decision 2's
phase-prose substrate. Decision 2's sentinel-gating depends on the
state file `/scope` already writes; no new sentinel mechanism is
introduced. Decision 3's ci_monitor edit and worktree-discipline
extension share the same koto template substrate but operate on
disjoint states (`ci_monitor` is finalization-phase, the
worktree-discipline check is per-child-dispatch-phase).

One implicit decision surfaced during architecture synthesis:
**Decision 2's sentinel-detection mechanism reads the state file
in a way that is robust to multiple parents.** A future parent skill
(beyond `/scope`) that wraps the tactical chain would write its
sentinel to its own `wip/<parent>_<topic>_state.md` file; the
`/design` Phase 0 read uses a glob pattern (`wip/*_<topic>_state.md`)
rather than hardcoding `wip/scope_<topic>_state.md`. This keeps the
fix forward-compatible with the parent-skill pattern's evolution
without binding to `/scope` specifically.

## Solution Architecture

### Overview

Three independent fix surfaces map 1:1 to three components. Each
component is independently shippable; the design imposes no shared
infrastructure or ordering constraint.

### Components

**Component 1 (Bug #156 — parser):** edits confined to
`skills/plan/scripts/plan-to-tasks.sh`.

- Line 288: regex change from `\*\*Dependencies\*\*:[[:space:]]*(.+)$`
  to `\*\*Dependencies:?\*\*:?[[:space:]]*(.+)$`.
- New code block after the main parsing loop (before the
  `waits_on`-resolution loop at line 448): iterate
  `issue_numbers[]` and `issue_deps[]`, count empty deps, emit
  a single stderr warning when the count is asymmetric (some
  empty, some not) on a multi-issue PLAN.
- Test fixtures (new files under
  `skills/plan/scripts/test-fixtures/` if absent, mirroring
  existing test conventions): one PLAN with both colon placements
  exercising AC1.1; one PLAN with mixed empty/non-empty deps
  exercising AC2.1 + AC2.2; one PLAN using `### Dependencies`
  section format exercising AC3.1.

**Component 2 (Bug #159 — chain-handoff):** edits to two phase
files, plus one DESIGN-body-only contract documentation.

- `skills/design/references/phases/phase-0-setup-prd.md` step 0.2:
  add the "Parent-orchestration auto-transition (sentinel-gated)"
  branch before the existing hard-stop check. New prose block is
  ~15 lines.
- `skills/plan/references/phases/phase-1-analysis.md` step 1.1: add
  the analogous branch for DESIGN-input mode. New prose block is
  ~15 lines.
- Sentinel-detection logic in both branches: read any
  `wip/*_<topic>_state.md` file matching the current topic, parse
  the `parent_orchestration:` block, check `invoking_child:` value,
  invoke `shirabe transition <upstream-path> <next-status>` when
  the sentinel matches and the upstream is at the expected status.
- DESIGN-body contract paragraph (lands in this DESIGN as the
  authoritative spec; implementing PR copies it into each phase
  file's prose where the branch is added): the symmetric three-skill
  contract stated under Decision 2 ("When a chain-context signal
  is present...").

**Component 3 (Bug #162 — work-on):** edits to one koto template
plus one phase prose file plus one repo-wide rename.

- `skills/work-on/koto-templates/work-on-plan.md`: new state
  `worktree_discipline_check` positioned in the per-child loop;
  edit to `ci_monitor` state (lines 84-111) adding the
  `merge_state_clean` gate, the `dirty_merge_state` enum value,
  the new transition to `escalate_dirty_merge_state`; new terminal
  state `escalate_dirty_merge_state`; new state
  `escalate_upstream_drift` routing intent-changing upstream
  classification.
- `skills/work-on/references/phases/phase-3-analysis.md` (or new
  `phase-2.5-worktree-discipline.md` — implementing PR chooses
  based on prose-flow): per-child instruction to fetch, rebase,
  classify, write
  `wip/work-on_${PLAN_SLUG}_impact.json`. The instruction
  references the renamed `references/worktree-discipline.md`.
- `references/parent-skill-worktree-discipline.md` →
  `references/worktree-discipline.md`: pure rename, cross-references
  updated across the repo. Affected cross-references (per current
  `grep -r 'parent-skill-worktree-discipline'`): `skills/scope/SKILL.md`
  (one line), `skills/scope/references/phases/phase-2-chain-orchestration.md`
  (one line), the PRD's R8 prose (does NOT need a code change —
  PRD prose is historical, but the DESIGN body and any new prose
  references use the renamed path).

**Cross-cutting (none):** the three components share no code, no
configuration, and no runtime state. The single shared activity is
the worktree-discipline reference rename in Component 3, which
touches existing consumers of the path (Component 3's own new
consumption + `/scope`'s existing consumption); it does not
introduce a new shared module or helper.

### Data flow

**Component 1 (parser):** PLAN file (stdin or `$1` path argument)
→ line-by-line scan in
`skills/plan/scripts/plan-to-tasks.sh:280-340` → issue
arrays (`issue_numbers[]`, `issue_deps[]`, etc.) → empty-deps
asymmetry check (new) → `waits_on` resolution loop (line 448) →
JSON output to stdout.

**Component 2 (chain-handoff):** `/scope` Phase 2 writes
`parent_orchestration:` block to
`wip/scope_<topic>_state.md` → invokes `/design` (or `/plan`)
→ child Phase 0 (or Phase 1) reads the sentinel via glob match
→ sentinel matches → child runs `shirabe transition
<upstream-path> <next-status>` → child proceeds to phase body
→ child Phase 6 (or Phase 7) finalizes artifact → `/scope` Phase 2
clears the sentinel.

**Component 3 (work-on):** koto state machine transitions through
per-child loop → before each child invocation, agent runs `git
fetch origin && git rebase origin/<tracking>` → agent classifies
impact per `references/worktree-discipline.md` → writes
`wip/work-on_${PLAN_SLUG}_impact.json` → koto evaluates
`worktree_discipline_check` gate and reads the JSON → if
intent-changing, routes to `escalate_upstream_drift`; otherwise
proceeds. At finalization, `ci_monitor` runs both `ci_passing`
gate AND `merge_state_clean` gate → agent submits one of
`{passing, failing_fixed, failing_unresolvable, dirty_merge_state}`
→ koto routes; dirty_merge_state lands in
`escalate_dirty_merge_state` → `done_blocked` with the
DIRTY-specific `failure_reason`.

### Interface contracts

**Component 2's sentinel-read contract.** `/design` Phase 0 and
`/plan` Phase 1 share the read protocol:

1. Compute the topic slug from `$ARGUMENTS` (the PRD or DESIGN
   path's basename minus the prefix and `.md` suffix).
2. Glob for `wip/*_<topic>_state.md`. Zero matches → sentinel
   absent → proceed to existing hard-stop.
3. For each match, parse the YAML frontmatter or top-level
   `parent_orchestration:` block. (The state file is markdown with
   a YAML block per `skills/scope/references/state-schema.md`.)
4. If any match has `parent_orchestration.invoking_child` equal to
   the current child name (`design` or `plan`) AND the upstream
   artifact's status is at the expected pre-transition status
   (`Accepted` for `/design`-reading-PRD, `Accepted` for
   `/plan`-reading-DESIGN), invoke `shirabe transition <upstream>
   <next-status>` and proceed.
5. Otherwise, fall through to the existing hard-stop.

The contract is "presence-and-match required for auto-transition";
absence falls through to hard-stop is the R6-preserving default.

**Component 3's impact-classification contract.**
`wip/work-on_${PLAN_SLUG}_impact.json` is the durable artifact the
agent writes and the gate reads:

```json
{
  "impact": "none | informational | intent-changing",
  "rationale": "one-paragraph explanation matching the worktree-discipline reference's classification examples",
  "upstream_commits": ["sha1", "sha2"]
}
```

The `impact` field drives koto routing; `rationale` and
`upstream_commits` are read by the
`escalate_upstream_drift` state if reached.

## Implementation Approach

Each component ships as one PR (or all three in one combined PR;
the PRD's D3 leaves the choice to the implementing engineer based
on review-burden and reviewer-set considerations).

### Phase A: Component 1 (parser fix)

1. Edit `skills/plan/scripts/plan-to-tasks.sh` line 288 regex.
2. Add the asymmetric-empty-deps warning block after the
   main loop, before the `waits_on` resolution at line 448.
3. Add test fixtures and a test runner (or extend the existing
   test infrastructure under `skills/plan/scripts/`).
4. Verify AC1.1, AC1.2, AC2.1, AC2.2, AC3.1 each grep-check or
   execute green.
5. PR: `fix(plan): accept both Dependencies colon placements
   and warn on asymmetric empty-deps`.

### Phase B: Component 2 (chain-handoff sentinel auto-transition)

1. Edit `skills/design/references/phases/phase-0-setup-prd.md` step
   0.2 to add the sentinel-gated branch.
2. Edit `skills/plan/references/phases/phase-1-analysis.md` step
   1.1 to add the analogous branch.
3. Verify AC4.1, AC4.2, AC5.1, AC5.2, AC6.1, AC7.1 each
   grep-check or execute green.
4. PR: `fix(design,plan): sentinel-gated chain-handoff
   auto-transition`.

### Phase C: Component 3 (work-on worktree-discipline + ci_monitor)

1. Rename `references/parent-skill-worktree-discipline.md` to
   `references/worktree-discipline.md` and update cross-references
   in `skills/scope/SKILL.md` and
   `skills/scope/references/phases/phase-2-chain-orchestration.md`.
2. Edit `skills/work-on/koto-templates/work-on-plan.md`: add
   `worktree_discipline_check` state, edit `ci_monitor` to add
   `merge_state_clean` gate and `dirty_merge_state` enum, add
   `escalate_upstream_drift` and `escalate_dirty_merge_state`
   terminal states.
3. Edit the appropriate `skills/work-on/references/phases/` file
   (or add `phase-2.5-worktree-discipline.md`) with the
   classification instruction.
4. Verify AC8.1, AC8.2, AC9.1, AC10.1, AC11.1 each grep-check or
   execute green.
5. PR: `fix(work-on): per-child worktree-discipline and
   ci_monitor DIRTY-vs-pending distinction`.

### Phase D: Sweep-level verification (AC12.1, AC13.1)

After Phases A, B, C land, run the sweep-level review:

1. Verify AC12.1: enumerate every file touched across the three
   PRs and confirm no edits land outside the three bugs' named
   surfaces (the table in Decision 4 is the reference).
2. Verify AC13.1: confirm no PR description, commit message, or
   issue cross-reference declares another PR as a precondition.

Phase D is review-only — no code edits. The PRs ship independently
or together at the team's discretion.

## Security Considerations

Threat surfaces this design touches:

- **Component 1 (parser):** the regex change accepts a strictly
  larger set of inputs. The previously-rejected
  `**Dependencies:**` form is now captured; the captured content
  is then passed through the existing `waits_on` resolution at
  line 448, which calls `die_schema` on unknown issue references.
  The new asymmetric-empty-deps warning writes to stderr only; no
  state mutation, no shell metacharacter exposure (the warning
  message is constructed via `printf`-equivalent
  parameter expansion, not via interpolation of file content).
  Threat vector closed by construction: an attacker who can write
  a PLAN file can already write a malicious `Dependencies` line
  under the pre-fix regex; the regex change does not expand the
  attacker's surface.

- **Component 2 (sentinel-gated auto-transition):** the
  sentinel-read protocol reads files under `wip/*_<topic>_state.md`,
  parses YAML, and conditionally invokes `shirabe transition`. The
  threat to weigh is sentinel forgery: an attacker who can write
  `wip/scope_<topic>_state.md` (e.g., via a malicious PR that
  injects the file) could trick `/design` Phase 0 into auto-
  transitioning an arbitrary PRD. Mitigation: the auto-transition
  only fires when the operator is running `/design` against a PRD
  path they themselves provided as `$ARGUMENTS`; the worst-case
  outcome is the operator's own PRD getting status-advanced one
  step (Draft → Accepted or Accepted → In Progress), which is a
  recoverable state via the `shirabe transition` reverse direction.
  The sentinel-read does NOT execute arbitrary code from the state
  file; it reads named fields only. Threat residual: low; the same
  threat exists for `/prd`'s shipped brief-handoff transition and
  has not surfaced as a real incident across the dogfooding window.

- **Component 3 (work-on worktree-discipline + ci_monitor):** the
  worktree-discipline check runs `git fetch origin && git rebase
  origin/<tracking>` — both standard git operations the operator
  was already running manually. The classification step reads
  upstream commits and the chain's artifacts; no shell
  interpolation of commit content into other commands. The
  ci_monitor change adds a new `gh pr view --json mergeStateStatus`
  call; `gh` is a trusted CLI surface already used elsewhere in
  the same template (line 89). No new external network call
  surfaces are introduced; `gh fetch` and `gh pr view` are both
  already in the template's existing call set.

No new authentication surfaces, no new persistent state, no new
network calls beyond the existing `gh` and `git` invocations the
template already uses. The substrate-disjointness of the three
components means each component's threat-surface analysis stands
alone; cross-component threats are not possible because no
component reads another component's output as input.

## Consequences

### Positive

- **Three routinely-reachable silent-failure modes close
  simultaneously.** Operators running the standard pattern-v1
  chain workflows stop paying the per-handoff manual-recovery tax
  the PRD frames.
- **The worktree-discipline reference becomes substrate-agnostic.**
  Renaming `parent-skill-worktree-discipline.md` to
  `worktree-discipline.md` makes the rule available to future
  consumers without re-deriving the name. The reference's content
  is already substrate-agnostic per its lines 11-14; the rename
  honors that.
- **The parent-orchestration sentinel earns a second consumer.**
  Decision 2 binds `/design` and `/plan` to the same
  `parent_orchestration:` sentinel `/scope` writes; the sentinel
  was authored as a pattern-level primitive, and this design is
  the first cross-skill validation that it serves that role.
- **The CI-suppression failure surfaces as a named state.** Adding
  `dirty_merge_state` as an enum value in `ci_monitor`'s accepts
  block gives the failure a name future observability work
  (release-blocker dashboards, koto-state-machine introspection)
  can filter on.

### Negative

- **The koto template grows in size.** `work-on-plan.md` adds a
  new state and a new gate to an existing state. The koto-template
  surface is already complex; adding two more states (and one
  escalation terminal each) is incremental but real.
- **The worktree-discipline rename touches every cross-reference.**
  The PR carrying the rename must update each consumer site;
  forgetting one creates a broken link that doesn't fail any
  validator (markdown link checking is not currently enforced for
  these `references/` paths). Mitigation: the PR description
  enumerates every touched site; reviewer verifies.
- **The sentinel-read protocol adds glob-based file discovery to
  child Phase 0/Phase 1.** Future parents that wrap the tactical
  chain must write their state file to a path matching
  `wip/*_<topic>_state.md`. The convention is enforced by the
  pattern doc, not by code; deviation would silently bypass the
  auto-transition. Mitigation: the convention is documented in
  the symmetric three-skill contract paragraph; future parents
  reading the pattern doc will inherit the convention.

### Mitigations

- **Cross-reference inventory.** Phase C's PR includes an
  explicit list of every site updated by the worktree-discipline
  rename, plus a `grep -r 'parent-skill-worktree-discipline'`
  output proving no orphan references remain.
- **Sentinel-detection tests.** Component 2's test suite includes
  a sentinel-present fixture, a sentinel-absent fixture, and a
  sentinel-mismatched fixture (sentinel present but
  `invoking_child:` is not `design` or `plan`) to verify the
  hard-stop preserves R6.
- **DIRTY-fixture for ci_monitor.** Component 3's test suite
  includes a fixture that simulates `mergeStateStatus=DIRTY` (via
  a mock `gh` wrapper or a controlled-state test PR) to verify
  `escalate_dirty_merge_state` routes correctly within the bounded
  test duration AC11.1 requires.
