# Lead: How does `/execute` invoke `/work-on` today -- what crosses the boundary, and what does each side assume the other has done?

## Findings

### 1. The exact invocation sites

There are **two distinct dispatch mechanisms** in play, and the design's own pattern
reference (`references/parent-skill-pattern.md:506-535`, "Dispatch Mechanism") names
both explicitly rather than treating `/execute` as a variance:

- **Inline Skill-tool invocation** — used by `/scope`/`/charter` for their authoring
  children, not by `/execute`.
- **"Materialized `/work-on` runs"** (`references/parent-skill-pattern.md:518-523`):
  > "`/execute` submits its per-issue children to a koto session that materializes
  > one child per issue against `/work-on`'s child template, and drives that loop
  > rather than blocking on a single call. Its coordinated path dispatches the same
  > `/work-on` single-issue run per repo through a plain durable-state loop instead
  > of a koto session."

The concrete site for the single-pr path is `spawn_and_await`'s `materialize_children`
block in `skills/execute/koto-templates/execute.md:302-305`:

```yaml
materialize_children:
  from_field: tasks
  failure_policy: skip_dependents
  default_template: ../../work-on/koto-templates/work-on.md
```

koto is pointed **directly at the koto template file** (`work-on.md`), not at the
`/work-on` slash command. The tasks are produced by
`skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}}` (`execute.md:598`), each task's
`vars.SHARED_BRANCH` is set to the branch recorded by `settled_branch_record`
(`execute.md:605-606`), and the whole set is submitted with
`koto next {{SESSION_NAME}} --with-data @"$TMP"` (`execute.md:608`). Before any of
this fires, `skills/execute/SKILL.md:161-174` (Step 1 of both the single-pr and
coordinated paths, repeated at `SKILL.md:322-329`) requires:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/assert-child-template.sh
```

For the **coordinated** path there is no shared koto session at all (`SKILL.md:295-309`,
`DESIGN-execute-skill.md` Decision 1 Option C): the SKILL itself drives a plain
durable-state loop, and Step 2 item 3 (`SKILL.md:358-360`) dispatches "each unblocked
PR node ... to `/work-on`'s `work-on.md` per repo, on that repo's own branch (the same
per-issue delegation contract the single-pr path uses, minus the shared branch)."

### 2. What crosses the boundary

Per task (single-pr path), the koto task JSON carries `name`, `vars`, `waits_on`
(`skills/plan/scripts/plan-to-tasks.sh:6`). The vars that reach the child template
are exactly the ones `work-on.md` declares in its `variables:` block
(`skills/work-on/koto-templates/work-on.md:15-41`): `ISSUE_NUMBER` (issue-backed
only), `ISSUE_TYPE` (default `code`), `ARTIFACT_PREFIX` (required), `ISSUE_SOURCE`
(`github`/`plan_outline`), `PLAN_DOC`, `SHARED_BRANCH`. `plan-to-tasks.sh:712-728`
(`process_single_pr`) builds `vars: {ISSUE_SOURCE, ARTIFACT_PREFIX, ISSUE_TYPE}` (or
without `ISSUE_TYPE` when the outline has none), and `execute.md:606` injects
`SHARED_BRANCH` afterward via `jq`. `PLAN_DOC` itself is a template variable of the
**parent** template (`execute.md:11-13`) referenced by the state prose, and is passed
into `spawn_and_await`'s shell as `{{PLAN_DOC}}`.

`SKILL.md`'s own text also documents an argument-string form of the same handoff:
"Mode Detection" (`skills/work-on/SKILL.md:143-152`) says `/work-on`, invoked as a
slash command, recognizes plan-backed child mode when `$ARGUMENTS` begins with
`-- plan-backed` (checked first, highest priority), and "Plan-Backed Child Mode"
(`SKILL.md:154-183`) lists the variables extracted from the remaining arguments:
`ISSUE_SOURCE`, `ISSUE_NUMBER` (github source only), `ARTIFACT_PREFIX`, `PLAN_DOC`,
`ISSUE_TYPE`. This is the same variable set the koto template declares. Whether koto's
`materialize_children` actually round-trips through this `-- plan-backed` argument
string when it spawns the agent that drives the child koto session, or whether it
seeds the child koto session's `entry` state directly with evidence
(`mode: plan_backed`, `issue_source`, ...) bypassing `SKILL.md`'s argument parsing
entirely, is **not determinable from the code in this repo** — koto's own
materialization runtime is external to `shirabe`. Both `SKILL.md`'s prose and the
koto template's `entry` state (`work-on.md:44-76`) are consistent with either
account.

No environment variables cross the boundary. `PLUGIN_ROOT` is explicitly *not*
passed to children this way — it is resolved once by the invoking shell into
`--var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}` at the parent's own `koto init`
(`execute.md:24-35`, `SKILL.md:196-200`), because koto template strings never
resolve shell-style `${...}` — only `{{KEY}}`.

### 3. `assert-child-template.sh`

`skills/execute/scripts/assert-child-template.sh:15-29` resolves
`${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md` (falling back to a
relative `../../..` walk from the script's own location if the env var is unset) and
exits 1 with a stderr message if the file is missing. It asserts nothing about
`work-on`'s *behavior* — only that the cross-skill relative path
`../../work-on/koto-templates/work-on.md` referenced from `execute.md:305` actually
resolves in this install, "otherwise a silent failure at child-spawn time" per the
script's own header comment. `SKILL.md:161-174` runs it before Step 2 (`koto init`)
in both the single-pr and coordinated paths, and a non-zero exit halts the run before
any child is spawned.

### 4. koto session topology

`DESIGN-execute-skill.md` Decision 1 states it plainly: "Per-issue delegation is
uniform: one `/work-on` (`work-on.md`) invocation per issue, **each its own koto
session**." The parent session is named `execute-<plan-slug>` (`SKILL.md:188`,
`execute.md:127` reconstructs it from `{{PLAN_SLUG}}` rather than trusting
`{{SESSION_NAME}}` in a `default_action`, for the koto 0.12.1 substitution-order
reason documented at `execute.md:105-121`). Each materialized child gets its own
session name (the task's `name` field from `plan-to-tasks.sh`), and
`references/cross-issue-context.md:1-16` confirms per-child sessions are addressable
independently: it collects `koto context get "$child" summary.md` from each
completed child by name and writes the combined text into the *next* child's session
with `koto context add <new-child-name> current-context.md --from-file
current-context.md` before that child is dispatched (`execute.md:247-248` calls this
out as the required step between children). So: parent and children are separate
koto sessions; there is no shared/nested koto context, only this explicit
context-relay file passed hand-to-hand.

### 5. What `/execute` assumes `/work-on` has done when a child returns

`SKILL.md:686-703` ("Child Inspection") is explicit that `/execute` inspects
**status surfaces only, never child artifact bodies** (R14/R15): for a `/work-on`
execution child "the surface is the PR state (Open / Closed / Merged), its labels,
and its CI check rollup — read through `gh` metadata," feeding
`child_snapshots:`'s content-fingerprint (`SKILL.md:430-435`). It does not assume
the child merged its PR, or even (for single-pr) that the child created a PR at all
— in the single-pr path the child never creates its own PR (see §7): `pr_creation`
for a `SHARED_BRANCH` child submits `pr_status: shared` and routes straight to
`done` (`work-on.md:766-767`), so `/execute`'s per-child status read in that path is
against the one shared PR it created itself in `orchestrator_setup`, not a
child-owned artifact. For the **coordinated** path, where each per-repo child *does*
create its own PR, `/execute` reads "each indexed PR's live merged/open status"
(`SKILL.md:342-345`) via `gh`, and the done-signal for the whole effort is gated on
`shirabe validate --merge-gate --mode=ready` (`SKILL.md:374-382`) — `/execute` never
confirms the child ran a finalization cascade on that PR (see §8: `/work-on` has no
such cascade at all).

### 6. What `/work-on` assumes its caller has already done

Plan-Backed Child Mode (`SKILL.md:154-183`) assumes the caller supplies
`ISSUE_SOURCE`, `ISSUE_NUMBER` (github only), `ARTIFACT_PREFIX`, `PLAN_DOC`,
`ISSUE_TYPE` as evidence/vars. When `SHARED_BRANCH` is set it assumes: (a) the
branch already exists and is checked out — `setup_plan_backed` is `skip_if
vars.SHARED_BRANCH: {is_set: true}` (`work-on.md:286-289`), so branch creation never
runs; (b) "the orchestrator owns the PR" (`SKILL.md:172`, `work-on.md:1176-1178`) —
the child submits `pr_status: shared`, skips PR creation and CI monitoring entirely,
and routes directly to its own terminal `done`; (c) a parent will later update that
shared PR's body (`SKILL.md:172`: "The orchestrator's `pr_finalization` state
updates the shared PR after all children complete"). It also assumes the parent has
already resolved worktree drift *before* dispatch — `worktree_discipline_check` /
`worktree_sync` live in `/execute`'s own template (`execute.md:170-288`), not in
`work-on.md`, and Plan-Backed Child Mode explicitly "skip[s] staleness checks"
(`SKILL.md:168`).

### 7. `/work-on`'s own terminal makes no merge/finalization claim

`work-on.md:1199-1201` — the `done` terminal for the ordinary (non-plan-backed, or
plan-backed-without-`SHARED_BRANCH`) path — reads: *"The workflow is complete. The
PR has been created and CI is passing."* There is no `gh pr merge` anywhere in
`work-on.md`, its phase references, or `phase-6-pr.md` (grepped; the only PR-lifecycle
calls in that file are `gh pr create` and `git push`). `references/phases/
phase-6-pr.md:49-57` lists `pr_creation`'s only evidence outcomes as `created`,
`shared`, `creation_failed_retry`, `creation_failed_escalate` — never a merged state.
This is the literal mechanism behind the exploration context's framing: `/work-on`
run to its own terminal stops at an open, green-CI PR. Note the tension with
`SKILL.md`'s own prose: the skill's `description` frontmatter (`SKILL.md:4-5`, "...
open the PR, watch CI") and `## Output` (`SKILL.md:264`, "A merged PR with passing
CI") both describe the goal as a *merged* PR, but no state in the koto template ever
merges one. This mismatch between the SKILL's stated Output and the koto template's
actual terminal is worth flagging as a fact, not resolving.

### 8. `/execute`'s finalization cascade lives only in `/execute`

`plan_completion` (`execute.md:429-456`, prose at `execute.md:700-729`) runs
`skills/execute/scripts/run-cascade.sh --push {{PLAN_DOC}}` — the PLAN-deletion +
BRIEF/PRD/DESIGN/ROADMAP transition cascade — then `gh pr ready`, entirely inside
`/execute`'s own template. `SKILL.md:183` (work-on) states this directly: "The
plan-level orchestrator — shared branch and draft PR, child spawning, cross-issue
context assembly, escalation, PR finalization, and **the completion cascade** — now
lives in `/execute` ... `/work-on` keeps only Plan-Backed Child Mode." No script or
state under `skills/work-on/` invokes `run-cascade.sh` or `shirabe validate
--lifecycle-chain`.

### 9. Whether `/work-on` can tell it is standalone vs. a child of `/execute`

The pattern-level generic mechanism other shirabe children use for this — the
`parent_orchestration:` sentinel written into the *parent's own* state file before
dispatch (`references/parent-skill-pattern.md:550-555`,
`references/parent-skill-state-schema.md`) — is **explicitly not read by
`/work-on`**. `SKILL.md:246-252` (work-on's own Resume section) says: "Phase 0
detection: if the parent-chain sentinel is present in `wip/scope_<topic>_state.md`
(tactical) or `wip/charter_<topic>_state.md` (strategic), see
`references/fixes/sub-agent-dispatch.md` ... Behavior under direct invocation is
unchanged when the sentinel is absent. (Per R9, `/work-on` does not add a Resume
Logic row -- the sentinel detection is scoped to the seven authoring children.)"
`wip/execute_<topic>_state.md` is not named at all. So the one generic
"am-I-a-child" signal the pattern defines is scoped away from `/work-on` by design.

The only signal `/work-on` actually has is **cooperative, not introspective**: the
caller must explicitly pass the plan-backed variable set (`-- plan-backed` argument
prefix per `SKILL.md:145-152`, or the equivalent koto template vars
`ISSUE_SOURCE`/`PLAN_DOC`/`SHARED_BRANCH`). Anyone — a human, a test harness, or
another skill — who supplies the same shape gets identical behavior; nothing in
`work-on.md` or `SKILL.md` checks who the caller is, what session invoked it, or any
process/session identifier. Furthermore, *within* plan-backed mode `/work-on` cannot
tell **which** kind of plan-backed child it is: `SHARED_BRANCH` set means single-pr
(`/execute`'s shared-branch path); `SHARED_BRANCH` absent with `PLAN_DOC`/
`ISSUE_SOURCE` set is structurally identical whether it came from `/execute`'s
coordinated per-repo dispatch or from a hand-typed `-- plan-backed` invocation with
no `/execute` session behind it at all — there is no field naming "invoked by
/execute" versus "invoked directly with plan-backed args." **This is checked, not
inferred: I grepped `skills/work-on/` and `skills/execute/` for any environment
variable, session-id comparison, or caller-identity check crossing the boundary and
found none; the only cross-boundary signals are the explicit vars/args enumerated
above.**

### 10. The `multi-pr` PLAN mode

`SKILL.md:121-141` implements the routing table entry directly: `/work-on`'s "Plan
Input (Dispatcher)" reads `execution_mode`, re-validates it against the closed set
`{single-pr, multi-pr, coordinated}` (`SKILL.md:128-130`), and for `single-pr` or
`coordinated` "hand[s] off to `/execute`" (`SKILL.md:132-136`) rather than running
anything itself. For `multi-pr`:

> "run in place, one issue at a time. Select the next unblocked issue from the PLAN
> (an issue is blocked while its Dependencies reference open issues) and run it as a
> single issue-backed unit against the repo-persisted PLAN, each landing its own PR.
> There is no shared branch and no cross-issue carry-forward" (`SKILL.md:137-141`).

Concretely, this per-plan logic — "which issue is next" — is agent-level reasoning
in `SKILL.md` prose, not a koto state, and it is **not** the same mechanism
`/execute` uses. `skills/work-on/evals/evals.json:300-307` states this as an
explicit eval expectation: "The dispatcher does NOT initialize a plan-orchestrator
template **and does NOT run `plan-to-tasks.sh`**; that orchestration now lives in
`/execute`." That means `/work-on`'s multi-pr path never touches koto's
`materialize_children`, never sets `PLAN_DOC`/`ISSUE_SOURCE`/`SHARED_BRANCH` on the
resulting koto session, and instead re-enters its own ordinary "Issue-backed mode"
`koto init` (`SKILL.md:193-198`: `--var ISSUE_NUMBER=<N> --var
ARTIFACT_PREFIX=issue_<N>`) once it has picked `<N>`. The resulting per-issue koto
run is therefore indistinguishable, inside the koto template, from a plain
`/work-on <N>` invocation — it carries zero plan-context vars. (`plan-to-tasks.sh`
does have a `process_multi_pr` function, at `skills/plan/scripts/plan-to-tasks.sh:
246-373`, but the dispatch table at `plan-to-tasks.sh:1240-1263` shows it emits
`vars: {ISSUE_SOURCE, ISSUE_NUMBER}` task JSON — this machinery exists in the shared
script but is not what `/work-on`'s multi-pr dispatcher calls per the eval's stated
expectation; it is plausibly used elsewhere, e.g. by `/plan` when it files GitHub
issues under a milestone for a multi-pr PLAN, per
`references/issues-table.md:121-134`.)

So: `/work-on` already contains one piece of genuinely per-plan logic for multi-pr —
picking the next unblocked issue from the PLAN's own dependency graph, evaluated
fresh on every invocation — and it runs once per issue (once per `/work-on`
invocation), never once per plan. There is no loop inside a single `/work-on` run
that drives the whole multi-pr PLAN to completion; each invocation advances exactly
one issue, the same shape as the pre-existing Milestone input mode
(`SKILL.md:34`: "list open issues in the milestone and select the first unblocked
one").

## Implications

- The call boundary is almost entirely **variable-passing through koto**, not a
  narrative Skill-tool call the parent blocks on (except for the coordinated path's
  plain loop, which does still delegate to the same `work-on.md` template per repo).
  Any redesign that "folds `/work-on` into `/execute`" has to reckon with the fact
  that `/execute` doesn't literally invoke a `/work-on` *skill* today so much as
  reuse its koto *template file* as a child-materialization target — the coupling is
  file-path-shaped (`assert-child-template.sh`), not command-shaped.
- The single-pr path's children never create their own PR or run CI monitoring
  (`pr_status: shared` short-circuits straight to `done`) — all the "does this turn
  into a mergeable PR" work for single-pr already lives in `/execute`'s own
  `pr_finalization`/`plan_completion`/`ci_monitor` states, entirely outside
  `work-on.md`. The coordinated path's children, by contrast, *do* run `work-on.md`'s
  own `pr_creation`/`ci_monitor` to a green, open, unmerged PR per repo, and nothing
  in the material read here shows what actually merges those per-repo PRs afterward
  (see Open Questions).
- `/work-on`'s multi-pr dispatcher already demonstrates the shape "per-plan logic
  that runs once per issue, at the top of `/work-on` itself, using no shared koto
  child machinery." That is direct, in-repo precedent for what "per-issue cascade
  instead of per-plan cascade" would concretely look like if finishing logic were
  migrated into `/work-on` without also building a plan-level driver inside it.
- The fact that `/work-on` cannot self-identify as an `/execute` child (§9) means any
  future "run the cascade only when I'm the top-level caller, not when I'm a
  child" branch cannot be built on introspection — it would need `/execute` to keep
  passing an explicit signal (as it already does for `SHARED_BRANCH`/`pr_status:
  shared`), the same cooperative-flag pattern used today.

## Surprises

- `SKILL.md`'s own frontmatter `description` and `## Output` describe `/work-on`'s
  goal as producing a *merged* PR (`SKILL.md:4-5`, `SKILL.md:264`), but the actual
  koto template never merges anything — `done` is reached at "PR created, CI green"
  (`work-on.md:1199-1201`), and there is no `gh pr merge` call anywhere under
  `skills/work-on/`.
- `/work-on` and `/execute` both lack a `team.yaml` (checked: `skills/execute/
  team.yaml` and `skills/work-on/team.yaml` do not exist, while the seven authoring
  skills — `brief`, `prd`, `design`, `plan`, `roadmap`, `strategy`, `vision` — all
  have one), even though `parent-skill-pattern.md`'s Pre-Dispatch State item 4 names
  the child-side `team.yaml` marker as something the parent "SHALL have" confirmed
  before dispatch. Not resolved here whether this is a documented exception for the
  "Materialized `/work-on` runs" binding or a gap.
- `/work-on`'s multi-pr dispatcher is explicitly forbidden (by its own eval) from
  running `plan-to-tasks.sh`, even though that script has a dedicated
  `process_multi_pr` function that looks purpose-built for exactly this. The
  function apparently serves a different caller (issue filing), not `/work-on`'s
  runtime dispatch.
- `references/parent-skill-pattern.md` treats `/execute`'s koto-materialization
  dispatch as a first-class, equally-weighted second binding of the same Layer-1
  "dispatch mechanism" element the inline Skill-tool call uses for `/scope`/
  `/charter` — the pattern was evidently amended specifically to accommodate
  `/execute` rather than `/execute` being a bolt-on exception.

## Open Questions

- Does koto's `materialize_children` runtime actually construct a `/work-on --
  plan-backed ...` argument string when it spawns a child agent (routing through
  `SKILL.md`'s own frontmatter/preflight/Mode-Detection), or does it seed the child
  koto session's `entry` state directly with evidence, bypassing `SKILL.md` entirely?
  Not determinable from this repo — koto's materialization runtime is external.
- For the **coordinated** path, each per-repo child runs `work-on.md` to its own
  `done` (PR created, CI green) with no merge. What actually merges those per-repo
  PRs before the coordination PR's merge-order DAG can be satisfied? Nothing read in
  `skills/execute/` performs a `gh pr merge` on a per-repo child PR either — this
  looks like it's left to a human, but that isn't stated explicitly anywhere I read.
- Is the `-- plan-backed` argument-prefix form actually exercised anywhere (a real
  Skill-tool call), or is it effectively dead prose now that materialization goes
  through the koto template path directly? No caller of that literal argument shape
  was found outside `SKILL.md`'s own description of itself.

## Summary
`/execute` never calls a `/work-on` slash command directly; it points koto's `materialize_children` at `work-on.md`'s template file (single-pr, one koto child-session per issue, `SHARED_BRANCH` injected) or, for coordinated, loops a plain `gh`-driven dispatch to the same template per repo — and in both cases `/work-on`'s own terminal state stops at "PR created, CI green," with all merging and the PLAN/BRIEF/PRD/DESIGN finalization cascade living only in `/execute`. `/work-on` has no way to introspect that it is an `/execute` child — the pattern's generic parent-sentinel mechanism is explicitly scoped away from it, and the only signal it has is whatever variables (`PLAN_DOC`, `ISSUE_SOURCE`, `SHARED_BRANCH`) a cooperative caller chooses to pass, which is exactly the shape multi-pr's own already-existing, once-per-issue "pick the next unblocked issue" logic in `/work-on` demonstrates. The biggest open question is what mechanism, if any, merges a coordinated child's per-repo PR, since neither `/work-on` nor `/execute` appears to do it.
