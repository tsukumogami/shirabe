# Context Injection

Extract design context for the current issue.

## Steps

### Extract Context

Run the context extraction script with the koto session name:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/work-on/references/scripts/extract-context.sh <N> --session <WF>
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

If you updated the content, store it back under `context.md`, by stdin pipe or
a `mktemp` file deleted after ingestion (see `../koto-context-conventions.md`).
