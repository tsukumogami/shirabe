---
status: Proposed
problem: |
  /explore dispatches research agents to investigate topics and surfaces findings,
  but the framing is always "how do we move forward" — never "should we move forward."
  For directional topics (new features, zero-to-one directions), no agent challenges
  whether the topic is worth pursuing at all. Adding a conditional adversarial lead
  that investigates the null hypothesis requires deciding: how to detect directional
  topics in Phase 1, what the agent investigates and how to frame it without reflexive
  negativity, how "don't pursue" becomes a first-class crystallize outcome rather than
  a fallback, and how to measure whether the lead produces honest assessments.
---

# DESIGN: Explore Adversarial Lead

## Status

Proposed

## Context and Problem Statement

`/explore` fans out research agents to investigate a topic and surfaces findings. Its
framing is directional by default: agents investigate how to approach a topic, not
whether the topic is worth approaching. For directional topics — new features, new
product directions, zero-to-one capabilities — this leaves the premise unchhallenged.
The exploration invests research cycles in what to build before anyone has asked whether
it's worth building.

Issue #9 proposes an adversarial lead that folds demand-validation questions into Phase 2
discovery as a research task. The lead investigates the null hypothesis using sources
already available in the repository (issues, code, docs, PR history) and folds findings
into Phase 3 convergence like any other lead. "Don't pursue this" becomes a first-class
output alongside PRD, design doc, and plan.

The parallel-fanout architecture of Phase 2 means an additional agent costs no wall-clock
latency. The design question is not whether to add the lead, but how to trigger it without
disrupting the UX for diagnostic topics, how to frame the agent's investigation to avoid
reflexive negativity, and how to extend the crystallize framework to handle a "don't
pursue" conclusion distinctly from "we ran out of leads."

Prior art: gstack's `/plan-ceo-review` runs a mandatory Step 0 premise challenge (right
problem? proxy problem? what if nothing?) before any content review. It avoids reflexive
negativity by framing the challenge as "find a better version," using an explicit cognitive
frame (proxy skepticism, inversion reflex, reversibility classification), and giving the
user mode selection control. gstack has no eval rubric measuring whether the challenge is
appropriately adversarial vs reflexively negative — issue #9 requires creating one.

## Decision Drivers

- **Zero latency cost**: Phase 2 already fans out agents in parallel. The adversarial lead
  runs alongside other leads at no additional wall-clock cost. Conditional triggering must
  therefore rest entirely on signal quality, not speed.
- **No UX disruption for diagnostic topics**: diagnostic users already route to `/work-on`,
  not `/explore`. But when they do reach explore (triage entry point, ambiguous topic), the
  adversarial lead firing would produce disorienting "demand validation" findings on a bug
  report or fix request.
- **Minimum disruption to existing phases**: Phase 2, Phase 3, and SKILL.md resume logic
  should be untouched. The scope file is Phase 2's sole input — any new lead written there
  dispatches automatically with zero Phase 2 changes.
- **"Don't pursue" must be durable**: rejection decisions are more important to document than
  acceptance decisions. A wip/-only artifact gets cleaned at PR merge and is permanently
  lost. A first-class crystallize outcome must write to a permanent location.
- **Honest assessment over reflexive negativity**: the adversarial lead must report evidence,
  not advocate. A lead framed as "challenge this" produces reflexive skepticism; one framed
  as "report what you found" produces honest findings. The eval rubric must distinguish these.

## Decisions Already Made

From the exploration (these are settled — the design should treat them as constraints):

- **Conditional, not always-on**: always-on produces systematic Phase 3 noise on diagnostic
  topics, training users to ignore the adversarial section. The decision rests on signal
  quality only (latency is free). Conditional with reliable classification is clearly superior.
- **Phase 1 is the integration point**: Phase 1's lead-production step already accumulates
  all classification inputs (intent, stakes, uncertainty, issue labels). Writing the adversarial
  lead into the scope file means Phase 2 dispatches it with zero logic changes. Options that
  add classification to Phase 2 or between Phase 1 and Phase 2 require modifying phase files
  or SKILL.md resume logic unnecessarily.
- **Reporter posture, not advocate posture**: the agent prompt must frame the task as "report
  what evidence you found" not "challenge this." The verdict belongs to convergence and the
  user, not to the adversarial agent.
- **"Demand not validated" ≠ "demand validated as absent"**: thin evidence (absence of issues,
  no documented demand) is different from positive rejection evidence (closed PR saying "not
  building this," design doc that explicitly de-scoped the feature). The crystallize path
  branches on this distinction.
- **"Don't pursue" needs a permanent artifact**: the current no-artifact path was designed
  for "we ran out of leads without a conclusion," not "we investigated and concluded the idea
  isn't viable." A rejection decision must survive wip/ cleanup.
- **`needs-prd` label is a strong pre-conversation proxy**: when entering from a triaged issue,
  `needs-prd` reliably signals directional topic; `bug` reliably signals diagnostic. These are
  available before Phase 1 conversation begins.
- **gstack Step 0 frame transfers**: the three premise questions (right problem? proxy problem?
  what if nothing?) apply to exploration topics as well as plans. The cognitive frame (proxy
  skepticism, inversion reflex, reversibility) is applicable in open-source context with
  substitutions: user value replaces revenue, ecosystem fit replaces market position,
  contribution gravity replaces talent.

## Considered Options

<!-- Decision points to resolve in this design doc: -->

### Decision 1: Classification signal design

How exactly does Phase 1 classify a topic as directional? Specifically:
- Which combination of signals (issue labels, conversation cues, topic string patterns,
  absence of concrete problem statement) defines the classification?
- What is the conservative threshold — when does the adversarial lead NOT fire on
  ambiguous topics (migration, refactor, "improve X")?
- How does the classification behave in `--auto` mode?

### Decision 2: Adversarial lead prompt framing

What does the lead's investigation frame look like?
- How are the six demand-validation questions (is demand real? what do people do today?
  who asked? what behavior change counts as success? is it already built? already planned?)
  structured in the agent prompt?
- How does the gstack Step 0 cognitive frame (proxy skepticism, inversion reflex) translate
  into agent instructions without introducing bias toward "don't pursue"?
- What confidence vocabulary (high/medium/low/absent per question) maps to which downstream
  actions?

### Decision 3: "Don't pursue" crystallize outcome

How does a "don't pursue" finding produce a permanent artifact?
- Does it extend the existing crystallize framework as a new supported type, or promote
  Decision Record from deferred status with a "reject" disposition?
- What does the artifact contain? (what was investigated, specific blockers, confidence,
  preconditions for revisiting)
- Where does it live? (`docs/decisions/`?)
- What is the user action after producing it? (close issue, what comment format?)
- Should production route through `/decision` (structured ADR, higher overhead) or be
  a lightweight standalone produce path?

### Decision 4: Eval rubric for honest vs reflexive assessment

How do we measure whether the adversarial lead produces honest assessments?
- What distinguishes an appropriately adversarial finding from a reflexively negative one?
- What ground truth source can eval cases use? (known-viable topics that produced value vs
  known-dead-ends)
- How many eval cases are needed and what do their assertions look like?

## Implementation Notes

The skill changes required once design decisions are made:
- `skills/explore/references/phases/phase-1-scope.md`: add classification step to lead
  production (section 1.2 or new 1.3), defining the adversarial lead's trigger conditions
  and writing it into the scope file when conditions are met.
- `skills/explore/references/quality/crystallize-framework.md`: extend supported types or
  promote Decision Record with reject disposition; add "don't pursue" signal/anti-signal rows.
- `skills/explore/references/phases/phase-5-produce.md` (or new `phase-5-produce-dont-pursue.md`):
  produce path for "don't pursue" crystallize outcome.
- Evals at `skills/explore/evals/evals.json`: new eval cases covering directional topic
  with demand validation, diagnostic topic without adversarial lead, and "don't pursue"
  crystallize path.
