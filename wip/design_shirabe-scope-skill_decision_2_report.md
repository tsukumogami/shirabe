# Decision 2 Report: R6 shape-predicate evaluation mechanism

**Status**: Draft (standard tier)
**Question**: How does `/scope` Phase 1 evaluate the three R6 shape predicates (2+ architectural requirements, references new components, Complex classification) against the just-produced or existing PRD?

## Context

R6 specifies three shape predicates that gate `/design` invocation:

1. The PRD's Requirements section contains 2+ requirements that imply
   architectural alternatives (e.g., multiple components, choice
   points between approaches).
2. The PRD references components, interfaces, or data flows NOT yet
   defined in the repo (new API surface, new infrastructure).
3. The PRD's complexity assessment classifies Complex per `/design`'s
   own complexity table (Files to modify 4+, new test infrastructure,
   API surface changes, or cross-package work).

PRD Question Deferred Q2 makes the evaluation **mechanism** explicitly
design-team territory: "checklist walk during Phase 1, structured
prompt to the agent, delegation to a sub-decision skill." The PRD's
Known Limitations section reinforces the unusual texture of these
predicates: unlike `/charter`'s R7 Building-Blocks-count predicate
(concrete and file-level — count `### ` headings under a named
section), `/scope`'s R6 predicates are **agent-judgment predicates**
that read PRD prose and classify it.

The mechanism choice has three orthogonal stakes:

- **Reproducibility.** Predicates 1 and 2 are interpretive; reasonable
  agents can disagree on whether "Requirement 4 implies an
  architectural alternative." The mechanism either tolerates this
  drift (and surfaces it to the author for confirmation) or tries to
  pin it down structurally.
- **Per-invocation cost.** A sub-decision skill spin-up costs minutes
  per `/scope` run. A checklist walk during the existing Phase 1
  discovery is essentially free. A structured prompt sits between.
- **Author-visible surface.** The chain-proposal output (R7.5)
  already names which children fire and why. Whatever produces the
  R6 verdict has to feed a one-line skip reason into that prompt
  cleanly.

The /charter precedent at `skills/charter/references/phases/phase-2-chain-orchestration.md`
(R7 shape gates section) shows the comparable mechanism for the
strategic chain: ALL predicates evaluated against named, structurally-
locatable sections of the just-produced STRATEGY (Building Blocks
count, Coordination Dependencies entries), with a one-line skip
reason quoted in the chain proposal ("skip `/roadmap` because the
STRATEGY's Building Blocks section has fewer than three blocks").
The /charter mechanism is implicitly a structured checklist walk:
agent reads the named section, counts/inspects, emits a verdict.

## Decision Drivers

- **D1: Cost-per-invocation budget.** R6 fires on every `/scope`
  full-run that reaches the PRD boundary (most runs). A mechanism
  that adds minutes per run compounds.
- **D2: Reproducibility across runs.** False negatives (skip
  `/design` when it should fire) cost re-work; false positives cost
  time. PRD Known Limitations calls this out as the chief R6 risk.
- **D3: Author-visible reason quality.** The chain-proposal output
  (R7.5) must contain a one-line reason citing which predicates
  fired or failed. The mechanism produces that string as a primary
  output, not as an afterthought.
- **D4: Consistency with /charter's R7.** R7 is the closest pattern
  precedent — sibling parent skill, structurally-similar gate
  decision. Matching its mechanism reduces design surface and makes
  the pattern-doc framing of "shape-dependent gates" coherent
  across both parents.
- **D5: Predicate 3 reuses /design's existing complexity table.**
  R6.3 explicitly cites `/design`'s own complexity table (Files to
  modify 4+, new test infrastructure, API surface changes,
  cross-package). This is structural, not interpretive — it's the
  same table at `skills/design/SKILL.md:200`. The mechanism should
  surface this asymmetry rather than treating all three predicates
  identically.

## Considered Options

### Option A: Structured checklist walk during Phase 1 discovery

`/scope` Phase 1 evaluates the three predicates as a final step
before the chain-proposal output, walking each predicate against
the PRD body (just-produced or already-Accepted) and recording a
boolean verdict plus a one-sentence rationale per predicate. The
walk is documented at the phase-reference altitude
(`skills/scope/references/phases/phase-1-discovery.md` section
analogous to /charter's 1.4) with the same prose-level commitment
that /charter's R7 enforcement gives: the agent reads the PRD's
Requirements section, the Components section (or equivalent), and
the Complexity Assessment block, then emits a per-predicate
verdict.

**Concrete shape per predicate:**

- **P1 (2+ architectural requirements).** Walk the PRD's
  Requirements section. For each requirement, classify as
  "implies architectural alternative" or "does not" using two
  positive-signal categories surfaced in the walk's documentation:
  (a) the requirement names multiple candidate components or
  approaches in the prose, (b) the requirement's verbs (consider,
  evaluate, choose, design) signal a decision rather than a
  specification. Verdict: positive when ≥2 requirements match.
- **P2 (new components/interfaces).** Walk the PRD body for
  noun-phrases that name components or data flows. For each,
  cross-check against the repo's existing surface (file/directory
  presence, README components list). Verdict: positive when ≥1
  named component does not exist.
- **P3 (Complex classification).** Read the PRD's "Complexity
  Assessment" section if present (PRDs often include this from
  `/prd`'s own Phase output) or apply /design's complexity table
  directly: Files-to-modify count ≥4, new test infrastructure
  flagged, API surface changes mentioned, or cross-package work
  named. Verdict: positive on any single hit.

The walk's output is captured in the state file at
`wip/scope_<topic>_state.md` under a new optional field
`design_gate_verdicts:` (per-predicate boolean + one-line reason),
and the chain-proposal output cites the fired predicate(s) by
name: "run `/design` because the PRD's Requirements section
contains 3 architectural requirements" or "skip `/design` because
none of the three R6 predicates hold."

**Pros:**

- Matches /charter's R7 mechanism exactly (D4). Pattern doc reads
  "shape-dependent gates evaluate named PRD sections during Phase
  1 discovery" for both parents.
- Per-invocation cost is essentially zero (D1) — the walk runs
  inline in the existing Phase 1 conversation; no separate skill
  invocation, no separate agent spin-up.
- Per-predicate reason strings drop directly into the chain-
  proposal output (D3). The reason quality is bounded by the
  walk's prose-level documentation.
- Surfaces predicate 3's structural asymmetry naturally (D5) —
  the walk's P3 step reads /design's complexity table by
  reference, not by re-derivation.
- The state-file `design_gate_verdicts:` field gives downstream
  reviewers and resume operations a durable trail of why
  `/design` was skipped or fired, supporting drift detection on
  later resumes (R11 child_snapshots).

**Cons:**

- Reproducibility across agent runs (D2) is only as good as the
  documented positive-signal categories. P1 in particular ("the
  verbs imply a decision") is interpretive — two agents may
  classify the same Requirement differently. The walk's
  documentation must include worked examples to bound this drift,
  which adds prose surface to maintain.
- The walk's verdict is the agent's own; there's no second-agent
  cross-check. False negatives bite the author (no `/design` when
  they wanted one) and are only recoverable via the chain-
  proposal "Adjust" option, which requires the author to read the
  skip reason and intervene.

### Option B: Delegation to a sub-decision skill

`/scope` Phase 1 delegates R6 evaluation to a focused sub-decision
skill (either /decision invoked with the three predicates as
input, or a purpose-built /design-gate-eval feeder). The
sub-decision runs its own structured evaluation (separate context,
possibly adversarial validators per /decision's standard tier
flow), produces a verdict artifact at
`wip/scope_<topic>_design_gate.md`, and `/scope` reads the verdict
to populate the chain-proposal output.

**Pros:**

- Reproducibility (D2) improves: the sub-decision skill can run
  adversarial cross-checks per /decision's standard tier, catching
  drift one agent run would miss.
- Decoupling: the evaluation logic lives in the sub-skill, not in
  /scope's Phase 1 prose. Updates to the predicates (e.g., adding
  a fourth predicate later) edit the sub-skill, not /scope.
- Per-predicate reasoning is captured in the sub-decision's own
  artifact, which can be deeper than what fits in /scope's chain-
  proposal one-liner.

**Cons:**

- Per-invocation cost (D1) is the chief disqualifier. /decision
  standard-tier runs spawn validator agents and span multiple
  phases (context, research, validation, synthesis). This adds
  minutes to every `/scope` run that reaches the PRD boundary —
  i.e., most runs. Tactical chains already span longer than
  strategic ones (R21's worktree-staleness rationale notes this);
  doubling the per-boundary overhead compounds.
- Pattern divergence (D4) from /charter's R7. The strategic
  chain's analogous gate is evaluated inline; tactical's would
  not. The pattern doc has to explain why, and "tactical
  predicates are interpretive" is a real reason but introduces
  asymmetry the pattern v1 commits to clean.
- Chain-proposal output (D3) gets a derivative one-liner pulled
  from the sub-decision's verdict, not the verdict itself. The
  surface is two hops away from the structural input, which is
  harder to debug when an author disagrees with the verdict.
- Recursion risk: a sub-decision skill that itself wants to
  invoke /design on a complex predicate-evaluation question
  creates a contract loop. R6 wants to be a leaf evaluation, not
  a chain entry point.

## Recommended Choice

**Option A: Structured checklist walk during Phase 1 discovery.**

The mechanism walks the PRD's named sections (Requirements,
component-noun-phrases, Complexity Assessment block) against the
three predicates inline in Phase 1, emits per-predicate verdicts
with one-line reasons, and feeds those reasons directly into the
chain-proposal output (R7.5). The walk is documented at the
phase-reference altitude with worked examples bounding the
interpretive drift on P1.

This is recommended because:

1. **Pattern coherence with /charter's R7 (D4).** Both parent
   skills evaluate shape-dependent gates inline during Phase 1
   against named upstream-artifact sections. The pattern doc
   reads cleanly: "shape-dependent gates inspect named sections
   of the upstream artifact during Phase 1 and emit per-
   predicate verdicts." No special-casing for tactical.
2. **Cost discipline (D1).** Zero per-invocation overhead beyond
   the existing Phase 1 conversation. Tactical chains already pay
   R21's worktree-staleness check four times per full run;
   adding a sub-decision spawn on top is not affordable for a
   gate this load-bearing.
3. **Reason-string quality (D3).** The walk produces the chain-
   proposal one-liner as its primary output, not as a derivative
   summary. Authors see exactly which PRD section produced the
   verdict.
4. **Predicate-3 structural reuse (D5).** P3's "read /design's
   complexity table" step is naturally structural. The walk's
   prose-level documentation cites the table by file path
   (`skills/design/SKILL.md:198-203`) and the agent reads it on
   each run; no duplication.

The chief risk (D2: reproducibility on P1's interpretive
classification) is mitigated by:

- The walk's documentation including 3-4 worked examples per
  predicate, showing positive and negative cases (analogous to
  /charter's three thesis-shift categories in phase-1-discovery.md
  section 1.4).
- The chain-proposal "Adjust" option (R7.5) as the author-side
  override: when the agent's verdict surprises the author, the
  one-line skip reason in the proposal is the visible surface to
  contest, and "Adjust" re-enters Phase 1 with the author's
  redirection. This is the same contract /charter relies on for
  its R7 verdict — verdicts are agent judgment, override is
  first-class through the chain-proposal prompt.
- The state-file `design_gate_verdicts:` block giving downstream
  reviewers a durable record of which predicate fired and why,
  enabling retroactive correction if the verdict turns out wrong.

## Implementation Sketch

**Phase reference location.** A new section in
`skills/scope/references/phases/phase-1-discovery.md` (the
companion to /charter's `phase-1-discovery.md`) documents the
checklist walk. Section number analogous to /charter's 1.4 (signal
detection), positioned between the framing-shift signal section
(if /scope adopts the same numbering) and the chain-proposal
prompt section.

**Walk steps:**

1. **Locate the PRD.** Read `docs/prds/PRD-<topic>.md` (the
   just-produced PRD when `/prd` ran in the chain; the existing
   Accepted PRD when `/prd` was auto-skipped per R5).
2. **Evaluate P1 (architectural requirements).** Walk the
   Requirements section. For each `**R<N>` entry, classify per
   the two positive-signal categories above. Record the count of
   positive classifications. P1 verdict = (count ≥ 2).
3. **Evaluate P2 (new components/interfaces).** Walk the PRD body
   for noun-phrases that name components, interfaces, APIs, or
   data flows. For each, cross-check against the repo's existing
   surface. Record names + verdict per name. P2 verdict = (at
   least one name does not exist).
4. **Evaluate P3 (Complex classification).** Read the PRD's
   complexity assessment block if present. Otherwise apply
   /design's complexity table directly. P3 verdict = (any of the
   four Complex criteria fire).
5. **Aggregate.** R6 verdict = P1 OR P2 OR P3 (the predicates are
   joined by OR per R6's "any of three" phrasing). Record per-
   predicate booleans and one-line reasons.

**State file extension.** R10's schema gains an optional block:

```yaml
design_gate_verdicts:                  # set ONLY after Phase 1 walk
  p1_architectural_requirements:
    verdict: <true | false>
    reason: <one-line rationale>
  p2_new_components:
    verdict: <true | false>
    reason: <one-line rationale>
  p3_complex_classification:
    verdict: <true | false>
    reason: <one-line rationale>
  aggregate: <true | false>
```

The block is conditional (R9 conditional-fields rule): present
only after Phase 1's R6 walk completes; absent before. The block
does not gate exit validation (R9's exit field is unchanged); it
exists to support resume drift detection and reviewer audit.

**Chain-proposal integration.** The R7.5 chain-proposal output
quotes the aggregate verdict's reason. Examples:

- Fired: "run `/design` because the PRD's Requirements section
  contains 3 architectural requirements (R2/R4/R6)."
- Skipped: "skip `/design` because none of the three R6
  predicates hold (1 requirement, all components exist, Simple
  classification)."

The reason string is bounded ≤120 characters by walk-documentation
convention. Longer rationales live in the state file's
`design_gate_verdicts:` block.

**Re-evaluation on resume.** When `/scope` re-enters against an
existing Accepted PRD (R11 ladder, PRD-Accepted row), the walk
re-runs on resume because the existing PRD's content may have
been edited out-of-chain since the last `/scope` run (R13 manual-
fallback rule). The state file's `design_gate_verdicts:` block
records the most recent walk; on re-run, drift is detectable by
comparing the new verdicts against the prior block.

## Open Questions

1. **Should the walk's per-predicate reason strings be templated
   or free-form?** Templated strings (e.g., always cite the
   section name and the count) improve eval-assertion stability;
   free-form strings give the agent room to surface unusual
   findings. Recommendation: templated for the chain-proposal
   one-liner, free-form for the state-file block.
2. **Does P2's "cross-check against the repo's existing surface"
   require a file-system probe, or does it stay at agent-
   knowledge altitude?** A probe (e.g., `ls docs/` or a grep
   against the repo) makes the verdict reproducible across agent
   sessions; an agent-knowledge-only check is cheaper but drifts.
   Recommendation: agent-knowledge with optional file probe;
   defer the probe specification to the phase-reference prose.
3. **What happens when the PRD has no Requirements section
   formatted in the conventional `**R<N>` shape?** PRDs from
   `/prd` always have this shape, but `/scope` may encounter
   hand-authored PRDs. Recommendation: fall back to "walk all
   paragraphs in the Requirements section as one block;
   classify each as a single requirement-equivalent." Documented
   in the phase reference as a graceful-degradation note.
4. **Does the walk apply to the just-produced PRD AND the
   existing Accepted PRD identically?** Per R6's "just-produced
   or existing PRD" phrasing, yes — but a just-produced PRD has
   the freshest framing (the discovery just informed it), while
   an Accepted PRD may have drifted out-of-chain. Recommendation:
   walk is identical; the state file records `walk_target:
   just-produced | existing` so downstream tools can distinguish.
