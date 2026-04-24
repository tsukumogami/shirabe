---
design_doc: wip/explore_work-on-friction-triage_findings.md
input_type: topic
decomposition_strategy: horizontal
strategy_rationale: "Mostly independent fixes to different phases of one skill, not a new feature with end-to-end flow."
confirmed_by_user: true
issue_count: 14
execution_mode: multi-pr
---

# Plan Decomposition: work-on-friction-fixes

## Strategy: Horizontal

Each A-item from the findings doc is atomic and touches a different phase
(context-injection, setup, analysis, implementation, finalization,
pr-creation) or a cross-cutting concern (env vars, tmp paths, AC scripts).
There is no end-to-end flow to skeleton first; each item ships independently.

Seven items are ready to implement directly (title prefix `feat|chore|docs`).
Seven items need a design doc before implementation and are filed as
planning issues (`docs(design): …` + `needs-design` label). When each design
is accepted, it feeds back through `/plan` to spawn its own implementation
issues in a follow-on plan.

## Ordering

A9 (env-var standardization) runs first because A2 touches the same
directives. A2's design should reflect the standardized env var.

Other implementation issues are parallel-ready after A9. Planning issues
are all parallel — independent designs.

## Issue Outlines

### Issue 1: chore(work-on): standardize on CLAUDE_PLUGIN_ROOT env var
- **Type**: standard
- **Complexity**: simple
- **Goal**: Replace all `${CLAUDE_SKILL_DIR}` references with
  `${CLAUDE_PLUGIN_ROOT}/skills/work-on` in SKILL.md and phase files so
  the skill works consistently under Claude Code's plugin loading.
- **Findings ref**: A9
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 2: chore(work-on): add `validation:simple` to phase-5 auto-skip list
- **Type**: standard
- **Complexity**: simple
- **Goal**: Extend the default skip list in
  `references/phases/phase-5-finalization.md` so `validation:simple`-labeled
  issues don't generate a redundant summary artifact.
- **Findings ref**: A5
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 3: docs(work-on): note that AC validation scripts are advisory
- **Type**: standard
- **Complexity**: simple
- **Goal**: Add one paragraph to `references/phases/phase-4-implementation.md`
  (or phase-5) explicitly stating that shell validation scripts in issue
  bodies are advisory, not authoritative — agents verify AC intent, not
  literal script pass.
- **Findings ref**: A13
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 4: feat(work-on): make subagent delegation opt-out for simplified-plan issues
- **Type**: standard
- **Complexity**: testable
- **Goal**: Modify `references/phases/phase-3-analysis.md` so
  simplified-plan issues (labels `docs`, `config`, `chore`, `validation:simple`)
  write the plan inline rather than forcing subagent delegation. Full-plan
  issues continue to delegate.
- **Findings ref**: A4
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 5: feat(work-on): prescribe per-session tmp paths
- **Type**: standard
- **Complexity**: testable
- **Goal**: Update `phase-1-setup.md` and `phase-3-analysis.md` (agent
  instructions) to write local artifacts under `/tmp/koto-<WF>/` rather
  than bare `/tmp/`. Eliminates collisions across concurrent workflows.
- **Findings ref**: A8
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 6: feat(work-on): accept scope_expanded_retry transition from implementation to analysis
- **Type**: standard
- **Complexity**: testable
- **Goal**: Add an `implementation_status: scope_expanded_retry` enum value
  in `koto-templates/work-on.md` with a transition back to `analysis`.
  Lets agents re-plan without `koto rewind`. Regenerate mermaid.
- **Findings ref**: A10
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 7: feat(work-on): add mid-implementation AC re-confirmation step
- **Type**: standard
- **Complexity**: testable
- **Goal**: Add an explicit "re-read acceptance criteria against current
  implementation" step to `references/phases/phase-4-implementation.md`.
  Empirically prevents AC drift in medium-to-complex implementations.
- **Findings ref**: A11
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 8: docs(design): extract-context DESIGN doc resolution across branches and repos
- **Type**: planning
- **Complexity**: simple
- **Goal**: Decide how `extract-context.sh` should resolve a DESIGN doc
  when it lives on a remote branch or in a sibling repo. Options: scan
  `origin/*` refs, use a workspace manifest (niwa), require an explicit
  `Design:` path + repo annotation on issues, or punt.
- **Findings ref**: A1
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 9: docs(design): staleness_check gate portability in shirabe
- **Type**: planning
- **Complexity**: simple
- **Goal**: Decide how to make the `staleness_check` gate work on a
  shirabe-only install. Options: port `check-staleness.sh` into shirabe,
  make the gate conditional on script availability, move staleness into
  koto, or drop the gate.
- **Findings ref**: A2
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: Issue 1 (env var standardization — any script paths
  in the design must use `${CLAUDE_PLUGIN_ROOT}`)

### Issue 10: docs(design): pre-existing baseline failure envelope
- **Type**: planning
- **Complexity**: simple
- **Goal**: Decide how the setup phase captures and routes baseline
  failures that exist before the current change. Options: new evidence
  value `baseline_status: broken_preexisting`, a dedicated gate, or a
  documented human-in-the-loop escape.
- **Findings ref**: A3
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 11: docs(design): pre-push confirmation gate with --auto mode
- **Type**: planning
- **Complexity**: simple
- **Goal**: Decide how `phase-6` and the `pr_creation` state should pause
  for user confirmation before `git push` and `gh pr create`, while still
  behaving in `--auto` mode (decision protocol or silent proceed).
- **Findings ref**: A6
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 12: docs(design): multi-issue bundling as a first-class /work-on flow
- **Type**: planning
- **Complexity**: simple
- **Goal**: Design how `/work-on` handles the "bundle another issue onto
  an existing branch and PR" flow. Options: a new invocation (`/work-on
  --bundle #N`), a dedicated state, a helper script, or a PR-body
  template. Likely the highest-impact fix; explicit design warranted.
- **Findings ref**: A7
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None

### Issue 13: docs(design): per-branch context findings cache
- **Type**: planning
- **Complexity**: simple
- **Goal**: Decide the cache key scheme and storage location for
  `extract-context.sh` findings so sibling issues on the same branch skip
  redundant remote-branch lookups. Options: koto context key, tmp file,
  or git-branch-scoped state.
- **Findings ref**: A12
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: Issue 8 (the resolution strategy decided in A1
  determines what the cache key looks like)

### Issue 14: docs(design): monorepo-aware baseline scoping
- **Type**: planning
- **Complexity**: simple
- **Goal**: Decide how the setup phase detects monorepo structure and
  scopes baseline tests to touched packages. Intersects with the
  language-skill question — decide whether scoping lives in work-on or
  in a future nodejs/go/rust language skill.
- **Findings ref**: A14
- **needs_label**: needs-design
- **Milestone**: Work-on Friction Fixes
- **Dependencies**: None
