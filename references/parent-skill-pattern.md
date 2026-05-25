# Parent-Skill Pattern: Contract Surface

The parent-skill pattern is a shared contract that every shirabe parent skill
follows. A parent skill walks an author through a sequence of child skills,
holds state across child boundaries, and enforces invariants that span the
chain. This document is the contract surface — what every parent SHALL
satisfy regardless of which storage substrate or team primitive it runs on.

The companion references fill in the details this document points at:

- [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`](parent-skill-state-schema.md) —
  the 5-field minimum state-file vocabulary plus extension discipline.
- [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`](parent-skill-resume-ladder-template.md) —
  the universal meta-ladder entries plus parent-specific body slots.
- [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`](parent-skill-child-inspection.md) —
  the R14-widened isolation rule plus the per-parent surface table.

## Two-Layer Contract

The contract is split into two layers so the same pattern can ship a
verifiable core-layer implementation today and admit a future amplifier-layer
implementation later without redesign.

**Layer 1 — Semantic invariants (substrate-agnostic).** Named properties
every parent SHALL satisfy regardless of how state is persisted or how teams
are spawned. The semantic layer is what reviewers prose-judge a new parent
against; it is the freeze line.

**Layer 2 — Reference implementation (substrate-bound).** A concrete
serialization that every core-layer parent uses verbatim. The reference
implementation makes the core-layer's pattern-level commitments testable
today; amplifier-layer implementations supply their own serialization that
satisfies the same Layer-1 invariants.

The split is what lets the design ship verifiable v1 commitments (via the
reference implementation) without locking out plausible amplifier-layer
substrates (cloud-backed context stores, session-scoped state, multi-leader
coordination primitives).

## Semantic Invariants

The pattern names six invariants. Each invariant has a one-line semantics
statement and is satisfied by every conforming parent (with one named
exception — see I-6).

- **I-1 — Recorded exit.** A parent records an exit outcome before
  terminating; bail routes to a terminal-artifact path, never to silent loss.
- **I-2 — Durable terminal artifact.** Every chain ends at a durable file on
  disk that human reviewers consume — `docs/<type>/<TYPE>-<topic>.md`. Git
  history is not a substitute.
- **I-3 — Child-isolated resume.** Resume across child boundaries inspects
  both parent state and child durable artifacts; child internals are never
  read.
- **I-4 — Topic-keyed state.** State is keyed by topic slug; concurrent or
  sequential invocations against different topics never interfere.
- **I-5 — Conditional fields absent when ungated.** Conditional fields in
  state are absent when their triggering condition does not hold (never null,
  empty string, or placeholder).
- **I-6 — Cross-branch resume.** Resume holds across feature branches: a
  parent run started on one branch can be resumed from another branch
  against the same topic.

**I-6 is load-bearing as an unsatisfied invariant in v1.** The v1 core-layer
implementation explicitly does NOT satisfy I-6 — state lives on the feature
branch where the parent run originated, and resume on a different branch
starts a fresh chain. Documenting I-6 as a pattern invariant the v1
implementation does not satisfy is the forcing function the amplifier
layer's value proposition depends on: the amplifier-layer mandate includes
closing the I-6 gap. The named-but-unsatisfied framing is deliberate; the
gap is not a bug to be silently lived with, it is a contract the amplifier
layer SHALL fulfill.

## Three Exit Paths

Every parent terminates through one of three named exit paths. The
per-parent binding (which children produce which artifacts, which sub-shapes
a Decision Record can take) is each parent's SKILL.md; the names and
one-line characterizations below are pattern-level.

- **full-run** — The chain reaches its terminal artifact: every required
  child produced its durable doc, the parent recorded `exit: full-run`, and
  `exit_artifacts:` lists the produced files.
- **re-evaluation** — A re-entry on a topic with an existing terminal
  artifact concludes without re-authoring; the parent writes a Decision
  Record (sub-shape parent-specific) and exits with `exit: re-evaluation`.
- **abandonment-forced** — The chain cannot complete the planned terminal
  artifact and the parent force-materializes a partial artifact in
  schema-compliant form, recording `exit: abandonment-forced` plus the
  triggering child and the phase reached.

The three names are stable across parents. Conditional state-file fields
attached to each exit (e.g., `referenced_strategy` on `re-evaluation`,
`triggering_child` on `abandonment-forced`) are gated by I-5 — present when
the exit fires, absent otherwise.

## Conditional Feeder Invocation Shape

A parent MAY offer a feeder skill (a side-channel child the chain does not
strictly require) conditionally. The pattern recognizes a three-condition
gate; signal-detection mechanics are NOT part of the pattern — they are
agent judgment per parent, with broad-category descriptions in each
parent's own SKILL.md.

The three-condition gate, all of which SHALL hold for the feeder to be
offered:

1. A parent-defined Phase 1 discovery signal fires (agent-judgment over
   broad categories the parent's SKILL.md names).
2. The feeder skill exists on disk (`skills/<feeder-name>/SKILL.md` is
   present).
3. A parent-defined visibility gate passes (using the workspace
   `## Repo Visibility:` mechanism).

When any of the three conditions fails, the parent's discovery prompts
SHALL NOT reference the feeder skill or its content surface (the
degenerate-silence rule). The author hears about the feeder only when all
three gates open.

## Named Substitution Surfaces

The design names two substitution variables whose v1 values are
core-layer-bound and whose alternate values are the amplifier-layer's
mandate. Each variable has a fixed v1 value and a stable name; the variable
itself is the freeze line, not the v1 value.

**`storage_substrate`.** How a parent persists state between invocations.

- **v1 value:** `wip-yaml-md` — state lives at
  `wip/<parent>_<topic>_state.md` as a YAML document with the `.md`
  extension (the extension matches shirabe's wip/ convention; the body has
  no markdown). This substrate does NOT satisfy invariant I-6; resume on a
  different branch starts fresh.
- **Alternate values** (amplifier-layer): substrate identifiers such as a
  context-store-backed persistence layer, a session-scoped store, or a
  multi-leader coordination primitive. The amplifier-layer implementation
  SHALL satisfy I-6.

**`team_primitive`.** How a parent's team is spawned and how nested teams
are handled.

- **v1 value:** `single-team-per-leader-no-nested` — a single team per
  leader, no nested team creation, no sub-agent spawning sub-agents. Three
  operational consequences follow from this value:
  1. **Inline-decision walks.** A parent that decomposes a problem into N
     decision questions cannot spawn N persistent validator sub-teams; each
     decision-researcher walks the decision protocol inline.
  2. **File-handoff between parents.** Downstream parents read upstream
     parents' artifacts from `docs/<type>/<TYPE>-<topic>.md` and (when the
     terminal artifact is not yet committed) from the upstream's state file
     under the same substrate convention. There is no live-team query
     interface in v1.
  3. **Upfront upper-bound team roster.** A parent that needs
     variable-cardinality peers declares the upper bound at team-creation
     time; the parent-of-the-parent materializes the full roster, and the
     coordinator dispatches a subset at runtime.
- **Alternate values** (amplifier-layer): substrate identifiers such as a
  nested-team-capable primitive or a live-team-query primitive. The
  amplifier-layer implementation MAY support nested teams, sub-agent
  spawning, and live-team queries.

## Team-Shape Declarator

Each parent skill declares its team shape so a parent-of-the-parent (the
agent invoking the skill) can materialize peers upfront. The declaration
includes:

- **Fixed roles** — peer names and responsibilities present in every
  invocation.
- **Variable-cardinality role types with an upper bound** — peer role
  *types* whose runtime count is determined by an earlier phase, with an
  upper bound declared in the SKILL.md.

The shape declaration is **contract**; the **spawn timing** is
substrate-specific (determined by `team_primitive`). v1's
`single-team-per-leader-no-nested` requires the parent-of-the-parent to
materialize the full roster at team-creation time. Amplifier-layer
implementations MAY support lazy spawning by the coordinator, but the
shape declaration remains the same.

**v1 core layer — prose declaration.** Each parent's SKILL.md declares its
team shape in free-form prose alongside the existing Workflow Phases and
Reference Files sections. The parent-of-the-parent reads the prose and
manually translates it into a team-creation call before invoking the child
skill.

**v2 amplifier layer — structured metadata.** When the amplifier-layer
substrate ships, parent skills MAY declare their team shape as a structured
metadata block (YAML or JSON, in SKILL.md frontmatter or a fenced section)
the substrate parses mechanically. The substrate spawns the upfront roster
from the declaration without human translation.

The two forms serve different layer concerns. Prose fits the manual-spawn
pattern of v1 (a human reads the declaration; an agent translates to a
roster spawn). Structured metadata fits the substrate-driven pattern of v2.
Migrating prose to structured metadata at v2 boundaries is a known
operation, not a contract change.

## Required SKILL.md Structural Elements

Every parent skill's `skills/<name>/SKILL.md` SHALL contain seven
structural elements. The list is pattern-level; the content slotted into
each element is parent-specific.

1. **Input Modes** section — parent-specific input shapes (topic-slug
   argument, optional flags, optional named files).
2. **Execution-mode flag parsing** — `--auto` / `--interactive`,
   `--max-rounds=N`, and any parent-specific flags.
3. **Topic-slug constraint** statement citing
   `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` for the
   regex `^[a-z0-9-]+$`.
4. **Workflow Phases** diagram — parent-specific phases laid out as a
   readable ordering.
5. **Resume Logic** ladder — body slots filled per the parent's chain shape
   and child set; meta-ladder rows cited from
   [`parent-skill-resume-ladder-template.md`](parent-skill-resume-ladder-template.md).
6. **Phase Execution** list — one phase reference per parent phase,
   pointing at `skills/<name>/references/phases/<phase>.md` files.
7. **Reference Files** table — including the four pattern-level references
   plus parent-specific references.

Parents extend the template with parent-specific sections beyond these
seven (e.g., chain-proposal output prose, conditional-feeder integration
prose), but the seven structural elements are the pattern-level floor.
