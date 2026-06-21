# Lead: How should `/execute` support an "implement, pause for review before finalization/merge" mode? (F3)

## Findings

### 1. The terminal state runs `gh pr ready`, NOT `gh pr merge`. `/execute` never merges.

The template's final reachable non-terminal state is `plan_completion`, whose Step 2 is the only "flip" command in the whole template:

`skills/execute/koto-templates/execute.md:359-363`:
```bash
**Step 2: Mark the PR ready for review.**
gh pr ready $(gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number --jq '.[0].number')
```

There is no `gh pr merge` anywhere in `execute.md`, `run-cascade.sh`, or `SKILL.md`. The `done` terminal state (`execute.md:386-388`) describes completion as "the PR description has been updated, and CI is green" — it does not merge. So the koto orchestrator's actual terminal is **a DRAFT→READY PR with green CI, awaiting a human merge.**

### 2. State machine sequence (single-pr path)

`orchestrator_setup` → `worktree_discipline_check` → `spawn_and_await` (children) → `pr_finalization` (PR body only, explicitly NOT ready) → `plan_completion` (cascade + `gh pr ready`) → `ci_monitor` → `done`.

Note the ordering quirk: `pr_finalization` routes to `plan_completion` (`execute.md:122`), and `plan_completion` routes to `ci_monitor` (`execute.md:198-206`), which routes to `done`. So the cascade-then-ready happens BEFORE the final CI watch, not after.

`pr_finalization` is explicit that it does NOT ready the PR — `execute.md:312-314`:
> "Do **not** mark the PR ready in this state — the DRAFT-vs-READY discipline (#117) requires the chain to be at its strict-mode passing state BEFORE `gh pr ready` fires... This state confines itself to PR-description assembly."

### 3. The done-signal: SKILL says "merges," template stops at "ready." This is the crux of F3.

The SKILL repeatedly defines `full-run` as the PR **merging**:

- `SKILL.md:364-368` (`full-run` exit): "the plan is driven to its **merged-PR done-signal**. For single-pr the single PR merges (after the `plan_completion` finalization cascade runs DRAFT-before-READY and the PR flips ready)... There is no separate 'complete' marker — the merged home PR is it."
- `SKILL.md:14-16`: "drives the plan's issues to merged code."

But the koto template it lifts terminates at `gh pr ready` + green CI (finding 1). **The merge itself is not performed by any code in the template or scripts.** So the SKILL's "the single PR merges" describes the human-or-external act that happens AFTER koto's `done`; the automated run already stops at ready-for-review.

This means **F3 is partly a misunderstanding**: the automated workflow already implements "implement all issues, stop before merge, leave a reviewable PR." What it does NOT have is a mode that stops *before finalization* (cascade + ready), leaving the PR in DRAFT for review. The author's described want ("review gate AT THE PLAN... stop before merge, then finalize/merge") is two different gates:
- **Gate after ready (already exists):** PR is READY + green, human reviews and clicks merge. This is the default terminal today.
- **Gate before ready (does NOT exist):** PR stays DRAFT, cascade not yet run, human reviews, then a resume runs cascade + ready (+ eventual merge).

The author wanting to review *before* the finalization cascade commits the BRIEF/PRD/DESIGN/PLAN transitions is the genuinely-missing mode.

### 4. The DRAFT-before-READY discipline constrains where a pause can sit

`run-cascade.sh` enforces an atomic, ordered finalization:
- Pre-cascade probe (`run-cascade.sh:668`, `lifecycle_probe "pre"`) expects a strict-mode FAILURE naming the present PLAN (chain at single-pr-Active mid-PR). A clean pass here means already-terminal → `cascade_status: skipped`, exit 0 (`run-cascade.sh:668-673`).
- Atomic finalization commit: `finalize-chain` transitions DESIGN→Current, PRD→Done, BRIEF→Done (`run-cascade.sh:682-825`), then `git rm` the PLAN (`run-cascade.sh:841`), all in ONE commit (`run-cascade.sh:851-854`, `git commit ... && git push`).
- Post-cascade verify (`run-cascade.sh:874-882`) expects a clean strict-mode pass.

Then `plan_completion` Step 2 runs `gh pr ready` (`execute.md:359-363`). The reason this ordering is load-bearing is in `execute.md:344-348` and `:116-121`: GitHub re-runs CI on the `ready_for_review` event with strict mode set; if `gh pr ready` fired BEFORE the cascade, the strict-mode CI re-run would see a non-terminal chain (PLAN still present, BRIEF/PRD not Done) and FAIL. So the cascade must precede ready.

**Consequence for a review gate:** the natural human-review pause point is BEFORE the cascade runs — i.e. between `pr_finalization` (PR body assembled, still DRAFT) and `plan_completion` (cascade + ready). At that point the PR is a complete, DRAFT, reviewable surface whose chain is NOT yet mutated. Pausing here means the reviewer sees the actual implementation diff without the lifecycle-transition commit muddying it, and nothing irreversible (PLAN deletion, doc transitions) has happened yet. This is the cleanest seam.

### 5. Interaction with `--auto`

Autonomy is defined to drive "to the done-signal or a genuine blocker" (`SKILL.md:397-404`, `execute.md:267-278`). A review gate is, by definition, an advisory checkpoint stop — exactly the kind of stop `--auto` forbids: "does not pause for checkpoints, confirmation, reassurance, or unsolicited advisory stops" (`SKILL.md:399-401`). And explicitly "A decision with a reasonable default is NOT a blocker" (`execute.md:276`).

So a review gate must be an **explicit opt-in** orthogonal to autonomy, not a default. The clean model: `--pause-for-review` (or `--no-finalize`) is its own flag. In `--auto` WITHOUT the review flag: drive straight through to ready (today's behavior). In `--auto` WITH `--pause-for-review`: the review gate is a *deliberate, author-requested* stop, so it is NOT an "advisory" stop — it's the configured done-signal for that run, and the run should pause there and emit an operator summary. The two flags compose: `--auto` governs *unsolicited* stops; `--pause-for-review` *adds a solicited one*. This needs to be stated explicitly because the current Autonomy text would otherwise read as forbidding it.

## Implications

**Needs-design (small).** This is not a one-line fix, because it changes the state machine's terminal contract and the SKILL's exit-path semantics, and it interacts with the #117 DRAFT-before-READY invariant. But it is a contained design, not a large one.

Design options evaluated:

- **(a) `--no-finalize` / `--pause-for-review` flag that stops after `pr_finalization`, before `plan_completion`.** Best fit. The seam is already a clean state boundary (finding 4). The PR is left DRAFT with an assembled body; the cascade and `gh pr ready` have NOT run, so no doc transitions, no PLAN deletion — fully reversible, ideal for review. A resume (`/execute` re-entry, or an explicit `/execute --finalize`) runs `plan_completion` (cascade + ready) and `ci_monitor`. The resume ladder already supports home-PR-keyed re-entry at a recorded `phase_pointer` (`SKILL.md:314-355`), so "resume at `plan_completion`" is mechanically supported — `phase_pointer` is already an enum that includes `plan_completion` (`SKILL.md:287-289`). Files: add a transition out of `pr_finalization` to a new `paused_for_review` terminal (or a non-failure pause terminal) in `execute.md`; teach `plan_completion` it can be entered on resume; add the flag + autonomy-composition wording in `SKILL.md` (**Autonomy**, **Execution-Mode Flags**, **Exit Paths**). Likely a new `exit:` value or reuse of `re-evaluation` is the open question (see below).

- **(b) New pause/exit state.** This is really the implementation vehicle for (a) — a `paused_for_review` koto state between `pr_finalization` and `plan_completion`, terminal-until-resumed. Same change set as (a); the difference is whether the pause is modeled as a koto terminal that a fresh `/execute` re-enters, or as a mid-loop wait. Given koto sessions don't block-and-wait across human time, a terminal-then-resume shape is the realistic one.

- **(c) Decouple "ready for review" from "merge" — claim the existing flow already satisfies F3.** Partly true (finding 3): the existing terminal already is "READY + green, human merges." If the author's only want was "don't auto-merge," **no change is needed** — `/execute` never merges. But if the author wants to review BEFORE the lifecycle cascade mutates the chain (the more likely reading of "review gate AT THE PLAN"), (c) does not satisfy it, because by the time the PR is READY the cascade has already deleted the PLAN and transitioned BRIEF/PRD/DESIGN.

**Recommendation:** ship (a)/(b) as the same change, AND document (c) — i.e. clarify in the SKILL that the default terminal is already ready-for-review-not-merge, and add `--pause-for-review` for the stop-before-finalization case. The cascade's atomicity is preserved in both: pausing happens entirely before the cascade, so the cascade still runs as one atomic commit when finalization resumes.

Files that change:
- `skills/execute/koto-templates/execute.md` — new pause state/transition out of `pr_finalization`; resume entry into `plan_completion`.
- `skills/execute/SKILL.md` — **Execution-Mode Flags** (add `--pause-for-review`/`--no-finalize`), **Autonomy** (flag composes with `--auto`), **Exit Paths** (new or reused exit value), **Phase Execution**/**Workflow Phases** (Phase 2 FINALIZE becomes resumable/gated).
- `run-cascade.sh` — likely NO change; it already exits cleanly and is idempotent, so a deferred resume just calls it later.

## Surprises

- The SKILL's prose ("the single PR merges") overstates what the automation does: the koto template terminates at `gh pr ready`, and nothing in the template/scripts ever runs `gh pr merge`. The "merge" is an out-of-band human/external act. So `/execute` is *already* an "implement and stop before merge" tool — F3's premise is half-satisfied today.
- The riskier, irreversible step (cascade: PLAN deletion + doc transitions) happens AFTER the PR is finalized but is sequenced BEFORE `gh pr ready` for CI reasons (#117). This means there is no point in the current flow where a reviewer sees a DRAFT PR that has NOT yet had its chain mutated — the cascade and ready are welded together in `plan_completion`. That welding is exactly what a `--pause-for-review` gate would split.

## Open Questions

- Which `exit:` value does a review-pause map to? It is neither `full-run` (not driven to done-signal), nor `abandonment-forced` (not a blocker/abandon), nor cleanly `re-evaluation` (no upstream-must-change). A fourth "paused/suspended" exit may be needed, OR the run simply records `exit: UNSET` (in-flight) and relies on resume — but the R9 hard-finalization check (`SKILL.md:290-293`) fires when `exit` is unset at termination, so a pause-terminal needs its own non-failure exit value or an explicit R9 carve-out.
- Does "resume to finalize" re-run children's CI or only the cascade? Since the cascade pushes a new commit, CI re-runs anyway — the `ci_monitor` state after `plan_completion` already handles this.
- Should the pause leave a PR label/marker (e.g. a "review-gate" label) so a human knows it's intentionally paused vs. abandoned? The `abandonment-forced` path leaves an "abandonment-marked PR" (`SKILL.md:374-378`); a review pause likely wants an analogous but distinct marker.

## Summary

`/execute`'s koto template already terminates at `gh pr ready` + green CI and never runs `gh pr merge`, so "implement all issues, stop before merge" is largely the existing behavior — F3 is partly a misunderstanding of the done-signal (the SKILL's "the PR merges" describes an out-of-band human act, not automation). The genuinely-missing mode is a pause BEFORE the `plan_completion` finalization cascade (which atomically deletes the PLAN and transitions BRIEF/PRD/DESIGN, welded to `gh pr ready` by the #117 DRAFT-before-READY rule), so a reviewer can see a DRAFT PR whose chain is not yet mutated; the clean seam is a new pause terminal out of `pr_finalization`, resumable into `plan_completion`. This is a contained needs-design change touching `execute.md` (new pause state) and `SKILL.md` (a `--pause-for-review`/`--no-finalize` flag that composes with `--auto` as a solicited stop, plus a pause exit value to satisfy the R9 hard-finalization check).
