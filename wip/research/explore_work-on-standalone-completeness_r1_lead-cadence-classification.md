# Lead: For each thing `/execute` does that `/work-on` does not, is it per-change finishing logic, per-plan orchestration, or shared machinery -- and what is the cadence consequence of moving it?

## Findings

### Setup: what `/work-on` actually does today (baseline for comparison)

`/work-on`'s own single-issue template (`skills/work-on/koto-templates/work-on.md`) creates its
own branch, verifies the work (`finalization` gate requires `summary_exists` and only reaches
`pr_precheck` via `verification_outcome: passed`, work-on.md:630-661), then opens a
**non-draft** PR in one shot: `pr_creation` (work-on.md:752-775) has no `--draft` anywhere, and
`phase-6-pr.md` never mentions "draft" or "ready" (confirmed by grep: zero hits). Title/body
conformance is authored inline at creation time (`phase-6-pr.md:25-35`), including
`Fixes #<N>` in Part 2 unconditionally. `ci_monitor` in work-on.md (777-819) has exactly one
gate, `ci_passing` -- no DIRTY/merge-state check. There is no cascade call anywhere in
work-on.md or `skills/work-on/SKILL.md` (grepped for `run-cascade`, `finalize-chain`,
`lifecycle-chain`: zero hits in either file).

When `/work-on` runs as an `/execute` child (`SHARED_BRANCH` set), it explicitly opts OUT of
PR creation: "If `SHARED_BRANCH` is set, this child is running on the orchestrator's shared
branch and the orchestrator owns the PR. Submit `pr_status: shared` -- no PR creation step is
needed here." (work-on.md, `## pr_creation` prose block). `work-on/SKILL.md:183` states this
plainly as a historical fact: "The plan-level orchestrator -- shared branch and draft PR,
child spawning, cross-issue context assembly, escalation, PR finalization, and the completion
cascade -- now lives in `/execute` ... `/work-on` keeps only Plan-Backed Child Mode."

### Classification table

| Capability | file:line | Classification | What happens if it runs per-issue instead of per-plan | Evidence |
|---|---|---|---|---|
| `orchestrator_setup` -- create ONE shared branch (`impl/<slug>`) + ONE `--draft` PR for the whole plan | `execute.md:494-513` | per-plan orchestration | Re-running the creation script per issue is harmless by design (idempotent: `gh pr list ... \| grep -q . \|\| gh pr create ...`, execute.md:505-506) -- it would just find the existing branch/PR and no-op. But the *reason* one shared draft PR exists at all is to host N children's commits under one review surface; running "create a branch+PR" once per issue is exactly what standalone `/work-on` already does (its own feature branch, its own ready PR), so this state has no meaning at per-issue cadence -- it collapses into `/work-on`'s own branch/PR creation, which already exists. | execute.md:500-511, 513 ("The script is idempotent") |
| `settled_branch_record` / `record-settled-branch.sh` | `execute.md:71-169`, `record-settled-branch.sh:1-105` | per-plan orchestration | Exists solely so *every child* commits to the *same* branch (comment: "The settled branch this state records is the ONLY thing that knows which branch children commit to on the adopt path", execute.md:72-77). A single `/work-on` run never needs this -- it reads its own branch directly in `pr_precheck` via `git rev-parse --abbrev-ref HEAD` (work-on.md:706-712) with no shared-branch bookkeeping. Per-issue cadence makes this a no-op / dead concept: there is nothing to "settle" across children if there is only one child. | execute.md:72-77, 105-127; record-settled-branch.sh:2-8 |
| `worktree_sync` -- `git fetch && git rebase origin/main`, gated on ancestor + no in-progress rebase | `execute.md:170-231` | shared machinery (mechanized once per plan; work-on has an unmechanized per-issue equivalent) | `/work-on` does the same underlying thing per issue, just as agent prose rather than a gated state: "Rebase on latest main if behind. Resolve conflicts and re-run tests." (`skills/work-on/references/phases/phase-6-pr.md:7`). Idempotent either way ("On an already-rebased branch the rebase is a no-op", execute.md:191-193). Running it once per issue (i.e. leaving it where `/work-on` already has it) is NOT wrong -- it is in fact fresher (each issue rebases against whatever `main` looks like at that moment) -- it is just less efficient across N issues (N rebases instead of 1) and, unlike execute's version, not backed by a dedicated idempotent gate (`rebased_on_main`, checking `git merge-base --is-ancestor` AND absence of `rebase-merge`/`rebase-apply`, execute.md:204-217) or an explicit conflict-vs-mid-rebase distinction. | execute.md:183-194, 204-217; phase-6-pr.md:5-9 |
| `worktree_discipline_check` / `escalate_upstream_drift` -- classify upstream drift as none / informational / intent-changing against the PLAN's intent | `execute.md:233-289` | per-plan orchestration (but historically per-child -- see note) | The state's own heading says "**Per-child** worktree-discipline check (#162)" (execute.md:561) even though it is wired to run exactly ONCE, before `spawn_and_await`, covering the whole batch of children about to be spawned -- not once per child today. The naming is a holdover: this judgment used to run inside `/work-on`'s own (now-removed) plan orchestrator, once per child, before the orchestrator moved into `/execute`. Running it once per issue (reverting to the old shape) is not incorrect the way the cascade would be -- it is a legitimate trade-off (fresher drift detection per issue vs. one classification for the whole batch) that the codebase has already made and moved away from once. | execute.md:233-251, 561-563 |
| `spawn_and_await` -- materialize one `/work-on` child per PLAN issue, gate on `children-complete`, aggregate `batch_outcome` | `execute.md:290-316, 577-636` | per-plan orchestration | This IS the multi-issue cadence itself; it has no single-issue analog. Its `batch_done` gate (`type: children-complete`, execute.md:291-293) is the ONLY mechanism in the whole template that knows "have all N issues finished" -- see the cross-cutting point below. | execute.md:290-293 |
| `pr_finalization` -- author conventional title + two-part body via `gh pr edit`, from aggregated `batch_final_view` across children | `execute.md:317-368, 638-682` | per-change requirement (conformant title/body is owed by every PR), but the *mechanism* (a separate later edit) is per-plan orchestration | Title/body conformance itself is shared: the same rule file (`references/pr-body-conformance.md`) governs both `/execute`'s `pr_finalization` (execute.md:642) and `/work-on`'s inline authoring at `pr_creation` (phase-6-pr.md:27-31). But `/work-on` authors it in ONE step at PR-open time because a single issue's outcome is already fully known then. `/execute` needs a SEPARATE later state because at `orchestrator_setup` time (when the draft PR opens) none of the children have run yet -- the body can only be assembled after `spawn_and_await`'s batch gate passes. Run per-issue, this state has nothing to aggregate (`batch_final_view` is a batch concept) and collapses into what `/work-on`'s `pr_creation` already does. | execute.md:640, 650-654; phase-6-pr.md:27-35 |
| Closing keywords (`Fixes #<N>`) | `execute.md:654`; `phase-6-pr.md:35` | per-change semantics, but batched at plan cadence by construction | `/work-on` includes `Fixes #<N>` unconditionally per PR (phase-6-pr.md:35) because each PR closes exactly one issue. `/execute` appends N `Fixes #<N>` lines into ONE shared PR body (execute.md:654) because there is only one PR for N issues. This is structurally impossible to do "per issue" under the current shared-branch model: when `SHARED_BRANCH` is set, `/work-on`'s own `pr_creation` explicitly skips the PR body entirely (`pr_status: shared`, work-on.md `## pr_creation` prose) -- closing-keyword insertion for execute children is deferred wholesale to the batched `pr_finalization`, not distributed per child. | execute.md:654; work-on.md `## pr_creation` prose ("If SHARED_BRANCH is set ... no PR creation step is needed here") |
| DRAFT-to-READY discipline: `--draft` set at PR creation, `gh pr ready` fires only in `plan_completion`, guarded by cascade-before-ready ordering (#117) and `PAUSE_BEFORE_FINALIZE` | `execute.md:502-513` (draft), `execute.md:429-437, 700-721` (ready), `execute.md:317-368` (pause guard) | per-plan orchestration | `/work-on` never opens a draft PR at all -- by the time it opens a PR, `verification` (a definition-of-done gate, work-on.md:592-629) has already passed, so there is no "incomplete work" to hide behind draft status. `/execute`'s draft exists for two per-plan reasons that don't exist per issue: (1) hiding a PR that represents fewer than N children having landed, and (2) hiding a PR whose upstream document chain (PLAN/DESIGN/PRD/BRIEF/ROADMAP) hasn't yet been cascaded to its terminal state. Explicit textual guard: "Do **not** mark the PR ready in this state -- the DRAFT-vs-READY discipline (#117) requires the chain to be at its strict-mode passing state BEFORE `gh pr ready` fires" (execute.md:640). Run per issue with nothing to gate on, this collapses to `/work-on`'s existing "just open it ready" behavior. | execute.md:502-513, 640, 700-704, 715-719 |
| `plan_completion` -- run `run-cascade.sh --push` (PLAN deletion, DESIGN->Current, PRD/BRIEF->Done, ROADMAP update/deletion) THEN `gh pr ready` | `execute.md:429-456, 700-729`; `run-cascade.sh` (whole file) | per-plan orchestration (document-chain completion cascade) | See detailed idempotency/partial-cascade analysis below. Running this per issue would be **actively wrong**, not merely wasteful: the first issue to finish would delete the PLAN doc and finalize DESIGN/PRD/BRIEF/ROADMAP before the remaining issues have even run. | run-cascade.sh:754-774, 804-822; execute.md:704-706 |
| `ci_monitor` DIRTY-merge-state detection (`merge_state_clean` gate, `escalate_dirty_merge_state`) | `execute.md:369-427, 683-698` | shared machinery, but currently execute-only | `/work-on`'s `ci_monitor` (work-on.md:777-819) has only the `ci_passing` gate; no `merge_state_clean` check, no DIRTY escalation path. DIRTY merge state is not an inherently plan-scale phenomenon -- any single PR can go DIRTY against a moved `main`. Execute added it (#162) because its shared-branch cascade push right before `gh pr ready` is a specific new trigger for GitHub suppressing check-runs, but the same class of problem (conflicts silently suppressing checks) can equally hit a lone `/work-on` PR. This reads as a capability `/work-on` is simply missing today rather than one that is per-plan by nature. | execute.md:369-388, 692-694; work-on.md:777-796 (no DIRTY handling) |
| `paused_for_review` / `PAUSE_BEFORE_FINALIZE` | `execute.md:37-46, 317-368, 468-480, 742-752` | per-plan orchestration | The pause sits between "PR body assembled" and "cascade + ready," i.e. between two per-plan states (`pr_finalization` and `plan_completion`). It is a single review checkpoint for the WHOLE batch's aggregate diff and document-chain transition. `/work-on` has no equivalent pause at all (its PR opens ready immediately once verified). Run per issue, this would turn into N separate pause points (one per issue) rather than one pause over the assembled multi-issue change -- a materially different (noisier) review cadence, not a like-for-like relocation. | execute.md:37-46, 468-480 |
| `orchestrator_setup`, `spawn_and_await` team-shape (`materialize_children`, koto session) | `execute.md:290-305`; SKILL.md:765-776 | per-plan orchestration | Structural: koto has no notion of "a batch of children" inside `/work-on`'s own single-issue template; this is the mechanism, not a relocatable "feature." | execute.md:302-305 |
| `assert-child-template.sh` | `skills/execute/scripts/assert-child-template.sh` (29 lines) | shared machinery (a preflight check `/execute` needs because it calls `/work-on`; meaningless for `/work-on` to run on itself) | Asserts the cross-skill path `../../work-on/koto-templates/work-on.md` resolves before any child spawns (assert-child-template.sh:1-14, 25-29). This is purely about the caller-callee coupling `/execute -> /work-on`; `/work-on` never needs to assert its own template exists. Not "per-issue vs per-plan" in the finishing-logic sense -- it is orchestration plumbing that only exists because `/execute` is a caller of `/work-on`. | assert-child-template.sh:1-14, 25-29 |

### `run-cascade.sh` idempotency and partial-cascade representability (close read)

**Idempotent on re-invocation, by construction of the pre-probe.** The script always begins
with a pre-cascade lifecycle probe seeded on the PLAN doc:

```
if ! lifecycle_probe "pre" "$PLAN_DOC"; then
    add_step "lifecycle_pre_probe" "$PLAN_DOC" "null" "skipped" \
        "chain at ready-posture passing state — cascade is a no-op..."
    emit_result "skipped"
    exit 0
fi
```
(`run-cascade.sh:768-774`)

`lifecycle_probe pre` treats a **clean pass** (exit 0 from `shirabe validate --lifecycle-chain
... --mode=ready`) as "cascade already ran, this is a no-op" and returns 1, which routes to the
early exit above (`run-cascade.sh:363-369`). So a second invocation after a completed cascade
short-circuits before touching git at all: `cascade_status: skipped`. The PLAN transition to
Done is separately documented as idempotent ("Idempotent: `shirabe transition <plan> Done` is
a no-op on a Done doc.", `run-cascade.sh:812`), and `handle_roadmap_deletion` is explicitly
idempotent at every negative branch ("Missing file returns 0 with no side effects (already
deleted).", `run-cascade.sh:572-586, 593-596`).

**A partial cascade (one issue of five done) is NOT representable inside `run-cascade.sh`
at all.** The script has no notion of "N of M issues done" -- its only input is a PLAN doc
path, and its only branching signal is the document chain's own lifecycle state (has this
chain reached ready-posture pass, yes/no). `cascade_status: partial` means a *node in the
document chain* failed to transition (a `finalize-chain` refusal, an `error` node, or a
failed `git rm`) -- it has nothing to do with how many of the PLAN's *issues* are implemented.
The invariant "don't cascade until every issue is done" is enforced entirely OUTSIDE this
script, at the orchestrator level: `spawn_and_await`'s `batch_done` gate
(`type: children-complete`, `execute.md:291-293`) is what makes `plan_completion` (and thus
`run-cascade.sh`) unreachable until every materialized child has reached a terminal state.
If `run-cascade.sh` (or an equivalent finalization call) were invoked directly from inside
`/work-on`'s own per-issue template, nothing internal to the script would stop it from firing
on issue 1 of 5 -- the safeguard is purely structural (a gate on a state machine that only
`/execute` runs), not a property of the cascade script itself. Moving the cascade into
`/work-on` without also rebuilding "is this the last issue in the PLAN" tracking inside
`/work-on` would let the first issue's PR delete the PLAN and finalize DESIGN/PRD/BRIEF/ROADMAP
while issues 2-5 are still unimplemented.

Concretely, what "one of five done" would actually do if the cascade ran anyway: `finalize-chain`
walks the PLAN's `upstream` chain unconditionally and transitions every reachable node
(`run-cascade.sh:782-791, 824-838`) -- DESIGN moves to `docs/designs/current/` with its
Implementation-Issues section stripped (comment at `run-cascade.sh:808-810` and the design
transition case at 864-869), PRD/BRIEF flip to Done (870-882), and if all ROADMAP features
already read `Done` textually, the ROADMAP feature is marked Done and the file is `git rm`'d
outright once every referenced issue is CLOSED (`handle_roadmap_deletion`,
`run-cascade.sh:589-654`). None of that is issue-count-aware; it is chain-lifecycle-aware only.
A stray early cascade would (a) delete the working PLAN doc that later issues' `/work-on`
children read via `plan_context_injection` (work-on.md:34-35, 956) to extract their own
outline, and (b) prematurely fold DESIGN/PRD/BRIEF to their terminal, committed state -- not a
"waste," an actual correctness break for the remaining 4 issues.

### Multi-pr mode: a real per-issue cadence already exists, and the cascade is NOT wired into it

`/work-on` already has a working per-issue cadence for `execution_mode: multi-pr` -- "run in
place, one issue at a time ... each landing its own PR. There is no shared branch and no
cross-issue carry-forward" (`skills/work-on/SKILL.md:137-140`). This is the closest thing in
the codebase today to "the finishing logic running once per issue." Grepping `work-on.md` and
`work-on/SKILL.md` for `run-cascade`, `finalize-chain`, and `lifecycle-chain` returns zero
hits in both files -- the cascade is simply not called anywhere in `/work-on`'s multi-pr path
today.

This directly contradicts a documentation claim elsewhere: `skills/plan/references/quality/plan-doc-structure.md:95`
states the PLAN's lifecycle trigger for Done as "multi-pr: all issues closed and the
work-completing PR runs the cascade; single-pr: /work-on cascade ran before the PR flipped to
ready" -- but `run-cascade.sh` now lives under `skills/execute/scripts/`, is invoked only from
`execute.md`'s `plan_completion` state, and `/work-on`'s own SKILL.md says plainly that the
cascade "now lives in `/execute`" (`work-on/SKILL.md:183`). `references/pipeline-model.md:222-230`
agrees with the current code, not with `plan-doc-structure.md`: "Plan-level execution (both
single-pr and coordinated modes) and the completion cascade are owned by `/execute`. `/work-on`
is the single-issue engine plus an execution_mode dispatcher: it runs multi-pr in place and
hands single-pr and coordinated plans to `/execute`." This means a `multi-pr` PLAN today has
**no wired path to ever finalize its document chain** -- a real gap, but a documentation/wiring
drift rather than an answer to this lead's question (flagged under Surprises).

## Implications

- The document-chain cascade (`plan_completion` / `run-cascade.sh`) is the cleanest example of
  a capability that is per-plan **by necessity**, not by historical accident: its correctness
  depends on an external "all children done" gate (`children-complete`) that only exists in
  `/execute`'s state machine. Moving it into `/work-on` verbatim, without rebuilding that
  completion-tracking machinery inside `/work-on`, would make a five-issue multi-pr-shaped run
  finalize the chain on the first issue.
- DRAFT-to-READY and the `paused_for_review` checkpoint are per-plan for a different reason:
  they exist to hide/checkpoint an *aggregate*, multi-issue diff and an *unfinalized document
  chain* -- neither condition exists for a single already-verified `/work-on` PR, which is why
  `/work-on` never opens a draft PR today.
- Title/body conformance and closing keywords are genuinely per-change obligations (every PR
  needs a conformant title/body and its own `Fixes #N`), but `/execute`'s specific
  implementation of them is shaped by the shared-PR/batch design, not by the requirement
  itself -- `/work-on` already discharges the identical requirement per issue, inline, with no
  separate finalization step.
- Two items look like they should be shared machinery but currently exist ONLY in `/execute`:
  DIRTY-merge-state detection (`merge_state_clean` / `escalate_dirty_merge_state`) and the
  mechanized rebase-with-conflict-detection gate (`worktree_sync`'s `rebased_on_main` gate vs.
  `/work-on`'s prose-only "rebase on latest main"). Neither is plan-scale by nature; `/work-on`
  simply doesn't have the hardened version yet.

## Surprises

- `worktree_discipline_check`'s own heading text calls itself a "**Per-child** worktree-discipline
  check (#162)" (execute.md:561) while it is wired to run exactly once per plan run, before any
  child spawns. This is a naming holdover from before the orchestrator moved out of `/work-on`;
  it is evidence the drift-classification judgment used to run once per child and was
  deliberately hoisted to run once per batch.
- `plan-doc-structure.md:95` documents a multi-pr cascade trigger ("the work-completing PR runs
  the cascade") that does not exist anywhere in the current `/work-on` implementation --
  `pipeline-model.md` and `work-on/SKILL.md:183` both describe the cascade as `/execute`-only.
  This means multi-pr PLANs currently have no wired mechanism to ever transition their PLAN to
  Done/deleted or cascade upstream docs -- a live gap independent of this lead's question.
- `/work-on` has no DRAFT PR concept at all today, in either standalone or multi-pr mode --
  every PR it opens is immediately ready. The DRAFT state is entirely an `/execute` invention
  tied to the multi-child batch, not a general PR-hygiene practice this codebase applies
  uniformly.

## Open Questions

- If finishing logic (title/body finalization, DRAFT/ready, cascade) migrates into `/work-on`,
  does `/work-on` need to grow its own "is this the last issue in the PLAN" completion check
  (e.g. querying the PLAN's Implementation Issues table / milestone) to safely gate the
  cascade -- effectively re-deriving `children-complete` outside koto? That machinery doesn't
  exist in `/work-on` today in any form.
- Is the multi-pr cascade gap (no wiring at all) something either candidate direction is
  expected to fix as a side effect, or does it stay explicitly out of scope for this
  exploration?
- Should DIRTY-merge-state detection and the mechanized `worktree_sync` gate be hardened into
  `/work-on` regardless of which direction is chosen, since neither is plan-scale by nature and
  `/work-on` currently lacks both?

## Summary

Of everything `/execute` does that `/work-on` doesn't, only the document-chain cascade
(`plan_completion`/`run-cascade.sh`) and the multi-child batch machinery around it
(`spawn_and_await`'s `children-complete` gate, `settled_branch_record`, DRAFT-to-READY,
`paused_for_review`) are per-plan by necessity, because their correctness depends on an
"all issues done" signal that exists only in `/execute`'s state machine and is not
representable inside `run-cascade.sh` itself. Title/body conformance and closing keywords are
per-change obligations that `/work-on` already discharges inline per issue -- `/execute`'s
separate `pr_finalization` step exists only because it must aggregate N children's outcomes
into one shared PR, not because the requirement itself is plan-scoped. The biggest open
question is whether relocating the cascade into `/work-on` requires rebuilding "is this the
last issue" completion-tracking inside `/work-on` from scratch, since nothing like it exists
there today, and a live discovery is that multi-pr PLANs currently have no cascade wiring at
all, contradicting one line of `plan-doc-structure.md`.
