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
| `ARTIFACT_PREFIX` | Same as `name` (e.g., `"outline-add-core-parser"`) |

## Frontmatter Requirements

The PLAN file must begin with YAML frontmatter delimited by `---`:

```yaml
---
schema: plan/v1
execution_mode: single-pr  # or multi-pr
...
---
```

The script exits 2 if:
- The file does not start with `---`
- `schema:` is missing or not `plan/v1`
- `execution_mode:` is missing or not `single-pr` / `multi-pr`

## Name-Sanitization Algorithm (single-pr)

For each `### Issue N: <Title>` heading:

1. Take the title string (everything after `Issue N: `)
2. Lowercase the entire string
3. Replace every character not in `[a-z0-9]` with `-`
4. Collapse consecutive `-` to a single `-`
5. Strip leading and trailing `-`
6. Prepend `outline-` to get the base name
7. Validate against R9 regex (`^[a-z][a-z0-9-]*$`); exit 2 if empty after steps 3-5

**Example:**

```
"feat(work-on): migrate gates to koto v0.6.0 strict mode"
  -> lowercase: "feat(work-on): migrate gates to koto v0.6.0 strict mode"
  -> replace:   "feat-work-on---migrate-gates-to-koto-v0-6-0-strict-mode"
  -> collapse:  "feat-work-on-migrate-gates-to-koto-v0-6-0-strict-mode"
  -> strip:     "feat-work-on-migrate-gates-to-koto-v0-6-0-strict-mode"
  -> prepend:   "outline-feat-work-on-migrate-gates-to-koto-v0-6-0-strict-mode"
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

## Collision Suffix Rule

When two issue titles produce the same slug, the second occurrence gets a numeric suffix:

| Occurrence | Name |
|------------|------|
| First | `outline-<slug>` |
| Second | `outline-<slug>-2` |
| Third | `outline-<slug>-3` |
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

Dependencies line formats:
- `**Dependencies**: None.` — no dependencies
- `**Dependencies**: Blocked by Issue N.` — single dependency
- `**Dependencies**: Blocked by Issue N, Issue M.` — multiple dependencies

Dependency references resolve to the `outline-<slug>` name of the referenced issue.
Exit 2 if a referenced issue number has no corresponding outline heading.

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
    "name": "outline-feat-add-parser",
    "vars": {"ISSUE_SOURCE": "plan_outline", "ARTIFACT_PREFIX": "outline-feat-add-parser"},
    "waits_on": []
  },
  {
    "name": "outline-feat-add-validator",
    "vars": {"ISSUE_SOURCE": "plan_outline", "ARTIFACT_PREFIX": "outline-feat-add-validator"},
    "waits_on": ["outline-feat-add-parser"]
  }
]
```
