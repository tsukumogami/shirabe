# Phase 0: Context Injection

Surface design context before implementation begins.

## Goal

Extract and internalize relevant design context for the current issue, ensuring you understand:
- Design rationale and constraints
- How this work fits into the larger design
- Dependencies and integration points

## Steps

### 0.1 Extract Context

Run the context extraction script:

```bash
${CLAUDE_SKILL_DIR}/references/scripts/extract-context.sh <N>
```

This creates `wip/IMPLEMENTATION_CONTEXT.md` with design context and a summary template.

### 0.2 Read and Summarize

Read `wip/IMPLEMENTATION_CONTEXT.md` using the Read tool. The file contains:
- A YAML frontmatter template with TODOs
- The extracted design excerpt

Fill in the TODO items in the frontmatter based on your understanding of the design excerpt. If the extracted context is incomplete, gather additional context as needed:
- Read related design docs or code files
- Check recently merged PRs for relevant patterns
- Review open or closed issues for prior decisions
- Check milestone context for broader goals
- Search the web for library docs or best practices

Use the Write tool to save the updated file with your completed summary.

### 0.3 Continue to Phase 1

Proceed with normal workflow. The summary in `wip/IMPLEMENTATION_CONTEXT.md` will be your quick reference during Phase 4.

## Quality Checklist

Before proceeding to Phase 1:
- [ ] Script executed successfully
- [ ] Context file read and understood
- [ ] All TODOs in frontmatter filled in
