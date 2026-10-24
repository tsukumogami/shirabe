# Phase 5: Finalize

Ratify the jury-cleared COMP through explicit human approval, transition
its status, close the session, create the PR, and emit the `[/comp]
FINALIZED` stdout contract.

## 5.1 Human Approval Gate

Present the jury-cleared draft to the user and ask for explicit approval
to finalize. This gate is blocking — do not transition or create a PR
without it. If the user wants changes, loop back to Phase 3.

## 5.2 Transition Status

After approval, transition the document with the lifecycle subcommand:

```bash
shirabe transition docs/competitive/COMP-<topic>.md Accepted
```

The subcommand updates frontmatter and body together and emits JSON on
stdout (`{success, doc_path, old_status, new_status, moved: false}`).
Capture `new_status` for the FINALIZED block.

## 5.3 Close the Session

The working keys have done their job. Close the session; its keys stay
readable:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close comp-<topic> done
```

Then grep the committed COMP document (frontmatter and prose) for any staging
path (`wip/...`) or session key reference and remove it. Both steps are
required: the session closed **and** no committed artifact pointing at a
staging path, or the document leaves a dangling reference.

## 5.4 Create the PR

Commit the COMP document and open a pull request. The COMP lives in a
private repo, so the PR may reference the competitive content directly.

The body describes the COMP in terms a reader of the repository
understands: the survey's finding and its leading implication, in a
sentence or two, and a link to `docs/competitive/COMP-<topic>.md`. By
default it carries none of the workflow's own records: no jury verdicts,
reviewer findings or list of the fixes they prompted, no session or key
names, and no link to a ROADMAP or PLAN, which is deleted when its work
completes. Those stay in the `comp-<topic>` session. A repository opts in
to them with `## PR Workflow Content: include` in its `CLAUDE.local.md` or
`CLAUDE.md`; ask the one reader rather than reading the header yourself:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/pr-workflow-content.sh"
```

It prints `include` or `omit` (the default). Under `include`, the body may
also summarize the jury's verdicts and link a ROADMAP or PLAN the COMP
informs.

## 5.5 Emit the FINALIZED Stdout Contract

Emit this exact block to stdout so a caller can capture the outcome by
shell parsing:

```
[/comp] FINALIZED <topic>
  path: docs/competitive/COMP-<topic>.md
  status: Accepted
  summary: |
    <one paragraph synthesizing the analysis for the caller>
```

The `summary` paragraph synthesizes the survey's finding and its leading
implication — enough for a caller to carry it downstream without
re-reading the whole document.

### Public-visibility case

If the workflow reaches Phase 5 under non-private visibility — either
because Phase 0 warned and the author chose to continue, or because the
visibility changed mid-run — emit the same signal line Phase 0 emits,
and emit no FINALIZED block, because nothing was finalized:

```
[/comp] WARNING <topic>: visibility=public
```

Say the consequence plainly at the approval gate, before the author
ratifies: `shirabe validate` rejects this document under public
visibility (R9), and the CI guardrail fails a PR carrying it, so there
is no path to merging it in this repo. Offer the two things that
actually work — move the analysis to a private repo and finalize it
there, or keep the draft as a working note and land only a BRIEF or PRD
here that references the competitive question.

The skill does not terminate the invocation on its own here any more
than it does at Phase 0; what stops a COMP from landing in a public repo
is the validator and CI, and both are still in force. Do not run
`shirabe transition` and do not open a PR — not as a skill-level
refusal, but because the transition's own validation will reject the
document and the PR could not merge. Close the session with
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close comp-<topic> abandoned`
instead of `done`, since nothing was finalized.

## Output

An Accepted COMP at `docs/competitive/COMP-<topic>.md`, a closed
`comp-<topic>` session, a PR, and the `[/comp] FINALIZED` block on stdout.
