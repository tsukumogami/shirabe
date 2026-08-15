# Lead: Can the "can this plan fit in a single PR" gate be made near-deterministic from a DESIGN's decomposition, and what would the rule be?

## Findings

### What a PLAN actually has at decision time

Phase 1 (`skills/plan/references/phases/phase-1-analysis.md`) extracts, before any
decomposition exists: a scope summary, a flat list of components/features, the
design's own Implementation Phases text, success metrics, and an `## External
Dependencies` list (other designs, existing code/features, required skills or
commands) -- prose, not structured data.

Phase 3 (`phase-3-decomposition.md`) is where issue-shaped structure first
appears: one outline per issue (Type, Complexity, Goal, Section, Milestone,
Dependencies as `Issue N` references), a decomposition-strategy label
(walking-skeleton vs horizontal), and, critically, the **value-confirmation
guard** (step 3.5a) which classifies every PR-shaped unit as pass / ambiguous /
fail against "would a reader observe value if this landed alone." Execution
mode itself is finalized in step 3.6, reading that guard's output plus a
named-hard-constraint check.

Phase 5 (`phase-5-dependencies.md`) adds the dependency graph proper: blocked-by
edges, parallelization opportunities, critical-path length, and a
circular-dependency check. Nothing here encodes *why* an edge exists --
`Blocked by` records ordering only, not whether the blocker is "code must exist
first" (same-PR-safe) or "artifact must be released/live first"
(same-PR-unsafe). That distinction is invisible at this layer.

`plan-format.md` shows the terminal PLAN doc structure: `execution_mode` is one
of `single-pr | multi-pr | coordinated` (frontmatter), each issue carries a
`Complexity` value (`trivial|simple|testable|complex` -- an *authoring-rigor*
axis, not a PR-boundary axis), and coordinated-mode issues additionally carry a
`Repo`/`Group` annotation row and, when needed, a `Gate` annotation row (a
named non-PR condition an issue depends on, e.g. a package publish).

### What genuinely FORCES multiple PRs (not preference)

`skills/plan/SKILL.md` (lines 137-221) and `references/workflow-principles.md`
(P1) name exactly two escape conditions from the single-pr default, and they
are not symmetric:

1. **A hard constraint forces it** -- cross-repo landing order, a workflow that
   must reach main before it can be invoked, a merge gate between steps. This
   is the "can't" case.
2. **Each PR is independently useful** -- a value judgment, not a mechanical
   impossibility. This is closer to "won't fit by choice" than "can't fit."

Only condition 1 belongs to the lead's "can" question; condition 2 is
value/review-ergonomics-adjacent and arguably belongs with the "should" gate
the lead scoped out.

`references/coordination-strategy.md` is where the cross-repo case is fully
specified, and it turns out cross-repo is not just a multi-pr trigger -- it is
a **third, distinct `execution_mode`** (`coordinated`), the "multi-repo
generalization of multi-pr." It is always multi-PR and adds a coordination PR
that merges last, per-repo `pr_group` tags, and a two-node (PR nodes + gate
nodes) merge-order DAG. The gate-node concept is the direct evidence for the
"released artifact of a prior issue" pattern the lead asked about: the doc's
own example is `Gate: publish-lib | After: pr-lib-default | Before:
pr-app-default` -- a named, live-verifiable condition (a package publish) that
is not itself a PR and that downstream work cannot proceed past until it
verifies live. `coordination-strategy.md` also states atomicity requirements
(two repos that must merge simultaneously) are **refused at planning time**,
never silently planned -- so shirabe already treats "can this land as fewer
PRs" as a decidable, refuse-if-impossible question in the cross-repo case
specifically.

I found no equivalent explicit gate-node mechanism for a **same-repo**
release/deploy dependency (e.g., a monorepo where one issue must be published
to a registry before a later issue can consume it) -- the Gate concept is
defined only inside the coordinated (cross-repo) contract.

I searched for evidence of "a workflow that must reach main before it can be
invoked" and "merge gate between steps" beyond the three lines that name them
(`skills/plan/SKILL.md:153`, `phase-3-decomposition.md:518`,
`references/workflow-principles.md:23`, and one BRIEF citation). There is no
worked example, script, or validator check for this pattern anywhere in the
repo -- it is asserted as a real category (and it is a real GitHub Actions
constraint: a workflow file generally must exist on the default branch before
`workflow_dispatch`/scheduled triggers can invoke it), but shirabe has built no
machine detection for it. Contrast with cross-repo and gate-nodes, which have a
full authoring format, a contraction algorithm, an acyclicity check (R13), and
a merge-gate validator (F4) in `coordination-strategy.md`.

### Does the complexity classification system help? No -- wrong axis

`skills/plan/scripts/apply-complexity-label.sh` and the `simple/testable/critical`
labels apply `validation:*` GitHub labels that gate how rigorously an issue's
*code* is reviewed/tested (simple: CI green; testable: has a validation
script; critical: needs security review). This is a per-issue authoring-rigor
signal, orthogonal to whether the issue set as a whole can land in one PR. The
`plan-format.md` Complexity column (`trivial|simple|testable|complex`) is the
same axis carried into the PLAN doc. Nothing in `references/quality/` computes
graph shape, repo spread, or file overlap for PR-boundary purposes -- that
computation doesn't exist yet.

### Does issue count alone force multi-pr? No -- disproven by /work-on and /execute

`skills/work-on/SKILL.md`'s own description states it "Accepts ... a PLAN
document path (drives multiple issues through one shared branch and PR)."
Line 168 confirms the plan-level orchestrator -- "shared branch and draft PR,
child spawning, cross-issue context assembly, escalation, PR finalization, and
the completion cascade" -- now lives in `/execute`, with `/work-on` only
implementing "Plan-Backed Child Mode," delegated to per issue. This is direct,
concrete evidence that an arbitrary number of issues, with a real dependency
graph among them (Phase 5's parallelization/critical-path machinery exists
precisely to sequence them), can and routinely does land in a single PR under
`single-pr` execution mode. Issue count and dependency-graph depth are
therefore not forcing signals for "can" -- they're inputs to the separate
review-ergonomics "should" question.

## Implications

A trustworthy "can" gate is really two nested checks, and only the first is
close to deterministic:

1. **Repo-count check (machine-checkable, close to deterministic).** If the
   decomposition's issues (or the design's stated target repos) span more than
   one repository, single-pr is impossible and the plan must be `multi-pr` or
   `coordinated`. This is checkable once the decomposition names a repo per
   issue -- but naming that repo is itself an authoring step, not something
   `/plan` derives from nothing. A design/PLAN with no `Repo:` annotation gives
   no repo-count signal at all.
2. **Release/availability-dependency check (agent-judgeable, not currently
   machine-checkable).** Does any issue require a *prior* issue's artifact to
   be externally available (published, deployed, merged to a ref another
   system reads) rather than merely present in the same commit history? This
   is the actual "can't" mechanism behind both named hard-constraint examples
   (cross-repo publish gates, workflow-must-reach-main). It requires platform
   knowledge (e.g., how `workflow_dispatch` activation works) that a plain
   `Blocked by <<ISSUE:N>>` edge does not encode. Nothing in Phase 5's
   dependency-mapping steps asks "is this edge same-PR-safe or
   release-gated?" -- that discrimination doesn't exist as a step.

Everything else the lead's prompt offered as a candidate signal --
dependency-graph depth/width, complexity labels, disjoint file sets -- is
either already proven not to force a split (depth/width, via /execute's
shared-branch mode) or measures a different question entirely (complexity
labels measure review rigor; file-set overlap would measure merge-conflict
risk / reviewability, a "should" concern, and isn't computed today anyway).

## Surprises

- Cross-repo is not a `multi-pr` trigger as SKILL.md's own prose phrasing
  ("Cross-repo landing order" listed under the multi-pr hard-constraint bullet)
  suggests in isolation -- it is routed to a **third, structurally distinct**
  execution mode (`coordinated`) with its own lifecycle, visibility rules, and
  merge-gate validator. A rule that just says "cross-repo -> multi-pr" would be
  wrong; the correct target is "cross-repo -> coordinated."
- The skill's own value-confirmation guard (3.5a) explicitly has an
  "ambiguous" outcome and, under `--auto`, never hard-stops on non-pass units
  -- it records them as `assumed` at high review priority instead. That is the
  skill's own admission that the *value* half of its execution-mode decision
  is not deterministic. The lead's framing correctly scopes that out as
  "should," but it means roughly half of shirabe's actual multi-pr escape
  logic (condition 2, independently-useful PRs) is judgment by design, not a
  gap to be closed.
- The "released artifact of a prior issue" pattern has a fully-built mechanism
  (Gate nodes) only in the cross-repo contract. A same-repo/same-monorepo
  version of the same problem (e.g., tsuku's `recipes/` needing a published
  recipe before the CLI's issue can consume it) has no equivalent modeling
  anywhere I found.

## Open Questions

- Should the same Gate-node mechanism (`references/coordination-strategy.md`)
  be generalized to single-repo plans, so a same-repo release/deploy
  dependency can be authored and machine-checked the same way a cross-repo
  publish gate is today? That would close the biggest gap this research found.
- Is there a reliable way to detect "a workflow that must reach main before it
  can be invoked" from a DESIGN's text, or does it always require the author
  to have thought of it and annotated it explicitly (the same authoring-burden
  problem as Gate nodes)? I found no detection heuristic in the repo to check
  against.
- If repo-count and Gate-node presence are the only two near-deterministic
  "can" signals, is that a thin enough rule to be worth automating, or does
  its dependence on author-supplied annotations (repo tags, gate nodes) mean
  it only formalizes what a careful author already had to decide by hand --
  i.e., does it move the judgment call rather than remove it?

## Summary

The only near-deterministic "can't fit in one PR" signal shirabe already
has built is repo-count spread, which routes to a distinct `coordinated`
mode (not plain `multi-pr`) and has a full Gate-node mechanism for
release/publish dependencies within that cross-repo contract; issue count,
dependency-graph depth, and complexity labels are all proven non-forcing by
`/execute`'s single-pr shared-branch/PR mode, which already drives many
dependent issues through one PR. The main gap is that "a workflow must reach
main before it's invokable" -- the other named hard constraint -- has no
detection mechanism anywhere in the repo, and even the built Gate-node
concept only exists for cross-repo plans, not same-repo release dependencies,
so any "can" rule built today would still lean on the author having noticed
and annotated the constraint by hand.
