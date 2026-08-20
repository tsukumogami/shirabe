# Lead: Can `/scope` and `/charter` sit on different substrates under the parent-skill pattern, and what conformance text moves if they do?

Short version: they already do sit on different footings, the pattern already
carries a third parent on a different substrate, and the machinery for
admitting a substrate difference (Layer-1/Layer-2 split, per-parent surface
table, `storage_substrate` substitution variable) is already load-bearing
rather than aspirational. The conformance cost of `/scope` adopting koto is
two structural elements and one paragraph of an observability rule — and the
precedent for both edits is `/execute`, which made them in 2026 and held.

Note on paths: `references/parent-skill-pattern.md` in this worktree is
byte-identical to the plugin-cache copy at
`/home/dgazineu/.claude/plugins/cache/shirabe/shirabe/0.18.1-dev/references/parent-skill-pattern.md`
(verified with `diff -q`). All line citations below use the worktree path;
they resolve identically in the cache.

## Findings

### 1. The seven structural elements, classified

The seven are at `references/parent-skill-pattern.md:674-699`. The framing
sentence is `:676-678`: "Every parent skill's `skills/<name>/SKILL.md` SHALL
contain seven structural elements. The list is pattern-level; the content
slotted into each element is parent-specific." `:697-699` adds that parents
extend past the seven and "the seven structural elements are the pattern-level
floor."

| # | Element (`:680-695`) | Classification | What moves under koto |
|---|---|---|---|
| 1 | Input Modes | binding-neutral | nothing |
| 2 | Execution-mode flag parsing | neutral content, gains plumbing | the resolved mode must reach the koto template as a variable at `koto init` |
| 3 | Topic-slug constraint | neutral, gains a second interpolation site | the koto session name becomes a slug-derived value |
| 4 | Workflow Phases diagram | binding-neutral | nothing |
| 5 | Resume Logic ladder | **binding-specific** | resume must reconcile koto session state with the wip state file |
| 6 | Phase Execution list | **binding-specific in its literal form** | phase bodies move from `references/phases/*.md` into a koto template |
| 7 | Reference Files table | neutral shape | gains rows for the template and any scripts |

Elements 5 and 6 are the only two that genuinely change. Every one of those
five judgments has a worked precedent in `/execute`:

- **Element 2 plumbing.** `skills/execute/SKILL.md:259-264`: "The pause is
  **mode-driven, not a flag**... Execution-mode resolution... sets the
  `PAUSE_BEFORE_FINALIZE` template var at `koto init` (Step 2): interactive →
  `true`, `--auto` → `false`." The flag-parsing element is unchanged; a
  reflection step is added downstream of it.
- **Element 3 second interpolation site.** `skills/execute/SKILL.md:183`:
  `koto init execute-<plan-slug>`. The session name is slug-derived, so the
  security surfaces bind to it. `skills/execute/SKILL.md:218-223` shows the
  same discipline applied to a recovered branch name: "re-validated against a
  safe ref pattern before it is stored or interpolated into emitted shell."
- **Element 4 survives verbatim.** `skills/execute/SKILL.md:110-119` still
  renders a four-phase ASCII diagram even though Phase 1's body is a koto
  loop. `:121-123`: "The two execution paths share this phase spine but differ
  in Phase 1's loop substrate (koto session for single-pr, plain durable-state
  loop for coordinated)." The diagram is above the substrate.
- **Element 6 is where the literal breaks.** The pattern's element 6
  (`:692-693`) reads "**Phase Execution** list — one phase reference per parent
  phase, pointing at `skills/<name>/references/phases/<phase>.md` files."
  `skills/execute/SKILL.md:129-131` says: "`/execute` runs its phases through
  the sections of this SKILL.md rather than separate per-phase reference files
  (it carries no `references/phases/` directory; its Phase-1 mechanics live in
  the lifted koto template and the **Coordinated** loop)." Confirmed on disk —
  `skills/execute/` has no `references/phases/`, while `skills/scope/` and
  `skills/charter/` both do. And `skills/execute/SKILL.md:752-756` asserts
  conformance anyway: "The parent-skill conformance binding (the seven required
  structural elements, state schema, resume ladder, three exit paths,
  metadata-only inspection, and the six security surfaces) is **complete**
  across the **Workflow Phases**, **Phase Execution**, **State**, **Resume**,
  **Exit Paths**, **Child Inspection**, and **Security Considerations**
  sections above."

  So element 6 is already read as "a per-phase list with a pointer to where
  each phase's mechanics live," not as "files at that exact path." A
  koto-driven `/scope` inherits that reading. Nobody amended `:692-693` when
  `/execute` shipped, which is itself a data point for question 7.
- **Element 7.** `skills/execute/SKILL.md:762-764` adds rows for
  `skills/execute/koto-templates/execute.md`,
  `skills/execute/scripts/assert-child-template.sh`, and
  `skills/execute/scripts/run-cascade.sh`.

**Element 5 is the expensive one.** `/scope`'s ladder
(`skills/scope/SKILL.md:322-360`) is meta rows 1-4 and 8-9 with body slots 5
(9 rows), 6 (4 rows), 7 (feeder handoff). Under koto, a resumed run has two
state locations that can disagree: `wip/scope_<topic>_state.md` (git-tracked,
branch-scoped) and the koto session. The koto session's home is
`~/.koto/sessions/<name>/ctx` — established concretely by
`skills/execute/scripts/settled-branch-record_test.sh:306`
(`LOCKED_CTX="$HOME/.koto/sessions/fail-probe/ctx"`) and `:71` ("real
`~/.koto`"). That is outside the repo, outside `wip/`, untracked, and not
branch-scoped. `/execute` solved the reconciliation by making the durable
home PR the anchor and rebuilding the wip projection from it
(`skills/execute/SKILL.md:476-479`). `/scope` has no PR to anchor on
mid-chain, so this is genuinely new design work rather than a copy.

### 2. Does `:519-522` stretch to a third shape?

Verbatim, `references/parent-skill-pattern.md:512-522`:

> The mechanism statement is widened to carry both rather than admitting
> `/execute` as a named variance. The layering already treats the dispatch
> mechanism as Layer-1 and its binding as Layer-2, so a second binding is what
> the split was built for; naming the third parent a variance would read a
> conforming parent as an exception and would put the pattern's own layering to
> no use. Both bindings sit under `team_primitive:
> single-team-per-leader-no-nested`, and all three parents are single-agent at
> their own layer. The four remaining elements are written against the inline
> binding because it came first; where they name the Skill-tool call, read it
> as the dispatch under whichever binding the parent uses.

And the enumerating sentence at `:495-497`:

> The Layer-1 element is that a parent hands a child a name and a topic key and
> then waits on it, owning no team of its own at the parent layer. v1 carries
> **two** Layer-2 bindings for that element:

What it licenses, precisely: the four non-mechanism elements are to be read
against **whichever binding the parent uses**, and the set of bindings is
closed at two by `:497`. It does not license inventing a third *dispatch*
binding by reading alone — that took a doc edit when `/execute` shipped, and
`:512-517` is the record of that edit.

**But shape (a) does not need it to stretch, because shape (a) is not a
dispatch binding at all.** The Dispatch Mechanism element governs the
parent/child boundary — "a parent hands a child a name and a topic key and
then waits on it" (`:495-496`). Under shape (a), `/scope` still hands `/brief`
a name and a topic key via the Skill tool and still waits on it. Koto would
sequence `/scope`'s own phases *between* those dispatches. The Dispatch
Mechanism element, the Pre-Dispatch State element, and the Hand-Back Contract
are all untouched. Shape (a) touches only the parent's internal phase
substrate — which the pattern governs through `storage_substrate`
(`:374-384`) and the structural elements, not through the Dispatch Contract.

**Shape (b) needs no stretch either, for the opposite reason:** the
materialized binding already exists as a named Layer-2 value (`:505-510`), and
`:519-522` explicitly tells you to read the remaining elements against it.

So neither candidate shape requires the read-as sentence to do work it was not
written for. The one thing that would — a genuinely novel dispatch binding —
is not on the table for either candidate.

### 3. What the Observability Surface would need

The surface is `references/parent-skill-pattern.md:569-589`. Its three bullets
(`:573-583`) are durable-artifact-path polling, `git log` since
`pre_invocation_sha`, and — the relevant one — `:581-583`:

> **The parent's own `wip/` filesystem** — the parent reads its own state file,
> its own intermediate artifacts, and its own `wip/<parent>_<topic>_state.md`.
> The parent does NOT read the child's wip/ state.

closed by `:585-589`: "the parent's observability surface is the durable
artifact path plus the parent's own worktree state, and nothing else."

Under koto, `/scope` would read its own koto session's state (context keys,
evidence fields, gate status) to know where its own phase pointer sits. That
is the parent's own state, so R14 child-isolation is not implicated at all —
but it is not "the parent's own `wip/` filesystem" and it is not "the parent's
own worktree state," because `~/.koto/sessions/` is neither. **Bullet 3 is the
single sentence that needs widening**, from `wip/`-and-worktree to "the
parent's own durable state under its declared `storage_substrate`, wherever
that substrate places it." That phrasing keeps the "nothing else" clause and
the child-isolation half intact.

**The Observability Surface is already looser in practice than its text.**
`:527-530` names the koto-era surface for `/execute`: "a materialized child is
reached through the same durable surfaces plus `gh` metadata on the child's
own pull request." `skills/execute/SKILL.md:673-677` spells it out: PR state,
labels, CI check rollup, read through `gh`. None of that is any of the three
bullets, and `gh` reads are not worktree state. The reconciliation is that the
operative rule for *what may be read about a child* lives in
`references/parent-skill-child-inspection.md`, whose Per-Parent Surface Table
(`:60-63`) has a row for "issue or PR (no doc) → issue/PR state + labels + CI
check rollup" — and whose `:65-67` says explicitly: "The table grows as new
parents land children with new shapes. Each parent that invokes a new child
shape adds a row; new rows go through the parent's own PR review."

So the pattern already ships a designed-to-grow widening seam, and `/execute`
already used it. Two consequences for the exploration:

- Under shape (a), children stay doc-emitting, so **no new row is needed** in
  the surface table. Only the pattern's bullet 3 changes.
- Under shape (b), `/scope`'s children are still doc-emitting (`/brief`,
  `/prd`, `/design`, `/plan` all write docs), so still no new row — this is
  where a koto-materialized `/scope` differs from `/execute`, whose children
  emit PRs rather than docs. Shape (b)'s observability cost is *lower* than
  `/execute`'s was.

The prior round's conclusion that "only the Observability Surface would need
widening" is confirmed, and it is one bullet, not a section.

### 4. The Hand-Back Contract survives unchanged — verified

`:591-620`, seven steps. Step by step against a koto-driven parent:

1. **R20 file-existence check** (`:595-598`) — "confirm the child's canonical
   durable artifact path exists." Filesystem. Substrate-independent.
2. **Frontmatter `status:` read** (`:599-601`) — reads the artifact. Same.
3. **Git blob hash capture** (`:602-606`) — reads the artifact. Same.
4. **Phase-N Reject discard-commit detection** (`:607-610`) — `git log
   <pre_invocation_sha>..HEAD`. Git, not the call.
5. **Validator pass-through** (`:611-613`) — `shirabe validate` against the
   artifact. Same.
6. **`parent_orchestration:` cleanup** (`:614-617`) — a write to the parent's
   own state file.
7. **`child_snapshots:` capture** (`:618-620`) — a write to the parent's own
   state file.

Five of seven read the artifact or git; two write the parent's own state. Not
one reads the Skill tool's return value. The only binding-flavored word in the
whole section is the trigger, `:593`: "When the Skill tool returns" — and that
is exactly what `:519-522` instructs you to read as "the dispatch under
whichever binding the parent uses." **The lead's hypothesis is correct and the
contract keys on the artifact, not the return.** Steps 6 and 7 would move from
a `wip/` write to a koto-context write under shape (b); their content is
unchanged.

### 5. How structurally parallel are `/scope` and `/charter`, really

Not very. The divergence already present is larger than anything koto adoption
would add.

| Dimension | `/scope` | `/charter` |
|---|---|---|
| SKILL.md length | 968 lines | 352 lines |
| Top-level sections | 22 | 10 |
| Phases | 5 (0,1,2,3,4) — `skills/scope/SKILL.md:288-301` | 4 (0,1,2,N) — `skills/charter/SKILL.md:178-188` |
| Phase reference files | 6 | 6 (different set) |
| Meta-ladder tail rows | 8-9 (`skills/scope/SKILL.md:338`) | **9-10** (`skills/charter/SKILL.md:216-217`) |
| Body slots | 5, 6, 7 (`:339-341`) | 5, 6, 7, **8.5** (`:218-227`) |
| Slot 5 row count | 9 rows (`:353-357`) | expands to rows 5-6 (`:220-221`) |
| Substitution-surface declaration | `## Binding Notes` (`:935-956`) | **absent** |
| State-file schema home | `skills/scope/references/state-schema.md` + inline `## State File Schema` | `phases/phase-state-management.md` |
| Exit paths | inline `## Three Exit Paths` (`:579`) | in `phases/phase-finalization.md` |
| `/design`-style shape gates | `## Chain-Proposal Output`, R6 predicates | none |
| Chain-proposal Adjust reach | cannot change membership (`references/parent-skill-pattern.md:741-743`) | **can** (`:743-744`) |

Two of those are outright pattern-level divergences the pattern itself
ratifies:

- **The ladder tail is numbered differently in the two parents for the same
  meta rows.** `/scope`'s meta tail is rows 8-9; `/charter`'s is rows 9-10,
  because `/charter` inserted a fractional row 8.5 to keep the tail at its
  existing ordinals — `skills/charter/SKILL.md:224-227`: "The fractional number
  keeps rows 9 and 10 — the shared meta-ladder tail `/scope` uses too — at
  their existing ordinals; the template licenses a body slot to expand this
  way."
- **Adjust reaches different things.** `references/parent-skill-pattern.md:735-748`:
  "Whether the re-entry can change chain *membership* is a per-parent property,
  and each parent SHALL state which it has in its own chain-proposal section.
  `/scope`'s cannot... `/charter`'s can."

There is also a Phase-2 structural asymmetry the dispatch-contract design
called out and deliberately preserved —
`docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md:359`: "The
asymmetry preserves /charter's existing per-child rule structure (which
encodes per-child conditional invocation logic; `/scope`'s children are
unconditionally ordered)... AC13's 'symmetric wording' requirement is satisfied
because the cross-reference TEXT is identical across all five attachment
points; only the location differs by parent structure."

That last sentence is the governing precedent for this whole lead: **the repo's
established test for "symmetric" is that the *contract text* is identical, not
that the *structure* is.** Location, phase count, section count, and row
numbering are already permitted to differ.

### 6. `/charter`'s missing consolidation sections — verified, with a correction

Verified on both halves:

- `/charter` has neither `## Why the Artifact Set Shrinks` nor `##
  Consolidation Judgment` (full header enumeration of
  `skills/charter/SKILL.md` yields 10 sections, neither among them). `/scope`
  has both at `:472` and `:532`.
- The pattern ratifies defining none.
  `references/parent-skill-pattern.md:141-147`: "A parent MAY define a post-hoc
  reduction mechanism that folds redundant artifacts away once they exist.
  `/scope` defines one, its consolidation judgment... `/charter` and `/execute`
  define none, **and a parent that defines none conforms fully**: the model
  constrains when reduction may happen, not whether a parent offers it at all."

**Correction to the lead brief's stated ground.** The brief attributes the
no-op verdict to "zero strategic hops are absorbable" at
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:353-372`.
Decision 9 is at `:353` and that reasoning is at `:369-370` ("Zero strategic
hops are absorbable, so porting the judgment would install a rule that can only
ever return `keep`"). But an amendment further down the same document
**withdraws that reasoning** — `:858-869`:

> **Decision 9 (`/charter` is out of scope) — the conclusion stands, the
> reasoning does not.**
>
> The reasoning was that "zero strategic hops are absorbable, so porting the
> judgment would install a rule that can only ever return `keep`." That rests
> on the same type-level mapping test, and under the current rule no chain can
> be declared unabsorbable in advance.
>
> The conclusion survives on grounds that do not depend on it: there is no
> consolidation judgment in `/charter` to change, and the judgment's logic
> lives entirely inside `/scope`'s own phase files, so extending it to the
> strategic chain would be new machinery rather than a follow-on edit.

This *strengthens* the divergence case rather than weakening it. Under the old
reasoning, `/charter` lacked the sections because the capability was
structurally impossible there — a fact about types. Under the current
reasoning, `/charter` lacks them because **nobody built them**, and building
them would be new work nobody has asked for. The two parents are permitted to
differ on substance not because one of them is incapable, but because the
pattern is a floor and neither parent owes the other feature parity.

The same document's scope boundary is explicit in the upstream PRD —
`docs/prds/PRD-scope-chain-mandatory-steps.md:65-67`: "Out: adding a
consolidation judgment to the strategic chain, retiring `/charter`'s roadmap
[declination]."

**What this implies for the lead question:** the two parents already differ on
a whole capability, ratified in pattern text, with the ratification surviving a
rewrite of its own justification. Substrate is a strictly smaller difference
than capability. If `/charter` may lack a mechanism `/scope` has, it may lack a
substrate `/scope` has.

### 7. The cost of divergence — and the precedent that already ran

**There is a deliberately-divergent pair, and it is not `/scope`+`/charter` —
it is `{/scope, /charter}` vs `/execute`.** `/execute` diverges on at least
four axes:

1. **Dispatch binding.** Materialized koto children vs inline Skill-tool
   (`references/parent-skill-pattern.md:499-510`).
2. **Phase-file layout.** No `references/phases/` at all
   (`skills/execute/SKILL.md:129-131`) against element 6's literal
   (`:692-693`).
3. **Observability.** `gh` PR metadata (`skills/execute/SKILL.md:673-679`)
   against the "nothing else" clause (`:585-589`), reconciled through the
   surface table rather than the pattern.
4. **Invariant I-6.** The pattern states flatly at `:68-71`: "**I-6 is
   load-bearing as an unsatisfied invariant in v1.** The v1 core-layer
   implementation explicitly does NOT satisfy I-6." `/execute` satisfies it —
   `skills/execute/SKILL.md:479` binds "the cross-branch-resume invariant
   (**I-6**)" through the home-PR lookup, and its own frontmatter (`:7-8`)
   advertises "a wip-yaml-md state projection over the durable home PR
   (cross-branch resume)." A v1 parent has closed a gap the pattern still
   describes as the amplifier layer's mandate.

**Did it hold up?** Structurally yes, textually with debt. The mechanism
statement was widened cleanly and the rationale for widening-over-variance is
recorded (`:512-517`). But three pattern passages went stale and are still
stale:

- `:68-76` still says v1 does not satisfy I-6, contradicted by `/execute`.
- `:585-589` still says "nothing else," contradicted by `/execute`'s `gh`
  reads.
- `:655-658` still says "the inline Skill-tool dispatch mechanism passes only
  the topic-slug argument" — contradicted by `/scope` itself, whose
  `skills/scope/references/phases/phase-2-chain-orchestration.md:183-187` table
  passes `docs/briefs/BRIEF-<topic>.md` to `/prd`,
  `docs/prds/PRD-<topic>.md` to `/design`, and
  `docs/designs/DESIGN-<topic>.md` plus `--upstream <roadmap-path>` to
  `/plan`. This is the inconsistency the brief flagged, and it bears on my lead
  as a fourth instance of the same failure mode. Note the practice is
  *conforming* — `phase-2-chain-orchestration.md:194-201` grounds it in the
  pattern's own "choosing among a child's shipped modes" rule
  (`references/parent-skill-pattern.md:346-352`) — so the stale text is the
  pattern's, not the parent's.

**So the observed maintenance cost of one substrate divergence is: roughly
three-to-four sentences of pattern prose that describe the old binding as if it
were universal, none of which caused a behavioral failure, and all of which
survived at least one release cycle unnoticed.** That is the honest number to
carry into the ranking — not zero, but nowhere near "every future pattern
change is written twice."

The reason it is that cheap is structural, and it was designed in. The pattern
separates Layer-1 (what every parent satisfies) from Layer-2 (how this parent
satisfies it) at `:24-38`. Every element that would be "written twice" under a
naive reading is Layer-2, and Layer-2 was always per-parent. `:487-491` lists
what is Layer-2 explicitly: "the two dispatch bindings named below, the
dedicated `team.yaml` file path, the YAML schema, the
`wip/<parent>_<topic>_state.md` path." The pattern-level prose that binds all
parents — seven invariants, three exit paths, gate vocabulary, security
surfaces, team-lead discipline — is substrate-agnostic by construction and is
written once regardless.

**One guardrail the repo already set, worth respecting.** A per-parent override
slot was proposed and rejected —
`docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md:202`:

> **Introduce a named override slot in v1.** *Pros:* Future-proof; if a third
> parent (e.g., `/work-on`) needs to override a contract element, the slot
> already exists. *Verdict:* Rejected. The slot would be empty in v1 and become
> a maintenance attractor.

Restated in the pattern at `:667-669`: "v1 has no per-parent override slot —
the contract applies verbatim to all three parents and to the nine children
counted above." So the sanctioned route for a `/scope` substrate change is
**widening a Layer-1 statement to name a second value**, exactly as `:512-517`
did — not adding a `/scope`-specific exemption clause. Any adoption proposal
that reads as "carve out `/scope`" will be arguing against a decision already
made.

### 8. Is there a third consumer?

Yes — three today, with a fourth named as a candidate and a fifth cultivated as
an audience.

- **Three live parents.** `references/parent-skill-pattern.md:465` ("all three
  v1 parents (`/scope`, `/charter`, `/execute`)"), repeated at `:668`, `:882`,
  `:892`, and tabulated at `:912-916`. The pattern's own prose was rewritten
  from two-parent to three-parent framing: `:471-480` records the child-roster
  recount from seven to nine, "An earlier revision said seven and listed the
  two authoring parents' non-feeder children only."
- **A fourth candidate, named twice.** `/work-on` migration appears as a future
  parent in `docs/prds/PRD-shirabe-scope-skill.md:966-969` ("so future parents
  (`/work-on` migration, future tactical parents) inherit the same trigger
  condition") and as the hypothetical third parent in the override-slot
  rejection above.
- **"A maintainer building a third parent" is a first-class persona** in the
  requirements, not an afterthought.
  `docs/prds/PRD-scope-chain-mandatory-steps.md:171-173`: "**A maintainer
  building a third parent skill.** They read the shared pattern and find the
  model stated, along with what a skip may legitimately mean and how an author
  declination differs from a gate the parent computes." Same PRD `:59-61` lists
  it among the journeys the feature exercises.

The lead's framing — "a pattern with two consumers tolerates divergence
differently than one with five" — is the right axis, and the count is closer to
five than to two once candidates and personas are included. But the direction
of the inference flips: **a pattern written for an open-ended set of future
parents has more reason to keep its Layer-1 statements substrate-neutral, not
less.** A two-consumer pattern could afford to hard-code one binding; a
three-plus-consumer pattern that is actively recruiting a fourth cannot. The
existing Layer-1/Layer-2 split, the `storage_substrate` and `team_primitive`
substitution variables, and the growable surface table are all evidence the
authors reached that conclusion already.

## Implications

**Both candidate shapes are permitted, and shape (a) is the cheaper of the two
on conformance.** Shape (a) leaves the entire Dispatch Contract untouched
(mechanism, pre-dispatch state, hand-back all key on the parent/child boundary,
which does not move) and costs: element 6's phase-file layout, element 5's
resume ladder, one bullet of the Observability Surface, and plumbing on
elements 2, 3, 7. Shape (b) costs all of that plus a rewritten dispatch loop —
though notably *not* a new surface-table row, since `/scope`'s children emit
docs rather than PRs, so shape (b)'s observability cost is lower than
`/execute`'s was.

**Nothing here obliges `/charter` to follow.** The pattern permits substrate
divergence three ways over: the Layer-1/Layer-2 split was built for it
(`:512-517`), the `storage_substrate` variable names the parent-side value as
substitutable (`:374-384`), and the surface table is explicitly growable
(`parent-skill-child-inspection.md:65-67`). More directly, the two parents
already differ on a whole capability with the pattern's blessing (`:141-147`),
and the repo's own definition of "symmetric" is identical contract text at
structurally different locations
(`DESIGN-shirabe-child-dispatch-contract.md:359`).

**The cost estimate to carry into the ranking is small and empirically
grounded.** One substrate divergence has already run for a full release cycle.
Its cost was three-to-four stale sentences in the pattern doc, zero behavioral
failures, and zero duplicated Layer-1 text. That is the number, and it should
replace the feared "every future pattern change is written twice."

**The adoption proposal should widen, not carve out.** `:512-517` is the model:
name a second value for a Layer-1 element and record why widening beats naming
a variance. The override-slot rejection
(`DESIGN-shirabe-child-dispatch-contract.md:202`) forecloses the alternative.

**A cleanup PR is worth scoping alongside.** Four pattern passages are stale
against shipped parents (`:68-76` on I-6, `:585-589` on "nothing else",
`:655-658` on topic-slug-only dispatch, and `:692-693`'s phase-file literal).
Fixing them is independent of whether `/scope` adopts koto, and doing it first
would make the adoption diff read as a clean widening rather than as a fifth
exception piling onto four unacknowledged ones.

## Surprises

**The brief's cited ground for Decision 9 has been withdrawn by its own
document.** "Zero strategic hops are absorbable" is explicitly retracted at
`DESIGN-scope-consolidation-over-skipping.md:858-864`; the conclusion now rests
on "there is no consolidation judgment in `/charter` to change... extending it
would be new machinery." This makes the divergence case stronger, not weaker —
the parents differ because nobody built the second one, not because types
forbade it.

**`/execute` satisfies I-6 while the pattern still says v1 does not.**
`:68-71` calls the unsatisfied I-6 "the forcing function the amplifier layer's
value proposition depends on." `skills/execute/SKILL.md:479` binds I-6 in v1
through a `gh`-recovered home PR. A core-layer parent has done what the pattern
reserves for the amplifier layer, and the pattern has not noticed.

**`/execute` ships no `references/phases/` directory and claims full
conformance anyway.** Element 6's literal names those files
(`:692-693`); `skills/execute/SKILL.md:129-131` declines them and `:752-756`
asserts the conformance binding is "complete." This is the single most useful
precedent in the whole investigation, because it is exactly the element
koto adoption would break, and it has already been broken without incident.

**The Observability Surface's "nothing else" clause is already false for a
shipped parent** and is reconciled only by reading
`parent-skill-child-inspection.md`'s surface table as the operative rule. The
prior round's conclusion that this section needs widening is confirmed — but
the widening is one bullet about the *parent's own* state, not the harder
question about children.

**The `--upstream`-path inconsistency the brief flagged runs the other way from
what it looks like.** `phase-2-chain-orchestration.md:194-201` grounds
path-passing in the pattern's own "choosing among a child's shipped modes" rule
(`:346-352`), so the parents are conforming and the pattern's `:657-658` is the
stale text. It is the fourth instance of the same failure mode, which is why it
belongs in the cleanup scope.

## Open Questions

1. **Where does `/scope`'s koto session state live relative to git, and what
   does that do to the resume ladder?** `~/.koto/sessions/<name>/ctx` is
   untracked and machine-local. `/execute` anchored on a durable home PR
   (`skills/execute/SKILL.md:476-479`); `/scope` mid-chain has no PR. Needs a
   human call on whether `/scope` gets a durable anchor, accepts a
   machine-local resume boundary, or keeps `wip/` authoritative with koto as a
   projection.

2. **Is the koto session name topic-keyed enough to preserve I-4?** I-4
   (`:54-55`) requires concurrent invocations on different topics never
   interfere. `/execute` uses `execute-<plan-slug>` (`:183`). `scope-<topic>`
   presumably works, but `skills/scope/SKILL.md:958-963` already declares
   same-topic concurrent runs a no-go on wip-state contention — a shared
   `~/.koto` adds a second, machine-global contention surface that spans
   worktrees. Worth confirming this does not widen the no-go.

3. **Should the four stale pattern passages be fixed before, with, or after the
   adoption change?** Doing it first is cleaner and is independent work;
   bundling risks a large diff. This is a sequencing call for whoever owns the
   pattern doc.

4. **Does `storage_substrate` need a third named value, or is koto a Layer-2
   detail below it?** `:376-384` names `wip-yaml-md` as the v1 value and
   describes alternates as amplifier-layer identifiers that "SHALL satisfy
   I-6." A koto-sequenced `/scope` that keeps `wip/` authoritative arguably
   stays on `wip-yaml-md`; one that moves phase state into koto arguably does
   not, and would then inherit the I-6 obligation. This distinction may decide
   which of shape (a) and shape (b) is cheaper, and I could not resolve it from
   the text.

5. **Is the `/work-on`-as-fourth-parent migration still live?** It is named in
   two documents (`PRD-shirabe-scope-skill.md:968`,
   `DESIGN-shirabe-child-dispatch-contract.md:202`), but
   `DESIGN-work-on-koto-unification.md` exists and `/execute` has since
   absorbed the plan-orchestrator out of `/work-on`
   (`skills/execute/SKILL.md:209-211`). If `/work-on` becomes a fourth parent
   on koto, the substrate majority flips and the divergence question inverts.
   Someone with roadmap context should say.

## Summary

`/scope` and `/charter` may sit on different substrates: the pattern's
Layer-1/Layer-2 split was built for exactly this (`references/parent-skill-pattern.md:512-517`),
`/execute` already exercises it across four axes including one the pattern still
denies is possible in v1 (I-6), and the two authoring parents already differ on
a whole capability with the pattern's explicit blessing
(`:141-147`) — though the brief's cited justification for that difference has
since been withdrawn and replaced by a weaker one that helps the divergence
case rather than hurting it.

The conformance text that moves is small and identical under both candidate
shapes: structural element 6's phase-file literal (`:692-693`, already broken
by `/execute` without incident), element 5's resume ladder, and one bullet of
the Observability Surface (`:581-583`) widened from "the parent's own `wip/`"
to the parent's own state wherever its declared substrate puts it — the
Hand-Back Contract survives untouched because all seven of its steps key on the
artifact and git rather than on the call's return.

The biggest open question is where a koto-sequenced `/scope` anchors its resume:
`/execute` used a durable home PR, `/scope` mid-chain has none, and
`~/.koto/sessions/` is untracked and machine-global — which is also what decides
whether `/scope` still gets to declare `storage_substrate: wip-yaml-md` or
inherits the amplifier layer's I-6 obligation along with the new substrate.
