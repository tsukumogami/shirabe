# Lead: Does /scope's skip vocabulary have a slot for reuse-under-fan-out?

Research question: does shirabe's parent-skill vocabulary have a slot for
"an upstream artifact is reused by more than one downstream artifact", or
does it only know two reasons a child might not run? All citations are
file:line against the `charter-scope-parity` worktree.

## Findings

### 1. The gate vocabulary has three shapes, none of which is reuse

`references/parent-skill-pattern.md:113-172` names exactly three gate
shapes and requires that "every child-invocation gate in every parent
SHALL be one of these three." Each is a statement about *this chain's*
relationship to *this child's own output slot*:

- **ALWAYS** (`:123-137`) — "the child is invoked unconditionally on
  every chain run; no gate exists." An optional author declination is
  "author-supplied input, not a predicate the parent computes."
- **shape-dependent** (`:139-147`) — "the child invocation's *form*
  (which sub-shape of the child fires, with how many peers, against
  which set of inputs) is determined by an upstream-recorded predicate
  on the chain. The gate is not whether-to-invoke but how-to-invoke."
  This is the only shape that reads an upstream at all, and it reads it
  to size a roster — never to conclude that an existing upstream already
  serves the purpose.
- **Mandatory-with-auto-skip** (`:148-168`) — "the child SHALL be
  invoked unless **its** durable artifact already exists at the
  published-Accepted status at **the canonical path**, in which case the
  child is recorded in `chain_skipped` and the chain proceeds to the next
  gate."

The third definition is where the answer lives. Its predicate is
possessive and path-canonical: what closes the gate is the child's own
output file at the child's own canonical path. An upstream artifact
belonging to a different topic, merely being consumed by this run, cannot
satisfy that predicate — it is not at the path the gate inspects.

The optional-override clause (`:174-179`) does not help either: "An
override is not a second route into the child. It can only fire in the
case the auto-skip would otherwise have closed the gate." The retired
EITHER-signal note (`:181-195`) records that the pattern has already been
through one round of collapsing a would-be fourth shape into this one,
on the finding that "the artifact state decides."

The nearest thing to a third reason a child does not run is the
Conditional Feeder Invocation Shape (`:197-242`) — a three-condition gate
for a side-channel child. It is explicitly not reuse, and explicitly not
recorded: "a child whose gate never opened was never planned, so there is
nothing to record" (`:222-224`).

Nothing in the Required SKILL.md Structural Elements
(`references/parent-skill-pattern.md:540-565`) or the prompt-literal
rules (`:566-599`) contemplates a shared upstream either.

### 2. The skip reason is free text at the pattern layer, enum-ish in practice

`references/parent-skill-state-schema.md:141-145` defines the triad, with
`chain_skipped` as "children the chain decided to skip, with **free-text**
reasons." `/charter` repeats this at
`skills/charter/references/phases/phase-state-management.md:141-144`:
"The reasons are NOT parsed by tooling — they are durable evidence for
human readers." So mechanically a reason string could carry "reused, not
re-derived" today.

Semantically nothing licenses it, and `/scope` has closed the door.
`skills/scope/references/state-schema.md:38-48`: Phase 1 "writes exactly
one reason, `settled-artifact-at-canonical-path-reentry-protection`; a
child is never recorded here because the chain judged its artifact not
worth producing, since `/scope` makes no such judgment before an artifact
exists." Same disavowal in prose at
`skills/scope/references/phases/phase-1-discovery.md:133-140`. Two
reasons exist in `/scope`'s vocabulary — Phase 1 re-entry protection, and
one Phase 2 reason when a Reject at a settled-upstream boundary ends the
chain (`state-schema.md:46-48`) — and neither is reuse.

### 3. The semantic test: the answer is (c), and the skip never fires for it

Scenario: an Active `VISION-platform-thesis.md` exists; the author opens
`/charter` for a second, different strategic bet under it.

`/charter` accepts a topic slug and nothing else.
`skills/charter/SKILL.md:81-93` rejects paths outright, using
`/charter docs/visions/VISION-foo.md` as the worked rejection, and states
that upstream references are "detected during Phase 1 discovery by
inspecting the topic-related child docs that exist in the repo." That
phrase is never operationalized beyond an exact-slug path check:
`skills/charter/references/phases/phase-1-discovery.md:151-155` and
`phase-2-chain-orchestration.md:32-38` both inspect
`docs/visions/VISION-<topic>.md` for the run's own slug. (Grep for
"topic-related" returns only prose mentions — `SKILL.md:92,137,200`,
`phase-0-setup.md:135`, `phase-1-discovery.md:131` — no mechanism.)

So the second bet takes a new slug, `VISION-<new-slug>.md` does not
exist, and the gate reads cold start: "A cold start is therefore always a
`/vision` run" (`phase-2-chain-orchestration.md:36-38`). `/vision` fires
and writes a brand-new VISION at `docs/visions/VISION-<new-slug>.md`
(`skills/vision/SKILL.md:49`, `:194`). It clobbers nothing — `/vision`'s
resume ladder rows for an existing VISION (`skills/vision/SKILL.md:147-148`,
"Offer to revise or start fresh") only match the same path.
**The auto-skip is never reached in the reuse scenario.**

If the author instead reuses the same slug, they do not get a second bet
either: `docs/strategies/STRATEGY-<topic>.md` is already Accepted, so
Row 5 of the resume ladder fires with the co-equal
`Re-evaluate / Revise / Bail` prompt
(`skills/charter/references/phases/phase-resume.md:164-176`).

Answer to the three-way question: **(c)** — the VISION is a shared
upstream being reused by a new downstream, and nothing needed to be
written. But **charter's `/vision` skip is not currently misfiled.**
Every run on which that skip actually fires is a same-slug run, where
re-running `/vision` would revise or rewrite the very file the skip
protects. Re-entry protection is the honest description of it. The defect
is narrower and different: the reuse case has no representation anywhere
in `/charter`, because there is no input mode for a differently-slugged
upstream and no gate predicate that reads one.

One coincidence hides this. When the same-slug skip does fire, the chain
then hands that same VISION to `/strategy` as its upstream —
`phase-2-chain-orchestration.md:206-209`: "A VISION exists for the topic
(either ran earlier in this chain or already Accepted/Active at the
published path). `/charter` passes the VISION path; `/strategy` reads it
as its Input Mode 3 upstream." Reuse is therefore already happening on
every skipped-`/vision` run; it rides along on slug identity and is
recorded only as protection. Nothing in the state file says this run's
STRATEGY hangs off an upstream the run did not write.

Reuse is real in the artifact model, independent of the gates:

- `skills/vision/references/vision-format.md:65-67` — Downstream
  Artifacts "Lists paths to the STRATEGY **documents** that carry the
  thesis forward" (plural).
- `skills/vision/references/vision-format.md:133` — "Active | **At least
  one** STRATEGY references this VISION as its upstream." One VISION to
  many STRATEGYs is a designed lifecycle state.
- `skills/strategy/SKILL.md:113-116` — Input Mode 3 takes any VISION path
  as the new STRATEGY's upstream, with no slug coupling and no
  exclusivity. A standalone `/strategy docs/visions/VISION-<other>.md`
  produces the second bet that `/charter` cannot.

### 4. The tactical chain is single-use per topic slug

Inside `/scope`'s four children, every canonical path is keyed by the one
topic slug — see the settled-status table at
`skills/scope/references/phases/phase-1-discovery.md:117-122`. One run
produces at most one of each.

Nothing forbids a second DESIGN off the same PRD:
`skills/design/SKILL.md:143` accepts any path matching
`docs/prds/PRD-*.md` with status Accepted; `skills/plan/SKILL.md:236-239`
accepts any DESIGN, PRD, or ROADMAP path;
`skills/prd/references/prd-format.md:92-93` lists Downstream Artifacts as
"design docs, plans, issues, or PRs". But a second DESIGN needs a second
topic slug and therefore a second `/scope` run — within one run each
artifact is single-use. The BRIEF format is the one place that reads
one-to-one: "Done | The **downstream PRD** has operationalized the brief"
(`skills/brief/references/brief-format.md:200`, and the transition table
at `:215`). I found no statement permitting or forbidding one PRD feeding
two DESIGNs; the question is simply not addressed anywhere.

The genuine tactical one-to-many sits one level up and *outside* the
chain: one ROADMAP sequences many features, each referencing "its
downstream artifact (brief, PRD, design doc, or plan)"
(`skills/roadmap/references/roadmap-format.md:110-111`), and `/brief`
Input Mode 3 takes a ROADMAP path as upstream
(`skills/brief/SKILL.md:110-113`). That is a shared upstream serving many
`/scope` runs — and it needs no vocabulary at all, because the ROADMAP is
an *input*, never a member of `planned_chain`
(`skills/scope/references/state-schema.md:30-35`: the chain "always
starts at `brief`").

### 5. Absorbability is tied to section-mapping totality, not to successor count

Added after other leads confirmed VISION to STRATEGY fan-out is live in the
real corpus, and that PRD to DESIGN fans out in three real cases (1:2, 1:4,
1:9) while BRIEF to PRD is 58/58 exactly 1:1.

`/scope`'s consolidation judgment states one absorbability criterion, and it
is a property of the two *formats*, not of the graph. Stage 1
(`skills/scope/references/phases/phase-2-chain-orchestration.md:395-415`):
"Absorption is available only where the downstream type's required sections
provide a home for **every** required section of the upstream type, so an
absorb never has to discard content or invent somewhere to put it." The
verdict table at `:402-406` marks BRIEF to PRD absorbable and the other two
hops not, and `:408-411` says the verdicts "are derived from the per-type
required-section contracts in `crates/shirabe-validate/src/formats.rs`, not
enumerated by hand."

Nothing in Stage 1, Stage 2 (`:417-434`), Stage 3 (`:436-479`), the cascade
note (`:481-487`), or the pattern doc ties absorbability to the upstream
having a single successor. The only appearance of successor count anywhere is
an incidental clause inside Stage 2's leaning prior (`:428-434`): "a BRIEF
that fed **one** PRD and did no independent framing work is a redundant
document rather than a redundant paragraph." That is a description of the
common case inside a prior about content redundancy, not a precondition, and
no verdict is gated on it. The upstream rationale assumes singularity the
same way: "Each document's fate is settled one step later, once **its
successor** lands"
(`docs/briefs/BRIEF-scope-consolidation-over-skipping.md:88-91`).

So the absorbable hop being the uniformly-1:1 hop is a coincidence with
respect to the stated rule. Mapping totality would license an absorb on a
fanned-out hop just as readily if the two formats happened to line up.

The absorb mechanics have no guard either. Stage 3 reads the absorbed
artifact's own `upstream:`, re-points **the survivor's** `upstream:`, then
`git rm`s the absorbed artifact and re-runs `shirabe validate` **on the
survivor** (`:463-479`). R6 is a per-doc check on the doc under test — it
flags a dangling `upstream:` in that doc, not other docs pointing at a
deleted file (`crates/shirabe-validate/src/checks.rs:771-822`,
`check_upstream_resolves`). And CI validates only the PR's changed files
(`.github/workflows/validate-docs.yml:88-100`). A sibling downstream still
pointing at an absorbed upstream would therefore survive both the absorb-time
re-validation and that PR's CI, surfacing only when the sibling is next
touched. Nothing anywhere counts consumers.

The fan-out on the PRD to DESIGN hop is produced by the child mid-run, not
planned by the parent: `/design`'s scaling heuristic
(`skills/design/references/phases/phase-1-decomposition.md:37-46`) counts
independent decision questions and, at 8-9, presents a split proposal
requiring confirmation; at 10+ it refuses and requires splitting. `/scope`
has one `design` slot with one canonical path
(`skills/scope/references/phases/phase-1-discovery.md:121`), and the
hand-back contract's R20 check looks for one canonical artifact path
(`references/parent-skill-pattern.md:459-465`).

## Implications

The asymmetry between the two parents is structural, not stylistic.
`/scope`'s constant `planned_chain` works because everything it can skip
is something it would itself write; its one shared upstream (the ROADMAP)
lives outside the chain and so never needs a skip reason. `/charter` puts
`/vision` *inside* `planned_chain` while VISION is the one artifact in
the system explicitly designed to outlive and serve multiple downstream
runs (`vision-format.md:133`).

That means any reuse-under-fan-out has to be expressed as a skip in
`/charter` — and the only skip vocabulary available is keyed to the
child's own canonical path and the run's own topic slug. The result today
is not a wrong reason string; it is an unreachable case. An author with a
live VISION and a second bet gets a cold-start `/vision` run under a new
slug, i.e. a second VISION document, with no way to say "this bet hangs
off the existing thesis."

## Surprises

- **The reuse skip cannot fire.** I expected to find charter's `/vision`
  skip doing double duty and being misfiled. It isn't: slug-keying means
  the only runs that reach the skip are the ones where re-entry
  protection is literally correct. The gap is an absent case, not a
  mislabelled one.
- **Standalone `/strategy` is strictly more capable than `/charter` here.**
  `strategy/SKILL.md:113-116` accepts an arbitrary VISION path;
  `/charter` rejects paths by construction (`charter/SKILL.md:81-93`).
  The parent cannot express an upstream relationship its own child can.
- **`/charter`'s `planned_chain` is not constant, unlike `/scope`'s
  post-PR-#260 chain**, and its own docs are not fully consistent about
  the skipped case: `phase-state-management.md:127-136` declares
  `planned_chain: [vision?, comp?, strategy, roadmap]` with `vision`
  conditional on its Phase 1 gate, while
  `phase-2-chain-orchestration.md:44` records a skipped `/vision` in
  `chain_skipped` — which per `:125` is "for children that were
  **planned** and then dropped." `child_snapshots` further requires "one
  entry per child in `planned_chain`"
  (`phase-state-management.md:160-162`). Whether a skipped `/vision` is a
  member of `planned_chain` is unsettled by the current text.
- **R4's wording already gestures at the missing concept.**
  `docs/prds/PRD-shirabe-charter-skill.md:290-294` says the skip applies
  to a VISION "matching the chain's scope" — a scope-match notion the
  implementation renders as an exact-slug path check and nothing more.

## Open Questions

- Is one PRD feeding two DESIGNs intended, tolerated, or forbidden? No
  document says. `prd-format.md:92-93` permits plural downstream links;
  `brief-format.md:200` reads one-to-one for BRIEF to PRD; the `/scope`
  chain is slug-keyed and therefore silent on the cross-run case. (Other
  leads report it happening three times in the real corpus, produced by
  `/design`'s split heuristic at
  `design/references/phases/phase-1-decomposition.md:37-46`.)
- Where does a split DESIGN land in `/scope`'s state? The chain has one
  `design` slot and one canonical path
  (`scope/references/phases/phase-1-discovery.md:121`), and the hand-back
  R20 check tests one path (`parent-skill-pattern.md:459-465`).
- Should Stage 1 absorbability test consumer count as well as
  section-mapping totality? Today only the latter is stated
  (`scope/references/phases/phase-2-chain-orchestration.md:395-415`), and
  nothing detects a sibling left pointing at an absorbed artifact.
- Does a skipped `/vision` belong in `/charter`'s `planned_chain`? The
  three cited passages disagree (see Surprises).
- Should the reuse relationship be recorded anywhere durable? Today a
  STRATEGY records its upstream VISION in frontmatter
  (`strategy/SKILL.md:46-48`), and the VISION records its downstream
  STRATEGYs (`vision-format.md:65-67`), but the parent's state file has
  no field saying this run consumed an upstream it did not produce.
- Would `/charter` accepting a VISION path conflict with its
  path-rejection rule (`charter/SKILL.md:81-93`), or is that rule aimed
  only at the topic-slug argument slot?

## Vocabulary surfaces that would carry a new term

Pattern layer:

- `references/parent-skill-pattern.md:113-172` — the three gate shapes;
  Mandatory-with-auto-skip at `:148-168`; override clause at `:174-179`;
  retired-EITHER-signal note at `:181-195`.
- `references/parent-skill-pattern.md:197-242` — Conditional Feeder
  Invocation Shape, including the never-recorded rule at `:220-230`.
- `references/parent-skill-pattern.md:540-565` — Required SKILL.md
  Structural Elements; prompt-literal rules at `:566-599`.
- `references/parent-skill-state-schema.md:136-152` — chain-tracking
  triad and `chain_skipped`'s free-text reasons; `:70-101` for the
  parent-specific conditional-field precedent; `:215-255` for R9's
  conditional-field checks.

`/charter`:

- `skills/charter/SKILL.md:61-93` (input modes, path rejection), `:223`
  (gate-shape line in the reference table).
- `skills/charter/references/phases/phase-1-discovery.md:139-203`
  (thesis-shift prompt and signal categories), `:216-284` (chain-proposal
  skip entries and stated reasons).
- `skills/charter/references/phases/phase-2-chain-orchestration.md:22-71`
  (`/vision` rule), `:113-129` (never-recorded rule), `:184-225` (the
  three upstream shapes passed to `/strategy`), `:330-339`
  (`chain_skipped` entry shape).
- `skills/charter/references/phases/phase-state-management.md:127-144`
  (`planned_chain` / `chain_skipped`), `:160-167` (`child_snapshots`
  one-per-planned-child), `:222-244` (schematic YAML).
- `skills/charter/references/phases/phase-finalization.md:75-105`
  (state-field assignments; AC11a declination coupling).
- `skills/charter/references/phases/phase-resume.md:164-176` (Row 5
  status-aware re-entry).

`/scope`:

- `skills/scope/references/phases/phase-1-discovery.md:107-146`
  (re-entry protection, settled-status table, not-a-worth-judgment
  paragraph).
- `skills/scope/references/state-schema.md:30-48` (`planned_chain` and
  the single reason string).
- `skills/scope/references/phases/phase-2-chain-orchestration.md:511`,
  `phase-3-exit-finalization.md:69` (consumers of `chain_skipped`).

Upstream requirement docs fixing the current wording:
`docs/prds/PRD-shirabe-charter-skill.md:290-327` (R4) and `:843-858`
(its ACs); `docs/designs/current/DESIGN-shirabe-scope-skill.md:1055-1090`;
`docs/prds/PRD-scope-consolidation-over-skipping.md:232-247`.

## Summary

The parent-skill vocabulary knows exactly two reasons a planned child
does not run — re-entry protection against a settled artifact at the
child's own canonical path (`parent-skill-pattern.md:148-168`,
`scope/references/phases/phase-1-discovery.md:107-146`) and an author
declination of an ALWAYS child (`parent-skill-pattern.md:129-135`) — plus
a third, unrecorded case for feeder children whose gate never opened
(`:197-242`). There is no slot for "this upstream is being reused by a
new downstream."

Shared-upstream reuse is nonetheless real in the artifact model: a VISION
is Active precisely when at least one STRATEGY points at it
(`vision-format.md:133`), its Downstream Artifacts section is plural
(`:65-67`), and `/strategy` accepts any VISION path as upstream
(`strategy/SKILL.md:113-116`). The tactical chain has the same shape one
level up, where a single ROADMAP fans out into many BRIEFs
(`roadmap-format.md:110-111`, `brief/SKILL.md:110-113`) — but there the
shared upstream is an input rather than a chain member, so no skip
vocabulary is needed.

Charter's `/vision` skip is correctly filed as re-entry protection: it is
reachable only on same-slug runs, where re-running `/vision` would
rewrite the file in place. What is missing is any representation of the
reuse case at all — `/charter` is slug-keyed end to end
(`charter/SKILL.md:81-93`, `phase-2-chain-orchestration.md:32-38`,
`:206-209`), so a second bet under a live VISION reads as a cold start
and authors a second VISION.
