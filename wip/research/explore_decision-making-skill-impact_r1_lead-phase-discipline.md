# Lead 6: Phase File Discipline Under Increased Complexity

## Summary

Phase file discipline holds up for the decision skill itself -- its 7 phases
fit comfortably within the established 150-line target. The real risk isn't
individual file size; it's the combinatorial state explosion when the design
skill orchestrates multiple decision sub-operations, each with their own
multi-phase lifecycle and resumability needs.

---

## 1. Current Phase File Size Distribution

### Phase files (38 total across 5 skills)

| Bucket | Count | Percentage |
|--------|-------|------------|
| Under 100 lines | 11 | 29% |
| 100-150 lines | 11 | 29% |
| 151-200 lines | 8 | 21% |
| 201-300 lines | 4 | 11% |
| Over 300 lines | 4 | 11% |

**Median: ~136 lines.** The "under 150" target is met by 58% of phase files.

### Outliers (over 300 lines)

| File | Lines | Skill | Notes |
|------|-------|-------|-------|
| phase-5-produce-deferred.md | 318 | explore | Routes to 5 artifact types; inherent branching |
| phase-7-creation.md | 359 | plan | Creates GitHub artifacts; complex but single-concern |
| phase-3-decomposition.md | 385 | plan | 3 decomposition strategies + execution mode; could split |
| phase-4-agent-generation.md | 437 | plan | Agent prompt templates + multi-mode logic; largest file |

Plan's Phase 3 and Phase 4 violate the 300-line reference file cap. Both have
clear internal branch points (input_type, execution_mode) that could justify
splitting, similar to how design's Phase 0 was already split into
phase-0-setup-prd.md and phase-0-setup-freeform.md.

### SKILL.md sizes

| Skill | Lines |
|-------|-------|
| private-content | 46 |
| public-content | 62 |
| writing-style | 73 |
| work-on | 121 |
| prd | 145 |
| design | 235 |
| explore | 286 |
| plan | 359 |

Plan's SKILL.md (359 lines) is close to the progressive disclosure edge. All
others are comfortably under 300.

### Observed patterns in well-sized phase files

From the sample (design/phase-2, explore/phase-3, work-on/phase-2):

1. **Single goal statement** at the top (1-3 sentences)
2. **Resume check** section (how to detect if this phase already completed)
3. **Numbered steps** (3-6 substeps) with concrete instructions
4. **Quality checklist** (2-3 items)
5. **Artifact state** (what exists after this phase)
6. **Next phase** pointer

Phase files that stay under 150 lines follow this template tightly. Files that
grow past 200 lines typically embed branching logic (multiple input types,
multiple modes) that could be split.

---

## 2. Decision Skill Phase Files: Estimated Content and Size

The decision skill has 7 phases. Based on the scope file's description
(research, alternatives, validation bakeoff, peer revision, cross-examination,
synthesis, report) and the established phase file patterns:

### Phase 0: Context and Framing (~80-100 lines)

**Contains:** Accept decision question from parent skill or user input. Extract
constraints, stakeholders, decision drivers. Create wip/ context artifact.

**Why small:** No branching. Single input format (decision question + context
from parent). Mirrors explore/phase-1-scope.md (136 lines) but simpler because
the scope is already constrained by the parent.

### Phase 1: Research (~120-140 lines)

**Contains:** Fan out research agents per alternative. Each agent investigates
one approach with equal depth. Cap at 5 alternatives (matching design's
advocate cap). Agent prompt template and output format.

**Why moderate:** Agent spawning logic parallels design/phase-1 (157 lines) and
explore/phase-2 (162 lines). Agent prompt might push toward 150 if inline, but
the established pattern uses a separate template file (plan has
agent-prompt.md at 220 lines).

**Split opportunity:** Agent prompt template should be a separate reference
file, keeping the phase file itself under 120.

### Phase 2: Alternatives Presentation (~100-130 lines)

**Contains:** Side-by-side comparison, recommendation with evidence,
AskUserQuestion for selection or "none of these" loop-back.

**Why moderate:** Direct parallel to design/phase-2-present-approaches.md (140
lines). Almost identical structure. In fact, if the decision skill is
a generalization of this, the design skill's phase 2 would delegate here.

### Phase 3: Validation Bakeoff (~120-150 lines)

**Contains:** Selected alternative undergoes deeper validation. Assign
devil's-advocate agents to stress-test assumptions. Structured output:
strengths confirmed, weaknesses found, risks surfaced.

**Why moderate:** New phase with no exact parallel in existing skills. Closest
analog is design/phase-3 (155 lines) which does deep investigation of the
chosen approach. Should include agent spawn, validation criteria, and output
template.

### Phase 4: Peer Revision (~80-110 lines)

**Contains:** In multi-decision mode, each decision's outcome is reviewed by
agents handling other decisions. Flag assumption conflicts. In single-decision
mode, this phase is a no-op or runs a lighter self-review.

**Why small:** Conditional execution. The peer review itself is a read-and-flag
operation, not a research operation. When skipped, the phase file just
documents the skip condition.

**Risk:** If the cross-validation logic is complex (comparing N decisions
pairwise), this could grow. Mitigation: the pairwise comparison format should
be a separate reference, keeping the phase orchestration lean.

### Phase 5: Cross-Examination (~100-130 lines)

**Contains:** If peer revision flagged conflicts, run targeted
cross-examination between conflicting decisions. Agent-mediated debate with
structured output. May trigger restart from an earlier phase.

**Why moderate:** The restart logic is the tricky part. Phase files should
declare "restart from Phase N" as an output, but the parent orchestrator
handles the actual restart. The phase file documents the conditions and output
format, not the loop control.

### Phase 6: Synthesis and Report (~130-160 lines)

**Contains:** Compile final decision record. Format: Context, Decision,
Rationale, Alternatives Considered, Assumptions, Consequences. Frontmatter
for machine readability. Commit the artifact.

**Why at the upper bound:** Output formatting is detailed. But this parallels
design/phase-6 (187 lines) which handles similar finalizing concerns. If the
output template is extracted to a reference file, the phase file stays under
140.

### Size estimate summary

| Phase | Estimated Lines | Confidence |
|-------|----------------|------------|
| 0: Context and Framing | 80-100 | High |
| 1: Research | 120-140 | Medium (depends on template extraction) |
| 2: Alternatives Presentation | 100-130 | High (close analog exists) |
| 3: Validation Bakeoff | 120-150 | Medium (new concept) |
| 4: Peer Revision | 80-110 | Medium (conditional complexity) |
| 5: Cross-Examination | 100-130 | Low (restart logic unclear) |
| 6: Synthesis and Report | 130-160 | Medium (template extraction dependent) |
| **Total** | **~730-920** | |

**Conclusion:** Individual phase files fit within the 150-line target if agent
prompt templates and output format templates are extracted to separate
reference files. This follows the established pattern (plan extracts
agent-prompt.md, design extracts considered-options-structure.md).

The decision skill would add ~7 phase files + ~2-3 reference files (agent
prompt template, output format template, peer review format). Total reference
file count: ~10. This is comparable to plan (7 phases + 8 templates/quality
files = 15 reference files).

---

## 3. Parent-Child Phase Tracking

### Does the design skill need to track decision-phase progress?

**No.** The decision skill's internal phases should be opaque to the parent.

**Evidence from existing patterns:**

- work-on's Phase 2 (introspection) delegates to the issue-introspection skill
  via an agent. The work-on skill doesn't track which introspection step is
  running -- it sends input, gets output, and checks the recommendation.
- plan's Phase 4 (agent generation) spawns per-issue agents. The plan skill
  doesn't track each agent's internal progress -- it checks for completion
  artifacts.
- design's Phase 1 spawns advocate agents. Same pattern.

**The contract is:** parent sends decision question + context, decision skill
produces a decision artifact file, parent reads the file and continues.

### What the parent needs to know

1. **Is the decision complete?** Check for
   `wip/decision_<topic>_<question-id>_report.md`
2. **Did it fail or need restart?** Check for a restart marker in the artifact
3. **What was decided?** Read the artifact's frontmatter (Context, Decision,
   Rationale)

### Where tracking lives

The decision skill maintains its own state in its own wip/ artifacts:
- `wip/decision_<topic>_<question-id>_context.md` (Phase 0 output)
- `wip/decision_<topic>_<question-id>_research_*.md` (Phase 1 outputs)
- `wip/decision_<topic>_<question-id>_comparison.md` (Phase 2 output)
- `wip/decision_<topic>_<question-id>_validation.md` (Phase 3 output)
- `wip/decision_<topic>_<question-id>_report.md` (Phase 6 output, final)

The parent (design) tracks which decisions are complete in its own orchestration
state. This parallels how the plan skill's manifest.json tracks which agent
generation jobs completed without knowing the agents' internal state.

### Design skill's orchestration concern

The design skill needs a lightweight tracking artifact:

```yaml
# wip/design_<topic>_decisions.yaml
decisions:
  - id: approach-selection
    question: "Which architecture approach?"
    status: complete  # pending | in-progress | complete | restart
    artifact: wip/decision_<topic>_approach-selection_report.md
  - id: data-model
    question: "Which data model?"
    status: in-progress
    artifact: null
```

This is the design skill's concern, not the decision skill's. The decision
skill doesn't know it's being orchestrated.

---

## 4. Resumability Across Nested Phases

### Scenario: Session breaks during decision Phase 3 of decision question 2 of design Phase 1

**State files needed:**

#### Design skill level
- `wip/design_<topic>_summary.md` -- confirms Phase 0 complete, branch exists
- `wip/design_<topic>_decisions.yaml` -- tracks which decisions are pending
  - Shows decision 1 complete, decision 2 in-progress

#### Decision skill level (for question 2)
- `wip/decision_<topic>_<q2-id>_context.md` -- Phase 0 complete
- `wip/decision_<topic>_<q2-id>_research_*.md` -- Phase 1 complete (one per alternative)
- `wip/decision_<topic>_<q2-id>_comparison.md` -- Phase 2 complete
- (no validation artifact yet -- Phase 3 was interrupted)

#### Decision skill level (for question 1)
- `wip/decision_<topic>_<q1-id>_report.md` -- complete decision artifact

### Resume sequence

1. Design skill's resume logic reads `wip/design_<topic>_decisions.yaml`
2. Finds decision 1 complete, decision 2 in-progress
3. Invokes decision skill for question 2 with the existing topic + question-id
4. Decision skill's own resume logic checks for artifacts:
   - context.md exists -> skip Phase 0
   - research_*.md exist -> skip Phase 1
   - comparison.md exists -> skip Phase 2
   - no validation.md -> resume at Phase 3
5. Decision skill completes, writes report.md
6. Design skill reads report, updates decisions.yaml, moves to next decision

### Total state file count for this scenario

| Level | Files | Notes |
|-------|-------|-------|
| Design skill | 2 | summary + decisions tracker |
| Decision Q1 | 1 | final report (intermediate artifacts cleaned) |
| Decision Q2 | 4 | context + 3 research files + comparison |
| **Total** | ~7 | Plus any wip/research/ files |

### Cleanup pattern

Decision skill should clean its intermediate artifacts after producing the
final report, keeping only the report.md. This matches plan's Phase 7 cleanup
pattern (`delete wip/plan_<topic>_*.md files`). Without cleanup, 5 decisions
with 5 alternatives each could produce 25+ research files.

**Cleanup timing matters.** Clean after each decision completes, not after all
decisions complete. This keeps the wip/ directory manageable and makes resume
logic simpler (presence of report.md means "done, skip this decision").

---

## 5. Risk Assessment: Where Does Complexity Break?

### Complexity budget analysis

| Factor | Current State | With Decision Skill | Breaking Point |
|--------|--------------|--------------------|----|
| Phase files per skill (max) | 8 (design) | 7 (decision) + 8 (design) = 15 loaded over full workflow | 20+ loaded in one session |
| wip/ files per workflow | ~8-12 | ~15-25 (multiple decisions) | 30+ files (cognitive load for debugging) |
| Resume logic conditions | 7-8 per skill | 7 (decision) nested inside 8 (design) = ~15 conditions to evaluate | Nested resume with 3+ levels |
| Context window pressure | 1 SKILL.md + 1 phase file | 2 SKILL.md files + 2 phase files simultaneously | 4+ concurrent skill contexts |
| User interaction points | 1-2 per phase | 1-2 per decision phase x N decisions | 10+ serial user interactions before visible progress |

### Where it breaks

**Risk 1: User fatigue from serial decision interactions (HIGH)**

If a design has 5 decisions and each goes through 7 phases with 1-2 user
interactions per phase, that's 35-70 interaction points before the design doc
is written. Users will abandon the workflow.

**Mitigation:** Not all decisions need the full 7-phase treatment. Simple
decisions (2 options, clear trade-off) should use a "fast path" that skips
validation bakeoff and peer revision. The decision skill SKILL.md should
define complexity tiers:
- **Simple** (2 alternatives, low risk): Phases 0, 1, 2, 6 only (~4 interactions)
- **Standard** (3+ alternatives, moderate risk): All 7 phases (~7-10 interactions)
- **Critical** (high-stakes, irreversible): All 7 phases + extended cross-examination

The parent skill classifies each decision's complexity when invoking.

**Risk 2: Context window exhaustion in nested skill execution (MEDIUM)**

When the design skill is at Phase 1 and invokes the decision skill, the context
window holds: design SKILL.md + design phase file + decision SKILL.md + decision
phase file + all prior conversation. That's 235 + ~150 + ~300 + ~150 = ~835 lines
of instruction, plus the actual conversation.

This is manageable for the 1M context model but could degrade instruction-following
if the conversation is already deep. The key mitigation is that phase files are
loaded on demand (progressive disclosure works here).

**Risk 3: wip/ artifact sprawl (MEDIUM)**

5 decisions x 5 alternatives x research files = 25 research files, plus context,
comparison, validation, and report files per decision = ~40 wip/ files total. This
makes the wip/ directory hard to navigate and increases the chance of
naming collisions.

**Mitigation:** Strict naming convention with question-id namespacing:
`wip/decision_<topic>_<question-id>_<artifact>.md`. Clean intermediate
artifacts after each decision completes.

**Risk 4: Nested resume logic correctness (MEDIUM)**

Resume depends on the design skill correctly detecting "decision in progress"
and delegating to the decision skill's resume logic. Two independent resume
systems must agree on state. If the design skill's decisions.yaml says
"in-progress" but the decision skill's artifacts say "complete" (e.g., report
exists but design didn't update its tracker), the system enters an
inconsistent state.

**Mitigation:** The design skill should derive decision status from the decision
skill's artifacts (check for report.md existence) rather than maintaining its
own status field. The tracker becomes a derived view, not a source of truth.
This eliminates dual-write consistency problems.

**Risk 5: The "standalone workflow" threshold (LOW for now)**

At what point should the decision skill be a standalone workflow rather than
a composable sub-operation?

The decision skill is ALREADY both. When invoked directly (`/decision`), it
runs standalone. When invoked by the design skill, it runs as a sub-operation.
The interface is the same either way -- input is a decision question + context,
output is a report artifact. The skill doesn't need to know which mode it's in.

This dual-mode design is sustainable as long as:
1. The decision skill has no awareness of its parent
2. The parent communicates only through artifacts (not shared state)
3. The decision skill's resume logic is self-contained

If any of these break -- for instance, if the decision skill needs to read the
parent's design doc directly to understand peer decisions -- then the
composition model has failed and the decision skill should become an
embedded phase of the design skill rather than a separate skill.

### Verdict

The decision skill as a composable sub-operation works if:

1. **Fast path exists** for simple decisions (skip phases 3-5)
2. **Cleanup after each decision** keeps wip/ manageable
3. **Derived status** (check artifacts, don't maintain a separate tracker)
4. **No parent awareness** in the decision skill's phase files
5. **Agent-mediated peer revision** runs as a batch after all decisions
   complete, not interleaved during individual decisions

The complexity budget breaks at **3+ nesting levels** (skill invoking skill
invoking skill) or **10+ serial user interactions** without visible artifact
progress. The current proposal stays at 2 levels (design -> decision) with
the fast path keeping most decisions to 4 interactions. This is within budget.

---

## Implications for Phase File Standards

### Confirmed standards

1. **150-line target per phase file** -- achievable for all 7 decision phases
   if templates are extracted
2. **Single-concern per file** -- each decision phase has a clear single
   concern (research, compare, validate, etc.)
3. **Progressive disclosure** -- SKILL.md describes the phases, phase files
   are loaded on demand, templates are loaded from phase files

### New standards needed for composable skills

1. **Sub-operation interface section** in SKILL.md: document the input
   contract (what the parent provides) and output contract (what artifact
   the skill produces) explicitly
2. **Cleanup policy** in the final phase file: list which intermediate
   artifacts to delete and which to keep
3. **Fast-path documentation** in SKILL.md: which phases can be skipped
   under what conditions, so parent skills can classify decision complexity
4. **Artifact-derived status**: phase files should never maintain status
   in a separate tracker when the artifact's existence IS the status
