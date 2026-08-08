# Phase 5: Finalize

Ratify the jury-cleared COMP through explicit human approval, transition
its status, clean up `wip/`, create the PR, and emit the `[/comp]
FINALIZED` stdout contract for parent capture.

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

## 5.3 Clean Up wip/

Remove the non-durable working files for this invocation:

- `wip/comp_<topic>_scope.md`
- `wip/research/comp_<topic>_phase4_*.md`

Then grep the committed COMP document (frontmatter and prose) for any
`wip/...` reference and remove it. Both steps are required: the files
must be deleted **and** no committed artifact may point at a `wip/` path,
or the cleanup commit leaves a dangling reference.

## 5.4 Create the PR

Commit the COMP document and open a pull request. The COMP lives in a
private repo, so the PR may reference the competitive content directly.

## 5.5 Emit the FINALIZED Stdout Contract

Emit this exact block to stdout so a parent skill (today, `/charter`) can
capture the outcome by shell parsing:

```
[/comp] FINALIZED <topic>
  path: docs/competitive/COMP-<topic>.md
  status: Accepted
  summary: |
    <one paragraph synthesizing the analysis for parent injection>
```

The `summary` paragraph synthesizes the survey's finding and its leading
implication — enough for the parent to inject downstream without
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
document and the PR could not merge.

## Output

An Accepted COMP at `docs/competitive/COMP-<topic>.md`, a clean `wip/`,
a PR, and the `[/comp] FINALIZED` block on stdout.
