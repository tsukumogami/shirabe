# Phase 4: Validate

Three-agent jury review followed by finalization and user approval.

## Goal

Validate the ROADMAP draft through independent review by three specialist agents, fix
any issues found, then finalize the ROADMAP with the user.

## Resume Check

If `wip/research/roadmap_<topic>_phase4_*.md` files exist, skip to step 4.3
(Process Feedback).

## Approach: 3-Agent Jury

Launch 3 agents with fixed roles. Each evaluates the ROADMAP from a different quality
dimension, all specific to what makes a roadmap effective.

### 4.1 Launch Jury Agents

Load `skills/roadmap/references/roadmap-format.md` and pass the relevant quality
guidance to each agent.

Launch all 3 agents in parallel using the Agent tool with `run_in_background: true`.

Each agent receives:
- The ROADMAP draft (read from `docs/roadmaps/ROADMAP-<topic>.md`)
- Their role and evaluation criteria
- The scope document (`wip/roadmap_<topic>_scope.md`) for reference

#### Theme Coherence Reviewer

```
You are reviewing a ROADMAP document for theme coherence and feature quality.
Your job is to test whether the features belong together and each is at the
right level of granularity.

## ROADMAP to Review
[Contents of docs/roadmaps/ROADMAP-<topic>.md]

## Original Scope
[Contents of wip/roadmap_<topic>_scope.md]

## Evaluate
1. Do all features belong under the stated theme? Could any feature be removed
   without weakening the theme, or does each contribute to the coordinated
   initiative?
2. Is each feature independently describable at PRD level? A feature that can't
   stand alone as a PRD is too granular. A feature that would need multiple PRDs
   is too broad.
3. Are there at least 2 features? Single-feature work doesn't need a roadmap.
4. Is the theme itself coherent? Does it explain WHY these features need
   coordinated sequencing rather than independent delivery?
5. Are feature rationales specific to this roadmap, or could they apply to any
   project? Generic rationales suggest weak theme coherence.

## Output Format
Write your full review to `wip/research/roadmap_<topic>_phase4_theme-coherence.md`:

# Theme Coherence Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Sequencing and Dependency Reviewer

```
You are reviewing a ROADMAP document for sequencing correctness and dependency
integrity. Your job is to test whether the ordering is justified and dependencies
are explicit and acyclic.

## ROADMAP to Review
[Contents of docs/roadmaps/ROADMAP-<topic>.md]

## Original Scope
[Contents of wip/roadmap_<topic>_scope.md]

## Evaluate
1. Are all dependencies explicit? Check for implied ordering that isn't captured
   as a stated dependency. If Feature B uses something Feature A produces, that's
   a dependency even if not listed.
2. Is the dependency graph acyclic? Trace the dependencies -- no feature should
   transitively depend on itself.
3. Does the sequencing rationale explain WHY this order, not just state the order?
   "Feature A before B" isn't a rationale. "Feature A before B because A produces
   the API that B consumes" is.
4. Are parallelization opportunities acknowledged? Features with no mutual
   dependencies should be noted as parallelizable. Ignoring parallelization
   suggests the sequencing wasn't thought through.
5. Are hard blockers distinguished from soft preferences? Conflating the two
   creates artificial bottlenecks.

## Output Format
Write your full review to `wip/research/roadmap_<topic>_phase4_sequencing-dependency.md`:

# Sequencing and Dependency Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Annotation and Boundary Reviewer

```
You are reviewing a ROADMAP document for annotation accuracy and content boundary
violations. Your job is to check that needs-* labels are correct and the roadmap
doesn't contain downstream content.

## ROADMAP to Review
[Contents of docs/roadmaps/ROADMAP-<topic>.md]

## Original Scope
[Contents of wip/roadmap_<topic>_scope.md]

## Evaluate
1. Do needs-* labels match feature descriptions? If a feature says "needs-design"
   but the description implies requirements aren't written yet, the label should
   be "needs-prd" instead.
2. Does the roadmap contain downstream content that belongs in other artifacts?
   Check for:
   - Feature requirements or user stories (belongs in a PRD)
   - Technical architecture decisions (belongs in a Design Doc)
   - Implementation tasks or issue lists (belongs in a Plan)
   - Dates or deadlines (roadmaps sequence features, not calendar time)
3. Are all features marked "Not Started"? At creation time, no feature should
   have progress.
4. Does the roadmap pass structural validation? Check against the format spec:
   required sections present, frontmatter correct, status is "Draft".
5. Are scope boundaries clear? The "covers" and "doesn't cover" should leave no
   ambiguity about what work falls inside this roadmap.

## Output Format
Write your full review to `wip/research/roadmap_<topic>_phase4_annotation-boundary.md`:

# Annotation and Boundary Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

### 4.2 Collect Results

Wait for all 3 agents to complete. Read their summaries.

### 4.3 Process Feedback

**Reference**: Full review details available in `wip/research/roadmap_<topic>_phase4_*.md`.

Determine consensus:

| Outcome | Action |
|---------|--------|
| All 3 pass | Proceed to finalization |
| 1-2 fail with minor issues | Fix issues, briefly show fixes to user, proceed |
| Any fail with significant issues | Present issues to user, incorporate fixes, re-validate if changes are substantial |
| Agents disagree on same issue | Present both perspectives to user, let user decide |

**For minor issues** (wording fixes, sharpening a needs-* label, clarifying a
dependency): Fix directly, update the ROADMAP, show the user what changed.

**For significant issues** (circular dependencies, missing features, downstream
content mixed in, sequencing without rationale): Present the jury's findings to the
user with specific recommendations. Use AskUserQuestion when the findings surface
trade-offs or decisions. If changes are substantial (feature additions, dependency
rewrites), loop back to Phase 3 step 3.5.

### 4.4 Finalize ROADMAP

After all issues are resolved:

1. Update the ROADMAP with all fixes
2. Verify the ROADMAP passes the format reference's validation rules
3. Commit: `docs(roadmap): finalize ROADMAP for <topic>`

### 4.5 Present to User

Present a brief summary:
- Theme (1 sentence)
- Feature count
- Key dependencies
- Any known open questions remaining

Use AskUserQuestion to ask for approval. Provide context explaining the ROADMAP is
validated and ready for activation. Options:
- **Approve** -- status changes to Active, ready for downstream work
- **Request changes** -- specify what needs to change

### 4.6 Handle Approval

**If user approves:**
1. Run `scripts/transition-status.sh <path> Active` to transition from Draft to Active
2. Commit: `docs(roadmap): activate ROADMAP for <topic>`
3. Create PR (or update existing PR if on a shared branch)

Then present routing options:

"The ROADMAP is active. Based on the features and their annotations, here are the
recommended next steps:"

| Situation | Suggestion |
|-----------|-----------|
| Features need requirements | /prd for features marked needs-prd |
| Features need architecture | /design-doc for features marked needs-design |
| Ready to plan implementation | /plan to break features into issues |

**If user wants changes:**
Return to Phase 3 step 3.5 to incorporate the specific feedback. Don't re-walk
the entire doc -- focus on the areas the user identified.

### 4.7 Cleanup

After the PR is created, clean up temporary artifacts:

```bash
rm -f wip/roadmap_<topic>_scope.md
rm -f wip/research/roadmap_<topic>_phase2_*.md
rm -f wip/research/roadmap_<topic>_phase4_*.md
```

Commit: `chore(roadmap): clean up working artifacts`

## Quality Checklist

- [ ] All 3 jury agents reviewed the ROADMAP
- [ ] All issues from jury review are resolved
- [ ] User has approved the ROADMAP

## Artifact State

Final ROADMAP at `docs/roadmaps/ROADMAP-<topic>.md` with:
- Status "Active" (after user approval)
- All features with correct needs-* annotations and "Not Started" status
- Working artifacts cleaned up (scope doc, research files removed)
