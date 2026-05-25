# Brief Content-Quality Verdict: shirabe-scope-skill

## Verdict: PASS

## Findings

### Problem Statement

The Problem Statement frames a genuine problem rather than smuggling a solution. The gap is named at three altitudes: (a) the surface gap — authors "re-derive the sequencing decisions on every run" and "carry context manually with no resume contract"; (b) the architectural gap — "the parent-skill pattern v1 ... has invariants that cannot be ratified for the parent skills that follow until a second parent stands them against a chain with genuinely different shape"; (c) the enforcement gap — "the work is done by discipline alone, and discipline is exactly the wrong substrate for an invariant."

The five-part enumeration ("No parent skill entry point", "No codified delegation graph", "No resume ladder across four child boundaries", "No terminal-artifact enforcement for the tactical chain", "No pattern-validation evidence beyond `/charter`") names what's missing in the world a reader inhabits today, not what gets built. The closing paragraph reinforces the framing: "The problem is not that authors can't sequence the tactical chain by hand. They do, every day. It's that without `/scope`, the tactical chain's invariants are unenforceable..." That is problem-shaped.

The named asymmetries (two re-evaluation boundaries, no-Phase-5-Reject default, multi-output-mode terminal child) are presented as gaps in the pattern's coverage of the tactical chain rather than as features `/scope` adds — which is the right framing at brief altitude.

PASS.

### User Outcome

The outcome opens by naming the user concretely ("A skill author opens Claude Code in shirabe...") and walks the experience: "invokes `/scope`. The skill opens with discovery: it inspects the durable artifacts already on disk... detects how far the tactical conversation has already gone, and proposes a chain to run from the most-downstream settled point. The author sees the chain plan, can adjust it, and confirms... The author never has to remember the order, the gates, or which artifact triggers which entry; the skill enforces the chain."

That is outcome-shaped — what an author can now do, what friction is gone — not a feature list. The two Mermaid diagrams (chain decision flow, three-exit decision flow) illustrate the experience rather than enumerating components.

The three durable exits (full-run, re-evaluation at either boundary, abandonment-forced) are framed as terminal experiences ("The chain reaches PLAN", "the lightweight exit satisfies the terminal-artifact contract", "The chain leaves a review surface regardless of how it ended"), not as code features. The resume and manual-fallback paragraphs continue the outcome framing ("The author can resume", "Authors and reviewers retain full control... `/scope` provides discipline without becoming a bottleneck").

The final paragraph ("Downstream, `/scope` shipping validates the parent-skill pattern v1...") names a second-order outcome — what becomes true downstream once the chain ships — rather than enumerating features built. The frontmatter `outcome:` paraphrases the prose accurately (orient on durable upstream artifacts, propose a chain, three durable exits, cross-boundary resume and manual fallback as first-class).

PASS.

### User Journeys

Five journeys, each with a name heading and the three required elements.

**Journey 1: Skill author, cold standalone invocation.** User: skill author. Trigger: "opens Claude Code in shirabe with a feature named on the roadmap and no durable upstream artifacts yet" + "invoke `/scope <topic-slug>` with the topic slug as the only argument". Outcome shape: full chain `/brief → /prd → /design → /plan`, terminal artifact (PLAN-Draft single-pr or PLAN-Active multi-pr), chain halts for review.

**Journey 2: Author with PRD already Accepted.** User: skill author. Trigger: returns to a feature whose PRD has already landed (either prior direct `/prd` run or interrupted prior `/scope`). Outcome shape: `/brief` auto-skips and records into `chain_skipped`; chain runs `/design` then `/plan`; lands terminal artifact. Distinct from Journey 1 by entry-point state (Accepted PRD upstream) and the gate-vocabulary lesson exercised (Mandatory-with-auto-skip).

**Journey 3: Author returns for re-evaluation at the DESIGN boundary.** User: skill author. Trigger: returns to a topic six weeks after an Accepted DESIGN landed, wants to verify the architecture still holds before `/plan`. Outcome shape: chain proposes Re-evaluate/Revise/Bail at the DESIGN boundary; on Re-evaluate, `/scope` writes `DECISION-design-<topic>-re-evaluation-<date>.md` referencing the existing DESIGN, does not re-author. Distinct from Journeys 1-2 by exercising a different terminal exit (re-evaluation Decision Record vs full-run).

**Journey 4: Mid-chain abandonment forcing materialization.** User: skill author. Trigger: starts a `/scope` run, `/brief` accepts, `/prd` enters discover phase, author switches tasks for a week, then either tells `/scope` to wrap up or the resume ladder detects partial state. Outcome shape: `/scope` forces `/prd` to materialize a Draft PRD from partial state with a Status block noting abandonment-forced; chain leaves a review surface. Distinct by exercising the third exit path and by the discipline-under-interruption test.

**Journey 5: Reviewer redirects mid-chain via manual fallback.** User: reviewer (the only journey with a different user role). Trigger: reads a Draft PRD produced by an earlier `/scope` run, decides Acceptance Criteria pre-suppose unmade design decisions, invokes `/prd` directly outside `/scope`. Outcome shape: `/prd` runs standalone, produces revised Draft at the same path, `/scope` does not interfere; later `/scope` resume warns that downstream DESIGN may be stale but does not act. Distinct by user role (reviewer, not author), by entry into the chain from outside, and by exercising the R13 manual-fallback non-interference rule.

All five journeys are concrete (named paths like `wip/prd_<topic>_*`, `docs/designs/current/DESIGN-<topic>.md`, exact Decision Record filenames). All five are distinct (different upstream-artifact states, different exits exercised, different invocation pathways). None are vignettes. None are "the user uses the skill" retold.

PASS.

### Scope Boundary

**In-list specificity (9 items).** Each names a concrete artifact or contract: the `/scope` SKILL.md following the parent-skill template; the four delegation contracts at each child boundary with gate vocabulary spelled out (Feeder-EITHER for `/brief`, Mandatory-with-auto-skip for `/prd`, shape-dependent for `/design`, ALWAYS-terminal for `/plan`); three exit paths with specific Decision Record filenames; resume ladder across four boundaries with the three-PLAN-status and DESIGN-directory-move asymmetries enumerated; pattern-level edits (new gate vocabulary entry in `references/parent-skill-pattern.md`, new `references/parent-skill-worktree-discipline.md`, L9 reclassification); Phase-N Reject contracts on `/prd` and `/design` as prerequisites; shared design doc rename from `DESIGN-shirabe-explore-split.md` to `DESIGN-shirabe-scope-skill.md`; workspace and shirabe CLAUDE.md updates; manual-redirect workflow as first-class; eval suite at `skills/scope/evals/evals.json`. Each item is sized for a downstream PRD author to know where the boundary sits.

**Out-list realness (8 items).** Each exclusion is a boundary a downstream author could plausibly cross by accident:

- `/work-on` migration into the pattern (SE8) — closely adjacent amplifier-layer work; named as separate feature.
- Review-time redirect mechanism (SE9) — natural extension of the manual-fallback story; explicitly deferred.
- Pattern-ergonomics tightening (SE12) — the SE4 retrospective folds that aren't v1-cheap.
- Re-litigating pattern invariants I-1 through I-7 — the pattern's seven semantic invariants stand as ratified; `/scope` adds vocabulary, not edits.
- Amplifier-layer workflow substrate — the migration into workflow-composition infrastructure.
- niwa workspace context surface — current CLAUDE.md visibility detection used as-is.
- Migration of existing tactical-progression artifacts — children's existing schemas unaffected.
- Authoring `/brief`, `/prd`, `/design`, `/plan` skill bodies — `/scope` consumes them as they ship; only Phase-N Reject contract extensions in scope.

No strawman exclusions ("not solving world hunger"). Each OUT item is a real adjacency a reader could otherwise assume sits inside the boundary. The Phase-N Reject contract carve-out is especially load-bearing: it preserves the symmetry premise while bounding the child-side work to one specific contract extension.

PASS.

### Open Questions

Seven questions present; the brief is in Draft status (matches the Draft-only constraint). Each defers a framing detail to the downstream PRD:

1. **Cascading pattern-level decisions enumeration.** Defers the exact requirement count and rollout sequencing across PRs to the PRD. The brief sketches the six cascades at framing altitude; the PRD operationalizes.
2. **Decision Record sub-shape inventory.** Defers single-sub-shape-with-parameter vs two-distinct-sub-shapes choice to the PRD, citing `/charter`'s precedent.
3. **`/plan` output-mode state binding.** Names the field (`execution_mode: single-pr | multi-pr`) and defers the read-rule and re-entry semantics to the PRD.
4. **`--max-rounds=N` default.** Defers the 3-vs-5 default and override surface; gives rationale (tactical chains have two re-evaluation boundaries and faster churn).
5. **Stale-session threshold.** Defers the 7-day default vs alternative to the PRD, noting that the pattern doesn't constrain.
6. **Validator pass-through scope.** Defers the exact `shirabe validate` invocation surface per boundary to the PRD, with the strict-pass-through stance already settled by exploration.
7. **Behavior against Active or Done PLAN.** Defers the redirect prompt wording and resume-ladder row to the PRD; the refuse-and-redirect direction is settled.

None of these are blockers masquerading as questions. Each names what the brief has settled (the architectural stance) and what the PRD will pick (the operational detail). The brief explicitly states "None block this brief", which is consistent with the question content.

PASS.

## Public-Repo Discipline

The BRIEF lands in shirabe (Public). Reviewed for private-repo references:

- All cited paths are inside shirabe (`skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`, `skills/charter/SKILL.md`, `references/parent-skill-pattern.md`, `references/parent-skill-state-schema.md`, `references/parent-skill-resume-ladder-template.md`, `references/parent-skill-child-inspection.md`, `references/parent-skill-worktree-discipline.md`, `references/cross-repo-references.md`, `skills/explore/references/phases/phase-2-discover.md`, `skills/explore/references/phases/phase-3-converge.md`, `docs/briefs/BRIEF-shirabe-charter-skill.md`, `docs/designs/DESIGN-shirabe-scope-skill.md`).
- No `private/` paths, no `vision/`, no `coding-tools/`, no `dot-niwa-overlay/`.
- No issue numbers (the brief uses `SE7`, `SE8`, `SE9`, `SE12` — these are roadmap-feature codes from the public roadmap exploration handoff, not GitHub issue references).
- No internal codenames or pre-announcement features beyond what the exploration handoff already cited publicly.
- The `upstream:` frontmatter field is absent, which is acceptable for a brief authored against a roadmap-feature topic with no single durable upstream document. The brief notes the roadmap context in prose without naming a private path.

CLEAN. No public-visibility flags.

## Required Revisions

None. The BRIEF passes content-quality review.
