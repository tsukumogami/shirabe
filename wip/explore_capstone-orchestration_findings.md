# Exploration Findings: capstone-orchestration

## Core Question

The author repeatedly pastes a long "how we will work this session" prompt before
running `/scope` then `/work-on` across a multi-repo niwa workspace. Which parts of
that manual operating contract can be baked into shirabe's workflows as workspace
preferences, per-invocation intent/flags, or smart defaults — and how should the
central idea, a **capstone PR** (a single-pr PLAN generalized to a multi-repo org),
be incorporated into the `/scope` → `/work-on` chain?

## Round 1

### Key Insights

- **`/work-on` already runs a single-repo prototype of the capstone** (lead:
  current-workflow-mechanics). It opens one `impl/<slug>` branch + one draft PR up
  front, children commit into it, then a final cascade consumes the upstream
  BRIEF/PRD/DESIGN/ROADMAP, deletes the PLAN, and fires `gh pr ready` as the done-signal.
  `/scope` itself has no branch/worktree/PR mechanics — it commits artifacts to the
  current branch, leaving a manual handoff gap that `/work-on <PLAN>` fills.
- **The lifecycle concept + consume-before-merge CI invariant lift cleanly** (lead:
  singlepr-plan-lifecycle). `.github/workflows/lifecycle.yml` already fails a
  ready-for-review PR that still carries a live PLAN. But three mechanisms are
  single-repo-bound: `finalize.rs` deliberately STOPS the chain walk at any cross-repo
  `owner/repo:path` upstream; `run-cascade.sh` rejects paths outside one git root and
  validates issues against a single `origin`; `validate_upstream_path` rejects paths
  outside `$REPO_ROOT`.
- **The merge-order primitive already exists** (lead: capstone-state-merge-order):
  `/plan` computes a validated, topologically-orderable issue DAG serialized as
  `waits_on` edges via `plan-to-tasks.sh`. Gap: lift it from an issue-node graph to a
  per-repo-PR graph by tagging issues with their target repo.
- **The example PRs document the concrete pattern** (lead: example-prs), already in
  shirabe's vocabulary: a docs-only PR on `feature/<slug>`, titled
  `docs(<type>): <effort> (capstone)`, holding `docs/<type>/*.md` with status
  frontmatter and `upstream:` chain pointers; merge order expressed in the PR *body*
  (a cross-repo PR-index table + a fenced merge-order block); created up front, updated
  across the session (10+ narrating commits, including a "reconcile capstone with
  live-validation outcome" commit); done = every index row MERGED + completion cascade
  run (statuses terminal, PLAN deleted). Artifact *set* is effort-dependent; the
  *role* (top-of-effort index/record, merged last, cascade-finalized) is the constant.
- **Interface model is settled by precedent** (lead: interface-model-tradeoffs):
  shirabe runs a `flag > CLAUDE.md-header > hard-default` stack (proven for execution
  mode and scope). Conventions 1/2/3/5 → smart defaults (infer + announce + override);
  convention 4 (≤1 worktree/repo) → durable CLAUDE.md preference + override.
- **Capstone state home = the capstone branch/PR itself** (lead:
  capstone-state-merge-order): re-discoverable after a context reset, wip-hygiene-clean,
  cleared on merge. The "consumed before merge" vs "state must persist" tension dissolves:
  the persistent anchor is the PR/branch; the ephemeral, cascade-deleted thing is the
  PLAN body.
- **Prior art = simple recombination** (lead: prior-art): Changesets (consumed-on-completion
  intent artifact) + Gerrit topics (cross-repo all-ready gate) + stacked-PR merge-last
  each contribute one mechanic. The merge-queue family (GitHub, bors, Mergify, GitLab
  trains) is overkill for a single author — its machinery exists to serialize concurrent
  contributors. "Created first as the plan, merged last as completion" ships in no single
  tool.

### Tensions

- **niwa got thinner, not richer** (lead: niwa-primitives): the mesh/delegation the
  workspace docs advertise has been removed (BRIEF/DESIGN-niwa-mesh-removal). Only
  `niwa worktree create/apply/destroy/list/attach` is live, with state at
  `.niwa/sessions/<id>.json` and `.niwa/instance.json` (which silently drops foreign
  keys). So ALL capstone/ordering orchestration must live in shirabe. A dormant
  `parent_session_id` field could link child worktrees to a capstone but isn't settable
  from the CLI yet.
- **Cross-repo PR-state tracking is the genuinely unsolved part**: in the examples the
  index table was updated by hand as other-repo PRs merged. Automating it (poll `gh`
  across repos, or a niwa-level aggregator) is the highest-design-risk piece.

### Gaps (now framed as design decisions)

- What triggers the completion cascade (manual command vs. detecting all-PRs-merged).
- How a capstone in repo A learns the merge state of PRs in repos B/C.
- Whether there's a canonical capstone-body template.
- Branch rebase cadence over a multi-day session.

### Decisions

See `wip/explore_capstone-orchestration_decisions.md`. Summary: home = shirabe
(Public, Tactical); interface = smart defaults for conventions 1/2/3/5 + durable
preference for convention 4; scope = full cross-repo lifecycle, design-whole +
sequence-delivery (DESIGN + ROADMAP, walking skeleton first); state home = the
capstone branch/PR; merge order = lifted `/plan` `waits_on` DAG with per-repo tagging.
Eliminated: ergonomics-only, scaffolding-first-standalone, another explore round.

### User Focus

The author leaned toward the full cross-repo lifecycle and explicitly wanted the
risk surface ("what I don't know") made visible before committing, applying
decision-framework rigor. After seeing the six unknowns, confirmed full lifecycle
with sequenced delivery.

## Accumulated Understanding

The capstone PR is not a new primitive — it is the **multi-repo generalization of a
mechanism shirabe already runs single-repo**: `/work-on`'s shared-branch plan
orchestrator (one branch, one PR, consume-upstream-and-delete-PLAN cascade, `gh pr
ready` done-signal) plus `/plan`'s `waits_on` DAG plus the `lifecycle.yml`
consume-before-merge invariant. The example PRs prove the target pattern in shirabe's
own artifact vocabulary and show the three things a tool must add over the manual
process: (1) a templated capstone PR body with a cross-repo PR-index table + merge-order
block, kept in sync as per-repo PRs merge; (2) a cross-repo chain walk / cascade
(lifting `finalize.rs` and `validate_upstream_path` past their single-repo guards via
an accepted `owner/repo:path` scheme); (3) a merge-gate that blocks the capstone until
every per-repo PR is MERGED.

The interface is settled: smart defaults (announce + override) for the capstone,
artifact-persistence, sequencing, and merge-order behaviors; a durable CLAUDE.md
preference for the ≤1-worktree-per-repo policy. Capstone session state lives on the
capstone branch/PR itself, so it survives context resets and clears naturally on merge.
niwa contributes only worktree plumbing (mesh removed), so shirabe owns all
orchestration. Prior art confirms this is a simple, novel recombination — no merge-queue
machinery needed for a single author.

The remaining unknowns (cross-repo PR-state tracking, the cascade trigger, lifting
`finalize.rs` across repos, the merge-gating mechanism, the niwa `parent_session_id`
seam, the docs-only-skips-CI wrinkle) are design decisions, best resolved inside a
DESIGN with per-decision trade-off analysis — then sequenced for delivery via a ROADMAP.

## Decision: Crystallize
