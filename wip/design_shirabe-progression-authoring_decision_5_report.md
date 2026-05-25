# Decision 5 Report: Framing the TeamCreate single-team-per-leader constraint

**Decision question.** How does the design surface the core-layer's
TeamCreate single-team-per-leader constraint — as a transient
implementation note, an explicit architectural property of the core
layer, or a substitution surface filled by the amplifier layer?

**Tier.** 4 (critical). Full path adapted: Phases 0, 1, 2, inline
adversarial pass, Phase 6 synthesis. No nested validator team
(SE4 §8 — `/decision` walked inline by this decision-researcher per
the same constraint this decision is about).

---

## Phase 0: Context

### Constraint, restated

`TeamCreate` in the Claude Code core layer enforces
single-team-per-leader: any agent that has already created a team
cannot create another, and there is no "nested team under a member"
primitive. Two further core-layer properties, surfaced by team-lead
on 2026-05-24, sit in the same constraint class:

- **Sub-agents cannot themselves spawn sub-agents.** The Agent tool
  is team-lead-only. So a coordinator can spawn workers but workers
  cannot spawn workers.
- **Variable-cardinality cohorts must be spawned upfront by the
  parent.** "Lazy spawn after Phase 1 reveals N" is infeasible; the
  parent must materialize the upper-bound roster, not the runtime
  count.

These three properties are not independent — they are facets of the
same "no nested control-flow in the team primitive" core-layer
limitation. The design must frame them as one architectural
property, not three.

### Two concrete consequences for parent-skill design

- **(a) `/decision` sub-skill invocation from a `/design`
  decision-researcher.** The intended `/decision` agent hierarchy
  (decider → research/alternative/validator sub-team) cannot be
  spawned by a non-team-lead agent. The decision-researcher walks
  `/decision` inline: no parallel alternative-research, no
  persistent validators across Phases 3-5, no cross-decision
  validator memory. This is exactly what this team is doing right
  now per SE4 §8.

- **(b) Cross-parent team query.** Each parent skill's team
  (`charter`, `scope`, future `work-on`) must be destroyed before
  the next parent's team can be created. Downstream parents cannot
  query upstream parents' teams. Today's contract is file-handoff
  via `docs/` and `wip/`.

### Three starter framings from the dispatch

- **(i) Transient implementation note.** Assume resolution lands
  soon; minimize the framing; treat the limitation as a footnote.
- **(ii) Explicit architectural property of the core layer.**
  Commit to file-handoff and inline-`/decision` as the v1 contract.
  Document them as known properties; amplifier-layer may resolve
  but the core-layer design doesn't depend on resolution.
- **(iii) Substitution surface filled by the amplifier layer.**
  Frame as a named substitution variable (`team_primitive:
  single-team-per-leader | nested-teams | sub-agent-spawn-tree`)
  and name the amplifier layer as where the variable takes a
  different value.

### Decision drivers in effect

- The constraint is real today. This team operates under it.
- The PRD records it as Question 6 deferred to design (neutral
  framing). The design's Decision 5 picks the framing.
- The design is public-repo. External readers exist. Framing a
  permanent core-layer property as transient under-serves them.
- The amplifier-layer scope is undetermined. The design must not
  pretend to know the shape of the resolution.
- team-lead's architectural note: the parent-skill pattern needs a
  "team-shape declarator" mechanism — each child skill declares its
  team shape; the parent materializes all peers upfront;
  variable-cardinality cases require the upper bound. For this
  design's own SE4 walk the upper bound was 9.

### Coupling to Decision 2

Decision 2 (substitution surface) frames the **storage**
substitution variable (wip/ ↔ amplifier-layer storage substrate;
cross-branch state-file boundary). Decision 5 frames the **team
primitive** substitution variable. Both are substrate-related
differences between core layer and amplifier layer; both name the
amplifier layer as the resolution surface.

**Assumed (stated as assumption per --auto mode):** Decision 2 will
adopt option (iii)-equivalent for storage (named substitution
variable, amplifier-layer as resolution surface). If Decision 2
chooses a weaker framing (e.g., "core-layer architectural
property" without naming the amplifier surface), Decision 5's
recommendation still holds independently — but the two decisions
should be presented under a shared "substitution surfaces" header
in the design's Open Questions / Consequences sections so the
reader sees a single coherent pattern, not two unrelated framings.

---

## Phase 1: Research

### Critical unknowns

- **Is the constraint actually permanent in the core layer, or is
  Anthropic/Claude Code likely to lift it?** The dispatch says
  "permanent in the core layer." The design must not bet on a
  lift. Even if Claude Code adds nested-team support in a future
  release, the design's public commitment shouldn't depend on it.
  **Resolution:** treat as permanent in the core layer. If it lifts,
  the substitution-variable framing trivially absorbs the change
  (the variable just takes a new value).

- **Does the amplifier layer have a concrete shape?** No. The
  workflow-substrate work is unbounded scope per the design's own
  Decision Drivers. The design can name the amplifier layer as the
  resolution surface without specifying what the resolution looks
  like.

- **Are the three core-layer constraints (single-team-per-leader,
  no sub-agent spawn, upfront-cardinality) actually one constraint
  or three?** All three are facets of "core-layer team primitive
  lacks nested control-flow." Naming them as one substitution
  variable (`team_primitive`) collapses correctly: any
  resolution-surface alternative that lifts one likely lifts the
  others (a workflow substrate that supports nested decisions
  almost certainly supports sub-agent spawning, etc.). Naming three
  variables would over-specify the resolution and create artificial
  coupling.

- **Does the PRD's Question 6 framing constrain Decision 5?** No.
  Question 6 is neutral: "the resolution is design-team territory."
  The PRD records the constraint; the design picks the framing.

- **Does the current design skeleton's Open Questions section
  already commit to a framing?** Yes — it commits to framing (ii)
  with a soft (iii) overlay: it calls them "architectural
  properties of the core layer, not a transient bug" AND names
  "the amplifier-layer workflow substrate is the expected
  resolution surface." This is a viable starting point but stops
  short of naming the substitution variable. Decision 5 can refine
  this into a sharper position.

### Background facts

- Three load-bearing consequences in scope:
  - Inline `/decision` walk (a)
  - File-handoff between parent skills (b)
  - Upfront roster materialization for variable-cardinality teams
    (a third consequence, surfaced by team-lead's 2026-05-24 note)

- The "team-shape declarator" mechanism team-lead surfaced is
  itself a contract surface — each child skill declares its
  upper-bound team shape; the parent materializes the roster. This
  is independent of which team primitive runs underneath, and it
  works for both the current core-layer constraint and any future
  amplifier-layer substrate. It is the actual contract the design
  should commit to.

### Assumptions made

- **A1: The constraint is permanent in the core layer.** If wrong:
  the framing still holds (the substitution variable takes the
  "nested-teams" value); no design rewrite needed.
- **A2: The amplifier layer will eventually exist as a substrate
  that lifts these primitives.** If wrong (amplifier never ships):
  the core-layer framing still stands; readers see file-handoff
  and inline-`/decision` as the v1 contract with no future
  obligation. The substitution-variable framing doesn't promise a
  resolution date.
- **A3: Decision 2 will adopt a substitution-variable framing for
  storage.** Stated as Decision 2 coupling assumption above. If
  wrong, Decision 5 still stands independently but loses some
  pattern coherence in the Open Questions section.

---

## Phase 2: Alternatives

The three starter framings are usable as-is. The adversarial pass
below shows where they have to refine. Two additional framings are
worth surfacing for completeness, then dismissed:

- **(iv) Combine (ii) and (iii) — architectural property AND
  substitution surface.** This is what the design skeleton
  currently does in spirit. It's defensible but vague: naming a
  thing as both "current property" and "future substitution" leaves
  the reader unsure which framing controls. Dismissed in favor of
  (iii) which subsumes (ii)'s honesty.
- **(v) Don't frame at all; just describe the consequences.**
  Dismissed: the PRD already lists Question 6; the design must
  resolve, not skip.

### Alternative (i): Transient implementation note

**Description.** Treat the constraint as a temporary nuisance. The
design body's main sections (Solution Architecture, Implementation
Approach) read as if nested teams were available; a footnote or
brief Open Questions line acknowledges the inline-walk and
file-handoff workarounds without dwelling on them.

**Key characteristics:**
- Minimal surface in the design.
- Implicit expectation that the constraint will resolve.
- Reader takes away: "this is shipping fine; the workaround is
  temporary."

### Alternative (ii): Explicit architectural property

**Description.** The design commits to file-handoff and
inline-`/decision` as the v1 contract. Open Questions section
documents both consequences as known core-layer properties.
Consequences section describes the trade-off (less interactive
inspection across the chain; less parallelism in `/decision`).
Amplifier layer may resolve them later, but the core-layer
contract stands independently.

**Key characteristics:**
- Honest about today's state.
- No commitment to a resolution path or substrate.
- Reader takes away: "this is the v1 reality; future work may
  change it but the contract is independent of that future."

### Alternative (iii): Substitution surface filled by the amplifier layer

**Description.** Frame the constraint as a named substitution
variable in the parent-skill contract. The variable
(`team_primitive`) has known values:
- `single-team-per-leader` (current core-layer value; inline
  `/decision`, file-handoff between parents, upfront roster
  materialization with team-shape declarators)
- `nested-teams` or `sub-agent-spawn-tree` (amplifier-layer
  candidate values; persistent validators, cross-parent team
  query, lazy-spawn cardinality possible)

The contract is invariant; the substrate substitutes. The
amplifier layer is named as the resolution surface — not because
its design is known, but because the substitution surface lives
there by definition.

**Key characteristics:**
- Names the architectural property AND the resolution surface.
- The contract surface (team-shape declarators, file-handoff
  semantics, inline `/decision` walk) is what each parent skill
  commits to today. The substrate is what changes.
- Reader takes away: "this is a substitution surface, current
  value documented, future value lives in the amplifier layer.
  The contract is stable across both."

---

## Inline adversarial pass

For each viable alternative, one steelman paragraph and one
case-against paragraph from a peer who chose differently.

### Adversarial on (i) Transient note

**Steelman.** "The amplifier-layer work is on the roadmap. By the
time external readers care about the team-primitive details,
those details will be different. A heavy framing today freezes
language we'll revise in six months. Lighter framing keeps the
design legible and avoids over-architecting around a constraint
we'll lift. Public-repo readers don't need the substitution-surface
metaphor; they need to know the skill ships."

**Case against (from a (iii) advocate).** This framing fails the
honesty test. The PRD already deferred Question 6 to design; the
design must resolve it, not minimize it. More concretely: "transient
note" assumes resolution within a foreseeable horizon, but the
amplifier-layer substrate is unbounded scope and an explicit Decision
Driver. If the design says "transient" and the amplifier work slips
a year, readers downstream (the next parent-skill author, the
`/work-on` migration team) inherit a misleading map. Worse: the
constraint shapes how decision-researchers run today (inline walk),
how parent skills hand off (files), and how variable-cardinality
teams are spawned (upfront). Calling these "transient" understates
their reach. Treating them as a footnote means future contributors
have to re-discover them when they hit the same wall — which is
exactly what shared design exists to prevent.

### Adversarial on (ii) Architectural property

**Steelman.** "This is the most honest framing. The constraint
exists today; we don't know what the amplifier layer looks like;
we don't even know if it will ship in its current envisioned
form. Naming a substitution variable implies a contract surface
the amplifier must conform to — but we can't author that surface
without knowing the substrate. Better to commit to the v1 contract
as a standalone thing and let the amplifier-layer design decide
whether to inherit, substitute, or replace. Less coupling between
the design we're shipping and a future design we haven't started."

**Case against (from a (iii) advocate).** The standalone-contract
framing leaves the design honest but incomplete: it documents the
constraint without locating the resolution. Three problems. First,
the design skeleton's Decision Drivers explicitly call out "leaves
room for the future amplifier-layer substrate" as a design goal —
(ii) records the constraint but doesn't name where the resolution
lives, which under-delivers on that goal. Second, the same
constraint shows up three different ways (inline `/decision`,
file-handoff, upfront cardinality) and (ii) treats them as three
properties rather than one substitution surface. The reader has
to do the pattern recognition themselves; the design should do it
for them. Third, naming a substitution variable doesn't author
the amplifier-layer's design — it names a contract surface the
amplifier layer (when it exists) will need to substitute. That's
not over-coupling; it's the minimum the parent-skill pattern
needs to be future-compatible. (iii) is (ii) plus a name for the
seam.

### Adversarial on (iii) Substitution surface

**Steelman.** "This is what the design problem asks for. The
Decision Driver explicitly says 'the freeze line is the contract
surface; the implementations are the substitution variables' —
(iii) is just applying that principle to the team primitive the
same way Decision 2 applies it to storage. Naming
`team_primitive` as a substitution variable makes the
parent-skill contract internally consistent: storage substitutes,
team primitive substitutes, contract stays. The reader sees one
pattern, not two unrelated framings. And by naming the team-shape
declarator mechanism explicitly (team-lead's 2026-05-24 insight),
the design gives downstream parent authors a concrete tool — not
just a 'future work' label."

**Case against (from a (i) advocate, charitable version).**
The substitution-variable framing risks two things. First,
**over-specification**: by naming `team_primitive` with explicit
values like `single-team-per-leader` and `nested-teams`, the design
implies a taxonomy the amplifier-layer designer must respect. If
the amplifier layer turns out to use a completely different
abstraction (durable workflows, content-addressed state machines,
something we haven't thought of), the named values become noise
or worse — wrong. Second, **scope creep**: documenting "the
team-shape declarator mechanism" as part of the contract surface
moves a not-yet-shipped pattern into a shared design. The team-shape
declarator is a team-lead architectural insight from 2026-05-24,
not a shipped primitive. Embedding it in the contract turns the
shared design into a forward-looking research note. Better to ship
the v1 contract under (ii) and let the amplifier-layer design,
when it bounds, formalize the seam.

### Adversarial-pass synthesis

The strongest case-against on (iii) is the over-specification risk:
naming concrete substitution values commits to a taxonomy. The
mitigation: name the **variable** (`team_primitive`) without
freezing its **value set**. Document the current core-layer value
in detail; note that any future amplifier-layer value substitutes;
do not list "nested-teams" as a future value with the same
authority as the current value. This preserves (iii)'s win (named
seam, single pattern with storage) without forcing the
amplifier-layer designer into a pre-committed taxonomy.

The strongest case-against on (ii) is incompleteness: it documents
three consequences as three properties rather than one substitution
surface. (iii), even refined per above, does that work for the
reader.

The strongest case-against on (i) is honesty: "transient" mis-states
the constraint's permanence in the core layer.

---

## Phase 6: Synthesis

### Chosen framing: (iii) Substitution surface, refined

The design surfaces the TeamCreate single-team-per-leader constraint
as a **named substitution surface** in the parent-skill contract,
co-located in framing and prose with Decision 2's storage
substitution surface so the two read as one coherent pattern of
"core-layer values vs. amplifier-layer substrate."

**Refinements from the adversarial pass.**

- **Name the variable, document the current value, do not freeze
  future values.** The substitution variable is `team_primitive`.
  Its current core-layer value is documented in detail. Future
  amplifier-layer values are referenced as "the value the amplifier
  layer's substrate will take" — not enumerated.

- **Collapse three consequences into one substitution surface.**
  The three consequences (inline `/decision` walk; file-handoff
  between parents; upfront roster materialization with team-shape
  declarators) all flow from the same constraint. Surface them as
  one substitution surface with three facets, not three independent
  Open Questions.

- **Accept team-lead's "team-shape declarator" insight, but locate
  it carefully.** The team-shape declarator mechanism IS the
  parent-skill contract surface for variable-cardinality cohorts —
  the parent declares an upper-bound team shape, the team primitive
  materializes the roster. This is contract-level, not
  substrate-level: it works in both core layer (parent spawns
  upper-bound roster upfront) and amplifier layer (substrate may
  spawn lazily). Place it in the design's Solution Architecture as
  a contract surface, NOT in the substitution variable's value
  list.

- **State the Decision 2 coupling.** Open Questions / Consequences
  sections present `storage_substrate` and `team_primitive` under
  one "core-layer-to-amplifier-layer substitution surfaces" header,
  not two separate items. The pattern is the same; the values
  differ.

### Confidence

**High.** The adversarial pass identified one substantive risk
(over-specification of future values), and the refinement (name
variable, don't freeze values) absorbs it cleanly. The other
two alternatives' adversarial steelmen were either honesty failures
(i) or under-deliveries on stated design goals (ii). The chosen
framing aligns with the design skeleton's existing direction (the
skeleton already says "this is an architectural property of the
core layer, not a transient bug" AND names the amplifier-layer
workflow substrate as the resolution surface — the chosen framing
sharpens this into named-variable form).

### Rationale (1-2 sentences for the YAML)

The constraint is permanent in the core layer and has three
facets that share one substrate; framing it as a single named
substitution variable (`team_primitive`) co-located with Decision
2's storage variable gives readers one coherent pattern, names the
amplifier layer as the resolution surface without prescribing its
shape, and preserves honesty about today's contract.

### Assumptions carried forward

- **A1: Constraint permanent in the core layer.** If lifted, the
  substitution-variable framing absorbs trivially.
- **A2: Amplifier layer eventually exists.** If not, the
  core-layer value of the variable stands alone with no future
  obligation.
- **A3: Decision 2 will frame storage as a substitution surface.**
  If Decision 2 chooses a different shape, Decision 5 still holds
  but its Open Questions presentation should be revisited so the
  two decisions don't read as inconsistent.

### What Phase 4 should write (direct input for design body)

The chosen framing yields these specific section commitments:

**Open Questions section refactor.** Replace the two current
items ("Nested-team support" and "Team persistence") with one
joint item, paired with Decision 2's storage item under a shared
"Core-layer-to-amplifier-layer substitution surfaces" header:

```
### Core-layer-to-amplifier-layer substitution surfaces

The parent-skill contract names two substitution variables whose
current core-layer values are documented here and whose future
amplifier-layer values are the resolution surface for ongoing
workflow-substrate work.

- **`storage_substrate`** [link to Decision 2 framing]
  Current core-layer value: wip/-based intermediates committed to
  the feature branch, deleted at workflow exit.
  Resolution surface: amplifier-layer workflow-substrate work.

- **`team_primitive`**
  Current core-layer value: single-team-per-leader. Three facets:
  (1) `/decision` sub-skill invocation by a `/design`
  decision-researcher walks inline (no nested validator team, no
  parallel alternative-research, no persistent validators); (2)
  downstream parent skills (`/scope`, `/work-on`) cannot query
  upstream parents' (`/charter`) teams — the contract is
  file-handoff via docs/ and wip/; (3) variable-cardinality
  cohorts are materialized upfront by the parent via the team-shape
  declarator mechanism (parent reads each child's declared
  upper-bound team shape and spawns the roster).
  Resolution surface: amplifier-layer workflow-substrate work.
  Each facet may be addressed independently when the substrate
  bounds — the contract surface is what the substrate must
  substitute, not the substrate's internal design.
```

**Consequences section additions.** Two sentences:
- "The parent-skill contract treats two substrates — storage and
  team primitive — as named substitution surfaces. Today both take
  core-layer values; both name the amplifier layer as the
  resolution surface without prescribing its shape."
- "Inline `/decision` walks and file-handoff between parents are
  not workarounds; they are the documented core-layer values of
  the `team_primitive` substitution variable. Future amplifier-layer
  work substitutes the variable without rewriting the contract."

**Solution Architecture additions.** One subsection introducing the
team-shape declarator mechanism as part of the contract surface
(not as a future-work item):
- Each child skill declares an upper-bound team shape (role names,
  upper-bound peer count for variable-cardinality cohorts).
- A parent skill materializes the roster against that upper bound
  when the cohort is ready — in the core layer this means
  team-lead spawns all upper-bound peers upfront; in any future
  amplifier-layer substrate, the substrate may spawn lazily.
- The contract surface is the upper-bound shape declaration; the
  spawn timing is substrate-specific.

### Rejected alternatives (for the YAML)

- **(i) Transient note**: rejected. The constraint is permanent in
  the core layer; framing as transient mis-states reality, fails
  honest disclosure, and under-serves downstream parent authors who
  will hit the same constraint.
- **(ii) Architectural property (standalone)**: rejected (vs.
  refined (iii)). Documents the property honestly but treats three
  consequences as three properties rather than one substitution
  surface, and doesn't name the resolution surface — under-delivers
  on the design's stated goal of "leaving room for the amplifier
  layer." Refined (iii) is (ii) plus a named seam.

---

<!-- decision:start id="team-primitive-framing" status="assumed" -->
### Decision: Frame the TeamCreate single-team-per-leader constraint as the `team_primitive` substitution surface

**Context**

The Claude Code core layer's TeamCreate primitive enforces
single-team-per-leader, sub-agents cannot spawn sub-agents, and
variable-cardinality cohorts must be materialized upfront by the
parent. These three properties are facets of the same "core-layer
team primitive lacks nested control-flow" constraint. The
constraint shapes how decision-researchers run inside `/design`
(inline `/decision` walk), how parent skills hand off (files between
docs/ and wip/), and how the parent-skill pattern materializes
teams (upfront upper-bound rosters via a team-shape declarator
mechanism). The PRD records the constraint as Question 6 deferred
to design with a neutral framing; this design's Decision 5 chooses
how to surface it.

**Assumptions**

- The constraint is permanent in the core layer. If lifted, the
  substitution-variable framing absorbs the change trivially.
- The amplifier-layer workflow substrate will eventually exist and
  is the natural resolution surface. If it doesn't ship, the
  core-layer value of the variable stands alone.
- Decision 2 will adopt a substitution-surface framing for
  `storage_substrate`. Decision 5 stands independently if Decision
  2 chooses differently, but the Open Questions / Consequences
  presentation assumes coupling.

**Chosen: Named substitution surface (`team_primitive`)**

The design names a substitution variable `team_primitive` in the
parent-skill contract. Its current core-layer value is documented
in detail with three facets:
- Inline `/decision` walk inside `/design` decision-researchers.
- File-handoff (docs/ + wip/) between parent skills, not in-process
  team query.
- Upfront upper-bound roster materialization via the team-shape
  declarator mechanism.

Future amplifier-layer values are referenced as "the value the
amplifier layer's substrate will take" — not enumerated. The
contract surface (team-shape declarators, file-handoff semantics,
inline `/decision` walk) is what each parent skill commits to. The
substrate underneath substitutes.

The design body presents `team_primitive` alongside Decision 2's
`storage_substrate` under a shared "Core-layer-to-amplifier-layer
substitution surfaces" header so the two variables read as one
coherent pattern.

**Rationale**

The constraint is permanent in the core layer, has three facets
sharing one substrate, and is paralleled by Decision 2's storage
substitution. Framing as a single named substitution variable
collapses the three facets into one architectural surface, names
the amplifier layer as the resolution surface without prescribing
its shape, and gives the design a coherent pattern for substrate
substitution. The refinement of (iii) — name the variable, document
the current value, don't enumerate future values — absorbs the
over-specification risk surfaced in the adversarial pass.

**Alternatives Considered**

- **Transient implementation note**: rejected. The constraint is
  not transient; the amplifier-layer substrate is unbounded scope.
  Framing as a footnote understates the reach into parent-skill
  contract surfaces and misleads future contributors.

- **Explicit architectural property (standalone)**: rejected. Honest
  about today's state but treats three consequences as independent
  properties and does not name the resolution surface, missing the
  design's stated goal of leaving room for the amplifier layer.
  Refined (iii) is this alternative plus a named seam.

**Consequences**

The parent-skill pattern's Open Questions and Consequences sections
present `storage_substrate` (Decision 2) and `team_primitive`
(Decision 5) as paired substitution surfaces. Inline `/decision`
walks and file-handoff between parent skills are documented as
current-value behaviors of the `team_primitive` variable, not as
workarounds. The team-shape declarator mechanism becomes a
contract surface in Solution Architecture: each child skill
declares an upper-bound team shape; parents materialize the roster
against the upper bound; the substrate substitutes the spawn
timing. Future amplifier-layer work substitutes `team_primitive`'s
value without rewriting the parent-skill contract.

<!-- decision:end -->

---

## Status: `assumed`

Three assumptions (A1, A2, A3) are explicit. The decision is made
in `--auto` mode without user confirmation. Per
`references/decision-block-format.md` threshold rules, status is
`assumed`.
