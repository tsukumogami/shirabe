---
schema: prd/v1
status: Draft
problem: |
  Document lineage is one-to-many in the formats and in practice, but the
  tooling assumes one-to-one. YAML sequence values never survive frontmatter
  parsing, the chain-targeted check evaluates whichever chain sorts first by
  filename, a document under two chains is given contradictory statuses with
  no diagnostic, and the finalization walk retires shared parents while other
  consumers still depend on them. Five documents in this repository carry
  dangling upstream references produced by exactly that last path.
goals: |
  Lineage that fans out is parsed, evaluated, and reported honestly. A
  document under several chains is either satisfiable or told precisely why
  it is not. Nothing retires a parent that something still points at. Where
  a run consumes an upstream it did not produce, that relationship is
  recorded rather than lost.
upstream: docs/briefs/BRIEF-chain-cardinality.md
motivating_context: |
  An exploration asked whether the /scope consolidation overhaul should be
  ported to /charter. Almost nothing remained to port, but the question
  surfaced that the two chains are not the same shape and that the tooling
  models neither of them correctly.
---

# PRD: Chain Cardinality

## Status

Draft

Requirements only. The technical approach is downstream design work.

## Problem Statement

Document lineage in this workspace is one-to-many. The format references say so — a
VISION lists STRATEGY documents, a STRATEGY lists the ROADMAPs sequencing its work, and
multiple STRATEGYs may operate under one VISION when they make distinct bets. Authors
work that way. Four PRDs across three repositories have several DESIGNs beneath them,
the largest with nine, and that shape is deliberate: an initiative-sized PRD whose
ROADMAP partitions its requirements into disjoint feature slices, one design per slice.

The tooling assumes one-to-one, in four separate places.

**Sequence values do not survive parsing.** An `upstream:` written as a YAML sequence —
block or flow — collapses to the empty string before any consumer sees it, and the
author is told `upstream "" does not exist on disk`. A single-item sequence fails
identically, so this is not a plurality problem but a parsing one. The chain walk
already splits multi-valued upstreams correctly and strips list prefixes; that code has
simply never been reachable. Three readers of the field exist and no two agree on its
shape.

**The chain-targeted check is a filename lottery.** It selects its chain with a
first-match over a map ordered by canonical path, so it evaluates whichever root sorts
first. Renaming a plan with no content change anywhere flips a shared BRIEF between
clean and failing. The whole-tree mode iterates every chain and does not share the
defect, so the two modes disagree about the same corpus.

**A document under two chains is given contradictory obligations.** Posture is a
property of a chain, a chain is identified by its root, and a shared member is cloned
into every chain that reaches it — each imposing an independent requirement on one
mutable status field. Across phase groups those requirement sets are disjoint for BRIEF
(`Accepted` versus `Done`) and for PRD (`Accepted` or `In Progress`, versus `Done`). No
status satisfies both. Sweeping every legal status over a shared BRIEF yields a minimum
of one finding and never zero. Each message reads as ordinary status drift and names one
expectation; nothing says another chain demands the opposite.

**Finalization retires shared parents.** The chain-completion walk follows one branch
and transitions every ancestor, with no consumer count and no warning. It will drive a
shared parent to `Done` while a second live chain requires it open. This is not
hypothetical: five documents in this repository carry dangling `upstream:` references
today, left by one commit that deleted a DESIGN and a PLAN which five siblings pointed
at. Neither gate catches them — CI validates only the files a pull request changed, and
the whole-tree check passes them because they are terminal.

The unsatisfiability is latent rather than live: it needs two plan roots under one
upstream in different phase groups, and plans are deleted at completion, so every
fan-out on disk today is post-completion with nothing live beneath it. That is a reason
to fix it before the shape becomes common, not after — and the fan-out is currently
*suppressing* findings, since a parent passes the orphan rule precisely because it has
children.

Separately, the parent skills cannot record a relationship they already rely on. Every
path a parent resolves derives from one topic slug, so a run that consumes an upstream
authored under a different slug has nowhere to put it. `/scope` invokes `/brief` with a
bare slug on the grounds that nothing sits above the chain head, though a ROADMAP often
does and `/brief` accepts one; the link is silently never recorded. `/charter` has the
same gap with a louder symptom.

## Goals

Lineage that fans out is parsed as written, evaluated against every chain a document
belongs to, and reported the same way regardless of what files are named.

A document under several chains either reaches a status that satisfies all of them or is
told, in one message, that its consumers demand contradictory states and which ones.

Nothing retires or deletes a document while another document still points at it.

Where a run consumes an upstream it did not produce, the relationship is recorded in
durable state rather than inferred from a slug or lost.

Existing single-parent documents — every document in the corpus today — behave exactly
as they do now.

## User Stories

- As a maintainer retiring a shipped plan, I want the lineage walk to tell me which
  chains the plan belongs to, so that I do not retire a parent another chain still
  needs.
- As an author writing a document with two upstreams, I want the list syntax I wrote to
  be understood, so that I am not told my upstream is the empty string.
- As a maintainer running the validator in CI, I want the same answer regardless of what
  sibling files are called, so that a rename cannot turn a passing branch red.
- As an author whose document sits under two chains at different phases, I want to be
  told that the requirements conflict, so that I do not cycle through statuses trying to
  satisfy both.
- As an author opening a second bet under an existing thesis, I want the run to record
  which thesis it attached to, so that the relationship survives into the artifact and
  the audit trail.
- As a reviewer, I want a document's deletion to be blocked while something still cites
  it, so that dangling references are prevented rather than discovered later.

## Requirements

### Functional — parsing and resolution

- **R1.** A frontmatter field whose YAML value is a sequence SHALL survive parsing with
  all entries preserved, in both block and flow syntax, including the single-entry case.
- **R2.** The upstream-resolution check SHALL evaluate each entry of a multi-valued
  `upstream:` independently and report one finding per entry that does not resolve.
- **R3.** The chain walk SHALL treat every entry of a multi-valued `upstream:` as a
  membership edge, rather than retaining only the first.
- **R4.** All readers of the `upstream:` field SHALL agree on its shape. A value that one
  reader accepts SHALL NOT be silently reinterpreted or discarded by another.

### Functional — chain evaluation

- **R5.** The chain-targeted lifecycle check SHALL evaluate every chain that contains the
  target document, not the first chain found.
- **R6.** Lifecycle results SHALL NOT depend on document filenames. Renaming a document
  without changing content SHALL NOT change any finding on any other document.
- **R7.** The chain-targeted mode and the whole-tree mode SHALL report the same findings
  for the same document over the same corpus.

### Functional — conflict diagnosis

- **R8.** When a document belongs to two or more chains whose required status sets have
  no value in common, the validator SHALL emit a single finding identifying the conflict,
  naming each conflicting chain and the status each requires.
- **R9.** When R8 fires, the per-chain findings it supersedes SHALL NOT also be emitted,
  so the author is not shown contradictory instructions alongside the explanation.
- **R10.** When a document belongs to several chains whose required status sets do
  intersect, the document SHALL pass at any status in the intersection.

### Functional — safe retirement

- **R11.** The chain-finalization walk SHALL NOT transition or delete a document while
  another document outside the walked branch still names it as an upstream.
- **R12.** When R11 blocks a transition, the walk SHALL report which documents still
  reference the blocked one.

### Functional — recording a consumed upstream

- **R13.** A parent skill SHALL accept an upstream artifact path as a flag, without
  changing its positional argument contract or its rejection of paths in that slot.
- **R14.** When a parent consumes an upstream it did not produce, it SHALL record that
  path in a conditional state-file field, absent when the condition does not hold.
- **R15.** A parent SHALL pass a recorded upstream path to the child whose input mode
  accepts it, so the produced artifact records the link in its own frontmatter.
- **R16.** R13 through R15 SHALL apply to both parents: the strategic chain's
  VISION-to-STRATEGY hop and the tactical chain's ROADMAP-to-BRIEF hop.

### Non-functional

- **R17.** No document currently in the corpus SHALL change its validation result. The
  full existing test suite SHALL pass unmodified.
- **R18.** No new frontmatter field, artifact type, or document status SHALL be
  introduced.
- **R19.** The conflict finding SHALL be suppressible by the same posture mechanism that
  governs existing lifecycle findings, so draft-stage work is not blocked by it.

## Acceptance Criteria

- [ ] An `upstream:` written as a block sequence with two entries resolves both, and the
      document appears in both chains.
- [ ] An `upstream:` written as a flow sequence behaves identically to the block form.
- [ ] An `upstream:` written as a single-entry sequence resolves that entry and reports
      no error.
- [ ] A multi-valued `upstream:` with one resolvable and one missing target reports
      exactly one finding, naming the missing path — not the empty string.
- [ ] Running the chain-targeted check on a document shared by two chains reports the
      same findings as the whole-tree check reports for that document.
- [ ] Renaming a plan file, with no content change anywhere in the corpus, produces
      byte-identical validator output before and after.
- [ ] A BRIEF shared by one in-flight chain and one completing chain produces a single
      conflict finding naming both chains and both required statuses, and does not
      additionally produce the two per-chain findings.
- [ ] A DESIGN shared by two chains whose required sets intersect at one status passes at
      that status with no finding.
- [ ] Chain finalization against a plan whose ancestors are shared refuses to transition
      the shared ancestor and names the documents still pointing at it.
- [ ] Chain finalization against a plan whose ancestors are unshared behaves exactly as
      it does today.
- [ ] A parent invoked with an upstream-path flag records that path in its state file;
      the same parent invoked without the flag has no such field.
- [ ] The artifact produced by a run that consumed a recorded upstream carries that path
      in its own `upstream:` frontmatter.
- [ ] Validating all three repositories before and after produces identical output in
      both draft and ready postures.
- [ ] The existing test suite passes with no test modified or removed.

## Out of Scope

- **Full edge-attached posture.** Making posture a property of the upstream edge rather
  than the chain would let two chains impose different obligations on one document
  coherently. It requires graph traversal in place of per-root walks, set algebra over
  required-status values, and a defined answer to which chain a targeted check means. The
  requirements above make the current model honest instead; if the conflict finding turns
  out to fire often in practice, that is the signal to revisit this.
- **Porting the consolidation judgment to `/charter`.** Settled on the record; zero
  strategic hops are section-mappable.
- **Consumer-count input to the consolidation judgment's absorbability test.** R11 blocks
  unsafe deletion at the finalization path, which is where the observed damage came from.
  Whether absorbability should also weigh consumer count is a narrower question the
  design may raise on its own evidence.
- **Inputs the validator silently declines to check.** Passing a directory to the
  per-file mode discards it without warning and exits zero; so does a document whose
  frontmatter omits `schema`, which is skipped with a notice and a zero exit. Both
  produced false clean results during this PRD's own authoring. They are real defects of
  the same class — a validator that reports success for work it did not do — and they
  warrant their own issue rather than riding along here.
- **Retrofitting the corpus.** The five dangling references this PRD's problem statement
  cites are evidence, not scope. Repairing them is follow-up work once the check that
  would have caught them exists.
- **`/design`'s self-split.** The refuse-at-ten threshold has never fired, has no naming
  convention for the sibling document it would create, and no owner for the prompt it
  would raise inside a parent chain. It is a real gap and not this one.
- **The other parent skills** beyond the two chains named in R16.

## Decisions and Trade-offs

**The three fan-out mechanisms are not one thing, and only two are in scope.**
Roadmap-mediated fan-out — one initiative PRD, a roadmap partitioning requirements, one
design per slice — is intended, documented, and produces the four real cases. Multi-valued
`upstream:` is permitted by the formats and unreachable in the parser. `/design`'s
self-split is unconsidered and untrodden. This PRD serves the first two and excludes the
third. The brief's open question "is `PRD -> DESIGN` fan-out intended, tolerated, or
forbidden" closes as: intended, when a roadmap mediates it.

**Posture stays attached to the chain.** The alternative — attaching it to the edge — is
the only option that makes two chains' differing obligations coherent rather than merely
diagnosable, and it was rejected on cost. It rewrites the module's core data structures,
while making the current model honest and diagnostic is a change to three functions plus
a conflict check built over structures that already exist. The trade-off accepted is that
a genuinely conflicted document is reported rather than resolved: the author is told to
fix the lineage, not given a status that satisfies everyone. The brief's open question
about where posture attaches closes as: the chain, with the conflict made explicit.

**The product is "make it honest," not "make fan-out easy."** The brief's third open
question offered supporting fan-out, refusing it legibly, or documenting the constraint.
Documenting the constraint was rejected because it contradicts an already-accepted
requirement in this repository stating that the walker handles both scalar and list
upstream shapes — a requirement the shipped code does not meet. Refusing fan-out legibly
was rejected because the corpus already contains it, deliberately, in four places. What
is chosen supports the fan-out that exists and diagnoses the case the model cannot
represent.

**The parent half is recorded in state and supplied by flag.** Alternatives were an
upstream-path input mode mirroring the child skill's, and a discovery scan that asks
which upstream to attach to. The input mode reopens a standing requirement that parents
reject artifact paths in their positional slot, and still needs the topic slug from
somewhere, making it two inputs wearing one input's costume. The scan adds a blocking
prompt to every run and has no safe non-interactive default — attaching a bet to the
wrong upstream silently is worse than today's visible duplicate. The flag leaves the
positional contract untouched and works identically for both chains.

**Fixing this makes a latent defect live, deliberately.** The conflict condition needs
two chains running concurrently under one upstream, which the corpus has never had. A
workflow that records consumed upstreams will make that shape more common. The
requirements above are sequenced so the diagnosis exists before the shape spreads.

## Known Limitations

- The conflict finding tells an author their consumers disagree; it does not tell them
  which consumer is wrong. Resolving that needs judgment the validator does not have.
- R11 blocks unsafe retirement at the finalization walk. A document deleted by any other
  means — a plain `git rm`, a manual edit — is still capable of stranding references, and
  only a subsequent whole-corpus validation will surface it.
- The strategic chain remains outside the lifecycle document index, so R5 through R10 do
  not apply to VISION, STRATEGY, or COMP documents. No such document exists in any
  repository in this workspace; the strategic half of the fan-out problem is entirely
  prospective, and admitting those directories to the index is a change this PRD does not
  require.
- R17's guarantee that nothing changes rests on no document in the corpus currently using
  a sequence-valued frontmatter field. That was verified across all three repositories at
  the time of writing.
