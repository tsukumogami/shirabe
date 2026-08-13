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
  it is not. Nothing retires a parent that something still points at. No
  author is silently handed a duplicate upstream, and where a run consumes an
  upstream it did not produce, that relationship survives the run.
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

### Terms used here

A **chain** is one lineage the validator walks. It is identified by its **root**, which
is the *downstream-most* document — a PLAN or a ROADMAP — and the walk proceeds upward
through `upstream:` links to the head. Root therefore means the leaf, not the ancestor;
every other directional word in this document (upstream, parent, ancestor) points the
opposite way.

A **posture** is the state a chain as a whole is in, inferred from its root: whether the
work is mid-flight or completing, and whether it runs as one pull request or many. A
chain's posture determines, for each role in it, which document statuses are acceptable —
the role's **required status set**. Postures fall into two **phase groups**: in-flight and
completing. Within a group the required sets agree; across groups they do not.

Separately, the validator runs in two modes: **whole-tree**, which evaluates every chain
in a corpus, and **chain-targeted**, which is asked about one document and evaluates the
chain containing it.

**Consumer** means a document that names another as its `upstream:`. Where this document
means a skill invocation reading an upstream, it says so.

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
author is told `upstream "" does not exist on disk`. A single-entry sequence fails
identically, so this is not a plurality problem but a parsing one. The chain walk
already splits multi-valued upstreams correctly and strips list prefixes; that code has
simply never been reachable. Three readers of the field disagree about its shape: two
treat the whole value as a single path, the third understands a list — and the walk
consuming that third reader discards every entry after the first.

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

Separately, the parent skills cannot record a relationship they already rely on, and do
not admit when they cannot. Every path a parent resolves derives from one topic slug, so
a run consuming an upstream authored under a different slug has nowhere to put it. Worse,
the run cannot see that upstream at all: it reads the absence as a cold start and authors
a fresh one, silently, with no way for the author to say the thesis already exists.
`/scope` has the same gap with a quieter symptom — it invokes `/brief` with a bare slug
on the grounds that nothing sits above the chain head, though a ROADMAP often does and
`/brief` accepts one, so the link is simply never recorded.

## Goals

Lineage that fans out is parsed as written, evaluated against every chain a document
belongs to, and reported the same way regardless of what files are named. This reaches
the tactical chain, which is the only chain the validator indexes; the strategic chain
stays outside it, for the reason given in Out of Scope.

A document under several chains either reaches a status that satisfies all of them or is
told, in one message, that its consumers demand contradictory states and which ones.

The finalization walk never retires or deletes a document that another document still
points at. Removal by other means remains possible and is caught later, by validation
rather than prevention.

No author is handed a duplicate upstream without having been given the chance to name the
existing one, and a relationship a run does consume survives into the artifact and the
run's own record.

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
- As an author opening a second bet under an existing thesis, I want to be told that an
  existing thesis may apply before a new one is written for me, so that I do not discover
  the duplicate afterwards.
- As an author resuming an interrupted run, I want to be told if the upstream it recorded
  has since moved or been retired, so that the run does not continue against a stale link.
- As a reviewer, I want the finalization walk to refuse to retire a document while
  something still cites it, so that the path which produced the dangling references
  already in this repository cannot produce more.

## Requirements

### Functional — parsing and resolution

- **R1.** Any frontmatter field whose YAML value is a sequence SHALL survive parsing with
  every entry preserved and individually recoverable, in both block and flow syntax,
  including the single-entry case. The guarantee is generic to sequence-valued fields, not
  special-cased to `upstream:`, and every reader of such a field SHALL be able to recover
  the same entries in the same order.
- **R2.** The upstream-resolution check SHALL evaluate each entry of a multi-valued
  `upstream:` independently and report one finding per entry that does not resolve.
- **R3.** An `upstream:` field that is present but carries no entries SHALL report exactly
  one finding identifying the field as empty. It SHALL NOT pass silently, and it SHALL NOT
  report a path-shaped message about the empty string.
- **R4.** The chain walk SHALL treat every entry of a multi-valued `upstream:` as a
  membership edge, rather than retaining only the first.
- **R5.** Every reader of the `upstream:` field SHALL interpret the same written value the
  same way. A value one reader accepts SHALL NOT be silently reinterpreted or discarded by
  another.

### Functional — chain evaluation

- **R6.** The chain-targeted lifecycle check SHALL evaluate every chain that contains the
  target document, rather than one selected chain. Where several chains produce the same
  finding on the same document, it SHALL be reported once; where they produce different
  findings, each SHALL be reported.
- **R7.** Lifecycle findings SHALL NOT depend on document filenames. Renaming a document
  without changing content SHALL NOT add, remove, or alter any finding on any document,
  including the renamed one. The path a finding names may change with the rename; nothing
  else may.
- **R8.** The chain-targeted mode and the whole-tree mode SHALL report the same findings
  for the same document over the same corpus.

### Functional — conflict diagnosis

- **R9.** When a document belongs to two or more chains whose required status sets have
  no value in common, the validator SHALL emit a single finding identifying the conflict,
  naming each conflicting chain and the full set of statuses each requires.
- **R10.** When R9 fires and is reported, the status-lifecycle findings arising from the
  conflicting chains' requirements on that document SHALL NOT also be reported, so the
  author is not shown contradictory instructions alongside the explanation. Findings of
  every other kind on that document — unresolvable upstreams, orphan status, file
  location — SHALL be reported unchanged.
- **R11.** When a document belongs to several chains whose required status sets do
  intersect, the document SHALL pass at any status in the intersection.

### Functional — safe retirement

- **R12.** The chain-finalization walk SHALL NOT transition or delete a document while a
  document it is not itself retiring in this walk still names it as an upstream, and that
  referrer has not reached a terminal status. A referrer already at a terminal status does
  not block, so a document cannot be pinned open forever by a finished sibling.
- **R13.** When R12 blocks a transition or a deletion, the walk SHALL report which
  documents still reference the blocked one.
- **R14.** When a document in the finalization walk has more than one upstream, the walk
  SHALL account for all of them. It SHALL NOT transition any ancestor on the basis of a
  single arbitrarily-selected upstream.

### Functional — upstreams a run did not produce

- **R15.** Before authoring a new artifact at its chain's head altitude, a parent SHALL
  make visible that an existing artifact elsewhere may apply, and how to attach to it. An
  author who names none still receives a new artifact — but never without having been
  told one might already exist.
- **R16.** A parent SHALL accept an upstream artifact path supplied as a flag, without
  changing its positional argument contract or its rejection of paths in that slot.
- **R17.** An upstream a run consumed but did not produce SHALL be recorded durably enough
  to survive an interrupted run, and SHALL be absent from that record when no such
  upstream was consumed.
- **R18.** A parent SHALL pass a consumed upstream to the child whose input mode accepts
  it, so that the produced artifact records the link in its own frontmatter.
- **R19.** When a recorded upstream no longer resolves on resume, the run SHALL surface it
  rather than continuing as though no upstream had been recorded.
- **R20.** R15 through R19 SHALL apply to both parents: the strategic chain's
  VISION-to-STRATEGY hop and the tactical chain's ROADMAP-to-BRIEF hop.

### Functional — specifications matching behavior

- **R21.** The format references SHALL state which written shapes of `upstream:` are
  supported, so that every shape the tooling accepts is documented and no shape they
  document is rejected.
- **R22.** The accepted acceptance criterion describing a path in a parent's positional
  slot as slug-derived SHALL be corrected to match the rejection the parents actually
  implement and that R16 preserves.

### Non-functional

- **R23.** No document currently in the corpus SHALL change its validation result. The
  full existing test suite SHALL pass unmodified, including the cross-implementation
  parity gate.
- **R24.** No new frontmatter field, artifact type, or document status SHALL be
  introduced.
- **R25.** The conflict finding SHALL be governed by the same posture mechanism as
  existing lifecycle findings. Where posture suppresses it, the per-chain findings it
  would have superseded SHALL be reported instead, so a conflicted document is never
  silent.
- **R26.** R9 through R11 SHALL be in place before R15 through R20 ship. No release SHALL
  make it easier to create concurrent chains under one upstream before the conflict those
  chains can produce is diagnosable.

## Acceptance Criteria

- [ ] An `upstream:` written as a block sequence with two entries resolves both, and the
      document appears in both chains.
- [ ] An `upstream:` written as a flow sequence behaves identically to the block form.
- [ ] An `upstream:` written as a single-entry sequence resolves that entry and reports
      no error.
- [ ] A multi-valued `upstream:` with one resolvable and one missing target reports
      exactly one finding, naming the missing path — not the empty string.
- [ ] A present-but-empty `upstream:` reports exactly one finding naming the field as
      empty.
- [ ] The same document with the same `upstream:` value produces consistent lineage under
      the resolution check, the chain walk, and the finalization walk.
- [ ] Running the chain-targeted check on a document shared by two chains reports the
      same findings as the whole-tree check reports for that document.
- [ ] Renaming a plan file, with no content change anywhere in the corpus, produces the
      same set of findings before and after, differing only where a finding names the
      renamed path itself.
- [ ] A document belonging to three chains, two of which produce the same finding on it,
      has that finding reported once.
- [ ] A conflicted document still reports its unresolvable-upstream and orphan findings
      alongside the conflict finding.
- [ ] Chain finalization proceeds when the only document still referencing the ancestor
      has itself reached a terminal status.
- [ ] No release ships the upstream-recording requirements without the conflict-diagnosis
      requirements already present.
- [ ] A BRIEF shared by one in-flight chain and one completing chain produces a single
      conflict finding naming both chains and both required statuses, and does not
      additionally produce the two per-chain findings.
- [ ] A DESIGN shared by two chains whose required sets intersect at one status passes at
      that status with no finding, and no conflict finding is emitted.
- [ ] Under a posture that suppresses the conflict finding, the same shared BRIEF still
      reports the per-chain findings rather than reporting nothing.
- [ ] Chain finalization against a plan whose ancestors are shared refuses to transition
      the shared ancestor and names the documents still pointing at it.
- [ ] Chain finalization against a plan whose ancestors are unshared behaves exactly as
      it does today.
- [ ] Chain finalization against a document with two upstreams does not transition an
      ancestor reachable through only one of them.
- [ ] A parent run that would author a head-altitude artifact states, before doing so,
      that an existing one may apply and how to supply it.
- [ ] A parent invoked with an upstream-path flag records that path; the same parent
      invoked without the flag has no such record.
- [ ] A parent invoked with a path in its positional slot still rejects it.
- [ ] The artifact produced by a run that consumed a supplied upstream carries that path
      in its own `upstream:` frontmatter.
- [ ] Resuming a run whose recorded upstream has since been deleted surfaces that fact
      rather than proceeding.
- [ ] Both the strategic and the tactical parent satisfy the four criteria above.
- [ ] The format references name every `upstream:` shape the tooling accepts, and the
      tooling accepts every shape they name.
- [ ] No frontmatter field, artifact type, or status exists after the change that did not
      exist before.
- [ ] Validating all three repositories before and after produces identical output in
      both draft and ready postures.
- [ ] The existing test suite, including the cross-implementation parity gate, passes with
      no test modified or removed.

## Out of Scope

- **Full edge-attached posture.** Making posture a property of the upstream edge rather
  than the chain would let two chains impose different obligations on one document
  coherently. It requires graph traversal in place of per-root walks, set algebra over
  required-status values, and a defined answer to which chain a targeted check means. The
  requirements above make the current model honest instead; if the conflict finding turns
  out to fire often in practice, that is the signal to revisit this.
- **Admitting the strategic directories to the lifecycle index.** The brief asked whether
  they should enter it. They should not, yet: no VISION, STRATEGY, or COMP document exists
  in any repository in this workspace, so indexing them would add a code path with nothing
  to exercise it. R6 through R11 therefore do not reach the strategic chain, and the
  strategic half of the fan-out problem stays prospective until a corpus exists.
- **Recording competitive analysis as a parallel input.** The brief carved this in. It is
  excluded here because the artifact type has no `upstream:` field at all and no document
  of that type exists in this workspace; stating its relationship in the format references
  is a documentation change with no consumer, and R21 is scoped to `upstream:` shapes.
- **Porting the consolidation judgment to `/charter`.** Settled on the record; zero
  strategic hops are section-mappable.
- **Consumer-count input to the consolidation judgment's absorbability test.** R12 blocks
  unsafe retirement at the finalization path, which is where the observed damage came from.
  Whether absorbability should also weigh consumer count is a narrower question the
  design may raise on its own evidence.
- **Inputs the validator silently declines to check.** Passing a directory to the
  per-file mode discards it without warning and exits zero; so does a document whose
  frontmatter omits `schema`, which is skipped with a notice and a zero exit. Both
  produced false clean results during this PRD's own authoring. They are real defects of
  the same class — a validator reporting success for work it did not do — and they
  warrant their own issue rather than riding along here.
- **Retrofitting the corpus.** The five dangling references this PRD's problem statement
  cites are evidence, not scope. Repairing them is follow-up work once the check that
  would have caught them exists.
- **`/design`'s self-split.** The refuse-at-ten threshold has never fired, has no naming
  convention for the sibling document it would create, and no owner for the prompt it
  would raise inside a parent chain. It is a real gap and not this one.
- **The other parent skills** beyond the two chains named in R20.

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
where making the current model honest and diagnostic works with the structures already
there. The design owns the actual sizing. The trade-off accepted is that
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

**A conflicted document is never silent.** R10 suppresses per-chain findings in favour of
the conflict message, and R25 lets posture suppress the conflict message. Composed
carelessly those two would leave a conflicted document reporting nothing at draft
posture, where today it reports errors. R25 is written so the suppression trades one
message for the other rather than removing both. The cost is that a draft-posture author
sees the older, less helpful findings rather than none.

**The parent half is supplied by flag and recorded durably.** Alternatives were an
upstream-path input mode mirroring the child skill's, and a discovery scan that asks
which upstream to attach to. The input mode reopens a standing requirement that parents
reject artifact paths in their positional slot, and still needs the topic slug from
somewhere, making it two inputs wearing one input's costume. The scan adds a blocking
prompt to every run and has no safe non-interactive default — attaching a bet to the
wrong upstream silently is worse than today's visible duplicate. The flag leaves the
positional contract untouched and works identically for both chains. R15 covers what the
flag alone does not: an author who does not know the flag exists still gets told, rather
than silently receiving a duplicate.

**Fixing this makes a latent defect live, deliberately — and the guard is a requirement,
not a hope.** The conflict condition needs two chains running concurrently under one
upstream, which the corpus has never had, because plans are deleted at completion and
every fan-out on disk is post-completion. A workflow that records consumed upstreams will
make concurrent chains more common. The alternative considered was to ship the validator
half alone and defer the parent half until the diagnosis had been exercised in practice.
It was rejected because it leaves the brief's own outcome unmet for however long the
deferral lasts — authors keep receiving silent duplicates — and because the two halves
share a release, so the deferral would have to be enforced by memory. R26 encodes the
ordering instead, since a requirement list is not itself an ordering contract and a plan
that split this across pull requests could otherwise land the recording half first while
conforming to every other word here.

One hole in that guard is worth stating plainly rather than leaving to be discovered.
R6 through R11 reach only the tactical chain, because the strategic directories are not
indexed and this PRD does not change that. R20 nonetheless requires the strategic hop to
record consumed upstreams. So on the strategic chain the workflow becomes easier while no
diagnosis exists at all. The exposure is bounded by there being no strategic document in
any repository in this workspace today — the shape cannot spread through a corpus that
does not exist — but the moment one is written, that chain has the recording half without
the diagnostic half. Admitting the directories to the index is the fix, and it is
deferred, not solved.

## Known Limitations

- The conflict finding tells an author their consumers disagree; it does not tell them
  which consumer is wrong. Resolving that needs judgment the validator does not have.
- R12 blocks unsafe retirement at the finalization walk. A document removed by any other
  means — a plain `git rm`, a manual edit — can still strand references, and only a
  subsequent whole-corpus validation will surface it.
- R23's guarantee that nothing changes rests on no document in the corpus currently using
  a sequence-valued frontmatter field, and on no parity fixture exercising one. Both were
  verified across all three repositories at the time of writing; R1 is the change that
  makes such a fixture possible, so the parity baseline needs re-checking as part of
  satisfying R23 rather than assumed.
- R15 makes a duplicate upstream a visible choice rather than an impossible one. An author
  who ignores the notice still gets the duplicate.
