# Exploration Findings: fold-record-scaling

## Core Question

`docs/folds.md` is a shared, append-only, one-row-per-fold record written by
`/scope`'s consolidation judgment. It exists to make an absorbed document
distinguishable from one that was never produced. Should it be removed outright,
or replaced by a different carrier?

## Round 1

### Key Insights

**The record has never recorded a fold.** `docs/folds.md` has exactly one commit
behind it (`83d29e1`, PR #302, merged 2026-08-15) and zero data rows on every
branch. It is 63 lines of header, rationale and column contract over an empty
table. Every claim on both sides of this question — the design's and the user's —
is a projection, not an observation. Migration cost today is literally zero, and
it grows with every fold. (all six leads, independently)

**"Should there be a record at all" was never asked.** The decision was fixed at
BRIEF altitude — `BRIEF-scope-artifact-persistence.md:140-142` lists "a durable
record, on the default branch, of what folded into what and on what verdict" in
the In-scope list. The DESIGN's Considered Options section
(`DESIGN-scope-artifact-persistence.md:164-177`) evaluates *which surface carries
a record*, never *whether a record*. All six underlying decisions were made in
`--auto` mode without author confirmation, and PR #302 (34 files, +3886/-209) has
zero comments and zero reviews. There is no defended cost/benefit for the log to
overturn — there never was one. (lead-design-history)

**Growth is not the problem.** A row is ~285 bytes; a fully-folded chain ~900. At
this repo's observed rate (~10 chains/month), three years is ~308 KB — under 8%
of today's `docs/` tree. The decisive framing: a fully-folded chain *deletes*
roughly 80 KB of documents and adds ~900 bytes of record. **The record costs
about 1% of what the fold reclaims.** Calling it unbounded growth inverts the
sign of what the mechanism does. (lead-growth-contention)

**Nothing loads it into agent context.** Every reference in `skills/` is a write
instruction, a write-set enumeration, a sweep carve-out, or prose.
`skills/execute/SKILL.md:597-600` goes out of its way to say "nothing here reads
it to make a lifecycle decision." `detect_format` returns `None` for the
basename, so `shirabe validate` skips it. `ARTIFACT_DIRS` does not include
`docs/` itself, so no whole-tree walker opens it. (lead-consumers,
lead-growth-contention)

**But there is one real context path, and it is a tooling accident.** Phase 2
step 6 says only "Append one row to `docs/folds.md` and `git add` it" — no
mechanism given. The workspace `CLAUDE.md` "File Operations" rule actively pushes
agents toward Edit over shell redirects, and Edit requires reading the file
first. At the 3-year figure that is a ~308 KB read to append 285 bytes, up to
three times per chain. One sentence mandating `>>` closes it. (lead-consumers,
lead-growth-contention)

**Contention is real, and worse than the design believes.** `merge=union` was
verified working across local merge, rebase, squash-merge and cherry-pick — and
verified to conflict without it. But **GitHub does not honor repository
`.gitattributes` merge drivers server-side.** Two open PRs each appending a row
still show "This branch has conflicts" and the merge button is still blocked.
Kubernetes removed its own union-merge attribute for exactly this reason
(kubernetes/kubernetes#70576). So `docs/folds.md:51-52`'s claim that concurrent
folds "merge cleanly instead of conflicting" is false on the platform this repo
merges on. What the driver actually buys is a silent local `git rebase main`
instead of a hand edit. (lead-growth-contention)

**Adopters get the check without the mitigation.** `.gitattributes` is a
repository file, not a plugin asset — `.claude-plugin/plugin.json` ships
`"skills": "./skills/"` and nothing else. No bootstrap path adds it
(`install.sh` installs a binary; `shirabe install-hooks` writes a pre-commit hook).
No adopter-facing doc mentions it: `docs/guides/doc-validation.md:53-68` documents
the fold check in five paragraphs without ever naming `.gitattributes`,
`merge=union`, or concurrency. Meanwhile the reusable workflow — pinned by koto,
niwa and tsuku — runs the fold assertions in the caller's repo in full.
(lead-growth-contention, lead-blast-radius)

**The CI check cannot fire on the case the record exists for.** The trigger is
`git diff --name-only --diff-filter=D "$BASE...$HEAD"`. That is a tree-to-tree
comparison; a document created *and* deleted inside the same branch is in neither
endpoint and is never reported as deleted. The fold's firing condition guarantees
exactly that state — the judgment fires only when both endpoints of the edge were
produced by this run. So `DELETED` is empty and the step `exit 0`s at line 123
without asserting anything. **This was reproduced independently by three agents
and by the orchestrator**, with a control confirming the filter does see deletions
of documents that existed at base. The file that declares itself "written
mechanically and read by CI" is, on its only live path, neither read nor verified.
(lead-unique-guarantee, lead-alternative-carriers, lead-growth-contention, +
orchestrator verification)

**A second CI bug produces false failures on correct records.**
`git rev-parse <sha>:<missing-path>` writes `fatal:` to stderr *and echoes the
literal argument to stdout*. So `want=$(git rev-parse "$BASE:$doc" 2>/dev/null || true)`
is never empty, the `[ -n "$want" ]` skip-guard at `validate-docs.yml:148` is dead
code, and the step emits `::error:: fold record hash does not match the pre-fold
blob (<sha>:<path>)` — naming a pathspec where a hash should be — against a row
that is perfectly correct. It triggers when `DELETED` (merge-base relative) and
`want` (`$BASE` relative) disagree, which is exactly what happens when a parallel
PR folding the same document merges first. **The parallel-agent contention this
exploration is about surfaces as a red CI check on a correct record, not as a
merge conflict.** (lead-alternative-carriers, lead-growth-contention)

**Two more defects in the same 60-line step.** (i) Duplicate detection is asserted
in three documents — `docs/folds.md:52-55`, `.gitattributes:6-8`,
`DESIGN-scope-artifact-persistence.md:316-318` all say "the checker flags it" —
and implemented in none; grepping the workflow for `duplicate` returns nothing.
(ii) The row lookup `grep -F "$doc" | head -1` matches the path in *any* column
including `Into`, so on a two-hop chain it returns hop 1's row and compares hop
2's document against hop 1's blob — CI red on a correct record, in the ordinary
case. (lead-consumers, lead-growth-contention)

**The unique guarantee is one fact in one shape.** For every fold whose survivor
stays on disk, the survivor carries an `absorbed:` declaration, a pinned
`## Status` line and a contribution section — all three enforced at error level by
`check_fc18` — and the `absorbed:` list **accumulates transitively** across hops
(`phase-2-chain-orchestration.md:748-755`: "a survivor's list is its ancestor's
list plus the ancestor"). That falsifies the first half of the argument that put
the record in a shared file: `DESIGN-scope-artifact-persistence.md:167` says the
frontmatter alternative "fails because the record dies with the document at the
next hop." It does not die at the next hop; it is carried forward by rule. What
remains unique is the case where `/execute`'s cascade `git rm`s the last survivor
(the PLAN) at finalization, taking every accumulated declaration with it.
(lead-unique-guarantee)

**Removal is cheap mechanically and bounded documentarily.** ~200 lines across 14
files, of which ~120 are prose justification. No compiled code changes, no eval
changes, one deleted test case. The documentary cost is four dated amendment
sections — and `PRD-scope-artifact-persistence.md` (status `Done`) is where R20
actually lives, not the consolidation PRD. A PRD has **no** `Superseded` status
(`formats.rs:271`: `Draft, Accepted, Done`), so amendment-in-place is not a
choice, it is the only mechanism the toolchain offers. Precedent is one day old:
both consolidation docs were amended in place at terminal status with the pinned
formula "The original text above is left unedited; this section records what no
longer holds." (lead-blast-radius)

**A second carrier already exists and is already populated.**
`skills/scope/references/state-schema.md:204-208`: Phase 3 copies `chain_ran`,
`chain_skipped` and `consolidation_judgments` into the run's PR body before Phase
4 removes the state file, because "the PR body is where a reviewer can tell 'not
produced' from 'absorbed into this other document' after the scratch is gone."
That is verbatim the job `docs/folds.md` claims as its reason to exist. The DESIGN
rejected the PR body as the *authoritative* carrier on a measured fidelity finding
(five merged PRs byte-compared; one silently lost 184 of 622 bytes through the
merge dialog) — but never removed the soft copy. (lead-blast-radius)

**Sharedness, not size, is what the findings indict.** A per-fold file
(`docs/folds/<date>-<slug>.md`) is structurally conflict-free — two agents never
write the same path — so it needs no merge driver at all, which also dissolves the
adopter gap. Its append-only assertion gets *simpler* ("no file under
`docs/folds/` was deleted or modified"), and every actual query against the data
is keyed by absorbed path, so lookups become a path check or `grep -rl` rather
than a whole-file read. Cost: file-count clutter and a lost "show me everything
that folded" single-file view. (lead-alternative-carriers, lead-growth-contention)

**Carrier survey verdicts.** git notes: disqualified — verified not fetched by
`git clone`, rendered nowhere, separately mutable. Commit trailers: verified to
survive squash-merge and parse, but **cannot be verified pre-merge** because the
squash commit does not exist until the button is pressed, and the merge dialog is
human-editable. PR body / labels / comments: not in the tree, freely editable,
GitHub-only, and the workflow declares `contents: read` only. Per-chain file
retired at finalization: inverts the requirement — it destroys the evidence at
exactly the moment the fully-folded case needs it. Rotation/pruning: needs an
escape hatch in the append-only assertion, and union merge preserves no row order
to truncate by (verified: squash and cherry-pick both put the later row first —
the record is a bag, not a log). (lead-alternative-carriers)

### Tensions

- **The user's two stated concerns do not survive equally.** Growth is close to
  unreal (1% of what a fold reclaims, nothing reads it). Contention is real but
  misdiagnosed — it bites as a blocked GitHub merge button and a false CI failure,
  not as a text conflict in the file. Both concerns point at the same place in the
  end, but for different reasons than stated.
- **"CI-verifiable" is the incumbent's strongest column and it is half-false.**
  The check fires only for folds of documents that already existed on the base
  branch — the case where git history independently preserves the artifact and the
  record is *least* needed — and does not fire for intra-chain folds, the case the
  file's own rationale names. Any carrier comparison that credits the status quo
  with CI verification is scoring it on something it has not earned.
- **Removing the record is mechanically cheap but reopens a settled design
  decision.** `DESIGN-scope-consolidation-over-skipping.md:838-846` rejected
  Option D (make DESIGN absorbable into PLAN) because it "trades a durable audit
  trail for a shorter run," then records that the objection was "answered rather
  than overruled" — and the answer is the record. Delete it with nothing in its
  place and the answer is withdrawn while the decision it rescued stays shipped.
- **The design believes it is protected by three things that do not exist:** a
  checker that flags duplicates, a `[ -n "$want" ]` guard that skips
  unrecoverable hashes, and a merge driver that prevents PR conflicts on GitHub.
- **`Into: none` names a state the mechanism cannot produce.** The PLAN is never a
  fold's deletion target (`skills/scope/SKILL.md:807-809`), and the cascade that
  deletes it appends nothing. Either a row is missing from the cascade, or the
  column value should go.
- **The tombstone stub was rejected on a corpus-growth argument** — "it leaves one
  durable file per fold in the corpus that motivated this work"
  (`PRD-scope-artifact-persistence.md:563-566`) — and the same lens was never
  turned on the shared log, which leaves one durable *row* per fold forever. The
  reasoning to catch this was present in the chain and applied to exactly one
  candidate.

### Gaps

- Whether koto, niwa or tsuku actually have a `docs/folds.md` with rows.
  Unverifiable from this repo; low likelihood since shirabe itself has none, but
  it would flip the zero-migration-cost claim.
- The expected fold rate. Every growth number is extrapolated from chain-document
  counts, not from folds, because there are no folds. If most hops return `keep`,
  the file may sit near-empty indefinitely.
- Whether `/scope` can fold a document that already existed on `main`. If it
  cannot, the duplicate residual is unreachable and the concurrency question
  shrinks to "does GitHub block the merge button." The resume ladder suggests it
  can, but this was not confirmed.
- Whether the three CI defects are in scope here or a separate bug to file. They
  undercut the "checked mechanically, fails closed" claim the design rests on, so
  a redesign premised on the checker working would be premised on something false.

### Decisions

Recorded in `wip/explore_fold-record-scaling_decisions.md`.

### User Focus

The author chose **removal** over per-fold files, over keep-and-fix, and over
splitting the CI fixes out first. The narrowing question put to them was whether
anything still needs to distinguish "absorbed" from "never produced" on the
default branch for the one shape where no survivor remains; removal is the answer
that says no.

Two consequences the produced artifact must carry rather than gloss:

1. The case for removal is **not** growth or context cost. Both were measured and
   both fail — a fold is net-negative on tree size and nothing reads the record.
   The honest case is that the record was never argued for, has never been
   exercised, its verification is broken in four ways, its concurrency mitigation
   is inert on GitHub and absent for adopters, and its unique benefit is one fact
   in one fold shape.
2. `DESIGN-scope-consolidation-over-skipping.md:838-846` rescued a rejected
   decision by citing this record. The amendment there has to say something
   substantive about what now answers that objection — "no longer holds" is not
   available, because the decision it rescued stays shipped.

## Decision: Crystallize

## Accumulated Understanding

The fold record was never justified on its own terms. Its existence was assumed at
BRIEF altitude, the DESIGN only picked a surface for it, no human confirmed the
choice, and no reviewer ever read it. One day later it has zero rows.

Its stated benefits are weaker than advertised. The survivor's `absorbed:`
declaration already carries the path, the survivor, the verdict and the carry
outcome for every fold whose survivor stays on disk — enforced at error level, and
accumulating transitively across hops, which falsifies the design's own "the
record dies at the next hop" argument. Two of six columns are information-free by
construction (Verdict is a constant; Carried is all-`true` or the fold aborted).
The blob hash is the only column with a machine consumer, and it fingerprints
bytes that a plain clone cannot reach after the branch is deleted. The record's
one genuinely unique guarantee is narrow: *this topic's chain ran and folded to
nothing*, in the case where `/execute`'s cascade later deletes the last survivor.

Its stated costs are also not the ones the user named. Growth is a rounding error
and a fold is net-negative on tree size. Nothing reads the file into context today.
What is real is sharedness: on GitHub the `merge=union` mitigation does not apply
server-side, so parallel folds block the merge button anyway; adopters never
received the mitigation at all while inheriting the check; and the check itself
cannot fire on the intra-chain fold it was written for, has a dead guard that
turns a correct record red whenever a parallel PR merges first, picks the wrong
row on any two-hop chain, and implements none of the duplicate detection that
three documents credit it with.

So the honest statement of the situation is: an unexercised mechanism, assumed
rather than argued, whose verification is broken in four ways, whose concurrency
mitigation is inert on the platform it runs on and absent for adopters, and whose
unique benefit is one fact in one fold shape that a much cheaper carrier could
hold.

The decision that follows is not "remove or replace" in the abstract. It is:
**does anything still need to distinguish "absorbed" from "never produced" on the
default branch, for the one shape where no survivor remains?** If no — R20 is
amended away and this is a straight deletion, with the Option D answer in the
consolidation DESIGN needing a substantive replacement paragraph rather than a
"no longer holds." If yes — R20's own wording ("remains on the default branch,
present in a checkout, greppable") forecloses PR bodies, git history and chain
documents, and the carrier must be another durable file, at which point a per-fold
file is strictly better than a shared one on every axis the findings surfaced
except single-file readability.

Either way, the four CI defects are real and independent of the carrier question.
A carrier swap that does not fix them ships the same holes to a new destination.
