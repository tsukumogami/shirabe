<!-- decision:start id="adversarial-lead-framing-and-dont-pursue-output" status="assumed" -->
### Decision: Adversarial Lead Framing and "Don't Pursue" Output

**Context**

The adversarial lead investigates the null hypothesis using six demand-validation
questions that map to code-readable sources (issues, code, docs, PR history). The
design faces two coupled design choices. First: how to frame the agent prompt so it
investigates honestly rather than reflexively seeking rejection. Second: what a "don't
pursue" conclusion produces as a permanent artifact, and whether that artifact routes
through the /decision skill or is written directly from /explore's produce phase.

These choices are coupled because the confidence vocabulary the agent emits (per the
framing decision) determines how crystallize branches, and the branch determines what
artifact the produce phase writes.

Research from three leads establishes the following. The six demand-validation
questions (is demand real? what do people do today? who specifically asked? what
behavior change counts as success? is this already built? is this already planned?)
each map to concrete, readable sources in a code-oriented repo. The agent's work is
structurally similar to other Phase 2 research agents — the critical design concern
is not investigation mechanics but the posture the agent is instructed to take.
gstack's /plan-ceo-review demonstrates a premise-challenge frame (three questions:
right problem? proxy? what if nothing?) with 18 named cognitive instincts, but it
operates on concrete implementation plans, not on exploration topics. The current
no-artifact path in /explore conflates two distinct states: low-signal exploration
that ran out of leads and high-signal investigation that reached a rejection decision.
The /decision skill handles "do not proceed" implicitly but routing there from /explore
would add a redundant investigation loop.

**Assumptions**

- The adversarial lead runs as a standard Phase 2 agent using the existing prompt
  template structure; no new agent dispatch mechanism is needed
- docs/decisions/ is the established permanent location for decision artifacts in the
  shirabe repo, or will be created for this purpose
- "don't pursue" artifact format can adopt the ADR field structure (context, rationale,
  evidence, preconditions for revisiting) without requiring the full /decision workflow
- The distinction between "demand not validated" (thin evidence) and "demand validated
  as absent" (positive rejection evidence) is determinable from the adversarial lead's
  per-question confidence outputs
- crystallize-framework.md signal/anti-signal scoring can accommodate a new supported
  type without breaking the evaluation procedure for existing types

**Chosen: Option A (Reporter Frame) + Option Z/X (Extend Crystallize with Standalone Produce Path)**

*Framing: Reporter frame with explicit per-question confidence vocabulary*

The adversarial lead uses a reporter posture: "Investigate whether evidence supports
pursuing this. Report what you found. Cite only what you found in durable artifacts."
The agent produces a finding for each of the six demand-validation questions with a
per-question confidence indicator: high, medium, low, or absent.

Confidence definitions:
- **High**: multiple independent sources confirm (distinct issue filers, maintainer
  labels, linked PRs, explicit acceptance criteria authored by maintainers)
- **Medium**: one source type confirms without corroboration (single issue, no
  maintainer signal)
- **Low**: evidence exists but is weak (single comment, proposed solution cited as
  if it were a problem statement)
- **Absent**: searched the relevant source types (issues, code, docs, PR history);
  found nothing

The agent also produces a calibration section distinguishing two conclusions:
- **Demand not validated**: findings are majority absent/low, no positive evidence of
  rejection. The right response is flagging the gap, not recommending abandonment.
  Another discover round or user clarification can surface what the repo artifacts
  couldn't.
- **Demand validated as absent**: positive evidence that demand doesn't exist or was
  already evaluated and rejected (closed PRs with explicit reasoning, design docs that
  de-scoped the feature, maintainer comments declining the request). Warrants "don't
  pursue" crystallize outcome.

This framing prevents reflexive negativity structurally: the instruction "report what
you found" gives no reward for skeptical conclusions. The agent is not asked to
"challenge" the topic. Its verdict belongs to convergence and the user, not to the
adversarial agent.

*Output: Extend crystallize-framework.md with a new "don't pursue" supported type
that routes to a standalone produce path writing to docs/decisions/*

crystallize-framework.md receives a new Supported Type: **Rejection Record**. Its
signals and anti-signals:

Signals:
- Exploration reached an active rejection conclusion (not exhaustion of leads)
- Adversarial lead returned high or medium confidence evidence of absent or rejected
  demand on multiple demand-validation questions
- Specific blockers or failure modes were identified with citations
- Re-proposal risk is high (common request, non-obvious rejection reasoning)
- Investigation was multi-round or adversarial

Anti-signals:
- Leads ran out without a conclusion (no positive rejection evidence; route to no-artifact)
- Rejection reasoning is already documented publicly (reference existing docs)
- Low-stakes decision unlikely to resurface (close with comment)

The produce path for Rejection Record writes a lightweight artifact to docs/decisions/
(permanent location, not wip/) covering:
1. What was investigated (scope and sources)
2. What was found per demand-validation question (with confidence)
3. What conclusion was reached and why
4. What preconditions would need to change to revisit

This artifact uses ADR-style fields without routing through /decision's full workflow.
The produce phase instructs the user to close the issue referencing the rejection
record. If re-proposal risk is high, it offers to produce a formal decision record
via /decision for additional structure.

The no-artifact path wording is tightened to explicitly exclude cases where a rejection
conclusion was reached: "Only appropriate when exploration produced no new decisions.
A rejection decision is a decision — route to Rejection Record instead."

**Rationale**

The reporter frame wins over the premise-challenge frame (Option B) because the
research finding is dispositive: reflexive negativity is a prompt-engineering problem,
not a structural one. The fix is in the framing of the agent's instruction, and
"investigate and report" with per-question confidence gives the agent no incentive to
reach skeptical conclusions. The premise-challenge frame's three questions (right
problem? proxy? what if nothing?) are covered by the six demand-validation questions
already established — "is demand real?" subsumes "what if nothing?"; "who specifically
asked?" and "what do people do today?" together address the proxy-problem question.
Adopting Option B would replace established vocabulary with a different vocabulary,
producing inconsistency without closing a real gap.

Option Y (route to /decision) is rejected because /explore already conducted the
investigation the /decision skill would repeat in Phases 1-2. Routing there adds
redundant overhead. The /decision skill's output format (ADR fields) is worth adopting;
its process is not worth repeating. Option X and Option Z are not competing — Z
describes the framework change (new Rejection Record supported type in
crystallize-framework.md) and X describes the artifact it produces (standalone
docs/decisions/ file). Combining them gives the cleanest result: the crystallize
evaluation procedure scores the new type correctly, and the produce path handles the
artifact without redundant process.

**Alternatives Considered**

- **Option B (Premise-challenge frame)**: Three questions from gstack Step 0 with 18
  named cognitive instincts. Rejected because it produces posture (pursue/narrow/don't
  pursue) rather than per-question confidence vocabulary; it operates on implementation
  plans where concrete components exist, not on exploration topics; and its three
  questions are subsumed by the six demand-validation questions already established.
  The cognitive frame's meta-transparency value is real, but can be incorporated into
  the reporter-frame prompt as named posture guidance without adopting B's structure.

- **Option C (Hybrid)**: Reporter frame for six questions + premise check as separate
  section. Rejected because the premise check adds complexity without resolving a gap
  the reporter frame doesn't already cover. Two separate sections can produce
  contradictory signals that require adjudication. Option A with strong reporter-posture
  instructions subsumes what Option C provides.

- **Option Y (Route to /decision)**: Hand off to /decision for formal ADR production.
  Rejected because /explore already did the investigation /decision would repeat in
  Phases 1-2. The skill's process is redundant; only its output format is valuable.
  Adopting the ADR field structure in the standalone produce path captures that value
  without the overhead.

**Consequences**

What changes:
- Phase 1 scope logic (where the adversarial lead gets injected) needs to produce the
  reporter-frame prompt with per-question confidence instructions
- crystallize-framework.md gains a new Rejection Record supported type with
  signal/anti-signal scoring rows
- phase-5-produce-no-artifact.md is tightened to exclude active rejection conclusions
- A new phase-5-produce-rejection-record.md file is created with the produce path for
  docs/decisions/ artifacts
- The user-facing close workflow (close issue referencing the rejection record) is
  defined in the produce phase file

What becomes easier:
- Crystallize can score "don't pursue" conclusions without forcing users to pick
  between PRD, Design, Plan, or the semantically wrong "no artifact"
- Future contributors find rejection reasoning in docs/decisions/ rather than buried
  in closed issue comments or lost wip/ files
- The adversarial lead's per-question confidence output maps directly to crystallize
  branching without additional interpretation

What becomes harder:
- The crystallize evaluation procedure has five types to score instead of four;
  Rejection Record's anti-signals must be written precisely enough that it doesn't
  score high for "ran out of leads" explorations
- Maintaining docs/decisions/ as the canonical location requires the produce path to
  create the directory if it doesn't exist

What is foreclosed:
- Routing all "don't pursue" outcomes through /decision (Option Y) is not the first-
  class path; /decision remains available as an offer for high-stakes rejections but
  is not the default
<!-- decision:end -->
