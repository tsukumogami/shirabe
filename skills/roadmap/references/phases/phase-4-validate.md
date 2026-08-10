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
3. Is there at least one feature? A roadmap with none has nothing to track.
   A one-feature roadmap is legitimate -- it is still the progress ledger for
   the strategy's execution and still the bridge into the tactical chain --
   so do not fail a roadmap for having exactly one feature.
4. Is the theme itself coherent? Does it explain WHY this is one tracked
   initiative rather than unrelated independent work?
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
| Agents disagree on same issue | Present both perspectives, recommend the better-supported one, let the user override |

**Reviewer disagreement:** quote both perspectives, then say which one you find
better supported and why, citing the specific verdict finding that decides it.
If the two are genuinely balanced, say so explicitly, still recommend one, and
name the tiebreaker. The user overrides if they disagree.

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
2. Populate the reserved sections (see 4.4a below)
3. Verify the ROADMAP passes the format reference's validation rules
4. Commit: `docs(roadmap): finalize ROADMAP for <topic>`

#### 4.4a Populate the reserved sections

The Implementation Issues and Dependency Graph sections are reserved for
the tool and ship as empty skeletons. Fill them here, before the author
reviews the roadmap in 4.5, so what they approve is what merges:

```bash
shirabe roadmap populate <roadmap-path> --no-issues
```

Three things about this step:

- **It is issueless, always.** The `--no-issues` flag is passed
  unconditionally, regardless of what `## Roadmap Issues:` resolved to
  during setup. An automatic run must never create GitHub issues; the
  preference governs only what a human-invoked `/roadmap populate <path>`
  does. Pass the flag explicitly rather than relying on the subcommand's
  default.
- **The R14 approval gate does not apply.** Nothing is created, so there
  is nothing to approve. Do not present the gate here.
- **Warnings are worth surfacing.** The run reports on stderr when a
  feature's label could not serve as a table key (it falls back to `F<n>`)
  or when a description had to be truncated. Include any such warning in
  the 4.5 summary -- it names a feature the author may want to rename or
  give a shorter opening.

If the roadmap has no Features section content yet, populate fails with a
clear error. That is a real problem with the draft, not a reason to skip
this step: return to Phase 3 and fix the Features section.

### 4.5 Present to User

Present a brief summary:
- Theme (1 sentence)
- Feature count
- Key dependencies
- Any known open questions remaining

Use AskUserQuestion to ask for approval. Frame the question as the agent
recommending activation based on the jury verdicts, not neutrally presenting
options; the user's verdict is the gate. Options:
- **Approve (Recommended)** -- status changes to Active, ready for downstream work
- **Request changes** -- specify what needs to change

**Description field:** Ground the recommendation in the jury verdicts -- name
which reviewers passed and any finding they flagged as non-blocking (e.g., "All
three reviewers passed; the dependency validator flagged the Feature C stub as
borderline but not blocking. Recommending Approve."). If a reviewer's residual
concern makes activation the weaker call, recommend Request changes instead and
cite the finding that drove it.

### 4.6 Handle Approval

**If user approves:**
1. Re-run the issueless population, so the sections reflect any edit made
   during review:
   ```bash
   shirabe roadmap populate <roadmap-path> --no-issues
   ```
   The feature list locks once the roadmap leaves Draft, so this is the last
   moment the sections can be brought into agreement with the Features
   section. Populate is idempotent -- when nothing changed since 4.4a this
   rewrites the same bytes and the commit in step 3 is empty of section
   changes. Still issueless, still no R14 gate.
2. Run `shirabe transition <path> Active` to transition from Draft to Active
3. Commit: `docs(roadmap): activate ROADMAP for <topic>`
4. Create PR (or update existing PR if on a shared branch)

The same re-run applies when `/roadmap activate <path>` is invoked
standalone (input mode 2) on a roadmap this session did not create: populate
issuelessly first, then transition. That is what covers roadmaps authored
before automatic population existed.

Then present routing options:

"The ROADMAP is active. Based on the features and their annotations, here are the
recommended next steps:"

| Situation | Suggestion |
|-----------|-----------|
| Features need requirements | /prd for features marked needs-prd |
| Features need architecture | /design-doc for features marked needs-design |
| Ready to plan implementation | /plan to break features into issues |
| Features should be tracked as GitHub issues | `/roadmap populate <path> --issues` to file them and re-render the table with issue links |

The last row is the issue-filing action. It is deliberately a separate step
taken after approval, not part of this run: the reserved sections are
already populated, and filing issues is the one action here with a side
effect on shared remote state. It goes through the R14 approval gate.

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
