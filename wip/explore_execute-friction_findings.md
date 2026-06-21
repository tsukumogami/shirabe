# Exploration Findings: execute-friction

## Core Question

What is the complete set of work needed to close the seven friction points
(F1–F7) reported against the new `/execute` skill, and for each: is it a direct
fix, or does it carry design decisions that need settling first?

## Round 1

### Key Insights

- **F1 (branch/PR targeting) — the override substrate already exists, but it's
  half-wired.** `orchestrator_setup` accepts `status: override` for ANY non-main
  branch carrying an open PR, and finalization (`ci_monitor`/`plan_completion`)
  already targets `HEAD`. But `spawn_and_await` hardcodes
  `SHARED_BRANCH="impl/$PLAN_SLUG"` (execute.md:286/300), so even a successful
  override routes per-issue children to a divergent `impl/<slug>` branch. The
  mechanical core fix is small and shirabe-only: capture the settled branch in
  `orchestrator_setup` and inject THAT into `SHARED_BRANCH` (no change to
  `plan-to-tasks.sh` or `/work-on`). (lead-branch-pr-targeting)

- **F3 (review-gate mode) — partly a misread; the real gap is contained.**
  `/execute`'s template already terminates at `gh pr ready` + green CI and
  NEVER runs `gh pr merge` — so "implement, stop before merge" is largely the
  existing behavior. The SKILL's "the PR merges" describes an out-of-band human
  act, not automation. The genuinely-missing mode is a pause BEFORE the
  `plan_completion` finalization cascade (which atomically deletes the PLAN and
  transitions BRIEF/PRD/DESIGN, welded to `gh pr ready` by the DRAFT-before-READY
  rule), so a reviewer can see a DRAFT PR whose chain is not yet mutated. Clean
  seam: a new pause terminal out of `pr_finalization`, resumable into
  `plan_completion`. (lead-review-gate-mode)

- **F4 (doc-completeness) — ownership is `/plan`, not `/execute`.** `/plan` is
  the only layer that reads the DESIGN body (Phase 4), where the user-visible-
  surface signal lives (e.g. a `docs/guides/*` reference). It already produces
  and routes `Type: docs` issues end-to-end — it just never EMITS a docs outline
  for user-facing surface during Phase 3 decomposition. `/execute`'s metadata-
  only R14/R15 contract makes a content-completeness check there architecturally
  wrong. Fix: a Phase 3 emission step + a Phase 6 backstop in `skills/plan/`.
  (lead-doc-completeness)

- **F6 (PR-template) — a real structural gap, present even on a clean run.**
  `pr_finalization` edits only the body (`gh pr edit --body`, execute.md:323)
  with a child-outcome table — never the two-part Part 1/`---`/Part 2 structure —
  and the title stays the non-conventional `impl: <slug>` set at PR creation
  (execute.md:242). So F6 is NOT merely a side effect of the F1 manual fallback;
  a clean automated run also produces a non-template-conformant PR. Fix: fold
  `/fix-pr`'s template logic (conventional title + two-part body; the child table
  becomes Part 2) into `pr_finalization`. (lead-pr-template-finalization)

- **F7 (friction-log durability) — a convention gap, not an `/execute` bug.**
  The cascade (`run-cascade.sh`) only `git rm`s the PLAN and ROADMAP docs — there
  is NO `wip/` scrub. It's the squash-merge (working exactly as the workspace
  wip-hygiene rule intends) that carries any `wip/friction_*.md` off `main`. The
  log was simply placed in a location designed to be disposable. Lowest-ceremony
  durable home: a GitHub issue on the shirabe repo (`gh issue create`, a pattern
  shirabe already owns in `/plan`/`/roadmap`), with a `docs/` note as fallback.
  (lead-friction-durability)

- **F2 (version skew) — out of shirabe scope, benign.** The active install is
  entirely `0.12.1-dev` (marketplace tracks the repo default branch unpinned;
  main carries the post-release `-dev` string, but shirabe never tags/publishes a
  `-dev` release). The within-chain skew is a Claude-Code plugin-cache resolution
  artifact: `/execute` exists only in 0.12.0+, so an older 0.11.0-cached session
  fell forward to the dev cache dir that contains it. 0.12.1-dev is a forward-
  compatible superset of 0.11.0. Route to install/marketplace (niwa / Claude
  Code); at most, shirabe advises pinning installs to release tags.
  (lead-version-skew)

### Tensions

- **F5 has two halves that pull apart.** Half (a) — "cascade not auto-invoked" —
  is purely a consequence of F1: fix the branch/PR targeting so the koto path
  runs, and `plan_completion` cascades automatically. Half (b) — "a manual/
  fallback path should still surface 'finalization not done'" — cannot live in
  koto (koto was bypassed), and the only existing guard (R9 hard-finalization)
  rides the `/execute` exit, so it can't fire when koto is bypassed. The
  strongest home for (b) is a NEW `shirabe validate` mode invokable from a manual
  path AND CI — consistent with the "check with `validate`" half of the CLI
  split. This is the one place where "just fix F1" doesn't fully cover the report.

- **`/execute` security envelope vs. richer finalization.** F6's fold-in and any
  F7 automated run-report emit both push on `/execute`'s deliberately closed
  write-target set and metadata-only inspection contract. F6 fits (writing the
  home PR body/title is already in-set). An automated F7 emit would WIDEN the set
  and is therefore design-gated, not a direct fix.

### Gaps

- No gaps in coverage — all six leads returned grounded findings with explicit
  direct-fix-vs-needs-design verdicts and file/line pointers. The remaining
  unknowns are DECISIONS to make in the next artifact, not missing research.

### Decisions

- Scope = clusters A+B+C+D; F2 routed out (install/cache, not shirabe code).
- Ready to crystallize after one round; remaining unknowns are design decisions.
- F5 splits: F5a→F1, F5b→new `shirabe validate` mode.
- F4 owned by `/plan`; F3 reframed (pause before cascade); F7 reframed as convention.
- See `wip/explore_execute-friction_decisions.md`.

### Direct-fix vs. needs-design ledger

| F# | Theme | Verdict | Owner | Files |
|----|-------|---------|-------|-------|
| F1 | Land into existing branch/PR | Mechanical core is a direct fix; user-surface + home-PR-adoption is small-design | `/execute` | `execute.md` (SHARED_BRANCH capture/inject), `SKILL.md` |
| F3 | Pause-before-finalize mode | Needs-design (contained) | `/execute` | `execute.md` (new pause state), `SKILL.md` (flag + pause exit) |
| F4 | Docs-coverage guarantee | Direct fix + small detection-contract design | `/plan` | `skills/plan/` (Phase 3 emit + Phase 6 backstop); maybe DESIGN/PRD `user_visible_surface` field |
| F5a | Cascade auto-runs | Collapses into F1 | `/execute` | (covered by F1) |
| F5b | "Finalization not done" guard | Needs-design | `shirabe validate` | new validate mode (manual + CI) |
| F6 | Template-conformant PR | Direct fix | `/execute` | `execute.md` (`pr_finalization`), `SKILL.md` |
| F7 | Friction-log durability | Convention/doc change; automated emit is design-gated | workspace + `/execute` | workspace `CLAUDE.md`, `skills/execute/SKILL.md` |
| F2 | Version skew | Out of shirabe scope (benign) | niwa / Claude Code | none (at most: advise pinning) |

### User Focus

User confirmed the full shirabe scope (A+B+C+D) and agreed F2 is out (install/
cache, not shirabe code). Chose to crystallize now rather than run another
discovery round.

## Decision: Crystallize

## Accumulated Understanding

The friction is real and almost entirely in `/execute`'s entry + finalization
seam, plus one `/plan` gap and one convention gap. The encouraging headline:
**most of the load-bearing machinery already exists** — the override substrate
(F1), the stop-at-ready behavior (F3), the docs-issue routing (F4) — so several
"missing features" are really half-wired or mis-framed, which shrinks the work.

The work clusters into four buckets plus one out-of-scope item:

- **Cluster A — `/execute` finalize-correctly seam (F1, F5, F6):** the integration
  spine. F1's `SHARED_BRANCH` fix unblocks the koto path (auto-cascading F5a);
  F6 makes the assembled PR template-conformant; F5b adds a manual-path guard.
  Tightly coupled — all about "land into the right PR and finalize it properly."
- **Cluster B — review-gate pause (F3):** a contained new pause state/flag in
  `/execute`, resumable into the cascade. Somewhat independent of Cluster A.
- **Cluster C — docs-coverage in `/plan` (F4):** a different skill, a different
  concern (decomposition completeness). Independent of `/execute` changes.
- **Cluster D — friction-log convention (F7):** a doc/convention carve-out;
  near-trivial, with an optional design-gated automated-emit follow-on.
- **Out of scope — F2:** install/marketplace + plugin-cache; route to niwa /
  Claude Code.

Design-bearing decisions to settle: F1's user surface + whether a `/scope`
`docs/<topic>` PR is ADOPTED as `/execute`'s home PR (and flipped ready by the
cascade) or kept distinct and linked; F3's pause-state shape and `--auto`
interaction; F4's detection contract (prose-grep vs. a structured
`user_visible_surface` flag); F5b's guard home in `shirabe validate`. These are
contained enough to settle inside one design pass rather than another explore
round.
