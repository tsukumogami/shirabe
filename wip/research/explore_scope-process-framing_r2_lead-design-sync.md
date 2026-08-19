# Lead: How a skill change that diverges from a status-Current DESIGN gets recorded

Round-2 research for exploration `scope-process-framing` (issue tsukumogami/shirabe#331).
Repo: `public/shirabe`, branch `docs/scope-process-framing`.

## Findings

### 1. The amendment convention is real, pinned in prose, and CI-tested at least once

The repo amends a Current design in place with an appended dated section. The
convention is not folklore — it was written down as a requirement and an
acceptance criterion in `PRD-fold-record-removal.md`, and restated as an
implementation instruction in `DESIGN-fold-record-removal.md:242-248`:

> **Group 5 — amend seven shipped documents.** Each gains a
> `## Amendment — <date>` section, with the separator being U+2014 EM DASH, the
> pinned opening formula, and the fixed sentence "The original text above is left
> unedited; this section records what no longer holds." Each retains its current
> status; no lifecycle transition is performed, and a requirements document has
> no superseded state in any case.

The binding requirement is `PRD-fold-record-removal.md:184-186`:

> **R10.** Each of these seven shipped documents SHALL carry a dated amendment
> section recording what no longer holds, and SHALL retain its current status

and its acceptance criterion at `PRD-fold-record-removal.md:326-330`:

> - [ ] **AC15.** Each of the seven documents named in R10 contains a section
>       heading matching `## Amendment — <date>` where `<date>` is on or after
>       the date this change lands, and the text under that heading contains the
>       string `folds.md`. Each document's `status:` is unchanged from the merge
>       base.

Three structural facts follow, all confirmed against shipped documents:

- **Heading form.** `## Amendment — <date>`, em dash, ISO date. Two variants are
  in the corpus and both are legitimate: a titled form
  (`## Amendment — 2026-07-06: opt-out hook registration and a complete
  cross-repo summary`, `DESIGN-session-work-summary.md:543`) and a
  decision-scoped form (`## Amendment to Decision 6 — 2026-08-15`,
  `DESIGN-roadmap-plan-standardization.md:801`).
- **Status does not change.** No `shirabe transition`, no move out of
  `docs/designs/current/`, no `superseded_by:`. AC15 asserts the status is
  unchanged from the merge base.
- **The original text is never edited.** Every amendment in the corpus opens by
  saying so. `DESIGN-scope-consolidation-over-skipping.md:824-827`:
  "The original text above is left unedited; this section records what no longer
  holds and why."

### 2. The choice between amendment, supersession, and a DECISION record is settled

`PRD-fold-record-removal.md:434-439` argues it explicitly:

> **Amendment in place, not supersession.** A requirements document has no
> superseded state, so the mechanism is unavailable for the document carrying the
> binding requirement. The designs could be superseded, but that discards sound
> unaffected decisions across documents whose other content is untouched.
> Amendment in place is both the only universally available mechanism and the one
> this corpus already used on two of these same documents.

Supersession exists and is mechanical — `skills/design/references/lifecycle.md:20-29`
defines `Superseded` -> `docs/designs/archive/` and requires
`shirabe transition <path> Superseded --superseded-by <doc>`; `transition.rs:452-453,
790` implements it. But it retires the whole document. The corpus reserves it for
a successor design that replaces the original wholesale, and it has not been used
on any of the scope-chain designs, all of which carry amendments instead.

A `docs/decisions/DECISION-*.md` record is a *different* artifact: the seven in
`docs/decisions/` (e.g. `DECISION-orphan-doc-passing-state-rule-2026-06-06.md`,
`DECISION-skill-preflight-verification-depth-2026-08-14.md`) record decisions taken
in isolation and cited *by* designs. None of them records a later change to a
shipped design. That is not the mechanism here.

### 3. Nothing mechanically checks a Current DESIGN against the skill it describes

This matters and is the most load-bearing negative finding.

`shirabe validate --lifecycle` (`crates/shirabe-validate/src/lifecycle.rs:1-64`)
enforces graph and status properties only — L01 passing-state mismatch, L02
orphan, L03 cycle, L04 dangling `upstream:`, L05 parse fallback, L06 unticked
outline-AC, **L07 a Current design outside `docs/designs/current/`**, L08 conflicting
chain requirements. Nothing reads a design's body and compares it to code or to
skill prose.

The content checks in `crates/shirabe-validate/src/checks.rs` are schema and
format checks (FC01-FC20, upstream resolution, upstream legality, visibility,
writing style, plan structure). The closest thing to a staleness check is **FC20**
(`checks.rs:4024-4111`), from `DESIGN-prose-reference-staleness.md`, and it keys on
*paths*:

```
"[FC20] reference {:?} names no file; {} exists -- the document moved"
```

It fires when a prose reference names a path that does not resolve while a file of
the same basename survives elsewhere. It is **notice-level**, and it cannot see a
reference to a *section title* inside a file that still exists.

So: deleting `## Why the Artifact Set Shrinks` from `skills/scope/SKILL.md` breaks
zero mechanical checks. The design's Component-changes block cites
`skills/scope/SKILL.md`, which still resolves. The paperwork question is entirely
a convention question, not a CI question.

### 4. There is exactly one inbound reference to the section by title, and it is a real defect if unfixed

`grep -rn "Why the Artifact Set Shrinks"` over non-`wip/` files returns three hits:

- `skills/scope/SKILL.md:472` — the section itself.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:427` — the
  Component-changes line.
- `skills/brief/references/phases/phase-0-setup.md:315` — **a live cross-reference
  in shipped skill prose.**

The brief's text (`phase-0-setup.md:309-315`):

> The reader-economy goal that path served is real, and it is now served where the
> reduction can actually be verified. `/scope`'s Phase 2 runs a consolidation
> judgment after each artifact lands: it reads the BRIEF and the PRD, checks
> section by section that the PRD carries the brief's problem, outcome, journeys,
> and boundary, and only then removes the brief. See the Consolidation Judgment
> section of `skills/scope/references/phases/phase-2-chain-orchestration.md` and the
> "Why the Artifact Set Shrinks" section of `skills/scope/SKILL.md`.

Note what this paragraph already concedes: the goal "is now served where the
reduction can actually be verified", and it names phase-2 *first*. Deleting the
SKILL.md section requires trimming the trailing clause of that sentence — a
one-line edit that leaves the sentence better, since the surviving pointer is the
one the paragraph's own logic prefers.

`## Consolidation Judgment` has more inbound references but all of them point at
the **phase-2** section, not the SKILL.md one: `phase-1-discovery.md:35`,
`phase-1-discovery.md:559`, `phase-0-setup.md:313`, and SKILL.md's own :576
deferral. Only the `phase-0-setup.md:315` clause names the SKILL.md copy.

### 5. What the design actually claims, and whether the change contradicts it

Decision Outcome, `DESIGN-scope-consolidation-over-skipping.md:414-418`:

> **`/brief`'s fold-into-PRD branch is retired** and the reader-economy
> rationale it carried moves into `/scope`'s Phase 1 and Phase 2 references and
> its SKILL.md, stated in `/scope`'s own words at the layer that now performs
> the reduction.

Component changes, `:426-430`:

```
skills/scope/SKILL.md
    # New "## Why the Artifact Set Shrinks" section — the reader-facing
    #   rationale, stated here rather than cited from /brief
    # New "## Consolidation Judgment" section — verdicts, absorbability
    #   rule, carry check, per-hop placement
```

and Implementation Approach Batch 3, `:670-673`: "Add the Why the Artifact Set
Shrinks and Consolidation Judgment sections".

**The lead's hypothesis is half-right and worth being precise about.** The phrase
"at the layer that now performs the reduction" is a contrast with `/brief`, not
with SKILL.md. Read against the Context section (`:74-79`), which complains that
"the reader-facing reason for reducing the artifact set is documented nowhere in
the skill that implements the reduction", *layer* means the **skill**, `/scope`
rather than `/brief`. It does not mean *phase file rather than SKILL.md* — the
sentence names both destinations conjunctively.

So the design's stated reason does not by itself authorize deleting the SKILL.md
copy. It does, however, mean the change **does not defeat the design's purpose**:
the rationale still lives in `/scope`, in `/scope`'s own words, at
`phase-2-chain-orchestration.md:492-500`. What is withdrawn is one of two named
destinations, not the requirement itself. That is a narrowing of a deliverable
list, not a reversal of a decision.

**The upstream PRD does not name SKILL.md, and this is decisive.** The binding
requirement is `PRD-scope-consolidation-over-skipping.md:205-207`:

> **R16.** The reader-facing reason for reducing the artifact set SHALL be
> documented at the layer that implements the reduction — `/scope`'s own phase
> references — and not only in a child skill.

and its acceptance criterion, `:282-284`:

> - [ ] AC18. `/scope`'s phase references state the reader-facing reason for
>       reducing the artifact set, in their own prose, without deferring to
>       `/brief` for the rationale.

Both name **`/scope`'s phase references** and nothing else. SKILL.md as a
destination was a design-level elaboration *beyond* what the requirement asked
for. `phase-2-chain-orchestration.md:492-500` discharges R16 and AC18 on its own,
today, with the SKILL.md copy deleted.

The PRD's only mention of SKILL.md is AC3 (`:237-239`): "`/scope`'s phase
references and SKILL.md contain no decision that reduces the artifact set before
the artifacts exist." Deleting an argumentative section can only make that more
true.

So the divergence is the weakest kind available: a design elaborated one extra
destination past its requirement, and that extra destination is being withdrawn.

There is precedent for amending at exactly this magnitude.
`BRIEF-scope-artifact-persistence.md:190-197` amends over the withdrawal of a
single in-scope list item:

> **"A durable record, on the default branch, of what folded into what and on what
> verdict" is withdrawn from the in-scope list.** It was the framing decision this
> brief made, and it was never re-examined downstream

and `DESIGN-scope-chain-mandatory-steps.md:812-822` amends over something smaller
still — a justification-by-analogy losing its analogue:

> **The clean-cancel carve-out no longer has the fold record's carve-out to be
> shaped like.** Both passages justify stating the carve-out explicitly by pointing
> at the shape the record's own carve-out in Phase 4 already used. That carve-out is
> deleted with the record. The justification stands on its own without the
> comparison

Both are one-paragraph amendments recording a withdrawn item and stating what
survives. That is the exact shape this change needs.

### 6. The `## Consolidation Judgment` rewrite is largely already covered

The Component-changes line describes that section as carrying "verdicts,
absorbability rule, carry check, per-hop placement". Two of those four are already
under an existing amendment: the 2026-08-15 amendment (`:822-827`) opens

> Superseded in part by `DESIGN-scope-artifact-persistence.md`, which makes
> the consolidation judgment decide absorbability from the two documents at
> a hop rather than from their types.

and `DESIGN-scope-artifact-persistence.md`'s Components table (`:427-434`) already
re-specifies both `skills/scope/SKILL.md` and
`skills/scope/references/phases/phase-2-chain-orchestration.md` ("Judgment
rewritten; mapping table deleted; preflight added; firing condition bound to
`chain_ran:`..."). The older design's component list is therefore already read as
a historical record of one PR, not a live contract over that section's contents.

Practically: as long as the rewritten SKILL.md section still states the verdicts,
still bounds the judgment, and still defers the procedure to phase-2 (which its
current `:574-577` already does), the rewrite is inside what the persistence design
and the 2026-08-15 amendment already re-specified. It does not need paperwork of
its own; a clause in the new amendment is sufficient and honest.

### 7. Conflict check against the other three Current designs

**`DESIGN-scope-artifact-persistence.md` — neutral, arguably supported.** Its three
claims about `skills/scope/SKILL.md` (`:401-403`, `:427`, `:519`) are all about the
*write-target set*, which lives in SKILL.md's `## Security Considerations`
(SKILL.md:822) — untouched by this change. `:401-403`:

> Enumerated rather than described, and declared in **both** sites the pattern
> requires — `skills/scope/SKILL.md`, which is authoritative, and the Phase 3
> reference, which must not diverge from it again.

Its floor prohibition is deliberately sited in phase-2, not SKILL.md
(`:427-433` component row: "floor prohibition sited here" against the phase-2 file),
and SKILL.md:574-577 already defers there. No conflict.

**`DESIGN-scope-chain-mandatory-steps.md` — supported.** Its rationale
(frontmatter, `:22-28`) is a one-home principle:

> And every fix lands in the document both parents inherit from, because a
> skill-local fix would leave the pattern contradicting the skill.

Its only SKILL.md concern (`:722-725`) is the write-target enumeration and its two
restatements — untouched. The design's whole thesis is that the model is stated
once in the shared pattern rather than duplicated per skill, which is the same
argument the exploration is making one level down.

**`DESIGN-chain-cardinality.md` — fully neutral.** `grep -n "SKILL.md"` returns
zero hits. Its skill-facing deliverable is the `--upstream` flag on both parents
(frontmatter `:20-22`), which surfaces in `skills/scope/SKILL.md`'s
`## Upstream Flag` (SKILL.md:123) — a different section, untouched.

**`DESIGN-fold-record-removal.md` — neutral.** Its one SKILL.md instruction
(`:214`) is "correct the cross-reference that states the step count", a different
line.

### 8. A supporting repo precedent for de-duplication

`.github/workflows/check-no-duplicate-rule-list.yml:15-18` exists for precisely
this class of defect:

> The writing-style rules have one home. Three copies existed before
> they were consolidated, and they drifted; this fails a PR that
> reintroduces one.

That is a CI gate whose entire premise is that a duplicated body of prose drifted
and had to be consolidated to one home. It does not cover this file, but it is the
repo's own recorded position on the underlying question.

## Implications

1. **The paperwork is one appended amendment section on one document.** Append
   `## Amendment — <landing date>` to
   `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`. Do not edit
   the text above it. Do not change `status: Current`. Do not run
   `shirabe transition`. Do not write a superseding design. Do not write a
   `docs/decisions/DECISION-*.md`. The document will then carry three amendments,
   which `PRD-fold-record-removal.md:462-464` already anticipated and called
   "correct but reads oddly on first encounter".

2. **The amendment's content is two short paragraphs.** One withdrawing SKILL.md as
   a destination for the reader-economy rationale and naming
   `phase-2-chain-orchestration.md:492-500` as the surviving site — noting that this
   is where the reduction is actually performed, so the design's own stated intent
   ("in `/scope`'s own words at the layer that now performs the reduction") is
   served more exactly than by the duplicate. One noting that the SKILL.md
   Consolidation Judgment section narrows to a bounding statement, with the
   procedure staying in phase-2 where the 2026-08-15 amendment and
   `DESIGN-scope-artifact-persistence.md` already put it.

3. **The mandatory non-paperwork edit is `skills/brief/references/phases/phase-0-setup.md:315`.**
   Trim the trailing `and the "Why the Artifact Set Shrinks" section of
   \`skills/scope/SKILL.md\`` clause. Nothing in CI catches this — FC20 keys on
   paths, and `skills/scope/SKILL.md` still exists. If the change ships without it,
   the corpus points at a section that is gone, which is exactly the defect class
   `DESIGN-prose-reference-staleness.md` was written about.

4. **No other document needs touching.** The three round-1-named designs are
   neutral to supported. `DESIGN-fold-record-removal.md` names a different SKILL.md
   line.

5. **The change is not a reversal.** A reversal would be a decision whose conclusion
   is falsified, which is what the 2026-08-15 amendment records for Decision 8. Here
   the decision — that the reader-economy rationale lives inside `/scope` rather
   than behind `/brief`'s unreachable branch — holds unchanged. Only one of the two
   sites it named is withdrawn.

6. **It is also not a no-op, but it is close.** The upstream PRD's R16 and AC18 are
   fully discharged by the phase-2 copy alone, so no requirement is violated and the
   PRD needs no amendment. What is left is a design-level elaboration: the Decision
   Outcome names SKILL.md conjunctively and the Component-changes block lists the
   section as a deliverable. A reader of the Current design who greps SKILL.md and
   finds nothing has been misled, and the corpus's own standard
   (`PRD-fold-record-removal.md:184`) is that a shipped document carries a dated
   section "recording what no longer holds". One paragraph discharges it.

## Surprises

- **The amendment convention is codified as an acceptance criterion, not just
  practice.** AC15 pins the heading regex, the date floor, a content substring, and
  "status unchanged from the merge base". Most repo conventions in this corpus are
  prose; this one was tested.

- **Nothing mechanically ties a Current DESIGN to the skill it specifies.** The
  design corpus's integrity checks are entirely about the `upstream:` graph, status
  vs. directory (L07), and format. A Current design can describe a skill that no
  longer exists and validate clean. The whole burden here is convention.

- **FC20 cannot see this defect.** The one check aimed at reference staleness
  resolves paths, and `skills/scope/SKILL.md` will still be there. The genuinely
  dangling reference — a *section title* inside a surviving file — falls in the gap.
  Worth noting as a real, small, out-of-scope observation about the check's reach.

- **`skills/brief/references/phases/phase-0-setup.md:309-315` already argues the
  exploration's case.** It says the reader-economy goal "is now served where the
  reduction can actually be verified" and then names phase-2 first and SKILL.md
  second. The prose already treats phase-2 as primary; only the trailing pointer
  disagrees.

- **The corpus has a CI gate built on the same argument at a different scale.**
  `check-no-duplicate-rule-list.yml` exists because three copies of the
  writing-style rules drifted. The repo's recorded position is that a duplicated
  body of prose has one home.

## Open Questions

1. **Does `skills/scope/evals/evals.json` assert anything about either section?**
   Round 1 flagged this as an open question and I did not resolve it. The
   fold-record precedent shows evals being rewritten alongside prose changes;
   `DESIGN-scope-artifact-persistence.md:451` also warns that Scenario 17 is a
   deliberate tripwire that must not be rewritten alongside its neighbours. Any
   eval touching this area needs reading before, not after.

2. **Does the rewritten `## Consolidation Judgment` still satisfy the parent-skill
   pattern's required SKILL.md sections?** Round 1's charter-control lead concluded
   neither section is pattern-required (`/charter` carries neither). I did not
   re-verify `references/parent-skill-pattern.md` independently. If that conclusion
   holds, deletion is safe on parity grounds too and the amendment is the only
   artifact needed.

## Summary

The repo's convention for a change that diverges from a status-Current DESIGN is an appended `## Amendment — <date>` section (em dash, ISO date) that leaves the original text unedited, keeps `status: Current`, runs no `shirabe transition`, and writes no superseding design or DECISION record — codified as `PRD-fold-record-removal.md` R10/AC15 and used three times on this exact document family; nothing in `shirabe validate --lifecycle` (L01-L08, status/graph only) or FC20 (path-keyed, notice-level) mechanically checks a Current design's claims against the skill it describes, so this is entirely a convention obligation.

The minimum correct paperwork is one appended paragraph on `DESIGN-scope-consolidation-over-skipping.md` and nothing else — not a reversal, and not quite a no-op: the upstream PRD's binding requirement R16 (`:205-207`) and AC18 (`:282-284`) name only "`/scope`'s phase references", which `phase-2-chain-orchestration.md:492-500` discharges today with the SKILL.md copy gone, so no requirement is violated and the PRD needs no amendment; SKILL.md was a design-level elaboration past the requirement, added by the Decision Outcome (`:414-418`) and the Component-changes block (`:426-430`), and withdrawing it is the weakest form of divergence the corpus amends over — the same shape as `BRIEF-scope-artifact-persistence.md:190-197`. The `## Consolidation Judgment` rewrite needs no separate paperwork, since the 2026-08-15 amendment and `DESIGN-scope-artifact-persistence.md`'s Components table already re-specified that section.

The one edit nothing will catch for you is `skills/brief/references/phases/phase-0-setup.md:315`, which cites `"Why the Artifact Set Shrinks"` by title in shipped skill prose — trim that clause, and the surviving pointer is the phase-2 one the same paragraph already names first; against the other Current designs the change is neutral-to-supported (`scope-artifact-persistence` touches only SKILL.md's write-target set, `scope-chain-mandatory-steps` argues the same one-home principle, `chain-cardinality` never mentions SKILL.md at all).
