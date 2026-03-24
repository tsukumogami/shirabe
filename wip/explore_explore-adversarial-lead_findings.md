# Exploration Findings: explore-adversarial-lead

## Core Question

How should `/explore` add an adversarial demand-validation lead for directional topics,
without changing the UX for diagnostic topics or the discover-converge loop?

## Round 1

### Key Insights

**No classification logic exists today — and Phase 1 already has everything needed to add it.**
There's no directional vs. diagnostic distinction anywhere in the explore workflow. But the
Phase 1 coverage tracking table (Intent, Stakes, Uncertainty, Prior Knowledge) naturally surfaces
exactly the signals needed: directional topics produce hedged intent statements ("should we
build X?"), lack a concrete broken behavior, and score high on Stakes. Issue labels give a
pre-conversation signal: `needs-prd` is a reliable directional proxy; `bug` reliably diagnostic.
The prd skill already does post-scope feature classification in Phase 2 — same pattern,
already established. Detection should happen at the end of Phase 1's lead-production step.

**The adversarial agent has a bounded, code-readable investigation scope.**
The six demand-validation questions (is demand real? what do people do today? who asked?
what behavior change counts as success? is it already built? is it already planned?) map
directly to: GitHub issues, existing code, docs, PR history, design docs/ROADMAP. The agent
posture should be "reporter, not advocate" — cite only what was found, not inferences from
absence. Critically, "demand not validated" (thin evidence) ≠ "demand validated as absent"
(positive evidence of rejection — a closed PR explicitly saying "not building this," a design
doc that de-scoped the feature). The crystallize path branches on this distinction.

**Conditional framing wins decisively; the latency argument doesn't exist.**
Phase 2 is parallel fan-out. Adding one more agent runs in zero additional wall-clock time.
So the choice between always-on and conditional rests purely on signal quality. Always-on
produces systematic Phase 3 noise on diagnostic topics — over many runs, users learn to ignore
the adversarial section, which defeats its purpose on directional topics. Conditional's only
failure mode is false negatives on uncertain directional topics, and the existing triage
machinery already provides a strong proxy: topics entering via `needs-prd` are reliably
directional. The trigger can reuse existing classification rather than building new logic.

**The minimum-disruption integration point is Phase 1's lead-production step.**
Options A (Phase 2 scope-file pre-population) and B (Phase 1 classification) collapse to the
same implementation: Phase 1 decides whether to include the adversarial lead and writes it
into the scope file. Phase 2 dispatches everything in the scope file with zero logic changes.
SKILL.md resume logic is unchanged (scope file presence → Phase 2 is already content-agnostic).
This follows the DESIGN-plan-review.md principle: extend existing artifacts, don't add new
phases or resume checks.

**"Don't pursue" must be a first-class crystallize type, not a fallback.**
The current `phase-5-produce-no-artifact.md` conflates two states: "we ran out of leads
without a conclusion" vs. "we investigated thoroughly and concluded this isn't worth pursuing."
The second is a decision — it needs a permanent artifact (not wip/, which gets cleaned at
merge). The crystallize framework has no signal rows for this outcome. The closest fit is a
Decision Record with a "reject" disposition, which the framework already marks as deferred
(Feature 5 in the roadmap). The no-artifact path's existing guard ("if decisions.md has entries,
return to Phase 4") would already redirect "don't pursue" findings — but there's nowhere to
redirect them to. A "don't pursue" crystallize type closes this gap.

**gstack's CEO review provides the premise-challenge framing, plus the exact eval gap.**
Step 0's three mandatory questions — Is this the right problem? Is it a proxy problem? What
happens if we do nothing? — are a clean transfer to /explore's pre-design context. Avoiding
reflexive negativity works in gstack through: (a) framing the challenge as "find a better
version, not block the current one," and (b) mode selection that separates premise challenge
from content posture, keeping the user in control. The key transfer: name the adversarial
lead's cognitive frame explicitly (like gstack names 18 CEO instincts) and frame it as
elevation, not rejection. gstack's fatal gap for this feature: no eval rubric measures whether
the challenge was appropriately adversarial vs reflexively negative. Issue 9 must fill this.

### Tensions

- **Who owns the "don't pursue" artifact?** /explore already did the investigation; routing to
  /decision would re-run premise research redundantly. But /decision already has a "do not
  proceed" output format. Should /explore's produce-don't-pursue path be lightweight (just
  write findings to docs/decisions/), or hand off to /decision for the structured ADR format?

- **Classification confidence threshold.** /explore is already directional-biased by routing
  (diagnostic users typically use /work-on). This means the adversarial lead's prior probability
  of firing on a diagnostic topic is low. Ambiguous topics (migration, refactor, "improve X")
  need a conservative default: exclude unless signals are strong. But how to define "strong"?

- **Modes vs. single posture for the adversarial lead.** gstack's four modes (Expand/Selective/Hold/Reduce)
  let users steer after premise challenge. /explore's adversarial lead could similarly produce
  a mode recommendation — but the action space is different (explore further / proceed to artifact
  / don't pursue / narrow scope). Is mode selection worth the UX overhead at this stage?

### Gaps

- **Eval rubric for honest vs reflexive assessment**: the key open gap from issue 9 AC5. No
  prior art (gstack doesn't have it either). Needs design. Ground truth source unclear.
- **Exact "don't pursue" artifact format**: content fields, location (docs/decisions/?), issue
  close workflow.
- **Confidence vocabulary**: what thresholds map to "proceed", "another round", "don't pursue"?

### Decisions

None yet — all four issue 9 design questions are now informed but not decided. Decisions belong
in the design doc.

## Accumulated Understanding

**What the adversarial lead is:**
An optional Phase 2 research agent that fires for directional topics. It investigates the null
hypothesis using code-readable demand signals. It reports evidence, not verdicts — the verdict
comes from convergence + user decision.

**How it integrates:**
Classification happens at the end of Phase 1's lead-production step (using issue labels +
conversation signals). The adversarial lead is written into the scope file. Phase 2 dispatches
it like any other lead. Zero changes to Phase 2, Phase 3, or SKILL.md resume logic.

**What it produces:**
A research file like any other Phase 2 lead. Findings include: evidence for each of the six
demand-validation questions, a confidence indicator (high/medium/low/absent) per question,
and a calibration section distinguishing "demand not validated" from "demand validated as absent."

**What crystallize does with it:**
If findings support proceeding → weights toward PRD or Design Doc as normal.
If findings show "demand validated as absent" → crystallize to "don't pursue" (new type).
If findings show "demand not validated" (thin evidence) → recommend another round or user clarification.

**What gstack adds:**
- Step 0's three premise questions (right problem? proxy? what if nothing?) are the adversarial
  lead's investigation frame
- "Elevation not rejection" posture prevents reflexive negativity
- Named cognitive frame (proxy skepticism, inversion reflex, reversibility) makes the challenge
  auditable
- Mode selection pattern may apply as a lightweight version: proceed / narrow scope / don't pursue

**Four open design questions from issue 9 — now answered:**
1. **Trigger**: Post-scope Phase 1 classification, using intent signals + issue labels (needs-prd)
2. **Lead framing**: Six demand-validation questions mapped to code sources; reporter posture, not advocate; gstack Step 0 as frame
3. **Crystallize path**: Yes — "don't pursue" should be first-class, as Decision Record with reject disposition
4. **Always-on vs conditional**: Conditional clearly superior; latency is irrelevant; needs-prd label as strong existing proxy

**Remaining design decisions for the design doc:**
- Exact confidence vocabulary and thresholds
- "Don't pursue" artifact format and issue close workflow
- Whether mode selection (proceed / narrow / don't pursue) belongs in the adversarial lead output
- Eval rubric design for honest-vs-reflexive (ground truth approach)

## Decision: Crystallize

The four open questions from issue 9 are sufficiently answered to write a design doc.
Coverage is strong across all six leads. Remaining gaps are design decisions, not research gaps.

Artifact type: **Design Doc** (`docs/designs/DESIGN-explore-adversarial-lead.md`)
This matches issue 9's explicit acceptance criterion and the tactical scope of this repo.
