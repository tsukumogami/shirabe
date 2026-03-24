# Lead: What are the failure modes of always-on vs conditional adversarial framing in /explore?

## Findings

### How /explore currently uses Phase 2 agents

Phase 2 fans out research agents in parallel, one per lead from the scope file. Agents run with
`run_in_background: true`. The orchestrator waits for all agents, then hands off to Phase 3
(Converge). Because agent work in Phase 2 is already parallel, adding one more agent — an
adversarial demand-validation lead — costs nothing in latency as long as it runs alongside the
existing leads. The latency impact is effectively zero if the adversarial agent can complete
within the same wall-clock window as the other leads.

This is structurally unlike `/review-plan`'s fast-path, where the review runs sequentially after
decomposition. In `/explore`, Phase 2 is the natural home for parallel speculation, and an
adversarial demand-validation lead is just another Phase 2 agent.

### The always-on failure mode

An adversarial demand-validation lead asks "is there real demand for this?" Its failure mode
on diagnostic topics is not latency (latency is free, as above) but signal noise and user
experience degradation in Phase 3.

For a diagnostic topic like "why does tsuku install fail on arm64?", the adversarial agent would
need to produce a finding. Its only honest finding is "this is not a demand question — the
demand is implicit in the bug report." That finding is noise: it consumes space in the Phase 3
synthesis, requires the converge step to dismiss it, and dilutes the findings that actually
matter. Over many diagnostic runs, users will learn to ignore the adversarial section, which
means the section loses its value precisely when it would be useful (directional topics).

There's also a reflexive negativity risk. On topics with genuine, well-established demand
(scenario b: adding a well-supported package manager format), an always-on adversarial agent
may surface "demand appears solid" as a finding — which is a null result dressed up as
investigation. This adds noise without adding signal. The user already knew demand was solid;
that's why they proposed it.

### The conditional failure mode

Conditional firing requires reliable topic classification. The classification question is roughly:
"Is this a directional/zero-to-one topic or a diagnostic/incremental topic?"

The /explore skill already does something analogous in Phase 0 (triage), where three competing
agents argue investigation vs. breakdown vs. ready. The triage machinery classifies issue type
before proceeding. However, the triage classification is coarse: it routes to exploration vs.
immediate implementation, not to "adversarial lead needed" vs. "adversarial lead skipped."

A demand-validation trigger needs a finer classification. Failure modes:

- **False negatives**: A directional topic gets classified as diagnostic, the adversarial lead
  doesn't fire, and the exploration proceeds to PRD/design without challenging the premise.
  For "add AI-assisted recipe generation" (scenario c), a false negative means the skill
  invests research cycles in how to build the feature without asking whether it should be built.
  This is the more costly failure mode — it produces artifacts that anchor the conversation
  on implementation when the fundamental question was never validated.

- **False positives**: A diagnostic topic gets classified as directional. The adversarial lead
  fires and produces a null finding ("demand is implicit in the bug report"). This is annoying
  noise but not a decision-corrupting failure — Phase 3 synthesis dismisses it and moves on.

### The /review-plan precedent: same categories, different depth

DESIGN-plan-review.md addresses an analogous question directly in Decision 2 (Two-Tier Model):
"Fast-path skips C and D" was explicitly rejected because skipping categories defeats the
purpose of mandatory review. The chosen approach is "same categories in both modes, different
agent count and evaluation depth."

This precedent cuts against always-on adversarial framing. The /review-plan rationale for
running all categories always is that all four categories target known, specific failure modes
that must not go undetected. An adversarial demand-validation lead does not have the same
property: it only targets one failure mode (premature commitment to zero-to-one directions),
and that failure mode does not apply to diagnostic or incremental topics. The /review-plan
analogy supports conditional firing by category, not always-on.

However, the precedent also supports one aspect of always-on: the rationale against
"skipping categories to save latency" applies here too. If latency is genuinely free (parallel
execution), the argument for conditional becomes purely about signal quality and user
experience, not speed.

### Scenario analysis

**a. Diagnostic: "why does tsuku install fail on arm64?"**
Always-on: adversarial agent fires, produces "demand implicit in bug report," noise in Phase 3.
Conditional: demand topic classification correctly fires false (diagnostic signal: "why does X
fail" framing, specific error context). Adversarial lead skipped. Clean findings.
Winner: conditional — always-on adds noise without benefit.

**b. Directional, clear demand: "add support for a well-established package manager format"**
Always-on: adversarial agent fires, finds demand solid, produces a null finding. Noise.
Conditional: must classify as directional (it is a "new capability" framing). If classification
succeeds, fires correctly. If it fails (false negative), a well-supported feature proceeds
without validation — but the cost is low since demand was solid anyway.
Winner: roughly equivalent. Always-on adds noise; conditional might miss, but the miss is cheap.

**c. Directional, uncertain demand: "add AI-assisted recipe generation"**
Always-on: adversarial agent fires, finds demand genuinely uncertain, produces a valuable
finding that challenges the premise and surfaces evidence (or lack thereof) for user need.
Conditional: classification must correctly identify this as directional + uncertain. The
"AI-assisted" framing is a directional signal. If classification succeeds, fires correctly.
If it fails (false negative), exploration proceeds to artifact production without demand
validation — a costly miss. This is the case where false negatives hurt most.
Winner: conditional if classification is reliable; always-on if false negatives are likely.

**d. Triage entry point: issue labeled needs-triage**
Phase 0 triage already classifies the issue type before Phase 1 even begins. By the time
Phase 2 runs, the skill has already committed to exploration (investigation path) vs.
breakdown/immediate implementation. The needs-triage label does not tell us whether the
issue is directional or diagnostic — a needs-triage bug can be just as "needs investigation"
as a needs-triage feature request.
Winner: conditional requires the triage classification to surface directionality, which current
Stage 2 triage (needs-prd / needs-design / needs-spike / needs-decision) partially supports.
`needs-prd` is the strongest signal for "directional topic."

### The user experience of "demand looks solid, proceed" vs. no finding

If the adversarial lead fires and returns "demand looks solid," the user sees a Phase 3 section
that says: the demand validation checked out. This is marginally useful as a sanity check —
it provides one sentence of reassurance. But the cost is that the finding occupies synthesis
space, trains users to gloss over it, and dilutes the overall signal quality of Phase 3.

If the adversarial lead doesn't fire (conditional, correct classification), the user gets a
denser Phase 3 with no demand section. The implicit message is "we validated this was a
directional topic and ran demand validation — it's fine." But that implicit message requires
the user to trust the classification, which they can't easily verify.

The user experience argument weakly favors conditional: users read Phase 3 synthesis to make
decisions, and a null adversarial finding competes for attention with genuine findings.

## Implications

1. **The latency argument for conditional is weak.** Parallel Phase 2 execution makes
   always-on essentially free in wall-clock time. The decision between always-on and
   conditional must rest on signal quality, not speed.

2. **The decisive question is: how reliable is topic classification?** If directional vs.
   diagnostic classification can be done with high confidence in Phase 1 (scope) — and
   the existing scope conversation already extracts intent, constraints, and uncertainty —
   then conditional is clearly superior. If classification is unreliable, always-on avoids
   false negatives at the cost of systematic noise on diagnostic topics.

3. **The /review-plan precedent supports conditional-by-type, not always-on.** The analogy
   that holds is: run the adversarial check when the failure mode it guards against is
   present. Demand validation guards against one specific failure mode (premature directional
   commitment) that is absent for diagnostic topics.

4. **False negatives on genuinely uncertain directional topics are the most costly failure.**
   Scenario c shows that missing demand validation on "add AI-assisted recipe generation"
   leads to artifact production work on a feature whose premise was never challenged. This
   is a concrete, recoverable but expensive mistake. False positives (noise on diagnostic
   topics) are annoying but not decision-corrupting.

5. **The trigger can be made reliable.** The scope conversation (Phase 1) already surfaces
   topic intent. A simple heuristic — fire the adversarial lead when the core question is
   "should we build X?" vs. "why does X fail?" — is classifiable with high confidence from
   the user's phrasing and the issue's label (needs-prd signals directional more strongly
   than needs-design or needs-spike, and no-issue topics can be classified from phrasing).

## Surprises

- The latency argument that typically motivates "conditional" features disappears here.
  Phase 2's parallel architecture means always-on and conditional have identical latency
  profiles. This forces the choice onto signal quality alone, which is less ambiguous.

- The existing Phase 0 triage already partially solves the classification problem. If an
  issue reaches Phase 2 via the `needs-prd` path, the skill already determined that
  requirements are the primary gap — which is a strong proxy for "directional topic."
  The trigger classification doesn't need to be invented from scratch; it can read the
  triage outcome.

- The /review-plan design rejects "skip categories to save latency" but for a reason that
  doesn't apply here: /review-plan categories guard against known failure modes that
  apply to every plan. Adversarial demand validation only guards against one failure mode
  that applies to a specific topic type. The analogy supports conditional.

## Open Questions

1. **Can Phase 1 scope output reliably encode the directional vs. diagnostic signal?** The
   scope file already has "Core Question" and "Context" sections. Would adding a
   `Topic Type: directional | diagnostic | incremental` field to the scope file give
   Phase 2 a clean trigger condition — and is Phase 1 capable of classifying it consistently?

2. **Is there a hybrid: always-on but with topic-aware framing?** Instead of firing a
   separate adversarial lead, the adversarial question could be embedded in the scope phase
   as a conditional scoping question: "Before we investigate how to build this, do we know
   there's real demand?" This moves the challenge earlier (before agents are launched) and
   avoids the Phase 3 noise problem entirely.

3. **What does "conditional" mean for the triage entry point?** When starting from a
   `needs-triage` issue, the Stage 2 triage already routes to needs-prd / needs-design /
   etc. Should the adversarial lead fire automatically for needs-prd routes, making the
   trigger implicit in the triage output rather than requiring a separate classification?

4. **What is the false negative rate for a simple phrasing-based classifier?** If "add X"
   or "support Y" patterns reliably indicate directional topics and "why does X fail" or
   "fix X" patterns reliably indicate diagnostic, the classifier's accuracy is testable
   against the existing /explore evals corpus.

## Summary

The latency argument for conditional firing disappears in /explore's parallel Phase 2 architecture — always-on adds zero wall-clock cost, forcing the decision onto signal quality alone. Conditional framing is still superior because always-on produces systematic Phase 3 noise on diagnostic topics (false positives that train users to ignore the adversarial section), while conditional's only risk is false negatives on genuinely uncertain directional topics — the most costly failure mode, but one that a reliable classifier can largely prevent. The existing Phase 0 triage output (specifically, the `needs-prd` classification) already provides a strong proxy signal for "directional topic," meaning conditional trigger detection can reuse existing classification machinery rather than requiring new logic.
