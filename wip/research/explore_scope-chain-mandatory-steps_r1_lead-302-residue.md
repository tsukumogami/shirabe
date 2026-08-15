# Lead: What did PR #302 actually change, and what in the corpus still assumes the world before it?

## Findings

### 1. What #280 reported and what #302 shipped

Issue #280 ("/scope always leaves a permanent PRD and DESIGN, so it cannot be
the default entry point for work that warrants neither") is CLOSED, closed by
commit `83d29e1` / PR #302 ("feat(scope): decide absorbability from the
documents, not the types"). #280 has **no comments** — the whole record of the
resolution is the PR body and the two durable documents #302 added.

`git show --stat 83d29e1`: 34 files, +3886/-209. The substantive surfaces are
`skills/scope/SKILL.md` (+161/-...), `skills/scope/references/phases/phase-2-chain-orchestration.md`
(+396), `phase-1-discovery.md` (+44/-...), `phase-3-exit-finalization.md`,
`state-schema.md`, the four format references (`brief-format.md`,
`prd-format.md`, `design-format.md`, `plan-doc-structure.md`), `checks.rs`
(+602), `formats.rs` (+69), two new scripts (`check-citations.sh` and its test),
`docs/folds.md` (new), and `skills/execute/SKILL.md`.

**The OLD model (type-level absorbability).** Stated most plainly in the
pre-#302 `SKILL.md` text the diff deletes:

> Absorption is available only where a total mapping exists from the upstream
> type's required sections into the downstream type's. Against the current
> formats that is BRIEF into PRD alone: a PRD has a home for a BRIEF's problem,
> outcome, journeys, and boundary, while a DESIGN has none for a PRD's
> requirements or acceptance criteria, and a PLAN has none for a DESIGN's
> decisions or architecture.

Consequences the old text drew from it, also deleted: "a `/scope` run ends with
either all four artifacts or the chain minus an absorbed BRIEF" and "a `/scope`
run always leaves something durable behind"; and the Phase 1 section "The
Durable-Artifact Floor", which ended "Do not add a guard for this. Its
condition cannot hold."

**The NEW model (document-level).** From
`skills/scope/references/phases/phase-2-chain-orchestration.md`:

The two clauses that bound the judgment (lines 514-534):

> **The ceiling.** The preflight below cannot reach any outcome stronger than
> `keep`. It refuses or it defers; it never decides to absorb.
>
> **The input restriction.** *No check in this judgment may read either type's
> required-section list, or compare the two types' section sets.* Chain
> position and provenance are admissible inputs; a type's content contract is
> not.
>
> The test for a violation: **a condition that refuses one pair while
> permitting its structural twin under identical repository state is a type
> rule.**

Stage 2, the only stage that can return `absorb` (lines 574-590):

> Read both bodies. The question is whether the upstream artifact does work the
> downstream does not: does the upstream hold anything beyond its contribution
> that compression into a contribution section would lose?
> - **No** — verdict `absorb`. Continue to Stage 3.
> - **Yes** — verdict `keep`, with a finding naming what the upstream holds
>   that the survivor does not.

And the replacement for the floor (lines 710-730):

> ### There is no durable-artifact floor
>
> A run can absorb its way down to a single surviving artifact, or to none once
> the PLAN is implemented, and that is a reachable outcome rather than a defect.
>
> **Do not add a guard that forces `keep` on the ground that the survivor would
> be the last artifact.** [...] It would decide a fold from the artifact *set*
> rather than from the two documents at the hop [...] And it would fire at
> exactly the DESIGN-to-PLAN hop that must be absorbable, closing by a second
> route the floor this work opened.

Supporting machinery: Stage 1 is now a **citation preflight**
(`skills/scope/scripts/check-citations.sh`, default-deny routing); the firing
condition is "both endpoints of the edge appear in `chain_ran:`"; each type's
format reference now names exactly one **contribution** (BRIEF = WHY, PRD =
WHAT, DESIGN = HOW, PLAN = WHEN) that a survivor carries as one section after
`## Status`, declared in an `absorbed:` frontmatter list; every completed fold
appends a row to `docs/folds.md`; FC17/FC18/FC19 enforce the declaration.

### 2. Durable documents motivating or recording the work

| Path | `status:` | Relation to #302 |
|---|---|---|
| `docs/briefs/BRIEF-scope-artifact-persistence.md` | `Done` | The framing for #302 |
| `docs/prds/PRD-scope-artifact-persistence.md` | `Done` | Requirements R1-R29 for #302 |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md` | `Current` | The design for #302 |
| `docs/briefs/BRIEF-scope-consolidation-over-skipping.md` | `Done` | The #260 predecessor; **no amendment added** |
| `docs/prds/PRD-scope-consolidation-over-skipping.md` | `Done` | #260 predecessor; **amended 2026-08-15** |
| `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | `Current` | #260 predecessor; **amended 2026-08-15** |
| `docs/briefs/BRIEF-chain-cardinality.md` | `Done` | Adjacent; carries retired-model prose, **not amended** |
| `docs/prds/PRD-chain-cardinality.md` | `Done` | Adjacent; carries retired-model prose, **not amended** |
| `docs/designs/current/DESIGN-chain-cardinality.md` | `Current` | Clean — no absorbability references |
| `docs/folds.md` | n/a | New; append-only fold record, **currently empty** (no rows) |

The amendment pattern #302 used is worth naming because it is the corpus's
answer to "what do we do with superseded durable prose": leave the original body
unedited and append an `## Amendment — <date>` section that names what no longer
holds. From `DESIGN-scope-consolidation-over-skipping.md`:

> Superseded in part by `DESIGN-scope-artifact-persistence.md` [...] The
> original text above is left unedited; this section records what no longer
> holds and why.
>
> **Decision 8 (the durable-artifact floor) — the conclusion is falsified, and
> the option it rejected is the one now adopted.**

That amendment also explicitly reverses the reasoning behind Decision 9
(`/charter` out of scope): "the conclusion stands, the reasoning does not."

### 3. Sweep: what still assumes the retired model

Judged (a) correct new-model prose, (b) stale, (c) deliberate historical account.

#### (b) STALE — the four that matter

**B1. `skills/scope/evals/evals.json` was never touched by #302.**
`git log --oneline -- skills/scope/evals/evals.json` shows its last change is
`3f702b6` (#260); `git diff 83d29e1^ 83d29e1 -- skills/scope/evals/evals.json`
is empty. Three scenarios grade the agent against the retired model, and two of
them would now *fail a correct agent*:

- Scenario 18 `durable-artifact-floor-is-structural`, expected output: "A
  /scope run always leaves at least one durable artifact [...] no hop above
  BRIEF-to-PRD is absorbable, so the smallest set a run can end with is a PRD, a
  DESIGN and a PLAN. A PLAN-alone run [...] is not reachable through /scope at
  all; an author who wants that invokes /plan directly." Expectations include
  "Plan notes that a PLAN-alone outcome is unreachable through /scope."
- Scenario 20 `consolidation-keep-at-unmapped-hop`, expectations include "Plan
  finds the prd->design mapping is not total and records `absorbable: false`"
  and "Plan derives absorbability from the per-type required-section contracts
  rather than a hard-coded list of hops." Both name the exact mechanism the
  input restriction now forbids, and `absorbable:` is a retired field.
- Scenario 19 `consolidation-absorb-brief-into-prd`: "Stage 1 finds the mapping
  total [...] so absorb is available." Stage 1 is now the citation preflight.

This is a **broken acceptance criterion, not a judgment call**.
`PRD-scope-artifact-persistence.md` R24 requires the suite be updated "so that
no scenario references a type-level mapping check" and gain "coverage of a hop
above BRIEF-to-PRD reaching `absorb` and the same hop reaching `keep`"; its AC
line 453 is `- [ ] **[mech]** Scenarios 18, 19 and 20 in
skills/scope/evals/evals.json are rewritten...`, and
`DESIGN-scope-artifact-persistence.md:444` names the file with "Scenarios 18, 19
and 20 rewritten; absorb and keep coverage added above the first hop. **Scenario
17 is untouched**". The scenario-17 carve-out landed (by doing nothing); the
rewrite of 18/19/20 did not. Both docs are at their terminal status (`Done` /
`Current`) with the requirement unmet.

**B2. `skills/scope/references/phases/phase-1-discovery.md` contradicts itself.**
Lines 38-43 give the redirect as live advice:

> **An author who wants a shorter chain reaches for a child skill directly.**
> `/design <topic>` and `/plan <topic>` are the documented ways to enter the
> tactical chain above `/brief` [...] `/scope` means "walk the whole chain"; it
> does not guess that an altitude is not worth writing down.

Lines 269-281, added by #302 in the same file, retire it:

> This section previously stated a durable-artifact floor [...] It also told
> maintainers not to guard the zero-artifact case [...] and redirected an author
> who wanted no durable record to invoke `/plan` directly.
>
> All three of those rested on the type-level absorbability test, which is gone.
> Every hop is now decidable, a run can absorb its way down to nothing, and the
> redirect describes an escape hatch from a constraint that no longer exists.

Strictly the retired one is the `/plan`-for-no-durable-record redirect and the
surviving one is the `/design`-to-start-higher redirect, but line 38 states its
motivation as **"wants a shorter chain"** — which is now exactly what `/scope`
delivers on its own. The two paragraphs read as opposite instructions to an
agent following the file top to bottom.

**B3. `skills/scope/SKILL.md:401-403`, the Chain-Proposal Output section:**

> The proposal never offers a shorter chain, because `/scope` has no way to
> produce one. An author who wants to start above `/brief` invokes `/design` or
> `/plan` directly.

The first clause's *reason* is now false. `/scope` does have a way to produce a
shorter artifact set — it is the whole point of the consolidation judgment. The
conclusion (the proposal offers no shortened chain) is still correct and
`planned_chain:` is still `[brief, prd, design, plan]` on every run, so this is
a stale justification attached to a live rule, 60 lines above the same file's
corrected text at 461-473 ("There is no durable-artifact floor").

**B4. `skills/scope/references/phases/phase-2-chain-orchestration.md:853-855`,
the References list:**

> - `crates/shirabe-validate/src/formats.rs` — the per-type required-section
>   contracts the absorbability mapping is **derived from**.

There is no absorbability mapping any more, and reading the required-section
lists is precisely what the same file's input restriction (line 520) forbids.
`formats.rs` is still a legitimate reference — it now owns the contribution
table and the `absorbed:` splice — but the annotation names the deleted
mechanism.

#### (b) STALE — secondary

**B5. `README.md`** is untouched by #302 and describes an artifact lifecycle in
which durable artifacts do not leave `docs/`:

> Artifacts come in two kinds. **Durable** artifacts stay in `docs/` after the
> work ships and serve as the audit trail: VISION, STRATEGY, BRIEF, PRD, DESIGN,
> COMP. **Working** artifacts -- ROADMAP and PLAN -- are not part of that audit
> trail [...]
>
> Retirement is conditional, not automatic. A PLAN is `git rm`'d before its work
> merges [...] A ROADMAP is only reached by the cascade when a plan downstream
> of it finishes [...]

A fold is now a second way a BRIEF, PRD or DESIGN leaves `docs/`, and the
retirement paragraph enumerates the paths without it. README never mentions
`docs/folds.md`, `absorbed:`, or the consolidation judgment. Separately, "Not
every step runs: a feature framed directly in its PRD has no BRIEF [...] and a
straightforward feature may skip the DESIGN entirely" is true of direct child
invocation but reinforces the choose-steps-up-front framing this exploration is
about. (Note: issue **#259** already tracks README structure/entry-point
problems and **#256** tracks "stale workflow pins and small README
inaccuracies" — neither names this.)

**B6. `docs/briefs/BRIEF-chain-cardinality.md` (Done) and
`docs/prds/PRD-chain-cardinality.md` (Done)** carry the retired model with no
amendment, unlike their consolidation siblings:

- BRIEF line 85: "`BRIEF -> PRD` is also the only hop `/scope`'s consolidation
  judgment can absorb, so absorption is well-defined by accident. The stated
  absorbability criterion is section-mapping totality..."
- BRIEF line 160 (Scope Boundary, In): "Whether the consolidation judgment's
  absorbability test should account for how many consumers an upstream has,
  alongside section-mapping totality." — the consumer-count half of this open
  question is now **answered** by #302's citation preflight; the
  section-mapping half is moot.
- PRD lines 374-378 repeat both, including "zero strategic hops [are
  absorbable]" — the reasoning `DESIGN-scope-consolidation-over-skipping.md`'s
  amendment explicitly falsifies.

Also note BRIEF line 144's user journey — "An author is partway through a chain
run when it reaches a hop where the upstream looks absorbable — and something
outside this run still points at that upstream. The run tells them the document
has another consumer and keeps it" — is now **implemented** by
`check-citations.sh`, in a Done BRIEF that does not say so.

#### (c) DELIBERATE HISTORICAL ACCOUNTS — correct, leave alone

- `docs/prds/PRD-scope-consolidation-over-skipping.md` `## Amendment —
  2026-08-15` ("**R14 (the durable-artifact floor) is superseded.**" and "'The
  commit history is the recovery path' is false as written").
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` `##
  Amendment — 2026-08-15` (Decisions 8 and 9).
- `skills/scope/references/state-schema.md:116-128` — `stage:` "replaces a
  boolean `absorbable:` that asked whether the required-section mapping was
  total — the type-level question the judgment no longer asks", plus the
  no-migration note.
- `skills/scope/references/phases/phase-2-chain-orchestration.md:706-708` — the
  same retirement note beside the judgment entry.
- `skills/scope/SKILL.md:452-459` — the account of the withdrawn Phase 1 entry
  altitude, and `:789` — "the deletion set named `docs/briefs/` alone, which was
  the type-level floor written into the security surface."
- `skills/scope/scripts/check-citations.sh:15` — a comment recording the 36/36
  measurement on the pre-change corpus.
- The unedited bodies of the two `-consolidation-over-skipping` documents,
  covered by their amendments.

#### (a) CORRECTLY UPDATED — the new model reads consistently here

- `skills/scope/SKILL.md` "Why the Artifact Set Shrinks" (425-478) and
  "Consolidation Judgment" (480-524), including the closed write-target set
  rewrite at 747-800 (deletions now cover `docs/{briefs,prds,designs}/`;
  mutations cover `docs/{prds,designs,plans}/`; `docs/folds.md` appended and
  carved out of Phase 4's sweep).
- `phase-2-chain-orchestration.md` Consolidation Judgment section in full
  (firing condition, two clauses, three stages, nine steps, rollback table).
- All four format references name exactly one contribution
  (`brief-format.md:504`, `prd-format.md:250`, `design-format.md:365`,
  `plan-doc-structure.md:308`), with the two-sided adequacy test and the
  "nothing absorbs into a BRIEF" / "`## Absorbed Plan` is structurally
  unreachable" edge notes.
- `skills/execute/SKILL.md:548-578` handles the zero-artifact outcome
  explicitly: "**A finalized chain that folded every artifact away.** [...]
  There is no anchor to seed on, and that is **completion, not a missing
  seed**", and the standing rule "**`/execute` does not know what the chain
  decided, and must not start knowing.**"
- `skills/work-on/references/phases/phase-4-implementation.md:32-49` — the
  record-why-in-code instruction, with "This holds regardless of what documents
  the work leaves behind" — plus the maintainer-reviewer brief in
  `phase-4b-review.md`.
- `docs/guides/doc-validation.md:28-58` — FC18/FC19 and the `docs/folds.md` CI
  check.
- `references/` (shared) and the other parent skills carry no retired-model
  prose; the `absorb` hits in `pipeline-model.md` are an unrelated sense of the
  word.

### 4. Were #280's four Directions all resolved?

**Direction 2 — "Loosen the absorbability test": fully resolved, and further
than proposed.** #280 suggested allowing an absorb to land content in optional
sections or letting a DESIGN carry a requirements appendix. #302 deleted the
type test outright and replaced it with a per-type contribution plus a content
judgment, then wrote an input restriction forbidding any future check from
reading the section lists.

**Direction 1 — "Decide persistence at finalization, not at entry": resolved in
substance, not literally.** The decision is still made per hop in Phase 2, right
after each artifact lands, not in one pass at finalization. That is
"after-the-fact" in #280's sense (every judgment sees both documents), and
`SKILL.md` line 444 keeps the single-mechanism rule. What did *not* happen is a
whole-set review at the end; each hop is judged in isolation, which is exactly
what the anti-guard rule at `phase-2:716` preserves ("Do not add a guard that
forces `keep` on the ground that the survivor would be the last artifact").

**Direction 3 — "Give the surviving reasoning a non-`docs/` home": partially
resolved, split two ways.** The *why* went to code comments (R23 →
`work-on/phase-4-implementation.md`, enforced through the maintainer reviewer's
brief rather than a gate). The *what happened* went to `docs/folds.md` — which
is still inside `docs/` and, by explicit design, records the operation and never
the prose: "The record is of the *operation*, never of the content [...] any
destination that preserved the content would assert, every time it fired, that
the verdict was partly wrong." So #280's specific suggestions (PR body, commit
trailer) were not adopted; the PR body does get the record per
`phase-3-exit-finalization.md:65-76`, but only until the state file is swept.

**Direction 4 — "Re-open chain shape": explicitly declined and fenced off.**
`PRD-scope-artifact-persistence.md` R28: "No judgment SHALL run before the
artifact it is about exists. Nothing here SHALL reintroduce a pre-artifact worth
decision in any form, **including an author-chosen entry altitude**." Its AC:
"Scenario 17 `chain-shape-is-constant` still passes [...] This is the tripwire
for R28: implementing R1 is exactly what makes an entry-altitude flag look
reasonable to a later maintainer." The DESIGN's file table repeats it. So the
answer to Direction 4 is a documented "no, and here is the guard" — which is
directly relevant to this exploration, since the author's reported friction
(`/explore` picking a step inside `/scope`, `/scope` opening by asking which
steps will run) is the behaviour R28 forbids.

### 5. Other open issues tracking overlapping ground

`gh issue list --state open --limit 60` and `--search "scope chain"` turn up
**no issue tracking the #302 residue**. Nearest neighbours:

- **#255** "test: judgment gates in /scope, /explore and /design are unasserted"
  — the closest match. It predates #302 (2026-08-08) and is about judgment gates
  lacking assertions generally; it does not name the stale scenarios 18/19/20 or
  the unmet R24.
- **#254** "chore(parents): three unresolved items in the parent-skill chains" —
  worth reading before filing anything, it may already be the home for corpus
  consistency chores.
- **#259** / **#256** — README structure and stale README pins; the durable/
  working artifact paragraph belongs to one of these if it is not filed fresh.
- **#273** "The tactical workflow cannot produce a second downstream document
  under one upstream" — the chain-cardinality follow-on; shares the BRIEF/PRD
  documents flagged in B6.
- **#296 / #295 / #294 / #293 / #289** — the FC18 prose-reference family, which
  is the mechanism a fold's dangling-reference problem rides on. #302's PR body
  names the ~77 unresolved `R<n>` citations and the five dangling `upstream:`
  refs as follow-ups; **#308** and **#298** are two of those five filed
  individually.
- **#307** "run-cascade.sh's post-cascade probe seeds on the PLAN it just
  deleted" and **#186** (same shape) — adjacent to #302's `/execute` repairs.

## Implications

1. **The corpus has one model and three-and-a-half surfaces that still teach the
   old one.** The prose in `SKILL.md` and `phase-2` is coherent and complete; the
   damage is concentrated in (i) `evals.json`, which is the only *executable*
   statement of what `/scope` should do and which now grades the retired model,
   (ii) the self-contradicting `phase-1-discovery.md`, (iii) one stale
   justification in `SKILL.md`'s chain-proposal section, and (iv) one stale
   reference annotation. Three of the four are single-paragraph edits.

2. **The eval gap is a shipped acceptance-criterion miss, not a discovered
   inconsistency.** That changes how it should be written up: `PRD-scope-artifact-persistence.md`
   R24 and its two ACs are unmet with the PRD at `Done` and the DESIGN at
   `Current`. Whoever fixes this should decide whether the documents get an
   amendment or the ACs get re-opened.

3. **#280 Direction 4 is the exploration's own question, already answered "no".**
   If this exploration concludes that `/explore` should stop routing into
   `/scope`'s interior and `/scope` should stop asking which steps to run, it is
   *enforcing* R28 rather than proposing anything new — and eval scenario 17 is
   the existing tripwire to extend rather than a thing to write from scratch.
   Conversely, scenario 17's third expectation ("Plan points the author at
   invoking /design directly if they want to start above /brief") is the same
   redirect B2 and B3 flag, so touching the redirect means deciding what happens
   to a scenario the DESIGN deliberately froze.

4. **The amendment pattern is the corpus's established answer for superseded
   durable prose** and it was applied to two of the four affected document
   families. Applying it to `BRIEF-`/`PRD-chain-cardinality` is a mechanical,
   low-risk follow-on with a precedent to copy.

5. **`docs/folds.md` has zero rows.** The whole mechanism — the fold, the
   `absorbed:` frontmatter, FC18/FC19, the CI blob check — has never fired on
   this repository. The PR body says so plainly ("this chain ran under the
   mechanism it replaces"). Any claim about how the new model behaves in practice
   is currently untested outside the Rust unit tests and the LLM-graded evals
   that themselves encode the old model.

## Surprises

- **#302's own chain could not be dogfooded**, and the PR body says so: "Two of
  its three hops reached `keep` without either document being read, because that
  is what the old judgment does." So `BRIEF-`, `PRD-` and
  `DESIGN-scope-artifact-persistence.md` all survive on disk as an artifact of
  the retired mechanism, not as evidence the new one kept them.
- **`phase-1-discovery.md` contradicts itself within one file** — the section
  #302 added to retire the redirect sits 230 lines below the paragraph that
  still gives it. That is not two authors disagreeing across files; it is one
  commit updating one half of one file.
- **The evals were named in the DESIGN's file-change table and then not
  changed.** The DESIGN singles out scenario 17 as deliberately untouched, which
  makes the omission of 18/19/20 read as an oversight during execution rather
  than a decision — and the PR body's Verification section lists `cargo test`,
  `check-citations_test.sh`, `run-cascade_test.sh` and `shirabe validate` but
  never the eval suite.
- **`/execute` is ahead of `/scope` on this.** `skills/execute/SKILL.md` carries
  the cleanest statement of the new model in the corpus ("`/execute` does not
  know what the chain decided, and must not start knowing"), while `/scope`'s
  own Phase 1 still tells authors to leave `/scope` for a smaller set.

## Open Questions

1. **Do scenarios 18 and 20 get rewritten, or deleted and replaced?** R24 says
   the consolidation family's scenario count must not decrease and must gain a
   hop-above-BRIEF absorb *and* keep pair. Scenario 18's subject
   (durable-artifact floor) no longer exists as a rule; its natural successor is
   "a run that folds everything away is a legitimate outcome and no guard is
   added" — which is a different assertion with the same anti-guard punchline.
   Needs an author call.
2. **What happens to scenario 17's third expectation?** It encodes the
   `/design`-directly redirect. If this exploration retires the redirect, the
   tripwire the DESIGN deliberately froze has to be re-cut without weakening the
   R28 guard it exists to hold.
3. **Is the `/design`-directly redirect retired, narrowed, or kept?** Three
   surfaces state it as live (`phase-1:38`, `SKILL.md:401` and `:461`,
   `CLAUDE.md`'s "remain directly invocable ... for authors who already know
   which altitude they want") and one states it as retired (`phase-1:278`).
   Whether the answer is "keep it, but stop justifying it by artifact-set size"
   or "drop it entirely" is a product call this lead cannot make.
4. **Does `docs/folds.md` satisfy #280's Direction 3, or is that still open?**
   The reasoning's durable home is now code comments enforced by a reviewer
   brief — a judgment gate, not a mechanism. #280 asked for a durable non-`docs/`
   home for decision provenance; whether an unenforced comment instruction counts
   is worth confirming with the author.
5. **Should the chain-cardinality BRIEF/PRD get amendments?** Two of their open
   questions are now answered and one cited rationale is falsified. The precedent
   exists; whether Done documents in an adjacent chain are in scope for this
   exploration is a scoping call.

## Summary

PR #302 replaced type-level absorbability with a per-hop content judgment bounded
by an explicit "no check may read either type's required-section list" rule, and
updated `SKILL.md`, `phase-2`, all four format references, `/execute` and
`/work-on` correctly — but left four surfaces teaching the retired model, the
worst being `skills/scope/evals/evals.json`, which #302 never touched despite its
own PRD's R24 and two acceptance criteria requiring scenarios 18/19/20 be
rewritten, so the only executable statement of `/scope`'s behaviour still grades
agents on the durable-artifact floor and the section-mapping test. The other
three are `phase-1-discovery.md` contradicting itself within one file (line 38
gives the "want a shorter chain? invoke a child directly" redirect that line 278
declares retired), a stale justification at `SKILL.md:401`, and a stale reference
annotation at `phase-2:853`; #280's Directions 1 and 2 were fully resolved,
3 partially, and 4 was explicitly declined and fenced with R28 plus eval scenario
17 — which is the guard this exploration's own conclusion would be enforcing, not
inventing. The biggest open question is what replaces eval scenarios 18 and 20,
since scenario 17's third expectation encodes the very redirect that is in
dispute, and no open GitHub issue tracks any of this today.
