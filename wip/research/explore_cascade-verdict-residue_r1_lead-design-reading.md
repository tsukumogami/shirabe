# Lead: What does DESIGN-completion-cascade.md actually say about a ROADMAP feature the cascade cannot find, read as a whole document?

All line numbers are against 7cd13d1 (the worktree HEAD is 7cd13d1 plus one wip-only commit, 52a4a3a, which touches nothing under `docs/designs/` or `skills/`).

## Findings

### 1. Every passage that touches the case

Eight places in `docs/designs/current/DESIGN-completion-cascade.md` speak to it. Seven agree with each other: step `skipped`, verdict `partial`. The table can be read either way, and it's the only one that doesn't name a step status at all.

| Line(s) | Passage (quoted) | Step status implied | `cascade_status` implied |
|---|---|---|---|
| :274-275 | `"status": "ok \| skipped \| failed"`, `"detail": "<human-readable description — required when status is skipped or failed>"` | n/a (schema) | n/a |
| :281-283 | "The `detail` field is the recovery surface. Every `skipped` or `failed` step must include a sentence that names what was being attempted and why it could not proceed" | Says a skipped step carries a detail just as a failed one does, so a step having a detail tells you nothing about which status it has | n/a |
| :291-294, :296, :302 | "**Error message contract:** Each failure class has a prescribed message format so the agent sees consistent, parseable descriptions" / column header `Failure` / row `ROADMAP feature not found` with the detail text | **None stated.** The table gives a detail string. It never gives a `status` value. Only the column header ("Failure") and the lead-in ("failure class") point toward failure | None stated |
| :340-356 | "**Example output — ROADMAP feature not found:**" ... `"cascade_status": "partial"` ... `"action": "update_roadmap_feature"`, `"status": "skipped"`, detail = the :302 string word for word | `skipped` | `partial` |
| :385-391 | "If no `**Downstream:**` field references the plan slug, `handle_roadmap` logs a warning, sets `cascade_status: partial`, and skips the update rather than silently succeeding." | "skips the update" (skip wording) | `partial` |
| :407-410 | `handle_roadmap` step 1: "If not found, record a `skipped` step with the prescribed "feature not found" message and return — do not update the file." | `skipped` (explicit) | not stated here |
| :421-425 | "The `plan_completion` directive reads this output and uses the `steps` array to determine `cascade_status` and whether any `failed` or `skipped` steps require follow-up." | Puts `failed` and `skipped` side by side as things that need follow-up | Loosely implies the verdict comes from the steps, but no mapping is given |
| :562-564 (Consequences, Negative) | "If the feature entry doesn't mention the plan slug, the update is silently skipped." | skipped | reads as *not* surfaced, i.e. `completed` |
| :572-574 (Mitigations) | "The ROADMAP feature lookup logs a warning if no matching entry is found, setting `cascade_status: partial` rather than silently succeeding. The agent can then surface this to the user." | (not stated) | `partial` |

A few other passages sit close by. :306-307 says the VISION terminal emits no step and "the overall status reflects work done up to that point". :462-463 lists the Phase 1 tests: "Missing upstream ... → `cascade_status: skipped`" and "Partial chain (DESIGN found but upstream PRD does not exist → `cascade_status: partial`)". The partial-cascade example at :309-338 shows a missing upstream file as `failed` with `partial`. That's the only worked example of a `failed` step, and it covers the "Upstream file not found" row, not the ROADMAP one. Step 3 of `handle_roadmap` at :414-416 describes the open-issue check as a guard: "Only transition if all referenced issues are confirmed closed." It isn't described as a failure.

### 2. What the :296-304 table actually is

The table's section heading is "**Error message contract**" (:291), and its stated purpose is "so the agent sees consistent, parseable descriptions" (:293-294). It has two columns, `Failure` and `` `detail` message ``. There's no status column. So it's a contract for message format. The column header and the words "failure class" are the only textual basis for reading every row as `status: failed`, and :281-283 has already said skipped steps need a detail too. Nothing in the document is titled "Failures". The code comment at run-cascade.sh:488-489 says the design "lists 'ROADMAP feature not found' under Failures", and the PR #353 body says "already lists that case under Failures". Both take the column header as a section title.

Here's each row against what run-cascade.sh does at 7cd13d1:

| Row | Status the code records | Does the code use the table's text? |
|---|---|---|
| Upstream file not found | `failed` (finalize-chain exits nonzero, so :958-966 records `transition_design` `failed` and sets ANY_FAILED) | No. The detail is "finalize-chain exited N while walking ... : <engine error>" |
| Path escapes repo | `failed` (same finalize-chain refusal path; the engine message is "path resolves outside the repository work tree", crates/shirabe-validate/src/finalize.rs:1261) | No |
| File not git-tracked | `failed` via the same path (the text lives in the validator, checks.rs:1336, as "[R6] upstream ... is not tracked by git") | No |
| Transition script failed | `failed` via the same path | No. There are no per-skill transition scripts any more. finalize-chain replaced them |
| ROADMAP feature not found | `failed` since #353 (:508-512, :519-523), which sets ANY_FAILED. It was `skipped` before #353 | **Yes**, word for word. This is the only row whose text the code reproduces exactly |
| Issue still open | **`skipped`**, with ANY_FAILED untouched (`delete_roadmap` arm, :670-673) | Reworded. It says "not deleting $path" where the table says "not transitioning <target> to Done", and the action is `delete_roadmap`, which isn't in the design's action enum at :271 (that enum has `transition_roadmap`) |
| Unknown artifact type | `failed` (the `error` node at :933-940 sets ANY_FAILED) | No. finalize.rs:727 says "has an unrecognized filename prefix; stopping chain walk" |

The "Issue still open" row settles the question. It's in the same table under the same `Failure` header, but the design's own step 3 (:414-416) treats it as a guard, and the code records it as `skipped`. It never sets ANY_FAILED, so it can yield `completed`. If the table really classified every row as `failed`, the code would be violating it on this row today, and nobody has said so. The table can't be both a status classification and correct for that row. The consistent reading is that it lists every case that gets a `detail` and prescribes the message for each, whatever the status.

The PR's argument that the row "already" prescribes the exact text the script emits holds for this one row. That's because this row is the only place the code copied the table's text. It says nothing about status.

### 3. One model, two halves, or something else?

Read whole, the design has one consistent model for this case: the step is `skipped` and the cascade is `partial`. Step 1 of `handle_roadmap` (:409), the worked example (:352, :344) and the text-substitution prose (:390) all say so. Mitigations (:573) repeats the verdict. The schema rule at :275/:281 makes the detail requirement the same for both statuses, so the table doesn't pull the other way.

There are two outliers, and neither is the table:

- **Consequences :562-564** says the update is "silently skipped". That contradicts the Mitigations bullet eight lines later (:572-574: "setting `cascade_status: partial` rather than silently succeeding"), and the :390 prose ("rather than silently succeeding"). The most plausible reading, which is inference: Consequences states the raw risk of the heuristic and Mitigations states the answer to it. That's a common design-doc pattern. Still, "silently" is literally false under the doc's own model.
- **The table's column header and lead-in** ("Failure", "failure class") use "failure" loosely, meaning "couldn't proceed", which is the phrase :282 uses. That loose word is what PR #353 read as a classification.

The coordinator's framing ("the Failures table says failed, its worked example says skipped") doesn't hold up as a contradiction inside the design. The design never says `failed` for this case. The code at 7cd13d1 contradicts the design on step status (it records `failed` where the design says `skipped`) and agrees with it on the verdict (`partial`).

There's a deeper gap: the design implies a derivation rule it never writes down. :390 and :573 say a skipped ROADMAP step "sets `cascade_status: partial`". But the design never says what a skipped step does to the verdict in general, and it gives the open-issue guard skip no verdict at all. The code's rule (run-cascade.sh:1128-1156) is `partial` iff ANY_FAILED, and a `skipped` step never contributes. The code has other `skipped` steps that deliberately don't affect the verdict: `delete_roadmap` on an open issue at :671, and `lifecycle_post_verify` at :1110-1114 ("ANY_FAILED is deliberately untouched"). Under the code's rule, a design that wants "skipped and partial" for this one case needs a special exception. That's exactly the gap #354 described, and #353 closed it by changing the status instead of adding the exception.

### 4. History

The design has three commits (`git log -- docs/designs/current/DESIGN-completion-cascade.md`):

- **67b7839** (2026-04-21, #67, "feat(work-on): add koto state machine...") created it, and it has lived in `docs/designs/current/` since that commit.
- **9f45603** (2026-08-14, #271, chain-cardinality) added only :285-289, the paragraph on `ok` steps that carry a detail. That commit's message describes "the specification corrections that bring the written contracts back in line with what the tooling does".
- **fc9133e** (2026-08-15, #305) added only `schema: design/v1` at :2.

`git blame` shows every line in :259-305 except the six :285-289 lines (plus the blank after them) comes from 67b7839. Lines :340-425 and :544-578 are 100% 67b7839. None of the ROADMAP-not-found passages has been touched since the doc was first written. That includes the table, the example, the step list, the prose, Consequences and Mitigations. PR #353 (7cd13d1) didn't change the design.

On a derivation rule: the design has none. The nearest things are :424-425 (the directive "uses the `steps` array to determine `cascade_status`", which oddly puts the derivation on the directive's side), :248 ("Exit 0: cascade ran (completed, partial, or skipped)"), the Phase 1 test bullets at :462-463, and the per-case assertions at :390/:573. The only written rule is in the code: the header at run-cascade.sh:1128-1138, where `partial` means "something failed", and `execute.md:754`, where partial means "at least one failed (a transition was refused, an upstream was missing, the finalization commit or push failed, or the post-verify failed)". Note that #354 quotes `execute.md:726` at 9f84fa7 as saying "a transition was skipped". At 7cd13d1 that line reads "a transition was refused", so #353 reworded it.

The design has also drifted in ways nobody has amended. It names `skills/work-on/scripts/run-cascade.sh`, but the script now lives at `skills/execute/scripts/run-cascade.sh` and the old path doesn't exist. It describes per-skill `transition-status.sh` scripts, which finalize-chain has replaced. Its action enum is missing `transition_brief`, `delete_roadmap`, `commit`, `push`, `lifecycle_pre_probe` and `lifecycle_post_verify`. And it says `transition_roadmap` where the code does `delete_roadmap`. The script header (run-cascade.sh:26-40) is where the current contract actually lives.

### 5. Lifecycle status and how to amend a Current design

Frontmatter says `status: Current` (:3), and `## Status` says Current (:32). Per `skills/design/references/design-format.md:205-233`, Current means "The PLAN has shipped. The DESIGN documents the current architecture", and the only transition out is to Superseded. The format reference has no rule for editing a Current design in place.

The repo shows two conventions in practice:

- **Dated appended amendment sections** for new decisions or shipped defects. Examples: `## Amendment — 2026-07-06: ...` in `DESIGN-session-work-summary.md:543` (commit 26465a2, "docs: amend session-work-summary scope for two shipped defects (#224)", which says "The design above is unchanged; this amendment adds..."), `## Amendment — 2026-08-15` / `2026-08-16` in `DESIGN-scope-consolidation-over-skipping.md:825,874`, and `## Amendment to Decision 6 — 2026-08-15` in `DESIGN-roadmap-plan-standardization.md:801`. `DESIGN-scope-artifact-persistence.md:445` even records "Two shipped documents | Appended dated amendment sections" as a practice.
- **Small in-place corrections** that bring a contract back in line with the code. The precedent is on this very design: 9f45603 added the `ok`-detail paragraph in place, with no Amendment heading, as one of the "specification corrections".

## Implications

- The residue isn't "two halves of the design disagree". The design agrees with itself on `skipped` + `partial`. The code chose `failed` + `partial`. The verdict #354 cared about is delivered, and only the step status differs from the design.
- The PR #353 rationale and the code comment at run-cascade.sh:485-493 both rest on a misreading ("lists ... under Failures"). The table is a message contract, and its own "Issue still open" row is recorded as `skipped` in the code. The comment is also self-contradictory against the design's step list at :409, which says `skipped` outright. Whichever way this is resolved, that comment should stop citing the design as its authority.
- #354's first criterion ("a skipped `update_roadmap_feature` step yields `cascade_status: partial`") and third ("matches the worked example") were written faithfully against the design. They aren't wrong about the design. They're only unmet in the literal sense, because the step is no longer skipped. The second criterion (a scenario asserting `partial`) is met by Scenario 28.
- #353 had a substantive reason to prefer `failed`: under the code's rule, `partial` iff ANY_FAILED, "skipped + partial" needs a one-off exception. `failed` also gates the PLAN deletion out of STAGED_FILES (run-cascade.sh:999), which is what keeps a half-finalized chain from publishing (Scenario 28's `git archive HEAD` assertion). A `skipped` step that still forced `partial` would need its own STAGED_FILES gate to keep that property, because the gate keys on ANY_FAILED. That's behaviour, not wording, so it's a real argument for `failed` over the design's `skipped`.
- If the design is amended, the repo's conventions allow an in-place correction, following 9f45603's precedent, for three things: :352, :409, and the "silently skipped" sentence at :564. A dated Amendment section fits better if the amendment also states the verdict-derivation rule (`partial` iff a step `failed`, with `skipped` never affecting the verdict) and decides what the "Issue still open" row means under that rule. The design has drifted elsewhere too (script path, action enum, finalize-chain), so any amendment will have to choose how much of that it takes on.

## Surprises

- There's no "Failures" section in the design. The label that #353's comment and PR body cite is a column header in a table titled "Error message contract".
- The "Issue still open" row sits in the same table, the code records it as `skipped`, and it can end `completed`. That's direct evidence the table was never a status classification. It also means #353's reading, applied consistently, would call the `delete_roadmap` arm a bug, and nobody has argued that.
- Of the seven rows, "ROADMAP feature not found" is the only one whose prescribed text the code reproduces word for word. The finalize-chain refactor quietly replaced the other five rows' texts with engine messages (the sixth, "Issue still open", was reworded), so the "error message contract" is mostly not honoured today, and that's undocumented.
- Consequences and Mitigations contradict each other eight lines apart ("silently skipped" vs "rather than silently succeeding"), and both have been there since the first commit.
- The design puts the step→verdict derivation on the `plan_completion` directive (:424-425: the directive "uses the `steps` array to determine `cascade_status`"). In the code, the script computes the verdict and the directive just reads it.
- The design has been `Current` since the commit that created it (67b7839 put it directly in `docs/designs/current/`), and it still names `skills/work-on/scripts/run-cascade.sh`, a path that no longer exists.

## Open Questions

- Which is authoritative for the step status: the design (`skipped`) or #353's behaviour (`failed`)? That's a human call. The STAGED_FILES gating argument favours `failed` and an amendment to the design. The design's internal consistency favours `skipped` plus an explicit exception in the verdict rule and a separate publish gate.
- Should the "Issue still open" guard (`delete_roadmap` skipped) affect the verdict? Under the design's loose "partial when something couldn't proceed" reading it arguably should. Under the code's rule it doesn't. Nobody has decided this.
- Should #354 close as delivered, with the criteria annotated to say the step is `failed` and the verdict `partial`? Or should it be rewritten against whatever the design amendment settles?
- How much of the design's other drift (script path, action enum, finalize-chain replacing the per-skill scripts, the error-message texts) should one amendment take on, versus a narrow correction covering only this case?
- Did anyone write down a verdict-derivation rule for skipped steps outside this repo's `docs/` (PRDs, the #67 PR discussion)? This lead only looked in the design, the script, `execute.md`, and the design format reference.

## Summary

Read whole, the design (unchanged on these passages since 2026-04-21) holds one model for a ROADMAP feature it can't find, step `skipped` with verdict `partial` (:352, :390, :409, :573), and its only internal contradiction is "silently skipped" in Consequences (:564). The ":296-304 Failures table" #353 cited is an "Error message contract" with no status column, and its "Issue still open" row is recorded as `skipped` in the code today (run-cascade.sh:671), so the residue is design/code disagreement on step status plus a code comment and PR rationale that misquote the design, not a self-contradictory design. The open question is whether to amend the design to `failed` and write down a "`partial` iff a step failed" rule it never states (backed by #353's point that `failed` also keeps the PLAN deletion from publishing), or return the code to `skipped` with a special verdict exception and its own publish gate.
