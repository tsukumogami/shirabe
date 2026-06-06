# Phase 2: Chain Orchestration

Phase 2 invokes the children Phase 1's chain proposal committed to. Each
invocation is gated by a parent-specific rule that determines whether
the child fires for this run; when a gate does not hold, the chain
silently skips the child and continues. The chain is sequenced; the
gating decisions are made BEFORE Phase 1's chain-proposal confirmation
prompt fires, and Phase 2 simply executes the accepted plan.

This file documents the four per-child invocation rules: `/vision`
(R4), `/comp` (R5 + R12), `/strategy` (R6, the load-bearing child), and
`/roadmap` (R7 with handoff pre-population). The chain-proposal output
that confirms the accepted plan is documented in section 1.5 of
`skills/charter/references/phases/phase-1-discovery.md`; this file
documents the per-child internal logic that the chain proposal
summarizes.

## /vision Invocation Rule (R4)

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

`/charter` invokes `/vision` when EITHER of two signals is present.
Both signals are independent — either one alone fires the invocation;
both holding simultaneously also fires it (and does so exactly once).

1. **No upstream VISION at the published path.** Phase 1 inspects
   `docs/visions/VISION-<topic>.md` for the topic slug; if no
   Accepted or Active VISION exists at that path, signal 1 is
   positive.
2. **Thesis-shift signal surfaced during Phase 1 discovery.** The
   thesis-shift signal detection itself is authored in
   `phase-1-discovery.md` section 1.4 (the literal question "Is the
   long-term thesis shifting, or is this an operational layer below
   it?" plus the three positive-signal categories). When the agent
   classifies the author's response into any of the three positive
   categories, signal 2 is positive.

The invocation passes ONLY the topic slug. `/charter` does NOT pass
an API-level "treat as revision" flag because `/vision` has no such
API surface. `/vision`'s own Resume Logic detects the existing-
VISION case (Draft / Accepted / Active) when one is present at the
published path; the parent's responsibility is only to fire the
invocation when one or both signals hold. The downstream `/vision`
run decides how to handle the existing artifact (revise, force-
abandon and rewrite, etc.) per `/vision`'s own contract.

## /comp Invocation Rule (R5 + R12)

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

`/charter` invokes `/comp` when ALL of the following hold (the
three-condition gate per the Conditional Feeder Invocation Shape
documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`):

1. Repository visibility is Private (per Phase 1's
   `## Repo Visibility:` header detection in section 1.1).
2. `skills/comp/SKILL.md` exists on disk (the feeder skill is
   shipped).

The third condition the pattern names — a parent-defined Phase 1
discovery signal — is satisfied implicitly for `/comp` v1 by the
visibility gate (a Private repo with the skill on disk is itself
the qualifying signal). The contract framing remains the three-
condition gate per the pattern reference; future revisions MAY
add an explicit discovery signal without changing the gate's
overall shape.

### Degenerate-Silence Rule

When either gate condition fails (public repo, or private repo
without the feeder skill on disk), `/charter` SHALL silently skip
the `/comp` step. Three properties bind the degenerate-silence
behavior:

- **Byte-identical chain-proposal output.** The chain-proposal
  output emitted to the author is byte-identical between public-
  repo invocations and private-repo-without-feeder invocations for
  the same topic. Neither output contains any feeder-related
  substring; the proposal lists `/strategy` (and `/vision` /
  `/roadmap` per their own gates) without mentioning the gated
  child or naming the gate.
- **No "skill not yet shipped" message.** `/charter` MUST NOT
  emit prose like "the feeder skill is not yet available" or "the
  visibility gate did not pass" or any other surfacing of the
  gate. The author hears about the feeder ONLY when all three
  conditions hold.
- **No internal-prose leakage into user-facing output.** The
  per-child invocation logic in THIS file is allowed to name the
  feeder skill and the visibility gate for documentation
  purposes; the chain-proposal output prose authored in
  `phase-1-discovery.md` section 1.5 (the user-facing surface)
  MUST omit these substrings when the gate fails.

The degenerate-silence shape ensures `/charter` v1 ships without
coupling to the feeder skill's existence on disk. When the
feeder lands, the integration is live with no `/charter`-side
change — the gate flips from skip to invoke based on file
existence, not on a code release.

### Citation

The three-condition gate is documented at the pattern level in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`
(Conditional Feeder Invocation Shape section). `/charter`'s feeder
invocation rule above is the first concrete consumer of that
contract.

## /strategy Invocation Rule (R6)

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

`/charter` ALWAYS invokes `/strategy`. It is the load-bearing
child of the chain; the chain completes either at `/strategy`'s
exit (when no `/roadmap` is warranted) or continues to `/roadmap`
on `/strategy`'s completion. There is no condition under which
`/charter` skips `/strategy`; if `/strategy` cannot run to
completion the chain enters the abandonment-forced exit path
(documented in a companion outline owning the exit-path
orchestration).

`/charter` passes `/strategy` one of three valid upstream shapes.
The three shapes are mutually exclusive — `/charter` picks the one
that matches the chain's discovery outputs.

1. **Freeform topic.** No upstream artifact path is available;
   `/charter` passes the topic slug alone, and `/strategy`'s
   Phase 1 grounds the conversation in the topic without an
   upstream document.
2. **VISION path.** A VISION exists for the topic (either ran
   earlier in this chain or already Accepted/Active at the
   published path). `/charter` passes the VISION path; `/strategy`
   reads it as its Input Mode 3 upstream.
3. **PRD path.** A PRD exists for the topic at a discoverable
   path. `/charter` passes the PRD path; `/strategy` reads it as
   the operationalizing input for the bet.

`/charter` MUST NOT pass a STRATEGY path to `/strategy`. STRATEGY
paths are `/strategy`'s lifecycle-verb mode (its Input Mode 2 —
accept / activate / sunset), which is mutually exclusive of the
create-new mode the three shapes above invoke. Passing a STRATEGY
path would route `/strategy` into a lifecycle transition rather
than into the chain-orchestration flow `/charter` is driving.

## /roadmap Invocation Rule (R7)

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

`/charter` invokes `/roadmap` when ALL of the following shape gates
hold against the just-produced STRATEGY:

1. The STRATEGY's Building Blocks section contains 3 or more blocks.
2. The STRATEGY's Coordination Dependencies section contains at
   least one non-empty entry that references another Building
   Block by name.

When either shape gate does not hold (1-2 Building Blocks, OR no
Coordination Dependencies section, OR a Coordination Dependencies
section with no qualifying entries), `/charter` SHALL skip
`/roadmap` and complete the chain at the full-run exit with the
STRATEGY as the sole `exit_artifacts` entry. Skipping `/roadmap`
when the shape gates fail is correct behavior, not a degraded
path — `/roadmap`'s value depends on the upstream STRATEGY
exhibiting feature-sequencing surface, and a STRATEGY without
that surface has no roadmap to derive.

### Handoff Pre-Population

When `/roadmap` fires, `/charter` passes BOTH of the following:

- `--upstream <strategy-path>` flag pointing at the just-produced
  STRATEGY. `/roadmap`'s Phase 3 writes the path into the
  ROADMAP's frontmatter verbatim; the contract accepts the path
  with no basename enforcement.
- A pre-populated `wip/roadmap_<topic>_scope.md` file matching the
  schema `/roadmap` Phase 1 expects. The handoff causes `/roadmap`
  to skip its Phase 1, analogous to the existing `/explore` Phase
  5 handoff pattern.

The pre-populated `wip/roadmap_<topic>_scope.md` schema has seven
named fields. `/charter` populates each based on the discovery and
STRATEGY content the chain has already produced.

- **Theme Statement** — a single-sentence framing of what the
  roadmap covers, derived from the STRATEGY's Defensibility
  Thesis.
- **Initial Scope** — the scope boundary the roadmap inherits
  from the STRATEGY, written as prose.
- **Candidate Features** — a list of features candidate for
  sequencing, derived from the STRATEGY's Building Blocks.
- **Dependency Sketch** — a sketch of feature-to-feature
  dependencies derived from the STRATEGY's Coordination
  Dependencies section.
- **Sequencing Constraints** — constraints that pin the ordering
  (technical prerequisites, organizational availability) the
  discovery surfaced.
- **Downstream Artifact State** — the state of related downstream
  artifacts (existing PRDs, designs, plans) the roadmap should
  align with.
- **Coverage Notes** — any gaps or open questions the discovery
  flagged that the roadmap author should resolve.

### Why /roadmap Is Conditional

`/roadmap` is conditional rather than always-fires because the
roadmap altitude is meaningful only when the upstream STRATEGY
has feature-sequencing surface. A STRATEGY with a single Building
Block, or no Coordination Dependencies, does not have a sequence
to ROADMAP about; the chain completes at STRATEGY with no
artificial roadmap padding. The author can run `/roadmap`
manually later if the STRATEGY's structure changes (the manual-
fallback non-interference rule documented in `phase-1-discovery.md`
section 1.2 covers this case).
