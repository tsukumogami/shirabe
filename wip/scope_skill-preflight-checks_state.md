```yaml
topic: skill-preflight-checks
chain_started: 2026-08-15T01:53:49Z
last_updated: 2026-08-15T01:53:49Z
phase_pointer: phase-4
exit: full-run
exit_artifacts:
  - docs/plans/PLAN-skill-preflight-checks.md
  - docs/briefs/BRIEF-skill-preflight-checks.md
  - docs/prds/PRD-skill-preflight-checks.md
  - docs/designs/DESIGN-skill-preflight-checks.md
  - docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md
plan_execution_mode: single-pr
planned_chain:
  - brief
  - prd
  - design
  - plan
  - plan
chain_skipped: []
chain_ran:
  - brief
  - prd
  - design
  - plan
child_snapshots:
  brief:
    status: Accepted
    content_hash: 64b5336a84f221d5ba2a52a835e46d604ee22eb8
    captured_at: 2026-08-15T02:20:00Z
    artifact: docs/briefs/BRIEF-skill-preflight-checks.md
    validator: clean
    jury: all-PASS on second pass; first pass FAIL on content quality, 7 required changes applied
  plan:
    status: Active
    content_hash: a18f3640199c41f6ca66874cfcab14b22b5ffdc4
    captured_at: 2026-08-15T06:30:00Z
    artifact: docs/plans/PLAN-skill-preflight-checks.md
    validator: clean (one deliberate FC14 notice)
    issue_count: 19
  design:
    status: Planned
    content_hash: 65bf3a8037b53be8977df31007e1f51ccee034f6
    captured_at: 2026-08-15T05:10:00Z
    artifact: docs/designs/DESIGN-skill-preflight-checks.md
    validator: clean
    jury: PASS on second pass; architecture and security both FAILed pass 1 (13 required changes), all applied
    carried_to_plan: >-
      Three non-blocking implementation traps from the final verification:
      (1) empty SHIRABE_PREFLIGHT_ROOTS aborts under set -u in bash 3.2 via
      "${arr[@]}" on an empty array, and the failure is swallowed by the
      || true guard; (2) the probe watchdog must explicitly release inherited
      capture file descriptors or every probe costs the full 2s timeout and a
      real hang is never killed -- measured at 2.014s on a 3ms call, roughly
      18s per /work-on load, and no planned test catches it; (3) flag
      tokenization inside an option line is unspecified, and a literal
      first-token reading drops --help, contradicting the design's own
      example block.
  prd:
    status: Accepted
    content_hash: 8e184dd2967e1d3bcef12b441dc1b5d8a744d8f1
    captured_at: 2026-08-15T03:40:00Z
    artifact: docs/prds/PRD-skill-preflight-checks.md
    validator: clean
    jury: PASS on final pass; three-axis jury FAILed all three on pass 1 (35 required changes), combined re-review FAILed with 6 must-fix, all applied
consolidation_judgments:
  - hop: design-into-plan
    verdict: keep
    reason: >-
      Not absorbable. A PLAN's required sections have no home for a DESIGN's
      Considered Options, Decision Outcome, Solution Architecture, or Security
      Considerations. The PLAN is also deleted by the completion cascade while
      the DESIGN is durable, so absorbing would destroy the record.
  - hop: prd-into-design
    verdict: keep
    reason: >-
      Not absorbable. A DESIGN's required sections have no home for a PRD's
      Requirements or Acceptance Criteria, so the mapping is not total and
      absorption would discard content rather than relocate it.
  - hop: brief-into-prd
    verdict: keep
    reason: >-
      The BRIEF's Problem Statement carries the survey of six coexisting
      mechanisms and the answer to Decision 6, neither restated in the PRD.
      Its five journeys name concrete entry points the PRD's role-framed
      user stories compress away. The upstream does work the downstream
      does not, so the hop is not absorbable.
decisions_recorded:
  - docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md
visibility: Public
pre_invocation_sha: 6872e04fea7c67de2f19c443ac43f85a85877786
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-08-15T01:58:00Z
    notes: origin/main fetched; branch 0 behind, 4 ahead. No rebase required.
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
