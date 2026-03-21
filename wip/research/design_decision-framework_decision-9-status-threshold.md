# Decision 9: Confirmed/Assumed Status Threshold

## Question

What specification determines when a decision block gets `status="confirmed"` vs
`status="assumed"`?

## Context

The decision block format (Decision 1 in the design doc) defines two operational
status values: `confirmed` and `assumed`. The design doc says `confirmed` means
"evidence-based, high confidence" and `assumed` means "best guess, pending review."
But there's no concrete rule for where the line falls. Without a specification,
agents will either mark everything `confirmed` (path of least resistance) or mark
everything `assumed` (cover-your-bases), and the status field loses its signal value.

The 39 blocking points from the ask inventory break into three categories that
interact differently with this threshold:

- **Researchable (11, 28%)**: The agent found the answer through research. These
  should almost always be `confirmed` -- the evidence exists and was checked.
- **Judgment calls (19, 49%)**: The agent followed a heuristic or weighed trade-offs.
  These are the contested boundary -- some heuristics produce clear winners, others
  don't.
- **Approval gates (10, 26%)**: The agent auto-approved its own output. These are
  inherently `assumed` in non-interactive mode because the user hasn't seen the work.

## Options Evaluated

### Option A: Three-condition heuristic

The proposed rule from the lightweight framework research:

Mark `status="assumed"` when ANY of these hold:
1. Evidence was split (roughly 60/40 or closer)
2. The choice depends on facts the agent couldn't verify during execution
3. In interactive mode, this would have triggered AskUserQuestion

Otherwise, mark `status="confirmed"`.

**Strengths:**
- Three concrete, checkable conditions. An agent can evaluate each one independently.
- Condition 3 creates a direct mapping from the existing AskUserQuestion sites --
  if the current skill file says "ask the user," that's `assumed` in auto mode.
- Covers the key uncertainty types: contested evidence (1), unverifiable premises (2),
  and design-intended user checkpoints (3).

**Weaknesses:**
- Condition 1 ("roughly 60/40") is subjective. What's 60/40 vs 70/30? The agent
  is self-assessing its own confidence, which is the same problem a confidence score
  has.
- Condition 3 is extremely broad. ALL 39 blocking points trigger AskUserQuestion in
  interactive mode. If every former AskUserQuestion site becomes `assumed`, then
  confirmed is reserved for decisions that never had a user interaction point -- which
  is basically only convention-following (Tier 1 decisions that don't get blocks at all).
  The status field becomes nearly useless because almost everything is `assumed`.
- The three conditions overlap. A 60/40 evidence split (condition 1) almost always
  means it would have been asked in interactive mode (condition 3). Overlapping
  conditions add complexity without discrimination.

**Gaming risk:** Medium. Condition 1 is gameable (agent can claim 70/30 for anything).
Conditions 2 and 3 are more objective but 3 is too inclusive.

### Option B: Confidence score (1-5)

Agent assigns a confidence score. 4-5 = confirmed, 1-3 = assumed.

**Strengths:**
- More granular than binary. A score of 2 ("I guessed") is different from 3
  ("evidence leaned one way but I'm not sure") which is different from 4
  ("evidence clearly pointed here").
- The score can be included in the decision block for review prioritization.
  Reviewers check score-2 decisions before score-4 ones.

**Weaknesses:**
- Pure self-assessment. LLMs are notoriously poorly calibrated on confidence. An
  agent that says "confidence: 4" and an agent that says "confidence: 3" may have
  identical evidence quality -- the difference is in the agent's disposition, not
  the evidence.
- Adds a field that looks precise but isn't. A reviewer seeing "confidence: 4"
  might trust it more than warranted. False precision is worse than honest vagueness.
- The 1-5 scale needs its own specification (what's a 1? what's a 5?), which just
  pushes the threshold problem down a level.
- In practice, agents cluster around 3-4. The distribution won't be informative.

**Gaming risk:** High. Agents default to 4 (sounds confident but not overconfident).
The threshold becomes meaningless because everything clusters above it.

### Option C: Evidence-based (assumptions exist = assumed)

If the Assumptions field in the decision block contains any entries, `status="assumed"`.
If the Assumptions field is empty, `status="confirmed"`.

**Strengths:**
- Mechanically simple. No judgment about confidence or evidence strength -- just
  check whether the Assumptions field is populated.
- Self-documenting. The reason a decision is `assumed` is right there in the
  Assumptions field. The status is derived from content, not declared independently.
- Hard to game without lying. To mark something `confirmed`, the agent must claim
  it made zero assumptions. If a reviewer finds an unlisted assumption, that's a
  clear error, not a judgment disagreement.
- Aligns with the framework's core value: assumption tracking. The whole system
  exists to surface assumptions. Making status directly dependent on assumptions
  reinforces that the Assumptions field is the most important part of the block.

**Weaknesses:**
- Too binary in the wrong direction. Almost every non-trivial decision rests on at
  least one assumption. "Interface definitions won't change" is an assumption.
  "The team prefers simplicity over flexibility" is an assumption. If any assumption
  means `assumed`, then the status is nearly always `assumed`.
- Doesn't distinguish between high-confidence assumptions ("the codebase uses
  kebab-case, verified in 12 files") and low-confidence ones ("the API probably
  supports pagination based on convention"). Both populate the Assumptions field;
  both would trigger `assumed`.
- Incentivizes agents to under-document assumptions to get `confirmed` status.
  This is the worst possible gaming outcome -- it undermines the core tracking
  mechanism.

**Gaming risk:** High in the wrong direction. The gaming incentive (omit assumptions
to get `confirmed`) directly undermines the framework's primary value proposition.
This is a disqualifying flaw.

### Option D: Category-based (mapped from ask inventory)

Map status from the three ask-inventory categories:
- Category (a) researchable: if answered by research, `confirmed`. If research was
  inconclusive, `assumed`.
- Category (b) judgment call: always `assumed`.
- Category (c) approval gate: always `assumed`.

**Strengths:**
- Grounded in the existing categorization of all 39 blocking points. The mapping
  is predetermined at skill-development time, not evaluated per-invocation by the
  agent.
- Clear separation: researchable questions that got researched are confirmed.
  Everything else is assumed. This matches the intuition that "confirmed" means
  "I checked" and "assumed" means "I chose."
- Low gaming risk for categories (b) and (c) -- the category is determined by the
  skill file's structure, not by the agent's self-assessment.

**Weaknesses:**
- Forces all judgment calls to `assumed` regardless of evidence strength. A
  decomposition strategy decision where the heuristic produces a 95/5 signal gets
  the same status as a 55/45 coin flip. This over-flags, creating noise in the
  review surface.
- Requires maintaining the category mapping as skills evolve. New decision points
  need to be classified. This is manageable but adds a maintenance burden.
- The "researchable but inconclusive" sub-case reintroduces the same judgment
  problem for category (a) that the other options have for everything.
- Doesn't account for mixed-category situations. A decision might start as
  researchable (category a) but after research, become a judgment call (category b).
  The category isn't always stable through the decision process.

**Gaming risk:** Low for (b) and (c). Medium for (a) -- the agent decides whether
its research was "conclusive."

## Analysis: What Problem Are We Actually Solving?

The status field serves one purpose: **review triage**. When a user reviews
assumptions after a non-interactive run, `assumed` says "look at this one" and
`confirmed` says "probably fine, skip unless something looks wrong."

This means the threshold needs to optimize for two things:
1. **Low false-negative rate**: decisions that need review must not be marked
   `confirmed`. Missing an important assumption is worse than flagging a solid one.
2. **Meaningful signal**: if everything is `assumed`, the status field adds no
   information and reviewers ignore it. The field must split the population
   into two meaningfully different groups.

These goals tension. Lower false-negatives push toward marking everything `assumed`.
Meaningful signal pushes toward marking most things `confirmed`. The right answer
is a threshold that catches the genuinely uncertain decisions without flooding the
`assumed` bucket.

From the 39 blocking points:
- 11 researchable: most should be `confirmed` after research
- 19 judgment calls: some have strong heuristics (14 of 19 per the inventory),
  some don't
- 10 approval gates: most should be `assumed` (user hasn't seen the artifact)

A good threshold should yield roughly 40-60% `confirmed` and 40-60% `assumed`.
That's the range where both values carry information.

## Decision

**Choice: Option D (category-based) with a refinement for judgment calls.**

The pure category-based approach has the right structural property -- categories
are determined at skill-development time, not self-assessed at runtime -- but it
over-flags judgment calls. The refinement:

- **Category (a) researchable, answered by research**: `confirmed`
- **Category (a) researchable, research inconclusive**: `assumed`
- **Category (b) judgment call, heuristic produced a clear signal**: `confirmed`
- **Category (b) judgment call, heuristic was close or absent**: `assumed`
- **Category (c) approval gate**: `assumed`

The "clear signal" vs "close" distinction for judgment calls uses the existing
heuristic infrastructure. 14 of 19 judgment calls already have recommendation
heuristics in their phase files. The specification:

> A judgment-call decision is `confirmed` when the skill's recommendation heuristic
> produced a winner AND the agent found no evidence contradicting that recommendation
> during the gather step. It is `assumed` when the heuristic was close (no clear
> winner), when no heuristic exists, or when contradicting evidence was found.

This is more objective than Option A's "roughly 60/40" because it's anchored to
existing heuristic outputs rather than the agent's general confidence. The heuristic
either produced a clear winner or it didn't -- that's observable from the heuristic's
own scoring/signal structure, not from the agent's feeling about it.

**Why not the others:**

- **Option A** (three-condition heuristic): condition 3 is too broad -- it makes
  everything `assumed`. Condition 1 is too subjective. The conditions overlap.
- **Option B** (confidence score): poorly calibrated LLM self-assessment. Agents
  cluster at 3-4. False precision.
- **Option C** (assumptions exist): gaming incentive is backwards -- agents would
  omit assumptions to get `confirmed`, undermining the framework's core value.

**Expected distribution:** With this threshold, roughly:
- 11 researchable points: ~9 confirmed, ~2 assumed (most research is conclusive)
- 19 judgment calls: ~10-12 confirmed (clear heuristic), ~7-9 assumed (close/absent)
- 10 approval gates: ~10 assumed

Total: ~19-21 confirmed (49-54%), ~18-20 assumed (46-51%). Both values carry signal.

## Specification

For inclusion in the decision block format reference:

```
Status Values

A decision block's status attribute is set according to these rules:

  confirmed  The decision is supported by evidence the agent verified
             OR by a skill heuristic that produced a clear winner with
             no contradicting evidence found during the gather step.

  assumed    The decision rests on facts the agent could not verify,
             OR the skill heuristic produced no clear winner,
             OR the decision auto-approved an artifact the user has
             not reviewed (approval gate in --auto mode).

  escalated  A lightweight decision was upgraded to the heavyweight
             decision skill. The partial block is superseded by the
             decision report.

Determination rules by ask-inventory category:

  Researchable  -> confirmed if research answered the question
                -> assumed if research was inconclusive

  Judgment call -> confirmed if the phase's recommendation heuristic
                   produced a clear winner AND no contradicting evidence
                   was found
                -> assumed otherwise (close heuristic, no heuristic,
                   or contradicting evidence found)

  Approval gate -> assumed (always, in --auto mode)
                -> confirmed (always, in interactive mode -- user approved)
```

## Assumptions

- The 14-of-19 judgment calls with existing heuristics will produce a
  "clear vs close" distinction that agents can evaluate more reliably
  than a general confidence score. If heuristic outputs don't have enough
  structure to make this distinction, the specification degrades to "all
  judgment calls are assumed" (Option D's original weakness).

- The expected 50/50 distribution holds in practice. If it skews heavily
  toward one status value, the threshold needs recalibration after
  observing real workflow runs.

## Decision Block

<!-- decision:start id="status-threshold" status="confirmed" -->
### Decision: Confirmed/assumed status threshold specification

**Question:** What rule determines when a decision block gets `status="confirmed"` vs `status="assumed"`?

**Evidence:** Evaluated four options against the 39-point ask inventory. Option C (assumptions-exist) creates a perverse incentive to omit assumptions. Option B (confidence score) relies on poorly calibrated LLM self-assessment. Option A's condition 3 ("would have asked the user") is so broad it makes everything assumed. Option D (category-based) anchors the distinction to skill-development-time categories but over-flags judgment calls without refinement.

**Choice:** Category-based mapping with a judgment-call refinement. Researchable questions resolved by research are confirmed. Judgment calls where the skill heuristic produced a clear winner with no contradicting evidence are confirmed. Approval gates in auto mode are always assumed. Everything else is assumed.

**Alternatives considered:**
- Three-condition heuristic (Option A): condition 3 too broad, conditions overlap, condition 1 subjective
- Confidence score 1-5 (Option B): LLM confidence is poorly calibrated, agents cluster at 3-4
- Assumptions-exist rule (Option C): gaming incentive to omit assumptions undermines core framework value

**Assumptions:**
- Existing skill heuristics produce enough structure to distinguish "clear winner" from "close call"
- The resulting ~50/50 distribution between confirmed and assumed holds in practice

**Consequences:** Each decision point's status is determined by its category (set at skill development time) plus a local evidence check (clear heuristic or not). Reviewers can trust that `confirmed` means either "researched and verified" or "strong heuristic signal" while `assumed` means "judgment call without clear signal" or "user hasn't seen this."
<!-- decision:end -->
