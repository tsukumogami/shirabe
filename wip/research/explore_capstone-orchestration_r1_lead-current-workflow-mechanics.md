# Lead: How do shirabe's `/scope`, `/work-on`, and `/plan` skills handle branches, worktrees, PRs, and artifact persistence today?

## Findings

### `/scope` — no branch/worktree/PR mechanics at all; commits docs to the current branch

`/scope` (`skills/scope/SKILL.md`) is a single-agent parent skill that walks
BRIEF → PRD → DESIGN → PLAN as one conversation. Its filesystem surface is a
**closed write-target set** and it never touches branches or PRs:

- State file: `wip/scope_<topic>_state.md` (YAML-in-md, `wip-yaml-md` substrate;
  SKILL.md L498-507 "Binding Notes").
- Durable artifacts it may write directly: Decision Records under
  `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<DATE>.md`
  and force-materialized partials under `docs/{briefs,prds,designs}/<TYPE>-<topic>.md`
  (phase-3-exit-finalization.md L258-283 "Closed Write-Target Set").
- It does **NOT** write the PLAN itself — `/plan` (its child) produces
  `docs/plans/PLAN-<topic>.md`; Phase 3's full-run exit only records the PLAN
  path in `exit_artifacts:` (phase-3 L274-283).

Critically: **there is no `git checkout`, `git branch`, `git push`, or
`gh pr create` anywhere in `/scope`.** The only git operations are:
- `git commit -F <tmpfile>`/stdin for author-supplied prose (Decision Records,
  divergence rationale) — phase-3 L212-240 "`git commit -F` Discipline".
- `git log <pre_invocation_sha>..HEAD` to observe a child's discard commit on
  Phase-N Reject (phase-2-chain-orchestration.md L211-249).
- `git fetch && git rebase origin/<tracking-branch>` as the per-child
  worktree-staleness check (phase-2 L58-122).

So `/scope` operates on **whatever branch the author is already on** (it has no
opinion about which branch that is) and leaves its durable artifacts committed
there. The "Public-History Disclaimer" (phase-3 L242-251) confirms commits land
in the repo's permanent history but says nothing about which branch or any PR.
There is no orchestrator that opens a PR to carry the BRIEF/PRD/DESIGN/PLAN it
produces. The author is expected to be on a branch and to handle PR creation
out-of-band (or via a subsequent `/work-on <PLAN>` run).

`/scope`'s storage substrate **explicitly does not satisfy cross-branch resume**
(invariant I-6): "resume on a different branch starts a fresh chain. Closing the
I-6 gap is the amplifier-layer substrate's mandate" (SKILL.md L502-507). Same-tree
concurrent same-topic invocations are an explicit no-go (SKILL.md L521-526).

### `/plan` — produces artifacts/issues; does git only via cleanup + design-status edit

`/plan` (`skills/plan/SKILL.md`) decomposes a source doc into issues. Two output
shapes:
- **single-pr**: writes `docs/plans/PLAN-<topic>.md` at status **Draft**, with an
  Issue Outlines section. No GitHub issues, no milestone (SKILL.md L439-444).
- **multi-pr**: writes the PLAN at status **Active**, creates a GitHub milestone
  (1:1 with the plan) and GitHub issues with complexity labels (SKILL.md L426-437).
  Roadmap input is always multi-pr.

`/plan` writes all intermediates to `wip/plan_<topic>_*` and deletes them in Phase
7 (SKILL.md L414). It updates the source design doc status Accepted → Planned
(status field only). It does not create a branch or a PR. The PLAN doc is the
handoff artifact consumed by `/work-on`.

The Draft→Active gate is the only difference between modes: multi-pr requires
human approval + GitHub side effects; single-pr auto-fires when authoring
finishes (SKILL.md L58-64). A committed Draft PLAN is a violation in both modes.

### `/work-on` — the only skill that owns branches and PRs; single-PR plan orchestration already exists

`/work-on` (`skills/work-on/SKILL.md`) has four modes (L52-60): plan-backed child,
**plan orchestrator**, issue-backed, free-form. Branch/PR mechanics:

**Single-issue modes** (issue-backed / free-form): Phase 1 setup
(`references/phases/phase-1-setup.md`) creates `feature/<N>-<desc>` /
`fix/...` / `chore/...`, establishes a test baseline (stored in koto context, not
wip/), and commits a baseline commit. Phase 6 (`phase-6-pr.md`) rebases on main,
pushes, runs `gh pr create` with `Fixes #<N>`, and monitors CI. Branch creation is
**conditional** — skipped when `SHARED_BRANCH` is set, when the user said to
continue on the current branch, or when resuming on an existing feature branch
(phase-1-setup L16-26; SKILL.md L201-208).

**Plan orchestrator mode answers the lead's core question: YES.** Driven by
`koto-templates/work-on-plan.md`. The flow:

1. `orchestrator_setup` state creates ONE shared branch `impl/<plan-slug>` and ONE
   **draft PR** up front, before any child is spawned (work-on-plan.md L231-247;
   SKILL.md L105-119). The script is idempotent (reuses branch/PR on re-run).
   Slug derives from the PLAN filename: `PLAN-foo-bar.md` → `impl/foo-bar`.
2. `worktree_discipline_check` rebases the shared branch on main once and
   classifies upstream drift as none/informational/intent-changing
   (phase-2.5-worktree-discipline.md). Intent-changing halts to `done_blocked`.
3. `spawn_and_await` runs `plan-to-tasks.sh` to turn the PLAN into koto tasks,
   injects `SHARED_BRANCH=impl/<slug>` into every task's vars via jq, and
   materializes one `work-on.md` child per issue with `failure_policy:
   skip_dependents` (work-on-plan.md L263-298).
4. Each child runs in **plan-backed child mode**: `SHARED_BRANCH` set → it does
   NOT create a branch, commits directly to the shared branch (`status: override`
   in `setup_plan_backed`), and at `pr_creation` submits `pr_status: shared` →
   skips PR creation entirely (SKILL.md L62-89; phase-6-pr.md L45-49). The
   orchestrator owns the single PR.
5. `pr_finalization` assembles a per-child PR description and `gh pr edit`s it —
   but does NOT mark ready yet (DRAFT-vs-READY discipline).
6. `plan_completion` runs `run-cascade.sh --push {{PLAN_DOC}}` which walks the
   PLAN's `upstream` frontmatter chain and atomically: deletes the PLAN
   (`git rm`), transitions DESIGN → Current, PRD → Done, BRIEF → Done, updates
   ROADMAP feature status (and optionally ROADMAP → Done), commits, pushes — THEN
   `gh pr ready` flips the PR out of draft so strict-mode CI runs on the finalized
   chain (SKILL.md L147-166; work-on-plan.md L331-360).
7. `ci_monitor` waits for green, with explicit DIRTY-merge-state handling.

Quoting the description verbatim (SKILL.md L3): "a PLAN document path (drives
multiple issues through one shared branch and PR)". And L78: "All child workflows
in the batch share this branch and the same draft PR."

So **`/work-on` already implements a single-pr capstone-like orchestration for one
repo**: branch + draft PR up front, multiple issues committed onto it, upstream
artifacts (BRIEF/PRD/DESIGN/ROADMAP) consumed/transitioned and the PLAN deleted at
the end, PR marked ready as the completion signal. This is exactly the shape the
exploration's "capstone PR" generalizes — but bounded to a single repo and keyed
off a single PLAN doc.

### Branch-context reuse / "use this branch" intent already partly modeled

`/work-on` already reads three branch signals (SKILL.md L43-49, L91-95, L201-208):
current branch name matching `impl/<slug>` with an open PR, an explicit user
instruction ("use this branch", "continue here"), or resuming on a prior feature
branch. Any of these → `status: override`, skip branch/PR creation. This is the
seed of the "operating-contract → preference/flag/default" idea: the manual "work
on this branch" instruction is already a recognized per-invocation signal, just
not yet a persisted preference.

### Single-repo-bound vs cross-repo aware

**All three skills are single-repo-bound.** A grep for `niwa`, `cross-repo`,
`multi-repo`, `workspace`, `sibling` across the three SKILL.md files returns
nothing. Concrete bindings:

- `run-cascade.sh` has an inline `validate_upstream_path()` that rejects any
  upstream path resolving **outside the repository root** (`$REPO_ROOT`) — the
  upstream chain walk is hard-confined to one repo.
- `orchestrator_setup`, `pr_finalization`, `plan_completion`, `ci_monitor` all
  operate on one branch, one PR, one `gh` repo context.
- `/scope`'s closed write-target set, state file, and Decision Record paths are
  all repo-relative; visibility is read from the one repo's CLAUDE.md.
- `/scope` SKILL.md L489-496 "v1 binds to public-repo tactical chains
  exclusively"; cross-visibility (let alone cross-repo) extension is explicitly
  deferred.

The only "workspace" awareness lives outside the skills, in CLAUDE.md / niwa mesh
delegation tooling (`niwa_delegate`, etc.) — not invoked by these skills.

## Implications

A "capstone PR" generalizing the single-pr PLAN to a multi-repo org would extend
mechanics that already exist for one repo:

1. **The single-repo template is the prototype.** `work-on-plan.md`'s
   orchestrator_setup (branch+draft-PR up front) → spawn children onto shared
   branch → pr_finalization → plan_completion (cascade consumes upstream
   artifacts, deletes PLAN, `gh pr ready` = completion signal) is structurally the
   capstone-PR lifecycle, just per-repo and keyed to one PLAN. A capstone would
   need a workspace-level orchestrator that creates the PR up front, holds the
   overarching plan + all upstream artifacts (brief/PRD/design/roadmap), and runs
   the cascade-and-ready step LAST.

2. **The upstream-consumption-then-delete cascade already exists** but is confined
   to one repo by `validate_upstream_path`'s `$REPO_ROOT` check. A capstone that
   holds artifacts spanning repos breaks that invariant and needs an explicit
   cross-repo path resolution model.

3. **`/scope` currently has no PR home for its artifacts.** It commits
   BRIEF/PRD/DESIGN/PLAN to the current branch with no PR and no branch opinion.
   For a capstone, `/scope`'s artifacts would need to land on the up-front capstone
   branch/PR — a new contract `/scope` does not have today.

4. **Branch-intent signals are already recognized per-invocation** (the
   override-on-existing-branch logic). Promoting "work on this branch / this is the
   capstone branch" to a persisted workspace preference or a `/scope`-level flag is
   an incremental extension of an existing seam, not a new mechanism.

5. **wip-hygiene already forces consumption-before-merge.** Phase 4 cleanup
   (`/scope`) and the cascade (`/work-on`) both delete wip/ and PLAN before a PR
   can merge. A capstone's "fully consumed (artifacts deleted) before merge"
   requirement maps directly onto this discipline — it would just be enforced at
   the capstone-PR level across repos rather than per-repo.

## Surprises

- The exploration's "capstone PR" is **already implemented in miniature** for the
  single-repo single-pr PLAN case: PR created up front (draft), holds the plan,
  updated as children run, the cascade consumes upstream artifacts + deletes the
  PLAN, and `gh pr ready` is the completion signal. The generalization is
  multi-repo + multi-artifact, not a from-scratch concept.
- `/scope` produces a PLAN but takes no responsibility for branch/PR at all — there
  is a clean handoff gap between `/scope` finishing and `/work-on <PLAN>` opening
  the branch/PR. An author bridging that gap manually is exactly the "operating
  contract paste" the exploration describes.
- The DRAFT-vs-READY discipline (cascade strictly before `gh pr ready`) is a
  load-bearing ordering tied to CI strict-mode re-runs — a capstone would have to
  preserve this ordering at the workspace level.

## Open Questions

- How would a workspace-level capstone PR relate to the per-repo `impl/<slug>` PRs
  that `/work-on` plan-orchestrator mode already creates? Is the capstone a parent
  PR in one "home" repo, or a coordinating artifact above N per-repo PRs?
- `validate_upstream_path` hard-rejects cross-repo upstream paths. Does a capstone
  store all upstream artifacts in one repo, or does it need a new cross-repo
  resolver (and how does that interact with the wip-hygiene `upstream:`-reject
  rule)?
- `/scope`'s I-6 cross-branch-resume gap ("resume on a different branch starts a
  fresh chain") — does a capstone require closing this first, since the author
  would run `/scope` then `/work-on` against a shared capstone branch?
- Where would `/scope`'s artifacts get committed if a capstone branch is created
  up front — does `/scope` gain a branch contract, or does a new outer skill set
  the branch before `/scope` runs?

## Summary

`/scope` has no branch/worktree/PR mechanics at all — it commits BRIEF/PRD/DESIGN
Decision-Records (and the child-produced PLAN) to whatever branch the author is
on, via `git commit -F`, with no branch creation and no PR, leaving a manual
handoff gap that `/work-on <PLAN>` later fills. `/work-on` already drives a PLAN
doc's multiple issues through ONE shared `impl/<slug>` branch and ONE draft PR
created up front, with children committing directly to it and a final cascade that
consumes the upstream BRIEF/PRD/DESIGN/ROADMAP and deletes the PLAN before `gh pr
ready` fires as the completion signal — a single-repo prototype of the exploration's
capstone PR. All three skills are strictly single-repo-bound (the cascade's
`validate_upstream_path` rejects paths outside `$REPO_ROOT`), so generalizing to a
multi-repo capstone means extending existing per-repo seams rather than inventing
new mechanics.
