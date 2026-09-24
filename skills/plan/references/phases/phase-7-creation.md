# Phase 7: PLAN Artifact Creation

Create the PLAN artifact and, when the resolved tracking level asks for them,
GitHub issues and a milestone. The branch taken depends on `execution_mode`
(`multi-pr`, `single-pr`, or `coordinated`).

When the input is a roadmap, **do not** re-drive this phase to fill the
roadmap's reserved sections by prose substitution -- that path is retired.
The roadmap workflow now ships its own native CLI subcommand,
`shirabe roadmap populate`, that reads the Features section using the
shared `shirabe-validate` parser and writes the reserved sections by
structural section replacement. Its issue-creating mode also creates one
GitHub issue per feature with discrete `gh issue create` args. Invoke it
via `/roadmap populate <path> --issues` to file issues, or
`/roadmap populate <path> --no-issues` to render the sections without
touching GitHub; always name the mode rather than relying on the
subcommand's default (see `skills/roadmap/SKILL.md`).

The `input_type: roadmap` branch in this phase remains only for the case
where a PLAN document is being produced from a roadmap upstream (i.e., the
author still wants the conventional PLAN artifact for a roadmap-scoped
slice). It no longer rewrites the roadmap document itself.

## Table of Contents

- [Resume Check](#resume-check)
- [Prerequisites](#prerequisites)
- [multi-pr Mode](#multi-pr-mode): 7.1 Create GitHub Issues, 7.2 Write PLAN Artifact (roadmap population is handled by `/roadmap populate`, not this phase), 7.3 Verify Creation, 7.4 Validate Traceability
- [single-pr Mode](#single-pr-mode): 7.1 Write PLAN Artifact, 7.2 Suggest Next Steps
- [coordinated Mode](#coordinated-mode): 7.C1 Filing Approval, 7.C2 Create GitHub Issues, 7.C3 Write PLAN Artifact, 7.C4 Suggest Next Steps
- [Common Steps](#common-steps-all-modes): 7.5 Status Transition, 7.6 Cleanup, 7.7 Report Summary, 7.8 Upstream Issue Update

## Resume Check

**For roadmap input** (`input_type: roadmap`): The roadmap's reserved
Implementation Issues and Dependency Graph sections are populated by the
roadmap-native subcommand `shirabe roadmap populate` (via
`/roadmap populate <path> --issues` or `--no-issues`), NOT by this phase.
This phase still handles creating a PLAN document for a roadmap-scoped
slice when one is wanted; for populating the roadmap document itself,
exit and run `/roadmap populate <path>` with the mode flag that matches
what you want -- `--issues` to file GitHub issues, `--no-issues` to
render the sections without them. Do not leave the mode to the
subcommand's default.

Check if `docs/plans/PLAN-<topic>.md` exists.

**For all other input types**: Check if `docs/plans/PLAN-<topic>.md` exists.

| Existing Status | Action |
|-----------------|--------|
| Active | Skip -- already complete |
| Done | Skip -- already complete |
| Draft | Ask user: continue editing or overwrite |
| _(does not exist)_ | Proceed normally |

## Prerequisites

Read all topic-scoped wip/ artifacts:
- `wip/plan_<topic>_analysis.md` -- design doc path and scope
- `wip/plan_<topic>_milestones.md` -- milestone definitions
- `wip/plan_<topic>_decomposition.md` -- issue outlines and strategy (includes `execution_mode` in YAML frontmatter)
- `wip/plan_<topic>_manifest.json` -- generated issue bodies and file references
- `wip/plan_<topic>_dependencies.md` -- dependency graph
- `wip/plan_<topic>_review.md` -- review approval

**STOP** if `wip/plan_<topic>_manifest.json` does not exist. Phase 4 (Agent Generation) must run first.

Read the `execution_mode` from the decomposition artifact's YAML frontmatter, then branch to the appropriate section below. Carry its `split_mode_source` (and, on a split, `split_rationale`) into the PLAN's frontmatter next to `execution_mode`: they are the record that lets a caller re-run `scripts/resolve-split-mode.sh` over the PLAN's split and compare.

### Resolve the Tracking Level first

Before either branch runs, resolve which GitHub artifacts this PLAN's work items
get. This is a **separate question from `execution_mode`** and is resolved on its
own stack:

```
flag > CLAUDE.md `## Tracking Level: none|issues|issues-and-milestone` > default
```

Where a level is stated it applies regardless of `execution_mode`. Where none is
stated, the default is derived from the mode -- `issues-and-milestone` for
`multi-pr`, `none` for `single-pr` and for `coordinated` -- which for single-pr
and multi-pr is the behavior every repo has today. An unrecognized value falls
through to that default rather than being used.

`coordinated` follows the same stack, with `none` as its default, and step 3.6's
step 5a has already resolved it into the decomposition artifact's
`tracking_level`, so Phase 4 could choose body depth; use that value. Phase 7
**always writes `tracking_level` into a coordinated PLAN's frontmatter**, `none`
included. The field is what selects the PLAN's shape downstream: the validator
and the task extractor read a coordinated PLAN as outline-shaped only at an
explicit `tracking_level: none`, and read one with no field as issue-carrying.

Write the resolved value into the PLAN's `tracking_level` frontmatter field. This
is load-bearing rather than bookkeeping: task extraction runs against a committed
PLAN, possibly long after authoring, and if it re-resolved the level from
CLAUDE.md then a repo that later changed its header would silently change how an
already-written plan's work items key.

The resolved level, not the mode, decides what gets created:

| Level | What is created |
|---|---|
| `none` | No GitHub artifacts. Work items live in the PLAN's Issue Outlines. |
| `issues` | One GitHub issue per work item, assigned to no milestone. |
| `issues-and-milestone` | One issue per work item, all assigned to one milestone. |

Every combination of `{single-pr, multi-pr, coordinated}` and the three levels
is reachable. A `single-pr` PLAN with `issues` files them; a `multi-pr` PLAN with
`none` files nothing; a `coordinated` PLAN files nothing at its default `none`
and files issues, behind an explicit approval, only at `issues` or
`issues-and-milestone`.

---

## multi-pr Mode

Steps 7.1 through 7.4 apply when `execution_mode: multi-pr`.

**Gated on the resolved tracking level, not on the mode.** Run 7.1 only when the
level is `issues` or `issues-and-milestone`; under `none`, skip to 7.2 and write
the PLAN with its work items in an `## Issue Outlines` section, exactly as the
single-pr branch does. Under `issues`, create the issues without a milestone --
pass no `--milestone` flag to the batch script.

### 7.1 Create GitHub Issues Using Batch Script

Use the batch script to create all issues in dependency order.

**Script**: `${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh`

Read `wip/plan_<topic>_milestones.md` for the milestone name and description, then run the batch script. The invocation varies by input type.

**For design/prd input types:**

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Design: \`<design-doc-path>\`" \
  --output-map wip/plan_<topic>_mapping.json
```

**For roadmap input type:**

The milestone description references the roadmap (not a design doc). Per-issue `needs_label` values from the manifest are applied automatically by the batch script (see Issue 3: each manifest entry's `needs_label` field is merged with global labels).

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Roadmap: \`<roadmap-path>\`" \
  --output-map wip/plan_<topic>_mapping.json
```

The manifest must include `needs_label` for each issue (populated during Phase 3 roadmap decomposition). The batch script applies these per-issue labels alongside any global `--labels`.

Options:
- `--milestone <name>` -- assign all issues to this milestone (created if it doesn't exist)
- `--milestone-description <desc>` -- milestone description (include source doc path)
- `--labels <labels>` -- comma-separated labels for all issues
- `--output-map <file>` -- write the final ID-to-GitHub-number mapping
- `--dry-run` -- preview without creating

**Strategic scope:** Add strategic labels:
```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Design: \`<design-doc-path>\`" \
  --labels "needs-design,repo:<target-repo>" \
  --output-map wip/plan_<topic>_mapping.json
```

#### Handle Failures

If the script reports failures:
1. Check error output for details
2. Fix the body file and re-run, or create individually:

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issue.sh \
  --file wip/plan_<topic>_issue_<id>_body.md \
  --title "<title>" \
  --complexity <complexity> \
  --map wip/plan_<topic>_mapping.json \
  --milestone "<Milestone Name>"
```

#### Placeholder Substitution

The batch script handles `<<ISSUE:N>>` placeholders in three passes:

1. **Create**: Issues created with placeholders intact. ID-to-GitHub-number mapping built as each issue is created.
2. **Update**: All issue bodies re-read, placeholders substituted using the complete mapping, GitHub issues updated via `gh issue edit`.
3. **Verify**: Each issue fetched and checked for unresolved placeholders.

This handles forward references -- an issue can reference any other issue in the batch.

#### Apply Complexity Labels

Complexity labels are applied via: `${CLAUDE_SKILL_DIR}/scripts/apply-complexity-label.sh`

### 7.2 Write Output Artifact

Write the PLAN artifact. (This phase no longer rewrites a roadmap document
itself; for roadmap input, see the redirect above.)

#### 7.2b Write PLAN Artifact

Create `docs/plans/PLAN-<topic>.md` with the following structure.

**Frontmatter:**

```yaml
---
schema: plan/v1
status: Active
execution_mode: multi-pr
split_mode_source: <flag | intent | default>   # from the decomposition artifact
split_rationale: |                             # from the decomposition artifact
  <branch>. <rationale>
upstream: <source-doc-path>   # design doc, PRD, or roadmap path
milestone: "<Milestone Name>"
issue_count: <N>
---
```

When `--upstream <roadmap-path>` was supplied, `upstream:` is a sequence: the
source document first, the ROADMAP second. The PLAN is the node that records
the crossing from the strategic chain into the tactical one, because it is a
working artifact the cascade deletes -- and deletes before the roadmap -- so
the link cannot outlive its target. No durable document in the chain may name
a roadmap.

```yaml
upstream:
  - <source-doc-path>
  - docs/roadmaps/ROADMAP-<name>.md
```

**Carry the design's decisions into the Decomposition Strategy rather than only
citing the design.** Where an issue's shape or its position in the sequence
follows from a decision the design made, say which decision and why it forces
that shape — not `per the DESIGN`, but the reasoning that makes this
decomposition the right one.

A plan whose strategy section only points at its design cannot fold that design,
because the design genuinely still holds reasoning the plan does not. That is the
right outcome when the design settled something contested. It is the wrong one
when the design's whole contribution was deciding what order to do things in and
the plan now encodes exactly that — which is the common case for a self-contained
fix, and the case this matters for. `/scope` composes the design's contribution
section from *this document's* body when it folds, so the material has to be here
first.

**Required sections** (in order):

1. **Status** -- `Active`
2. **Scope Summary** -- from `wip/plan_<topic>_analysis.md`
3. **Decomposition Strategy** -- from `wip/plan_<topic>_decomposition.md`:
   - design/prd: "Walking skeleton" or "Horizontal decomposition" with rationale
   - roadmap: "Feature-by-feature planning" with rationale
4. **Implementation Issues** -- table with GitHub issue links, dependencies, complexity. Include description rows below each issue. Follow the format in `../quality/plan-doc-structure.md`.
5. **Dependency Graph** -- Mermaid diagram following these rules:
   - Use `graph TD` (not `flowchart`)
   - Node IDs: `I<issue-number>`, labels in `["..."]`
   - Edges MUST be outside subgraphs
   - `classDef` definitions at the end -- include the full expanded set: `done`, `ready`, `blocked`, `needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`, `tracksDesign`, `tracksPlan`
   - For roadmap planning issues: each node's initial class matches its `needs_label` (e.g., `needsPrd`, `needsDesign`)
   - Class assignments use `class` directive (not inline `:::`)
   - Include legend line after diagram
6. **Implementation Sequence** -- critical path, parallelization opportunities, recommended order

Reference `../quality/plan-doc-structure.md` for detailed format rules.

### 7.3 Verify Creation

```bash
gh issue list --milestone "<Milestone Name>"
```

Verify:
- [ ] All issues created
- [ ] Milestone assignments correct
- [ ] Dependencies reference correct issue numbers

### 7.4 Validate Traceability References

#### Strategic scope (design/prd input)

Verify every needs-design issue body contains a `Design:` reference line:

1. Read each body file from the manifest
2. Check for `Design: \`<path>\`` (backtick-quoted path to the parent design doc)
3. If missing, add it to the Context section and re-run the batch script for that issue

This reference is required to locate the parent design doc when accepting a child design.

#### Roadmap input

Verify every planning issue body contains both traceability references:

1. Read each body file from the manifest
2. Check for `Roadmap: \`<path>\`` (backtick-quoted path to the parent roadmap)
3. Check for `Feature: <feature-name>` identifying which roadmap feature this issue plans
4. If either is missing, add it to the Context section and re-run the batch script for that issue

These references enable traceability from planning issues back to the source roadmap and specific feature.

---

## single-pr Mode

Steps 7.1 through 7.2 apply when `execution_mode: single-pr`.

**Gated on the resolved tracking level, not on the mode.** Under the default
(`none` for single-pr) no GitHub milestone or issues are created, which is
today's behavior. Under a stated `issues` or `issues-and-milestone`, run the
multi-pr branch's 7.1 to create them, then continue here.

### 7.1 Write PLAN Artifact

Create `docs/plans/PLAN-<topic>.md` with the following structure.

PLANs whose activation creates no GitHub artifacts are authored directly at
`status: Active`: the Draft -> Active transition auto-fires as authoring
completes under the unified PLAN lifecycle. An activation that **will** create
GitHub issues requires human approval first, whatever the `execution_mode` --
the gate tracks the remote artifacts, not the mode. See the approval-gate rule in
`skills/plan/SKILL.md`.
A committed single-pr PLAN that lands on a branch at `status: Draft`
is a violation — the chain-aware `--lifecycle` check fails on it.

**Frontmatter:**

```yaml
---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none   # from the decomposition artifact
upstream: <design-doc-path>
milestone: "<Milestone Name>"
issue_count: <N>
---
```

When `--upstream <roadmap-path>` was supplied, `upstream:` is a sequence: the
source document first, the ROADMAP second. The PLAN is the node that records
the crossing from the strategic chain into the tactical one, because it is a
working artifact the cascade deletes -- and deletes before the roadmap -- so
the link cannot outlive its target. No durable document in the chain may name
a roadmap.

```yaml
upstream:
  - <source-doc-path>
  - docs/roadmaps/ROADMAP-<name>.md
```

**Required sections** (in order):

1. **Status** -- `Active`
2. **Scope Summary** -- from `wip/plan_<topic>_analysis.md`
3. **Decomposition Strategy** -- from `wip/plan_<topic>_decomposition.md` (walking skeleton, horizontal, or feature-by-feature planning, with rationale)
4. **Issue Outlines** -- read from body files (`wip/plan_<topic>_issue_<id>_body.md`), format as structured outlines with these subsections per issue:
   - **Goal** -- what the issue delivers
   - **Acceptance Criteria** -- how to verify completion
   - **Dependencies** -- which internal IDs this blocks on
5. **Dependency Graph** -- same Mermaid format as multi-pr, but nodes use internal IDs (`I1`, `I2`, ...) instead of GitHub issue numbers. Same `classDef` rules apply.
6. **Implementation Sequence** -- critical path, parallelization opportunities, recommended order

No Implementation Issues table in single-pr mode.

### 7.2 Suggest Next Steps

Recommend running `/execute docs/plans/PLAN-<topic>.md` to begin implementation.
For a `multi-pr` PLAN the advice is `/work-on` instead, per issue (see 7.7).

---

## coordinated Mode

Steps 7.C1 through 7.C4 apply when `execution_mode: coordinated`. The
coordinated contract (lifecycle, grouping, merge order, done-signal) is
`${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md`; this section only
writes the PLAN and, when asked, files its issues. It does not open the
coordination PR -- `/execute` does that when it runs the PLAN.

**Gated on the resolved tracking level**, which step 5a recorded as
`tracking_level` in the decomposition artifact:

- **`none` (the default):** skip 7.C1 and 7.C2 entirely and go to 7.C3. No
  `gh issue` command and no `gh api` milestone call runs on this path; the work
  items live only in the PLAN's Issue Outlines.
- **`issues` or `issues-and-milestone`:** run 7.C1, then 7.C2, then 7.C3.

The multi-pr and single-pr branches above are unchanged; the approval step in
7.C1 exists only on this coordinated filing path.

### 7.C1 Filing Approval (tracking level `issues` or `issues-and-milestone` only)

Filing creates remote artifacts, so it runs only after an explicit approval,
**before the first `gh issue create`**:

- **Interactive:** ask with AskUserQuestion, naming the number of issues, the
  repositories they will be filed in, and whether a milestone will be created:

  ```
  The tracking level for this coordinated PLAN is <issues|issues-and-milestone>,
  so Phase 7 will file <N> GitHub issues in <owner/repo>[, ...]<and create the
  milestone "<Milestone Name>">.

  - File them now (Recommended)
  - Don't file: write the PLAN at tracking level none, with outlines instead
  ```

  On "Don't file", set the tracking level to `none` and continue at 7.C3's
  outline-shaped branch.
- **`--auto`:** do not prompt. Resolve the approval per
  `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` -- a stated tracking
  level in `CLAUDE.md` is the repository's standing instruction to file, so the
  resolution is to file -- and record a decision block in
  `wip/plan_<topic>_decisions.md` naming the level, where it came from, and the
  issues to be filed. Then continue to 7.C2.

### 7.C2 Create GitHub Issues (tracking level `issues` or `issues-and-milestone` only)

Reuse the batch script exactly as the multi-pr branch's 7.1 does:

```bash
${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh \
  --manifest wip/plan_<topic>_manifest.json \
  --milestone "<Milestone Name>" \
  --milestone-description "Design: \`<design-doc-path>\`" \
  --output-map wip/plan_<topic>_mapping.json
```

At `issues`, pass no `--milestone` or `--milestone-description`, so no
milestone is created or assigned. Failure handling, placeholder substitution,
and complexity labels are as in multi-pr 7.1.

### 7.C3 Write PLAN Artifact

Create `docs/plans/PLAN-<topic>.md` at `status: Active` in both shapes: at
`none` nothing is filed, so the Draft -> Active transition auto-fires; at the
issue levels the filing was approved in 7.C1.

**Frontmatter:**

```yaml
---
schema: plan/v1
status: Active
execution_mode: coordinated
split_mode_source: <flag | intent | header>   # from the decomposition artifact
split_rationale: |                            # from the decomposition artifact
  <branch>. <rationale>
tracking_level: <none | issues | issues-and-milestone>   # always written
upstream: <source-doc-path>
milestone: "<Milestone Name>"
issue_count: <N>
---
```

A `--upstream <roadmap-path>` makes `upstream:` a sequence, exactly as in the
other branches.

**At tracking level `none` -- the outline-shaped coordinated PLAN.** Required
sections, in order:

1. **Status** -- `Active`
2. **Scope Summary** -- from `wip/plan_<topic>_analysis.md`
3. **Decomposition Strategy** -- as in the other branches
4. **Issue Outlines** -- one `### Issue <N>: <title>` outline per work item,
   read from the body files, each with:
   - **Goal**
   - **Acceptance Criteria**
   - **Dependencies** -- internal IDs only; never a gate
   - `**Repo**: <owner/repo>` and `**Group**: <slug>`, from the decomposition
     artifact

   followed by one `### Gate: <name>` block per declared gate, with
   `**After**:`, `**Before**:`, and `**Condition**:` lines, in the form
   `../quality/plan-doc-structure.md` documents under "Coordinated Mode".
5. **Dependency Graph** -- same Mermaid rules as single-pr, nodes `I1`, `I2`, ...
6. **Implementation Sequence**

No `## Implementation Issues` table: the validator treats a coordinated PLAN at
`tracking_level: none` as outline-shaped and reports FC14 when both outlines
and an issue table are populated.

**At `issues` or `issues-and-milestone` -- the issue-carrying coordinated PLAN.**
Required sections as in the multi-pr branch's 7.2b, with the Implementation
Issues table built from `wip/plan_<topic>_mapping.json` and, under each issue's
row, a `_Repo: <owner/repo> \| Group: <slug>_` annotation row, plus one
`_Gate: <name> \| After: ... \| Before: ..._` row per declared gate. No Issue
Outlines section. Follow `../quality/plan-doc-structure.md` for the exact row
format.

**Validate.** Step 7.4b's `shirabe validate` run must exit 0 on this PLAN, with
no FC04 or FC14 finding in either shape. An FC14 finding naming an outline's
missing or invalid `**Repo**:` / `**Group**:`, or a gate naming no outline, is
fixed in the PLAN before continuing.

### 7.C4 Suggest Next Steps

Recommend running `/execute docs/plans/PLAN-<topic>.md`, which cuts one branch
per PR node, opens the coordination PR, and lands the nodes in merge order.

---

## Common Steps (All Modes)

These steps run after the mode-specific steps above.

### 7.4b Validate PLAN Doc Reference Hygiene

Before transitioning the source doc's status (which marks the planning step
as "done" upstream), grep the PLAN artifact for non-durable or
visibility-violating references. Run from the repo root:

```bash
# 1. No wip/ paths anywhere in the PLAN body or frontmatter.
git grep -nE 'wip/' -- 'docs/plans/PLAN-<topic>.md'

# 2. Frontmatter, structure, and every upstream: entry. The field may be a
#    sequence -- a PLAN under a roadmap names its design and that roadmap --
#    and every entry is read, not just the first.
shirabe validate 'docs/plans/PLAN-<topic>.md'

# 3. Whether the upstream is at a status a PLAN may be built from.
shirabe validate --lifecycle-chain 'docs/plans/PLAN-<topic>.md'
```

`shirabe validate` is the reader here rather than a hand-written grep, and
that is deliberate: a scalar-only reader returns nothing for a sequence and
then reports "no upstream field", which silently skips the check for exactly
the PLANs that carry two entries. One normalizer in the validator enumerates
both written shapes and feeds every reader of the field, so the document that
passes is the document the extractor reads.

What the two invocations check between them: the required frontmatter fields
(`schema`, `status`, `execution_mode`, `milestone`, `issue_count`), the
required sections and the single-pr / multi-pr mutual exclusions, the outline
shapes task extraction depends on, and -- under `R6` -- that each `upstream:`
entry exists on disk, is tracked by git, is not a symlink, and does not
resolve outside the repository. The last two matter because the value reaches
a committed frontmatter field: a symlinked upstream resolves to different
content for different readers, and one escaping the tree names something no
other clone has. The git invocation passes every path after `--`, so a value
beginning with a dash is a pathspec rather than an option. Validation is not
the guarantee there; the argument boundary is.

A single earlier bash pre-flight used to run here and answered the upstream
-status question differently from the lifecycle check, accepting an upstream
at `Accepted` and rejecting one at `Current`. The lifecycle model's rule is
the surviving one: `/plan` moves the upstream DESIGN from `Accepted` to
`Planned` while authoring the PLAN, so a PLAN still naming an `Accepted`
DESIGN is evidence that transition did not run.

**Match handling:**

- **Any `wip/...` hit in the body or frontmatter is a hard fail.** wip/ paths
  are non-durable: they are deleted before merge and would leave the PLAN
  doc's references orphaned the moment cleanup runs. The trigger violation
  this check exists to catch is acceptance-criteria prose that names a
  specific `wip/PR-<topic>.md` or `wip/<artifact>.md` path -- replace with
  a generic phrase that describes the artifact's purpose without naming a
  non-durable path. Example: instead of `A PR draft is committed to
  wip/PR-foo.md`, write `A PR draft exists locally (cleaned before merge)`.
- **Prose mentions of the wip-hygiene rule itself are acceptable.** If a
  matching line is *describing* the rule (e.g., "wip/ artifacts are tolerated
  on the branch but must be cleaned before the PR opens"), it is allowed.
  Path-shaped references (anything that resolves to a file location) are
  not.
- **Every `upstream:` entry must resolve.** `shirabe validate` reports an
  `R6` finding naming each entry that does not, and exits 2. For a
  `owner/repo:path` entry it skips the local checks, because there is no
  local path to resolve, so confirm visibility direction by hand against
  `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md` (public repos
  must not reference private repos). A `ROADMAP-` entry is held to `Active`
  by the lifecycle chain check: a roadmap is Active for as long as any of
  its features is still being built, which is the whole window in which a PLAN
  naming it exists.
- **An exit 4 means the PLAN was not checked at all.** The filename routed it
  to the plan format but its `schema:` field is missing or is not `plan/v1`,
  so nothing above ran. Add the field and re-run; do not read the absence of
  findings as a pass.

**STOP if any check fails.** Fix the PLAN doc and re-run before proceeding to
status transition.

**Worked example (the failure mode this step prevents).** A planning agent
authoring a multi-issue decomposition writes an acceptance criterion that
says "the PR description is committed to `wip/PR-<topic>.md`." On the same
branch, another acceptance criterion says "clean up any leftover `wip/`
artifacts before merge." Both criteria get committed into the PLAN doc body.
The cleanup commit deletes the wip/ file but leaves the PLAN's prose
reference pointing at it -- the PLAN is now self-contradictory and contains
a path that resolves to nothing.

### 7.5 Source Document Status Transition

**For design docs and PRDs** (input_type: design or prd):

Transition the upstream design doc from Accepted to Planned:

```bash
shirabe transition <design-doc-path> Planned
```

**Important constraints** (implementation tracking lives in the PLAN artifact, not the design doc):
- This is a status-only change
- Do NOT insert an Implementation Issues section into the design doc
- Do NOT modify the design doc body
- Only the status line changes (Accepted -> Planned)

**For roadmaps** (input_type: roadmap):

Roadmaps stay at "Active" status. The PLAN artifact tracks the planning work, but the roadmap itself isn't transitioned -- it remains Active until all features are delivered. No status change is needed.

### 7.6 Cleanup

Delete topic-scoped wip/ artifacts on success:

```bash
rm -f wip/plan_<topic>_analysis.md
rm -f wip/plan_<topic>_milestones.md
rm -f wip/plan_<topic>_decomposition.md
rm -f wip/plan_<topic>_dependencies.md
rm -f wip/plan_<topic>_review.md
rm -f wip/plan_<topic>_issue_*.md
rm -f wip/plan_<topic>_manifest.json
rm -f wip/plan_<topic>_mapping.json
```

Do NOT delete on failure -- artifacts are needed for resume.

### 7.7 Report Summary

Summarize what was created:

**multi-pr:**
```markdown
## Created Artifacts

### Milestone: [<Name>](<milestone-url>)

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#N: <title>](<url>) | None | simple |
| [#M: <title>](<url>) | [#N](<url>) | testable |

### Dependency Graph

[Mermaid diagram]

**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needs-design, Orange = tracks-design

### Next Steps
Start with issues that have no dependencies (marked `ready` in diagram), running
`/work-on` on each:
- [#N](<url>): <title>
```

**single-pr:**
```markdown
## Created Artifacts

PLAN document: `docs/plans/PLAN-<topic>.md`
Design doc status: Planned

### Next Steps
Run `/execute docs/plans/PLAN-<topic>.md` to begin implementation.
```

**coordinated:**
```markdown
## Created Artifacts

PLAN document: `docs/plans/PLAN-<topic>.md` (tracking level: <none|issues|issues-and-milestone>)
Design doc status: Planned
Split mode: coordinated (split_mode_source: <flag|intent|header>)

| Work item | Repo | Group | Dependencies |
|-----------|------|-------|--------------|
| Issue 1 (or #N): <title> | <owner/repo> | <slug> | None |

### Next Steps
Run `/execute docs/plans/PLAN-<topic>.md` to begin implementation.
```

### 7.8 Upstream Issue Update

Ask the user if there's an upstream issue that should be updated:

```
Is there an upstream issue that should be updated to link to these newly created issues?

If yes, provide the issue reference in <owner>/<repo>#<number> format.
```

**If user provides an upstream issue:**

1. **Verify visibility direction**: Only update if the upstream issue is in a repo with SAME or MORE PRIVATE visibility. Never add references from public issues to private issues.

2. **Append implementation tracking**:
   ```bash
   CURRENT_BODY=$(gh issue view <number> --repo <owner>/<repo> --json body --jq '.body')

   gh issue edit <number> --repo <owner>/<repo> --body "$CURRENT_BODY

   ---
   ## Implementation Issues (in <current-repo>)

   - [#<N>](<issue-url>): <title>
   - [#<N>](<issue-url>): <title>
   "
   ```

3. **If the upstream issue still has `needs-design` label**, remove it now.

**Visibility rule**: Public issues must NEVER reference private issues. Only private issues can reference public issues.

**Strategic scope note:** After creating the milestone and issues, note that these are placeholder issues with `needs-design` label. The user should run `/work-on` on individual issues to create tactical designs when ready.

## Quality Checklist

Before completing:
- [ ] PLAN artifact created at `docs/plans/PLAN-<topic>.md`
- [ ] Frontmatter includes all required fields (`schema`, `status`, `execution_mode`, `milestone`, `issue_count`)
- [ ] multi-pr: all issues created, milestone assigned, status is Active
- [ ] coordinated: `tracking_level` written; at `none` no `gh issue` or milestone
  call ran and every outline carries `**Repo**:` and `**Group**:`; at `issues`
  levels the filing was approved before the first `gh issue create`
- [ ] PLAN doc reference hygiene (step 7.4b) passed: no `wip/...` paths in
  frontmatter or body prose; `upstream:` resolves on disk or is a valid
  public cross-repo reference

## Next Phase

This is the final phase of the /plan command.
