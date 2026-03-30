# Lead 3: Resume Implications

## Explore lifecycle at Phase 5

Explore considers itself done at Phase 5. No cleanup steps. wip/ artifacts stay
on the branch intentionally for downstream reference. The target skill's
orchestrator takes over.

## Branch naming: no conflict

Both explore and design use `docs/<topic>` branches. This is intentional — wip/
artifacts from both skills coexist on the same branch.

## Failure recovery

No automatic rollback mechanism. If /design fails mid-way:
- Explore's wip/ artifacts remain on branch
- Design's resume logic picks up from where it stopped
- User can /cleanup and start fresh if needed
- No circular return to explore is documented

## Resume vulnerability

If explore auto-invokes /design and design fails, running /explore again will
find `wip/explore_<topic>_crystallize.md` and jump to Phase 5 — re-issuing the
same handoff. The user is locked into the original artifact choice unless they
/cleanup first. This is an acceptable trade-off: forward momentum over
backtracking flexibility.

## Key Finding

Auto-invocation doesn't introduce new risks. The branch, artifacts, and resume
logic all support it. The only change needed is making the agent actually invoke
the downstream skill via the Skill tool after writing handoff artifacts.
