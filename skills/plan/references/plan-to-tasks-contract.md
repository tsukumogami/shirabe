# plan-to-tasks.sh Contract

Reference for `skills/plan/scripts/plan-to-tasks.sh`. This document defines the
CLI signature, JSON output schema, name-sanitization rules, and mode-specific
behavior that consuming scripts and templates depend on.

## CLI Signature

```
plan-to-tasks.sh <PLAN.md-path>
```

**Arguments:** Exactly one positional argument — the path to a PLAN.md file.

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Success; valid JSON array written to stdout |
| 1 | Malformed input: file not found, unreadable, or `jq` not in PATH |
| 2 | Schema mismatch: wrong `schema:` value, missing `execution_mode`, empty slug, unresolvable dependency reference, or an unschedulable coordinated effort (see coordinated Mode) |

**Output:** JSON array on stdout. Log messages written to stderr (prefixed `[plan-to-tasks]`).

**Prerequisites:** `jq` must be available in `PATH`. Exit 1 if not found.

The `shirabe` binary is also required, because the `## Issue Outlines` parse
lives there rather than in this script (see below). It is resolved in the same
order `skills/work-on/scripts/run-cascade.sh` uses:

1. `$SHIRABE_BIN`, if set — the hook a test harness uses to pin a build.
2. `shirabe` on `PATH` — the plugin-installed binary.
3. `target/release/shirabe` or `target/debug/shirabe` under the repo root, for
   a developer working from a `cargo build`.

A missing binary is exit 1 with a message naming all three. There is no
fallback to a bash parse: a second implementation of this section is the defect
this arrangement removed, and one reachable only when the primary path is
unavailable would be the copy nobody tests. The script does not require a git
repository — the repo-root probe is best-effort and only feeds the third
option.

## JSON Output Schema

Each element in the array:

```json
{
  "name": "<string>",
  "vars": { "<KEY>": "<value>", ... },
  "waits_on": ["<name>", ...]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Task identifier. Must satisfy R9 regex. |
| `vars` | object | Key-value pairs passed to the koto template. |
| `waits_on` | array of strings | Names of tasks this task depends on. Empty array if none. |

The `template` field is intentionally omitted (set by the caller).

### multi-pr vars

Emitted when the PLAN's `tracking_level` is `issues` or
`issues-and-milestone`, or when the field is absent (the pre-existing
shape, and the mode-derived default).

| Key | Value |
|-----|-------|
| `ISSUE_SOURCE` | `"github"` |
| `ISSUE_NUMBER` | Issue number as string (e.g., `"42"`) |

Entries are emitted in Implementation Issues table order, one per entity row,
with `name: issue-<N>`. That order is part of the contract, not an accident of
the walk: a wrapper that lists the startable roots (`waits_on == []`) lists
them in PLAN order by reading this output as-is.

### multi-pr vars, issueless

Emitted when the PLAN's `tracking_level` is `none`. No GitHub issues
exist, so there is no `#N` to key on; work items come from the PLAN's own
`## Issue Outlines` section instead.

| Key | Value |
|-----|-------|
| `ISSUE_SOURCE` | `"plan_item"` |
| `ARTIFACT_PREFIX` | Same as `name` (e.g., `"m-add-foundation"`) |
| `ISSUE_TYPE` | Value of the **Type**: annotation, omitted if annotation is absent |

The shape is deliberately identical to single-pr's below: the two share
one parser and one local-id algorithm (slugify, collision suffixing,
64-char truncation), and only the `ISSUE_SOURCE` value and the id prefix
differ. Reusing that path is what satisfies "no GitHub issue numbers as
work-item keys" without a second parser.

The distinct value matters even though the vars match. `plan_outline`
signals single-pr's execution model (one shared branch, one pull
request), and an issueless multi-pr PLAN shares the parser but not that
model. A consumer branching on `ISSUE_SOURCE` would be wrong if the two
collapsed into one value.

`tracking_level` is read from the PLAN rather than re-resolved from
CLAUDE.md, so extraction is a function of the document: a repository that
changes its header later cannot retroactively change how an
already-written plan's work items key. An absent or unrecognized value
falls through to the mode-derived default.

### single-pr vars

| Key | Value |
|-----|-------|
| `ISSUE_SOURCE` | `"plan_outline"` |
| `ARTIFACT_PREFIX` | Same as `name` (e.g., `"o-add-core-parser"`) |
| `ISSUE_TYPE` | Value of the **Type**: annotation, omitted if annotation is absent |

### coordinated vars

Coordinated mode emits one task entry per merge-order **node** (not per work
item): the work-item graph is collapsed into `(repo, pr_group)` PR nodes plus
non-PR gate nodes. Each node's `waits_on` lists its immediate predecessors in
the contracted, acyclic merge order. A coordinated PLAN spans one or more
repositories, so all of its PR groups may sit in one repository; each group is
still its own PR node.

Every PR node (`NODE_KIND: "pr"`) carries, on both the table path and the
outline path:

| Key | Value |
|-----|-------|
| `NODE_KIND` | `"pr"` |
| `REPO` | The full `owner/repo` the node's work items name (e.g., `"acme/repo-a"`) |
| `PR_GROUP` | The PR group as written (e.g., `"core"`, `"default"`) |
| `ISSUES` | The node's work items as a comma-separated string with no spaces and no `#`, in PLAN order: GitHub issue numbers on the table path (`"1,2"`), outline numbers from the `### Issue <N>:` headings on the outline path |
| `ISSUE_SOURCE` | `"github"` on the table path, `"plan_outline"` on the outline path |

A gate node carries only `NODE_KIND: "gate"`: none of `REPO`, `PR_GROUP`,
`ISSUES`, or `ISSUE_SOURCE`. All values are JSON strings.

Across the PR nodes, `ISSUES` partitions the PLAN's work items: each appears in
exactly one node. A consumer can therefore cut one branch per node in `REPO`
and dispatch the node's work items without re-parsing the PLAN; when
`ISSUE_SOURCE` is `plan_outline` the work items are outlines read from the PLAN
document itself, not GitHub issues.

Node `name` values: `pr-<repo-name>-<pr_group>` for PR nodes (the owner is
dropped; the slug is sanitized to R9) and `gate-<gate-name>` for gate nodes. A
PR node split at the seam to break a contraction cycle yields per-item node
names of the form `pr-<repo-name>-<pr_group>-i<N>`. A split node carries its
origin node's `REPO`, `PR_GROUP`, and `ISSUE_SOURCE`, and `ISSUES` equal to
`"N"`.

## Frontmatter Requirements

The PLAN file must begin with YAML frontmatter delimited by `---`:

```yaml
---
schema: plan/v1
execution_mode: single-pr  # or multi-pr, or coordinated
...
---
```

The script exits 2 if:
- The file does not start with `---`
- `schema:` is missing or not `plan/v1`
- `execution_mode:` is missing or not `single-pr` / `multi-pr` / `coordinated`
- (coordinated) a work item is missing its Repo/Group declaration, a tag or
  gate name is invalid, a gate names no work item (outline path), or the
  contracted PR DAG has an irreducible cycle (atomicity across PR groups —
  the effort is unschedulable)

## Name-Sanitization Algorithm (single-pr)

For each `### Issue N: <Title>` heading:

1. Take the title string (everything after `Issue N: `)
2. Lowercase the entire string
3. Replace every character not in `[a-z0-9]` with `-`
4. Collapse consecutive `-` to a single `-`
5. Strip leading and trailing `-`
6. Prepend `o-` to get the base name
7. Validate against R9 regex (`^[a-z][a-z0-9-]*$`); exit 2 if empty after steps 3-5

**Example:**

```
"feat(work-on): migrate gates to koto v0.6.0 strict mode"
  -> lowercase: "feat(work-on): migrate gates to koto v0.6.0 strict mode"
  -> replace:   "feat-work-on---migrate-gates-to-koto-v0-6-0-strict-mode"
  -> collapse:  "feat-work-on-migrate-gates-to-koto-v0-6-0-strict-mode"
  -> strip:     "feat-work-on-migrate-gates-to-koto-v0-6-0-strict-mode"
  -> prepend:   "o-feat-work-on-migrate-gates-to-koto-v0-6-0-strict-mode"
```

## R9 Regex

All emitted `name` values must match:

```
^[a-z][a-z0-9-]*$
```

- Must start with a lowercase letter
- Subsequent characters: lowercase letters, digits, or `-`
- No uppercase, no underscores, no special characters

The script validates every generated name and exits 2 if any name violates R9 after sanitization.

## Koto Name Length Limit

Koto enforces a maximum of 64 characters for task names. If a sanitized name exceeds this limit, the script truncates it to 64 characters, strips any trailing `-`, then logs a warning to stderr. The script does not exit — truncated names are valid as long as they still pass R9 and remain unique after the Collision Suffix Rule is applied.

## Collision Suffix Rule

When two issue titles produce the same slug, the second occurrence gets a numeric suffix:

| Occurrence | Name |
|------------|------|
| First | `o-<slug>` |
| Second | `o-<slug>-2` |
| Third | `o-<slug>-3` |
| ... | ... |

The suffixed names also pass R9 validation.

## Mode-Specific Behavior

### multi-pr Mode

Reads the `## Implementation Issues` section. Expects a markdown table with a `Dependencies` column header.

Supported table formats:

```markdown
| Issue | Dependencies | Complexity |
| Issue | Title | Complexity | Dependencies |
```

For each data row where the first cell contains `#N` (plain or as part of a link):
- `name` = `issue-<N>`
- `vars.ISSUE_NUMBER` = `"N"` (as string)
- `waits_on` = list of `issue-<M>` for each `#M` in the Dependencies cell; `[]` if cell is `None`

### single-pr Mode

Reads the `## Issue Outlines` section. Each issue is a `### Issue N: <Title>` heading
with a `**Dependencies**:` line.

**The parse does not live in this script.** It lives in `shirabe-validate`
(`parse_issue_outlines` in `crates/shirabe-validate/src/table.rs`) and reaches
this script through `shirabe plan outlines <PLAN.md>`, which writes a
`shirabe-plan-outlines/v1` JSON envelope to stdout. The same function backs
`shirabe validate`'s FC14, FC17, and L06 checks, which is the point: a PLAN
that validates clean is by construction a PLAN this script reads the same way.
Before the collapse there were three independent readers of this section and
they disagreed in eight ways — see
`docs/designs/current/DESIGN-issue-outlines-one-parser.md`. An envelope whose `schema`
is not the expected value is refused rather than read field by field, so a
binary and a script that have skewed across an install fail loudly.

What this script still owns is everything after the parse: slug generation,
the `o-` prefix, 64-character truncation, collision suffixing, the
`**Files**:` ownership edges, and the koto task-entry assembly.

Dependencies line formats:
- `**Dependencies**: None.` — no dependencies (the trailing period is optional
  and is stripped before the `None` test)
- `**Dependencies**: Blocked by Issue N.` — single dependency
- `**Dependencies**: Blocked by Issue N, Issue M.` — multiple dependencies
- `**Dependencies:**` with the colon inside the bold parses identically
- a `### Dependencies` sub-heading whose body carries the references is also
  accepted, and does not open a new outline

Dependency references also support the `<<ISSUE:N>>` placeholder format as an alternative to `Issue N`. Both forms resolve to the `o-<slug>` name of the referenced issue.

References resolve against the issue numbers written in the headings, not
against an outline's position in the section, so a PLAN numbered
non-consecutively resolves correctly.

**An unresolvable reference stops the work at both boundaries.** A reference
that names no sibling outline — whether it names a number no outline declares,
or is written in a shape that is not a reference at all (a bare number, a `#N`
GitHub reference) — is an error at validation time (`FC17`, so
`shirabe validate` exits non-zero) and exit 2 here. Neither is redundant:
validation is not a precondition of extraction, so an error alone would leave
the silent path open on invocations that skip the gate; and a refusal alone
would leave `shirabe validate` reporting exit 0 on a document that cannot be
built. Before this, the first kind exited 2 and the second was dropped without
a word, producing a complete task list with the edge missing.

`#N` is deliberately **not** accepted here. It is the multi-pr table's
dependency form, where it means a GitHub issue number; reading it as an outline
reference in a single-pr PLAN, which has no GitHub issues, would invent an edge
rather than find one.

A section with no canonically-shaped heading extracts to zero tasks and exits
2, naming the headings it found instead. This has always failed closed and
still does.

### coordinated Mode

A coordinated PLAN has two input shapes, selected by its frontmatter
`tracking_level` exactly as `shirabe validate`'s `plan_is_outline_shaped()`
selects them:

- **Outline path** — only when `tracking_level` is explicitly `none`. Work
  items are the `## Issue Outlines` outlines; nothing was filed on GitHub.
- **Table path** — every other case: `tracking_level` absent, unrecognized,
  `issues`, or `issues-and-milestone`. A coordinated PLAN written before
  coordinated followed the tracking level has no field and is read as
  issue-carrying.

Both paths build the same work-item records and hand them to one contraction
implementation (`build_contracted_graph`, `kahn_order`, `split_repo_at_seam`);
there is no second contraction.

#### Table path

Reads the `## Implementation Issues` section like multi-pr, plus two annotation
row types (escaped-pipe-separated so each stays a single markdown table cell):

- `| ^_Repo: owner/repo \| Group: <pr-group>_ | | |` — tags the issue on the
  preceding entity row with its `(repo, pr_group)`. Every coordinated issue
  MUST carry one (exit 2 otherwise). `repo` is validated against the GitHub
  owner/repo charset; `pr_group` against `^[a-z][a-z0-9-]*$`.
- `| ^_Gate: <name> \| After: <node>,... \| Before: <node>,..._ | | |` —
  declares a non-PR gate node sitting between its `After` predecessors and
  `Before` successors.

#### Outline path

Reads the `shirabe plan outlines` envelope, through the same binary resolution
and with the same failure handling as single-pr (missing binary, non-zero exit,
unrecognized schema: exit 1). The markdown is never re-parsed here. From each
outline it reads `number`, `repo`, `group`, `waits_on`, and
`unresolved_dependencies`; from the top-level `gates` array it reads each gate's
`name`, `after`, `before`, `unresolved_after`, and `unresolved_before`. An
envelope without the `repo`, `group`, or `gates` keys comes from a binary older
than this script and is exit 1 with the "out of step; rebuild or reinstall"
guidance, not a report of missing declarations.

The PLAN declares, in `## Issue Outlines`:

```markdown
### Issue 1: feat: core base

**Repo**: acme/repo-a

**Group**: core

**Dependencies**: None

### Gate: publish-core

**After**: Issue 1

**Before**: Issue 3

**Condition**: the core release is published.
```

Refusals, each exit 2 with empty stdout:

- no outlines at all;
- an outline whose dependencies name no sibling outline (the single-pr wording);
- an outline missing `**Repo**:` or `**Group**:` —
  `coordinated outline Issue 3 is missing a Repo/Group declaration (**Repo**: owner/repo and **Group**: <pr-group>)`;
- an invalid repo or group (the same `validate_repo_tag` / `validate_pr_group`
  rules as the table path);
- a gate name outside `^[a-z][a-z0-9-]*$`;
- a gate whose `**After**:` or `**Before**:` names no outline.

A `### Gate:` block becomes a gate node exactly as a `^_Gate:` row does: node
`gate-<name>`, `vars.NODE_KIND: "gate"`, an edge from the node holding each
`After` outline to the gate, and from the gate to the node holding each
`Before` outline. The outline references resolve to their current node on every
contraction attempt, so a split at the seam retargets the gate's edges.

#### Processing (both paths)

1. Map each work item to its `(repo, pr_group)` PR node id (`pr-<repo-name>-<group>`).
2. Contract the work-item `waits_on` edges into PR-node edges (an edge between
   distinct PR nodes; self-edges within one node are dropped).
3. Add gate nodes and their After/Before edges.
4. Run a Kahn topological sort (R13 acyclicity). On a contraction cycle, apply
   the R16-vs-R13 discriminator: split a multi-item PR node on the residual
   cycle into per-item nodes (`pr-<repo-name>-<group>-i<N>`) and retry. If the
   only cyclic nodes are single-item (unsplittable), refuse with exit 2 and
   empty stdout — the effort is unschedulable because of atomicity across PR
   groups (which may all sit in one repository). The diagnostic names a
   compatible-intermediate sequence and `references/coordination-strategy.md`
   as the way out. A cyclic order is never emitted.
5. Emit one task entry per node in the serialized order, each with `vars`
   (`NODE_KIND`, plus the four PR-node vars on a PR node) and `waits_on`
   listing its immediate predecessors.

## Examples

### multi-pr Example

Input table:
```markdown
| Issue | Title | Complexity | Dependencies |
|-------|-------|------------|--------------|
| #42 | feat: add X | testable | None |
| #43 | feat: add Y | simple | #42 |
```

Output:
```json
[
  {"name": "issue-42", "vars": {"ISSUE_SOURCE": "github", "ISSUE_NUMBER": "42"}, "waits_on": []},
  {"name": "issue-43", "vars": {"ISSUE_SOURCE": "github", "ISSUE_NUMBER": "43"}, "waits_on": ["issue-42"]}
]
```

### coordinated Example, table path (one repository, two groups)

Input table:
```markdown
| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: feat core base](https://example.com/1) | None | testable |
| ^_Repo: acme/repo-a \| Group: core_ | | |
| [#2: feat core more](https://example.com/2) | [#1](https://example.com/1) | testable |
| ^_Repo: acme/repo-a \| Group: core_ | | |
| [#3: feat cli](https://example.com/3) | [#1](https://example.com/1) | testable |
| ^_Repo: acme/repo-a \| Group: cli_ | | |
```

Output:
```json
[
  {"name": "pr-repo-a-core", "vars": {"NODE_KIND": "pr", "REPO": "acme/repo-a", "PR_GROUP": "core", "ISSUES": "1,2", "ISSUE_SOURCE": "github"}, "waits_on": []},
  {"name": "pr-repo-a-cli", "vars": {"NODE_KIND": "pr", "REPO": "acme/repo-a", "PR_GROUP": "cli", "ISSUES": "3", "ISSUE_SOURCE": "github"}, "waits_on": ["pr-repo-a-core"]}
]
```

### coordinated Example, outline path (one repository, two groups)

Input, with `tracking_level: none` in the frontmatter:
```markdown
### Issue 1: feat: core base

**Repo**: acme/repo-a

**Group**: core

**Dependencies**: None

### Issue 2: feat: core more

**Repo**: acme/repo-a

**Group**: core

**Dependencies**: Blocked by Issue 1

### Issue 3: feat: cli

**Repo**: acme/repo-a

**Group**: cli

**Dependencies**: Blocked by Issue 1
```

Output (the same nodes and edges as the table path; `ISSUES` holds outline
numbers):
```json
[
  {"name": "pr-repo-a-core", "vars": {"NODE_KIND": "pr", "REPO": "acme/repo-a", "PR_GROUP": "core", "ISSUES": "1,2", "ISSUE_SOURCE": "plan_outline"}, "waits_on": []},
  {"name": "pr-repo-a-cli", "vars": {"NODE_KIND": "pr", "REPO": "acme/repo-a", "PR_GROUP": "cli", "ISSUES": "3", "ISSUE_SOURCE": "plan_outline"}, "waits_on": ["pr-repo-a-core"]}
]
```

### single-pr Example

Input outlines:
```markdown
### Issue 1: feat: add parser

**Dependencies**: None.

### Issue 2: feat: add validator

**Dependencies**: Blocked by Issue 1.
```

Output:
```json
[
  {
    "name": "o-feat-add-parser",
    "vars": {"ISSUE_SOURCE": "plan_outline", "ARTIFACT_PREFIX": "o-feat-add-parser"},
    "waits_on": []
  },
  {
    "name": "o-feat-add-validator",
    "vars": {"ISSUE_SOURCE": "plan_outline", "ARTIFACT_PREFIX": "o-feat-add-validator"},
    "waits_on": ["o-feat-add-parser"]
  }
]
```
