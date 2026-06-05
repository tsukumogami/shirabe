---
schema: design/v1
status: Current
upstream: docs/prds/PRD-shirabe-child-dispatch-contract.md
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
  child's team shape as a declared shape that exists as a contract
  surface (file at well-known path; fixed schema) but is NOT
  parsed by the parent at dispatch time in v1. Encode the child's
  team-shape declaration as a dedicated `team.yaml` file at the
  well-known per-skill location `skills/<name>/team.yaml`, where
  reviewers, the future Phase D validator, and the future
  amplifier-layer substrate can load ~10 lines of YAML rather than
  scanning the child's full SKILL.md. Construct the team (when one
  exists) at the child-dispatch layer, owned by the child itself;
  the parent owns no team. Land a single Dispatch Contract section
  in `references/parent-skill-pattern.md` between Team-Shape
  Declarator and Required SKILL.md Structural Elements, with five
  labelled sub-elements (mechanism, pre-dispatch state, observability
  surface, hand-back, child-team-shape-declaration). Propagate
  verbatim cross-references from both parent SKILL.mds. The Phase 2
  cross-references are asymmetric by parent structure: /scope's
  single `## Child Invocation` section gets one cross-reference;
  /charter's four per-child Invocation Rule sections each get one.
  All seven child SKILL.mds gain a brief `## Team Shape` section
  pointing at the sibling team.yaml.
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
  own. The dedicated team.yaml declarator beats prose
  (grep-anchorable, schema-validatable), frontmatter (children
  already use frontmatter for plugin metadata; a `team:` key would
  collide with the skill plugin loader), and embedded markdown
  (forces parents to load the child's full SKILL.md to read ~10
  lines of structured contract). Child-owned construction preserves
  R14 child-isolation: the parent reads the declaration but never
  materializes peers, so the child remains the team's sole
  parent-of-the-parent. The Layer-1 / Layer-2 split is preserved
  by labelling the YAML schema and the Skill-tool primitive as
  Layer 2, with the four contract elements as Layer 1.
spawned_from:
  issue: 150
  repo: tsukumogami/shirabe
  parent_design: docs/prds/PRD-shirabe-child-dispatch-contract.md
---

# DESIGN: shirabe-child-dispatch-contract

## Status

Current

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

### Decision 1: Dispatch Mechanism

The question: which harness primitive carries each child invocation?

#### Chosen: 1C — Inline Skill-tool invocation

The parent calls the Skill tool directly with the child's name and the topic slug, the same way a user typing `/<child> <topic>` would. The child runs in the parent's own agent context; the child's own team-construction (juries, decision-researchers) is the child's responsibility and happens at the child layer, not at the parent layer.

- *Pros:* The literal reading of Phase 2's "the child's existing input mode." Compatible with `team_primitive: single-team-per-leader-no-nested` — the parent owns no team; the child owns its own team. R14 child-isolation is preserved because the parent reads only the child's durable artifact path, never the child's internal team coordination. The R19 discipline binds at the child layer (the child runs the discipline against its own peers) not at the parent layer (the parent runs no team-lead loop at all — there is no team to lead).
- *Cons:* Requires re-interpreting the R19 binding for `/scope` and `/charter`. Today, `/scope`'s Team Shape section says R19 binds at the child-skill-dispatch layer, which gestures at parent-runs-team-lead-against-child. Under 1C, R19 binds inside the child against the child's own peers, and the parent's role is the synchronous Skill-tool caller. The Binding Notes section in the pattern reference (which today describes `/charter` as having a vacuous parent-layer binding and a concrete child-dispatch binding) needs rewording to reflect that R19 binds inside the child, not across the dispatch.

The substrate is the forcing function: only inline Skill-tool dispatch matches `single-team-per-leader-no-nested`. The R19 reinterpretation is a wording change, not a discipline change — the sleep-check-nudge loop runs inside whichever skill spawns a team, which is the child, not the parent. The author's intent in the run that surfaced #150 matches 1C: the parent stays single-agent, the child runs its own discipline.

#### Alternatives Considered

- **Option 1A — TeamCreate-backed team per child dispatch.** The parent calls `TeamCreate` to spawn a team for each child invocation. The team has a coordinator (the child) and peers materialized from the child's declared team shape. The parent dispatches via `SendMessage` to the coordinator. *Pros:* Matches the R19/I-7 discipline's asynchronous shape literally; the parent has structured messages to inbox-process; the team-lead discipline reads against a real team boundary. *Cons:* Violates `team_primitive: single-team-per-leader-no-nested` when the child itself runs a jury (`/prd`, `/design`, `/brief`, `/strategy`, `/roadmap`, `/vision`). The child's jury would be a nested team inside the dispatch team. The substrate forbids this in v1. Also: the parent now owns the team it dispatched to, which breaks R14 child-isolation — the parent would see the child's peers' inbox messages and partial artifacts. Rejected because the substrate constraint is hard.

- **Option 1B — Single general-purpose sub-agent per child dispatch.** The parent spawns one sub-agent via the Agent tool. The sub-agent runs the child invocation. The parent monitors the sub-agent via `run_in_background` polling. *Pros:* Matches the R19 sleep-check-nudge loop in shape; lets the parent run as single-agent at its own layer. *Cons:* The sub-agent is itself a parent-of-the-team-the-child-creates. When the child runs a jury, that jury is nested inside the dispatched sub-agent — the same `single-team-per-leader-no-nested` violation 1A hits, dressed differently. Worse, the parent's filesystem-evidence check now reads against a layer (the sub-agent's filesystem) the parent does not own; this is what triggered the run that surfaced #150 — the author flagged the dispatch as not matching intent because the sub-agent's filesystem state was opaque to the parent. Rejected because the "single sub-agent" compromise is the silent reading that broke the original run.

- **Option 1D — Shape-dependent: parent reads the child's declared shape and constructs the matching primitive.** The user's hypothesis. The parent inspects the child's team-shape declaration; if the declaration names peers, the parent constructs a team; if not, the parent calls inline. *Pros:* Matches the intuition that "the contract reads the inner skill's declared shape." Lets simple children stay simple and complex children get teams. *Cons:* Reintroduces the 1A violation for any child that itself runs a jury — the parent-constructed team plus the child-run jury equals a nested team. The "shape-dependent" framing also conflates two concerns: the dispatch primitive (how the parent calls the child) and the team-construction layer (which agent materializes the child's peers). Decision 3 below settles the team-construction layer separately; conflating it here makes the contract harder to read. Finally, "shape-dependent" is already a gate-vocabulary term in the pattern (see `## Gate Vocabulary` in the pattern reference, where "shape-dependent" describes a gate whose sub-shape is upstream-recorded). Reusing the term for dispatch-mechanism choice would overload it. Rejected because the intuition the option captures is real but is the wrong altitude: the parent SHOULD read the child's declared shape (this is what AC7 requires) but the reading does not change the dispatch primitive; it informs *who* constructs the team (the child, per Decision 3 below).

### Decision 2: Declarator Format

The question: how does each of the seven children declare its team shape so the parent can read it?

#### Chosen: 2E — Dedicated `team.yaml` file at `skills/<name>/team.yaml`

Each child gets a new file at `skills/<name>/team.yaml` containing the structured YAML declaration. The file is the contract surface; SKILL.md retains a brief `## Team Shape` prose section that cross-references `team.yaml` as the source of truth.

- *Pros:* Minimum-context-load by design: a reader (human, future-substrate, future-validator, future-amplifier-layer parent) loads ~10 lines of YAML rather than a 300-700-line SKILL.md to learn the team shape. The file IS the contract — its path is the well-known location, its content is the declaration. Glob-checkable for presence (`ls skills/*/team.yaml` returns seven files) rather than grep-checkable across mixed markdown bodies. Schema validation is trivial (parse the YAML file directly; no markdown extraction). Separates two distinct readers cleanly: `team.yaml` is machine-readable contract; SKILL.md is human-readable operating manual for the child agent. Amplifier-layer migration is a no-op — the substrate already has a YAML file to parse; no new file format introduced. The file's path under `skills/<name>/` matches shirabe's existing per-skill organization (`SKILL.md`, `references/`, `scripts/`, `evals/` siblings).
- *Cons:* Two files to keep consistent per skill (the `team.yaml` declares the shape; SKILL.md prose may reference it). Mitigation: a future shirabe validator check (Phase D) can verify the SKILL.md `## Team Shape` section references `team.yaml` and that the declared shape matches actual team construction at runtime. Slightly more migration work (create 7 new files vs add 7 headings) but each file is ~10 lines and the work is per-skill independent.

The contract surface is a file at a path — clean, machine-readable, minimum-context-by-construction, and matches the user's stated principle: "the team lead loads in its context the minimum amount of info about the skill it's about to launch." See "v1 runtime read semantics" note below for the v1-vs-v2 read distinction.

**v1 runtime read semantics.** In v1, the parent does NOT parse `team.yaml` at dispatch time. The substrate has no team.yaml parser; Decision 1's inline Skill-tool mechanism passes the topic-slug argument and nothing else. The file is consumed in v1 by: (a) reviewers reading the declaration to verify it matches the child's actual peer roster, (b) the Phase D validator extension when it ships, and (c) the future amplifier-layer substrate when it ships TeamCreate semantics. The "minimum-context-load" framing is forward-looking — when those readers materialize, they load the file's ~10 lines rather than the child's full SKILL.md. The contract surface (file at path) exists in v1; the runtime read is a v2 binding under `team_primitive`'s Layer-2 substitution.

The exact schema (identical for 2D and 2E; only the location differs):

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

The SKILL.md `## Team Shape` section retains a brief prose description (one or two sentences naming the team's purpose and pointing at the file) so a child-agent reader of SKILL.md still sees the team mentioned in-line. The cross-reference text: "See [`team.yaml`](./team.yaml) for the machine-readable team-shape declaration. v1 parent skills (`/scope`, `/charter`) do not parse this file at dispatch time; it is consumed by reviewers, the Phase D validator extension, and the future amplifier-layer substrate."

#### Alternatives Considered

- **Option 2A — Prose subsection under a `## Team Shape` heading.** Each child gets a `## Team Shape` heading with free-form prose describing peers. *Pros:* Zero new validation infrastructure; matches the v1 prose-declarator form the parent-skill-pattern already calls out. *Cons:* Not mechanically parseable. The PRD's R3 requires the declaration to distinguish reviewer-shaped roles from variable-cardinality worker role types and to name an upper bound for variable-cardinality. Prose cannot be grep-checked for those distinctions; a reviewer evaluating compliance would need to read prose against intent. AC9 (upper bound named) becomes a judgment call. *Verdict:* Rejected. R3's structural distinctions need a structural format.

- **Option 2B — Structured YAML in SKILL.md frontmatter.** Add a `team:` top-level key to the child's SKILL.md frontmatter with a nested schema for peers, roles, cardinality, upper bound. *Pros:* Frontmatter is the most schema-validated surface in shirabe; existing artifact validators already parse it. *Cons:* Children's SKILL.md frontmatter today does not follow the artifact schema/v1 convention — SKILL.md files have plugin-format frontmatter (`name`, `description`), not artifact frontmatter. Adding a `team:` key to that frontmatter risks collisions with the plugin loader's parser and with future skill-marketplace metadata. Worse, the artifact validators that already parse `schema:` and `status:` would attempt to validate the `team:` block against schemas that do not apply to SKILL.md files. *Verdict:* Rejected. The frontmatter surface is wrong: SKILL.md frontmatter is for plugin metadata, not for content schemas.

- **Option 2C — Structured markdown table under `## Team Shape`.** Each child gets a `## Team Shape` heading with a fixed-column markdown table (Role, Cardinality, Upper Bound, Notes). *Pros:* Tables are grep-anchorable by column headers and human-readable. *Cons:* Tables are brittle to wrap, hard to extend without breaking column alignment, and a poor fit for nested data (a role with multiple notes-of-notes). The amplifier-layer migration to structured metadata (as the pattern reference's Team-Shape Declarator section anticipates) would require re-encoding tables as YAML anyway. *Verdict:* Rejected. Tables are a halfway house between prose and YAML; the amplifier-layer migration path makes the halfway position more expensive than going straight to YAML.

- **Option 2D — Fenced YAML block under `## Team Shape` in SKILL.md body.** Each child has a `## Team Shape` heading whose body contains a fenced YAML code block following a fixed schema. The schema's top-level keys: `parent_layer:` (peers materialized at parent-of-parent time, almost always empty), `child_layer:` (peers spawned inside the child, with role types and cardinality). *Pros:* YAML is the schema language the pattern already uses for state files. Grep-anchorable on the heading and on the fence (` ```yaml `). Schema-validatable via a separate validator pass without coupling to SKILL.md frontmatter. Distinguishes reviewer-shaped roles from variable-cardinality worker role types via explicit `cardinality:` and `upper_bound:` fields, satisfying R3 / AC8 / AC9 grep-checkably. *Cons:* Forces the parent to load the entire child SKILL.md into context to read ~10 lines of structured declaration. Today's SKILL.md files are 300-700 lines each; the team declaration is a fraction of a percent of that surface. Loading the whole file violates R3's "loads only the team-shape information into context" principle. Schema validation requires extracting YAML from a markdown fence, an extra parse step the substrate doesn't need anywhere else. Mixing the contract surface (machine-read by the parent) with the operating manual (read by the child agent at invocation time) couples two distinct readers to one file. *Verdict:* Rejected on reconsideration. The minimum-context-load principle (added to R3 during the DESIGN-Accepted re-review) makes the embedded-in-SKILL.md location wrong. The earlier verdict that "2D is already in the destination shape" for amplifier-layer migration is true but undersells the cost — every parent reading the declaration today eats the cost.

### Decision 3: Team-Construction Layer

The question: when a child has peers, who constructs the team — the parent (the `/scope` or `/charter` coordination layer), or the child itself?

#### Chosen: 3C — Child-layer team construction

The parent calls the Skill tool inline (per Decision 1's 1C). The child reads its own team-shape declaration during its Phase 0; if the declaration names peers, the child calls TeamCreate at its own layer (matching today's behavior — `/prd`'s Phase 4 jury, `/design`'s Phase 2 decision-researchers, etc.). The parent owns no team.

- *Pros:* Compatible with `single-team-per-leader-no-nested` (only one team exists at a time — the child's). Preserves R14 child-isolation (the parent has no view into the child's team). Matches the actual runtime behavior of `/prd`, `/design`, `/brief`, `/strategy`, `/roadmap`, `/vision` today — those children already construct their own juries; this decision codifies it. Lets the parent's Team Shape section honestly say "single-agent, no team" because that is what the parent actually does.
- *Cons:* The R19 discipline binding moves. Today's `/scope` Team Shape section says R19 binds at the child-skill-dispatch layer; under 3C it binds inside the child against the child's own peers. The Binding Notes section in the pattern reference needs to be reworded. (This is the same wording change Decision 1 already requires.)

This resolves issue #150's "Reading 1 vs Reading 2" question explicitly: Reading 2 (parent constructs the team) is rejected; Reading 1 (child constructs its own team if any) is the contract. The issue's suggested-fix title ("/scope spawns a TeamCreate-backed team per child dispatch") is wrong as stated; the correct framing is "/scope invokes the child inline; the child spawns its own team if it has one."

#### Alternatives Considered

- **Option 3A — Parent constructs the team for the whole chain (one team spans all children).** `/scope` constructs a team at chain start with peers covering all child-emitted roles; the coordinator dispatches each child as a phase. *Pros:* Single team spans the chain; teardown is once per chain run. *Cons:* Violates `team_primitive: single-team-per-leader-no-nested` because the parent now owns a team while children spawn juries inside that team. The upper-bound-roster declared at team-creation time would need to span every possible role across all four children — `/brief`'s 2 reviewers, `/prd`'s 3 jurors, `/design`'s N decision-researchers, `/plan`'s decomposers — turning the parent's Team Shape section into a transitive declaration of every descendant's team needs. R14 child-isolation breaks: the parent sees the peers the child dispatches. *Verdict:* Rejected.

- **Option 3B — Parent constructs a fresh team per child dispatch.** `/scope` calls TeamCreate per child invocation; the team's roster matches the child's declaration; the team is torn down after the child returns. *Pros:* Smaller blast radius than 3A; the parent's roster declaration stays per-child. *Cons:* Same nested-team violation as Decision 1's option 1A. The child's internal jury (when it has one) becomes a nested team inside the parent's per-child team. *Verdict:* Rejected.

### Decision 4: Per-Parent Override Slot in v1 (PRD D5(a))

The question: should the contract introduce a named override slot in `/scope`'s and `/charter`'s SKILL.md files for per-parent dispatch-behavior overrides?

#### Chosen: No override slot in v1

The contract section in the pattern reference includes a one-sentence note: "v1 has no per-parent overrides; the contract applies verbatim to both parents." When `/work-on` migrates and an override is genuinely needed, the slot is introduced at that point with the override's content as the forcing function. AC14's "absence is explicit" branch is satisfied.

- *Cons:* AC13 requires the contract-relevant passages to differ only in child names and topic-slug placeholders. An override slot that exists but is empty in v1 is a maintenance attractor — reviewers debate what should go in it; future contributors fill it for the wrong reasons.

#### Alternatives Considered

- **Introduce a named override slot in v1.** *Pros:* Future-proof; if a third parent (e.g., `/work-on`) needs to override a contract element, the slot already exists. *Verdict:* Rejected. The slot would be empty in v1 and become a maintenance attractor; AC13 requires the contract-relevant passages to differ only in child names and topic-slug placeholders.

### Decision 5: Declarator Format Granularity (PRD D5(b))

The question: granularity of the declarator schema — every field optional, fields constrained, or fields required?

#### Chosen: Mixed strictness

`parent_layer.peers` and `child_layer.peers` are required lists (may be empty). When a peer is declared, `role`, `cardinality`, `phase`, `purpose` are required; `upper_bound` is required iff `cardinality: worker`. An empty-team child declares two empty lists; this is the explicit "no team" branch that satisfies R3. Field-value vocabularies are fixed at contract-section time:

- `role`: kebab-case string ending in `-reviewer` for reviewer cardinality or matching the worker role-type name (e.g., `decision-researcher`, `decomposer`).
- `cardinality`: enum, exactly `reviewer` or `worker`.
- `upper_bound`: positive integer when `cardinality: worker`; absent when `cardinality: reviewer`.
- `phase`: kebab-case slug matching the child's phase reference filename without extension (e.g., `phase-4-validate`, `phase-2-execution`, `phase-6-final-review`). The phase slug is grep-checkable against `skills/<name>/references/phases/<phase>.md`; an invalid phase slug fails the validator extension when it ships (Phase D).
- `purpose`: free-text one-line description.

#### Alternatives Considered

- **Permissive (every field optional).** *Pros:* Lower migration burden. *Verdict:* Rejected. Defeats grep-checking; AC8 / AC9 become unverifiable.

- **Strict (every field required).** *Pros:* Maximum grep-checkability. *Verdict:* Rejected. Produces vacuous fields for empty teams; `upper_bound` makes no sense for reviewer cardinality.

### Decision 6: Forward-Looking Note Placement (PRD D5(c))

The question: where does R11's forward-looking note ("the contract applies to chain runs initiated after the contract lands; existing in-flight runs are not retroactively re-shaped") live?

#### Chosen: In the contract section itself as a closing sentence

Place the note in the contract section itself as a closing sentence after the four elements. AC17 is satisfied with one grep target rather than three. The parents' SKILL.md cross-references inherit the note via the cross-reference.

- *Pros:* One-stop reading; a reader who finds the contract section finds the scope boundary in the same place.

#### Alternatives Considered

- **Place the note in a separate scope sub-section.** *Pros:* Lets the contract section stay focused on the four elements. *Verdict:* Rejected. Splits the scope boundary from the four contract elements, requiring a second grep target.

- **Place the note in parent SKILL.md files.** *Pros:* Closest to where in-flight-run authors would look. *Verdict:* Rejected. Forces both parents to carry duplicate prose, violating AC13's symmetric-wording requirement.

## Decision Outcome

The DESIGN binds the dispatch mechanism to **inline Skill-tool invocation** (Decision 1's 1C), the child-side declarator format to a **dedicated `skills/<name>/team.yaml` file** (Decision 2's 2E), and team construction to **the child layer** (Decision 3's 3C). The three decisions reinforce each other: 1C requires the parent to own no team; 2E gives any reader (human reviewer, Phase D validator, future amplifier-layer substrate) a minimum-context, machine-readable declaration without forcing them to scan the child's full operating manual; 3C places team construction with the entity that has the substrate to construct it. The four PRD-required contract elements (R2.1-R2.4) become four labelled sub-sections under a single new `## Dispatch Contract` heading in `references/parent-skill-pattern.md`, plus a fifth Child Team-Shape Declaration sub-section naming the `skills/*/team.yaml` glob marker.

In v1, the parent does NOT parse `team.yaml` at dispatch time — Decision 1's inline Skill-tool mechanism passes only the topic-slug argument; the substrate has no team.yaml parser yet. The file is consumed by reviewers and the future amplifier-layer substrate. The contract surface (file at well-known path; fixed schema; glob-checkable presence) exists in v1; the runtime read is a v2 binding under `team_primitive`'s Layer-2 substitution.

The combination is the only one consistent with v1's `team_primitive: single-team-per-leader-no-nested`. The alternatives all fail at the substrate level: TeamCreate per child (1A) and parent-constructed teams (3A/3B) violate no-nested; single sub-agent per child (1B) hides team state behind an opaque layer the parent does not own. Inline Skill-tool plus dedicated-file declarator plus child-owned construction lets the parent stay honestly single-agent, lets the parent read a minimum-context contract surface, and lets the child run its own R19 discipline against its own peers — which is what every existing jury-running child already does.

The Layer-1 / Layer-2 split is preserved: the four contract elements are Layer 1 (substrate-agnostic — every future substrate names a mechanism, a pre-dispatch state, an observability surface, and a hand-back). The specific bindings (the Skill tool, the dedicated `team.yaml` file path, the YAML schema, the wip/state.md path) are Layer 2 (substrate-bound — replaceable when the amplifier layer ships).

## Solution Architecture

### Component 1 — The `## Dispatch Contract` section in `references/parent-skill-pattern.md`

A single new top-level section, placed between the end of `## Team-Shape Declarator` (the section spans approximately lines 250-298 of the current `references/parent-skill-pattern.md`) and the start of `## Required SKILL.md Structural Elements` (line 300). The placement matches the natural flow: declarator (how children describe their shape) -> dispatch contract (how the parent reads the shape and invokes the child) -> structural elements (what SKILL.md must contain). The `## Team-Lead Operating Discipline` section (line 334) cites the new contract section but is NOT adjacent to it — the frontmatter's prior wording "between Team-Shape Declarator and Team-Lead Operating Discipline" was imprecise and is corrected here to "between Team-Shape Declarator and Required SKILL.md Structural Elements."

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

[Enumerates the four pre-dispatch state elements:
1. parent_orchestration: sentinel block (invoking_child,
   suppress_status_aware_prompt, rationale).
2. Worktree-staleness gate output (rebase impact classification:
   None / Informational / Intent-changing-resolved-in-place).
3. State-file fields written before dispatch (planned_chain
   advance, last_updated bump, pre_invocation_sha capture).
4. Child-side team-shape declaration glob marker
   (skills/<name>/team.yaml exists with valid schema).
Cross-references parent-skill-state-schema.md.]

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

### Child Team-Shape Declaration

[Names the glob marker as part of the contract: each child SHALL
declare its team shape at the well-known path
`skills/<name>/team.yaml`. The file follows the YAML schema in
Decision 2's body. A parent SHALL be able to enumerate every
child's team shape via the glob `skills/*/team.yaml` returning
N files where N equals the count of in-pattern child skills.
v1 NOTE: the parent does NOT parse team.yaml at runtime — the
declaration is documentation and future-substrate-ready data,
read by reviewers and the future amplifier-layer substrate;
v1's substrate does not yet consume the file mechanically. The
glob check is the contract surface.]

[Closing paragraph — Layer-1 / Layer-2 label, no-per-parent-
override-in-v1 statement, forward-looking note (R11).]
```

Total section length: approximately 110 lines (matches the section-density of the surrounding pattern reference).

### Component 2 — Child team-shape declarations

Every one of `skills/brief/`, `skills/prd/`, `skills/design/`, `skills/plan/`, `skills/vision/`, `skills/strategy/`, `skills/roadmap/` gets a NEW file `team.yaml` at the skill directory root, containing the schema per Decision 2's 2E. The child's existing SKILL.md gets a brief `## Team Shape` section (one or two sentences naming the team's purpose) that cross-references the sibling `team.yaml` as the machine-readable source of truth.

Two separate edits per child:
1. **Create `skills/<name>/team.yaml`** — the structured declaration the parent reads at dispatch time. ~10 lines per file.
2. **Add `## Team Shape` section to SKILL.md** — short prose pointer: "This skill's team shape is declared in [`team.yaml`](./team.yaml), read by parent skills (`/scope`, `/charter`) at dispatch time. [One sentence summary of what's in it.]"

The migration table below names what each child's `team.yaml` content looks like, derived by reading each child's actual phase reference files (`skills/<name>/references/phases/`). Every role-name and phase-slug in the table is grounded in a specific source file cited in parentheses; nothing is invented. Phase slugs follow the controlled vocabulary `phase-N-<name>` derived from each child's phase reference filename (e.g., `phase-4-validate`).

| Child | parent_layer.peers | child_layer.peers |
|---|---|---|
| `/brief` | `[]` | `content-quality-reviewer` (reviewer, phase-4-validate, "evaluates Problem Statement / User Outcome / Journeys / Scope Boundary quality"); `structural-format-reviewer` (reviewer, phase-4-validate, "verifies schema, heading, and format conformance") — source: `skills/brief/references/phases/phase-4-validate.md` |
| `/prd` | `[]` | `completeness-reviewer` (reviewer, phase-4-validate, "finds gaps in requirements vs problem statement"); `clarity-reviewer` (reviewer, phase-4-validate, "evaluates wording and unambiguity"); `testability-reviewer` (reviewer, phase-4-validate, "evaluates AC verifiability") — source: `skills/prd/references/phases/phase-4-validate.md` |
| `/design` | `[]` | `decision-researcher` (worker, upper_bound: 9, phase-2-execution, "walks the decision protocol per pending architectural question") — source: `skills/design/references/phases/phase-2-execution.md`; canonical upper_bound 9 per `docs/designs/current/DESIGN-shirabe-progression-authoring.md:1192`. `security-researcher` (reviewer, phase-5-security, "investigates security implications of the chosen architecture") — source: `skills/design/references/phases/phase-5-security.md`. `architecture-reviewer` (reviewer, phase-6-final-review, "evaluates structural integrity of the final DESIGN"); `security-reviewer` (reviewer, phase-6-final-review, "evaluates security posture of the final DESIGN") — source: `skills/design/references/phases/phase-6-final-review.md` |
| `/plan` | `[]` | `decomposer` (worker, upper_bound: 20, phase-4-agent-generation, "generates an issue body per outline from Phase 3; runtime count equals the issue count emitted by Phase 3, capped at the upper bound") — source: `skills/plan/references/phases/phase-4-agent-generation.md`. `/plan` Phase 6 invokes `/review-plan` as a sub-skill via inline Skill-tool dispatch, which is a CHILD invocation (Decision 1's contract surface), NOT a peer; it is excluded from `child_layer.peers`. |
| `/vision` | `[]` | `thesis-quality-reviewer` (reviewer, phase-4-validate, "evaluates whether the thesis is a falsifiable bet"); `content-boundary-reviewer` (reviewer, phase-4-validate, "evaluates audience and value-proposition framing"); `section-guidance-reviewer` (reviewer, phase-4-validate, "evaluates structural conformance to vision-format.md") — source: `skills/vision/references/phases/phase-4-validate.md` |
| `/strategy` | `[]` | `bet-quality-reviewer` (reviewer, phase-4-validate, "evaluates whether the strategy names a falsifiable bet"); `altitude-reviewer` (reviewer, phase-4-validate, "evaluates altitude band conformance"); `structural-format-reviewer` (reviewer, phase-4-validate, "evaluates structural conformance to strategy-format.md") — source: `skills/strategy/references/phases/phase-4-validate.md` |
| `/roadmap` | `[]` | `theme-coherence-reviewer` (reviewer, phase-4-validate, "evaluates whether features belong under one theme"); `sequencing-and-dependency-reviewer` (reviewer, phase-4-validate, "evaluates dependency graph between features"); `annotation-and-boundary-reviewer` (reviewer, phase-4-validate, "evaluates per-feature annotations and roadmap scope boundary") — source: `skills/roadmap/references/phases/phase-4-validate.md` |

All seven have `parent_layer.peers: []` — consistent with Decision 3 (the parent constructs no team). The `child_layer.peers` list captures what the child actually spawns today via existing substrate primitives (Agent tool / Task agent with `run_in_background: true`); the declaration codifies existing behavior at the SHAPE layer per the Team-Shape Declarator section's "shape declaration is contract; spawn timing is substrate-specific" distinction.

**Substrate note.** Today's children dispatch peers via the Agent tool or Task primitive with `run_in_background: true`, not via TeamCreate. The Team-Shape Declarator section treats this as peer materialization in shape-vocabulary terms (the shape is the role roster; the substrate is how the roster gets realized). When the amplifier-layer ships TeamCreate semantics, the SAME team.yaml declarations become the input to TeamCreate calls without re-authoring; only the substrate's spawning step changes.

### Component 3 — Parent cross-references

`/scope` SKILL.md and `/charter` SKILL.md each get:

1. **Updated `## Team Shape` section.** Existing prose is preserved (the parent runs single-agent at its own layer); a new closing sentence cross-references the new `## Dispatch Contract` section as the source of the dispatch mechanism. The cross-reference uses the `${CLAUDE_PLUGIN_ROOT}/references/...` form to match the idiom both parent SKILL.md files already use throughout: "See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation." The relative `../../references/...` form is NOT used because every existing cross-reference in `skills/scope/SKILL.md` and `skills/charter/SKILL.md` already resolves the pattern reference through `${CLAUDE_PLUGIN_ROOT}` (verified at `skills/scope/SKILL.md:33, 51, 154, 187, 273-278` and `skills/charter/SKILL.md:27, 40, 105, 141, 206-211`).

2. **No body changes to other sections.** The Phase 2 reference is updated separately (Component 4); other sections are unaffected.

The cross-reference text is verbatim between the two parents, satisfying AC10 and AC13.

### Component 4 — Phase 2 cross-references (asymmetric)

The two parents' Phase 2 references have asymmetric structures, so the cross-references land in different sections — but the cross-reference TEXT is identical.

**`/scope`'s Phase 2 reference** (`skills/scope/references/phases/phase-2-chain-orchestration.md`) has a single `## Child Invocation` section (line 124) that handles all four children uniformly. The cross-reference lands once in that section.

**`/charter`'s Phase 2 reference** (`skills/charter/references/phases/phase-2-chain-orchestration.md`) has per-child `## /<name> Invocation Rule (RN)` sections — `## /vision Invocation Rule (R4)`, `## /comp Invocation Rule (R5 + R12)`, `## /strategy Invocation Rule (R6)`, `## /roadmap Invocation Rule (R7)`. The cross-reference lands in each of those four sections (one cross-reference per child), pointing at the same `## Dispatch Contract` section.

The asymmetry preserves /charter's existing per-child rule structure (which encodes per-child conditional invocation logic; `/scope`'s children are unconditionally ordered) while still landing the cross-reference at every child-invocation point. AC13's "symmetric wording" requirement is satisfied because the cross-reference TEXT is identical across all five attachment points (one in /scope's Child Invocation, four in /charter's per-child Invocation Rules); only the location differs by parent structure.

Today's "Phase 2 invokes the child via the child's existing input mode: `/<child-name> <topic-slug>`" wording in /scope's `## Child Invocation` section is preserved AND a leading sentence cross-references the `## Dispatch Contract` section in the pattern reference as the source of the dispatch mechanism. The /charter per-child Invocation Rules each get a leading sentence with the same cross-reference. Existing wording is preserved across all five attachment points.

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
         +-- Phase 4: spawn 2 reviewers in parallel        <-- child owns this team
             (via Agent tool with run_in_background: true;
              future amplifier-layer substrate replaces this
              with TeamCreate. The peer SHAPE — 2 reviewers,
              one content-quality and one structural-format —
              is declared in skills/brief/team.yaml and is
              substrate-agnostic.)
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

1. Add `## Dispatch Contract` section to `references/parent-skill-pattern.md` with the five sub-sections specified in Component 1 (Dispatch Mechanism, Pre-Dispatch State, Observability Surface, Hand-Back Contract, Child Team-Shape Declaration).
2. Reword `### Binding Notes for /charter` and add `### Binding Notes for /scope`.
3. Annotate `references/parent-skill-state-schema.md`.

This is one atomic edit to the pattern reference. After this phase, the contract section exists and is the single source of truth, but the parents and children do not yet cross-reference it. The pattern reference is internally consistent; the surrounding skills temporarily appear inconsistent (they still describe the dispatch as scattered passages). This phase deliberately ships before the parents are updated, so the cross-reference target exists when the parents are updated.

### Phase B — Update parent SKILL.md and Phase 2 cross-references (asymmetric)

1. Update `skills/scope/SKILL.md` `## Team Shape` section — add cross-reference to the new `## Dispatch Contract` section.
2. Update `skills/charter/SKILL.md` `## Team Shape` section — same cross-reference text.
3. Update `skills/scope/references/phases/phase-2-chain-orchestration.md` `## Child Invocation` section (single attachment point) — add leading cross-reference.
4. Update `skills/charter/references/phases/phase-2-chain-orchestration.md` per-child Invocation Rule sections (four attachment points: `## /vision Invocation Rule (R4)`, `## /comp Invocation Rule (R5 + R12)`, `## /strategy Invocation Rule (R6)`, `## /roadmap Invocation Rule (R7)`) — each gets the same cross-reference text.

The cross-reference TEXT is identical across all five attachment points (one in /scope's Child Invocation, four in /charter's per-child rules); only the location differs by the parents' structural asymmetry. AC10, AC11, AC13 are verified by grepping the cross-reference text appears at all five attachment points.

### Phase C — Migrate child team-shape declarations

Seven children. For each child: (1) create `skills/<name>/team.yaml` with the schema-conformant declaration from Component 2's verified migration table; (2) add a brief `## Team Shape` section to `skills/<name>/SKILL.md` pointing at `team.yaml`. The order does not matter; the changes are independent. After this phase, AC7, AC8, AC9 are verified (glob `skills/*/team.yaml` returns exactly seven files; each file parses as valid YAML against the Decision 5 vocabulary).

### Phase D — Validator extension (deferred)

`shirabe validate` learns to (a) parse `skills/<name>/team.yaml` files, (b) check schema conformance against the Decision 5 vocabulary, (c) verify the SKILL.md `## Team Shape` section's cross-reference to `team.yaml` resolves, and (d) optionally verify the declared shape matches actual team construction at runtime by inspecting each child's phase references. This is captured as future work in Consequences; the immediate PR (Phases A-C) does not require it.

**Phase D's relationship to Phase A-C.** Phase A's contract section declares `skills/*/team.yaml` as a glob marker the validator extension will eventually grep-check. Until Phase D ships, AC7's glob check is a manual `ls` rather than a `shirabe validate` step. The transient is acceptable: a missing team.yaml is detectable by the manual glob; the validator extension just automates the check.

### Phase E — Forward-looking note in pattern reference

Already included in Phase A's contract-section closing paragraph (Decision 6). No separate edit.

The PRD specifies that this DESIGN's downstream /plan will decompose Phase A-C into atomic issues. The phases above are the implementation ordering, not the issue boundaries.

## Security Considerations

The contract is documentation reconciliation; it introduces no new code paths, no new state-file fields, and no new external interfaces. The security surface analysis covers three angles:

**Dispatch primitive surface.** Inline Skill-tool invocation has the same security properties as a user typing the child's slash command directly — the child runs in the parent's agent context with the same tool allowlist. The contract does not widen the tool allowlist; it does not grant the parent privileged access to the child's internals. R14 child-isolation is preserved (the parent reads only the durable artifact path and frontmatter, never child wip/).

**Declarator format surface.** The `skills/<name>/team.yaml` file is plain YAML at a fixed per-skill location. It is not code; it is parsed by a future validator (Phase D) that lives in shirabe and runs against the same trust boundary as the rest of `shirabe validate`. No external input flows into the YAML parser; the declarations are author-written and committed to the repo. The file path is fixed (not author-supplied) so no path-traversal surface is introduced.

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

- **Validator extension deferred.** Phase D's validator extension is captured as future work; until it ships, the team.yaml schema conformance relies on author / reviewer discipline. Glob-checking `skills/*/team.yaml` for presence (exactly seven files) is sufficient for AC7.
- **In-flight-run forward-looking note.** Existing runs continue to work because the contract codifies their current dispatch shape (the runs already use inline Skill-tool dispatch in practice; the contract just names it). The R11 note exists for completeness, not because in-flight runs would actually break.

### Future Work

This DESIGN's scope is the contract surface; it does not modify any child skill's behavior beyond declaring shape. The contract structure this DESIGN lands ENABLES four enhancements surfaced in `friction-log-shirabe-0.7.0.md` during the DESIGN's own authoring and review, captured here so a future PR can pick them up without rediscovering the framing:

- **Ground-truth-verification reviewer for `/design`'s Phase 6 jury.** The current jury (architecture-reviewer, security-reviewer) verifies internal coherence of the DESIGN body but does not verify that claims about existing-codebase behavior are accurate against the cited files. This gap caused the initial Component 2 migration table in THIS DESIGN to fabricate three `/design` reviewer roles that did not exist; an adversarial-review pass caught it at PR time. A new `ground-truth-verification-reviewer` peer (tool surface: Read + Grep + Bash) would verify every "codifies existing behavior" claim against the cited file. Once landed, the addition is one edit to `skills/design/phase-6-final-review.md` plus one peer row in `skills/design/team.yaml` (the team.yaml shape the contract introduces makes the addition mechanical). Out of scope for this PR because adding a new peer changes `/design`'s actual team, beyond PRD R3's "codifies existing behavior" commitment.

- **Option-space coverage rubric for `/design`'s Phase 1 decision decomposition.** Same root cause as the ground-truth gap: this DESIGN's Decision 2 originally enumerated four declarator-location options (all under SKILL.md) and missed the obvious orthogonal axis "dedicated file." A future rubric extension at Phase 1 could require, for any location-relevant decision, that the option-walk include both "embedded in existing file" and "dedicated new file" as enumerated alternatives. Same out-of-scope reasoning.

- **`/design`-jury rubric vs format-reference cross-check.** Prior session's friction (logged before this PR) noted that `/design`'s jury did not cross-check the structural-review rubric the DESIGN authored against the artifact's own format reference, allowing a `scope: market | tool` enum clause to ship inside a DESIGN whose own format reference described `scope` as free-text prose. Same fix family as the ground-truth-verification reviewer; same out-of-scope reasoning.

- **Forward-compatibility note for `/plan`'s Phase 4 fan-out.** `/plan`'s Phase 4 dispatches N decomposer agents via the Task / Agent primitive in parallel. Today's substrate makes this OK because `/scope` has no team — the fan-out makes `/plan`'s context the single team. If a v2 substrate change ever gives parents peers (e.g., `/scope` materializes a coordinator at its own layer), `/plan`'s existing fan-out becomes a nested team and violates `team_primitive: single-team-per-leader-no-nested`. The contract's Layer-1 / Layer-2 split anticipates this — the Layer-2 binding to inline Skill-tool dispatch IS where the constraint lives — but the specific `/plan` fan-out is a v2-attention-point worth tracking. No code change in v1; a v2 substrate proposal SHALL revisit `/plan`'s Phase 4 alongside `/scope` and `/charter`'s parent-layer team primitive.

The first three items share the same root cause (juries inspect documents but not the code/references the documents claim to reflect) and could land as a single follow-up PR adding one new peer to `/design`'s team and the matching reviewer prose in `phase-6-final-review.md`. The fourth is documentation-only when v2 substrate work begins.

## References

- Upstream PRD: `docs/prds/PRD-shirabe-child-dispatch-contract.md`.
- Upstream BRIEF: `docs/briefs/BRIEF-shirabe-child-dispatch-contract.md`.
- Pattern source the contract reconciles: `references/parent-skill-pattern.md` (Team-Shape Declarator section, Team-Lead Operating Discipline / I-7 section, Named Substitution Surfaces).
- Pattern companion: `references/parent-skill-state-schema.md` (`parent_orchestration:` block schema).
- Tactical-chain parent: `skills/scope/SKILL.md` (Team Shape section, Phase 2 reference in `skills/scope/references/phases/phase-2-chain-orchestration.md`).
- Strategic-chain parent: `skills/charter/SKILL.md` (Team Shape section, Phase 2 reference in `skills/charter/references/phases/phase-2-chain-orchestration.md`).
- Children migrated: `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`, `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md`.
- Upstream conversation: GitHub issue `tsukumogami/shirabe#150` ("docs(scope): clarify that /scope spawns a TeamCreate-backed team per child dispatch") — the issue's suggested-fix wording is rejected by this DESIGN; the correct framing is documented in Decision 3.
