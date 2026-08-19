# Lead: What does the parent-skill pattern require of every parent, and what does `/scope` carry beyond it?

## Findings

### 1. What the pattern actually requires of a parent's SKILL.md

`references/parent-skill-pattern.md` (916 lines) is explicit that the SKILL.md
floor is **seven structural elements** and nothing else:

`references/parent-skill-pattern.md:674-699`

1. **Input Modes** section
2. **Execution-mode flag parsing** (`--auto` / `--interactive` / `--max-rounds=N`)
3. **Topic-slug constraint** statement citing `parent-skill-state-schema.md`
4. **Workflow Phases** diagram
5. **Resume Logic** ladder
6. **Phase Execution** list pointing at `skills/<name>/references/phases/*.md`
7. **Reference Files** table

Line 697-699 states the extension licence verbatim: "Parents extend the
template with parent-specific sections beyond these seven (e.g., chain-proposal
output prose, conditional-feeder integration prose), but the seven structural
elements are the pattern-level floor."

Everything else the lead asked about — the invariants I-1..I-7
(`parent-skill-pattern.md:46-66`), the Three Exit Paths (`:78-111`), the Gate
Vocabulary (`:113-280`), the Team-Lead Operating Discipline (`:750-880`) — is
required of the **parent**, not of its SKILL.md text. The pattern nowhere
requires a parent to restate them in SKILL.md; it requires the parent to
satisfy them and to bind the per-parent specifics somewhere. `/charter` binds
its gate shapes in one table cell of its Reference Files row
(`skills/charter/SKILL.md:276`) and its exit paths in the Phase Execution list
(`skills/charter/SKILL.md:267-270`). `/scope` gives each its own SKILL.md
section. Both conform.

Two additional SKILL.md-level requirements sit just outside the seven and both
parents satisfy them: the option-triad literal-form rule
(`parent-skill-pattern.md:702-733`) and the "what Adjust reaches" statement
(`:735-748`), which each parent SHALL state in its own chain-proposal section.
`/scope` states it at `skills/scope/SKILL.md:453-454`; `/charter` states it in
`skills/charter/references/phases/phase-1-discovery.md` §1.5, not in SKILL.md.
That is already a placement asymmetry running the *other* direction.

**Nothing in the pattern requires either reduction section.** Neither
`## Why the Artifact Set Shrinks` nor `## Consolidation Judgment` is a
pattern-level element, and no eval or script checks for their presence
(`grep -rn "Why the Artifact Set Shrinks"` across the repo returns four hits,
all discussed below; `scripts/` contains no SKILL.md section-structure check).

### 2. Section-by-section comparison

`/scope` = 968 lines, 23 sections. `/charter` = 352 lines, 11 sections. Every
one of `/charter`'s 11 sections has a `/scope` counterpart; `/scope` has 12
sections `/charter` lacks, totalling **526 lines** — 85 % of the 616-line
delta. The remaining 90 lines are `/scope`'s shared sections running longer.

Sections both parents have (scope lines / charter lines):

| Section | /scope | /charter | Pattern element |
|---|---|---|---|
| Preamble (`# Scope` / `# Charter`) | 30 | 29 | — |
| Team Shape | 25 | 15 | Team-Shape Declarator (`:409`) |
| Input Modes | 28 | 39 | element 1 |
| Execution-Mode Flags | 21 | 18 | element 2 |
| Upstream Flag | 50 | 41 | parent-specific (DESIGN-chain-cardinality D5) |
| Topic-Slug Constraint | 21 | 13 | element 3 |
| Workflow Phases | 37 | 28 | element 4 |
| Resume Logic | 40 | 43 | element 5 |
| Phase Execution | 41 | 26 | element 6 |
| Reference Files | 18 | 17 | element 7 |
| Security Considerations | 113 | 64 | `parent-skill-security.md` binding |

Sections unique to `/scope`, classified:

| Section | Lines | Classification |
|---|---|---|
| `## Coordination Intent` (173) | 91 | **/scope-specific and necessary** — multi-repo coordination contract; `/charter` has no coordinated mode and no `mode:coordinated` requires.tsv records |
| `## Chain-Proposal Output` (421) | 51 | **/scope-specific and necessary** — the pattern requires each parent state what Adjust reaches (`:735-748`); `/charter` states it in phase-1-discovery instead. But `:436-445` is discretionary argumentation *inside* it (see below) |
| `## Why the Artifact Set Shrinks` (472) | 60 | **discretionary argumentation** — no pattern requirement; content duplicated at the hop |
| `## Consolidation Judgment` (532) | 47 | **/scope-specific capability summary** — `/charter` has no such mechanism at all; full procedure lives in phase-2 (`:574-577` says so) |
| `## Three Exit Paths` (579) | 47 | **/scope-specific and necessary** — `/scope` has four exit sub-shapes (two boundaries x two Decision-Record sub-shapes) that need discriminator binding; `/charter` has one Decision-Record shape and binds it in Phase Execution |
| `## State File Schema` (626) | 19 | discretionary placement — `/charter` puts the same pointer inside Resume Logic (`charter:205-212`) |
| `## Visibility Detection` (645) | 19 | /scope-specific — carries the literal "Default to Private if unknown" warning string; `/charter` puts it in phase-1-discovery §1.1 |
| `## Manual-Fallback Non-Interference` (664) | 34 | discretionary placement — `/charter` has the identical rule in phase-1-discovery §1.2 (`charter/references/phases/phase-1-discovery.md:73`) |
| `## Validator Pass-Through` (698) | 48 | /scope-specific — per-intermediate validation; `/charter` validates once at finalization |
| `## Phase-N Reject In-Chain Integration` (746) | 12 | /scope-specific — `/prd` and `/design` have Reject paths; the strategic children do not |
| `## Abandonment-Forced HTML-Comment Marker` (758) | 64 | discretionary placement — `/charter` has the same marker, specified in evals and phase-finalization |
| `## Binding Notes` (935) | 34 | discretionary placement — `/charter`'s equivalent is folded into Team Shape |

So the reduction pair is 107 of 968 lines (11 %). Only ~60 of those (the
`## Why the Artifact Set Shrinks` section) is argumentation with no
capability behind it.

### 3. Does `/charter` have an artifact-reduction mechanism at all? No.

`grep -rniE "consolidat|absorb"` across `skills/charter/**` returns nine hits,
**every one of them a false positive** — "absorbing the violation" (SKILL.md:119),
"silently absorb the malformation" (phase-state-management.md:532), "absorb
staleness" (phase-resume.md:173). Not one names an artifact-reduction mechanism.
`skills/vision/**` and `skills/strategy/**` return **zero** hits;
`skills/roadmap/**` returns one, an eval topic slug named
`platform-consolidation`.

This is not an oversight. It was decided, argued, and recorded:

**`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:353-372`,
"Decision 9: Whether the model generalizes to `/charter`":**

> - **Option A (chosen): state in prose that the consolidation model is a no-op
>   on the strategic chain, and change nothing.**
> - **Option B (rejected): implement the same model in `/charter` now.** Out of
>   scope per the PRD, and the consolidation half would add machinery that can
>   never fire.
>
> [...] STRATEGY's required sections have no home for a VISION's Audience, Value
> Proposition, Org Fit, or Success Criteria; ROADMAP's have no home for a
> STRATEGY's Defensibility Thesis, Building Blocks, or Bet-Specific
> Falsifiability. Zero strategic hops are absorbable, so porting the judgment
> would install a rule that can only ever return `keep`.

The shared pattern ratifies this at `references/parent-skill-pattern.md:141-147`:

> A parent MAY define a post-hoc reduction mechanism that folds redundant
> artifacts away once they exist. `/scope` defines one, its consolidation
> judgment [...] `/charter` and `/execute` define none, and a parent that
> defines none conforms fully: the model constrains when reduction may happen,
> not whether a parent offers it at all.

**So the asymmetry is capability, not argumentation.** `/charter` carries no
`## Consolidation Judgment` section because it has no consolidation judgment.
It carries no `## Why the Artifact Set Shrinks` because on the strategic chain
the artifact set does not shrink. The issue's closing claim — "The reduction
argument is unique to `/scope`. Removing it does not break parity between the
two parents; it restores it" — is **half right and half wrong**. The
*argumentation* is unique to `/scope` and removing it does not create an
asymmetry `/charter` does not already have. But `/charter` is not a control for
whether `/scope` needs a place to document its reduction mechanism, because
`/charter` has no mechanism to document. Deleting `## Consolidation Judgment`
from `/scope` on parity grounds would leave a live, six-referrer mechanism
undocumented at the parent's top level; parity with a parent that lacks the
feature is not an argument for hiding a feature you have.

Note also that `parent-skill-pattern.md:141-153` is where the reduction model
*lives* pattern-side, and it is already stated in the shared reference both
parents load "All phases". Whatever `/scope`'s SKILL.md says about reduction is
a second statement of something already loaded.

### 4. The decisive finding: the reduction argument is already stated at the hop

`skills/scope/references/phases/phase-2-chain-orchestration.md:488-500` opens
the Consolidation Judgment section with:

> ## Consolidation Judgment
>
> Step 8 is where the artifact set shrinks.
>
> **Why it exists.** Three documents restating one problem at three altitudes
> cost a reader three reads for one idea, and an obvious concept articulated
> three times reads as ceremony. Reducing the set is worth doing for the reader.
> It is only honest to do it *here* — against two bodies that exist, where the
> question "does the upstream do work the downstream does not?" has an answer.

That is the same argument as `skills/scope/SKILL.md:474-478`, near-verbatim, in
the file that is loaded only at the hop where the judgment fires. The
placement fix the issue asks for is **already half-implemented**. The SKILL.md
section is the copy that leaks; the phase-2 copy is the one that is correctly
placed and correctly scoped. This is the strongest evidence that removing the
SKILL.md section loses no content: the content already exists downstream, at
exactly the point the issue says it should arrive.

The same duplication holds for the "shorter conversation, not a smaller
artifact set" argument: `skills/scope/SKILL.md:508-517` and
`skills/scope/references/phases/phase-1-discovery.md:38-49` state it twice, and
phase-1's copy is the one the run actually reads at the moment it matters.
And the "an earlier revision decided per hop" history — the sentence the issue
identifies as reading like settled history rather than a live warning — appears
at `SKILL.md:485-489` and again at `phase-1-discovery.md:21-26`.

Two constraints on removal, both real but both cheap:

- **`skills/brief/references/phases/phase-0-setup.md:315`** cites the section
  by name: "See the Consolidation Judgment section of
  `skills/scope/references/phases/phase-2-chain-orchestration.md` and the
  \"Why the Artifact Set Shrinks\" section of `skills/scope/SKILL.md`."
  Deleting the section makes this a dangling reference. It is one edit, and
  `/brief` is outside the stated blast radius of `/scope`-only — worth flagging
  to the author as a required companion edit or as a reason to keep a
  differently-titled stub.
- **`DESIGN-scope-consolidation-over-skipping.md:412-415`** is the ruling that
  put the section there: "`/brief`'s fold-into-PRD branch is retired and the
  reader-economy rationale it carried moves into `/scope`'s Phase 1 and Phase 2
  references **and its SKILL.md**, stated in `/scope`'s own words at the layer
  that now performs the reduction." Note the design's own justification —
  "at the layer that now performs the reduction" — argues for Phase 1 and
  Phase 2, and SKILL.md was included in the same breath without a separate
  reason. The Component-changes block at `:426-430` lists both new SKILL.md
  sections as deliverables. So there *is* a DESIGN that argued the sections
  into existence, and its stated reason covers the reference copies, not the
  SKILL.md copy.

### 5. Does `/charter` state why its steps are run? Yes — and `/scope` could borrow the shape

`/charter` has exactly the purpose statement `/scope` lacks, in
`skills/charter/references/phases/phase-2-chain-orchestration.md:463-511`,
titled **"Why /roadmap Is Unconditional"**. It argues affirmatively for running
a step, and at `:482-490` it states the cost of skipping in sink-and-source terms:

> The stronger reason is that a ROADMAP is the only bridge from a STRATEGY into
> the tactical chain. `/brief` is *framed against* a ROADMAP and never a
> STRATEGY [...] so a chain that ends at a STRATEGY alone strands whatever it
> made actionable: no downstream artifact can pick the work up, and nothing
> tracks its progress.

"Strands whatever it made actionable" and "no downstream artifact can pick the
work up" is the process-is-the-product framing, already written, in the corpus,
at a hop. It is the nearest existing prose to what issue #331 asks `/scope` to
say. `/charter`'s roadmap-confirmation prompt (`:302-360`) reinforces it: the
prompt explicitly refuses size as grounds ("The question the prompt asks is NOT
'is this strategy big enough to sequence.' Size never disqualifies a ROADMAP"),
which is the exact refusal `/scope`'s reader-economy argument fails to make.

Where `/charter` is weaker: its SKILL.md preamble (`:22-41`) is descriptive, not
purposive — it says what the chain is and which artifact is durable, not what
running it buys. So neither parent states the purpose at SKILL.md level.
`/charter` states it once, per-child, at the hop. That is a placement precedent
`/scope` can cite rather than invent.

Two more `/charter` purpose statements worth noting:
`phase-1-discovery.md:435` "Why the Prompt Is Stable", and
`phase-2-chain-orchestration.md:257` "Why the Slug and the Upstream Travel
Separately". `/charter`'s house style is a "Why X" section at the point of use.
`/scope`'s two reduction sections are the same house style, hoisted to SKILL.md.

### 6. Frontmatter descriptions and requires.tsv

The two `description:` fields are structurally parallel
(`scope/SKILL.md:3-12`, `charter/SKILL.md:3-13`): parent skill for the
<tactical|strategic> chain, walks an author through <chain>, holds state across
child boundaries, produces <terminal artifact>. Neither description promises a
document count, and neither promises reduction. `/scope`'s says "producing a
PLAN as the terminal artifact"; `/charter`'s says "producing a durable STRATEGY
plus a working ROADMAP". Both name what walking the chain produces, not why it
is walked — so the description surface offers no defence against the reading
that produced the incident, in either parent.

`requires.tsv` differs materially:

- `skills/charter/requires.tsv` — 2 records, both `always`: `shirabe validate
  --format,--visibility` and `git`. Comment: "/charter opens no PR itself — its
  children do — so no gh record appears."
- `skills/scope/requires.tsv` — 5 records: `shirabe slug-prefix-detect
  --docs-root` (always), `shirabe validate --format,--visibility` (always),
  `git` (always), `shirabe validate --coordination-body,--merge-gate`
  (mode:coordinated), `gh` (mode:coordinated). Its comment block names the
  absorb path's `git rm` — the only place in either requires.tsv where the
  reduction mechanism surfaces.

The requires.tsv delta is entirely explained by coordination and by the
per-intermediate validator pass-through. It does not bear on the reduction
question except to confirm, once more, that `/scope` has a fold operation and
`/charter` does not.

### 7. Has anyone run this comparison before?

Not this one. `grep -rn "parity"` across `docs/designs/current/` returns one
hit, unrelated (manual-fallback parity). No design compares the two parents'
SKILL.md section sets or line counts. The four designs that bear on the
reduction question are:

- **`DESIGN-scope-consolidation-over-skipping.md`** (901 lines, Current) — the
  load-bearing one. Replaced `/scope`'s produce-or-skip gates with a whole
  chain plus a post-hoc consolidation judgment. Decision Drivers D1
  (`:89-92`): "Any decision that reduces the artifact set must read a body that
  exists." Decision 8 (`:328-351`): the durable-artifact floor is structural,
  no guard implements it. Decision 9 (`:353-372`): the model is a no-op on
  `/charter`. Its Decision Outcome (`:412-415`) is the ruling that put both
  sections in `/scope`'s SKILL.md. **It never argues that the reader-economy
  rationale belongs at SKILL.md altitude specifically** — its stated reason is
  that the rationale belongs "at the layer that now performs the reduction",
  and the layer that performs it is Phase 2.
- **`DESIGN-scope-artifact-persistence.md`** (732 lines, Current) — deleted the
  type test, made every hop decidable, and amended the write-target set
  (`:400-419`) to the enumerated form now at `SKILL.md:835-890`. Its first
  Decision Driver (`:120-122`): "Nothing may judge an artifact before that
  artifact exists. This killed a previously-shipped feature and is the
  constraint every alternative was measured against first."
- **`DESIGN-scope-chain-mandatory-steps.md`** (822 lines, Current) — pushed the
  mandatory-steps model up into the shared pattern (the Gate Vocabulary text at
  `parent-skill-pattern.md:115-160`), because "a skill-local fix would leave the
  pattern contradicting the skill".
- **`DESIGN-chain-cardinality.md`** (595 lines, Current) — the `--upstream`
  contract on both parents; not about reduction.

So the reasoning that put the sections in `/scope`'s SKILL.md is recoverable and
it is *thin*: one clause in a Decision Outcome, no decision question devoted to
placement, and a Component-changes block that lists the sections without
arguing for the altitude.

## Implications

**Removing `## Why the Artifact Set Shrinks` from SKILL.md is safe on parity
grounds and safe on content grounds.** No pattern element requires it, no
script or eval checks for it, and its argument already exists near-verbatim at
`phase-2-chain-orchestration.md:492-500` where the judgment fires. The one
mechanical consequence is the dangling cite at
`skills/brief/references/phases/phase-0-setup.md:315`, which points at the
section by title.

**Removing `## Consolidation Judgment` is a different call and is not supported
by the `/charter` control.** `/charter` lacks the section because it lacks the
mechanism (`DESIGN-scope-consolidation-over-skipping.md:353-372`;
`parent-skill-pattern.md:141-147`). `/scope`'s section is a 47-line summary
whose last paragraph explicitly delegates the procedure downstream
(`SKILL.md:574-577`). If it goes, `/scope` becomes the only parent whose
SKILL.md omits a capability that changes what files exist on disk — and the
`## Security Considerations` deletion list at `SKILL.md:835-843` would then be
the only SKILL.md-level trace of the fold, which is the surface the issue is
already trying to constrain. My reading is that this section should be
*rewritten*, not removed: it currently reads as a rationale for reduction
delivered up front; it could read as a bounding statement (the chain has one
mechanism that removes a document, it runs after both exist, here is where it
is specified) with the argument stripped out.

**The purpose statement `/scope` needs has a precedent to copy rather than
invent.** `/charter`'s "Why /roadmap Is Unconditional"
(`charter/references/phases/phase-2-chain-orchestration.md:463-511`) states why
a step runs in terms of what skipping strands downstream. Both the framing and
the placement (at the hop, in the phase reference, per-child) match what #331
asks for. If `/scope` wants the sink-and-source framing, the shape already
exists one directory over — and it is a shape that lives *below* SKILL.md, which
is consistent with the disclosure-ordering argument.

**The parity claim in #331 should be narrowed before it is acted on.** As
written ("The reduction argument is unique to `/scope`. Removing it does not
break parity; it restores it") it reads as covering both sections. It is
sound for the argumentation section and unsound for the mechanism section.

## Surprises

- **The reduction argument is already at the hop, in nearly the same words.**
  `phase-2-chain-orchestration.md:492-500` and `SKILL.md:474-478` are the same
  paragraph. The issue frames the fix as "deliver the persistence justification
  at the hop where the judgment fires" as if that were new work. It is done;
  the defect is that the SKILL.md copy was not deleted when the phase-2 copy
  was written. Same for the "shorter conversation" argument
  (`SKILL.md:508-517` vs `phase-1-discovery.md:38-49`) and for the
  earlier-revision history (`SKILL.md:485-489` vs `phase-1-discovery.md:21-26`).

- **`/charter` is *more* compliant than `/scope` on one pattern requirement
  `/scope` was supposed to model.** The pattern requires each parent to state
  what Adjust reaches (`parent-skill-pattern.md:735-748`) in its own
  chain-proposal section. `/charter`'s chain-proposal section is a *phase
  reference* section, not a SKILL.md section — so `/charter` already
  demonstrates that this material lives fine below SKILL.md. `/scope` hoisted
  it and then hung 25 lines of reduction argument off it
  (`SKILL.md:436-445`).

- **`/charter`'s SKILL.md prints its terminal artifact path too.**
  `charter/SKILL.md:166` prints `docs/strategies/STRATEGY-<topic>.md` in the
  Topic-Slug Constraint section, and `:341` names `docs/strategies/` in the
  write-target set. The write-target set is not the only leak, and it is not
  `/scope`-specific — but `/scope` is the one that prints all three
  intermediate paths plus the terminal one in a single brace-expansion
  (`SKILL.md:847`), and `/scope` is the one where every path in the chain is
  therefore addressable up front. The lead's premise that `/charter` "describes
  its write-target set as six places composed from the validated slug rather
  than printing path patterns" is right about the *composition*, but `/charter`
  does print `wip/charter_<topic>_state.md`, `wip/roadmap_<topic>_scope.md`,
  and `wip/charter_<topic>_handoff.md` at `:337-345`. The difference is that
  none of `/charter`'s durable child artifacts appear as templated paths.

- **The pattern reference already carries the mandatory-steps model both
  parents load on every phase** (`parent-skill-pattern.md:115-160`), and it is
  better-framed than `/scope`'s SKILL.md restatement: "Chain steps are
  mandatory, and reduction is post-hoc." That sentence, six words in, says what
  `/scope`'s 60-line section takes 60 lines to imply. `/scope`'s section is a
  third statement of something stated twice already.

- **Nowhere in the corpus does the sink-and-source framing appear.**
  `grep -rniE "\bsink\b|materializ.*step|hands (the )?work to|process is the
  product"` over `references/`, `skills/scope/`, `skills/charter/` returns only
  false positives ("force-materialize"). The framing #331 proposes is genuinely
  absent, not merely mis-placed.

## Open Questions

1. **Is editing `skills/brief/references/phases/phase-0-setup.md:315` in
   scope?** The author's blast radius is `/scope` only, but that file names the
   SKILL.md section by title. Either the edit is allowed as a mechanical
   consequence, or the section keeps a title so the cite still resolves.
2. **Should `## Consolidation Judgment` survive as a bounding statement?** My
   reading is yes — it is the only SKILL.md-level notice that a `/scope` run
   deletes files. But that is a judgment about what SKILL.md owes a reader, not
   something the `/charter` control can settle.
3. **Does the `/charter` "Why /roadmap Is Unconditional" shape scale to four
   children?** `/charter` writes one such section for one child. `/scope` would
   need four, or one generalized statement — and a generalized statement at
   SKILL.md altitude is exactly the shape that failed.
4. **`DESIGN-scope-consolidation-over-skipping.md` is status `Current`.**
   Removing a section its Decision Outcome names would put the skill and a
   Current design out of sync. Does this work need an amendment to that design
   (it already carries two, dated 2026-08-15 and 2026-08-16), or does the
   skill-vs-design divergence get recorded elsewhere?

## Summary

The pattern requires only seven SKILL.md structural elements and neither reduction section is among them; `/charter` lacks both because `DESIGN-scope-consolidation-over-skipping.md:353-372` ruled the consolidation model a no-op on the strategic chain and `parent-skill-pattern.md:141-147` ratified that a parent may define no reduction mechanism at all — so the asymmetry is capability, not just argumentation, and "parity" only licenses removing the argumentation.

The decisive evidence for removal is that `phase-2-chain-orchestration.md:492-500` already states the reader-economy argument near-verbatim at the hop where the judgment fires, as do `phase-1-discovery.md:21-26` and `:38-49` for the other two arguments in the SKILL.md section — the SKILL.md copy is a duplicate that leaks, and its only inbound dependency is a by-title cite at `skills/brief/references/phases/phase-0-setup.md:315`.

`/charter` does have the purpose statement `/scope` lacks — "Why /roadmap Is Unconditional" (`charter/references/phases/phase-2-chain-orchestration.md:463-511`) argues a step runs because skipping it "strands whatever it made actionable" — which is the sink-and-source framing already written, at a hop, in a phase reference rather than in SKILL.md; the framing itself appears nowhere else in the corpus.
