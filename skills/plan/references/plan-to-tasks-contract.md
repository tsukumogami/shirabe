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
| 2 | Schema mismatch: wrong `schema:` value, missing `execution_mode`, empty slug, or unresolvable dependency reference |

**Output:** JSON array on stdout. Log messages written to stderr (prefixed `[plan-to-tasks]`).

**Prerequisites:** `jq` must be available in `PATH`. Exit 1 if not found.

The `shirabe` binary is also required, because the `## Issue Outlines` parse
lives there rather than in this script (see below). It is resolved in the same
order `skills/execute/scripts/run-cascade.sh` uses:

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

| Key | Value |
|-----|-------|
| `ISSUE_SOURCE` | `"github"` |
| `ISSUE_NUMBER` | Issue number as string (e.g., `"42"`) |

### single-pr vars

| Key | Value |
|-----|-------|
| `ISSUE_SOURCE` | `"plan_outline"` |
| `ARTIFACT_PREFIX` | Same as `name` (e.g., `"o-add-core-parser"`) |
| `ISSUE_TYPE` | Value of the **Type**: annotation, omitted if annotation is absent |

### coordinated vars

Coordinated mode emits one task entry per merge-order **node** (not per issue):
the issue-level graph is collapsed into `(repo, pr_group)` PR nodes plus non-PR
gate nodes. Each node's `waits_on` lists its immediate predecessors in the
contracted, acyclic merge order.

| Key | Value |
|-----|-------|
| `NODE_KIND` | `"pr"` for a `(repo, pr_group)` PR node, `"gate"` for a non-PR gate node |

Node `name` values: `pr-<repo-name>-<pr_group>` for PR nodes (the owner is
dropped; the slug is sanitized to R9) and `gate-<gate-name>` for gate nodes. A
repo split at the seam to break a contraction cycle yields per-issue node names
of the form `pr-<repo-name>-<pr_group>-i<issue-number>`.

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
- (coordinated) an issue is missing its `Repo`/`Group` annotation, a tag is
  invalid, or the contracted PR DAG has an irreducible cycle (true cross-repo
  atomicity — the effort is unschedulable)

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

Reads the `## Implementation Issues` section like multi-pr, plus two annotation
row types (escaped-pipe-separated so each stays a single markdown table cell):

- `| ^_Repo: owner/repo \| Group: <pr-group>_ | | |` — tags the issue on the
  preceding entity row with its `(repo, pr_group)`. Every coordinated issue
  MUST carry one (exit 2 otherwise). `repo` is validated against the GitHub
  owner/repo charset; `pr_group` against `^[a-z][a-z0-9-]*$`.
- `| ^_Gate: <name> \| After: <node>,... \| Before: <node>,..._ | | |` —
  declares a non-PR gate node sitting between its `After` predecessors and
  `Before` successors.

Processing:

1. Map each issue to its `(repo, pr_group)` PR node id (`pr-<repo-name>-<group>`).
2. Contract the issue-level `waits_on` edges into PR-node edges (an edge between
   distinct PR nodes; self-edges within one node are dropped).
3. Add gate nodes and their After/Before edges.
4. Run a Kahn topological sort (R13 acyclicity). On a contraction cycle, apply
   the R16-vs-R13 discriminator: split a multi-issue PR node on the residual
   cycle into per-issue nodes (`pr-<repo-name>-<group>-i<N>`) and retry. If the
   only cyclic nodes are single-issue (unsplittable), refuse with exit 2 — the
   effort is unschedulable (true cross-repo atomicity). A cyclic order is never
   emitted.
5. Emit one task entry per node in the serialized order, each with `vars.NODE_KIND`
   (`pr` or `gate`) and `waits_on` listing its immediate predecessors.

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
