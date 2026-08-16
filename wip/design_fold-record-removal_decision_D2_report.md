# Decision D2: the roadmap downstream cell

## Current behavior

Three shapes reach a reader. Only two of them are written by the cascade.

**Shape 1 — a DESIGN survived.** `skills/execute/scripts/run-cascade.sh:463`

```awk
print "**Downstream:** " ref " (Current)"
```

`ref` is `basename "$CASCADE_DESIGN_PATH"` (set at `run-cascade.sh:452-455` from
the finalize-chain report's `new_path`). The emitted line is a **bare basename
plus a terminal-state parenthetical** — `**Downstream:** DESIGN-cascade-test-short.md
(Current)` — never a repo-relative path. The committed corpus matches:
`crates/shirabe/tests/fixtures/golden/corpus/real/ROADMAP-strategic-pipeline.md:101`
and eight sibling lines carry `DESIGN-<slug>.md (Current)` or
`PRD-<slug>.md (Done), DESIGN-<slug>.md (Current)`.

**Shape 2 — the chain folded to nothing.** `run-cascade.sh:465`

```awk
print "**Downstream:** _none (chain folded; see docs/folds.md)_"
```

This is the branch under decision. It fires when `CASCADE_DESIGN_PATH` is empty —
`/scope`'s consolidation judgment absorbed the DESIGN into the PLAN, and this same
cascade then `git rm`s the PLAN, so there is no surviving name to write.

**Shape 3 — the chain never ran.** The cascade never touches this cell; it is
author-written at roadmap-drafting time and stays as written. The committed corpus
shows one dominant form, `**Downstream:** Needs PRD`
(`ROADMAP-strategic-pipeline.md:216, 264, 281, 298, 327` — five occurrences). The
test and eval fixtures show two more: an in-flight cell naming the PLAN
(`**Downstream:** PLAN-cascade-test-short.md`, `run-cascade_test.sh:71`) and the
literal `closed` (`run-cascade_test.sh:81`).

So the three states a reader has to tell apart are `Needs PRD` (never ran),
`DESIGN-x.md (Current)` (ran, something survived), and whatever this decision
writes (ran, nothing survived). They are already lexically far apart; the folded
string does not have to work hard to stay distinct.

**One structural finding worth carrying into the design.** The
`**Downstream:**` field is **not in the ROADMAP format contract**.
`skills/roadmap/references/roadmap-format.md:149-167` ("Per-Feature Format")
documents `**Needs:**`, `**Dependencies:**`, and `**Status:**` — and nothing else.
The only `Downstream` in that reference is line 31, naming
`Feature | Status | Downstream Artifact` as one of the *divergent committed table
shapes* that `references/issues-table.md:196` is migrating away from. The prose
field the cascade rewrites is a de-facto convention with no written contract and
no validator, which is precisely why it was able to grow a pointer to
`docs/folds.md` and hold it silently.

## Test coverage

**One scenario, one assertion, and it is a negative regex.**
`skills/execute/scripts/run-cascade_test.sh:423-480`,
`scenario_plan_roadmap_no_design`. The assertion is lines 465-474:

```bash
downstream=$(grep -m1 '^\*\*Downstream:\*\*' \
    "$repo/docs/roadmaps/ROADMAP-cascade-test.md" || true)

if printf '%s' "$downstream" | grep -qE 'PLAN-|DESIGN-'; then
    fail "$scenario: roadmap Downstream points at a deleted artifact: $downstream"
    ok=false
else
    pass "$scenario: roadmap Downstream points at no deleted artifact"
fi
```

Three consequences:

1. **Nothing asserts on `folds.md`.** Dropping the pointer breaks no assertion.
   Baseline, run just now: `bash skills/execute/scripts/run-cascade_test.sh` →
   `=== Results: 19 passed, 0 failed ===`.
2. **Any wording that names the folded artifact fails this test.** The regex is
   `PLAN-|DESIGN-`. `_none (DESIGN-foo.md absorbed into the PLAN)_` matches and
   fails. Adopting the naming family therefore also means deciding to weaken the
   one guard that exists here — and that guard is the whole reason the folded
   branch was written (see the comment block at `run-cascade.sh:438-451`).
3. **`grep -m1` reads the first `**Downstream:**` line in the file**, which is
   Feature 1's — correct only because the fixture's short plan maps to Feature 1.
   A positional coincidence, not a property. Harmless for a wording change; worth
   knowing before anyone reorders that fixture.

**The evals assert only on the survivor branch.** `skills/execute/evals/evals.json`
lines 148, 318, 347, 374 all read "Downstream references the DESIGN doc at
Current." No eval mentions the folded string or `folds.md`. Nothing outside
`run-cascade_test.sh` observes this branch.

## The cell's purpose and lifetime

**Purpose, mechanical.** The cascade reads this field to find its work.
`run-cascade.sh:401`:

```bash
downstream_line=$(grep -n -F "$plan_slug" "$path" | grep -i "Downstream:" | head -1 | cut -d: -f1)
```

It locates the feature entry by finding a `Downstream:` line containing the plan
slug, then walks up to the enclosing `### ` heading. So the cell is a lookup key
*before* the rewrite. After the rewrite it is no longer a key for anything — no
later run resolves it.

**Purpose, human.** The Features section and its per-feature statuses are the
roadmap's progress ledger (`roadmap-format.md:144-147`: "This is the ledger: it,
and the per-feature statuses it mirrors, are the only record of how far along the
strategy's execution is"). A reader scanning that ledger uses the Downstream cell
to answer "and where did this feature's work go?"

**No validator reads it.** FC05/FC06 validate the Implementation Issues *table*,
not this prose field (`roadmap-format.md:381-386`). FC20, the stale-prose-reference
check, cannot see it either: `crates/shirabe-validate/src/references.rs:105-118`
resolves only paths written `./`/`../` or rooted in one of `ARTIFACT_DIRS`, and
drops everything else because "a base the check cannot see … manufactures
findings." A bare `DESIGN-foo.md` has no directory, so it is dropped — which is
why the committed corpus of bare-basename Downstream cells validates clean, and
why `docs/folds.md` (not artifact-shaped in the first place) was never checked.
The current dangling pointer is invisible to every automated reader in the repo.

**Lifetime.** Short, and on the common case zero.

`handle_roadmap` rewrites Status and Downstream (lines 426-470), *then* checks
whether every feature is Done (475-488) and, if so, calls
`handle_roadmap_deletion`, which flips the ROADMAP to Done and `git rm`s it
(`run-cascade.sh:570-577`) — in the same staged commit set. The `git add` that
would stage the rewrite is guarded by `[[ -f "$path" ]]` (line 495) and no-ops once
the file is gone.

So:

- **One-feature roadmap:** the folded cell is written and the file deleted inside
  one commit. The string never appears in any tree state that merges. It exists on
  disk for the duration of one bash function.
- **Multi-feature roadmap:** the cell lives from this feature's finalization until
  the last feature's finalization deletes the roadmap. Its readers in that window
  are humans scanning the ledger, plus the cascade greping *other* features' plan
  slugs (which will not match this rewritten line).

That window is the entire audience. Whatever this cell says is gone by the time
anyone asks the archaeological question, so it cannot be the durable answer to
"did this chain fold or never run?" — that is AC11's job, in
`skills/execute/SKILL.md:591-600`.

## Options

Emission constraints that bound all of them: the string is a literal inside an
awk `print`, inside a single-quoted awk program, inside bash. No `'` (terminates
the bash quoting), no unescaped `"`, one line only. A literal `|` is safe *today*
because this is a prose line rather than a table row, but it would break the day
features migrate into the `Feature | Status | Downstream Artifact` table shape —
avoid it. `_..._` italics is the established form for this branch. Em dashes,
semicolons, and parentheses are all free.

### Option A — minimal: drop only the pointer

**Literal:** `**Downstream:** _none (chain folded)_`

- **Tells a reader:** this feature's chain ran to completion and every artifact in
  it was absorbed, so there is nothing durable to point at. Read with the
  `**Status:** Done` set two lines up in the same rewrite, it says "finished, and
  deliberately left no document."
- **Does NOT tell:** what was absorbed into what, where the prose went, which PR
  carried it, or whether that was the right call.
- **AC12 part 1 (no pointer to the record):** passes.
- **AC12 part 2 (folded ≠ never ran):** passes. "chain folded" is not a phrase any
  author writes by hand into a never-ran cell; the never-ran forms in the corpus
  are `Needs PRD` and a named in-flight PLAN.
- **Test:** passes unchanged, no `PLAN-`/`DESIGN-`. **R8** ("replaced with a claim
  that holds without it, rather than deleted"): passes — "chain folded" is the
  claim, and it holds with no record behind it.
- **Cost:** a five-word deletion. Nothing else in the repo moves.

### Option B — name what was folded

**Literal (illustrative):** `**Downstream:** _none (chain folded into PLAN-<slug>.md, deleted)_`

- **Tells:** which document was the last survivor before deletion, giving a
  git-archaeology handle.
- **Does NOT tell:** where that document's content ended up (nowhere — it was
  deleted), or how to recover it without a git log.
- **AC12 part 1:** passes. **Part 2:** passes, more informatively than A.
- **Two hard problems.** First, feasibility: at line 452 the only artifact name in
  scope is `CASCADE_DESIGN_PATH`, which is empty *by definition* in this branch.
  The PLAN slug is available (`$plan_slug`, arg 3) — but that is the file this same
  cascade just `git rm`'d, so the cell would name a nonexistent document. That is
  the exact defect `scenario_plan_roadmap_no_design` was written to catch, restated
  in different words. Second, it **fails the existing test's `PLAN-|DESIGN-`
  regex**, so shipping it requires deliberately loosening that guard.
- Naming the *absorbed* DESIGN instead of the PLAN is not available either: the
  fold happened in `/scope` Phase 2 (`phase-2-chain-orchestration.md:655-678`), in
  a different process, and the cascade is never told what was absorbed.

### Option C — point at the merged PR or squash commit

**Literal (illustrative):** `**Downstream:** _none (chain folded; see PR #<n>)_`

- **Tells:** where to go read the diff that contains both the fold and the
  deletion.
- **Does NOT tell:** anything, if the lookup is unavailable.
- **AC12 part 1:** passes on the letter. **Part 2:** passes when the number
  resolves.
- **Not available at emit time.** The cascade runs on the feature branch as one
  atomic finalization commit *before the PR flips ready*
  (`evals.json:139`, "DRAFT-before-READY"). The squash SHA does not exist yet, and
  the PR may not exist yet either. The script never queries `gh pr view` — its only
  `gh` use is `check_issue_closed`. Adding a network lookup inside an awk-driven
  file rewrite gives this function a failure mode it does not have today, in a path
  that has no rollback.
- Note also that it swaps one external pointer for another. AC12 removes a pointer
  to a file; this substitutes a pointer to GitHub, which is the same shape of
  dependency the PRD is trying to shed.

### Option D — bare `_none_`, distinction carried elsewhere

**Literal:** `**Downstream:** _none_`

Where "elsewhere" would be, in descending order of strength:

1. **The feature's own `**Status:**`**, set to `Done` at `run-cascade.sh:430` in
   the same rewrite. A never-ran feature is at `Not started` or `Planned`. The pair
   `Status: Done` + `Downstream: none` versus `Status: Not started` +
   `Downstream: none` already separates the two states without a word of prose.
   This is genuinely true and is the strongest argument for D.
2. **The Progress section**, which the format reference names as the ledger
   (`roadmap-format.md:144-147`).
3. **Git history of the finalization commit.**

- **AC12 part 1:** passes. **Part 2: fails on the letter.** AC12 requires "the
  roadmap downstream cell the script emits … still distinguish[es] a chain that
  folded from one that never ran." Under D the cell distinguishes nothing; the
  neighbouring field does. The brief already calls this out, and reading the AC any
  other way makes it vacuous.
- **R8:** also fails — the claim is deleted rather than replaced.
- Worth stating anyway, because point 1 is the reason the *stakes* here are low:
  even the wrong answer to D2 loses very little.

### Option E — state the outcome, not the jargon

**Literal:** `**Downstream:** _none — every artifact was absorbed; nothing durable survives_`

- **Tells:** the same fact as A, plus *why* there is nothing to point at, in words
  that do not assume the reader knows what "fold" means in this corpus. A roadmap
  is read by strategic-chain readers who may never have run `/scope`.
- **Does NOT tell:** which artifacts, or where to look — same omissions as A.
- **AC12 part 1:** passes. **Part 2:** passes.
- **Test:** passes. Quoting: safe (em dash and semicolon are fine in awk and in
  markdown; no apostrophe, no `|`).
- **Trade against A:** longer, and it drops the corpus's own vocabulary. "Fold" /
  "absorb" is the established term — `/scope`'s `absorb` verdict
  (`skills/scope/SKILL.md:542-544`), `execute/SKILL.md:591-600`, the PRD itself. A
  keeps one vocabulary across the corpus; E is self-explaining to a reader who
  arrived from the strategy side.

### Option F — point at surviving in-tree evidence

**Literal (illustrative):** `**Downstream:** _none (chain folded; see the survivor's absorbed: frontmatter)_`

Listed to be ruled out explicitly, because it is the obvious first instinct once
the record is gone. It **does not work in this branch**: a fold's durable in-tree
evidence is the survivor's `absorbed:` frontmatter and its
`## Contribution from …` section (`skills/scope/SKILL.md:550-556`, FC18). In a
*fully*-folded chain the survivor is the PLAN, and the cascade deletes the PLAN.
There is no surviving `absorbed:` block to point at — which is exactly the case
AC11 requires `execute/SKILL.md` to concede in prose. A cell that points at it
would be a second dangling pointer with a longer half-life than the first.

## Over-reach check

The cell is one prose line in a document the cascade deletes — on a one-feature
roadmap, in the same commit that writes it. Three ways an option can overweight it:

- **Making it depend on state outside the function.** Option C needs a network
  call; Option B needs knowledge of a fold that happened in another process. Both
  buy a sentence that, on the common case, is never read by anyone, and both add a
  failure mode to a function that currently cannot fail.
- **Making it name a file.** Option B reintroduces the dangling-reference defect
  the folded branch exists to prevent, and FC20 will not catch the relapse (bare
  basenames are unresolvable by design), so the next stale pointer would be as
  silent as `docs/folds.md` was.
- **Making it the durable answer.** Any wording that tries to carry the
  folded-versus-never-ran distinction *for the repository* is asking a deleted line
  to be an archive. That distinction belongs to AC11 and
  `skills/execute/SKILL.md`. This cell's job is narrower: keep a human reading the
  ledger during the pre-deletion window from concluding the feature was skipped.

The opposite over-reach also exists and is worth naming: because the field has no
format contract and no validator, whatever is written here will never be checked
again. That argues for the shortest string that satisfies the AC, not the richest.

## Recommendation input

What the design should weigh, in the order the constraints bite:

1. **AC12's two-part test is met by the minimal edit.** Deleting `; see
   docs/folds.md` satisfies both halves and R8. The live question is whether the
   design *wants* more, not whether the AC *needs* more.
2. **The existing test's `PLAN-|DESIGN-` negative regex rules out the whole naming
   family** (Option B) unless the design also decides to weaken that guard — and
   that guard is the reason this branch was written at all. Treat "name the folded
   artifact" as a decision to change the test, not a wording choice.
3. **The PR/commit family is not reachable at emit time** (Option C). The cascade
   commits before the PR is ready; there is no squash SHA and no `gh pr view` call
   in the script. Rejecting C is a fact about when the code runs, not a preference.
4. **`**Status:** Done`, set in the same rewrite, already carries most of the
   distinction.** That caps how much this cell must say — and caps the cost of
   choosing wrong.
5. **The real choice is between A and E**: keep the corpus's term of art ("chain
   folded", one line shorter, consistent with `/scope` and `execute/SKILL.md`), or
   spell the outcome out for a strategic-chain reader who has never run `/scope`.
   Both pass both halves of AC12, both pass the test unchanged, and both are
   one-line diffs.
6. **Consider whether this chain should also document the field.**
   `roadmap-format.md`'s Per-Feature Format does not mention `**Downstream:**` at
   all. A three-line addition naming the field and its legal values — a downstream
   artifact with its terminal state, a `Needs <TYPE>` placeholder, and the
   folded-to-nothing form — would put this string under a written contract for the
   first time. That is scope beyond AC12 and the design should decide it
   deliberately rather than by omission; the argument for it is that an
   undocumented, unvalidated field is how the `docs/folds.md` pointer survived
   unnoticed in the first place.
