# Lead: How does `/plan` choose the execution mode, and can a caller steer it or learn it early?

## Findings

### 1. The rule: default to one PR, split only on a named branch

The authoritative rule is `skills/plan/SKILL.md` lines 151-195 ("Execution Mode
Decision"). The default comes from the repo's Delivery Preference, resolved on a
`flag > CLAUDE.md ## Delivery Preference: header > consolidated` stack
(SKILL.md:158-161). Under `consolidated` (every repo that declares nothing) the
default is `single-pr`. A split needs one of three named branches, defined once in
`references/split-triggers.md` (Shared Core, lines ~20-65):

- **Hard Constraint** -- "a named, non-optional condition that makes a single pull
  request impossible": cross-repo landing order, a workflow file that must reach
  the default branch before anything can invoke it, a step whose output must be
  published/deployed/merged before a later step consumes it, a merge gate between
  steps. Explicitly: "This would be a large diff" is not a hard constraint.
- **Incremental Value** -- each unit is independently useful to a reader who meets
  it alone. "Could be separate pull requests" is not the test.
- **Stated Preference** -- "The repository has said, on the durable CLAUDE.md
  convention channel, that it wants this shape" (i.e. `## Delivery Preference:
  atomic`). This is where reviewability lives.

The procedure is `skills/plan/references/phases/phase-3-decomposition.md` step 3.6
(lines 492-590). It runs after the value-confirmation guard (step 3.5a, lines
400-488), resolves the Delivery Preference (step 3 of the procedure, line 521),
then maps the situation to a mode + branch (lines 525-538):

| Situation | Mode | Branch |
|---|---|---|
| Roadmap input | multi-pr | Incremental Value |
| Plan input with a named hard constraint | multi-pr | Hard Constraint |
| Plan input where each PR is independently useful | multi-pr | Incremental Value |
| `atomic` preference, decomposition permits a split | multi-pr | Stated Preference |
| `consolidated`, no branch fires | single-pr | none, nothing recorded |
| `atomic` but stays single-pr | single-pr | still owes a branch |

The branch is written into the PLAN's `split_rationale` frontmatter and checked by
validator rule `L09` (`skills/plan/references/plan-format.md` lines 47-83). A
`single-pr` PLAN under `consolidated` omits the field.

Interactive mode presents the recommendation via AskUserQuestion and accepts an
override (phase-3 lines 551-574, "Use <recommended mode>, or override?"). Under
`--auto` the recommendation is followed; a multi-pr choice without a hard
constraint or clear per-unit value rationale is recorded as `assumed` at high
review priority (lines 576-579).

Note the asymmetry in the value guard: "A plan the author intends to land in a
single PR has one unit (the whole plan) and that unit passes by construction"
(phase-3 ~line 423). So the guard can only push away from multi-pr, never toward it.

### 2. Can a caller steer it? Only through two channels

- **The CLAUDE.md header** `## Delivery Preference: consolidated|atomic`
  (`references/fixes/claude-md-conventions.md` lines 75-86). This is repo-wide and
  durable, not per-invocation.
- **The interactive override** at step 3.6. A human (or the agent answering the
  AskUserQuestion) can pick the other mode.

The "flag" layer of the `flag > header > default` stack is documented
(SKILL.md:160, phase-3:521, `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md`
line 484) but **no such flag exists** in `/plan`'s flag parser (SKILL.md:272-300
lists only `--auto`, `--interactive`, `--strategic`, `--tactical`,
`--walking-skeleton`, `--no-skeleton`, `--upstream`). There is no `--single-pr`,
`--multi-pr`, `--delivery=...` or equivalent.

"Stated Preference" cannot come from the session's goal text. split-triggers.md
defines it strictly as a CLAUDE.md declaration, and only the `atomic` direction is
a split trigger at all. Since `consolidated` is already the default, "prefer
single-pr unless a hard constraint forces otherwise" is essentially what the
default rule already says -- except that **Incremental Value** can still push a
plan to multi-pr even under `consolidated`, and there is no knob that disables that
branch. So there is no mechanism to say "Hard Constraint only".

### 3. `/scope` passes nothing that affects the mode

`skills/scope/references/phases/phase-2-chain-orchestration.md` lines 188-195: the
`/plan` hop is invoked as `/plan docs/designs/DESIGN-<topic>.md` plus
`--upstream <roadmap-path>` when a roadmap was consumed. Nothing else. Lines 256-263
and `references/parent-skill-pattern.md` lines 329-365 forbid a parent from adding
flags a child does not already own ("the test separating the two is whether the flag
works when the parent is absent"). The only other parent-to-child channel is the
`parent_orchestration:` sentinel (invoking_child, suppress_status_aware_prompt,
rationale -- parent-skill-pattern.md 550-560), which carries no delivery hint.

`/scope`'s own `--auto` (scope SKILL.md:166-181) is not shown as propagated to the
`/plan` invocation either; `/plan` falls back to the CLAUDE.md `## Execution Mode:`
header (SKILL.md:281), which shirabe's CLAUDE.md does not declare.

### 4. How `coordinated` gets chosen -- not by `/plan`'s step 3.6

`coordinated` is defined as the multi-repo generalization of multi-pr (SKILL.md
197-219; `references/coordination-strategy.md` lines 25-47). But step 3.6's
procedure and the SKILL.md summary (line 472: "chooses single-pr or multi-pr")
only produce `single-pr` or `multi-pr`; no branch in 3.6 emits `coordinated`, and
phase-3/phase-4 templates only offer the two values.

Coordination is instead decided by `/scope` at Phase 0 as **coordination intent**
(scope SKILL.md 202-224): `--coordinated` / `--no-coordinated` flag, then the
`## PR Grouping Policy:` and `## Reviewability Ceiling:` headers, then single-repo.
When intent is present, `/scope` creates the coordination PR up front, before any
child runs. So `coordinated` is the one mode a caller *can* choose at launch -- but
it is chosen on `/scope`, not `/plan`, and the handoff that makes `/plan` write
`execution_mode: coordinated` is not visible in the `/plan` hop's arguments.

### 5. Does an earlier hop predict the mode?

Partly. `/plan` Phase 1 copies the DESIGN's "Implementation Approach -- phased build
plan" into its analysis (`skills/plan/references/phases/phase-1-analysis.md`
line 122; `skills/design/SKILL.md` line 89). Every Hard Constraint instance is a
fact already visible in the DESIGN: cross-repo scope, a reusable workflow that must
land before invocation, a publish/deploy step before consumption. Those are strong
predictors. Incremental Value is judged only at decomposition (3.5a/3.6), so it
isn't knowable before `/plan` runs. BRIEF and PRD carry no delivery-shape field;
no skill in the chain mentions `execution_mode` before `/plan` (the only DESIGN
mention is design-format.md:146-150 on who owns the issues table).

The mode is learnable the moment `/scope` finishes: the PLAN frontmatter carries
`execution_mode`, and `/scope`'s state file records `plan_execution_mode:
single-pr | multi-pr | coordinated` at full-run exit
(`skills/scope/references/phases/phase-3-exit-finalization.md` lines 43-66). Status
also differs: Draft for single-pr, Active (with milestone) for multi-pr/coordinated.

### 6. How often each mode is chosen

Only one PLAN is on disk (`docs/plans/PLAN-work-on-friction-fixes.md`, multi-pr,
Incremental Value, a planning-issue plan). PLANs are working artifacts deleted by
the completion cascade, so git history (`git log --all -G execution_mode: --
docs/plans`) is the better sample:

- **single-pr (7):** work-on-koto-unification (2026-04-14), completion-cascade,
  work-on-hardening, work-on-skip-if, lifecycle-draft-ready-discipline (2026-06-06),
  execute-friction (2026-06-21), skill-adherence-enforcement (2026-08-15).
- **multi-pr (5):** reusable-release-system (2026-03-28), shirabe-scope-skill,
  roadmap-plan-standardization, shirabe-cli-rust-rewrite (all ~2026-05-31),
  work-on-friction-fixes (first written single-pr, later multi-pr).
- **coordinated (0).**

The multi-pr ones are large multi-feature efforts or planning-issue plans; every
single-feature plan since June is single-pr. The sample undercounts single-pr:
a single-pr PLAN committed and deleted within one squash-merged branch leaves no
trace on reachable refs.

## Implications

- For the "run /scope then /execute until merged" session, the mode is not
  knowable at launch but is cheaply knowable at the `/scope`-to-`/execute` seam:
  read `execution_mode` from the PLAN frontmatter (or `plan_execution_mode` in the
  scope state file) and branch there. That's the natural decision point.
- In a `consolidated` repo (the default), a single feature lands `single-pr` unless
  a Hard Constraint or genuine Incremental Value fires. Hard Constraints are
  mostly predictable from the DESIGN; Incremental Value is the unpredictable part.
- There is no sanctioned per-invocation way to say "prefer single-pr unless a hard
  constraint forces it." Options would be: (a) implement the documented-but-missing
  delivery flag on `/plan` (it would pass the parent-skill test, since it works
  without a parent), and have `/scope` forward it; (b) the session answers the 3.6
  override prompt with single-pr when no Hard Constraint is named; (c) no change,
  accept the mode and route multi-pr to a different endgame.
- `coordinated` is the one mode a launcher controls up front (`/scope --coordinated`),
  so a session goal can know in advance whether it's in coordinated territory.

## Surprises

- The Delivery Preference stack names a "flag" layer everywhere, but `/plan`
  defines no flag for it. The documented steering hook doesn't exist.
- `/plan` step 3.6 never emits `coordinated`; the mode comes from `/scope`'s Phase 0
  intent, and how it reaches the PLAN frontmatter isn't visible in the `/plan` hop's
  argument list.
- shirabe's own CLAUDE.md declares `## PR Grouping Policy: coarsest-legal` and
  `## Reviewability Ceiling: default`, the very headers `/scope` reads for
  coordination intent. The evals treat intent as absent without a
  "coordinated-default header," so presence alone probably doesn't turn it on, but
  the rule for what value counts as a coordinated default isn't spelled out in
  scope SKILL.md.
- `/scope --auto` isn't forwarded to `/plan`, so the 3.6 prompt's behavior inside a
  `/scope --auto` run depends on the agent, not the contract.

## Open Questions

- How does `/plan` learn coordination intent from `/scope` to write
  `execution_mode: coordinated`, given the hop passes only the DESIGN path? (Maybe
  through the design's cross-repo content, maybe undocumented.)
- Would adding a real `--delivery=consolidated|atomic` (or a "hard-constraint-only")
  flag to `/plan` be acceptable under the L13 parent-skill rule? It would pass the
  "works with no parent" test, but `/scope` forwarding it is new wiring.
- In a `/scope --auto` run, does `/plan` behave as `--auto` at step 3.6, or does it
  prompt?
- Should Incremental Value be suppressible for single-feature plans, or is it the
  right call that a feature with independently useful slices splits?

## Summary

`/plan` defaults to `single-pr` under the repo's Delivery Preference (`consolidated` unless CLAUDE.md says `atomic`) and splits only on a named branch (Hard Constraint, Incremental Value, or a CLAUDE.md-declared Stated Preference), recorded in `split_rationale`. `/scope` passes nothing that affects this: it hands `/plan` only the DESIGN path plus `--upstream`, the "flag" layer of the preference stack is documented but no flag exists, and session goal text can't count as a Stated Preference, so there's no way to say "single-pr unless a hard constraint forces it" beyond the interactive override at step 3.6. `coordinated` is the exception, chosen up front via `/scope --coordinated` or headers rather than by `/plan`. Otherwise the mode is only knowable when `/scope` exits (PLAN frontmatter and `plan_execution_mode` in the state file), though Hard Constraints are usually visible in the DESIGN already. History shows 7 single-pr, 5 multi-pr and 0 coordinated PLANs, and every single-feature plan since June was single-pr.
