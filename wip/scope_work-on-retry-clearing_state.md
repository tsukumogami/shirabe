---
topic: work-on-retry-clearing
chain_started: 2026-08-16T18:30:00Z
last_updated: 2026-08-16T18:30:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran: []
child_snapshots: {}
consolidation_judgments: []
visibility: Public
execution_mode: auto
max_rounds: 5
pre_invocation_sha: 4859557
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-16T18:30:00Z
    notes: branch hard-reset to origin/main at 4859557; nothing to rebase
---

# /scope state: work-on-retry-clearing (second run)

## Why this run replaces the first

The first chain scoped and shipped a fix built around an absence: koto had no
`context remove`, so the design settled on overwrite-to-clear plus a
`context-matches` content gate, and the PRD deliberately left the mechanism open
because one live option reached another repository.

That option was then taken. `koto context remove` is merged
(tsukumogami/koto#196) and released in **v0.11.5**, and shirabe's `.tsuku.toml`
pins `"tsukumogami/koto" = "latest"`, so CI installs a koto that has it. The
absence the first design worked around no longer exists, so its chosen mechanism
is no longer the best answer to its own problem.

The branch was hard-reset to `origin/main` (4859557) and the first chain's
PRD, DESIGN and PLAN are gone. This is a replacement, not an increment.

## What changed in the world since the first run

1. **`koto context remove` exists and is released.** Verified against the
   installed binary: `koto 0.11.5`, `remove` in `koto context --help`, and the
   exact command the issue said did not resolve now exits 0 and makes a
   `context-exists` gate report absent.
2. **The gates on `main` are already correct.** All twelve are
   `type: context-exists`. With removal available, a presence gate is exactly
   right for "this phase must produce a fresh artifact" -- remove the key and it
   fails. The first run converted three of them to `context-matches`; that
   conversion is now unnecessary and `work-on.md` needs **no gate change at
   all**.
3. **Removal is content-agnostic.** The first run's pattern keyed on
   `"passed": true`, which structurally cannot reach `plan.md` or `summary.md` --
   markdown written `--from-file`. Removal does not care what the value holds,
   so one mechanism now covers all six unsound gates instead of three.
4. **`docs/folds.md` is gone** (#318). A fold is now recorded by the survivor's
   `absorbed:` frontmatter alone.

## Phase 0 record

- Flags parsed and removed before the positional slug: `--auto`. No
  `--upstream`, no coordination flags.
- Residue `work-on-retry-clearing` validated AS PROVIDED against
  `^[a-z0-9-]+$`: match.
- Visibility from CLAUDE.md `## Repo Visibility: Public` -> Public.
- **Coordination intent: absent, and this time that is a finding rather than a
  default.** The first run reasoned that the coordinated path was available but
  expensive. It is now simply inapplicable: the cross-repo half is merged and
  released, so every remaining change lands in shirabe alone. The
  mode-scoped preflight for the coordinated surface is therefore not run.
- No stale `parent_orchestration:` block (fresh state file).

## Phase 1 record

Cold start after the reset -- no BRIEF, PRD, DESIGN or PLAN exists for this
topic, so no child is held back by re-entry protection.

R6 shape-predicate walk:

- **P1 does-not-fire.** The architectural question the first run faced -- which
  of three mechanisms forces a fresh verdict -- is settled by the world, not by
  this chain. `remove` is the direct answer and the alternatives it beat are
  gone or moot. No architectural alternative is left open for the DESIGN.
- **P2 does-not-fire.** No new binary, service, library or substrate. The verb
  the work depends on already ships.
- **P3 does-not-fire.** No `complexity: Complex` classification and no prose
  claim of architectural complexity. The change is a loop in three phase files
  plus a test.

All three negative, so `/design` runs with the **minimum roster**: it records
the one live option and why no alternative is live, which is a shorter document
than the first run's contested design and a better audit trail than silence.
Note this is a shape verdict, not a produce-or-skip gate -- `/design` still runs.

The pre-authoring upstream notice fired (both conditions: `/brief` is in
`planned_chain:`, and Phase 0 recorded no `consumed_upstream:`). `--auto`
auto-proceeded past Proceed / Adjust / Bail.
