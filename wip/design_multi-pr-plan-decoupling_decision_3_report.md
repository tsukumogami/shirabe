<!-- decision:start id="issueless-task-keys" status="decided" -->

## Context

PRD-multi-pr-plan-decoupling R8 requires all six combinations of
{single-pr, multi-pr} x {none, issues, issues-and-milestone} to be
reachable, and R12 requires task extraction to produce a schedulable
dependency graph for a `none`-tracking plan "without depending on GitHub
issue numbers as work-item keys." `skills/plan/scripts/plan-to-tasks.sh`'s
`process_multi_pr` currently does exactly that: it walks the `##
Implementation Issues` table, pulls `#N` out of each row's first cell as
the work item's key, and resolves every `waits_on` edge by scanning the
Dependencies cell for further `#N` tokens (`plan-to-tasks.sh:296-334`,
`:352-363`). When the resolved tracking level is `none`, Phase 7 never
files GitHub issues, so no plan will ever have a real `#N` to write in
either place. Both the row key and the edge-resolution mechanism break at
the source, not just at the margin.

I also traced where `process_multi_pr`'s JSON output is actually consumed
today, because it bears on how much freedom this decision has. It is
none: `/execute` declines `multi-pr` outright (`skills/execute/SKILL.md:40-41`,
"out of scope for `/execute`; multi-pr plans run one issue at a time
through `/work-on`"), and `/work-on`'s multi-pr path does not call
`plan-to-tasks.sh` at all -- it resolves "next unblocked issue" by reading
live GitHub issue state directly (`skills/work-on/SKILL.md:122-126`, `:19`).
`process_multi_pr`'s emitted `{ISSUE_SOURCE: github, ISSUE_NUMBER: N}`
shape matches `/work-on`'s Plan-Backed Child Mode contract byte-for-byte,
but that mode is only entered by `/execute`'s shared-branch orchestration,
which multi-pr never runs. So today's multi-pr branch of this script is a
documented, tested contract with no live caller -- which means this
decision is free to shape the issueless case without an existing consumer
to keep byte-compatible, but it is not free to leave the *documented*
contract inconsistent, since `plan-to-tasks-contract.md` states it is
relied on by consumers this repo does not fully enumerate.

## Assumptions

- Whatever frontmatter field Decision 1 introduces to record the resolved
  tracking level exists and is readable by `plan-to-tasks.sh` at parse
  time (see Consequences -- this decision depends on that field existing,
  it does not invent it).
- An issueless multi-pr PLAN still needs the goal/AC/dependency content
  that a GitHub issue body would otherwise hold, because Phase 7 for
  `tracking: none` creates no issue to hold it. That content has to live
  in the PLAN document itself.

## Chosen

**Alternative A**, refined: a third `ISSUE_SOURCE` value for issueless
multi-pr work items, distinct from both `github` and `plan_outline` --
but built by reusing the existing `## Issue Outlines` parse (the
`shirabe plan outlines` binary call `process_single_pr` already uses)
rather than reimplementing a second parser, and reusing single-pr's
downstream local-id machinery (slugify, collision suffixing, 64-char
truncation) with a different id prefix so the two schemes stay visibly
distinct.

Proposed name: `ISSUE_SOURCE=plan_item`. Proposed id prefix: `m-<slug>`
(paired with single-pr's existing `o-<slug>` and coordinated's `pr-`/
`gate-`, each mode already gets its own letter).

### Implementation Issues table row shape

For `execution_mode: multi-pr` with resolved tracking `none`, the table
keeps the canonical two-row-per-item shape from `plan-format.md`, but the
first cell holds a local anchor into the PLAN's own `## Issue Outlines`
section instead of a `#N` GitHub link -- the same convention single-pr
already uses, applied at multi-pr cardinality:

```markdown
| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [m-add-foundation: feat: add foundation](#issue-m-add-foundation-feat-add-foundation) | None | testable |
| _Build the shared foundation module that later work items extend._ | | |
| [m-add-extension: feat: add extension](#issue-m-add-extension-feat-add-extension) | [m-add-foundation](#issue-m-add-foundation-feat-add-foundation) | simple |
| _Extend the foundation with the new capability. Ships as its own PR._ | | |
```

The PLAN also carries a `## Issue Outlines` section identical in shape to
single-pr's (`### Issue N: <Title>`, `**Goal**`, `**Acceptance
Criteria**`, `**Dependencies**`, optional `**Type**`/`**Files**`) --
that's what makes the `shirabe plan outlines` parse reusable verbatim.
The row's `<N>` in `### Issue N:` is the PLAN-internal outline number
(used only to resolve `Blocked by Issue N` / `<<ISSUE:N>>` references,
exactly as it already means for single-pr); it is never a GitHub number
and the table's displayed key is the derived `m-<slug>` id, not `N`.

### Emitted vars

| Key | Value |
|-----|-------|
| `ISSUE_SOURCE` | `"plan_item"` |
| `ARTIFACT_PREFIX` | Same as `name`, e.g. `"m-add-foundation"` |
| `ISSUE_TYPE` | Value of the outline's `**Type**:` annotation, omitted if absent |

Structurally identical to single-pr's vars table, deliberately: the two
modes now share one parser and one local-id algorithm, and only the
`ISSUE_SOURCE` value and the id prefix differ. `waits_on` resolution is
untouched from `process_single_pr`'s existing logic (sibling-outline
references plus `**Files**` ownership edges) -- R12's "no GitHub issue
numbers as keys" requirement falls out of reusing that logic rather than
`process_multi_pr`'s `#N` regex walk.

## Rationale

Traced against what the script and contract actually do:

- `process_multi_pr`'s only two responsibilities are pulling `#N` from
  the row's first cell (`plan-to-tasks.sh:296-304`) and pulling further
  `#N` tokens from the Dependencies cell (`:352-363`). Both are the exact
  mechanism R12 says an issueless plan cannot depend on. There is no
  version of "keep `process_multi_pr`'s current shape" that satisfies R12
  -- the branch has to change for this cell of the R8 matrix regardless
  of which alternative is chosen.
- `process_single_pr` already solved "derive a stable local id and a
  schedulable graph from PLAN-internal prose, with no GitHub issue in the
  loop" -- that is its entire job. Reusing its parse and its id algorithm
  is not a new mechanism, it's recognizing that issueless-multi-pr and
  single-pr have the identical *sourcing* problem (no GitHub issue holds
  the content) and only differ in *execution* (multiple independent PRs
  vs. one shared-branch PR).
- The one-parser precedent is explicit and load-bearing:
  `plan-to-tasks-contract.md`'s single-pr section says the parse "lives in
  `shirabe-validate`... reaches this script through `shirabe plan
  outlines`... the same function backs `shirabe validate`'s FC14, FC17,
  and L06 checks, which is the point: a PLAN that validates clean is by
  construction a PLAN this script reads the same way," and names the
  three-independent-readers defect (`DESIGN-issue-outlines-one-parser.md`)
  that arrangement removed. Building a second, multi-pr-flavored
  re-implementation of `## Issue Outlines` parsing to solve issueless
  multi-pr would reopen exactly that defect for a fourth time.

## Alternatives Considered

**B -- reuse `plan_outline` semantics with an internal-id convention.**
Rejected. `ISSUE_SOURCE=plan_outline` is not just an id scheme, it's a
contract with `/work-on`'s Plan-Backed Child Mode
(`skills/work-on/SKILL.md:139-168`): it expects a `SHARED_BRANCH` var
injected by `/execute`'s orchestrator, commits directly to that branch
with `status: override`, and skips PR creation because "the orchestrator
owns the PR." Multi-pr's design explicitly rejects that model --
"There is no shared branch and no cross-issue carry-forward -- multi-pr
issues are independent, per the DESIGN's ephemeral-home model"
(`skills/work-on/SKILL.md:126`). Emitting `ISSUE_SOURCE=plan_outline` for
issueless multi-pr work items would either (a) require `/execute` to stop
declining multi-pr and start faking a shared branch it was designed not
to have, or (b) require `Plan-Backed Child Mode` to grow an
`execution_mode`-conditional branch inside a consumer that today has none
-- a second place besides `plan-to-tasks.sh` that has to know issueless
multi-pr is a distinct case. A also reuses the *parse*, but keeps the
*execution contract* distinct, which is the piece B's constraint
correctly flags as broken.

**C -- make the table's first cell a stable internal id in all modes,
carry the GitHub number in a separate column.** Rejected, though it is
the more uniform fix. See Adversarial Pass -- the blast radius lands on
the five R8 cells this feature does not otherwise touch, for no benefit
those five cells need.

**D -- do not support issueless multi-pr in task extraction; narrow R8.**
Rejected on the evidence, not on taste: R8 and the Tracking preference
acceptance criteria ("Task extraction on a multi-pr plan whose tracking
level is none produces a task graph in which every dependency edge
resolves to a declared work item, with no unresolved keys") are settled
PRD requirements, not open questions this design gets to relitigate. The
DESIGN document's own "Known Costs to Carry" section names this exact gap
as "the largest underpriced item" to solve, not a candidate for descoping
-- so D is already foreclosed by documents upstream of this decision.

## Adversarial Pass

C is the cleanest read if you only look at the schema: one row shape for
every mode, a `github_number` column that is simply empty when tracking
is `none`. It removes the asymmetry this decision otherwise introduces
(single-pr and issueless-multi-pr both use local anchors; issue-tracked
multi-pr alone keeps `#N` as the *displayed* key). I want to be honest
about what rejecting it costs: A leaves the table format genuinely mode-
dependent -- a reader has to know the tracking level to know whether the
first cell's `#N` is real or whether to look for `m-<slug>` -- where C
would make the table format uniform and let tracking level be a pure
runtime fact instead of a syntax fact.

That said, the blast radius is the deciding fact, and it is not close.
Changing the canonical Implementation Issues table shape touches:
`plan-format.md`'s table contract, `plan-to-tasks.sh`'s `process_multi_pr`
*and* `process_coordinated` (both parse the same `#N`-in-first-cell
shape via `re_issue_num`), the validator's FC05/FC06/FC07 checks
(`plan-format.md`'s own Validation Rules section), and every place
`## Implementation Issues` is rendered or read across Phase 4/7 for the
`issues` and `issues-and-milestone` tracking levels -- five of the six R8
cells, none of which this feature is otherwise touching. R19 is explicit
that this feature's non-functional bar is "a repository that states
neither preference SHALL observe today's behavior in what the workflow
produces" for the unaffected cells. A schema change to the shared table
format is a harder promise to keep than a new, additive `ISSUE_SOURCE`
branch that only fires when tracking resolves to `none`. R19's own escape
hatch (no committed PLAN corpus to migrate, since the completion cascade
deletes them) blunts the *migration* cost of C but does nothing about the
*validator and consumer surface area* cost, which is the real charge here.

So this is deliberately the narrower fix over the more uniform one, and I
am choosing it on the belt-and-suspenders principle the DESIGN doc itself
states as a decision driver: "Distinguish itself from a prior rejection"
-- `DESIGN-capstone-orchestration.md` Decision G rejected an orthogonal
flag for permitting invalid combinations and doubling the validator's
branches. A uniform-schema change asks the *opposite* question but lands
in the same place: it changes a shared, validated surface for the benefit
of one cell of a six-cell matrix. If a later feature needs the GitHub
number to be optional metadata rather than the row's identity in more
than this one cell, C should be revisited then, with that second driver
in hand -- it would no longer be over-fitted to this decision's needs
alone.

## Consequences

- `plan-to-tasks-contract.md` needs a new documented `ISSUE_SOURCE=
  plan_item` vars table (shown above under Chosen), and its "multi-pr
  Mode" section needs to state explicitly that multi-pr now has two
  sub-shapes gated on the resolved tracking level, with issueless
  multi-pr cross-referencing single-pr's parse description rather than
  restating it (P4: one canonical description of the `## Issue Outlines`
  parse).
- `process_multi_pr` needs to branch before it starts its `#N` table
  walk. I recommend that branch read the tracking-level frontmatter field
  Decision 1 introduces (mirroring how `execution_mode` itself is read
  from frontmatter today) rather than sniffing whether the first data row
  contains `#N` -- sniffing is exactly the kind of implicit-detection
  fragility the rest of this script's error handling (e.g. the
  `shirabe-plan-outlines/v1` schema-version refusal) is built to avoid.
  This is a real coupling to flag back to whoever owns Decision 1/2: this
  decision assumes that field exists and is script-readable at parse
  time; if Decision 1 lands the tracking level as CLAUDE.md-only state
  with no PLAN-local record, `plan-to-tasks.sh` has no deterministic way
  to pick a branch and this decision's Chosen option needs revisiting.
- `plan-to-tasks_test.sh` needs a new fixture class alongside
  `test_multi_pr_basic` and `test_single_pr_basic`: an issueless multi-pr
  PLAN exercising `m-<slug>` ids, waits_on resolution through the shared
  outline parse, and (given the shared parser) the existing single-pr
  edge-case fixtures -- placeholder deps, section-header deps, Files
  ownership edges, truncation -- are very likely reusable near-verbatim
  against the new mode by construction, which is additional evidence for
  reusing the parser rather than a cost of it.
- **`/work-on M<N>` is lost for issueless multi-pr, honestly.** There is
  no milestone (tracking `none` creates no GitHub artifacts at all, R9),
  so `M<N>` has no referent, and `/work-on`'s multi-pr "select the next
  unblocked issue" logic reads live GitHub issue state
  (`skills/work-on/SKILL.md:19`), which does not exist here either. The
  natural replacement is `/work-on <PLAN.md-path>`, but it requires new
  work outside this decision's scope: `/work-on`'s Plan Input dispatcher
  today only knows how to hand `multi-pr` off to "run in place, one issue
  at a time" against GitHub issue state (`skills/work-on/SKILL.md:122-126`).
  An issueless multi-pr plan needs a third branch there that (a) calls
  this decision's extended `plan-to-tasks.sh` to get the schedulable
  graph, and (b) determines "already done" for a work item some other way
  than "GitHub issue is closed" -- most plausibly a local completion
  marker (a merged branch matching the item's `ARTIFACT_PREFIX`, or a
  status annotation written back into the table row). This decision makes
  that graph exist and be keyed correctly; it does not solve how `/work-on`
  reads real-world completion state without a GitHub issue to poll, which
  is a genuinely separate, currently-unowned piece of work and should be
  named explicitly as a follow-on rather than assumed solved.

<!-- decision:end -->
