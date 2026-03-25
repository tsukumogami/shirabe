# Phase 5: Rejection Record

When crystallize selects "Rejection Record", write a permanent rejection record
documenting why this topic was explored and why it should not be pursued.

A Rejection Record is appropriate only when exploration reached an active rejection
conclusion — specific blockers were identified, demand was validated as absent, or
re-proposal risk is high. If leads merely ran out without a conclusion, route to
No Artifact instead.

## Write the Artifact

Write `docs/decisions/REJECTED-<topic>.md`. Create the `docs/decisions/` directory
if it does not exist.

```markdown
# Rejected: <topic>

## What Was Investigated

<Scope of exploration: what questions were asked, what sources were examined
(issues, docs, codebase, PRs). 2-4 sentences.>

## Findings by Question

For each demand-validation question that was investigated, record what was found
and its confidence level (High / Medium / Low / Absent):

1. **Is demand real?** — [High|Medium|Low|Absent]
   <Finding>

2. **What do people do today instead?** — [High|Medium|Low|Absent]
   <Finding>

3. **Who specifically asked?** — [High|Medium|Low|Absent]
   <Finding: cite issue numbers, comment authors, PR references>

4. **What behavior change counts as success?** — [High|Medium|Low|Absent]
   <Finding>

5. **Is it already built?** — [High|Medium|Low|Absent]
   <Finding>

6. **Is it already planned?** — [High|Medium|Low|Absent]
   <Finding>

## Conclusion

<Why this topic should not be pursued. Cite the specific evidence that led to
this conclusion — closed PRs with rejection rationale, design docs that de-scoped
it, maintainer comments, or validated absence of demand. 2-4 sentences.>

## Preconditions for Revisiting

<What would need to be true before this topic is worth re-evaluating. Be specific:
e.g., "three or more distinct users report the absence of X as a blocker",
"the technical constraint in Y is resolved", or "a concrete use case emerges
that the current workaround cannot address.">
```

## Commit

Commit: `docs(explore): record rejection of <topic>`

## Next Steps

After writing and committing the artifact:

1. If the exploration started from an issue: tell the user to close the issue
   with a comment linking to the rejection record (`docs/decisions/REJECTED-<topic>.md`).

2. If re-proposal risk is high (the crystallize scoring flagged high re-proposal
   risk as a signal): offer to route to `/decision` for a formal ADR that captures
   the rejection as an architectural decision record. This is optional — the rejection
   record alone is sufficient for most cases.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `docs/decisions/REJECTED-<topic>.md` (new)
- No handoff to another skill — this is the final produce step
