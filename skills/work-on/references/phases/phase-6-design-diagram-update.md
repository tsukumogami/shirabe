# Design Document Diagram Update

Update the dependency diagram in a referenced design document to reflect
completed work. This step is project-specific -- it assumes design docs
use Mermaid dependency graphs with `:::ready`, `:::blocked`, and `:::done`
status classes.

## When to run

Only if the issue body contains `Design: \`<path>\``. If no design
reference is found, skip silently.

## Steps

### Extract Design Doc Path

Look for `Design: \`<path>\`` in the issue body (from Phase 1 issue reading).

### Validate Path

Before reading the file, validate the path:

- **No path traversal**: Reject paths containing `..`
- **Markdown file**: Path must end with `.md`
- **Expected directory**: File must be within `docs/` directory
- **File exists**: Verify file exists at the path

If validation fails, log warning, skip diagram update, continue to Push Branch.

### Find and Update Diagram

1. Read the design document
2. Locate the `### Dependency Graph` section with Mermaid diagram
3. Find the current issue's node: `I<N>` where N is the issue number
4. Change its class from `:::ready` or `:::blocked` to `:::done`

**Regex pattern for node with class:**
```
I(\d+)\[([^\]]+)\]:::(\w+)
```
- Group 1: Issue number
- Group 2: Label
- Group 3: Current class (done/ready/blocked)

### Recalculate Downstream Status

For each node that depends on this issue:

1. Parse all edges to find nodes blocked by this issue:
   ```
   I<N>.*-->.*I(\d+)
   ```
2. For each downstream node, check if ALL its blocking dependencies are now `:::done`
3. If all blockers are done, change the downstream node from `:::blocked` to `:::ready`

**Edge pattern:**
```
I(\d+).*-->.*I(\d+)
```
- Group 1: Source (blocker) issue number
- Group 2: Target (blocked) issue number

### Validate and Commit

1. Verify the modified Mermaid syntax is valid (all `classDef` statements present, balanced brackets)
2. Stage the design document with the implementation changes
3. The design doc update will be included in the same commit/PR as the implementation

**Error handling:**
- Diagram section not found: Log warning, skip update (old format design)
- Node for issue not found: Log warning, skip update
- Syntax validation fails: Log error, abort diagram update, continue PR without it
