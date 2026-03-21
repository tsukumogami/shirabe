# Phase 5: Plan Handoff

Two paths depending on whether open decisions remain:

**No open decisions** (scope is clear, work is decomposable, no architectural
decisions need to be documented first): Tell the user to run `/plan <topic>` where
topic is a short description of what was explored. /plan will treat this as a direct
topic and produce a plan without requiring an upstream document.

**Open decisions remain** (technical approach or requirements still need to be
documented): Tell the user to complete the upstream artifact first, then run
`/plan <artifact-path>` once it's accepted. Suggest /prd if requirements need
capturing, /design if the technical approach is open.

Tell the user:

> Your exploration confirmed the scope and approach. Run `/plan <topic>` to break
> the work into issues directly.

or, if open decisions remain:

> Your exploration identified "plan" as the right next step, but [technical approach /
> requirements] still need to be documented first. [Create a design doc / PRD], then
> run `/plan <artifact-path>` once it's accepted.
>
> Your exploration research is saved in `wip/` if you need to reference it.

If the crystallize decision noted that an existing artifact covers this topic,
include its path in the suggestion.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- No new artifacts; user runs `/plan <path>` separately
