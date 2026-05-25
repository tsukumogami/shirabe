# Lead: tactical-chain-gates

## Findings

The /charter chain's per-child gate vocabulary, codified in
`skills/charter/references/phases/phase-2-chain-orchestration.md`, names
four gate shapes: EITHER-signal (R4), three-condition gate (R5+R12, per
the pattern-level Conditional Feeder Invocation Shape), ALWAYS (R6), and
shape-dependent (R7). The pattern-level surface
(`references/parent-skill-pattern.md`, "Conditional Feeder Invocation
Shape") generalizes the three-condition gate so that future parents can
plug feeder children into it without re-deriving the contract.

The tactical chain's four children (/brief, /prd, /design, /plan) each
have entry conditions, input modes, and resume logic that constrain the
gate shape `/scope` should apply. Each child below is grounded in its
SKILL.md at `public/shirabe @ origin/main`.

### /brief — Feeder-EITHER signal (Phase-0 brief-just-landed dog-food)

**Citation:** `skills/brief/SKILL.md`, sections "Input Modes" (modes 1-4),
"Resume Logic" (8-row resume ladder including `BRIEF exists with status
"Accepted" or "Done" -> Offer to revise or start fresh`), "Critical
Requirements" (the `Artifact decision: Phase 0 decides ... whether to
produce a durable brief or pass the existing evidence forward to the
PRD` bullet), and the SKILL.md description body
("...including when an issue or conversation already states the problem,
since the skill's job is to persist that framing ... not merely to
supply framing that is missing").

**Proposed gate:** Feeder-EITHER signal. /scope invokes /brief when
EITHER of two signals holds, analogous to /charter's R4 EITHER-signal
shape but with /brief-specific semantics:

1. **No upstream BRIEF at the published path.** /scope inspects
   `docs/briefs/BRIEF-<topic>.md`; if no Draft/Accepted/Done BRIEF
   exists, signal 1 is positive.
2. **Framing-shift signal surfaced during Phase 1 discovery.** The
   topic re-frames the feature's problem/outcome pair in a way the
   existing BRIEF (if any) does not capture — analogous to /charter's
   thesis-shift signal but at the feature-framing altitude.

If a BRIEF already exists for the topic AND no framing shift is detected
AND the topic was dog-fooded "brief-just-landed" (the brief is the
upstream that triggered /scope), /scope SHALL skip /brief; the existing
artifact suffices. /brief's own resume logic then handles the
revise-vs-fresh decision if invoked.

**Why not three-condition gate:** /brief is not a feeder skill — it is
part of the tactical chain's main backbone. The visibility gate doesn't
apply (no public/private gating for /brief; it has no
visibility-gated section per the SKILL.md "Repo Visibility" section).
The skill-exists gate also doesn't apply (SE6 shipped at shirabe#95;
/scope SE7 explicitly depends on its existence). EITHER-signal is the
better fit because both signals (no artifact OR framing-shift) are
independently sufficient.

### /prd — Mandatory-with-auto-skip-when-Accepted-PRD-exists

**Citation:** `skills/prd/SKILL.md`, "Input Modes" (modes 1 & 2),
"Resume Logic" (4-row ladder; `PRD exists with status "Accepted" ->
Offer to revise or start fresh`), and the description body
("Use /prd when you know you need requirements definition"). PRD has
NO three-condition gate, NO visibility-gated skip, NO shape gate; it is
present in shirabe pre-SE4 and represents the canonical "requirements
contract" altitude.

**Proposed gate:** Mandatory-with-auto-skip. /scope ALWAYS invokes /prd
UNLESS an Accepted PRD already exists for the topic at
`docs/prds/PRD-<topic>.md`. This is asymmetric to /charter's /strategy
ALWAYS gate (R6): /strategy has no auto-skip because STRATEGY is the
load-bearing single-feature thesis; /prd is the load-bearing requirements
contract but is auto-skippable when the artifact already exists.

The "auto-skip when Accepted exists" semantics mirror /brief's resume
logic (Offer to revise or start fresh) — /scope's gate decision is
*invoke vs skip*, and if invoked, /prd's own resume logic handles
revise-vs-fresh. /scope MUST NOT silently overwrite an Accepted PRD.

**Why not pure ALWAYS:** /prd has explicit "Accepted -> revise or start
fresh" resume semantics. Forcing /prd to fire when an Accepted PRD
exists would either redundantly re-prompt (wasteful) or silently
overwrite (unsafe). Auto-skip-on-existing-Accepted is the correct
semantics. Note /prd is still effectively ALWAYS in the new-topic case
— the auto-skip only triggers when a prior artifact exists.

### /design — Shape-dependent (only when topic carries technical-decision surface)

**Citation:** `skills/design/SKILL.md`, "Input Modes" (modes 1-3,
including freeform topic and Accepted PRD path), the description
("Use when deciding how to implement something"), and the body intro
("Design documents capture HOW to build something -- the technical
approach, trade-offs considered, and architecture chosen"). Importantly,
/design's downstream-output table (after Phase 6) drives a "Plan vs
Approve only" AskUserQuestion based on a complexity assessment
(`Files to modify: 1-3 vs 4+`, `New tests: Updates only vs New test
infrastructure`, `API changes: None vs Surface changes`, `Cross-package:
No vs Yes`). The complexity criteria themselves indicate the design
altitude is NOT meaningful for trivial work.

**Proposed gate:** Shape-dependent. /scope invokes /design when the
topic exhibits technical-decision surface. The shape gates (analogous
to /charter's R7 Building-Blocks-and-Coordination-Dependencies gates,
but at the feature-implementation altitude):

1. **The just-produced PRD's Requirements section contains 2+
   requirements that imply architectural alternatives** (decision
   questions exist), OR
2. **The PRD references components/interfaces NOT yet defined in the
   repo** (new API surface, new data flow, new infrastructure), OR
3. **The PRD complexity assessment (mirrored from /design's own
   complexity table) classifies Complex** — Files to modify 4+, new
   test infrastructure, API surface changes, or cross-package work.

When NONE of the shape gates hold (a PRD with 1 requirement that adds a
recipe, fixes a typo, updates docs), /scope SHALL skip /design and
proceed directly to /plan with the PRD as upstream. /plan accepts
`docs/prds/PRD-*.md` as Input Mode 2.

**Why shape-dependent:** Tactical-chain reality is that some features
ship without a DESIGN — the lead explicitly flagged this with the
recipe-additions and doc-fixes examples. /charter's /roadmap is also
shape-dependent because the roadmap altitude is meaningful only when
the upstream STRATEGY has feature-sequencing surface; analogously,
/design's altitude is meaningful only when the upstream PRD has
architectural-decision surface. The gate shape is the same; the shape
predicate differs.

### /plan — ALWAYS-when-reached

**Citation:** `skills/plan/SKILL.md`, "Input Detection" (modes 1-3,
accepting design, PRD, roadmap, or topic), "Handoff Validation"
("Only plan documents with the right status: Accepted designs/PRDs,
Active roadmaps. ... Direct topics skip status validation."), and the
description ("Decomposes a design doc, PRD, roadmap, or directly-stated
topic into atomic, sequenced issues"). /plan is the terminal child of
the tactical chain — it materializes the implementable work.

**Proposed gate:** ALWAYS-when-reached. /scope ALWAYS invokes /plan if
the chain reaches /plan (i.e., the chain has not terminated via
abandonment-forced or re-evaluation). This is directly analogous to
/charter's /strategy R6 ALWAYS rule but at a different position in the
chain (/strategy is mid-chain load-bearing; /plan is terminal
load-bearing).

The "when-reached" qualifier matters: if /brief or /prd or /design
abandons (e.g., user bails during Phase 1 scoping), the chain enters
abandonment-forced exit and /plan does NOT fire. ALWAYS-when-reached
is structurally identical to /strategy's ALWAYS — both children are
invoked if the chain reaches them, and a chain that doesn't reach them
exits via abandonment-forced per the parent-skill-pattern's three-exit
contract.

**Why not auto-skip-on-existing:** /plan's resume logic (`if GitHub
issues exist for this design -> Resume at Phase 7 (verify/complete)`)
handles the existing-artifact case internally — /plan re-invocation on
a topic with existing issues *verifies and completes* rather than
re-authoring. /scope does not need a parent-side auto-skip because
/plan already idempotent-resumes when re-invoked.

### Comparison Table — /charter vs /scope

| Position | /charter (strategic) | Gate shape | /scope (tactical) | Gate shape |
|----------|---------------------|-----------|-------------------|-----------|
| Child 1 | /vision | EITHER-signal (R4) | /brief | EITHER-signal (no-artifact OR framing-shift) |
| Child 2 (feeder) | /comp | Three-condition gate (R5+R12) | (none) | — (no feeder in tactical chain v1) |
| Child 3 (load-bearing mid) | /strategy | ALWAYS (R6) | /prd | Mandatory-with-auto-skip-when-Accepted-exists |
| Child 4 (terminal/conditional) | /roadmap | Shape-dependent (R7) | /design | Shape-dependent (PRD has architectural-decision surface) |
| Child 5 (terminal) | — | — | /plan | ALWAYS-when-reached |

Note the structural alignment: each chain has an EITHER-signal head, a
mandatory mid-chain load-bearing child, and a shape-dependent
descend-or-skip step. The tactical chain has FIVE positions (vs
/charter's four) because /plan is positionally distinct from /design —
they sit at different altitudes (HOW vs ATOMIC-WORK-DECOMPOSITION) and
have different exit semantics.

## Implications

**Phase 2 chain-orchestration table for /scope.** The /scope SKILL.md's
phase-2-chain-orchestration.md (parallel to /charter's) needs five
sections — one per child gate — following the same prose structure
/charter uses: name the gate, name the signals, document the
degenerate behavior, cite the upstream evidence. The structural
template is reusable; only the gate predicates differ.

**No /comp-equivalent feeder in tactical chain v1.** The tactical chain
has no feeder skill — there is no competitive-framing-at-feature-level
analog. This means /scope's chain proposal output is simpler than
/charter's (no degenerate-silence rule for an absent feeder). If a
future feeder lands (e.g., /spike-feasibility for high-risk features),
the three-condition gate template is already specified at the
pattern-level (parent-skill-pattern.md "Conditional Feeder Invocation
Shape") and /scope can plug into it without re-deriving the contract.

**Resume-logic delegation.** /scope's gates make *invoke-vs-skip*
decisions only. Once /scope decides to invoke a child, the child's own
resume logic handles the revise-vs-fresh-vs-resume-from-phase-N
decision. This mirrors /charter's R4 framing: "/charter elicits the
signal ... /vision then uses its own resume logic to detect whether
an existing VISION exists at the published path and routes
accordingly. Extending the child's input surface would couple the
parent to the child's API" (parent-skill-pattern.md, "Parents do not
extend children's input surfaces"). /scope SHALL NOT pass --revise or
--from-phase flags to its children.

**Brief-just-landed dog-fooding semantics.** SE4 used the brief as a
Phase-0 input. In SE7, this becomes the canonical case where /scope is
invoked with `--upstream docs/briefs/BRIEF-<topic>.md` (analogous to
/charter's chain-proposal-with-upstream pattern). /scope's Phase 1
discovery reads the BRIEF, /scope's gate-evaluation step for /brief
detects "BRIEF exists AND no framing-shift" and skips /brief, then
proceeds to /prd. This is structurally the same as /charter's R4
behavior when a VISION already exists at the published path.

## Surprises

**Asymmetry: the tactical chain has FIVE children where /charter has
FOUR.** /design and /plan are *both* positionally significant — /design
captures HOW, /plan decomposes the HOW into atomic work. This
five-position chain has no /charter analog and the parent-skill-pattern
documentation doesn't explicitly anticipate it. The pattern's
three-exit contract still applies (full-run / re-evaluation /
abandonment-forced), but the chain-proposal output prose needs to
handle five chain entries instead of four.

**/prd is mandatory-with-auto-skip, NOT pure ALWAYS, which is a NEW
gate shape.** /charter's R6 /strategy is pure ALWAYS — there is no
auto-skip-when-Accepted-STRATEGY-exists. /prd needs auto-skip because
PRDs are revisable (the "Offer to revise or start fresh" resume case)
in a way STRATEGY apparently is not. This is a genuinely new
tactical-chain-only gate-shape that /scope's phase-2 doc will need to
define at the pattern level if the pattern wants to canonicalize it.
Alternative framing: this is just EITHER-signal where signal 2 (a
"requirements-shift" signal analogous to thesis-shift) is detected
during discovery — which would unify /prd's gate with /brief's and
/vision's.

**No analog in /scope for /charter's /comp three-condition gate.** The
tactical chain has no feeder skill in v1. This means /scope ships
without the three-condition-gate machinery. /scope's chain-proposal
output prose is correspondingly simpler — no degenerate-silence rule
to enforce. If the /scope SKILL.md is structured as a template for
future tactical chains, the empty feeder slot should still be named
(per the pattern's expectation that feeder slots exist whether
populated or not).

**No analog in /charter for /scope's /plan terminal ALWAYS.** /charter
ends at /strategy (with optional /roadmap descent); the chain has no
"decompose into atomic implementation work" terminal step. /plan is a
tactical-chain-only position.

**The /design shape-gate predicate is harder to specify mechanically
than /roadmap's.** /charter's R7 shape gates are concrete and
file-level (3+ Building Blocks, 1+ Coordination Dependencies). /design's
shape gates ("PRD has architectural-decision surface") are
agent-judgment predicates — Phase 1 discovery has to read the PRD and
classify it. The complexity assessment table from /design's SKILL.md
gives a hint at the predicate (4+ files, new test infrastructure, API
changes, cross-package), but these are *post-design* signals. /scope
would need *pre-design* heuristic signals derived from the PRD.

## Open Questions

1. **/prd gate shape — EITHER-signal or Mandatory-with-auto-skip?**
   The findings propose Mandatory-with-auto-skip, but the alternative
   framing (EITHER-signal where signal 1 is "no Accepted PRD exists"
   and signal 2 is "requirements-shift signal during Phase 1") would
   unify /prd's gate with /vision's and /brief's. Which framing does
   the user prefer? The structural difference matters for
   chain-proposal output prose and for whether the
   three-different-gate-shapes minimum stays at three (EITHER /
   ALWAYS / shape) or expands to four
   (EITHER / mandatory-with-auto-skip / ALWAYS / shape).

2. **/design pre-design shape gates — what predicates does Phase 1 use?**
   The proposed gates are agent-judgment ("PRD implies architectural
   alternatives", "PRD references new components/interfaces", "PRD
   classifies Complex"). Should /scope use a checklist of concrete
   predicates the agent walks at Phase 1, or should it delegate the
   judgment to a sub-decision skill invocation? The latter is heavier
   but more rigorous; the former is faster but more error-prone.

3. **Brief-just-landed: do we codify the auto-skip as a fourth /brief
   signal beyond no-artifact-and-framing-shift?** The lead explicitly
   names "brief-just-landed" as a dog-fooded SE4 mode. If /scope is
   invoked with `--upstream BRIEF-<topic>.md`, is that itself a third
   signal that bypasses the EITHER-signal evaluation entirely? Or does
   it just satisfy signal 1 ("BRIEF exists at published path")
   negatively (skip)? The semantics differ in whether /scope re-reads
   the BRIEF to test for framing shift even when handed an explicit
   upstream.

4. **Does /scope ship with a feeder slot named-but-empty (mirroring
   /charter's /comp position), or is the feeder slot omitted entirely
   from /scope v1?** Pattern-level future-proofing argues for the
   named-but-empty slot; YAGNI argues for omission. The choice affects
   the chain-proposal output prose and the phase-2-chain-orchestration
   doc structure.

5. **/plan terminal position — does /scope's chain-proposal output
   ever list 0-or-more terminal-children, anticipating a future
   `/track-progress` or `/verify-implementation` step after /plan?**
   /charter's chain explicitly ends at /roadmap (or /strategy when
   shape-gates fail). /scope's chain explicitly ends at /plan, but the
   tactical-chain conceptually continues into /work-on territory.
   Should /scope's chain-proposal name this boundary, or stay silent
   on what happens after /plan?

## Summary

Each tactical-chain child needs a distinct gate: /brief gets
EITHER-signal (no-artifact OR framing-shift), /prd gets
mandatory-with-auto-skip-when-Accepted-exists (or unify as EITHER-signal
per Open Question 1), /design gets shape-dependent (PRD must exhibit
architectural-decision surface), and /plan gets ALWAYS-when-reached.
The tactical chain is structurally five-position vs /charter's
four-position, with /plan a tactical-only terminal position and no
/comp-equivalent feeder slot in v1, so /scope's Phase 2 chain-orchestration
doc must extend the gate vocabulary rather than directly copy /charter's
template. The biggest open question is whether to model /prd as a new
"mandatory-with-auto-skip" gate shape (introducing a fourth pattern-level
gate type) or unify it with EITHER-signal (keeping the pattern's gate
vocabulary at three: EITHER / ALWAYS / shape) — this decision shapes
the canonical phase-2 documentation template for all future parent
skills, not just /scope.

## Visibility / Handoff Flag

Source-of-truth citations in this report draw from PUBLIC repo content
(`public/shirabe @ origin/main`). All paths and skill names cited
(`/brief`, `/prd`, `/design`, `/plan`, `/charter`, `/vision`, `/comp`,
`/strategy`, `/roadmap`, shirabe SKILL.md paths, parent-skill-pattern
references) are public-safe. This report contains NO private-only
content — when the BRIEF derived from this exploration lands in shirabe
(Public), no filtering at handoff is required.
