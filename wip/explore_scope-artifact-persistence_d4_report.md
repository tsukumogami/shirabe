<!-- decision:start id="retroactive-corpus-scope" status="assumed" -->
### Decision: Retroactive scope of the existing corpus

**Context**

`/scope` drives BRIEF → PRD → DESIGN → PLAN with a consolidation judgment per hop
that decides whether the upstream folds into the downstream and is deleted. Issue
#280 reports that the judgment can never return `absorb` above BRIEF→PRD, because
Stage 1 compares type schemas rather than document content. The fix makes the
verdict content-decided per run.

The author's justification for allowing documents to fold away rests on a claim
about the existing corpus: that the workspace's documents accumulated because the
workflow never asked whether they should be deleted, not because each was judged
worth keeping. That argument cuts toward applying the same judgment retroactively
— if those documents were kept only because nothing ever asked, the same reasoning
applies to them.

Three measurements decide the question, and the first is structural. The forward
operation is a **fold**: an upstream is distilled into a surviving downstream.
Measured per hop, the downstream exists for BRIEF→PRD in 60 of 61 cases and for
PRD→DESIGN in 94 of 103 — but for DESIGN→PLAN in **8 of 352**. The other 338 have
nothing downstream at all, because the PLAN is deleted at finalization by design
(`transition.rs`: PLAN's lifecycle is `Draft → Active → Done → DELETED`). The
consolidation judgment's own trigger condition requires an artifact that just
landed and a durable artifact above it that this chain produced; for those 338
neither holds. Its Stage 3 carry check walks each section recording where it
landed and aborts the absorb on any `carried: false`, downgrading to `keep` and
deleting nothing. **Run the real judgment over the DESIGN population and it
returns `keep` for all 338 — not as a verdict, but as the absence of a runnable
judgment.** Every validator, including the one assigned to argue for a full sweep,
converged on this after reading the source.

Second, the redundancy the premise rests on is a counting artifact. The headline
"366 DESIGNs, 3.5 per PRD" includes 44 golden test fixtures; the real corpus is
**516 documents (352 DESIGN, 103 PRD, 61 BRIEF)**. Among DESIGNs actually in a PRD
chain the ratio is **1.03**, 94 of 103 PRDs have exactly one child, and only 12%
of DESIGNs share even a two-token topic prefix with a sibling. The 3.42 comes
entirely from tsuku (21.0) and private/tools (23.5), repos that predate the
PRD-first workflow. The corpus is a lot of independent design work, not a pile of
duplicates.

Third, the safety net is absent. Deleting the 338 would leave **201 surviving
files holding broken references, 111 of them outside `docs/`** in skills, code, CI
and scripts. No rule checks any of them: `validate-docs.yml` is diff-scoped with
`--diff-filter=ACMR`, which excludes deletions outright, and the whole-tree
lifecycle gate does not run R6 (verified by executing the binary). The one
precedent is commit `a133581`, a **four-file** cascade that stranded five
references which have been broken for 64 days and still are.

**Assumptions**

- Golden test fixtures under `crates/shirabe/tests/fixtures/` are not corpus
  (44 files excluded). *If wrong:* every count rises ~4%, no proportion changes.
- `upstream:` frontmatter is the only machine-readable chain edge. A full
  frontmatter key census found no second lineage field with meaningful coverage.
- Git history was reachable only for shirabe; the sandbox refused `git -C` on the
  other repos. **tsuku's 147 DESIGNs — 42% of the corpus — are unmeasured for age
  and post-merge amendment.** This is the largest remaining measurement gap. It
  does not affect the recommendation, because the DESIGN population is excluded on
  structural grounds rather than on age.
- Text-file citation scanning (12,586 files, 14 extensions, ten checkouts)
  approximates the reference surface. GitHub issue bodies, PR descriptions and
  commit messages are outside it, so every breakage count is a **floor**.
- D's carry measurement uses token overlap of the ancestor's `Problem Statement`
  against the survivor's body — a lexical proxy for a semantic property. It is
  strong enough to clear a pre-committed threshold, not strong enough to substitute
  for the carry check itself.
- Run in `--auto` mode; the author has not confirmed this decision.

**Chosen: Out of scope — no retroactive pass in this work, with the boundary
rewritten to carry its reason, one repair pulled in, and the one defensible
population specified as a named follow-on**

Four parts.

**1. No sweep, and no retroactive pass of any kind in this work.** The 516
documents on disk stay untouched. No deletions, no archive moves, no pilot repo,
no corpus report.

**2. The `Out of Scope` line is rewritten rather than left as inherited
boilerplate.** It currently reads "Retrofitting artifacts already on disk." It
should record *why*, because "the corpus is out of scope" and "the corpus is out
of scope because the fold has no target below the PRD→DESIGN hop" are the same
decision with very different half-lives. Substantially as the sweep's own advocate
drafted it:

> **Out of scope: retroactive application to documents already on disk.** The
> consolidation judgment runs against two bodies that exist, at the moment a child
> lands. For 338 of the 352 DESIGNs on disk the downstream PLAN was deleted at
> finalization by design, so there is no second body and no landing event: `keep`
> is not a verdict the judgment renders on them, it is the absence of a runnable
> judgment. For the 154 BRIEF→PRD and PRD→DESIGN pairs where both bodies do
> survive, a retroactive fold is definable, but it requires the
> contribution-section format this work is still designing and would edit settled
> artifacts, so it cannot be specified here. **Neither statement means those
> documents were judged to earn their place.** Whether a settled document is live
> guidance or the historical record of shipped work is a lifecycle question with
> its own criterion and its own disposal (archive, not delete); it is filed as
> follow-on work rather than left implicit.

**3. The retirement guard comes INTO scope, as a point query.** This is a
correction to already-scoped work, not new scope. The exploration committed to
wiring `lifecycle::build_referrer_map` before the `git rm` and called it "the
single change that turns the reduction back into a move." **That sentence is
false and must be corrected.** The map indexes only `upstream:` frontmatter edges,
so it is blind to prose, skill, code, CI and script citations — the classes that
have actually broken here — and it would have permitted `a133581` exactly as it
happened.

What the absorb needs is not an index but a point query: *who mentions the one
document I am about to delete, in this repo, right now?* It runs inside Stage 3
between the `upstream:` re-point and the `git rm`, scanning the same repo's text
files (`.md .rs .go .sh .yml .yaml .toml .json .py .ts .js`, skipping `.git`,
`node_modules`, `target`, `dist`, `.venv`, `**/tests/fixtures/**`). Two tiers: a
path-exact hit downgrades the verdict `absorb` → `keep` through the abort path
that already exists verbatim ("Any `carried: false` aborts the absorb… Nothing is
deleted on a failed carry check"); bare-name hits route into the judging agent's
findings rather than acting mechanically. No new severity, no new error code, and
no override — a guard whose only power is refusing to delete has no unsafe failure
mode, and it must never be allowed to grow an action stronger than `keep`.

Explicitly fenced OUT of this work: the corpus-wide citation index; a
notice-severity validator rule for unresolvable citations (it would fire on ~374
pre-existing unresolvable names across ~467 mentions — a repair campaign, not a
guard); and the CI deletion blindness (adding `D` to the diff filter is not a
one-line fix, since it would pass deleted paths to a validator that cannot open
them — the right check validates the *referrers* of deleted paths).

**And a firewall, stated in the scope file in these words:** the guard is
justified entirely by the DESIGN→PLAN hop this work opens *forward*. It carries no
retroactive commitment and produces no verdict about any existing document.
Without that sentence, corpus work rides in on the guard's back and this decision
gets re-litigated as an implementation detail.

**4. Two named follow-ons, both now fully specified.**

*First follow-on — the BRIEF→PRD retroactive fold.* This is the one retroactive
operation that is coherent with the forward mechanism, and the bakeoff
characterised it precisely. Population: BRIEF→PRD pairs at status `Done` with
exactly one live child and a matching slug (60 of 60 share their exact slug),
excluding the 1 PRD with no `Problem Statement`, the 3 ambiguous multi-child PRDs,
and the 14 PRDs whose requirement numbers are cited from outside their own chain —
two of those from compiled Go (`install.go:327` `(R3)`,
`lifecycle.rs:3657` `(R12)`). Gates: the point-query guard lands first; the four
absorb repairs land and are exercised forward at least once; the
contribution-section format is settled; the `R<n>` citation rule lands or the
R-cited PRDs are excluded. Sequencing: cross-repo citation repairs first (5 named
files), then shirabe, with a stop point before the other repos.

*Second follow-on — a lifecycle criterion for settled documents.* The question
"is this document live guidance, or the historical record of work that shipped?"
is a lifecycle question, not a consolidation question, with its own criterion and
its own disposal. It needs an `Archived` status (~3 lines: `transition.rs:447`,
`transition.rs:453`, `formats.rs:113`) because the existing `Superseded` transition
requires a `superseded_by:` pointer an orphan DESIGN cannot honestly supply. Most
defensibly scoped to the 141 DESIGNs cited by nothing, with archive as the
disposal — where being wrong costs a re-move rather than a lost document. Note
this would not select the corpus: 68 of the 338 are cited from outside `docs/`,
including from `skills/plan/SKILL.md`, `gh.rs` and CI.

**Rationale**

The author's argument is that these documents persist because nothing ever asked.
The decisive finding is not that the argument is wrong — it is that for 96% of the
population it names, **there is no question to ask**. The consolidation judgment
compares an artifact that just landed against a surviving durable artifact above
it. For 338 of 352 DESIGNs the PLAN was deleted at finalization by design, so
there is one body, not two, and no landing event. The mechanism's own text names
this: "It is only honest to do it *here* — against two bodies that exist… The same
question asked at Phase 1, before either document is written, has no answer, and
answering it anyway is how content gets lost." A retroactive sweep over that
population would not be applying the same judgment; it would be inventing a
discard verdict the mechanism refuses, against a reference surface no rule checks,
where a four-file precedent already stranded five references for 64 days.

The evidence that would have supported a sweep dissolved under measurement. The
3.5-DESIGNs-per-PRD ratio is 1.03 among chained documents. Document length is
useless as a proxy and more so than stated — the "10-line DESIGN" was a test
fixture; the real floor is 81 lines and the median is 544. And the prior
`DECISION-orphan-doc-passing-state-rule` (still Accepted) named the same blocker
two months ago in its own words — "no clear migration target" — which this work
does not remove for the DESIGN population.

The narrow call is the BRIEF→PRD hop, and it deserves an honest account because
the evidence there runs the other way. One validator pre-committed a falsifiable
threshold — concede the hop at ≥80% carry — and the measurement cleared it
decisively: 53 of 58 pairs at ≥0.70 overlap, all 58 at ≥0.61, no low tail, and the
predicted pre/post-#260 bimodality falsified by dating every pair. So the feared
operation is verification of a carry that already happened, not authoring into
settled artifacts. The reason it is still deferred is ordering, not merit: the
pass writes contribution sections in a format this work is still designing, so it
cannot be specified inside the design that produces it; and it would be the
first-ever production execution of the absorb procedure, at scale, inside the
change that repairs four known bugs in it. Deferring costs nothing permanent — the
population is now measured, the exclusion filters are written, and the evidence is
in this report. Including it risks the mechanism's debut being a mass operation.

The asymmetry is the whole argument: `keep` is always a safe outcome, and every
piece of retroactive work here is equally available in three months against a
mechanism that has run.

**Alternatives Considered**

- **(a) Out of scope, forward-only, corpus untouched.** Effectively chosen, but
  **rejected as stated**, on two counts. Its clustering with option (e) assumed
  opportunistic convergence comes free; that was verified false. And leaving the
  `Out of Scope` line as inherited boilerplate would record the corpus as
  *vindicated* when it is merely *unreached* — the distinction the sweep's own
  advocate won and the only thing it won.

- **(b) Ship a read-only corpus report.** Rejected. Its own advocate withdrew it
  in Phase 4. Five independent throwaway scanners produced convergent numbers in
  one session, which killed the durability and repeatability arguments, and D's
  enumeration discharged what the report was for. What survived is the runtime
  guard, which is a different thing and is adopted above.

- **(c) In scope, sweep everything.** Rejected, and its own advocate voted against
  it after reading the trigger condition. For 96% of its population the judgment
  has no runnable form; the operation would be a bare discard with no receiver,
  breaking 201 surviving files behind CI that structurally cannot see deletions.
  Its best surviving points are adopted rather than discarded: that "516
  irreversible calls" is wrong (deleted files return from `main` in two commands),
  and that the corpus must be recorded as unreached.

- **(d) In scope but bounded.** The strongest rejected alternative, and rejected on
  ordering rather than on merit — its hop bound is adopted wholesale as the first
  follow-on, with its measured population, its filters and its R-citation
  carve-out. Its two weaker forms died in the bakeoff: the terminal-chain bound is
  vacuous (307 of 352 DESIGNs are already at `Current`, so it admits 87% of the
  population — a rubber stamp with a filter's rhetoric), and the one-repo pilot
  does not contain its own blast radius (shirabe's hop-bound documents are cited
  from five files in four other repos, so a "shirabe pilot" is already a five-repo
  PR sequence).

- **(e) Opportunistic — judge a document when work next touches its topic.**
  Rejected, and the reason is a correction to this decision's own framing. It was
  initially clustered into (a) on the ground that `/scope` re-entry leaves a
  settled artifact present in the chain and therefore subject to fold-or-survive.
  **That is false**: re-entry records held-back children in `chain_skipped:` and
  keeps them out of `planned_chain:`, and Step 8 fires "only when this chain
  produced a durable artifact above the one that just landed." A pre-existing
  settled artifact is never judged. As a standalone option it would need a new
  trigger and a new judgment class, and it would aim deletion at the most-cited
  documents. Declined — but the fact that convergence does not happen by itself
  must be recorded, because no decision here may be justified by an assumption
  that the corpus self-corrects.

- **(f) Retroactive but archive rather than delete** (surfaced by research, not in
  the original list). Rejected for this work by its own advocate, who concluded
  "E contributes nothing to this work's scope." Archiving is not the retroactive
  arm of the consolidation judgment, because the judgment never reaches these
  documents; and `Archived` repairs nothing the forward mechanism depends on, so
  it fails the same test that admits the guard. Cheap is not the same as in scope.
  It survives as the disposal for the second follow-on.

**Consequences**

*What becomes easier.* The scope stays bounded around the judgment fix, the four
absorb repairs, the format-contract changes and the two `/execute` changes, plus
one repair that makes the forward fold safe. The forward absorb — the operation
with **no** recovery path, since squash-merge plus branch deletion means an
absorbed document never existed on `main` — gets a guard that can see the
reference classes that have actually broken. The boundary is recorded with its
reason, so the next person reads why rather than reopening the question.

*What becomes harder.* Two named follow-ons now exist that did not before, and
they carry real content: a specified BRIEF→PRD pass with ~55 candidates after
exclusions, and a lifecycle criterion needing a new status. If neither is picked
up, the corpus question stays open indefinitely — and the honest form of that is
that 240 chainless and 141 uncited DESIGNs will never be judged by any current or
planned mechanism. That is a curation gap, not a pipeline gap: the instrument
already exists (`shirabe transition … Superseded`, git-mv into
`docs/designs/archive/`, 22 documents already there) and nobody has spent an
afternoon with it. The scope file must say so rather than let "out of scope" imply
the corpus is healthy.

*Corrections this decision forces on the exploration, independent of the verdict.*
The `build_referrer_map` sentence in `findings.md` is false and load-bearing.
The claim that reduction "stays a content-preserving move" with "no discard
verdict" is superseded within `decisions.md` itself, which still carries both
statements — the surviving formulation is that every fold is a distillation and
what varies is *where the distillate lands*, never *whether* it lands. And the
constraint that a retroactive pass must not add to the broken-reference class is
sound, but the irreversibility premise behind it is backwards: retroactive
deletion is recoverable from `main`, forward absorption is not.

*Residual risk being accepted.* The guard is same-repo only, so cross-repo
citations stay unguarded — and they exist (`dot-niwa-overlay/.niwa/CLAUDE.overlay.md`
cites a niwa DESIGN; `private/tools/plugin/tsukumogami/skills/**` cites DESIGNs
across repos). GitHub issue bodies, PR descriptions and commit messages are
outside every count here, so all breakage figures are floors. Bare-name citations
route to an agent rather than blocking, which is weaker than a machine guarantee
and strictly better than today's zero — and whether agents reliably act on routed
soft findings is untestable from this repo's history, because the absorb procedure
has never executed once.
<!-- decision:end -->
