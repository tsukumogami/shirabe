# Lead: Directional vs Diagnostic Topic Detection

## Findings

### Current State: No Classification Logic Exists

Phase 1 (scope) in `/home/dangazineu/dev/workspace/tsuku/tsuku-5/public/shirabe/skills/explore/references/phases/phase-1-scope.md` contains no topic classification logic. It is a conversational scoping phase that tracks six areas (intent, prior knowledge, uncertainty, constraints, scope edges, stakes) internally and produces research leads. There is no code path, branching logic, or heuristic that distinguishes directional from diagnostic topics before or during this phase.

Phase 0 (setup) in `phase-0-setup.md` handles branch setup, context resolution (visibility/scope), and issue triage. The triage process classifies issues into "needs investigation / needs breakdown / ready" and then "needs-prd / needs-design / needs-spike / needs-decision." This is the closest existing classification logic, but it operates on issue labels and body text after the user has already described what they need — it does not distinguish directional from diagnostic as a topic property.

The `SKILL.md` input detection section (line 78-83) recognizes three input forms: empty (prompt user), issue number, or free-form topic string. No topic type inference happens at input detection time.

### Issue 9's Own Description of the Gap

Issue 9 (`feat(explore): add adversarial lead for demand validation on directional topics`) explicitly names this as an open question: "how does Phase 1 detect 'directional' vs 'diagnostic' topics? What signals distinguish 'should I build X' from 'how do I fix X'?" The issue does not answer it — detection design is left to the design doc this exploration is meant to produce.

### Observable Signal Categories

**Topic string heuristics (from $ARGUMENTS or issue title)**

Directional signals in topic strings tend to cluster around construction and creation verbs: "add", "build", "new", "implement", "create", "introduce", "support", "enable". They also appear as noun phrases that name a feature that doesn't exist yet: "adversarial lead", "plugin system", "version resolution."

Diagnostic signals tend toward problem-locating verbs: "fix", "debug", "investigate", "why is", "broken", "failing", "incorrect", "not working", "regression." They often include a specific existing behavior that is wrong.

The boundary cases are legitimately ambiguous: "improve performance" (existing feature, diagnostic-adjacent), "refactor X" (existing feature, no clear demand question), "migrate X to Y" (structural, neither directional nor diagnostic).

**Issue label signals**

From the issue list and `label-reference.md`: `needs-prd` is the strongest proxy for directional topics — it means "requirements unclear or contested," which implies a new capability. `needs-design` can be either (a new feature needing architecture, or an existing feature needing a rethink). `needs-spike` and `needs-decision` are agnostic. `bug` label is a reliable diagnostic signal.

Issue 9 itself carries `needs-design`, which is consistent with a directional feature: the what (adversarial demand validation) is roughly understood, the how (detection, integration, framing) is not.

**Conversation cues in Phase 1**

The Phase 1 coverage tracking table includes "Stakes" (what happens if we get it wrong, who cares) and "Intent" (what the user is trying to accomplish). These are natural extraction points. Directional topics tend to produce hedged intent statements: "I want to add...", "I'm thinking of building...", "should we...". Diagnostic topics produce more grounded ones: "X is broken", "users are seeing...", "this fails when...".

The Phase 1 instruction to "name uncertainty" (line 30-32) is already attuned to hedged phrasing. An extension of this behavior — recognizing hedging around whether the thing should exist at all — is a natural fit.

**Absence of problem statement**

Diagnostic topics almost always have a problem statement: a specific behavior, error, or failure. Directional topics often lack one. The absence of a concrete problem statement is a positive signal for directional classification. In Phase 1 scoping terms, if "prior knowledge" and "intent" reveal no existing broken behavior, that suggests the topic is additive rather than corrective.

**PRD/design routing signals from SKILL.md**

The SKILL.md routing table (lines 35-58) makes implicit directional/diagnostic distinctions without naming them. "I want to build X but don't know where to start" routes to `/explore` because artifact type is unclear — this is prototypically directional. "I know what to build, not how" routes to `/design` — directional with resolved requirements. None of the routing entries correspond to "how do I fix X" patterns, because those typically don't reach `/explore` at all — they route to `/work-on` directly.

This is a key structural insight: `/explore` as currently described is nearly always invoked on directional or ambiguous topics, not diagnostic ones. The "how do I fix X" user would typically use `/work-on`, not `/explore`. This has implications for false-positive cost.

### Analogous Classification Logic Elsewhere

The prd skill's `phase-2-discover.md` (lines 23-29) performs feature type classification: "User-facing feature / Technical/infrastructure / Process/workflow" — each maps to different specialist agent roles. This is the closest analogous pattern in the codebase. It's done post-scope (after Phase 1), using the contents of the scope file rather than the raw topic string. This suggests a workable model: classify after scoping rather than before, using what the conversation revealed.

The `plan/SKILL.md` (line 333) detects input type from path pattern (design, prd, roadmap, topic). This is purely structural pattern matching on file paths, not semantic topic classification.

### False-Positive Cost Analysis

**False positive (fires on diagnostic topic):** The adversarial lead asks: "is demand real? what do people do today instead? who asked for this? what behavior change counts as success?" Applied to a diagnostic topic like "fix the broken rate limiter," these questions become nonsensical or actively obstructive. The agent investigating them would either produce useless findings or, worse, slow down the exploration. The user is already in problem-solving mode; being asked to justify the demand for the fix is disorienting and erodes trust in the tool.

Cost: moderate to high. It adds noise to the findings, wastes agent compute on one lead, and may confuse convergence if the adversarial findings don't fit the framing. Recoverable — the user can ignore the findings — but degrades UX noticeably.

**False negative (misses directional topic):** The adversarial lead is not fired on a topic like "add adversarial demand validation." The exploration proceeds without anyone asking "is this worth building?" The converge phase and crystallize framework might still surface this implicitly (the PRD signals table asks about contested requirements), but the adversarial framing — null hypothesis investigation — would be absent.

Cost: low to moderate. The exploration produces a less critical artifact. The demand validation question might get raised in later phases (design review, PRD validation) or by the user themselves. It's a missed opportunity, not a blocking failure.

**Asymmetry:** False positives cost more than false negatives. The diagnostic user is disrupted; the directional user just gets slightly less rigor. This argues for a conservative detection threshold: only fire when signals are strong and consistent, not on ambiguous cases.

## Implications

### Detection Should Happen After Phase 1 Conversation, Not Before

The most reliable signal source is what Phase 1 reveals: whether the topic has an existing broken behavior, whether intent is additive or corrective, whether the user hedges around whether the thing should exist. Attempting to classify from the raw topic string alone (before any conversation) would be brittle — "migrate auth to OAuth" looks superficially directional but is often diagnostic (fixing an auth problem by replacement).

A practical implementation: at the end of Phase 1, before writing the scope file, the orchestrator applies classification logic to what it has learned — intent area, prior knowledge area, presence/absence of a concrete problem statement — and decides whether to include an adversarial lead automatically.

### Issue Labels as Pre-Conversation Signal

If entering from an issue, label signals are available before Phase 1 starts. `bug` label = reliably diagnostic (skip adversarial). `needs-prd` = reliably directional (include adversarial). `needs-design` = uncertain (defer to Phase 1 conversation). No label = defer to Phase 1.

### The NLP Heuristic Is Unreliable Alone

Keyword matching on "add/build/implement" vs "fix/debug/investigate" has real false-positive problems. "Add a workaround for the broken parser" starts with "add" but is diagnostic. "Fix how we handle new user onboarding" starts with "fix" but addresses a directional improvement. The heuristic can serve as a weak prior but shouldn't be the sole signal.

### The '/explore' Invocation Pattern Is Naturally Filtered

As noted above, diagnostic topics rarely reach `/explore` — users with a bug typically use `/work-on`. This means detection's prior probability of encountering a diagnostic topic in `/explore` is lower than it would be across all tools. This raises the acceptable false-negative tolerance and lowers false-positive exposure — a useful structural property to exploit.

## Surprises

**'/explore' is already directional-biased by routing.** The SKILL.md routing table routes diagnostic topics away from `/explore` and toward `/work-on`. This means the population of topics that actually reach Phase 1 is already skewed toward directional. Detection doesn't need to be defensive against diagnostic topics as frequently as the issue framing implies.

**The prd skill already does feature-type classification mid-workflow.** This is directly analogous to what issue 9 proposes. The prd skill waits until after Phase 1 scoping, reads the scope file, and classifies before launching agents. This pattern — classify post-scope, not pre-scope — is already established in the codebase and could be adopted without introducing a novel mechanism.

**Issue labels are the most reliable pre-conversation signal, but the codebase doesn't use them this way yet.** Phase 0's triage logic uses labels for routing (needs-triage, needs-design, etc.) but doesn't forward label information to Phase 1 as a classification hint. This is a simple addition.

## Open Questions

1. **Where exactly in Phase 1 does classification happen?** At the start (if entering from an issue with labels), during the conversation (as signals accumulate), or at the end before writing the scope file? The post-scope approach is safest but adds latency. The during-conversation approach could be natural but requires the orchestrator to maintain running classification state.

2. **Should the adversarial lead be named as such to the user?** Presenting it as "I'm also including a lead to validate whether this is worth pursuing" sets clear expectations. Silently adding it is cleaner UX but might confuse users when findings include demand-skeptical content.

3. **How does the adversarial lead interact with the converge phase?** If it returns "demand is weak, three alternatives exist," does that automatically affect artifact type recommendation in crystallize? Or does it just fold in as one input among many? The current crystallize framework has no "don't pursue" first-class outcome.

4. **What handles the "don't pursue" crystallize outcome?** Issue 9's acceptance criteria call this out explicitly. The crystallize framework currently supports PRD, Design Doc, Plan, No artifact, and deferred types. A "don't pursue" output is different from "no artifact" — it's an affirmative recommendation not to build. This needs its own produce path.

5. **What's the right treatment of ambiguous topics (e.g., "migrate X to Y", "improve performance")?** These are neither clearly directional nor diagnostic. Should ambiguous cases default to including the adversarial lead (false-positive risk) or excluding it (false-negative risk)? The asymmetric cost analysis above suggests defaulting to exclusion with an option to include.

## Summary

No directional vs diagnostic classification logic exists in `/explore` today; Phase 1 is a pure conversation with no topic-type inference, and no other skill in the codebase solves this exact problem — though the prd skill's post-scope feature classification is the closest analogue and a viable model. The most reliable detection approach combines issue labels (available pre-conversation) with Phase 1 conversation output (available post-scope), applied conservatively because false positives on diagnostic topics are costlier than false negatives on directional ones. The biggest open question is not detection itself but what happens downstream: the crystallize framework has no first-class "don't pursue" outcome, and that gap must be designed before the adversarial lead has anywhere to land.
