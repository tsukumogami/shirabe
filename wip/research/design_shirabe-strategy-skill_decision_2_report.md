# Decision 2 Report: /strategy Phase Structure and Phase 4 Jury Prompts

## Question

Two coupled sub-questions:

1. **Phase decomposition.** What concrete work happens in Phases 0 through 5 of the `/strategy` SKILL.md, given the PRD R5 commitment to a six-phase shape (Setup, Discovery, Drafting, Structural Fill, Jury Validate, Finalize) and the constraint that structural divergence from `/vision` requires explicit rationale.

2. **Phase 4 jury prompts.** What is the actual prompt text each of the three reviewer agents (bet quality, altitude, structural format) receives at agent-invocation time, modeled on `/vision` Phase 4's three-reviewer pattern.

## Considered Options

### Sub-question 1: Phase decomposition

**Option 1A: Five-phase shape matching `/vision` exactly (0 Setup, 1 Scope, 2 Discover, 3 Draft, 4 Validate).** Maximum pattern fidelity; no divergence. Forces drafting and structural fill into a single Phase 3 the way `/vision` does. Cost: PRD R5 explicitly names six phases (0-5) and separates "Structural Fill" from "Drafting" because STRATEGY has more required sections than VISION (eight versus six) and the Building Blocks section needs a dedicated decomposition pass distinct from initial drafting.

**Option 1B: Six-phase shape (0 Setup, 1 Discover, 2 Draft, 3 Structural Fill, 4 Validate, 5 Finalize).** Matches PRD R5 verbatim. Splits drafting (initial thesis + audience-level content) from structural fill (Building Blocks decomposition + Coordination Dependencies + Falsifiability tables). Adds an explicit Finalize phase rather than folding the status transition into Phase 4 the way `/vision` does. Cost: divergence from `/vision`'s five-phase shape requires rationale.

**Option 1C: Six-phase shape with Scope merged into Setup.** Same six phases but skip the `/vision`-style Phase 1 Scope dialogue, on the theory that STRATEGY authors come in with more concrete inputs (an upstream VISION typically exists). Cost: removes a conversational entry point that catches misframed thesis bets before research; the PRD's "upstream VISION may not exist" optionality (R1 `upstream` is optional) means a scoping conversation is still load-bearing for org-scope strategies.

**Chosen: Option 1B.** PRD R5 names the six phases and the rationale for splitting Draft from Structural Fill is sound (Building Blocks is a distinct decomposition activity that benefits from a dedicated phase). The explicit Phase 5 Finalize separates "validation passed" from "status transitioned + PR opened" cleanly, which matches the PRD R5 "skill performs the Draft → Accepted status change in code after the user explicitly approves" language better than `/vision`'s in-Phase-4 finalization.

### Sub-question 2: Phase 4 jury prompts

**Option 2A: Copy `/vision` Phase 4 prompts verbatim with topic substitution.** Maximum fidelity; minimum invention. Cost: the three reviewer roles are different (bet quality, altitude, structural format) versus `/vision`'s (thesis quality, content boundary, section guidance). Verbatim copying produces wrong reviewers.

**Option 2B: Author three new reviewer prompts modeled on `/vision`'s structure (role description → input list → evaluation criteria → output format) but with novel evaluation criteria specific to STRATEGY.** Matches the structural pattern of `/vision` Phase 4 (each agent receives self-contained inputs, writes verdict to `wip/research/<prefix>_phase4_<role>.md`, returns summary to parent) while specializing the actual criteria. Cost: more authoring effort, but the PRD R6 and R6.1 already enumerate what each reviewer checks.

**Chosen: Option 2B.** The PRD R6 commits to three distinct reviewer roles whose evaluation criteria differ from `/vision`'s; copying verbatim is not viable. The `/vision` Phase 4 prompt structure (six-section template: role, inputs, criteria, output format, output file path, summary contract) transfers directly. The novelty is contained to the evaluation criteria, not the prompt skeleton.

## Decision Outcome

### Phase decomposition (Phases 0-5)

| Phase | Name | Work | Artifacts |
|-------|------|------|-----------|
| 0 | Setup | Detect entry mode (cold, handoff from `/vision`, resume on existing STRATEGY); detect repo visibility; create or verify branch `docs/strategy-<topic>`; initialize `wip/strategy_<topic>_*` paths | Branch checked out; visibility logged |
| 1 | Discover | If no `wip/strategy_<topic>_scope.md` handoff exists, run a brief conversational scope dialogue (upstream VISION reference, scope=project\|org, falsifiability sketch). Fan out parallel research agents covering: upstream-VISION fit, bet falsifiability, building-block candidates, coordination-dependency landscape, competitive considerations (private only) | `wip/strategy_<topic>_scope.md`; `wip/research/strategy_<topic>_phase1_*.md` |
| 2 | Draft | Produce initial STRATEGY draft covering Status, Strategic Context, Defensibility Thesis, Non-Goals, Downstream Artifacts (placeholders), Decisions and Trade-offs scaffold. Skip Building Blocks and Coordination Dependencies at this phase — they get filled in Phase 3 | `docs/strategies/STRATEGY-<topic>.md` (partial draft) |
| 3 | Structural Fill | Decompose Building Blocks (apply the granularity rubric from R6.1 as authoring guidance, not yet as validation); fill Coordination Dependencies with concrete upstream/downstream/cross-product references; populate Bet-Specific Falsifiability table with load-bearing claims and corrective actions; resolve Open Questions or move to Status section | `docs/strategies/STRATEGY-<topic>.md` (complete) |
| 4 | Jury Validate | Spawn three reviewer agents in parallel with `run_in_background: true` (bet quality, altitude, structural format). Each writes verdict to `wip/research/strategy_<topic>_phase4_<role>.md` and returns a one-line summary. Aggregate: all-PASS proceeds; 1-2 FAIL with minor issues fixed in place; significant FAIL surfaces via AskUserQuestion with loop-back to Phase 3 option | `wip/research/strategy_<topic>_phase4_{bet-quality,altitude,structural-format}.md` |
| 5 | Finalize | Present jury summary + STRATEGY summary to user via AskUserQuestion; on approval, transition Draft → Accepted via `skills/strategy/scripts/transition-status.sh`; clean up `wip/strategy_<topic>_*` and `wip/research/strategy_<topic>_*`; commit and open PR | STRATEGY in Accepted status; wip artifacts cleaned; PR opened |

**Divergence from `/vision` rationale.** Two divergences: (a) Phase 1 Discover combines the `/vision` Phase 1 Scope dialogue with the `/vision` Phase 2 Discover research fan-out, because the upstream-VISION-references-may-exist optionality makes a heavy standalone scoping phase rarely load-bearing; (b) Phase 5 Finalize is a separate phase rather than folded into Phase 4, because the PRD R5 sequencing (jury PASS → user approval → status transition → cleanup → PR) is non-trivial and benefits from explicit phase boundaries.

### Phase 4 reviewer prompts (full agent-invocation text)

These prompts will land verbatim in `skills/strategy/references/phases/phase-4-validate.md` as the three agent invocations.

#### Bet Quality Reviewer

```
You are reviewing a STRATEGY document for bet quality and falsifiability.
Your job is to test whether the Defensibility Thesis is a genuine
falsifiable bet and whether the Bet-Specific Falsifiability section
names concrete invalidation conditions.

## STRATEGY to Review
[Contents of docs/strategies/STRATEGY-<topic>.md]

## Scope Document
[Contents of wip/strategy_<topic>_scope.md]

## Quality Guidance
[Relevant sections from strategy-format.md, especially Defensibility
Thesis and Bet-Specific Falsifiability per-section guidance]

## Evaluate
1. Is the Defensibility Thesis a hypothesis ("We bet that...because...")
   or a problem statement ("The problem is...")? A STRATEGY thesis is a
   bet — it must name an outcome that can be observed to fail.
2. Does the thesis name explicit invalidation conditions? "If X
   happens, the bet is wrong" — not just an aspirational claim.
3. Does the Bet-Specific Falsifiability section enumerate load-bearing
   claims (the assumptions the bet rests on, where each is the kind of
   claim that could turn out false) and pair each with a corrective
   action (what we do if this claim fails)?
4. Are the load-bearing claims testable? "Users will adopt feature X"
   is testable (you can measure adoption); "Users want feature X" is
   not (preferences aren't directly measurable).
5. Is the bet specific enough that two reasonable readers would
   reach the same conclusion about whether it was invalidated? A bet
   that's so vague no observation could falsify it is not a bet.

## Output Format
Write your full review to wip/research/strategy_<topic>_phase4_bet-quality.md:

# Bet Quality Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, issue count, and summary to this conversation.
```

#### Altitude Reviewer

```
You are reviewing a STRATEGY document for altitude — whether the
document operates at medium-term defensibility (between VISION's
long-term thesis and ROADMAP's sequenced feature decomposition).
Your job is to catch content that drifts upward (re-justifying the
long-term thesis the way VISION does) or downward (decomposing into
sequenced features the way ROADMAP does), and to verify the Building
Blocks section is decomposed at the right granularity.

## STRATEGY to Review
[Contents of docs/strategies/STRATEGY-<topic>.md]

## Upstream VISION (if referenced)
[Contents of the upstream: path from frontmatter, if present]

## Altitude Guidance
STRATEGY operates at medium-term defensibility:
- VISION (upward boundary): long-term thesis, audience, value
  proposition. STRATEGY carries forward upstream VISION content; it
  does NOT re-articulate the long-term thesis.
- ROADMAP (downward boundary): sequenced features with delivery
  ordering. STRATEGY does NOT decompose into sequenced features; it
  identifies Building Blocks that downstream design docs decompose.

## Building Blocks Granularity Rubric
- **Block count.** 5-8 Building Blocks is typical. Fewer than 3
  blocks risks being under-decomposed (likely a single block
  masquerading as a strategy). More than 10 blocks risks being a
  roadmap in disguise.
- **Downstream-artifact ratio.** Each Building Block should map to
  1-2 downstream design docs minimum. Blocks with no plausible
  downstream design are framing statements rather than coherent
  units of work. Blocks that decompose into 5+ design docs are
  likely conflating multiple blocks.
- **Scope coherence.** Single-product blocks are the norm.
  Cross-product blocks (spanning 2 repos) are permitted but should
  be exceptional (under 20% of total blocks). Blocks spanning 3+
  repos signal that the strategy is two strategies sharing a
  document.

## Evaluate
1. Does the document re-articulate the long-term thesis the upstream
   VISION already establishes? If so, that content belongs upstream,
   not here.
2. Does the document sequence features or name delivery ordering?
   That belongs in a ROADMAP, not a STRATEGY.
3. Apply the granularity rubric to the Building Blocks section:
   - Count the blocks. Flag if outside 5-8 range.
   - For each block, ask: does this block have plausible decomposition
     into 1-2 downstream design docs? Flag blocks that read as framing
     statements with no decomposition path, and flag blocks that
     would clearly require 5+ design docs.
   - For each block, identify the products/repos it touches. Compute
     the cross-product percentage and flag if over 20%. Flag any
     block touching 3+ repos as a candidate for strategy
     decomposition.
4. Does the Strategic Context section give just enough framing to
   ground the bet, or does it re-litigate audience, value
   proposition, or org fit?

## Output Format
Write your full review to wip/research/strategy_<topic>_phase4_altitude.md:

# Altitude Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Granularity Rubric Results
- Block count: <N> (target 5-8)
- Blocks with implausible decomposition: <list, or "none">
- Blocks with excessive decomposition: <list, or "none">
- Cross-product percentage: <N>% (target under 20%)
- Blocks spanning 3+ repos: <list, or "none">

## Issues Found
1. <issue>: <explanation and suggested fix>

## Suggested Improvements
1. <improvement>: <rationale>

## Summary
<2-3 sentences>

Return only the verdict, granularity rubric results, issue count, and
summary to this conversation.
```

#### Structural Format Reviewer

```
You are reviewing a STRATEGY document for structural format compliance.
Your job is to verify the document matches the strategy-format.md
specification: required sections present and in order, frontmatter
fields and values valid, visibility-gated sections honoring the
visibility rule, and Downstream Artifacts entries referencing durable
paths.

## STRATEGY to Review
[Contents of docs/strategies/STRATEGY-<topic>.md]

## Repo Visibility
[Public or Private, detected from CLAUDE.md or repo path]

## Format Specification
[Relevant sections from strategy-format.md: Frontmatter Schema,
Required Sections, Optional Sections, Visibility-Gated Sections,
Validation Rules]

## Evaluate
1. **Frontmatter fields.** Required: status, bet, scope. Optional:
   upstream. Verify all required fields are present and non-empty.
2. **Status value.** Must be one of: Draft, Accepted, Active, Sunset.
   Frontmatter status must match the body Status section value.
3. **Scope value.** Must be one of: project, org.
4. **bet field.** Must be a YAML literal block scalar (uses `|`),
   paragraph-length, articulating the same hypothesis the
   Defensibility Thesis section elaborates.
5. **Required sections in order.** Verify presence and ordering:
   Status, Strategic Context, Defensibility Thesis, Building Blocks,
   Coordination Dependencies, Bet-Specific Falsifiability, Non-Goals,
   Downstream Artifacts.
6. **Visibility-gated sections.** A `Competitive Considerations`
   section is permitted only in private repos. If the repo is public
   and this section is present, flag as a violation.
7. **Open Questions section.** Permitted only when status is Draft.
   If status is Accepted, Active, or Sunset and an Open Questions
   section is present (and non-empty), flag.
8. **Downstream Artifacts durability.** Verify no entry references
   `wip/...` paths (wip is non-durable; cleanup deletes those files).
   Verify no entry references a private-repo path when this STRATEGY
   is in a public repo.
9. **Section ordering.** Sections appear in the order named in the
   format specification. Out-of-order sections are a violation even
   if all required sections are present.

## Output Format
Write your full review to wip/research/strategy_<topic>_phase4_structural-format.md:

# Structural Format Review

## Verdict: PASS | FAIL
<1 sentence explanation>

## Frontmatter Check
- status: <value> [VALID | INVALID]
- bet: [PRESENT, literal block | PRESENT, wrong shape | MISSING]
- scope: <value> [VALID | INVALID]
- upstream: [PRESENT: <path> | ABSENT (optional)]

## Section Presence and Order
<list of required sections, marked PRESENT or MISSING; flag any
out-of-order>

## Visibility Gating
- Repo visibility: <Public | Private>
- Competitive Considerations section: [ABSENT | PRESENT and ALLOWED |
  PRESENT and VIOLATES gating]

## Status-Gated Sections
- Open Questions section: [ABSENT | PRESENT and Draft status |
  PRESENT and VIOLATES status gating]

## Downstream Artifacts Durability
- wip/... references: <count, target 0>
- Private-from-public references: <count, target 0>

## Issues Found
1. <issue>: <explanation and suggested fix>

## Summary
<2-3 sentences>

Return only the verdict, the per-check pass/fail summary, and the
issue count to this conversation.
```

### Phase 4 aggregation (matches `/vision` Phase 4.3)

After all three agents complete:

| Outcome | Action |
|---------|--------|
| All 3 PASS | Proceed to Phase 5 (Finalize) |
| 1-2 FAIL with minor issues | Fix in place, show brief summary to user, proceed |
| Any FAIL with significant issues | Present findings to user via AskUserQuestion; user may approve fixes or loop back to Phase 3 |
| Reviewers disagree on the same issue | Present both perspectives via AskUserQuestion |

## Assumptions

- The `/vision` Phase 4 three-agent prompt structure (role → inputs → criteria → output format) transfers to `/strategy` without modification beyond the criteria content.
- Phase 1 combines `/vision`'s Scope and Discover into a single phase because STRATEGY scoping is lighter-weight (upstream VISION often exists; the bet altitude is already established by the artifact-type choice).
- The Building Blocks granularity rubric numeric defaults (5-8 blocks, 1-2 designs per block, under 20% cross-product) live in `strategy-format.md` per PRD R6.1, and the altitude reviewer's prompt loads them from there at agent-invocation time.
- Agents do not share memory; each prompt is fully self-contained (the prompt text above shows the full inputs each agent receives).
- The verdict format (`PASS | FAIL` plus structured issue list) is sufficient for the aggregation logic in Phase 4.3; the parent skill does not need richer verdict semantics.

## Rejected Alternatives

- **Option 1A (five-phase shape matching `/vision`).** Rejected because PRD R5 explicitly names six phases, and the Building Blocks decomposition warrants a dedicated phase distinct from initial drafting.
- **Option 1C (Scope merged into Setup).** Rejected because org-scope STRATEGY may not have an upstream VISION, so a brief scoping conversation remains load-bearing.
- **Option 2A (copy `/vision` prompts verbatim).** Rejected because PRD R6 commits to three distinct reviewer roles whose evaluation criteria do not match `/vision`'s.
- **Single-jury reviewer covering all three dimensions.** Rejected because PRD R6 explicitly commits to three parallel reviewers, and single-reviewer designs lose the independent-perspective property the jury structure exists to provide.
- **Reviewer prompts that share context across agents.** Rejected because the constraint specifies self-contained prompts with no shared memory; cross-agent context sharing would require a different orchestration pattern not supported by `run_in_background: true` parallelism.
