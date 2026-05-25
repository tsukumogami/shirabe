<!-- decision:start id="competitive-framing-signal-detection-scope" status="assumed" -->
### Decision: Scope of competitive-framing signal detection in the parent-skill pattern

**Context**

When the `/comp` feeder skill ships, `/charter`'s recommended default for offering `/comp` during Phase 1 depends on detecting "competitive framing signals" — author utterances naming a competitor, externally-framed bets, market-share language, or related categories. The PRD specifies the broad signal categories but defers the detection mechanism to design (PRD Question 5).

The shared design doc `docs/designs/DESIGN-shirabe-progression-authoring.md` lifts ten `[pattern-level]` requirements from `/charter`'s PRD into pattern-level scope (R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18). PRD R12 (visibility detection via `## Repo Visibility:` header) is pattern-level. PRD R4 (thesis-shift signal detection) and R5 (`/comp` invocation gating) are both tagged `[/charter-specific]`. The PRD's default interpretation for competitive-framing signal detection is `/charter`-specific, but the deferred-question framing leaves room for the design to promote the mechanism to pattern-level if a generalizable shape is warranted.

The decision is reversible: promoting or demoting the contract level later is a docs update, not an irreversible architectural commitment. The public-repo constraint applies — whatever the design commits to, the wording must be safe for public visibility (no competitor names, no business strategy, no internal framing).

**Assumptions**

- `/scope` (the next parent-skill consumer of this pattern) is not specified in enough detail today to confirm whether it will have any conditional feeder-skill integration. If `/scope` later ships with a clearly analogous conditional-feeder shape, the contract surface should be revisited.
- The `/comp` skill is not yet on disk. The chosen position must not block `/comp`'s integration shape when it ships, since `/charter`'s R5 already gates the `/comp` invocation behind a skill-existence check.
- "Agent judgment with broad categories" remains the detection mechanism (consistent with PRD R4's thesis-shift signal). Whatever the design commits to must accommodate that mechanism — no keyword-list or structured-prompt mandate is implied.
- The pattern-level contract surface today already includes visibility detection (R12). Any "conditional feeder invocation" recognition can name the visibility gate as the shared component without re-specifying it.

**Chosen: Hybrid — pattern recognizes "conditional feeder invocation" as an integration shape; `/charter` provides the only v1 binding**

The shared design names "conditional feeder invocation" as a recognized integration shape that a parent skill MAY use, identifies the visibility-gate component (already pattern-level via R12) as the shared mechanism, and explicitly declines to specify signal-detection mechanics or feeder-integration body shapes at pattern level. Each parent that adopts the shape provides its own binding: the discovery-signal categories it watches for, the feeder skill it offers, the visibility gate's value (Private vs Public). `/charter`'s competitive-framing-signal → `/comp` → Private-repo binding is the only v1 instantiation; the design does not pre-commit a second.

The contract surface this commits to:

- **Recognized shape (pattern-level prose).** "A parent skill MAY offer a feeder skill conditionally during discovery when (a) a parent-defined discovery signal is detected, (b) a parent-defined feeder skill exists on disk, AND (c) a parent-defined visibility gate passes per R12." The three components are named; their values are parent-specific.
- **Shared mechanism (pattern-level by reference).** The visibility-gate component reuses R12's `## Repo Visibility:` header detection verbatim. No new pattern-level mechanism is introduced.
- **Per-parent binding (charter-specific).** `/charter`'s binding stays in `/charter`'s PRD / SKILL.md: signal = competitive-framing utterances (competitor names, externally-framed bets, market-share language); feeder = `/comp`; visibility gate = Private. Detection mechanism = agent judgment, consistent with PRD R4's precedent prose.
- **Silence on absent feeders (pattern-level by reference).** PRD R5's "degenerate-silence" requirement (no "skill not yet shipped" message, no reference to the feeder's domain when the feeder is absent or the gate fails) generalizes naturally to the shape: any parent's conditional-feeder integration MUST be silent when the feeder is absent or the gate fails, with no leakage of the feeder's domain to the author.

What the design does NOT specify at pattern level:
- The detection mechanism (keyword list vs LLM judgment vs structured prompt). Each parent picks per its binding.
- The signal categories. Each parent enumerates them in its own PRD / SKILL.md prose.
- The feeder-skill API shape. Each feeder defines its own contract; the parent calls it as a regular skill invocation.

**Rationale**

This position resolves the tension between three forces the coordinator's framing surfaced:

1. **PRD signal.** R4 and R5 are both `[/charter-specific]`. The PRD's default interpretation for competitive-framing signal detection is charter-specific. Pure pattern-level adoption (alternative a) would override that signal without a second concrete consumer to justify it.

2. **Pattern reuse cost.** The shared design's stated purpose is to lift pattern-level mechanics out of `/charter`'s scope so `/scope` and the `/work-on` migration inherit rather than re-derive. Refusing to acknowledge the integration shape at all (alternative b) would leave the next parent to re-derive the visibility-gate + feeder-existence-check + silence-on-absent composition from scratch, even though those components ARE pattern-level (R5's silence requirement, R12's visibility detection).

3. **Reversibility budget.** Standard-tier was chosen precisely because the wrong choice is reversible. The hybrid commits the minimum surface area: it names the shape and reuses pattern-level components, but does not commit to a detection mechanism or signal taxonomy. Promoting more later (if `/scope` ships a second binding) is a docs update; demoting later (if the shape proves charter-only) is also a docs update — and the demotion path is cheap because nothing has been over-specified.

The hybrid also satisfies the public-repo constraint: the recognized-shape prose names "conditional feeder invocation", "discovery signal", "feeder skill", and "visibility gate" — generic vocabulary safe for public visibility. The competitor-name / market-share examples stay in `/charter`'s scope where the visibility gate confines them to Private-repo materializations.

The Phase 4 Solution Architecture can write directly from this position: a short pattern-level section naming the shape and its three components, a reference to R12 for the visibility-gate mechanism, and a pointer to `/charter`'s PRD for the only v1 binding. No new pattern-level reference file is required; the recognized-shape prose lives in the existing `references/parent-skill-pattern.md` (or equivalent shared-reference location the design names elsewhere).

**Alternatives Considered**

- **(a) Pattern-level "feeder-skill conditional invocation" contract with full mechanics.** Generic contract: "when condition X is detected, parent SHOULD offer feeder-skill Y if Y exists and visibility-gate Z passes." `/charter` instantiates with X=competitive-framing, Y=`/comp`, Z=Private. `/scope` could instantiate with different X/Y/Z. Rejected because (1) the PRD tags R4 and R5 charter-specific by default and no second concrete consumer (`/scope`, `/work-on`) is bounded enough today to validate the contract shape; (2) lifting signal-detection mechanics to pattern level without a second binding to ratify them risks over-specifying — the next parent might need a different shape (e.g., feeder invocation gated by something other than visibility), and committing the contract surface now would force a breaking change or an awkward second contract; (3) the standard-tier reversibility budget makes "commit less now" the lower-cost default when one binding exists.

- **(b) `/charter`-specific binding only; no pattern-level acknowledgment.** Competitive-framing signal detection is a `/charter` Phase 1 feature, full stop. Other parents may add their own conditional-feeder logic but the design declines to pre-commit any contract surface. Rejected because (1) the design ALREADY lifts R12 (visibility detection) to pattern level, so the visibility-gate component of any conditional-feeder shape is already pattern-level — refusing to acknowledge the shape entirely creates a worse situation where `/scope` re-derives the composition (visibility + feeder existence + silence) without a pointer; (2) PRD R5's degenerate-silence requirement generalizes cleanly to "any parent with a conditional feeder", and burying that generalization inside `/charter`-only prose hides reuse value; (3) leaves the next parent author to discover by accident that the components compose, rather than naming the composition once in shared design.

- **(c) Hybrid — pattern recognizes the shape; `/charter` provides the only binding.** Chosen. See rationale.

**Consequences**

- **Phase 4 Solution Architecture.** Authors a short pattern-level subsection (estimate: 150-250 words) naming the recognized "conditional feeder invocation" shape, its three components (discovery signal, feeder skill, visibility gate), the pattern-level visibility-gate mechanism (reference R12), and the pattern-level degenerate-silence rule (reference PRD R5). Names `/charter` as the only v1 binding and points readers to `/charter`'s PRD for the competitive-framing-signal-detection binding details. No new shared reference file is required.

- **Phase 4 Consequences section.** The design exposes that the contract surface for conditional feeder invocation is partially specified (shape + visibility gate + silence rule are pattern-level; signal detection and feeder API are parent-specific). A future parent that needs the same shape gets the visibility-gate and silence-rule reuse for free; one that needs a different shape (e.g., non-visibility-gated feeder) is not forced into the recognized shape — they can add a separate pattern-level shape later if a second consumer ratifies it.

- **What becomes easier.** When `/comp` ships, `/charter`'s integration is local — the recognized-shape prose in the shared design names the components, but `/charter`'s PRD owns the binding mechanics. No coordination with `/scope` design is required to land the binding. The visibility-gate + silence-rule reuse is documented once, in shared design, with `/charter` as the example.

- **What becomes harder.** If `/scope` later turns out to need a conditional feeder with a DIFFERENT gate (not visibility — say, repo-state or chain-history), the recognized shape's "visibility gate" naming becomes a leaky abstraction. Mitigation: the recognized-shape prose names "parent-defined visibility gate" so the gate's identity is already a parent-specific binding; only the mechanism (R12-style header detection) is shared. The naming risk is real but bounded.

- **Reversibility.** Promoting the shape to a full pattern-level contract (alternative a) later requires (1) a second concrete binding from `/scope` or `/work-on`, (2) ratification that the two bindings share the same detection mechanism altitude. Demoting the shape (alternative b) requires deleting the recognized-shape prose and moving the visibility-gate + silence-rule pointers into `/charter`'s scope. Both paths are docs updates with no code or schema impact.

- **Eval impact (R18).** No new pattern-level eval scenarios are required by this decision. `/charter`'s evals already cover R5's degenerate silence (AC7, AC8) and R12's visibility default (AC21). The recognized-shape prose is a documentation commitment, not a behavioral commitment beyond what `/charter`'s ACs already exercise.

- **Public-visibility safety.** The recognized-shape prose stays generic ("conditional feeder invocation", "discovery signal", "visibility gate") with no competitor names, business strategy, or internal framing. The competitive-framing-signal binding's specifics stay in `/charter`'s scope where visibility gating confines them to materializations in Private repos.
<!-- decision:end -->
