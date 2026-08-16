# Lead: What does the fold record (`docs/folds.md`) uniquely prove that the surviving document's `absorbed:` frontmatter declaration and `## Status` absorption line do not?

## Findings

### 0. Baseline: the record is empty and the mechanism has never run

`docs/folds.md` is 63 lines, and the `## Record` table at lines 61-63 has a
header row and a separator row and **nothing else**. No fold has ever landed.
This is consistent with `DESIGN-scope-artifact-persistence.md:69-73` — "No BRIEF
has ever been deleted in this repository's history ... Every code path under the
verdict is untested." Everything below is therefore analysis of the specified
mechanism, not of observed behaviour.

### 1. What the survivor durably carries, and how hard it is enforced

Four traces land on the survivor at every absorb, per
`skills/scope/references/phases/phase-2-chain-orchestration.md:634-663` (step 5):

1. `absorbed:` frontmatter — a scalar or sequence of repo-relative paths.
2. A `## Status` line per entry in the pinned shape
   `Absorbed [<name>](<path>); carried in <Heading>.`
3. A contribution section (`## Absorbed Brief` / `Absorbed PRD` /
   `Absorbed Design`) immediately after `## Status`, in chain order.
4. An `upstream:` splice inheriting the absorbed document's parents.

Three of the four are enforced at **error level**:

- `crates/shirabe-validate/src/checks.rs:363-493` — `check_fc18`, six clauses:
  the declaration parses (clause 1), every entry matches
  `ABSORBED_ENTRY_PATTERN` and is not cross-repo (clauses 2, 6), every entry is
  strictly upstream of the carrier (clause 3), the contribution sections appear
  *contiguously and immediately after* `## Status` in chain order (clause 4),
  and a well-formed `## Status` absorption line exists per entry (clause 5, the
  regex at `checks.rs:355-357`).
- `crates/shirabe-validate/src/checks.rs:294-333` — `required_sections_for`
  splices the implied contribution headings after `Status`, so FC04 (presence)
  and FC15 (order) also see them.
- `crates/shirabe-validate/src/validate.rs:87-101, 114-137` — FC18 and FC19 are
  **not** in `is_intrinsic_notice` and are `AlwaysEnforced`, so they resolve to
  `Severity::Error` under both Draft and Ready posture. They fail the build.

The survivor is Added-or-Modified in the fold PR, so it lands in the workflow's
`FILES` set (`.github/workflows/validate-docs.yml:86-88`,
`--diff-filter=ACMR`) and FC18 actually runs on it.

`absorbed:` is deliberately invisible to path resolution:
`crates/shirabe-validate/src/upstream.rs:70` reads only the `upstream` field, so
the dangling-reference check never resolves an `absorbed:` target. That
satisfies PRD R21 (`docs/prds/PRD-scope-artifact-persistence.md:259-263`).

### 2. The declaration accumulates transitively — which falsifies the design's own reason for the record's location

`phase-2-chain-orchestration.md:748-755`: "What does ride along is the
`absorbed:` declaration, which accumulates: a survivor's list is its ancestor's
list plus the ancestor." Same rule at
`DESIGN-scope-artifact-persistence.md:279-284`: "The list is flat and complete."

This matters because the design killed the frontmatter-only alternative on
exactly this ground. `DESIGN-scope-artifact-persistence.md:164-169`:

> *The survivor's frontmatter*, alone or hybridized with an index, is genuinely
> immune to the cross-hop citation problem and was the closest loser. **It fails
> because the record dies with the document at the next hop**, and because the
> terminal fold has no survivor at all.

The first clause is **false against the shipped mechanism**. A BRIEF absorbed
into a PRD, then the PRD absorbed into a DESIGN, then the DESIGN into the PLAN,
leaves the PLAN declaring all three paths in `absorbed:`, all three `## Status`
lines, and all three contribution sections — every one of them FC18-enforced.
The record does not die at the next hop; it is carried forward by rule. The only
thing that kills it is the *last* survivor being deleted, which is the second
clause, not the first.

So one of the two arguments that placed the record in a shared durable file does
not hold. The other one does — see §4.

### 3. Fold shape by fold shape: what the row asserts and who else asserts it

The row's columns are at `docs/folds.md:29-38`: Date, Absorbed, Into, Verdict,
Carried, Blob.

**Shape A — absorb into a survivor that stays durable** (BRIEF→PRD, PRD→DESIGN,
and DESIGN→PLAN *when the PLAN merges separately and is never cascaded away*).

| Column | Another durable carrier? |
|---|---|
| Absorbed (path) | Yes — `absorbed:` frontmatter and the `## Status` line, both FC18-enforced. `git grep <dead-path>` finds the survivor. |
| Into (survivor) | Yes — it is the file carrying the declaration. |
| Verdict | Yes, vacuously. "always `absorb`; a `keep` writes no row" (`docs/folds.md:34`). A constant column carries zero bits; the presence of `absorbed:` asserts the same thing. |
| Carried | Derivable, and also vacuous. Every `carried: false` **aborts the absorb to `keep`** (`phase-2:632-637`), so every row that exists is all-`true` by construction. The itemization *set* is `formats.rs`'s required sections for the ancestor's type plus the contribution headings the ancestor inherited — and the inherited set is the survivor's own `absorbed:` list minus the ancestor, because the list is flat and complete. |
| Date | Not on the survivor. Available from the commit that added the `absorbed:` line — a squash commit, but one whose date and diff are on the default branch. |
| Blob | **Genuinely unique.** Nothing on the survivor holds a content hash of the deleted bytes. |

For shape A, a reader holding a dead path — the beneficiary PRD R20 names
(`PRD-scope-artifact-persistence.md:253-255`: "a reader holding a dead path who
greps for it needs the record in the working tree") — is served **completely by
the survivor**, in the working tree, greppable, with the added information of
*which section now carries the content*, which the row does not have.

The blob hash's residual value is narrow. It cannot be dereferenced from the
default branch: under the firing condition the absorbed document was produced by
this run, so its blob never existed on `main`. Recovering the bytes requires
fetching the PR's head ref from the forge. And the design explicitly rules out
content preservation as a purpose (`DESIGN-scope-artifact-persistence.md:326-328`:
"Any destination preserving absorbed content must assert, every time it fires,
that the verdict was partly wrong").

**Shape B — the terminal fold with `Into: none`.** This shape appears to be
**unreachable in the shipped mechanism**. Three independent constraints:

- `crates/shirabe-validate/src/formats.rs:184-186` —
  `ABSORBED_ENTRY_PATTERN` is
  `^docs/(briefs|prds|designs)/(BRIEF|PRD|DESIGN)-[a-z0-9-]+\.md$`. `docs/plans/`
  is not in it, so no document can ever declare it absorbed a PLAN.
- `phase-3-exit-finalization.md:312-314` and
  `DESIGN-scope-artifact-persistence.md:406-408` — the deletion set is
  BRIEF/PRD/DESIGN. "The PLAN is never a deletion target of a fold."
- `crates/shirabe-validate/src/formats.rs:164-167` — "`Absorbed Plan` is
  structurally unreachable, because the PLAN is terminal and nothing downstream
  survives to carry it."

`docs/folds.md:32` documents `Into` as "the survivor, or `none` at the terminal
hop", and `DESIGN-scope-artifact-persistence.md:310` repeats it. But
`DESIGN-...:460-462` says the opposite in the same document: "at the terminal hop
the PLAN is the *survivor* rather than a casualty — it is on disk when `/scope`
exits, and only the implementation cascade deletes it later." The `none` value
describes a state the mechanism cannot produce. It is a documentation artifact of
an earlier model.

**Shape C — the survivor is later deleted by `/execute`'s cascade.** This is the
real second shape, and it is where the record has a unique guarantee.
`skills/execute/SKILL.md:585-594`: post-finalization the cascade `git rm`s the
PLAN. If the DESIGN folded into the PLAN, then when the PLAN goes, so do the
`absorbed:` list, all three `## Status` lines, and all three contribution
sections. Nothing chain-shaped remains on the default branch.

What the record uniquely asserts here: **this topic ran a `/scope` chain and it
folded to nothing**, versus **this topic never ran**. On disk those are identical
(the design's own framing, `docs/folds.md:19-21`).

There *is* one other durable carrier for that fact, and it is worth naming:
`skills/execute/scripts/run-cascade.sh:465` rewrites the ROADMAP's downstream
line to `**Downstream:** _none (chain folded; see docs/folds.md)_`. That is a
durable, human-readable, default-branch assertion that this feature's chain
folded away. It is weaker than a row — it does not say what was absorbed into
what, or on what verdict — and it only exists when the topic came through a
ROADMAP feature. But it does mean shape C is not a total blank without the
record.

### 4. Who reads it, and to answer what

- **CI** reads it, but only to check itself.
  `.github/workflows/validate-docs.yml:102-164` is the sole mechanical reader.
  It asserts a row exists for a fold-signature deletion, that the row's hash
  matches the pre-fold blob, and that no row was removed or rewritten. Every one
  of those questions is *about the record*. Delete the record and the check
  deletes with it; nothing else in CI degrades.
- **`/execute` explicitly does not read it.** `skills/execute/SKILL.md:596-599`:
  "The record is the evidence; it is not a seed, and **nothing here reads it to
  make a lifecycle decision**." The finalization guard's fully-folded branch is
  reached by *absence of an anchor*, not by consulting the record.
- **`run-cascade.sh`** writes a pointer to it (line 465) and never reads it.
- **`check-citations.sh`** (lines 56, 69) excludes it from the citation search —
  it must not count as a citer of the doomed path. That is a write-side
  accommodation, not a read.
- **No skill or agent instruction anywhere loads it into context.** Grep across
  `skills/`, `crates/`, `.github/` finds writers, excluders and one self-checker.
- **A human auditor** is the only reader with a real question, and the question
  is: *"There is a squash commit for topic X on main and no artifact for it —
  did a chain run and fold, or did nothing happen?"* For shape A that is
  answerable from the survivor. For shape C it is answerable from the record, or
  partially from the ROADMAP line.

### 5. The claim "An absorbed document leaves no trace otherwise" is false as written

`docs/folds.md:17` states it flat. Tested against the mechanism:

- For every fold whose survivor is still on disk, the absorbed document leaves
  **four** traces on the survivor, three of them error-level enforced (§1), plus
  a fifth in the `upstream:` splice. The path is greppable in the working tree.
- The traces survive arbitrarily many further folds, because `absorbed:` is flat
  and complete (§2).
- The claim is true only for shape C — where the last survivor is itself deleted
  after `/scope` exits — and even there the ROADMAP carries a weaker durable
  signal.

The paragraph's reasoning ("this repository merges a whole `/scope` chain as one
squash commit, so a document created and folded away inside that chain never
existed on the default branch at all") is correct about the *absorbed document*
and irrelevant to the *declaration*, which is on the survivor and does reach the
default branch.

### 6. Surprise: the record's CI enforcement appears structurally dead on the primary path

`.github/workflows/validate-docs.yml:119-121`:

```
DELETED=$(git diff --name-only --diff-filter=D "$BASE...$HEAD" \
  | grep -E '^docs/(briefs|prds|designs)/(BRIEF|PRD|DESIGN)-[a-z0-9-]+\.md$' || true)
if [ -z "$DELETED" ]; then exit 0; fi
```

`git diff A...B` is a two-endpoint tree comparison (merge-base of A and B,
against B). A file that **does not exist at BASE and does not exist at HEAD** is
absent from that diff entirely — it is not reported as a deletion.

The firing condition guarantees exactly that state.
`DESIGN-scope-artifact-persistence.md:212-215`: "The judgment fires only when
**both endpoints of the edge the run drew were produced by this run**, read from
`chain_ran:` membership." The absorbed document was created by this `/scope` run
inside this PR's branch, so it is not in the base tree; the fold deleted it, so
it is not in the head tree. `DELETED` is empty and the step exits 0 without
checking anything.

The hash assertion has the same problem twice over — line 146,
`want=$(git rev-parse "$BASE:$doc" ...)` resolves against BASE, where the
document never existed, so `want` is empty and line 148's `[ -n "$want" ]` guard
skips the comparison even if `DELETED` were somehow non-empty.

Net effect: on the path the record exists for, the fold-record checker never
fires, while FC18 on the survivor fires hard. The asymmetry is the inverse of
`docs/folds.md:6`'s framing — "This file is written mechanically and **read by
CI**" — and of `DESIGN-...:478-489`'s account of the trigger. I did not find a
reachable configuration where `DELETED` is non-empty under the firing condition;
it would require the absorbed document to have merged to the base branch in an
earlier PR, which `chain_ran:` membership forbids.

This finding is one static reading of the shell and the diff semantics, not an
executed test — no fold has ever run, so there is no CI log to check against. It
should be confirmed with a constructed PR before it is treated as settled.

### 7. What the record is *not* trusted for, by the design's own statement

`DESIGN-scope-artifact-persistence.md:652-658`:

> It proves a row exists and its hash matches. It does not prove the row was
> machine-written: the file is hand-editable, and a forged row would pass. That
> is acceptable because the record is **an audit aid rather than an
> authorization, and nothing reads it to decide anything** — but it should not
> be described as proof that a fold was legitimate.

And `:487-489`: "It does not prove the fold was correct, that the contribution
carries, or that the row was written by the procedure rather than by hand."

## Implications

**The record's unique guarantee is one fact in one fold shape.** It is: *this
topic's chain ran and folded to nothing*, distinguishable from *this topic never
ran*, in the case where `/execute`'s cascade later deletes the last survivor.
Everything else the row asserts is either duplicated by the survivor's
FC18-enforced declaration (path, survivor, verdict), derivable from `formats.rs`
plus the survivor's flat `absorbed:` list (the carry itemization), vacuous by
construction (Verdict is a constant, Carried is all-`true` or the fold aborted),
or a content hash that cannot be dereferenced from the default branch.

**The scope brief's framing of "non-terminal versus terminal" should be replaced
with "survivor stays versus survivor is cascaded away."** The terminal *fold*
with `Into: none` is unreachable; the terminal *hop* (DESIGN→PLAN) produces a
perfectly ordinary survivor. The discriminating variable is `/execute`'s
cascade, which runs after `/scope` has exited, not anything the judgment does.

**Two of the design's load-bearing arguments for a shared durable file are
weaker than they read.** The "record dies at the next hop" argument is falsified
by the accumulation rule the same design adopted. The "terminal fold has no
survivor at all" argument is true only in the sense that the survivor dies
*later, elsewhere, at `/execute`'s hand* — which points at a much narrower
requirement than a repository-wide append-only file.

**This narrows the alternative-carrier space considerably.** Anything that
durably records "topic X's chain folded to nothing" at the moment `/execute`
deletes the last survivor would cover the entire unique guarantee. The cascade
already writes one such marker into the ROADMAP
(`run-cascade.sh:465`). A carrier sited at the cascade rather than at the
judgment would also sidestep the shared-write-point problem entirely, because
`/execute` runs one cascade per chain rather than up to three folds per chain.

**If the checker really is dead (§6), the cost/benefit shifts sharply.** The
file's stated justification is that it is machine-written and CI-verified. If CI
never verifies it on the live path, the record is an agent-written prose row with
no gate behind it, and the `merge=union` driver, the append-only assertion, and
the Phase 4 sweep carve-out are all machinery protecting an unverified artifact.

## Surprises

1. **`absorbed:` accumulates transitively**, which falsifies the "the record
   dies with the document at the next hop" half of the argument that placed the
   record in a shared file (`DESIGN-scope-artifact-persistence.md:167` versus
   `phase-2-chain-orchestration.md:748-755`).

2. **`Into: none` is unreachable.** `ABSORBED_ENTRY_PATTERN` excludes
   `docs/plans/`, the deletion set excludes the PLAN, and `formats.rs:164-167`
   calls `Absorbed Plan` "structurally unreachable." Yet
   `docs/folds.md:32` and `DESIGN-...:310` both document `none` as a live value.
   The same design contradicts itself at line 460.

3. **The fold-record CI check appears never to fire** on a `/scope` chain PR,
   because `git diff BASE...HEAD --diff-filter=D` cannot see a file that was
   created and deleted inside the range, and the firing condition guarantees the
   absorbed document was created inside the range (§6). Static reading; needs a
   constructed PR to confirm.

4. **Two of the six columns carry no information.** Verdict is always `absorb`
   (a `keep` writes no row, `docs/folds.md:34`), and Carried is always all-`true`
   (any `carried: false` aborts the absorb, `phase-2:632-637`).

5. **The cascade already writes a durable fold marker** into the ROADMAP
   (`run-cascade.sh:465`), so shape C is not the total blank the record's
   justification describes.

6. **The record is a reusable-workflow obligation for adopters.** The checker
   lives in `validate-docs.yml`, which downstream repos pin
   (`docs/guides/doc-validation.md:56-68`). Adopters inherit the file's contract
   — and, if §6 is wrong and the check does fire somewhere, its failure modes.

## Open Questions

1. **Is §6 correct?** This needs a constructed PR that creates and folds a BRIEF
   in one branch, to confirm the checker exits 0 without asserting anything. If
   it does fire in some configuration I did not find, most of the cost/benefit
   here changes.

2. **Is shape C the only case where the last survivor dies?** I traced
   `/execute`'s cascade `git rm` of the PLAN. Are there other paths that delete a
   surviving chain artifact — supersession via `shirabe transition`, manual
   housekeeping — and does the record cover those or only the cascade?

3. **Does anyone actually ask the shape-C question?** The record's unique
   guarantee is answering "did a chain run for topic X?" for a topic with no
   artifacts. Has that question ever been asked, by a human or otherwise? If it
   has not, the guarantee is real but unexercised, which is the user's actual
   concern. This needs human input, not more code reading.

4. **Is the blob hash wanted as a recovery handle?** It is unusable from the
   default branch but usable via the forge's PR refs. The design says the record
   is "of the operation, never the content"
   (`DESIGN-...:326-328`), so recovering deleted prose from the hash is arguably
   against the verdict's meaning. Whether the author wants that handle is a
   decision, not a finding.

5. **Should `Into: none` be deleted from the column spec?** If it is unreachable,
   it is a documented state the mechanism cannot produce, which is the same
   defect class the design criticized in the retired mapping table ("a check that
   can never fire teaches a later maintainer that the case is possible",
   `DESIGN-scope-consolidation-over-skipping.md:335-337`). This holds
   independently of whether the record survives.

## Summary

The record's only unique guarantee is that a chain ran and folded to nothing in
the one shape where `/execute`'s cascade later deletes the last survivor — for
every fold whose survivor stays on disk, the survivor's `absorbed:` declaration,
`## Status` line and contribution section carry the same facts, are FC18-enforced
at error level, accumulate transitively across hops, and are greppable in the
working tree, which falsifies both `docs/folds.md:17`'s "leaves no trace
otherwise" and the design's "the record dies with the document at the next hop."
Two of the six columns are information-free by construction, `Into: none` names a
state the mechanism cannot reach, and the fold-record CI check appears unable to
fire on a `/scope` chain PR at all because `git diff BASE...HEAD --diff-filter=D`
cannot see a file created and deleted inside the range. The biggest open question
is whether that CI reading is right — it needs a constructed PR to confirm, and
if it is, the file is an unverified agent-written row rather than the
mechanically-written CI-read artifact it declares itself to be.
