# Phase 2: Chain Orchestration

Phase 2 invokes the children Phase 1's chain proposal committed to. Each
invocation is gated by a parent-specific rule that determines whether
the child fires for this run; when a gate does not hold, the chain
skips the child, says so, and continues. The chain is sequenced; the
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

The `/vision` gate is the Mandatory-with-auto-skip shape from the
Gate Vocabulary in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`, with
the thesis-shift signal as its override. The settled statuses
`/charter` skips against are Accepted and Active.

`/charter` invokes `/vision` unless an Accepted or Active VISION
already exists at the published path. Phase 1 inspects
`docs/visions/VISION-<topic>.md` for the topic slug; if nothing
Accepted or Active is there, `/vision` runs. A cold start with no
supplied upstream is therefore always a `/vision` run — there is no
upstream thesis to build on, and nothing the author says about the
thesis changes that.

**A supplied upstream is an upstream thesis.** When the state file
carries `consumed_upstream:` — the author invoked
`/charter <topic> --upstream <vision-path>` and the value passed
Phase 0 step 0.4 — the auto-skip half of the gate fires on that
value rather than on the canonical path, and `/charter` records
`/vision` in `chain_skipped` with reason
`upstream-supplied-by-author`; the supplied path itself goes in the
entry's optional `detail:`, which nothing reads. The thesis-shift override still applies: a positive
signal fires `/vision` anyway, and a chain that authors its own
VISION passes that one to `/strategy` instead.

Skipping is the point of the flag rather than an optimization of
it. The auto-skip condition has always been "an upstream thesis
already exists"; the canonical-path check was the only way to
observe one before the flag existed. Running `/vision` against a
chain whose author just pointed at the thesis would write a second
copy of it under this chain's slug, which is the duplication the
flag exists to avoid.

When an Accepted or Active VISION *does* exist at that path, the
thesis-shift question decides whether `/vision` runs anyway. A
positive signal overrides the auto-skip and fires the invocation;
no signal leaves the existing VISION in place and the chain skips
the child, recording it in `chain_skipped`. The question is an
override on an existing VISION, not a second route into the child,
and this is the only case where the answer changes what the chain
does.

An earlier revision of the pattern classified this gate as
EITHER-signal, reading the thesis-shift question and the
absence-of-a-VISION condition as two independent routes into the
child. They never were, and the shape was retired 2026-08-08 (see
the Gate Vocabulary's dated note). The gate fires on exactly the
same runs under either name.

The question is still surfaced on every run: `phase-1-discovery.md`
section 1.4 requires it verbatim ("Is the long-term thesis shifting,
or is this an operational layer below it?") and owns the detection
machinery — the literal wording and the three positive-signal
categories the response is classified into. This rule only consumes
that classification, and on a cold start the classification cannot
change the outcome.

The invocation passes ONLY the topic slug. `/charter` does NOT pass
an API-level "treat as revision" flag because `/vision` has no such
API surface. `/vision`'s own Resume Logic detects the existing-
VISION case (Draft / Accepted / Active) when one is present at the
published path; the parent's responsibility is only to fire the
invocation when this rule says it fires. The downstream `/vision`
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

### Stated-Skip Rule

When either gate condition fails, `/charter` SHALL state the skip
in its conversational output and continue the chain. The statement
names the child and the reason:

- **Public repo.** *"Skipping competitive analysis — `/comp`
  writes a private-only artifact and this repo is public. The
  chain continues without it."*
- **Feeder skill not on disk.** *"Skipping competitive analysis —
  the `/comp` skill isn't installed in this workspace. The chain
  continues without it."*

The reason is stated, not implied. An author who expected a
competitive step and gets none deserves to know a rule dropped it
rather than being left to wonder whether `/charter` considered the
question at all.

#### The Statement Is Conversational, Never Recorded

The skip statement lives in the conversation and nowhere else.
Nothing that gets committed carries it:

- `wip/charter_<topic>_state.md` — no `chain_skipped:` entry for
  `comp`, and `comp` is absent from `planned_chain`. The state
  file is durably public from feature-branch push time (see the
  security discussion in
  `skills/charter/references/phases/phase-state-management.md`),
  so an entry naming `comp` would put a private-only artifact type
  into a public record whatever the `reason` field said. A child
  whose gate never opened was never planned, so there is nothing to
  record; `chain_skipped:` is for children that were planned and
  then held back, like a declined `/roadmap`.
- The STRATEGY, the ROADMAP, and anything else the chain writes
  under `docs/` — no mention of the skipped child, the gate, or
  the reason.

#### Why Stating It Is Correct

The visibility rule governs **document references**: a document in
a public repo must not name documents, paths, or content belonging
to a private repo. It says nothing about what the agent may say to
the author sitting in front of it. Reading it as a gag order was
the mistake the earlier degenerate-silence rule made, and the cost
was real — a step the author might reasonably expect vanished with
no explanation, and the same silence covered two unrelated
conditions (a public repo and a missing skill) that call for
different responses.

Splitting the two surfaces gets both properties at once: the
conversation is honest about what ran and what didn't, and the
artifacts in the repo stay clean. Neither the sentence
`"skipping competitive analysis"` nor the word `/comp` reaches a
committed file, so nothing in the public repo points at a
private-only artifact type or at any private document.

#### Why /charter Checks Visibility At All

`/comp` runs its own visibility check (see
`skills/comp/references/phases/phase-0-setup.md` section 0.2), and
that is not a duplicate of this gate. The two checks do different
jobs:

- `/comp` is directly invocable. An author can reach it with no
  parent involved, so it has to evaluate visibility itself. Its
  response is a **warning**: it names the consequence and lets the
  author decide.
- `/charter` is the thing steering the author. Its job is to not
  route someone toward a private-only artifact type in a public
  repo in the first place. Its response is a **skip**, decided by
  the parent, stated to the author.

Neither check is a workaround for the other's absence, and
removing either one leaves a real hole: drop `/comp`'s and a
direct invocation gets no warning at all; drop `/charter`'s and
the chain proposes a step that cannot land.

The gate reads the feeder skill's presence off the filesystem, so
installing or removing `/comp` changes `/charter`'s behavior with
no `/charter`-side edit.

### Citation

The three-condition gate and the stated-skip rule are documented at
the pattern level in
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
that matches the chain's discovery outputs and the state file's
`consumed_upstream:` field.

1. **Freeform topic.** No upstream artifact path is available;
   `/charter` passes the topic slug alone, and `/strategy`'s
   Phase 1 grounds the conversation in the topic without an
   upstream document.
2. **VISION path.** A VISION is available — either `/vision` ran
   earlier in this chain, or one is already Accepted/Active at the
   published path, or the author supplied one with `--upstream`
   and Phase 0 recorded it in `consumed_upstream:`. `/charter`
   invokes `/strategy <topic-slug> --upstream <vision-path>`,
   which is `/strategy`'s own upstream-flag input mode. The topic
   slug stays in the positional slot and the VISION path travels
   in the flag; see "Why the Slug and the Upstream Travel
   Separately" below.
3. **PRD path.** A PRD exists for the topic at a discoverable
   path. `/charter` passes the PRD path positionally; `/strategy`
   reads it as the operationalizing input for the bet. A grounding
   PRD never travels in `--upstream`, because that flag's value is
   what `/strategy` records in `upstream:` frontmatter and a PRD is
   never recorded (see the read-vs-record rule in
   `skills/strategy/references/phases/phase-0-setup.md`).

   > *Open: whether a STRATEGY may be grounded in a tactical-chain PRD
   > at all is unresolved — see
   > [#257](https://github.com/tsukumogami/shirabe/issues/257). The PRD is
   > never recorded as the STRATEGY's `upstream:`; only the grounding
   > input remains open.*

`/charter` MUST NOT pass a STRATEGY path to `/strategy`. STRATEGY
paths are `/strategy`'s lifecycle-verb mode (its Input Mode 2 —
accept / activate / sunset), which is mutually exclusive of the
create-new mode the three shapes above invoke. Passing a STRATEGY
path would route `/strategy` into a lifecycle transition rather
than into the chain-orchestration flow `/charter` is driving.

### Why the Slug and the Upstream Travel Separately

`/strategy` derives its topic slug from the BASENAME of a
positional path it is handed. So handing it the VISION positionally
names the produced document after the VISION: a bet on
`payment-retries` grounded in `docs/visions/VISION-platform.md`
would land at `docs/strategies/STRATEGY-platform.md`, under a slug
`/charter` never validated and never recorded, while `/charter`'s
own state file, its `exit_artifacts:` list, and its R20
file-existence check all still name `STRATEGY-payment-retries.md`.

That has worked until now only because the two slugs coincided by
construction: a chain that produced its own VISION produced it
under the chain's topic slug. Consuming an upstream the chain did
not produce is defined by that coincidence not holding — it is the
whole point of the flag — so the hand-off cannot keep relying on
it. Passing `<topic-slug> --upstream <vision-path>` decouples the
two: the slug is the parent's, the upstream is a separate argument,
and neither is derived from the other.

`--upstream` is `/strategy`'s own flag, authored in its SKILL.md
input modes and its Phase 0 contract and equally usable by an
author invoking `/strategy` directly. `/charter` is choosing among
the child's shipped input surface, not extending the child's
argument parser — the R14 isolation rule holds unchanged.

## /roadmap Invocation Rule (R7)

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

`/charter` ALWAYS invokes `/roadmap` on a full-run chain. No
property of the just-produced STRATEGY feeds the decision:
`/charter` does NOT count Building Blocks, does NOT test the
Coordination Dependencies section for qualifying entries, and does
NOT parse the document for feature-sequencing surface. The chain
that produced a STRATEGY produces a ROADMAP.

`/charter` still READS those sections. The handoff pre-population
below derives Candidate Features from Building Blocks and the
Dependency Sketch from Coordination Dependencies, and the
confirmation prompt's observation walk reads the STRATEGY to tell
the author what it saw. The distinction is what the reading is
for: filling in the handoff and informing the author, never
deciding whether the invocation happens.

### The Roadmap Confirmation Prompt

The one path that skips `/roadmap` is an explicit author
declination. Immediately before the invocation — after `/strategy`
has completed and the Draft STRATEGY is on disk — `/charter` reads
that STRATEGY, says what it observed, and asks. The default is to
proceed; the author's answer is the only thing that decides.

The question the prompt asks is NOT "is this strategy big enough to
sequence." Size never disqualifies a ROADMAP. The question is
whether the strategy is **headed for execution at all** — a STRATEGY
that records a bet nobody intends to act on is the one case that
legitimately gets no ROADMAP.

#### Observation Walk

`/charter` reads three observations out of the Draft STRATEGY before
asking. Each emits a verdict (`headed-for-execution` /
`not-headed-for-execution`) and a one-line reason; the reasons go
into the prompt verbatim so the author sees the reading rather than
a label. The shape follows `/scope`'s R6 predicate walk (see
`skills/scope/references/phases/phase-1-discovery.md`).

- **O1 — Building Blocks describe deliverables.** Read the
  STRATEGY's Building Blocks. A block naming something to build
  ("ship the merge-gate check in `shirabe validate`") reads
  headed-for-execution; a block naming a question to answer first
  ("determine whether adopters want a merge gate") reads
  not-headed-for-execution.
- **O2 — Invalidation conditions read as things you would act on.**
  Read the per-direction invalidation conditions. A condition
  naming a signal someone would watch ("a second adopter rejects
  the gate") reads headed-for-execution; a condition with no
  observable signal behind it reads not-headed-for-execution.
- **O3 — The STRATEGY does not defer its own work.** Read for an
  explicit park ("revisit next planning round", "nobody is picking
  this up this cycle"). Its presence is the strongest
  not-headed-for-execution signal. Its absence is neutral, not
  positive — most STRATEGYs say nothing about their own timing.

Roll the three up as headed-for-execution unless O3 fires, or O1 and
O2 both read not-headed-for-execution.

#### Prompt Shape

The prompt states the verdict, grounds it in the observations, and
offers the two answers with Proceed pre-selected. It follows the
house convention in
[`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`](${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md):
form a reading, ground it in what you found, let the author
override.

Headed for execution (the common case):

> *"I read the Draft STRATEGY first. Its Building Blocks name things
> to build (`<block>`, `<block>`), and its invalidation conditions
> name signals you would act on (`<condition>`). That reads as
> headed for execution, so it's worth sequencing now. Proceed with
> `/roadmap`, or skip it for now?"* — default **Proceed**.

Not headed for execution:

> *"I read the Draft STRATEGY first. Its Building Blocks read as
> open questions rather than deliverables (`<block>`), and
> `<the O2 or O3 reason>`. That reads as a bet being recorded rather
> than one headed for execution, which is the one case a ROADMAP
> doesn't help. Worth knowing before you answer: a ROADMAP is the
> only bridge from a STRATEGY into the tactical chain, so skipping
> leaves this work with no path forward until someone runs
> `/roadmap` by hand. Proceed with `/roadmap`, or skip it for
> now?"* — default **Proceed**.

The default is **Proceed** in both readings. A negative reading
changes what `/charter` says, never which answer is pre-selected —
the observations inform the author, they do not vote. And the
observation walk is not a gate: whatever it reads, `/charter` still
invokes `/roadmap` unless the author says otherwise.

`/charter` skips `/roadmap` if and only if the author declines
here. In `--auto` mode the prompt does not fire at all and
`/roadmap` always runs — there is no roadmap-specific `--auto`
special case, and no observation the walk can produce creates one.
The declination is an interactive choice, never an inference.

A declination is recorded in the state file's `chain_skipped:`
list as a `{child, reason}` entry. `roadmap` stays in
`planned_chain` — the plan was to run it; the author declined —
and is absent from `chain_ran`:

```yaml
chain_skipped:
  - child: roadmap
    reason: author-declined-at-confirmation-prompt
    detail: declined the roadmap prompt; STRATEGY marked non-actionable
```

`reason` is the vocabulary member, not prose about this run;
`detail:` is the optional sibling that carries the specifics, and
nothing reads it. Both are cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`.

The chain then completes at the full-run exit with the STRATEGY as
the sole `exit_artifacts` entry (the AC11a shape in
`skills/charter/references/phases/phase-finalization.md`).

The declination is how an author marks a STRATEGY **non-actionable**
— one that records a bet without heading toward execution at all.
It is not a judgment about the STRATEGY being too small or too
simple to sequence.

The confirmation prompt is the ONLY path that skips `/roadmap`.
Phase 1's "Adjust" option re-shapes the chain before any child
fires, but it drops no child at all — it can force a
previously-skipped one on and nothing more (see The Three Options
in `skills/charter/references/phases/phase-1-discovery.md`). For
`/roadmap` the consequence is concrete: a chain that reached
full-run on a Phase 1 drop would land a one-entry `exit_artifacts`
with no matching `chain_skipped:` entry, the contract violation
`skills/charter/references/phases/phase-finalization.md` names
under AC11a. An author who already knows at discovery time that no
roadmap is wanted still declines at the confirmation prompt; that
is what records the decision, against a STRATEGY they can read.

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
tactical side) drives work rather than serving as the audit trail;
`/strategy`'s STRATEGY is what the chain leaves behind for the
record. A ROADMAP is small, and producing one commits the author to
nothing.

Be precise about what "working" buys, though: it does NOT mean the
document reliably disposes of itself. The completion cascade only
reaches a ROADMAP through a finished downstream PLAN, and deletes
it only when every feature is Done AND every referenced GitHub
issue is closed; otherwise it just updates that feature's progress.
A ROADMAP nobody plans against is never visited at all. The
argument for firing unconditionally rests on the document being
cheap and non-authoritative, not on it being auto-reclaimed.

The stronger reason is that a ROADMAP is the only bridge from a
STRATEGY into the tactical chain. `/brief` is *framed against* a ROADMAP
and never a STRATEGY, though the STRATEGY is typically what it ends up
recording (see the Input Modes section of `skills/brief/SKILL.md`), so a
chain that ends at a STRATEGY
alone strands whatever it made actionable: no downstream artifact
can pick the work up, and nothing tracks its progress. Skipping the
ROADMAP is only correct when there is no work to strand, which is
exactly what the confirmation prompt asks about.

Nothing about the STRATEGY's size changes that. A one-block
STRATEGY yields a one-feature ROADMAP, and a one-feature ROADMAP is
a valid document — `/roadmap` has no minimum feature count to trip
over. Parent-side arithmetic on Building Blocks would buy nothing
and cost the author a rule to remember.

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
