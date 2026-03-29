# Context Injection

Extract design context for the current issue.

## Steps

### Extract Context

Run the context extraction script with the koto session name:

```bash
${CLAUDE_SKILL_DIR}/references/scripts/extract-context.sh <N> --session <WF>
```

The script stores the extracted context directly into koto context under
the key `context.md` and prints the full content to stdout.

### Read and Summarize

Review the script's stdout output. Fill in the TODO items in the frontmatter
based on the design excerpt. If context is incomplete, gather more from:
- Related design docs or code files
- Recently merged PRs for relevant patterns
- Open or closed issues for prior decisions
- Milestone context for broader goals

If you updated the content, store it back:

```bash
koto context add <WF> context.md --from-file <updated-file>
```

## Evidence

Submit `status: completed` after the context artifact exists, `status: override`
if providing context through a different mechanism, or `status: blocked` if the
issue cannot be reached.
