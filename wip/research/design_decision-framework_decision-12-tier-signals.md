# Decision 12: What Concrete Signals Should Agents Use to Classify Decision Tier?

## Context

The lightweight decision framework (see `explore_decision-making-skill-impact_r2_lead-lightweight-framework.md`) defines four decision tiers: trivial (no documentation), lightweight (micro-protocol), standard (decision skill fast path), and critical (full 7-phase). Section 5 of that document provides a classification heuristic -- a five-step waterfall of questions the agent evaluates in order.

The problem: the heuristic relies on subjective assessments. "Does available context clearly favor one option?" is the boundary between Tier 2 and Tier 3, but "clearly" is undefined. An agent that's 65% confident one option is better -- is that "clear"? Different model runs will answer differently. The ask inventory (39 blocking points across 5 skills) shows that 19 of those points are category (b) judgment calls, most of which sit right on the Tier 2/3 boundary. If classification is inconsistent, agents will either over-escalate (wasting tokens on the decision skill for straightforward choices) or under-escalate (making lightweight decisions that deserved deeper investigation).

The tier boundary that matters most is 2 vs 3. Tier 1 vs 2 is low-stakes (worst case: you document a trivial decision, wasting a few lines). Tier 3 vs 4 is rare and high-signal (irreversibility is usually obvious). But Tier 2 vs 3 determines whether the agent spends 30 seconds on a micro-protocol or 5+ minutes invoking the decision skill. Getting this wrong in either direction has real cost.

## Options Evaluated

### (a) Signal checklist

A numbered checklist the agent evaluates sequentially. Each signal contributes a score or tier recommendation. The agent tallies results and picks the tier.

Example implementation:

```
1. Count viable alternatives:
   - 1 option -> Tier 1
   - 2-3 options -> Tier 2 baseline
   - 4+ options -> Tier 3 baseline

2. Evidence clarity (does loaded context favor one option?):
   - One option is clearly best -> no change
   - Evidence leans toward one but with caveats -> bump +1 tier
   - No option is clearly favored -> bump +1 tier

3. Reversibility cost:
   - Seconds to reverse (rename, flag change) -> Tier 1
   - Hours to reverse (1-3 files, no architecture change) -> no change
   - Days to reverse (multi-component, architecture impact) -> bump +1 tier
   - Practically irreversible (public API, data migration) -> Tier 4

4. Downstream dependency count:
   - 0 downstream consumers -> no change
   - 1-2 downstream consumers -> no change
   - 3+ downstream consumers -> bump +1 tier

5. Is this the primary question this phase exists to answer?
   - Yes -> minimum Tier 3
   - No -> no change
```

**Accuracy:** Moderate. The checklist forces the agent to evaluate each dimension separately, which reduces the chance of skipping a signal. But the "evidence clarity" signal (item 2) is still subjective. "Leans toward one but with caveats" vs "no option is clearly favored" is exactly the fuzzy boundary the current heuristic already has.

**Overhead:** Medium-high. Five evaluation steps per decision point. For a workflow with 6-8 decisions, this adds meaningful token cost. The checklist also introduces a scoring system that can produce ambiguous totals (what if one signal says Tier 2 and another says bump to Tier 3?).

**Maintainability:** Adding new signals means updating the checklist in one place. But tuning the weights (when does a bump override a baseline?) requires iterating on the scoring rules.

### (b) Decision tree

A branching flowchart with binary or ternary questions. The agent follows the branches to a terminal node (the tier).

Example implementation:

```
Is there only one reasonable option?
  YES -> Tier 1
  NO ->
    Does loaded context (codebase, prior decisions, constraints)
    clearly favor one option over all others?
      YES -> Tier 2
      NO ->
        Is the decision practically irreversible?
          YES -> Tier 4
          NO ->
            Is this the primary decision this phase exists to make?
              YES -> Tier 3
              NO -> Tier 2
```

**Accuracy:** Lower than the checklist for edge cases. The tree evaluates signals in a fixed order, so early branches can mask later ones. A decision that has "clear" evidence (-> Tier 2 at branch 2) but is also practically irreversible (-> should be Tier 4) gets classified as Tier 2 because the irreversibility check never fires. The tree would need cross-cutting override rules ("regardless of prior branches, if irreversible -> Tier 4"), which makes it no longer a clean tree.

The specific failure mode: the tree in Section 5 of the framework document already IS a decision tree, and it already has this masking problem. The "Does available context clearly favor one option?" branch catches most decisions (since evidence usually leans *some* direction), sending them to Tier 2 before the agent ever evaluates reversibility or phase-primacy.

**Overhead:** Low. 3-4 branch evaluations per decision. Fast to execute, minimal token cost.

**Maintainability:** Adding a new signal means restructuring the tree. Branch order matters, so inserting a new question in the middle changes classification for all downstream nodes. Fragile.

### (c) Phase-file pre-classification

Each phase file annotates its own decision points with a tier. The agent doesn't classify at runtime -- the workflow author classified when writing the phase.

Example in a phase file:

```markdown
## Decomposition Strategy
<!-- decision-tier: 2 -->

Evaluate walking skeleton vs horizontal decomposition...
```

The agent reads the tier annotation and applies the corresponding protocol (micro-protocol for Tier 2, decision skill for Tier 3, etc.).

**Accuracy:** High for known decision points. The workflow author, who understands the decision's weight, assigns the tier during design time. No runtime ambiguity. The 39 blocking points in the ask inventory could each get a tier annotation based on the analysis already done (category (a) maps roughly to Tier 1-2, category (b) to Tier 2-3, category (c) to Tier 2-3 depending on reversibility).

But: accuracy drops for emergent decisions. Design Phase 3-4 surfaces decisions that weren't anticipated when the phase was written (D5-D8 in the inventory -- deal-breakers, mid-investigation choices, implicit decisions). These can't be pre-classified because they don't exist until the agent discovers them. The ask inventory's cross-cutting observation #4 confirms this: "Design has the most mid-workflow decision points... the questions are emergent, not predetermined."

**Overhead:** Near zero at runtime. The agent reads an annotation instead of evaluating signals. Classification cost shifts entirely to authoring time.

**Maintainability:** Adding a new *known* decision point means adding a tier annotation to the phase file -- localized and simple. But emergent decisions still need a runtime classifier, so this option doesn't eliminate the classification problem; it just reduces how often the runtime classifier fires.

## Analysis

The options aren't mutually exclusive. Pre-classification (c) handles the predictable cases, and a runtime classifier (a or b) handles emergent decisions. The real question is which runtime classifier to pair with pre-classification.

The decision tree (b) is what the framework already has (Section 5's classification heuristic). Its weakness -- the masking problem where early branches prevent later signals from firing -- is exactly what prompted this decision. Keeping a tree doesn't solve anything.

The signal checklist (a) addresses the masking problem by evaluating all signals independently. But it adds overhead and still has the subjective "evidence clarity" assessment. However, there's a key insight from the ask inventory: 14 of 19 judgment calls already have recommendation heuristics in their phase files. The agent doesn't need to assess "evidence clarity" in the abstract -- it runs the existing heuristic and checks whether the result is decisive or close.

This suggests a hybrid: pre-classify known decision points (c), and for emergent decisions, use a simplified checklist (a) with one critical refinement -- replace the subjective "evidence clarity" signal with a measurable proxy: **confidence of the existing heuristic**. If the phase's recommendation heuristic produces a clear winner (e.g., all signals agree, 80%+ score), that's Tier 2. If it's close (signals split, 50-65%), that's Tier 3 territory.

## Decision

<!-- decision:start id="tier-classification-signals" -->
### Decision: Tier classification mechanism

**Question:** What concrete signals should agents use to classify decisions into the correct tier?

**Choice:** Hybrid of (c) phase-file pre-classification and (a) signal checklist for emergent decisions.

**How it works:**

1. **Known decision points** get a `<!-- decision-tier: N -->` annotation in their phase file. The 39 blocking points from the ask inventory are classified at authoring time. The agent reads the annotation and applies the corresponding protocol. No runtime evaluation needed.

2. **Emergent decisions** (discovered during execution, not pre-annotated) use a three-signal checklist:

   **Signal 1 -- Reversibility:**
   - Trivially reversible (seconds, no downstream impact) -> Tier 1
   - Moderate effort to reverse (hours, 1-3 files) -> no tier override
   - Requires architectural change or is irreversible -> minimum Tier 4

   **Signal 2 -- Heuristic confidence:**
   - Run whatever evaluation logic is available (codebase patterns, prior decisions, constraint analysis)
   - If the result is decisive (one option clearly dominates) -> Tier 2
   - If the result is close (no clear winner) -> Tier 3

   **Signal 3 -- Phase primacy:**
   - Is this the primary question this phase exists to answer? -> minimum Tier 3

   Apply in order. Reversibility overrides (irreversible = Tier 4 regardless). Then heuristic confidence sets the baseline. Phase primacy bumps to Tier 3 minimum.

3. **Default remains Tier 2.** If the checklist is ambiguous or the agent can't determine a signal, it defaults to the lightweight micro-protocol. Over-documenting is cheaper than under-investigating.

**Alternatives considered:**
- (a) Signal checklist alone: accurate but adds overhead to every decision, including the many that could be pre-classified. 5-signal evaluation for "decomposition strategy" is wasteful when we already know it's Tier 2.
- (b) Decision tree alone: fast but has a masking problem where early branches prevent later signals from firing. The existing Section 5 heuristic is already a decision tree and already has this problem.
- (c) Pre-classification alone: zero runtime cost for known points but can't handle emergent decisions, which are the hardest to classify correctly.

**Assumptions:**
- The ask inventory's 39 blocking points cover the large majority of decisions agents encounter. Emergent decisions are the minority case.
- Phase-file authors can accurately classify tier at authoring time. If they consistently mis-classify, the pre-annotations become noise rather than signal.
- "Heuristic confidence" is assessable by the agent. Most phase files already include recommendation heuristics, so the agent can check whether signals agree or split.

**Reversibility:** High. Tier annotations in phase files can be changed one at a time. The emergent-decision checklist is defined in one place and can be tuned without touching phase files.
<!-- decision:end -->

## Pre-Classification of the 39 Blocking Points

Based on the ask inventory categories and the signals above, here's how the known decision points should be annotated:

### Category (a) -- Researchable: mostly Tier 1-2

| ID | Recommended Tier | Rationale |
|----|-----------------|-----------|
| E1, D1, P1, PL1 | Tier 1 | Empty input inference -- single reasonable action (infer or fail). No alternatives. |
| E11 | Tier 1 | Informational output, not a decision. |
| D2 | Tier 2 | Scoping has alternatives (narrow vs broad), but codebase signals usually resolve it. |
| D4 | Tier 2 | "What's missing" requires judgment, but the micro-protocol captures it. |
| P2 | Tier 1 | Branch relevance check -- mechanical, one right answer. |
| PL2 | Tier 2 | Feature classification has a documented heuristic. Follow it, record result. |
| PL6 | Tier 1 | Upstream issue lookup -- mechanical search, one right answer. |
| W2 | Tier 2 | Ambiguity resolution. Micro-protocol captures the assumption. |

### Category (b) -- Judgment calls: mostly Tier 2, some Tier 3

| ID | Recommended Tier | Rationale |
|----|-----------------|-----------|
| E2 | Tier 2 | Binary choice with jury recommendation. Follow majority. |
| E3 | Tier 2 | Investigation type with jury recommendation. Follow majority. |
| E5, E6 | Tier 2 | Narrowing within convergence. Research evidence drives the choice. |
| E7 | Tier 2 | Loop decision with existing gap-analysis heuristic. |
| E8 | Tier 2 | Artifact type with scoring framework already defined. |
| E9, E10 | Tier 2 | Deferred choices with simple heuristics. |
| D3 | Tier 3 | Approach selection is the primary purpose of Design Phase 2. Phase primacy applies. |
| D5 | Tier 3 | Deal-breaker evaluation has architectural consequences and moderate irreversibility. |
| D6 | Tier 2-3 | Depends on the specific mid-investigation decision. Pre-classify as Tier 2; let emergent checklist bump if needed. |
| D10 | Tier 2 | Post-completion routing. Reversible (can re-plan later). |
| P4 | Tier 2 | Loop decision with coverage heuristic. |
| P5 | Tier 2 | Trade-offs resolved by research evidence. |
| P7 | Tier 2 | Jury recommendations are already structured evidence. |
| PL3 | Tier 2 | Decomposition strategy has documented heuristic. |
| PL4 | Tier 2 | Execution mode has documented signal-strength heuristic. |
| W1 | Tier 2 | Binary with clear default (proceed). |
| W3 | N/A | This is an error stop, not a decision. Agent halts execution. |

### Category (c) -- Approval gates: Tier 2

| ID | Recommended Tier | Rationale |
|----|-----------------|-----------|
| E4, P3 | Tier 1 | Scope checkpoints are informational. In non-interactive mode, log and proceed. |
| D7, D8 | Tier 2 | Decision review. Record agent-inferred decisions with micro-protocol. |
| D9, P8 | Tier 2 | Final approval. Auto-approve if all automated checks pass; document. |
| P6 | Tier 2 | Draft review. Skip external feedback; proceed to validation. |
| PL5 | Tier 2 | Pre-creation review. Proceed if checks pass. |
| W4 | N/A | Safety gate. Agent halts, not a tier-classified decision. |

## Implementation Notes

1. **Annotation format.** Add `<!-- decision-tier: N -->` comments to phase files above the relevant section. The agent reads these when entering a decision point. If no annotation is present, the agent falls through to the emergent-decision checklist.

2. **Two blocking points are not decisions.** W3 (CI failure halt) and W4 (red check halt) are error stops, not decisions. They should be annotated `<!-- decision-tier: halt -->` to signal that the agent must stop execution rather than classify and proceed.

3. **D6 is the test case for the emergent checklist.** Mid-investigation decisions in Design Phase 3 are the most variable. Pre-classifying as Tier 2 with a note that the emergent checklist may bump to Tier 3 is the right approach. This is where the hybrid pays for itself.

4. **The checklist's three signals are ordered by override strength.** Irreversibility trumps everything (-> Tier 4). Phase primacy sets a floor (-> minimum Tier 3). Heuristic confidence fills in the middle (Tier 2 vs Tier 3). This ordering avoids the decision tree's masking problem because all signals are evaluated, and the strongest override wins.
