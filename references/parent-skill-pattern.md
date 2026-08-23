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

The pattern names seven invariants. Each invariant has a one-line semantics
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
- **I-7 — Active Orchestration.** A parent's team-lead MUST NOT transition
  to passive wait while dispatched teammates are in flight. The team-lead
  actively polls evidence under a bounded sleep-check-nudge loop until each
  dispatched task reaches a terminal exit (PASS / FAIL / ESCALATE). See the
  Team-Lead Operating Discipline section below for the full discipline.

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

The three-exit contract operationalizes the discipline-vs-artifact
decoupling thesis as its underlying principle: strategic conversation can
be *disciplined* without being forced to *produce*. Each exit demonstrates
a specific decoupling property — full-run produces a terminal artifact;
re-evaluation disciplines without re-producing (the Decision Record is the
durable record of the disciplined judgment, not a re-authored artifact);
abandonment-forced ends at a review surface (a schema-compliant partial
artifact with the abandonment marker) rather than letting a bailed chain
silently lose. The three exits together preserve the property that every
disciplined conversation has a durable home, even when production is the
wrong outcome.

## Gate Vocabulary

**Chain steps are mandatory, and reduction is post-hoc.** A parent
SHALL NOT decide, before a child's artifact exists, that the artifact
is not worth producing. Reduction of the artifact set happens against
documents that exist, or it does not happen. The reason is that the
judgment in question is whether one document holds anything its
successor does not, and that is only answerable by reading two
documents. When a chain is proposed neither has been written, so
nothing a parent can read at that point answers it.

Three grounds let a child legitimately not run. Every gate the
pattern defines, in this section and in Conditional Feeder
Invocation Shape below, admits exactly those three and no fourth:

1. A settled durable artifact already sits at the child's canonical
   path, so the auto-skip closes the gate (Mandatory-with-auto-skip).
2. The author declines an ALWAYS child at a prompt formed after the
   upstream artifact is on disk (ALWAYS, and see Author Declination
   on an ALWAYS Child below).
3. A conditional feeder's gate never opened, so the child was never
   planned at all (Conditional Feeder Invocation Shape).

None of the three is a worth judgment made against an unwritten
document. The first reads the filesystem, the second reads the
author, and the third reads whether the feeder's own preconditions
ever held.

A parent MAY define a post-hoc reduction mechanism that folds
redundant artifacts away once they exist. `/scope` defines one, its
consolidation judgment, which reads the two bodies at each hop and
absorbs the upstream when folding loses nothing. `/charter` and
`/execute` define none, and a parent that defines none conforms
fully: the model constrains when reduction may happen, not whether a
parent offers it at all.

A parent SHALL NOT carry two reduction mechanisms firing at different
times. One running before the artifacts exist and one running after
leaves neither reading as the rule, which is why `/scope` withdrew
its entry-altitude choice rather than keeping it beside the
consolidation judgment.

The model is stated over children rather than over state-file fields,
so it binds a parent that keeps no `planned_chain`. `/execute` is
that parent: its run is a homogeneous execution loop rather than a
heterogeneous authoring chain, and it omits the chain-tracking triad
for that reason. What it inherits is the rule above, not a field it
does not write.

Parents invoke children behind named gates. The pattern recognizes
three gate shapes; every child-invocation gate in every parent SHALL
be one of these three. Naming the shapes pattern-side keeps reviewers
from inventing per-parent vocabulary when a parent's chain shape
introduces a category the existing shapes already cover.

- **ALWAYS** — the child is invoked unconditionally on every chain
  run; no gate exists. Canonical example: `/charter`'s `/strategy`
  invocation, which is the main-chain spine and runs whether or not
  upstream VISION or ROADMAP exists. `/charter`'s `/roadmap`
  invocation is ALWAYS as well: the parent inspects nothing in the
  upstream STRATEGY to decide. A parent MAY offer the author an
  explicit declination for an ALWAYS child, under the three-property
  clause in Author Declination on an ALWAYS Child below; the gate
  stays ALWAYS because the skip comes from the author rather than
  from anything the parent computes.

- **shape-dependent** — the child invocation's *form* (which sub-
  shape of the child fires, with how many peers, against which set
  of inputs) is determined by an upstream-recorded predicate on the
  chain. The gate is not whether-to-invoke but how-to-invoke.
  Canonical example: `/scope`'s `/design` invocation, whose
  decision-roster shape is determined by the R6 predicates
  (architectural-alternatives count, new-component references,
  Complex classification) recorded during Phase 1 discovery.

- **Mandatory-with-auto-skip** — the child SHALL be invoked unless
  its durable artifact already exists at the published-Accepted
  status at the canonical path, in which case the child is recorded
  in `chain_skipped` and the chain proceeds to the next gate. A
  parent MAY additionally define a signal that overrides the skip
  and invokes the child anyway. The override is optional per-parent:
  a gate that defines none is still this shape. A parent whose
  child's lifecycle carries a further settled status MAY name it in
  its own binding (`/charter` skips against an Active VISION as well
  as an Accepted one); the shape requires only that the settled set
  be fixed before the run.
  Canonical example without an override: `/scope`'s `/prd`
  invocation, where an Accepted PRD at `docs/prds/PRD-<topic>.md`
  causes the gate to auto-skip and the chain continues to
  `/design`; absent that artifact, `/prd` runs. Canonical example
  with an override: `/charter`'s `/vision` invocation, which skips
  against an Accepted or Active VISION at
  `docs/visions/VISION-<topic>.md` and runs anyway when Phase 1
  discovery surfaces a thesis shift. `/scope`'s `/brief` is the
  same shape with a framing-shift override.

The three shapes are stable across parents. Each shape's
canonical example fixes the meaning against an existing parent's
SKILL.md so a reviewer can grep the example to confirm the shape
identifier matches the binding.

An override is not a second route into the child. It can only fire
in the case the auto-skip would otherwise have closed the gate — a
settled artifact already on disk — so a cold start fires the child
whatever the signal says. A parent MAY still surface the override
question on every run for the framing it gives the conversation; it
just cannot change the outcome when there is nothing to skip.

### Author Declination on an ALWAYS Child

A declination is an instance of the mandatory-steps model, not an
exception to it. The child was planned, the parent decided nothing,
and the author answered a question about a document they could
already read. What the model forbids is a parent deciding that an
unwritten artifact is not worth producing, and a declination is not
that.

Three properties make a declination conforming. A parent offering
one SHALL satisfy all three.

- **Author-supplied.** No predicate the parent evaluates can produce
  the skip on its own. A parent MAY read the upstream artifact to
  inform what it tells the author at the prompt; reading for the
  prompt is not reading for the gate, and the gate stays ALWAYS as
  long as no reading can change the pre-selected answer or skip the
  child by itself. In a non-interactive mode where no author
  answers, the child runs. `/charter` binds this by not firing the
  roadmap prompt at all under `--auto`, so `/roadmap` always runs
  there.
- **Formed against a document that exists.** The prompt fires after
  the upstream artifact is on disk. `/charter` asks immediately
  after `/strategy` returns, with the Draft STRATEGY written, so the
  author answers about a document rather than about a plan to write
  one.
- **Recorded.** The child stays in `planned_chain`, because the plan
  was to run it, and the skip lands in `chain_skipped` with its
  ground. Unlike an exit-path intervention such as Bail, a
  declination leaves the chain on its normal exit.

The prompt SHALL NOT ask whether the child's artifact is worth
producing. `/charter`'s roadmap prompt is the worked example of a
question that stays inside the model: it asks whether the STRATEGY
is headed for execution at all, and it refuses size and shape as
grounds, so a small strategy still gets a ROADMAP and only a bet
nobody intends to act on does not.

Offering a declination is per-parent and optional. `/scope`'s
`/plan` is ALWAYS with no declination surface at all, and
`/charter`'s `/roadmap` is the only live instance in the corpus.

Restating the clause changed no behavior: the same children fire on
the same runs.

*EITHER-signal retired 2026-08-08.* An earlier revision named a
fourth shape, EITHER-signal: "the child is invoked when a
parent-defined signal fires OR an upstream condition holds, with
either signal sufficient to open the gate," with `/charter`'s
`/vision` as its canonical example. Once each gate carrying that
label was written out as its own rule, every one of them
(`/charter`'s `/vision`, `/scope`'s `/brief`) turned out to be an
auto-skip gate with an override: the artifact state decides, and the
signal matters only when a settled artifact is already on disk. No
gate in any parent invoked its child on a signal alone, so the shape
had no examples left and was folded into Mandatory-with-auto-skip's
optional-override clause. Skill files and durable docs written before
that date may still call these gates EITHER-signal; read the label as
this shape. No gate's behavior changed — the same children fire on
the same runs.

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

When any of the three conditions fails, the parent SHALL state the skip
in its conversational output, naming the child and the condition that
failed (the stated-skip rule). A step the author might reasonably expect
does not disappear without explanation, and two different failing
conditions do not produce the same message.

The statement is conversational and is **never recorded**. Nothing that
gets committed carries it: not the parent's state file (no
`chain_skipped:` entry — a child whose gate never opened was never
planned, so there is nothing to record), not the chain's durable
artifacts, not anything landing under `docs/`. The split is what makes
the rule safe. The workspace visibility rule governs **document
references** — a document in a public repo must not name documents,
paths, or content from a private repo — and says nothing about what the
agent may say to the author. Honest conversation and clean artifacts are
not in tension once the two surfaces are kept apart.

An earlier revision of this pattern required the opposite (a
"degenerate-silence" rule: byte-identical output across failing
conditions, no surfacing of the gate). It was removed 2026-08-08. It
rested on reading the visibility rule as a constraint on speech, and it
cost the author any signal that a step had been dropped.

A parent's visibility gate is not made redundant by a feeder skill
running its own visibility check. A directly-invocable feeder checks
because it can be reached with no parent involved; a parent checks
because it should not route an author toward a gated artifact type in
the first place. Both are load-bearing.

**Parents do not extend children's input surfaces** with parent-
specific flags or arguments. A pattern-level suppression signal —
defined once in the pattern-doc, read by all parents, and recognized
by all children identically — is permitted as the sole parent-
orchestration primitive. The signal mechanism is the parent's state
file's `parent_orchestration:` block at a substrate-defined path;
children consult it as a pattern-level convention, not as a per-
parent API. The block names the invoking child and carries the
parent's upfront decision about whether the run is a fresh chain or
a revision, so the child can suppress its own status-aware re-entry
prompt without learning about the parent that invoked it.

The per-parent prohibition still holds — a parent SHALL NOT add
flags or arguments to a child's `$ARGUMENTS` parser, and SHALL NOT
extend the child's environment-variable surface with parent-named
keys. What the prohibition forbids is a parent inventing an input
the child would not otherwise have; passing a flag the child
authors in its own SKILL.md and phase contracts, and that an author
can hand the child directly, is choosing among the child's shipped
modes. `--upstream <path>` is the worked example: `/brief`,
`/strategy`, `/prd`, `/roadmap`, and `/comp` each own the flag in
their own contracts, and a parent passing it is using that surface
rather than extending it. The test separating the two is whether
the flag works when the parent is absent. The `parent_orchestration:` convention is the one named
exception, and only because it is pattern-defined: every parent
writes the same block at the same path, and every child reads it
identically. PRD R4's thesis-shift signal illustrates the loose-
coupling rule the prohibition protects — when a parent elicits a
shift signal that needs to reach the child, the parent passes the
topic slug through the child's existing input mode and writes its
upfront decision to the `parent_orchestration:` block; the child
reads the block at its own Phase 0 and routes accordingly. The
child's `$ARGUMENTS` surface, flag parser, and env-var consumption
are untouched. Extending those would couple the parent to the
child's API and break the moment the child refactors its inputs;
passing through existing modes plus the pattern-level convention
keeps the parent loosely coupled across child revisions.

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

A parent MAY drive its phases from a workflow session while declaring
`storage_substrate: wip-yaml-md`. A session holds position within a single
run and is disposed of at its terminal state; this substitution surface
names how a parent persists state between invocations. The two axes are
independent, so a parent that runs its phases as a workflow session still
declares the v1 value and still writes its state file at
`wip/<parent>_<topic>_state.md`.

This is a widening rather than a variance: it names a second thing a parent
may do, and `/charter` is not required to do it. The precedent is the
Dispatch Mechanism below, whose Layer-1 statement carries two Layer-2
bindings rather than admitting the second as a named exception.

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

**Reviewer-shaped roles vs variable-cardinality worker role types.** The
team-shape declaration MUST distinguish two role-cardinality shapes so a
coordinator knows how to dispatch correctly. **Reviewer-shaped roles**
iterate over work items themselves: ONE architecture-reviewer reviews ALL
N work items in one pass; the reviewer is materialized once regardless of
N. **Variable-cardinality worker role types** spawn one peer per work
item: `/design`'s `decision-researcher` role type spawns one researcher
per decision question; `/plan`'s `decomposer` role type spawns one
decomposer per outline. The team-shape declarator section above lists the
two cardinality shapes separately so the parent-of-the-parent knows
whether to materialize a single instance (reviewer) or N instances
(worker) at team-creation time.

## Dispatch Contract

The dispatch contract is the single source of truth for how a parent
skill invokes a child skill across the parent/child boundary. It is a
contract — every parent SHALL satisfy every element verbatim and every
child SHALL participate identically. It applies symmetrically to all
three v1 parents (`/scope`, `/charter`, `/execute`) and to every child
they invoke; no parent or child gets a per-binding override slot in v1.

**What the child roster counts.** Nine children, counted as the
distinct children the three parents actually invoke: `/scope`'s
`/brief`, `/prd`, `/design`, and `/plan`; `/charter`'s `/vision`,
`/strategy`, `/roadmap`, and its conditional feeder `/comp`; and
`/execute`'s `/work-on`. An earlier revision said seven and listed the
two authoring parents' non-feeder children only, which left `/comp`
out and said nothing about `/work-on`. The roster counts invocation
rather than artifact altitude: a child a parent dispatches is bound by
this contract whether it authors a durable doc, runs a competitive
analysis, or implements an issue. Seven of the nine ship the
`team.yaml` the Child Team-Shape Declaration element below requires;
`/comp` and `/work-on` do not, which is a conformance gap in those two
children rather than a per-binding exemption in the contract.

The contract has five labelled elements: a dispatch mechanism, a
pre-dispatch state, an observability surface, a hand-back contract,
and a child team-shape declaration. The four Layer-1 elements
(mechanism, pre-dispatch state, observability surface, hand-back)
are substrate-agnostic — every future substrate names them. The
specific bindings (the two dispatch bindings named below, the
dedicated `team.yaml` file path, the YAML schema, the
`wip/<parent>_<topic>_state.md` path) are Layer 2 (substrate-bound,
replaceable when the amplifier layer ships via the `team_primitive`
substitution surface above).

### Dispatch Mechanism

The Layer-1 element is that a parent hands a child a name and a
topic key and then waits on it, owning no team of its own at the
parent layer. v1 carries **two** Layer-2 bindings for that element:

- **Inline Skill-tool invocation.** The authoring parents (`/scope`,
  `/charter`) call the Skill tool from their own agent context with
  the child's name and the topic slug, the same way a user typing
  `/<child-name> <topic-slug>` would. The child runs in the parent's
  agent context and constructs whatever team it needs at the child
  layer.
- **Materialized `/work-on` runs.** `/execute` submits its per-issue
  children to a koto session that materializes one child per issue
  against `/work-on`'s child template, and drives that loop rather
  than blocking on a single call. Its coordinated path dispatches the
  same `/work-on` single-issue run per repo through a plain
  durable-state loop instead of a koto session.

The mechanism statement is widened to carry both rather than
admitting `/execute` as a named variance. The layering already treats
the dispatch mechanism as Layer-1 and its binding as Layer-2, so a
second binding is what the split was built for; naming the third
parent a variance would read a conforming parent as an exception and
would put the pattern's own layering to no use. Both bindings sit
under `team_primitive: single-team-per-leader-no-nested`, and all
three parents are single-agent at their own layer. The four remaining
elements are written against the inline binding because it came
first; where they name the Skill-tool call, read it as the dispatch
under whichever binding the parent uses.

R14 child-isolation is preserved by construction under both. The
parent reads only the child's durable artifact (per the hand-back
contract below) and never inspects the child's wip/ state, the
child's inbox, or any sub-team the child spawns. The Skill tool gives
the parent no privileged view into the child's internals, and a
materialized child is reached through the same durable surfaces plus
`gh` metadata on the child's own pull request.

### Pre-Dispatch State

Before invoking the child, the parent SHALL have written the
following four pre-dispatch state elements:

1. **`parent_orchestration:` sentinel block** in the parent's state
   file, with subfields `invoking_child:` (the child the parent is
   about to invoke), `suppress_status_aware_prompt:` (the upfront
   decision to silence the child's status-aware re-entry prompt), and
   `rationale:` (the upfront `fresh-chain | revise` framing the child
   reads to route its own Slot 2 behavior).
2. **Worktree-staleness gate output** — the rebase impact
   classification from the parent's worktree-discipline check
   (`None | Informational | Intent-changing-resolved-in-place`).
   The classification SHALL be resolved before dispatch; an
   unresolved classification fails the gate and dispatch does not
   fire.
3. **State-file fields written before dispatch** — the parent bumps
   `last_updated` and captures `pre_invocation_sha` (the HEAD commit
   SHA at dispatch time, used by the hand-back contract's Phase-N
   Reject discard-commit detection) BEFORE the Skill-tool call fires.
   `planned_chain` is not one of them. The list is fixed before the
   first child is invoked and no dispatch advances it; what the chain
   did lands in `chain_ran` and `chain_skipped` instead (see
   Chain-tracking in
   [`parent-skill-state-schema.md`](parent-skill-state-schema.md)).
4. **Child-side team-shape declaration glob marker** — the file
   `skills/<name>/team.yaml` exists and parses against the schema
   below. The marker is the contract surface; the parent does NOT
   parse the file at dispatch time in v1 (see Child Team-Shape
   Declaration below for the v1 read semantics).

The `parent_orchestration:` block is the canonical pre-dispatch
state element and is described as the pre-dispatch state element of
the dispatch contract in
[`parent-skill-state-schema.md`](parent-skill-state-schema.md).

### Observability Surface

The parent's observability surface for an in-flight child invocation
is **strictly** limited to:

- **Durable artifact path polling** — the parent checks for the
  child's canonical durable artifact at the well-known per-child
  path (e.g., `docs/briefs/BRIEF-<topic>.md`).
- **`git log` since `pre_invocation_sha`** — the parent inspects
  commits added during the child's run on its own worktree, for the
  hand-back contract's Phase-N Reject discard-commit detection.
- **The parent's own `wip/` filesystem** — the parent reads its own
  state file, its own intermediate artifacts, and its own
  `wip/<parent>_<topic>_state.md`. The parent does NOT read the
  child's wip/ state.

The parent SHALL NOT inspect the child's internal team coordination,
the child's inbox, the child's `wip/` state, or any sub-team the
child constructs. R14 child-isolation is the binding constraint:
the parent's observability surface is the durable artifact path
plus the parent's own worktree state, and nothing else.

**The parent's own workflow session.** A parent that drives its
phases from a workflow session also reads two surfaces belonging to
that session: the session-status surface, which reports the state
the run currently occupies and what it is blocked on, and the
per-hop record, which reports what each hop did once the run has
ended. Both are the parent observing its own session. The
enumeration above governs a parent's view of an in-flight child and
is unchanged by this item, as is the child-isolation limb that
closes it: a parent still inspects no child's internal team
coordination, inbox, `wip/` state, or sub-team, and reading one's
own session confers no view into a child's. Whether a child is ever
materialized as a session of its own is a separate question this
item neither settles nor forecloses.

### Hand-Back Contract

When the Skill tool returns, the parent SHALL perform the following
hand-back steps in order:

1. **R20 file-existence check** — confirm the child's canonical
   durable artifact path exists. A returning child with no artifact
   at the canonical path is a PASS-with-no-artifact violation
   surface.
2. **Frontmatter `status:` read** — read the artifact's frontmatter
   `status:` value to learn the child's terminal exit (Accepted,
   Done, Abandoned, etc.).
3. **Git blob hash capture** — capture the artifact's git blob hash
   as the content-fingerprint for the per-child snapshot dual-check
   (per the pattern-level invariant in
   [`parent-skill-state-schema.md`](parent-skill-state-schema.md)).
4. **Phase-N Reject discard-commit detection** — run
   `git log <pre_invocation_sha>..HEAD` to detect any Phase-N Reject
   discard commits the child may have created; the commits are part
   of the chain's audit trail.
5. **Validator pass-through** — run `shirabe validate` against the
   returning artifact; a validator failure is a contract violation
   the parent surfaces to its own exit path.
6. **`parent_orchestration:` cleanup** — clear the sentinel block
   from the parent's state file. The block is gated on
   in-flight-dispatch presence (invariant I-5); leaving it set after
   the child returns is a conditional-field-gating violation.
7. **`child_snapshots:` capture** — write the per-child snapshot
   `{status, content_hash, commit_sha}` to the parent's state file
   for the per-child snapshot dual-check.

### Child Team-Shape Declaration

Every child SHALL declare its team shape at the well-known per-skill
path `skills/<name>/team.yaml`. The file is the contract surface for
the child's team — its path is the glob marker, its content is the
declaration. The schema:

```yaml
parent_layer:
  # Peers the parent-of-the-parent materializes upfront.
  # Empty for every child in v1 (the parent owns no team).
  peers: []

child_layer:
  # Peers the child itself spawns during its phases.
  # An empty list is a valid declaration meaning "no team."
  peers:
    - role: <kebab-case-role-name>
      cardinality: reviewer | worker
      upper_bound: <integer>  # required iff cardinality: worker
      phase: <phase-slug>     # e.g., phase-4-validate
      purpose: <one-line description>
```

The schema mirrors the Team-Shape Declarator section's
reviewer-shaped-vs-variable-cardinality vocabulary verbatim;
`reviewer` cardinality means one peer reviews all N work items
(`upper_bound` omitted; one is implicit), `worker` cardinality means
one peer per work item (`upper_bound` names the maximum N). The
`phase:` value is a kebab-case slug matching the child's phase
reference filename without extension (e.g., `phase-4-validate`,
`phase-2-execution`, `phase-6-final-review`).

**v1 runtime read semantics.** The parent does NOT parse
`team.yaml` at dispatch time in v1. The substrate has no team.yaml
parser; the inline Skill-tool dispatch mechanism passes only the
topic-slug argument. The file is consumed in v1 by: (a) reviewers
verifying that the declaration matches the child's actual peer
roster, (b) the future Phase D validator extension when it ships,
and (c) the future amplifier-layer substrate when it ships
TeamCreate semantics under `team_primitive`'s Layer-2 substitution.
The contract surface (file at well-known path; fixed schema;
glob-checkable presence via `skills/*/team.yaml`) exists in v1; the
runtime read is a v2 binding.

v1 has no per-parent override slot — the contract applies verbatim
to all three parents and to the nine children counted above. The
contract applies to
chain runs initiated after the contract lands; existing in-flight
runs are not retroactively re-shaped (R11), because their dispatch
shape already matches what the contract codifies.

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

The default-option wording at status-aware re-entry prompts is part of
the contract surface, not a UX detail; each parent specifies it as
literal-substring requirements in ACs (e.g., the "Re-evaluate / Revise /
Bail" triad against an Accepted upstream artifact), so the eval surface
can grep-check the prompt vocabulary and downstream parents inherit the
discipline.

**Which literal form to require.** Specify an option triad as ONE
contiguous literal (separator ` / ` exactly) where the contract
requires the options be **co-equal with no default**; specify it as
independent per-token substrings everywhere else. Contiguity is not a
style preference — it is the mechanical proxy for co-equality, because
a single option line cannot rank or bury its options while prose can,
and per-token checking cannot tell a co-equal menu from three words
buried in a leading question.

The rule classifies the existing triads without exemptions:

| Prompt | Co-equal, no default? | Form |
|--------|----------------------|------|
| Status-aware re-entry (`Re-evaluate / Revise / Bail`) | yes — the parent PRDs make co-equality contractual | contiguous |
| Chain proposal (`Proceed` / `Adjust` / `Bail`) | no — Proceed is the expected path, and a parent MAY render an interstitial label such as "Adjust chain" | per-token |
| Per-child confirmation prompts carrying an explicit default | no — the default marker is the point | per-token |
| Drift detection (`Re-run` / `Accept` / `Proceed without`) | no | per-token |

Do NOT generalize contiguity to a triad in the per-token rows: a
parent whose chain-proposal prompt renders "Adjust chain" would fail a
contiguous check against its own canonical example.

Note that the SHALL-NOT constraints naming this triad (the
refuse-and-redirect rows) are **conceptual**, not byte-literal — they
forbid *offering* the triad, however rendered — so they neither depend
on nor are weakened by the positive form chosen here.

**What Adjust reaches.** The chain proposal's Adjust option SHALL
re-enter the parent's own discovery with the author's adjustment
input and re-emit the proposal against the adjusted result. That much
is pattern-level and the same in every parent. Whether the re-entry
can change chain *membership* is a per-parent property, and each
parent SHALL state which it has in its own chain-proposal section.
`/scope`'s cannot: its planned chain is the same four children on
every run, so Adjust refines the topic and the framing and the
proposal returns with the same membership. `/charter`'s can: its
redirected discovery may force a previously-skipped child on.
Neither reach admits a third thing. No parent may use Adjust to reach
a child whose artifact the parent judged not worth producing, because
under the mandatory-steps model no parent makes that judgment, and
Adjust is not a route back to one.

## Team-Lead Operating Discipline

The pattern names a parent-skill discipline that binds the team-lead of
any team-emitting parent skill while peer agents are in flight. The
discipline operationalizes semantic invariant I-7 (Active Orchestration):
the team-lead actively polls evidence under a bounded loop and drives
dispatched tasks to terminal exits rather than transitioning to passive
wait.

### Canonical 5-Step Sleep-Check-Nudge Loop

Every team-lead executing the discipline runs the following loop per
in-flight dispatched task. The loop is the contract; specific timing
values per task class are in the table below.

1. **Dispatch** — the team-lead spawns the peer with directly-executable
   instructions (the artifact to read or produce, the location to write
   to, and the structured verdict to reply with on completion).
2. **Sleep** — bounded wait per the task class (see the table). The
   sleep is not unbounded; it has a fixed window before the next
   evidence check.
3. **Filesystem evidence check (priority 1)** — inspect the worktree
   for terminal-artifact presence, partial-artifact growth, `git log`
   for new commits since dispatch, and `wip/` artifact growth. Terminal
   artifact present plus passing validation maps to PASS; partial
   evidence resets the patience budget; no change decrements the
   patience budget by one.
4. **Inbox processing (priority 2)** — read structured PASS / FAIL /
   PROGRESS verdicts from the team-lead's inbox. Idle pings do NOT
   count as inbox messages (see the rule below); only verdicts route
   the loop.
5. **Nudge (priority 3)** — when neither filesystem evidence nor a
   structured inbox verdict resolves the task, send a directly-
   executable nudge to the peer naming the artifact, the location, and
   the verdict to reply with. Generic nudges ("what's happening?")
   are forbidden.

### Three Terminal Exit Conditions

Every dispatched task ends at exactly one of three terminal exits. The
loop does not run indefinitely.

- **PASS** — terminal artifact present and valid, OR structured PASS
  verdict from the peer with the artifact verified by the team-lead.
- **FAIL** — FAIL verdict received from the peer, OR artifact
  validation failure (artifact present but does not pass its own
  validator).
- **ESCALATE** — patience budget exhausted (default 5 stagnation
  cycles per teammate). ESCALATE maps to the parent's
  `abandonment-forced` exit path with a `triggering_teammate:` field
  recording which peer's stagnation triggered the escalation.

### Strict Priority Ordering

The three checks in the loop are ordered with strict priority:
filesystem evidence (priority 1) BEFORE inbox messages (priority 2)
BEFORE nudges (priority 3). The ordering is not advisory — it is the
discipline. A team-lead that consults the inbox before checking
filesystem evidence misses durable terminal-artifact PASS that the
peer has already produced. A team-lead that nudges before consulting
the inbox produces noise (the peer may have already replied with a
verdict the team-lead would have read).

### Task-Class Timing Table

Each task class has a sleep window (how long the team-lead waits
between evidence checks) and a patience budget (how many stagnation
cycles before ESCALATE fires). The values are the v1 pattern-level
defaults; parents MAY tune them per their own runtime profile.

| Task class | Sleep window | Patience budget |
|---|---|---|
| Review verdict | 30s | 5 cycles |
| Decomposition / generation | 60s | 10 cycles |
| Implementation pass | 120s | 10 cycles |
| External wait (CI, network) | 60s | unlimited |

Stagnation is the absence of progress evidence in either the
filesystem or the inbox; progress evidence (a new commit, a partial
artifact write, a PROGRESS verdict) resets the patience budget
implicitly to the full task-class allotment.

### Idle-Pings-Are-Not-Inbox-Messages Rule

Idle pings (peer messages indicating the peer is still alive but has
no verdict) are infrastructure noise; they MUST NOT count as inbox
messages in step 4 of the loop. Only structured PASS / FAIL /
PROGRESS verdicts are actionable interface signals. A team-lead that
treats idle pings as PROGRESS verdicts would mistakenly reset the
patience budget on every ping, defeating ESCALATE.

The discipline name for the rule: structured verdicts are the
actionable interface; idle pings are infrastructure-level liveness
signals the team-lead's inbox processing ignores.

### Nudge Content Rule

Every nudge sent by the team-lead (priority 3) MUST contain
directly-executable instructions. The nudge SHALL name:

- **What artifact** the peer is being asked to read or produce.
- **Where** the artifact lives (the canonical path).
- **What verdict** the peer should reply with on completion
  (structured PASS / FAIL / PROGRESS).

Generic nudges ("what's happening?", "any update?", "please
respond") are forbidden. They are noise on the channel and do not
advance the loop; they consume cycles without producing actionable
evidence. The discipline replaces generic nudges with concrete
directly-executable instructions every time.

### `ci_outcome` Semantics

When a task-class run depends on CI (the External wait class above),
the loop tracks two distinct CI outcomes that are NOT
interchangeable:

- **`passing`** — CI was always green; the team-lead's evidence
  check observed only PASS verdicts on CI runs since dispatch. No
  fix-pushes occurred.
- **`failing_fixed`** — CI flipped from FAIL to PASS after a fix
  push. The team-lead observed a failure verdict, the peer (or
  another agent) pushed a fix, and a subsequent CI run flipped the
  rollup green.

Distinguishing the two matters because `passing` is the strong
durable-evidence claim (no flake, no rework) while `failing_fixed`
records that rework occurred. Downstream consumers (release notes,
audit trails, retrospectives) treat them differently.

### Binding Notes for v1 Parents

All three v1 parents (`/scope`, `/charter`, `/execute`) bind the
discipline at the child layer, not at the dispatch boundary. The two
dispatch bindings the discipline binds against are named in the
`## Dispatch Contract` section above, and neither gives the parent a
team of its own: the child runs its own team (when it has one) at the
child layer. The discipline's content — sleep-check-nudge loop, terminal
exits, timing table, idle-pings rule, nudge content rule, `ci_outcome`
semantics — is unchanged; what changes is the layer the binding fires at.

- **At the parent-itself layer:** the binding is vacuous in v1. All
  three parents run as single-agent skills (see each parent's SKILL.md
  Team Shape section); no peers are dispatched at the parent-itself
  layer, so the loop has zero dispatched tasks to drive. `/execute`'s
  orchestrator loop is not a counterexample: what it drives is children,
  not peers.
- **At the child-itself layer:** the discipline binds inside each child
  against the child's own peers. Each child constructs its own team (when
  it has one) per the Dispatch Contract's Child Team-Shape Declaration;
  the child is the team-lead in the discipline sense, driving its own
  peers' dispatched tasks to terminal exits. The child-skill invocation
  task class is the implementation pass class above (120s window,
  10-cycle patience budget) as seen from the parent's wait on the
  child, synchronous under the inline binding and loop-driven under
  the materialized one. When ESCALATE fires inside a child invocation, the
  escalation surfaces through the child's normal terminal artifact (a
  partial doc with abandonment-forced state) and the child's
  `triggering_teammate:` field; the parent learns about it via the
  Hand-Back Contract's R20 file-existence check and frontmatter `status:`
  read, not by inboxing a verdict from a team it does not own.

| Parent | Children invoked |
|---|---|
| `/scope` | `/brief`, `/prd`, `/design`, `/plan` |
| `/charter` | `/vision`, `/strategy`, `/roadmap`, `/comp` (conditional feeder) |
| `/execute` | `/work-on` (one run per issue) |
