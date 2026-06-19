# Lead

What does shirabe's `/plan` use as its decomposition unit today, how do those units map to PRs, and what would it take to make the effective unit a "grouped, per-repo, merge-ordered PR" instead of a per-issue or per-PR-per-repo unit?

## Findings

### The decomposition unit today is the *issue*

`/plan` decomposes a source doc (DESIGN/PRD/ROADMAP/topic) into **atomic issues**. The unit is named explicitly and consistently across the skill:

- `skills/plan/SKILL.md:418` — "**Atomic Issues**: each issue should be independent and completable in one session."
- `skills/plan/references/phases/phase-3-decomposition.md:44-50` — issues are "Atomic / Independent / Complete," one focused deliverable each.
- `skills/plan/references/quality/plan-doc-structure.md` (referenced) and `plan-format.md:300-303` — "Each issue is atomic: a single PR can ship it. If an issue requires multiple PRs, split it."

So the *authoring* granularity is the issue; the *delivery* granularity is governed separately by execution mode (below). There is no first-class "PR" object and no "repo group" object in the model.

### Issue → PR mapping is set by `execution_mode`, NOT by repo

Execution mode is a frontmatter field (`execution_mode: single-pr | multi-pr`, `plan-format.md:40-43`) chosen in Phase 3.6 (`phase-3-decomposition.md:444-507`). It is the *only* knob that controls how issues collapse into PRs:

- **single-pr** — ALL issues in the PLAN land in ONE PR on ONE shared branch. The PLAN stays self-contained (no GitHub issues); issues are "Issue Outlines" with local anchors (`plan-format.md:131-138`). This is the default (`SKILL.md:146`, anchored on principle P1 "usable value is the unit of work").
- **multi-pr** — each issue maps 1:1 to a GitHub issue, and "Each issue ships its own PR" (`plan-format.md:138`). Materializes a GitHub milestone + issues at Phase 7.

Crucially, the two existing modes are the two *extremes* of the grouping spectrum: single-pr collapses everything to one group; multi-pr makes every issue its own group. **There is no middle setting — no "group these N issues into one PR, those M into another."** The capstone requirement ("related work within a repo grouped into one PR; a repo MAY have >1 PR") is exactly this missing middle.

### The dependency graph is issue-level (`waits_on`), and it is the collapse-target

Dependencies are expressed per-issue:

- In the PLAN doc: a `Dependencies` column (multi-pr table) or a `**Dependencies**:` line per outline (single-pr), plus a Mermaid `graph TD` with `I<N> --> I<M>` edges (`plan-format.md:142-160`).
- Serialized by `skills/plan/scripts/plan-to-tasks.sh` into koto task entries `{name, vars, waits_on:[...]}`. `waits_on` is **issue-level**: multi-pr emits `issue-<N>` names with `waits_on` of `issue-<M>` (script L100-232); single-pr emits `o-<slug>` names with `waits_on` of the referenced outline's slug (L235-542).
- `plan-to-tasks-contract.md` is the stable contract: `waits_on` = "Names of tasks this task depends on."

A subtle extra edge source already exists in single-pr: **file-collision edges**. When two outlines declare the same `**Files**:` path, the later one gets a `waits_on` edge to the earlier (`plan-to-tasks.sh:444-516`). This is a precedent for *deriving* DAG edges from a per-issue attribute — directly relevant to deriving repo/group edges from a `repo:`/`group:` attribute.

The DAG is consumed by koto's scheduler (the `work-on-plan.md` koto template runs `plan-to-tasks.sh`, injects `SHARED_BRANCH`, and submits `{"tasks":[...]}`). The scheduler parallelizes independent tasks and respects `waits_on`. So **the DAG is the natural object to collapse to PR/repo level** — it already carries the ordering semantics.

### `/work-on` plan mode: ONE branch + ONE PR, single-repo today

`skills/work-on/SKILL.md:39-166` (Plan Mode):

- `orchestrator_setup` creates ONE shared branch `impl/<plan-slug>` and ONE draft PR (`SKILL.md:105-119`).
- `spawn_and_await` runs `plan-to-tasks.sh`, injects the single `SHARED_BRANCH` into every task, and spawns per-issue child workflows (`-- plan-backed`). Every child commits to the same branch and the orchestrator owns the single PR (`SKILL.md:62-89`, `pr_status: shared`).
- `pr_finalization` updates that ONE PR; `plan_completion` runs the cascade then `gh pr ready` on that ONE PR.

So in *both* single-pr and multi-pr, the **work-on orchestrator drives one branch + one PR**. (multi-pr's "each issue ships its own PR" is the *intended* model per the format doc, but the plan-orchestrator path funnels a PLAN's children onto one shared branch/PR regardless.) There is no per-repo branch fan-out, no per-group PR fan-out, and no cross-repo `git`/`gh` context switching. The orchestrator is hardwired single-repo: it `git checkout`s one branch in the current repo and creates one PR there.

### What "repo" awareness exists today (thin and unstructured)

The only repo notion is in **strategic scope**:

- `phase-3-decomposition.md:117-121` — strategic issues are titled `docs(<target-repo>): design <purpose>` and "Target repo is specified in the issue body" (prose, not a structured field).
- `phase-7-creation.md:113` and `create-issues-batch.sh` — a `repo:<target-repo>` GitHub *label* is applied **uniformly to all issues in the batch** via the global `--labels` flag. It is one repo per milestone, not per-issue, and it is a label string, not a routing primitive consumed by `/work-on` or `plan-to-tasks.sh`.

Neither the PLAN frontmatter, the Implementation Issues table columns (`Issue | Dependencies | Complexity`, `plan-format.md:98-102`), nor the koto task vars carry a per-issue `repo:` or `group:` field. `plan-to-tasks.sh` does not read or emit one.

## Implications

### Two design options (the lead's (a) vs (b))

**Option (a): per-issue attributes + DAG collapse.** Tag each issue with `repo:` (target repo) and a `pr_group` key, then collapse the issue-level `waits_on` DAG into a PR/repo-level DAG. This fits the existing machinery best:

- It reuses the existing per-issue-attribute → derived-edge precedent (the `**Files**:` collision edges in `plan-to-tasks.sh:444-516`).
- The collapse is a quotient of the issue DAG: nodes = distinct `(repo, pr_group)` pairs; an edge `G1 → G2` exists iff any issue in G1 `waits_on` any issue in G2. `plan-to-tasks.sh` (or a new sibling, e.g. `plan-to-pr-groups.sh`) emits PR-group task entries with `waits_on` at group granularity, plus a `repo` var per group.
- `/work-on` plan mode changes from "one branch/PR" to "one branch/PR **per PR-group**, in the target repo, scheduled by the collapsed DAG." `SHARED_BRANCH` becomes per-group; `orchestrator_setup` fans out branch+draft-PR creation per group; cross-repo groups need `gh -R <repo>` / per-repo checkout.
- Repo boundary is enforced by construction: two issues in different repos can never share a `pr_group` (the group key must be `(repo, group)` or repo must be a hard partition key).

**Option (b): explicit PR-grouping layer.** Introduce a new PLAN section/object ("PR Groups") that names groups, lists member issues, names the target repo, and declares group-level merge order — a layer above issues. More expressive (a human can author the grouping and the cross-repo order directly) but it duplicates ordering info that already lives in the issue DAG and creates a reconciliation burden (FC-style check: every issue in exactly one group; group order consistent with issue `waits_on`).

**Recommendation surfaced by the evidence:** (a) is the lower-friction path *because the issue DAG already exists and already collapses cleanly*; (b)'s explicit order is mostly redundant with the derived collapse. The one thing (a) needs that doesn't exist is the `pr_group` assignment itself — which is a Phase 3 decomposition decision, not a new artifact.

### Where the grouping + collapse would live

- **Assignment** (`repo` + `pr_group` per issue): Phase 3 decomposition (`phase-3-decomposition.md`), as new outline fields alongside `**Type**`/`**Dependencies**`/`**Files**`, plus a new Implementation Issues table column (or a per-issue annotation). This is the same altitude where execution_mode and Files already live.
- **Schema**: PLAN frontmatter / table needs `repo` + `pr_group` fields; `plan-format.md` table contract (`plan-format.md:93-140`) and the FC05/FC06/FC07 validator checks would extend to recognize them.
- **Collapse**: `plan-to-tasks.sh` / a sibling script — emit group-level task entries with group-level `waits_on` and a `repo` var. The contract (`plan-to-tasks-contract.md`) extends with a third emission shape ("grouped" alongside single-pr/multi-pr).
- **Execution**: `/work-on` plan mode — per-group branch/PR fan-out keyed off the collapsed DAG, with cross-repo `gh -R`/checkout. This is the largest change; today's orchestrator is single-branch/single-repo end to end.

### What breaks: collapse can create merge-order cycles

The critical hazard. The issue DAG is acyclic (Phase 5.5 validates "No circular dependencies"). **But a quotient of an acyclic graph is NOT guaranteed acyclic.** If issue A1 (group G1) `waits_on` B1 (group G2), and B2 (group G2) `waits_on` A2 (group G1), the collapsed graph has G1 → G2 *and* G2 → G1 — a merge-order cycle that has no valid PR landing order, even though every issue edge was fine. This means:

- The grouping step MUST run a cycle check on the *collapsed* DAG, not just the issue DAG. Phase 5/6 validation needs a new "collapsed-DAG is acyclic" check.
- A detected cycle is a *mis-grouping* signal (two groups are mutually entangled and should be merged, or an issue is in the wrong group), structurally analogous to the existing value-confirmation guard (Phase 3.5a) that flags mis-decomposition. The fix is to merge the cyclic groups or re-assign the offending issue — which can collide with the "minimize churn / group related work" goal.
- Repo boundaries as *hard* partition keys reduce but do not eliminate this: cross-repo cycles (G1 in repo X waits on G2 in repo Y and vice versa) are exactly the cross-repo merge-order deadlock the capstone must detect and refuse.

## Surprises

- **There is no PR object anywhere in `/plan` today.** "PR" is purely emergent from `execution_mode` (all-in-one vs one-per-issue). The capstone's "grouped per-repo PR" is a genuinely new first-class concept, not a tweak to an existing field.
- **multi-pr's documented "each issue ships its own PR" is contradicted by the actual `/work-on` plan-orchestrator path**, which funnels a PLAN's children onto ONE shared branch + ONE PR (`work-on/SKILL.md:105-166`). So the *real* effective unit is already "one PR per PLAN" in practice — the capstone wants to slot a grouping granularity *between* PLAN-level and issue-level.
- **`plan-to-tasks.sh` already derives DAG edges from a per-issue attribute** (the `**Files**:` collision logic, L444-516). The repo/group-collapse is a direct generalization of a pattern that already ships, which makes Option (a) materially cheaper than it first appears.
- **A repo field already half-exists but only in strategic scope and only as a uniform batch label** (`repo:<target-repo>`, one repo per milestone, in the issue body as prose). It is not structured, not per-issue, and not consumed by execution — but it establishes the naming convention (`repo:<name>`) a capstone could formalize.

## Open Questions

1. Is `pr_group` author-assigned (explicit, Option b-flavored) or *inferred* from issue clustering (by shared files / scope / `waits_on` density)? Inference keeps Phase 3 light but risks surprising groupings; explicit assignment adds authoring burden.
2. Should `repo` be a hard partition on `pr_group` (a group is always single-repo by definition) or a separate field that the collapse uses to forbid cross-repo groups? The former is cleaner; the latter allows future "intentional cross-repo group" escape hatches.
3. Does the collapsed-DAG cycle check belong in `/plan` (Phase 5/6, fail-at-authoring) or in `/work-on` (fail-at-execution)? Authoring-time is the wip-hygiene-friendly answer but requires the collapse logic to run inside `/plan`.
4. How does `/work-on` plan mode acquire cross-repo working trees? Today it operates in one repo's checkout. Per-group branches in different repos need either niwa workspace multi-repo checkout or per-group `gh -R`/clone — a substantial orchestrator change not scoped by `/plan` alone.
5. Does the single-pr/multi-pr binary survive, or does "grouped" become a third execution_mode value (single-pr = 1 group, multi-pr = N groups of 1, grouped = the general case)? Treating the existing two as degenerate cases of "grouped" is the cleanest model and would let `plan-to-tasks.sh` carry one code path.

## Summary

Today `/plan`'s decomposition unit is the atomic *issue*, and issues collapse to PRs only via the `execution_mode` binary — single-pr puts every issue in one shared branch/PR, multi-pr makes each issue its own (though `/work-on`'s plan orchestrator funnels even multi-pr children onto one branch/PR), with no per-repo or per-PR-group concept and an issue-level `waits_on` DAG serialized by `plan-to-tasks.sh`. To get grouped-per-repo merge-ordered PRs, the lowest-friction path is Option (a): tag each issue with `repo` + `pr_group` in Phase 3, then collapse the issue DAG into a `(repo, pr_group)`-level DAG in a `plan-to-tasks.sh` sibling — reusing the existing per-issue-attribute-to-derived-edge precedent (the `**Files**:` collision logic), with the collapse and a per-group branch/PR fan-out landing in `/work-on` plan mode. The load-bearing hazard is that quotienting an acyclic issue DAG can produce merge-order *cycles* between groups, so the grouping step must add a collapsed-DAG acyclicity check that treats cross-group cycles (especially cross-repo ones) as a mis-grouping to refuse.
