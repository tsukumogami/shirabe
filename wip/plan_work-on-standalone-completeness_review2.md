# PLAN Re-Review: work-on-standalone-completeness

## Verdict

PASS

## The three prior findings — closed, or a new error introduced

**Finding 1 (Issues 5/6, generic "a child session").** Closed, and correctly re-targeted. Issue 5's first criterion (`PLAN:191-198`) now names the exact failure mode: a single-pr child is dispatched with `SHARED_BRANCH`, submits `pr_status: shared`, and `pr_creation` routes it straight to `done` (verified directly: `skills/work-on/koto-templates/work-on.md:765-767`), never reaching `ci_monitor` or the new `session_role` branch. It substitutes a **coordinated** child instead of the original review's proposed **multi-pr** child — see the sharpening judgment below; the substitution is correct. Issue 6 (`PLAN:221-225`) cross-references Issue 5's constraint rather than restating it, and correctly notes a single-pr child "never gets there and would make this vacuous."

**Finding 2 (Issue 4, recovery-guidance parity with R5).** Closed. `PLAN:207-210` now reads: "The recovery guidance matches `/execute`'s for both partial shapes... Verified by comparing against `execute.md:735-740`," and states both shapes correctly. I read `skills/execute/koto-templates/execute.md:737,739-740` directly: line 737 is the failed-`push` case ("finalization commit is in local history and the fix is to push it" — the plan's "without commit and push... recovery is local" is this case merged with the no-`commit`-step case at line 739); line 740 is "A refused `transition_*` WITH `commit` and `push` at `ok`: the walk stopped partway and published what it had reached... recovery is a follow-up commit or a revert, not a reset" — matches the plan's second clause verbatim in substance. This is now a real comparison against the cited text, not an assertion that guidance merely "exists."

**Finding 3 (empty `## Dependency Graph` heading).** Closed correctly, and I verified it two ways rather than taking the author's reasoning on faith. First, `crates/shirabe-validate/src/formats.rs:230-244` (`plan_execution_mode_sections`) hard-codes the single-pr required-sections list as `Status, Scope Summary, Decomposition Strategy, Issue Outlines, Implementation Sequence` — `Dependency Graph` is not in that set, so omitting it is not a workaround, it is the specified shape. Second, `PRD-single-pr-plan-validation.md:132-135` (an already-Done PRD, i.e. the current validator behavior, not aspirational) says outright: "`Implementation Issues` and `Dependency Graph` are optional; if present, they MUST be empty." Third, I ran `shirabe validate docs/plans/PLAN-work-on-standalone-completeness.md` myself against the current file: exit 0, no output. The original review's objection rested on `plan-doc-structure.md`'s Execution Mode Differences table not listing Dependency Graph as mode-varying, but that table is incomplete relative to the actual validator and the more specific single-pr-validation PRD — the author found the more authoritative source and it settles the question. No heading, empty or otherwise, is required.

I looked specifically for an edit that reports success but didn't land (per the standing caution in this task). All three fixes are present at the cited locations with correct, verified citations (`work-on.md:762-770`, `execute.md:735-740`, `skills/execute/SKILL.md:316` and `:359-361` all checked byte-for-byte against the current files), the doc has no stray duplicate headers or dangling old phrasing (`grep -n "multi-pr child"` against the PLAN returns nothing — the old, wrong phrasing is gone, not merely supplemented), and `issue_count: 10` matches the 10 issues actually enumerated. I did not find a silent-failure edit in this file.

## The child-type sharpening — is the author right

Yes. I confirmed independently, not from the plan's own assertions:

- `skills/work-on/SKILL.md:137-140`: multi-pr "run[s] in place, one issue at a time... each landing its own PR. There is no shared branch and no cross-issue carry-forward." This is the top-level `/work-on` invocation running directly against the repo-persisted PLAN — no koto child session is spawned.
- `skills/execute/SKILL.md:48-49`: "`multi-pr` — out of scope for `/execute`; multi-pr plans run one issue at a time through `/work-on`... Direct the user to `/work-on`." `/execute` is the only thing that materializes koto children (Plan-Backed Child Mode); it explicitly does not touch multi-pr.
- The design agrees this is the present state, not just the plan's characterization of it: `DESIGN-work-on-standalone-completeness.md:305-306` says plainly "no cascade exists for multi-pr today, despite two committed documents stating that one does," and Decision 5 (`DESIGN:298-300`) describes multi-pr gaining "a third execution path in `/execute` reusing the per-child dispatch" as future work — i.e. the very capability that would let a multi-pr child exist is the migration this plan explicitly excludes.
- `skills/execute/SKILL.md:316` and `:359-361` confirm the coordinated path today dispatches each repo's issue(s) to `/work-on`'s `work-on.md` on that repo's own branch, landing its own per-repo PR — a real koto child, on its own branch, with `pr_status: created` rather than `shared`, so it reaches `pr_creation` → `ci_monitor` normally.

So the original review's proposed fix (require a multi-pr child) named a child type that cannot be constructed as a koto child today, which would have made Issue 5/6's criteria unsatisfiable as stated. The author's substitution (a coordinated child) is the only child that both exists today and exercises the new branch, and the plan is honest that this is a today-scoped constraint that changes once the migration lands.

## Per-criterion falsifiability

Issues 1, 2, 3, 7, 8 are unchanged from the original review's pass and remain sound (chain-traversal test, byte-identical relocation checks, honest anchoring review-obligation, byte-identical gate, `gh`-observed keyword check — each names a specific wrong implementation it would catch).

Issue 4: now falsifiable end-to-end, including the previously-missing R5 comparison (above).

Issues 5 and 6: now falsifiable against a constructible child. The remaining escape hatch ("If no such child can be constructed in the harness, say so and name what stands in its place") is appropriately cautious rather than a loophole — it does not let a broken implementation pass, it only defers to honest reporting if the harness genuinely cannot drive a coordinated child, which is a reasonable hedge given coordinated-path testing infrastructure isn't the subject of this plan.

Issues 9 and 10: unchanged from the original review. Issue 9's classification-table criterion ("None is left in neither category") is worded identically to the PRD's own R8 acceptance criterion (`PRD:373-377`) rather than the plan inventing weaker language, so this is not a plan-introduced gap — it inherits the PRD's own chosen strictness. Issue 10's cardinality and reachability criteria are unchanged and sound.

## Required changes

None.
