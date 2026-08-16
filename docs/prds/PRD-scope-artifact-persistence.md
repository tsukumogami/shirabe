---
schema: prd/v1
status: Done
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

Done

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

### Terms

A **contribution** is what an artifact type adds to the chain, declared once per
type. A **contribution section** is the section in a surviving document that
carries an absorbed ancestor's contribution. R3 declares the first; R4 through
R9 govern the second.

### The judgment

**R1.** The absorbability decision SHALL be made against the two documents
present at the hop, not against their types. No hop SHALL be unabsorbable purely
because of the types involved.

**R2.** The judgment SHALL fire only at a hop where this run produced both
documents. An artifact held back by re-entry protection SHALL NOT be judged.

**R3.** Each artifact type SHALL declare exactly one contribution it makes to
the chain.

**R4.** A document that absorbs an ancestor SHALL carry that ancestor's
contribution as a single section, placed after its `## Status` section and
before its own first other required section.

**R5.** Each type's contribution section SHALL have a fixed heading derived from
the absorbed type, so the section is machine-recognisable without reading its
body.

**R6.** Contributions SHALL accumulate transitively: a document that absorbs an
ancestor which had itself absorbed another owes both. Where a document carries
more than one contribution section, they SHALL appear in chain order.

**R7.** The contribution section's format contract SHALL state a two-sided
adequacy criterion: a section that reads as a rewrite of the absorbed document
is too long, and a section without which the survivor's own argument does not
stand is too thin. Presence alone SHALL NOT satisfy it.

**R8.** A document SHALL declare its absorptions in frontmatter. `shirabe
validate` SHALL require the contribution sections those declarations imply, and
SHALL leave documents declaring no absorption unaffected.

**R9.** The existing canonical-section-order check SHALL enforce the placement
R4 and R6 require.

**R10.** Each format reference's citation-not-duplication rule SHALL carve out
the absorbed case, so a contribution section carried under R4 does not violate
the content-boundary contract of the document carrying it.

**R11.** The DESIGN-to-PLAN hop SHALL be absorbable when the judgment finds the
DESIGN holds nothing beyond its contribution that compression would lose.

**R12.** The fold verdict SHALL be the judging agent's call at every hop,
including the terminal one. No independent reviewer, human confirmation, or
mode-conditional gate SHALL be added to it.

### The absorb procedure

**R13.** The carry check SHALL be evaluated against contribution text that
already exists, never against a prediction that it will be written.

**R14.** The carry check SHALL itemize the ancestor's required sections as it
does today, and SHALL additionally itemize each contribution the ancestor
carries — its own and any it inherited. A contribution or section that does not
carry SHALL abort the absorb, downgrade the verdict to `keep`, and delete
nothing.

**R15.** Before deleting an artifact, the procedure SHALL search the repository's
git-tracked files for citations of it, excluding `wip/`, excluding the survivor
of this fold, and excluding any bookkeeping surface the procedure itself writes.
A citation containing the artifact's repo-relative path
SHALL downgrade the verdict to `keep` through the existing abort path. A
citation naming the artifact without its path SHALL be surfaced to the judging
agent as a finding and SHALL NOT by itself change the verdict. The check SHALL
have no override and SHALL NOT be capable of any outcome stronger than `keep`.
It is justified entirely by the hops this work opens forward; it carries no
retroactive commitment and produces no verdict about any document already on
disk.

The bookkeeping exclusion covers the same failure one step removed: a record of
an earlier fold names a still-live survivor by path, so without the exclusion the
first fold in a chain refuses the second. Re-pointing those earlier records
instead is barred by this requirement's own ordering — the search runs before any
mutation.

The survivor exclusion is a precondition of the mechanism working at all, not a
convenience. The survivor always cites the absorbed artifact by repo-relative
path in its own `upstream:` — and that is behaviour the consolidation change
deliberately shipped, having named the old non-citing behaviour as the defect it
was fixing. Without the exclusion the guard refuses every fold, including the one
hop absorbable today. Excluding only the `upstream:` line is insufficient,
because most survivors cite the path more than once. The exclusion is a named,
static, design-time rule rather than an override: it narrows what is searched,
never what the search is allowed to conclude.

A record of an earlier fold naming a still-live document SHALL NOT cause a later
hop in the same chain to refuse. The exclusion above is how, and it is the only
route this requirement leaves open. Re-pointing earlier records before the scan
is barred by the ordering — the search runs before any mutation — and it would
also assert something that never happened: the operation at the first hop was
BRIEF-into-PRD, and rewriting that row to read BRIEF-into-DESIGN collapses the
hop-by-hop sequence the record exists to preserve. Naming the survivor by a bare
name instead of a path is rejected too: it trades the record's most useful field
for a finding that would fire on every cascading fold and be dismissed every
time.

**R16.** `shirabe validate` SHALL fail when an `R<n>` requirement citation whose
target document this run absorbed resolves neither within the surviving document
nor within its spliced upstream. The check is tied to the absorb event because
that is what it guards: an absorb that drops requirement numbering orphans every
citation below it, silently, and fold time is the only point at which that is
catchable.

A broader rule — every `R<n>` citation in every document resolves — is worth
having and is named as follow-on work below. It is not this work because it
audits the corpus rather than guarding this operation. Roughly 77 documents
carry dangling requirement citations today; that is a defect of the process this
work fixes, and the cleanup belongs on its own terms rather than as a condition
on shipping.

**R17.** Re-pointing a survivor's `upstream:` SHALL splice the absorbed
artifact's parents into the survivor's existing list rather than replacing it,
preserving sibling parents and cross-repo entries verbatim.

**R18.** Post-absorb re-validation SHALL cover the survivor. A failure SHALL
revert the absorb in full: the absorbed document restored, the survivor's
`upstream:` splice undone, its absorption declaration and `## Status` line
removed, and its contribution section removed. The revert SHALL be recorded.

Narrowed from "the survivor and every document that referenced the absorbed
artifact": that second set is empty by construction once R15 has run, because
every path citer was already refused and `upstream:` referrers are themselves
path citations. The residue is bare-name referrers, on which the validator has
no check at all — the population this work explicitly fences out. What R18
covers that R15 does not is the survivor, which receives four new writes that
can each fail validation, and the revert semantics: R15 aborts before any
mutation, R18 reverts after several plus a deletion.

**R19.** `/scope`'s closed write-target set SHALL name every path an absorb at
any hop writes or deletes.

**R19a.** The absorb SHALL stage and commit its own output. Today `/scope` has
no `git add` anywhere and its only `git commit` is on the decision-record path,
so a completed absorb leaves a staged deletion, an unstaged working-tree edit for
the `upstream:` re-point, and nothing that commits either. R20's record cannot
reach the default branch until this is settled, and neither can the fold itself.

**R20.** A fold SHALL NOT land unless a record was written to the default branch
naming what folded into what, on what verdict, with the per-contribution carry
result and a content hash of the pre-fold original. The record SHALL be produced
mechanically and SHALL NOT carry the absorbed document's contributions.

"Written to the default branch" means the record **remains** on the default
branch — present in a checkout, greppable — not merely that it was written to
some commit later removed. The terminal fold decides this: a record carried in
the PLAN reaches `main` and is then deleted by the implementation cascade, so
under the weaker reading the one fold that leaves nothing else behind also
leaves no record of itself. That is the case the record exists for. It also
follows from the beneficiary R21 names: a reader holding a dead path who greps
for it needs the record in the working tree, not in history they have no reason
to search.

**R21.** A surviving document SHALL record what it absorbed in both a
machine-readable frontmatter field and one line in its `## Status` section
naming the absorbed artifact and which contribution section now carries it. The
`## Status` line SHALL follow a pinned shape rather than free prose. The
frontmatter field SHALL be excluded from path resolution, since its target is
deleted by construction.

### Downstream skills

**R22.** `/execute` SHALL NOT assume any surviving durable artifact. Its
finalization guard and the cascade's roadmap downstream-reference rewrite SHALL
both behave correctly for a chain that folded every artifact away. The PRD-level
contract for what `exit_artifacts:` holds under a fully folded chain SHALL be
stated so the guard has a defined seed.

**R23.** `/work-on`'s implementation phase SHALL carry a standing instruction to
record in code comments why the code is shaped as it is, kept current as the
code changes, unconditional and independent of what the chain decided. The
instruction SHALL be enforced by naming it in the maintainer reviewer's existing
blocking brief rather than by a new gate.

### Verification surface

**R24.** `/scope`'s eval suite SHALL be updated so that no scenario references a
type-level mapping check, and SHALL gain coverage of a hop above BRIEF-to-PRD
reaching `absorb` and the same hop reaching `keep`. The consolidation family's
scenario count SHALL NOT decrease.

**R25.** The state-file schema SHALL stop documenting absorbability as a
question about the required-section mapping. Its `consolidation_judgments` entry
currently annotates `absorbable:` as "is the required-section mapping total?",
which is the model R1 deletes sitting in the machine-readable contract that the
carry-check criteria parse. A fixture built against the current schema would
encode the deleted model.

**R26.** `docs/guides/doc-validation.md` SHALL document any check family this
work adds.

### Non-functional

**R27.** The consolidation judgment SHALL remain the only mechanism that reduces
the artifact set. Nothing added here SHALL constitute a second reduction
mechanism; a mechanism whose only possible effect is to force `keep` does not
count.

**R28.** No judgment SHALL run before the artifact it is about exists. Nothing
here SHALL reintroduce a pre-artifact worth decision in any form, including an
author-chosen entry altitude.

**R29.** The checks this work adds SHALL emit nothing on a document that declares
no absorption, so a document untouched by an absorb is unaffected by this change
— including against the frozen cross-repo parity baseline, so downstream callers
pinning a shirabe tag do not break.

This is a scoping requirement, not a promise that the corpus is clean. Where a
document already on disk carries a defect this work's checks happen to surface,
the finding stands and the document is fixed on its own terms as named follow-on
work. Pre-existing breakage SHALL NOT be a reason to narrow a check that is
otherwise correct.

**R30.** The absorb procedure SHALL fail toward `keep` at every decision point
this work adds: the citation preflight, the carry check, post-absorb
re-validation, and record production.

Four, not five. An earlier draft listed "the replaced first stage" and "the
citation check" separately; the design established that they are the same
decision point, because what occupies the first stage after the type test is
deleted is the citation check itself.

## Acceptance Criteria

Each criterion names its verification instrument.

- **[mech]** — a machine decides it: a Rust test, a golden fixture, a shell
  harness scenario, or a CI job.
- **[judg]** — an agent decides it, via a skill eval. For `/scope` evals that
  means LLM-graded, plan-graded (the eval grades the agent's stated plan, not an
  executed run), and run on a weekly cron rather than as a merge gate. The one
  `/execute` eval here is stronger: `/execute` has the isolated-clone mechanism,
  so that criterion can be graded against an executed run.
- **[insp]** — settled by a human or agent reading a file, because the thing
  being checked is prose with no machine-readable enumeration to diff against.

See Known Limitations for what the [judg] instrument does and does not buy.

### The judgment

- [ ] **[judg]** A paired `/scope` eval entered at the DESIGN-to-PLAN hop
      returns `absorb` against a sequencing-only DESIGN fixture and `keep`
      against a live-alternatives DESIGN fixture. The two fixtures are
      constructed to differ only in whether a recorded alternative remains live:
      the folding fixture's every Decision is sequencing or ordering with its
      rationale recoverable from the PLAN, and the keeping fixture carries at
      least one rejected alternative whose reason the PLAN's issue order does not
      imply.
- [ ] **[mech]** The two fixtures behind that pair are committed, sit within 10%
      of each other on line count, and share section set, Decision count,
      `status`, `upstream` and topic slug.
- [ ] **[judg]** On the `absorb` verdict, the plan states the DESIGN is removed
      and the PLAN carries a contribution section for it.
- [ ] **[judg]** An artifact held back by re-entry protection is not judged.
- [ ] **[mech]** The citation preflight fails toward `keep`: when its search
      cannot complete — the git-tracked file set is unreadable, or the deletion
      target's path cannot be composed — both documents stay on disk.
- [ ] **[judg]** Scenario 17 `chain-shape-is-constant` still passes — an author
      declaring the framing settled is not offered a shorter chain. This is the
      tripwire for R28: implementing R1 is exactly what makes an entry-altitude
      flag look reasonable to a later maintainer.

### Contribution sections

- [ ] **[insp]** Each of the BRIEF, PRD, DESIGN and PLAN format references names
      exactly one contribution for its type.
- [ ] **[mech]** Each type's contribution section heading is a fixed string
      derived from the absorbed type, named in the format reference, so the
      validator recognises it without reading the section body.
- [ ] **[mech]** A survivor that absorbed one ancestor carries one contribution
      section, immediately after `## Status`.
- [ ] **[mech]** A survivor that absorbed an ancestor which had itself absorbed
      another carries two contribution sections, in chain order.
- [ ] **[mech]** `shirabe validate` fails a document whose frontmatter declares
      an absorption and which lacks the implied contribution section.
- [ ] **[mech]** `shirabe validate` fails a document whose contribution sections
      are present but out of order.
- [ ] **[insp]** The contribution-section contract in each of the BRIEF, PRD,
      DESIGN and PLAN format references states both the too-long and the
      too-thin failure.
- [ ] **[mech]** The content-boundary rule in each of the PRD, DESIGN and PLAN
      format references names the absorbed case as an exception. (BRIEF is
      excluded: nothing absorbs into a BRIEF, so it has no absorbed case.)

### The absorb procedure

- [ ] **[judg]** An absorb whose contribution does not carry leaves both
      documents on disk and records the failure.
- [ ] **[mech]** An absorb of an artifact cited by repo-relative path from any
      tracked file outside `wip/`, other than the survivor, is refused and the
      citing file is named. Exercised by the guard's own test harness under a
      merge gate.
- [ ] **[mech]** A fold whose only path citation is the survivor's own
      `upstream:` is NOT refused. This is the canonical BRIEF-to-PRD case;
      without the survivor exclusion every fold refuses, so this criterion is
      the tripwire for the whole mechanism.
- [ ] **[mech]** A chain that folds at two hops in sequence is not refused at
      its second hop by a record written at its first.
- [ ] **[judg]** A citation naming an artifact without its path is surfaced as a
      finding and does not by itself change the verdict.
- [ ] **[mech]** A DESIGN citing `R7` whose PRD was absorbed without carrying
      the requirement numbering fails `shirabe validate`.
- [ ] **[mech]** A survivor whose absorbed ancestor had two parents carries both
      in its `upstream:` field after the re-point.
- [ ] **[judg]** An absorb whose post-absorb re-validation fails restores the
      absorbed document, undoes the `upstream:` splice, removes the absorption
      declaration, the `## Status` line and the contribution section, and
      records the revert.
- [ ] **[insp]** Every path the absorb procedure writes or deletes appears in
      `/scope`'s enumerated write-target set, and every deletion in that set is
      reached only through the consolidation judgment's abort-or-absorb path.
      The set is prose with no machine-readable enumeration to diff, so this is
      a reading rather than a test — the second clause is what would catch a
      second deletion site appearing in the procedure, which is R27's real risk.
- [ ] **[insp]** The absorb procedure's authoring step precedes its carry-table
      step, so the carry check cannot run against a prediction.
- [ ] **[mech]** After a completed absorb the working tree is clean: the
      deletion, the `upstream:` re-point, the survivor's edits and the fold
      record are all committed, with nothing left staged or unstaged.
- [ ] **[mech]** A chain whose first hop folds is not refused at its second hop
      by the record its first hop wrote.
- [ ] **[mech]** An absorb of an ancestor already carrying two contributions
      itemizes all three carries — the ancestor's own and both inherited — and
      aborts if any one fails.
- [ ] **[mech]** A completed fold leaves a record identifying the absorbed
      document, the survivor, the verdict, and a content hash matching the
      pre-fold document's bytes. Evaluated on the branch, before merge.
- [ ] **[judg]** A fold whose record cannot be written does not land.
- [ ] **[mech]** A survivor's absorption declaration is present and holds the
      absorbed path.
- [ ] **[mech]** A survivor's `## Status` absorption line matches its pinned
      shape.
- [ ] **[mech]** `shirabe validate` reports no finding against a survivor's
      absorption declaration, whose target no longer exists.

### Downstream skills

- [ ] **[mech]** `run-cascade_test.sh` gains a scenario building a PLAN-to-
      ROADMAP chain with no DESIGN, asserting the roadmap's `**Downstream:**`
      line carries no dangling reference. (This fails against current code:
      `run-cascade.sh` leaves the pre-existing line untouched when
      `CASCADE_DESIGN_PATH` is unset.)
- [ ] **[judg]** A finalized chain with no surviving durable artifact passes
      `/execute`'s finalization guard, seeded per R22's stated contract.
- [ ] **[insp]** `/work-on`'s implementation phase file carries the rationale
      instruction, and the maintainer reviewer's brief names it as a blocking
      finding.

### Verification surface

- [ ] **[mech]** Scenarios 18, 19 and 20 in `skills/scope/evals/evals.json` are
      rewritten so that none references a type-level mapping check, and the
      consolidation family's scenario count does not decrease.
- [ ] **[mech]** `docs/guides/doc-validation.md` names every check family this
      work adds.

### Regression

- [ ] **[mech]** A corpus-wide test walks every document under `docs/`, runs
      `shirabe validate`, and asserts that none of the check codes this work
      adds fires on a document that declares no absorption. It does not assert
      exit 0: pre-existing findings from other checks are the corpus cleanup's
      business, not this change's gate.
- [ ] **[mech]** `git diff --exit-code docs/` is clean in the same job, proving
      no existing document was edited to make the corpus pass.
- [ ] **[mech]** `cargo test --workspace` passes, including the byte-exact
      golden parity tests across all corpus files and the absorption rule-set
      parity suite.

## Out of Scope

- **Retroactive application to documents already on disk.** The judgment runs
  against two bodies that exist at the moment a child lands. For most DESIGNs in
  the corpus the downstream PLAN was deleted at finalization by design, so there
  is one body and no landing event; `keep` there is the absence of a runnable
  judgment rather than a verdict. Two follow-ons are named rather than left
  implicit. First, a BRIEF-to-PRD retroactive fold — the one coherent
  retroactive operation, with a measured population of roughly 55 candidates
  after exclusions, gated on this work's guard and repairs landing and being
  exercised forward at least once. Second, a lifecycle criterion for settled
  documents, with archive rather than deletion as its disposal.
- **Corpus cleanup of dangling requirement citations.** Roughly 77 documents
  cite an `R<n>` that resolves nowhere, which is a defect of the process this
  work fixes rather than a constraint on it. Cleaning them up, and then widening
  R16 from the absorb event to every citation in every document, is named
  follow-on work. It is sequenced after this change rather than blocking it:
  fixing the process comes first, and the documents the old process produced are
  repaired on their own terms.
- **The strategic chain under `/charter`.** No consolidation judgment exists
  there to change, and the judgment's logic lives entirely inside `/scope`'s own
  phase files, so extending it is new machinery rather than a follow-on edit.
- **Manual invocation of child skills outside `/scope`**, the only route to a
  chain with a genuinely missing ancestor.
- **A repository-wide citation index, and a notice-severity rule for
  unresolvable document names.** Both are repair campaigns against references
  already broken — roughly 374 pre-existing unresolvable names — not guards on
  the operation this work adds. R16 is narrower and distinct: it fires on
  requirement numbers orphaned by this work's own absorbs.
- **The CI deletion blindness.** `validate-docs.yml` computes its file set with
  `git diff` and cannot see a document stranded by a deletion. Widening the diff
  filter is not a fix, because it feeds deleted paths to a validator that cannot
  open them. R15's guard makes fold time the catchable point instead.
- **Bringing the isolated-clone eval mechanism to `/scope`.** It exists and
  `/execute` uses it. It would let the fold/keep pair grade an executed fold
  rather than a described one, which is the honest upgrade for Known Limitation 2
  — and it is its own change.

## Decisions and Trade-offs

Each ran through the `/decision` framework during exploration. Two are marked
**[critical]**: they ran the full adversarial path with persistent validators
through bakeoff, peer revision and cross-examination. These are inputs to the
DESIGN, not questions for it.

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
the incentive and padding satisfies it free. The same decision adopted R16's
citation-resolution rule as the one mechanical backstop available anywhere in
this problem — it is the only depth expectation here a machine can check.

**[critical] The verdict gets no gate; the operation gets the backstop.** Both
rival advocates withdrew their own alternatives. Human confirmation is
self-refuting against the decision that agents make this call, and fails
differently in all three of its sub-variants. An independent reviewer is
structurally unavailable: `/scope` owns no team at its own layer, has no
sub-agent spawn site in any of its seven phase files, and no row in the dispatch
binding table. The reviewer's one real contribution — judging an artifact rather
than a prediction — is bought for free by R13, which requires the carry check to
run against text that exists.

**[critical] The corpus stays out of scope, and the boundary carries its
reason.** A sweep would invent a discard verdict the mechanism refuses, against
201 surviving files holding broken references behind CI that structurally cannot
see deletions. The advocate assigned to argue for the sweep voted against it
after reading the trigger condition. The redundancy argument that motivated the
question did not survive measurement either: among DESIGNs actually in a PRD
chain the ratio is 1.03, not the 3.5 the raw count suggests.

**A durable record of the operation, not of the distillate.** Any destination
preserving the absorbed content must assert, every time it fires, that the
verdict was partly wrong, since the fold's meaning is that the content did not
warrant a durable artifact. That argument closes the whole class, including an
archive directory and a per-run decision record. A record that a judgment
happened, about what, with what carried, asserts nothing the fold denies. It is
written mechanically because an agent-authored record inserts another
unverifiable content judgment at the moment of maximum consequence.

**A survivor records what it absorbed in frontmatter plus one `## Status` line.**
This is house pattern rather than invention: `shirabe transition` already writes
a `superseded_by:` key and splices a line into `## Status` for supersession, the
nearest existing analogue — and R21 adopts its format discipline, not just its
shape. The beneficiary is the reader of a third document citing the dead path,
who is not holding the survivor and does not know it exists. A tombstone stub was
stronger on the merits and was rejected because it leaves one durable file per
fold in the corpus that motivated this work.

**Everything ships in one change with no ordering constraint.** The repo's own
plan rule makes one PR the default and permits a split only on a named hard
constraint, and this work has none. The rationale-in-code instruction is bounded
to instruction text in files that already exist, with no new gate, so it cannot
expand into an open-ended quality effort and become a de facto blocker. That work
belongs to `/work-on` rather than `/execute`: R14/R15 of the execute contract bar
`/execute` from reading diffs, so the only agent in the chain holding the diff is
`/work-on`'s implementation phase.

## Known Limitations

**Static validation buys presence, not fidelity.** An empty or gutted
contribution section satisfies R8. R7's adequacy test is prose an agent applies,
as every content criterion in this repository is. The residual gaming vector is
omission: an agent that writes one fluent paragraph and silently drops the one
contested thing the ancestor settled is not caught, because the folding agent
cannot see the absence it created.

**The feature's central behaviour is graded, not gated.** The fold-versus-keep
discrimination is verified by a `/scope` eval, which is LLM-graded, grades the
agent's stated plan rather than an executed fold, and runs on a weekly cron
rather than on pull requests. Every criterion marked **[judg]** inherits that.
This is weaker than it reads, and the honest upgrade — the isolated-clone eval
mechanism that already exists for `/execute`, which grades an executed run — is
deliberately out of scope here.

**The worth judgment is ungradeable in principle.** A fixture eval can grade
whether content was lost, because the fixture retains both bodies. It cannot
grade whether reasoning deserved to persist, and after the fold the comparison
object is gone. A green eval is not a check on the whole judgment.

**Forward absorption has no recovery path from a clone.** Squash-merge with
branch deletion means an absorbed document never existed on the default branch.
`refs/pull/<N>/head` retains the content, but that is best-effort platform
behaviour rather than a git guarantee — which is why R20's record carries a
content hash rather than a path, and why its criterion is evaluated on the
branch rather than after merge.

**R15's guard is same-repo only.** Cross-repo citations exist and stay
unguarded. Issue bodies, PR descriptions and commit messages are outside its
reach entirely, so its coverage is a floor rather than a bound.

**R29's cross-repo half is unverified.** The in-repo corpus walk and the
byte-exact golden parity suite cover this repository. The frozen cross-repo
baseline lives in `parity-check.yml`, which shirabe does not self-call, so
nothing in the criteria set exercises it. The in-repo walk stands as a proxy:
if the added checks emit nothing on non-absorbing documents here, they emit
nothing downstream for the same reason. That is an argument, not a test.

**The rationale-in-code instruction is unmeasurable.** No check distinguishes a
run that wrote useful why-comments from one that did not. R23 accepts an
instruction plus an existing blocking reviewer as the honest ceiling for a
qualitative property; its criterion checks that the instruction landed, not that
it worked.

**This chain cannot dogfood the change.** The run producing this PRD uses the
current `/scope`, so it will leave a permanent PRD and DESIGN regardless of what
the new judgment would have decided about them.

## Open Questions

- What surface carries R20's record? A single shared append-only index is the
  leading candidate because it is not a per-run artifact and so cannot read as a
  floor, but a survivor's frontmatter serves the one hop that has a survivor, and
  there are three deletion sites rather than one. The criteria for R20, and the
  surface named in the failure findings of R14 and R15, all inherit this answer.
- Is the contribution section authored by the child at drafting time or by the
  parent at fold time? R13 fixes the property the carry check needs without
  naming the actor. The answer decides whether R7's criterion rides an existing
  jury and whether each child needs a consumption block of its own, which changes
  the PLAN's decomposition materially.
- Do the two contradicted claims in the shipped consolidation chain get amended?
  `DESIGN-scope-consolidation-over-skipping.md`'s Decision 9 justifies leaving
  `/charter` alone on reasoning R1 falsifies, and that PRD's R14 requires the
  floor R1 removes. Both sit durably on `main`, reachable from this chain's own
  references.

## References

- `docs/briefs/BRIEF-scope-artifact-persistence.md` — the framing these
  requirements are written from.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` — Decision 8
  rejected DESIGN-to-PLAN absorption; R11 reverses it. Decision 9's rationale is
  the subject of an open question above.
- `docs/prds/PRD-scope-consolidation-over-skipping.md` — its R14 requires the
  floor R1 removes.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — the three
  stages and the mapping table.

## Amendment — 2026-08-16

`PRD-fold-record-removal.md` removes `docs/folds.md`. The original text above is left unedited; this section records what no longer holds.

**R20 is withdrawn.** No fold writes a record to the default branch. The
requirement's gloss argued that a record carried in the PLAN would be deleted by
the implementation cascade, so the one fold leaving nothing else behind would
leave no record of itself. That reasoning is sound and the case is real; it is
now an accepted residual rather than a requirement, because the shared file that
discharged it cost more than the case is worth. The reasoning is recorded in
`DESIGN-fold-record-removal.md`.

**R21 is unaffected and now carries the guarantee alone.** The survivor's
`absorbed:` declaration and `## Status` absorption line remain error-level
enforced, and they accumulate across hops, so a reader holding a dead path is
served by the surviving document at every hop that leaves one.

**R15's bookkeeping-surface clause is vacuous rather than unmet.** The citation
preflight no longer excludes a record, because there is none to exclude.
