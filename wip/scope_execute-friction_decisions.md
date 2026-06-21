# /scope execute-friction — Decision Log (--auto from PRD acceptance)

The author approved the PRD and authorized `--auto` from that point onward. The
remaining chain (`/design`, `/plan`, finalize) runs non-interactively, settling
deferred decisions on the exploration's recommended defaults and recording each
here, stopping only on a genuine blocker.

## Round 1

- **Switch to --auto at PRD acceptance**: author instruction "approve, and run in
  --auto from here onward." Rationale: framing (BRIEF) and requirements (PRD) are
  settled and reviewed; the remaining mechanism decisions have clear
  exploration-backed defaults, so autonomous settlement is appropriate.

## Design decision defaults to apply (D1–D5 from the PRD)

These are the recommended defaults `/design` will settle in --auto, each grounded
in the committed exploration; `/design`'s own decision/security/jury agents may
refine them:

- **D1 (existing-PR surface)**: default to the lowest-ceremony surface — generalize
  the existing `status: override` reuse beyond `impl/<slug>` and capture the settled
  branch into `SHARED_BRANCH` (the one hardcoded line), plus a `/scope → /execute`
  handoff so a `docs/<topic>` PR is ADOPTED as the home PR. Preserve R7 default.
- **D2 (pause shape)**: default to a `--pause-for-review`/`--no-finalize` flag that
  stops after `pr_finalization` but before `plan_completion`, resumable into the
  cascade. New pause terminal/exit value to satisfy R9 hard-finalization; composes
  with --auto as a solicited stop (R8).
- **D3 (docs-coverage owner/signal)**: default owner `/plan` (it reads the DESIGN
  body); signal = a structured `user_visible_surface` flag on DESIGN/PRD with a
  prose `docs/guides/*`-reference fallback; `/plan` emits a docs work item, `/execute`
  keeps a metadata-only completeness gate (does not read child bodies).
- **D4 (finalization guard home)**: default to a new `shirabe validate` mode
  (e.g. `--finalization-complete`) invokable from CLI and CI.
- **D5 (durable friction home)**: default to a convention carve-out (report-upstream
  artifacts → a GitHub issue on the skill repo, never `wip/`) + a pointer in the
  `/execute` SKILL; automated run-report emit deferred as a design-gated follow-on.
