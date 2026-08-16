# Phase 5: Competitive Analysis

Route to `/comp`. `/explore` writes no competitive analysis of its own.

`/comp` owns `docs/competitive/COMP-<topic>.md` and drives a six-phase workflow,
a three-reviewer jury, and the lifecycle transition to Accepted. The inline
handler this arm replaces wrote a Draft at the same path with none of that, so
the two producers disagreed about what a finished COMP is.

This arm is reachable only in a private repo. Crystallize evaluates visibility
as a candidacy precondition and removes the category outright under public
visibility, so the refusal the old handler carried has no run to fire on. If you
reached this file in a public repo, the precondition was skipped — go back to
`wip/explore_<topic>_crystallize.md` and read the Candidacy section rather than
producing anything here.

**What the arm passes:** the topic slug. `/comp` takes `<topic-slug>` and an
optional `--upstream <path>`; the exploration's research stays in `wip/`, where
`/comp`'s own phases can read it.

Invoke `/comp <topic>`. It runs its own Phase 0 visibility detection, scopes the
competitive question with the author, and produces the document.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- No document written by `/explore`
- Session continues in `/comp`
