# Context Injection

Extract design context for the current issue.

## Steps

### Extract Context

Run the context extraction script with the koto session name and the issue's
repository, exactly as the state's directive gives the command:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/work-on/references/scripts/extract-context.sh <N> --session <WF> --issue-repo "<ISSUE_REPO>"
```

`<ISSUE_REPO>` is the run's `ISSUE_REPO`, which the directive fills in: empty
for an issue in this repository, `owner/repo` for one elsewhere. The flag is
required even when empty; the script never guesses the repository.

The script stores the extracted context directly into koto context under
the key `context.md`, prints the full content to stdout, and ends with a JSON
summary whose `status` decides the evidence for this state. For an issue in
another repository it reads the issue from that repository and skips this
repository's design docs, whose `#<N>` names a different issue.

- `success` or `degraded` — the context is stored (`degraded` means it came
  from the issue body alone). Read and summarize it below, then submit
  `status: completed`.
- `failed` — nothing was stored. The JSON's `error` and `warnings` say why:
  no session, no `--issue-repo` or one that isn't `owner/repo`, no koto on
  PATH, a failed `koto context add`, or a missing `gh`. A missing or
  malformed `--issue-repo` means the command wasn't run as the directive
  gives it: run that command again. Otherwise submit `status: blocked` with
  the reason as `detail`, which ends the run at `done_blocked`. If the context comes another way instead (you
  gather it from the issue and store it under `context.md` yourself, say),
  submit `status: override` with `detail` naming where it came from.

### Read and Summarize

Review the script's stdout output. Fill in the TODO items in the frontmatter
based on the design excerpt. If context is incomplete, gather more from:
- Related design docs or code files
- Recently merged PRs for relevant patterns
- Open or closed issues for prior decisions
- Milestone context for broader goals

If you updated the content, store it back under `context.md`, by stdin pipe or
a `mktemp` file deleted after ingestion (see `../koto-context-conventions.md`).
