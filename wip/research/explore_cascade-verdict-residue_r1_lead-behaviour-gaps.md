# Lead: Does any shape still report the wrong cascade verdict on 7cd13d1, and which shapes do the tests pin?

Evidence labels: **measured** means I ran it and have output; **read** means it comes from reading code or docs only.

The experiments ran against the worktree's `skills/execute/scripts/run-cascade.sh` (7cd13d1), using the real `target/release/shirabe` the suite had just built (the suite log ended at "33 passed, 0 failed"). The harness is `/home/dangazineu/.claude/jobs/03bfd163/tmp/exp/exp.sh` and its output is `/home/dangazineu/.claude/jobs/03bfd163/tmp/exp/results.txt`. Every case builds a temp repo with a bare origin and a tracking branch, runs the cascade with `--push` and a `gh` stub on PATH, and records four things: the verdict and steps, whether HEAD moved and was pushed, whether the PLAN is still in HEAD, and what `shirabe validate --lifecycle . --mode=ready` says about `git archive HEAD` (the published tree CI would check).

## Findings

### 1. The two not-found arms in `handle_roadmap`

On 7cd13d1 both arms (`run-cascade.sh:508-513` and `:519-524`) set `ANY_FAILED=true` and record `update_roadmap_feature` as `failed`, with identical detail text (**read**). Before the fix, at 9f84fa7, both were `skipped` (`git show 9f84fa7:...` shows `add_step ... "skipped"` at :475 and :485) (**read**).

- **Arm 1** (no line contains both the slug and `Downstream:`). Scenario 28 (`scenario_roadmap_feature_not_found`, `run-cascade_test.sh:2519-2616`) pins it in the direct PLAN→ROADMAP shape, and it passes in the suite run (**measured**, from the suite log). My E0 reproduces it: `partial`, HEAD did not move, the PLAN is still in HEAD, and the published tree fails L01 on the PLAN (**measured**).
- **Arm 2** (a matching Downstream line, but no `### ` heading above it). No scenario covers it (**read**: only Scenario 28 asserts a failed `update_roadmap_feature`, and its fixture has no Downstream line). It is reachable, though. The lookup is a case-insensitive `grep -F "$plan_slug" | grep -i "Downstream:"` over the whole file, so any prose line above the first `### ` heading that contains both strings hits it. E3 puts "Downstream: PLAN-orphan.md is where this lands." in the Theme section and gets arm 2: `partial`, nothing published (**measured**). A roadmap whose feature headings use `## ` rather than `### ` would reach it too (**read**). The practical risk is small: a real roadmap usually has some `### ` heading before its Features section (the corpus `ROADMAP-strategic-pipeline.md` has `### Pipeline Model` at :38), and that would silently become the "enclosing" heading instead.
- **Substring false positive (a real gap).** The slug match is neither anchored to `PLAN-` nor bounded, and it takes `head -1`. With plan `PLAN-cascade-test.md`, a Feature 1 whose Downstream is `PLAN-cascade-test-extended.md` is matched before the real Feature 2. E4 shows the result: Feature 1 is rewritten to `Done` / `DESIGN-cascade-test.md (Current)`, Feature 2 stays `Planned`, and the verdict is `completed` with post-verify `ok` (**measured**).
- **Wrong feature only (the worst shape found).** In E4b the real feature for the plan is missing and an unrelated `In Progress` feature matches by substring. That feature is marked Done, which makes every feature Done, so `handle_roadmap_deletion` runs and the ROADMAP is `git rm`'d and pushed. The verdict is `completed`, `delete_roadmap` is `ok`, post-verify is `ok`, and the published tree passes the ready-mode check (**measured**). Someone else's in-flight feature gets closed and its roadmap deleted, and the run reports success.
- **Downstream naming a different slug.** That is plain arm 1, so the result is `failed`/`partial` (E0, E1 and E9 are this shape) (**measured**). The slug also matches non-PLAN names: `DESIGN-foo.md (Current)` contains `foo`. That is harmless when it is the right feature, but it widens the false-positive surface (**read**).

### 2. The ROADMAP reached directly and through DESIGN / PRD / BRIEF chains

Every shape now reports `partial` when the feature is not found (**measured**):

| Shape | Verdict | Commit / push | PLAN deleted in HEAD | Post-verify | Published tree ready-check |
|---|---|---|---|---|---|
| E0 PLAN→ROADMAP | partial | none | no | not run | fails (L01, PLAN) |
| E1 PLAN→DESIGN→ROADMAP | partial | ok / ok | yes | ok (DESIGN) | passes |
| E2 PLAN→DESIGN→PRD→ROADMAP | partial | ok / ok | yes | ok (DESIGN) | passes |
| E2b …→PRD→BRIEF→ROADMAP | partial | ok / ok | yes | ok (DESIGN) | passes |
| E2c PLAN→PRD→ROADMAP | partial | ok / ok | yes | ok (PRD) | passes |
| E9 canonical `/roadmap` format, DESIGN chain | partial | ok / ok | yes | ok | passes |

The execution order explains the split (**read**, `run-cascade.sh`):

1. Pre-probe runs (:806).
2. `finalize-chain` runs (:838), then the PLAN's Active→Done flip (:851-860).
3. The node loop stages each transitioned DESIGN/PRD/BRIEF into `STAGED_FILES` (:903-919).
4. `handle_roadmap` runs after the loop (:954-956) and sets `ANY_FAILED`.
5. `delete_plan` does `git rm -f` (:983) and appends the PLAN to `STAGED_FILES` only if `ANY_FAILED` is false (:999-1001).
6. The commit gate is `PUSH && ${#STAGED_FILES[@]} > 0` (:1010).
7. Post-verify runs only when `COMMIT_LANDED` is true (:1093).

In the direct shape `STAGED_FILES` is empty when step 6 is reached, so nothing publishes. In every chained shape it already holds the transitioned nodes, so the commit fires. Because `git commit` publishes the whole index, the commit also carries the PLAN's staged deletion even though the PLAN never entered the array. The commit is pushed and post-verify passes.

So Scenario 28's comment is true only for the direct shape. It says (`run-cascade_test.sh:2585-2586`): "ANY_FAILED is set before delete_plan, so the PLAN never enters STAGED_FILES and nothing publishes." In the chained shapes the verdict is correct (`partial`), but the finalization including the PLAN deletion is published and pushed. The ROADMAP feature is still at its old status, and the published tree passes the ready-mode lifecycle check, so CI cannot see the gap. No scenario pins a chained not-found shape (**read**).

Consequence for `/execute`: `execute.md` halts on `partial` before `gh pr ready` (**read**, `koto-templates/execute.md:715-729`). Its recovery list (:737-743) covers failed push, failed commit, refused `transition_*` with or without a commit, and failed post-verify. It has no entry for "`update_roadmap_feature` failed, with commit and push at ok". An agent reading it is not told the finalization already reached the remote, or that the fix is a hand edit of the ROADMAP feature followed by `gh pr ready` (**read**).

### 3. The open-issue `delete_roadmap` skip reports `completed`

E7 (chained) and E7b (direct) cover all features Done with an issue still OPEN. Both report `completed`, with `delete_roadmap` `skipped`, commit and push ok, and post-verify ok. The ROADMAP stays at `status: Active` with every feature Done (**measured**).

Post-verify cannot catch this. `required_state` in `crates/shirabe-validate/src/lifecycle.rs` (~:966-971) requires a ROADMAP that is a member but not the root of the evaluated chain to be `Active`, and `(Roadmap, SinglePrAtMerge)` also answers `Active` (~:891). An all-Done ROADMAP still at Active therefore passes both the anchored and the full-corpus ready check (E7: published tree rc=0) (**read**, plus **measured** via E7). The validator never reads feature statuses.

Scenario 12 (`scenario_deletion_open_issue_skip`, `run-cascade_test.sh:1275-1335`) pins this as `completed`, dry-run only (no `--push`) (**read**; it passes in the suite run, **measured**).

Is `completed` right here? Defensibly yes for the tactical chain, but the recovery text is broken. The detail says "close the issue first or run the cascade again after it closes". The cascade deletes the PLAN in this same run, though, and a re-run exits 1 without it (`run-cascade.sh:774-777`). Nothing but a hand edit will ever delete this ROADMAP (**read**). The design classes "Issue still open" among its failure messages (`DESIGN-completion-cascade.md:303`). Its handle_roadmap prose calls it a guard ("Only transition if all referenced issues are confirmed closed", :414-415), and the script's comment calls it a skip (:618). The design is ambiguous, and the script chose `completed`.

Two aggravations:

- **E7c.** When `gh` itself fails (unauthenticated, network), `check_issue_closed` returns 1 (:176-179), and that is treated exactly like an open issue: `skipped`, `completed` (**measured**). The detail wrongly claims the issue "is still open".
- **The URL scan covers the whole ROADMAP file** (`grep -oE ... "$path"`, :659-660), not just this feature. Any open issue URL anywhere in the roadmap, even in prose, blocks deletion (**read**).

### 4. Other arms that silently don't finalize, with verdict `completed`

The `update_roadmap_feature` `ok` step at :579 is unconditional. Both awk rewrites only act when their patterns match (`^\*\*Status:\*\*` inside the feature; `^\*\*Downstream:\*\*` on exactly `downstream_line`), and neither reports whether it changed anything (**read**). Four shapes follow from that (**measured**):

- **E5, feature with no `**Status:**` line.** Downstream is rewritten, the status is not, and the step is `ok` (`completed`).
- **E6, list-item fields (`- **Status:**`, `- **Downstream:**`).** The grep matches but neither awk does. The ROADMAP is byte-identical except for staging, the Downstream still names the now-deleted PLAN (the dangling reference that `scenario_plan_roadmap_no_design` exists to prevent), and the step is `ok` (`completed`).
- **E6b, list-item fields while every bold-at-start Status elsewhere is Done.** The `all_done` scan (:584, and :638 in the deletion handler) counts only `^\*\*Status:\*\*` lines, so the unrewritten `- **Status:** Planned` is invisible to it. The ROADMAP is deleted and pushed with a feature still reading Planned, `delete_roadmap` `ok` (`completed`).
- **E8, lower-case `**downstream:**`.** `grep -i` matches, the case-sensitive awk does not. Status flips to Done, the Downstream line keeps naming the deleted PLAN, and the result is `completed`.

A related point (**read**): `handle_roadmap` is called as `handle_roadmap ... || true` (:955). In bash, `set -e` is suspended for the whole body of a function called in a `||` context, including the nested `handle_roadmap_deletion`. So a failing `awk`/`mv`/`mktemp` inside it does not abort. The `awk ... > "$tmp" && mv` pairs just skip the `mv`, and the step still records `ok`. I did not force such a failure, so this is from code only.

The `all_done` loop in `handle_roadmap` (:585-590) does not skip empty lines. If no bold Status line exists at all, the here-string yields one empty line, so `all_done=false`. That is safe (**read**).

### 4a. The not-found arm is not rare. It is the default for canonical roadmaps (the most consequential finding)

The canonical per-feature format in `skills/roadmap/references/roadmap-format.md` (~:152-163) is `**Needs:**`, `**Dependencies:**`, `**Status:**`. There is **no `**Downstream:**` field**, and the per-feature section calls `Needs` optional (**read**). The only `**Downstream:**` lines in the repo outside the cascade script and its tests are two eval fixtures, a legacy corpus fixture (`crates/shirabe/tests/fixtures/golden/corpus/real/ROADMAP-strategic-pipeline.md`), and the design and SKILL text (**read**, grep).

No skill writes the field. `/scope` hands the roadmap to `/brief` (which reads the feature entry) and to `/plan` (which records the roadmap in the PLAN's frontmatter), and neither edits the ROADMAP (`skills/scope/references/phases/phase-2-chain-orchestration.md:178-230`) (**read**). `/plan` phase 7 only adds `Feature: <name>` to issue bodies (`skills/plan/references/phases/phase-7-creation.md:292-296`) (**read**).

E9 runs a roadmap in exactly the canonical format through a DESIGN chain. The result is `partial`, commit and push ok, the feature's Status never updated, and the published tree green (**measured**).

On 9f84fa7 this same shape reported `completed` with a `skipped` step. On 7cd13d1 every `/execute` run over a roadmap authored by the current `/roadmap` skill will report `partial` and halt before `gh pr ready`, after already pushing the finalization (**read** for the 9f84fa7 comparison, **measured** for 7cd13d1).

So the lookup `handle_roadmap` does (slug in a `Downstream:` line) doesn't match the format the upstream skill produces. #353 turned that silent mismatch into a loud halt. The halt is honest, but it now fires on the happy path.

### 5. What is measured and what is only read

- **Measured** (suite log and my runs):
  - Scenario 28 passes.
  - Every chained not-found shape is `partial` and still publishes.
  - Arm 2 is reachable and yields `partial`.
  - The substring false positive, including the ROADMAP deletion in E4b, reports `completed`.
  - The no-Status, list-form and lower-case shapes report `completed` with nothing or only half rewritten.
  - The E6b deletion happens with a Planned feature left in place.
  - The open-issue and gh-failure skips report `completed` under `--push`, and the published tree passes the ready check.
  - The canonical-format roadmap reports `partial`.
- **Read only:**
  - The `set -e` suspension under `|| true`.
  - The whole-file issue-URL scan.
  - The impossibility of re-running the cascade after the PLAN is gone.
  - The validator's `Active` requirement for a non-root ROADMAP.
  - That no skill writes `**Downstream:**`.
  - The `execute.md` recovery-list omission.
  - The 9f84fa7 behaviour.
- **Pinned by tests:**
  - Scenario 28: direct not-found → `partial`, nothing published, published tree fails the ready check.
  - Scenario 12: open-issue skip → `completed`, dry-run.
  - Scenarios 1 and 2: happy DESIGN and DESIGN→PRD chains → `completed`.
  - `scenario_plan_roadmap_no_design`: direct happy shape → `completed`, Downstream folded.
- **Not pinned by any test:** arm 2, a chained not-found shape, a false-positive slug match, a feature with no status line or non-bold fields, open-issue under `--push`, gh failure, and a canonical-format roadmap.

## Implications

- The residue is not only a document to amend. The `partial` verdict #354 asked for is delivered in every not-found shape. But three behavioural gaps nobody has named sit next to it:
  - Silent-success arms where the ROADMAP was finalized wrongly or not at all (false-positive slug, unconditional `ok` after non-matching awk, the `all_done` scan blind to non-bold Status) still report `completed`. Two of them delete a ROADMAP that should not have been deleted.
  - The chained not-found shapes publish and push before reporting `partial`, contrary to Scenario 28's comment, and `/execute`'s recovery list doesn't describe that state.
  - Because `/roadmap` never emits `**Downstream:**`, the new `partial` fires on the ordinary path for current-format roadmaps, so the fix changed the happy-path outcome of `/execute` from "completed, feature silently not updated" to "halt after push".
- #354's criteria written against `skipped` and the design's worked example (`DESIGN-completion-cascade.md:340-356`, which shows `skipped` with `partial`) are the least important part. The design's handle_roadmap step 1 (:407-410) still prescribes `skipped`, and both need amending to `failed`. But whichever way the docs go, the lookup contract (`Downstream:` plus slug) is out of sync with the roadmap format, and that is a design question, not a doc typo.
- Scenario 28's comment at `run-cascade_test.sh:2585-2586` is only true for the direct shape and should be scoped to it.

## Surprises

- The canonical `/roadmap` per-feature format has no `**Downstream:**` field, and no skill ever adds one. The cascade's ROADMAP lookup only works on hand-edited or legacy roadmaps.
- A substring slug match can close an unrelated in-flight feature and delete the whole ROADMAP with verdict `completed` and every check green (E4b).
- `delete_roadmap` skip's recovery advice ("run the cascade again after it closes") is impossible to follow, because the same run deletes the PLAN the cascade needs as input.
- Scenario 28's "nothing publishes" holds only for the direct shape. Every chained not-found shape pushes.

## Open Questions

- Should `handle_roadmap` locate the feature some other way (for example by the `Feature:` label, by the roadmap reference the PLAN records, or by a PLAN-anchored `PLAN-<slug>.md` word-boundary match), or should `/plan` or `/brief` start writing a `**Downstream:**` cell into the feature entry? This needs a human design call. Until it's made, `partial` is the normal outcome for current-format roadmaps.
- For chained shapes, should a not-found ROADMAP block the commit (the way the refused-walk gate does), or is publishing the tactical finalization and reporting `partial` the intended split? If it's intended, `execute.md` needs a recovery entry for it.
- Should the open-issue skip, and especially a `gh` failure misread as "open", lower the verdict? And what recovery path exists for a ROADMAP left all-Done at Active once the PLAN is gone?
- Should the awk rewrites report whether they matched, and turn a no-op into `failed`?
- I stumbled on but did not investigate: #355 (a blocked finalize-chain node recorded as `ok`) and #356 (`partial` has no route of its own). The `error`-node arm at :933-940 labels every error node `transition_design` whatever its type, which is a small mislabel next to #355.

## Summary

On 7cd13d1 every not-found shape (direct, and through DESIGN, PRD and BRIEF chains, both arms) now reports `partial`. But the chained shapes still commit and push before saying so, and several neighbouring arms still report `completed` after silently mis-finalizing: a substring slug match can close the wrong feature and even delete the ROADMAP (measured, E4b), and the unconditional `ok` after non-matching awk rewrites leaves statuses unchanged and references dangling. The bigger implication is that the canonical `/roadmap` feature format has no `**Downstream:**` field and no skill writes one, so the not-found arm is the ordinary path for current-format roadmaps, and #353 turned a silent `completed` into a routine halt after push. The biggest open question is whether to change how `handle_roadmap` finds the feature (or have `/plan` or `/brief` write the Downstream cell); no test pins chained not-found, arm 2, false-positive matches, open-issue-under-`--push`, or a canonical-format roadmap.
