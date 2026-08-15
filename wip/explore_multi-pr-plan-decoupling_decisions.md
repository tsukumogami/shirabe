# Exploration Decisions: multi-pr-plan-decoupling

## Round 1

- Config channel settled on CLAUDE.md convention headers: seven scalar
  preferences already live there on a `flag > CLAUDE.md-header > default` stack,
  Rust parses them through one generic tested walker, and
  `DESIGN-roadmap-issueless-preference.md` already rejected a `.shirabe.toml`
  layer as disproportionate for a single preference. No third config channel.
- `team.yaml` eliminated as a config surface: it declares koto agent-fan-out
  topology (roles, cardinality, upper bounds per phase), not repo preferences.
- `.claude/shirabe-extensions/*.md` eliminated as the binding point for these
  two preferences: it is built for file-glob-to-command tables (the work-on
  verification map), not scalar enums, which CLAUDE.md headers already own.
- Reusing the name `Execution Mode` for the new decomposition preference ruled
  out: that CLAUDE.md header already means autonomy (`auto|interactive`) and
  collides with the unrelated `execution_mode` PLAN frontmatter enum. A third
  meaning would be actively harmful.
- Issue count, dependency-graph depth, and complexity labels eliminated as "can"
  gate signals: `/execute`'s single-pr path already drives many dependent issues
  through one shared branch and PR, and complexity labels measure per-issue
  review rigor, a different axis.
- "Cross-repo implies multi-pr" rejected as a candidate rule: cross-repo routes
  to `coordinated`, a structurally distinct third mode with its own lifecycle,
  merge-order DAG, and validator. A rule naming multi-pr would be wrong.
- Milestone-worthiness reframed from a significance judgment to a mechanical one:
  shirabe milestones carry no progress rollup, completion trigger, or cascade
  role -- their sole functional consumer is `/work-on M<N>` issue selection -- so
  the answerable question is "does this plan need a GitHub-side grouping handle,"
  not "is this a project milestone."
- Scope accepted: decoupling tracking re-opens the Draft->Active approval gate,
  whose asymmetry is justified in `DECISION-multi-pr-posture-detection-2026-06-06.md`
  precisely by multi-pr being the moment remote artifacts are created. Re-keying
  that gate on "does this run create GitHub artifacts" is a consequence to carry,
  not a surprise to discover later.
- Amend rather than re-derive: `DESIGN-roadmap-plan-standardization.md`
  Decision 6 is the current owner of the single-pr/multi-pr rule and already did
  the decomposition-strategy/execution-mode de-conflation. New work amends it.
