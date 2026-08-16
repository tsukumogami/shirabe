# Lead: Are unbounded growth and merge contention real problems for `docs/folds.md`, and at what scale do they bite?

Short version: growth is a rounding error and nothing reads the file, so
concern (1) is close to unreal. Concern (2) is real, but not in the shape
the design anticipated — the mitigation does not work where this repository
actually merges, and the checker that is supposed to backstop it does not
run at all in the primary case.

## Findings

### (a) Growth — a rounding error, and in aggregate the record makes the tree smaller

**Rows per chain: at most three.** The tactical chain is BRIEF → PRD →
DESIGN → PLAN, three hops. `skills/scope/SKILL.md:801-826` enumerates the
closed write-target set: the deletion set is exactly
`docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`,
`docs/designs/DESIGN-<topic>.md`, and **"The PLAN is never a deletion target
of a fold"** (`skills/scope/SKILL.md:807-809`). A `keep` verdict writes no
row (`docs/folds.md:32`, Verdict column: "always `absorb`; a `keep` writes
no row"). So a chain produces 0, 1, 2, or 3 rows.

**There is no extra terminal row.** The `Into` column is documented as "the
survivor, or `none` at the terminal hop" (`docs/folds.md:31`), which reads
as if a fourth row exists for the PLAN's own removal. It does not. At the
design→plan hop the PLAN *is* the survivor
(`skills/scope/SKILL.md:816-818`), and the implementation cascade deletes
it later, outside `/scope`. I grepped the cascade:
`skills/execute/scripts/run-cascade.sh` mentions folds exactly three times
(lines 441, 445, 465) and all three are comments or a printed pointer
string — `print "**Downstream:** _none (chain folded; see docs/folds.md)_"`.
**The cascade appends nothing.** `Into: none` is currently unreachable; see
Surprises.

**Row width, measured against this repo's real slugs.** I composed rows
from the actual required-section lists in
`crates/shirabe-validate/src/formats.rs` (BRIEF 457-463, PRD 303-312,
DESIGN 303-308) plus the inherited contributions the carry check requires
(`phase-2-chain-orchestration.md:625-634`: "A survivor absorbing a document
that already carried two contributions must confirm three things carried"),
and a real 40-hex blob hash:

```
slug=scope-artifact-persistence (len 26)  hop1=244  hop2=299  hop3=309  chain_total=855
slug=shirabe-pattern-v1-workflow-friction (len 36)  hop1=264  hop2=319  hop3=329  chain_total=915
slug=x (len 1)                            hop1=194  hop2=249  hop3=259  chain_total=705
```

So **~285 bytes per row, ~900 bytes for a fully-folded chain.** Rows widen
slightly down the chain because `Carried` accumulates inherited
contributions.

**Extrapolation** (worst case: every chain folds all three hops):

| Rate | per month | 1 year | 3 years | rows @ 3yr |
|---|---|---|---|---|
| 10 chains/mo | 8.6 KB | 103 KB | 308 KB | 1,080 |
| 50 chains/mo | 43 KB | 513 KB | 1.5 MB | 5,400 |

A realistic mean is well under 3 rows/chain, since any hop can return
`keep`; at 1.5 rows/chain halve every figure.

**Scale comparison, measured in this tree:**

- `docs/` total: **4,036,823 bytes** (173 markdown files)
- largest single doc: **112,291 bytes** (`DESIGN-skill-preflight-checks.md`)
- `CLAUDE.md`: 12,429 bytes; `AGENTS.md`: 5,394 bytes
- chain docs on disk today: 43 briefs, 49 PRDs, 56 designs, 1 plan
- `docs/folds.md` today: **2,939 bytes, and zero data rows** — the Record
  table is empty (the mechanism landed 2026-08-15 in `83d29e1`, one day ago)

At 10 chains/month, three years of records is 308 KB — under 8% of today's
`docs/` tree, and about 2.7x the single largest document already in it. At
the observed rate for this repo (~148 chain documents in 5 months, so
roughly 10 chains/month) that is the realistic ceiling.

**The decisive framing: a fold is net-negative on tree size.** The average
chain document here is ~27 KB. A fully-folded chain deletes a BRIEF, a PRD
and a DESIGN — roughly 80 KB — and adds ~900 bytes of record. **The record
costs about 1% of what the fold reclaims.** Every row that lands means the
tree got dramatically smaller. Framing the record as unbounded growth
inverts the sign of what the mechanism does.

Growth is not a real problem at any volume this repository or a plausible
adopter will see.

### (b) Context cost — currently zero, with one real path that would pay it

**Nothing reads the file.** Every reference in the skills is prose *about*
the file, not an instruction to read it:

| Site | What it does |
|---|---|
| `skills/scope/references/phases/phase-2-chain-orchestration.md:667-669` | "Append one row to `docs/folds.md` and `git add` it" — write only |
| `skills/scope/references/phases/phase-3-exit-finalization.md:318` | Write-target enumeration |
| `skills/scope/references/phases/phase-4-cleanup.md:101-110` | Carve-out: enumerated, never swept |
| `skills/scope/SKILL.md:824` | Write-target enumeration |
| `skills/execute/SKILL.md:597-600` | Explains what it is for, and says explicitly: **"The record is the evidence; it is not a seed, and nothing here reads it to make a lifecycle decision."** |
| `skills/execute/scripts/run-cascade.sh:465` | Prints a pointer string |

**The indirect paths, checked one by one:**

- **`shirabe validate $FILES` in CI.** `docs/folds.md` *is* in `$FILES` on
  every fold PR — the workflow passes every changed path
  (`.github/workflows/validate-docs.yml:88-97`). But `detect_format`
  (`crates/shirabe-validate/src/formats.rs:475-487`) matches on filename
  prefix and returns `None` for anything unrecognized (its own test asserts
  `detect_format("notes.md").is_none()`, line 512). `docs/guides/doc-validation.md:9-13`:
  "Everything else is silently skipped." No cost.
- **The whole-tree walkers.** `ARTIFACT_DIRS`
  (`crates/shirabe-validate/src/lifecycle.rs:318-325`) is
  `docs/{briefs,prds,designs,designs/current,plans,roadmaps}` — **`docs/`
  itself is not in the list**, so neither `build_doc_index` nor
  `scan_artifact_dirs` (`references.rs:223-255`) ever opens `docs/folds.md`.
  The lifecycle scan, the reference/target index, and the dangling-reference
  machinery are all blind to it. This matters more than it sounds: every row
  names deleted paths, so a reference scanner that *did* walk `docs/` would
  flag every row as a dangling citation.
- **Globs.** `parity-check.yml:25` documents `corpus-glob: "docs/**/*.md"`,
  which matches `docs/folds.md` — and the same workflow documents that
  "Files whose basename has no shirabe format prefix ... are silently
  skipped."
- **The pre-commit hook** (`shirabe install-hooks`) passes the staged set;
  same skip. `docs/guides/multi-consumer-cli-contract.md:172`.

**What `check-citations.sh --record` implies.** The flag *excludes* the
record from the fold's citation search
(`skills/scope/scripts/check-citations.sh:52,116-129,143-156`), and the
comment says why: the record "names a live survivor by path and would
otherwise make a chain's first fold refuse its second." That is the
important inference — **a bare `git grep` over this repository for a
document path DOES hit `docs/folds.md`**, because rows carry live survivor
paths in the `Into` column. Any agent or tool grepping for a doc path gets
record rows in its output, growing linearly with the record. The guard is
the one search that has been taught to exclude it; nothing else has.

**The one path that actually pays an O(n) cost.** Appending a row via the
`Edit` tool requires reading the file first — the harness rejects an Edit
on a file not previously Read. `phase-2-chain-orchestration.md:667-669`
does not specify a mechanism, and the workspace-level `CLAUDE.md` ("File
Operations": prefer Write/Edit over `cat`/`echo` redirects) actively pushes
an agent toward Edit. That instruction is workspace-level, not in shirabe's
own `CLAUDE.md` or `AGENTS.md` — I checked, neither carries it — so an
adopter's agent is unconstrained and this repo's is pushed the wrong way.
At the 3-year/10-chains-per-month figure that is a **308 KB / ~77k-token
read, paid up to three times per chain**, to append 285 bytes. This is the
only real form of the context concern, and it is fixable with one sentence
telling the appender to use `>>`.

Verdict on (b): the cost the user is worried about is **not currently
paid**, with the single exception above, which is a tooling choice rather
than a property of the design.

### (c) Concurrency — the mitigation does not apply where this repo merges

All results below are from throwaway repos; scripts are in
`/home/dgazineu/.claude/jobs/83dd7c3d/tmp/`.

**Union merge works locally, on every local operation I tested.** Baseline,
without the driver, two branches appending rows conflict:

```
############ 1. plain merge, NO union driver ############
CONFLICT (content): Merge conflict in docs/folds.md
<<<<<<< HEAD
| ... BRIEF-beta.md ... |
=======
| ... BRIEF-alpha.md ... |
>>>>>>> a
```

With `docs/folds.md merge=union` committed:

```
############ 2. rebase b onto a, WITH union ############   rebase exit=0  -> both rows, base-first
############ 3. rebase b onto a, NO union ############     rebase exit=1  -> CONFLICT
############ 4. merge --squash a into b, WITH union ####   squash exit=0  -> both rows
############ 5. cherry-pick a onto b, WITH union #######   cherry exit=0  -> both rows
```

So rebase, local squash-merge and cherry-pick all honor the driver. The
attribute must be reachable from the working tree: with `.gitattributes`
absent, the same merge conflicts (`############ 7`, output above).

**But GitHub's server-side merge does not honor it, and that is where this
repository merges.** I could not test github.com from here, so this rests
on GitHub's own statements rather than my own experiment. GitHub support,
in the still-open community discussion:

> "GitHub doesn't consider user-defined .gitattributes files (normally, we
> use our own .gitattributes file which you can't change)."

and the only workaround offered is "to merge pull requests in your local
clone (and not via the web UI)". The request is unimplemented as of 2026.
Kubernetes removed its own union-merge attribute for exactly this reason
(kubernetes/kubernetes#70576, titled "remove the union merge driver since
GitHub doesn't support it"). GitLab implemented it; GitHub did not.

What this means concretely for a repository that squash-merges whole
`/scope` chains: **`merge=union` does not stop GitHub from marking a PR
conflicted.** Two open PRs each appending a row will still show "This
branch has conflicts that must be resolved," and the merge button will
still be blocked. The driver's actual value is narrower than the design
implies: it makes the *local* fix — `git rebase main` — resolve silently
instead of requiring a hand edit. That is worth something, but it is not
"two branches each appending a row merge cleanly instead of conflicting"
(`docs/folds.md:51-52`), which is what the file claims about itself.

**Second branch rebasing onto the first.** Clean, and correctly ordered —
the base row first, then the rebased branch's:

```
### PR B after rebase:
| 2026-08-16 | docs/briefs/BRIEF-alpha.md | ... | (from main)
| 2026-08-16 | docs/briefs/BRIEF-beta.md  | ... | (this branch)
### CI additions-only assertion on the rebased PR B:  -> additions only (pass)
```

**The concrete duplicate sequence — and it is easier to reach than the
design suggests.** Two agents fold the *same* pre-existing document in
parallel, changing nothing else about it. Both `git rm` it (delete/delete
is not a conflict), both append the identical `absorbed:` line to the same
survivor (an identical change is not a conflict), and the two record rows
differ only in the `Date` column, so union keeps both:

```
--- PR B rebases onto main (nothing else differs between the branches) ---
rebase exit=0
| 2026-08-16 | docs/briefs/BRIEF-topic.md | docs/prds/PRD-topic.md | absorb | ... | be1723... |
| 2026-08-17 | docs/briefs/BRIEF-topic.md | docs/prds/PRD-topic.md | absorb | ... | be1723... |
rows naming BRIEF-topic: 2
--- CI on PR B: ---
no chain-doc deletions; check exits 0
```

**The checker does not catch it.** Reading
`.github/workflows/validate-docs.yml:123-172`, it makes exactly three
assertions — a row exists for each folded doc, the row's blob hash matches
the pre-fold blob, and the record diff is additions-only. **There is no
duplicate detection of any kind.** `docs/folds.md:52-55`, `.gitattributes:6-8`
and `DESIGN-scope-artifact-persistence.md:316-318` all assert "the checker
flags it." It does not. That claim is stated in three places and implemented
in none.

**Worse: the checker does not run at all in the primary case.** The trigger
is `git diff --name-only --diff-filter=D "$BASE...$HEAD"`. A file created
*and* deleted between the two endpoints appears in neither, so the diff
reports no deletion. But the design's own premise
(`DESIGN-scope-artifact-persistence.md`, "Why this exists", and
`docs/folds.md:16-19`) is that "this repository merges a whole `/scope`
chain as one squash commit, so a document created and folded away inside
that chain never existed on the default branch at all." I built exactly
that PR — a chain drafted and folded in one branch, with a correct record —
and ran the shipped checker verbatim:

```
############ 1. ordinary same-PR /scope chain fold ############
pre-fold blob (computed at fold time, as the skill says) = 9eae95dd...
--- record is correct by construction; now run CI: ---
no chain-doc deletions; check exits 0
```

The record is entirely unverified for the case it was built for.

**A latent false positive in the same step.** When the deleted doc *is*
absent from `$BASE` (the un-rebased concurrent-fold case), the guard meant
to skip the hash check is dead:

```
want=$(git rev-parse "$BASE:$doc" 2>/dev/null || true)
```

`git rev-parse` on an unresolvable `<rev>:<path>` prints **the literal
argument to stdout** and exits 128 (stderr carries the `fatal:`). Measured:

```
stdout captured = [2c1171bc...:docs/missing.md]
length = 56
raw exit=128
```

So `want` is non-empty garbage, `[ -n "$want" ]` passes, and the comparison
against the row fails:

```
want = [d594fa34...:docs/briefs/BRIEF-topic.md]     <-- note: not a hash
::error::docs/briefs/BRIEF-topic.md: fold record hash does not match the pre-fold blob (d594fa34...:docs/briefs/BRIEF-topic.md)
```

The row was correct. The check fires anyway, with a message naming a
path-spec where a hash should be. It happens to fail the one un-rebased
duplicate case — accidentally, and for the wrong stated reason.

Related, smaller: the presence assertion is `grep -qF "$doc"`, which also
matches the `Into` column of an earlier row. At the second hop of a chain
whose first fold is already on `main`, `grep -F "$doc" | head -1` picks the
*previous* row, whose blob is the previous document's.

**Union merge does not break the additions-only assertion.** I tried to
make it. The check uses three-dot (`$BASE...$HEAD`, merge-base relative),
and that is what saves it:

```
### CI additions-only assertion on the union-merged PR B:   -> additions only (pass)
### main advanced; assertion re-run on the stale union-merged PR B:
  -> additions only (pass)
### and with the two-dot diff the check does NOT use:
-| 2026-08-17 | docs/briefs/BRIEF-gamma.md | ... |
  -> REWRITE DETECTED (two-dot)
```

The three-dot form is load-bearing and nothing in the workflow says so. A
maintainer "simplifying" it to two dots would turn every stale branch into
a spurious append-only violation.

**One genuine mitigation the design under-claims.** Two branches appending
a *byte-identical* row do not duplicate — git treats the same change on
both sides as non-conflicting and takes it once:

```
############ 6. IDENTICAL row appended on both branches, WITH union ############
merge exit=0
| 2026-08-16 | docs/briefs/BRIEF-alpha.md | ... | aaaa111 |     (one row, not two)
```

Duplication therefore requires the rows to *differ*. Given the blob hash is
identical for the same pre-fold bytes and everything else is a closed
vocabulary, the only realistic differing field is `Date` — a fold recorded
on two different days. That narrows the residual to "the same document
folded on two branches across a date boundary," which is a much smaller
target than "any concurrent fold."

### (d) Adopters — they get the check without the mitigation

This is the sharpest form of the concern, and it holds.

`.gitattributes` appears in exactly two places in the entire repository
outside design documents: the record file's own prose (`docs/folds.md:51`)
and the design's component table
(`DESIGN-scope-artifact-persistence.md:442`). I grepped every `.md`,
`.json`, `.yml`, `.sh` and `.rs`.

- **The plugin manifest ships skills only.** `.claude-plugin/plugin.json`
  declares `"skills": "./skills/"` and nothing else. `.gitattributes` is a
  repository file, not a plugin asset. An adopter installing shirabe gets
  `/scope` — and therefore folds, and therefore rows — and no merge
  attribute.
- **The reusable workflow runs the check in the caller's repo.** The
  "Verify the fold record" step operates on the *caller* checkout
  (`.github/workflows/validate-docs.yml:99-172`). An adopter pinning
  `uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v0.6.0`
  (README.md:245-250) inherits the fold-record assertions in full.
- **No adopter-facing documentation mentions it.**
  `docs/guides/doc-validation.md:53-68` documents the fold-record check for
  adopters in five paragraphs and never mentions `.gitattributes`,
  `merge=union`, or concurrency. `README.md:224-278` covers the reusable
  workflow, custom statuses, visibility and local install, and does not
  mention it either.
- **No bootstrap path adds it.** `install.sh` installs the binary.
  `shirabe install-hooks` — the one existing scaffold-into-the-adopter's-repo
  command (`docs/guides/multi-consumer-cli-contract.md:174-180`) — writes a
  pre-commit hook and nothing else. It is the natural home for this and does
  not do it.

So an adopting repository gets: a skill that appends to a shared file, CI
that asserts things about that file, and zero conflict mitigation. Given
finding (c) — that the mitigation is largely inert on github.com anyway —
the adopter is roughly where shirabe itself is. The gap is real but it is
smaller than it looks, because what they are missing does not work well
where it matters.

## Implications

1. **Drop growth as a driver.** 285 bytes a row, ~900 a chain, ~1% of what
   the fold reclaims. Any design work justified by file size is solving a
   problem that does not exist. If the exploration wants a size story, the
   honest one is that folding shrinks the tree and the record is the receipt.
2. **Context cost is a tooling fix, not a design change.** One sentence in
   `phase-2-chain-orchestration.md` step 6 — append with `>>`, do not Edit —
   removes the only O(n) read in the system. If the exploration wants a
   durable guarantee rather than an instruction, that argues for a
   `shirabe fold record` subcommand that owns the append, which would also
   give the "written mechanically" claim in `docs/folds.md:6` something
   behind it (today the row is composed by an agent following prose).
3. **The concurrency mitigation needs restating, because as written it is
   false on this platform.** `docs/folds.md:50-52` tells a reader that
   concurrent folds "merge cleanly instead of conflicting." On github.com
   they do not; the PR is marked conflicted and a human or agent rebases.
   Whatever else this exploration decides, that sentence should say what
   union merge actually buys: a trivial local rebase instead of a manual
   resolution.
4. **The checker needs three fixes independent of any redesign** — it does
   not fire on same-PR chains, it has a dead `-n "$want"` guard that
   produces false errors, and it does not implement the duplicate detection
   that three separate documents claim it implements. The first is the
   serious one: the record's integrity guarantee is currently unenforced in
   the normal case.
5. **If the design keeps a shared append-only file, the adopter story needs
   an owner.** Either the merge attribute travels with the skill (a
   `shirabe init` / `install-hooks` side effect), or the adopter
   documentation states the concurrency property plainly, or the record
   moves to a shape with no shared file. Choosing among those is the
   decision this exploration is actually for.
6. **A per-fold file (`docs/folds/<date>-<slug>.md`) would dissolve (c) and
   (d) entirely** — no shared file, no merge driver, no adopter gap, no
   duplicate residual — at the cost of directory clutter and a reader who
   must glob rather than grep one file. I am not recommending it here; I am
   noting that the strongest findings all point at *sharedness*, not at
   *size*, and sharedness is the property a per-fold file removes.

## Surprises

- **The record has never had a row.** The Record table in `docs/folds.md`
  is empty; the mechanism landed 2026-08-15 in `83d29e1`, one day before
  this investigation. Every concern here is prospective. Nothing has been
  observed to be a problem because nothing has happened yet.
- **The CI fold-record check never fires on the case the design was written
  for.** A document created and folded inside one PR produces no deletion
  in a `BASE...HEAD` diff. This is the design's own stated premise for why
  the record exists, and it is exactly the input the checker cannot see.
- **`git rev-parse <rev>:<missing-path>` writes the literal argument to
  stdout and exits 128.** The workflow's `|| true` swallows the exit code
  and keeps the garbage, defeating the `[ -n "$want" ]` guard. A one-line
  bug in a step nobody has run yet.
- **"The checker flags it" is asserted three times and implemented zero
  times** — `docs/folds.md:52-55`, `.gitattributes:6-8`,
  `DESIGN-scope-artifact-persistence.md:316-318`. The duplicate residual is
  therefore larger than the design believes, because the design believes
  something catches it.
- **Union merge deduplicates byte-identical rows for free.** Git treats the
  same change on both sides as non-conflicting. The design says union
  "cannot deduplicate," which is true of the driver in general and false of
  the specific case that matters most.
- **`Into: none` is unreachable.** The column is documented
  (`docs/folds.md:31`) and the design leans on it ("the terminal fold has
  no survivor at all", line 167), but the PLAN is never a fold's deletion
  target and the cascade that deletes it appends nothing. Either a row is
  missing from the cascade or the column value should go.
- **The three-dot diff is load-bearing and undocumented.** Two-dot turns
  every stale branch into an append-only violation. I demonstrated it.
- **`check-citations.sh` excluding the record is evidence that ordinary
  greps hit it.** The record names live survivor paths, so it participates
  in exactly the path searches agents run. That is the growth-times-context
  interaction, and only one caller has been taught about it.

## Open Questions

- Is the same-PR blind spot in the CI checker in scope for this
  exploration, or a separate bug to file? It undercuts the "checked
  mechanically and fails closed" claim the design rests on, so a redesign
  premised on the checker working would be premised on something false.
- Does this repository (or any adopter) ever fold a document that already
  existed on `main`? If never, the duplicate residual is unreachable and
  the whole concurrency question shrinks to "does GitHub block the merge
  button." Someone should confirm whether `/scope` can run against a
  pre-existing BRIEF/PRD — the resume ladder suggests yes.
- Is `merge=union` worth keeping at all given (c)? It costs nothing and
  helps the local rebase, but it makes a false promise in three documents.
  Keeping the attribute and rewriting the prose is one answer; removing it
  as Kubernetes did is another.
- Should the append become a `shirabe` subcommand? That would settle
  "written mechanically," remove the Edit-tool read, allow real duplicate
  rejection at write time, and give the adopter something to install — but
  it is new surface area and belongs to whoever owns the CLI boundary.
- What is the actual expected fold rate? Every growth number here is
  extrapolated from chain-document counts, not from folds, because there
  are no folds. If most hops return `keep`, the file may sit near empty
  indefinitely.

## Summary

Growth is not real — a row is ~285 bytes, a fully-folded chain ~900, about
1% of the ~80 KB of documents that same fold deletes — and nothing reads
the file today, so the context cost is unpaid except where an agent uses the
Edit tool to append and must read the whole record first. Contention is
real but misdiagnosed: `merge=union` works on every local operation I tested
yet GitHub does not honor `.gitattributes` server-side, so concurrent folds
still block the merge button on the squash-merge flow this repo uses, and
adopters inherit the CI check with no merge attribute at all. The biggest
open question is whether the checker itself is trustworthy — it does not run
on a chain created and folded in one PR, which is the exact case the record
was built for, and the duplicate detection three documents credit it with
does not exist.
