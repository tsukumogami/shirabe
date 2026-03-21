# Research: Explore-to-Decision-Skill Convergence

**Lead:** explore-convergence
**Round:** 1
**Date:** 2026-03-21
**Scope:** How a future decision-making skill affects explore's Decision Record artifact type, crystallize framework, and handoff mechanics.

---

## Question 1: What happens today when explore crystallizes to "Decision Record"?

Today, explore treats Decision Record as a "deferred" artifact type handled in `phase-5-produce-deferred.md`. When crystallize selects it, phase-5 produces an ADR directly inline -- writing `docs/decisions/ADR-<topic>.md` with sections for Status, Context, Decision, Options Considered, and Consequences. There's no handoff to another skill. Explore does the full authoring itself, using accumulated findings and decisions from convergence rounds as source material.

This is different from how explore handles PRD, Design Doc, and Plan. Those three route to their respective skills (/prd, /design, /plan) via handoff artifacts -- explore writes a skeleton or brief, then invokes the target skill to do the real work. Decision Record gets no such delegation because no decision skill exists.

The crystallize framework itself treats Decision Record as deferred, with a note that it should suggest "Design Doc" as the closest available alternative. But `phase-5-produce-deferred.md` contradicts this by actually producing the ADR. The deferred-type table in `crystallize-framework.md` (line 84) says "Design Doc -- captures the decision with full context" as the alternative, while the production file just goes ahead and writes the ADR anyway. This is a minor inconsistency -- the framework was written before the deferred types got their own production logic.

---

## Question 2: Should explore invoke the decision skill or hand off to it?

**Recommendation: Hand off, mirroring the /design and /prd pattern.**

The handoff pattern is well-established in explore. For PRD and Design Doc, explore writes a handoff artifact (skeleton or brief) populated from findings, then invokes the target skill to drive the full production workflow. The target skill adds its own structure -- phases, validation, quality checks -- that explore doesn't replicate.

A decision skill would add value that explore's inline ADR production lacks:

1. **Structured alternatives evaluation.** The proposed 7-phase decision workflow includes research, alternative generation, validation bakeoff, peer revision, and cross-examination. Explore's current ADR just dumps whatever options the exploration discovered into an "Options Considered" section with no systematic evaluation.

2. **Bakeoff pattern.** The decision skill generalizes the design skill's advocate pattern -- multiple agents argue for different options, then a synthesis phase picks a winner. Explore's inline ADR has no adversarial evaluation at all.

3. **Resumability.** The decision skill would have its own phase files and wip/ artifacts, making a partially-completed decision resumable. Explore's current inline production is all-or-nothing.

The handoff would work like the design doc handoff: explore writes a decision brief (`wip/explore_<topic>_decision-brief.md`) containing the decision question, context from findings, known options, and relevant constraints. Then it invokes `/decision <topic>` which runs its own workflow.

The one concern is weight. If the decision is simple (two clear options, one obviously better), the 7-phase workflow is overkill. The handoff should include a complexity signal from explore's findings so the decision skill can fast-track simple decisions. This mirrors how the design doc handoff includes scope information that lets /design calibrate its depth.

---

## Question 3: Should the crystallize framework itself use the decision skill?

**No. Crystallize should stay inline.**

The crystallize framework asks "which artifact type?" -- it's a meta-decision about what kind of document to produce, not a substantive technical or architectural choice. Its evaluation is mechanical: count signals, apply demotion, check tiebreakers. The decision skill's value (adversarial bakeoff, peer review, cross-examination) doesn't apply to artifact type selection because:

- The options are predefined (PRD, Design Doc, Plan, No artifact, plus deferred types). There's nothing to research or generate.
- The evaluation criteria are codified in the signal/anti-signal tables. No judgment call requires adversarial debate.
- The user confirms the choice anyway. Crystallize is already a user-facing decision point with alternatives presented.

Using the decision skill for crystallize would add 7 phases of ceremony to a question that the current framework answers in one phase with a scoring rubric. The overhead-to-value ratio is wrong.

One edge case: if a future crystallize adds more artifact types or the signal tables become contested, the decision skill could help resolve ambiguity. But that's a future problem -- today's framework handles the known types well.

---

## Question 4: How does the explore-to-decision-skill handoff work?

### What explore passes (decision brief):

The handoff artifact should contain everything the decision skill needs to skip its own discovery phase:

```
# Decision Brief: <topic>

## Decision Question
<One sentence: what specific choice needs to be made?>

## Context
<From findings: why this decision matters, what's blocked, what forces are at play.>

## Known Options
<From findings/decisions: options already identified during exploration.
Each with a brief description and any evidence for/against from research.>

## Constraints
<From findings: non-negotiable requirements, compatibility needs, timebox.>

## Relevant Research
<Paths to wip/research/ files the decision skill should read for detail.>

## Complexity Signal
<Simple (2 clear options, evidence strongly favors one) or
Complex (3+ options, trade-offs are genuinely contested, stakeholders disagree)>
```

### What the decision skill needs as input:

The decision skill's 7 phases (per issue #6 description) start with research. If explore has already done that research, the decision skill should be able to skip or abbreviate its research phase by consuming the brief. The skill needs:

1. **A clear decision question.** Not "explore this topic" but "choose between X and Y for reason Z."
2. **Pre-existing options** (optional). If explore found options, the skill can validate and expand them rather than discovering from scratch.
3. **Context and constraints.** Forces that bound the decision space.
4. **Research pointers.** Paths to detailed research files so the skill doesn't duplicate work.

### What the decision skill produces:

The output should map to the ADR format currently in phase-5-produce-deferred.md, plus the structured decision data needed by design docs (Considered Options sections). The output format should be a superset:

- `docs/decisions/ADR-<topic>.md` -- the permanent artifact (same location as today)
- A structured data section (or frontmatter) that other skills can consume programmatically -- specifically, the design skill needs to pull decisions into its Considered Options sections.

---

## Question 5: Does the decision skill subsume explore's convergence pattern?

**No. They're fundamentally different operations.**

Explore's convergence pattern answers "what should we investigate next?" and "what kind of artifact do we need?" It's a discovery loop: fan out research agents, converge findings, decide whether to explore further or crystallize. The output is understanding -- accumulated findings that inform what to build.

The decision skill answers "which option should we pick?" It's an evaluation loop: research alternatives, argue for each one, cross-examine, synthesize. The output is a choice -- a specific option selected with rationale.

The relationship is sequential, not overlapping:

```
Explore: "We don't know what we need"
  -> Discovery rounds
  -> Crystallize: "We need a decision"
  -> Handoff to decision skill

Decision: "We know the question, need to pick an answer"
  -> Alternative evaluation
  -> Bakeoff / cross-examination
  -> Decision record
```

Explore discovers THAT a decision needs to be made. The decision skill MAKES the decision. Trying to merge them would conflate two different cognitive modes -- open-ended exploration vs. focused evaluation. Explore's value is that it doesn't commit to a direction prematurely; the decision skill's value is that it commits rigorously.

That said, explore's convergence rounds sometimes make implicit decisions (scope narrowing, option elimination -- tracked in the decisions file). These micro-decisions don't warrant the full decision skill treatment. They're recorded in `wip/explore_<topic>_decisions.md` and carried forward into whatever artifact explore produces. The decision skill is for the big, explicit decisions that deserve their own artifact.

---

## Implications for implementation

### Changes to explore

1. **phase-5-produce-deferred.md Decision Record section**: Replace inline ADR production with a handoff to `/decision`. Write a decision brief instead of the final ADR. The brief format parallels the design doc skeleton and PRD brief that other handoffs produce.

2. **phase-5-produce.md routing table**: Add Decision Record to the set of types that route to a dedicated skill, moving it out of the deferred catch-all.

3. **crystallize-framework.md deferred types table**: Move Decision Record from the deferred types table to the supported types table once the decision skill exists. Update its "Closest Available Alternative" entry to remove the "Design Doc" fallback.

4. **SKILL.md reference files table**: Add a new entry for `phase-5-produce-decision.md` alongside the existing produce sub-files.

### Changes NOT needed

- Crystallize framework scoring logic: no changes. Decision Record's signals and anti-signals stay as-is.
- Explore's convergence loop: unchanged. The discover-converge pattern is explore's, not the decision skill's.
- The decisions file (`wip/explore_<topic>_decisions.md`): unchanged. Micro-decisions during exploration stay in this file. Only the final "which option?" decision routes to the decision skill.

### Open questions

1. **Fast-track for simple decisions.** If the complexity signal is "simple," should the decision skill skip the bakeoff entirely? This affects the handoff contract -- explore needs to signal complexity, and the decision skill needs to respect it.

2. **Design doc integration.** A design doc may trigger 3-5 decision skill invocations (one per Considered Options section). Does explore's handoff to the decision skill look different when the decision was discovered during explore vs. when the design skill spawns a decision mid-workflow? The input format should probably be the same, but the output routing differs (standalone ADR vs. embedded in a design doc section).

3. **Decision Record vs. ADR naming.** The crystallize framework calls it "Decision Record" and the produced file is `ADR-<topic>.md`. The decision skill's output format should standardize this. ADR (Architecture Decision Record) is an established term but may be too narrow -- not all decisions are architectural. "Decision Record" is the broader term.
