---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-koto-default-action-adoption.md
milestone: "koto default_action adoption"
issue_count: 7
---

# PLAN: Adopting `default_action` in shirabe's koto templates

## Status

Active

Tracking level is `none`, so no GitHub issues or milestone are filed and the
Draft to Active transition fires on authoring rather than on approval.

## Scope Summary

Convert four mechanical steps in shirabe's three koto-backed templates into
`default_action` states with independent gates and fallback prose, delete five
re-derivations of a variable `/execute` already declares, and record the rule
that decided each conversion.

## Decomposition Strategy

**Horizontal**, with the shared reference landing first.

The design's five changes are independent edits to templates that do not
interact at runtime. Nothing here has an end-to-end path to exercise: each
converted state is verified by its own gate, its own compile, and the same two
repository checks. A walking skeleton would build a thin slice of a pipeline
that does not exist.

The one real coupling is file ordering rather than behavior. Three units edit
`skills/execute/koto-templates/execute.md`, so they are sequenced against each
other to keep the diffs legible and the state list coherent, and the `Files`
annotations below let the conflict topology see it.

The conversion record is written first, though nothing depends on it. Every
later unit's review reads against the rule it records, and a reviewer meeting
the second conversion without that rule in front of them has to reconstruct it
from the diff. Making it a blocker would serialize three units that touch
different files for a reason that is about reading order rather than
correctness, so it is sequenced by intent and not by an edge.

Execution mode is `single-pr` under the repository's default `consolidated`
delivery preference. No split trigger fires: no unit reaches a remote or gates
another, and none is independently useful to a reader who meets it alone --
three of the four conversions are worked examples of one rule, and the rule
without them is a page nobody has to follow.

## Issue Outlines

### Issue 1: Record the conversion rule and point CLAUDE.md at it

**Goal**: Write the rule that decides whether koto runs a command or the agent
does, where a template author will find it, citing koto's authoring guide as
the authority rather than restating its reasoning.

**Acceptance Criteria**:
- [ ] `references/default-action-conversion.md` exists and states the rule:
      keep `default_action` off any command whose successful exit is itself the
      irreversible, externally visible event; allow it where the only
      irreversibility is bounded and repairable.
- [ ] The reference names koto's `docs/guides/default-action-authoring.md` as
      the authority for the reasoning and does not reproduce it.
- [ ] The reference carries shirabe's two additional filters from the design:
      the command must exit non-zero when it fails, and it must leave a trace
      some other command can check.
- [ ] The reference carries shirabe's three authoring constraints: a `fallback`
      names the evidence and not just the command; a body longer than one
      clause goes in a script reached through a declared variable; every
      transition out of a converted state names the state's gate.
- [ ] The reference names the secret-in-the-event-log check an author runs
      before converting anything.
- [ ] `CLAUDE.md`'s "Authoring koto-using Skills" section links to it.
- [ ] `shirabe validate` reports no error-severity finding on either file.

**Dependencies**: None

**Type**: docs
**Files**: `references/default-action-conversion.md`, `CLAUDE.md`

### Issue 2: Stop re-deriving PLAN_SLUG in execute.md

**Goal**: Replace the five shell re-derivations of `PLAN_SLUG` in
`execute.md`'s body with the `{{PLAN_SLUG}}` variable the frontmatter already
declares and validates at compile time.

**Acceptance Criteria**:
- [ ] `basename {{PLAN_DOC}} .md | sed 's/^PLAN-//'` appears nowhere in
      `skills/execute/koto-templates/execute.md`.
- [ ] Every site that consumed that derivation reads `{{PLAN_SLUG}}`.
- [ ] `koto template compile skills/execute/koto-templates/execute.md` exits 0.
- [ ] `scripts/check-template-interpolation.sh` exits 0.
- [ ] `scripts/validate-template-mermaid.sh` exits 0.
- [ ] No behavior changes: the value each site now reads is the same string the
      derivation produced.

**Dependencies**: None

**Type**: docs
**Files**: `skills/execute/koto-templates/execute.md`

### Issue 3: Add a branch_check state ahead of /scope's setup

**Goal**: Give `/scope` a state that reads the branch name, captures it for
every later state, and gates on HEAD being a named non-default branch, so the
check the setup directive states in prose is enforced instead of requested.

**Acceptance Criteria**:
- [ ] `scope.md` declares a `branch_check` state carrying a `default_action`
      that runs `git symbolic-ref --quiet --short HEAD` with
      `capture_stdout_as: BRANCH` and a non-empty `fallback`.
- [ ] The `fallback` names both the manual command and the evidence to submit.
- [ ] `branch_check` declares a gate rejecting an empty branch name, `main`,
      and `master`, and all three of its transitions name that gate.
- [ ] `initial_state` is `branch_check`.
- [ ] `setup`'s directive no longer asks the agent to confirm the branch.
- [ ] The passing path advances to `setup` with no evidence submitted.
- [ ] The failing path returns the gate's exit code with an `expects` schema
      offering `override` and `blocked`.
- [ ] `branch_check` appears in `skills/scope/koto-templates/scope.mermaid.md`
      with its edges.
- [ ] The action's command run twice in sequence exits 0 both times and leaves
      the working tree unchanged.
- [ ] `koto template compile`, `scripts/validate-template-mermaid.sh`, and
      `scripts/check-template-interpolation.sh` all exit 0.

**Dependencies**: None

**Type**: code
**Files**: `skills/scope/koto-templates/scope.md`, `skills/scope/koto-templates/scope.mermaid.md`, `skills/scope/references/phases/phase-0-setup.md`

### Issue 4: Move /execute's settled-branch record into its own state

**Goal**: Replace the twelve-line recording block and its five paragraphs of
explanation in `orchestrator_setup` with a state whose action runs a script,
whose existing `context-matches` gate verifies the result, and whose capture
lets `spawn_and_await` read the branch instead of recovering it.

**Acceptance Criteria**:
- [ ] `skills/execute/scripts/record-settled-branch.sh` exists, takes the
      session name as its argument, and prints only the branch name on stdout.
- [ ] The script exits non-zero with a diagnostic naming the cause for a
      detached HEAD, a branch name outside `^[A-Za-z0-9._/-]+$`, and the
      default branch (`main` or `master`).
- [ ] `execute.md` declares a `PLUGIN_ROOT` variable and `/execute`'s
      `koto init` invocation in `skills/execute/SKILL.md` passes
      `--var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}`.
- [ ] `execute.md` declares a `settled_branch_record` state whose
      `default_action` invokes the script through `{{PLUGIN_ROOT}}`, declares
      `capture_stdout_as: SETTLED_BRANCH`, and carries a `fallback` naming both
      the manual step and the evidence.
- [ ] The `settled_branch_recorded` gate is declared on `settled_branch_record`
      and referenced by its transitions; `orchestrator_setup` no longer
      declares or references it.
- [ ] `settled_branch_record` has no `override` edge, so a run that cannot
      record its branch cannot wave the gate through.
- [ ] `orchestrator_setup` routes to `settled_branch_record`, and the recording
      block and its explanatory paragraphs are gone from its prose.
- [ ] `spawn_and_await` reads `{{SETTLED_BRANCH}}` and the block that reads the
      context key, branches on koto's exit status, and falls back to
      `impl/<slug>` is gone.
- [ ] The branch injected into each child task's vars is the value the gate
      verified, on the create path and the adopt path alike -- the deletion
      above removes a fallback, so this is what proves it was dead code rather
      than load-bearing.
- [ ] `skills/execute/scripts/settled-branch-record_test.sh` tests the script
      file rather than shell extracted from the template, and covers the
      detached-HEAD, malformed-name, and default-branch refusals.
- [ ] `settled_branch_record` appears in
      `skills/execute/koto-templates/execute.mermaid.md` with its edges.
- [ ] Running the script twice in sequence leaves the same stored value and
      exits 0 both times.
- [ ] `koto template compile`, `scripts/validate-template-mermaid.sh`,
      `scripts/check-template-interpolation.sh`, and the script's own test all
      exit 0.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/execute/koto-templates/execute.md`, `skills/execute/koto-templates/execute.mermaid.md`, `skills/execute/scripts/record-settled-branch.sh`, `skills/execute/scripts/settled-branch-record_test.sh`, `skills/execute/SKILL.md`

### Issue 5: Move /execute's fetch and rebase into a worktree_sync state

**Goal**: Separate the mechanical half of `worktree_discipline_check` -- fetch
origin and rebase the shared branch on main -- from the impact classification,
which is judgment, and gate it on whether the rebase's goal actually holds.

**Acceptance Criteria**:
- [ ] `execute.md` declares a `worktree_sync` state whose `default_action` runs
      `git fetch --quiet origin && git rebase origin/main` and carries a
      `fallback` covering the conflict case and naming the evidence.
- [ ] The state's gate is `git merge-base --is-ancestor origin/main HEAD`, which
      asks whether the rebase's goal holds rather than whether the command
      succeeded, and all of the state's transitions name it.
- [ ] `worktree_discipline_check`'s prose no longer asks the agent to fetch or
      rebase, and still asks for the classification and the impact JSON.
- [ ] `settled_branch_record` routes to `worktree_sync`, which routes to
      `worktree_discipline_check`.
- [ ] `worktree_sync` appears in `execute.mermaid.md` with its edges.
- [ ] A second run against an already-rebased branch exits 0 and changes
      nothing.
- [ ] `koto template compile`, `scripts/validate-template-mermaid.sh`, and
      `scripts/check-template-interpolation.sh` all exit 0.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `skills/execute/koto-templates/execute.md`, `skills/execute/koto-templates/execute.mermaid.md`

### Issue 6: Add a pr_precheck state before /work-on opens a pull request

**Goal**: Read the branch name once on the single edge into `pr_creation`,
capture it for the states that need it, and gate on not being about to open a
pull request from the default branch.

**Acceptance Criteria**:
- [ ] `work-on.md` declares a `pr_precheck` state whose `default_action` runs
      `git rev-parse --abbrev-ref HEAD` with `capture_stdout_as: BRANCH` and a
      `fallback` naming both the manual command and the evidence.
- [ ] Its gate carries a name distinct from `on_feature_branch`, and all of its
      transitions name it.
- [ ] Both edges into `pr_creation` -- from `finalization` and from
      `deferral_approval` -- route through `pr_precheck`.
- [ ] `pr_creation`'s prose reads `{{BRANCH}}` and no longer contains
      `$(git rev-parse --abbrev-ref HEAD)`.
- [ ] `pr_precheck` appears in
      `skills/work-on/koto-templates/work-on.mermaid.md` with its edges.
- [ ] The action's command run twice in sequence exits 0 both times and leaves
      the working tree unchanged.
- [ ] `koto template compile`, `scripts/validate-template-mermaid.sh`, and
      `scripts/check-template-interpolation.sh` all exit 0.

**Dependencies**: None

**Type**: code
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`

### Issue 7: Run the evals for every skill whose content changed

**Goal**: Satisfy the repository's standing rule that a skill whose content
changes has its evals run, and report the outcome honestly.

**Acceptance Criteria**:
- [ ] Every skill touched by issues 1 through 6 is identified from the diff.
- [ ] `scripts/run-evals.sh <skill>` is run for each, or the reason it could
      not be run in this environment is stated plainly.
- [ ] The results, or the plain statement that they could not be run, appear in
      the pull request body in the format `CLAUDE.md` prescribes.
- [ ] No eval result is reported that was not actually produced.

**Dependencies**: Blocked by <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>

**Type**: task
**Files**: none

## Implementation Sequence

**Critical path**: Issue 2 to Issue 4 to Issue 5 to Issue 7. Four units deep,
and the depth is file ordering rather than behavior -- all three of the middle
units edit `execute.md`, and sequencing them keeps the state list coherent and
each diff readable on its own.

**Parallelizable**: Issues 1, 3, and 6 have no dependencies and touch files
nothing else touches. Issue 1 is worth landing first anyway, since every later
unit's review reads against the rule it records, but nothing blocks on it.

**The one unit that has to be last**: Issue 7 reads the diff to decide which
skills changed, so it cannot start until the content changes have landed.

**Where the risk is**: Issue 4. It is the largest diff, it moves a gate between
states, it adds a required template variable that `/execute`'s own `koto init`
must pass, and it deletes a block in `spawn_and_await` that exists to survive
the key being absent. The gate that now guarantees the key is present is what
makes that deletion safe, and a reviewer should check that link specifically.
