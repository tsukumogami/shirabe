# Architecture Review: DESIGN-plan-review.md

Phase 6 architecture review of the `/review-plan` skill design.

---

## 1. Is the architecture clear enough to implement?

**Overall: Yes, with one gap.**

The component tree, file layout, key interfaces, and data flow are specified at a
level where a developer could start implementing. The `review_result` YAML schema is
fully specified with field names, types, and semantics. The sub-operation invocation
contract is defined (args: `plan_topic`, `round`, `mode`). The standalone interface
is defined (`--adversarial` flag). Each phase file has a named responsibility.

The one implementable gap is **hint-threading in `/plan` Phase 6**. The design says
"`/plan` must implement a hint-threading step" and calls it "a new interface
requirement," but the existing `phase-6-review.md` file is not updated in the design
beyond the stub reference in the component tree. A developer implementing Phase 4 of
the implementation plan (Verdict synthesis and loop-back) would need to write
`phase-6-loop-back.md` for `/review-plan` *and* update `/plan`'s `phase-6-review.md`
to invoke the sub-operation, read the verdict, execute the read-then-delete sequence,
and inject hints into Phase 4 prompts. The design states this is required but doesn't
describe what the updated `phase-6-review.md` should contain step by step — only that
it must exist.

**Secondary gap**: The design says "the `round` field is passed at invocation by
`/plan`," but doesn't specify where `/plan` tracks the current round between
invocations. The loop-back deletes the review artifact, which would carry the round
value. A developer needs to decide whether the round counter lives in the
decomposition artifact, the analysis artifact, or is re-derived from some other
signal. The round counter exists solely to guard against infinite loops; without
specifying its persistence location, the "configurable max-rounds guard" in the
Mitigations section is unimplementable.

---

## 2. Missing components or interfaces

**a. Round counter persistence.** Described in Decision 1 and Mitigations but not
assigned a location. The review artifact is deleted on loop-back, taking the round
value with it. `/plan` must write the round counter somewhere before deleting the
artifact — either in the decomposition artifact's YAML frontmatter or in a dedicated
field in the analysis artifact. Neither is specified.

**b. `/plan` Phase 6 updated step specification.** The component tree names
`references/phases/phase-6-review.md` as a required change, but the design gives no
step-level spec for the updated file. The current `phase-6-review.md` (passive check,
no sub-operation invocation, no loop-back logic) would need a full rewrite. This is
the most implementation-critical missing specification.

**c. Correction hint injection interface.** The design says `/plan` injects correction
hints "into Phase 4 regeneration agent prompts." Phase 4 (`phase-4-agent-generation.md`)
uses a template substitution system with named placeholders (`{{DESIGN_DOC_CONTENT}}`,
`{{ISSUE_ID}}`, etc.). A correction hint for a specific issue ID needs a placeholder
or some injection mechanism. The design doesn't name a placeholder or describe how
the hint reaches the per-issue agent context in step 4.4.

**d. Category E conditional logic.** The design says Category E runs when input type
is `design` or `prd` and skips for `roadmap`. Phase 0 must detect input type and
configure the category set. This is implied but not made explicit in the phase-0
setup spec — "detect input_type" is listed as a Phase 0 responsibility, but the
branching table for which categories to run (and whether to skip B/C/D fast for
roadmap) isn't formalized.

**e. Standalone invocation without a pre-existing review artifact.** The data flow
section covers fast-path only. For standalone full adversarial mode, the design says
"same phases but each category spawns multiple validator agents." It doesn't describe
how Phase 0 detects mode (flag vs. sub-operation call), how the standalone caller
provides `plan_topic`, or what happens to the verdict artifact after standalone
review — does it persist? Does it gate a subsequent `/plan` Phase 7 if the user runs
`/plan` next? The design implies it persists (it's a "prerequisite marker"), but this
creates a question: if a standalone review produces `loop-back`, does `/plan` pick
that up on next run or re-run review from scratch?

---

## 3. Are the implementation phases correctly sequenced?

**Yes, with one dependency concern.**

The five implementation phases have the right dependencies:

- Phase 1 (scaffold + schema) must precede all others: file structure and the
  `review-result-schema.md` / `ac-discriminability-taxonomy.md` templates are
  prerequisites for writing any phase file.
- Phase 2 (categories A, B, D) is correctly sequenced before Phase 3 (category C),
  since C is the most complex and benefits from the surrounding framework being stable.
- Phase 3 (category C) must precede Phase 4 (verdict synthesis), since verdict
  synthesis aggregates all category findings including C.
- Phase 4 (verdict + loop-back) must precede Phase 5 (adversarial mode), since
  adversarial mode extends fast-path without changing its contract.

The one concern is that Phase 4 includes updating `/plan`'s `phase-6-review.md`, but
this update depends on knowing the exact sub-operation invocation contract, which is
defined in Phase 1. That dependency is satisfied. However, the hint-threading step
also depends on Phase 3's correction hint schema being finalized — if Category C
findings change shape during Phase 3, the hint-threading code written in Phase 4
would need a revision. A developer should treat Phase 4's `/plan` update as
dependent on Phase 3 being complete, not just Phase 1.

**Testability sequencing**: The design doesn't describe how each implementation phase
is tested before the next begins. Categories A, B, D can be independently tested with
a plan artifact and design doc; C requires the taxonomy file from Phase 1. But there's
no description of what a passing test looks like for each implementation phase. For a
complex skill, this matters: Phase 4 (loop-back) is hard to test without a working
Phase 5 (verdict synthesis telling it to loop). The design implicitly assumes
integration testing, but doesn't say so.

---

## 4. Simpler alternatives that were overlooked

**a. Inline review in Phase 6 (no new skill file).** The design's stated motivation
for a separate skill is standalone callability and the `/decision` analogy. But all
four review categories read artifacts that are already in scope during Phase 6. A
single well-structured Phase 6 prompt with the four categories as sections and a
structured output block would achieve fast-path without any new skill infrastructure.
The cost is losing standalone callability, which the design treats as a requirement.
If standalone review is actually used infrequently, this would be a significant
simplification. The design doesn't evaluate this option — it's rejected implicitly
by the standalone requirement, but the requirement's source (user need vs. design
symmetry with `/decision`) isn't stated.

**b. Keep the review artifact on loop-back, add a `reviewed_at` timestamp field.**
Decision 1 rejects this because it would require making the resume logic content-aware.
But the resume logic already checks *which* artifact exists, which is a content signal.
Adding one content check (`if review_result.verdict == "loop-back" → re-run review`)
is a small change. The alternative is rejected without quantifying the scope of the
resume logic change. On inspection, the change would be one conditional in
`phase-6-review.md`'s resume check — small but acknowledged as "modifying rather
than reusing." The decision is defensible; the evaluation is slightly thin.

**c. LLM-only AC discriminability with taxonomy in the system prompt.** The two-pass
approach (pattern heuristics first, then LLM adversarial reasoning for remainder) adds
implementation complexity: two passes, different logic paths, pattern-specific flags.
Decision 3 argues this is needed because pattern-only misses patterns 2/4/5/6 and
LLM-only produces inconsistent findings. The taxonomy-anchored LLM pass already covers
all seven patterns. The pattern pass provides speed (confirmed matches resolve without
an LLM call) and explainability (matched pattern is unambiguous). In fast-path mode
with a single agent, the speed benefit is small — the agent will read all ACs once
regardless. The main benefit is false-positive reduction for pattern 5. This is
a reasonable trade-off, but the design doesn't quantify the latency savings or
false-positive reduction rates, so the "combination is better" claim rests on
qualitative reasoning.

---

## 5. Cross-cutting observations

**The design is internally consistent.** The four decisions compose without conflict,
and the design explicitly calls out the one cross-decision interaction that requires
sequencing (read-then-delete on loop-back). The rationale sections follow "constraint
→ ruling-out alternatives → chosen approach," which makes the logic followable.

**The security section is well-placed.** Prompt injection via plan artifact content is
a real risk given that issue bodies are user-generated content read into agent prompts.
The mitigation (explicit data framing in phase files) is appropriate and
implementation-time. The correction-hint injection attack chain is identified and
mitigated.

**Scope of `/plan` changes is understated.** The design lists only two `/plan` files
as requiring changes, but the actual change to `phase-6-review.md` is substantial: it
replaces a passive completion check with a sub-operation invocation, result reading,
conditional branching, artifact deletion, and hint-threading. Calling this "no changes
needed" for Phase 7 while correctly noting Phase 6 needs an update is accurate, but
the *magnitude* of the Phase 6 change is not surfaced. Implementation teams may
underestimate the work.

---

## Summary

The architecture is implementable from the design document for the `/review-plan` skill
itself. The critical implementation gaps are in the `/plan` side: the updated
`phase-6-review.md` specification is absent, the round counter persistence location is
unspecified, and the correction hint injection mechanism into Phase 4 agent prompts
needs a named placeholder or injection protocol. These gaps would block a developer
implementing Phase 4 of the implementation plan without additional design work.
