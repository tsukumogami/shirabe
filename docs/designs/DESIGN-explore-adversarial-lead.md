---
status: Proposed
problem: |
  /explore dispatches research agents to investigate topics, but its framing is always
  "how do we move forward" — never "should we move forward." For directional topics
  (new features, zero-to-one directions), no agent challenges whether the topic is
  worth pursuing. The crystallize framework has no first-class path for "don't pursue
  this" conclusions; active rejection decisions get lost in wip/ cleanup or mislabeled
  as "no artifact needed."
decision: |
  Add a conditional adversarial demand-validation lead that Phase 1 injects into the
  scope file for directional topics. The lead runs in Phase 2 alongside other agents
  with zero latency cost, using a reporter posture — per-question confidence across six
  demand-validation questions — to produce honest findings without reflexive negativity.
  Extend the crystallize framework with a Rejection Record supported type that writes
  a permanent docs/decisions/ artifact when exploration concludes a topic is not worth
  pursuing.
rationale: |
  Conditional triggering (not always-on) eliminates Phase 3 noise on diagnostic topics
  while reusing existing classification machinery. Phase 1's lead-production step is
  the minimum-disruption integration point: writing the adversarial lead into the scope
  file requires zero changes to Phase 2, Phase 3, or resume logic. The reporter frame
  prevents reflexive negativity structurally — "report what you found" gives the agent
  no reward for skeptical conclusions. A new Rejection Record crystallize type captures
  active rejection decisions in permanent artifacts rather than losing them to wip/
  cleanup or routing them through /decision's redundant investigation process.
---

# DESIGN: Explore Adversarial Lead

## Status

Proposed

## Context and Problem Statement

`/explore` fans out research agents to investigate a topic and surfaces findings through
a discover-converge loop. Its framing is directional by default: agents investigate how
to approach a topic, never whether the topic is worth approaching. For directional topics
— new features, new product directions, zero-to-one capabilities — this leaves the premise
unchallenged. The skill invests research cycles in what to build before anyone has asked
whether it's worth building.

Issue #9 proposes an adversarial lead that folds demand-validation questions into Phase 2
discovery as a research task, not as user interview questions. Six demand-validation
questions (is demand real? what do people do today instead? who specifically asked? what
behavior change counts as success? is it already built? is it already planned?) map to
code-readable sources already available in any repo: GitHub issues, existing code, docs,
and PR history.

A second gap exists downstream. When exploration concludes a topic is not worth pursuing,
the crystallize framework has no first-class path for this outcome. The current
`phase-5-produce-no-artifact.md` was designed for "we ran out of leads without a
conclusion" — not for "we investigated thoroughly and concluded this isn't viable."
Active rejection decisions are either lost to wip/ cleanup or mislabeled as "no artifact
needed," making them invisible to future contributors who would otherwise re-propose the
same idea.

Prior art: gstack's `/plan-ceo-review` runs a mandatory Step 0 premise challenge (right
problem? proxy problem? what if nothing?) before any content review. It avoids reflexive
negativity by framing the challenge as "find a better version," using explicit cognitive
frames (proxy skepticism, inversion reflex, focus as subtraction, reversibility
classification). gstack's eval only checks that the skill ran — it has no rubric measuring
whether the challenge was appropriately adversarial vs reflexively negative.

## Decision Drivers

- **Zero latency cost**: Phase 2 fans out agents in parallel. An extra agent adds no
  wall-clock time. The choice between conditional and always-on rests entirely on signal
  quality, not speed.
- **No UX disruption for diagnostic topics**: always-on would add Phase 3 noise on
  diagnostic topics, training users to ignore the adversarial section — defeating its
  purpose on directional topics.
- **Minimum disruption to existing phases**: Phase 2, Phase 3, and SKILL.md resume logic
  must remain unchanged. The scope file is Phase 2's sole input — a lead written there
  dispatches automatically.
- **Honest assessment over reflexive negativity**: the agent must report evidence, not
  advocate. Framing drives this: "report what you found" gives no reward for skeptical
  conclusions.
- **"Don't pursue" decisions must be durable**: rejection decisions are more important to
  document than acceptance decisions — future contributors should not have to re-discover
  why a topic was abandoned.

## Decisions Already Made

From the pre-design exploration (these are settled constraints):

- Conditional, not always-on — latency is irrelevant; conditional avoids Phase 3 noise
- Phase 1 lead-production step is the integration point — zero changes to Phase 2 or later
- Reporter posture (cite evidence, not inferences) prevents reflexive negativity
- `needs-prd` label is a strong pre-conversation directional proxy
- "Demand not validated" (thin evidence) ≠ "demand validated as absent" (positive rejection)
- Rejection decisions need permanent artifacts outside wip/

## Considered Options

<!-- decision:start id="classification-trigger-adversarial-lead" status="confirmed" -->
### Decision 1: Classification Trigger for the Adversarial Demand-Validation Lead

**Context**

The adversarial lead fires as one of Phase 2's parallel research agents — asking "is there
real demand for this?" on directional topics. The trigger must be conditional: always-on
produces Phase 3 noise on diagnostic topics and trains users to ignore the adversarial
section over time.

Two structural facts shape the decision. First, latency is not a differentiator: Phase 2
runs agents in parallel, so an always-on adversarial agent adds zero wall-clock cost. The
choice rests entirely on signal quality and UX. Second, `/explore` is already
directional-biased by routing — diagnostic users typically use `/work-on`, not `/explore`.
This lowers false-positive exposure compared to what the question framing implies.

The cost asymmetry is decisive: a false positive (fires on diagnostic topic) adds Phase 3
noise and degrades trust. A false negative (misses directional topic) means exploration
proceeds without premise challenge — recoverable, but costly on genuinely uncertain topics.
Given this asymmetry, the threshold is conservative: ambiguous topics (migration, refactor,
"improve X") default to not firing.

**Key assumptions:**
- `needs-prd` label is a reliable directional proxy; `bug` is a reliable diagnostic proxy
- Phase 1 conversation reliably surfaces additive vs corrective intent from the scope file's
  Core Question and Context sections
- Ambiguous topics are more common than missed directional topics → conservative defaulting
- In `--auto` mode, label signals govern when no conversation output is available

#### Chosen: Option B — Label + conversation signal (two-gate trigger)

The adversarial lead fires under two conditions, evaluated in order:

**1. Pre-conversation gate (label-based):** If entering from an issue with the `needs-prd`
label, the adversarial lead is added to the scope file before Phase 2 without waiting for
Phase 1 conversation output. If entering from an issue with the `bug` label, the lead is
explicitly skipped. `needs-design` and other labels defer to the post-conversation gate.

**2. Post-conversation gate (scope-based):** At the end of Phase 1, before writing the
scope file, the orchestrator classifies topic type from what the conversation revealed.
Three signals in combination:
- **Intent signal**: additive phrasing ("I want to add / build / support...") vs corrective
  phrasing ("X is broken / failing / incorrect...")
- **Problem statement presence**: diagnostic topics almost always surface a concrete broken
  behavior; its absence is a positive directional signal
- **Hedged intent**: user phrases goals as "maybe" or "should we..." = directional signal

The threshold is conservative: classify as directional only when **two or more signals
align**. Ambiguous topics classify as not directional unless intent is explicit and strong.

**Visibility:** The adversarial lead is named in the Phase 1 checkpoint summary when it
fires — listed as a research lead like any other, phrased as "Is there evidence of real
demand for this, and what do users do today instead?" This sets clear expectations without
adversarial framing.

**`--auto` mode:** Falls back to pre-conversation gate only. Fire if `needs-prd` present;
skip if `bug` present; default to not firing for all other cases.

#### Alternatives Considered

- **Option A — Label-only**: Rejected because free-text topic invocations (no issue) are
  a common entry point, and the label gate would never fire for them.
- **Option C — Conversation-only**: Rejected because it ignores `needs-prd`, the strongest
  pre-conversation signal, and leaves `--auto` mode behavior undefined.
- **Option D — Topic string heuristic**: Rejected as unreliable for primary classification.
  "Add a workaround for X" reads as directional but is diagnostic; "fix how we onboard new
  users" reads as diagnostic but is an improvement. Demoted to optional tiebreaker within
  the post-conversation gate.

<!-- decision:end -->

<!-- decision:start id="adversarial-lead-framing-and-dont-pursue-output" status="confirmed" -->
### Decision 2: Adversarial Lead Framing and "Don't Pursue" Output

**Context**

The adversarial lead investigates the null hypothesis using six demand-validation questions
that map to code-readable sources. The design faces two coupled choices: how to frame the
agent prompt to prevent reflexive negativity, and what a "don't pursue" conclusion produces
as a permanent artifact.

These choices are coupled because the confidence vocabulary the agent emits determines how
crystallize branches, and the branch determines what the produce phase writes.

Research established: the agent's work is structurally similar to other Phase 2 research
agents. The critical design concern is the posture the agent is instructed to take.
gstack's premise-challenge frame (three questions: right problem? proxy? what if nothing?)
operates on concrete implementation plans, not exploration topics, and its three questions
are subsumed by the six demand-validation questions already established. The current
no-artifact path conflates two distinct states that need separate handling.

**Key assumptions:**
- The adversarial lead uses the existing Phase 2 agent dispatch mechanism without structural
  changes
- `docs/decisions/` will be created as the permanent location for rejection artifacts
- The distinction between "demand not validated" and "demand validated as absent" is
  determinable from per-question confidence outputs
- The crystallize framework can accommodate a new supported type without breaking existing
  evaluation

#### Chosen: Reporter frame + Rejection Record crystallize type + standalone produce path

**Framing — Reporter frame with per-question confidence vocabulary:**

The adversarial lead uses a reporter posture: "Investigate whether evidence supports
pursuing this. Report what you found. Cite only what you found in durable artifacts."

The agent produces a finding for each of the six demand-validation questions with a
per-question confidence indicator:
- **High**: multiple independent sources confirm (distinct issue filers, maintainer labels,
  linked PRs, explicit ACs authored by maintainers)
- **Medium**: one source type confirms without corroboration
- **Low**: evidence exists but is weak (single comment, proposed solution cited as problem)
- **Absent**: searched relevant sources; found nothing

The agent also produces a calibration section explicitly distinguishing:
- **Demand not validated**: majority absent/low, no positive rejection evidence. Flag the
  gap; another round or user clarification may surface what the repo couldn't.
- **Demand validated as absent**: positive evidence that demand doesn't exist or was
  evaluated and rejected (closed PRs with explicit reasoning, design docs that de-scoped
  the feature, maintainer comments declining the request). Warrants "don't pursue"
  crystallize outcome.

This framing prevents reflexive negativity structurally: "report what you found" gives the
agent no reward for skeptical conclusions. The verdict belongs to convergence and the user.

**Output — Rejection Record supported type + standalone produce path:**

`crystallize-framework.md` receives a new supported type: **Rejection Record**.

Signals:
- Exploration reached an active rejection conclusion (not exhaustion of leads)
- Adversarial lead returned high or medium confidence evidence of absent or rejected demand
  on multiple demand-validation questions
- Specific blockers or failure modes were identified with citations
- Re-proposal risk is high (common request, non-obvious rejection reasoning)

Anti-signals:
- Leads ran out without a conclusion (no positive rejection evidence → no-artifact)
- Rejection reasoning is already documented publicly (reference existing docs)
- Low-stakes decision unlikely to resurface (close with comment)

The produce path for Rejection Record writes a permanent artifact to `docs/decisions/`
covering: what was investigated (scope and sources), what was found per demand-validation
question with confidence levels, what conclusion was reached and why, and what preconditions
would need to change to revisit. The produce phase instructs the user to close the issue
referencing the rejection record.

`phase-5-produce-no-artifact.md` wording is tightened: "Only appropriate when exploration
produced no new decisions. A rejection decision is a decision — route to Rejection Record."

#### Alternatives Considered

- **Option B — Premise-challenge frame**: Rejected because its three questions are subsumed
  by the six demand-validation questions. It produces posture (pursue/narrow/don't pursue)
  rather than per-question confidence vocabulary, and operates on implementation plans, not
  exploration topics. Adopting it would replace established vocabulary without closing a gap.
- **Option C — Hybrid**: Rejected because two separate sections produce contradictory signals
  requiring adjudication. Option A with strong reporter-posture instructions subsumes Option C.
- **Option Y — Route to /decision**: Rejected because /explore already conducted the
  investigation /decision would repeat. The skill's output format (ADR fields) is worth
  adopting; its process is not worth repeating.

<!-- decision:end -->

<!-- decision:start id="eval-rubric-honest-vs-reflexive" status="confirmed" -->
### Decision 3: Eval Rubric for Honest vs Reflexive Assessment

**Context**

Issue #9 requires eval criteria that measure whether the adversarial lead produces honest
assessments rather than reflexive negativity. gstack's plan-ceo-review has no such rubric —
its eval only checks that the skill ran and produced output. The challenge: measuring
"honest" requires ground truth, which must be encoded in fixture files.

Demand signals in a code-oriented repo are fixture-reproducible: distinct issue reporters,
maintainer-assigned labels, linked merged PRs, and explicit PR rejection comments can all
be encoded in synthetic files that the lead reads like real repo artifacts.

**Key assumptions:**
- The adversarial lead reads fixture files from `inputs/` (consistent with review-plan evals)
- Fixture files can simulate GitHub issue metadata, PR references, and code search results
- Three eval cases covers the non-overlapping behavioral scenarios
- Primary assertions target with-skill output against fixture ground truth

#### Chosen: Composite A + C + D (fixture ground truth + anti-reflexivity + confidence calibration)

Three eval cases, each using a `fixture_dir` with synthetic demand signals:

**Eval 1: strong-demand**
- Fixture: 4 distinct issue reporters, maintainer-assigned `needs-design` label, linked
  merged PR for a related feature, no prior rejection in PR history
- Ground truth: demand is real and well-evidenced
- Assertions: lead does NOT output "don't pursue"; lead cites ≥2 distinct demand signals
  from fixture; reported confidence for "is demand real?" is high

**Eval 2: absent-demand**
- Fixture: no issue files, a closed PR with explicit maintainer rejection comment ("not
  building this — adds complexity without user benefit"), no workarounds in docs
- Ground truth: demand validated as absent (positive rejection evidence)
- Assertions: lead outputs a demand-gap finding citing the PR rejection; lead distinguishes
  "demand validated as absent" from "demand not validated"; confidence for "is demand real?"
  is absent or low with specific citation

**Eval 3: diagnostic-topic**
- Fixture: topic framed as constraint analysis ("what are the performance limits of X?"),
  not a feature request; no issue files
- Ground truth: demand validation doesn't apply to this topic type
- Assertions: lead notes demand validation is not applicable; lead does NOT produce a false
  demand-gap finding; output does not force proceed/don't-pursue onto a non-demand question

#### Alternatives Considered

- **Option B — Comparative assertion only**: Rejected because specificity alone doesn't
  test correctness. A reflexively negative output can be specific and still reach the wrong
  conclusion.
- **Options C or D alone**: Each requires fixture ground truth (Option A) as infrastructure
  without which there's no anchor for correctness.

<!-- decision:end -->

## Decision Outcome

The three decisions compose cleanly. Phase 1's two-gate classification (label pre-check +
conversation post-check) adds the adversarial lead to the scope file when warranted.
Phase 2 dispatches it like any other lead — no new agent infrastructure needed. The lead
runs a reporter-frame investigation across six demand-validation questions, producing
per-question confidence that Phase 3 convergence folds in alongside other findings.

When crystallize scores the accumulated findings, a new Rejection Record type provides
a home for active rejection conclusions — distinct from both "no artifact needed" (low-signal
exploration) and "design doc needed" (viable direction with open decisions). The produce
path for Rejection Record writes to `docs/decisions/` permanently, making the rejection
reasoning discoverable to future contributors.

The three-eval rubric gives the skill measurable quality criteria for honest vs reflexive
assessment — a gap gstack didn't fill for its analogous CEO review.

## Solution Architecture

### Overview

The adversarial lead is not a new file — it is a conditionally-injected agent prompt that
Phase 1 writes into the scope file when topic classification fires. Phase 2 dispatches it
like any other lead. The changes are in: classification logic (Phase 1), the crystallize
framework (new Rejection Record type), and the produce path (new produce file for Rejection
Records).

### Components

**Modified: `skills/explore/references/phases/phase-1-scope.md`**

Gains a classification step at the end of lead production (between existing steps 1.1
and 1.2, or as a new 1.3). The step:

1. Checks issue labels (if entering from an issue): `needs-prd` → directional; `bug` → skip
2. In `--auto` mode: uses label result only; defaults to not firing with no label
3. In interactive mode: reads Phase 1 conversation output for intent signal, problem
   statement presence, and hedged intent; fires if ≥2 signals align
4. If directional: appends the adversarial lead to the scope file's `## Research Leads`
   section before step 1.2 (Persist Scope), naming it "Is there evidence of real demand
   for this, and what do users do today instead?"

The scope file gains an optional `## Topic Type: directional | diagnostic | ambiguous`
field written by this step. Phase 2 reads the leads section as normal — no Phase 2 changes.

The adversarial lead agent prompt template (embedded in phase-1-scope.md) instructs the
agent to:
- Investigate each of the six demand-validation questions (is demand real? what do people
  do today? who asked? what behavior change counts as success? already built? already
  planned?) by reading issues, code, docs, and PR history
- Report a per-question confidence level (high / medium / low / absent) with specific
  citations
- Produce a calibration section distinguishing "demand not validated" from "demand
  validated as absent"
- Use reporter posture: "Report what you found. Cite only what you found in durable
  artifacts. The verdict belongs to convergence and the user."

**Modified: `skills/explore/references/quality/crystallize-framework.md`**

The Supported Types table gains a fifth entry: **Rejection Record**.

Signals: active rejection conclusion; adversarial lead found high/medium absent demand on
multiple questions; specific citable blockers; re-proposal risk is high; investigation was
multi-round or adversarial.

Anti-signals: leads ran out without conclusion; rejection reasoning already documented;
low-stakes rejection unlikely to resurface.

Routes to the new `phase-5-produce-rejection-record.md`.

**Modified: `skills/explore/references/phases/phase-5-produce-no-artifact.md`**

The "only appropriate when" wording gains an explicit exclusion: "A rejection decision is a
decision — if exploration reached an active rejection conclusion, route to Rejection Record
instead of No Artifact."

**New: `skills/explore/references/phases/phase-5-produce-rejection-record.md`**

Produce path for Rejection Record crystallize outcome. Writes
`docs/decisions/REJECTED-<topic>.md` (creates `docs/decisions/` if needed) with:
- What was investigated (scope and sources examined)
- Per demand-validation question: what was found and confidence level
- Conclusion: what specific evidence led to "don't pursue"
- Preconditions for revisiting: what would need to change to reconsider

After writing: instructs the user to close the source issue with a comment referencing
the rejection record. Offers to route to `/decision` for a formal ADR if re-proposal
risk is high.

**New: `skills/explore/evals/evals.json` (and fixture files)**

Three eval cases with `fixture_dir` entries (see Decision 3 for case definitions).

### Key Interfaces

**Scope file `## Topic Type:` field**
Written by Phase 1 classification step. Values: `directional | diagnostic | ambiguous`.
Read by Phase 1 itself before writing the leads section (determines whether to inject
the adversarial lead). Not read by Phase 2 directly — Phase 2 just dispatches whatever
leads are in the scope file.

**Adversarial lead output format**
Research file at `wip/research/explore_<topic>_r<N>_lead-adversarial-demand.md`.
Sections: findings per question (with confidence), calibration section, summary.
Standard Phase 2 lead format, with per-question confidence as the additional requirement.

**Rejection Record artifact**
Path: `docs/decisions/REJECTED-<topic>.md`
Fields: Investigated Scope, Demand Signal Analysis (per question with confidence),
Conclusion, Preconditions for Revisiting.

### Data Flow

```
Phase 0/1: Classification
  Issue label (needs-prd/bug) OR Phase 1 conversation signals
    → Topic Type: directional?
      Yes → adversarial lead added to scope file ## Research Leads
      No  → scope file written without adversarial lead

Phase 2: Dispatch
  All leads in scope file dispatched in parallel
  Adversarial lead → wip/research/explore_<topic>_r1_lead-adversarial-demand.md
    reads: inputs/ (if fixtures present) OR actual repo issues/code/docs/PRs
    produces: per-question confidence + calibration section

Phase 3: Convergence
  Adversarial findings folded in alongside other leads
  User sees demand evidence (or absence) among other findings

Phase 4: Crystallize
  crystallize-framework.md scores Rejection Record type
  "demand validated as absent" findings → Rejection Record scores high
  "demand not validated" findings → another round or no artifact

Phase 5: Produce (if Rejection Record chosen)
  Writes docs/decisions/REJECTED-<topic>.md
  Instructs user to close source issue referencing the record
```

## Implementation Approach

### Phase 1: Classification and adversarial lead injection

Modify `skills/explore/references/phases/phase-1-scope.md` to add:
- Topic Type classification logic at end of lead production (step 1.1 extension or new 1.3)
- `## Topic Type:` field written to scope file
- Adversarial lead agent prompt template (inline)
- Conditional injection into `## Research Leads` before step 1.2 persist

Deliverables:
- Updated `skills/explore/references/phases/phase-1-scope.md`

### Phase 2: Crystallize extension and Rejection Record produce path

Modify and create produce-side files:
- `skills/explore/references/quality/crystallize-framework.md`: add Rejection Record type
- `skills/explore/references/phases/phase-5-produce-no-artifact.md`: tighten wording
- New `skills/explore/references/phases/phase-5-produce-rejection-record.md`

Deliverables:
- Updated crystallize-framework.md
- Updated phase-5-produce-no-artifact.md
- New phase-5-produce-rejection-record.md

### Phase 3: Evals

Create `skills/explore/evals/evals.json` with 3 eval cases and fixture directories.
Fixture files must encode demand signals in a format the adversarial lead will read as
real repo artifacts (issue files, PR rejection notes, code search stubs).

Deliverables:
- `skills/explore/evals/evals.json`
- `skills/explore/evals/fixtures/strong-demand/` (fixture files)
- `skills/explore/evals/fixtures/absent-demand/` (fixture files)
- `skills/explore/evals/fixtures/diagnostic-topic/` (fixture files)

## Security Considerations

_To be completed by security review agent._

## Consequences

### Positive

- **Directional premise gets challenged before resources are committed**: the adversarial
  lead runs in Phase 2 at zero latency cost, asking "is there real demand?" before
  crystallize recommends a PRD or design doc.
- **Rejection decisions survive wip/ cleanup**: `docs/decisions/REJECTED-<topic>.md`
  persists after the branch closes, making rejection reasoning discoverable to future
  contributors.
- **No regression on diagnostic topics**: the two-gate trigger explicitly skips the
  adversarial lead for `bug`-labeled issues and for topics without directional signals;
  diagnostic explorations are unchanged.
- **Zero Phase 2/3/resume logic changes**: the adversarial lead enters the scope file
  like any other lead; Phase 2 dispatches it automatically with no branching logic.
- **Measurable eval rubric fills gap gstack left open**: three fixture-backed eval cases
  with confidence-calibration assertions provide the first verifiable quality signal for
  honest-vs-reflexive demand assessment.

### Negative

- **Phase 1 gains classification judgment**: for free-text topics without issue labels,
  Phase 1 must classify based on conversation output. This judgment is imperfect;
  ambiguous topics ("migrate X to Y") will sometimes fire incorrectly or miss.
- **Crystallize framework has five types instead of four**: the evaluation procedure adds
  complexity. Rejection Record anti-signals must be precise enough to not score high on
  "ran out of leads" explorations.
- **`docs/decisions/` is a new directory**: the produce path must create it if it doesn't
  exist; tooling that scans docs/ may need to be updated.
- **Diagnostic-topic eval requires the adversarial lead to self-identify as inapplicable**:
  this is a subtle behavior to test reliably.

### Mitigations

- **Classification imprecision**: the conservative two-signal threshold reduces false
  positives. False negatives (missed directional topics) are recoverable — the premise
  challenge surfaces later in design review. The eval corpus provides ongoing calibration.
- **Rejection Record anti-signals**: the key anti-signal ("leads ran out without
  conclusion") is distinguishable from the key signal ("active rejection conclusion
  with citations") by the presence of positive rejection evidence in the adversarial
  lead's calibration section.
- **Diagnostic eval robustness**: the agent prompt explicitly instructs the lead to
  report "demand validation does not apply to this topic type" when the topic is not a
  demand question, giving the eval assertion a specific string to check.
