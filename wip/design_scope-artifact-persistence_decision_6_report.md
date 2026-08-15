<!-- decision:start id="citation-guard-implementation" status="assumed" -->
### Decision: The pre-deletion citation guard is a tested skill-local script with prose routing

**Context**

R15 requires that before deleting an artifact, the absorb procedure search the
repository's git-tracked files, excluding `wip/`, for citations of it. A path
citation downgrades the verdict to `keep` through the existing abort path; a
bare-name citation is a finding the judging agent sees and does not by itself
change the verdict. The guard has no override and no outcome stronger than `keep`.

Fold time is the only point where this is catchable. `.github/workflows/validate-docs.yml`
computes its file set with `git diff --name-only --diff-filter=ACMR`, so a document
stranded by a deletion is never in the changed set and R6 cannot fire on it at the
PR that breaks it — verified against the workflow, whose own comment states that
the CLI never discovers files itself. Five documents in this repository carry
dangling `upstream:` refs today and `shirabe validate` exits 2 on them; diff-scoped
CI has not noticed for months.

Two measurements decide the shape. First, `lifecycle::build_referrer_map` — public
at `lifecycle.rs:539`, wired to `finalize-chain` at `finalize.rs:506`, and confirmed
unreachable from the absorb path — indexes only `upstream:` frontmatter edges, via
`build_inverse_upstream` iterating `indexed.upstreams`. A census of every
`docs/{briefs,prds,designs}` document's path citations across tracked files finds
271 citing lines, of which 77 (28%) are frontmatter edges and 194 (72%) are prose,
References sections, code comments and CI comments — including the three
non-markdown citations in the repo (`lifecycle.yml`, `gh.rs`, `lifecycle.rs`).
Wiring the referrer map would catch 28% of the surface. The exploration's original
claim that it is "the single change that turns the reduction back into a move" is
false by roughly 3.5x, and D4's correction holds. A text search over tracked files
is a strict superset: it finds all 271 lines including all 77 the referrer map
would.

Second, and decisive for where the guard lives: **the survivor always cites the
absorbed artifact by path**, because its `upstream:` names it. Measured across all
36 BRIEF/PRD pairs on disk, a naive search blocks **36 of 36 folds**. Excluding the
survivor as a file brings that to 20 of 36. Excluding only the `upstream:` line is
not enough either — 22 of 36 survivors cite the absorbed path more than once, in
prose and References sections. The exclusion set is not a refinement of this guard;
it is the difference between a guard and a total fold-blocker, and it is exactly
the kind of detail prose ships wrong.

**Assumptions**

- Run in `--auto`; no user confirmation was taken on any of the below.
- Adding `skills/scope/scripts/` and a `check-scope-scripts.yml` job is acceptable.
  `skills/plan` and `skills/execute` both ship this exact pattern, so it needs no
  new CI infrastructure, but `/scope` has neither today.
- The guard stays same-repo, per the PRD's stated Known Limitation. Cross-repo
  citations, issue bodies and PR descriptions are out of reach and the coverage is
  a floor, not a bound.
- The measured 42% third-party block rate is informative about the guard's bite,
  not a number to tune down. R30 says fail toward `keep`.

**Chosen: A shell script under `skills/scope/scripts/`, with verdict routing left in Stage 3 prose**

The guard splits along its natural seam. The **search** is deterministic and ships
as `skills/scope/scripts/check-citations.sh`, taking the absorbed path and the
survivor path and printing two tiers. The **routing** — path hit downgrades to
`keep` through the existing abort path, bare-name hits become findings — stays in
Stage 3 prose, because routing a verdict is agent behaviour and no script decides
it.

*What the script does.* One `git grep -I -F -n` per tier over tracked files. `-F`
because a document path contains `.` and `-`, which are regex-significant; `-I`
because 35 of the 897 tracked files are binary. The pathspec exclusion set is
pinned in the script, not left to the caller:

- `:!wip/` — required by R15, and load-bearing rather than hygienic:
  `state-schema.md:79-80` records `absorbed:` and `into:` with both paths inside
  the run's own state file, so without the carve-out the guard blocks on its own
  bookkeeping.
- `:!<absorbed path>` and `:!<survivor path>` — without the survivor exclusion the
  guard refuses 100% of folds.
- `:!*tests/fixtures/*` and `:!*evals/fixtures/*` — the same pair
  `validate-docs.yml:91` already excludes. The measured fixture false-positive
  surface across the whole corpus is exactly one file,
  `crates/shirabe/tests/fixtures/golden/corpus/real/DESIGN-gha-doc-validation.md`,
  a verbatim copy of a real DESIGN carrying its real `upstream:`. There are no
  vendored trees in this repository.

No extension filter. Three of the 271 citing lines are in `.rs` and `.yml` files,
and those are precisely the class that breaks silently — a `.md`-only search would
drop them for no gain.

*Tiers and exit codes.* Tier 1 is a fixed-string search for the repo-relative path;
tier 2 is a search for the filename stem without its directory. Exit 0 clean, exit
1 path-exact hits present, exit 2 bare-name hits only, each printing
`file:line:text` so the finding can name the citing file as the PRD's criterion
requires. There is no exit code meaning "proceed anyway" — the script has no
override to express, which is what makes it structurally incapable of an outcome
stronger than `keep`.

*Where it runs in Stage 3.* At the top, before the contribution section is
authored and before the `upstream:` re-point — not, as the exploration's D4 wrote
it, between the re-point and the `git rm`. The search needs only the absorbed
artifact's path, known at Stage 2's verdict, and it costs 16ms. Running it first
makes a downgrade a pure abort with nothing to undo, rather than a rollback of
mutations already applied. That is strictly the stronger R30 posture, and it
satisfies R15's "before deleting" a fortiori. This refines D4's placement sentence
without contradicting the PRD.

*Testability.* A co-located `check-citations_test.sh` runs in
`.github/workflows/check-scope-scripts.yml`, mirroring `check-plan-scripts.yml:36`
and `check-execute-scripts.yml:26`. The PRD defines **[mech]** to include "a shell
harness scenario", so the search half becomes a merge gate. Fixtures worth pinning:
survivor-cites-absorbed must not block; third-party path citation must block;
fixture-directory citation must not block; bare-name-only must exit 2 not 1; a
`wip/` citation must not block.

**Rationale**

Three constraints select this and nothing else. The guard must see prose, code and
CI citations, which rules out the referrer map at 28% coverage. Its exclusion set
must be pinned and tested, because getting it wrong blocks every fold rather than
degrading gracefully, and prose has no instrument stronger than a plan-graded
weekly eval. And it must not buy a new public interface, which rules out a
`shirabe` subcommand governed by the multi-consumer CLI contract that R29 already
flags as an unverified cross-repo surface.

**Alternatives Considered**

- **Skill prose only.** Rejected because the exclusion set cannot be pinned in
  prose and getting it wrong is catastrophic rather than degraded — 36 of 36 folds
  blocked. Its only instrument is a plan-graded `/scope` eval on a weekly cron
  (every consolidation scenario in `evals.json` is worded "Plan aborts...", "Plan
  re-runs..."), which grades whether the agent *said* it would exclude the
  survivor. R15's blocking criterion would be stuck at [judg].
- **Wire `lifecycle::build_referrer_map` into the absorb path.** Rejected on
  measurement: 77 of 271 citing lines, blind to every prose, References-section,
  code-comment and CI-comment citation. It is also a Rust API with no CLI surface,
  so the skill could not call it without a new subcommand anyway.
- **A new `shirabe check-citations` subcommand.** Rejected because it would
  reimplement `git grep`'s tracked-file scope and pathspec exclusion in Rust for no
  capability gain over a 16ms one-liner, while entering
  `docs/guides/multi-consumer-cli-contract.md` — a versioned interface with
  cross-repo consumers pinning tags. Every existing subcommand parses shirabe
  documents with format knowledge; a fixed-string search over `.rs` and `.yml`
  files is not that.
- **Extend `shirabe validate` with a repo-wide citation check.** Rejected as
  out of PRD scope — the Out of Scope section fences the repository-wide citation
  index and the notice-severity rule as repair campaigns against ~374 pre-existing
  broken references — and it would emit findings against documents already on disk,
  which R15's last sentence and R29 both forbid.

**R18's relationship to R15: the referrer-set clause collapses, the rest does not**

The clause "and every document that referenced the absorbed artifact" is empty by
construction once R15 has passed, and re-validating what remains of it emits
nothing. Taking the residue in turn:

- **Path-citing documents.** R15 already refused the fold. Never reached.
- **`upstream:` referrers.** A frontmatter edge *is* a path citation. Subsumed —
  this is the class `build_referrer_map` would have caught, and R15 catches it as
  77 of the 271 lines it sees.
- **Bare-name referrers the agent waved through.** These are the only documents
  that survive into R18's set, and `shirabe validate` has no check on bare names.
  That is the ~374 pre-existing unresolvable-name population the PRD explicitly
  fences out of scope. Re-validating these documents is guaranteed to emit nothing
  about the absorb.
- **`wip/` and cross-repo citers.** Outside R15 by design and outside R18's reach
  equally. No gain.

So R18 buys nothing over R15 on referrers. What it *does* buy is two things R15
has no analogue for, and both are load-bearing:

1. **The survivor.** R15 says nothing about it. The absorb writes four new things
   into the survivor — the `upstream:` splice (R17), the absorption declaration
   (R8/R21), the `## Status` line (R21), and the contribution section (R4/R6/R9) —
   every one of which can fail validation. This is step 4 of Stage 3 as it already
   exists, and it is the half that actually fires.
2. **Revert-in-full versus abort.** R15 aborts *before* any mutation, so "fail
   toward `keep`" costs nothing. R18 reverts *after* several mutations and a
   deletion, so it must restore the absorbed document, undo the splice, remove the
   declaration, the `## Status` line and the contribution section, and record the
   revert. Different mechanism, different failure mode, no overlap.

The recommendation is therefore to **narrow R18's coverage clause to the survivor**
and let its revert semantics carry the requirement, rather than keep a referrer
clause that is provably empty. Keeping it as written costs an implementer a
re-validation loop over a set that is always empty except for documents on which
the validator is silent — dead code that reads as a safety net.

**R16's placement: the validator, keyed on the absorption declaration**

R16 does not live with R15's guard. Different time, different trigger, different
mechanism. R15 fires at fold time, before deletion, over the whole repository,
keyed on a path. R16 fires at validate time, on one document, keyed on that
document's own frontmatter.

R16's own text says "`shirabe validate` SHALL fail", and the PRD's criterion is
**[mech]**: "A DESIGN citing `R7` whose PRD was absorbed without carrying the
requirement numbering fails `shirabe validate`." So it is a validator check code
alongside R6 and the FC family.

The scoping that keeps it from failing 77 documents is the absorption declaration
R8 puts in frontmatter. The check reads: *if* this document declares an absorption,
then every `R<n>` it cites must resolve within its own body or within its spliced
`upstream:`. A document with no absorption declaration is not examined at all,
which is exactly R29's requirement that the added checks emit nothing on
non-absorbing documents. The 77 documents citing an `R<n>` they do not define —
including the PRD whose upstream BRIEF carries no requirement numbers and the
`Done` BRIEF citing another chain's PRD by path — declare no absorption and are
untouched. The scoping falls out of the frontmatter field rather than needing a
run-identity mechanism, which is what makes it implementable at all: the validator
has no notion of "this run".

**Consequences**

`skills/scope/` gains a `scripts/` directory and the repository gains a
`check-scope-scripts.yml` job, both patterned on `skills/plan` and `skills/execute`.
Stage 3 gains one step at its top and a routing paragraph. R19's closed
write-target set is unaffected by the guard itself — the search is read-only — but
still needs the amendment the blast-radius research identified for the deletion
targets under `docs/prds/` and `docs/designs/`.

Two consequences a maintainer should find written down rather than discover:

- **The guard bites hard.** On today's corpus, 15 of 36 BRIEF-to-PRD pairs (42%)
  have a genuine third-party path citation and would fold to `keep`. That is the
  guard working, not misfiring, but anyone expecting folds to be routine should
  see the number first.
- **`/scope` can block itself.** Its own Decision Record templates write durable
  files under `docs/decisions/` citing artifact paths verbatim —
  `decision-record-prd-rejection.md:71` names `docs/prds/PRD-<topic>.md`, and
  `decision-record-design-rejection.md:69,76` name both the DESIGN and the PRD
  path. `docs/decisions/` is tracked, outside `wip/`, and not a fixture, so a topic
  that once produced a rejection record becomes permanently unfoldable at that hop
  on every later run. This is correct under R30 — a Decision Record citing a
  deleted path really is a stranded citation — but it is a designed outcome and
  belongs in the DESIGN's prose.

The survivor's own now-dead citations are a **rewrite obligation on the fold, not a
block**: 22 of 36 survivors cite the absorbed path in prose beyond the `upstream:`
line, and after the fold those point at a file that no longer exists. Excluding the
survivor from the guard is what makes folding possible at all, so something else
has to clean them, and that duty belongs in the absorb procedure next to the
`upstream:` splice.

**Criterion tags this choice supports**

- R15's blocking behaviour: the search half becomes **[mech]** (shell harness in a
  merge gate) rather than [judg]. The PRD's current criterion — "An absorb of an
  artifact cited by repo-relative path from any tracked file outside `wip/` is
  refused, both documents stay, and the citing file is named" — splits into a
  [mech] half (the script finds the citation, names the file, and exits non-zero
  under the pinned exclusion set) and a [judg] half (the agent routes that into
  `keep` through the existing abort path).
- R15's bare-name tier stays **[judg]**. "Surfaced as a finding and does not by
  itself change the verdict" is a statement about agent behaviour; the script can
  only be tested for classifying the hit as tier 2, which is the [mech] half.
- R16 stays **[mech]** and needs no change — it is a validator check code with a
  Rust test, exactly as the PRD has it.
- R18's survivor coverage stays **[judg]** as written. Its referrer clause, if
  narrowed as recommended, stops implying a mechanical check that would have
  nothing to check.
<!-- decision:end -->
