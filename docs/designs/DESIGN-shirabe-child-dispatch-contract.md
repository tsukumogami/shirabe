---
schema: design/v1
status: Accepted
problem: |
  The parent-skill pattern v1 reference and the two parent SKILL.md
  files describe parent-to-child dispatch across three passages
  (Team Shape, Phase 2, R19/I-7) that name no harness mechanism.
  Children declare their team needs in scattered prose. An
  orchestrator reading the docs cannot reconstruct a single
  dispatch contract, so each run picks a mechanism by guess and
  drifts from authorial intent.
decision: |
  Bind the dispatch mechanism to a single harness primitive — the
  Skill tool, invoked inline by the parent — and treat the
  child's team shape as a declared shape the parent reads but does
  NOT pre-materialize at the parent layer. Encode the child's
  team-shape declaration as a fenced YAML block embedded under a
  stable `## Team Shape` heading in the child's SKILL.md. Construct
  the team (when one exists) at the child-dispatch layer, owned by
  the child itself; the parent owns no team. Land a single
  Dispatch Contract section in `references/parent-skill-pattern.md`
  between Team-Shape Declarator and Team-Lead Operating Discipline,
  with four labelled sub-elements (mechanism, pre-dispatch state,
  observability surface, hand-back). Propagate verbatim
  cross-references from both parent SKILL.mds and all seven
  child SKILL.mds.
rationale: |
  Three competing mechanism readings are reconciled by treating
  the literal "child's existing input mode" passage as the
  contract and the other two passages as cross-references against
  it. Inline Skill-tool dispatch is the only mechanism that
  matches v1's `team_primitive: single-team-per-leader-no-nested`
  without requiring substrate that does not exist: TeamCreate per
  child violates no-nested when children themselves spawn juries;
  single sub-agent per child silently re-routes the discipline's
  filesystem-evidence checks against a layer the parent does not
  own. The fenced YAML declarator beats prose (grep-anchorable,
  schema-validatable) and frontmatter (children already use
  frontmatter for schema/status; a `team:` key would collide with
  artifact-schema validators). Child-owned construction preserves
  R14 child-isolation: the parent reads the declaration but never
  materializes peers, so the child remains the team's sole
  parent-of-the-parent. The Layer-1 / Layer-2 split is preserved
  by labelling the YAML schema and the Skill-tool primitive as
  Layer 2, with the four contract elements as Layer 1.
upstream: docs/prds/PRD-shirabe-child-dispatch-contract.md
spawned_from:
  issue: 150
  repo: tsukumogami/shirabe
  parent_design: docs/prds/PRD-shirabe-child-dispatch-contract.md
---

# DESIGN: shirabe-child-dispatch-contract

## Status

Accepted

## Context and Problem Statement

shirabe ships two parent skills today — `/scope` (tactical chain: `/brief` -> `/prd` -> `/design` -> `/plan`) and `/charter` (strategic chain: `/vision` -> `/strategy` -> `/roadmap`). The parent-skill pattern v1 contract lives in `references/parent-skill-pattern.md`. Both parents and the pattern reference describe a parent invoking a child, but they do not pin down *how* the invocation crosses the boundary.

Three passages touch the handoff and disagree:

- **`/scope`'s `## Team Shape` section** declares the parent is single-agent with "no team spawned at the `/scope`-itself layer." Read alone, this rules out team primitives at dispatch time.
- **`/scope`'s Phase 2 child-invocation step** in `phase-2-chain-orchestration.md` says invocation goes via "the child's existing input mode: `/<child-name> <topic-slug>`." Read literally, this points at an inline Skill-tool call.
- **R19/I-7 Team-Lead Operating Discipline** in the pattern reference describes a sleep-check-nudge loop, filesystem evidence checks, PASS/FAIL/ESCALATE terminal exits, and `triggering_teammate:` fields. That posture only makes sense against an asynchronously-dispatched workload.

Each passage is internally coherent. None of them is coherent with all three at once. An orchestrator reading the docs cold picks one of: (a) inline Skill tool, (b) a single general-purpose subagent, (c) a TeamCreate-backed team per child. Issue `tsukumogami/shirabe#150` ("docs(scope): clarify that /scope spawns a TeamCreate-backed team per child dispatch") is the upstream surfacing of the gap. The issue's title proposes one resolution; the PRD deliberately leaves the choice open to this DESIGN.

The PRD's R1-R11 frame the contract surface: four labelled elements (dispatch mechanism, pre-dispatch state, observability surface, hand-back), symmetric application to `/scope` and `/charter`, child-side declarations for all seven children, preservation of seven semantic invariants (I-1 through I-7) and the Layer-1 / Layer-2 split. The PRD's D5 names three decisions deferred to DESIGN: per-parent override slot in v1, declarator format granularity, forward-looking note placement.

The technical problem DESIGN settles: pick one harness primitive consistent with v1's `team_primitive: single-team-per-leader-no-nested`; pick a declarator format that propagates to seven children with low migration cost; place the contract section in the pattern reference; specify per-file edits that reconcile the three passages without renumbering invariants or breaking the existing pattern validator.

## Decision Drivers

- **DD1 — Mechanism must be compatible with `team_primitive: single-team-per-leader-no-nested`.** The named substitution surface fixes v1's team primitive. Any mechanism that requires nested teams or a sub-agent spawning a sub-agent breaks this binding before the amplifier layer ships.
- **DD2 — Mechanism must accommodate children that themselves run juries.** `/prd` runs a 3-agent jury at Phase 4; `/design` runs decision-researchers in Phase 2; `/brief` runs a 2-reviewer jury; `/strategy`, `/roadmap`, `/vision` all run juries. The chosen mechanism must let these children operate without forcing the parent to participate in the team-construction call.
- **DD3 — R14 child-isolation must remain enforceable.** The parent reads only the child's durable artifact frontmatter and git blob hash. A mechanism that gives the parent privileged inspection of child internals breaks R14.
- **DD4 — R20 file-existence check stays a path test, not a content read.** The parent confirms the canonical artifact path exists; it does not read the child's wip/.
- **DD5 — Declarator format must be grep-anchorable.** AC7 requires a grep-checkable marker across seven SKILL.md files. The marker shape is fixed at contract-section time.
- **DD6 — Declarator format must not collide with existing frontmatter.** Children already use frontmatter for `schema:` and `status:`. A new top-level frontmatter key risks breaking artifact-schema validators downstream.
- **DD7 — Migration cost must be bounded.** Seven children plus two parents plus two phase references plus the pattern reference plus the state-schema reference. The chosen format must apply uniformly across all seven children regardless of whether their team is currently prose-described, jury-prose-described, or absent.
- **DD8 — Forward compatibility with amplifier-layer substitution.** The contract's properties are Layer 1; the chosen mechanism is Layer 2 (slots into `team_primitive`). The DESIGN must label the split explicitly.
- **DD9 — Invariant preservation.** I-1 through I-7 wording stays unchanged. The DESIGN operationalizes I-7 (Active Orchestration) by naming the mechanism the discipline binds against; it does not introduce a new invariant.

## Considered Options

The DESIGN settles three independent decisions and three D5 backlog items. Each decision walks its alternatives before naming the chosen option, per the PRD's "no solution before deliberation" constraint.

### Decision 1 — Dispatch Mechanism

The question: which harness primitive carries each child invocation?

**Option 1A — TeamCreate-backed team per child dispatch.** The parent calls `TeamCreate` to spawn a team for each child invocation. The team has a coordinator (the child) and peers materialized from the child's declared team shape. The parent dispatches via `SendMessage` to the coordinator.

- *Pros:* Matches the R19/I-7 discipline's asynchronous shape literally; the parent has structured messages to inbox-process; the team-lead discipline reads against a real team boundary.
- *Cons:* Violates `team_primitive: single-team-per-leader-no-nested` when the child itself runs a jury (`/prd`, `/design`, `/brief`, `/strategy`, `/roadmap`, `/vision`). The child's jury would be a nested team inside the dispatch team. The substrate forbids this in v1. Also: the parent now owns the team it dispatched to, which breaks R14 child-isolation — the parent would see the child's peers' inbox messages and partial artifacts.
- *Verdict:* Rejected. The substrate constraint is hard.

**Option 1B — Single general-purpose sub-agent per child dispatch.** The parent spawns one sub-agent via the Agent tool. The sub-agent runs the child invocation. The parent monitors the sub-agent via `run_in_background` polling.

- *Pros:* Matches the R19 sleep-check-nudge loop in shape; lets the parent run as single-agent at its own layer.
- *Cons:* The sub-agent is itself a parent-of-the-team-the-child-creates. When the child runs a jury, that jury is nested inside the dispatched sub-agent — the same `single-team-per-leader-no-nested` violation 1A hits, dressed differently. Worse, the parent's filesystem-evidence check now reads against a layer (the sub-agent's filesystem) the parent does not own; this is what triggered the run that surfaced #150 — the author flagged the dispatch as not matching intent because the sub-agent's filesystem state was opaque to the parent.
- *Verdict:* Rejected. The "single sub-agent" compromise is the silent reading that broke the original run.

**Option 1C — Inline Skill-tool invocation.** The parent calls the Skill tool directly with the child's name and the topic slug, the same way a user typing `/<child> <topic>` would. The child runs in the parent's own agent context; the child's own team-construction (juries, decision-researchers) is the child's responsibility and happens at the child layer, not at the parent layer.

- *Pros:* The literal reading of Phase 2's "the child's existing input mode." Compatible with `team_primitive: single-team-per-leader-no-nested` — the parent owns no team; the child owns its own team. R14 child-isolation is preserved because the parent reads only the child's durable artifact path, never the child's internal team coordination. The R19 discipline binds at the child layer (the child runs the discipline against its own peers) not at the parent layer (the parent runs no team-lead loop at all — there is no team to lead).
- *Cons:* Requires re-interpreting the R19 binding for `/scope` and `/charter`. Today, `/scope`'s Team Shape section says R19 binds at the child-skill-dispatch layer, which gestures at parent-runs-team-lead-against-child. Under 1C, R19 binds inside the child against the child's own peers, and the parent's role is the synchronous Skill-tool caller. The Binding Notes section in the pattern reference (which today describes `/charter` as having a vacuous parent-layer binding and a concrete child-dispatch binding) needs rewording to reflect that R19 binds inside the child, not across the dispatch.
- *Verdict:* Chosen. The substrate is the forcing function: only inline Skill-tool dispatch matches `single-team-per-leader-no-nested`. The R19 reinterpretation is a wording change, not a discipline change — the sleep-check-nudge loop runs inside whichever skill spawns a team, which is the child, not the parent. The author's intent in the run that surfaced #150 matches 1C: the parent stays single-agent, the child runs its own discipline.

**Option 1D — Shape-dependent: parent reads the child's declared shape and constructs the matching primitive.** The user's hypothesis. The parent inspects the child's team-shape declaration; if the declaration names peers, the parent constructs a team; if not, the parent calls inline.

- *Pros:* Matches the intuition that "the contract reads the inner skill's declared shape." Lets simple children stay simple and complex children get teams.
- *Cons:* Reintroduces the 1A violation for any child that itself runs a jury — the parent-constructed team plus the child-run jury equals a nested team. The "shape-dependent" framing also conflates two concerns: the dispatch primitive (how the parent calls the child) and the team-construction layer (which agent materializes the child's peers). Decision 3 below settles the team-construction layer separately; conflating it here makes the contract harder to read. Finally, "shape-dependent" is already a gate-vocabulary term in the pattern (see `## Gate Vocabulary` in the pattern reference, where "shape-dependent" describes a gate whose sub-shape is upstream-recorded). Reusing the term for dispatch-mechanism choice would overload it.
- *Verdict:* Rejected. The intuition the option captures is real but is the wrong altitude: the parent SHOULD read the child's declared shape (this is what AC7 requires) but the reading does not change the dispatch primitive; it informs *who* constructs the team (the child, per Decision 3 below).

**Chosen: 1C — Inline Skill-tool invocation.**

### Decision 2 — Declarator Format

The question: how does each of the seven children declare its team shape so the parent can read it?

**Option 2A — Prose subsection under a `## Team Shape` heading.** Each child gets a `## Team Shape` heading with free-form prose describing peers.

- *Pros:* Zero new validation infrastructure; matches the v1 prose-declarator form the parent-skill-pattern already calls out.
- *Cons:* Not mechanically parseable. The PRD's R3 requires the declaration to distinguish reviewer-shaped roles from variable-cardinality worker role types and to name an upper bound for variable-cardinality. Prose cannot be grep-checked for those distinctions; a reviewer evaluating compliance would need to read prose against intent. AC9 (upper bound named) becomes a judgment call.
- *Verdict:* Rejected. R3's structural distinctions need a structural format.

**Option 2B — Structured YAML in SKILL.md frontmatter.** Add a `team:` top-level key to the child's SKILL.md frontmatter with a nested schema for peers, roles, cardinality, upper bound.

- *Pros:* Frontmatter is the most schema-validated surface in shirabe; existing artifact validators already parse it.
- *Cons:* Children's SKILL.md frontmatter today does not follow the artifact schema/v1 convention — SKILL.md files have plugin-format frontmatter (`name`, `description`), not artifact frontmatter. Adding a `team:` key to that frontmatter risks collisions with the plugin loader's parser and with future skill-marketplace metadata. Worse, the artifact validators that already parse `schema:` and `status:` would attempt to validate the `team:` block against schemas that do not apply to SKILL.md files.
- *Verdict:* Rejected. The frontmatter surface is wrong: SKILL.md frontmatter is for plugin metadata, not for content schemas.

**Option 2C — Structured markdown table under `## Team Shape`.** Each child gets a `## Team Shape` heading with a fixed-column markdown table (Role, Cardinality, Upper Bound, Notes).

- *Pros:* Tables are grep-anchorable by column headers and human-readable.
- *Cons:* Tables are brittle to wrap, hard to extend without breaking column alignment, and a poor fit for nested data (a role with multiple notes-of-notes). The amplifier-layer migration to structured metadata (as the pattern reference's Team-Shape Declarator section anticipates) would require re-encoding tables as YAML anyway.
- *Verdict:* Rejected. Tables are a halfway house between prose and YAML; the amplifier-layer migration path makes the halfway position more expensive than going straight to YAML.

**Option 2D — Fenced YAML block under `## Team Shape` in SKILL.md body.** Each child has a `## Team Shape` heading whose body contains a fenced YAML code block following a fixed schema. The schema's top-level keys: `parent_layer:` (peers materialized at parent-of-parent time, almost always empty), `child_layer:` (peers spawned inside the child, with role types and cardinality).

- *Pros:* YAML is the schema language the pattern already uses for state files. Grep-anchorable on the heading and on the fence (` ```yaml `). Schema-validatable via a separate validator pass without coupling to SKILL.md frontmatter. The amplifier-layer migration to structured metadata is a no-op — the body block already IS structured metadata; the substrate just needs to parse it. Distinguishes reviewer-shaped roles from variable-cardinality worker role types via explicit `cardinality:` and `upper_bound:` fields, satisfying R3 / AC8 / AC9 grep-checkably.
- *Cons:* Slightly heavier than prose for children with empty teams (the `parent_layer: []` and `child_layer: []` block is more visual weight than "no team"). The mitigation: a fixed-schema empty-team block is itself a clear declaration and satisfies the "explicit no-team" branch of R3.
- *Verdict:* Chosen. The amplifier-layer migration argument is the decider — every other option needs re-encoding when the substrate ships; 2D is already in the destination shape.

**Chosen: 2D — Fenced YAML block under `## Team Shape` in SKILL.md body.**

The exact schema:

```yaml
parent_layer:
  # Peers the parent-of-the-parent materializes upfront.
  # Empty for every child in v1, because Decision 3 places
  # team construction at the child layer.
  peers: []

child_layer:
  # Peers the child itself spawns during its phases.
  # An empty list is a valid declaration meaning "no team."
  peers:
    - role: <kebab-case-role-name>
      cardinality: reviewer | worker
      upper_bound: <integer>  # required when cardinality = worker
      phase: <phase-name>
      purpose: <one-line description>
```

`reviewer` cardinality means one peer reviews all N work items; `upper_bound` is omitted (one is implicit). `worker` cardinality means one peer per work item; `upper_bound` names the maximum N. The schema mirrors the pattern reference's existing Reviewer-shaped-vs-variable-cardinality vocabulary verbatim.

### Decision 3 — Team-Construction Layer

The question: when a child has peers, who constructs the team — the parent (the `/scope` or `/charter` coordination layer), or the child itself?

**Option 3A — Parent constructs the team for the whole chain (one team spans all children).** `/scope` constructs a team at chain start with peers covering all child-emitted roles; the coordinator dispatches each child as a phase.

- *Pros:* Single team spans the chain; teardown is once per chain run.
- *Cons:* Violates `team_primitive: single-team-per-leader-no-nested` because the parent now owns a team while children spawn juries inside that team. The upper-bound-roster declared at team-creation time would need to span every possible role across all four children — `/brief`'s 2 reviewers, `/prd`'s 3 jurors, `/design`'s N decision-researchers, `/plan`'s decomposers — turning the parent's Team Shape section into a transitive declaration of every descendant's team needs. R14 child-isolation breaks: the parent sees the peers the child dispatches.
- *Verdict:* Rejected.

**Option 3B — Parent constructs a fresh team per child dispatch.** `/scope` calls TeamCreate per child invocation; the team's roster matches the child's declaration; the team is torn down after the child returns.

- *Pros:* Smaller blast radius than 3A; the parent's roster declaration stays per-child.
- *Cons:* Same nested-team violation as Decision 1's option 1A. The child's internal jury (when it has one) becomes a nested team inside the parent's per-child team.
- *Verdict:* Rejected.

**Option 3C — Child constructs its own team at the child layer.** The parent calls the Skill tool inline (per Decision 1's 1C). The child reads its own team-shape declaration during its Phase 0; if the declaration names peers, the child calls TeamCreate at its own layer (matching today's behavior — `/prd`'s Phase 4 jury, `/design`'s Phase 2 decision-researchers, etc.). The parent owns no team.

- *Pros:* Compatible with `single-team-per-leader-no-nested` (only one team exists at a time — the child's). Preserves R14 child-isolation (the parent has no view into the child's team). Matches the actual runtime behavior of `/prd`, `/design`, `/brief`, `/strategy`, `/roadmap`, `/vision` today — those children already construct their own juries; this decision codifies it. Lets the parent's Team Shape section honestly say "single-agent, no team" because that is what the parent actually does.
- *Cons:* The R19 discipline binding moves. Today's `/scope` Team Shape section says R19 binds at the child-skill-dispatch layer; under 3C it binds inside the child against the child's own peers. The Binding Notes section in the pattern reference needs to be reworded. (This is the same wording change Decision 1 already requires.)
- *Verdict:* Chosen.

**Chosen: 3C — Child-layer team construction.**

This resolves issue #150's "Reading 1 vs Reading 2" question explicitly: Reading 2 (parent constructs the team) is rejected; Reading 1 (child constructs its own team if any) is the contract. The issue's suggested-fix title ("/scope spawns a TeamCreate-backed team per child dispatch") is wrong as stated; the correct framing is "/scope invokes the child inline; the child spawns its own team if it has one."

### Decision 4 — Per-Parent Override Slot in v1 (PRD D5(a))

The question: should the contract introduce a named override slot in `/scope`'s and `/charter`'s SKILL.md files for per-parent dispatch-behavior overrides?

- *Pros of introducing one:* Future-proof; if a third parent (e.g., `/work-on`) needs to override a contract element, the slot already exists.
- *Cons:* AC13 requires the contract-relevant passages to differ only in child names and topic-slug placeholders. An override slot that exists but is empty in v1 is a maintenance attractor — reviewers debate what should go in it; future contributors fill it for the wrong reasons.
- *Decision:* No override slot in v1. The contract section in the pattern reference includes a one-sentence note: "v1 has no per-parent overrides; the contract applies verbatim to both parents." When `/work-on` migrates and an override is genuinely needed, the slot is introduced at that point with the override's content as the forcing function. AC14's "absence is explicit" branch is satisfied.

### Decision 5 — Declarator Format Granularity (PRD D5(b))

The question: granularity of the declarator schema — every field optional, fields constrained, or fields required?

- *Pros of permissive (every field optional):* Lower migration burden.
- *Cons:* Defeats grep-checking. AC8 / AC9 become unverifiable.
- *Pros of strict (every field required):* Maximum grep-checkability.
- *Cons:* Vacuous fields for empty teams; `upper_bound` makes no sense for reviewer cardinality.
- *Decision:* Mixed strictness. `parent_layer.peers` and `child_layer.peers` are required lists (may be empty). When a peer is declared, `role`, `cardinality`, `phase`, `purpose` are required; `upper_bound` is required iff `cardinality: worker`. An empty-team child declares two empty lists; this is the explicit "no team" branch that satisfies R3.

### Decision 6 — Forward-Looking Note Placement (PRD D5(c))

The question: where does R11's forward-looking note ("the contract applies to chain runs initiated after the contract lands; existing in-flight runs are not retroactively re-shaped") live?

- *Pros of placing in the contract section itself:* One-stop reading; a reader who finds the contract section finds the scope boundary in the same place.
- *Pros of placing in a separate scope sub-section:* Lets the contract section stay focused on the four elements.
- *Pros of placing in parent SKILL.md files:* Closest to where in-flight-run authors would look.
- *Decision:* Place the note in the contract section itself as a closing sentence after the four elements. AC17 is satisfied with one grep target rather than three. The parents' SKILL.md cross-references inherit the note via the cross-reference. Rejected: placement in parent SKILL.md (forces both parents to carry duplicate prose, violating AC13's symmetric-wording requirement).

## Decision Outcome

The DESIGN binds the dispatch mechanism to **inline Skill-tool invocation** (Decision 1's 1C), the child-side declarator format to a **fenced YAML block under `## Team Shape`** (Decision 2's 2D), and team construction to **the child layer** (Decision 3's 3C). The three decisions reinforce each other: 1C requires the parent to own no team; 2D gives the child a parseable declaration the parent can read at dispatch time; 3C places team construction with the entity that has the substrate to construct it. The four PRD-required contract elements (R2.1-R2.4) become four labelled sub-sections under a single new `## Dispatch Contract` heading in `references/parent-skill-pattern.md`.

The combination is the only one consistent with v1's `team_primitive: single-team-per-leader-no-nested`. The alternatives all fail at the substrate level: TeamCreate per child (1A) and parent-constructed teams (3A/3B) violate no-nested; single sub-agent per child (1B) hides team state behind an opaque layer the parent does not own. Inline Skill-tool plus child-owned construction lets the parent stay honestly single-agent and lets the child run its own R19 discipline against its own peers — which is what every existing jury-running child already does.

The Layer-1 / Layer-2 split is preserved: the four contract elements are Layer 1 (substrate-agnostic — every future substrate names a mechanism, a pre-dispatch state, an observability surface, and a hand-back). The specific bindings (the Skill tool, the YAML schema, the wip/state.md path) are Layer 2 (substrate-bound — replaceable when the amplifier layer ships).

## Solution Architecture

### Component 1 — The `## Dispatch Contract` section in `references/parent-skill-pattern.md`

A single new top-level section, placed between `## Team-Shape Declarator` (line 250) and `## Required SKILL.md Structural Elements` (line 300). The placement matches the natural flow: declarator (how children describe their shape) -> dispatch contract (how the parent reads the shape and invokes the child) -> structural elements (what SKILL.md must contain).

The section's structure:

```
## Dispatch Contract

[Opening paragraph — names the contract as a contract, states the
single mechanism, states the symmetric applicability across all
parents and all children.]

### Dispatch Mechanism

[Names the Skill tool as the v1 binding. States `team_primitive`
Layer-2 substitution. Cross-references R14.]

### Pre-Dispatch State

[Enumerates: parent_orchestration: sentinel, worktree-staleness
gate output, state-file fields written before dispatch. Cross-
references parent-skill-state-schema.md.]

### Observability Surface

[Positive statement: durable artifact path polling, git log,
wip/ filesystem of the parent itself. Negative statement: cites
R14 for child internals. Names what's allowed and what's not,
explicitly.]

### Hand-Back Contract

[Enumerates: R20 file-existence check, frontmatter status read,
git blob hash capture, Phase-N Reject discard-commit detection
via git log <pre_invocation_sha>..HEAD, validator pass-through,
parent_orchestration: cleanup, child_snapshots: capture.]

[Closing paragraph — Layer-1 / Layer-2 label, no-per-parent-
override-in-v1 statement, forward-looking note (R11).]
```

Total section length: approximately 110 lines (matches the section-density of the surrounding pattern reference).

### Component 2 — Child team-shape declarations

Every one of `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`, `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md` gets a `## Team Shape` section containing a fenced YAML block per Decision 2's schema. The migration table below names what each child's declaration looks like, derived from the child's existing phases.

| Child | parent_layer | child_layer peers (post-migration) |
|---|---|---|
| `/brief` | `peers: []` | `content-quality-reviewer` (reviewer, phase: validate, purpose: review Problem Statement, User Outcome, Journeys, Scope Boundary); `structural-format-reviewer` (reviewer, phase: validate, purpose: schema / heading / format checks) |
| `/prd` | `peers: []` | 3 jury reviewers (cardinality: reviewer; phase: validate; purpose: content quality, requirements completeness, structural format) |
| `/design` | `peers: []` | `decision-researcher` (worker, upper_bound: 8, phase: execution, purpose: walk decision protocol per question); `architecture-reviewer` (reviewer, phase: jury), `contract-completeness-reviewer` (reviewer, phase: jury), `migration-feasibility-reviewer` (reviewer, phase: jury), `structural-format-reviewer` (reviewer, phase: jury) |
| `/plan` | `peers: []` | `decomposer` (worker, upper_bound: per-outline; phase: decomposition); review jury per existing /plan structure |
| `/vision` | `peers: []` | jury reviewers per existing /vision phase 4 |
| `/strategy` | `peers: []` | 3 jury reviewers (bet quality, altitude, structural format) per existing strategy phase 4 |
| `/roadmap` | `peers: []` | jury reviewers per existing /roadmap phase 4 |

All seven have `parent_layer.peers: []` — consistent with Decision 3 (the parent constructs no team). The `child_layer.peers` list captures what the child actually spawns today. The declaration codifies existing behavior; it does not introduce new peers.

### Component 3 — Parent cross-references

`/scope` SKILL.md and `/charter` SKILL.md each get:

1. **Updated `## Team Shape` section.** Existing prose is preserved (the parent runs single-agent at its own layer); a new closing sentence cross-references the new `## Dispatch Contract` section as the source of the dispatch mechanism: "See [`Dispatch Contract`](../../references/parent-skill-pattern.md#dispatch-contract) for the mechanism that carries each child invocation."

2. **No body changes to other sections.** The Phase 2 reference is updated separately (Component 4); other sections are unaffected.

The cross-reference text is verbatim between the two parents, satisfying AC10 and AC13.

### Component 4 — Phase 2 cross-references

`skills/scope/references/phases/phase-2-chain-orchestration.md` and `skills/charter/references/phases/phase-2-chain-orchestration.md` each get:

1. **Updated `## Child Invocation` section.** Today's "Phase 2 invokes the child via the child's existing input mode: `/<child-name> <topic-slug>`" wording is preserved AND a leading sentence cross-references the `## Dispatch Contract` section in the pattern reference as the source of the dispatch mechanism. The "the child's existing input mode" wording remains (now described as the literal Skill-tool surface).

The cross-reference text is verbatim between the two parents (with child names substituted in the enumeration of canonical artifact paths, which is the AC13-permitted variation).

### Component 5 — R19/I-7 Binding Notes rewording

`references/parent-skill-pattern.md`'s `### Binding Notes for /charter` subsection (lines 464-481) is reworded to reflect the new contract. The current text describes R19 binding "at the child-skill dispatch layer" with the parent as team-lead of the child invocation; the new text describes R19 binding inside the child against the child's own peers (the team the child constructs at the child layer). A new `### Binding Notes for /scope` subsection is added symmetrically.

The discipline's *content* (sleep-check-nudge loop, terminal exits, timing table, idle-pings rule, nudge content rule, ci_outcome semantics) is preserved verbatim. Only the binding-layer description changes.

### Component 6 — State-schema annotation

`references/parent-skill-state-schema.md` gets a one-paragraph annotation under the `parent_orchestration:` block schema noting that the block is the pre-dispatch state element of the dispatch contract, with a cross-reference to the new contract section. No schema fields change; the existing fields (`invoking_child`, `suppress_status_aware_prompt`, `rationale`) remain.

### Interaction diagram

```
Author types: /scope my-topic
  |
  v
/scope (single agent, no team)
  |
  +-- Phase 0: setup, state file with parent_orchestration:
  +-- Phase 1: discovery
  +-- Phase 2: child invocation loop
       |
       +-- writes parent_orchestration: { invoking_child: brief, ... }
       +-- captures pre_invocation_sha = HEAD
       +-- Skill tool: invoke /brief my-topic   <-- DISPATCH POINT
            |
            v
       /brief (child agent context, runs at its own layer)
         |
         +-- Phase 0: reads parent_orchestration: from state file
         +-- Phase 1-3: drafts BRIEF
         +-- Phase 4: TeamCreate {2 reviewers}   <-- child owns this team
              |
              +-- R19 discipline binds HERE
              +-- /brief is the team-lead
              +-- reviewers PASS or FAIL
         +-- Phase 5: finalize, write BRIEF-my-topic.md
            |
            v (Skill tool returns)
       +-- /scope reads:
            - canonical path docs/briefs/BRIEF-my-topic.md exists (R20)
            - frontmatter status: Accepted
            - git blob hash of artifact
            - git log <pre_invocation_sha>..HEAD for Phase-N Reject
            - shirabe validate pass-through
       +-- clears parent_orchestration:
       +-- captures child_snapshots.brief.{status, content_hash, commit_sha}
       +-- proceeds to next child (or exits chain)
```

The R19 discipline runs at the `/brief` layer (against the 2 reviewers /brief spawned), not at the `/scope` layer (`/scope` has no team to lead). When R19 fires ESCALATE inside `/brief`, the escalation surfaces through `/brief`'s normal terminal artifact (a partial BRIEF with abandonment-forced state) which `/scope` then reads through the R20 surface — `/scope` learns about the escalation by reading the BRIEF's frontmatter, not by inboxing a verdict from a child team it does not own.

## Implementation Approach

The migration is sequenced in five phases to minimize the window during which the pattern reference and the children disagree.

### Phase A — Land the contract section (single PR)

1. Add `## Dispatch Contract` section to `references/parent-skill-pattern.md`.
2. Reword `### Binding Notes for /charter` and add `### Binding Notes for /scope`.
3. Annotate `references/parent-skill-state-schema.md`.

This is one atomic edit to the pattern reference. After this phase, the contract section exists and is the single source of truth, but the parents and children do not yet cross-reference it. The pattern reference is internally consistent; the surrounding skills temporarily appear inconsistent (they still describe the dispatch as scattered passages). This phase deliberately ships before the parents are updated, so the cross-reference target exists when the parents are updated.

### Phase B — Update parent SKILL.md cross-references

1. Update `skills/scope/SKILL.md` `## Team Shape` section.
2. Update `skills/charter/SKILL.md` `## Team Shape` section.
3. Update `skills/scope/references/phases/phase-2-chain-orchestration.md` `## Child Invocation`.
4. Update `skills/charter/references/phases/phase-2-chain-orchestration.md` `## Child Invocation`.

Verbatim cross-references between the two parents. AC10, AC11, AC13 are verified.

### Phase C — Migrate child team-shape declarations

Seven children, one `## Team Shape` section each. The order does not matter; the changes are independent. After this phase, AC7, AC8, AC9 are verified.

### Phase D — Validator extension (optional, deferred)

`shirabe validate` learns to parse the `## Team Shape` YAML block and check schema conformance. This is OUT of scope per the PRD's "harness substrate changes" exclusion and is captured in the consequences section as future work.

### Phase E — Forward-looking note in pattern reference

Already included in Phase A's contract-section closing paragraph (Decision 6). No separate edit.

The PRD specifies that this DESIGN's downstream /plan will decompose Phase A-C into atomic issues. The phases above are the implementation ordering, not the issue boundaries.

## Security Considerations

The contract is documentation reconciliation; it introduces no new code paths, no new state-file fields, and no new external interfaces. The security surface analysis covers three angles:

**Dispatch primitive surface.** Inline Skill-tool invocation has the same security properties as a user typing the child's slash command directly — the child runs in the parent's agent context with the same tool allowlist. The contract does not widen the tool allowlist; it does not grant the parent privileged access to the child's internals. R14 child-isolation is preserved (the parent reads only the durable artifact path and frontmatter, never child wip/).

**Declarator format surface.** The fenced YAML block is markdown content under a SKILL.md heading. It is not code; it is parsed by a future validator (Phase D) that lives in shirabe and runs against the same trust boundary as the rest of `shirabe validate`. No external input flows into the YAML parser; the declarations are author-written and committed to the repo.

**Pre-dispatch state surface.** The `parent_orchestration:` block was already named in the pattern; the contract section codifies its role but does not add fields. The block is read by children at their Phase 0 (existing behavior) and cleared by the parent at Phase 2 end (existing behavior).

**Outcome.** No new security risks identified. The contract documents an existing dispatch shape and codifies an existing declaration practice; the security surface is unchanged from v1.

## Consequences

### Positive

- **Single mechanism reading replaces three.** Orchestrators reading the docs cold reach one answer to "which harness primitive carries the dispatch?" — the Skill tool, called inline. AC18 / AC19 / AC20 are satisfied.
- **R14 child-isolation strengthened, not weakened.** The contract makes explicit that the parent owns no view into the child's team. Today's prose is silent on this; the new section says it.
- **R19/I-7 binding clarified.** The discipline binds inside whichever skill spawns a team. For single-agent parents (`/scope`, `/charter`), that means inside the child. For team-emitting children (`/prd`, `/design`, etc.), that means against the child's own jury. The discipline's content does not change.
- **Amplifier-layer migration path preserved.** The four contract elements are Layer 1; the Skill-tool primitive and the YAML schema are Layer 2. When the amplifier substrate ships, only the Layer-2 binding changes; the contract elements stay.
- **Children's existing team behavior codified.** Every child that runs a jury today already constructs its own team. The contract names this practice rather than introducing it.
- **Layer-collision question resolved for issue #150.** Issue #150 proposed parent-constructs-team-per-child; the contract rejects that reading explicitly, with the substrate constraint as the reason.

### Negative

- **R19 Binding Notes wording changes.** The current `/charter` Binding Notes describe R19 as binding at the child-skill-dispatch layer; the new text describes R19 as binding inside the child. Reviewers familiar with the current wording need to re-read. Mitigation: the discipline's content is unchanged; only the layer-description is updated.
- **Seven children take an edit.** Migration is one section addition per child. Mitigation: the edits are mechanical and independent.
- **Empty-team children carry a slightly heavier declaration.** A `## Team Shape` section with two empty lists is more visual weight than a one-line "no team" sentence. Mitigation: the explicit-no-team branch satisfies R3 grep-checkably; the visual weight is a one-time cost per child.

### Mitigations

- **Validator extension deferred.** Phase D's validator extension is captured as future work; until it ships, the YAML block's schema conformance relies on author / reviewer discipline. Grep-checking the heading and the fence is sufficient for AC7.
- **In-flight-run forward-looking note.** Existing runs continue to work because the contract codifies their current dispatch shape (the runs already use inline Skill-tool dispatch in practice; the contract just names it). The R11 note exists for completeness, not because in-flight runs would actually break.

## References

- Upstream PRD: `docs/prds/PRD-shirabe-child-dispatch-contract.md`.
- Upstream BRIEF: `docs/briefs/BRIEF-shirabe-child-dispatch-contract.md`.
- Pattern source the contract reconciles: `references/parent-skill-pattern.md` (Team-Shape Declarator section, Team-Lead Operating Discipline / I-7 section, Named Substitution Surfaces).
- Pattern companion: `references/parent-skill-state-schema.md` (`parent_orchestration:` block schema).
- Tactical-chain parent: `skills/scope/SKILL.md` (Team Shape section, Phase 2 reference in `skills/scope/references/phases/phase-2-chain-orchestration.md`).
- Strategic-chain parent: `skills/charter/SKILL.md` (Team Shape section, Phase 2 reference in `skills/charter/references/phases/phase-2-chain-orchestration.md`).
- Children migrated: `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`, `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md`.
- Upstream conversation: GitHub issue `tsukumogami/shirabe#150` ("docs(scope): clarify that /scope spawns a TeamCreate-backed team per child dispatch") — the issue's suggested-fix wording is rejected by this DESIGN; the correct framing is documented in Decision 3.
