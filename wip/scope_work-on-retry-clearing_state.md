---
topic: work-on-retry-clearing
chain_started: 2026-08-15T00:00:00Z
last_updated: 2026-08-15T00:00:00Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
chain_ran:
  - name: brief
    started_at: 2026-08-15T00:05:00Z
child_snapshots:
  brief:
    status: Accepted
    content_hash: 14b9f0d0f374b31744fe8f0ceba64a78fba4b4b2
    captured_at: 2026-08-15T00:10:00Z
consolidation_judgments: []
pre_invocation_sha: 8872b36
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-15T00:00:00Z
    notes: fresh worktree; HEAD already equals origin/main
  - phase: prd
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-15T00:12:00Z
    notes: no upstream movement since the brief hop
parent_orchestration:
  invoking_child: prd
  suppress_status_aware_prompt: true
  rationale: fresh-chain
visibility: Public
execution_mode: auto
max_rounds: 5
---

# /scope state: work-on-retry-clearing

Parent-skill state for the tactical chain run against shirabe issue #304 --
`/work-on`'s retry loop clears a stale artifact with `koto context remove`,
a subcommand koto does not have.

## Phase 0 record

- Flags parsed and removed before the positional slug was read: `--auto`.
  No `--upstream`, no coordination flags.
- Residue `work-on-retry-clearing` validated AS PROVIDED against
  `^[a-z0-9-]+$`: match.
- `shirabe slug-prefix-detect work-on-retry-clearing --docs-root docs` returned
  `no-prevailing-prefix`, so no prefix recommendation was surfaced.
- Visibility read from CLAUDE.md `## Repo Visibility: Public` -> Public.
- Coordination intent: absent. The two CLAUDE.md headers
  (`## PR Grouping Policy: coarsest-legal`, `## Reviewability Ceiling: default`)
  configure how a coordinated effort groups its PRs; they do not by themselves
  make this effort span repositories. Whether it does is one of the questions
  this chain's DESIGN has to settle, so the run starts on the single-repo path
  and revisits coordination only if the design's chosen mechanism reaches
  another repository.
- No stale `parent_orchestration:` block found (fresh state file).

## Phase 1 record

Cold start. Globs against `docs/briefs/BRIEF-work-on-retry-clearing.md`,
`docs/prds/PRD-work-on-retry-clearing.md`,
`docs/designs/DESIGN-work-on-retry-clearing.md`,
`docs/designs/current/DESIGN-work-on-retry-clearing.md`, and
`docs/plans/PLAN-work-on-retry-clearing.md` all missed, so no child is held
back by re-entry protection and `child_snapshots:` is empty.

R6 shape-predicate walk, evaluated against the projected PRD:

- **P1 fires** -- at least three architectural alternatives are left open for
  the DESIGN to settle: wire a `remove` subcommand into koto's CLI, change the
  gate type so an overwrite genuinely clears, or restructure the retry contract
  so nothing needs clearing.
- **P2 does-not-fire** -- no new binary, service, library, or runtime
  substrate. Every candidate composes koto's existing context store and gate
  types plus shirabe's existing `scripts/` test surface.
- **P3 fires** -- one live alternative reaches a second repository, and the
  `context-exists` gate couples the command choice to the state-machine shape,
  so the choice is architectural rather than mechanical.

Two of three predicates fire, so `/design` runs with a full decision roster
rather than the minimum.

The pre-authoring upstream notice fired (both conditions held: `/brief` is in
`planned_chain:` and Phase 0 recorded no `consumed_upstream:`). `--auto`
auto-proceeded past the Proceed / Adjust / Bail prompt.
