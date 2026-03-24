# Lead: gstack /plan-ceo-review — CEO Review Skill Analysis

Source: https://github.com/garrytan/gstack/tree/main/plan-ceo-review

## Findings

### What the CEO Review Investigates

The skill is framed as "CEO/founder-mode plan review." Its stated purpose is not quality assurance of a finished design but premise challenge and scope calibration before implementation begins. The core investigative structure:

**Step 0: Nuclear Scope Challenge** (mandatory, runs before any content review):

- **0A. Premise Challenge**: Three questions applied to every plan:
  1. Is this the right problem to solve? Could a different framing yield a simpler or more impactful solution?
  2. What is the actual user/business outcome? Is the plan the most direct path, or is it solving a proxy problem?
  3. What would happen if we did nothing? Real pain point or hypothetical?

- **0B. Existing Code Leverage**: What existing code already partially or fully solves each sub-problem? Is this plan rebuilding something that already exists?

- **0C. Dream State Mapping**: Describe the ideal end state 12 months from now. Does this plan move toward that state or away from it? Uses an explicit three-column diagram: CURRENT STATE → THIS PLAN → 12-MONTH IDEAL.

- **0C-bis. Implementation Alternatives (MANDATORY)**: Produce 2-3 distinct implementation approaches with effort/risk/pros/cons before selecting a mode. One must be "minimal viable," one must be "ideal architecture."

- **0D. Mode-Specific Analysis**: Scope Expansion (10x check + platonic ideal), Selective Expansion (cherry-pick ceremony), Hold Scope (complexity check), or Scope Reduction (ruthless cut). Mode selection happens after premise challenge.

- **0E. Temporal Interrogation**: What decisions will need to be made during implementation that should be resolved NOW?

- **0F. Mode Selection**: User chooses one of four modes; skill commits fully to it.

After Step 0, the skill runs 10 technical review sections (architecture, error mapping, security, data flow, code quality, tests, performance, observability, deployment, long-term trajectory). Section 11 covers UI/UX if applicable.

### The Cognitive Frame

The skill names its frame explicitly: "How Great CEOs Think." Eighteen cognitive patterns are listed under the heading "Cognitive Patterns — How Great CEOs Think." They are explicitly framed as instincts to internalize, not checklist items. Key patterns relevant to premise challenge:

- **Inversion reflex** (Munger): For every "how do we win?" also ask "what would make us fail?"
- **Focus as subtraction** (Jobs): Primary value-add is what NOT to do. 350 products → 10.
- **Proxy skepticism** (Bezos Day 1): Are metrics still serving users or have they become self-referential?
- **Temporal depth**: Think in 5-10 year arcs. Regret minimization for major bets.
- **Speed calibration** (Bezos): 70% information is enough to decide; only slow down for irreversible high-magnitude decisions.
- **Classification instinct** (Bezos): Categorize every decision by reversibility × magnitude (one-way vs two-way doors).

The cognitive frame is fundamentally about user/business outcomes, not about implementation quality. The 10 technical sections address implementation quality; Step 0 addresses whether the implementation is worth doing.

### How It Avoids Reflexive Negativity

This is handled through two mechanisms:

**1. Mode selection is the null hypothesis resolution.** The skill does not assume the plan is wrong. It runs a premise challenge, then asks the user to select a mode. The four modes represent four distinct postures: dream bigger, hold and cherry-pick, hold and harden, or cut down. "Do nothing" is one question (0A.3) but not a mode. The challenge is structured to produce a better version, not a rejection.

**2. The posture description explicitly addresses the risk.** Under each mode:
- EXPANSION: "You have permission to dream — and to recommend enthusiastically."
- SELECTIVE EXPANSION: "Neutral recommendation posture — present the opportunity, state effort and risk, let the user decide without bias."
- HOLD SCOPE: "Make it bulletproof — catch every failure mode." (No negativity framing at all.)

The skill states: "You are not here to rubber-stamp this plan. You are here to make it extraordinary." This frames the goal as elevation, not rejection. The challenge questions in 0A are about finding a better path, not blocking the current one.

There is no scoring rubric or grading system. The skill uses AskUserQuestion throughout — one issue per call — and the user remains "100% in control." Every scope change is an explicit opt-in. This structural feature prevents the skill from being a gate that blocks; it's a decision amplifier that surfaces options.

### The VERDICT: NO REVIEWS YET Pattern

The skill does not use "VERDICT: NO REVIEWS YET" as terminology. The prior exploration's description of this pattern maps to the **Review Log / Review Readiness Dashboard** in gstack.

The skill produces a structured Completion Summary table at the end. After completing, it runs:

```bash
~/.claude/skills/gstack/bin/gstack-review-log '{"skill":"plan-ceo-review","timestamp":"...","status":"...","unresolved":N,"critical_gaps":N,"mode":"...","scope_proposed":N,"scope_accepted":N,"scope_deferred":N,"commit":"..."}'
```

The `status` field is either `"clean"` (0 unresolved decisions AND 0 critical gaps) or `"issues_open"`. The `/ship` skill reads this dashboard. The pattern functions as a state machine: a review that has not been run does not appear in the dashboard, making its absence a signal. A review that ran but has `unresolved > 0` or `critical_gaps > 0` blocks shipping.

So "VERDICT: NO REVIEWS YET" is the dashboard state when no review log entry exists — an explicit no-opinion state that counts as a gate signal. The ship workflow interprets absence of a review entry the same as a failing review.

### How CEO Review Findings Feed Back vs Eng Review

The CEO review chains to `/plan-eng-review` and optionally `/plan-design-review`. The skill recommends eng review after CEO review when:
- Scope was expanded or architectural direction changed
- Accepted scope expansions were UI-facing (triggers design review too)
- The CEO review's commit hash will predate the eng review (stale detection)

The CEO review produces a **CEO Plan document** (for EXPANSION and SELECTIVE EXPANSION modes) persisted to `~/.gstack/projects/$SLUG/ceo-plans/`. This artifact carries the vision and scope decisions forward. The eng review does not re-run premise challenge; it accepts the scope decisions from the CEO review and reviews architectural rigor.

Divergence: eng review produces the "required shipping gate" (the skill explicitly calls it this). CEO review is a scope/premise gate. The CEO plan document is consumed by the eng reviewer as the source of truth for what's in scope.

### Eval Structure in gstack

gstack has end-to-end tests in `test/skill-e2e-plan.test.ts`. The plan-ceo-review test:
- Creates a minimal synthetic plan document (user dashboard with React/Express/PostgreSQL/Redis)
- Runs the skill in HOLD SCOPE mode with non-interactive prompting
- Asserts: exit reason is `success` or `error_max_turns` (the review is verbose enough that turn limits are a known issue)
- Asserts: output file exists and is longer than 200 bytes

The eval does NOT assess:
- Whether the premise challenge was adversarial enough
- Whether the review avoided reflexive negativity
- Whether scope challenge was appropriately calibrated to the plan's actual risk

The eval-baselines.json file contains rubrics for other tools (browse, QA, command reference) but not for plan-ceo-review. There is no grading rubric measuring whether CEO review produces honest assessments vs reflexive negativity.

## Implications

### What Transfers to /explore's Adversarial Lead

The strongest transferable pattern is **Step 0's structure**, specifically:

1. **Premise Challenge as mandatory Step 0 before content review.** The three questions (right problem? proxy? what if nothing?) apply directly to exploration topics, not just implementation plans. These questions are pre-design, which is where /explore operates.

2. **Dream State Mapping (0C).** For /explore acting on a topic rather than a plan, an equivalent would be: describe the ideal capability 12 months from now. Does exploring this topic move toward that state? The three-column diagram (CURRENT STATE → THIS EXPLORATION → 12-MONTH IDEAL) is a clean structure for directional topics.

3. **Implementation Alternatives (0C-bis) maps to exploration alternatives.** For a topic, the equivalent is: what are 2-3 distinct ways to approach this area? One minimal (narrow the question), one ambitious (broaden it). Forces consideration of whether the exploration framing is optimal.

4. **Mode selection separates the premise challenge from the content review.** /explore's adversarial lead should similarly produce a mode or posture before diving in — not collapse premise and content challenge into one pass.

### What Changes When Applied Earlier (Pre-Design vs Plan Review)

/plan-ceo-review acts on a concrete plan: named components, files, endpoints, data flows. The premise challenge has material to interrogate. /explore's adversarial lead acts on a topic: a direction, a capability area, a question.

Key differences:

- **Step 0A becomes "is this worth exploring?" rather than "is this the right solution?"** The inversion question changes: instead of "what would make this implementation fail?" it becomes "what would make this topic not worth investigating?"

- **Existing code leverage (0B) becomes existing knowledge/prior art leverage.** Is there already sufficient understanding of this area? Is this exploration re-inventing the wheel?

- **Dream State Mapping (0C) becomes the directional test.** Does exploring this topic produce findings that are actionable vs findings that are academic? What's the mechanism by which exploration produces value?

- **Mode selection is less applicable.** The CEO review's four modes (Expansion/Selective/Hold/Reduction) map to implementation postures. /explore might need different axes: depth (broad survey vs deep dive), stance (open inquiry vs adversarial challenge), or scope (narrow to this repo vs consider adjacent territory).

### CEO Frame in Open-Source/Tool Context

The CEO frame is explicitly business-value-oriented (ROI, product-market fit, user outcomes, revenue). For open-source tools, the analogous frame is:

- **User value** replaces revenue: Does this capability solve a real user problem or a hypothetical one?
- **Ecosystem fit** replaces market position: Does this direction align with how tools in this space are evolving?
- **Contribution gravity** replaces talent: Will this direction attract contributors, or create a maintenance burden with no one to carry it?
- **Reversibility** translates directly: One-way vs two-way door decisions are as relevant in open source as in a company.

The proxy skepticism question ("are our metrics still serving users?") is directly relevant: are the features being explored driven by actual user needs or by what's interesting to build?

## Surprises

1. **The skill is extremely long.** The SKILL.md.tmpl is hundreds of lines. The CEO review is not a lightweight premise check — it's a full plan review with 10 technical sections after Step 0. The premise challenge is mandatory but is the entry point to a comprehensive review, not a standalone filter.

2. **There is no eval rubric for the adversarial quality of the challenge.** gstack's eval for plan-ceo-review only checks that the skill ran and produced output. There is no measurement of whether the challenge was appropriately rigorous, appropriately calibrated, or free from reflexive negativity. This gap directly maps to issue 9's requirement.

3. **The skill explicitly names the cognitive frame.** Unlike skills that embed assumptions implicitly, gstack names 18 CEO cognitive patterns explicitly and explains which questions to apply them to. This meta-transparency makes the frame auditable — you can check whether the review applied the right frame to each section.

4. **Mode selection is a user decision, not a skill decision.** The CEO review does not decide whether to expand or hold scope. It presents options with context-dependent defaults and asks. This preserves user agency and prevents the skill from becoming a gate that blocks work. The adversarial quality comes from making the options legible, not from forcing a particular posture.

5. **The "completeness is cheap" principle actively counteracts scope reduction bias.** The skill explicitly tells the model to prefer complete options over shortcuts, and says "AI coding compresses implementation time 10-100x." This is a direct countermeasure to the reflexive "scope down" response. For /explore's adversarial lead, the equivalent would be: prefer exploring the harder questions, not the comfortable ones.

## Open Questions

1. **What are the right "modes" for /explore's adversarial lead?** The CEO review's four modes (Expansion, Selective Expansion, Hold Scope, Reduction) map to implementation postures. Exploration may need different axes. Candidates: depth (survey vs focused), stance (open vs adversarial), or temporal (near-term vs long-term direction). Is mode selection the right pattern to transfer, or is it implementation-specific?

2. **How should the adversarial lead handle null findings?** If Step 0 determines the topic is worth exploring, the lead has served its purpose and the main exploration proceeds. But if Step 0 finds the topic is not worth exploring, what happens? The CEO review always produces an output artifact. Should /explore's adversarial lead produce a "skip this exploration" output, and how does that fold back into the workflow?

3. **What is the right granularity for the premise challenge in /explore?** The CEO review's three questions (right problem? proxy? what if nothing?) are scoped to a specific plan. For /explore, the topic might be broad ("how should /explore handle adversarial validation?") or narrow ("what does gstack's CEO review do?"). Does the premise challenge change with topic granularity?

4. **How do we measure "honest assessment vs reflexive negativity" without a rubric?** gstack has no eval for this. Issue 9 requires creating one. The challenge is that "honest" requires knowing whether a topic is actually worth exploring, which requires ground truth. Possible approach: use cases where the answer is known (topics that clearly produced value vs topics that were dead ends) and check whether the adversarial lead correctly identifies them. What's the ground truth source?

5. **Does the Dream State Mapping (0C) work for topics that don't have a "12-month ideal state"?** Some exploration topics are about understanding current constraints, not building toward a target. For those, the temporal framing may not apply. Is there an alternative framing for constraint-analysis explorations?

## Summary

gstack's `/plan-ceo-review` runs a mandatory Step 0 premise challenge (three questions: right problem? proxy? what if nothing?) before any content review, uses an explicitly named CEO cognitive frame of 18 instincts (inversion, proxy skepticism, focus as subtraction, reversibility classification), and avoids reflexive negativity by framing the challenge as elevation toward a dream state rather than rejection, with mode selection giving the user control over posture. The "VERDICT: NO REVIEWS YET" pattern is the review dashboard's absence state — reviews that haven't run are treated as failing gates by the /ship workflow, making non-execution explicitly meaningful rather than a neutral default. gstack has no eval rubric measuring whether the challenge is appropriately adversarial vs reflexively negative, which is the key gap that issue 9 must fill.
