# Review: skill-contract half of `feat/upstream-legality`

Scope: `git diff main -- skills/ references/`, against PLAN Issues 3-7 and PRD
R11-R25. Findings are ranked most-serious first.

---

## 1. Issue 6's repo-wide sweep is ticked but fails — four survivors, one of them in `references/`

Issue 6's last criterion: *"no file under `references/` or `skills/*/references/`
documents a ROADMAP as a legal upstream for a BRIEF, a PRD, or a DESIGN."* It is
ticked. Running it finds four files that still do, none of which the diff
touches and none of which appear in any issue's `Files` list. All four are
record language ("takes a ROADMAP as its upstream", "written into BRIEF
frontmatter"), not the grounding-input language the criterion explicitly
exempts.

| File:line | Text | Why it is a violation |
|---|---|---|
| `skills/vision/references/vision-format.md:85` | "The ROADMAP is where the strategic chain hands off to the tactical one -- `/brief` crosses that boundary by taking a ROADMAP as its upstream -- so no strategic document reaches past it." | Verbatim the sentence `references/pipeline-model.md` deleted in Issue 3. Names a ROADMAP as the BRIEF's upstream. |
| `skills/strategy/references/phases/phase-3-structural-fill.md:159-161` | "The ROADMAP is the boundary: `/brief` crosses it by taking a ROADMAP as upstream, and no strategic document reaches past it." | Same deleted sentence, second copy. |
| `skills/roadmap/references/roadmap-format.md:288-290` | "it is the only bridge from the strategic chain to the tactical one -- `/brief` takes a ROADMAP as its upstream, never a STRATEGY and never a PRD." | Same claim, and it is the justification for the one-feature-roadmap rule, so it is load-bearing prose rather than a passing mention. |
| `references/cross-repo-references.md:100` | "\| `skills/brief` \| [Phase 2 draft] \| The recorded upstream before it is written into BRIEF frontmatter (Phase 0 step 0.3 validates the value's shape; **this step decides whether a public BRIEF may name it**) \|" | Points a reader at `skills/brief/references/phases/phase-2-draft.md` for a decision that file no longer makes — the diff replaced that paragraph with "There is no `upstream:` field." The table's own closing note ("When updating either side, update the other") is the instruction that was missed. |

**Consequence.** A reader or an agent reaching `/brief`'s contract through
`/roadmap`, `/vision`, `/strategy`, or the cross-repo reference table is told to
write a link `shirabe validate` now rejects at error severity. The
`roadmap-format.md` and `roadmap/SKILL.md` copies are the worst of them, because
`/roadmap` is the skill an author runs immediately before `/scope`.

Two more copies of the same sentence sit outside the sweep's literal scope but
carry the same contract:

- `skills/roadmap/SKILL.md:43-44` — "`/brief` takes a ROADMAP as its upstream --
  never a STRATEGY, and never a PRD."
- `skills/vision/references/vision-format.md:85` (already above; the file is a
  reference, so it is in scope).

The two-line correction is the same in each: the roadmap grounds the brief and
is recorded on the PLAN.

---

## 2. `skills/scope/evals/evals.json` — `upstream-flag-consumed` was never rewritten

PRD R22 names five eval expectations and gives each a disposition. Four moved.
The fifth did not:

`skills/scope/evals/evals.json:345`, scenario `upstream-flag-consumed`, still
reads:

> "...and the produced **docs/briefs/BRIEF-inline-diff.md carries upstream:
> docs/roadmaps/ROADMAP-editor.md in its frontmatter.**"

R22's disposition for this row is *"rewritten: the roadmap reaches the PLAN
instead."* The diff to that file is a single line (`git diff main --numstat`:
`1 1`), and it is the `pre-authoring-notice-cold-start` reword.

**Consequence.** The `/scope` eval suite now grades the produced brief on
carrying the exact field `/brief` is contractually forbidden to write. A
conforming `/scope` run fails this scenario; a run that violates the new rule
passes it. This is the one place in the diff where an eval expectation
contradicts the prose it grades, and it also leaves R22 undischarged.

The same scenario's `expectations` list is stale in a second way: it asserts
"the three ordered checks (wip/ rejection, git-tracked confirmation,
public-repo-to-private-upstream omission)" — still correct for `/scope`, which
kept all three, but the eval never mentions the `docs/roadmaps/` confinement
Issue 6 added at `skills/scope/references/phases/phase-0-setup.md:163-170`.

---

## 3. Issue 6's criterion 6 is ticked with nothing asserting it

> "A `/scope` run supplied with a roadmap produces a chain in which no durable
> artifact names it and the produced plan does, and where the run's
> consolidation absorbs the brief, the surviving PRD is left with no `upstream:`
> field rather than the roadmap's path."

The *behaviour* holds by construction — the absorb rule at
`skills/scope/references/phases/phase-2-chain-orchestration.md:514-516` already
says "Set the survivor's `upstream:` to that value, **or remove the field when
the absorbed artifact had none**", which is exactly R16.1's argument. Nothing
asserts it. `skills/scope/evals/evals.json` gained no scenario, and the criterion
names an observable outcome, not a design fact. Combined with finding 2, the
`/scope` eval suite has no scenario at all that exercises the new routing.

---

## 4. `skills/scope/SKILL.md:754-758` contradicts `/scope`'s own phase file

SKILL.md, untouched by the diff:

> **The flag's value reaches a committed field.** Nothing about a flag suggests
> its value ends up in a committed file, and this one does: `/brief` writes it
> into the produced BRIEF's `upstream:` frontmatter, and that document is
> committed.

`skills/scope/references/phases/phase-0-setup.md:201-206`, changed by the diff:

> The third check is the load-bearing one, because the flag's value reaches a
> committed `upstream:` field in the produced PLAN. **It does not reach the
> BRIEF**: a BRIEF records no upstream [...]

Same skill, opposite statements, and SKILL.md is the entry point. The passage
also uses the BRIEF to justify why the private-upstream check is mandatory
rather than advisory — the conclusion survives (the PLAN carries the value) but
the stated reason is now false. `skills/scope/SKILL.md:135-142` has a milder
version: it describes the validated value as "handed to `/brief`" full stop,
with no mention of `/plan`, which is now half the routing.

`skills/scope/SKILL.md` appears in no issue's `Files` list, which is how this
was missed. Issue 6's criterion 1 says only that the *child-argument table*
carries the flag; the table lives in `phase-2-chain-orchestration.md` and does
carry it.

---

## 5. `R10` where the code is `R11` — two places, one of them self-contradicting

The precedence rule is settled: a durable document naming a ROADMAP violates
both properties and reports the **lifetime** finding, `R11`
(`crates/shirabe-validate/src/checks.rs:929`, and PLAN Issue 2's third
criterion). Two of the new sentences say `R10`, and both are in the sentence
that describes precisely the roadmap case:

- `skills/brief/references/brief-format.md:44-46` — "`shirabe validate` reports
  any value the field holds as an `R10` direction violation." Forty lines later
  the same file gets it right at `:84-86`: "reports one as `R11` when the target
  is a roadmap and `R10` for any other type." The two statements are in the same
  document.
- `skills/brief/references/phases/phase-2-draft.md:85-87` — "reports any value
  it carries as an `R10` direction violation. Do not write the field even when
  Phase 0 recorded a grounding ROADMAP" — the very next clause names the case
  that reports `R11`.

`skills/brief/references/phases/phase-0-setup.md:101` (`R10` for a follow-up
brief naming downstream work) and `:235` (`R11` for the roadmap) are both
correct, as is `references/pipeline-model.md:147`.

**Consequence.** An author who greps for the code the validator emitted lands on
prose that names the other one. Fix: say "`R11` when the target is a ROADMAP,
`R10` otherwise", or drop the code from the summary line and leave it to the
"Why a brief has no upstream" section that already gets it right.

---

## 6. `skills/scope/evals/evals.json:332` — "the only flag it ever passes is `/brief`'s own `--upstream`"

Scenario `upstream-path-invocation-preserves-child-isolation` (id 22). `/scope`
now also passes `/plan`'s `--upstream`
(`phase-2-chain-orchestration.md:181`). The scenario's own run supplies no
upstream so its outcome is unaffected, but the sentence is a general claim about
`/scope`'s invocation surface and it is now wrong. Low impact; one-word fix
("`/brief`'s and `/plan`'s own `--upstream`").

---

## 7. Old-shape cascade scenario lost an expectation it still describes

`skills/execute/evals/evals.json`, scenario
`e2e-execute-cascade-old-shape-still-reaches-the-roadmap` (id 34). The
`expected_output` still says "updates ROADMAP-cascade-test.md Feature 2 entry
Status to Done **and Downstream to reference the DESIGN at Current**", but the
rewrite deleted the matching expectation line ("ROADMAP-cascade-test.md Feature
2 Downstream references the DESIGN doc at Current") while keeping the Status
one. The new-shape scenario (id 20) keeps both. R22 authorizes rewriting this
scenario, so this is not a rule violation — it is an unintended coverage loss in
the scenario whose whole job is to prove nothing changed for a pre-existing
corpus.

---

## 8. The shell script — the awk handles every shape it claims

`skills/plan/scripts/validate-plan.sh:87-120`, `get_upstream_entries`. I drove
the function directly with fixtures. All four claimed shapes are correct:

| Input | Result |
|---|---|
| scalar | one entry |
| inline sequence `[a, b]` | two entries |
| block sequence, then `milestone: "M"` | two entries, terminates on the key |
| block sequence unindented (`- a` at column 0) | two entries |
| block sequence as the last frontmatter key | two entries |
| `upstream:` after a block scalar containing `- a bullet` | correct, the indented bullet is not misread |
| block scalar `notes: \|` *after* the sequence, containing `- not a path` | correct, exits on `notes:` before the bullets |
| quoted flow seq `['a', "b"]` | two entries, quotes stripped |
| blank line between the sequence and the next key | correct |

The terminator `/^[^ \t-]/` is right for every case that matters. Excluding `-`
is what lets an unindented block sequence work, and it is safe because
`extract_frontmatter` (`:47-57`) strips both `---` markers before the function
ever sees them, and a top-level YAML key cannot begin with `-`. Two inputs break
it, both marginal:

- **A column-0 YAML comment inside the block sequence** silently ends
  enumeration. `upstream:` / `  - docs/a.md` / `# comment` / `  - docs/b.md`
  yields `docs/a.md` only — `#` matches the terminator. This is the one input
  where the terminator does the wrong thing, and it is the exact failure class
  the function's own header comment says it exists to prevent (a silently
  skipped entry). Indented comments are handled correctly.
- **CRLF frontmatter** never enters block mode at all: `upstream:\r` misses
  `/^upstream:[ \t]*$/`, falls through to the scalar branch, and emits a bare
  `\r`. The script then exits 3 with "upstream file does not exist: ''", so it
  fails loudly rather than silently — and `get_field` has had the same blind
  spot since before this change, so it is a pre-existing class, not a
  regression.

Neither is worth blocking on. A trailing `#` comment on a scalar or a sequence
entry is carried into the path and produces a loud "file does not exist";
`upstream: []` is read as no upstream and skips the check, also pre-existing in
spirit.

`bash skills/plan/scripts/validate-plan_test.sh` is **green: 17 passed, 0
failed.** `git diff main --numstat` on the test file is `213 0` — 213 added
lines, zero deletions, so Issue 5's "no existing case is modified" holds
literally. The new cases cover both written shapes, a bad second entry, a
symlink, a cross-repo entry, and roadmap-at-Draft; the roadmap-at-`Active`
**pass** is covered inside the two sequence cases, both of which include an
Active `ROADMAP-*.md` and exit 0. The rewritten upstream block
(`:181-288`) is correct: per-entry loop, placeholder skip, cross-repo skip,
existence, symlink rejection, containment against a realpath'd root, `git
ls-files --error-unmatch -- "$path"` with the `--` terminator, and the
ROADMAP-vs-other status split.

I also ran the script against the real new PLAN
(`docs/plans/PLAN-upstream-link-legality.md`): exit 0, upstream reported
`Planned`.

---

## 9. Files changed that no issue claims

`git diff main --stat`, restricted to `skills/` and `references/`, against the
per-issue `Files` lists:

| File | Claimed by | Note |
|---|---|---|
| `skills/brief/references/phases/phase-1-discover.md` | **nobody** | 1-line terminology change (`upstream ROADMAP path` → `grounding ROADMAP path`). Correct and in the spirit of Issue 4, but Issue 4's `Files` list does not include it. |
| `skills/execute/evals/fixtures/briefs/BRIEF-cascade-test-new-shape.md` | **nobody** | Issue 7 lists only `fixtures/plans/` and `fixtures/roadmaps/`. |
| `skills/execute/evals/fixtures/designs/DESIGN-cascade-test-new-shape.md` | **nobody** | same |
| `skills/execute/evals/fixtures/prds/PRD-cascade-test-new-shape.md` | **nobody** | same |
| `skills/execute/evals/fixtures/scenarios/e2e-cascade-new-shape/.keep` | **nobody** | same; content `{}` matches the existing `e2e-cascade-full/.keep` convention exactly |

All five are legitimate under R23 ("a new-shape fixture chain [...] is added
beside them") — the `Files` lists are what is incomplete, not the work. Nothing
in `skills/` or `references/` was touched that the change does not need.

Outside my half, for the record: `crates/shirabe/tests/cli.rs` (+77) is not in
Issue 2's `Files` list either (`checks.rs`, `validate.rs`, `main.rs`). That
belongs to the Rust reviewer.

---

## What is clean

**Issue 3 — clean.** `references/pipeline-model.md` and
`skills/prd/references/prd-format.md` no longer document a ROADMAP as a PRD's or
a DESIGN's parent. The lifetime rule is stated positively at `pipeline-model.md:140-146` ("A link runs from the shorter-lived document to the longer-lived
one"), and the crossing-on-the-PLAN-alone statement is at `:153-159`, bolded.
The nearest-produced rule survives with the roadmap case removed
(`pipeline-model.md:122-123`), and `prd-format.md:36-44` names the PRD case
explicitly: "A PRD written with no brief above it omits the field rather than
reaching past it to the ROADMAP that sequenced the feature." `shirabe validate
--lifecycle . --mode=draft` exits 0 with the single pre-existing
`PRD-koto-adoption.md` orphan notice — verified by running it.

**Issue 4 — clean.** Every criterion holds. The read-versus-record section is at
`skills/brief/references/phases/phase-0-setup.md:218-249` and gives the reason as
what a BRIEF is ("its legal-parent set is empty: it heads its own tactical
lineage") rather than what it was handed. Both routes survive
(`SKILL.md:110-136`). The announcement is mandated at `phase-0-setup.md:351-359`
("It is not optional") and graded by both rewritten evals. The `ROADMAP-`
basename check is re-justified at `phase-0-setup.md:160-165`. The tracked-by-git
drop is explicit and argued at `:196-206`, and the `docs/roadmaps/` confinement
that compensates for it is at `:151-155`. `brief-format.md` drops the field from
the skeleton, the required/optional list, and the field glossary, and gains a
"Why a brief has no upstream" section. The `## Upstream Path` key is renamed to
`## Grounding Path` everywhere — I grepped the whole repo and the only survivors
are in `wip/`, which is deleted before merge.

**Issue 5 — clean.** The flag contract is at `skills/plan/SKILL.md:268-331`:
parsed before the positional, never the slug source, bare and repeated both
rejected, and the six validation steps in exactly the order the criterion names
with the reason the order is not cosmetic. The private-upstream omission is step
6, stated in `/plan`'s own contract for the standalone case. The sequence shape
is documented in both frontmatter blocks of `phase-7-creation.md` (`:168-180` and
`:266-278`). The Phase 7 hygiene step now calls the script instead of a
scalar-only `head | grep`, with the reasoning for the swap spelled out. The new
eval (`skills/plan/evals/evals.json` id 32) asserts both halves — the flag is
recorded and the slug still comes from the positional. See finding 8 for the
script itself.

**Issue 7 — clean apart from finding 7.** The new-shape chain is genuinely new
shape: `PLAN-cascade-test-new-shape.md` carries a block-sequence `upstream:` with
the design first and `ROADMAP-cascade-test.md` second;
`BRIEF-cascade-test-new-shape.md` has no `upstream:` and says so in its body;
the PRD names the BRIEF and the DESIGN names the PRD. `ROADMAP-cascade-test.md`
gains Feature 3 pointing at the new plan, so the two scenarios do not collide.
The old-shape fixtures (`BRIEF-cascade-test-full.md`,
`DESIGN-cascade-test-short.md`) are untouched — confirmed by the diff — and the
rewritten scenario adds an explicit guard against migrating them ("Plan does NOT
propose removing the BRIEF's `upstream:` field"). Eval ids are unique; no eval
outside R22's five changed.

**`/explore`'s handoff — clean.** `skills/explore/references/phases/phase-5-produce-roadmap.md:43-60`
detects a STRATEGY, refuses a VISION explicitly, and tells the run what to do
when a VISION was found and no STRATEGY was (omit the flag, name it in prose).

---

## Suggested order of repair

1. Rewrite `upstream-flag-consumed` in `skills/scope/evals/evals.json` (finding
   2) and add the absorb assertion Issue 6 criterion 6 names (finding 3).
2. Fix the four sweep survivors and the two SKILL.md copies (finding 1) and the
   `/scope` SKILL.md contradiction (finding 4). Then re-run the sweep as a grep
   rather than by reading the diff.
3. Correct the two `R10`/`R11` mislabels (finding 5).
4. Restore the dropped Downstream expectation (finding 7) and fix the id-22
   sentence (finding 6).
5. Optionally, handle a column-0 comment in the block sequence (finding 8) by
   narrowing the terminator to `/^[^ \t#-]/`, or leave it and note the shape.
