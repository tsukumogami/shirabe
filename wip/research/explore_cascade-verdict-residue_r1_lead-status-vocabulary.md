# Lead: What rule does the cascade's per-step status vocabulary (`ok` / `skipped` / `failed`) follow in practice, and where does "ROADMAP feature not found" fall under it?

All script line numbers below are at 7cd13d1 unless a different commit is named.
10e46f4 is the parent of 9f84fa7 (#345).

## Findings

### 1. Every non-`ok` `add_step` arm in run-cascade.sh

| # | Line | Action | Status | Condition | Sets ANY_FAILED? | What it means for the chain |
|---|------|--------|--------|-----------|------------------|-----------------------------|
| 1 | :509-511 | update_roadmap_feature | failed | no `Downstream:` line in the ROADMAP names the plan slug | yes, same arm | Asked to mark this chain's feature Done and couldn't. A re-run hits the same result; a human has to edit the ROADMAP |
| 2 | :520-522 | update_roadmap_feature | failed | `Downstream:` found, but no enclosing `### ` heading above it | yes | Same as 1, with the same detail text |
| 3 | :671-672 | delete_roadmap | skipped | every feature is Done but a referenced issue is still open | **no** | Deferred on purpose. The feature update already went through at `ok` (:579). The ROADMAP's own deletion waits on external state, and the detail says to "run the cascade again after it closes". Scenario 12 (run-cascade_test.sh:1271-1321) pins `completed` for this |
| 4 | :686-688 | delete_roadmap | failed | `git rm` of the ROADMAP failed | yes | Asked and couldn't |
| 5 | :807-809 | lifecycle_pre_probe | skipped | the chain already passes ready posture | n/a (emits `skipped` and exits 0 on the spot) | Nothing to do |
| 6 | :937-939 | transition_design | failed | finalize-chain reported an `error` node | yes | Asked and couldn't |
| 7 | :942-944 | transition_design | failed | finalize-chain reported an unknown action | yes | Asked and couldn't |
| 8 | :960-966 | transition_design | failed | finalize-chain exited non-zero (refused a node) | yes | Asked and couldn't |
| 9 | :1003-1005 | delete_plan | failed | `git rm` of the PLAN failed | yes | Asked and couldn't |
| 10 | :1040-1044 | commit | failed | `git commit` failed | yes | Asked and couldn't |
| 11 | :1052-1055 | push | failed | `git push` failed | yes | Asked and couldn't |
| 12 | :1096-1098 | lifecycle_post_verify | failed | the post-cascade ready check failed | yes | The chain didn't reach its terminal state |
| 13 | :1113-1114 | lifecycle_post_verify | skipped | no recorded chain document survived the commit | **no**, and the comment at :1110-1112 says that's deliberate | Nothing left to verify (PRD-cascade-post-verify-seed R4) |
| 14 | :1123-1124 | lifecycle_post_verify | skipped | the commit block ran but the commit didn't land | no (the comment at :1121 says it's already true from row 10) | Can't verify, because an earlier step failed |

Some "not done" outcomes record no step at all. `handle_roadmap_deletion` returns silently when the file is missing or some feature isn't Done (:630-651). A dry run records no post-verify step. A VISION stop records none either (:929-932).

### 2. The rule the script follows

At 7cd13d1 the mapping between `failed` and `ANY_FAILED=true` is exact, in both directions. Every `failed` arm sets the flag in the same block, and no `skipped` arm sets it. Since the verdict is `partial` iff `ANY_FAILED` (:1150-1156), the working rule is "`partial` iff at least one step is `failed`". There's no exception at 7cd13d1 in either direction.

The only `skipped` step that ever appears next to `partial` is row 14. It never causes the `partial`: it's the downstream consequence of row 10's failure.

In practice `skipped` covers three meanings, and none of them is "asked and couldn't":
- **Nothing to do**: rows 5 and 13.
- **Couldn't check because of an earlier failure**: row 14.
- **Deliberately deferred on a condition outside the cascade's control**: row 3.

At 10e46f4 and 9f84fa7 the mechanics were the same rule: `skipped` never touched `ANY_FAILED`. What #353 changed is where "feature not found" is filed. It moved from the `skipped` bucket to the `failed` bucket, and the rule itself stayed put.

A second consumer depends on the rule. execute.md's halt block (around :715-722) prints only `select(.status == "failed")` steps on a `partial`. A `partial` driven by a `skipped` step would halt with nothing printed. So the step status isn't only cosmetic: the design's worked example (`skipped` + `partial`) is incompatible with how execute.md surfaces the reason for a halt.

### 3. What sibling documents say

**PRD-cascade-post-verify-seed.md R8 (:233-239).** It says the per-step vocabulary "gains no new value — R4 reuses `skipped`, already in use at `:404`, `:414`, `:564` and `:698` — and is otherwise unchanged". The PRD was committed in 9f84fa7, and its line numbers resolve against the parent commit, 10e46f4:
- :404 and :414 are the **two** `update_roadmap_feature` "not found" `skipped` arms.
- :564 is the `delete_roadmap` open-issue skip.
- :698 is the `lifecycle_pre_probe` no-op skip.

The same PRD's :885 is `git commit` and :909/:912 are the post-verify failed/ok arms, which confirms the base. So half of that PRD's cited precedent for `skipped` is the two arms #353 turned into `failed`. R4 (:194-202) defines the new skip as not setting `ANY_FAILED` and says "a run that verified nothing must not be reported as one that verified something". That's consistent with the "skipped never forces partial" rule.

**DESIGN-completion-cascade.md (Current).** This is the only document that still pairs `skipped` with `partial` for this case, and it contradicts itself in several places:
- The error-message table (:293-305) lists "ROADMAP feature not found" in a column headed "Failure". The same table also lists "Issue still open", which the script records as `skipped` with a `completed` verdict (Scenario 12). The prose above the table says it covers "Every `skipped` or `failed` step" (:281). So appearing in the "Failure" column doesn't decide a step's status. #353's argument ("already lists that case under Failures") therefore proves too much.
- The worked example (:340-356) shows `update_roadmap_feature` at `"status": "skipped"` with `"cascade_status": "partial"`.
- The `handle_roadmap` step list (:407-410) says "record a `skipped` step with the prescribed 'feature not found' message and return".
- :388-391 and :572-574 say the lookup "sets `cascade_status: partial`" and "skips the update". :563-564 still calls it "silently skipped".
- :425 says the directive checks "whether any `failed` or `skipped` steps require follow-up".
- Nothing in the doc defines `skipped` against `failed`, or how `cascade_status` is derived from steps.

PR #353 changed only four files (execute.md, evals.json, run-cascade.sh and its test). It left all of this untouched.

**DESIGN-skill-cascade-lifecycle-check.md (:271-293).** It covers only the pre-probe skip, which yields the `skipped` verdict, and a post-verify failure, which yields `partial`. It still says a post-verify failure "exits non-zero", which is stale: the script now exits 0. It doesn't define step-level `skipped`.

**PRD-finalize-chain.md R8 (:107-116) and R10 (:124-130).** They preserve the `cascade_status` vocabulary and the step shape, and the "skipped and partial cases" for covered scenarios. Neither defines step semantics. R8's action enum names `transition_roadmap`, which the script never emits (it uses `delete_roadmap`).

**DESIGN-finalize-chain.md (:110-119).** The script "aggregates `cascade_status`", and no aggregation rule is stated.

**run-cascade.sh header (:19-47).** It lists the status enum and says `detail` is required for `skipped`/`failed`. It gives no semantics. The emit comment (:1129-1136) lists what causes `partial`: "finalize-chain refused, an error node, git rm failed, the finalization commit or push failed, or the post-cascade verification failed". It **omits ROADMAP feature not found**, which is stale after #353. It also says `completed` means "every node transitioned cleanly", which Scenario 12 contradicts: the ROADMAP stays un-deleted and the verdict is still `completed`.

**execute.md (read only).** #353 rewrote the `partial` definition (:726 at 9f84fa7) from "a transition was skipped" to "a transition was refused". That removed the second source #354 cited. The recovery list (around :737-743) names failed push, failed commit, refused `transition_*` with or without a commit, and failed `lifecycle_post_verify`. It has **no entry for a failed `update_roadmap_feature`** or a failed `delete_roadmap`.

### 4. `failed` vs `skipped`: is the not-found / open-issue split principled?

I think yes, on two of the three candidate criteria. The third doesn't discriminate.

- **Whose node.** The feature entry is this PLAN's own record on the ROADMAP. Not updating it leaves this chain's own finalization undone. Deleting the ROADMAP is a whole-initiative event that happens to trigger here, after this chain's own work (`update_roadmap_feature ok`) has already succeeded.
- **Whether a re-run fixes it without a human.** A re-run of not-found gives the same result every time, because somebody has to edit the ROADMAP. The open-issue skip is framed as fixing itself once the issue closes.
  - Caveat: that path is shaky. A `completed` run deletes and pushes the PLAN, and run-cascade.sh exits 1 when the PLAN doc isn't found (header :45). So "run the cascade again" can't mean re-running on that PLAN. Only a later cascade from another plan on the same ROADMAP would reach `handle_roadmap_deletion`. If this was the last feature, nothing in the script re-attempts the deletion.
- **The posture the post-cascade check attests to.** This criterion doesn't discriminate the two cases. Scenario 28's comment (run-cascade_test.sh:2506-2513) says that with the skip, the published tree *passed* the ready-mode lifecycle check while the feature was still `Planned`. The check doesn't look at ROADMAP feature status. The claim at run-cascade.sh:486-489 ("the chain does not reach the posture the post-cascade check attests to") holds only because `ANY_FAILED` gates the PLAN append, and that gate is what keeps the PLAN alive and the check red. The argument is circular.

The "nothing publishes" outcome is also specific to one shape. In a chain carrying a DESIGN, `STAGED_FILES` is already non-empty from the DESIGN transition. So the commit fires and publishes the index, including the PLAN `git rm`, even with `ANY_FAILED` set (:990-995 explains that the array only gates whether a commit happens). Post-verify then runs against the DESIGN and probably passes. That run reports `partial` with `commit`/`push` at `ok`. What the `failed` label reliably buys is the verdict plus execute.md's halt and the surfacing of the reason. Publication is held back only in the PLAN→ROADMAP-only shape.

Recording not-found as `skipped` while still setting `ANY_FAILED` would have produced the same verdict and the same publish gating. It would have been the one exception to the one-to-one mapping, and execute.md's `failed`-only filter would have halted without saying why. That's the strongest concrete argument for `failed`.

### 5. Did #353 argue the vocabulary?

Only by citation, and only in the PR body and commit message. The PR has no reviews, no review comments and no inline comments (`gh api .../pulls/353/comments` returns nothing). The squash commit message says "DESIGN-completion-cascade.md already lists that case under Failures with the exact detail text the script emits, so only the status was wrong". The rest of the argument is about why `ANY_FAILED` must be set: the skip left it false and a PLAN→ROADMAP chain published green.

The PR never mentions the worked example at :340-356, which shows the opposite status. It doesn't mention the "Issue still open" row in the same table, and it doesn't weigh "`skipped` plus `ANY_FAILED`" as an option. Its mutation list includes "a roadmap-feature-not-found recorded as a skip", which presumably means a skip without the flag.

The #354 update comment by the issue owner points at the worked example as the prescription. #353 took the table row instead. Nobody reconciled the two.

## Implications

- The behaviour #354 wanted (not-found gives `partial` and a halt) shipped. The residue is documentary plus acceptance-criteria wording. It's not a behavioural gap in the verdict.
  - AC1 ("a skipped `update_roadmap_feature` step yields partial") is literally unsatisfiable at 7cd13d1 because no such step exists any more, but its intent is met.
  - AC3 (matches the worked example) holds for the verdict and not for the step status.
  - The honest closing note for #354 is that the criterion's wording was tied to the design's example, and the example is what's wrong.
- The document to amend is DESIGN-completion-cascade.md: the worked example status at :352, the `handle_roadmap` step at :409-410, and the wording at :390, :425, :563-564 and :573. It would also help to state the rule explicitly: `failed` iff `ANY_FAILED`, and `skipped` means nothing to do, deferred, or unverifiable. It could also relabel the table column, since it mixes skip and failure classes.
- run-cascade.sh's emit comment (:1131-1133) should add ROADMAP feature not found to the `partial` list. Its `completed` definition (:1136) overstates what completed means.
- PRD-cascade-post-verify-seed R8 now cites two arms that are `failed`. Whether a point-in-time PRD gets amended is a policy question; the rest of the doc can't point to it as current truth either way.
- Two neighbouring gaps turned up (not asked for, but they bear on "gap nobody named"):
  - execute.md's recovery list has no entry for a failed `update_roadmap_feature` or `delete_roadmap`. Another worker owns that file.
  - The open-issue deferral's "run the cascade again" has no evident trigger once the PLAN is gone.

## Surprises

- The design's own "Failure" table includes "Issue still open", which ships as `skipped`/`completed`. The table can't be the authority #353 treated it as.
- execute.md's halt surfaces only `failed` steps. That makes the `failed` label load-bearing for the caller even though the verdict doesn't depend on it, which contradicts the scope framing that this is "only vocabulary".
- The ready-mode post-cascade check doesn't attest ROADMAP feature status at all. A DESIGN-bearing chain with a missing feature still publishes and verifies green, and only the verdict flags it.
- The PRD-cascade-post-verify-seed R8 precedent list was half made of the very arms at issue.
- The open-issue skip's detail tells the reader to "run the cascade again", but the PLAN it would need has been deleted and pushed.

## Open Questions

- Are `docs/designs/current/` docs amended in place to track later behaviour changes, or treated as historical? That decides whether DESIGN-completion-cascade.md is "the document to amend" or needs a superseding note.
- Should PRD-cascade-post-verify-seed R8 be touched at all, given it's a requirements record for #345?
- Is anything outside run-cascade.sh meant to re-attempt ROADMAP deletion after the last open issue closes? If not, the open-issue skip is less "deferred" than its detail claims, and it might deserve its own issue.
- Should execute.md's recovery list gain a failed `update_roadmap_feature` shape? That's out of this worker's scope, since another worker owns the file.

## Summary

At 7cd13d1 the script follows an exact rule: every `failed` arm sets `ANY_FAILED` and no `skipped` arm does, so `partial` iff some step failed. `skipped` means nothing to do, deliberately deferred, or unverifiable, never "asked and couldn't", and "ROADMAP feature not found" correctly falls under `failed`, which execute.md's `failed`-only halt filter also needs. The residue is documentary rather than behavioural: DESIGN-completion-cascade.md (worked example :340-356, handler step :409-410, and surrounding prose) and the script's own emit comment (:1131-1133) still describe the old skip, #354's AC wording was tied to that wrong example, and PRD-cascade-post-verify-seed R8's `skipped` precedent (:404/:414 at 10e46f4) was exactly the two arms #353 flipped. The biggest open question is whether Current designs are amended in place. Secondary gaps: the open-issue `delete_roadmap` deferral has no evident re-run path once the PLAN is deleted, and execute.md's recovery list has no entry for a failed `update_roadmap_feature`.
