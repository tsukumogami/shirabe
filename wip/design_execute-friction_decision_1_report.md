# Decision D1: How should /execute target an existing branch/PR (PRD R1), preserving the default path (PRD R7)?

## Source confirmation

**The override substrate already exists in `orchestrator_setup`** (`skills/execute/koto-templates/execute.md`):

- State accepts `status: {completed, override, blocked}` (lines 18-24); both `completed` and `override` route to `worktree_discipline_check` (lines 26-31).
- The prose predicate (lines 233, 247): "If the current branch is non-main and an open PR already covers this work, submit `status: override` rather than running the creation script." And: "Submit ... `status: override` if the agent is already on an appropriate branch with an existing PR (skipping branch/PR creation)."
- Finalization already targets HEAD, not a hardcoded name. `plan_completion` step 2 readies the PR via `gh pr list --head $(git rev-parse --abbrev-ref HEAD)` (line 362); `ci_monitor` reads checks off the same HEAD-derived PR (line 135). So once children land on the settled branch, the PR that gets finalized is whatever PR rides HEAD.

**The bug — `SHARED_BRANCH` is hardcoded in three places**, so a successful `override` still routes children to `impl/<slug>`:

- `orchestrator_setup` creation script (lines 238-242) hardcodes `impl/$PLAN_SLUG` for checkout + push + PR create. (Correct for the create path; this is the default branch identity.)
- `spawn_and_await` **Tick 1 — spawn** (lines 283-286): `PLAN_SLUG=...; TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "impl/$PLAN_SLUG" '[.[] | .vars.SHARED_BRANCH = $b]')`.
- `spawn_and_await` **Tick 2 — complete** (lines 297-300): the same `jq --arg b "impl/$PLAN_SLUG"` re-injection.

So even after `orchestrator_setup` correctly emits `override` (skipping creation, staying on the author's branch), `spawn_and_await` recomputes `impl/$PLAN_SLUG` from `PLAN_SLUG` and injects THAT into every child's `vars.SHARED_BRANCH`. The children obey it: `work-on.md` `setup_plan_backed` (lines 916-920) and SKILL.md lines 155-157 / 206-210 say a child with `SHARED_BRANCH` set submits `status: override` and "commit[s] directly to `SHARED_BRANCH` without creating a new one"; `pr_creation` (work-on.md 1072-1074) submits `pr_status: shared` and leaves PR ownership to the orchestrator. The child treats `SHARED_BRANCH` as an opaque branch string — it never re-derives it — so injecting the settled branch instead of `impl/<slug>` is sufficient to route children correctly. **No change to `plan-to-tasks.sh` or `/work-on` is required.**

## Options Considered

- **(a) Generalize the existing override + capture the settled branch into `SHARED_BRANCH` (auto-detect "current branch has an open PR").** The override predicate already auto-detects the case (non-main branch + open PR). The only missing piece is carrying the SETTLED branch name out of `orchestrator_setup` and into the `jq` injection in both `spawn_and_await` ticks, instead of recomputing `impl/$PLAN_SLUG`. Lowest ceremony: zero new input surfaces, zero new flags, reuses the existing enum and the existing child contract. Con: relies on the orchestrator persisting one branch-name value across states.

- **(b) Add an explicit `--branch`/`--pr` flag.** Explicit and unambiguous. Cons: new untrusted input surface that must be slug/ref-validated before interpolation into emitted shell (Security Considerations surface 1 & 6); redundant with the already-working auto-detect; raises ceremony for the common case (author is already standing on their branch). Violates the lowest-ceremony goal. The auto-detect already covers the same intent without an operator typing a branch name.

- **(c) Formalize a /scope -> /execute handoff that adopts the home PR.** `/scope` is the tactical parent that produces the PLAN and, per the Coordinated path note (SKILL.md line 190), already "creat[es] the coordination home up front" for coordinated efforts. For single-pr, a `/scope` run that authored a `docs/<topic>` PR is exactly the "author's existing branch + open PR" R1 targets. The handoff is what makes the override fire in practice (it is the supplier of the existing-PR context). Con on its own: a handoff with the SHARED_BRANCH bug unfixed still misroutes children — (c) needs (a).

## Chosen Option

**(a) generalized auto-detect override + settled-branch capture, combined with (c) home-PR adoption — and explicitly: the `docs/<topic>` PR is ADOPTED as /execute's home PR, not kept distinct+linked.**

The auto-detect predicate already lives in `orchestrator_setup`; the fix is to stop discarding the branch it settled on. (c) is the realistic source of the existing-PR context for single-pr (a /scope-authored `docs/<topic>` branch+PR), so naming the adoption rule closes R1 end-to-end. Adopt-don't-link is correct because `/execute`'s durable source of truth IS the home PR (SKILL.md State, lines 277-283: "The durable source of truth is the home pull request ... reachable from any branch through that one PR"); a second, linked PR would split the durable home and break the topic-keyed cross-branch resume (I-6, Resume lines 326-343), which finds exactly one home PR by topic. Flag (b) is rejected as redundant ceremony and a new validation surface for a case auto-detect already covers.

## Concrete Mechanism

One file: `skills/execute/koto-templates/execute.md`. Capture the settled branch in `orchestrator_setup`, then inject THAT into `SHARED_BRANCH` in both `spawn_and_await` ticks.

1. **`orchestrator_setup` — persist the settled branch.** After the create-or-override decision, write the settled branch name to a stable location both ticks can read. Minimal form: capture `git rev-parse --abbrev-ref HEAD` into a wip sentinel at the end of the setup block, e.g. `git rev-parse --abbrev-ref HEAD > wip/execute_${PLAN_SLUG}_branch` (on the override path this is the author's branch; on the create path it is `impl/$PLAN_SLUG`, preserving today's value byte-for-byte). The prose at lines 233/247 already describes the predicate; add one sentence: "On `override`, the branch you stay on (not `impl/<slug>`) is the settled branch and becomes the home PR; record it for `spawn_and_await`."

2. **`spawn_and_await` Tick 1 (lines 283-286)** — replace the hardcoded arg:
   - from `TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "impl/$PLAN_SLUG" ...)`
   - to read the settled branch: `SETTLED_BRANCH=$(cat wip/execute_${PLAN_SLUG}_branch 2>/dev/null || echo "impl/$PLAN_SLUG"); TASKS_WITH_BRANCH=$(echo "$TASKS" | jq --arg b "$SETTLED_BRANCH" '[.[] | .vars.SHARED_BRANCH = $b]')`.
   The `|| echo "impl/$PLAN_SLUG"` fallback makes the default path identical when no sentinel exists.

3. **`spawn_and_await` Tick 2 (lines 297-300)** — apply the identical substitution (the dedup re-submit must inject the same branch).

4. **Home-PR adoption rule (prose, `orchestrator_setup` + SKILL.md Input Modes / Single-PR path).** State the adoption explicitly: when entering on an author/`/scope` branch that already has an open PR (including a `docs/<topic>` PR), `/execute` ADOPTS that PR as the home PR — it does NOT open a second PR and does NOT link a distinct one. Finalization (`pr_finalization` `gh pr edit`, `plan_completion` `gh pr ready`) and `ci_monitor` already target the HEAD-derived PR, so adoption requires no change there once children land on the settled branch. One line in `/execute` SKILL.md **Input Modes** / **Single-PR Execution Path** documenting "existing-PR context (e.g. a /scope `docs/<topic>` PR) is adopted as the home PR" makes R1 explicit without new mechanism.

No change to `skills/plan/scripts/plan-to-tasks.sh`, `skills/work-on/koto-templates/work-on.md`, or `/work-on` SKILL.md — the child already treats `SHARED_BRANCH` as an opaque branch string and leaves PR ownership to the orchestrator.

## R7 Preservation

A fresh run with no existing-PR context behaves byte-identically:

- `orchestrator_setup` runs the unchanged creation script (lines 238-242), checks out / creates `impl/$PLAN_SLUG`, pushes, and opens the draft PR exactly as today; it submits `status: completed`. HEAD is `impl/$PLAN_SLUG`, so the recorded settled branch is `impl/$PLAN_SLUG` — the same string the hardcode produced.
- Both `spawn_and_await` ticks read that sentinel and inject `impl/$PLAN_SLUG`; and the `|| echo "impl/$PLAN_SLUG"` fallback guarantees the identical value even if the sentinel is absent (crash/re-run). The `jq` filter, the task array, and the child contract are unchanged.
- No new flag is added (option (b) rejected precisely to avoid touching the default invocation surface), so a fresh `/execute docs/plans/PLAN-<topic>.md` parses identically. The override branch is reached ONLY when the auto-detect predicate (non-main branch + open PR) is already true — the exact condition that is false on a fresh run.

## Open Risks

- **Sentinel placement vs the closed write-target set.** `wip/execute_<topic>_*` is already inside `/execute`'s permitted write set (Security Considerations surface 2, SKILL.md line 453), so a `wip/execute_${PLAN_SLUG}_branch` sentinel is in-bounds. If reviewers prefer not to add a new wip file, the settled branch can instead be carried via a koto context key set in `orchestrator_setup` and read in `spawn_and_await` — same effect, no extra file; pick one to keep it minimal.
- **Settled-branch is an input surface.** A branch recovered from the environment/`gh` is untrusted (consistent with the slug re-validation rule, surface 1). The injected branch name should match the same `^[a-z0-9/_.-]+$`-class ref constraint before it reaches the `jq --arg`/emitted shell; `git rev-parse --abbrev-ref HEAD` output is low-risk but should still be guarded rather than trusted blindly.
- **Adoption vs draft state.** A `/scope` `docs/<topic>` PR may be non-draft while `/execute`'s DRAFT-before-READY discipline (#117, `plan_completion`) assumes it readies a draft. Adopting a PR that is already ready means `gh pr ready` is a no-op — benign, but the finalization cascade ordering (cascade BEFORE ready) should be confirmed to still fire its strict-mode CI re-run when the PR was already ready on adoption.
