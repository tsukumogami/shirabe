# Lead: How should `/execute` land into an EXISTING branch/PR — especially a `/scope`-produced `docs/<topic>` branch with an open PR from mid-chain review — instead of always creating a new `impl/<slug>` branch + draft PR? (F1, root cause of F5/F6)

## Findings

### 1. `orchestrator_setup` ALREADY has an override path — but it's branch-name-blind and undocumented as a user surface

`skills/execute/koto-templates/execute.md` lines 231-247 (the `orchestrator_setup` prose):

> "Before running the script, check the current branch context. Derive `PLAN_SLUG` from `{{PLAN_DOC}}` (strip the `PLAN-` prefix), then run `git rev-parse --abbrev-ref HEAD` to get the current branch and `gh pr list --head <current-branch> --json number --jq '.[0].number'` to find any open PR on it. **If the current branch is non-main and an open PR already covers this work, submit `status: override`** rather than running the creation script."

The creation script it guards (lines 237-243):

```bash
PLAN_SLUG=$(basename {{PLAN_DOC}} .md | sed 's/^PLAN-//')
git checkout impl/$PLAN_SLUG 2>/dev/null || git checkout -b impl/$PLAN_SLUG
git push -u origin impl/$PLAN_SLUG 2>/dev/null || true
gh pr list --head impl/$PLAN_SLUG --json number --jq '.[0].number' | grep -q . || \
  gh pr create --draft --title "impl: $PLAN_SLUG" --body "Implements $(basename {{PLAN_DOC}})."
```

Closing line (247):

> "Submit `status: completed` after branch and draft PR exist, `status: override` if the agent is already on an appropriate branch with an existing PR (skipping branch/PR creation), or `status: blocked` ..."

**The override predicate is "current branch is non-main AND has an open PR."** It is NOT restricted to `impl/<slug>`. A `docs/<topic>` branch with open PR #167 satisfies it. So the state-machine substrate to reuse the `/scope` branch+PR EXISTS today.

The frontmatter (lines 16-37) confirms `override` is a first-class accepted `status` that routes identically to `completed` (`worktree_discipline_check`). No gate blocks it.

### 2. So why did the dogfood fail? `SHARED_BRANCH` is HARD-CODED to `impl/$PLAN_SLUG` in `spawn_and_await` — the override only skips creation, it does not redirect children

Even when `orchestrator_setup` overrides onto `docs/<topic>`, the very next state that dispatches children re-derives the branch name from scratch and ignores the branch the orchestrator actually overrode onto.

`execute.md` `spawn_and_await`, Tick 1 (lines 282-290) and Tick 2 (lines 297-305), both do:

```bash
PLAN_SLUG=$(basename {{PLAN_DOC}} .md | sed 's/^PLAN-//')
...
TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "impl/$PLAN_SLUG" '[.[] | .vars.SHARED_BRANCH = $b]')
```

`SHARED_BRANCH` is unconditionally set to the literal `"impl/$PLAN_SLUG"`. Children receive that and commit there (work-on.md line 916-917: "When `SHARED_BRANCH` is set ... Commit directly to `SHARED_BRANCH`"). So even a successful `status: override` onto `docs/niwa-default-worktree` produces children that commit to `impl/niwa-default-worktree` — a DIFFERENT branch than the one the override reused. The override and the child branch diverge. There is no variable carrying "the branch I actually settled on" out of `orchestrator_setup` into `spawn_and_await`.

This is the concrete mechanical break: **the override path is half-wired. It can skip creation but cannot propagate the reused branch to the children.** An author following the instructions literally would either (a) not hit the override path at all (it requires being on the branch already, which `/execute` invoked fresh in one sitting may not guarantee in the agent's reading), or (b) hit it and still get children on `impl/<slug>`.

### 3. `ci_monitor` / `plan_completion` use `HEAD`, not the slug — so those states ARE branch-agnostic

By contrast, `ci_monitor` (line 135) and `plan_completion` step 2 (line 362) both resolve the PR via `git rev-parse --abbrev-ref HEAD`:

```bash
gh pr ready $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number')
```

So the FINALIZATION half already targets "whatever branch we're on." The only slug-hardcoded site is `SHARED_BRANCH` injection in `spawn_and_await`. That is the single point of repair on the template side.

### 4. work-on side: the override contract recognizes (a) `SHARED_BRANCH` set, (b) explicit user instruction, (c) resuming — but plan-backed children are driven only by `SHARED_BRANCH`

`skills/work-on/SKILL.md` "Branch Setup" (lines 203-210) lists three override triggers:

> - **User instruction**: if the user asked you to continue on the current branch, submit `status: override`
> - **Plan-backed mode**: if `SHARED_BRANCH` is set, the orchestrator has already created the branch — commit directly to it with `status: override`
> - **Resuming work**: if already on a feature branch from a previous session ...

For plan-backed children (the path `/execute` uses), the operative trigger is purely `SHARED_BRANCH` (work-on.md lines 285-289: `setup_plan_backed` has `skip_if: vars.SHARED_BRANCH.is_set: true`). The child does not independently inspect "current branch has an open PR" — it trusts whatever `SHARED_BRANCH` the orchestrator injects. So fixing the orchestrator's `SHARED_BRANCH` value is sufficient and necessary; the child needs no change.

The SKILL.md-level "Branch Context Evaluation" (work-on.md lines 155-157, SKILL.md 204-210) reuse path for STANDALONE `/work-on` (not via `/execute`) does honor an explicit "work on this branch" instruction via `status: override`. But that path is not what `/execute` drives.

### 5. `/execute` SKILL has NO `--branch` / `--pr` surface today

`skills/execute/SKILL.md` "Input Modes" (lines 32-48): the only inputs are (1) a PLAN doc path, (2) empty (ask which PLAN). No branch/PR argument.

"Execution-Mode Flags" (lines 50-63): only `--auto` and `--interactive`. No `--branch`/`--pr`. Confirmed by grep — no `--branch` or `--pr` token anywhere in the SKILL.

Single-PR path Step 2 (lines 133-142) inits the orchestrator with only `--var PLAN_DOC=<path>`. There is no place to thread a target branch or PR even if the author wanted to.

### 6. There IS a latent auto-detect mechanism: the home-PR resume lookup — but it is gated on "topic in PR title," which a `docs/<topic>` brief-review PR may not match

`/execute` SKILL Resume (lines 326-343): before declaring "fresh chain," rows 8-9 run a **topic-keyed home-PR lookup**:

```bash
gh pr list --state open --search "<topic> in:title" --json number,title,headRefName
```

> "If a home PR is found ... **resume the run on the found PR's branch** ... a `/execute` invocation that starts on a different branch — or with no `wip/` scratch at all — still finds the durable home PR by topic and continues ..."

This is option (b) in embryo — it already resumes onto a found PR's branch. BUT: (1) it keys on `<topic> in:title`, and a `/scope` brief-review PR titled e.g. "docs: niwa-default-worktree brief" may or may not match the execute topic-slug search; (2) it is framed as RESUME (I-6 cross-branch resume), reached only at rows 8-9 AFTER no local state, not as a first-class "target this PR" intent; (3) when it DOES match and resume onto the found branch, the `spawn_and_await` `SHARED_BRANCH=impl/$PLAN_SLUG` hardcode (Finding 2) still fires — so children still diverge to `impl/<slug>`. The resume lookup and the child-branch injection are not connected.

### 7. The `/scope` → `/execute` handoff seam is unspecified for branch/PR continuity

`/scope` produces `docs/plans/PLAN-<topic>.md` as terminal artifact (SKILL.md lines 368-369) and records `plan_execution_mode:` in its state (line 316). Its branch behaviors (lines 341-353) are about the chain-proposal Proceed/Adjust/Bail, and its resume ladder rows 8-9 are "on-topic branch → main fallback" (lines 252, 263-272). Nothing in `/scope` hands a branch name or PR number to `/execute`; nothing in `/execute` Input Modes reads one. The two skills share only the PLAN doc path. The `docs/<topic>` branch + mid-chain review PR that `/scope` leaves behind is invisible to `/execute` except through the fuzzy title-search resume lookup.

### 8. Security/slug surfaces that any fix must respect

- The topic slug is re-validated against `^[a-z0-9-]+$` before any interpolation, including the `gh`-recovered slug on resume (SKILL.md lines 65-73, 345-347). A user-supplied `--branch`/`--pr` value would be a NEW untrusted input surface needing the same re-validation before it reaches `git checkout` / `gh` / `SHARED_BRANCH`.
- `execution_mode` is re-validated against `{single-pr, coordinated, multi-pr}` (lines 44-48).
- `plan-to-tasks.sh` independently re-validates every generated task name against R9 `^[a-z][a-z0-9-]*$` (lines 63-69) but does NOT touch the branch name — `SHARED_BRANCH` is injected by the template's jq, downstream of the script, so a branch-targeting fix lives entirely in the template + SKILL, not in `plan-to-tasks.sh`.

## Implications

**This is NOT a pure direct fix; it carries design decisions.** The cleanest minimal repair (template-only) is mechanical, but the surface choice (flag vs auto-detect vs handoff) is a design call.

Repair options, ranked:

- **(Mechanical core, required by all options) Stop hardcoding `SHARED_BRANCH`.** In `execute.md` `orchestrator_setup`, capture the settled branch (the override branch or the freshly-created `impl/<slug>`) into a context var, and have `spawn_and_await` inject THAT instead of the literal `impl/$PLAN_SLUG`. Without this, every higher-level option still routes children to `impl/<slug>`. File: `skills/execute/koto-templates/execute.md` lines 286, 300.

- **(c) Generalize the override predicate — cheapest user-facing win.** The predicate already accepts any non-main branch with an open PR (Finding 1). Make it the documented, FIRST thing `orchestrator_setup` checks, and wire its branch into `SHARED_BRANCH`. This directly solves the dogfood case: author on `docs/niwa-default-worktree` with PR #167 → override → children + finalization all land there. Low risk; reuses existing state-machine routing. Files: `execute.md` orchestrator_setup + spawn_and_await; one paragraph in `execute/SKILL.md`.

- **(b) Promote the home-PR lookup to also match the `/scope` branch.** Broaden the resume lookup beyond `<topic> in:title` to also detect "current branch has an open PR" and treat it as the home PR, then feed its branch to `SHARED_BRANCH`. Folds F1 into the existing I-6 machinery. Risk: title-search false matches; needs the branch→SHARED_BRANCH wiring anyway.

- **(a) Add `--branch`/`--pr` flags.** Most explicit, best for the one-sitting `/scope → /execute --auto` flow where the author KNOWS the target. Adds an untrusted input surface (slug/branch re-validation, Finding 8) and a new flag to the parent-skill conformance surface. Files: `execute/SKILL.md` Input Modes + Execution-Mode Flags + Security Considerations; `execute.md` (thread the var); Step 2 `koto init --var`.

- **(d) Explicit `/scope → /execute` handoff.** `/scope` records the brief-review branch/PR in its state/PLAN frontmatter; `/execute` reads it. Highest cohesion for the chained-in-one-sitting use case but touches both skills and the parent-skill state schema. Heaviest.

**Recommended shape:** (c)+core as the base fix (smallest diff, solves the exact dogfood failure), optionally (a) as the explicit operator surface for the non-chained case. (b) and (d) are the more invasive "make it automatic across the chain" investments.

**Files/repos that change:** all options are shirabe-only (public). Core: `skills/execute/koto-templates/execute.md`. Surface: `skills/execute/SKILL.md`. Option (d) also: `skills/scope/SKILL.md` + `references/parent-skill-state-schema.md`. `plan-to-tasks.sh` does NOT change. `work-on` does NOT change (children already obey `SHARED_BRANCH`).

**`impl/<slug>` naming convention:** under (c)/(a) it stays the DEFAULT (used when not overriding onto an existing branch), so back-compat is preserved; the convention simply stops being mandatory.

## Surprises

1. The override path is **already present and already branch-name-agnostic** — the lead's premise ("no documented option to target the existing branch/PR") is true at the SKILL/UX layer but the state machine accepts `status: override` for any non-main branch with an open PR. The gap is documentation + the unwired `SHARED_BRANCH`.
2. The fix is **asymmetric across states**: finalization (`ci_monitor`, `plan_completion`) already uses `HEAD` and is branch-agnostic; only `spawn_and_await`'s `SHARED_BRANCH` injection hardcodes the slug. So the divergence the author saw was children-on-`impl/<slug>` while the override (if taken) and finalization pointed at the real branch — a split-brain, not a uniform "always creates new branch."
3. `/execute` ALREADY resumes onto a found PR's branch (I-6 home-PR lookup) — option (b) is 70% built; it just isn't connected to child branch injection and keys on title-search.

## Open Questions

1. **Surface choice (human call):** explicit `--branch`/`--pr` flag (a), generalize override (c), broaden auto-detect (b), or formal `/scope → /execute` handoff (d)? The mechanical `SHARED_BRANCH` repair is needed regardless.
2. Should a `docs/<topic>` brief-review PR be treated as the `/execute` "home PR," or should `/execute` open its own and link them? (Affects the DRAFT-vs-READY discipline and the finalization cascade, which assumes it owns the PR body.)
3. If reusing the `/scope` PR, who owns its title/body? `plan_completion` runs `gh pr ready` on `HEAD`'s PR — flipping a `/scope` review PR to ready may be surprising if the author opened it for brief review, not implementation.
4. Does the home-PR title-search (`<topic> in:title`) reliably match `/scope`-produced PRs, or do their titles diverge from the execute topic-slug?

## Summary

The override substrate already exists — `orchestrator_setup` accepts `status: override` for ANY non-main branch carrying an open PR, and finalization (`ci_monitor`/`plan_completion`) already targets `HEAD` — but the fix is half-wired: `spawn_and_await` hardcodes `SHARED_BRANCH="impl/$PLAN_SLUG"` (execute.md lines 286/300), so even a successful override routes children to a divergent `impl/<slug>` branch while there is no `--branch`/`--pr` input surface and no `/scope → /execute` branch handoff. The required mechanical core is to capture the settled branch in `orchestrator_setup` and inject THAT into `SHARED_BRANCH` (shirabe-only, public, no change to `plan-to-tasks.sh` or `work-on`); the design decision riding on top is which user surface to expose — generalize the existing override (cheapest), add explicit flags, broaden the home-PR auto-detect, or formalize the chain handoff. The biggest open question is whether a `/scope` brief-review `docs/<topic>` PR should be adopted as `/execute`'s home PR (and flipped to ready by the cascade) or kept distinct and linked.
