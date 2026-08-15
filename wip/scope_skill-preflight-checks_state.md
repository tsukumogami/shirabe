```yaml
topic: skill-preflight-checks
chain_started: 2026-08-15T01:53:49Z
last_updated: 2026-08-15T01:53:49Z
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
visibility: Public
execution_mode: auto
max_rounds: 5
coordinated: false
```

## Phase 0 Notes

- Topic slug `skill-preflight-checks` validated as provided against
  `^[a-z0-9-]+$`. No normalization applied.
- `shirabe slug-prefix-detect skill-preflight-checks --docs-root docs` returned
  `no-prevailing-prefix`; Phase 0 proceeds without a prefix recommendation.
- Visibility read from `CLAUDE.md` `## Repo Visibility: Public`.
- No `--upstream` supplied. `consumed_upstream:` absent per invariant I-5.
- No prior state file; no stale `parent_orchestration:` block to self-heal.
- Coordination intent resolved to **absent**. `CLAUDE.md` carries
  `## PR Grouping Policy: coarsest-legal` and `## Reviewability Ceiling:
  default`, but this effort is confined to the `shirabe` repository alone.
  Under coarsest-legal, one repository is one PR, so there is no cross-repo
  merge order to coordinate and no coordination PR is created. The single-repo
  path applies.
- Execution mode `--auto` per author instruction: the run does not block on
  author input, and contested decisions route through the `/decision` framework
  rather than surfacing a prompt.

## Phase 1 Notes

Cold start: no artifact exists at any canonical path for this topic
(`docs/briefs/`, `docs/prds/`, `docs/designs/`, `docs/designs/current/`,
`docs/plans/`). No re-entry protection fires; `chain_skipped:` is empty and
`child_snapshots:` starts empty.

Framing-shift question (R4): no prior BRIEF, PRD, or DESIGN exists for this
topic, so there is no accepted framing to invalidate. The upstream `/explore`
run did shift the framing of the *problem* -- from "prerequisite prose is a
context tax" to "host dependencies are invoked unguarded and fail silently" --
and that shift is carried into the BRIEF as an input rather than as an override
of an on-disk artifact.

Cold-start projection: the slug carries none of the projection keywords
(`feature`, `fix`, `migration`, `rollout`, `consolidation`) verbatim, but the
work shape is feature-altitude -- a new capability added to shirabe's own
skills, not a repair of a broken one. The three defects the exploration
surfaced are consequences of the missing capability, not the work item itself.

### R6 shape-predicate verdicts (pre-PRD, to be re-evaluated post-`/prd`)

- **P1 architectural-alternatives count -- FIRES.** Four alternatives are live
  and unsettled from the exploration: implementation home (plugin shell script
  vs. split shim-plus-binary-subcommand); check depth (presence-and-version vs.
  per-subcommand capability probe); declaration format (`metadata:` frontmatter
  vs. per-skill manifest file vs. a table compiled into the binary); and
  install-advice resolution (delegate to tsuku vs. a per-OS command matrix).
- **P2 new-component references -- FIRES.** The check surface does not exist.
  `crates/shirabe/src/` has no doctor-like module (`Commands` enum is Validate,
  Roadmap, Transition, FinalizeChain, SlugPrefixDetect, InstallHooks,
  WorkSummary, PrBodyHook), and no shared preflight script exists --
  `skills/execute/scripts/preflight.sh` checks one file path and hard-fails,
  which is a different contract.
- **P3 Complex classification -- FIRES.** Two prior design positions must be
  argued past rather than around: `DESIGN-shirabe-pattern-v1-ergonomics`
  Decision 6 rejected per-SKILL inline snippets and once-per-chain probes for
  R30 in favour of lazy-loaded prose, and PR #278 chose a CI matrix over the
  runtime version guard offered in #270.

All three fire, so `/design` is invoked with the full decision roster.

Chain proposal emitted with the Proceed / Adjust / Bail triad and the
pre-authoring upstream notice (both firing conditions held: `/brief` is in
`planned_chain:` and no `consumed_upstream:` was recorded). `--auto` mode
auto-selected **Proceed**.

## Upstream Exploration

This chain is grounded on a completed `/explore` run on the same branch. The
exploration artifacts are inputs, not artifacts this chain reproduces:

- `wip/explore_skill-preflight-checks_crystallize.md`
- `wip/explore_skill-preflight-checks_findings.md`
- `wip/explore_skill-preflight-checks_scope.md`
- `wip/research/explore_skill-preflight-checks_r1_lead-*.md` (7 files)
