# Walking Skeleton Issue Template

This template is used when walking skeleton decomposition is active. It handles both skeleton issues (Issue #1) and refinement issues (subsequent issues).

## Template Variables

- `{{IS_SKELETON}}` - Boolean: true for skeleton issue, false for refinement
- `{{FEATURE_NAME}}` - Extracted from design doc title
- `{{DESIGN_DOC_PATH}}` - Relative path to design document
- `{{SKELETON_ID}}` - Internal ID of skeleton issue (for refinements)
- `{{REFINEMENT_SEQUENCE}}` - Position in refinement order (2, 3, 4...)

## Template Content

### For Skeleton Issues (IS_SKELETON = true)

```markdown
---
complexity: testable
complexity_rationale: Walking skeleton requires e2e validation
skeleton: true
---

## Goal

Create walking skeleton for {{FEATURE_NAME}}: minimal end-to-end working system with stubs.

## Context

This is a **walking skeleton** issue. It establishes the e2e structure that refinement issues will build upon.

Design: `{{DESIGN_DOC_PATH}}`

## Acceptance Criteria

- [ ] E2E flow: command → processing → output (stubs are OK)
- [ ] Command accepts expected arguments with --help
- [ ] Returns success for happy path (hardcoded response is acceptable)
- [ ] Tests validate e2e flow with stub data
- [ ] CI green

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# Verify skeleton implementation exists and is executable
# (Specific validation will be customized by agent based on feature type)

echo "Walking skeleton validation placeholder"
echo "Agent should customize this for the specific feature"
```

## Dependencies

None (this is the foundation issue)

## Downstream Dependencies

All refinement issues for this feature depend on this skeleton:
- Must deliver: Working e2e flow with clear stub boundaries
- Must maintain: E2e functionality after each refinement
```

### For Refinement Issues (IS_SKELETON = false)

```markdown
---
complexity: {{AGENT_COMPLEXITY}}
complexity_rationale: {{AGENT_COMPLEXITY_RATIONALE}}
skeleton_refinement: true
skeleton_id: <<ISSUE:{{SKELETON_ID}}>>
---

## Goal

{{AGENT_GOAL}}

## Context

This is a **refinement issue** that builds on the walking skeleton (<<ISSUE:{{SKELETON_ID}}>>).

Design: `{{DESIGN_DOC_PATH}}`

## Acceptance Criteria

{{AGENT_AC}}
- [ ] E2E flow still works (do not break the skeleton)
- [ ] Tests updated for refined behavior

## Validation

{{AGENT_VALIDATION}}

## Dependencies

Blocked by <<ISSUE:{{SKELETON_ID}}>> (walking skeleton)

## Downstream Dependencies

{{AGENT_DOWNSTREAM}}
```

## Usage Notes

1. **Skeleton issues** use a fixed template structure - agents customize the validation script for the specific feature type.

2. **Refinement issues** allow agent customization of goal, AC, and validation, but MUST include:
   - The "E2E flow still works" AC item
   - The skeleton dependency
   - The `skeleton_refinement: true` frontmatter

3. **Complexity for refinements**: Agents determine appropriate complexity based on the refinement scope. Most refinements are `testable`, but security-related refinements should be `critical`.

4. **Parallel refinements**: For cross-cutting changes, refinement issues may use `parallel_after_skeleton` dependency model where Issues #2-N are mutually independent.
