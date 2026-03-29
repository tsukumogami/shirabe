# Demand Validation: Converting Shirabe Skills to Koto State Management

Research lead: adversarial demand validation
Date: 2026-03-28

---

## 1. Is Demand Real?

**Partially. One skill has converted; no user-facing demand exists for the rest.**

The evidence splits into two categories: problems with the current approach, and
requests for koto adoption specifically.

### Problems with current approach (real, documented)

- **shirabe#25**: The /design skill's phase-based workflow has no enforcement
  gates. Agents bypass phases 1-5 and write design documents directly from
  context. The issue documents two production failures. The root cause is that
  the skill relies on prose instructions to enforce sequencing, and agents ignore
  them when context is compacted.

- **shirabe#19**: Design contradictions and fixture-anchored acceptance criteria
  survive through design, plan, and QA phases uncaught. A binary index
  implementation shipped with the wrong data source because the design doc had
  contradictory method names in two sections, and no phase transition caught the
  mismatch. This is a verification gap -- the workflow produced no structural
  check that design intent matched implementation.

- **shirabe#22**: The /explore workflow stops after the user confirms the
  crystallize decision and tells them to run /design manually. The skill lacks
  the ability to chain into a downstream workflow because there's no state
  machine connecting the two skills. Each skill is a self-contained prompt with
  its own resume logic.

### Requests for koto adoption specifically

- **koto#73**: "feat(shirabe): integrate /work-on skill with koto template" --
  the only issue that directly requests koto integration for a shirabe skill.
  This was implemented (shirabe PR#20, merged 2026-03-23). The /work-on skill
  now uses koto for orchestration.

- **koto#72**: "feat(template): write the work-on koto template" -- the 17-state
  template that koto#73 depends on. Also implemented.

There are **zero open issues** requesting koto adoption for /explore, /design,
/plan, /prd, /decision, or /review-plan. Nobody has filed "convert /explore to
koto" or "convert /design to koto."

### Koto engine issues that would be prerequisites

Several koto engine features needed for broader skill adoption are still open:

- **koto#66**: Mid-state decision capture (needed for /design's Phase 2 parallel
  decisions, /explore's multi-round research). Status: open, needs-design.
- **koto#65**: Template variable substitution. Status: open, needs-design.
- **koto#87**: Evidence promotion to workflow-scoped variables. Status: open.

These are infrastructure gaps that would block converting skills with complex
state patterns. The /work-on conversion was possible because its states fit
koto's current capabilities.

## 2. What Do People Do Today Instead?

Every skill except /work-on uses **wip/ artifact presence as implicit state**.
The pattern is consistent across all skills:

**Explore** (6 phases):
```
wip/explore_<topic>_crystallize.md exists  -> Phase 5
wip/explore_<topic>_findings.md exists     -> Phase 3
wip/explore_<topic>_scope.md exists        -> Phase 2
```

**Design** (7 phases):
```
Design doc has Solution Architecture       -> Phase 5
wip/design_<topic>_coordination.json       -> Phase 2-3
wip/design_<topic>_summary.md exists       -> Phase 1
```

**Plan** (8 phases):
```
wip/plan_<topic>_review.md exists          -> Phase 7
wip/plan_<topic>_manifest.json exists      -> Phase 5
wip/plan_<topic>_analysis.md exists        -> Phase 2
```

**PRD** (5 phases):
```
wip/research/prd_<topic>_phase2_*.md exist -> Phase 3
wip/prd_<topic>_scope.md exists            -> Phase 2
```

This approach has known weaknesses:

1. **No enforcement**: Nothing prevents an agent from skipping phases (shirabe#25).
   The resume logic tells the agent where it *should* be; it doesn't prevent
   advancing without completing the current phase.

2. **No verification**: Phase transitions don't check that the previous phase
   produced valid output. The agent can create an empty wip/ file and resume at
   any phase.

3. **No cross-skill handoff**: Skills can't chain because each has independent
   resume logic. The /explore -> /design handoff (shirabe#22) requires the user
   to manually invoke the next skill.

4. **Resume is fragile**: If wip/ artifacts are partially written (agent
   interrupted mid-file), resume logic may misclassify the current phase.

However, this approach also has strengths that shouldn't be dismissed:

1. **Simplicity**: The resume logic is 10-15 lines of readable conditionals.
   There's no state machine to debug, no event log to inspect, no separate CLI
   tool to learn.

2. **Transparency**: `ls wip/` tells you exactly where a workflow stands.
   Artifacts are human-readable files, not opaque state in a database.

3. **No dependency**: Skills work with zero external tooling. No koto install
   required.

## 3. Who Specifically Asked?

**No external users asked.** All evidence comes from internal workflow failures:

- shirabe#25 (phase skipping in /design) -- filed by project maintainer
- shirabe#19 (design contradictions surviving) -- filed by project maintainer
- shirabe#22 (explore -> design handoff) -- filed by project maintainer
- koto#73 (work-on integration) -- filed by project maintainer

There are no community requests, no external issue reports, and no discussions
asking for koto adoption in other skills. The project has no external
contributors yet, so the absence of external demand is unsurprising but still
relevant: the only signal is self-assessed need.

## 4. What Behavior Change Counts as Success?

This question hasn't been formally answered anywhere. Inferring from the issues:

- **Phase skipping eliminated**: Agents can't write Phase 5 artifacts before
  Phase 2 gates pass (addresses shirabe#25).
- **Verification at transitions**: State transitions check artifact existence
  and validity, not just artifact presence (addresses shirabe#19 partially).
- **Cross-skill chaining**: /explore can hand off to /design without user
  re-invocation (addresses shirabe#22).
- **Reliable resume**: Interrupted workflows resume at the correct state
  regardless of partial artifact state.

No issue defines measurable success criteria for "koto adoption across skills."
The /work-on integration (koto#73) defined specific criteria, but those are
skill-specific, not cross-cutting.

## 5. Is It Already Built?

**One data point: /work-on uses koto.** The conversion is complete (PR#20 merged
2026-03-23, PR#29 merged for content ownership). The skill uses `koto init`,
`koto next`, and `koto context` for its 17-state workflow.

Is this evidence of demand or just one data point? Arguments both ways:

**Evidence of demand:**
- The /work-on skill was the most complex skill with the most resume failures.
  It had ~55 lines of orchestration logic that koto replaced.
- Post-conversion, the skill gained gate-based verification, structured evidence
  collection, and reliable resume through koto's event log.
- A context patterns guide (`docs/guides/koto-context-patterns.md`) was written,
  suggesting the team expects more skills to follow.

**Just one data point:**
- /work-on is the only skill with a linear, deterministic-heavy topology that
  maps cleanly to koto's current capabilities. Other skills (/explore, /design)
  have branching, parallel dispatch, and multi-round loops that koto doesn't
  support yet (koto#66, koto#65).
- The conversion required building a 17-state template and multiple koto engine
  features. The effort was substantial. Repeating it for 5+ additional skills
  is a large commitment.
- No post-conversion evaluation measured whether the problems (phase skipping,
  resume failures) actually decreased. The benefit is assumed, not measured.

## 6. Is It Already Planned?

**Not explicitly.** There is no roadmap, design doc, or issue titled "convert all
skills to koto" or "koto adoption plan for shirabe skills."

What exists:

- The koto-templates directory was created in shirabe (currently contains only
  work-on.md), suggesting the project structure anticipates more templates.
- The koto context patterns guide is written generically, not specific to
  /work-on, implying future skills are expected to use koto.
- shirabe#9 (adversarial demand validation lead for /explore) would benefit from
  structured state management but doesn't mention koto.
- No shirabe issue requests converting /explore, /design, /plan, /prd, or
  /decision to koto.

The implicit plan is "work-on first, others later," but "later" has no timeline,
no dependency analysis, and no success criteria.

---

## Assessment

**The demand is real but narrow.** Three documented workflow failures (shirabe#25,
#19, #22) demonstrate genuine problems with the current wip/-based approach. But
the problems have different root causes, and koto addresses only some of them:

| Problem | Koto solves it? | Notes |
|---------|----------------|-------|
| Phase skipping (shirabe#25) | Yes, via gates | But shirabe#25's proposed fix (inline format specs + prose gates) doesn't require koto |
| Design contradictions (shirabe#19) | Partially | Verification gates help, but the core issue was contradictory design content, not missing state checks |
| Cross-skill handoff (shirabe#22) | Potentially | Requires multi-workflow chaining, which koto doesn't support yet |
| Resume fragility | Yes | koto's event log is more reliable than file-presence checks |

**The alternative explanation deserves weight.** shirabe#25's own proposed fix is
prose-level: add inline format specs and explicit prohibitions to SKILL.md. This
is cheaper than a koto conversion, faster to implement, and addresses the
specific failure mode. If the prose fix works, the motivation for converting
/design to koto weakens significantly.

**Missing prerequisites are a real constraint.** koto#66 (mid-state decision
capture) and koto#65 (variable substitution) are both open and marked
needs-design. These are required for /design and /explore conversions. Converting
skills before these land would require working around engine limitations, which
undermines the point of using a state machine.

**The "one success" argument is weaker than it appears.** /work-on's koto
adoption proves the approach works for linear, deterministic-heavy workflows. It
doesn't prove it works for branching multi-agent workflows (/explore), parallel
decision evaluation (/design), or iterative decomposition (/plan). Generalizing
from one skill to all skills is premature.

## Recommendation

Don't pursue a broad "convert all skills to koto" initiative now. Instead:

1. **Ship the prose fix for shirabe#25** (inline format specs + gates). Measure
   whether phase skipping decreases. If it does, the /design skill doesn't need
   koto.

2. **Wait for koto#66 and koto#65 to land.** These engine features are
   prerequisites for any non-trivial skill conversion.

3. **Pick the next candidate based on failure data, not architecture preference.**
   If /explore has resume failures in production, convert /explore. If /plan has
   phase-ordering bugs, convert /plan. Don't convert skills that are working.

4. **Define success criteria before converting.** "Uses koto" is not a success
   criterion. "Phase skipping rate drops from X to zero" is.
