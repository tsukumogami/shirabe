# Split Triggers

The single source for when work is delivered as more than one pull
request. Two rules used to answer this question at two altitudes and
disagreed about reviewability: principle P1 in
`workflow-principles.md` governed the plan-level single-pr/multi-pr
choice, and the Coarsest-Legal-Grouping Rule in
`coordination-strategy.md` governed per-repo grouping inside a
coordinated effort. Both now cite this file.

The shape follows `issues-table.md`: a shared core both profiles
consume, then per-profile deltas. Neither citing file re-enumerates
the branches, which is what keeps them from drifting apart again.

## Shared Core

Work is delivered as few pull requests as the repository's stated
delivery preference permits. A split beyond that default requires a
**named branch**, recorded in the artifact that plans the work.

Three branches justify a split. They are exhaustive at plan
altitude; the coordinated profile adds a fourth below.

### Hard Constraint

A named, non-optional condition that makes a single pull request
impossible. The constraint is a fact about the work, not a judgment
about it.

Instances: work spanning more than one repository, where landing
order across repos is load-bearing; a workflow file that must reach
the default branch before anything can invoke it; a step whose
output must be published, deployed, or merged before a later step
can consume it; a merge gate between steps.

The test is whether one pull request could land at all, not whether
it would be pleasant to review. "This would be a large diff" is not
a hard constraint.

### Incremental Value

Each resulting unit is independently useful to a reader who
encounters it alone — not a building block someone has to wait on.

This is the branch the value-confirmation guard checks (`/plan`
step 3.5a). That guard runs regardless of which branch produced the
split, so naming this branch does not exempt a unit from it and
naming another branch does not skip it.

"Could be separate pull requests" is not the test. "Each pull
request is independently useful to a reader" is.

### Stated Preference

The repository has said, on the durable CLAUDE.md convention
channel, that it wants this shape.

This is where reviewability lives, at every altitude. A team that
splits work because its reviewers cannot absorb a large diff names
this branch and says so in those terms. Before this file existed
that team had no sanctioned vocabulary: P1 permitted a split only
for a hard constraint or genuine incremental value, so a
reviewability preference had to be laundered as a value claim, while
the coordination rule listed a reviewability ceiling as a legitimate
trigger. Naming the branch once, here, is what resolves that
disagreement.

## Plan Profile

Consumed by principle P1 in `workflow-principles.md` and by the
Execution Mode Decision on `skills/plan/SKILL.md`.

All three shared branches apply as written. There is no
profile-specific fourth branch.

The unit is a pull request. The default is `single-pr`, unless the
repository's delivery preference says otherwise. A plan that is not
`single-pr`, or that departs from what the resolved preference would
have produced, records its branch in the PLAN's `split_rationale`
frontmatter field.

Worked examples:

- A change adding a reusable workflow, plus a second change invoking
  it. The workflow must reach the default branch before the
  invocation resolves. **Hard Constraint.**
- A repository declaring `atomic` delivery, planning a change whose
  decomposition permits a split. **Stated Preference** — and the
  record says so rather than inventing a value claim.
- Three independently shippable capabilities that each land
  observable behavior on their own. **Incremental Value.**
- A large refactor in a repository declaring `consolidated`, with no
  publish step and no cross-repo work. No branch fires; it is
  `single-pr`, and it records nothing.

## Coordinated Profile

Consumed by the Coarsest-Legal-Grouping Rule in
`coordination-strategy.md`.

All three shared branches apply, plus one that exists only here.

The unit is a `(repo, pr_group)` node rather than a plain pull
request, and the default is the coarsest legal grouping: one pull
request per repository.

### Merge-Order Necessity (coordinated only)

A split is required to break a contraction cycle in the merge-order
DAG. This has no plan-altitude analog, because there is no
merge-order DAG at plan altitude.

### Retired Triggers

Two triggers this rule used to carry as free-standing bullets are
retired, folded into Hard Constraint's coordinated examples:
"the slices are independently mergeable" and "the slices are
independently rollback-able." Both named a symptom rather than a
cause — what makes a slice independently mergeable is a repository
boundary or a landing-order requirement, which is a Hard Constraint.
Keeping them as separate triggers also made them over-fire if lifted
to plan altitude, where almost any well-decomposed plan satisfies
them.

The "configured reviewability ceiling" trigger is likewise retired
as a fourth trigger and folded into Stated Preference, which is now
the one place reviewability is named at any altitude.
