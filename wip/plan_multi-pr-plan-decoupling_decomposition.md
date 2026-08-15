---
input_type: design
source: docs/designs/DESIGN-multi-pr-plan-decoupling.md
execution_mode: single-pr
---

# Decomposition: multi-pr-plan-decoupling

## Strategy

Horizontal. The design's four batches are layered rather than a vertical slice:
a shared reference and a record format, then two independent preferences riding
them, then the extraction change that depends on one of the preferences existing.
Interfaces between the layers are well defined (a frontmatter field, two header
names, a resolved enum), which is the condition the strategy guidance names for
horizontal over walking skeleton. There is no end-to-end runtime path whose
integration risk would justify a skeleton first.

## Step 3.5a: Value confirmation

The plan is not being split for incremental value, so the guard runs against the
whole plan as one unit. Verdict: **pass**. Landed alone, the change gives a
reader plans that record why they are shaped as they are, and two repository
preferences that were previously unexpressible. That is observable value, not a
building block someone waits on.

## Step 3.6: Execution mode

**single-pr.**

Applying the rule as it stands today, not as this design proposes to change it:

- *Does a hard constraint force multiple PRs?* No. Nothing spans a second
  repository. No workflow file has to reach the default branch before something
  can invoke it. No step needs a merge gate before the next can start. Every
  issue is an edit to a file in this repository, and the eight of them can land
  in one commit set.
- *Is each PR independently useful?* Not applicable, because the plan is not
  proposing a split. Issue 1 would be independently useful if split out, but
  "could be separate PRs" is explicitly not the test.

So the default holds and the plan lands as one pull request.

Worth recording, because this plan's own subject matter is the thing it
demonstrates: under the current rule the PLAN this produces will carry no record
of why it is single-pr, and it does not need one. Under the design's own R15 it
still would not, because shirabe's repository states no delivery preference and
`consolidated` is the default, so single-pr is exactly what the preference would
have produced. The plan is a negative example of the feature and passes it.

## Issues

Eight, in dependency order.

1. Author the shared split-triggers reference; repoint P1 and the
   Coarsest-Legal-Grouping Rule. **testable**
2. Document `split_rationale` and teach step 3.6 to emit its branch. **testable**
3. Implement the `L09` check and its posture registration. **testable**
4. Add the delivery-preference header and its resolution. **testable**
5. Add the tracking-level header and gate issue creation on it. **testable**
6. Re-key the approval-gate prose and amend its decision record. **simple**
7. Emit issueless multi-pr work items from the plan's own outlines. **critical**
8. Amend Decision 6 of the roadmap-plan-standardization design. **simple**
