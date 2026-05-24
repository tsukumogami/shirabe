# Decision 1 Report: STRATEGY Format Reference — Per-Section Content Rules

## Question

The PRD commits STRATEGY to 8 required sections. The format reference at
`skills/strategy/references/strategy-format.md` must specify per-section content
rules for the four sections without direct VISION/PRD/ROADMAP precedent:
**Strategic Context**, **Building Blocks**, **Coordination Dependencies**,
**Bet-Specific Falsifiability**, **Downstream Artifacts**. The skeleton
(Frontmatter → Required Sections → Optional Sections → Visibility-Gated
Sections → Section Matrix → Content Boundaries → Lifecycle → Validation Rules
→ Quality Guidance) mirrors `vision-format.md` and `roadmap-format.md`. The
question is: what per-section content rules go inside that skeleton?

## Considered Options (per sub-question)

### A. Strategic Context — carry-forward rules

- **A1: Minimum required sub-headings.** Spec mandates fixed sub-headings
  (e.g., "Operability primitives," "Audience," "What this strategy
  operationalizes") with 1-paragraph minimum each.
  *Pros:* deterministic; structural reviewer can check; mirrors VISION's
  Required Sections discipline. *Cons:* the upstream VISION content varies
  per project; fixed sub-headings would force re-shaping content that doesn't
  exist in some VISIONs.
- **A2: Required content properties, free sub-structure.** Spec lists the
  *properties* the section must satisfy ("a reader can understand the bet
  without reading the upstream VISION," "covers audience, value-category,
  org-fit equivalents from the upstream") but leaves sub-heading shape to
  the author.
  *Pros:* flexible across diverse upstream VISIONs; matches the
  proof-by-example doc's actual shape (four sub-headings, but chosen for
  this project); reviewer checks the property, not the structure.
  *Cons:* harder to mechanically validate.
- **A3: Freeform prose with one rule (must stand alone).** Just say
  "the section must let a reader understand the bet without the upstream
  VISION; everything else is at author discretion."
  *Pros:* simplest. *Cons:* under-specifies — authors get no guidance on
  what content to carry forward.

### B. Building Blocks — per-block sub-structure

- **B1: Strict template per block.** Each block uses a fixed template:
  `Name`, `Description`, `Dependencies`, `Owning product`, with the same
  field set in every block. Mirrors ROADMAP's per-feature format.
  *Pros:* deterministic; consumable by downstream tools; matches the
  granularity rubric (R6.1) which already counts blocks, fanout, scope.
  *Cons:* the proof-by-example uses prose paragraphs with embedded
  qualifications ("Two adjacent concerns previously bundled..."). A strict
  template would force restructuring real-shaped content.
- **B2: Required name + freeform paragraphs.** Each block has a required
  `### Block <N>: <Name>` heading and a freeform body. The body covers
  description and dependencies *somewhere*, but in prose, not pinned fields.
  *Pros:* matches the proof-by-example; lets blocks vary in shape (some
  blocks have 1 paragraph, some have 5); discoverability is preserved by
  the heading convention.
  *Cons:* dependencies aren't easily extracted; downstream tooling can't
  rely on a field.
- **B3: Hybrid — heading + required leading paragraph + free expansion.**
  Each block starts with `### Block <N>: <Name>`, a leading 1-paragraph
  description that satisfies the granularity rubric, then optional
  freeform expansion (dependencies, caveats, related work).
  *Pros:* gives the altitude reviewer a deterministic location to check
  block count / scope coherence; preserves prose expansion for nuance;
  matches the proof-by-example shape closely.
  *Cons:* slight added rigidity vs B2.

### C. Coordination Dependencies — format choice

- **C1: ASCII-art layered diagrams (proof-by-example shape).** Mirrors
  the actual STRATEGY doc — ASCII boxes inside fenced code blocks, with
  prose framing.
  *Pros:* matches what works in practice; renders identically everywhere
  (GitHub, file viewer, terminal); no Mermaid dependency.
  *Cons:* harder to author; can't be machine-parsed.
- **C2: Mermaid graph (ROADMAP precedent).** Like ROADMAP's Dependency
  Graph reserved section — a Mermaid `graph TD` block.
  *Pros:* machine-parseable; consistent with ROADMAP. *Cons:* loses the
  "layered" semantic (core vs amplifier); coordination is about *layers*,
  not just edges; the proof-by-example explicitly groups blocks into core
  and amplifier layers, which Mermaid can express only awkwardly.
- **C3: Prose-only.** Pure prose narration of dependencies.
  *Pros:* fully flexible. *Cons:* the diagram is the easiest entry point
  for readers; dropping it loses scannability.
- **C4: Hybrid — required prose framing + at least one visual aid (author
  picks ASCII or Mermaid).** Spec requires a textual narration of layered
  dependencies plus at least one visual representation; visual format is
  author's choice.
  *Pros:* flexibility without losing the visual entry point; matches the
  proof-by-example (which uses ASCII) without locking format.

### D. Bet-Specific Falsifiability — per-direction structure

- **D1: Numbered list (R1, R2... style from PRD).** Each direction is
  numbered (F1, F2, ...) with a fixed template: `Claim` / `Invalidation
  signal` / `Corrective action`.
  *Pros:* cross-referenceable from jury verdicts; mirrors PRD requirements;
  bet quality reviewer checks F1.claim is a hypothesis, F1.corrective is
  concrete.
  *Cons:* the proof-by-example uses bulleted prose ("If X, → Corrective:
  Y"), not numbered fields.
- **D2: Bullet template with embedded markers.** Bullets shaped as
  `*If <invalidation condition>*, <consequence>. → *Corrective: <action>.*`
  (the proof-by-example shape, named as a template).
  *Pros:* matches the proof-by-example exactly; bet quality reviewer
  checks each bullet has the *if/→Corrective* pair; readable as prose.
  *Cons:* not numbered, so cross-reference is by quoting the condition.
- **D3: Freeform.** No structure, just "describe falsifiability conditions
  with corrective actions."
  *Pros:* simplest. *Cons:* gives the bet quality reviewer no checkable
  shape.

### E. Downstream Artifacts — entry format

- **E1: Typed link list with descriptions.** Each entry: `**ARTIFACT-name**
  (path or cross-repo ref) — <1-2 sentence description of what it resolves>`.
  *Pros:* matches VISION's Downstream Artifacts convention; the structural
  reviewer can check entries are durable paths (per PRD R6 requirement);
  matches the proof-by-example.
  *Cons:* not numbered.
- **E2: Freeform paragraphs.** Prose narration of downstream work.
  *Pros:* flexible. *Cons:* harder to validate; loses scannability.
- **E3: Table.** Columns: `Artifact | Path | What it resolves`.
  *Pros:* most scannable. *Cons:* divergence from VISION/PRD; the
  proof-by-example doesn't use a table.

## Decision Outcome

- **A: A2 (required properties, free sub-structure).** The proof-by-example
  has four sub-headings, but those sub-headings reflect the upstream
  VISION's specific shape, not a universal template. Specifying *what
  content must carry forward* (the bet, the audience equivalent, the
  altitude framing — enough that the doc stands alone) is robust across
  upstream VISIONs of different shapes. The structural reviewer checks the
  property ("can the bet be understood without the upstream?") not the
  sub-heading count.

- **B: B3 (heading + required leading paragraph + free expansion).** The
  granularity rubric (R6.1) requires the altitude reviewer to count blocks
  and check scope coherence. Pinning the `### Block <N>: <Name>` heading
  and a leading description paragraph gives the reviewer a deterministic
  location; freeform expansion preserves the proof-by-example's prose
  shape. This is the minimum structure that makes R6.1 mechanically
  applicable.

- **C: C4 (required prose framing + author-chosen visual).** Coordination
  is fundamentally about *layers* (core vs amplifier in the
  proof-by-example), and readers need a visual entry point. Prose is
  non-negotiable because the layered semantic isn't captured by edges
  alone; the visual is author's-choice because ASCII (proof-by-example)
  and Mermaid (ROADMAP precedent) both work, and locking to one trades
  flexibility for marginal consistency. The format spec MAY recommend
  ASCII for layered semantics but MUST allow Mermaid.

- **D: D2 (bullet template with embedded markers).** The proof-by-example
  established the *if/→Corrective* shape, and it reads naturally as
  prose. The bet quality reviewer can check each bullet has the
  hypothesis-shaped *if* and a concrete *Corrective*. Numbering (D1) would
  diverge from the proof-by-example without adding much; falsifiability
  conditions aren't cross-referenced the way PRD requirements are.

- **E: E1 (typed link list with descriptions).** Matches VISION's
  Downstream Artifacts precedent and the proof-by-example exactly. The
  structural reviewer needs to validate that entries are durable paths
  (PRD R6), and a typed link list makes that check trivial. Tables (E3)
  diverge from precedent for no real gain at this scale (8-10 entries
  typical).

## Assumptions

- The proof-by-example STRATEGY (`STRATEGY-shirabe-evolution.md`) is
  representative enough that mirroring its per-section shape is sound;
  if future strategies show divergent shapes the rules can revise in the
  format reference (per the PRD constraint, no PRD amendment needed).
- Authors will be able to learn the format by diffing
  `strategy-format.md` against `vision-format.md` — so the skeleton
  ordering and headings must match VISION exactly even where STRATEGY
  has unique sections.
- The Phase 4 jury (bet quality, altitude, structural format reviewers)
  is the primary consumer of these rules; mechanically-checkable
  structure where the rubric requires it (Building Blocks count,
  Downstream Artifacts paths) matters more than uniformity for its own
  sake.

## Rejected Alternatives

- **A1 (fixed sub-headings in Strategic Context):** rejected because
  upstream VISION content varies and fixed sub-headings would force
  authors to reshape content that doesn't naturally fit.
- **A3 (freeform Strategic Context):** rejected because the
  must-stand-alone property needs accompanying content rules so authors
  know what to carry forward.
- **B1 (strict per-block template):** rejected because the proof-by-
  example uses prose-shaped blocks with embedded qualifications, and a
  strict field template would force restructuring real content.
- **B2 (heading + freeform body):** rejected because the granularity
  rubric needs a deterministic per-block leading description for
  reviewer mechanics; pure freeform is too loose.
- **C1 (ASCII-only):** rejected because locking to ASCII forecloses
  Mermaid, which has ROADMAP precedent and may be preferable in some
  layouts.
- **C2 (Mermaid-only):** rejected because Mermaid expresses edges
  cleanly but layered grouping (core vs amplifier) awkwardly, and the
  proof-by-example demonstrates ASCII as a legitimate shape.
- **C3 (prose-only):** rejected because the visual entry point is the
  fastest way for readers to grasp layered dependencies.
- **D1 (numbered Falsifiability list):** rejected because falsifiability
  conditions aren't cross-referenced the way PRD requirements are, and
  numbering diverges from the proof-by-example without adding value.
- **D3 (freeform Falsifiability):** rejected because the bet quality
  reviewer needs a checkable shape per direction.
- **E2 (freeform Downstream Artifacts):** rejected because the
  structural reviewer needs to validate durable paths per PRD R6,
  which freeform prose makes harder.
- **E3 (Downstream Artifacts table):** rejected because the
  proof-by-example uses a typed link list and divergence here doesn't
  improve discoverability at typical entry counts.
