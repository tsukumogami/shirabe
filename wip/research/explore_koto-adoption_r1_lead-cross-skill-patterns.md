# Cross-Skill Pattern Analysis for Koto Adoption

Round 1 research output for the koto-adoption exploration. Analyzes 8 shirabe
skills (explore, design, prd, plan, decision, release, review-plan, work-on)
for repeating patterns that koto could standardize.

## Skills Analyzed

| Skill | Koto Integration | Phase Count |
|-------|-----------------|-------------|
| work-on | Full (koto template exists) | 12 states |
| explore | None (prose resume logic) | 6 phases |
| design | None (prose resume logic) | 7 phases |
| prd | None (prose resume logic) | 5 phases |
| plan | None (prose resume logic) | 7 phases |
| decision | None (prose resume logic) | 7 phases |
| release | None (prose phases) | 6 phases |
| review-plan | None (prose resume logic) | 7 phases |

Only work-on has a koto template today. All others encode state machines in
natural language.

---

## Pattern 1: File-Existence Resume

**Description:** Skills check whether wip/ artifacts exist to determine which
phase to resume at. The pattern is always a top-to-bottom conditional chain:
"if file X exists, resume at phase N; else if file Y exists, resume at phase M."

**Skills using it:** explore, design, prd, plan, decision, review-plan (6 of 8)

**How each skill does it:**

- **explore**: Checks for `wip/explore_<topic>_crystallize.md`, then
  `_findings.md` with a "Decision: Crystallize" marker, then `_findings.md`
  without it, then research files, then `_scope.md`, then branch state.
  6-level cascade.
- **design**: Checks design doc status fields ("Accepted", "Proposed"), then
  wip/ files for security report, Solution Architecture section presence,
  Considered Options presence, coordination JSON completeness. 8-level cascade.
- **prd**: Checks PRD status ("Accepted", "Draft"), then wip/ research files,
  then scope file, then branch. 5-level cascade.
- **plan**: Checks GitHub issues, then 6 wip/ artifact files in reverse phase
  order. 7-level cascade.
- **decision**: Checks report, examination, bakeoff, alternatives, research,
  context files. 6-level cascade.
- **review-plan**: Checks review.md, review_loopback.md. 2-level cascade.

**work-on (koto):** Resume is handled by `koto workflows` + `koto next`. The
state machine knows where it left off from the persisted state. No file-existence
checks needed.

**Koto candidate: Strong.** This is the highest-value pattern for koto adoption.
Every non-koto skill reimplements the same "check artifacts, pick phase" logic
in prose. Koto's state persistence eliminates this entire class of instructions.
The work-on template already proves this works. The `context-exists` gate type
directly replaces "if wip/X exists" checks.

---

## Pattern 2: CI Polling

**Description:** Check CI/workflow status, wait for checks to pass, react to
failures.

**Skills using it:** work-on, release (2 of 8)

**How each skill does it:**

- **work-on**: Has a dedicated `ci_monitor` state with a `ci_passing` gate
  that runs `gh pr checks`. Evidence accepts passing/failing_fixed/failing_unresolvable.
  Already in koto.
- **release**: Phase 2 checks CI green on HEAD using a fallback chain
  (`gh api commits/.../status`, then `gh run list`). Phase 6 polls
  `gh run list` every 10 seconds for up to 5 minutes to monitor a dispatched
  workflow.

**Koto candidate: Medium.** work-on already models this as a koto state with
a command gate. Release's Phase 6 polling pattern (retry with timeout) is
different -- it needs a "poll until condition or timeout" primitive that koto
doesn't currently have. The Phase 2 check is a simple gate.

---

## Pattern 3: User Confirmation Gates

**Description:** Ask the user to confirm before proceeding to the next phase.
Blocks workflow execution until user responds.

**Skills using it:** explore, design, prd, release (4 of 8)

**How each skill does it:**

- **explore**: Phase 3 converge presents "Explore further" vs "Ready to decide"
  using AskUserQuestion. Phase 4 crystallize confirms artifact type. Phase 5
  produce confirms handoff.
- **design**: Phase 6 presents complexity assessment with "Plan" vs "Approve only"
  using AskUserQuestion.
- **prd**: Phase 4 validate requires user review before finalizing. Phase 3 draft
  walks through with user for feedback.
- **release**: Phase 3 presents version recommendation with alternatives using
  AskUserQuestion, then allows release notes edits. Confirms both version and
  notes before proceeding.

**work-on (koto):** User confirmation is implicit -- the agent submits evidence
that includes the user's decision. Koto states with enum `accepts` fields
effectively model user choice points.

**Koto candidate: Medium.** Koto's `accepts` with enum values already models
the "pick an option" pattern. What's missing is the presentation layer --
AskUserQuestion formatting with recommendations and descriptions. A koto
primitive could standardize the "present options, collect choice" pattern while
leaving formatting to the skill layer.

---

## Pattern 4: Parallel Agent Fan-Out/Collection

**Description:** Spawn N agents in parallel, wait for all to complete, collect
and synthesize results.

**Skills using it:** explore, design, prd, plan, decision, review-plan (6 of 8)

**How each skill does it:**

- **explore**: Phase 2 fans out lead-specific research agents. Each writes
  `wip/research/explore_<topic>_r<N>_lead-<name>.md`. Phase 3 reads all files.
- **design**: Phase 2 spawns one decision agent per decision question. Each
  writes `wip/design_<topic>_decision_<N>_report.md`.
- **prd**: Phase 2 fans out specialist research agents. Each writes
  `wip/research/prd_<topic>_phase2_*.md`.
- **plan**: Phase 4 spawns agents to generate issue bodies in parallel. Each
  writes `wip/plan_<topic>_issue_*.md`.
- **decision**: Phase 3 spawns N validator agents (persistent, reused in
  Phases 4-5 via SendMessage). Phase 2 spawns N alternative agents (disposable).
- **review-plan**: Adversarial mode spawns 3 validator agents per category
  (12 total) in parallel. Fast-path uses 1 agent per category (4 total).

**work-on (koto):** No fan-out. The template is single-threaded.

**Koto candidate: Strong.** This is the most structurally complex pattern and
appears in 6 skills. Today each skill encodes fan-out/collection in prose
instructions. A koto "parallel" or "fan-out" state type could:
- Declare N parallel sub-tasks
- Collect results into named context keys
- Gate the next state on all sub-tasks completing
- Optionally support persistent agents (decision's validator pattern)

The decision skill's multi-phase validator reuse (spawn in Phase 3, SendMessage
in Phases 4-5) is the most complex variant and would need a "persistent agent
pool" concept.

---

## Pattern 5: Decision Recording

**Description:** Capture decisions with rationale during workflow execution for
auditing and downstream consumption.

**Skills using it:** explore, design, prd, plan, work-on, decision (6 of 8)

**How each skill does it:**

- **explore**: Creates `wip/explore_<topic>_decisions.md` with round-scoped
  decision entries. Appended to across rounds. Format: `- <decision>: <rationale>`.
- **design**: Creates `wip/design_<topic>_decisions.md` (--auto mode). Follows
  `references/decision-protocol.md`.
- **prd**: Creates `wip/prd_<topic>_decisions.md` (--auto mode). Follows
  `references/decision-protocol.md`.
- **plan**: Creates `wip/plan_<topic>_decisions.md` (--auto mode). Follows
  `references/decision-protocol.md`.
- **work-on (koto)**: Uses `koto decisions record <WF> --with-data '{"choice": "...",
  "rationale": "...", "alternatives_considered": [...]}'`. Also accepts `decisions`
  field in analysis and implementation evidence.
- **decision**: The entire skill IS a decision process. Output is a decision
  report.

**Koto candidate: Strong.** work-on already uses `koto decisions record`, proving
koto has this capability. The other 4 skills that create decisions.md files are
doing manually what koto provides natively. Adopting koto for these skills would
eliminate the bespoke decision file management.

---

## Pattern 6: Artifact Validation

**Description:** Check that a file has required sections, valid frontmatter, or
correct structure before proceeding.

**Skills using it:** design, prd, plan, review-plan (4 of 8)

**How each skill does it:**

- **design**: Validates frontmatter fields (status, problem, decision, rationale).
  Checks required sections exist in order. Phase 6 validates rejected alternatives
  have "genuine depth" (strawman check).
- **prd**: References `references/prd-format.md` for structure validation.
  Phase 4 jury review validates completeness and quality.
- **plan**: Phase 6 AI review validates completeness, sequencing, and complexity
  assignments. Phase 7 validates plan doc structure against
  `references/quality/plan-doc-structure.md`.
- **review-plan**: All four categories (A-D) are validation checks against the
  plan artifact. The entire skill is artifact validation.

**Koto candidate: Medium.** Koto's `command` gate type could run validation
scripts (e.g., a frontmatter checker). But the "AI validates quality" checks
are qualitative -- they need agent judgment, not script exit codes. A hybrid
approach: structural validation as command gates, quality validation as
agent-mediated states.

---

## Pattern 7: Status Transitions

**Description:** Change a document's status field from one lifecycle state to
another (e.g., Draft -> Accepted, Proposed -> Planned).

**Skills using it:** design, prd, plan (3 of 8)

**How each skill does it:**

- **design**: Lifecycle states: Proposed -> Accepted -> Planned -> Current -> Archived.
  References `${CLAUDE_PLUGIN_ROOT}/scripts/transition-status.sh` for file movement.
  Phase 6 sets status to "Proposed". Downstream /plan changes to "Planned".
- **prd**: Draft -> Accepted. Phase 4 transitions on user approval.
- **plan**: Changes source design doc from "Accepted" to "Planned" (status field
  only, no body edits). Plan doc itself goes Draft -> Active -> Done.

**Koto candidate: Low-Medium.** Status transitions are simple (update a field,
possibly move a file). They're already handled by a shared script
(`transition-status.sh`). Koto could model document lifecycle as a separate
sub-workflow, but the value is incremental over the existing script approach.

---

## Pattern 8: External Command Gates

**Description:** Run a script or command, check exit code, gate workflow
progression on the result.

**Skills using it:** work-on, release (2 of 8; work-on uses koto command gates)

**How each skill does it:**

- **work-on (koto)**: Multiple command gates:
  - `on_feature_branch`: `test "$(git rev-parse --abbrev-ref HEAD)" != "main"`
  - `staleness_fresh`: `check-staleness.sh --issue {{ISSUE_NUMBER}} | jq -e ...`
  - `code_committed`: compound test (branch check + commit count + go test)
  - `ci_passing`: `gh pr checks ... | grep -q true`
- **release**: Phase 2 runs 6 precondition checks (clean tree, CI green, no
  existing tag, no existing draft, no blockers, security PRs). Each is a
  command with pass/fail semantics.

**Koto candidate: Strong (for release).** work-on already uses koto command
gates effectively. Release Phase 2's precondition checks are a textbook case
for command gates -- 6 independent pass/fail checks that must all pass before
proceeding. Converting release to koto would make these gates declarative.

---

## Pattern 9: Loop Management

**Description:** Repeat a set of phases until a condition is met (user says
stop, quality threshold reached, max rounds hit).

**Skills using it:** explore, design, prd, plan, work-on, review-plan (6 of 8)

**How each skill does it:**

- **explore**: Discover-converge loop (Phases 2-3) repeats until user says
  "Ready to decide." Round counter N increments each iteration. --auto mode
  caps at --max-rounds (default 3).
- **design**: Phase 3 cross-validation may loop back. Phase 6 corrective loop
  with --max-rounds (default 1).
- **prd**: Phases 1-3 may loop back to Discover or Draft based on open questions.
  --max-rounds (default 2).
- **plan**: review-plan Phase 6 loops back to a plan phase when verdict is
  "loop-back", deleting wip/ artifacts back to the target.
- **work-on (koto)**: Self-loops on `scope_changed_retry` (analysis, up to 3),
  `partial_tests_failing_retry` (implementation, up to 3),
  `creation_failed_retry` (pr_creation, up to 3). Uses conditional `when`
  blocks.
- **review-plan**: Phase 6 loop-back deletes artifacts and signals /plan to
  re-enter at a specific phase.

**Koto candidate: Strong.** work-on demonstrates koto's self-loop pattern with
conditional transitions and retry semantics. The explore/prd multi-phase loops
(repeat phases 2-3 with incrementing round counters) are a more complex variant
that needs a "loop over a sub-sequence" primitive -- not just single-state
self-loops. The --max-rounds pattern across explore, design, and prd suggests a
standardized loop counter with configurable cap.

---

## Pattern 10: Context Detection

**Description:** Read CLAUDE.md for repo visibility (Public/Private) and default
scope (Strategic/Tactical), then load content governance skill.

**Skills using it:** explore, design, prd, plan, work-on (5 of 8)

**How each skill does it:**

All five skills follow the same 4-step process with minor variations:

1. Check $ARGUMENTS for --strategic/--tactical flags (scope override)
2. Read CLAUDE.md for `## Repo Visibility: Public|Private`
3. If not found, infer from repo path (`private/` -> Private, `public/` -> Public)
4. Load `skills/private-content/SKILL.md` or `skills/public-content/SKILL.md`

Additionally, explore, design, prd, and plan detect execution mode
(--auto/--interactive) from arguments and CLAUDE.md.

**Variations:**
- explore: Also checks for --max-rounds, --auto. Logs "Exploring with [visibility]
  in [scope]..."
- design: Scope detection also used for context-aware sections (Market Context, etc.)
- plan: Most elaborate flag parsing (--walking-skeleton, --no-skeleton, scope flags,
  execution mode flags)
- work-on: Detects visibility, loads content governance, but no scope detection

**Koto candidate: Strong.** This is pure duplication. The same instructions are
copy-pasted across 5 skills with small wording variations. A koto "context
resolution" phase (or a shared pre-workflow hook) could:
- Run once at workflow start
- Detect visibility, scope, and execution mode
- Set workflow variables that downstream states reference
- Load the correct content governance skill

This could be a standard `context_resolution` state that all koto workflows
include as their first state, or a koto-level plugin that runs before the
initial state.

---

## Summary: Koto Adoption Priority

| Priority | Pattern | Skills | Koto Primitive Needed |
|----------|---------|--------|-----------------------|
| P0 | File-existence resume (1) | 6 | State persistence (already exists) |
| P0 | Context detection (10) | 5 | Shared initial state or pre-hook |
| P0 | Decision recording (5) | 6 | `koto decisions record` (already exists) |
| P1 | Parallel agent fan-out (4) | 6 | Fan-out state type with collection |
| P1 | Loop management (9) | 6 | Sub-sequence loops with round counter |
| P2 | User confirmation gates (3) | 4 | Enum accepts (exists) + presentation hints |
| P2 | External command gates (8) | 2 | Command gate type (already exists) |
| P2 | Artifact validation (6) | 4 | Command gates + agent-mediated states |
| P3 | CI polling (2) | 2 | Poll-until-timeout primitive |
| P3 | Status transitions (7) | 3 | Low incremental value over scripts |

**P0 patterns** require no new koto primitives -- adopting koto for the remaining
skills would eliminate these patterns immediately.

**P1 patterns** need new koto capabilities (fan-out state type, sub-sequence
loops) but cover 6 skills each and represent the most complex prose instructions
currently in SKILL.md files.

**P2-P3 patterns** are either already solved by koto or affect few skills.

### Key Insight

work-on's koto template validates the approach: it eliminated file-existence
resume, command gates, decision recording, self-loops, and CI polling patterns
by modeling them as declarative states. The remaining 7 skills carry 60-80% of
their SKILL.md line count in prose that describes these same patterns. Converting
them to koto templates would shrink each SKILL.md to the domain-specific
instructions (what to research, how to evaluate quality) rather than workflow
mechanics (where to resume, what to check, how to loop).

The two missing koto primitives for full adoption are:
1. **Fan-out/collection**: parallel sub-tasks with result aggregation
2. **Sub-sequence loops**: repeat a range of states with a counter and exit condition
