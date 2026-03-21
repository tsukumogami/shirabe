# Decision 13: Upper bound on decisions per design doc

## Decision Question

What upper bound should be set on decisions per design doc, and how should
large decision sets be split?

## Context

The framework targets 3-5 decisions per design doc. Cross-validation runs
pairwise checks across all decisions -- O(N^2) comparisons. At 20 decisions,
that's 380 pairs. The design doc itself becomes unreadable with 20+ Considered
Options sections (2000+ lines just for decisions). No guidance currently exists
for splitting or capping.

Decision 5 (cross-validation) uses single-pass with bounded restart. Decision 6
(phase restructuring) adds Phase 1 decomposition and Phase 3 cross-validation.
Neither addresses what happens when decomposition produces too many questions.

The multi-decision orchestration research confirms that the design skill
orchestrator performs decision question extraction, and that erring toward
"fewer, broader decisions" is already recommended. But there's no enforcement
mechanism.

## Analysis

### What "too many decisions" looks like in practice

A design doc with 3-5 decisions is typical for a focused component design.
At 8+ decisions, the problem is usually one of these:

1. **The scope is too broad.** The design covers multiple components that should
   each have their own design doc. Example: "Design the entire plugin system"
   spans discovery, loading, configuration, lifecycle, and API surface -- each
   a separate design.

2. **Decisions are too granular.** Sub-decisions that should be lightweight
   protocol calls are being promoted to heavyweight. Example: "Which naming
   convention for config keys?" doesn't need a 7-phase bakeoff.

3. **The problem is genuinely complex.** Some designs have many orthogonal
   axes. This is rare but real -- a security model might touch authentication,
   authorization, encryption, audit logging, and key management as truly
   independent decisions.

### Cross-validation scaling

| Decisions | Pairwise checks | Agent spawns | Practical? |
|-----------|----------------|--------------|------------|
| 3 | 6 | 3 | Yes |
| 5 | 20 | 5 | Yes |
| 8 | 56 | 8 | Marginal |
| 12 | 132 | 12 | No -- context window and cost |
| 20 | 380 | 20 | Unusable |

Not all pairs need checking -- unrelated decisions have no shared assumptions.
But the orchestrator still needs to *read all outputs* to determine which pairs
are related. At 12+ decisions, just reading all outputs consumes significant
context.

### User experience of multiple design docs

Users don't want to manage a web of sub-designs. Each design doc has setup
overhead (problem statement, decision drivers, security review). Splitting a
7-decision design into two 3-4 decision designs doubles that overhead. More
importantly, it fragments the narrative -- a reader needs two documents to
understand one system.

Hierarchical decomposition (Option C) sounds elegant but adds coordination
complexity: parent-level cross-validation across sub-designs, reference
management, and a new document type. Implementation cost is high for a problem
that rarely occurs.

### Option evaluation

#### (a) Hard cap at 8 decisions

Forces splitting when decomposition produces 9+. Each sub-design gets
independent cross-validation.

Strengths:
- Clear, enforceable rule
- Prevents the degenerate 20-decision case
- Cross-validation stays tractable (max 56 pairs)

Weaknesses:
- Arbitrary threshold -- 9 orthogonal decisions are fine, 8 coupled ones aren't
- Splitting mid-design disrupts flow; the user must re-scope and restart
- Forces users to manage multiple design docs for one conceptual design
- The number 8 is high enough that cross-validation is already expensive

#### (b) Soft guidance with agent judgment

Recommend 3-7 decisions. If decomposition produces 8+, suggest splitting but
let the user override.

Strengths:
- Flexible -- respects that some designs genuinely need 8+ decisions
- No hard failures or forced workflow interruptions
- Agent can explain *why* splitting helps rather than just refusing
- Matches the framework's general philosophy of agent-with-recommendation

Weaknesses:
- Users will always override ("just do all 8")
- No protection against the 20-decision degenerate case
- "Suggest" is weak -- agents already suggest things users ignore

#### (c) Hierarchical decomposition

Decisions sharing themes become sub-designs. Parent references sub-designs.
Cross-validation runs within each sub-design, then across sub-designs at
parent level.

Strengths:
- Scales to arbitrary complexity
- Cross-validation is localized (cheaper per sub-design)
- Models real-world architecture (systems of systems)

Weaknesses:
- Significant new document type and coordination mechanism
- Two-level cross-validation (within + across) is more complex than flat
- Implementation cost is disproportionate to how often this arises
- The parent design becomes a routing document with little substance
- Users now manage 3-4 documents instead of 1

#### (d) No limit, optimize cross-validation

Keep decisions unlimited. Make cross-validation smarter -- only check
related pairs based on shared assumptions or component overlap.

Strengths:
- No user-facing constraints
- Addresses the actual cost driver (pairwise checks)
- Doesn't require splitting or new document types

Weaknesses:
- Doesn't address the readability problem (20 Considered Options sections)
- "Smart" pair selection requires the orchestrator to understand assumption
  relationships before checking them -- still needs to read all outputs
- Agent cost for 20 parallel decision skill instances is high regardless
  of cross-validation optimization
- Optimizing cross-validation is premature -- the framework doesn't exist yet

### Synthesis

The real constraint isn't cross-validation cost -- it's document readability
and agent context. A design doc with 12+ Considered Options sections is
unreadable for humans and consumes too much context for agents. But a hard cap
creates friction for edge cases, and hierarchical decomposition is
overengineered.

Option (b) gets the agent judgment part right but lacks teeth. The fix: combine
soft guidance with a practical ceiling. The decomposition phase (Phase 1) should
target 3-5 decisions, warn at 6-7, and require explicit user confirmation at 8+
with a concrete suggestion for how to split. Above 10, the agent should refuse
and require splitting -- not because cross-validation breaks, but because the
design doc will be unreadable.

This is essentially a modified (b) with a hard ceiling at 10 and a soft
threshold at 8, plus actionable split suggestions.

## Decision Block

<!-- decision:start id="scaling-decisions-per-doc" status="confirmed" -->
### Decision: Upper bound on decisions per design doc

**Question:** What upper bound should be set on decisions per design doc, and
how should large decision sets be split?

**Evidence:** Cross-validation is O(N^2) pairwise -- 56 checks at 8 decisions,
132 at 12. Document readability degrades past 7 decisions (1400+ lines of
Considered Options alone). The multi-decision research recommends "fewer, broader
decisions" but provides no enforcement. Real designs rarely need more than 7
truly independent decisions; 8+ usually indicates scope creep or over-granular
decomposition.

**Choice:** Tiered guidance with hard ceiling at 10

Phase 1 (Decision Decomposition) applies three tiers:

| Decisions | Behavior |
|-----------|----------|
| 1-5 | Proceed normally |
| 6-7 | Agent warns that the design may benefit from splitting; proceeds if user confirms or in --auto mode |
| 8-9 | Agent presents a concrete split proposal (which decisions group into which sub-designs); proceeds only with explicit user confirmation; in --auto mode, executes the split |
| 10+ | Agent refuses and requires splitting; presents split proposal |

Split proposals group decisions by shared assumptions or component affinity.
Each resulting design doc gets independent Phase 1-3 (decomposition, execution,
cross-validation). A brief "see also" cross-reference links related designs.

**Alternatives considered:**
- Hard cap at 8: too rigid for edge cases; 8 is already conservative
- Soft guidance only: users always override; no protection against degenerate cases
- Hierarchical decomposition: high implementation cost for rare scenarios; introduces a new document type and two-level cross-validation
- No limit, optimize cross-validation: doesn't address readability; premature optimization

**Assumptions:**
- Designs rarely need more than 7 truly independent decisions (based on the current design doc having 10 decisions with several that could have been lightweight)
- Users will accept splitting at 10+ if the agent provides a concrete proposal
- --auto mode should execute splits rather than proceed with oversized designs

**Consequences:** Prevents degenerate cases while preserving flexibility for
8-9 decision designs. Adds a split-proposal step to Phase 1 that must generate
groupings. The 6-7 warning may create friction that's unnecessary for experienced
users, but it's a confirmation prompt, not a blocker.
<!-- decision:end -->
