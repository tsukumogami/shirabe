# Lead: What else could carry the fact the fold record carries, and what does each option cost?

## Findings

### What the current carrier actually is, grounded

The record is `docs/folds.md`: a markdown table, one row per fold, appended by
`/scope` Phase 2 Stage 3 step 6 — "Append one row to `docs/folds.md` and
`git add` it — before anything is deleted, so a failed append aborts with
nothing lost" (`skills/scope/references/phases/phase-2-chain-orchestration.md:667-669`).
Step 7 then `git rm`s the absorbed artifact. The rollback table
(`phase-2-chain-orchestration.md:685-698`) makes the un-append explicit,
"because the row is forced to exist before the deletion."

Four properties are asserted about it, and all four check out in the tree:

- **Operation, never content** (`docs/folds.md:21-26`). "Any destination that
  preserved the content would assert, every time it fired, that the verdict was
  partly wrong." This is the constraint that eliminates most of the prior art
  below.
- **Append-only, union-merged** (`.gitattributes:3-11`, `docs/folds.md:49-58`).
- **Enumerated in the closed write-target set and carved out of the Phase 4
  sweep** (`skills/scope/SKILL.md:822-826`,
  `skills/scope/references/phases/phase-4-cleanup.md:101-111`).
- **Excluded from the fold preflight's own citation search**
  (`skills/scope/scripts/check-citations.sh:56,69`) — without that carve-out the
  record's own row, which names the path about to be deleted, would read as a
  dangling citation. Any replacement carrier that lives somewhere the preflight
  scans needs the same exemption.

The file currently holds **zero rows** (`docs/folds.md:62-63`; 2939 bytes, all
of it prose header). Every scaling claim on either side is therefore a
projection, not an observation.

### The load-bearing consumer, and it is smaller than it looks

Three consumers exist. Only one of them is a hard dependency.

1. **The reusable CI workflow** (`.github/workflows/validate-docs.yml:102-165`)
   — see the next subsection, which finds it verifies far less than advertised.
2. **`/execute`'s finalization guard**
   (`skills/execute/SKILL.md:590-600`): a chain that folded every artifact away
   has no anchor to seed on, and "distinguishing it from a genuinely
   unfinalized chain is what `docs/folds.md` is for." But the same passage says
   plainly: "The record is the evidence; it is not a seed, and **nothing here
   reads it to make a lifecycle decision**." The consumer is a human
   investigator, not a gate.
3. **A committed prose citation.** `skills/execute/scripts/run-cascade.sh:465`
   writes into ROADMAP documents on the default branch:
   `**Downstream:** _none (chain folded; see docs/folds.md)_`. Deleting the file
   dangles a pointer already written into durable artifacts.

The strongest argument for *some* carrier is not any of these. It is
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:838-846`.
Decision 8 originally rejected making DESIGN absorbable into PLAN on the ground
that the PLAN is deleted, so the move "loses the record of why the work
happened." The amendment overturns that rejection, and the reason it gives is
`docs/folds.md`: "the record of *what happened* is `docs/folds.md`, which
survives on the default branch whether or not any chain artifact does."
**Removing the record with nothing in its place reopens a rejected design
decision.** That is the real cost of option 1, and it is a design-integrity
cost rather than a tooling cost.

### The CI check does not fire for the case the file exists to serve

This is the most consequential thing I found, and it is verifiable.

The fold signature is computed from
`git diff --name-only --diff-filter=D "$BASE...$HEAD"`
(`validate-docs.yml:119-120`). That is a tree-to-tree comparison. A document
created in one commit of the chain and deleted in a later commit of the same
chain **does not appear in that diff at all** — it is absent from both
endpoints.

Verified in a throwaway repo (`/home/dgazineu/.claude/jobs/83dd7c3d/tmp/t1.sh`):
a branch that adds `docs/prds/PRD-x.md`, then adds `DESIGN-x.md` carrying
`absorbed: docs/prds/PRD-x.md` and `git rm`s the PRD, produces

```
--- diff --diff-filter=D BASE...HEAD (fold signature input):
--- (end; empty = signature never fires)
--- name-status BASE...HEAD:
A	docs/designs/DESIGN-x.md
```

`DELETED` is empty, so the check `exit 0`s at `validate-docs.yml:123-125`
before reaching anything else.

The blob assertion has the same hole from the other direction. `want=$(git
rev-parse "$BASE:$doc")` (`validate-docs.yml:146`) resolves only if the absorbed
doc existed on the base branch, and the hash comparison is guarded by
`if [ -n "$want" ]` (`:148`). So:

| Fold shape | Signature fires? | Row presence checked? | Blob hash checked? |
|---|---|---|---|
| Doc pre-existed the base branch, folded on this branch | yes | yes | yes |
| Doc created *and* folded inside the same chain PR | **no** | no | no |

The second row is precisely the case `docs/folds.md:14-19` names as the reason
the file exists: "a document created and folded away inside that chain never
existed on the default branch at all." **CI verifies the fold record for every
case except the one the fold record was written for.**

### The blob check has a dead guard that turns into a false CI failure

Separately from the signature hole, `validate-docs.yml:146-152` is unsound:

```sh
want=$(git rev-parse "$BASE:$doc" 2>/dev/null || true)
row=$(git show "$HEAD:docs/folds.md" | grep -F "$doc" | head -1)
if [ -n "$want" ] && ! printf '%s' "$row" | grep -qF "$want"; then
```

`git rev-parse <sha>:<missing-path>` writes its `fatal:` to stderr **and echoes
the unresolved argument to stdout**. Verified in isolation
(`/home/dgazineu/.claude/jobs/83dd7c3d/tmp/t5.sh`):

```
want=[74240459c19c79cb511bf37f7ad95800c0bff4cb:docs/prds/PRD-missing.md]
is want empty? NO -- guard is dead, want is the literal argument
```

So `[ -n "$want" ]` is never false. When the path does not resolve at `$BASE`,
`want` is the literal `<sha>:<path>` string, the `grep -qF` necessarily misses,
and the step emits `::error::… fold record hash does not match the pre-fold
blob` against a row that is perfectly correct. The intended "skip when we cannot
recover the pre-fold bytes" branch does not exist.

Reaching it requires `DELETED` to name a doc that `$BASE:$doc` cannot resolve,
and the two are computed against different endpoints: `DELETED` uses the
three-dot `"$BASE...$HEAD"` (merge-base vs head, `:119`) while `want` uses
`$BASE` directly (`:146`). Those disagree exactly when the base branch has
advanced past the merge base — which is what happens when **two agents fold the
same pre-existing document in parallel and one PR merges first**. The second
PR's `pull_request.base.sha` now points at a main where the doc is already gone,
the merge base still has it, so `DELETED` lists it and `want` does not resolve.
The parallel-agent contention this exploration is about therefore surfaces not
as a merge conflict but as a **spurious CI failure on a correct record**.
Reproduced end-to-end in `t4.sh`, which drives the checker verbatim.

Two corollaries matter for the options below. First, "the reusable workflow can
verify it" is a weaker discriminator between carriers than it appears, because
the incumbent only half-satisfies it and misfires on the other half. Second, the blob hash is verifiable
*against nothing* after merge: I confirmed the pre-fold blob becomes unreachable
once the branch is deleted and gc runs (`t1.sh` tail: `fatal: Not a valid object
name 55e52c07…`). On GitHub the objects survive via `refs/pull/N/head`, which is
retained, so a determined reader can still recover them — but that is a
GitHub-hosting property, not a git one, and the workflow is offered to adopters
generally (`docs/guides/doc-validation.md:54-67`).

### Union merge: verified, and better than the file's own description

Behaviour matrix run at `/home/dgazineu/.claude/jobs/83dd7c3d/tmp/t2.sh`:

| Scenario | Result |
|---|---|
| Plain merge, no union driver | **CONFLICT** |
| Rebase, no union driver | **CONFLICT** |
| Merge with union | clean, both rows |
| Rebase with union | clean, both rows |
| `merge --squash` with union | clean, both rows |
| Cherry-pick with union | clean, both rows |
| Byte-identical row on both branches, union | clean, **deduplicated to one row** |
| Union driver absent from the merge base (adopter-shaped) | **CONFLICT** |

Two corrections to the file's own account. `docs/folds.md:52-55` says "Union
merge resolves silently and cannot deduplicate, so a cross-branch duplicate is
possible." For *byte-identical* rows that is not what happens — ort's union
driver produced a single row. A duplicate therefore requires the two rows to
differ in at least one field (most plausibly `Date`, if two agents record the
same fold across a midnight boundary or in different timezones), which narrows
the residual considerably. And union preserves neither chronology nor a stable
order: the squash and cherry-pick cases both put the later row above the
earlier one. The record is a bag of rows, not a log — which forecloses any
truncation scheme that assumes the oldest rows sit at the top.

The practical upshot for the user's merge-conflict objection: **for git
mechanics, it is already solved in this repo.** The residual contention is not
git-level. It is two agents in the same worktree, and it is the ordering/dup
noise above.

### Growth, sized

A representative row — ISO date, two `docs/<type>/<TYPE>-<slug>.md` paths,
`absorb`, four `Section=true` pairs, a 40-char blob — runs about 270 bytes, and
up to roughly 450 at a terminal hop where `Carried` also lists inherited
contributions (`phase-2-chain-orchestration.md:630-635`: a survivor absorbing a
document that already carried two contributions confirms three). This
repository holds 43 briefs, 49 PRDs, 56 designs — call it ~50 chains of history.
Had every hop folded, that is ~150 rows, ~45 KB, ~12k tokens. That is the
whole-history ceiling, not an annual rate. Unbounded, yes; alarming at this
repo's velocity, not yet. The growth objection is a real property with a
currently-small magnitude, and honest framing should keep those separate.

---

### Option 1 — Nothing (delete the record)

What is lost is narrower than the file's prose implies but not nothing. The
`absorbed:` frontmatter already covers every non-terminal fold, so nothing is
lost there. What is lost is (a) the distinction between a fully-folded chain and
a chain that never ran, for a human investigating a finalization
(`skills/execute/SKILL.md:596-600`), and (b) the answer that the design
amendment gave to Decision 8's objection
(`DESIGN-scope-consolidation-over-skipping.md:838-846`). Who notices: a human
reading a ROADMAP whose `Downstream:` line points at a file that no longer
exists (`run-cascade.sh:465`), and anyone re-litigating whether DESIGN should be
absorbable into PLAN. CI notices nothing, because as shown above CI already
notices nothing in that case.

Cost to adopters: the reusable workflow's fold step is deleted, so pinned
consumers get a strictly smaller check. That is the only carrier option with a
*negative* adoption cost.

### Option 2 — Survivor frontmatter only

Already exists and is already validated: the `absorbed:` declaration plus the
pinned `## Status` line `Absorbed [<name>](<path>); carried in <Heading>.`
(`phase-2-chain-orchestration.md:649-652`), with `ABSORBED_ENTRY_PATTERN`
enforced in `crates/shirabe-validate/src/formats.rs` and the list accumulating
across hops (`:756-757`).

It covers every fold where a survivor persists on the default branch. It fails
in exactly two places, and they are the same place viewed twice:

- **The terminal fold.** The PLAN is the survivor at the DESIGN→PLAN hop
  (`skills/scope/SKILL.md:812-818`), and `/execute`'s cascade `git rm`s the PLAN
  at finalization (`skills/execute/SKILL.md:585-586`). The declaration dies with
  its carrier. `phase-2-chain-orchestration.md:728-748` is explicit that a chain
  folding to zero durable artifacts "is a reachable outcome rather than a
  defect," so this is a supported path, not a corner.
- **Cascade deletion generally.** Anything that later deletes a survivor takes
  every `absorbed:` entry it accumulated with it, including the inherited ones
  from earlier hops.

It also carries no blob hash and no date, so it is an assertion without a
verifiable fingerprint. Adopter cost: zero, it is already shipped.

### Option 3 — Commit trailer on the squash commit

Verified: trailers survive squash-merge intact and parse
(`t2.sh` §A — `git interpret-trailers --parse` returns
`Folded: docs/prds/PRD-x.md -> docs/designs/DESIGN-x.md` from the default-branch
commit). `git log --grep='^Folded:'` finds them, given the `fetch-depth: 0` the
workflow already sets (`validate-docs.yml:132-135`).

The disqualifying problem is verification timing. **The squash commit does not
exist until the merge button is pressed**, so a `pull_request`-triggered check
cannot assert the trailer will be present. GitHub's squash dialog lets whoever
merges edit the title and body, and repositories that default the squash body to
the PR description inherit every human edit made to that description. A
post-merge `push`-triggered check could detect a missing trailer, but only after
the fact, and the fix would be a follow-up commit that cannot retroactively
correct the merge commit. The record would be reliable exactly when nobody
edited it and unverifiable-in-advance always.

Adopter cost: a second workflow on `push`, plus a repo setting change, plus
depending on human merge discipline. It is also invisible to any reader who is
reading files rather than history.

### Option 4 — git notes on the merge commit

Verified fatal (`t2.sh` §B): a note added to HEAD, then `git clone`d — the clone
has `refs/heads/main`, `refs/remotes/origin/{HEAD,feat,main}` and **no
`refs/notes/*`**; `git notes show HEAD` in the clone returns `error: no note
found`. Notes require an explicit refspec to fetch and an explicit push to
publish, GitHub renders them nowhere, and they are separately mutable from the
commit they annotate, so they carry none of the append-only property the current
record has. Everything the option costs is paid before it delivers anything. The
honest evaluation the lead asked for is: this is not a candidate.

### Option 5 — Per-chain file retired when the chain finalizes

This inverts the requirement. The record's whole job is to outlive the chain —
`DESIGN-scope-consolidation-over-skipping.md:845-846`, "survives on the default
branch whether or not any chain artifact does." Retiring the file at
finalization destroys the evidence at precisely the moment `/execute`'s
fully-folded case needs it (`skills/execute/SKILL.md:592-600`), because
finalization *is* when the chain folds to nothing. If "retire" instead means
"fold its rows into a central index," the central index is the file we started
with, and the problem has moved by one hop and come back. It does solve
concurrency (one file per topic slug, so parallel chains never collide) — but
option 8 gets that same property without giving up durability.

### Option 6 — PR body, GitHub label, or PR comment

Not durable in the repository: none of these are in the tree, so a clone carries
none of them. All are freely editable after the fact by anyone with write
access, so the append-only property is gone. The reusable workflow *could* read
them (`pull_request` events carry the body; labels and comments need an API call
and `issues: read`, which the workflow does not currently request — it declares
`contents: read` only, `validate-docs.yml:118`). And they are unavailable to a
non-GitHub repo, which matters because the workflow is published as a pinned
reusable workflow for external adopters (`validate-docs.yml:2-13`). A PR body
also does not survive as a *file* through squash merge; only whatever text the
merger allowed into the commit message does, which collapses this into option 3
with an extra hop of indirection.

### Option 7 — Pruning, rotating, or archiving index

Rotation by year (`docs/folds/2026.md`) reduces the read cost of the current
file and bounds any single file's size, but it does not bound the set. Two
specific frictions:

- **The append-only assertion becomes conditional.** `validate-docs.yml:157-162`
  fails any PR whose `docs/folds.md` diff contains a removed row. Rotation is,
  by construction, a bulk row removal from one file and a bulk addition to
  another. It needs an exemption, and any exemption a rotation commit can claim
  is an exemption a row-deleting commit can also claim. The check's value is
  that it has no escape hatch.
- **Union merge does not order rows** (verified above), so "truncate the oldest
  N" cannot be implemented positionally. It would need a sort by the `Date`
  column, which is agent-supplied.

Pruning outright (drop rows older than N) contradicts the guarantee: the
question "was this artifact absorbed or never produced?" has no expiry, and a
reader hitting a pruned range gets exactly the ambiguity the file exists to
remove. Adopter cost: rotation needs a scheduled job or a manual ritual, which
is new machinery in every pinning repo.

### Option 8 — One file per fold

`docs/folds/<date>-<absorbed-slug>.md`, holding the same six fields as prose or
frontmatter. Path is composed from the validated topic slug and the type, so it
stays inside the closed write-target set that `skills/scope/SKILL.md:824` and
`phase-3-exit-finalization.md:318` require — the constant becomes a directory
prefix instead of a filename.

- **Concurrency:** structurally conflict-free. Two agents never write the same
  path, so no merge driver is needed at all, which also fixes the adopter-side
  failure in scenario 7 of the matrix (a repo without the `merge=union` line in
  `.gitattributes` conflicts today).
- **Context:** total bytes are unchanged, but they become lazily loadable. Every
  actual query against this data is keyed by the absorbed path — CI's
  `grep -qF "$doc"` (`validate-docs.yml:137`), `/execute`'s "did this chain
  fold?" — and both become a path existence check or a `grep -rl` over a
  directory rather than a whole-file read. This is the option that most directly
  answers the growth objection, because the objection is about read cost, not
  disk.
- **Append-only:** *stronger*, not weaker. "No file under `docs/folds/` was
  deleted or modified in this diff" is a simpler assertion than the current
  `grep -E '^-[^-]'` heuristic on a diff, and it has no false-positive surface
  around reflowed markdown.
- **Cost:** file count grows one per fold, and `ls docs/folds/` becomes a long
  listing. Discoverability drops for the "show me everything that ever folded"
  question, which today is one file open. `check-citations.sh` must exclude the
  whole directory rather than one path (`check-citations.sh:69`), a one-line
  change. It does not fix the CI hole in the intra-chain case — that hole is in
  the *signature*, not the carrier, and every option in this survey inherits it.

### Comparison table

| Option | Guarantee preserved | What it loses | CI-verifiable by the reusable workflow | Survives squash merge | Conflict-free under parallel agents | Bounded growth | Adopter cost |
|---|---|---|---|---|---|---|---|
| 1. Nothing | none | terminal-fold evidence; the answer to Decision 8's objection; dangles `run-cascade.sh:465` | n/a (step deleted) | n/a | yes | yes | negative — one less check |
| 2. Survivor frontmatter only | every fold with a surviving carrier | terminal fold; any fold whose survivor is later cascade-deleted; no blob, no date | already validated by `shirabe validate` | yes | yes (survivor is per-topic) | yes (bounded by live docs) | zero, already shipped |
| 3. Commit trailer | operation record, in history | **cannot be verified pre-merge**; editable in the merge dialog; invisible to file readers | only post-merge, after the fact | yes (verified) | yes | yes (history, not tree) | new push-triggered workflow + merge discipline |
| 4. git notes | nothing in practice | not fetched by clone (verified), separately mutable, rendered nowhere | no, without extra refspec plumbing | note is on a commit, so nominally yes | yes | yes | high, for no delivered guarantee |
| 5. Per-chain file, retired | nothing durable | deletes the evidence exactly when the fully-folded case needs it | during the chain only | yes, until retirement | yes | yes | moderate; re-creates the index problem |
| 6. PR body / label / comment | operation record, off-tree | not in the tree; freely editable; GitHub-only | needs `issues: read` the workflow lacks | no (only via option 3) | yes | yes | GitHub lock-in; breaks non-GitHub adopters |
| 7. Rotate / prune index | full record only if rotate, partial if prune | append-only assertion needs an exemption; union gives no row order to truncate by | yes, with a weakened check | yes | yes (union) | per-file yes, in aggregate no | rotation ritual in every pinning repo |
| 8. Per-fold file | same as today | wholesale readability; more files | yes, and more simply than today | yes | **structurally** — no merge driver needed | file count grows; per-read cost does not | one-line preflight exclusion; no `.gitattributes` requirement |
| Status quo | full | — | **only for folds whose doc pre-existed the base branch, and misfires when the base advances** | yes | via `merge=union`, verified | no | requires `merge=union` in `.gitattributes`, absent by default |

### Prior art, briefly

**ADR supersession** (Nygard / `adr-tools` / MADR): the superseded record is
kept on disk and its status flipped to "superseded by ADR-XXXX." This is the
closest cultural match and the **worst structural fit**, because keeping the
file is exactly the thing `docs/folds.md:21-26` forbids — a preserved absorbed
document asserts the fold verdict was partly wrong. The convention's own
rationale ("editing it loses the trail of what the team actually believed at the
time") does not transfer, because a fold is not a reversal of belief.

**Terraform `moved` blocks** are the sharpest analogue: a durable in-repo record
that "this thing became that thing," carrying no copy of the old thing, and
explicitly intended to be removable once the transition has propagated —
HashiCorp's guidance is to keep them a release cycle or until a major version
bump, while noting some teams keep them indefinitely as refactoring
documentation. The disanalogy is the expiry condition: a `moved` block can be
dropped once every consumer has applied, and a fold record has no equivalent
"everyone has seen it" moment.

**Changelog `Removed` sections** (Keep a Changelog) and **docs redirect maps**
(`redirects.yml`) are both accepted unbounded append-only files that nobody
rotates. They are direct precedent that the growth objection is survivable in
practice — but neither is machine-verified against a content hash, so neither
tests the harder half of this problem.

**In-place deprecation markers** (`#[deprecated]`, `DeprecationWarning`, K8s API
deprecation) all require the deprecated thing to still exist. Non-starters here
by the same argument as ADRs.

No prior art was found for the specific shape this needs: a durable, hash-keyed,
machine-verified record of a deletion whose subject is gone. The nearest is a
`git rm` plus a tombstone file, which is option 8.

## Implications

The comparison changes shape once the CI hole is admitted. "Verifiable by CI"
reads today as the incumbent's strongest column, and it is half-true: the check
fires for folds of documents that existed on the base branch — the case where
git history already preserves the artifact and the record is least needed — and
does not fire for intra-chain folds, the case the file's own rationale names.
Whatever the exploration converges on, **the signature at
`validate-docs.yml:119-120` and the dead guard at `:148` need fixing
independently of the carrier**. The signature fix is a different diff (a walk of
the branch's commits, or `git log --diff-filter=D $BASE..$HEAD`); the guard fix
is `git rev-parse --verify "$BASE:$doc^{blob}"` plus consistent endpoints. Both
are bugs in *how* the record is checked, not arguments about *where* it lives,
and a carrier swap that does not fix them ships the same holes to a new
destination.

The two objections that opened this exploration do not survive equally. The
merge-conflict objection is largely already answered by `merge=union` — verified
clean across merge, rebase, squash, and cherry-pick, and deduplicating on
identical rows. What survives is adopter-side (a repo pinning the workflow that
never adds the `.gitattributes` line conflicts on its first parallel fold, and
nothing tells it to), cosmetic (rows land out of chronological order), and the
false-failure path above — parallel contention does bite, but as a red check on
a correct record rather than as a merge conflict, which is a materially
different complaint from the one the objection states. The
growth objection is real in kind but currently ~12k tokens for this repo's
entire hypothetical history, and it is a *read* cost, which is what makes option
8 the one that addresses it directly rather than by deletion.

If the exploration leans toward removal, the sharpest question to answer is not
a tooling one. It is whether Decision 8 in
`DESIGN-scope-consolidation-over-skipping.md:838-846` still stands without the
record it cites as its justification — removal without an answer there reopens
the terminal-fold decision by a side door.

## Surprises

**The CI check cannot fire for the case the file was written for.** Verified
empirically: a document created and folded inside the same chain never appears
in `git diff --diff-filter=D BASE...HEAD`, so `DELETED` is empty and the step
exits 0 before checking anything. The blob assertion is separately guarded by
`[ -n "$want" ]`, which is only non-empty when the doc existed at base. This
inverts the coverage relative to the stated rationale.

**The blob check's skip-guard is dead code and produces false failures.**
`git rev-parse <sha>:<missing-path>` echoes its unresolved argument to stdout, so
`[ -n "$want" ]` (`validate-docs.yml:148`) is never false and a non-resolving
path yields `::error::` on a correct row. It triggers when `DELETED`
(merge-base-relative) and `want` (`$BASE`-relative) disagree — i.e. when a
parallel PR folding the same document merges first. Parallel-agent contention
shows up here as a red CI check, not a conflict.

**Union merge deduplicates byte-identical rows**, contradicting
`docs/folds.md:52-55` ("cannot deduplicate"). A duplicate requires the rows to
differ, which in practice means the `Date` field. The residual is narrower than
documented.

**Union merge does not order rows chronologically** — squash and cherry-pick
both placed the later row first. The record is a bag, not a log, which
independently forecloses positional truncation.

**The pre-fold blob is unreachable after the branch is deleted and gc runs**
(verified). The hash in the record is a fingerprint of bytes that exist nowhere
in a plain clone. On GitHub `refs/pull/N/head` retains them; that is a hosting
property the workflow's adopters do not all have.

**`docs/folds.md` is already cited from durable artifacts.**
`run-cascade.sh:465` writes `see docs/folds.md` into ROADMAP `Downstream:` lines
on the default branch. Any removal or rename has to reach that string.

**The file has zero rows.** Every argument on both sides is a projection.

## Open Questions

- Should the signature bug be treated as in-scope for this exploration or split
  out? It changes which carriers look attractive, because "CI can verify it" is
  currently doing work it has not earned.
- Does any adopter repository actually pin this workflow *and* run `/scope`? If
  the fold path is only exercised here, the adopter column across the whole
  table is hypothetical and the `.gitattributes` gap has never bitten.
- Is the blob hash worth keeping at all, given it is verified only in the case
  where git history independently preserves the artifact, and is unverifiable in
  a plain clone after merge? Dropping it shortens every row by 41 bytes and
  removes the strongest argument for a machine-readable table format.
- Who is the actual reader? Every identified consumer is either a human
  investigating a finalization or a CI grep keyed on a path. Neither needs a
  table; both would be served by a path lookup. If no consumer needs to read all
  folds at once, the single-file shape is unmotivated independent of scaling.
- What does "Into: `none` at the terminal hop" (`docs/folds.md:34`) describe
  concretely? The terminal hop's survivor is the PLAN, which `/execute` deletes
  later, so `none` at *fold* time was not reachable from anything I found in
  Phase 2. Worth confirming the column's stated vocabulary matches the writer.

## Summary

The fold record's strongest claimed property does not hold: the CI check keys on
`git diff --diff-filter=D BASE...HEAD`, which cannot see a document created and
folded inside the same chain — the exact case `docs/folds.md:14-19` names as the
reason the file exists — and its blob-hash skip-guard at `validate-docs.yml:148`
is dead code that emits a false failure whenever the base branch advances, so
the check is absent on the case it was written for and misfires on the rest. Of the eight carriers, git notes and PR
metadata are disqualified on durability, trailers on pre-merge unverifiability,
per-chain files on retiring the evidence when it is most needed, and rotation on
requiring an escape hatch in the append-only assertion; the survivor's
`absorbed:` frontmatter covers everything except the terminal fold, and a
per-fold file preserves the full guarantee while removing the merge driver
entirely. The biggest open question is whether removal is even available:
`DESIGN-scope-consolidation-over-skipping.md:838-846` cites this record as the
answer to the objection that blocked making DESIGN absorbable into PLAN, so
deleting it without a replacement reopens a settled design decision.
