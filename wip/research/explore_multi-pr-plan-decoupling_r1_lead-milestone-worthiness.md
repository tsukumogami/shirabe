# Lead: Is "milestone-worthy" a judgment separable from "needs multiple PRs", and how are milestones actually used today across ROADMAP versus PLAN?

## Findings

### What Phase 2 (milestone derivation) actually does

`skills/plan/references/phases/phase-2-milestone.md` runs unconditionally as the
second phase of every `/plan` invocation, for every input type (design, prd,
roadmap, topic) -- and, critically, it runs **before** execution mode is even
decided. The workflow order in `skills/plan/SKILL.md`'s phase table is:

```
1. Analysis -> 2. Milestone -> 3. Decomposition -> 3.5a Value Confirmation
-> 3.6 Execution Mode Selection -> 4. Generation -> ... -> 7. Creation
```

Phase 2 states its governing rule as an unconditional invariant, not a
judgment call:

> "Each source document (or topic) maps to exactly one GitHub milestone."
> "One source document (or topic) = one GitHub milestone"
> "If work needs multiple milestones, create separate documents via
> `needs-design` issues"

There is no step in Phase 2 that asks "is this worthy of a milestone." The
only judgment-shaped step is **2.3 Scope Check**, and it is explicitly
non-gating: "If > 15 issues: Consider whether the document should be split
... This is guidance, not a hard rule." It never says "skip the milestone" --
splitting produces *more* milestones (one per resulting document), never
zero.

A milestone is **never skipped** at the Phase 2 level. What happens instead
is that the Phase 2 artifact (`wip/plan_<topic>_milestones.md`) is written
for every plan, then either materializes into a real GitHub milestone (Phase
7, multi-pr) or is discarded unused (Phase 7 cleanup, single-pr) --
`skills/plan/references/phases/phase-7-creation.md` states this directly:

> "single-pr Mode ... No GitHub milestone or issues are created in
> single-pr mode."
> "multi-pr Mode ... Read `wip/plan_<topic>_milestones.md` for the milestone
> name and description, then run the batch script."

So today, milestone creation is **100% gated on `execution_mode`**, decided
at step 3.6, which happens *after* Phase 2 already derived a milestone title
and description nobody asked whether was warranted. The gate is mechanical:
multi-pr always gets exactly one milestone (1:1 invariant); single-pr never
gets one, regardless of how substantial the single-PR plan is.

### Does ROADMAP create milestones, or does each PLAN under a roadmap?

Both, at two different levels, and they're easy to conflate:

1. **The ROADMAP's own milestone**, for its *planning* issues (one issue per
   feature, each tracking "needs-prd"/"needs-design"/etc., not code). This is
   created by `shirabe roadmap populate <path> --issues --milestone "<Milestone
   Name>" ...` (`skills/roadmap/SKILL.md` lines 417-421), invoked via
   `/roadmap populate <path> --issues` after the roadmap is approved. This is
   a *roadmap-level* milestone whose issues are placeholders for downstream
   artifact creation, not implementation work.

2. **A per-feature PLAN's own milestone**, created later when a roadmap
   feature has gone through `/brief` -> `/prd` -> `/design` -> `/plan`, and
   that `/plan` run (input_type: roadmap, `--upstream <roadmap-path>`) itself
   produces a `PLAN-<topic>.md` that -- if multi-pr -- gets its *own* separate
   GitHub milestone via the ordinary Phase 2/Phase 7 mechanism. Confirmed in
   `skills/plan/SKILL.md`: "roadmap input" in multi-pr mode still says
   "GitHub milestone (1:1 with the plan)."

So a single ROADMAP can spawn N+1 milestones over its life: one roadmap-level
milestone for the N planning issues, plus up to N more milestones as each
feature's own `/plan` run resolves multi-pr. `/plan` on a roadmap does NOT
feed into or reuse the roadmap's milestone -- it's a fully independent 1:1
document-to-milestone invariant applied again at the PLAN level.

### What does a milestone provide functionally in shirabe today?

Grepped `skills/execute/SKILL.md` and `skills/inflight/SKILL.md` for
`milestone` (case-insensitive): **zero hits in either file's actual logic**
(only test fixtures under `skills/execute/evals/fixtures/plans/*.md` mention
milestones, as PLAN frontmatter values, not as something the execute/inflight
logic reads or branches on). Grepped `skills/roadmap/references/roadmap-format.md`
similarly: no functional milestone reads.

The only place a milestone is functionally *consumed* (not just created) is
`skills/work-on/SKILL.md`:

> "Milestone inputs: `M3`, `M#3`, milestone URL, or `"Milestone Name"` --
> list open issues in the milestone and select the first unblocked one ...
> If multiple unblocked issues exist, pick the one with lowest number."

That's the entire functional contract: **a milestone is an issue-selection
filter for `/work-on`** when a human points `/work-on` at a milestone
instead of a specific issue. It provides no progress percentage, no
completion-cascade trigger, and no grouping semantics beyond "issues tagged
with this milestone." GitHub's own milestone UI incidentally shows an
open/closed issue count, but nothing in shirabe's own skills reads or acts
on that count -- the completion cascade (in `/plan`, `/execute`,
`/work-on`) is driven entirely by PLAN doc state (`status`, the
Implementation Issues table, the Dependency Graph) and the lifecycle chain
check (`shirabe validate --lifecycle-chain`), never by milestone open/closed
state.

`phase-2-milestone.md` also points to a "github-milestone" skill for "the
full milestone convention (title rules, description format, conformance
checklist)" at `../../../github-milestone/SKILL.md`. That path does not
resolve inside this worktree (`skills/github-milestone/` does not exist
under `skills/plan/`) -- it is `tsukumogami:github-milestone`, a skill that
lives in a different (org-level, tsukumogami) plugin layer, not in shirabe
itself. Per the exploration's visibility scope, I did not chase this
outside the worktree; noting only that shirabe's own milestone *mechanics*
are what's documented above, and the deeper conformance rules live
elsewhere.

### If a multi-pr PLAN created issues but NO milestone, what specifically breaks?

Based on the above, concretely:

- **`/work-on M<N>` / `/work-on "Milestone Name"` stops working** as an entry
  point -- there's nothing to resolve issues against. A human would have to
  reference issues individually or by the PLAN doc path instead.
- **Nothing in `/plan`, `/execute`, or `/inflight` breaks**, because none of
  them read milestone state functionally. The completion cascade, the
  PLAN's own Implementation Issues table, and the Dependency Graph are the
  actual mechanisms driving sequencing and completion; the milestone is not
  in that chain at all.
- **Traceability/organization on GitHub's issue list view degrades** --
  issues would be discoverable only by label/search
  (`gh issue list --search "Design: <path>"`), which Phase 1's resume logic
  already relies on as the primary lookup mechanism anyway (not the
  milestone).
- The 1:1 invariant itself is never violated by omission today because
  Phase 7 always creates the milestone in multi-pr mode as an unconditional
  step of issue creation (`create-issues-batch.sh --milestone "<name>"` is
  a required flag in every documented invocation) -- there's no code path in
  the current skill that creates multi-pr issues without a milestone.

### Is there an existing notion of "significance" or "user-visible outcome" to ground a milestone-worthiness judgment?

The closest existing construct is **not milestone-scoped at all** -- it's the
**value-confirmation guard (Phase 3.5a)**, which is entirely about execution
mode, not milestones:

> "For each unit, evaluate the question 'if this unit landed alone, would a
> reader observe value, or only a building block someone has to wait on?'"

This is precisely a "user-visible outcome" judgment, but it's wired to decide
single-pr vs multi-pr (step 3.6 consumes its output), not whether a milestone
should exist. Since milestone creation is a pure function of execution mode
in the current implementation, the value-confirmation guard's judgment
*is* the only significance judgment in the pipeline, and it currently
double-serves as the (uninstantiated) milestone-worthiness judgment by
proxy -- there's no independent question asked.

`roadmap-format.md` and the roadmap SKILL don't add a separate "is this
milestone-worthy" concept either: a roadmap's Features section states each
feature with a description and a `needs_label`, but nothing in the format
spec asks whether a feature deserves its own milestone (it always gets one
issue, and the whole roadmap gets one milestone if issues are filed at all).
VISION/STRATEGY artifacts (not read in depth for this lead, out of scope) are
several altitude-levels removed from milestone mechanics and were not
searched further per the lead's boundaries.

## Implications

- Any new "milestone-worthy" gate the author wants to introduce would be a
  **genuinely new decision point** -- it does not already exist under another
  name inside `/plan`. It would have to be inserted either into Phase 2 (to
  decide whether to derive/materialize a milestone at all) or into Phase 7
  (to decide, independent of `execution_mode`, whether the milestone that
  Phase 2 already derived gets created).
- Because Phase 2 runs *before* execution mode is decided (step 3.6), a
  milestone-worthiness judgment that wants to reuse Phase 2's derived title
  would need to either move later (after 3.6) or be re-evaluated once
  execution mode is known -- currently Phase 2's output is used unconditionally
  once multi-pr is chosen.
- If milestone-worthiness were introduced as independent from execution mode,
  the two live spaces to reconcile are: (a) a multi-pr plan that is NOT
  milestone-worthy (issues created, but filed under no milestone, or under
  labels only) -- this breaks `/work-on M<N>` addressing for that plan, which
  is the one real functional consumer identified above; (b) the roadmap
  level's own milestone (per-feature planning issues) is a separate 1:1
  document rule and is unaffected by whatever the PLAN-level rule becomes.

## Surprises

- Milestone *derivation* (title/description) happens unconditionally and
  early (Phase 2), decoupled in the skill's own control flow from milestone
  *creation*, which is late (Phase 7) and execution-mode-gated. The
  separation already exists mechanically for a different reason (resumability
  / phase ordering), which means "decouple milestone-worthiness from
  multi-PR-ness" is not as large a structural change as it might first
  appear -- the seam is already there, just not exposed as a decision.
- Milestones carry almost no functional weight in shirabe today beyond being
  a `/work-on` issue-selection filter. No progress percentage, no completion
  trigger, no cascade dependency. This means the "cost" of getting
  milestone-worthiness wrong (in either direction) is lower than intuition
  might suggest -- it degrades one entry-point ergonomic, not correctness.
- A single ROADMAP can already spawn many independent milestones over its
  life (one roadmap-level + one per multi-pr feature-PLAN), so "1:1
  document-to-milestone" is already a per-artifact-not-per-initiative rule,
  which weakens any assumption that milestones map to "a project milestone"
  in the colloquial/strategic sense the author's framing implies.

## Open Questions

- Does `tsukumogami:github-milestone` (outside this worktree, referenced by
  `phase-2-milestone.md`'s relative path) define a broader "significance"
  convention for milestone titles/descriptions that shirabe's `/plan` doesn't
  surface? Not checked -- out of scope per visibility/worktree boundary.
- If milestone-worthiness became independent, what happens to issues from a
  multi-pr plan judged NOT milestone-worthy -- do they get a milestone-less
  multi-pr mode, or does the judgment instead just change Phase 2's
  materialization step while multi-pr issue creation still requires *some*
  grouping mechanism (label instead of milestone)? This is a design question
  the author's downstream work will need to answer; nothing in the current
  code anticipates a multi-pr-without-milestone state.
- VISION/STRATEGY artifacts weren't read for "significant/user-visible
  outcome" language given the lead's scope boundaries (workspace-wide file
  search was intentionally limited to `skills/plan`, `skills/roadmap`,
  `skills/execute`, `skills/inflight`) -- worth a follow-up lead if the
  author wants strategic-altitude precedent for "significance."

## Summary

Milestone creation in shirabe today is a pure function of `execution_mode`
(multi-pr always gets exactly one milestone per the 1:1 doc-invariant;
single-pr never gets one) -- there is no separate milestone-worthiness
judgment anywhere in `/plan`, `/roadmap`, `/execute`, or `/inflight`; the
closest analog, Phase 3.5a's value-confirmation guard, already asks the
"is this a real user-visible increment" question but wires its answer only
to single-pr-vs-multi-pr, not to milestone materialization. The counter-
hypothesis holds in the current implementation: milestone-worthiness has
fully collapsed into multi-PR-ness, and the biggest open question is what a
"multi-pr plan without a milestone" state would even mean functionally,
since the milestone's only live consumer is `/work-on`'s milestone-based
issue selection.
