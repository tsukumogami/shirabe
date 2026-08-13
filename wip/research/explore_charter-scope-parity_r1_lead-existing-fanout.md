# Lead: How does the system already handle the fan-out it has?

Research question: the shirabe pipeline contains at least one genuine 1:N
fan-out -- a ROADMAP sequences MANY features, each becoming its own `/scope`
run. How is that fan-out modeled today, and is the pattern extensible to
fan-out INSIDE the strategic chain?

**Standing fact from the author (round 2):** the 1:N fan-out is LIVE in real
use on both strategic links -- multiple STRATEGYs under one VISION, and more
than one ROADMAP under a single STRATEGY. It is sanctioned in the format spec:
"One Active STRATEGY per bet at a time. Multiple STRATEGYs may operate under
one upstream VISION when they make distinct bets"
(`skills/strategy/references/strategy-format.md:277-279`). The artifacts live
in a private repo, so nothing in this repo exercises it.

All paths are relative to the shirabe repo root
(`public/shirabe/`, worktree `.claude/worktrees/charter-scope-parity`).

## Findings

### 1. The ROADMAP -> feature boundary

The fan-out lives **entirely inside one document** -- the ROADMAP's Features
section -- and crosses the boundary as free text, not as a link any tooling
maintains.

The canonical statement is `references/pipeline-model.md:193-210` ("Roadmap
branching"): a Roadmap decomposes into features, each feature gets a `needs-*`
label, "each feature's pipeline runs independently." The traceability diagram
at `references/pipeline-model.md:109-118` marks the boundary explicitly:
`Brief (upstream: Roadmap, per feature)` -- the only "per feature" annotation
in the whole chain. Inside the roadmap document the 1:N is the `Issues`
column, described at `references/issues-table.md:144-147` as "the one-to-many
fan-out of clickable issue links the feature decomposed into, encoding the
feature-to-issues altitude jump. This is the roadmap profile's defining
addition."

**How a feature row becomes a `/scope` run: it does not, mechanically.**

- `/brief` Input Mode 3 accepts a ROADMAP path and records it as `upstream:`
  (`skills/brief/SKILL.md:110-113`). That is the only place in the system
  where a downstream artifact binds to a roadmap, and a ROADMAP is the only
  document that mode accepts (`skills/brief/SKILL.md:116-128` rejects a PRD
  path as chain inversion).
- `/scope` never uses it. `/scope` invokes `/brief` with the bare topic slug:
  "It is the head of the chain, so there is nothing above it to hand it"
  (`skills/scope/references/phases/phase-2-chain-orchestration.md:165-167`).
  Every later child gets a path
  (`.../phase-2-chain-orchestration.md:168-179`), but the head does not.
- A case-insensitive grep for `roadmap` across
  `skills/scope/references/phases/*.md` and
  `skills/scope/references/state-schema.md` returns **zero hits**;
  `skills/scope/SKILL.md` never mentions ROADMAP either.

So a `/scope` run launched off a roadmap feature produces a BRIEF with no
`upstream:` back to the ROADMAP, and `/scope` has no notion that a roadmap
exists. The two chains do not reference each other through the parent skills.
The only bindings are author-typed: `/brief docs/roadmaps/ROADMAP-x.md`, or a
hand-written `**Downstream:**` line on the feature row.

### 2. Reverse traversal

Three separate mechanisms; none enumerates N downstream artifacts from a
ROADMAP.

**Downward (roadmap -> its downstream), by hand.** A per-feature
`**Downstream:**` line, e.g. `**Downstream:** PLAN-cascade-test-full.md`
(`skills/work-on/evals/fixtures/roadmaps/ROADMAP-cascade-test.md:19,26`). It
is *not* parsed -- the `Feature` struct carries only `id`, `label`, `needs`,
`dependencies`, `status`, `description`
(`crates/shirabe-validate/src/features.rs:40-65`) -- and it does not appear in
the per-feature format example
(`skills/roadmap/references/roadmap-format.md:129-141`). Only prose asks for
it: "Each feature should reference its downstream artifact ... when one
exists" (`skills/roadmap/references/roadmap-format.md:109-115`).

**Upward (downstream -> roadmap), by frontmatter walk.** `shirabe
finalize-chain` walks `upstream:` from a finished PLAN and dispatches on
filename prefix: DESIGN -> Current, PRD -> Done, BRIEF -> Done, `Roadmap` ->
`RoadmapHandoff` with `stop=true`, `VISION` -> `Stop`, anything else ->
`Error` (`crates/shirabe-validate/src/finalize.rs:426-451`). Note that
**`STRATEGY` is not a recognized prefix**; a walk reaching one would error
out, though it cannot, because ROADMAP terminates the walk.

**The roadmap-side match is a string grep on the plan slug.**
`handle_roadmap` greps the roadmap file for the plan slug on a line containing
`Downstream:`, walks up to the enclosing `### ` heading, rewrites that
feature's `**Status:**` to `Done` and its `**Downstream:**` to the DESIGN
basename (`skills/execute/scripts/run-cascade.sh:376-443`). The slug is
`basename "$PLAN_DOC" .md | sed 's/^PLAN-//'`
(`skills/execute/scripts/run-cascade.sh:680`). No match yields a `skipped`
step and no update (`.../run-cascade.sh:388-391`).

**Rollup.** Once every `**Status:**` line reads `Done`,
`handle_roadmap_deletion` checks that every `https://github.com/.../issues/N`
URL found in the file is closed, transitions the ROADMAP Active -> Done, and
`git rm`s it (`skills/execute/scripts/run-cascade.sh:489-553`). That is the
entire progress rollup: greps over one file's own text plus `gh` calls on URLs
found inside it.

So walking a ROADMAP to its N downstream artifacts happens only as **N
independent cascade runs**, each triggered by its own finished PLAN, each
locating its own row by slug substring match. Nothing goes the other
direction.

**`shirabe roadmap populate` is a within-document renderer**, not a
traversal: it reads the Features section, renders the Implementation Issues
table and the mermaid diagram, and structurally replaces the two reserved
sections (`skills/roadmap/SKILL.md:346-360`). The "reconciliation" in
`4df0c02` reconciles against each feature's *own* `**Status:**` plus an
optional `--mapping` seed -- `obtain_mapping` mints issues only for features
both absent from the seed and not already terminal
(`crates/shirabe/src/populate.rs:536-560`) -- never by reading a downstream
document. The one durable outward pointer it mints lives on GitHub, not in the
repo: issue bodies carry ``Roadmap: `<path>` `` and `Feature: <label>`
(`crates/shirabe/src/populate.rs:510-530`, test at `:1443-1459`).

### 3. What identifies a feature

Three coexisting identifiers, **all document-local**:

- **Positional 1-based index** -- `id`, "the source-of-truth identifier the
  dependency edges resolve against"
  (`crates/shirabe-validate/src/features.rs:41-45`). Heading form is
  cosmetic: `### Feature 1:` and `### ED1:` are equivalent because "features
  are numbered positionally in source order regardless of the tag"
  (`skills/roadmap/references/roadmap-format.md:147-165`).
- **The label** -- the table's key column since `d87a73b`, with an
  `is_stable_table_key` fixpoint test running the validator's own normalizers
  and an `F<n>` fallback when a label cannot key a row
  (`skills/roadmap/references/roadmap-format.md:417-425`).
- **The `F<n>` alias** -- `503fb14` gave FC06 a second, narrower resolution
  rule: a Dependencies token matching `^F[0-9]+$` that matched no entity-row
  key resolves against the nth entity row, 1-based, counting entity rows only
  (`crates/shirabe-validate/src/checks.rs`;
  `skills/roadmap/references/roadmap-format.md:385-398`). The commit message
  is explicit that "Resolution reads the parsed table alone, so FC06 stays
  document-local", and the plan profile's alias row count is zero.

The `needs-*` label is routing, not identity -- it selects which diamond the
feature enters (`references/pipeline-model.md:195-206`).

**None of this is reusable for identifying which STRATEGY sits under a
VISION.** All three are positions or strings inside a single Features section
parsed off `### ` headings. There is no cross-document identity scheme for a
child artifact anywhere in the system. The only cross-document key that exists
is the topic slug in the filename.

### 4. The asymmetry: can one `/charter` run produce more than one of a type?

No -- blocked in three independent places. Confirmed, and it matches the
author's account: the live fan-out arises **across** `/charter` runs, never
within one.

- `planned_chain` is "an ordered list of child-name strings", values from
  `{vision?, comp?, strategy, roadmap}`; `chain_ran` is "an ordered
  **sub-list of `planned_chain`**"
  (`skills/charter/references/phases/phase-state-management.md:130-141`). A
  sub-list of a name set cannot express repeats.
- `child_snapshots` is "a mapping from child-name to a `{path, status,
  content_hash}` block, with **one entry per child** in `planned_chain`"
  (`skills/charter/references/phases/phase-state-management.md:161-167`). A
  second STRATEGY has no key to live under.
- `exit_artifacts` on `full-run` is exactly two entries (STRATEGY + ROADMAP),
  or exactly one when `/roadmap` was declined *with* a matching
  `chain_skipped` entry; anything else is "a contract violation, not a chain
  shape" (`skills/charter/references/phases/phase-state-management.md:153-159`;
  `skills/charter/references/phases/phase-finalization.md:96-120`).

R9's hard finalization check enforces the shape closed and is not suppressed
by `--auto` (`skills/charter/references/phases/phase-state-management.md:290-345`).

`/strategy` is unconditional with no auto-skip -- "There is no condition under
which `/charter` skips `/strategy`"
(`skills/charter/references/phases/phase-2-chain-orchestration.md:188-196`).
So every `/charter` run writes exactly one new STRATEGY and (unless declined)
one new ROADMAP. There is no charter path that reuses an existing STRATEGY and
adds a second ROADMAP under it either.

### 5. The second `/charter` run, traced (critical path)

Setup: the author has an Active `docs/visions/VISION-A.md`. They open
`/charter` for a **distinct second bet**, which needs its own slug B so its
STRATEGY lands at `docs/strategies/STRATEGY-B.md` rather than overwriting A's.

**What charter looks up.** Exactly one path per child, built from the one
validated slug. The `/vision` gate: "Phase 1 inspects
`docs/visions/VISION-<topic>.md` for the topic slug; if nothing Accepted or
Active is there, `/vision` runs"
(`skills/charter/references/phases/phase-2-chain-orchestration.md:32-38`).
Phase 0 validates `$ARGUMENTS` byte-for-byte and rejects anything path-shaped
(`skills/charter/references/phases/phase-0-setup.md:47-137`). The resume
ladder's R14 rule confines decision logic to three sources, the first being
frontmatter `status:` read from the published path -- `VISION-<topic>.md`,
`STRATEGY-<topic>.md`, `ROADMAP-<topic>.md`
(`skills/charter/references/phases/phase-resume.md:434-448`). There is no
directory scan of `docs/visions/`, no query over `upstream:` fields, and no
prompt asking which VISION this bet sits under. "Topic-related child-doc
discovery" appears as a phrase in four places
(`skills/charter/SKILL.md:92,137,200-201`;
`skills/charter/references/phases/phase-0-setup.md:135`) but is never given a
procedure -- the only concrete lookup in the skill is the slug-derived path.

**Step by step:**

1. Phase 0 validates `B`, creates `wip/charter_B_state.md` with
   `phase_pointer: 0`, `exit: UNSET`
   (`skills/charter/references/phases/phase-0-setup.md:138-156`). No
   contention with A's state file.
2. Phase 1 detects visibility, runs the discover/converge loop, and surfaces
   the thesis-shift question verbatim
   (`skills/charter/references/phases/phase-1-discovery.md:139-197`).
3. The `/vision` gate inspects `docs/visions/VISION-B.md`. **Miss.** Charter
   concludes this is a cold start.
4. The cold-start rule is absolute: "A cold start is therefore always a
   `/vision` run -- there is no upstream thesis to build on, and **nothing the
   author says about the thesis changes that**"
   (`.../phase-2-chain-orchestration.md:36-38`). The author's thesis-shift
   answer is classified and then cannot matter: the classification "decides
   the `/vision` invocation **only when** an Accepted or Active VISION already
   exists at `docs/visions/VISION-<topic>.md`"
   (`.../phase-1-discovery.md:150-155`). Note precisely what has gone wrong:
   there **is** an upstream thesis -- VISION-A -- and charter has concluded
   there is none because it looked at exactly one path.
5. The chain proposal reads "run `/vision`" -- it is "the only child whose
   entry turns on what is already on disk: it reads 'run' on every cold start"
   (`.../phase-1-discovery.md:242-245`).
6. `/vision` is invoked, and "The invocation passes ONLY the topic slug"
   (`.../phase-2-chain-orchestration.md:64-71`). `/vision`'s own resume logic
   detects an existing VISION only "when one is present at the published
   path"; `docs/visions/VISION-B.md` is not
   (`skills/vision/references/phases/phase-3-draft.md:15`), so it drafts
   fresh.
7. **A second VISION is written** at `docs/visions/VISION-B.md`, status Draft
   (`skills/vision/SKILL.md:192-194`). The correct behavior -- reuse VISION-A
   -- never becomes reachable.
8. `/strategy` then takes upstream shape 2, which requires "A VISION exists
   for the topic (either ran earlier in this chain or already Accepted/Active
   at the published path)" (`.../phase-2-chain-orchestration.md:204-209`).
   That resolves to the **just-created VISION-B**. STRATEGY-B records
   `upstream: docs/visions/VISION-B.md`. VISION-A is never read, never linked.
9. `/roadmap` fires with `--upstream docs/strategies/STRATEGY-B.md`
   (`.../phase-2-chain-orchestration.md:362-372`).
10. Finalization writes `exit: full-run` with two `exit_artifacts` and R9
    passes (`skills/charter/references/phases/phase-finalization.md:113-120`).
    Nothing anywhere objects.

**Net effect:** the author gets a duplicate thesis document, and the second
bet is attached to the duplicate instead of to the real VISION. The fan-out
the format spec sanctions is inverted into a fork of the vision layer.

#### Is there any way to tell charter "reuse VISION-A"?

No. Exhaustively:

- **Input modes** -- only empty, or a string matching `^[a-z0-9-]+$`. Paths
  are explicitly rejected, and the rejection table names
  `docs/visions/VISION-foo.md` as a worked example
  (`skills/charter/SKILL.md:61-93`;
  `skills/charter/references/phases/phase-0-setup.md:83-137`).
- **Flags** -- `/charter` parses `--auto`, `--interactive`, `--max-rounds=N`
  and nothing else (`skills/charter/SKILL.md:97-106`). No `--upstream`.
- **State schema** -- 17 fields, fully enumerated
  (`skills/charter/references/phases/phase-state-management.md:100-211`). None
  is an upstream pointer. `child_snapshots` holds paths but is written from
  child results, never from author input.
- **Phase 1 "Adjust"** -- can "force a previously-skipped child on ... opt out
  of a child that would otherwise fire, or reframe the topic entirely"
  (`.../phase-1-discovery.md:296-304`). Opting `/vision` out is expressible.
  **It does not help.** With no VISION at `docs/visions/VISION-B.md`,
  `/strategy`'s upstream shape 2 still does not hold, so charter falls to
  shape 1 (freeform topic, no upstream artifact,
  `.../phase-2-chain-orchestration.md:198-203`) and STRATEGY-B is drafted with
  the field omitted (`skills/strategy/references/phases/phase-2-draft.md:78-82`,
  "omit field if none"). The escape hatch trades a duplicate VISION for an
  orphaned STRATEGY.
- **Reframing to slug A** -- the only remaining lever, and it collides:
  `docs/strategies/STRATEGY-A.md` already exists, so resume-ladder rows 5/6
  match on that exact path and read the run as re-entry into the *same* bet,
  offering Re-evaluate / Revise / Bail
  (`skills/charter/references/phases/phase-resume.md:168,216`).

Slug-sharing (needed for the VISION lookup to hit) and slug-distinctness
(needed for STRATEGY-B not to clobber STRATEGY-A) are mutually exclusive under
a single `<topic>` key. This is independent of the state schema: all three
canonical paths plus `wip/charter_<topic>_state.md` derive from that one slug,
so even a schema that allowed repeats would resolve them to one filename.

#### What does "One Active VISION per project at a time" do about it?

**Nothing. It is unenforced prose.** The rule is at
`skills/vision/references/vision-format.md:170` (and restated at
`docs/designs/current/DESIGN-vision-artifact-type.md:277`). No check
implements it, and no check could as things stand:

- **Per-file validation of a VISION runs four generic checks and one
  format-specific one.** `validate_file` runs FC01-FC04, FC15, writing-style,
  eval-fixture, CLAUDE.md-conventions, and `check_upstream_resolves`, then
  dispatches on format; the `"VISION"` arm is a single call to
  `check_vision_public` -- a public-repo prohibited-sections check
  (`crates/shirabe-validate/src/validate.rs:182-262`;
  `crates/shirabe-validate/src/checks.rs:824-841`). All of it is
  single-document. The `"Strategy"` arm is likewise only
  `check_strategy_public`.
- **The only corpus-wide check family is the L-family, and it does not index
  the strategic chain.** `build_doc_index` walks exactly `docs/briefs`,
  `docs/prds`, `docs/designs`, `docs/designs/current`, `docs/plans`,
  `docs/roadmaps` (`crates/shirabe-validate/src/lifecycle.rs:275-283`) and
  filters to filenames prefixed `BRIEF-`/`PRD-`/`DESIGN-`/`PLAN-`/`ROADMAP-`
  (`.../lifecycle.rs:305-312`). **`docs/visions/` and `docs/strategies/` are
  not indexed at all.** The check codes are L01-L07
  (`.../lifecycle.rs:13-36`); none is a uniqueness or sibling-count rule.
- **`shirabe transition` enforces only the status graph.** The VISION spec is
  a four-state graph with three edges and three named rejections
  (`crates/shirabe-validate/src/transition.rs:279-300`). The documented
  "Active: ... plus at least one Downstream Artifact entry"
  (`skills/vision/references/vision-format.md:180`) has no implementation --
  no downstream check appears in the VISION arm.
- **CI validates changed files only**, positionally, with no corpus pass over
  visions (`.github/workflows/validate-docs.yml:79-100`). The
  `--lifecycle` pass in `lifecycle.yml:135-137` runs the L-family, which as
  above never sees `docs/visions/`.

So the second VISION passes every gate cleanly, at write time and forever
after. The duplicate is invisible to tooling; the only detector is a human
reading `docs/visions/`.

### 6. The manual fallback has the same defect, mirrored

`/charter`'s non-interference rule makes direct child invocation "first-class
steady-state capability, not a degraded path"
(`skills/charter/references/phases/phase-1-discovery.md:73-88`), so the
by-hand route is the sanctioned one. It works for one strategic link and not
the other, and the reason is a two-line difference between two skills.

**`/roadmap` decouples slug from upstream.** It takes `--upstream <path>` as a
flag, independent of the topic (`skills/roadmap/SKILL.md:165-173`;
`skills/roadmap/references/phases/phase-3-draft.md:32-35`). Its own eval
covers exactly the fan-out shape: `/roadmap platform-consolidation --upstream
docs/strategies/STRATEGY-platform.md` -- different slug, explicit upstream
(`skills/roadmap/evals/evals.json:117-124`). **N ROADMAPs under one STRATEGY
is expressible by hand.**

**`/strategy` couples them.** It has **no `--upstream` flag** (a grep for
`--upstream` across `skills/strategy/`, `skills/vision/`, `skills/roadmap/`,
`skills/brief/` hits only `/roadmap`). Its Input Mode 3 takes a VISION path
(`skills/strategy/SKILL.md:113-116`), and Phase 0 derives the slug **from that
path's basename**: "If `$ARGUMENTS` is a path argument, take the basename,
strip the `VISION-` or `PRD-` prefix and `.md` suffix, and use the remainder"
(`skills/strategy/references/phases/phase-0-setup.md:98-103`). So:

- `/strategy docs/visions/VISION-A.md` for a second distinct bet derives slug
  **A**, targets `docs/strategies/STRATEGY-A.md`, and hits `/strategy`'s own
  resume row "STRATEGY exists with status Accepted or Active -> Offer to
  revise or start fresh" (`skills/strategy/SKILL.md:190`). It cannot create a
  sibling.
- `/strategy <freeform-topic-b>` (Input Mode 5) gets slug B, but passes no
  VISION path, so no upstream is recorded and the draft omits the field
  (`skills/strategy/references/phases/phase-2-draft.md:78-82`).

The internal plumbing to separate them already exists -- Phase 0 records the
mode and the upstream in `wip/strategy_<topic>_context.md`, and Phase 2 reads
`## Recorded Upstream` to write the frontmatter
(`skills/strategy/references/phases/phase-0-setup.md:63-64`;
`.../phase-2-draft.md:85-87`). Only the slug-derivation rule ties the two
together.

**Consequence:** no shipped code path produces a second STRATEGY under an
existing VISION with *both* a distinct slug and a correct `upstream:`. The
live artifacts in the private repo were therefore either hand-authored or had
`upstream:` hand-edited after a freeform run. That is an inference from the
code paths, not something confirmed against the private repo.

## Implications

- The one demonstrably-working fan-out (ROADMAP -> features) is **not a
  mechanism**; it is the absence of one. It works because each downstream unit
  is a wholly separate parent run with its own slug and state file, and
  because the cross-chain link is free text a human writes. There is no
  reusable fan-out primitive to lift into the strategic chain.
- The blocker on strategic fan-out is the **slug-keyed canonical-path
  convention**, not the state schema. Every artifact path and the state-file
  path derive from one `<topic>`, so 1:1 is forced before any schema field is
  consulted.
- The decisive difference between the link that works by hand and the link
  that does not is one flag: `/roadmap` has `--upstream`, `/strategy` does
  not, and `/strategy` instead derives its slug from the upstream's basename.
- `/charter` cannot express either strategic fan-out, because it always
  invokes `/strategy` (unconditional, no auto-skip) and always keys on one
  slug. Every second bet through `/charter` forks the vision layer.
- Nothing detects the fork. The strategic chain's two top altitudes sit
  outside the only corpus-wide check the validator has.

## Surprises

- **The document formats already model the 1:N the skills cannot produce.**
  `skills/vision/references/vision-format.md:65-67` defines Downstream
  Artifacts as "added when the **first** STRATEGY that operationalizes this
  VISION exists. Lists paths to the STRATEGY **documents** that carry the
  thesis forward" -- plural, with "first" implying successors.
  `skills/strategy/references/strategy-format.md:277-279` states the rule
  outright. `skills/roadmap/references/roadmap-format.md:81-82` mirrors it
  from below. No code reads any of these lists.
- **`docs/visions/` and `docs/strategies/` are invisible to the corpus-wide
  validator** (`crates/shirabe-validate/src/lifecycle.rs:275-312`). Every
  cross-document rule the strategic chain documents -- one Active VISION per
  project, Active requires a downstream STRATEGY -- is unenforced prose.
- **The cold-start rule's own words invert on this case.** "There is no
  upstream thesis to build on" is false in exactly the situation that matters;
  it is true only of the path charter looked at.
- **Adjust cannot save it.** Dropping `/vision` produces an orphaned STRATEGY
  rather than a linked one, because `/strategy`'s upstream shape is keyed on
  the same path that just failed to exist.
- **The manual fallback fails in the mirror image.** `/strategy` handed a
  VISION path inherits that VISION's slug, so a second bet targets the first
  bet's filename.
- **`/scope` diagnoses its own version of this gap and does not close it.**
  `skills/scope/references/phases/phase-2-chain-orchestration.md:199-202`
  argues for passing paths to children because a child handed a bare slug
  "records no `upstream:` link back to it" -- which is what still happens to
  `/brief` three lines above at `:165-167`.
- **The feature -> downstream link the cascade depends on is unparsed and
  undocumented in the format spec** (`run-cascade.sh:386` greps for
  `**Downstream:**`; absent from `features.rs:40-65` and from the format
  example at `roadmap-format.md:129-141`).
- **`STRATEGY` is not a recognized prefix in the upstream walk**
  (`crates/shirabe-validate/src/finalize.rs:426-451`) -- reaching one would
  produce `NodeAction::Error`.

## Open Questions

- How were the live private-repo artifacts actually produced? The code paths
  admit no clean route, so either they were hand-edited, or a path exists that
  this pass did not find.
- Is the `**Downstream:**` feature field meant to be part of the roadmap
  format (parsed and validated), or is it cascade-internal convention? The
  three sources disagree.
- Was the VISION -> STRATEGY 1:N ever expressible through tooling, or has it
  always been a by-hand convention that the format spec documented and the
  skills never implemented? Nothing in `docs/` was found arguing either way.
- What consumes the `Downstream Artifacts` sections at all? No reader found.
- Does the private repo's `/charter` usage already show the duplicate-VISION
  symptom (multiple visions where one was intended)? Not checkable from here,
  and it would be the fastest confirmation that the trace above is what
  actually happens in practice.

## Summary

The ROADMAP -> features fan-out is not a mechanism the system implements; it
is what happens when the system does nothing. N features become N wholly
independent `/scope` runs, each with its own slug and state file, linked to
the roadmap only by text a human types. Reverse traversal is likewise N
independent events: each finished PLAN walks `upstream:` up to the ROADMAP,
then a grep finds its feature row by plan slug and flips one `**Status:**`.
Feature identity (positional `id`, label, `F<n>`) is deliberately
document-local and cannot name a sibling STRATEGY.

The critical path is the second `/charter` run. With an Active VISION-A on
disk and a distinct second bet needing slug B, charter's only lookup --
`docs/visions/VISION-B.md` -- misses, charter concludes "there is no upstream
thesis to build on", the cold-start rule fires unconditionally, and `/vision`
writes a **second VISION at `docs/visions/VISION-B.md`**. `/strategy` then
binds STRATEGY-B to that duplicate rather than to VISION-A, and the run
finalizes clean. There is no input, flag, state field, or Adjust branch that
says "reuse VISION-A": charter rejects paths by design, parses only
`--auto`/`--interactive`/`--max-rounds`, has no upstream field in its 17-field
schema, and dropping `/vision` via Adjust yields an orphaned STRATEGY with
`upstream:` omitted instead. Reusing slug A to make the lookup hit collides on
`docs/strategies/STRATEGY-A.md` and is read as re-entry into the same bet.

Nothing catches the duplicate. "One Active VISION per project at a time"
(`vision-format.md:170`) has no implementation: per-file validation of a
VISION is FC01-FC04/FC15 plus a public-visibility section check, `shirabe
transition` enforces only the status graph, and the one corpus-wide check
family indexes `docs/{briefs,prds,designs,plans,roadmaps}` -- never
`docs/visions/` or `docs/strategies/`.

The by-hand route, which `/charter` explicitly protects as first-class, works
for one link and not the other because of a two-line difference: `/roadmap`
takes `--upstream <path>` independent of its topic slug (its evals cover the
exact fan-out shape), while `/strategy` has no such flag and derives its slug
from the upstream VISION's basename -- so a second bet under VISION-A either
inherits slug A and targets the first STRATEGY's filename, or takes a freeform
slug and loses the upstream link entirely. N ROADMAPs under one STRATEGY is
expressible by hand; N STRATEGYs under one VISION is not expressible at all,
by hand or through `/charter`, with both a distinct slug and a correct
`upstream:`.
