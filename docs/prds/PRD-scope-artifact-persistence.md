---
schema: prd/v1
status: Draft
problem: |
  `/scope`'s consolidation judgment gates absorption on a comparison between
  two type schemas, so above the BRIEF-to-PRD hop its verdict is fixed before
  either document is read. Every completed run leaves a permanent PRD and
  DESIGN whether or not the work earned them, and the only way to a smaller
  set is to leave `/scope` and invoke a child skill directly.
goals: |
  Each hop's verdict is decided against the two documents in front of it, so a
  run ends with all four artifacts, some, or none according to what it actually
  produced. Reductions stay honest: a survivor carries what it absorbed, a
  deletion cannot strand a citation, and the default branch records that the
  fold happened.
upstream: docs/briefs/BRIEF-scope-artifact-persistence.md
source_issue: 280
---

# PRD: Scope Artifact Persistence

## Status

Draft

Requirements drawn from the accepted BRIEF plus the upstream exploration, whose
five settled decisions are recorded under Decisions and Trade-offs rather than
re-opened. Three questions are left live for the DESIGN and named in Open
Questions.

## Problem Statement

`/scope` walks BRIEF, PRD, DESIGN and PLAN, deciding per hop whether each
document folds into the next. The judgment has three stages: whether absorption
is possible, whether it is warranted, and the move plus its verification. Stage
2 is the one that reads the documents and the only one that can answer
differently on different runs.

Stage 1 short-circuits it. It asks whether the downstream *type's* required
sections have a home for every required section of the upstream *type* — a
schema comparison, reached without opening either document, with the same answer
on every run. Against the current formats it is true for BRIEF-to-PRD and false
everywhere else, permanently. So above the first hop the verdict is `keep`
regardless of whether the DESIGN carries four hundred lines of contested
architecture or restates a decision the PLAN already encodes.

Every completed run therefore leaves a permanent PRD and DESIGN — correct for
work that earned them, ceremony for work that didn't. An author who wants a
smaller set has to leave `/scope` and invoke a child skill directly, which means
the judgment isn't encapsulated in the workflow that owns it. It's made by the
author, in advance, from outside, when they have least information about what
the work will become.

Two things compound it. The absorb procedure below the verdict has never
executed once in this repository, so every path it would take is untested and
four defects are already visible by reading. And because only the largest
outcome is reachable, documents accumulate because nothing ever asks whether
they should.

## Goals

An author runs `/scope` and gets an artifact set that reflects the work. A
contested change keeps the altitudes it earned. A self-contained fix folds down
to its code. The author picks neither and doesn't have to know which way the run
is heading when it starts.

Reductions stay honest under that pressure. A survivor carries what it absorbed
in a form a cold reader can use, a deletion cannot strand a reference elsewhere
in the repository, and the default branch keeps a record that the fold happened
and what it claimed to carry.

## User Stories

**As a maintainer fixing a self-contained bug**, I want the chain to fold its
own scaffolding away once it has served its purpose, so that an afternoon's work
doesn't leave three permanent documents describing it.

**As an author making a contested architectural change**, I want every altitude
that did independent work to survive, so that the reasoning behind a rejected
option is still there when someone reopens the question a year later.

**As a contributor reading a surviving document months later**, I want to tell
whether it absorbed something and where that content went, so that a section
reading unlike the rest of the document is explicable rather than mysterious.

**As a contributor following a citation to a document that folded away**, I want
the trail to continue, so that a path from an old issue leads me to the survivor
instead of ending in a rotted reference.

**As a maintainer of this repository**, I want a fold that would strand a
citation to be refused rather than performed, so that the reduction cannot
silently break a reference that CI structurally cannot see.

## Requirements

### Functional

**R1.** The absorbability decision SHALL be made against the two documents
present at the hop, not against their types. No hop SHALL be unabsorbable purely
because of the types involved.

**R2.** Each artifact type SHALL declare one contribution it makes to the chain.
A document that absorbs an ancestor SHALL carry that ancestor's contribution as
a single section, placed ahead of its own content in chain order.

**R3.** Contributions SHALL accumulate transitively: a document that absorbs an
ancestor which had itself absorbed another owes both. The number of contribution
sections a document carries SHALL be bounded by the number of ancestor types.

**R4.** A contribution section SHALL carry an adequacy expectation with both a
too-long and a too-thin failure, judged against whether the survivor's own
argument stands without the absorbed document. Presence alone SHALL NOT satisfy
it.

**R5.** `shirabe validate` SHALL require the contribution sections a document's
declared absorptions imply, and SHALL leave documents declaring no absorption
unaffected.

**R6.** The DESIGN-to-PLAN hop SHALL be absorbable when the judgment finds the
DESIGN holds nothing beyond its contribution that compression would lose.

**R7.** The fold verdict SHALL be the judging agent's call at every hop,
including the terminal one. No independent reviewer, human confirmation, or
mode-conditional gate SHALL be added to it.

**R8.** The absorb procedure SHALL author the contribution section before
building the carry table, so the recorded verdict is a consequence of authored
text rather than a prediction.

**R9.** The carry check SHALL run per contribution at every hop. A contribution
that does not carry SHALL abort the absorb, downgrade the verdict to `keep`, and
delete nothing.

**R10.** Before deleting an artifact, the procedure SHALL determine whether any
other file in the repository cites it. A citation by path SHALL downgrade the
verdict to `keep` through the existing abort path. A weaker citation match SHALL
be surfaced to the judging agent rather than acted on mechanically. The check
SHALL have no override and SHALL NOT be capable of any outcome stronger than
`keep`.

**R11.** Re-pointing a survivor's `upstream:` SHALL splice the absorbed
artifact's parents into the survivor's existing list rather than replacing it,
preserving sibling parents and cross-repo entries verbatim.

**R12.** Post-absorb re-validation SHALL cover the survivor and every document
that referenced the absorbed artifact, so a failure reverts the absorb.

**R13.** `/scope`'s closed write-target set SHALL name every path an absorb at
any hop writes or deletes.

**R14.** A completed fold SHALL leave a record on the default branch naming what
folded into what, on what verdict, with the per-contribution carry result and a
content-addressed pointer to the pre-fold original. The record SHALL be produced
mechanically, SHALL NOT carry the absorbed document's contributions, and its
absence SHALL prevent the fold.

**R15.** A surviving document SHALL record what it absorbed in both a
machine-readable frontmatter field and one human-readable line in its `## Status`
section naming which contribution section now carries the folded content. The
frontmatter field SHALL be excluded from path resolution, since its target is
deleted by construction.

**R16.** `/execute` SHALL NOT assume a surviving DESIGN. Its finalization guard
and the cascade's roadmap downstream-reference rewrite SHALL both behave
correctly when the chain folded the DESIGN away.

**R17.** Implementation SHALL carry a standing instruction to record in code
comments why the code is shaped as it is, kept current as the code changes,
unconditional and independent of what the chain decided. The instruction SHALL
be enforced through an existing blocking review path rather than a new gate.

**R18.** The skill's eval suite SHALL be updated so that no eval asserts the
type-level absorbability rule or the durable-artifact floor as invariants.

### Non-functional

**R19.** The consolidation judgment SHALL remain the only mechanism that reduces
the artifact set. Nothing added here SHALL constitute a second reduction
mechanism; a mechanism whose only possible effect is to force `keep` does not
count.

**R20.** No judgment SHALL run before the artifact it is about exists. Nothing
here SHALL reintroduce a pre-artifact worth decision in any form, including an
author-chosen entry altitude.

**R21.** Documents already on disk SHALL validate unchanged. The
contribution-section requirement SHALL apply only to documents that declare an
absorption.

**R22.** The absorb procedure SHALL fail toward `keep` at every added decision
point.

## Acceptance Criteria

- [ ] A chain whose DESIGN holds only sequencing value folds that DESIGN into
      the PLAN, and the run ends with no durable artifact in `docs/`.
- [ ] A chain whose DESIGN records live rejected alternatives returns `keep` at
      the DESIGN-to-PLAN hop, and the DESIGN survives.
- [ ] The same two chains differ only in document content, not in flags, mode,
      or invocation.
- [ ] A survivor that absorbed a BRIEF carries one contribution section for it,
      ahead of the survivor's own content.
- [ ] A survivor that absorbed a PRD which had absorbed a BRIEF carries two
      contribution sections, in chain order.
- [ ] `shirabe validate` fails a document that declares an absorption and lacks
      the implied contribution section.
- [ ] `shirabe validate` passes every document in `docs/` that declares no
      absorption, with no change to those documents.
- [ ] An absorb whose contribution does not carry leaves both documents on disk
      and records the failure.
- [ ] An absorb of an artifact cited by path from any other file in the
      repository is refused, both documents stay, and the citing file is named.
- [ ] A survivor whose absorbed ancestor had two parents carries both parents in
      its `upstream:` field after the re-point.
- [ ] A completed fold leaves a record on the default branch identifying the
      absorbed document, the survivor, the verdict, and a pointer that resolves
      to the pre-fold content.
- [ ] A survivor's `## Status` section names what it absorbed and which section
      carries it.
- [ ] `shirabe validate` reports no finding against a survivor's
      absorbed-artifact frontmatter field, whose target no longer exists.
- [ ] A finalized chain with no surviving DESIGN passes `/execute`'s
      finalization guard.
- [ ] A finalized chain with no surviving DESIGN leaves no dangling downstream
      reference in an upstream roadmap.
- [ ] No eval in the suite asserts that hops above BRIEF-to-PRD are
      unabsorbable, or that a run always leaves a durable artifact.
- [ ] `cargo test` passes and the existing golden fixtures are updated in the
      same change as any format-contract edit.

## Out of Scope

- **Retroactive application to documents already on disk.** The judgment runs
  against two bodies that exist at the moment a child lands. For most DESIGNs in
  the corpus the downstream PLAN was deleted at finalization by design, so there
  is one body and no landing event; `keep` there is the absence of a runnable
  judgment rather than a verdict. Whether a settled document is live guidance or
  the historical record of shipped work is a lifecycle question with its own
  criterion and its own disposal, deferred as named follow-on work.
- **The strategic chain under `/charter`.** No consolidation judgment exists
  there to change, and the judgment's logic lives entirely inside `/scope`'s own
  phase files, so extending it is new machinery rather than a follow-on edit.
- **Manual invocation of child skills outside `/scope`**, the only route to a
  chain with a genuinely missing ancestor.
- **A repository-wide citation index, and a validator rule for unresolvable
  citations generally.** Both are repair campaigns against references already
  broken, not guards on the operation this work adds.
- **The CI deletion blindness.** `validate-docs.yml` computes its file set with
  `git diff` and cannot see a document stranded by a deletion. Widening the diff
  filter is not a fix, because it feeds deleted paths to a validator that cannot
  open them. R10's guard makes fold time the catchable point instead.

## Decisions and Trade-offs

Each ran through the `/decision` framework during exploration; the two marked
critical ran the full adversarial path with persistent validators. These are
inputs to the DESIGN, not questions for it.

**Contribution sections carry a two-sided adequacy test** rather than a presence
check. The criterion is lifted from `strategy-format.md`'s Strategic Context
contract, which is a contribution section in all but name and already ships: if
the section reads like a rewrite of the upstream, fold it back; if a reader
cannot follow *this* document's argument without the upstream, expand. Presence-
only was rejected because it hollows out the carry check while keeping its shape,
contradicting the principle that absorption is only legitimate when something
confirms the content arrived. A scored rubric was rejected because this repo has
no scored rubric anywhere and its functional tests demonstrably work. No word
count or length floor: under a model whose point is compression, a floor inverts
the incentive and padding satisfies it free.

**The verdict gets no gate; the operation gets the backstop.** Both rival
advocates withdrew their own alternatives. Human confirmation is self-refuting
against the decision that agents make this call, and fails differently in all
three of its sub-variants. An independent reviewer is structurally unavailable:
`/scope` owns no team at its own layer, has no sub-agent spawn site in any of its
seven phase files, and no row in the dispatch binding table. The reviewer's one
real contribution — judging an artifact rather than a prediction — is bought for
free by R8's reorder.

**A durable record of the operation, not of the distillate.** Any destination
preserving the absorbed content must assert, every time it fires, that the
verdict was partly wrong, since the fold's meaning is that the content did not
warrant a durable artifact. A record that a judgment happened, about what, with
what carried, asserts nothing the fold denies. It is written mechanically because
an agent-authored record inserts another unverifiable content judgment at the
moment of maximum consequence.

**A survivor records what it absorbed in frontmatter plus one `## Status` line.**
This is house pattern rather than invention: `shirabe transition` already writes
a `superseded_by:` key and splices a line into `## Status` for supersession, the
nearest existing analogue. The beneficiary is the reader of a third document
citing the dead path, who is not holding the survivor and does not know it
exists. A tombstone stub was stronger on the merits and was rejected because it
leaves one durable file per fold in the corpus that motivated this work.

**Everything ships in one change with no ordering constraint.** The repo's own
plan rule makes one PR the default and permits a split only on a named hard
constraint; this work has none. The rationale-in-code instruction is bounded to
two diff-checkable edits so it cannot expand into an open-ended quality effort
and become a de facto blocker.

## Known Limitations

**Static validation buys presence, not fidelity.** An empty or gutted
contribution section satisfies R5. R4's adequacy test is prose an agent applies,
as every content criterion in this repository is. The residual gaming vector is
omission: an agent that writes one fluent paragraph and silently drops the one
contested thing the ancestor settled is not caught, because the folding agent
cannot see the absence it created.

**The worth judgment ships ungraded and ungradeable.** A fixture eval can grade
whether content was lost, because the fixture retains both bodies. It cannot
grade whether reasoning deserved to persist, and after the fold the comparison
object is gone. A green eval is not a check on the whole judgment.

**Forward absorption has no recovery path from a clone.** Squash-merge with
branch deletion means an absorbed document never existed on the default branch.
`refs/pull/<N>/head` retains the content, but that is best-effort platform
behaviour rather than a git guarantee, which is why R14's pointer is
content-addressed rather than a path.

**R10's guard is same-repo only.** Cross-repo citations exist and stay
unguarded. Issue bodies, PR descriptions and commit messages are outside its
reach entirely, so its coverage is a floor rather than a bound.

**The rationale-in-code instruction is unmeasurable.** No check distinguishes a
run that wrote useful why-comments from one that did not. R17 accepts an
instruction plus an existing blocking reviewer as the honest ceiling for a
qualitative property.

**This chain cannot dogfood the change.** The run producing this PRD uses the
current `/scope`, so it will leave a permanent PRD and DESIGN regardless of what
the new judgment would have decided about them.

## Open Questions

- What surface carries R14's record? A single shared append-only index is the
  leading candidate because it is not a per-run artifact and so cannot read as a
  floor, but a survivor's frontmatter serves the one hop that has a survivor, and
  there are three deletion sites rather than one.
- Is the contribution section authored by the child at drafting time or by the
  parent at fold time? R8 fixes the ordering within the absorb, but not which
  actor writes the prose, and the answer decides whether R4's criterion rides an
  existing jury or needs its own reviewer.
- Does `DESIGN-scope-consolidation-over-skipping.md`'s Decision 9 get amended?
  Its stated rationale — that zero strategic hops are absorbable, so porting the
  judgment would install a rule that can only return `keep` — is falsified by R1,
  and it sits durably on `main` reachable from this chain's own references.

## References

- `docs/briefs/BRIEF-scope-artifact-persistence.md` — the framing these
  requirements are written from.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — Decision 8
  rejected DESIGN-to-PLAN absorption; R6 reverses it. Decision 9's rationale is
  the subject of an open question above.
- `docs/prds/PRD-scope-consolidation-over-skipping.md` — R14 there requires the
  floor R1 removes.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — the three
  stages and the mapping table.
