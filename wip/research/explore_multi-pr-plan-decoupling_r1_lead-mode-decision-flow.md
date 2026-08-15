# Lead: Where is the single-pr / multi-pr / coordinated PLAN mode decision actually made today, and what inputs feed it?

## Findings

### 1. Control flow that selects the mode (skills/plan/)

The decision is a two-step procedure inside a single phase file,
`skills/plan/references/phases/phase-3-decomposition.md`, run *after* issue
decomposition and *before* Phase 4 (agent generation):

- **Step 3.5a — Value Confirmation** (lines 401-487). For every "unit" (each
  feature for a roadmap; each PR-shaped unit for a plan the author intends to
  split; the whole plan as one unit otherwise), the guard asks "if this unit
  landed alone, would a reader observe value, or only a building block someone
  has to wait on?" and buckets each into Pass / Ambiguous / Fail. Interactive
  mode routes non-passing units to `AskUserQuestion`; `--auto` mode records a
  `confirmed`/`assumed` decision block per
  `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` and never hard-stops.
  This step does **not** choose the mode — it only validates the units the mode
  decision will act on.

- **Step 3.6 — Execution Mode Selection** (lines 490-554). This is where the
  mode is actually chosen, via an explicit procedure (numbered steps in the
  file):
  1. Check the surfaced rule on `skills/plan/SKILL.md` ("Execution Mode
     Decision" section).
  2. Read the 3.5a guard output.
  3. Recommend a mode using a 4-way branch: roadmap input -> multi-pr; plan
     input with a named hard constraint -> multi-pr; plan input where each PR
     is independently useful -> multi-pr; plan input otherwise -> single-pr.
  4. **Present the recommendation to the user via `AskUserQuestion`** in
     interactive mode (verbatim template at phase-3-decomposition.md:526-539).
  5. Under `--auto`, follow the recommendation and record `confirmed` (clear
     rationale) or `assumed` at high review priority (multi-pr chosen without a
     hard constraint or clear value rationale).
  6. Record `execution_mode: single-pr` (or `multi-pr`) into the decomposition
     artifact's YAML frontmatter (`wip/plan_<topic>_decomposition.md`).

Note: `coordinated` is never a candidate output of this procedure. Step 3.6's
recommendation branch only ever emits `single-pr` or `multi-pr`. I found no
code path in `/plan` that sets `execution_mode: coordinated` — see Surprises.

### 2. The "surfaced rule" verbatim (skills/plan/SKILL.md:137-197)

This is the authoritative statement Phase 3.6 defers to. Quoted verbatim:

> **Default: single-pr.** Reach for one PR. Anchored on principle P1 (usable
> value is the unit of work) in
> `${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` -- every PR
> delivers observable value on its own, and one PR is the lowest-ceremony
> shape that clears that bar.
>
> **Escape to multi-pr only when a named condition forces it:**
>
> 1. **A hard constraint forces multiple PRs.** Cross-repo landing order; a
>    workflow that must reach main before it can be invoked; a merge gate
>    between steps. The constraint must be named in the PLAN doc.
> 2. **Each PR is independently useful.** The split delivers genuine
>    incremental value: every PR-shaped unit lands observable value on its
>    own, not just a building block someone has to wait on. "Could be
>    separate PRs" is not the test; "each PR is independently useful to a
>    reader" is.
>
> A roadmap input is always multi-pr -- not because the input is a roadmap,
> but because each feature is a cohesive deliverable that lands observable
> incremental value on its own (P1 again). The mechanism "the input is a
> roadmap" is not the reason; the value the feature delivers is.

And on `coordinated` (SKILL.md:174-196), quoted verbatim:

> `coordinated` is the third execution mode: the multi-repo generalization of
> multi-pr. Reach for it when the effort spans more than one repository and
> the per-repo PRs must land in a coordinated order with a coordination PR
> that merges last. It is always multi-PR and shares multi-pr's section shape
> (Implementation Issues table + Dependency Graph); it adds per-issue `repo`
> and `pr_group` tags plus a two-node merge-order DAG.

This confirms `coordinated` is framed as a strict specialization of multi-pr
("the multi-repo generalization"), triggered by a structural fact (effort
spans >1 repo) rather than the "should" preference logic in step 3.6. I could
not find the actual selection step that sets `coordinated` vs plain `multi-pr`
in the phase files — the SKILL.md prose describes when to "reach for it" but
Phase 3.6's numbered procedure never branches to it. This looks like a gap:
either the coordinated selection happens implicitly (author names cross-repo
constraint -> multi-pr -> then repo-count check upgrades it to coordinated
somewhere in Phase 4/7) or it's currently undocumented in the phase
procedure. Worth flagging to the author.

### 3. Mode recorded in PLAN frontmatter

Yes. Confirmed in three places:

- `skills/plan/references/plan-format.md:27,34,40-43` — `execution_mode` is a
  **required** frontmatter field, documented as one of `single-pr` or
  `multi-pr` only (this file does not mention `coordinated` in its enum
  description at line 40, though the example set elsewhere does — see
  Surprises).
- `skills/plan/references/quality/plan-doc-structure.md:65` — `execution_mode:
  single-pr  # single-pr | multi-pr | coordinated` (three-way enum, matches
  SKILL.md).
- `skills/plan/SKILL.md:54-56` — "Frontmatter includes `schema: plan/v1`,
  `status`, `execution_mode` (single-pr, multi-pr, or coordinated),
  `milestone`, and `issue_count`."

So the field exists, is required, and is a closed three-value enum
(`single-pr`, `multi-pr`, `coordinated`) per the two more-authoritative
sources (SKILL.md and plan-doc-structure.md); plan-format.md's frontmatter
section appears to be the stale two-value description (see Surprises).

### 4. How skills/execute/ reads and branches on the mode

`skills/execute/SKILL.md:34-48`:

> 1. **Path to a PLAN doc** ... — read the PLAN's `execution_mode`:
>    - `single-pr` — run the single-pr execution path below.
>    - `coordinated` — run the coordinated execution path below.
>    - `multi-pr` — out of scope for `/execute`; multi-pr plans run one issue
>      at a time through `/work-on` against the repo-persisted PLAN. Direct
>      the user to `/work-on`.
>
> The PLAN's `execution_mode` is an enum-typed input surface; re-validate it
> against `{single-pr, coordinated, multi-pr}` before it selects an execution
> path or is interpolated into any branch name or emitted shell ... `/execute`
> is the first untrusted-enum consumer; the `/work-on` dispatcher is the
> second, and re-validates the same enum independently.

So `/execute` owns `single-pr` and `coordinated` (plan-level execution with a
shared home PR / coordination PR); `multi-pr` is explicitly out of scope for
`/execute` and is redirected to `/work-on`.

### 5. How skills/work-on/ reads and branches on the mode

`skills/work-on/SKILL.md:106-127` ("Plan Input (Dispatcher)"):

> When `$ARGUMENTS` is a path to a PLAN.md file, `/work-on` acts as a thin
> dispatcher on the PLAN's `execution_mode`. `/work-on` no longer orchestrates
> a whole plan: plan-level execution (single-pr and coordinated) is owned by
> `/execute`, which delegates each single issue back to `/work-on`'s
> Plan-Backed Child Mode below.
>
> Read `execution_mode` from the PLAN frontmatter and **re-validate it
> against the closed set `{single-pr, multi-pr, coordinated}` before using it
> in any path or branch interpolation** (an out-of-set value halts with a
> clear error). Then route:
>
> - **`single-pr` or `coordinated`** — hand off to `/execute`. `/work-on`
>   does not run these directly; direct the caller to invoke `/execute
>   <PLAN>` ... When `/execute` is already driving the plan, it spawns
>   `/work-on` per issue via Plan-Backed Child Mode.
> - **`multi-pr`** — run in place, one issue at a time. Select the next
>   unblocked issue from the PLAN ... and run it as a single issue-backed
>   unit against the repo-persisted PLAN, each landing its own PR. There is
>   no shared branch and no cross-issue carry-forward — multi-pr issues are
>   independent, per the DESIGN's ephemeral-home model.

So the two skills are exact mirror images: `/execute` handles `{single-pr,
coordinated}` and redirects `multi-pr` to `/work-on`; `/work-on` handles
`{multi-pr}` directly (plus per-issue child mode for the other two when
dispatched by `/execute`) and redirects `{single-pr, coordinated}` to
`/execute`. Both independently re-validate the enum against the closed set —
described explicitly as defense against an "untrusted-enum" (`/execute` is
first consumer, `/work-on` dispatcher is second).

### 6. Is the decision presented to the user, inferred by the agent, or forced by a rule?

All three, layered, by scenario:

- **Forced by rule (no user involvement, no LLM judgment):** roadmap input
  always resolves to multi-pr (phase-3-decomposition.md:301-307,
  515-516) — "not because the input is a roadmap, but because each feature is
  a cohesive deliverable that lands observable incremental value on its own."
  This is stated as a hard rule keyed on structural input type, dressed as a
  value-principle application.
- **Inferred by agent judgment, then presented to the user (interactive
  mode default):** for design/prd/topic input, the agent applies the 4-branch
  recommendation logic (hard constraint / independently-useful / default) and
  then must present it via `AskUserQuestion` with the exact template at
  phase-3-decomposition.md:526-539, ending "Use <recommended mode>, or
  override?" — the user has final say.
- **Agent-decided with recorded rationale, no user gate, under `--auto`:**
  the recommendation is followed automatically; a `confirmed` or `assumed`
  (high-review-priority) decision block is written instead of blocking.

So in the default (interactive) run, the decision is *agent-inferred,
user-confirmed*. Under `--auto` it's *agent-inferred, no gate, flagged for
later human review* when the rationale isn't airtight.

### 7. Where "coordinated" fits and how it's distinguished

Per SKILL.md:174-196 (quoted above) and plan-doc-structure.md:124-181,
`coordinated` is documented as structurally triggered — "the effort spans
more than one repository and the per-repo PRs must land in a coordinated
order with a coordination PR that merges last" — not value-triggered like the
single-pr/multi-pr split. It shares multi-pr's PLAN section shape
(Implementation Issues table + Dependency Graph) but adds:
- per-issue `repo` + `pr_group` annotation rows (`^_Repo: owner/repo | Group:
  <pr-group>_`, default `Group: default`, one PR per repo),
- a two-node merge-order DAG,
- `scripts/plan-to-tasks.sh` collapses the issue-level graph into a
  `(repo, pr_group)`-level PR DAG with non-PR gate nodes, checks acyclicity
  post-contraction, and either splits a repo at the seam to resolve a cycle or
  refuses if no acyclic order exists.

Downstream, `coordinated` is functionally treated as a peer of `single-pr`
(both owned by `/execute`, both use the durable-home-PR / cross-branch resume
model), while `multi-pr` is functionally a peer of neither — it's the "run
each issue independently, no shared branch" mode owned by `/work-on`. That is:
the *execution-mechanics* grouping is `{single-pr, coordinated}` vs
`{multi-pr}`, even though the *conceptual* grouping the author is
describing is `{single-pr}` vs `{multi-pr, coordinated}` (multi-repo being a
variant of "can't be one PR"). This is a structural mismatch worth surfacing:
see Implications.

## Implications

1. **The "can" and "should" gates are genuinely fused in step 3.6, exactly as
   the lead described.** The hard-constraint check (a "can" fact — cross-repo
   landing order, a merge gate, a workflow needing main) and the
   independently-useful check (a "should" preference — is fewer-PRs vs
   smaller-PRs preferred) are evaluated by the same procedure, in the same
   `AskUserQuestion` prompt, producing one flag. There's no separate repo-level
   configuration read anywhere in Phase 3 — the "should" question is decided
   fresh, per-plan, by agent judgment (or the user's override) every time,
   with no persistent preference to consult. A repo wanting "always fewest
   PRs" or "always small increments" has no lever to pull today except
   overriding the `AskUserQuestion` prompt every single run, or always passing
   an as-yet-nonexistent flag.

2. **The tracking mechanism (GitHub issues/milestone) is hardcoded to the
   mode, not bound to a separate preference**, exactly as described. Look at
   plan-format.md:40-43 and SKILL.md's Output section
   (phase docs at SKILL.md:507-530): `multi-pr` *is* "GitHub milestone +
   issues created"; `single-pr` *is* "no GitHub artifacts, self-contained PLAN
   doc." There is no PLAN or repo-level field that lets an author choose "land
   this as one PR but still track it with GitHub issues" or "split into
   multiple PRs but skip GitHub issue tracking, use the PLAN's own Issue
   Outlines table instead." The tracking mechanism is a hardcoded side effect
   of the mode value, not an independent axis.

3. **The "can" gate is not actually "near-deterministic" today** in the sense
   the framing hopes for. The hard-constraint branch (cross-repo, merge gate,
   workflow-must-reach-main) is closer to deterministic — these are facts
   about the design, nameable and checkable. But the "each PR is independently
   useful" branch is squarely agent judgment, phrased as a discrimination test
   ("could be separate PRs" is not the test; "each PR is independently useful
   to a reader" is) with no algorithmic criterion — it is evaluated by the
   value-confirmation guard (3.5a), which is itself explicitly a judgment call
   ("Ambiguous... two readers could reasonably disagree").

4. **`coordinated` doesn't fit cleanly into a single-axis "should" model.**
   It is currently triggered by a structural fact (repo count) that overlaps
   with the "can" gate (cross-repo landing order is literally hard-constraint
   reason #1 in the surfaced rule), but it's also documented as a distinct
   mode with its own doc-shape and DAG-contraction machinery. If the redesign
   separates "can it land in one PR" from "how is it tracked," `coordinated`'s
   repo-spanning trigger probably belongs entirely inside the "can" gate
   (multi-repo effort inherently can't be one PR), while its "coordination PR
   merges last" tracking behavior is a tracking-mechanism variant layered on
   top of "can't be single-pr" — suggesting coordinated may collapse from "a
   third mode" into "multi-pr's can-gate outcome when repo count > 1" plus
   "the coordination-PR tracking variant," which maps well onto the proposed
   decoupling.

## Surprises

- **`plan-format.md` documents a stale two-value enum.** Line 40 says
  "**execution_mode** -- one of `single-pr` or `multi-pr`" with no mention of
  `coordinated`, while `plan-doc-structure.md:65` and `SKILL.md:54-56` both
  document the three-value enum including `coordinated`, and `/execute` and
  `/work-on` both explicitly re-validate against
  `{single-pr, multi-pr, coordinated}`. `plan-format.md` looks like it predates
  the addition of `coordinated` mode and was not updated. This is a
  documentation drift the author should know about independent of the
  decoupling work.

- **No explicit Phase-3.6 branch ever selects `coordinated`.** The
  step-by-step "Recommend a mode" procedure at
  phase-3-decomposition.md:514-522 only ever recommends `single-pr` or
  `multi-pr`. SKILL.md's "Coordinated Mode" section describes when to reach
  for it but I found no wiring from Phase 3's decision procedure to actually
  set `execution_mode: coordinated` in the decomposition artifact. Either
  this is an undocumented manual override (the author picks it directly,
  outside the AskUserQuestion flow) or a real gap in the phase file. Flagging
  as unresolved rather than assuming an answer.

- **`/execute` and `/work-on` groupings cut across the mode set differently
  than SKILL.md's mode taxonomy does.** SKILL.md presents three peer modes;
  the actual runtime ownership split is `{single-pr, coordinated}` (owned by
  `/execute`, durable-home-PR model) vs `{multi-pr}` (owned by `/work-on`,
  independent-PR-per-issue, no shared branch). This means "multi-pr" and
  "coordinated" — despite coordinated being pitched as "the multi-repo
  generalization of multi-pr" — currently have almost nothing in common
  mechanically: coordinated behaves like single-pr's execution machinery
  (shared home artifact, cross-branch resume, exit-path bindings) scaled to
  multiple repos, while multi-pr behaves like N independent single-issue runs
  with no shared state at all.

## Open Questions

1. Where (if anywhere) does `execution_mode: coordinated` actually get set
   during `/plan`'s run? Is it a manual/flag-driven override not documented in
   Phase 3, or a genuine gap in phase-3-decomposition.md's procedure?
2. Is there a repo-level or workspace-level config surface anywhere in
   shirabe (CLAUDE.md headers, a `.claude/shirabe-extensions/plan.local.md`
   override, or similar) that could carry a "should" preference (fewest-PRs
   vs smallest-increments) today, even if `/plan`'s Phase 3.6 doesn't consult
   it? (`skills/plan/SKILL.md:13-14` references
   `@.claude/shirabe-extensions/plan.md` / `plan.local.md` — worth a follow-up
   read to see if repo-level override hooks already exist there for other
   decisions and could be reused.)
3. If tracking mechanism becomes its own axis, does the `Issue Outlines`
   vs `Implementation Issues` table shape (currently strictly single-pr vs
   multi-pr, per plan-format.md:109,139-145) need to become
   independently selectable too, or does it stay coupled to "can it land in
   one PR"?
4. How does `plan-to-tasks.sh`'s DAG-contraction logic (coordinated-only
   today) generalize if "coordinated" stops being a distinct mode and
   becomes "multi-pr with repo-spanning constraint + coordination-PR
   tracking"?

## Summary

The mode decision lives entirely in `skills/plan/references/phases/phase-3-decomposition.md` step 3.6, which fuses a near-deterministic "can" check (named hard constraints: cross-repo order, merge gates, must-reach-main) with a judgment-based "should" check ("each PR independently useful to a reader") into one `AskUserQuestion` recommendation that's recorded as `execution_mode` in PLAN frontmatter and then re-validated independently by both `/execute` (owns `single-pr`+`coordinated`) and `/work-on` (owns `multi-pr`) as a closed three-value enum — and the tracking mechanism (GitHub issues/milestone vs self-contained PLAN doc) is a hardcoded side effect of that same flag rather than an independent choice, confirming the fusion the author described. The biggest open question is where (or whether) `execution_mode: coordinated` is actually ever selected by the documented Phase 3.6 procedure — I found no wiring path to it, only a description of when an author should "reach for it," plus a related documentation-drift finding that `plan-format.md`'s frontmatter reference still describes `execution_mode` as a stale two-value enum.
