# Decision Context: Retroactive scope of the corpus

## Question

Is the existing corpus of documents already on disk (366 DESIGNs, 107 PRDs, 64
BRIEFs across six repos) in scope for the same content-decided consolidation
judgment retroactively -- should this work include a sweep that applies the new
verdict to those documents and deletes the ones that do not earn their place?

## Complexity

critical (Tier 4, full path: phases 0, 1, 2, 3, 4, 5, 6)

## Constraints

- Whatever is decided must not strand references or add to the existing
  broken-reference class. Five documents already carry dangling `upstream:`
  refs today; `shirabe validate` exits 2 on them right now.
- Scope discipline: this work already includes the judgment fix, four
  absorb-procedure repairs, format-contract changes, and two `/execute`
  changes.
- The author values autonomy and dislikes ceremony, but this is irreversible
  mass mutation across six repositories, two of them private.
- The result must replace the consolidation judgment rather than sit beside it
  (the single-mechanism constraint that killed the entry altitude).
- Must not reintroduce a judgment that runs before the artifact it is about
  exists (#260's core principle). Note this cuts oddly here: retroactive
  judgment runs long *after* the artifact exists, which is the opposite
  failure -- judging without the run context that produced it.

## Known Options

- (a) **Out of scope, forward-only.** The corpus stays as it is. The new
  judgment applies only to runs from here on.
- (b) **Out of scope now, ship a read-only report.** No deletions in this work,
  but produce a candidate-identification pass so the decision can be made later
  with data.
- (c) **In scope, sweep everything.** Apply the judgment to all 537 documents
  and delete the ones that fail, as PRs against each of the six repos.
- (d) **In scope but bounded.** One repo as a pilot, or only documents whose
  whole chain is already terminal (all downstream work merged/closed).
- (e) **Opportunistic.** A document is judged only when work next touches its
  topic; no sweep, but the corpus converges over time.

## Background

`/scope` drives BRIEF -> PRD -> DESIGN -> PLAN with a consolidation judgment per
hop deciding whether the upstream folds into the downstream and is deleted.
Issue #280 reports the judgment can never return `absorb` above BRIEF->PRD,
because Stage 1 compares type schemas rather than document content. The fix
makes the verdict content-decided per run.

The author's justification for allowing documents to fold away rests on a claim
about the existing corpus: that the workspace's documents accumulated because
the workflow never asked whether they should be deleted, not because each was
judged worth keeping. Measured: 366 DESIGN docs, 107 PRDs, 64 BRIEFs (tsuku 147
DESIGNs, shirabe 62, niwa 56, private/tools 47, koto 40, private/vision 14).
Roughly three and a half DESIGNs per PRD.

The author's own argument cuts toward yes: if those 366 DESIGNs were kept only
because nothing ever asked, the same reasoning applies to them. The
exploration's scope file currently says retrofitting artifacts already on disk
is OUT of scope, but that line was inherited from an earlier framing and
predates this argument.

Evidence established by the exploration that bears on this decision:

- **Length does not identify the unwarranted ones.** Smallest DESIGN in tsuku is
  132 lines, in shirabe 227; distributions substantial throughout. There is no
  thin-document population to target. A retroactive sweep would require reading
  and judging each document on content.
- **Deleting documents strands references, and this is live.** Five documents in
  the repo already carry dangling `upstream:` refs (three stranded by a mere
  directory move, two by PLAN deletion). `shirabe validate` exits 2 on them now,
  and diff-scoped CI does not notice until an unrelated PR touches a victim.
- **The largest reference surface is unvalidated.** 73 files cite a PRD path in
  prose and nothing validates those citations. DESIGNs and PLANs cite
  requirements as bare `R<n>` numbers and there is NO rule anywhere in
  `crates/shirabe-validate/src/` validating a requirement citation -- confirmed
  directly. Mass deletion would orphan an unknown number of these silently.
- **The retirement guard exists, unwired.** `lifecycle::build_referrer_map` is a
  public API written for the finalization walk in #271, not called from the
  consolidation path.
- **Six repositories, two private.** Deletions land as PRs against each.
- **The absorb procedure has never executed once in this repo.** The forward
  mechanism is entirely untested; a retroactive sweep would be its first
  production use, at 537-document scale, with no worked example anywhere in
  history.
- **Historical documents are the record of decisions already taken and
  shipped.** Several are cited from skill prose (e.g. `skills/plan/SKILL.md`
  cites decision records).

The forward judgment is a fold: the upstream's contribution is distilled into
the surviving downstream. Retroactively, the downstream often does not exist
(the PLAN was deleted at finalization, or the work merged years ago), so there
is frequently nothing to fold *into* -- which makes a retroactive sweep closer
to a discard verdict than to the fold the forward mechanism performs. That
asymmetry is the central thing to test.
