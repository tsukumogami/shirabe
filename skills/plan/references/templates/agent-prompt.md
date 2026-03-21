# Agent: Issue Body Generation

You are generating the body for a GitHub issue as part of the `/plan` command.

## Your Task

Generate a complete issue body following the issue-drafting skill format. Your output must enable the implementation to succeed AND provide everything downstream dependents need.

## Context

### Design Document

The full design document is provided below. Use this to understand:
- The problem being solved
- Design decisions and rationale
- Implementation approach
- Security considerations

Design: `{{DESIGN_DOC_PATH}}`

```
{{DESIGN_DOC_CONTENT}}
```

### This Issue

**Internal ID**: {{ISSUE_ID}}
**Title**: {{ISSUE_TITLE}}
**Dependencies**: {{ISSUE_DEPENDENCIES}}
**Section**: This issue implements the following section from the design:

```
{{ISSUE_SECTION}}
```

### Downstream Dependents

These issues depend on THIS issue. Your deliverables must enable them to proceed:

{{DOWNSTREAM_DEPENDENTS}}

If no downstream dependents are listed, this is a leaf node - focus on delivering complete functionality.

### Skeleton Context

{{SKELETON_CONTEXT}}

**If skeleton_mode is true:**

For **skeleton issues** (is_skeleton_issue = true):
- Use the skeleton template from `walking-skeleton-issue.md`
- Goal: Create minimal e2e flow with stubs
- Complexity is always `testable`
- Frontmatter must include `skeleton: true`
- AC focuses on e2e flow working, even with hardcoded/stub responses

For **refinement issues** (is_skeleton_issue = false):
- Your AC MUST include: `- [ ] E2E flow still works (do not break the skeleton)`
- Dependencies MUST include: `Blocked by <<ISSUE:skeleton_id>>`
- Frontmatter must include `skeleton_refinement: true` and `skeleton_id: <<ISSUE:N>>`
- Goal describes what aspect of the skeleton is being refined

**If skeleton_mode is false:** Ignore this section - use standard horizontal decomposition.

### Temporary ID Format

**Important**: GitHub issue numbers don't exist yet. Use the placeholder format `<<ISSUE:N>>` for all issue references, where N is the internal ID.

**Standard format**: `<<ISSUE:N>>`
- Regex pattern: `<<ISSUE:\d+>>`
- Example: `<<ISSUE:1>>`, `<<ISSUE:2>>`, `<<ISSUE:12>>`

**Usage in body:**
- Dependencies section: `Blocked by <<ISSUE:1>>, <<ISSUE:2>>`
- Downstream deliverables: `(required by <<ISSUE:5>>)`
- Anywhere an issue number would appear: `<<ISSUE:N>>`

Phase 7 will substitute these placeholders with actual GitHub issue numbers (e.g., `#291`) when creating issues.

### Execution Mode

{{EXECUTION_MODE}}

**If execution_mode is "single-pr":**
- Produce a lighter structured outline instead of a full issue body
- Focus on: goal, acceptance criteria, and dependencies
- No validation scripts needed
- No Security Checklist section
- Complexity classification still required in frontmatter
- Downstream deliverables section can be brief

**If execution_mode is "multi-pr":**
- Produce the full issue body with all complexity-specific sections
- Include validation scripts for testable/critical complexity levels
- Include Security Checklist for critical complexity
- Include detailed downstream deliverables

## Complexity Classification

You must classify this issue into one of three complexity levels based on its scope and risk:

| Complexity | When to Use | Validation Required |
|------------|-------------|---------------------|
| **simple** | Docs, typos, comments, README updates, trivial fixes | CI passes |
| **testable** | New features, refactoring, behavior changes | Validation script in issue body |
| **critical** | Auth, security, payments, crypto, permissions, tokens | Validation script + security checklist |

**Classification guidance:**

- **simple**: Use when the issue is low-risk documentation or trivial fixes. Look for: README, docs/, .md files, comments, typos.
- **testable**: Default for most implementation work. New code, refactoring, bug fixes that change behavior.
- **critical**: Use when the issue touches security-sensitive areas. Look for: authentication, authorization, secrets, payments, cryptography, user data exposure.

When in doubt between complexity levels, choose the higher level (safer).

## Output Requirements

### File/Chat Separation

Write the complete issue body to: `wip/plan_{{TOPIC}}_issue_{{ISSUE_ID}}_body.md`

After writing the file, return ONLY the structured summary below. Do NOT include any part of the issue body in your response. The orchestrator reads the file directly -- repeating the body in chat wastes context and risks truncation.

**Structured summary format (return ONLY this):**
```
Status: PASS | VALIDATION_FAILED | ERROR
Complexity: <simple|testable|critical>
File: wip/plan_{{TOPIC}}_issue_{{ISSUE_ID}}_body.md
Sections: <comma-separated list of sections present>
Dependencies: <issue IDs or "none">
```

### Required Sections (written to file)

The file must include these sections in order:

1. **Goal** - One sentence stating what this issue accomplishes
2. **Context** - Why this matters, reference to design doc. Must include `Design: \`<path>\`` with the parent design doc path (from `{{DESIGN_DOC_PATH}}` above).
3. **Acceptance Criteria** - Checkboxes for specific, testable criteria
4. **Dependencies** - List blocking issues (or "None")
5. **Downstream Dependencies** - What dependents need from this issue

### Complexity-Specific Requirements

**Simple complexity**: Basic AC checkboxes only.

**Testable complexity** (multi-pr mode only): Include a Validation section with a bash script block:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Test commands here
```

**Critical complexity** (multi-pr mode only): Include both Validation section AND Security Checklist with security-specific checkboxes.

**Single-pr mode**: Skip Validation and Security Checklist sections regardless of complexity.

### Validation Script Safety

If your complexity requires validation scripts (multi-pr mode), you MUST:
- Use heredoc with QUOTED delimiter for any multi-line strings: `<<'EOF'` (not `<<EOF`)
- Never use `eval`, backticks for command substitution, or `curl | bash` patterns
- Use explicit file paths, not dynamic path construction

**Good patterns**:
```bash
# Safe heredoc
cat <<'EOF'
content here
EOF

# Safe command substitution
result=$(command arg)
```

**Bad patterns** (will cause rejection):
```bash
# Unsafe - variable expansion in heredoc
cat <<EOF
$variable
EOF

# Unsafe - eval
eval "$command"

# Unsafe - backticks
result=`command`
```

### Downstream Deliverables

For each downstream dependent, your AC section MUST include an explicit deliverable:

```markdown
- [ ] Must deliver: <specific output> (required by #<downstream-issue>)
```

If you cannot determine what a downstream dependent needs, add:
```markdown
- [ ] Must unblock #<downstream-issue> - review dependent's requirements before marking complete
```

## Output Format

Output the issue body markdown with a YAML front matter block containing the complexity classification.

Start with the front matter, then the issue body:
```
---
complexity: <simple|testable|critical>
complexity_rationale: <one sentence explaining why this complexity>
---

## Goal

<goal statement>
```

The front matter will be parsed and removed before the issue is created. The complexity determines which validation label is applied.
