# Phase 5: No Artifact

A rejection decision is a decision — if exploration reached an active rejection
conclusion (not just lead exhaustion), route to Rejection Record instead of No
Artifact. See `phase-5-produce-rejection-record.md`.

Only appropriate when exploration produced no new decisions -- it confirmed what was
already known, or validated that a simple, clearly-understood task can proceed.

**Before finalizing this path:** check `wip/explore_<topic>_decisions.md`. If it
exists and contains any entries, the exploration made decisions that need a permanent
home. Architectural choices, dependency selections, or structural decisions need a
design doc even if nothing remains undecided. `wip/` is cleaned before merge --
decisions recorded only there are permanently lost.

If the decisions file exists and has entries, return to Phase 4 and reconsider.
"No artifact" means nothing was decided that a future contributor needs to know,
not that everything is now settled.

If the decisions file doesn't exist or is empty, this path is appropriate.

If truly no decisions were made, summarize what was learned and suggest concrete
next steps.

Present to the user:

> Your exploration covered [brief summary of what was investigated]. Here's
> what we found:
>
> [3-5 bullet points: key findings, grounded in specifics]
>
> **Suggested next steps:**
> - Create a focused issue with `/issue` if there's a specific task to track
> - Start implementing directly with `/work-on` if the path is clear

No handoff artifacts to write. No commit needed beyond what prior phases
already committed.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- No new artifacts
