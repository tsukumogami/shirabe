# Lead: Who reads the cascade's per-step `status` (as distinct from `cascade_status`), and what would each possible resolution of shirabe#354's residue touch?

All facts below are read from 7cd13d1 (the worktree HEAD is 7cd13d1 plus one wip commit).

## Findings

### 1. Consumers of the cascade's JSON output

A search for `cascade_status`, `update_roadmap_feature` and `run-cascade` across skills, scripts, references, crates, docs and workflows turns up one runtime consumer that reads `steps[].status`, one test suite that pins it, and nothing else.

**`skills/execute/koto-templates/execute.md`, `plan_completion` (READ ONLY).** This is the only production consumer. It reads the verdict to decide whether to go on:

```bash
case "$CASCADE_STATUS" in
    completed|skipped) : ;;
    *) echo "$RESULT" | jq -r '.steps[]? | select(.status == "failed") | "\(.action): \(.detail)"'
       exit 1 ;;
esac
```

So the continue/halt decision rests on `cascade_status` alone, but the halt surfaces its reason by filtering for `.status == "failed"`. The recovery guidance after it (around :736-742) is also written in terms of failed steps: a failed `push`, a failed `commit`, a refused `transition_*`, a failed `lifecycle_post_verify`. There's no bullet for a failed `update_roadmap_feature`. The verdict glossary (around :754) defines `partial` as "some steps ran but at least one failed (a transition was refused, an upstream was missing, the finalization commit or push failed, or the post-verify failed)". The not-found case isn't named there, but "at least one failed" covers it on 7cd13d1. Nothing in execute.md treats `skipped` as meaningful for a single step; the `cascade_detail` field description at :445 ("why steps were skipped") is loose prose about the run. On 7cd13d1 the not-found case produces a `failed` step, so the jq filter prints the design's detail text when the run halts.

**`skills/work-on/koto-templates/work-on.md` (READ ONLY).** `grep -c cascade` returns 0. It doesn't consume the cascade output at all, so no resolution touches it.

**`skills/execute/koto-templates/execute.mermaid.md`.** A generated diagram. It shows only the three `cascade_status` edges to `ci_monitor`.

**`skills/execute/SKILL.md`.** Prose about verdicts and DRAFT-before-READY. No step-status semantics.

**`skills/execute/evals/evals.json`.** Every cascade eval (`parity-finalization-cascade-atomic`, `e2e-execute-cascade-design-roadmap`, `e2e-execute-cascade-new-shape-plan-carries-roadmap`, `e2e-execute-cascade-old-shape-still-reaches-the-roadmap`) asserts `cascade_status is completed` plus artifact state on disk. `execute-plan-completion-cascade` (:286-297) asserts the agent "surfaces the failed steps to the human instead of marking the PR ready on a partial". That's the execute.md filter restated, so it depends on the `failed` label being present on a partial run. No eval covers a ROADMAP feature that can't be found.

**`skills/execute/scripts/run-cascade_test.sh`.** This is the file that actually pins step statuses:
- Scenario 28 (`scenario_roadmap_feature_not_found`, :2519-2600) asserts `partial`, exactly one `update_roadmap_feature` step at `failed`, the detail text "no matching feature entry was found", no `commit` or `push` step, HEAD unmoved, and that the published tree still fails `validate --lifecycle . --mode=ready`. Its fixture is a ROADMAP feature with no `Downstream:` line at all, which exercises only the first not-found arm (`run-cascade.sh:508`). The second arm, a `Downstream:` line with no enclosing `### ` heading (`:519`), has no scenario.
- Scenario 12 (`scenario_deletion_open_issue_skip`, :1275) asserts `cascade_status: completed` alongside a `delete_roadmap` step at `skipped`. That pins "a skipped step doesn't imply partial".
- The post-verify scenarios (`scenario_push_no_survivor`, `scenario_push_plan_only_commits_deletion`, `scenario_commit_failure_skips_verification`) assert `lifecycle_post_verify` at `skipped` under verdicts `completed`, `skipped` and `partial` respectively, so a skipped step never sets the verdict by itself.
- Scenario 5 (`scenario_partial_chain`, :759) pairs `partial` with at least one `failed` step that has a non-null detail.

Taken together, the suite encodes the rule that `partial` holds exactly when some step failed, and that `skipped` steps have no effect on the verdict.

**Rust crates.** No code parses the cascade's JSON. Mentions of `run-cascade.sh` in `crates/shirabe-validate/src/finalize.rs`, `transition.rs` and `crates/shirabe/tests/transition_parity.rs` are comments about finalize-chain's own report or the transition output. As a side note, `crates/shirabe-validate/src/lifecycle.rs:1681` and `crates/shirabe/src/main.rs:1285` still name the old path `skills/work-on/scripts/run-cascade.sh`.

**Scripts and references.** `scripts/run-evals.sh:54` mentions the cascade in a comment. `scripts/check-tool-diagnostic-discards_test.sh:277-278` is a fixture string that reads `.cascade_status`, not a consumer. `references/tool-diagnostic-discards.md` catalogues the script's `|| true` sites. `references/pipeline-model.md:241` points readers to `DESIGN-completion-cascade.md` "for the design".

**Docs that restate step-status semantics.**
- `DESIGN-cascade-post-verify-seed.md:169` says the no-anchor arm "records `skipped` ... and does not touch `ANY_FAILED`", and its diagram (:197) pairs `step: failed` with `ANY_FAILED=true` and `step: skipped` with "ANY_FAILED untouched".
- `PRD-cascade-post-verify-seed.md:235-236` says "The per-step `status` vocabulary gains no new value".
- `PRD-finalize-chain.md` R8 (:108-110) freezes the stdout contract (verdict vocabulary, action list and fields), but not what each step status means.
- `DESIGN-shirabe-artifact-decision-contract.md:774` says ROADMAP-deletion negatives are "a recorded `skipped`/`failed` step; the cascade continues".
- `DESIGN-finalize-chain.md:35` says the cascade's behaviour "was established by" DESIGN-completion-cascade.md.

None of these depend on the not-found case in particular. The two post-verify-seed documents do set a precedent across documents that a `skipped` step leaves `ANY_FAILED` alone.

### 2. What each resolution touches

**(a) Amend DESIGN-completion-cascade.md to say `failed` plus `partial`, then close #354.**
- Files: `docs/designs/current/DESIGN-completion-cascade.md` only.
- Passages, by line on 7cd13d1:
  - :352, worked example, `"status": "skipped"` becomes `"failed"`. This is the only change to the example.
  - :389-391, ROADMAP substitution prose ("logs a warning, sets `cascade_status: partial`, and skips the update"). The verdict is already right; the wording "skips the update" becomes "records a `failed` step and does not update the file".
  - :409-410, `handle_roadmap` step 1, "record a `skipped` step" becomes "record a `failed` step".
  - :562-564, Consequences/Negative, "the update is silently skipped". This contradicts the doc's own Mitigations at :572-574. Reword it as the risk and let the Mitigation say it becomes a `failed` step and a `partial` verdict.
  - :572-574, Mitigations. Already says `partial`; optionally add "records a failed step".
  - :281 and :424-425 are generic ("every `skipped` or `failed` step must include a detail"; "any `failed` or `skipped` steps require follow-up") and don't need to change.
  - The error-message contract table (:296-304) needs no change: the "ROADMAP feature not found" row already sits under a column headed "Failure", and the script emits exactly that detail text.
- Neither read-only file is needed. execute.md is already consistent with `failed` plus `partial`.
- Then close #354 as delivered by #353 (see 2b for how each criterion reads).
- Validator impact: `./target/release/shirabe validate docs/designs/current/DESIGN-completion-cascade.md` returns rc=0 today, with one notice: `[FC10] em-dash-density: 10.4 per thousand words ... above the threshold of 10`. `validate-docs.yml` validates changed doc files and gates on exit code, and a notice doesn't fail it. An amendment will put the file in that changed set, so it's worth not adding more em-dashes.

**(b) Rewrite or withdraw #354's first and third criteria.**
- Files: none. This is an issue-body edit only.
- How each criterion stands on 7cd13d1:
  - The first ("A skipped `update_roadmap_feature` step yields `cascade_status: partial`") can't be tested literally, because the script no longer emits a skipped `update_roadmap_feature` step anywhere. Its intent, that the not-found case yields `partial`, is met. Honest wording: "A ROADMAP feature the cascade cannot find, whether no `Downstream:` line references the plan slug or that line has no enclosing `### ` heading, yields `cascade_status: partial`, recorded as a `failed` `update_roadmap_feature` step carrying the design's 'no matching feature entry was found' detail." Worded that way it covers both arms, and only the first arm is tested today.
  - The second is met by scenario 28, for the first arm.
  - The third ("The verdict matches the worked example") is already literally true. The example's `cascade_status` is `partial` and so is 7cd13d1's. What doesn't match is the step's `status`, which the criterion never mentions. Honest wording: "The verdict and step status match the worked example for this case in DESIGN-completion-cascade.md, amended to show `failed`." Withdrawn or not, it has to point at the document.
- On its own, (b) leaves the design's five contradictory passages in place. It's only complete when paired with (a), or with a hand-off to #358 as in (d).

**(c) Change the code back to `skipped` while keeping `partial`.**
- Files: `skills/execute/scripts/run-cascade.sh` (:508-512 and :519-523, where the status goes back to `skipped` with `ANY_FAILED=true` kept; plus the handler comment at :485-493, which argues the opposite) and `run-cascade_test.sh` (scenario 28's assertion at :2579 and its header comment at :2500-2517). Also the `:1129-1136` verdict comment, which lists what `partial` means.
- What it breaks:
  - `partial` would no longer hold exactly when some step failed. The script would have two kinds of `skipped`: the benign ones (`delete_roadmap` with an open issue under a `completed` verdict, the two `lifecycle_post_verify` skips) and one that forces `partial`. A reader of `steps[]` couldn't tell them apart without parsing `detail`. It also contradicts the post-verify-seed design's rule that a skipped step leaves `ANY_FAILED` alone.
  - Setting a variable named `ANY_FAILED` from a skipped step is misleading on its face.
- It needs a READ-ONLY file. execute.md's halt filter (`select(.status == "failed")`) would print nothing for this shape, so the agent would halt and surface no reason. Its glossary ("at least one failed") would also become false. Both would need editing. The `execute-plan-completion-cascade` eval's "surfaces the failed steps" would then describe an empty list.
- Reopening #353's choice as a code change is out of scope for this exploration.

**(d) Other resolutions I find more natural.**
- **(d1) Close #354 as done by #353 now and hand the document fix to #358.** Files: none now. #354's own comment says the fix moved "in PR #353 itself", but #353's body says only `Fixes #346` / `Fixes #347`, which is why #354 stayed open. The catch is that #358's suggested scope reads "keeping the report schema and worked examples as they are", which would keep the wrong example. #358's body would need changing, see section 3.
- **(d2) Amend the design narrowly, then close #354 against its rewritten criteria.** This is (a) and (b) together: one small docs PR touching only DESIGN-completion-cascade.md, plus an issue-body edit and a closing comment naming 7cd13d1 and scenario 28. It needs neither read-only file.
- **(d3) Optional follow-up, whichever route is taken:** a scenario for the second not-found arm (`Downstream:` line with no enclosing `### ` heading). It's untested, and the first and third criteria as reworded above cover it. It touches only `run-cascade_test.sh`.

### 3. Landing against #358, and overlap with #357

- #358 (written against 9f84fa7) says "The report schema in the design is still accurate, and its worked examples are still the reference for the verdict vocabulary." Its suggested route keeps "the report schema and worked examples as they are", and its third criterion reads "The report schema and its worked examples remain available as the cascade's contract."
- On 7cd13d1 that premise is wrong in more places than the one example:
  - The schema's `action` enum (:271) lists `transition_roadmap`, which the script never emits. It omits `lifecycle_pre_probe`, `transition_brief`, `delete_roadmap`, `commit`, `push` and `lifecycle_post_verify`, all of which the script emits (see `run-cascade.sh:30-33`).
  - "The script always emits a JSON object to stdout, regardless of success or failure" (:261) is false: precondition failures go to stderr, and a usage error emits nothing (`run-cascade.sh:19-25`).
  - `check_issue_closed` is described as validating that owner/repo matches origin (:380-382, :508-511). The code deliberately doesn't (`run-cascade.sh:136-163`).
  - The ROADMAP-not-found example contradicts the shipped step status.
- Taking #358's third criterion literally would canonize a contract the code doesn't honour. Whatever else happens, it needs to become something like "the report schema and worked examples remain available and match the output `run-cascade.sh` emits".
- Ordering, before or inside:
  - **Before #358.** The #354 amendment is about five sentences and doesn't touch the architecture sections #358 rewrites (Components, main loop, `get_frontmatter_field`, per-skill transition scripts). Landing it first lets #354 close without waiting on a larger rewrite. #358 then inherits a correct example, and its third criterion only needs "as they are" read against the amended doc.
  - **Inside #358.** Workable only if #358's body is edited to add "correct the ROADMAP-not-found example and the four prose passages to `failed`" and to drop "as they are". Otherwise the #358 worker is told to preserve the contradiction.
  - Either way, #358's third criterion and suggested scope need editing. Its line references are stale too: it cites `run-cascade.sh:800` and `:845-905`, and the walk now sits at `:880-956`.
- **#357** (the `--strict` vocabulary) doesn't touch DESIGN-completion-cascade.md, which never mentions `--strict` or "strict mode". Its overlap is with execute.md, where the prose says "strict-mode" (read-only here), and with `run-cascade_test.sh`, whose stubs match on `--strict` and which also holds scenario 28. It isn't a conflict for a docs-only amendment. It only matters if (c) or (d3) edits the test file at the same time.

### 4. Conventions for amending a Current design, and validator constraints

- `skills/design/references/lifecycle.md` covers only state transitions (Current lives in `docs/designs/current/`; Superseded requires `--superseded-by`). No written rule says a Current design's body is frozen, and none describes how to amend one. CLAUDE.md and AGENTS.md say nothing about it either.
- Precedent from git history:
  - **Dated Amendment section.** 26465a2 ("docs: amend session-work-summary scope for two shipped defects (#224)") appended `## Amendment — 2026-07-06: ...` to `DESIGN-session-work-summary.md` (:543), with "The design above is unchanged; this amendment adds...". The same pattern appears in `DESIGN-scope-consolidation-over-skipping.md`, `DESIGN-scope-artifact-persistence.md`, `DESIGN-roadmap-plan-standardization.md` and `DESIGN-scope-chain-mandatory-steps.md`. This pattern records new decisions made after shipping.
  - **In-place edit.** fc9133e (#305) edited DESIGN-completion-cascade.md in place to add `schema: design/v1`. Many feature commits modify `docs/designs/current/*` in place (#336, #318, #311, #297, #302, #271, #264, #252).
- For this case the defect is an internal contradiction in the body. The error table and Mitigations already say failure and `partial`, while five passages say `skipped`. An appended Amendment section would leave the contradicting passages in the body. That makes it the weaker fit here; an in-place correction plus, optionally, a one-line dated note is the more natural fit. The history allows either.
- Validator constraints (`crates/shirabe-validate/src/formats.rs:296-316`): design/v1 requires the frontmatter fields `status`, `problem`, `decision` and `rationale`, a valid status, and nine required sections (Status through Consequences). L07 checks that a Current design sits in `docs/designs/current/`. Nothing constrains body content changes. The one live signal is the non-blocking FC10 em-dash density notice (10.4 per 1000 words against a threshold of 10).

### 5. Existing issues for the design's internal contradiction

I searched open and closed issues for "DESIGN-completion-cascade", "update_roadmap_feature", "worked example cascade" and "cascade skipped partial".
- None names the contradiction between the design's `skipped` passages and its error table, or between the example and the shipped `failed`.
- #358 is the closest, and it asserts the examples are accurate.
- #354 cites the example as its evidence.
- Adjacent open issues on the same function or verdict:
  - #362: `update_roadmap_feature`'s awk substitutions can match nothing and still record `ok` at `run-cascade.sh:579`, and the `git add ... || true` sites record `ok` too.
  - #355: a blocked finalize-chain node is recorded `ok`.
  - #356: `partial` shares its route with the other verdicts.
  - #361: `/work-on` standalone.
- Closed issues #186, #307 and #328 are about post-verify seeding and aren't relevant.

## Implications

- Only one production reader depends on the step label for this case: execute.md's `select(.status == "failed")` halt filter. On 7cd13d1 it works: the not-found case halts and surfaces the design's detail text. The label change in #353 is load-bearing for that consumer, not just cosmetic. Any resolution that keeps `failed` needs no change to either read-only file.
- Resolution (c) is the only one that reaches a read-only file (execute.md's filter and glossary). It also breaks the invariant that the test suite and the post-verify-seed design encode. Its cost is noticeably higher than the others'.
- (a) and (b) together (d2) are docs and issue-body only: about five passages in one Current design, two criteria rewritten, and #354 closed citing 7cd13d1 and scenario 28.
- However #354 closes, #358's suggested scope ("worked examples as they are") and third criterion need editing, because the schema has drifted in more places than this example.

## Surprises

- #354's third criterion is already literally satisfied. The worked example's verdict is `partial`, and so is 7cd13d1's. Only the step status, which the criterion doesn't mention, differs.
- The design's own prose at :390 always prescribed `partial` for this case. The contradiction is between "skipped" wording and a `partial` verdict inside the document, not between the design and #353.
- #354's comment says the fix moved into #353, but #353's body closes only #346 and #347, which is why #354 is still open.
- #358's premise that "the report schema is still accurate" is stale on 7cd13d1. The action enum is six values short, lists a `transition_roadmap` that's never emitted, and the "always emits JSON to stdout" and `check_issue_closed` origin claims are false.
- Scenario 28 exercises only the first not-found arm. The second arm (`run-cascade.sh:519-523`) is untested.
- Two Rust doc comments still name `skills/work-on/scripts/run-cascade.sh`.

## Open Questions

- Should the amendment be an in-place correction (my reading of what fits a contradiction) or a dated Amendment section (the #224 precedent)? The repo has no written rule.
- Does the #354 amendment land before #358, or does #358's body get edited to take it on? Either way, who edits #358's third criterion and suggested scope?
- Should the second not-found arm get its own scenario before #354 closes, given that the reworded first criterion covers both arms?
- Does anyone want `failed` reconsidered as vocabulary for "asked to do X and couldn't"? The only consumer evidence (execute.md's filter) favours keeping it.

## Summary

The only production reader of per-step `status` is execute.md's halt filter, `select(.status == "failed")` (a read-only file); evals, Rust, work-on.md and other scripts read `cascade_status` or nothing, and the test suite pins the rule that `partial` holds exactly when some step failed, with `skipped` never setting the verdict. That makes an in-place fix to about five passages in DESIGN-completion-cascade.md plus rewording #354's first and third criteria (the third is already literally met, since both verdicts are `partial`) a docs-and-issue-only fix, while reverting the code to `skipped` would break that rule and force edits to execute.md. The biggest open question is how this lands against #358, whose suggested scope keeps the worked examples "as they are" and whose third criterion calls them the contract, even though on 7cd13d1 the report schema has drifted in several more places and both need rewording whichever order is chosen.
