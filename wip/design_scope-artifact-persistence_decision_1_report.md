<!-- decision:start id="fold-record-surface" status="assumed" -->
### Decision: What surface carries R20's durable fold record

**Context**

R20 requires that a fold not land unless a record was written to the default
branch naming what folded into what, on what verdict, with the per-contribution
carry result and a content hash of the pre-fold original — produced mechanically,
carrying none of the absorbed document's contributions. The exploration settled
that the record is of the *operation* and never of the distillate, closing the
whole class of destinations that preserve absorbed content, and left the surface
to this decision.

The question is harder than one hop. Three deletion sites were in play: the
BRIEF-to-PRD fold, where a durable survivor exists and could carry the record in
its own frontmatter; the terminal fold into the PLAN, where no survivor exists
and the PLAN is itself deleted later; and `/execute`'s cascade deletion of the
PLAN, which happens in a different skill, on every run, fold or no fold.

Two facts about how this repository merges shape everything. `origin/main`
carries 165 commits and **zero merge commits** — every PR squash-merges — and a
`/scope` run's chain can land in one squash commit, verified directly: `42d5185`
added a BRIEF, PRD, DESIGN and PLAN together in a single commit. Nothing in
`skills/scope/` or `skills/brief/` merges anything; merge is a human act after
the chain ends. So every fold in a run happens on one branch before one merge,
and only the final tree state of that branch reaches the default branch — which
means any record living inside a chain document that a later hop deletes never
arrives.

**Assumptions**

- **R20's "written to the default branch" means the record persists there.**
  Ruled by the author and now explicit in R20's body. The PRD's Goals sentence
  was already stative — "the default branch **keeps** a record that the fold
  happened and what it claimed to carry" — and sits third in a list whose two
  companions describe the corpus after the operation rather than events during
  it. *If wrong* — if a record written to a commit later removed satisfies the
  requirement — the cheaper frontmatter answers become viable and this decision
  should be re-run.
- **Site 3 is outside R20.** `/execute`'s cascade PLAN deletion is not a fold: it
  fires unconditionally, no document absorbs the PLAN, and three of R20's four
  required fields have no value there. Five of five validators concurred. *If
  wrong*, the surface is unchanged but an `/execute` R9 amendment
  (`skills/execute/SKILL.md:634-640`), a `run-cascade.sh` edit and a
  `STAGED_FILES` add are added to the cost.
- **Fold frequency stays low enough that `merge=union` is adequate.** *If wrong*
  and folds become routine across concurrent branches, the residual duplicate-row
  case below grows from cosmetic to worth a sorted-insertion producer.
- **The terminal DESIGN-to-PLAN fold will actually occur once R11 ships.** It has
  fired zero times because the hop is not absorbable today. *If wrong* and folds
  stay confined to BRIEF-to-PRD, the index still holds every record but the site
  that justified building it never exercises.

**Chosen: a single shared append-only index at a fixed path, covering the fold
sites only**

One file, `docs/folds.md`, created on first append, one row per completed fold,
written mechanically by `/scope` Phase 2 at every hop that folds. Site 3 is
declared out of R20 with its reason recorded, and `/execute` needs no change at
all. R21's frontmatter declaration and `## Status` line stay exactly where D3 put
them — they are navigation for a reader holding the survivor, a different
requirement with a different beneficiary, and nothing here touches them. One
producer per requirement, with independent `[mech]` criteria.

The row carries a date, the absorbed artifact's repo-relative path, the
survivor's repo-relative path (or `none` at the terminal fold), the verdict, a
mechanical serialization of the state file's existing `carry_check:` mapping —
section names and outcomes, never section text — and the `git hash-object` blob
SHA of the pre-fold original. Both path columns carry full paths: they are what
a reader greps and what the checker resolves. The hash is recomputed at fold time
rather than promoted from `child_snapshots.content_hash`, because that value is
captured post-invocation and the drift machinery at `phase-resume.md:141-150`
exists precisely because it can differ from the live bytes, while R20 requires the
hash of what was actually deleted.

Seven mechanics the DESIGN must pin.

1. **The record is on disk and staged before anything is deleted**, so R30's
   fail-toward-`keep` is structural rather than procedural. A failed append
   aborts to `keep` and deletes nothing.
2. **`git add docs/folds.md` beside the existing `git rm`.** `/scope` never
   commits — the absorb is a bare `git rm` at `phase-2:493` and the `upstream:`
   re-point at `phase-2:487-492` is an unstaged working-tree edit — and `git
   commit -a` does not stage an untracked file, so the file's very first write is
   the one most likely to be dropped. Without this the deletion lands and the
   record does not. Four of five validators reached it independently. The larger
   gap behind it is that **who commits `/scope`'s output is unspecified today**,
   and that owes an answer regardless of this decision.
3. **`docs/folds.md` joins R15's exclusion clause**, beside `wip/` and the
   survivor. This is the mechanism R15's new paragraph requires the design to
   name. Without it the record refuses the *next* hop's fold: the row names a
   still-live survivor by path, and R15 scans git-tracked files outside `wip/`
   for the path of the artifact about to be deleted. It also disposes of an
   ordering hazard — R15's scan runs before the `git rm` too, so an unexcluded
   index appended before the scan would name the *current* deletion candidate and
   refuse at hop one. With the exclusion, the relative order of scan and append
   stops mattering, though writing the record before the deletion is still forced
   by R30.
4. **No re-pointing of prior rows.** The alternative fix — re-pointing a prior
   row's survivor field to the new survivor before the scan — is rejected twice
   over. It is barred procedurally, since the PRD draws its R15/R18 distinction on
   "R15 aborts before any mutation" and a pre-scan re-point converts that abort
   into a rollback. And it is wrong on the settled ground that the record is of
   the *operation*: the operation at hop 1 was BRIEF-into-PRD, and a dated row
   saying so is permanently true, while re-pointing it to say BRIEF-into-DESIGN
   records an operation that never happened. It buys navigational tidiness by
   falsifying the log, and it collapses three rows onto the last survivor,
   destroying the hop-by-hop reconstruction that is the record's point. The
   truthful row sequence is already transitively navigable by reading.
5. **On an R18 revert the row is removed.** Because R30 forces the row to exist
   before the `git rm`, a revert must un-append a row it already wrote, and that
   un-append has to be specified explicitly — left unstated it strands a durable
   row on `main` asserting a fold that was undone, which is the exact failure R20
   exists to prevent. The un-append is cheap: the row is uncommitted and
   intra-branch, so it never reaches a merge and never interacts with
   `merge=union`.
6. **The checker is deletion-driven, gated on a fold signature, and lives in
   `validate-docs.yml`.** It drives off `git diff --diff-filter=D` and demands a
   row for each deleted document, because a row-driven check starts from the
   record and cannot see a fold that landed with no record at all. It must not
   demand a row for a *legitimate non-fold deletion* — `d432f13` is a real merged
   commit removing superseded roadmaps with no fold involved, and a naive check
   would fail ordinary documentation housekeeping in every adopter repo. The
   discriminator is mandated by R29 rather than invented: demand a row only when
   the diff carries a fold signature, a chain-document deletion together with an
   absorption declaration added in the same diff naming that path. That couples
   R20's check *trigger* to R21's declaration — trigger only, not surface, and
   R21 ships regardless, but it is a real dependency the DESIGN must state.
   `validate-docs.yml` already sets `fetch-depth: 0`, so `git rev-parse
   BASE:<path>` recovers the pre-fold blob without the file; `check-sentinel.yml`
   and `pr-body.yml` are both depth 1 and cannot. The decisive reason for that
   host is that it is the *reusable* workflow adopters pin, and folds happen in
   adopter repos — a shirabe-local check would leave every adopter's destructive
   operation unverified, which is R29's stated concern. `check-plan-docs.yml`
   supplies a 26-line skeleton of exactly this shape.
7. **One line of `.gitattributes`: `docs/folds.md merge=union`.** Verified by
   running it — without a driver two branches appending produce
   `CONFLICT ... UU folds.md`; with the line, a clean merge keeping both rows.

**The write-target-set amendment**, stated explicitly rather than widened
quietly. It adds one bullet at `phase-3-exit-finalization.md:283-297` and one at
`skills/scope/SKILL.md:719-723`; corrects that entry's "one deletion target" to
one deletion **and one append** target, and its "Phase 3 does not delete; it
records" to name **Phase 2** as the recorder; adds a Phase 4 carve-out so the
file is enumerated but never swept, and repairs that section's stale
`L670-674` cross-references; and rewrites the absorb steps at
`phase-2-chain-orchestration.md:485-496`. Plus the `.gitattributes` line, the
check in `validate-docs.yml`, and an R26 entry in `docs/guides/doc-validation.md`
stating the family lives in CI rather than in `shirabe validate`.

The same pass owes two pre-existing defects the bakeoff found. The current set
gates `docs/{briefs,prds,designs}/` writes on "force-materialization only, on
`abandonment-forced` exit", so the full-run absorb's mutation of the survivor is
**already** outside the enumerated set and W2's when-clause must widen. And
`SKILL.md` names `docs/plans/` while `phase-3:299-302` says Phase 3 does not
write the PLAN. R19 is the pass that owes both regardless of this decision.

The path is a fixed constant with nothing interpolated, which is stronger for the
injection argument at `SKILL.md:724-726` than the slug-composed paths already in
the set.

**Rationale**

The reading of R20 decided the field before any cost argument was reached. Under
"the default branch keeps a record", every surface that lives inside a chain
document is disqualified, because a whole chain merges as one squash and any
document a later hop folds away takes its record with it. That kills the hybrid
in the case the feature exists to serve — a self-contained fix that folds down to
its code — and it kills the minimal answer outright, since the terminal fold is
exactly the case where the corpus otherwise retains no evidence the work happened.

The PLAN sub-variant deserved its separate examination, and it fails on
**determinacy** rather than on a flat claim that the PLAN never lands. It does
land: six PLAN documents have been added to `main` and five later deleted, all
through standalone `docs:` chain PRs merged ahead of their implementation PRs. But
`/execute`'s `orchestrator_setup` **adopts** an open `docs/<topic>` scoping PR as
its home PR when it finds one and stays on that branch, and on that path the chain
documents, the implementation and the cascade's `git rm` of the PLAN all land in a
single squash — so the PLAN is created and deleted inside one commit and never
reaches the default branch. Both shapes are live today. A record carried in the
PLAN therefore survives only when a run happens to take the separate-PR path and
vanishes entirely when it takes the adopted-PR path, and its survival turns on a
workflow choice the chain neither controls nor records. That disqualifies the
surface for a reason that holds whichever path a given run takes.

There is a sharper way to put the same objection to the hybrid, which its own
advocate accepted: under that surface, whether a record reaches the default branch
is decided by a verdict rendered *after* the record is written. At hop 1 the
producer cannot know whether the PRD survives — that is hop 2's judgment. A
surface that cannot answer "will this reach the default branch?" at write time
cannot discharge a requirement about the default branch, and the partial-fold case
where it does survive merely gets lucky.

What remained were two surfaces outside the chain, and the shared index beat one
file per topic on arithmetic its own advocate conceded: in a chain that folds all
three hops the index leaves zero new files under `docs/` where per-topic leaves
one, and at a hundred fully-folded topics that is nought against a hundred, which
would make `docs/folds/` larger than `docs/designs/current/`. The per-file shape's
one surviving edge was avoiding a merge driver, and that edge is worth a single
line of `.gitattributes`.

The strongest objection to the index was never contention — which was measured and
solved — but that R15 would make the record refuse the next hop's fold. That
finding is real and it changed the design. It also sat on top of a larger defect
the same investigation surfaced: **R15 as originally drafted refused every fold**,
including the only hop absorbable today, because the survivor cites the absorbed
artifact by repo-relative path in its own `upstream:` at the moment the scan runs,
and that citation is load-bearing — the reference check requires it to resolve.
Four agents found it independently, one of them measuring it at 36 of 36
BRIEF/PRD folds refused. **The survivor carve-out is a precondition of the whole
mechanism, not a property of this surface**, and R15 now names it. Once an
exclusion clause exists, naming the record surface beside it is one more entry in
a list being written anyway — and the objection that this is functionally an
override proves too much, since running it on the survivor's `upstream:` would
prove R15 must refuse every fold forever. R15 protects third parties from being
orphaned; the survivor and the record are the operation's own bookkeeping, which
is the same reasoning that already carves out `wip/`.

Two things gave the outcome unusual weight. Three of the five advocates abandoned
or conceded their own assigned alternatives on the evidence — the PR-body advocate
withdrew after first *strengthening* its own best argument and then finding the
defect that killed it, the per-file advocate conceded on arithmetic, and the
hybrid's advocate withdrew after verifying the opposing mechanism empirically
rather than taking it on assertion. And the one validator with no stake, asked to
referee, ranked the shared index first on grounds it built itself. The final tally
is four of five.

The PR-body route deserves a specific epitaph, because it is already written into
`phase-3-exit-finalization.md:64-76` and never implemented, and a future
contributor will find it there and think it cheap. It is not merely unimplemented.
Part 1 of a PR body reaches `main` through a human-editable merge dialog, and a
byte-comparison of five real PRs found that `a133581` silently lost 184 of 622
bytes — a whole paragraph, and that paragraph was a tree-state attestation,
exactly R20's genre — while all five were reflowed in a way that would break a
40-hex SHA across a newline. A record R20 requires to be produced mechanically
cannot be delivered by hand at eighty percent fidelity.

**Two further obligations this decision inherits.**

*The record must accumulate transitively.* This is a defect in the frontmatter
surfaces rather than in the chosen one, but it is the reason the chosen one is
whole: R6 and R8 already require contribution sections and their declarations to
accumulate across hops, so a frontmatter-borne record would have to ride the same
splice — and without that a three-fold chain leaves the first two hops' records on
documents deleted before merge, so `main` keeps one fold in three. The index has
this property for free, since every hop appends its own row to a file no fold
deletes, and the DESIGN should say that is *why* the surface is uniform rather
than treating it as incidental. The DESIGN should separately state that R21's
`absorbed:` accumulates transitively per R6 and R8, which no one has written down.

*`chain_ran:` is specified and never written.* It is defined in the state schema,
consumed by Phase 3 in three places — the hard-finalization check gates on it,
the durable-record instruction copies "every artifact in `chain_ran:`", and
`plan_execution_mode:` presence is conditioned on it — and nothing anywhere
populates it. The chosen surface does not lean on it: a row records what folded
into what directly, from the judgment that produced it. But the harm
`phase-3:74-76` names — that "a reviewer cannot tell an artifact that was absorbed
from one that was never produced" — is only half addressed by the record, since
the record speaks to absorption and `chain_ran:` is what would speak to
production. Anything that needs the second half must populate the field first.

**The R14 and R15 findings do not go here.** Both are abort paths: nothing is
deleted, both documents stay on disk, and R20's obligation attaches to a fold
landing. The decisive argument is R30 — if reaching `keep` required a durable
write that can itself fail, the safe outcome would acquire its own failure mode
and there would be no safer direction left to fail in. Both criteria are `[judg]`
and plan-graded, so a file on disk is invisible to the instrument that grades
them. They go to `consolidation_judgments:` in the state file and surface in the
run's own output. The DESIGN should note plainly that Phase 4 deletes that state
file on every exit path, so this recording is deliberately non-durable — adequate
for a finding about something that did not happen, and precisely why it is not
adequate for R20's record. A revert is the related case: it is a defect signal
rather than a fold record, and `phase-2:500-501` already routes it to R8
bail-handling, which the DESIGN should confirm surfaces to the author rather than
being swallowed.

**Alternatives Considered**

- **The survivor's frontmatter, alone or hybridized with an index at the sites
  that lack a survivor.** Structurally immune to the R15 cross-hop problem, since
  a record living in the survivor names the survivor by location rather than by
  path — a genuine advantage, conceded by every peer who examined it. Rejected on
  grounds its own advocate verified and accepted: a record in a document a later
  hop deletes never reaches `main`, whether it reaches `main` is decided by a
  verdict rendered after it is written, and because the terminal fold has no
  survivor the hybrid must build the index anyway — making it the index plus a
  second producer, a second format and a second reader location for one
  requirement.
- **One mechanical record file per fold, or per topic, in a dedicated
  directory.** Solves merge contention perfectly and is idempotent by path.
  Withdrawn to per-topic by its own advocate after the per-fold arithmetic proved
  indefensible, then ranked second by that advocate behind the index it conceded
  to. Loses on corpus count at scale, and carries the same R15 exposure the index
  does. A defensible fallback if `merge=union` ever proves unworkable.
- **The PR body's durable half.** Withdrawn by its own advocate. Three
  independent failures: `/scope` opens no PR on the single-pr path, the route has
  never been implemented, and `/execute` replaces the whole body unconditionally
  via `--body-file`. The kill was none of those — it was that Part 1 arrives on
  `main` through a human-editable field that measurably drops content.
- **Narrowing R20 to record nothing where no survivor exists.** The cheapest
  answer and the only one that builds nothing new. Rejected because it does not
  answer the question so much as remove the case that makes it hard: it drops the
  requirement at the site the requirement was written for, which amends the Goal
  rather than the requirement. Its own advocate conceded once the Goals text was
  put in front of it.
- **A new shape under `docs/decisions/`, an archive directory, or a per-run
  decision record.** Closed before this decision began, by the settled finding
  that a destination preserving the distillate must assert every time it fires
  that the verdict was partly wrong. Not re-litigated.
- **Git notes or a commit trailer.** Out on R20's text alone. Notes are not in the
  default fetch refspec and are not carried by a squash-merge; the repository has
  no trailer convention and the one trailer it mentions is a prohibition.

**Consequences**

`docs/folds.md` would be this repository's first shared append-only durable file
and `merge=union` its first merge driver. There is no precedent to inherit — the
sweep for a CHANGELOG, an index, a ledger or a manifest found nothing — and "one
line" understates the reviewer cost of the first instance of anything. Set against
that, the file is invisible to `shirabe validate` by construction: format dispatch
is basename-prefix only, so a non-prefixed file under `docs/` is skipped before it
is opened, verified by running the built binary and pinned by a golden fixture.
That buys zero Rust, zero `FormatSpec`, zero golden-fixture and zero
parity-baseline churn — a real saving, though not what protects R29, since a check
keyed on an absorption declaration emits nothing on non-absorbing documents under
either surface. It costs the fact that the validator cannot check the record
either, which is why the check is a CI script rather than a validator rule. Row
shape and hash verification could live in the Rust validator; deletion-to-row
correspondence is inherently diff-shaped and cannot.

Every fold now has a write that can fail, so the absorb gains a failure mode it
did not have. It fails toward `keep`, consistent with the existing direction, but
it is one more path.

One residual defect, stated plainly. `merge=union` keeps both sides' lines by
construction and therefore cannot deduplicate at merge time, while a write-time
guard cannot see other branches. A row is keyed by the pre-fold blob SHA, which is
unique per fold, so a duplicated row is a duplicate of an identical fact — untidy
rather than wrong — and the checker can flag it. Within a branch the resume
ladder's `Re-run` path is the only route to a double append, and it is arguably
unreachable, since after a successful absorb the upstream is gone and the hop is
no longer judgeable; a one-line guard closes it regardless. Note also that union
resolves silently with no conflict marker, so a merge can produce a semantically
odd file without signalling anything.

The blob hash is decorative after merge, under every alternative. Squash-merge
with branch deletion means the absorbed bytes are unreachable from `main`, so the
hash proves the record's honesty at write time and nothing more — which is what
makes the branch-time checker load-bearing rather than optional. The DESIGN should
say that rather than let a reader infer a recovery path that does not exist.

Finally, a reader following a survivor forward through the index gets there by
reading rather than by any repair step: a row naming a document that itself folds
later is followed by another row recording where *that* went. The chain resolves
by inspection, which is why no re-pointing is required and why every row stays
permanently true.
<!-- decision:end -->
