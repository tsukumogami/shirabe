# Phase 2: Chain Orchestration

Phase 2 invokes the children Phase 1's chain proposal committed to. Each
invocation is gated by a parent-specific rule that determines whether
the child fires for this run; when a gate does not hold, the chain
silently skips the child and continues. The chain is sequenced; the
gating decisions are made BEFORE Phase 1's chain-proposal confirmation
prompt fires, and Phase 2 simply executes the accepted plan. The one
in-Phase-2 author decision is `/roadmap`'s confirmation prompt (R7),
which is a declination offer rather than a gate — `/roadmap` has no
computed gate to evaluate.

This file documents the four per-child invocation rules: `/vision`
(R4), `/comp` (R5 + R12), `/strategy` (R6, the load-bearing child), and
`/roadmap` (R7, unconditional with handoff pre-population). The
chain-proposal output
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
  substring; the proposal lists `/strategy` and `/roadmap` (and
  `/vision` per its own gate) without mentioning the gated child
  or naming the gate.
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
child of the chain; the chain continues to `/roadmap` on
`/strategy`'s completion, or completes at `/strategy`'s exit when
the author declines `/roadmap` at its confirmation prompt. There
is no condition under which `/charter` skips `/strategy`; if
`/strategy` cannot run to completion the chain enters the
abandonment-forced exit path
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

`/charter` ALWAYS invokes `/roadmap` on a full-run chain. No
property of the just-produced STRATEGY feeds the decision:
`/charter` does NOT count Building Blocks, does NOT test the
Coordination Dependencies section for qualifying entries, and does
NOT parse the document for feature-sequencing surface. The chain
that produced a STRATEGY produces a ROADMAP.

`/charter` still READS those sections — the handoff
pre-population below derives Candidate Features from Building
Blocks and the Dependency Sketch from Coordination Dependencies.
The distinction is what the reading is for: filling in the
handoff, never deciding whether the invocation happens.

### The Roadmap Confirmation Prompt

The one path that skips `/roadmap` is an explicit author
declination. Immediately before the invocation — after `/strategy`
has completed and the Draft STRATEGY is on disk, so the author can
actually read what the roadmap would sequence — `/charter` surfaces
a one-line confirmation whose default is to proceed:

> *"This strategy is about to get a ROADMAP. Proceed, or skip for
> now?"* — default **Proceed**.

`/charter` skips `/roadmap` if and only if the author declines
here. In `--auto` mode the prompt does not fire at all and
`/roadmap` always runs; the declination is an interactive choice,
never an inference.

A declination is recorded in the state file's `chain_skipped:`
list as a `{child, reason}` entry. `roadmap` stays in
`planned_chain` — the plan was to run it; the author declined —
and is absent from `chain_ran`:

```yaml
chain_skipped:
  - child: roadmap
    reason: author declined the roadmap at the confirmation prompt
```

The chain then completes at the full-run exit with the STRATEGY as
the sole `exit_artifacts` entry (the AC11a shape in
`skills/charter/references/phases/phase-finalization.md`).

The declination is how an author marks a STRATEGY **non-actionable**
— one that records a bet without heading toward execution at all.
It is not a judgment about the STRATEGY being too small or too
simple to sequence; a one-block strategy still gets a ROADMAP
unless the author says the work is not headed for execution.
Phase 1's "Adjust" option remains available for an author who
already knows at discovery time that no roadmap is wanted; the
confirmation prompt is the later, better-informed moment for the
same decision.

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

### Why /roadmap Is Unconditional

`/roadmap` fires by default because a ROADMAP is a **working
artifact**, not a durable one. Per the `## Artifact Lifecycle`
model in the repository's CLAUDE.md, ROADMAP (like PLAN on the
tactical side) exists while its job is in flight and the cascade
deletes it once its features are done. It is cheap to produce and
cheap to throw away.

An earlier revision gated the invocation on the STRATEGY's shape —
three or more Building Blocks plus a qualifying Coordination
Dependencies entry. That threshold cost more than it saved. Every
author and every agent reasoning about the chain had to hold two
counting rules in their head to predict what `/charter` would do,
and the payoff was skipping a small, disposable document. "The
chain that produces a STRATEGY produces a ROADMAP" is one sentence
and needs no arithmetic.

The author keeps the escape hatch: the confirmation prompt above
skips `/roadmap` on request, and the manual-fallback
non-interference rule documented in `phase-1-discovery.md` section
1.2 means a declined roadmap can always be produced later by
running `/roadmap` directly.
